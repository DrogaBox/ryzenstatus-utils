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
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
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
                currentTarget = ""
                return
            }

            let state = ProcessorModel.shared.getCPPCActiveMode()
            isActive = state.active
            currentEPP = state.epp

            guard state.active else {
                currentCPULoad = 0
                currentTarget = ""
                return
            }

            // Read thresholds live from UserDefaults — they change via @AppStorage.
            let idleThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppIdleThreshold)
            let loadThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.autoEppLoadThreshold)

            let loads = await ProcessorModel.shared.getLoadIndex()
            let avg = loads.isEmpty ? 0 : loads.reduce(0, +) * 100 / Float(loads.count)
            currentCPULoad = avg

            if avg < Float(idleThreshold) {
                // Idle: set to Power Save (max efficiency)
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 255)
                currentTarget = "Power Save"
                currentEPP = 255
            } else if avg > Float(loadThreshold) {
                // High load: set to Performance (max speed)
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 0)
                currentTarget = "Rendimiento"
                currentEPP = 0
            } else {
                // Moderate load: balanced EPP
                _ = ProcessorModel.shared.setCPPCEPPValue(epp: 128)
                currentTarget = "Balanced"
                currentEPP = 128
            }
        }
    }
}
