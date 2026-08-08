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

    // MARK: - Presets Settings

    public var amdPowerPreset: String? {
        get { defaults.string(forKey: DefaultsKey.amdPowerPreset) }
        set { defaults.set(newValue, forKey: DefaultsKey.amdPowerPreset) }
    }
}
