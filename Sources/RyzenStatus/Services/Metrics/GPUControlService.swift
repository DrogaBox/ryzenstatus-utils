// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Whether the GPU control page and its panel row exist: only with a kext
/// that has the write path (0.5.0 and later), or with the model in a
/// development build. Thread-safe, so the Settings directory can ask.
enum GPUControlVisibility {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fake = false

    static var isVisible: Bool {
        lock.withLock { fake } || GPUSensorsService.shared.hasWritePathNow
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
    @Published private(set) var armTool: GPUControlArmTool.Availability = .missing(buildPath: nil)
    @Published private(set) var isArming = false
    @Published private(set) var armFailed = false
    @Published private(set) var mode: GPUControlConnectionMode = .none
    /// The "remember" box (off by default).
    @Published var remember: Bool {
        didSet {
            guard remember != oldValue else { return }
            defaults.set(remember, forKey: DefaultsKey.gpuControlRemember)
            rememberChanged()
        }
    }

    private let defaults: UserDefaults
    private var controller: GPUControlController?
    private var fake: FakeGPUControlKext?
    private var viewers = 0
    private var pollTimer: Timer?
    private var rememberTimer: Timer?
    private var pendingRemembered = false
    private var ownerChoseStartUp = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remember = defaults.bool(forKey: DefaultsKey.gpuControlRemember)
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
        controller.start()
        self.controller = controller
        if rememberActive, GPUControlRemembered.load(defaults) != .nothing {
            pendingRemembered = true
            startRememberWatch()
        }
    }

    /// `applicationWillTerminate`: release at once, close (1 s at most).
    func shutdown() {
        pollTimer?.invalidate()
        rememberTimer?.invalidate()
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
        ownerChoseStartUp = false
        controller.choose(.power(watts: UInt32(watts)))
    }

    func backToStartUp() {
        guard let controller else { return }
        ownerChoseStartUp = true
        controller.choose(.startUp)
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
        if let fake {
            fake.advance(by: 1_000)
            control = Self.fakeControl(fake)
        } else {
            control = GPUSensorsService.shared.currentControl()
        }
        controller?.refresh()
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
            : GPUControlArmTool.availability(home: NSHomeDirectory())
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
        if next.held != previous?.held || (ownerChoseStartUp && next.held == nil && next.activity == .none) {
            if let save = GPUControlRememberPolicy.toSave(held: next.held,
                                                          ownerChoseStartUp: ownerChoseStartUp && next.held == nil,
                                                          active: rememberActive) {
                save.save(defaults)
            }
            if next.held == nil, next.activity == .none { ownerChoseStartUp = false }
        }
        if next.stopped != nil { pendingRemembered = false }
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
        } else if rememberActive, case .power(let watts)? = snapshot?.held {
            GPUControlRemembered.power(watts: Int(watts)).save(defaults)
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
        pendingRemembered = false
        if let request = GPUControlRememberPolicy.request(remembered: .load(defaults), active: rememberActive,
                                                          facts: facts, stopped: snapshot?.stopped) {
            controller.choose(request, origin: .remembered)
        }
    }
}
