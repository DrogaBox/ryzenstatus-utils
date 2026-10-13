// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Unit conversion: what converts, what is refused, and how a number is read
/// in each region's format. Expectations are the upstream suite's
/// (Tests/CommandBarFeatureTests.swift, "Command bar unit conversion") run
/// against the local `CommandBarUnits`.
enum CommandBarUnitsCases {
    static func run(_ expect: CommandBarExpect) {
        func units(_ input: String,
                   decimal: String = ".",
                   grouping: String = ",",
                   locale: String = "en_US") -> String? {
            CommandBarUnits.convert(input,
                                    decimalSeparator: decimal,
                                    groupingSeparator: grouping,
                                    locale: Locale(identifier: locale))?.formatted
        }
        func unitValue(_ input: String) -> Double? {
            CommandBarUnits.convert(input,
                                    decimalSeparator: ".",
                                    groupingSeparator: ",",
                                    locale: Locale(identifier: "en_US"))?.value
        }

        // MARK: What converts

        expect(unitValue("100 km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "a distance converts")
        expect(unitValue("20 c to f").map { abs($0 - 68) < 0.001 } == true,
               "a temperature converts as an absolute reading, not as a step")
        expect(unitValue("0 c to f").map { abs($0 - 32) < 0.001 } == true,
               "freezing reads as freezing")
        expect(unitValue("5 gb to mb").map { abs($0 - 5000) < 0.001 } == true,
               "storage uses the decimal units it is written with")
        expect(unitValue("1 gib to mib").map { abs($0 - 1024) < 0.001 } == true,
               "and the binary ones when those are written instead")
        expect(unitValue("100km to mi").map { abs($0 - 62.1371) < 0.001 } == true,
               "the number and the unit do not need a space between them")
        expect(unitValue("5 in to cm").map { abs($0 - 12.7) < 0.001 } == true,
               "the word that also means inches is read correctly on both sides")
        expect(unitValue("2 h to min").map { abs($0 - 120) < 0.001 } == true,
               "hours become minutes")
        expect(unitValue("1 kg to lb").map { abs($0 - 2.20462) < 0.001 } == true,
               "mass converts")
        expect(unitValue("1.5 l to ml").map { abs($0 - 1500) < 0.001 } == true,
               "a decimal amount converts")

        // MARK: What stays a search

        expect(units("100 km to kg") == nil, "two different families never meet")
        expect(units("100 km") == nil, "without the word there is no conversion")
        expect(units("to") == nil && units("in") == nil,
               "the little words alone convert nothing")
        expect(units("safari to dock") == nil, "plain words are not units")
        expect(units("5 xyz to cm") == nil, "an unknown unit is refused, never guessed")
        expect(units("minutes to read the article") == nil,
               "a sentence that happens to contain a unit word stays a search")

        // MARK: A comma decimal

        expect(CommandBarUnits.convert("1,5 m to cm",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))
                .map { abs($0.value - 150) < 0.001 } == true,
               "a comma decimal converts where that is the custom")

        // A first group of 0 is never thousands, so "0,250" is a quarter where
        // the dot is decimal, while "1,050" still groups.
        let dotDecimalInputs: [(String, Double)] = [
            ("1.5", 150.0), ("1,5", 150.0), ("-1,5", -150.0),
            ("1,500", 150_000.0), ("-123,456", -12_345_600.0),
            ("1,234.5", 123_450.0), ("1.234,5", 123_450.0),
            ("1,234,567", 123_456_700.0),
            ("0,250", 25.0), ("-0,500", -50.0), ("1,050", 105_000.0),
        ]
        let commaDecimalInputs: [(String, Double)] = [
            ("1,5", 150.0), ("1.5", 150.0), ("-1.5", -150.0),
            ("1.500", 150_000.0), ("-123.456", -12_345_600.0),
            ("1.234,5", 123_450.0), ("1,234.5", 123_450.0),
            ("1.234.567", 123_456_700.0),
            ("0.250", 25.0), ("-0.500", -50.0), ("1.050", 105_000.0),
        ]
        // de_CH groups thousands with an apostrophe, pt_PT with a no-break
        // space and fr_FR with a narrow one. There the alternate is whichever
        // of "." and "," is not the decimal, the same as in the calculator.
        for (region, decimal, grouping, inputs) in [
            ("en_US", ".", ",", dotDecimalInputs),
            ("de_CH", ".", "'", dotDecimalInputs),
            ("de_DE", ",", ".", commaDecimalInputs),
            ("pt_PT", ",", "\u{00A0}", commaDecimalInputs),
            ("fr_FR", ",", "\u{202F}", commaDecimalInputs),
        ] {
            for (number, expected) in inputs {
                let converted = CommandBarUnits.convert("\(number) m to cm",
                                                        decimalSeparator: decimal,
                                                        groupingSeparator: grouping,
                                                        locale: Locale(identifier: "en_US"))
                expect(converted.map { abs($0.value - expected) < 0.001 } == true,
                       "unit conversion in \(region) reads \(number) as \(expected) cm")
            }
            for number in ["1,,5", "1..5", "--1", "1-5"] {
                expect(CommandBarUnits.convert("\(number) m to cm",
                                               decimalSeparator: decimal,
                                               groupingSeparator: grouping) == nil,
                       "unit conversion in \(region) refuses malformed number \(number)")
            }
        }

        // MARK: Feet and inches

        // The measurement's words come from the localization data of the macOS
        // it runs on, not from the locale it is handed, so only the split into
        // whole feet and leftover inches and the number format are pinned here
        // (upstream issue #1344).
        let unitNumbers: (String?) -> [String] = { text in
            (text ?? "").split(whereSeparator: { !"0123456789.,-".contains($0) })
                .filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }
                .map(String.init)
        }
        expect(unitNumbers(units("180 cm to ft")) == ["5", "10.87"],
               "a length converting to feet keeps precise feet and inches")
        expect(unitNumbers(units("1.75 m to ft")) == ["5", "8.9"],
               "a decimal length keeps its fractional inches")
        expect(unitNumbers(units("6 ft to ft")) == ["6"],
               "a whole number of feet has no leftover inches shown")
        expect(unitNumbers(units("5.9999 ft to ft")) == ["6"],
               "inches that round up to twelve carry into the next whole foot")
        expect(unitNumbers(units("2 cm to ft")) == ["0.0656"],
               "a length below one foot stays precise instead of rounding to inches")
        expect(unitNumbers(units("-180 cm to ft")) == ["-5.91"],
               "a negative length keeps the existing decimal format")
        expect(unitNumbers(units("180 cm to in")) == ["70.87"],
               "converting to inches specifically stays a plain decimal, unaffected by the feet formatting")
        expect(unitNumbers(units("180 cm para pes", decimal: ",", grouping: ".", locale: "pt_BR"))
                == ["5", "10,87"],
               "feet and inches follow the person's number format")
    }
}
