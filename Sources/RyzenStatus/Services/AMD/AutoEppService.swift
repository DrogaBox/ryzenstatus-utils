// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Global singleton that monitors CPU load and automatically adjusts the EPP
/// (Energy Performance Preference) when Auto EPP mode is active.
///
/// Unlike per-view timers, this service runs in the background while Auto EPP
/// is on, so the CPU throttles down to Power Save during idle even when no
/// Settings or menu panel view is open. It does not run while the kext
/// ignores EPP writes (`ProcessorModel.eppWritesTakeEffect`), and starts as
/// soon as a kext that applies them loads (`kextEppSupportChanged(_:)`).
///
/// Thresholds are read live from AmdSettingsStore, so changes via `@AppStorage`
/// in the settings views take effect immediately on the next poll cycle.
@MainActor
final class AutoEppService: ObservableObject {
    static let shared = AutoEppService()

    // MARK: - Published state (observed by views)

    /// Whether the kext reports Auto EPP as active.
    @Published private(set) var isActive: Bool = false
    /// Current average CPU load (0–100%).
    @Published private(set) var currentCPULoad: Float = 0
    /// Current GPU load (0–100%) from SystemMonitor snapshot.
    @Published private(set) var currentGPULoad: Float = 0
    /// Human-readable label for the EPP target the service last applied;
    /// empty until a write has reached the kext.
    @Published private(set) var currentTarget: String = ""
    /// The raw EPP value last written to the kext; nil until one is, so no
    /// view shows a value the CPU was never given.
    @Published private(set) var currentEPP: UInt8?
    /// Whether the last write attempt returned kIOReturnNotPrivileged.
    @Published private(set) var privilegeDenied: Bool = false
    /// Observable mirror of `ProcessorModel.eppWritesTakeEffect`, so views
    /// update when a kext that applies EPP loads or goes away.
    @Published private(set) var writesTakeEffect: Bool = ProcessorModel.eppWritesTakeEffect

    // MARK: - Internal state

    private var pollTask: Task<Void, Never>?
    private static let pollInterval: TimeInterval = 1.5
    /// The EPP last written, nil when none has been since the last reset.
    /// Used to skip redundant MSR writes. Not a 0xFF sentinel: 255 is the
    /// Power Save target, which a sentinel would have skipped forever.
    private var lastWrittenEPP: UInt8?
    /// The target in force and how many polls in a row asked for less
    /// performance than it (see `AutoEppPolicy.settle`).
    private var appliedTarget: AutoEppTarget?
    private var stepDownPolls = 0
    /// Wake observer token. Without it the EPP was never restored after
    /// sleep — see resetWriteSentinel().
    private var wakeObserver: Any?
    /// Set by suspend()/resume() — blocks poll() writes without touching UserDefaults.
    private(set) var isSuspended: Bool = false

    @MainActor
    private init() {
        self.isActive = AmdSettingsStore.shared.autoEppEnabled
        // This was the only AMD service with no wake handling
        // (FanCurveController and C6ResidencyService both observe didWake).
        // Pattern matches C6ResidencyService.swift:38-55.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetWriteSentinel()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Clears the dedup sentinel so the next poll re-asserts the EPP.
    ///
    /// `poll()` skips the MSR write when `targetEPP == lastWrittenEPP`. That is
    /// correct in steady state, but the SMU can lose the EPP across a suspend
    /// while our target value is unchanged — in which case the write was skipped
    /// forever and the EPP silently stayed at the firmware default until the
    /// user happened to change presets. nil means "never written".
    private func resetWriteSentinel() {
        lastWrittenEPP = nil
        appliedTarget = nil
        stepDownPolls = 0
    }

    // MARK: - Lifecycle

    /// Starts the monitoring loop when it can matter (`AutoEppPolicy.shouldRun`).
    /// Called from the app delegate at launch, whenever Auto EPP is switched
    /// on or resumed, and when a kext that applies EPP loads (the launch call
    /// may run before the kext profile is read). Idempotent — safe to call
    /// multiple times.
    func start() {
        guard pollTask == nil,
              AutoEppPolicy.shouldRun(enabled: AmdSettingsStore.shared.autoEppEnabled,
                                      suspended: isSuspended,
                                      writesTakeEffect: ProcessorModel.eppWritesTakeEffect)
        else { return }
        pollTask = Task.detached(priority: .background) { [weak self] in
            // Exit the loop when the owner is gone. Previously the
            // `await self?.poll()` simply no-op'd and the loop kept waking every
            // 1.5 s forever, because the only thing that cancels it is a method
            // on the object that just went away.
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
    }

    /// Stops the monitoring loop. Called on termination.
    func stop() {
        stopLoop()
        // Deinit never fires on a `static let shared` singleton, so the
        // observer is released here — stop() is the real teardown point
        // (AppDelegate.applicationWillTerminate).
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Called by `ProcessorModel` each time it reads the kext's eppApplied
    /// flag: on every load and reload, and with `false` when the kext unloads.
    /// A freshly loaded kext holds no EPP of the user's, so with the flag set
    /// Auto EPP starts, or, while it is off, the manual EPP is written back
    /// once. Nothing is written while Gaming Mode holds the EPP, including at
    /// launch before `GamingModeService.restoreIfNeeded()` has suspended this
    /// service; its `resume()` starts the loop when the mode ends.
    func kextEppSupportChanged(_ applied: Bool) {
        writesTakeEffect = applied
        resetWriteSentinel()
        currentEPP = nil
        currentTarget = ""
        guard applied,
              !isSuspended,
              !AmdSettingsStore.shared.gamingModeActive,
              !GamingModeService.shared.isActive
        else { return }
        if AmdSettingsStore.shared.autoEppEnabled {
            start()
        } else {
            Task { await AmdPowerControlsModel.shared.restoreManualEPP() }
        }
    }

    // MARK: - Gaming Mode coordination

    /// Suspends the Auto EPP poll loop without touching AmdSettingsStore.
    /// Used by GamingModeService to prevent poll-cycle EPP overwrites
    /// while Gaming Mode holds the Extreme preset.
    /// Safe to call when already suspended (idempotent).
    func suspend() {
        stopLoop()
        isSuspended = true
        resetWriteSentinel() // F7: resume writes immediately
    }

    /// Resumes the poll loop if Auto EPP is still enabled in AmdSettingsStore.
    /// GamingModeService calls this on deactivation.
    @MainActor
    func resume() {
        isSuspended = false
        start()
    }

    /// Switches Auto EPP on or off and updates published state immediately.
    ///
    /// On engages CPPC active mode (selector 24 = 1). Off does not send
    /// selector 24 = 0, which cannot release CPPC before a reboot and pins
    /// EPP 0 (max performance): the user's manual EPP is written instead, so
    /// the manual picker takes over from the last Auto EPP value.
    @MainActor
    func setCPPCActive(_ active: Bool) {
        AmdSettingsStore.shared.autoEppEnabled = active
        self.isActive = active
        // A preset or the manual picker may have written the EPP since Auto
        // EPP last did, so its first poll after this must write again.
        resetWriteSentinel()
        currentEPP = nil
        currentTarget = ""
        if active {
            start()
            Task {
                let res = await Task.detached(priority: .userInitiated) {
                    ProcessorModel.shared.setCPPCActiveMode(active: true)
                }.value
                self.privilegeDenied = res == ProcessorModel.kIOReturnNotPrivilegedCode
                if self.pollTask != nil { await self.poll() }
            }
        } else {
            stopLoop()
            // Gaming Mode holds the EPP while suspended; a kext that ignores
            // EPP would only answer unsupported.
            guard !isSuspended, writesTakeEffect else { return }
            Task {
                let res = await AmdPowerControlsModel.shared.restoreManualEPP(
                    fallback: AMDPowerPreset.balance.eppValue)
                self.privilegeDenied = res == ProcessorModel.kIOReturnNotPrivilegedCode
            }
        }
    }

    // MARK: - Polling

    func poll() async {
        guard !isSuspended else { return }
        // Thread-safe connection check to avoid data races
        let isConnected = ProcessorModel.shared.isConnected
        guard isConnected else {
            await MainActor.run {
                if self.currentCPULoad != 0 { self.currentCPULoad = 0 }
                if self.currentGPULoad != 0 { self.currentGPULoad = 0 }
                if !self.currentTarget.isEmpty { self.currentTarget = "" }
            }
            return
        }

        // F12: Snapshot all MainActor settings at once
        let (enabled, idleThreshold, loadThreshold, gpuUsage, cpuUsageFallback) = await MainActor.run {
            (
                AmdSettingsStore.shared.autoEppEnabled,
                AmdSettingsStore.shared.autoEppIdleThreshold,
                AmdSettingsStore.shared.autoEppLoadThreshold,
                SystemMonitor.shared.snapshot.gpuUsage ?? 0,
                Float((SystemMonitor.shared.snapshot.cpuUsage ?? 0) * 100)
            )
        }

        // F12: If Auto EPP is disabled, early return before reading Mach CPU load
        guard enabled else {
            await MainActor.run {
                if self.isActive != false { self.isActive = false }
                if !self.currentTarget.isEmpty { self.currentTarget = "" }
            }
            return
        }

        let loads = await ProcessorModel.shared.getLoadIndex()
        let cpuAvg: Float = !loads.isEmpty
            ? (loads.reduce(0, +) * 100 / Float(loads.count))
            : cpuUsageFallback

        let gpuLoad = Float(gpuUsage * 100)

        let candidate = AutoEppPolicy.target(cpuLoad: cpuAvg, gpuLoad: gpuLoad,
                                             idleThreshold: Float(idleThreshold),
                                             loadThreshold: Float(loadThreshold))
        let settled = AutoEppPolicy.settle(candidate: candidate, current: appliedTarget,
                                           pendingStepDownPolls: stepDownPolls)
        appliedTarget = settled.target
        stepDownPolls = settled.pendingStepDownPolls
        let targetEPP = settled.target.epp
        let targetName = settled.target.label

        var newPrivilegeDenied = self.privilegeDenied
        if targetEPP != lastWrittenEPP {
            let writeRes = await ProcessorModel.shared.setCPPCEPPValue(epp: targetEPP)
            if writeRes == KERN_SUCCESS {
                newPrivilegeDenied = false
                lastWrittenEPP = targetEPP
            } else if writeRes == ProcessorModel.kIOReturnNotPrivilegedCode {
                newPrivilegeDenied = true
            }
            // Any other failure records nothing, so the next poll retries.
        }

        // Only what reached the kext is shown: a refused write leaves the
        // CPU on the last value written, or on none.
        let finalEPP = lastWrittenEPP
        let finalTarget = lastWrittenEPP == targetEPP ? targetName : ""
        let finalPrivilegeDenied = newPrivilegeDenied

        await MainActor.run {
            if self.isActive != enabled { self.isActive = enabled }
            if self.currentCPULoad != cpuAvg { self.currentCPULoad = cpuAvg }
            if self.currentGPULoad != gpuLoad { self.currentGPULoad = gpuLoad }
            if self.currentTarget != finalTarget { self.currentTarget = finalTarget }
            if self.currentEPP != finalEPP { self.currentEPP = finalEPP }
            if self.privilegeDenied != finalPrivilegeDenied { self.privilegeDenied = finalPrivilegeDenied }
        }
    }
}

/// What Auto EPP asks the CPU for.
enum AutoEppTarget: Equatable {
    case gpuPerformance, performance, gpuActive, balanced, powerSave

    var epp: UInt8 {
        switch self {
        case .gpuPerformance, .performance: return 0
        case .gpuActive, .balanced: return 128
        case .powerSave: return 255
        }
    }

    /// The same names the manual EPP picker shows for these values.
    @MainActor
    var label: String {
        let s = L10n.shared.amdPower
        switch self {
        case .performance: return s.perfMax
        case .gpuPerformance: return "GPU · \(s.perfMax)"
        case .balanced: return s.perfBalMinus
        case .gpuActive: return "GPU · \(s.perfBalMinus)"
        case .powerSave: return s.perfEco
        }
    }
}

/// Auto EPP's decisions, kept apart from the service so they can be tested.
enum AutoEppPolicy {
    /// GPU load above which the CPU is kept at full performance to feed it.
    static let gpuHeavyThreshold: Float = 60
    /// GPU load above which the CPU is not allowed to idle down.
    static let gpuActiveThreshold: Float = 30
    /// Polls in a row (1.5 s apart) a lower-performance target must be asked
    /// for before it is applied.
    static let stepDownPolls = 3

    /// Whether the poll loop runs at all. While the kext ignores EPP writes
    /// (`ProcessorModel.eppWritesTakeEffect`) it would wake the app every
    /// 1.5 s to change nothing.
    static func shouldRun(enabled: Bool, suspended: Bool, writesTakeEffect: Bool) -> Bool {
        enabled && !suspended && writesTakeEffect
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

    /// Fast up, slow down: more performance applies at once, so a burst of
    /// work is never held back, while less performance waits until it has
    /// been asked for `stepDownPolls` times in a row, so load hovering around
    /// a threshold does not flip the EPP every poll.
    static func settle(candidate: AutoEppTarget, current: AutoEppTarget?,
                       pendingStepDownPolls: Int) -> (target: AutoEppTarget, pendingStepDownPolls: Int) {
        guard let current, candidate.epp > current.epp else {
            return (candidate, 0)
        }
        let pending = pendingStepDownPolls + 1
        return pending >= stepDownPolls ? (candidate, 0) : (current, pending)
    }
}
