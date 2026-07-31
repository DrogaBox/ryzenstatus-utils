// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Step-change footprint detector to distinguish intentional document loads from continuous leaks.
final class ChangeDetector: @unchecked Sendable {
    static let shared = ChangeDetector()

    private var previousFootprints: [pid_t: Int64] = [:]
    private let lock = NSLock()

    private init() {}

    /// Detects a sudden step-change jump in RAM footprint (e.g., > 100 MB jump in a single sample).
    func detectStepChange(pid: pid_t, currentBytes: Int64, thresholdMB: Double = 100.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let prev = previousFootprints[pid] else {
            previousFootprints[pid] = currentBytes
            return false
        }
        previousFootprints[pid] = currentBytes

        let deltaMB = Double(currentBytes - prev) / 1_048_576.0
        return deltaMB >= thresholdMB
    }

    func clear(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        previousFootprints.removeValue(forKey: pid)
    }
}
