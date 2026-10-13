// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Cumulative Mach CPU tick counters from one sample. Busy counts user,
/// system and nice ticks; system is kept apart so graphs can stack kernel
/// time over user time.
struct CPUTickSample: Equatable {
    let busy: UInt64
    let system: UInt64
    let total: UInt64

    init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        busy = user + system + nice
        self.system = system
        total = busy + idle
    }

    /// Per-core counters arrive as `integer_t`, but the kernel keeps them
    /// unsigned. Past 2^31 ticks (about 248 days awake at 100 Hz) one reads
    /// negative, so it is taken bit for bit instead of trapping in `UInt64(_:)`.
    init(machUser user: integer_t, system: integer_t, idle: integer_t, nice: integer_t) {
        self.init(user: UInt64(UInt32(bitPattern: user)),
                  system: UInt64(UInt32(bitPattern: system)),
                  idle: UInt64(UInt32(bitPattern: idle)),
                  nice: UInt64(UInt32(bitPattern: nice)))
    }

    /// Busy and system shares of the interval since `previous`, 0...1. Nil
    /// when the counters did not advance or went backwards: the kernel keeps
    /// them in 32 bits, so a wrap must skip a sample, not trap on underflow.
    func load(since previous: CPUTickSample) -> (busy: Double, system: Double)? {
        guard total > previous.total, busy >= previous.busy, system >= previous.system else { return nil }
        let elapsed = Double(total - previous.total)
        let busyShare = min(1, Double(busy - previous.busy) / elapsed)
        let systemShare = min(busyShare, Double(system - previous.system) / elapsed)
        return (busyShare, systemShare)
    }
}
