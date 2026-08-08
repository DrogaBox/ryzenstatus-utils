// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// One-tap power profiles applied through the kext's existing selectors:
/// EPP (25), CPB (12), PPM (14) and LPM (19).
///
/// Pure data (no IOKit / no UI) so `./build.sh --test` can exercise it on any
/// machine. The actual kext writes live in `ProcessorModel.applyPowerPreset(_:)`.
enum AMDPowerPreset: String, CaseIterable, Identifiable {
    case eco = "Eco"
    case balance = "Balance"
    case performance = "Performance"
    case extreme = "Extreme"

    var id: String { rawValue }

    /// EPP target (0–255, selector 25). Lower = more performance.
    var eppValue: UInt8 {
        switch self {
        case .eco: return 255
        case .balance: return 128
        case .performance: return 32
        case .extreme: return 0
        }
    }

    /// Core Performance Boost (selector 12).
    var cpbEnabled: Bool {
        switch self {
        case .eco: return false
        case .balance, .performance, .extreme: return true
        }
    }

    /// Processor Power Manager limit (selector 14) — locks to P1 when on.
    /// No preset enables PPM today; kept explicit so the exclusivity logic
    /// below stays self-documenting and future presets can opt in.
    var ppmEnabled: Bool {
        switch self {
        case .eco: return false
        case .balance: return false
        case .performance: return false
        case .extreme: return false
        }
    }

    /// Low Power Mode limit (selector 19) — locks to P2 when on.
    var lpmEnabled: Bool {
        switch self {
        case .eco: return true
        case .balance: return false
        case .performance: return false
        case .extreme: return false
        }
    }

    /// PPM and LPM are mutually exclusive in the kext (`setPMPStateLimit`).
    /// Invariant enforced by the model and by `applyPowerPreset(_:)`.
    var keepsPowerLimitsExclusive: Bool { !(ppmEnabled && lpmEnabled) }

    /// Whether the preset wants deep C-States (C6) enabled. C6 is a boot-arg
    /// (`amdcstate=0`, NVRAM) — it is informational here and requires a reboot;
    /// presets never touch it live.
    var c6Desired: Bool {
        switch self {
        case .eco, .balance: return true
        case .performance, .extreme: return false
        }
    }

    /// SF Symbol shown on the preset card.
    var systemImage: String {
        switch self {
        case .eco: return "leaf.fill"
        case .balance: return "scalemass.fill"
        case .performance: return "bolt.fill"
        case .extreme: return "flame.fill"
        }
    }

    /// The preset last applied by the user or by Gaming Mode, from
    /// `DefaultsKey.amdPowerPreset`, or nil when none has been applied yet.
    /// Views that highlight the selected card re-read this whenever Gaming
    /// Mode toggles, so the highlight tracks what is actually applied.
    static func saved() -> AMDPowerPreset? {
        guard let raw = UserDefaults.standard.object(forKey: DefaultsKey.amdPowerPreset) as? String,
              let preset = AMDPowerPreset(rawValue: raw) else { return nil }
        return preset
    }
}
