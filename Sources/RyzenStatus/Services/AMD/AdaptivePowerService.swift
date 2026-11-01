// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// Adaptive power limit: while it is on, the package power limit follows the
/// temperature. Above the target it drops 5 W every 5 s; once the CPU is 10 °C
/// below the target and loaded, it climbs back 5 W at a time, never past the
/// PPT of the profile in force (Auto EPP's preset, the custom profile or the
/// saved preset). Desktop parts with PPT/TDC/EDC only (selector 62 bit 0).
@MainActor
final class AdaptivePowerService: ObservableObject {
    static let shared = AdaptivePowerService()

    /// The limit this service last wrote, in W; nil while it is idle.
    @Published private(set) var currentLimitW: Int?

    private var loopTask: Task<Void, Never>?
    private static let interval: UInt64 = 5_000_000_000
    /// The profile PPT the limit was last measured against: a new one (a
    /// preset switch) was written in full by the profile, so the limit
    /// restarts there.
    private var lastCeilingW: Int?

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.amdAdaptivePowerEnabled) }

    var targetCelsius: Int {
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.amdAdaptiveTargetCelsius)
        return stored == 0 ? AdaptivePowerPolicy.defaultTargetCelsius : stored
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: DefaultsKey.amdAdaptivePowerEnabled)
        on ? start() : stop()
    }

    func setTarget(celsius: Int) {
        UserDefaults.standard.set(celsius, forKey: DefaultsKey.amdAdaptiveTargetCelsius)
    }

    /// Starts the loop when enabled. Idempotent; called when the kext loads
    /// and when the user switches it on.
    func start() {
        guard loopTask == nil, isEnabled else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: Self.interval)
            }
        }
    }

    /// Stops the loop and puts the profile's own limit back.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        currentLimitW = nil
        lastCeilingW = nil
        Task { await AmdPresetController.shared.reapplyLimitsInForce() }
    }

    private func tick() async {
        guard isEnabled, !GamingModeService.shared.isActive,
              AmdPowerControlsModel.shared.powerCapabilities.contains(.pptTdcEdcLimits),
              let profile = AmdPresetController.shared.profileInForce(),
              let ceiling = profile.pptW, let tdc = profile.tdcA, let edc = profile.edcA,
              let packet = await Task.detached(operation: { ProcessorModel.shared.getTelemetry() }).value else {
            currentLimitW = nil
            lastCeilingW = nil
            return
        }
        if lastCeilingW != ceiling {
            lastCeilingW = ceiling
            currentLimitW = ceiling
        }
        let current = currentLimitW ?? ceiling
        let next = AdaptivePowerPolicy.next(currentW: current, ceilingW: ceiling,
                                            tempC: packet.packageTempC, targetC: targetCelsius,
                                            cpuLoad: AutoEppService.shared.currentCPULoad,
                                            loadThreshold: Float(AmdSettingsStore.shared.autoEppLoadThreshold))
        guard next != current else { return }
        let res = await Task.detached {
            ProcessorModel.shared.setPBOLimits(pptMilliwatts: next * 1000,
                                               tdcMilliamps: tdc * 1000, edcMilliamps: edc * 1000)
        }.value
        if res == KERN_SUCCESS { currentLimitW = next }
    }
}

/// The adaptive limit's decision, apart from the service so it can be tested.
enum AdaptivePowerPolicy {
    static let stepW = 5
    static let floorW = 45
    static let defaultTargetCelsius = 80
    static let targetRange: ClosedRange<Int> = 60...95
    /// How far below the target the CPU must be before the limit climbs.
    static let recoveryMarginC: Float = 10

    static func next(currentW: Int, ceilingW: Int, tempC: Float, targetC: Int,
                     cpuLoad: Float, loadThreshold: Float) -> Int {
        let floor = min(floorW, ceilingW)
        if tempC > Float(targetC) { return max(floor, currentW - stepW) }
        if tempC < Float(targetC) - recoveryMarginC && cpuLoad > loadThreshold {
            return min(ceilingW, currentW + stepW)
        }
        return min(max(currentW, floor), ceilingW)
    }
}
