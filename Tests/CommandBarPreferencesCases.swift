// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// Everything the person decides about the bar: which kinds of result it may
/// offer, the names they gave things, what they pinned and what they hid.
///
/// Expectations lifted from upstream's `CommandBarFeatureTests` (the sources,
/// aliases, pins, hidden rows and position sections).
enum CommandBarPreferencesCases {
    static func run(_ expect: CommandBarExpect) {
        // MARK: - Which source a row came from

        expect(CommandBarPreferences.source(ofRowID: "app.x") == .apps
                && CommandBarPreferences.source(ofRowID: "menu.1.Bold") == .menus
                && CommandBarPreferences.source(ofRowID: "folder./tmp") == .folders
                && CommandBarPreferences.source(ofRowID: "macsettings.com.apple.Sound-Settings.extension")
                    == .macSettings
                && CommandBarPreferences.source(ofRowID: "settings.general") == .settingsPages
                && CommandBarPreferences.source(ofRowID: "action.screenshot") == .actions
                && CommandBarPreferences.source(ofRowID: "action.recentCaptures") == .actions
                && CommandBarPreferences.emojiBrowserRowID == "emoji.browse"
                && CommandBarPreferences.source(ofRowID: CommandBarPreferences.emojiBrowserRowID)
                    == .emoji,
               "every row knows which source it came from")
        expect(Set(CommandBarSource.allCases.map(\.rawValue)).count == CommandBarSource.allCases.count,
               "no two sources share the id the preference stores")
        expect(CommandBarSource.actions.isAlwaysOn
                && CommandBarSource.allCases.filter(\.isAlwaysOn).count == 1,
               "only the app's own actions cannot be switched off")

        // MARK: - Which sources are switched off

        expect(CommandBarPreferences.isEnabled(.folders, disabledRaw: "folders,emoji") == false
                && CommandBarPreferences.isEnabled(.apps, disabledRaw: "folders,emoji") == true
                && CommandBarPreferences.isEnabled(.actions, disabledRaw: "actions") == true,
               "a switched off source stays off, and actions never can be")
        expect(CommandBarPreferences.isEnabled(.folders,
                                               disabled: CommandBarPreferences.disabledSources(from: "folders"))
                == false,
               "the same rule answers for a set the caller already holds")
        expect(CommandBarPreferences.storageValue(for: [.emoji, .folders, .actions]) == "emoji,folders",
               "the disabled list writes the same way every time")
        expect(CommandBarPreferences.disabledSources(from: "folders, nonsense ,emoji")
                == Set([.folders, .emoji]),
               "an unknown source id is dropped instead of corrupting the set")
        expect(CommandBarPreferences.disabledSources(from: "").isEmpty,
               "an empty list switches nothing off")

        // MARK: - The rows that open another category

        let actionBrowseIDs: Set<String> = [
            CommandBarPreferences.emojiBrowserRowID,
            CommandBarPreferences.killProcessBrowserRowID,
            "uninstall.browse", "uninstall.finder",
        ]
        expect(CommandBarPreferences.actionBrowseRowIDs == actionBrowseIDs,
               "the app's own actions build all four rows that open another category")
        expect(Set(actionBrowseIDs.map(CommandBarPreferences.source(ofRowID:)))
                    == [.uninstallApps, .emoji, .killProcess]
                && actionBrowseIDs.allSatisfy(CommandBarPreferences.isActionRow),
               "a navigation row is filed under the category it opens, so the actions list admits it by name")
        expect(CommandBarPreferences.isActionRow("action.cleaner")
                && !CommandBarPreferences.isActionRow("app.Safari")
                && !CommandBarPreferences.isActionRow("settings.appearance")
                && !CommandBarPreferences.isActionRow("emoji.grin"),
               "naming the navigation rows widens the actions list to them alone")
        let emojiSwitchedOff = CommandBarPreferences.disabledSources(from: "emoji")
        expect(!CommandBarPreferences.isActionRow(
                    CommandBarPreferences.emojiBrowserRowID, disabled: emojiSwitchedOff)
                && CommandBarPreferences.isActionRow(
                    CommandBarPreferences.emojiBrowserRowID, disabled: []),
               "the row that opens the emoji browser leaves the actions list while emoji is switched off")
        let killSwitchedOff = CommandBarPreferences.disabledSources(from: "killProcess")
        expect(!CommandBarPreferences.isActionRow(
                    CommandBarPreferences.killProcessBrowserRowID, disabled: killSwitchedOff)
                && CommandBarPreferences.isActionRow("action.cleaner", disabled: killSwitchedOff),
               "an action of the app's own cannot be switched off, only a navigation row can")

        // MARK: - What a row is worth before a letter is read

        expect(CommandBarPreferences.rankBias(for: .files)
                    < CommandBarPreferences.rankBias(for: .actions)
                && CommandBarPreferences.rankBias(for: .apps)
                    > CommandBarPreferences.rankBias(for: .actions),
               "a borrowed menu command sits under an owned row, and files under both")
        expect(CommandBarPreferences.rankBias(for: .uninstallApps) == 0
                && CommandBarPreferences.rankBias(for: .menus) < 0
                && CommandBarPreferences.rankBias(for: .settingsPages) < 0,
               "a file or a settings page has to be a plainly better match to lead the list")

        // MARK: - Names the person gave

        var aliases = CommandBarPreferences.settingAlias("codex", for: "app./Applications/Chat.app", in: [:])
        expect(aliases["app./Applications/Chat.app"] == "codex", "a row takes the name it was given")
        expect(CommandBarPreferences.aliasMatches("codex", query: "codex")
                && CommandBarPreferences.aliasMatches("codex", query: "cod")
                && !CommandBarPreferences.aliasMatches("codex", query: "codexx"),
               "the name matches whole or as it is being typed, never beyond it")
        expect(CommandBarPreferences.aliasMatches("meu chat codex", query: "codex"),
               "several words all find the same row")
        expect(CommandBarPreferences.aliasMatches("Códex", query: "codex"),
               "accents in a name never break it")
        aliases = CommandBarPreferences.settingAlias("  ", for: "app./Applications/Chat.app", in: aliases)
        expect(aliases.isEmpty, "clearing the field removes the name")
        expect(CommandBarPreferences.decodeAliases(
                    CommandBarPreferences.encodeAliases(["a": "one", "b": "two"])) == ["a": "one", "b": "two"],
               "names survive the round trip")
        expect(CommandBarPreferences.decodeAliases("not json").isEmpty,
               "a corrupt name list decodes as none")
        expect(CommandBarPreferences.decodeAliases("{\"a\":\"   \"}").isEmpty,
               "a name of spaces is no name at all")
        expect(CommandBarPreferences.acceptsAlias(rowID: "app.x")
                && !CommandBarPreferences.acceptsAlias(rowID: "menu.1.Bold")
                && !CommandBarPreferences.acceptsAlias(rowID: "window.4")
                && !CommandBarPreferences.acceptsAlias(rowID: "clipboard.abc")
                && !CommandBarPreferences.acceptsAlias(rowID: "uninstall.x"),
               "only rows that are the same thing tomorrow can be named")
        expect(CommandBarPreferences.aliasHit("codex", query: "codex") == .exact
                && CommandBarPreferences.aliasHit("codex", query: "cod") == .prefix
                && CommandBarPreferences.aliasHit("codex", query: "zzz") == nil,
               "a finished name outranks one still being typed")
        expect(CommandBarPreferences.AliasHit.exact.rawValue > 1200
                && CommandBarPreferences.AliasHit.prefix.rawValue > 900,
               "the name the person gave beats the app's own title")
        expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.b")
                == "app.a",
               "a name already taken is reported instead of being stolen")
        expect(CommandBarPreferences.rowUsingAlias("codex", in: ["app.a": "codex"], excluding: "app.a")
                == nil,
               "renaming a row never conflicts with itself")
        expect(CommandBarPreferences.removingAliases(for: ["app.a", "app.b"],
                                                     in: ["app.a": "one", "app.c": "two"])
                == ["app.c": "two"],
               "an uninstalled app's name goes with its row")

        // MARK: - Pins

        expect(!CommandBarPreferences.acceptsPin(rowID: "uninstall.x")
                && !CommandBarPreferences.acceptsPin(rowID: "menu.1.Bold")
                && CommandBarPreferences.acceptsPin(rowID: "app.x"),
               "an uninstall row is offered fresh each time, so it cannot be pinned")
        var pins = CommandBarPreferences.togglingPin("action.screenshot", in: [])
        pins = CommandBarPreferences.togglingPin("app.chat", in: pins)
        expect(pins == ["action.screenshot", "app.chat"], "pins keep the order they were made in")
        expect(CommandBarPreferences.togglingPin("action.screenshot", in: pins) == ["app.chat"],
               "the same gesture unpins")
        expect(CommandBarPreferences.leadingPins(["app.chat", "app.gone"],
                                                 available: ["app.chat", "action.a"]) == ["app.chat"],
               "the empty bar leads with the pins that still exist")
        expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.chat", "settings.cleaningMode"],
                    present: ["app.chat"]) == ["app.chat"],
               "an uninstalled feature is not listed as a pin")
        expect(CommandBarPreferences.listedPins(
                    ["action.cleaningMode", "app.gone"],
                    present: ["action.cleaningMode"]) == ["action.cleaningMode", "app.gone"],
               "an app that left this Mac still appears so its pin can be removed")
        expect(CommandBarPreferences.pinTieBreak < 700,
               "a pin breaks a tie and never jumps over a better match")
        expect(CommandBarPreferences.decodePins(CommandBarPreferences.encodePins(["a", "b"])) == ["a", "b"]
                && CommandBarPreferences.decodePins("a\na\n\nb") == ["a", "b"],
               "pins survive the round trip and never repeat")
        expect(CommandBarPreferences.removingPins(for: ["app.a"], in: ["app.a", "app.b"]) == ["app.b"],
               "an uninstalled app's pin goes with its row")

        // MARK: - Rows the person never wants to see

        var hidden = CommandBarPreferences.togglingHidden("app.x", in: [])
        expect(hidden == ["app.x"], "a row can be told never to show")
        hidden = CommandBarPreferences.togglingHidden("app.x", in: hidden)
        expect(hidden.isEmpty, "and told to come back")
        expect(CommandBarPreferences.decodeHidden(
                    CommandBarPreferences.encodeHidden(["b", "a"])) == ["a", "b"],
               "hidden rows survive the round trip")
        expect(CommandBarPreferences.removingHidden(for: ["app.a"], in: ["app.a", "app.b"]) == ["app.b"],
               "an uninstalled app's hidden entry goes with its row")

        // MARK: - Where the bar was dragged to

        let positionOffset = CGSize(width: -24.4, height: 80.6)
        expect(CommandBarPreferences.decodePositionOffset(
                    CommandBarPreferences.encodePositionOffset(positionOffset))
                == CGSize(width: -24, height: 81),
               "the command bar position offset survives a rounded round trip")
        expect(CommandBarPreferences.encodePositionOffset(.zero) == "",
               "a bar that was never dragged stores nothing")
        for invalidOffset in ["", "12", "12,", "12,nope", "12,nope,20", "nan,1", "inf,1"] {
            expect(CommandBarPreferences.decodePositionOffset(invalidOffset) == .zero,
                   "an invalid command bar position offset is ignored (\(invalidOffset))")
        }

        // MARK: - Emoji preferences

        expect(CommandBarPreferences.emojiIdentity(fromRowID: "emoji.grin") == "grin"
                && CommandBarPreferences.emojiIdentity(fromRowID: "emoji.") == nil
                && CommandBarPreferences.emojiIdentity(fromRowID: "kill.x") == nil,
               "only a row under the emoji prefix names an emoji")
        expect(CommandBarPreferences.skinTone(from: "") == .none
                && CommandBarPreferences.skinTone(from: "nonsense") == .none
                && CommandBarPreferences.skinTone(from: "dark") == .dark,
               "an unknown stored tone reads as the yellow default")
    }
}
