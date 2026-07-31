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

    /// Calculates energy impact score for processes based on CPU%, GPU%, and background activity.
    func calculateEnergyImpact(processes: [ProcessUsage]) -> [ProcessEnergyRecord] {
        return processes.map { proc in
            let isApp = ProcessGlossary.resolve(name: proc.name, pid: proc.pid).category == .app
            let cpuPct = proc.value
            let gpuPct = 0.0
            // Formula: Energy = CPU% * 1.0 + GPU% * 1.5 + (isApp ? 2.0 : 0.5)
            let score = (cpuPct * 1.0) + (gpuPct * 1.5) + (isApp ? 2.0 : 0.5)
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
