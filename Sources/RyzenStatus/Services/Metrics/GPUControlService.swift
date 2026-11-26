// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation
import os

/// Whether the GPU control page and its panel row exist: only with a kext
/// that has the write path (0.5.0 and later), or with the model in a
/// development build. Thread-safe, so the Settings directory can ask.
enum GPUControlVisibility {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fake = false

    /// `fake` is for a development build's model. Without the write path
    /// there is no page; with it, the page stays for every off state except
    /// the kext's no-supported-card state.
    static func visible(hasWritePath: Bool, hasUnsupportedCard: Bool, fake: Bool = false) -> Bool {
        fake || (hasWritePath && !hasUnsupportedCard)
    }

    static var isVisible: Bool {
        visible(hasWritePath: GPUSensorsService.shared.hasWritePathNow,
                hasUnsupportedCard: GPUSensorsService.shared.hasUnsupportedCardNow,
                fake: lock.withLock { fake })
    }

    static func setFake(_ on: Bool) { lock.withLock { fake = on } }
}

/// The live row: the card's power and fan as macOS publishes them, and the
/// hotspot from GPUSensors.kext.
struct GPUControlLive: Equatable, Sendable {
    var boardW: Double?
    var fanRPM: Double?
    var hotspotC: Double?
}

/// The app's side of the GPU control: one controller on the one channel the
/// app connects at launch (never in a development build unless asked), what
/// the page shows, remembering the setting, opening writing, notifications.
@MainActor
final class GPUControlService: ObservableObject {
    static let shared = GPUControlService()

    @Published private(set) var snapshot: GPUControlSnapshot?
    /// The properties of the whole-table read, while the page or the row is
    /// on screen (and in the background while a remembered setting waits).
    @Published private(set) var control: GPUControlStatus?
    @Published private(set) var live = GPUControlLive()
    @Published private(set) var armTool: GPUControlArmTool.Availability = .missing
    @Published private(set) var isArming = false
    @Published private(set) var armFailed = false
    /// "Allow changes after restart too": the daemon is installed
    /// (`GPUControlBootArm`). Read from the disk, never from a preference.
    @Published private(set) var bootArm = false
    @Published private(set) var isChangingBootArm = false
    @Published private(set) var bootArmFailed = false
    @Published private(set) var mode: GPUControlConnectionMode = .none
    /// The "remember" box (off by default).
    @Published var remember: Bool {
        didSet {
            guard remember != oldValue else { return }
            defaults.set(remember, forKey: DefaultsKey.gpuControlRemember)
            rememberChanged()
        }
    }

    /// The "Allow overclocking" switch (GPUSensors 0.9.0; off by default).
    /// Turning it off gives back every raise the app holds or asks for.
    @Published var overclock: Bool {
        didSet {
            guard overclock != oldValue else { return }
            defaults.set(overclock, forKey: DefaultsKey.gpuControlOverclock)
            let on = overclock
            overclockNow.withLock { $0 = on }
            if !overclock { controller?.dropRaises() }
        }
    }

    /// The owner's GPU profiles, as saved in the app's defaults.
    @Published private(set) var profiles: [GPUControlProfile] = []
    /// What the last profile loaded came to: the section under the list says
    /// what went out and what this card did not take.
    @Published private(set) var profileLoad: GPUControlProfileLoad?
    /// The display card's PCI device id, read once: a profile records the
    /// card it was made on with it.
    private let cardDeviceID: UInt32? = GPUControlCardDevice.displayDeviceID()
    private var profileStore = GPUControlProfileStore()

    private let defaults: UserDefaults
    /// The switch for the controller's queue: a remembered raise is checked
    /// against it right before it goes out.
    private let overclockNow = OSAllocatedUnfairLock(initialState: false)
    private var controller: GPUControlController?
    private var fake: FakeGPUControlKext?
    private var viewers = 0
    private var pollTimer: Timer?
    private var rememberTimer: Timer?
    private var pendingRemembered = false
    private var refreshTicks = 0
    /// Security review S-5 and S-9: another program's hold or close.
    private var foreignWatch = GPUControlForeignWatch()
    private var foreignTimer: Timer?
    /// When the owner last pressed "Close changes" (system uptime).
    private var closeAskedAt: TimeInterval?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remember = defaults.bool(forKey: DefaultsKey.gpuControlRemember)
        let on = defaults.bool(forKey: DefaultsKey.gpuControlOverclock)
        overclock = on
        overclockNow.withLock { $0 = on }
        profileStore = GPUControlProfileStore.load(defaults)
        profiles = profileStore.profiles
    }

    var facts: GPUControlFacts? { GPUControlPageLogic.facts(snapshot: snapshot, control: control) }

    var state: GPUControlPageState? {
        facts.map { GPUControlPageLogic.state(facts: $0, snapshot: snapshot) }
    }

    private var rememberActive: Bool {
        GPUControlRememberPolicy.isActive(enabled: remember, isDeveloperBuild: AppInfo.isDeveloperBuild)
    }

    // MARK: Launch and quit

    /// `applicationDidFinishLaunching`, the only place the app connects a
    /// channel. `makeRealChannel` is called only when the real one is used.
    func connectAtLaunch(makeRealChannel: () -> GPUControlChannel) {
        guard controller == nil else { return }
        mode = GPUControlConnectionMode.choose(isDeveloperBuild: AppInfo.isDeveloperBuild, defaults: defaults)
        let channel: GPUControlChannel
        switch mode {
        case .none:
            return
        case .real:
            channel = makeRealChannel()
        case .fake:
            let model = FakeGPUControlKext()
            fake = model
            channel = model.connection()
            GPUControlVisibility.setFake(true)
        }
        let controller = GPUControlController(channel: channel)
        controller.onChange = { snapshot in
            Task { @MainActor in GPUControlService.shared.received(snapshot) }
        }
        controller.onNotice = { notice in
            Task { @MainActor in GPUControlService.shared.notify(notice) }
        }
        controller.setReaskAfterWake(rememberActive)
        let model = fake
        let overclockNow = overclockNow
        controller.setReaskFilter { request in
            let control = model.flatMap(GPUControlService.fakeControl) ?? GPUSensorsService.shared.currentControl()
            let od8Ready = control?.writing?.od8Read == .read
            return GPUControlRememberPolicy.checkedAgain(
                request, stockGfxMaxMHz: control?.writing?.od8?.stockGfxMaxMHz,
                gfxMin: GPUControlClockMinLogic.limits(writing: control?.writing, od8Ready: od8Ready),
                volt: GPUControlVoltLogic.limits(writing: control?.writing, od8Ready: od8Ready),
                overclock: GPUControlOverclockLogic.gfxLimits(writing: control?.writing, od8Ready: od8Ready),
                overclockAllowed: overclockNow.withLock { $0 })
        }
        // The kext refuses a curve or a raise while the watchdog's readings
        // are older than 2 s: one read right before each such change.
        if mode == .real { controller.setFreshenReadings { GPUControlReadings.freshen() } }
        controller.start()
        self.controller = controller
        if mode == .real { startForeignWatch() }
        if rememberActive, GPUControlRemembered.load(defaults) != .nothing {
            pendingRemembered = true
            startRememberWatch()
        }
    }

    /// `applicationWillTerminate`: release at once, close (1 s at most).
    func shutdown() {
        pollTimer?.invalidate()
        rememberTimer?.invalidate()
        foreignTimer?.invalidate()
        controller?.shutdown(timeout: 1)
    }

    // MARK: Choices

    /// The pop-up and the panel row: the start-up value is the way back.
    func choosePower(_ watts: Int) {
        guard let controller, let facts else { return }
        if watts == facts.bootW {
            backToStartUp()
            return
        }
        controller.choose(.power(watts: UInt32(watts)))
    }

    /// "Apply curve": the whole fan state; the controller keeps a held GFX
    /// maximum with it and gives a power limit back first.
    func applyFan(_ draft: GPUControlFanDraft) {
        // Always through the controller: a stock fan keeps a held clock, and
        // never gives back a power limit.
        controller?.chooseFan(curve: draft.want.curve, zeroRpmOff: draft.want.zeroRpmOff)
    }

    /// The clock control: a lower GFX maximum, or nil for the stock clock.
    /// The controller keeps a held fan state with it and gives a power limit
    /// back first.
    func chooseGfxMax(_ mhz: Int?) {
        controller?.chooseGfxMax(mhz)
    }

    /// The minimum clock control (GPUSensors 0.9.0): a raised GFX minimum,
    /// or nil for the stock one. The rest of a held OD8 state goes with it.
    func chooseGfxMin(_ mhz: Int?) {
        controller?.chooseGfxMin(mhz)
    }

    /// The overclock control (GPUSensors 0.9.0): a GFX maximum above stock,
    /// sent with the overclock flag, or nil for the stock maximum.
    func chooseGfxMaxRaised(_ mhz: Int?) {
        controller?.chooseGfxMaxRaised(mhz)
    }

    /// The voltage control (GPUSensors 0.9.0): a lower GFX voltage in mV, or
    /// nil for stock. The rest of a held OD8 state goes with it.
    func chooseVolt(_ mv: Int?) {
        controller?.chooseVolt(mv)
    }

    func backToStartUp() {
        controller?.choose(.startUp)
    }

    /// "Close changes" (kext 0.8.0): back to the start-up values, then
    /// `disarm` on the app's own connection. No password.
    func closeChanges() {
        guard let controller else { return }
        closeAskedAt = ProcessInfo.processInfo.systemUptime
        controller.close()
    }

    /// "Open writing…": the administrator dialog runs the installed tool's
    /// fixed command, only when the owner presses the button.
    func openWriting(prompt: String) {
        guard !isArming else { return }
        if let fake {
            fake.arm()
            refreshNow()
            return
        }
        refreshArmTool()
        guard armTool == .button else { return }
        isArming = true
        armFailed = false
        AdminShell.run(GPUControlArmTool.armCommand, prompt: prompt) { ok in
            Task { @MainActor in
                let service = GPUControlService.shared
                service.isArming = false
                service.armFailed = !ok
                service.refreshNow()
            }
        }
    }

    /// The switch: installs or removes the start-up daemon, through the
    /// administrator dialog, only when the owner flips it. Turning it on is
    /// offered only while the button would be (the tool is installed safely);
    /// turning it off always is.
    func setBootArm(_ on: Bool, prompt: String) {
        guard !isChangingBootArm, on != bootArm else { return }
        if fake != nil {
            bootArm = on
            if on { fake?.arm() }
            refreshNow()
            return
        }
        if on {
            refreshArmTool()
            guard armTool == .button else { return }
        }
        isChangingBootArm = true
        bootArmFailed = false
        let command = on ? GPUControlBootArm.installCommand : GPUControlBootArm.removeCommand
        AdminShell.run(command, prompt: prompt) { ok in
            Task { @MainActor in
                let service = GPUControlService.shared
                service.isChangingBootArm = false
                service.refreshBootArm()
                service.bootArmFailed = !ok || service.bootArm != on
                service.refreshNow()
            }
        }
    }

    private func refreshBootArm() {
        guard fake == nil else { return }
        let installed = GPUControlBootArm.isInstalled()
        if bootArm != installed { bootArm = installed }
    }

    // MARK: On screen

    /// The page or the row appeared: read every second while one shows.
    func viewerAppeared() {
        viewers += 1
        guard viewers == 1 else { return }
        refreshArmTool()
        refreshNow()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in GPUControlService.shared.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func viewerDisappeared() {
        guard viewers > 0 else { return }
        viewers -= 1
        guard viewers == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshNow() {
        // Installing gpucontrol with the page open shows the button within 5 s.
        refreshTicks += 1
        if refreshTicks % 5 == 0 { refreshArmTool() }
        if let fake {
            fake.advance(by: 1_000)
            control = Self.fakeControl(fake)
        } else {
            control = GPUSensorsService.shared.currentControl()
        }
        controller?.refresh()
        checkForeign()
        let hotspot = GPUSensorsService.shared.currentReading()?.sample.hotspot
        Task {
            let power = await IOAcceleratorCache.shared.power()
            let fan = await IOAcceleratorCache.shared.fanRPM()
            await MainActor.run {
                let next = GPUControlLive(boardW: power, fanRPM: fan, hotspotC: hotspot)
                if GPUControlService.shared.live != next { GPUControlService.shared.live = next }
            }
        }
        tryRemembered()
    }

    private func refreshArmTool() {
        armTool = fake != nil ? .button
            : GPUControlArmTool.availability()
        refreshBootArm()
    }

    /// The model's properties, as the kext would publish them.
    nonisolated static func fakeControl(_ fake: FakeGPUControlKext) -> GPUControlStatus? {
        var properties = fake.properties()
        properties["Control"] = "watching the profile requests"
        properties["PowerWatch"] = ["BootW": NSNumber(value: fake.bootW)]
        return GPUControlStatus.parse(properties)
    }

    // MARK: From the controller

    private func received(_ next: GPUControlSnapshot) {
        let previous = snapshot
        snapshot = next
        // The owner's own way back (the button, or a fan or clock control
        // back to stock that left nothing held) forgets the remembered one.
        let released = next.ownerReleased && previous?.ownerReleased != true
        if next.held != previous?.held || released {
            if let save = GPUControlRememberPolicy.toSave(held: next.held,
                                                          ownerChoseStartUp: released && next.held == nil,
                                                          active: rememberActive) {
                save.save(defaults)
            }
        }
        if next.stopped != nil { pendingRemembered = false }
        // The sentence about the last profile loaded is about the state it
        // put on the card: another change makes it old news.
        if let load = profileLoad, next.outcome == nil, next.activity == .none,
           next.held != load.request {
            profileLoad = nil
        }
    }

    // MARK: Profiles

    /// The card as the kext and the registry describe it now.
    private var cardNow: GPUControlProfileCard {
        GPUControlProfileCard.current(facts: facts, writing: control?.writing, deviceID: cardDeviceID)
    }

    /// The saved profile that is exactly what the card holds now, if any.
    var matchingProfile: String? {
        GPUControlProfiles.match(profiles, held: snapshot?.held)
    }

    /// What the card holds now goes into a profile under `raw`. Only what
    /// the kext confirmed is saved, as Remembering does; a name is trimmed,
    /// may not be empty and may not repeat another profile's.
    @discardableResult
    func saveProfile(named raw: String) -> GPUControlProfileSave {
        guard !profileStore.isNewerVersion else { return .newerVersion }
        guard let held = snapshot?.held, held != .startUp else { return .nothingToSave }
        guard let name = GPUControlProfileStore.clean(raw) else { return .emptyName }
        guard !profileStore.isTaken(name) else { return .duplicateName(name) }
        guard let profile = GPUControlProfiles.profile(named: name, held: held, card: cardNow) else {
            return .nothingToSave
        }
        profileStore.add(profile)
        profileStore.save(defaults)
        profiles = profileStore.profiles
        return .saved(name: name)
    }

    @discardableResult
    func renameProfile(named name: String, to raw: String) -> GPUControlProfileSave {
        guard !profileStore.isNewerVersion else { return .newerVersion }
        guard let clean = GPUControlProfileStore.clean(raw) else { return .emptyName }
        guard profileStore.profile(named: name) != nil else { return .nothingToSave }
        guard !profileStore.isTaken(clean, excluding: name) else { return .duplicateName(clean) }
        profileStore.rename(name, to: clean)
        profileStore.save(defaults)
        profiles = profileStore.profiles
        return .saved(name: clean)
    }

    func deleteProfile(named name: String) {
        guard !profileStore.isNewerVersion else { return }
        profileStore.remove(named: name)
        profileStore.save(defaults)
        profiles = profileStore.profiles
    }

    /// A profile goes out through the controller's own path, exactly as a
    /// value the owner changes by hand does: the same checks, the same
    /// waiting, the same refusal on screen. What this card does not take now
    /// is left out, and the section says which part. With Remember on, a
    /// profile the kext confirms becomes the remembered state like any other
    /// change (`received`).
    func loadProfile(_ profile: GPUControlProfile) {
        let writing = control?.writing
        let od8Ready = facts?.od8Ready ?? false
        let load = GPUControlProfiles.load(
            profile, card: cardNow, facts: facts, stockGfxMaxMHz: writing?.od8?.stockGfxMaxMHz,
            od8Ready: od8Ready, kextVersion: writing?.kextVersion,
            gfxMin: GPUControlClockMinLogic.limits(writing: writing, od8Ready: od8Ready),
            volt: GPUControlVoltLogic.limits(writing: writing, od8Ready: od8Ready),
            overclock: GPUControlOverclockLogic.gfxLimits(writing: writing, od8Ready: od8Ready),
            overclockAllowed: overclock)
        profileLoad = load
        if let request = load.request { controller?.choose(request) }
    }

    // MARK: Another program (security review S-5, S-9)

    /// Every 10 s while the app runs with the real kext: a hold by another
    /// program while the app holds nothing, or writing closed by another
    /// program, is told with a notification even with the page closed. The
    /// read is the shared one the sensors use (one per second at most).
    private func startForeignWatch() {
        let timer = Timer(timeInterval: 10, repeats: true) { _ in
            Task { @MainActor in GPUControlService.shared.checkForeign() }
        }
        RunLoop.main.add(timer, forMode: .common)
        foreignTimer = timer
    }

    private func checkForeign() {
        guard mode == .real, GPUSensorsService.shared.hasWritePathNow else { return }
        let current = viewers > 0 ? control : GPUSensorsService.shared.currentControl()
        guard let current, let facts = GPUControlFacts(control: current) else { return }
        let appHolds = snapshot?.held != nil || GPUControlPageLogic.pending(snapshot) != nil
        // The app's own close: its answer and the next read may cross.
        let appClosing = closeAskedAt.map { ProcessInfo.processInfo.systemUptime - $0 < 90 } ?? false
        guard let notice = foreignWatch.next(facts: facts, appHolds: appHolds, appClosing: appClosing) else { return }
        let language = L10n.shared.language
        let strings = FeatureStrings.gpuControlPage(language)
        let body = notice == .changed ? strings.otherProgramChanged : strings.closedByOther
        Notifier.post(title: FeatureStrings.gpuControl(language).title, body: body)
    }

    private func notify(_ notice: GPUControlNotice) {
        guard mode == .real else { return }
        let language = L10n.shared.language
        let strings = FeatureStrings.gpuControlPage(language)
        switch notice {
        case .writingOff(let reason):
            let group = reason.flatMap { GPUControlTextGroup.forWriteOff($0.rawValue) } ?? .writingOff
            Notifier.post(title: FeatureStrings.gpuControl(language).title, body: strings.sentence(group))
        }
    }

    // MARK: Remembering

    private func rememberChanged() {
        controller?.setReaskAfterWake(rememberActive)
        if !remember {
            GPUControlRemembered.nothing.save(defaults)
            pendingRemembered = false
            rememberTimer?.invalidate()
            rememberTimer = nil
        } else if rememberActive, let held = snapshot?.held,
                  let save = GPUControlRememberPolicy.toSave(held: held, ownerChoseStartUp: false, active: true) {
            save.save(defaults)
        }
    }

    /// A remembered setting waits for writing to open (it never asks for a
    /// password): every 5 s, as long as it waits.
    private func startRememberWatch() {
        tryRemembered()
        guard pendingRemembered, rememberTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Task { @MainActor in GPUControlService.shared.tryRemembered() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rememberTimer = timer
    }

    private func tryRemembered() {
        guard pendingRemembered, let controller else {
            rememberTimer?.invalidate()
            rememberTimer = nil
            return
        }
        if viewers == 0 { control = fake.flatMap(Self.fakeControl) ?? GPUSensorsService.shared.currentControl() }
        guard let facts else { return }
        // Closed: keep waiting for an administrator to open it. Off, or held
        // by another program: give up until the next launch.
        if facts.off || facts.writeOffCode != 0 || (facts.owned && !facts.mine) {
            pendingRemembered = false
            return
        }
        guard facts.armed else { return }
        let remembered = GPUControlRemembered.load(defaults)
        if case .od8 = remembered, !facts.od8Ready, control?.writing?.od8Read?.isWaiting ?? true {
            // OD8 is not read yet after boot or a wake: keep waiting.
            return
        }
        pendingRemembered = false
        // Below the card's floor (saved with an older kext): forget it.
        if GPUControlRememberPolicy.forgets(remembered: remembered, facts: facts) {
            GPUControlRemembered.nothing.save(defaults)
            return
        }
        let writing = control?.writing
        if let request = GPUControlRememberPolicy.request(remembered: remembered, active: rememberActive,
                                                          facts: facts, stopped: snapshot?.stopped,
                                                          stockGfxMaxMHz: writing?.od8?.stockGfxMaxMHz,
                                                          kextVersion: writing?.kextVersion,
                                                          gfxMin: GPUControlClockMinLogic.limits(
                                                            writing: writing, od8Ready: facts.od8Ready),
                                                          volt: GPUControlVoltLogic.limits(
                                                            writing: writing, od8Ready: facts.od8Ready),
                                                          overclock: GPUControlOverclockLogic.gfxLimits(
                                                            writing: writing, od8Ready: facts.od8Ready),
                                                          overclockAllowed: overclock) {
            controller.choose(request, origin: .remembered)
        }
    }
}
