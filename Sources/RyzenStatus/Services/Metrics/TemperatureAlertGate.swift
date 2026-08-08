// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Filters high temperature alerts so a transient single-core boost spike on
/// AMD Ryzen does not trigger a notification when the CPU cools right back down.
struct TemperatureAlertGate {
    /// How long the temperature must stay at or above the threshold before an alert fires.
    private let window: TimeInterval
    private let hysteresis: Double
    private var hotSince: Date?
    private var lastReadingAt: TimeInterval?
    private var armed: Bool = true

    init(window: TimeInterval = 10, hysteresis: Double = 5) {
        self.window = window
        self.hysteresis = hysteresis
    }

    /// Evaluates a new temperature reading against the alert threshold.
    mutating func shouldAlert(temperature: Double?,
                              threshold: Double,
                              readAt: TimeInterval?,
                              now: Date = Date()) -> Bool {
        guard let temperature, let readAt else {
            reset()
            return false
        }
        
        if temperature < threshold {
            hotSince = nil
            lastReadingAt = nil
            if temperature <= threshold - hysteresis {
                armed = true
            }
            return false
        }

        if !armed {
            return false
        }

        if let last = lastReadingAt, readAt <= last {
            guard let hotSince else { return false }
            if now.timeIntervalSince(hotSince) >= window {
                armed = false
                return true
            }
            return false
        }
        
        lastReadingAt = readAt
        if let hotSince {
            if now.timeIntervalSince(hotSince) >= window {
                armed = false
                return true
            }
            return false
        } else {
            hotSince = now
            return false
        }
    }

    mutating func reset() {
        hotSince = nil
        lastReadingAt = nil
        armed = true
    }
}
