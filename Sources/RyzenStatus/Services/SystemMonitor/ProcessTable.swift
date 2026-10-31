// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// One line of `ps -eo pid,ppid,pcpu,rss,comm`: the one process listing the
/// process manager (KillProcessService) and the dashboards' rankings
/// (ProcessUsageService) both read, so the two never disagree on a number.
struct PSProcessRow: Equatable {
    let pid: pid_t
    let ppid: pid_t
    /// `ps`'s %cpu, on the per-core scale: a busy multi-threaded process can
    /// pass 100.
    let cpuPercent: Double
    /// Resident memory in bytes (`ps` reports KiB).
    let rssBytes: Double
    /// The full executable path; it may contain spaces.
    let commandPath: String

    var shortName: String {
        commandPath.contains("/") ? (commandPath as NSString).lastPathComponent : commandPath
    }
}

enum ProcessTable {
    static let psArguments = ["-eo", "pid,ppid,pcpu,rss,comm"]

    /// Lines look like "  437     1  12.5  20480 /System/Library/.../WindowServer".
    /// The header and malformed lines are skipped, never read as zeros; a
    /// comma decimal (some locales) reads like a point.
    static func parse(_ output: String) -> [PSProcessRow] {
        var rows: [PSProcessRow] = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard columns.count == 5,
                  let pid = pid_t(columns[0]), pid > 0,
                  let ppid = pid_t(columns[1]),
                  let cpu = number(columns[2]), cpu >= 0
            else { continue }
            let commandPath = String(columns[4]).trimmingCharacters(in: .whitespaces)
            guard !commandPath.isEmpty else { continue }
            rows.append(PSProcessRow(pid: pid,
                                     ppid: ppid,
                                     cpuPercent: cpu,
                                     rssBytes: max(0, number(columns[3]) ?? 0) * 1024,
                                     commandPath: commandPath))
        }
        return rows
    }

    private static func number(_ text: Substring) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
