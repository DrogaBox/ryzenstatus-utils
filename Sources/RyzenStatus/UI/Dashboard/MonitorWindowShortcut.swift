// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The global shortcut that opens the Monitor window from any app, or brings
/// it to the front when it is already open: Control-Shift-Escape by default,
/// the combination Task Manager answers to on Windows. A Carbon hotkey like
/// the quick tools', so it needs no Accessibility and fires while another
/// app is in front.
///
/// The window belongs to the app rather than to a hub feature, so nothing in
/// the hub switches this off; its own toggle and recorder live on the
/// Dashboard settings page and on the shortcuts page.
@MainActor
final class MonitorWindowShortcut: ObservableObject {
    static let shared = MonitorWindowShortcut()
    /// The Monitor's symbol, shared by its settings page and shortcut row.
    nonisolated static let symbolName = "gauge.with.dots.needle.33percent"

    /// True when macOS refused the combination because another app holds it.
    @Published private(set) var registrationFailed = false

    private let role = GlobalShortcutRole.monitorWindow
    private let hotkey = QuickToolHotkey(id: 95)

    private init() {
        // The shared Carbon handler delivers presses on the main queue.
        hotkey.onPress = {
            MainActor.assumeIsolated { MonitorWindowController.shared.show() }
        }
    }

    /// Registers or releases the key to match the preferences. Called at
    /// launch, when either preference changes and when a shortcut field stops
    /// listening (`ShortcutCapture` releases every quick tool key while one
    /// listens).
    func syncWithPreferences(defaults: UserDefaults = .standard) {
        let enabled = !ShortcutCapture.isCapturing
            && role.requiredEnableKeys.allSatisfy { defaults.bool(forKey: $0) }
        let shortcut = role.assignedShortcut(storedValue: { defaults.string(forKey: $0) }) ?? role.defaultShortcut
        registrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut, storageKey: role.storageKey)
    }
}

extension GlobalShortcutRole {
    /// Re-registers this role's key after its preferences changed: through
    /// the feature's runtime binding, or directly for a role that belongs to
    /// the app itself.
    @MainActor
    func syncRegistration() {
        if self == .monitorWindow {
            MonitorWindowShortcut.shared.syncWithPreferences()
        } else {
            FeatureRuntime.shared.sync(availabilityFeatures)
        }
    }
}
