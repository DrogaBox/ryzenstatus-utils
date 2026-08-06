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
/// Thresholds are read live from UserDefaults, so changes via `@AppStorage`
/// in the settings views take effect immediately on the next poll cycle.
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

    private var timer: Timer?
    private static let pollInterval: TimeInterval = 1.5

    private init() {
        self.isActive = UserDefaults.standard.bool(forKey: DefaultsKey.autoEppEnabled)
    }

    // MARK: - Lifecycle

    /// Starts the monitoring loop. Called once from the app delegate at launch.
    /// Idempotent — safe to call multiple times.
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Fire immediately so the UI has data on first observation.
        poll()
    }

    /// Stops the monitoring loop. Called on termination.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Toggles CPPC Active Mode in the kext and updates published state immediately.
    @MainActor
    func setCPPCActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: DefaultsKey.autoEppEnabled)
        self.isActive = active
        let res = ProcessorModel.shared.setCPPCActiveMode(active: active)
        if res == ProcessorModel.kIOReturnNotPrivilegedCode {
            privilegeDenied = true
        } else {
            privilegeDenied = false
        }
        poll()
    }

    // MARK: - Polling

    func poll() {
        Task { @MainActor in
            guard ProcessorModel.shared.connect != 0 else {
                currentCPULoad = 0
                currentGPULoad = 0
                currentTarget = ""
                return
            }

            let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoEppEnabled)
            if self.isActive != enabled {
                self.isActive = enabled
            }

            // Read CPU load continuously so the UI load meter always reflects live load
            let loads = await ProcessorModel.shared.getLoadIndex()
            let cpuAvg: Float
            if !loads.isEmpty {
                cpuAvg = loads.reduce(0, +) * 100 / Float(loads.count)
            } else {
                cpuAvg = Float((SystemMonitor.shared.snapshot.cpuUsage ?? 0) * 100)
            }
            currentCPULoad = cpuAvg

            // Read GPU load from SystemMonitor snapshot
            let gpuUtil = SystemMonitor.shared.snapshot.gpuUsage ?? 0
            let gpuLoad = Float(gpuUtil * 100)
            currentGPULoad = gpuLoad

            guard enabled else {
                currentTarget = ""
                return
            }

            // Read thresholds live from UserDefaults — they change via @AppStorage.
            let idleThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppIdleThreshold)
            let loadThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppLoadThreshold)

            // GPU-aware EPP logic:
            // - If GPU is heavily loaded (>60%), force Performance mode for gaming/rendering
            // - If GPU is loaded (>30%) but CPU is idle, use Balanced (media playback)
            // - Otherwise, use standard CPU-based logic
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

            currentTarget = targetName
            currentEPP = targetEPP

            let writeRes = ProcessorModel.shared.setCPPCEPPValue(epp: targetEPP)
            if writeRes == ProcessorModel.kIOReturnNotPrivilegedCode {
                privilegeDenied = true
            }
        }
    }
}
