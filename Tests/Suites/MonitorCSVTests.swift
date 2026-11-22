// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum MonitorCSVTests {
    static func run(_ suite: TestSuite) {
        quoting(suite)
        numbers(suite)
        timestamps(suite)
        logRows(suite)
        snapshotSample(suite)
        historyExport(suite)
        fileNames(suite)
        writer(suite)
    }

    private static let utcMinus3 = TimeZone(secondsFromGMT: -3 * 3600)!

    private static func quoting(_ suite: TestSuite) {
        suite.expect(CSVFormat.field("plain") == "plain", "a plain field is not quoted")
        suite.expect(CSVFormat.field("a,b") == "\"a,b\"", "a comma is quoted")
        suite.expect(CSVFormat.field("say \"hi\"") == "\"say \"\"hi\"\"\"", "a quote is doubled inside quotes")
        suite.expect(CSVFormat.field("two\nlines") == "\"two\nlines\"", "a line break is quoted")
        suite.expect(CSVFormat.field("") == "", "an empty field stays empty")
        suite.expect(CSVFormat.row(["a", "b,c", ""]) == "a,\"b,c\",\r\n", "a row joins with commas and ends in CRLF")
    }

    private static func numbers(_ suite: TestSuite) {
        suite.expect(CSVFormat.number(1234.5678, decimals: 2) == "1234.57", "a number rounds to its decimals")
        suite.expect(CSVFormat.number(nil, decimals: 1) == "", "a missing value is an empty field")
        suite.expect(CSVFormat.number(.nan, decimals: 1) == "", "NaN is an empty field")
        suite.expect(CSVFormat.number(.infinity, decimals: 1) == "", "infinity is an empty field")
        suite.expect(CSVFormat.number(3.0, decimals: 0) == "3", "no decimals writes an integer")
        suite.expect(!CSVFormat.number(1_000_000.25, decimals: 2).contains(","), "no thousands separator")
        // The same figure through a German formatter shows why the locale is
        // pinned: the field must read "0.5" whatever the user's region.
        suite.expect(String(format: "%.1f", locale: Locale(identifier: "de_DE"), 0.5) == "0,5",
                     "a German locale would write a decimal comma")
        suite.expect(CSVFormat.number(0.5, decimals: 1) == "0.5", "the CSV keeps \".\" as the decimal separator")
    }

    private static func timestamps(_ suite: TestSuite) {
        // 2026-11-21 17:05:09 UTC
        let date = Date(timeIntervalSince1970: 1_795_280_709)
        suite.expect(CSVFormat.timestamp(date, timeZone: utcMinus3) == "2026-11-21T14:05:09-03:00",
                     "ISO 8601 local time with its offset, got \(CSVFormat.timestamp(date, timeZone: utcMinus3))")
        suite.expect(CSVFormat.timestamp(date, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-11-21T17:05:09Z",
                     "UTC is written with Z")
    }

    private static func logRows(_ suite: TestSuite) {
        let layout = MonitorCSVLayout(fans: [.init(id: 0, label: "CPU, front"), .init(id: 3, label: "Pump")],
                                      timeZone: utcMinus3)
        suite.expect(layout.header == "Time,CPU (%),CPU temperature (°C),CPU package power (W),"
                     + "CPU average clock (MHz),EPP,GPU temperature (°C),GPU power (W),"
                     + "\"CPU, front (RPM)\",Pump (RPM)\r\n",
                     "the header has the fixed columns, then one quoted-if-needed column per fan")
        let full = MonitorCSVSample(time: Date(timeIntervalSince1970: 1_795_280_709),
                                    cpuUsage: 0.4567, cpuTemperature: 61.24, cpuPower: 88.456,
                                    averageClock: 4512.4, epp: 128, gpuTemperature: 55.0,
                                    gpuPower: 120.5, fanRPM: [0: 1210, 3: 2400])
        suite.expect(layout.row(full) == "2026-11-21T14:05:09-03:00,45.7,61.2,88.46,4512,128,55.0,120.50,1210,2400\r\n",
                     "a full row, got \(layout.row(full))")
        let sparse = MonitorCSVSample(time: Date(timeIntervalSince1970: 1_795_280_710), cpuUsage: 0.1)
        suite.expect(layout.row(sparse) == "2026-11-21T14:05:10-03:00,10.0,,,,,,,,\r\n",
                     "missing readings and fans are empty fields, got \(layout.row(sparse))")
        let header = layout.header.split(separator: ",", omittingEmptySubsequences: false).count
        let row = layout.row(sparse).split(separator: ",", omittingEmptySubsequences: false).count
        suite.expect(header == row + 1, "every row has as many fields as the header (one header label holds a comma)")
        let noFans = MonitorCSVLayout(fans: [], timeZone: utcMinus3)
        suite.expect(noFans.header.hasSuffix("GPU power (W)\r\n"), "without fans the header ends at GPU power")
    }

    private static func snapshotSample(_ suite: TestSuite) {
        var snapshot = SystemSnapshot()
        snapshot.cpuUsage = 0.25
        snapshot.cpuTemperature = 50
        snapshot.cpuPower = 40
        snapshot.avgCPUFreq = 3600
        snapshot.gpuTemperature = 45
        snapshot.gpuPower = 30
        let good = FanState(id: 1, name: "CPU", rpm: 900, throttlePWM: 100, isKextAuto: true, controlMode: .auto)
        let bad = FanState(id: 2, name: "SYS", rpm: 65_000, throttlePWM: 0, isKextAuto: true, controlMode: .auto,
                           rpmValid: false)
        let sample = MonitorCSVLogger.sample(from: snapshot, fans: [good, bad], epp: nil)
        suite.expect(sample.cpuUsage == 0.25 && sample.averageClock == 3600 && sample.gpuPower == 30,
                     "the sample reads the monitor snapshot")
        suite.expect(sample.fanRPM[1] == 900, "a fan's RPM is taken")
        suite.expect(sample.fanRPM[2] == nil, "a fan with a bad tachometer is left empty")
        suite.expect(sample.epp == nil, "an unknown EPP stays unknown")
    }

    private static func historyExport(_ suite: TestSuite) {
        let step: TimeInterval = 60
        var tiers = LongHistoryMetric.allCases.map { _ in LongHistoryTier(step: step, capacity: 100) }
        let end: TimeInterval = 1_795_280_700 // on a minute boundary
        tiers[LongHistoryMetric.cpu.rawValue].record(0.5, at: end - 120)
        tiers[LongHistoryMetric.cpu.rawValue].record(0.25, at: end)
        tiers[LongHistoryMetric.cpuTemperature.rawValue].record(60.04, at: end)
        let table = LongHistoryStore.table(tiers: tiers, step: step, duration: 600, end: end)
        suite.expect(table.times.count == 10, "a 10-minute range at 1-minute steps has 10 rows")
        suite.expect(table.times.last == end && table.times.first == end - 540, "rows run oldest first up to the end slot")
        suite.expect(table.columns.count == LongHistoryMetric.allCases.count, "one column per metric")
        let csv = table.csv(timeZone: TimeZone(secondsFromGMT: 0)!)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        suite.expect(lines.first == "Time,CPU (%),CPU temperature (°C)",
                     "only metrics with readings get a column, got \(lines.first ?? "")")
        suite.expect(lines.count == 3, "rows with no readings are left out, got \(lines.count - 1) rows")
        suite.expect(lines.dropFirst().first == "2026-11-21T17:03:00Z,50.0,", "a row with one reading leaves the other empty")
        suite.expect(lines.last == "2026-11-21T17:05:00Z,25.0,60.0", "usage is a percentage, temperature in °C")
        suite.expect(LongHistoryTable.format(1_234_567, for: .networkDown) == "1234567", "traffic is whole bytes per second")
        suite.expect(LongHistoryTable.format(12.345, for: .systemPower) == "12.35", "power keeps two decimals")
        suite.expect(LongHistoryTable.format(nil, for: .gpu) == "", "an empty slot is an empty field")

        let store = LongHistoryStore(fileURL: nil, now: end)
        store.record(.gpu, 0.75, at: end - 10)
        let fine = store.exportTable(range: .tenMinutes, end: end)
        suite.expect(fine.step == LongHistoryStore.fineStep && fine.times.count == 120,
                     "ten minutes comes from the five-second ring")
        let coarse = store.exportTable(range: .oneDay, end: end)
        suite.expect(coarse.step == LongHistoryStore.coarseStep && coarse.times.count == 1440,
                     "a day comes from the minute ring")
        suite.expect(fine.csv().contains("75.0") && coarse.csv().contains("75.0"), "both rings hold the reading")
    }

    private static func fileNames(_ suite: TestSuite) {
        let date = Date(timeIntervalSince1970: 1_795_280_709)
        suite.expect(MonitorCSVLogger.defaultFileName(date: date, timeZone: utcMinus3) == "RyzenStatus-2026-11-21.csv",
                     "the log's default name carries the date")
        suite.expect(MonitorCSVLogger.defaultFileName(prefix: "RyzenStatus-History", date: date, timeZone: utcMinus3)
                     == "RyzenStatus-History-2026-11-21.csv", "the export's default name carries the date")
    }

    private static func writer(_ suite: TestSuite) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryzenstatus-csv-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("old contents\n".utf8).write(to: url)
        let writer = CSVAppendWriter()
        let opened = DispatchSemaphore(value: 0)
        let result = OSAllocatedFlag()
        writer.open(url) { ok in result.set(ok); opened.signal() }
        opened.wait()
        suite.expect(result.value, "the writer opens the chosen file")
        writer.append("a,b\r\n") { _ in }
        writer.append("1,2\r\n") { _ in }
        writer.close(synchronously: true)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        suite.expect(text == "a,b\r\n1,2\r\n", "rows are appended in order and a replaced file starts empty, got \(text)")

        let missing = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/log.csv")
        let failed = DispatchSemaphore(value: 0)
        let failure = OSAllocatedFlag()
        failure.set(true)
        writer.open(missing) { ok in failure.set(ok); failed.signal() }
        failed.wait()
        suite.expect(!failure.value, "a file that cannot be created reports failure")
    }
}

/// A Bool the writer's queue sets and the test reads after a semaphore.
private final class OSAllocatedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set(_ new: Bool) { lock.withLock { stored = new } }
}
