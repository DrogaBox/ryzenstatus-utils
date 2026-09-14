// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Which value the panel's core grid renders. `load` is the classic
/// CPU-usage fill (kext metric array, per logical thread). The other three
/// Are SMU-native per-physical-core values from the PM table; they
/// fall back to the classic grid whenever the table does not decode.
public enum PanelCoreGridMetric: String {
    case load
    case clock
    case temp
    case power

    /// Fixed scale ceilings keep cells comparable across cores and over time
    /// (same philosophy as the disclosure's sparklines): clocks against a
    /// ceiling above Vermeer's ~5.15 GHz boost, temps against 0–100 °C,
    /// per-core power against a 25 W ceiling (well above single-core peaks).
    var clockCeilingMHz: Double { 5400 }
    var tempCeilingC: Double { 100 }
    var powerCeilingW: Double { 25 }
}

public struct CPUCoreGridView: View {
    let cores: [CoreSnapshot]
    /// KEXT_WAVE C-1: per-core C6 residency % (kext selector 32). Index =
    /// logical thread. Empty array (old kext / no kext) hides the overlay.
    let c6Residency: [UInt16]
    /// KEXT_WAVE C-5: logical-thread indices on the CPU's favorite cores
    /// (CPPC ranking, selector 21). Empty set hides the badge.
    let favoriteThreads: Set<Int>
    /// SMU per-physical-core rows (PM-table decode, present slots only).
    /// Empty when the table doesn't decode — the SMU metric modes then fall
    /// back to the classic load grid instead of rendering an empty shell.
    let smuCores: [AMDSmuPMTable.CoreRow]
    /// Persisted metric mode (DefaultsKey.panelCoreGridMetric).
    let metric: PanelCoreGridMetric
    @Environment(\.colorScheme) private var colorScheme

    /// SMU mode is live only when data exists; otherwise classic load.
    private var smuActive: Bool { metric != .load && !smuCores.isEmpty }

    private var effectiveCount: Int { smuActive ? smuCores.count : cores.count }

    private var colCount: Int {
        let count = effectiveCount
        if count > 64 { return 12 }
        if count > 32 { return 10 }
        if count > 16 { return 8 }
        if count > 8  { return 6 }
        return 4
    }

    private var columns: [GridItem] {
        return Array(repeating: GridItem(.flexible(), spacing: 3), count: colCount)
    }

    private var cellHeight: CGFloat {
        let count = effectiveCount
        if count > 64 { return 14 }
        if count > 32 { return 18 }
        return 24
    }

    private var showTextLabels: Bool {
        return effectiveCount <= 32
    }

    private var showOverlays: Bool {
        return !smuActive && effectiveCount <= 32 && (!c6Residency.isEmpty || !favoriteThreads.isEmpty)
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
        if smuActive {
            smuGrid
        } else {
            classicGrid
        }
    }

    // MARK: - Classic load grid (kext metric array, per logical thread)

    private var classicGrid: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(cores) { core in
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.25)
                                                        : Color.primary.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )

                        // Fill
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.cyan.opacity(0.85), Color.purple.opacity(0.9)]),
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .frame(height: geo.size.height * CGFloat(core.loadPct / 100.0))

                        // KEXT_WAVE C-1: C6 residency dot — green when the thread
                        // spent most of the window idling (high residency), dim
                        // when busy. Sized for the dense grid.
                        if showOverlays, core.id < c6Residency.count {
                            let residency = Int(c6Residency[core.id])
                            Circle()
                                .fill(residency >= 50 ? Color.green.opacity(0.95)
                                                      : Color.green.opacity(Double(residency) / 100.0 * 0.5))
                                .frame(width: 5, height: 5)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 2)
                                .padding(.top, 1)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }

                        // KEXT_WAVE C-5: favorite-core badge (highest CPPC score).
                        if showOverlays, favoriteThreads.contains(core.id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.yellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 2)
                                .padding(.top, 1)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }

                        // Labels (adaptive visibility for dense core layouts)
                        if showTextLabels {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("\(core.id)")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.45))
                                        .padding(.leading, 3)
                                        .padding(.top, 1)
                                    Spacer()
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", core.loadPct))
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.bottom, 1.5)
                            }
                        }
                    }
                }
                .frame(height: cellHeight)
                .help(hoverText(for: core))
            }
        }
    }

    // MARK: - SMU per-physical-core grid

    /// True per-physical-core cells from the PM table — no SMT duplication.
    /// Fill height encodes the selected metric against a fixed ceiling so
    /// cells stay comparable across cores and over time; sleeping cores
    /// render as flat dim cells with a dash, mirroring the disclosure.
    @ViewBuilder
    private var smuGrid: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(smuCores, id: \.slot) { core in
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.25)
                                                        : Color.primary.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )

                        if !core.isSleeping {
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(smuFill(core))
                                .frame(height: geo.size.height * smuFraction(core))
                        }

                        if showTextLabels {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("\(core.slot)")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.45))
                                        .padding(.leading, 3)
                                        .padding(.top, 1)
                                    Spacer()
                                }
                                Spacer()
                                Text(smuValueText(core))
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(core.isSleeping
                                                     ? (colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.4))
                                                     : (colorScheme == .dark ? .white : .black))
                                    .padding(.bottom, 1.5)
                            }
                        }
                    }
                }
                .frame(height: cellHeight)
                .help(smuHoverText(core))
            }
        }
    }

    /// Fill fraction for the selected SMU metric against its fixed ceiling.
    private func smuFraction(_ core: AMDSmuPMTable.CoreRow) -> CGFloat {
        guard !core.isSleeping else { return 0 }
        switch metric {
        case .clock: return CGFloat(min(1, Double(core.freqMHz) / metric.clockCeilingMHz))
        case .temp:  return CGFloat(min(1, Double(core.tempC) / metric.tempCeilingC))
        case .power: return CGFloat(min(1, Double(core.powerW) / metric.powerCeilingW))
        case .load:  return CGFloat(core.c0Percent / 100)
        }
    }

    /// Per-metric fill color: clocks stay in the classic cyan family, temps
    /// shift green→orange→red with heat, power goes purple (the classic
    /// gradient's top color), matching the disclosure's column colors.
    private func smuFill(_ core: AMDSmuPMTable.CoreRow) -> some ShapeStyle {
        switch metric {
        case .clock:
            return AnyShapeStyle(Color.cyan.opacity(0.85))
        case .temp:
            let color: Color = core.tempC >= 70 ? .red : (core.tempC >= 50 ? .orange : .green)
            return AnyShapeStyle(color.opacity(0.85))
        case .power:
            return AnyShapeStyle(Color.purple.opacity(0.85))
        case .load:
            return AnyShapeStyle(Color.green.opacity(0.85))
        }
    }

    private func smuValueText(_ core: AMDSmuPMTable.CoreRow) -> String {
        guard !core.isSleeping else { return "—" }
        switch metric {
        case .clock: return String(format: "%.0f", core.freqMHz)
        case .temp:  return String(format: "%.0f°", core.tempC)
        case .power: return String(format: "%.1fW", core.powerW)
        case .load:  return String(format: "%.0f%%", core.c0Percent)
        }
    }

    private func smuHoverText(_ core: AMDSmuPMTable.CoreRow) -> String {
        if core.isSleeping {
            return String(format: "Core %d: parked (C0 %.1f%% · CC6 %.1f%%)", core.slot, core.c0Percent, core.cc6Percent)
        }
        return String(format: "Core %d: %.0f MHz eff · %.1f °C · %.2f W · C0 %.1f%% · CC6 %.1f%% · %.2f V",
                      core.slot, core.freqMHz, core.tempC, core.powerW, core.c0Percent, core.cc6Percent, core.voltageRaw)
    }

    /// KEXT_WAVE C-1/C-5: enriched tooltip with residency and favorite status.
    private func hoverText(for core: CoreSnapshot) -> String {
        var parts = [String(format: "Thread %d: %.1f%%", core.id, core.loadPct)]
        if core.id < c6Residency.count {
            parts.append(String(format: "C6 residency %d%%", Int(c6Residency[core.id])))
        }
        if favoriteThreads.contains(core.id) {
            parts.append("★ favorite core")
        }
        return parts.joined(separator: " · ")
    }
}
