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
    private var wakeObserver: Any?
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
                self?.resetApplied()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// The next poll applies its target in full even if it did not change.
    private func resetApplied() {
        lastAppliedPreset = nil
        appliedTarget = nil
        stepDownPolls = 0
    }

    // MARK: - Lifecycle

    /// Starts the monitoring loop when it can matter (`AutoEppPolicy.shouldRun`).
    /// Called at launch, whenever Auto EPP is switched on or resumed, and when
    /// a kext loads. Idempotent.
    func start() {
        guard pollTask == nil,
              AutoEppPolicy.shouldRun(enabled: AmdSettingsStore.shared.autoEppEnabled,
                                      suspended: isSuspended, kextLoaded: canRun)
        else { return }
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

    private func stopLoop() {
        pollTask?.cancel()
        pollTask = nil
        AmdPresetController.shared.showAutoPreset(nil)
    }

    /// Stops the monitoring loop. Called on termination.
    func stop() {
        stopLoop()
        // Deinit never fires on a `static let shared` singleton.
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
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
        } else if writesTakeEffect {
            Task { await AmdPowerControlsModel.shared.restoreManualEPP() }
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
        currentEPP = nil
        currentTarget = ""
        if on {
            start()
            return
        }
        stopLoop()
        guard restore, !isSuspended else { return }
        Task {
            if let preset = AMDPowerPreset.saved() {
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
        guard !isSuspended, AmdSettingsStore.shared.autoEppEnabled else {
            if isActive != AmdSettingsStore.shared.autoEppEnabled { isActive = AmdSettingsStore.shared.autoEppEnabled }
            return
        }

        let idleThreshold = Float(AmdSettingsStore.shared.autoEppIdleThreshold)
        let loadThreshold = Float(AmdSettingsStore.shared.autoEppLoadThreshold)
        let gpuLoad = Float((SystemMonitor.shared.snapshot.gpuUsage ?? 0) * 100)
        let cpuFallback = Float((SystemMonitor.shared.snapshot.cpuUsage ?? 0) * 100)
        let loads = await ProcessorModel.shared.getLoadIndex()
        let cpuLoad = loads.isEmpty ? cpuFallback : loads.reduce(0, +) * 100 / Float(loads.count)

        let candidate = AutoEppPolicy.target(cpuLoad: cpuLoad, gpuLoad: gpuLoad,
                                             idleThreshold: idleThreshold, loadThreshold: loadThreshold)
        let settled = AutoEppPolicy.settle(candidate: candidate, current: appliedTarget,
                                           pendingStepDownPolls: stepDownPolls)
        appliedTarget = settled.target
        stepDownPolls = settled.pendingStepDownPolls
        let preset = settled.target.preset

        if preset != lastAppliedPreset {
            let result = await ProcessorModel.shared.applyPreset(preset)
            privilegeDenied = result.privilegeDenied
            // Any other failure records nothing, so the next poll retries.
            if result.succeeded { lastAppliedPreset = preset }
            // The boost, PPM/LPM and CC6 toggles show what the kext now holds.
            Task { await AmdPowerControlsModel.shared.syncFromKext() }
        }

        // A loop stopped while this poll ran must not publish its target.
        guard pollTask != nil else { return }
        let applied = lastAppliedPreset == preset
        isActive = true
        if currentCPULoad != cpuLoad { currentCPULoad = cpuLoad }
        if currentGPULoad != gpuLoad { currentGPULoad = gpuLoad }
        let label = applied ? settled.target.label : ""
        if currentTarget != label { currentTarget = label }
        let epp: UInt8? = applied && writesTakeEffect ? preset.eppValue : nil
        if currentEPP != epp { currentEPP = epp }
        AmdPresetController.shared.showAutoPreset(applied ? preset : nil)
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
    /// app every 1.5 s to change nothing.
    static func shouldRun(enabled: Bool, suspended: Bool, kextLoaded: Bool) -> Bool {
        enabled && !suspended && kextLoaded
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
