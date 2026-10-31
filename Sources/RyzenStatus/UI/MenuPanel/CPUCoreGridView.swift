// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Which value the panel's core grid renders. `load` is the classic
/// CPU-usage view (kext metric array, per logical thread). The other three
/// are SMU-native per-physical-core values from the PM table; they
/// fall back to the load view whenever the table does not decode.
public enum PanelCoreGridMetric: String {
    case load
    case clock
    case temp
    case power

    /// Fixed scale ceilings keep rings comparable across cores and over time
    /// (same philosophy as the disclosure's sparklines): clocks against a
    /// ceiling above Vermeer's ~5.15 GHz boost, temps against 0–100 °C,
    /// per-core power against a 25 W ceiling (well above single-core peaks).
    var clockCeilingMHz: Double { 5400 }
    var tempCeilingC: Double { 100 }
    var powerCeilingW: Double { 25 }
}

/// Ring layout for a core count: cores per row and ring diameter. The rows
/// divide the count evenly where they can, the rest fall back to 8 per row.
struct CoreRingLayout: Equatable {
    let perRow: Int
    let diameter: CGFloat

    /// Stroke width of the track and of the value arc.
    static let thickness: CGFloat = 3
    /// Vertical gap between rows.
    static let rowGap: CGFloat = 6

    init(count: Int) {
        switch count {
        case let n where n > 0 && n % 12 == 0: (perRow, diameter) = (12, 14)
        case let n where n > 0 && n % 10 == 0: (perRow, diameter) = (10, 18)
        case let n where n > 0 && n % 9 == 0:  (perRow, diameter) = (9, 22)
        case let n where n > 0 && n % 7 == 0:  (perRow, diameter) = (7, 24)
        default:                               (perRow, diameter) = (8, 24)
        }
    }

    /// Value labels fit inside rings of 22 pt and up.
    var showsValue: Bool { diameter >= 22 }
}

/// One core as a ring gauge: a faint full-circle track and an arc that starts
/// at twelve o'clock and runs clockwise to the value's share of its scale.
private struct CoreRing: View {
    let fraction: Double
    let color: Color
    let label: String?
    let diameter: CGFloat
    let dimmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10),
                        lineWidth: CoreRingLayout.thickness)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: CoreRingLayout.thickness, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundColor(dimmed ? .secondary.opacity(0.6) : .primary)
                    .padding(.horizontal, CoreRingLayout.thickness)
            }
        }
        .padding(CoreRingLayout.thickness / 2)
        .frame(width: diameter, height: diameter)
    }
}

public struct CPUCoreGridView: View {
    let cores: [CoreSnapshot]
    /// Per-core C6 residency % (kext selector 32). Index = logical thread.
    /// Empty array (old kext / no kext) hides the overlay.
    let c6Residency: [UInt16]
    /// Logical-thread indices on the CPU's favorite cores (CPPC ranking,
    /// selector 21). Empty set hides the badge.
    let favoriteThreads: Set<Int>
    /// SMU per-physical-core rows (PM-table decode, present slots only).
    /// Empty when the table doesn't decode — the SMU metric modes then fall
    /// back to the load view instead of rendering an empty shell.
    let smuCores: [AMDSmuPMTable.CoreRow]
    /// Persisted metric mode (DefaultsKey.panelCoreGridMetric).
    let metric: PanelCoreGridMetric
    @Environment(\.colorScheme) private var colorScheme

    /// SMU mode is live only when data exists; otherwise load.
    private var smuActive: Bool { metric != .load && !smuCores.isEmpty }

    private var layout: CoreRingLayout {
        CoreRingLayout(count: smuActive ? smuCores.count : cores.count)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: layout.perRow)
    }

    init(cores: [CoreSnapshot],
         c6Residency: [UInt16] = [],
         favoriteThreads: Set<Int> = [],
         smuCores: [AMDSmuPMTable.CoreRow] = [],
         metric: PanelCoreGridMetric = .load) {
        self.cores = cores
        self.c6Residency = c6Residency
        self.favoriteThreads = favoriteThreads
        self.smuCores = smuCores
        self.metric = metric
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: CoreRingLayout.rowGap) {
            if smuActive {
                ForEach(smuCores, id: \.slot) { core in
                    CoreRing(fraction: smuFraction(core),
                             color: smuColor(core),
                             label: layout.showsValue ? smuValueText(core) : nil,
                             diameter: layout.diameter,
                             dimmed: hidesValue(core))
                        .help(smuHoverText(core))
                }
            } else {
                ForEach(cores) { core in
                    CoreRing(fraction: Double(core.loadPct) / 100,
                             color: PanelMetricColor.cyan(for: colorScheme),
                             label: layout.showsValue ? String(format: "%.0f", core.loadPct) : nil,
                             diameter: layout.diameter,
                             dimmed: core.loadPct < 1)
                        .overlay(alignment: .topTrailing) { badges(for: core) }
                        .help(hoverText(for: core))
                }
            }
        }
        // The residency dots are polled only while a grid is on screen.
        .onAppear { C6ResidencyService.shared.startPolling() }
        .onDisappear { C6ResidencyService.shared.stopPolling() }
    }

    // MARK: - Load (kext metric array, per logical thread)

    /// Favorite-core star and C6 residency dot, kept small on the ring's
    /// shoulder so they never cover the value.
    @ViewBuilder
    private func badges(for core: CoreSnapshot) -> some View {
        if favoriteThreads.contains(core.id) {
            Image(systemName: "star.fill")
                .font(.system(size: 5, weight: .bold))
                .foregroundColor(.yellow)
        } else if core.id < c6Residency.count, c6Residency[core.id] >= 50 {
            Circle()
                .fill(Color.green.opacity(0.95))
                .frame(width: 4, height: 4)
        }
    }

    private func hoverText(for core: CoreSnapshot) -> String {
        var parts = [String(format: "Thread %d: %.1f%% (system %.1f%%)", core.id, core.loadPct, core.systemPct)]
        if core.id < c6Residency.count {
            parts.append(String(format: "C6 residency %d%%", Int(c6Residency[core.id])))
        }
        if favoriteThreads.contains(core.id) {
            parts.append("★ favorite core")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - SMU per-physical-core values

    /// A parked core's effective clock is meaningless; its temperature and
    /// power are not.
    private func hidesValue(_ core: AMDSmuPMTable.CoreRow) -> Bool {
        core.isSleeping && metric == .clock
    }

    /// Share of the metric's fixed ceiling.
    private func smuFraction(_ core: AMDSmuPMTable.CoreRow) -> Double {
        guard !hidesValue(core) else { return 0 }
        switch metric {
        case .clock: return Double(core.freqMHz) / metric.clockCeilingMHz
        case .temp:  return Double(core.tempC) / metric.tempCeilingC
        case .power: return Double(core.powerW) / metric.powerCeilingW
        case .load:  return Double(core.c0Percent) / 100
        }
    }

    /// Clocks cyan, power purple, temperatures green → orange → red with heat.
    private func smuColor(_ core: AMDSmuPMTable.CoreRow) -> Color {
        switch metric {
        case .clock, .load:
            return PanelMetricColor.cyan(for: colorScheme)
        case .temp:
            return core.tempC >= 70 ? .red : (core.tempC >= 50 ? .orange : .green)
        case .power:
            return .purple
        }
    }

    private func smuValueText(_ core: AMDSmuPMTable.CoreRow) -> String {
        guard !hidesValue(core) else { return "—" }
        switch metric {
        case .clock: return String(format: "%.1f", core.freqMHz / 1000)
        case .temp:  return String(format: "%.0f°", core.tempC)
        case .power: return String(format: "%.1f", core.powerW)
        case .load:  return String(format: "%.0f", core.c0Percent)
        }
    }

    private func smuHoverText(_ core: AMDSmuPMTable.CoreRow) -> String {
        if core.isSleeping {
            return String(format: "Core %d: parked · %.1f °C · %.2f W · C0 %.1f%% · CC6 %.1f%% · %.2f V",
                          core.slot, core.tempC, core.powerW, core.c0Percent, core.cc6Percent, core.voltageRaw)
        }
        return String(format: "Core %d: %.0f MHz eff · %.1f °C · %.2f W · C0 %.1f%% · CC6 %.1f%% · %.2f V",
                      core.slot, core.freqMHz, core.tempC, core.powerW, core.c0Percent, core.cc6Percent, core.voltageRaw)
    }
}
