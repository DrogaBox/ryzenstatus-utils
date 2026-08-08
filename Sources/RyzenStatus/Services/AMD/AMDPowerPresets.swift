// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import SwiftUI

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

    /// Processor Power Manager limit (selector 14).
    var ppmEnabled: Bool { false }

    /// Low Power Mode limit (selector 19).
    var lpmEnabled: Bool {
        switch self {
        case .eco: return true
        case .balance, .performance, .extreme: return false
        }
    }

    /// PPM and LPM are mutually exclusive in the kext.
    var keepsPowerLimitsExclusive: Bool { !(ppmEnabled && lpmEnabled) }

    var c6Desired: Bool {
        switch self {
        case .eco, .balance: return true
        case .performance, .extreme: return false
        }
    }

    var systemImage: String {
        switch self {
        case .eco: return "leaf.fill"
        case .balance: return "scalemass.fill"
        case .performance: return "bolt.fill"
        case .extreme: return "flame.fill"
        }
    }

    // MARK: — UI helpers (single source of truth — eliminates duplication in views)

    /// Accent color used by all preset buttons and cards.
    var color: Color {
        switch self {
        case .eco: return .green
        case .balance: return .blue
        case .performance: return .orange
        case .extreme: return .red
        }
    }

    /// Snaps a raw EPP byte to the nearest segmented-picker value (0/85/170/255).
    /// Used by both AmdPowerSettingsView and AmdControlSection — single definition.
    static func snapEPP(_ e: UInt8) -> UInt8 {
        if e < 42  { return 0 }
        if e < 127 { return 85 }
        if e < 212 { return 170 }
        return 255
    }

    /// The preset last applied by the user or by Gaming Mode, from UserDefaults.
    static func saved() -> AMDPowerPreset? {
        guard let raw = AmdSettingsStore.shared.amdPowerPreset,
              let preset = AMDPowerPreset(rawValue: raw) else { return nil }
        return preset
    }
}
