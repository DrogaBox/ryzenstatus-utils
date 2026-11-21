// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The global shortcut that opens the Monitor window, like Task Manager's
/// Control-Shift-Escape on Windows.
enum MonitorShortcutTests {
    static func run(_ suite: TestSuite) {
        defaults(suite)
        systemShortcuts(suite)
        availability(suite)
        registration(suite)
    }

    private static func defaults(_ suite: TestSuite) {
        let role = GlobalShortcutRole.monitorWindow
        let shortcut = GlobalShortcut.monitorWindowDefault
        suite.expect(shortcut.keyCode == Int64(kVK_Escape) && shortcut.modifiers == [.control, .shift],
                     "the Monitor opens with Control-Shift-Escape by default")
        suite.expect(shortcut.isValid, "Control-Shift-Escape is a valid global shortcut")
        suite.expect(shortcut.displayString == "⌃⇧Esc", "the default reads ⌃⇧Esc, got \(shortcut.displayString)")
        suite.expect(GlobalShortcut(storageValue: shortcut.storageValue) == shortcut,
                     "the default survives a round trip through its stored value")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.monitorWindowShortcutEnabled] as? Bool == true,
                     "the Monitor shortcut is on out of the box")
        suite.expect(registered[role.storageKey] as? String == shortcut.storageValue,
                     "the registered default is Control-Shift-Escape")
        suite.expect(role.defaultShortcut == shortcut && role.requiredEnableKeys == [DefaultsKey.monitorWindowShortcutEnabled],
                     "the role reads its own default and switch")
        let others = GlobalShortcutRole.allCases.filter { $0 != role }
        suite.expect(!others.contains { $0.defaultShortcut == shortcut },
                     "no other shortcut of the app defaults to Control-Shift-Escape")
        suite.expect(GlobalShortcutRole.conflict(for: shortcut, excluding: role, isAvailable: { _ in true },
                                                 radialMenuShortcuts: { [] },
                                                 storedValue: { _ in nil }) == nil,
                     "the default collides with no other role's default")
        suite.expect(GlobalShortcutRole.conflict(for: shortcut, isAvailable: { _ in true },
                                                 radialMenuShortcuts: { [] },
                                                 storedValue: { _ in nil }) == role,
                     "another field recording Control-Shift-Escape is told the Monitor holds it")
        suite.expect(!role.supportsClearing && role.supportsTakeOver,
                     "the row turns off with its switch, and may take a macOS shortcut over")
    }

    /// The Escape rows of the WindowServer's live table on macOS 26.7 (read
    /// with CGSGetSymbolicHotKeyValue on 2026-11-19): ids 0 and 6 are Force
    /// Quit (⌘⌥⎋ and ⌘⌥⇧⎋), 58 and 177 use ⌥⎋, 260 uses ⌘⎋. None is ⌃⇧⎋.
    private static func systemShortcuts(_ suite: TestSuite) {
        let escape = Int64(kVK_Escape)
        let live: [LiveSystemShortcut] = [
            LiveSystemShortcut(id: 0, keyCode: escape, flags: [.maskCommand, .maskAlternate], enabled: true),
            LiveSystemShortcut(id: 6, keyCode: escape, flags: [.maskCommand, .maskAlternate, .maskShift],
                               enabled: true),
            LiveSystemShortcut(id: 58, keyCode: escape, flags: [.maskAlternate], enabled: true),
            LiveSystemShortcut(id: 177, keyCode: escape, flags: [.maskAlternate], enabled: true),
            LiveSystemShortcut(id: 260, keyCode: escape, flags: [.maskCommand], enabled: true),
        ]
        suite.expect(!GlobalShortcut.conflictsWithSystemShortcut(.monitorWindowDefault, liveEntries: live,
                                                                 symbolicHotKeys: nil, role: .monitorWindow),
                     "Control-Shift-Escape is free next to the macOS 26 Escape shortcuts")
        suite.expect(GlobalShortcut.conflictsWithSystemShortcut(
                        GlobalShortcut(keyCode: escape, modifiers: [.command, .option]),
                        liveEntries: live, symbolicHotKeys: nil, role: .monitorWindow),
                     "Force Quit's ⌘⌥⎋ still counts as taken, so the check itself is live")
    }

    private static func availability(_ suite: TestSuite) {
        let role = GlobalShortcutRole.monitorWindow
        suite.expect(role.isAlwaysAvailable && role.isAvailable(using: { _ in false }),
                     "no hub switch takes the Monitor shortcut away")
        suite.expect(GlobalShortcutRole.availableRoles(isAvailable: { _ in false }) == [role],
                     "with every feature off, the Monitor shortcut is still listed")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.monitorWindowShortcutEnabled },
                                                    isAvailable: { _ in false },
                                                    storedValue: { _ in nil }) == [role],
                     "its own switch alone makes it live")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: { $0 != DefaultsKey.monitorWindowShortcutEnabled },
                                                    storedValue: { _ in nil }).allSatisfy { $0 != role },
                     "turning its switch off takes it off the live list")
        suite.expect(role.feature.group == .monitor, "the row is listed with the monitor's shortcuts")
        suite.expect(!GlobalShortcutRole.featuresToSilenceWhileRecording.contains(.monitorCPU),
                     "recording a shortcut does not re-plan the monitor; ShortcutCapture gives the key back itself")
    }

    /// The shortcuts page hands this role to the Monitor's own shortcut, not
    /// to the feature runtime, and switching it off releases the key.
    private static func registration(_ suite: TestSuite) {
        suite.expect(GlobalShortcutRole.monitorWindow.registrar == .monitorWindow,
                     "the shortcuts page re-registers the Monitor key through MonitorWindowShortcut")
        let others = GlobalShortcutRole.allCases.filter { $0 != .monitorWindow }
        suite.expect(others.allSatisfy { $0.registrar == .features($0.availabilityFeatures) },
                     "every other role still goes through its features' runtime bindings")
        // Switched off: nothing is registered, so nothing can be refused.
        // (Switched on would register a real global key from the tests.)
        let name = "ryzenstatus.tests.monitor-shortcut"
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "a scratch defaults domain opens")
            return
        }
        defaults.removePersistentDomain(forName: name)
        defaults.set(false, forKey: DefaultsKey.monitorWindowShortcutEnabled)
        MainActor.assumeIsolated {
            MonitorWindowShortcut.shared.syncWithPreferences(defaults: defaults)
            suite.expect(!MonitorWindowShortcut.shared.registrationFailed,
                         "with its switch off the Monitor key is released and shows no refusal")
        }
        defaults.removePersistentDomain(forName: name)
    }
}
