// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Filters high temperature alerts so a transient single-core boost spike on
/// AMD Ryzen does not trigger a notification when the CPU cools right back down.
///
/// Time handling uses `ProcessInfo.processInfo.systemUptime` (monotonic,
/// unaffected by NTP adjustments or sleep/wake clock jumps). Wall-clock
/// `Date()` timestamps would violate the `readAt` monotonicity check and can
/// fire alerts immediately after a clock change.
struct TemperatureAlertGate {
    /// How long the temperature must stay at or above the threshold before an alert fires.
    private let window: TimeInterval
    private let hysteresis: Double
    private var hotSince: TimeInterval?
    private var lastReadingAt: TimeInterval?
    private var armed: Bool = true

    init(window: TimeInterval = 10, hysteresis: Double = 5) {
        self.window = window
        self.hysteresis = hysteresis
    }

    /// Evaluates a new temperature reading against the alert threshold.
    ///
    /// `readAt` and the optional `now` must come from a monotonic clock
    /// (`ProcessInfo.processInfo.systemUptime`) — never from `Date()`.
    mutating func shouldAlert(temperature: Double?,
                              threshold: Double,
                              readAt: TimeInterval?,
                              now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
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
            if now - hotSince >= window {
                armed = false
                return true
            }
            return false
        }
        
        lastReadingAt = readAt
        if let hotSince {
            if now - hotSince >= window {
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
