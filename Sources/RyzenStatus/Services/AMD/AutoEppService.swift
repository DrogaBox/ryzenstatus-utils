// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// Global singleton that monitors CPU load and automatically adjusts the EPP
/// (Energy Performance Preference) when Auto EPP mode is active.
///
/// Unlike per-view timers, this service runs continuously in the background
/// so the CPU throttles down to Power Save during idle even when no Settings
/// or menu panel view is open.
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
    /// Human-readable label for the EPP target the service last applied.
    @Published private(set) var currentTarget: String = ""
    /// The raw EPP value last written to the kext.
    @Published private(set) var currentEPP: UInt8 = 0
    /// Whether the last write attempt returned kIOReturnNotPrivileged.
    @Published private(set) var privilegeDenied: Bool = false

    // MARK: - Internal state

    private var pollTask: Task<Void, Never>?
    private static let pollInterval: TimeInterval = 1.5
    /// Sentinel (0xFF) means "never written". Used to skip redundant MSR writes.
    private var lastWrittenEPP: UInt8 = 0xFF
    /// Set by suspend()/resume() — blocks poll() writes without touching UserDefaults.
    private(set) var isSuspended: Bool = false

    @MainActor
    private init() {
        self.isActive = AmdSettingsStore.shared.autoEppEnabled
    }

    // MARK: - Lifecycle

    /// Starts the monitoring loop. Called once from the app delegate at launch.
    /// Idempotent — safe to call multiple times.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached(priority: .background) { [weak self] in
            await self?.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                await self?.poll()
            }
        }
    }

    /// Stops the monitoring loop. Called on termination.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Gaming Mode coordination

    /// Suspends the Auto EPP poll loop without touching AmdSettingsStore.
    /// Used by GamingModeService to prevent poll-cycle EPP overwrites
    /// while Gaming Mode holds the Extreme preset.
    /// Safe to call when already suspended (idempotent).
    func suspend() {
        pollTask?.cancel()
        pollTask = nil
        isSuspended = true
        lastWrittenEPP = 0xFF // F7: reset sentinel so resume writes immediately
    }

    /// Resumes the poll loop if Auto EPP is still enabled in AmdSettingsStore.
    /// GamingModeService calls this on deactivation.
    @MainActor
    func resume() {
        isSuspended = false
        guard AmdSettingsStore.shared.autoEppEnabled else { return }
        start()
    }

    /// Toggles CPPC Active Mode in the kext and updates published state immediately.
    @MainActor
    func setCPPCActive(_ active: Bool) {
        AmdSettingsStore.shared.autoEppEnabled = active
        self.isActive = active
        Task {
            let res = ProcessorModel.shared.setCPPCActiveMode(active: active)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeDenied = true
            } else {
                self.privilegeDenied = false
            }
            await self.poll()
        }
    }

    // MARK: - Polling

    func poll() async {
        guard !isSuspended else { return }
        // AUDIT F-27: thread-safe connection check to avoid data races
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

        let gpuHeavyThreshold: Float = 60
        let gpuActiveThreshold: Float = 30

        let targetEPP: UInt8
        let targetName: String

        if gpuLoad > gpuHeavyThreshold {
            targetEPP = 0
            targetName = "GPU Performance"
        } else if cpuAvg < Float(idleThreshold) && gpuLoad < gpuActiveThreshold {
            targetEPP = 255
            targetName = "Power Save"
        } else if cpuAvg > Float(loadThreshold) {
            targetEPP = 0
            targetName = "Performance"
        } else if gpuLoad > gpuActiveThreshold {
            targetEPP = 128
            targetName = "GPU Active"
        } else {
            targetEPP = 128
            targetName = "Balanced"
        }

        var newPrivilegeDenied = self.privilegeDenied
        if targetEPP != lastWrittenEPP {
            let writeRes = await ProcessorModel.shared.setCPPCEPPValue(epp: targetEPP)
            if writeRes == ProcessorModel.kIOReturnNotPrivilegedCode {
                newPrivilegeDenied = true
            } else {
                newPrivilegeDenied = false
                lastWrittenEPP = targetEPP
            }
        }

        let finalEPP = targetEPP
        let finalPrivilegeDenied = newPrivilegeDenied

        await MainActor.run {
            if self.isActive != enabled { self.isActive = enabled }
            if self.currentCPULoad != cpuAvg { self.currentCPULoad = cpuAvg }
            if self.currentGPULoad != gpuLoad { self.currentGPULoad = gpuLoad }
            if self.currentTarget != targetName { self.currentTarget = targetName }
            if self.currentEPP != finalEPP { self.currentEPP = finalEPP }
            if self.privilegeDenied != finalPrivilegeDenied { self.privilegeDenied = finalPrivilegeDenied }
        }
    }
}
