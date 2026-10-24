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
}

enum NotchCapsuleCenterSupport {
    /// How long a rotating middle keeps each reading.
    static let rotationPeriod: TimeInterval = 6
    /// How long the AMD telemetry carousel keeps each reading.
    static let carouselPeriod: TimeInterval = 3.5
    /// Readings change width as their digits do. The capsule grows in steps
    /// this wide, so a counting number does not resize it every second.
    static let widthStep: CGFloat = 12

    static func song(title: String?, artist: String?) -> String? {
        let parts = [title, artist].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func metric(_ metric: NotchCapsuleMetric, snapshot: SystemSnapshot, unit: TemperatureUnit) -> String? {
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
                return String(format: "Boost %.2f GHz", peak / 1000.0)
            } else if let avg = snapshot.avgCPUFreq, avg > 0 {
                return String(format: "Clock %.2f GHz", avg / 1000.0)
            } else if let last = snapshot.cpuFreqHistory.last, last > 0 {
                return String(format: "Clock %.2f GHz", last)
            }
            return nil
        case .fanSpeed:
            if let fan = snapshot.gpuFan, fan > 0 {
                return String(format: "Fan %.0f RPM", fan)
            }
            return nil
        }
    }

    static func clock(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                     now: Date) -> String? {
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
                if let temp = s.cpuTemperature {
                    readings.append("CPU " + MetricFormat.temperatureCompact(temp, unit: unit))
                }
                if let power = s.cpuPower, power > 0 {
                    readings.append(String(format: "PPT %.0fW", power))
                }
                if let peak = s.peakCPUFreq, peak > 0 {
                    readings.append(String(format: "Boost %.2f GHz", peak / 1000.0))
                } else if let last = s.cpuFreqHistory.last, last > 0 {
                    readings.append(String(format: "Clock %.2f GHz", last))
                }
                if let fan = s.gpuFan, fan > 0 {
                    readings.append(String(format: "Fan %.0f RPM", fan))
                }
                if let used = s.memoryUsed, let total = s.memoryTotal, total > 0 {
                    readings.append("RAM " + MetricFormat.percent(Double(used) / Double(total)))
                }
                if let gpuTemp = s.gpuTemperature {
                    readings.append("GPU " + MetricFormat.temperatureCompact(gpuTemp, unit: unit))
                }
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
