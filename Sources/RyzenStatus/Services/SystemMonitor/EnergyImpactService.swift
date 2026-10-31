// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import AppKit

/// Per-process energy impact statistics.
struct ProcessEnergyRecord: Identifiable, Sendable, Codable, Equatable {
    var id: pid_t { pid }
    var pid: pid_t
    var name: String
    var energyScore: Double
    var cpuPct: Double
    var gpuPct: Double
    var isApp: Bool

    init(pid: pid_t, name: String, energyScore: Double, cpuPct: Double, gpuPct: Double, isApp: Bool) {
        self.pid = pid
        self.name = name
        self.energyScore = energyScore
        self.cpuPct = cpuPct
        self.gpuPct = gpuPct
        self.isApp = isApp
    }
}

/// Service computing energy impact breakdown per application.
final class EnergyImpactService: @unchecked Sendable {
    static let shared = EnergyImpactService()

    private init() {}

    /// Estimated impact: the CPU share plus 1.5 × the GPU share. It is an
    /// estimate for ranking, not Apple's Energy Impact, and an idle app no
    /// longer outranks a busy daemon through a flat bonus for being an app.
    static func score(cpuPct: Double, gpuPct: Double) -> Double {
        cpuPct + gpuPct * 1.5
    }

    /// Ranks processes by their estimated impact.
    func calculateEnergyImpact(processes: [ProcessUsage]) -> [ProcessEnergyRecord] {
        // BUG-18 fix: GPU was always hardcoded to 0.0. Build a PID-keyed GPU lookup
        // from topGPU so each process reflects its real GPU utilization.
        let gpuRows = ProcessUsageService.shared.topGPU(limit: 50)
        let gpuByPID: [pid_t: Double] = Dictionary(
            gpuRows.map { ($0.pid, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        return processes.map { proc in
            let isApp = ProcessGlossary.resolve(name: proc.name, pid: proc.pid).category == .app
            let cpuPct = proc.value
            let gpuPct = gpuByPID[proc.pid] ?? 0.0
            let score = Self.score(cpuPct: cpuPct, gpuPct: gpuPct)
            return ProcessEnergyRecord(
                pid: proc.pid,
                name: proc.name,
                energyScore: score,
                cpuPct: cpuPct,
                gpuPct: gpuPct,
                isApp: isApp
            )
        }.sorted { $0.energyScore > $1.energyScore }
    }
}
