// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import Combine

/// Single source of truth for AMD backend settings.
/// Replaces scattered UserDefaults accesses to prevent race conditions and "ghost states".
@MainActor
public final class AmdSettingsStore: ObservableObject {
    public static let shared = AmdSettingsStore()
    private let defaults = UserDefaults.standard

    // MARK: - Auto EPP Settings

    public var autoEppEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.autoEppEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.autoEppEnabled) }
    }

    public var autoEppIdleThreshold: Int {
        defaults.integer(forKey: DefaultsKey.autoEppIdleThreshold)
    }

    public var autoEppLoadThreshold: Int {
        defaults.integer(forKey: DefaultsKey.autoEppLoadThreshold)
    }

    // MARK: - Gaming Mode Settings

    public var gamingModeActive: Bool {
        get { defaults.bool(forKey: DefaultsKey.gamingModeActive) }
        set { defaults.set(newValue, forKey: DefaultsKey.gamingModeActive) }
    }

    public var gamingModeHideMenuBar: Bool {
        defaults.bool(forKey: DefaultsKey.gamingModeHideMenuBar)
    }

    /// The user's preset before Gaming Mode was activated, persisted so a
    /// relaunch with the mode still active can restore the real profile
    /// instead of a hardcoded fallback. nil when the mode has never been
    /// activated or has already been deactivated.
    public var gamingModeRestorePreset: String? {
        get { defaults.string(forKey: DefaultsKey.gamingModeRestorePreset) }
        set { defaults.set(newValue, forKey: DefaultsKey.gamingModeRestorePreset) }
    }

    // MARK: - CC6 idle
    /// CC6 idle wanted; the kext starts with it off, so it is put back when
    /// the kext loads.
    public var c6IdleEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.amdC6IdleEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.amdC6IdleEnabled) }
    }
    // MARK: - Custom power profiles

    var customProfiles: [AMDPowerProfile] {
        get {
            guard let data = defaults.data(forKey: DefaultsKey.amdCustomProfiles) else { return [] }
            return (try? JSONDecoder().decode([AMDPowerProfile].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: DefaultsKey.amdCustomProfiles) }
    }

    /// The custom profile last applied, nil when a preset (or nothing) is.
    public var customProfileName: String? {
        get { defaults.string(forKey: DefaultsKey.amdCustomProfileName) }
        set { defaults.set(newValue, forKey: DefaultsKey.amdCustomProfileName) }
    }

    // MARK: - Presets Settings

    public var amdPowerPreset: String? {
        get { defaults.string(forKey: DefaultsKey.amdPowerPreset) }
        set { defaults.set(newValue, forKey: DefaultsKey.amdPowerPreset) }
    }

    // MARK: - Manual EPP

    /// The EPP last chosen by hand, with the picker or a preset; nil until
    /// the user chooses one. Written back when a kext that applies EPP loads
    /// and when Auto EPP is switched off.
    public var manualEpp: UInt8? {
        get { (defaults.object(forKey: DefaultsKey.amdManualEpp) as? Int).map { UInt8(clamping: $0) } }
        set {
            if let newValue {
                defaults.set(Int(newValue), forKey: DefaultsKey.amdManualEpp)
            } else {
                defaults.removeObject(forKey: DefaultsKey.amdManualEpp)
            }
        }
    }
}
