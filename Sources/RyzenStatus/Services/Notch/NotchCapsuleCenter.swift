// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What a capsule shows in its middle while the music strip is closed. A
/// notched Mac keeps its camera there; a capsule has none, so the room can
/// carry a reading instead of staying empty.
enum NotchCapsuleCenter: String, CaseIterable {
    /// Nothing, and the capsule shrinks to its cover and bars.
    case none
    case song, metric, rotate, clock

    static func current(_ defaults: UserDefaults = .standard) -> NotchCapsuleCenter {
        NotchCapsuleCenter(rawValue: defaults.string(forKey: DefaultsKey.notchCapsuleCenter) ?? "") ?? .song
    }
}

/// The reading a capsule's middle shows when it shows a metric.
enum NotchCapsuleMetric: String, CaseIterable {
    case cpuTemperature, cpuUsage, gpuTemperature, memory, network

    static func current(_ defaults: UserDefaults = .standard) -> NotchCapsuleMetric {
        NotchCapsuleMetric(rawValue: defaults.string(forKey: DefaultsKey.notchCapsuleMetric) ?? "") ?? .cpuTemperature
    }
}

enum NotchCapsuleCenterSupport {
    /// How long a rotating middle keeps each reading.
    static let rotationPeriod: TimeInterval = 6
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
        }
    }

    /// The width the middle reserves for `text`, rounded up to a whole step.
    static func reservedWidth(_ text: String?, measure: (String) -> CGFloat) -> CGFloat {
        guard let text, !text.isEmpty else { return 0 }
        return (measure(text) / widthStep).rounded(.up) * widthStep
    }
}
