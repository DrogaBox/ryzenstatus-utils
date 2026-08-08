// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Pure decision logic for the CPPC core ranking (kext selector 21).
/// Kept separate from the UI so `./build.sh --test` can exercise the edge
/// cases on any machine.
enum AMDCoreRanking {
    /// Returns the logical-thread indices that sit on the CPU's favorite
    /// cores — the threads whose HighestPerf score equals the maximum.
    ///
    /// `scores` may be a fixed 64-entry buffer with trailing zeros (that is
    /// how `ProcessorModel.getCPPCScore()` returns it); `logicalThreadCount`
    /// trims to the threads that actually exist before deciding, so the
    /// padding can never fake a "spread".
    ///
    /// No favorites when:
    /// - the ranking is unsupported,
    /// - the max score is 0,
    /// - every real thread shares the same score (no meaningful favorites).
    static func favoriteThreads(supported: Bool,
                                scores: [UInt8],
                                logicalThreadCount: Int) -> Set<Int> {
        guard supported, logicalThreadCount > 0 else { return [] }
        let effective = Array(scores.prefix(logicalThreadCount))
        guard let maxScore = effective.max(), maxScore > 0 else { return [] }
        guard let minScore = effective.min(), minScore != maxScore else { return [] }
        return Set(effective.enumerated().compactMap { $0.element == maxScore ? $0.offset : nil })
    }
}
