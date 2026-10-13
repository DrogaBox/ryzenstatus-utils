// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The emoji catalog and the tones it can carry.
///
/// Expectations lifted from upstream's `CommandBarEmojiTests` (the pure parts:
/// the catalog's identity contract and the skin-tone rules). The row
/// construction, usage recording and query-habit halves of that file need the
/// catalog and the service, which this harness does not compile.
enum CommandBarEmojiCases {
    static func run(_ expect: CommandBarExpect) {
        // MARK: - Skin tones

        let tones = CommandBarEmoji.SkinTone.allCases
        expect(tones.count == 6 && CommandBarEmoji.SkinTone.none.rawValue == "",
               "the yellow default stores as an empty string and five tones sit beside it")
        expect(Set(tones.map(\.rawValue)).count == tones.count,
               "every stored tone reads back as exactly one tone")

        expect(!CommandBarEmoji.acceptsSkinTone("👪")
                && tones.allSatisfy { CommandBarEmoji.applying($0, to: "👪") == "👪" },
               "family stays unchanged instead of offering unsupported skin tones")
        expect(["👍", "☝️", "🤝", "👫", "👬", "👭", "💏", "💑"].allSatisfy {
            CommandBarEmoji.acceptsSkinTone($0)
        },
               "excluding family preserves supported single-person and multi-person tones")
        expect(CommandBarEmoji.applying(.none, to: "👍") == "👍",
               "the default tone adds nothing")
        expect(CommandBarEmoji.applying(.dark, to: "👍") == "👍" + String(Unicode.Scalar(0x1F3FF)!),
               "the dark tone is the darkest modifier on the hand")
        expect(CommandBarEmoji.applying(.light, to: "👪") == "👪",
               "a tone on an unsupported emoji is refused rather than mangled")
        expect(CommandBarEmoji.SkinTone.dark.swatch == CommandBarEmoji.applying(.dark, to: "✋"),
               "a tone's swatch shows the same picker in every tone")

        // MARK: - Row identity

        expect(CommandBarPreferences.emojiBrowserRowID == "emoji.browse",
               "the row that opens the emoji browser keeps the id row shortcuts persist")
        expect(CommandBarPreferences.emojiRowID(identity: "👍") == "emoji.👍"
                && CommandBarPreferences.emojiIdentity(fromRowID: "emoji.👍") == "👍",
               "an emoji's row id survives the round trip through storage")
        expect(CommandBarPreferences.emojiIdentity(fromRowID: "emoji.") == nil
                && CommandBarPreferences.emojiIdentity(fromRowID: "app.x") == nil,
               "only an emoji row names an emoji")

        // MARK: - The catalog itself

        let catalog = CommandBarEmoji.emoji
        expect(!catalog.isEmpty, "the catalog is never empty")
        expect(Set(catalog.map(\.character)).count == catalog.count,
               "no emoji is offered twice under one character")
        expect(catalog.contains { $0.identity == "👍" },
               "the thumbs up the skin-tone rows hang off is in the catalog")
        expect(catalog.contains { $0.identity == "🔥" },
               "a popular emoji leads the catalog")
        expect(catalog.first { $0.identity == "🔥" }?.keywords.contains("fire") == true,
               "an emoji carries the words people actually type for it")
        expect(catalog.first { $0.identity == "👍" }?.name.contains("thumbs") == true,
               "an emoji's name comes from Unicode, so the long tail needs no list of its own")
        expect(catalog.allSatisfy { !$0.name.isEmpty },
               "every emoji in the catalog has a name to be found by")
    }
}
