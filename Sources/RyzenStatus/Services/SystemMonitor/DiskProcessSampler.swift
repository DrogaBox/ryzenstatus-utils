// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// Bytes a process has read from and written to storage since it started.
struct DiskProcessTotals: Equatable {
    var read: UInt64
    var written: UInt64
}

/// Per-process disk throughput between two readings of the cumulative
/// counters. A process seen for the first time, or whose counters went back
/// (its pid was reused), has no rate until the next reading.
struct DiskProcessDeltaTracker {
    private var previous: [pid_t: DiskProcessTotals] = [:]
    private var previousTime: TimeInterval?

    /// Read and write rates in bytes per second since the last call, or nil on
    /// the first call and when no time has passed.
    mutating func rates(_ totals: [pid_t: DiskProcessTotals],
                        at time: TimeInterval) -> [pid_t: (read: Double, write: Double)]? {
        defer {
            previous = totals
            previousTime = time
        }
        guard let previousTime, time > previousTime else { return nil }
        let elapsed = time - previousTime
        var rates: [pid_t: (read: Double, write: Double)] = [:]
        for (pid, now) in totals {
            guard let before = previous[pid], now.read >= before.read, now.written >= before.written else { continue }
            let read = Double(now.read - before.read) / elapsed
            let write = Double(now.written - before.written) / elapsed
            if read > 0 || write > 0 {
                rates[pid] = (read, write)
            }
        }
        return rates
    }
}

/// Reads every process's storage counters from `proc_pid_rusage`. Processes
/// of other users (root daemons) do not answer without privileges and are
/// left out, as `ps` leaves out their footprint.
enum DiskProcessSampler {
    static func totals() -> [pid_t: DiskProcessTotals] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [:] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [:] }
        var totals: [pid_t: DiskProcessTotals] = [:]
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                let raw = UnsafeMutableRawPointer(pointer)
                let rebound = raw.bindMemory(to: (rusage_info_t?).self, capacity: 1)
                return proc_pid_rusage(pid, RUSAGE_INFO_V2, rebound)
            }
            guard status == 0 else { continue }
            totals[pid] = DiskProcessTotals(read: info.ri_diskio_bytesread, written: info.ri_diskio_byteswritten)
        }
        return totals
    }

    /// The process's short name, or nil when it has gone.
    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
