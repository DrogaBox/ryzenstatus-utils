// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Carbon.HIToolbox
import Foundation

/// The combinations the person tied to single rows of the bar.
///
/// Expectations lifted from upstream's `CommandBarFeatureTests` (the row
/// shortcut, pending-launch and app-cleanup sections). Upstream's take-over
/// cases are left out on purpose: this fork has no system-shortcut take-over
/// engine, so `conflictsWithMacOS` is the only macOS question a row asks and it
/// needs the live system shortcut list, which this harness does not touch.
enum CommandBarRowShortcutCases {
    static func run(_ expect: CommandBarExpect) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option, .command])
        let commandPeriod = GlobalShortcut(keyCode: 47, modifiers: [.command])

        // MARK: - Binding one row

        var bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.a", in: [:])
        expect(bound["app.bundle.a"] == optionB, "a row answers to the keys it was given")
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.a", in: bound) == nil,
               "recording an app's existing shortcut is allowed")
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: "app.bundle.b", in: bound)
                == .occupied("app.bundle.a"),
               "the app editor names an occupied shortcut before replacing another app's binding")
        expect(CommandBarRowShortcuts.assignmentIssue(
                    GlobalShortcut(keyCode: 11, modifiers: []), for: "app.bundle.a", in: bound) == .invalid,
               "an app shortcut cannot take an ordinary typing key even when editing an existing binding")
        bound = CommandBarRowShortcuts.setting(optionB, for: "app.bundle.b", in: bound)
        expect(bound["app.bundle.b"] == optionB && bound["app.bundle.a"] == nil,
               "the same keys move to the last row that asked; two rows never share one")
        expect(CommandBarRowShortcuts.setting(nil, for: "app.bundle.b", in: bound).isEmpty,
               "taking the keys off leaves nothing behind")
        expect(CommandBarRowShortcuts.key(for: optionB, in: bound) == "app.bundle.b"
                && CommandBarRowShortcuts.key(for: optionN, in: bound) == nil,
               "a press is routed to the row that owns it")
        expect(CommandBarRowShortcuts.isUsable(optionB)
                && !CommandBarRowShortcuts.isUsable(GlobalShortcut(keyCode: 11, modifiers: [])),
               "a bare letter is never taken from every app on the Mac")
        expect(CommandBarRowShortcuts.decode(CommandBarRowShortcuts.encode(bound)) == bound,
               "the bindings survive a round trip through storage")
        expect(CommandBarRowShortcuts.shortcutStorageKey(for: "app.bundle.a")
                == "\(DefaultsKey.commandBarRowShortcuts).app.bundle.a",
               "an app row's hotkey is claimed under the name its row has")
        expect(CommandBarRowShortcuts.appKey(bundleID: "com.x.Y", path: "/Applications/Y.app")
                == "app.bundle.com.x.Y"
                && CommandBarRowShortcuts.appKey(bundleID: nil, path: "/Applications/Y.app")
                    == "app./Applications/Y.app",
               "an app is listed under its bundle id when it has one, and under its path otherwise")

        // MARK: - Hiding an app that is already in front

        expect(CommandBarRowShortcuts.hidesAppInFront(isFrontmost: true, isHidden: false,
                                                      ownsFrontWindow: true),
               "an app in front with its window in front hides on its own shortcut")
        expect(!CommandBarRowShortcuts.hidesAppInFront(isFrontmost: true, isHidden: false,
                                                       ownsFrontWindow: false),
               "an app in front without the front window comes forward instead of hiding")
        expect(!CommandBarRowShortcuts.hidesAppInFront(isFrontmost: false, isHidden: false,
                                                       ownsFrontWindow: true),
               "an app behind another one comes forward")
        expect(!CommandBarRowShortcuts.hidesAppInFront(isFrontmost: true, isHidden: true,
                                                       ownsFrontWindow: true),
               "a hidden app comes back")
        var windowListRead = false
        expect(!CommandBarRowShortcuts.hidesAppInFront(isFrontmost: false, isHidden: false,
                                                       ownsFrontWindow: {
                                                           windowListRead = true
                                                           return true
                                                       }()) && !windowListRead,
               "bringing an app forward never waits on the window server")

        // MARK: - Room for more than the alphabet

        let emojiBinding = CommandBarRowShortcuts.setting(
            commandPeriod, for: CommandBarPreferences.emojiBrowserRowID, in: [:])
        expect(CommandBarRowShortcuts.key(for: commandPeriod, in: emojiBinding)
                == CommandBarPreferences.emojiBrowserRowID,
               "the Emoji browser row can own a global shortcut like any other row")
        var alphabetBindings: [String: GlobalShortcut] = [:]
        for index in 0..<26 {
            alphabetBindings = CommandBarRowShortcuts.setting(
                GlobalShortcut(keyCode: Int64(index), modifiers: [.control]),
                for: "app.bundle.\(index)", in: alphabetBindings)
        }
        expect(alphabetBindings.count == 26
                && CommandBarRowShortcuts.hasRoom(for: "row.extra", in: alphabetBindings)
                && CommandBarRowShortcuts.decode(CommandBarRowShortcuts.encode(alphabetBindings))
                    == alphabetBindings,
               "26 app shortcuts fit with room left for other commands")
        var full: [String: GlobalShortcut] = [:]
        for index in 0..<CommandBarRowShortcuts.limit {
            full["row.\(index)"] = GlobalShortcut(keyCode: Int64(index), modifiers: [.control])
        }
        expect(!CommandBarRowShortcuts.hasRoom(for: "row.new", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.0", in: full)
                && CommandBarRowShortcuts.hasRoom(for: "row.new", in: [:]),
               "a full list says so before the keys are taken, and rebinding is always allowed")
        expect(CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.new", in: full) == .full
                && CommandBarRowShortcuts.assignmentIssue(optionN, for: "row.0", in: full) == nil,
               "the app editor reports a full list while still allowing existing shortcuts to change")
        expect(CommandBarRowShortcuts.isUsable(
                    GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [.command])),
               "Command Q is a real combination; the card has to be able to store it")

        // MARK: - An app shortcut waiting for its first catalog

        let appBindings = ["app.bundle.a": optionB, "app.bundle.b": optionN]
        var pendingApp = CommandBarRowShortcuts.PendingAppLaunch()
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.a"
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "an app shortcut waiting for its first catalog runs exactly once")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.schedule("app.bundle.b", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: true) == "app.bundle.b",
               "the latest app shortcut replaces an earlier request while the catalog loads")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: [:], isAvailable: true) == nil,
               "removing a shortcut while apps load cancels its pending launch")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: ["app.bundle.a": optionN], isAvailable: true) == nil,
               "changing a shortcut while apps load cannot run its previous binding")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        expect(pendingApp.take(in: appBindings, isAvailable: false) == nil
                && pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "disabling the feature discards the deferred launch rather than postponing it")
        pendingApp.schedule("app.bundle.a", in: appBindings)
        pendingApp.cancel()
        expect(pendingApp.take(in: appBindings, isAvailable: true) == nil,
               "suspending shortcuts or running another command cancels a queued app launch")

        // MARK: - An uninstalled app loses its shortcut

        let rowsKey = "app.bundle.com.rows.Rows"
        let ghosttyKey = "app.bundle.com.ghostty.Ghostty"
        var multiAppBindings = CommandBarRowShortcuts.setting(optionB, for: rowsKey, in: [:])
        multiAppBindings = CommandBarRowShortcuts.setting(optionN, for: "app.bundle.other",
                                                          in: multiAppBindings)
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: ghosttyKey, in: multiAppBindings)
                == .occupied(rowsKey),
               "before cleanup, a new app assigning an occupied shortcut encounters a conflict")
        let uninstalledKeys = CommandBarRowShortcuts.applicationStableKeys(
            bundleIDs: ["com.rows.Rows"], paths: ["/Applications/Rows.app"])
        expect(uninstalledKeys.contains(rowsKey) && uninstalledKeys.contains("app./Applications/Rows.app"),
               "applicationStableKeys identifies both bundle ID and file path keys")
        let cleanedBindings = CommandBarRowShortcuts.removing(keys: uninstalledKeys, in: multiAppBindings)
        expect(cleanedBindings[rowsKey] == nil && cleanedBindings["app.bundle.other"] == optionN,
               "removing uninstalled app keys clears its shortcut while preserving other apps")
        expect(CommandBarRowShortcuts.assignmentIssue(optionB, for: ghosttyKey, in: cleanedBindings) == nil,
               "after cleanup, the freed shortcut is immediately available for other applications")
        expect(CommandBarRowShortcuts.removing(keys: [], in: multiAppBindings) == multiAppBindings,
               "nothing to remove leaves the bindings untouched")
    }
}
