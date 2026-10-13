// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What the bar noticed about this session: the letters that led to a row.
///
/// Expectations lifted from upstream's `CommandBarFeatureTests` ("What the bar
/// noticed about this session" and the folded-letters pair). The stored query
/// habits (`CommandBarQueryHabits`, `CommandBarUsage`) live in
/// `CommandBarSupport.swift`, which this harness does not compile, so the
/// in-memory memory is what is pinned here.
enum CommandBarLearningCases {
    static func run(_ expect: CommandBarExpect) {
        // MARK: - What a prefix is

        expect(CommandBarQueryMemory.prefixes(of: "wha") == ["w", "wh", "wha"],
               "choosing a row for what was typed also answers every shorter piece of it")
        expect(CommandBarQueryMemory.prefixes(of: "  Résumé ")
                == ["r", "re", "res", "resu", "resum", "resume"],
               "what is remembered is folded the way the ranking folds, accents and all")
        expect(CommandBarQueryMemory.prefixes(of: "   ").isEmpty,
               "an empty field teaches nothing")
        expect(CommandBarQueryMemory.prefixes(of: String(repeating: "a", count: 40)).count
                == CommandBarQueryMemory.longestPrefix,
               "past a word's worth of letters the ranking already knows what to do")

        // MARK: - What a remembered choice is worth

        var memory = CommandBarQueryMemory()
        expect(memory.isEmpty && memory.boost(query: "pri", id: "app.primary") == 0,
               "a row never chosen for these letters is worth nothing extra")
        memory.record(query: "primary", id: "app.primary", step: 1)
        expect(memory.boost(query: "pri", id: "app.primary") > 0
                && memory.boost(query: "pri", id: "app.other") == 0
                && memory.boost(query: "prim", id: "app.primary") > 0,
               "the row chosen for a word answers to the letters on the way to it")
        expect(memory.boost(query: "primary extra", id: "app.primary") == 0,
               "letters that were never typed on their own teach nothing")
        memory.record(query: "primary", id: "app.primary", step: 2)
        memory.record(query: "primary", id: "app.primary", step: 3)
        memory.record(query: "primary", id: "app.primary", step: 4)
        expect(memory.boost(query: "pri", id: "app.primary") == CommandBarQueryMemory.maximumBoost,
               "choosing the same row again stops adding up once it is certain")
        expect(CommandBarQueryMemory.maximumBoost < 60,
               "what the bar noticed reorders ties and never beats a better keyword match")

        // MARK: - Forgetting

        memory.forget(id: "app.primary")
        expect(memory.isEmpty, "forgetting one row takes it out of every prefix")
        memory.record(query: "a", id: "one", step: 1)
        memory.clear()
        expect(memory.isEmpty, "and the whole session can be forgotten at once")

        // MARK: - One prefix remembers a few rows

        // Five rows compete for one prefix; the least chosen is the one that
        // stops being remembered.
        var crowded = CommandBarQueryMemory()
        for index in 0..<(CommandBarQueryMemory.idsPerQuery + 1) {
            for repeatCount in 0...(index == 0 ? 0 : 3) {
                crowded.record(query: "x", id: "row.\(index)", step: index * 10 + repeatCount)
            }
        }
        expect(crowded.boost(query: "x", id: "row.0") == 0
                && crowded.boost(query: "x", id: "row.4") > 0,
               "one prefix remembers a few rows, and the one picked least drops out")

        // MARK: - Folded letters ask the same question

        var folded = CommandBarQueryMemory()
        expect(folded.boost(normalizedQuery: "pri", id: "app.primary") == 0,
               "a memory holding nothing is worth nothing for folded letters either")
        folded.record(query: "Primary", id: "app.primary", step: 1)
        expect(folded.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"), id: "app.primary") > 0
                && folded.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"), id: "app.primary")
                    == folded.boost(query: "PRÍ", id: "app.primary"),
               "folded letters ask the query memory the same question the raw ones do")
    }
}
