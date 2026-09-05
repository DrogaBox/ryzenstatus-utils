// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

public struct CPUCoreGridView: View {
    let cores: [CoreSnapshot]
    /// KEXT_WAVE C-1: per-core C6 residency % (kext selector 32). Index =
    /// logical thread. Empty array (old kext / no kext) hides the overlay.
    let c6Residency: [UInt16]
    /// KEXT_WAVE C-5: logical-thread indices on the CPU's favorite cores
    /// (CPPC ranking, selector 21). Empty set hides the badge.
    let favoriteThreads: Set<Int>
    @Environment(\.colorScheme) private var colorScheme
    
    private var colCount: Int {
        let count = cores.count
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
        let count = cores.count
        if count > 64 { return 14 }
        if count > 32 { return 18 }
        return 24
    }
    
    private var showTextLabels: Bool {
        return cores.count <= 32
    }
    
    private var showOverlays: Bool {
        return cores.count <= 32 && (!c6Residency.isEmpty || !favoriteThreads.isEmpty)
    }
    
    public init(cores: [CoreSnapshot],
                c6Residency: [UInt16] = [],
                favoriteThreads: Set<Int> = []) {
        self.cores = cores
        self.c6Residency = c6Residency
        self.favoriteThreads = favoriteThreads
    }
    
    public var body: some View {
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
