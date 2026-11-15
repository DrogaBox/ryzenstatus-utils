// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What AMDCCDScheduler.kext reports through `sysctl debug.ccd_stat`.
/// The kext keeps the threads of one process on one CCD (one L3); see
/// docs/CCD_SCHEDULER.md. Parsing is pure so `./build.sh --test` covers it.
struct CCDSchedulerStatus: Equatable {
    /// `debug.ccd_state` values, as AMDCCDScheduler.cpp sets them.
    enum State: Int {
        case notRun = 0
        case installed = 1
        case symbolMissing = 2
        case layoutMismatch = 3
        case routeFailed = 4
        case singleL3 = 5
    }

    var rawState: Int
    /// 1 home CCD per process, 0 off, 2 the 0.1.0 behaviour (first placements only, for comparisons).
    var mode: Int
    var psets: Int
    /// Placements the kext looked at: user threads, not realtime, no affinity set (`new`).
    var newThreads: UInt64
    /// The kernel would have started the thread on another CCD; the kext started it on its process's CCD.
    var keptHome: UInt64
    /// The kernel's own choice already was the process's CCD.
    var sameAnyway: UInt64
    /// Processes that were given a home CCD (`nohint`, the 0.1.0 name of the field).
    var noHint: UInt64
    /// The process's CCD had no free physical core, so the kernel's choice stood (`full`, kext 0.2.1 and later).
    var busyHome: UInt64? = nil

    var state: State? { State(rawValue: rawState) }
    var isHooked: Bool { state == .installed }
    var isActive: Bool { isHooked && mode == 1 }
    var isLegacyMode: Bool { isHooked && mode == 2 }

    /// Parses "state 1 mode 1 psets 2 new 10 kept 5 same 3 nohint 2 full 4".
    /// Unknown keys are ignored; a missing or malformed required key gives nil.
    /// `full` is optional (kexts before 0.2.1 do not report it); a malformed one is left out.
    static func parse(_ text: String) -> CCDSchedulerStatus? {
        var values: [String: String] = [:]
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        var i = 0
        while i + 1 < words.count {
            values[words[i]] = words[i + 1]
            i += 2
        }
        guard let state = values["state"].flatMap(Int.init),
              let mode = values["mode"].flatMap(Int.init),
              let psets = values["psets"].flatMap(Int.init),
              let new = values["new"].flatMap(UInt64.init),
              let kept = values["kept"].flatMap(UInt64.init),
              let same = values["same"].flatMap(UInt64.init),
              let noHint = values["nohint"].flatMap(UInt64.init) else { return nil }
        return CCDSchedulerStatus(rawState: state, mode: mode, psets: psets, newThreads: new,
                                  keptHome: kept, sameAnyway: same, noHint: noHint,
                                  busyHome: values["full"].flatMap(UInt64.init))
    }

    /// Number of L3 domains (CCDs on Ryzen) from `hw.cacheconfig` and
    /// `hw.logicalcpu`: cacheconfig[3] is how many logical CPUs share one L3.
    static func l3Domains(cacheConfig: [UInt64], logicalCPUs: Int) -> Int {
        guard cacheConfig.count > 3, cacheConfig[3] > 0, logicalCPUs > 0 else { return 1 }
        let perL3 = Int(cacheConfig[3])
        return max(1, (logicalCPUs + perL3 - 1) / perL3)
    }
}

/// Reads AMDCCDScheduler's sysctls and switches its mode.
enum CCDSchedulerService {
    static let statName = "debug.ccd_stat"
    static let logName = "debug.ccd_log"
    static let modeName = "debug.ccd_mode"

    /// nil when the kext is not loaded (the sysctl does not exist).
    static func readStatus() -> CCDSchedulerStatus? {
        readString(statName).flatMap(CCDSchedulerStatus.parse)
    }

    static func readLog() -> String? {
        readString(logName)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// L3 domains of this CPU (2 on a 5900X/5950X/5900XT, 1 on single-CCD parts).
    static func l3Domains() -> Int {
        var config = [UInt64](repeating: 0, count: 10)
        var size = config.count * MemoryLayout<UInt64>.size
        let ok = config.withUnsafeMutableBytes { sysctlbyname("hw.cacheconfig", $0.baseAddress, &size, nil, 0) } == 0
        var logical: Int32 = 0
        var lsize = MemoryLayout<Int32>.size
        guard ok, sysctlbyname("hw.logicalcpu", &logical, &lsize, nil, 0) == 0 else { return 1 }
        return CCDSchedulerStatus.l3Domains(cacheConfig: Array(config.prefix(size / MemoryLayout<UInt64>.size)),
                                            logicalCPUs: Int(logical))
    }

    /// Writing the mode needs root (the sysctl is CTLFLAG_RW without ANYBODY),
    /// so it goes through the system password prompt. Lasts until restart.
    /// The switch writes 1 or 0; mode 2 is only reached with ccdmode=2 or a manual sysctl.
    static func setMode(_ on: Bool, prompt: String) -> Bool {
        AdminShell.runSync("/usr/sbin/sysctl -w \(modeName)=\(on ? 1 : 0)", prompt: prompt)
    }

    private static func readString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
