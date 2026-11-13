// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

enum LeakHistoryTests {
    static func run(_ suite: TestSuite) {
        footprint(suite)
        sampling(suite)
        window(suite)
        verdicts(suite)
    }

    private static func footprint(_ suite: TestSuite) {
        let own = ProcessFootprint.bytes(of: getpid())
        suite.expect((own ?? 0) > 1 << 20, "a running process reports the memory it holds")
        suite.expect(ProcessFootprint.bytes(of: 0x7FFF_FFF0) == nil, "a process that does not exist reports none")
    }

    private static func sampling(_ suite: TestSuite) {
        var history = LeakHistory()
        let start = Date(timeIntervalSinceReferenceDate: 820_000_000)
        suite.expect(history.isDue(at: start), "the first sample is always due")
        history.record([10: 100], at: start)
        suite.expect(!history.isDue(at: start.addingTimeInterval(LeakHistory.sampleInterval - 1)),
                     "a refresh a second later adds no sample")
        suite.expect(history.isDue(at: start.addingTimeInterval(LeakHistory.sampleInterval)),
                     "the next sample is due after the interval")
        suite.expect(history.isDue(at: start.addingTimeInterval(-60)), "a clock set back does not stop the sampling")
    }

    private static func window(_ suite: TestSuite) {
        var history = LeakHistory()
        let start = Date(timeIntervalSinceReferenceDate: 820_000_000)
        let steps = Int(LeakHistory.window / LeakHistory.sampleInterval) * 3
        for step in 0..<steps {
            history.record([10: UInt64(step), 11: 5], at: start.addingTimeInterval(Double(step) * LeakHistory.sampleInterval))
        }
        let kept = history.series[10] ?? []
        let most = Int(LeakHistory.window / LeakHistory.sampleInterval) + 1
        suite.expect(kept.count == most, "a series keeps the window and nothing older")
        suite.expect(kept.last?.1 == UInt64(steps - 1) && kept.first?.1 == UInt64(steps - most),
                     "the newest readings are the ones kept, in order")
        history.record([11: 5], at: start.addingTimeInterval(Double(steps) * LeakHistory.sampleInterval))
        suite.expect(history.series[10] == nil && history.series[11] != nil, "an app that quit is forgotten")
    }

    /// The case that raised a false alarm: resident size climbing for half an
    /// hour while the memory really held stays where it was.
    private static func verdicts(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 820_000_000)
        var steady = LeakHistory()
        var leaking = LeakHistory()
        var resident: [(Date, UInt64)] = []
        for step in 0...180 {
            let at = start.addingTimeInterval(Double(step) * LeakHistory.sampleInterval)
            let wobble = UInt64((step * 37) % 11) << 20
            steady.record([10: (200 << 20) + wobble], at: at)
            leaking.record([10: (200 << 20) + UInt64(step) * (1 << 20)], at: at)
            resident.append((at, (400 << 20) + UInt64(step) * (1 << 20)))
        }
        suite.expect(LeakDetector.analyze(series: resident) != nil, "resident size that only climbs reads as a leak")
        suite.expect(LeakDetector.analyze(series: steady.series[10] ?? []) == nil,
                     "a footprint that holds steady is no leak, whatever the resident size does")
        suite.expect(LeakDetector.analyze(series: leaking.series[10] ?? []) != nil,
                     "a footprint that climbs for half an hour is still caught")
    }
}
