// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
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

    /// True when `RegisterEventHotKey` refused the combination: the system
    /// does not accept it, or this app already registered it for another
    /// key. Another app holding the same combination is not a refusal:
    /// Carbon lets several processes register one hotkey (the
    /// `eventHotKeyExistsErr` note in CarbonEventsCore.h).
    @Published private(set) var registrationFailed = false

    private let role = GlobalShortcutRole.monitorWindow
    private let hotkey = QuickToolHotkey(id: 95)
    private var activationObserver: NSObjectProtocol?

    private init() {
        // The shared Carbon handler delivers presses on the main queue.
        hotkey.onPress = {
            MainActor.assumeIsolated { MonitorWindowController.shared.show(toActiveSpace: true) }
        }
        // After a refusal, coming to the front (where its settings are read)
        // tries again. That clears the warning only when this app's own other
        // registration of the combination has gone since; a combination the
        // system does not accept stays refused, and the retry costs one call.
        // A key that is registered is left alone.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let shortcut = MonitorWindowShortcut.shared
                if shortcut.registrationFailed { shortcut.syncWithPreferences() }
            }
        }
    }

    /// Registers or releases the key to match the preferences. Called at
    /// launch, when either preference changes, when a shortcut field stops
    /// listening (`ShortcutCapture` releases every quick tool key while one
    /// listens) and, after a refusal, when the app comes to the front.
    func syncWithPreferences(defaults: UserDefaults = .standard) {
        let enabled = !ShortcutCapture.isCapturing
            && role.requiredEnableKeys.allSatisfy { defaults.bool(forKey: $0) }
        let shortcut = role.assignedShortcut(storedValue: { defaults.string(forKey: $0) }) ?? role.defaultShortcut
        registrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut, storageKey: role.storageKey)
    }
}

extension GlobalShortcutRole {
    /// Who registers a role's key again after its preferences changed.
    enum Registrar: Equatable {
        /// The Monitor window's own shortcut, which belongs to the app.
        case monitorWindow
        /// The runtime bindings of these features.
        case features([AppFeature])
    }

    var registrar: Registrar {
        self == .monitorWindow ? .monitorWindow : .features(availabilityFeatures)
    }

    /// Re-registers this role's key after its preferences changed: through
    /// the feature's runtime binding, or directly for a role that belongs to
    /// the app itself.
    @MainActor
    func syncRegistration() {
        switch registrar {
        case .monitorWindow:
            MonitorWindowShortcut.shared.syncWithPreferences()
        case .features(let features):
            FeatureRuntime.shared.sync(features)
        }
    }
}
