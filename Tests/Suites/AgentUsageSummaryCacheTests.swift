// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum AgentUsageSummaryCacheTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // The day before the spring DST transition, including future entries.
        var now = AgentTimestamp.parse("2026-03-07T23:55:00Z")!
        let cache = AgentUsageSummaryCache()
        var records: [AgentUsageRecord] = (0..<6_000).map { index -> AgentUsageRecord in
            let provider: AgentProvider = index % 2 == 0 ? .claude : .codex
            let date = now.addingTimeInterval(-Double(index) * 1_400 + 900)
            let model = index % 2 == 0 ? "claude-opus-5-5" : "gpt-6-sol"
            let tokens = AgentTokens(input: index + 1, output: 10)
            let cost: Double? = index % 13 == 0 ? nil : Double(index % 11) / 8
            return AgentUsageRecord(provider: provider, date: date, model: model, project: "p\(index % 7)",
                                    session: "s", tokens: tokens, cost: cost, savings: 0.125)
        }
        var providers = Set(AgentProvider.allCases)
        var live: [AgentLiveSession] = []
        var limits: [AgentProvider: AgentLimits] = [:]
        var plans: [AgentProvider: AgentPlan] = [:]
        func check(_ message: String) {
            let actual = cache.snapshot(records: records, limits: limits, live: live, plans: plans,
                                        providers: providers, now: now, calendar: calendar)
            let expected = AgentUsageSummary.snapshot(records: records, limits: limits, live: live, plans: plans,
                                                       providers: providers, now: now, calendar: calendar)
            suite.expect(actual == expected, actual == expected ? message
                         : message + " (differs in: " + differingFields(actual, expected).joined(separator: ", ") + ")")
        }
        let tied = [AgentShare(id: "copilot:Opus 5.5", name: "Opus 5.5", provider: .copilot, totals: AgentTotals()),
                    AgentShare(id: "claude:Opus 5.5", name: "Opus 5.5", provider: .claude, totals: AgentTotals())]
        suite.expect(AgentUsageSummary.sorted(tied, byCost: false).map(\.id)
                        == AgentUsageSummary.sorted(tied.reversed(), byCost: false).map(\.id),
                     "shares with the same name and weight sort the same whatever order they arrive in")
        check("cached history matches every field of the full summary")
        suite.expect(cache.accumulatedRecords == records.count, "the first snapshot accumulates history once")
        live = [AgentLiveSession(id: "live", provider: .codex, started: now, lastActivity: now,
                                 model: "gpt-6-sol", project: "p", tokens: AgentTokens(), cost: 0)]
        check("live sessions update without changing historical usage")
        suite.expect(cache.accumulatedRecords == 0, "live-only publications accumulate no historical records")
        limits[.codex] = AgentLimits(provider: .codex, windows: [], observedAt: now, source: .sessionLog)
        plans[.codex] = AgentPlan(name: "Pro", monthlyPrice: 200)
        check("plan and limit changes update independently from historical totals")
        suite.expect(cache.accumulatedRecords == 0, "metadata-only publications accumulate no historical records")
        let appended = AgentUsageRecord(provider: .codex, date: now, model: "gpt-6-sol", project: "new",
            session: "s", tokens: AgentTokens(input: 50, output: 10), cost: 0.25, savings: 0.125)
        records.append(appended)
        cache.recordChanged(at: records.count - 1, previous: nil)
        check("an appended response updates all periods, buckets and breakdowns")
        suite.expect(cache.accumulatedRecords == 1, "one appended response does not rescan the history")
        for _ in 0..<3 {
            let position = records.count - 1
            cache.recordChanged(at: position, previous: records[position])
            records[position].tokens.output += 5
            records[position].cost! += 0.125
        }
        check("several streamed corrections use the original response exactly once")
        suite.expect(cache.accumulatedRecords == 1, "a streamed response only accumulates one delta")
        // A response can be appended and revised within the same publication.
        cache.recordChanged(at: records.count, previous: nil)
        records.append(appended)
        cache.recordChanged(at: records.count - 1, previous: appended)
        records[records.count - 1].tokens.output += 1
        check("a response appended and revised before publication is not subtracted twice")
        let late = AgentUsageRecord(provider: .claude, date: now.addingTimeInterval(-20 * 86_400),
            model: "unknown", project: "late", session: "s", tokens: AgentTokens(output: 5), cost: nil, savings: 0)
        cache.recordChanged(at: records.count, previous: nil)
        records.append(late)
        check("a newly discovered old response updates history without entering sliding windows")
        // Exercise an unpriced response becoming priced through a correction.
        cache.recordChanged(at: 13, previous: records[13])
        records[13].cost = 0.5
        records[13].tokens.output += 2
        check("streaming updates unpriced counts and model sort weights")
        now = now.addingTimeInterval(3_600)
        check("sliding windows expire and future responses become current without a history scan")
        suite.expect(cache.accumulatedRecords == 0, "clock-only updates leave historical totals cached")
        live = []
        providers = [.claude]
        check("disabling a provider removes its usage, limits and live sessions")
        providers = Set(AgentProvider.allCases)
        check("reenabling a provider rebuilds its historical totals")
        now = now.addingTimeInterval(86_400)
        check("midnight across DST rebuilds daily and hourly boundaries")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        check("a time-zone change rebuilds the date buckets")
        now = now.addingTimeInterval(-90_000)
        check("a backwards clock restores entries that left the sliding windows")
        records.removeFirst(20)
        cache.invalidate()
        check("pruning rebuilds positions and totals without stale recent entries")
        for index in records.indices { records[index].cost = 0.5 }
        cache.invalidate()
        check("repricing rebuilds cost, savings and unpriced totals")
        storeIntegration(suite, now: now, calendar: calendar)
    }

    /// Which parts of two snapshots differ, so a failure on CI says where to
    /// look instead of only that something did.
    static func differingFields(_ actual: AgentUsageSnapshot, _ expected: AgentUsageSnapshot) -> [String] {
        var fields: [String] = []
        for period in AgentPeriod.allCases {
            let left = actual.usage(period), right = expected.usage(period)
            if left.total != right.total { fields.append("\(period.rawValue).total") }
            if left.byProvider != right.byProvider { fields.append("\(period.rawValue).byProvider") }
            if left.models != right.models {
                fields.append("\(period.rawValue).models \(left.models.map(\.id)) vs \(right.models.map(\.id))")
            }
            if left.projects != right.projects {
                fields.append("\(period.rawValue).projects \(left.projects.map(\.id)) vs \(right.projects.map(\.id))")
            }
        }
        if actual.periods.keys.sorted(by: { $0.rawValue < $1.rawValue })
            != expected.periods.keys.sorted(by: { $0.rawValue < $1.rawValue }) { fields.append("periods.keys") }
        if actual.days != expected.days { fields.append("days") }
        if actual.hours != expected.hours { fields.append("hours") }
        if actual.burnRate != expected.burnRate { fields.append("burnRate") }
        if actual.claudeBlock != expected.claudeBlock { fields.append("claudeBlock") }
        if actual.lastActivity != expected.lastActivity { fields.append("lastActivity") }
        if actual.seen != expected.seen { fields.append("seen") }
        if actual.limits != expected.limits { fields.append("limits") }
        if actual.plans != expected.plans { fields.append("plans") }
        if actual.live != expected.live { fields.append("live") }
        if actual.now != expected.now || actual.loaded != expected.loaded { fields.append("now/loaded") }
        return fields.isEmpty ? ["no field compared here"] : fields
    }

    private static func storeIntegration(_ suite: TestSuite, now: Date, calendar: Calendar) {
        let store = AgentUsageStore()
        let providers = Set(AgentProvider.allCases)
        func check(_ message: String) {
            let actual = store.snapshot(plans: [:], providers: providers, now: now, calendar: calendar)
            let expected = AgentUsageSummary.snapshot(records: store.records, limits: store.limits, live: store.live,
                                                       plans: [:], providers: providers, now: now, calendar: calendar)
            suite.expect(actual == expected, message)
        }
        check("the store starts with a valid empty summary")
        func apply(output: Int, key: String, age: TimeInterval = 0) {
            let tokens = AgentTokens(input: 100, output: output)
            let billable = AgentBillable(tokens: tokens)
            let price = AgentPricing.cost(billable, model: "gpt-6-sol")
            let record = AgentUsageRecord(provider: .codex, date: now.addingTimeInterval(-age), model: "gpt-6-sol",
                project: "project", session: "s", tokens: tokens, cost: price.cost, savings: price.savings)
            store.apply([.usage(key: key, record: record, billable: billable)], file: "f", provider: .codex,
                        tracksTurns: false, modified: now, now: now)
        }
        apply(output: 5, key: "first")
        check("store insertion invalidates the cached summary")
        apply(output: 15, key: "first")
        apply(output: 15, key: "first")
        check("store streaming and duplicate records preserve summary totals")
        apply(output: 5, key: "old", age: 80 * 86_400)
        check("late historical responses update their own date buckets")
        store.reprice()
        check("store repricing invalidates every cached total")
        store.dropRecords(before: now.addingTimeInterval(-86_400))
        check("store pruning invalidates cached record positions")
    }
}
