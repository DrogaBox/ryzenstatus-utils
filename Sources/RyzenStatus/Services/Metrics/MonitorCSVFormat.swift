// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// RFC 4180 CSV: comma separated, CRLF line ends, a field quoted only when
/// it holds a comma, a quote or a line break, and numbers always written
/// with "." whatever the user's locale, so a spreadsheet in any language
/// reads the same file. A missing reading is an empty field, never 0.
enum CSVFormat {
    static let lineEnd = "\r\n"
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + lineEnd
    }

    static func number(_ value: Double?, decimals: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(max(0, decimals))f", locale: posix, value)
    }

    /// ISO 8601 with the local offset, "2026-11-21T14:05:09-03:00".
    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// One reading of the continuous log, taken from the monitor's snapshot.
struct MonitorCSVSample {
    var time: Date
    var cpuUsage: Double?        // 0...1
    var cpuTemperature: Double?  // °C
    var cpuPower: Double?        // W
    var averageClock: Double?    // MHz
    var epp: UInt8?
    var gpuTemperature: Double?  // °C
    var gpuPower: Double?        // W
    /// RPM by fan id; a fan missing here or with a bad tachometer is nil.
    var fanRPM: [Int: Double] = [:]
}

/// The continuous log's fixed columns. The fan columns are the fans the Mac
/// reported when the log started, so every row has the same shape even if
/// a fan drops out later (its field is then empty).
struct MonitorCSVLayout {
    struct Fan: Equatable {
        let id: Int
        let label: String
    }

    let fans: [Fan]
    var timeZone: TimeZone = .current

    static let fixedHeader = [
        "Time", "CPU (%)", "CPU temperature (°C)", "CPU package power (W)",
        "CPU average clock (MHz)", "EPP", "GPU temperature (°C)", "GPU power (W)",
    ]

    var header: String {
        CSVFormat.row(Self.fixedHeader + fans.map { "\($0.label) (RPM)" })
    }

    func row(_ sample: MonitorCSVSample) -> String {
        var fields = [
            CSVFormat.timestamp(sample.time, timeZone: timeZone),
            CSVFormat.number(sample.cpuUsage.map { $0 * 100 }, decimals: 1),
            CSVFormat.number(sample.cpuTemperature, decimals: 1),
            CSVFormat.number(sample.cpuPower, decimals: 2),
            CSVFormat.number(sample.averageClock, decimals: 0),
            sample.epp.map(String.init) ?? "",
            CSVFormat.number(sample.gpuTemperature, decimals: 1),
            CSVFormat.number(sample.gpuPower, decimals: 2),
        ]
        fields += fans.map { CSVFormat.number(sample.fanRPM[$0.id], decimals: 0) }
        return CSVFormat.row(fields)
    }
}

/// A slice of the long history laid out for export: one row per slot of
/// the ring it came from, one column per metric.
struct LongHistoryTable {
    /// Seconds per row: the ring's step.
    let step: TimeInterval
    /// Start of each row's slot, oldest first.
    let times: [TimeInterval]
    /// Per metric, the slot means aligned with `times`; nil where empty.
    let columns: [(metric: LongHistoryMetric, values: [Float?])]

    static func header(for metric: LongHistoryMetric) -> String {
        switch metric {
        case .cpu: return "CPU (%)"
        case .gpu: return "GPU (%)"
        case .memory: return "Memory (%)"
        case .networkDown: return "Network down (B/s)"
        case .networkUp: return "Network up (B/s)"
        case .diskRead: return "Disk read (B/s)"
        case .diskWrite: return "Disk write (B/s)"
        case .cpuTemperature: return "CPU temperature (°C)"
        case .gpuTemperature: return "GPU temperature (°C)"
        case .systemPower: return "System power (W)"
        case .gpuMemoryTemperature: return "VRAM temperature (°C)"
        case .cpuPower: return "CPU package power (W)"
        case .cpuClock: return "CPU average clock (MHz)"
        }
    }

    /// Stored value → exported figure and its decimals: usage is kept as
    /// 0...1 and written as a percentage.
    static func format(_ value: Float?, for metric: LongHistoryMetric) -> String {
        guard let value else { return "" }
        switch metric {
        case .cpu, .gpu, .memory:
            return CSVFormat.number(Double(value) * 100, decimals: 1)
        case .networkDown, .networkUp, .diskRead, .diskWrite:
            return CSVFormat.number(Double(value), decimals: 0)
        case .cpuTemperature, .gpuTemperature, .gpuMemoryTemperature:
            return CSVFormat.number(Double(value), decimals: 1)
        case .systemPower, .cpuPower:
            return CSVFormat.number(Double(value), decimals: 2)
        case .cpuClock:
            return CSVFormat.number(Double(value), decimals: 0)
        }
    }

    /// The table as CSV. Only metrics with at least one reading get a
    /// column, and a row where every column is empty (the app was not
    /// running) is left out.
    func csv(timeZone: TimeZone = .current) -> String {
        let kept = columns.filter { $0.values.contains { $0 != nil } }
        var out = CSVFormat.row(["Time"] + kept.map { Self.header(for: $0.metric) })
        for (index, time) in times.enumerated() {
            let fields = kept.map { column -> String in
                index < column.values.count ? Self.format(column.values[index], for: column.metric) : ""
            }
            guard fields.contains(where: { !$0.isEmpty }) else { continue }
            out += CSVFormat.row([CSVFormat.timestamp(Date(timeIntervalSince1970: time), timeZone: timeZone)] + fields)
        }
        return out
    }
}
