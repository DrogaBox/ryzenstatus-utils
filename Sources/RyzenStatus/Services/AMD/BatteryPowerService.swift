// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit.ps

/// What Auto EPP does while a laptop runs on its battery (Settings › AMD
/// Ryzen Power › On battery). Plugged in, every mode behaves like
/// `.sameAsPluggedIn`. A manual EPP is never touched.
enum AMDBatteryPowerMode: String, CaseIterable, Identifiable {
    /// The same Auto EPP as on AC power (the default).
    case sameAsPluggedIn = "same"
    /// Auto EPP never picks Performance; it stops at Balance.
    case saveMore = "saveMore"
    /// Auto EPP holds Eco.
    case maximumSaving = "maximum"

    var id: String { rawValue }

    /// The stored mode; an absent or unknown value is the default.
    init(stored: String?) {
        self = stored.flatMap(AMDBatteryPowerMode.init(rawValue:)) ?? .sameAsPluggedIn
    }
}

/// Where the Mac takes its power from, as far as this feature cares.
enum AMDPowerSource: Equatable {
    case external, battery

    /// Battery only when the Mac has an internal battery and IOPS says it is
    /// running on it; anything unknown counts as plugged in.
    init(hasBattery: Bool, onBattery: Bool?) {
        self = hasBattery && onBattery == true ? .battery : .external
    }
}

/// The On battery rules, kept apart from the services so they can be tested
/// without a battery: (source, mode, Auto EPP target) → the target applied.
///
/// Like Linux amd-pstate's dynamic EPP, which moves the EPP on a power
/// source change only while the platform profile is "balanced" and never
/// touches a profile the user picked, this acts on Auto EPP alone: a manual
/// EPP or preset is the user's explicit choice. Every rule only lowers the
/// target, and on external power every rule is the identity, so plugging in
/// gives Auto EPP's normal choice back at its next poll.
enum AMDBatteryPowerPolicy {
    /// Whether the mode changes anything for this source.
    static func adjusts(source: AMDPowerSource, mode: AMDBatteryPowerMode) -> Bool {
        source == .battery && mode != .sameAsPluggedIn
    }

    /// The Auto EPP target to apply in place of the load-driven `target`.
    /// "Save more" turns Performance into Balance (GPU · Performance into
    /// GPU · Balance), as Linux uses balance_performance instead of
    /// performance on battery; "Maximum saving" holds Eco.
    static func autoTarget(_ target: AutoEppTarget, source: AMDPowerSource,
                           mode: AMDBatteryPowerMode) -> AutoEppTarget {
        guard adjusts(source: source, mode: mode) else { return target }
        switch mode {
        case .sameAsPluggedIn:
            return target
        case .saveMore:
            switch target {
            case .performance: return .balanced
            case .gpuPerformance: return .gpuActive
            case .gpuActive, .balanced, .powerSave: return target
            }
        case .maximumSaving:
            return .powerSave
        }
    }

    /// The preset the idle clock limit is decided on. The limit means "the
    /// CPU is idle", so it follows the load-driven target, never an Eco this
    /// policy forced under load; and only while Eco is what was applied.
    static func idleLimitPreset(loadTarget: AutoEppTarget, appliedTarget: AutoEppTarget) -> AMDPowerPreset {
        appliedTarget.preset == .eco ? loadTarget.preset : appliedTarget.preset
    }
}

/// Watches the power source through the IOPS notification run-loop source
/// (no poll of its own) and publishes it with the On battery mode. It
/// writes nothing: Auto EPP's poll, the one writer while Auto EPP is on,
/// asks `autoTarget(_:)` every 1.5 s and applies the result the way it
/// applies any target, so a refused write is retried at the next poll.
/// Macs without an internal battery never install the source and always
/// read as plugged in.
@MainActor
final class BatteryPowerService: ObservableObject {
    static let shared = BatteryPowerService()

    /// The Mac has an internal battery: the On battery row is shown.
    let hasBattery = PowerSampler.hasInternalBattery
    @Published private(set) var source: AMDPowerSource = .external
    @Published private(set) var mode: AMDBatteryPowerMode = AmdSettingsStore.shared.batteryPowerMode

    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// Installs the IOPS notification on the main run loop. Called at launch;
    /// idempotent; does nothing without a battery.
    func start() {
        guard hasBattery, runLoopSource == nil else { return }
        let callback: IOPowerSourceCallbackType = { _ in
            // The source is on the main run loop, so this runs on main.
            MainActor.assumeIsolated { BatteryPowerService.shared.refresh() }
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() else { return }
        runLoopSource = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        refresh()
    }

    /// Removes the notification. Called on termination.
    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.runLoopSource = nil
    }

    func setMode(_ newMode: AMDBatteryPowerMode) {
        AmdSettingsStore.shared.batteryPowerMode = newMode
        if mode != newMode { mode = newMode }
    }

    /// Reads the power source again (IOPS told us something changed).
    private func refresh() {
        let now = AMDPowerSource(hasBattery: hasBattery, onBattery: SystemInfo.batterySnapshot()?.isOnBattery)
        if source != now { source = now }
    }

    /// Auto EPP's target for this source and mode.
    func autoTarget(_ target: AutoEppTarget) -> AutoEppTarget {
        AMDBatteryPowerPolicy.autoTarget(target, source: source, mode: mode)
    }
}
