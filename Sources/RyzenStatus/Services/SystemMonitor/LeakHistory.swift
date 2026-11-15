// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// A process's physical footprint: the memory it really holds, the figure
/// Activity Monitor shows as Memory. Resident size is not that: it also
/// counts pages the process has already freed and the system has not taken
/// back yet, so a process that allocates and frees a lot shows a resident
/// size that climbs for hours while it leaks nothing.
enum ProcessFootprint {
    /// Nil for a process that has gone or belongs to another user: those do
    /// not answer without privileges.
    static func bytes(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            let rebound = raw.bindMemory(to: (rusage_info_t?).self, capacity: 1)
            return proc_pid_rusage(pid, RUSAGE_INFO_V2, rebound)
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return info.ri_phys_footprint
    }
}

/// The memory series the leak detector reads, one per app, over the last
/// half hour. A leak shows over twenty minutes, so one sample every ten
/// seconds says as much as one a second, and keeps each series under two
/// hundred points instead of rebuilding thousands of them on every refresh
/// of the process list.
struct LeakHistory {
    static let window: TimeInterval = 1800
    static let sampleInterval: TimeInterval = 10

    private(set) var series: [pid_t: [(Date, UInt64)]] = [:]
    private var lastSample: Date?

    /// Whether enough time has passed for another sample.
    func isDue(at now: Date) -> Bool {
        guard let lastSample else { return true }
        let elapsed = now.timeIntervalSince(lastSample)
        // A clock set back must not stop the sampling for good.
        return elapsed >= Self.sampleInterval || elapsed < 0
    }

    /// Adds one reading per app, drops what is older than the window and
    /// forgets the apps that are no longer running.
    mutating func record(_ memory: [pid_t: UInt64], at now: Date) {
        lastSample = now
        let cutoff = now.addingTimeInterval(-Self.window)
        for (pid, bytes) in memory {
            series[pid, default: []].append((now, bytes))
            if let stale = series[pid]?.firstIndex(where: { $0.0 >= cutoff }), stale > 0 {
                series[pid]?.removeFirst(stale)
            }
        }
        let gone = series.keys.filter { memory[$0] == nil }
        for pid in gone { series[pid] = nil }
    }
}
