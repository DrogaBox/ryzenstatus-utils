// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Global singleton behind Auto EPP: it watches CPU and GPU load and moves
/// the processor between the Eco, Balance and Performance presets by the
/// EPP thresholds, applying each preset's whole profile for this CPU (CC6,
/// boost, power limits, cHTC, EPP; `AMDPowerPreset.profile(for:)`). Levers a
/// CPU lacks are skipped by `ProcessorModel.applyPowerProfile(_:)`.
///
/// It runs in the background while Auto EPP is on, so the CPU drops to Eco at
/// idle even with no Settings or menu panel view open. Thresholds are read
/// live from AmdSettingsStore, so `@AppStorage` changes in the settings views
/// take effect on the next poll.
@MainActor
final class AutoEppService: ObservableObject {
    static let shared = AutoEppService()

    // MARK: - Published state (observed by views)

    /// Auto EPP is switched on.
    @Published private(set) var isActive: Bool = false
    /// Current average CPU load (0–100%).
    @Published private(set) var currentCPULoad: Float = 0
    /// Current GPU load (0–100%) from SystemMonitor snapshot.
    @Published private(set) var currentGPULoad: Float = 0
    /// Label of the target last applied; empty until a profile has reached
    /// the kext.
    @Published private(set) var currentTarget: String = ""
    /// The EPP of the preset last applied, when this CPU takes EPP writes;
    /// nil otherwise, so no view shows a value the CPU was never given.
    @Published private(set) var currentEPP: UInt8?
    /// Whether the last apply was refused with kIOReturnNotPrivileged.
    @Published private(set) var privilegeDenied: Bool = false
    /// Observable mirror of `ProcessorModel.eppWritesTakeEffect` for the EPP
    /// picker.
    @Published private(set) var writesTakeEffect: Bool = ProcessorModel.eppWritesTakeEffect
    /// A kext is loaded, so presets have something to write to.
    @Published private(set) var canRun: Bool = false
    /// The kext refused the idle clock limit `AMDIdleClockLimitWrites.maxFailures`
    /// times in a row; the settings row shows it as unavailable.
    @Published private(set) var idleClockLimitFailed = false

    // MARK: - Internal state

    private var pollTask: Task<Void, Never>?
    private static let pollInterval: TimeInterval = 1.5
    /// The preset last applied in full, nil when none has been since the
    /// last reset (sleep, a manual change or a kext reload may have moved the
    /// settings it wrote).
    private var lastAppliedPreset: AMDPowerPreset?
    /// The target in force and how many polls in a row asked for a lower
    /// preset than it (see `AutoEppPolicy.settle`).
    private var appliedTarget: AutoEppTarget?
    private var stepDownPolls = 0
    /// The CPPC max perf this service last wrote for the idle clock limit
    /// (0 = none), nil when unknown: the next poll writes it again.
    fileprivate var appliedIdleMaxPerf: UInt8?
    /// Whether a cap may be in force, and the kext's refusals in a row.
    fileprivate var idleLimitWrites = AMDIdleClockLimitWrites()
    /// Retries a refused lift while the loop is stopped.
    private var liftRetryTask: Task<Void, Never>?
    /// The serial queue behind every selector-69 write (see the class at the
    /// bottom of this file): one IPC in flight, off the main actor, values
    /// dispatched in the order they were asked for.
    fileprivate var idleLimitQueue = IdleLimitWriteQueue()
    /// The CPU's CPPC range, read once per kext load (selector 68).
    fileprivate var cppcRange: AMDCppcRange?
    fileprivate var cppcUnsupported = false
    private var wakeObserver: Any?
    private var reconnectObserver: Any?
    /// Set by suspend()/resume(): Gaming Mode holds the power settings.
    private(set) var isSuspended: Bool = false

    @MainActor
    private init() {
        self.isActive = AmdSettingsStore.shared.autoEppEnabled
        // Firmware re-initialises the cores on wake: apply the target again.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // The power source may have changed while asleep: read it
                // first, so the re-apply uses the source after the wake.
                BatteryPowerService.shared.refresh()
                self?.resetApplied()
                // A refusal before the sleep may have been passing: try again.
                self?.clearIdleLimitFailures()
            }
        }
        // The watchdog reopens the kext connection after a kext reload or a
        // dead handle. Closing the old connection lifts the idle clock limit
        // in the kext, so the next poll writes it again on the new one.
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: ProcessorModel.kextReconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.forgetIdleClockLimit()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let reconnectObserver {
            NotificationCenter.default.removeObserver(reconnectObserver)
        }
    }

    /// The kext holds no idle clock limit from this service: a fresh kext, or
    /// a connection that just closed (the kext lifts the limit itself then).
    private func forgetIdleClockLimit() {
        appliedIdleMaxPerf = nil
        idleLimitWrites = AMDIdleClockLimitWrites()
        if idleClockLimitFailed { idleClockLimitFailed = false }
    }

    /// Every value is sent again, and the row stops showing the limit as
    /// unavailable until the kext refuses it again.
    private func clearIdleLimitFailures() {
        idleLimitWrites.clearFailures()
        if idleClockLimitFailed { idleClockLimitFailed = false }
    }

    /// Seconds of system uptime, the clock of `AMDIdleClockLimitWrites`.
    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The next poll applies its target in full even if it did not change.
    private func resetApplied() {
        lastAppliedPreset = nil
        appliedTarget = nil
        stepDownPolls = 0
        appliedIdleMaxPerf = nil
    }

    // MARK: - Lifecycle

    /// Starts the monitoring loop when it can matter (`AutoEppPolicy.shouldRun`).
    /// Called at launch, whenever Auto EPP is switched on or resumed, and when
    /// a kext loads. Idempotent.
    func start() {
        guard pollTask == nil,
              AutoEppPolicy.shouldRun(enabled: AmdSettingsStore.shared.autoEppEnabled,
                                      suspended: isSuspended, kextLoaded: canRun,
                                      profileIdleLimit: profileIdleLimitMHz != nil)
        else { return }
        // The loop writes the limit it wants from its first poll.
        liftRetryTask?.cancel()
        liftRetryTask = nil
        pollTask = Task.detached(priority: .background) { [weak self] in
            // Exit when the owner is gone; nothing else cancels the loop.
            guard let strong = self else { return }
            await strong.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let strong = self else { break }
                await strong.poll()
            }
        }
    }

    /// The idle clock limit of the custom profile in force, while Auto EPP
    /// is off; nil when there is none. The loop then only watches the load
    /// and writes this limit at idle, leaving the profile's other levers as
    /// they were applied.
    private var profileIdleLimitMHz: Int? {
        guard !AmdSettingsStore.shared.autoEppEnabled, !cppcUnsupported,
              let name = AmdPresetController.shared.selectedCustomName,
              let profile = AmdPresetController.shared.customProfiles.first(where: { $0.name == name }),
              let limit = profile.idleClockLimitMHz, limit > 0
        else { return nil }
        return limit
    }

    /// Called when the custom profile in force or its idle clock limit
    /// changes. While Auto EPP is off it starts the loop for the profile's
    /// limit, or stops it and lifts the limit when there is none.
    func customProfileChanged() {
        guard !AmdSettingsStore.shared.autoEppEnabled, !isSuspended else { return }
        resetApplied()
        if profileIdleLimitMHz != nil {
            start()
        } else {
            stopLoop()
        }
    }

    private func stopLoop() {
        pollTask?.cancel()
        pollTask = nil
        AmdPresetController.shared.showAutoPreset(nil)
        liftIdleClockLimit()
    }

    /// Puts the full CPPC range back when this service may have narrowed it:
    /// Auto EPP off, paused for Gaming Mode, or the app quitting. A refused
    /// lift is tried again every poll interval while the loop stays stopped,
    /// until it succeeds; after `AMDIdleClockLimitWrites.maxFailures`
    /// refusals only once every `retryAfter`. If the app dies first, the
    /// kext lifts the limit itself when the connection closes.
    private func liftIdleClockLimit() {
        guard idleLimitWrites.mayBeCapped, canRun else { return }
        // The write leaves the main actor now (it runs on the serial queue);
        // the guards are re-checked after the hop, and a refusal still arms
        // the retry loop.
        Task { [weak self] in
            guard let self else { return }
            guard self.pollTask == nil, self.canRun,
                  self.idleLimitWrites.mayBeCapped else { return }
            let lifted = await self.writeIdleClockLimit(0)
            if !lifted { self.scheduleLiftRetry() }
        }
    }

    private func scheduleLiftRetry() {
        guard liftRetryTask == nil else { return }
        liftRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard self.pollTask == nil, self.canRun, self.idleLimitWrites.mayBeCapped else { break }
                // Given up for now: wait out the retry instead of leaving a
                // cap that may be in force for the whole session.
                let delay = self.idleLimitWrites.retryDelay(for: 0, now: Self.uptime)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                if await self.writeIdleClockLimit(0) { break }
            }
            // start() and stop() cancel and clear it themselves.
            if !Task.isCancelled { self?.liftRetryTask = nil }
        }
    }

    /// Sends the CPPC max perf (min stays the CPU's own) and records the
    /// answer on the main actor, in the order the values were asked for. A
    /// refusal leaves the written value unknown, so whatever the next poll
    /// wants is sent, and a lift is still owed while a cap may be in force.
    ///
    /// Coalescing: when several values are pending, the queue sends only the
    /// newest — a superseded value was about to be overwritten anyway, and
    /// the kext ends at the last value asked for. A superseded value answers
    /// nil: nothing was sent, so no answer is recorded. Its `willWrite`
    /// already ran, so a superseded cap can only cost one extra lift.
    ///
    /// True when the kext took THIS value.
    @discardableResult
    fileprivate func writeIdleClockLimit(_ maxPerf: UInt8) async -> Bool {
        // Before the value leaves: a lift asked for while this cap is still
        // queued or in flight must see that a cap may be in force.
        idleLimitWrites.willWrite(maxPerf)
        // The continuation is made here, on the main actor, so the value
        // joins the queue before this call suspends: two writes asked for in
        // a row reach the queue in that order.
        let queue = idleLimitQueue
        let answer = await withCheckedContinuation { (cont: CheckedContinuation<IdleLimitWriteQueue.Verdict?, Never>) in
            queue.submit(maxPerf, cont: cont)
        }
        guard let verdict = answer else { return false }
        appliedIdleMaxPerf = verdict.succeeded ? maxPerf : nil
        let now = Self.uptime
        if idleLimitWrites.record(maxPerf, succeeded: verdict.succeeded, now: now) {
            NSLog("AutoEppService: the kext refused CPPC max perf %u %ld times; trying it again every %.0f s",
                  UInt32(maxPerf), AMDIdleClockLimitWrites.maxFailures, AMDIdleClockLimitWrites.retryAfter)
        }
        // Shown until a write succeeds, a wake, Auto EPP is switched or the
        // kext reloads.
        let failed = idleLimitWrites.anyGivenUp(now: now)
        if idleClockLimitFailed != failed { idleClockLimitFailed = failed }
        return verdict.succeeded
    }

    /// How long `stop()` may wait for the queued writes to land: the kernel
    /// side of selector 69 is a handful of MSR writes (microseconds) or one
    /// PCC transaction (the latency PCCT declares, single-digit
    /// milliseconds on these boards), so 750 ms is two orders of magnitude
    /// of margin while still shorter than a delay a quitting user notices.
    private static let quitDrainTimeout: TimeInterval = 0.75

    /// Stops the monitoring loop. Called on termination.
    func stop() {
        stopLoop()
        // `stopLoop()` asks for its lift through an async task, which needs
        // the main actor — about to be blocked by the drain below. Enqueue
        // the lift synchronously too (same guard `liftIdleClockLimit` uses):
        // the value is on the serial queue before this returns, the queue
        // needs no main actor to run, and a second lift from the async path
        // either coalesces into this one or repeats the same idempotent 0.
        if idleLimitWrites.mayBeCapped, canRun {
            idleLimitQueue.enqueueDetached(0)
        }
        // Leave the lift written before the process ends, without hanging
        // the quit on a kext that does not answer. A lift that still fails
        // (refused, or past the cap) is covered by the kext itself: closing
        // the connection in `closeDriver()` runs clientClose → the CPPC
        // limits are lifted there.
        idleLimitQueue.waitUntilIdle(until: Date().addingTimeInterval(Self.quitDrainTimeout))
        liftRetryTask?.cancel()
        liftRetryTask = nil
        // Deinit never fires on a `static let shared` singleton.
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let reconnectObserver {
            NotificationCenter.default.removeObserver(reconnectObserver)
            self.reconnectObserver = nil
        }
    }

    /// Called by `ProcessorModel` each time it reads the kext's profile (every
    /// load and reload) and when the kext unloads. A freshly loaded kext holds
    /// none of the user's settings, so Auto EPP starts, or, while it is off,
    /// the manual EPP goes back once. Nothing is written while Gaming Mode
    /// holds the power settings; its `resume()` starts the loop when it ends.
    func kextChanged(loaded: Bool) {
        writesTakeEffect = ProcessorModel.eppWritesTakeEffect
        canRun = loaded
        resetApplied()
        cppcRange = nil
        cppcUnsupported = false
        forgetIdleClockLimit()
        currentEPP = nil
        currentTarget = ""
        if !loaded { stopLoop() }
        guard loaded,
              !isSuspended,
              !AmdSettingsStore.shared.gamingModeActive,
              !GamingModeService.shared.isActive
        else { return }
        if AmdSettingsStore.shared.autoEppEnabled {
            start()
        } else {
            // A custom profile's idle clock limit watches the load too.
            start()
            if writesTakeEffect {
                Task { await AmdPowerControlsModel.shared.restoreManualEPP() }
            }
        }
    }

    // MARK: - Gaming Mode coordination

    /// Pauses the loop without touching AmdSettingsStore, while Gaming Mode
    /// holds the Extreme preset.
    func suspend() {
        stopLoop()
        isSuspended = true
        resetApplied()
    }

    /// Resumes the loop if Auto EPP is still on. Called when Gaming Mode ends.
    func resume() {
        isSuspended = false
        start()
    }

    /// Switches Auto EPP on or off. Off hands the CPU back to the user: their
    /// saved preset is applied again, or, without one, their manual boost and
    /// EPP. `restore: false` when the caller applies a preset of its own.
    func setEnabled(_ on: Bool, restore: Bool = true) {
        AmdSettingsStore.shared.autoEppEnabled = on
        isActive = on
        resetApplied()
        idleLimitWrites.clearFailures()
        if idleClockLimitFailed { idleClockLimitFailed = false }
        currentEPP = nil
        currentTarget = ""
        if on {
            start()
            return
        }
        stopLoop()
        guard restore, !isSuspended else { return }
        Task {
            if let name = AmdPresetController.shared.selectedCustomName,
               let custom = AmdPresetController.shared.customProfiles.first(where: { $0.name == name }) {
                let result = await AmdPresetController.shared.apply(custom: custom)
                self.privilegeDenied = result.privilegeDenied
            } else if let preset = AMDPowerPreset.saved() {
                let result = await AmdPresetController.shared.withPresetTransaction(preset)
                self.privilegeDenied = result.privilegeDenied
            } else {
                await AmdPowerControlsModel.shared.restoreManualBoost()
                if self.writesTakeEffect {
                    let res = await AmdPowerControlsModel.shared.restoreManualEPP(
                        fallback: AMDPowerPreset.balance.eppValue)
                    self.privilegeDenied = res == ProcessorModel.kIOReturnNotPrivilegedCode
                }
            }
        }
    }

    // MARK: - Polling

    func poll() async {
        var profileLimit = isSuspended ? nil : profileIdleLimitMHz
        guard !isSuspended, AmdSettingsStore.shared.autoEppEnabled || profileLimit != nil else {
            if isActive != AmdSettingsStore.shared.autoEppEnabled { isActive = AmdSettingsStore.shared.autoEppEnabled }
            return
        }

        let idleThreshold = Float(AmdSettingsStore.shared.autoEppIdleThreshold)
        let loadThreshold = Float(AmdSettingsStore.shared.autoEppLoadThreshold)
        let gpuLoad = Float((SystemMonitor.shared.snapshot.gpuUsage ?? 0) * 100)
        let cpuFallback = Float((SystemMonitor.shared.snapshot.cpuUsage ?? 0) * 100)
        let loads = await ProcessorModel.shared.getLoadIndex()
        // The loop may have been stopped while the load was read (a profile
        // change lifts the cap): do not write a limit read before that.
        guard pollTask != nil, !Task.isCancelled else { return }
        profileLimit = isSuspended ? nil : profileIdleLimitMHz
        let cpuLoad = loads.isEmpty ? cpuFallback : loads.reduce(0, +) * 100 / Float(loads.count)

        let candidate = AutoEppPolicy.target(cpuLoad: cpuLoad, gpuLoad: gpuLoad,
                                             idleThreshold: idleThreshold, loadThreshold: loadThreshold)
        let settled = AutoEppPolicy.settle(candidate: candidate, current: appliedTarget,
                                           pendingStepDownPolls: stepDownPolls)
        appliedTarget = settled.target
        stepDownPolls = settled.pendingStepDownPolls

        // A custom profile with an idle clock limit: the load decides only
        // the limit. No preset is applied and nothing is published, since
        // Auto EPP itself is off.
        if let profileLimit {
            await applyIdleClockLimit(for: settled.target.preset, limitMHz: profileLimit)
            return
        }
        // On battery the On battery mode may lower the load's target; the
        // hysteresis above stays on the load alone, so plugging in or
        // unplugging changes the preset at this poll.
        let target = BatteryPowerService.shared.autoTarget(settled.target)
        let preset = target.preset

        if preset != lastAppliedPreset {
            let result = await ProcessorModel.shared.applyPreset(preset)
            privilegeDenied = result.privilegeDenied
            // Any other failure records nothing, so the next poll retries.
            if result.succeeded { lastAppliedPreset = preset }
            // The boost, PPM/LPM and CC6 toggles show what the kext now holds.
            Task { await AmdPowerControlsModel.shared.syncFromKext() }
        }
        if lastAppliedPreset == preset {
            await applyIdleClockLimit(for: AMDBatteryPowerPolicy.idleLimitPreset(loadTarget: settled.target,
                                                                                 appliedTarget: target),
                                      limitMHz: AmdSettingsStore.shared.autoEppIdleClockLimitMHz)
        }

        // A loop stopped while this poll ran must not publish its target.
        guard pollTask != nil else { return }
        let applied = lastAppliedPreset == preset
        isActive = true
        if currentCPULoad != cpuLoad { currentCPULoad = cpuLoad }
        if currentGPULoad != gpuLoad { currentGPULoad = gpuLoad }
        let label = applied ? target.label : ""
        if currentTarget != label { currentTarget = label }
        let epp: UInt8? = applied && writesTakeEffect ? preset.eppValue : nil
        if currentEPP != epp { currentEPP = epp }
        AmdPresetController.shared.showAutoPreset(applied ? preset : nil)
    }
}

extension AutoEppService {
    /// The CPPC range the idle clock limit is set in (selector 68). Kept once
    /// known; nil while the kext cannot report it, and `cppcUnsupported`
    /// stops asking a kext without selector 68 or without CPPC.
    func currentCppcRange() -> AMDCppcRange? {
        if let cppcRange { return cppcRange }
        guard canRun, !cppcUnsupported else { return nil }
        guard let range = ProcessorModel.shared.getCppcRange(), range.mechanism != .none else {
            cppcUnsupported = true
            return nil
        }
        // ACPI CPPC reports its range only after the first EPP write.
        if range.isKnown { cppcRange = range }
        return range
    }

    /// Writes the CPPC max perf for this preset (`limit` while Eco holds,
    /// none otherwise) when it differs from the last one written. `limit` is
    /// Auto EPP's idle clock limit, or the custom profile's while Auto EPP
    /// is off.
    /// A refused write records nothing, so the next poll retries, up to
    /// `AMDIdleClockLimitWrites.maxFailures` refusals of the same value and
    /// then once every `retryAfter`.
    fileprivate func applyIdleClockLimit(for preset: AMDPowerPreset, limitMHz limit: Int) async {
        guard let range = currentCppcRange() else { return }
        let maxPerf = AMDIdleClockLimitPolicy.maxPerf(preset: preset, limitMHz: limit, range: range)
        let now = Self.uptime
        // A retry window that ran out shows the row as available again.
        let failed = idleLimitWrites.anyGivenUp(now: now)
        if idleClockLimitFailed != failed { idleClockLimitFailed = failed }
        guard maxPerf != appliedIdleMaxPerf, !idleLimitWrites.hasGivenUp(on: maxPerf, now: now) else { return }
        await writeIdleClockLimit(maxPerf)
    }
}

/// One serial queue for every selector-69 write, so the kext receives the
/// values in the order the service asked for them — a cap sent before a lift
/// can never land after it — and the main thread never waits on the IPC: the
/// write itself runs on a dedicated serial queue, and `enqueue` suspends its
/// caller instead of blocking it.
///
/// Coalescing: a write that has not started yet is replaced by a newer one.
/// When the queue picks the next value it takes the NEWEST pending, resumes
/// the waiters it superseded with nil (nothing was sent, nothing is to be
/// recorded) and answers the newest waiter with the kext's real verdict — so
/// the last value asked for always reaches the kext, and its result is
/// recorded on the main actor, in request order.
final class IdleLimitWriteQueue: @unchecked Sendable {
    struct Verdict: Sendable { let value: UInt8; let succeeded: Bool }

    private struct Waiter: Sendable {
        let value: UInt8
        let cont: CheckedContinuation<Verdict?, Never>?
    }

    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var running = false
    private let queue = DispatchQueue(label: "wtf.spinach.RyzenStatus.idle-limit-69", qos: .utility)

    /// Queues `value`. Nil when a newer value superseded this one before its
    /// write started; otherwise the kext's answer for the write that carried
    /// the newest value at dispatch time — the caller's own whenever no newer
    /// value arrived in between.
    func enqueue(_ value: UInt8) async -> Verdict? {
        await withCheckedContinuation { (cont: CheckedContinuation<Verdict?, Never>) in
            submit(value, cont: cont)
        }
    }

    /// Queues `value` with the continuation that gets its answer, from the
    /// caller's own context: the value is on the queue when this returns.
    func submit(_ value: UInt8, cont: CheckedContinuation<Verdict?, Never>) {
        enqueue(value, cont: cont)
    }

    /// Fire-and-forget variant: the value is on the queue before this
    /// returns and no verdict is delivered. For the termination path, where
    /// the caller is about to block the main actor and only the write
    /// landing matters.
    func enqueueDetached(_ value: UInt8) {
        enqueue(value, cont: nil)
    }

    /// True when nothing is pending and no write is in flight.
    var isIdle: Bool {
        lock.lock(); defer { lock.unlock() }
        return waiters.isEmpty && !running
    }

    /// Blocks the calling thread until the queue settles or `deadline`
    /// passes (checked every 5 ms). The queue needs no main actor, so this
    /// is safe to call with the main thread blocked.
    func waitUntilIdle(until deadline: Date) {
        while !isIdle, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private func enqueue(_ value: UInt8, cont: CheckedContinuation<Verdict?, Never>?) {
        lock.lock()
        waiters.append(Waiter(value: value, cont: cont))
        let start = !running
        if start { running = true }
        lock.unlock()
        if start { queue.async { self.run() } }
    }

    /// The queue's own thread: one IPC at a time, newest value first.
    private func run() {
        while true {
            lock.lock()
            guard let newest = waiters.last else {
                running = false
                lock.unlock()
                return
            }
            let superseded = Array(waiters.dropLast())
            waiters.removeAll()
            lock.unlock()

            let status = ProcessorModel.shared.setCppcLimits(minPerf: 0, maxPerf: newest.value)
            let verdict = Verdict(value: newest.value, succeeded: status == KERN_SUCCESS)

            // Request order: those asked first (and superseded) resume
            // first, with nothing to record.
            for waiter in superseded { waiter.cont?.resume(returning: nil) }
            newest.cont?.resume(returning: verdict)
        }
    }
}

/// What Auto EPP asks the CPU for.
enum AutoEppTarget: Equatable {
    case gpuPerformance, performance, gpuActive, balanced, powerSave

    /// The preset this target applies.
    var preset: AMDPowerPreset {
        switch self {
        case .gpuPerformance, .performance: return .performance
        case .gpuActive, .balanced: return .balance
        case .powerSave: return .eco
        }
    }

    /// The preset's name, marked when the GPU load chose it.
    @MainActor
    var label: String {
        let s = L10n.shared.amdPower
        switch self {
        case .performance: return s.presetPerformance
        case .gpuPerformance: return "GPU · \(s.presetPerformance)"
        case .balanced: return s.presetBalance
        case .gpuActive: return "GPU · \(s.presetBalance)"
        case .powerSave: return s.presetEco
        }
    }
}

/// Auto EPP's decisions, kept apart from the service so they can be tested.
enum AutoEppPolicy {
    /// GPU load above which the CPU is kept at full performance to feed it.
    static let gpuHeavyThreshold: Float = 60
    /// GPU load above which the CPU is not allowed to idle down.
    static let gpuActiveThreshold: Float = 30
    /// Polls in a row (1.5 s apart) a lower preset must be asked for before
    /// it is applied.
    static let stepDownPolls = 3

    /// Whether the poll loop runs at all: without a kext it would wake the
    /// app every 1.5 s to change nothing. `profileIdleLimit`: Auto EPP is off
    /// and the custom profile in force has an idle clock limit, so the loop
    /// runs to watch the load for it.
    static func shouldRun(enabled: Bool, suspended: Bool, kextLoaded: Bool,
                          profileIdleLimit: Bool = false) -> Bool {
        (enabled || profileIdleLimit) && !suspended && kextLoaded
    }

    /// The EPP picker value the views show (0/85/170/255), or nil to leave it
    /// unselected: while the kext ignores EPP writes, or while Auto EPP is on
    /// and has not applied a value yet. Never a made-up "Max".
    static func shownEPP(writesTakeEffect: Bool, autoActive: Bool,
                         autoEPP: UInt8?, manualEPP: UInt8) -> UInt8? {
        guard writesTakeEffect else { return nil }
        if autoActive { return autoEPP.map(AMDPowerPreset.snapEPP) }
        return AMDPowerPreset.snapEPP(manualEPP)
    }

    /// The target for one reading of CPU and GPU load (0–100).
    static func target(cpuLoad: Float, gpuLoad: Float,
                       idleThreshold: Float, loadThreshold: Float) -> AutoEppTarget {
        if gpuLoad > gpuHeavyThreshold { return .gpuPerformance }
        if cpuLoad < idleThreshold && gpuLoad < gpuActiveThreshold { return .powerSave }
        if cpuLoad > loadThreshold { return .performance }
        if gpuLoad > gpuActiveThreshold { return .gpuActive }
        return .balanced
    }

    /// Fast up, slow down: a higher preset applies at once, so a burst of
    /// work is never held back, while a lower one waits until it has been
    /// asked for `stepDownPolls` times in a row, so load hovering around a
    /// threshold does not flip presets every poll.
    static func settle(candidate: AutoEppTarget, current: AutoEppTarget?,
                       pendingStepDownPolls: Int) -> (target: AutoEppTarget, pendingStepDownPolls: Int) {
        guard let current, rank(candidate.preset) < rank(current.preset) else {
            return (candidate, 0)
        }
        let pending = pendingStepDownPolls + 1
        return pending >= stepDownPolls ? (candidate, 0) : (current, pending)
    }

    private static func rank(_ preset: AMDPowerPreset) -> Int {
        AMDPowerPreset.allCases.firstIndex(of: preset) ?? 0
    }
}
