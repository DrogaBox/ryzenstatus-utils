// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The questions about time the bar answers from the calendar this Mac already
/// carries, and the much larger set of things that must stay a search.
/// Expectations are the upstream suite's (Tests/CommandBarFeatureTests.swift,
/// "Dates and places") run against the local `CommandBarDates`.
enum CommandBarDatesCases {
    static func run(_ expect: CommandBarExpect) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let english = Locale(identifier: "en_US")
        let tuesday = Date(timeIntervalSince1970: 1_785_240_000)   // 2026-07-28

        func dated(_ input: String, locale: Locale) -> String? {
            CommandBarDates.evaluate(input, now: tuesday, calendar: gregorian, locale: locale)?.formatted
        }
        func answer(_ input: String) -> CommandBarDates.Result? {
            CommandBarDates.evaluate(input, now: tuesday, calendar: gregorian, locale: english)
        }

        // MARK: Counting forwards and backwards

        expect(dated("in 3 weeks", locale: english) == "August 18, 2026",
               "three weeks from now is a date, not a search")
        expect(dated("daqui 10 dias", locale: Locale(identifier: "pt_BR")) == "7 de agosto de 2026",
               "the same question in the person's own words, written their way")
        expect(dated("3 days ago", locale: english) == "July 25, 2026"
                && dated("ha 3 dias", locale: english) == "July 25, 2026",
               "backwards counts backwards, before or after the number")
        expect(dated("today + 10 days", locale: english) == "August 7, 2026"
                && dated("today - 10 days", locale: english) == "July 18, 2026",
               "a plain sign decides the direction")

        // MARK: The gate that keeps the bar a launcher

        expect(dated("3 days", locale: english) == nil
                && dated("2+2", locale: english) == nil
                && dated("100 km to mi", locale: english) == nil,
               "without a direction it is not a question, and a sum is not a date")
        for innocent in ["1password", "2 monitors", "3 tags", "notes", "day one",
                         "5 minutes", "2026-07-28", "the 3 body problem"] {
            expect(answer(innocent) == nil, "\"\(innocent)\" is a search, not a date")
        }

        // MARK: The one line under the answer

        expect(answer("in 3 weeks")?.detail == "Tuesday",
               "the answer says which weekday it lands on")
        expect(answer("time in tokyo")?.detail.hasPrefix("Tokyo") == true,
               "the clock somewhere else, from the time zones the Mac already knows")
        expect(answer("hora em londres")?.detail.hasPrefix("London") == true,
               "a city named the way the person's language names it")
        expect(answer("time") == nil,
               "a time word with nowhere to look is not an answer")

        // MARK: How far away a written date is

        expect(dated("days until 12/25", locale: english)?.contains("150") == true,
               "how far away a written date is, counted in whole days")
    }
}
