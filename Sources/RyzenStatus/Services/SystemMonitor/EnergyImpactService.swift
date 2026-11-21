// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The energy estimate the process table shows per app.
enum EnergyImpactService {
    /// Estimated impact: the CPU share plus 1.5 × the GPU share. It is an
    /// estimate for ranking, not Apple's Energy Impact, and an idle app no
    /// longer outranks a busy daemon through a flat bonus for being an app.
    static func score(cpuPct: Double, gpuPct: Double) -> Double {
        cpuPct + gpuPct * 1.5
    }
}
