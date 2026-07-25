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

    // MARK: - Internal state

    private var timer: Timer?
    private static let pollInterval: TimeInterval = 2.0

    private init() {}

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

    // MARK: - Polling

    private func poll() {
        Task { @MainActor in
            guard ProcessorModel.shared.connect != 0 else {
                isActive = false
                currentCPULoad = 0
                currentGPULoad = 0
                currentTarget = ""
                return
            }

            let state = ProcessorModel.shared.getCPPCActiveMode()
            isActive = state.active
            currentEPP = state.epp

            guard state.active else {
                currentCPULoad = 0
                currentGPULoad = 0
                currentTarget = ""
                return
            }

            // Read thresholds live from UserDefaults — they change via @AppStorage.
            let idleThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppIdleThreshold)
            let loadThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppLoadThreshold)

            let loads = await ProcessorModel.shared.getLoadIndex()
            let avg = loads.isEmpty ? 0 : loads.reduce(0, +) * 100 / Float(loads.count)
            currentCPULoad = avg

            // Read GPU load from SystemMonitor snapshot
            let gpuUtil = SystemMonitor.shared.snapshot.gpuUsage ?? 0
            let gpuLoad = Float(gpuUtil * 100)
            currentGPULoad = gpuLoad

            // GPU-aware EPP logic:
            // - If GPU is heavily loaded (>60%), force Performance mode for gaming/rendering
            // - If GPU is loaded (>30%) but CPU is idle, use Balanced (media playback)
            // - Otherwise, use standard CPU-based logic
            let gpuHeavyThreshold: Float = 60
            let gpuActiveThreshold: Float = 30

            if gpuLoad > gpuHeavyThreshold {
                // GPU gaming/rendering: maximum performance
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 0)
                currentTarget = "GPU Performance"
                currentEPP = 0
            } else if avg < Float(idleThreshold) && gpuLoad < gpuActiveThreshold {
                // CPU + GPU idle: Power Save
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 255)
                currentTarget = "Power Save"
                currentEPP = 255
            } else if avg > Float(loadThreshold) {
                // High CPU load: Performance
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 0)
                currentTarget = NSLocalizedString("Performance", comment: "EPP Performance mode label")
                currentEPP = 0
            } else if gpuLoad > gpuActiveThreshold {
                // GPU active (media/video): Balanced
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 128)
                currentTarget = "GPU Active"
                currentEPP = 128
            } else {
                // Moderate CPU load: Balanced
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 128)
                currentTarget = "Balanced"
                currentEPP = 128
            }
        }
    }
}
