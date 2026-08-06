// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Filters high temperature alerts so a transient single-core boost spike on
/// AMD Ryzen does not trigger a notification when the CPU cools right back down.
struct TemperatureAlertGate {
    /// How long the temperature must stay at or above the threshold before an alert fires.
    private let window: TimeInterval
    private var hotSince: Date?
    private var lastReadingAt: TimeInterval?

    init(window: TimeInterval = 10) {
        self.window = window
    }

    /// Evaluates a new temperature reading against the alert threshold.
    mutating func shouldAlert(temperature: Double?,
                              threshold: Double,
                              readAt: TimeInterval?,
                              now: Date = Date()) -> Bool {
        guard let temperature, temperature >= threshold, let readAt else {
            hotSince = nil
            lastReadingAt = nil
            return false
        }
        if lastReadingAt == readAt {
            guard let hotSince else { return false }
            return now.timeIntervalSince(hotSince) >= window
        }
        lastReadingAt = readAt
        if let hotSince {
            return now.timeIntervalSince(hotSince) >= window
        } else {
            hotSince = now
            return false
        }
    }

    mutating func reset() {
        hotSince = nil
        lastReadingAt = nil
    }
}
