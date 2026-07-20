// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

public struct CPUCoreGridView: View {
    let cores: [CoreSnapshot]
    
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
    
    public init(cores: [CoreSnapshot]) {
        self.cores = cores
    }
    
    public var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(cores) { core in
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color.black.opacity(0.25))
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
                        
                        // Labels (adaptive visibility for dense core layouts)
                        if showTextLabels {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("\(core.id)")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.white.opacity(0.35))
                                        .padding(.leading, 3)
                                        .padding(.top, 1)
                                    Spacer()
                                }
                                Spacer()
                                Text(String(format: "%.0f%%", core.loadPct))
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 1.5)
                            }
                        }
                    }
                }
                .frame(height: cellHeight)
                .help(String(format: "Thread %d: %.1f%%", core.id, core.loadPct))
            }
        }
    }
}
