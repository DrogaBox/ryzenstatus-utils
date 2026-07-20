// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Snapshot of a single logical core's state during one telemetry interval.
public struct CoreSnapshot: Identifiable, Equatable {
    public let id: Int
    public let freqMHz: Float
    public let loadPct: Float
    public let isLogical: Bool
    
    // CPPC / Core Ranking (optional, for Ryzen 3000/5000+ support)
    public let cppcScore: UInt8?
    public let cppcScoreEstimated: Bool
    public let coreRank: Int?

    public init(
        id: Int,
        freqMHz: Float,
        loadPct: Float,
        isLogical: Bool,
        cppcScore: UInt8? = nil,
        cppcScoreEstimated: Bool = false,
        coreRank: Int? = nil
    ) {
        self.id = id
        self.freqMHz = freqMHz
        self.loadPct = loadPct
        self.isLogical = isLogical
        self.cppcScore = cppcScore
        self.cppcScoreEstimated = cppcScoreEstimated
        self.coreRank = coreRank
    }
}
