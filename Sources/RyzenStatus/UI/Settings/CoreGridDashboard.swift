// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct CoreGridDashboard: View {
    let cores: [CoreSnapshot]
    let ccdTemperatures: [Float]
    let physicalCoresCount: Int
    
    @AppStorage("grid_show_load") private var gridShowLoad = true
    @AppStorage("grid_show_freq") private var gridShowFreq = true
    @AppStorage("grid_show_temp") private var gridShowTemp = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    @ViewBuilder
    private func gridHUDToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .toggleStyle(.checkbox)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Per-Core CPU Load")
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    gridHUDToggle("Temp", isOn: $gridShowTemp)
                    gridHUDToggle("Freq", isOn: $gridShowFreq)
                    gridHUDToggle("Load", isOn: $gridShowLoad)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cores) { core in
                    CoreCell(
                        core: core,
                        ccdTemperatures: ccdTemperatures,
                        physicalCoresCount: physicalCoresCount,
                        showLoad: gridShowLoad,
                        showFreq: gridShowFreq,
                        showTemp: gridShowTemp
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct CoreCell: View {
    let core: CoreSnapshot
    let ccdTemperatures: [Float]
    let physicalCoresCount: Int
    let showLoad: Bool
    let showFreq: Bool
    let showTemp: Bool

    private var loadColor: Color {
        if core.loadPct > 80 { return Color.red }
        if core.loadPct > 50 { return Color.orange }
        return Color.green
    }

    private var labelText: String {
        let base = core.isLogical ? "T\(core.id + 1)" : "C\(core.id + 1)"
        var parts: [String] = [base]
        if let score = core.cppcScore, score > 0 {
            parts.append("[\(score)]")
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(labelText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(core.isLogical ? .secondary.opacity(0.7) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if showLoad {
                    Spacer(minLength: 2)
                    Text(String(format: "%.0f%%", core.loadPct))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundColor(loadColor)
                }
            }

            if showLoad {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: 3)
                        Capsule().fill(loadColor)
                            .frame(width: geo.size.width * CGFloat(core.loadPct / 100.0), height: 3)
                            .shadow(color: loadColor.opacity(0.4), radius: 1)
                    }
                }
                .frame(height: 3)
            }

            if showFreq || showTemp {
                HStack(spacing: 2) {
                    if showFreq {
                        Text(String(format: "%.0fMHz", core.freqMHz))
                            .font(.system(size: 8, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(.secondary)
                    }
                    
                    let limitPhys = physicalCoresCount > 0 ? physicalCoresCount : 16
                    let ccdIdx = (core.id % limitPhys) / 8
                    
                    if showFreq && showTemp && ccdTemperatures.count > ccdIdx {
                        Spacer(minLength: 1)
                    }
                    
                    if showTemp {
                        if ccdTemperatures.count > ccdIdx {
                            Text(String(format: "%.0f°C", ccdTemperatures[ccdIdx]))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundColor(.red)
                        } else {
                            Text("-")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(6)
        .frame(height: 52)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(loadColor.opacity(0.2)))
        .cornerRadius(6)
    }
}
