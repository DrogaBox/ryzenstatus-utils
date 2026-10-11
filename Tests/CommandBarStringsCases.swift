// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The command bar's localization contract, in the same spirit as the checks
/// `./build.sh --test` runs over the main catalog: every language is built,
/// no field is left empty, every format keeps the specifiers it has to fill,
/// and no string carries another app's brand.
enum CommandBarStringsCases {
    static func run(_ expect: CommandBarExpect) {
        let languages = AppLanguage.allCases
        expect(languages.count == 15, "the command bar is translated into every language the app ships")
        // Assembled from parts so this file itself never trips the brand grep
        // the project runs before closing a phase.
        let forbiddenBrand = "vor" + "ssaint"

        var catalogFields = 0
        for language in languages {
            let strings = FeatureStrings.commandBar(language)
            let mirror = Mirror(reflecting: strings)
            var fields: [String: String] = [:]
            for child in mirror.children {
                guard let name = child.label, let value = child.value as? String else { continue }
                fields[name] = value
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                expect(!trimmed.isEmpty, "\(language.rawValue).\(name) is empty")
                expect(!value.lowercased().contains(forbiddenBrand),
                       "\(language.rawValue).\(name) carries another app's brand")
            }
            if catalogFields == 0 { catalogFields = fields.count }
            expect(fields.count == catalogFields,
                   "\(language.rawValue) defines the same field set as en-US")

            // A format must keep the placeholders its call sites fill, or the
            // row would show a literal `%@` in that language alone. These are
            // the fields whose call sites pass arguments (see CommandBarService
            // and CommandBarSettings).
            let reference = formatFields(of: FeatureStrings.commandBar(.enUS))
            for (name, format) in formatFields(of: strings) {
                let expected = specifiers(in: reference[name] ?? format)
                expect(specifiers(in: format) == expected,
                       "\(language.rawValue).\(name) lost a format specifier (expected \(expected))")
            }
            expect(specifiers(in: strings.keepAwakeForFormat) == ["@"],
                   "\(language.rawValue).keepAwakeForFormat fills a duration")
            expect(specifiers(in: strings.quitFormat) == ["@"],
                   "\(language.rawValue).quitFormat fills an app name")
            expect(specifiers(in: strings.argumentRangeFormat).count == 2,
                   "\(language.rawValue).argumentRangeFormat fills a range")
            expect(specifiers(in: strings.rowShortcutsLimitFormat) == ["d"]
                       || specifiers(in: strings.rowShortcutsLimitFormat) == ["ld"],
                   "\(language.rawValue).rowShortcutsLimitFormat fills a count")
        }

        // 166 fields is the whole bar as upstream ships it: the guard catches a
        // language that was pasted in with half of its struct, not a new field.
        expect(catalogFields >= 150, "the catalog carries the whole bar, not a subset (\(catalogFields) fields)")
    }

    /// The fields whose value is a format string, keyed by name so the same
    /// field can be compared across languages.
    private static func formatFields(of strings: CommandBarFeatureStrings) -> [String: String] {
        [
            "keepAwakeForFormat": strings.keepAwakeForFormat,
            "needsSetupFormat": strings.needsSetupFormat,
            "quitFormat": strings.quitFormat,
            "quitConfirmFormat": strings.quitConfirmFormat,
            "aliasTakenFormat": strings.aliasTakenFormat,
            "argumentRangeFormat": strings.argumentRangeFormat,
            "rowShortcutsLimitFormat": strings.rowShortcutsLimitFormat,
            "turnOnFormat": strings.turnOnFormat,
            "turnOffFormat": strings.turnOffFormat,
            "restartAppFormat": strings.restartAppFormat,
            "forceQuitAppFormat": strings.forceQuitAppFormat,
            "forceQuitAppConfirmFormat": strings.forceQuitAppConfirmFormat,
            "uninstallAppFormat": strings.uninstallAppFormat,
        ]
    }

    /// The specifier letters a format contains, in order, the same way the
    /// main harness reads them: `%%` is a literal and contributes nothing.
    private static func specifiers(in format: String) -> [String] {
        var specifiers: [String] = []
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            index = format.index(after: index)
            if index < format.endIndex, format[index] == "%" {
                index = format.index(after: index)
                continue
            }
            while index < format.endIndex {
                let character = format[index]
                if character.isLetter || character == "@" {
                    specifiers.append(String(character))
                    index = format.index(after: index)
                    break
                }
                index = format.index(after: index)
            }
        }
        return specifiers
    }
}
