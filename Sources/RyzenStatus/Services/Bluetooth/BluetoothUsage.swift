// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Whether the app talks to Bluetooth at all. Switched off in Settings, or on
/// a Mac without a Bluetooth controller, nothing loads IOBluetooth, asks the
/// Bluetooth daemon or runs `system_profiler` for Bluetooth batteries. A Mac
/// whose Bluetooth answers slowly (common on a Hackintosh) can turn it off.
enum BluetoothUsage {
    static func isAllowed(in defaults: UserDefaults = .standard,
                          hasController: Bool = BluetoothSleepService.isSupported) -> Bool {
        hasController && defaults.bool(forKey: DefaultsKey.bluetoothEnabled)
    }

    /// The features that use Bluetooth follow the switch at once. Each is
    /// touched only while installed, so the switch never brings one to life.
    static func preferenceChanged() {
        if AppFeature.notchAccessories.isAvailable { NotchAccessoryService.shared.syncWithPreferences() }
        if AppFeature.bluetoothSleep.isAvailable { BluetoothSleepService.shared.syncWithPreferences() }
    }
}
