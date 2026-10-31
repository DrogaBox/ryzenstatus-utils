// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What a capsule shows in its middle while the music strip is closed. A
/// notched Mac keeps its camera there; a capsule has none, so the room can
/// carry a reading instead of staying empty.
enum NotchCapsuleCenter: String, CaseIterable {
    /// Nothing, and the capsule shrinks to its cover and bars.
    case none
    case song, metric, rotate, clock, carousel

    static func current(_ defaults: UserDefaults = .standard) -> NotchCapsuleCenter {
        NotchCapsuleCenter(rawValue: defaults.string(forKey: DefaultsKey.notchCapsuleCenter) ?? "") ?? .song
    }
}

/// The reading a capsule's middle shows when it shows a metric.
enum NotchCapsuleMetric: String, CaseIterable {
    case cpuTemperature, cpuUsage, gpuTemperature, memory, network, cpuPower, peakFrequency, fanSpeed

    static func current(_ defaults: UserDefaults = .standard) -> NotchCapsuleMetric {
        NotchCapsuleMetric(rawValue: defaults.string(forKey: DefaultsKey.notchCapsuleMetric) ?? "") ?? .cpuTemperature
    }

    static func currentList(_ defaults: UserDefaults = .standard) -> [NotchCapsuleMetric] {
        if let stored = defaults.stringArray(forKey: DefaultsKey.notchCapsuleSelectedMetrics), !stored.isEmpty {
            let parsed = stored.compactMap { NotchCapsuleMetric(rawValue: $0) }
            if !parsed.isEmpty { return parsed }
        }
        return [current(defaults)]
    }

    static func carouselList(_ defaults: UserDefaults = .standard) -> [NotchCapsuleMetric] {
        if let stored = defaults.stringArray(forKey: DefaultsKey.notchCapsuleCarouselMetrics), !stored.isEmpty {
            let parsed = stored.compactMap { NotchCapsuleMetric(rawValue: $0) }
            if !parsed.isEmpty { return parsed }
        }
        return [.cpuTemperature, .cpuPower, .peakFrequency, .fanSpeed, .memory, .gpuTemperature]
    }
}

enum NotchCapsuleCenterSupport {
    /// How long a rotating middle keeps each reading.
    static let rotationPeriod: TimeInterval = 6
    /// How long the AMD telemetry carousel keeps each reading.
    static let carouselPeriod: TimeInterval = 3.5
    /// Readings change width as their digits do. The capsule grows in steps
    /// this wide, so a counting number does not resize it every second.
    static let widthStep: CGFloat = 12

    /// Whether the once-a-second reading runs: something to show, an island
    /// that runs and can present, and a capsule that shows it.
    static func runsTimer(center: NotchCapsuleCenter, running: Bool, suspended: Bool, capsuleShows: Bool) -> Bool {
        center != .none && running && !suspended && capsuleShows
    }

    static func song(title: String?, artist: String?) -> String? {
        let parts = [title, artist].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func metric(_ metric: NotchCapsuleMetric, snapshot: SystemSnapshot, unit: TemperatureUnit,
                       strings: NotchCapsuleCenterStrings = FeatureStrings.notchCapsuleCenter(.enUS)) -> String? {
        switch metric {
        case .cpuTemperature:
            return snapshot.cpuTemperature.map { "CPU " + MetricFormat.temperatureCompact($0, unit: unit) }
        case .cpuUsage:
            return snapshot.cpuUsage.map { "CPU " + MetricFormat.percent($0) }
        case .gpuTemperature:
            return snapshot.gpuTemperature.map { "GPU " + MetricFormat.temperatureCompact($0, unit: unit) }
        case .memory:
            guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return nil }
            return "RAM " + MetricFormat.percent(Double(used) / Double(total))
        case .network:
            return snapshot.netDownBytesPerSec.map { "↓ " + MetricFormat.networkRateCompact($0) }
        case .cpuPower:
            return snapshot.cpuPower.map { String(format: "PPT %.0fW", $0) }
        case .peakFrequency:
            if let peak = snapshot.peakCPUFreq, peak > 0 {
                return String(format: strings.boostReading, peak / 1000.0)
            } else if let avg = snapshot.avgCPUFreq, avg > 0 {
                return String(format: strings.clockReading, avg / 1000.0)
            } else if let last = snapshot.cpuFreqHistory.last, last > 0 {
                return String(format: strings.clockReading, last)
            }
            return nil
        case .fanSpeed:
            if let fan = snapshot.gpuFan, fan > 0 {
                return String(format: strings.fanReading, fan)
            }
            return nil
        }
    }

    /// Formats multiple metrics side by side separated by " · ".
    static func multiMetric(_ metrics: [NotchCapsuleMetric], snapshot: SystemSnapshot, unit: TemperatureUnit,
                            strings: NotchCapsuleCenterStrings = FeatureStrings.notchCapsuleCenter(.enUS)) -> String? {
        let parts = metrics.compactMap { metric($0, snapshot: snapshot, unit: unit, strings: strings) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Read once a second: a format style, not a new formatter each time.
    static func clock(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
    }

    /// The middle's text, or nil when it has nothing to show. A rotating
    /// middle takes turns between the song and the metric, and keeps to
    /// whichever of them has a reading.
    static func text(center: NotchCapsuleCenter, song: String?, metric: String?, clock: String,
                     now: Date) -> String? {
        text(center: center, song: song, metric: metric, clock: clock, snapshot: nil, unit: .celsius, now: now)
    }

    static func text(center: NotchCapsuleCenter, song: String?, metric: String?, clock: String,
                     snapshot: SystemSnapshot?, unit: TemperatureUnit,
                     carouselMetrics: [NotchCapsuleMetric]? = nil,
                     now: Date,
                     strings: NotchCapsuleCenterStrings = FeatureStrings.notchCapsuleCenter(.enUS)) -> String? {
        switch center {
        case .none: return nil
        case .song: return song
        case .metric: return metric
        case .clock: return clock
        case .rotate:
            let readings = [song, metric].compactMap { $0 }
            guard !readings.isEmpty else { return nil }
            let turn = Int((now.timeIntervalSinceReferenceDate / rotationPeriod).rounded(.down))
            return readings[((turn % readings.count) + readings.count) % readings.count]
        case .carousel:
            var readings: [String] = []
            if let s = snapshot {
                let items = carouselMetrics ?? NotchCapsuleMetric.carouselList()
                readings = items.compactMap { self.metric($0, snapshot: s, unit: unit, strings: strings) }
            }
            if readings.isEmpty {
                if let m = metric { readings.append(m) }
                if let s = song { readings.append(s) }
                readings.append(clock)
            }
            let turn = Int((now.timeIntervalSinceReferenceDate / carouselPeriod).rounded(.down))
            return readings[((turn % readings.count) + readings.count) % readings.count]
        }
    }

    /// The width the middle reserves for `text`, rounded up to a whole step.
    static func reservedWidth(_ text: String?, measure: (String) -> CGFloat) -> CGFloat {
        guard let text, !text.isEmpty else { return 0 }
        return (measure(text) / widthStep).rounded(.up) * widthStep
    }
}
