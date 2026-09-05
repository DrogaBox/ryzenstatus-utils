// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Pure C6 residency sampling math, extracted from C6ResidencyService.poll()
/// (AUDIT F-28) so it can be unit tested without a kext connection.
enum C6Sampling {
    /// Folds one kext sample into the baseline state.
    /// - Parameters:
    ///   - raw: cumulative C6 residency counter in microseconds (kext selector 31)
    ///   - now: sample timestamp (`ProcessInfo.processInfo.systemUptime`)
    ///   - lastRaw/lastTimestamp: previous baseline (0/0 = no baseline yet)
    /// - Returns: `(pct, lastRaw, lastTimestamp)` — `pct` is nil when the window
    ///   isn't ready (first sample, counter reset, or no counter); the returned
    ///   baseline is always the state to store.
    static func sample(raw: UInt64, now: TimeInterval,
                       lastRaw: UInt64, lastTimestamp: TimeInterval)
        -> (pct: Double?, lastRaw: UInt64, lastTimestamp: TimeInterval) {
        guard raw > 0 else { return (nil, 0, 0) }                  // no counter
        if lastRaw > 0 && raw < lastRaw { return (nil, raw, now) } // counter reset
        var pct: Double? = nil
        if lastRaw > 0 && lastTimestamp > 0 {
            let deltaUs = Double(raw - lastRaw)
            let elapsedUs = (now - lastTimestamp) * 1_000_000
            if elapsedUs > 0 { pct = min(100, max(0, (deltaUs / elapsedUs) * 100.0)) }
        }
        return (pct, raw, now)
    }
}
