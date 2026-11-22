// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// CPU package power and the average CPU clock in the 30-day history: where
/// they sit in the file, a file from before them, and a save and reload.
enum LongHistoryCPUTests {
    /// The metrics a history file held before these two: every case up to
    /// and including the VRAM temperature.
    private static let oldMetricCount = 11

    static func run(_ suite: TestSuite) {
        order(suite)
        oldFile(suite)
        roundTrip(suite)
        chartMetrics(suite)
    }

    private static func coarseTier() -> LongHistoryTier {
        LongHistoryTier(step: LongHistoryStore.coarseStep, capacity: LongHistoryStore.coarseCapacity)
    }

    /// A value per metric that no other metric shares, in its own units.
    private static func sample(_ index: Int) -> Double {
        Double(index + 1) * 10 + 0.5
    }

    private static func holds(_ values: [Double], _ expected: Double) -> Bool {
        let finite = values.filter(\.isFinite)
        return !finite.isEmpty && finite.allSatisfy { abs($0 - expected) < 0.01 }
    }

    private static func order(_ suite: TestSuite) {
        suite.expect(LongHistoryMetric.gpuMemoryTemperature.rawValue == oldMetricCount - 1,
                     "the VRAM metric is still the last of the old file's metrics")
        suite.expect(LongHistoryMetric.cpuPower.rawValue == oldMetricCount
                     && LongHistoryMetric.cpuClock.rawValue == oldMetricCount + 1,
                     "package power and clock come after every metric older files store")
        suite.expect(LongHistoryMetric.allCases.count == oldMetricCount + 2,
                     "the history keeps 13 metrics")
    }

    /// A file written by the build before these metrics: eleven tiers, each
    /// with its own value. Every old metric loads where it was, and the two
    /// new ones start empty.
    private static func oldFile(_ suite: TestSuite) {
        var tiers = (0..<oldMetricCount).map { _ in coarseTier() }
        for index in tiers.indices {
            for minute in 0...30 { tiers[index].record(sample(index), at: TimeInterval(minute * 60)) }
        }
        let data = LongHistoryStore.encode(tiers)
        let storedCount = data.count >= 12
            ? data.subdata(in: 8..<12).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            : 0
        suite.expect(storedCount == UInt32(oldMetricCount), "the fixture has the old file's eleven metrics")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-history-cpu-old-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try data.write(to: url)
        } catch {
            suite.expect(false, "the eleven-metric fixture could be written")
            return
        }
        let store = LongHistoryStore(fileURL: url, now: 1_800)
        for index in 0..<oldMetricCount {
            guard let metric = LongHistoryMetric(rawValue: index) else {
                suite.expect(false, "metric \(index) still exists")
                continue
            }
            suite.expect(holds(store.averages(metric, range: .oneHour, end: 1_800), sample(index)),
                         "\(metric) keeps its saved history from the old file")
        }
        for metric in [LongHistoryMetric.cpuPower, .cpuClock] {
            suite.expect(!store.averages(metric, range: .oneHour, end: 1_800).contains { $0.isFinite },
                         "\(metric) starts empty after an old file")
            suite.expect(!store.averages(metric, range: .thirtyDays, end: 1_800).contains { $0.isFinite },
                         "\(metric) has nothing over 30 days either")
        }
    }

    /// Every metric, the two new ones included, survives a save and a
    /// relaunch with its own value, in its own units (W and MHz).
    private static func roundTrip(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-history-cpu-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent("long-history.bin")
        defer { try? FileManager.default.removeItem(at: folder) }
        let watts = 88.25
        let megahertz = 4_512.5
        func value(_ metric: LongHistoryMetric) -> Double {
            switch metric {
            case .cpuPower: return watts
            case .cpuClock: return megahertz
            default: return sample(metric.rawValue)
            }
        }
        let first = LongHistoryStore(fileURL: url, now: 0)
        for minute in 0...30 {
            for metric in LongHistoryMetric.allCases {
                first.record(metric, value(metric), at: TimeInterval(minute * 60))
            }
        }
        first.save(synchronously: true)
        suite.expect(FileManager.default.fileExists(atPath: url.path), "the history is written to disk")

        let second = LongHistoryStore(fileURL: url, now: 1_860)
        for metric in LongHistoryMetric.allCases {
            suite.expect(holds(second.averages(metric, range: .oneHour, end: 1_860), value(metric)),
                         "\(metric) reads back its saved value after a relaunch")
        }
        var restored = LongHistoryMetric.allCases.map { _ in coarseTier() }
        if let data = try? Data(contentsOf: url) {
            LongHistoryStore.decode(data, into: &restored)
        }
        let slot = restored[LongHistoryMetric.cpuClock.rawValue].slot(at: 600)
        suite.expectClose(Double(restored[LongHistoryMetric.cpuClock.rawValue].mean(slot: slot) ?? .nan),
                          megahertz, "the clock is stored in MHz", tol: 0.01)
        suite.expectClose(Double(restored[LongHistoryMetric.cpuPower.rawValue].mean(slot: slot) ?? .nan),
                          watts, "the package power is stored in watts", tol: 0.01)

        // An older build reading this file keeps its own metrics and skips
        // the ones it does not know.
        var older = (0..<oldMetricCount).map { _ in coarseTier() }
        if let data = try? Data(contentsOf: url) {
            LongHistoryStore.decode(data, into: &older)
        }
        suite.expect(older.indices.allSatisfy { index in
            older[index].mean(slot: older[index].slot(at: 600)).map { abs(Double($0) - sample(index)) < 0.01 } ?? false
        }, "a build with only the old metrics still reads its own from the new file")
    }

    /// The History chart offers both, each mapped to its own series, and
    /// every language names them.
    private static func chartMetrics(_ suite: TestSuite) {
        suite.expect(HistoryMetric.allCases.contains(.cpuPower) && HistoryMetric.allCases.contains(.cpuClock),
                     "the History metric menu lists package power and clock")
        suite.expect(HistoryMetric.cpuPower.series == [.cpuPower] && HistoryMetric.cpuClock.series == [.cpuClock],
                     "each chart metric reads its own series")
        suite.expect(HistoryMetric.allCases.map(\.rawValue).count == Set(HistoryMetric.allCases.map(\.rawValue)).count,
                     "the stored History metric names stay unique")
        for language in AppLanguage.allCases {
            let strings = MonitorWindowStrings.localized(language)
            suite.expect(!strings.cpuPower.isEmpty && !strings.cpuClock.isEmpty
                         && strings.cpuPower != strings.systemPower && strings.cpuPower != strings.cpuClock,
                         "\(language.rawValue) names package power and clock apart from system power")
            if language != .enUS {
                let english = MonitorWindowStrings.localized(.enUS)
                suite.expect(strings.cpuPower != english.cpuPower && strings.cpuClock != english.cpuClock,
                             "\(language.rawValue) translates package power and clock")
            }
        }
    }
}
