// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI
import Charts

// MARK: - BTop Cyberpunk TUI/GUI Dashboard View
struct BTopDashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var topProcesses: [ProcessUsage] = []
    @State private var procSortMode: ProcSortMode = .cpu
    @State private var processTimer: Timer?
    @Environment(\.colorScheme) private var colorScheme
    
    enum ProcSortMode: String, CaseIterable, Identifiable {
        case cpu = "CPU %"
        case memory = "MEM Usage"
        case gpu = "GPU %"
        var id: String { rawValue }
    }
    
    private let neonCyan = Color(red: 0.0, green: 0.96, blue: 0.83)     // #00F5D4
    private let neonPurple = Color(red: 0.61, green: 0.35, blue: 0.95)  // #9D4EDD
    private let neonGreen = Color(red: 0.22, green: 0.88, blue: 0.45)   // #38E54D
    private let neonOrange = Color(red: 1.0, green: 0.6, blue: 0.0)     // #FF9F1C
    private let neonPink = Color(red: 1.0, green: 0.0, blue: 0.45)      // #FF0072
    private var darkBg: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.09)   // #121217
            : Color(nsColor: .windowBackgroundColor)
    }
    private var boxBg: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.14)   // #1C1C24
            : Color(nsColor: .controlBackgroundColor)
    }

    /// Hardware-derived box title (brand + core/thread counts), computed once
    /// instead of hardcoding a specific SKU.
    private static let cpuBoxTitle: String = {
        let brand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let threads = ProcessInfo.processInfo.processorCount
        let cores = max(1, threads / 2)
        let name = brand.isEmpty ? "AMD Ryzen" : brand
        return "CPU  ·  \(name) (\(cores)-Core / \(threads)-Thread)"
    }()

    var body: some View {
        VStack(spacing: 14) {
            // --- TOP ROW: CPU & SYSTEM OVERVIEW (32-THREAD MATRIX & TOTAL LOAD) ---
            bTopBox(title: Self.cpuBoxTitle, accentColor: neonCyan) {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Left: Total Load gauge + Sparkline
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("TOTAL UTILIZATION")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                let cpuPct = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
                                Text(String(format: "%.1f%%", cpuPct))
                                    .font(.system(size: 16, weight: .black, design: .monospaced))
                                    .foregroundColor(neonCyan)
                            }
                            
                            // Load sparkline using TrendChart Canvas engine
                            if monitor.snapshot.cpuHistory.isEmpty {
                                Rectangle().fill(Color.clear).frame(height: 32)
                            } else {
                                let history = monitor.snapshot.cpuHistory
                                let now = Date()
                                let count = history.count
                                let points = history.enumerated().map { TrendPoint(date: now.addingTimeInterval(Double($0.offset - count)), value: $0.element) }
                                let series = TrendSeries(points: points, color: neonCyan, filled: true, lineWidth: 2)
                                TrendChart(series: [series])
                                    .frame(height: 32)
                            }
                            
                            // Stats Badges
                            HStack(spacing: 12) {
                                if let temp = monitor.snapshot.cpuTemperature {
                                    statBadge(label: "TEMP", val: String(format: "%.1f°C", temp), color: temp > 80 ? neonPink : (temp > 65 ? neonOrange : neonGreen))
                                }
                                if let freq = monitor.snapshot.cpuFreqHistory.last {
                                    statBadge(label: "FREQ", val: String(format: "%.2f GHz", freq), color: neonCyan)
                                }
                                if let pwr = monitor.snapshot.cpuPower {
                                    statBadge(label: "POWER", val: String(format: "%.1f W", pwr), color: neonPurple)
                                }
                            }
                        }
                        .frame(maxWidth: 240)
                        
                        Divider().background(Color.white.opacity(0.12))
                        
                        // Right: 32-Thread Cyberpunk Micro Grid (4 columns for clean spacing)
                        let cores = monitor.snapshot.cores
                        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                        LazyVGrid(columns: cols, spacing: 5) {
                            ForEach(cores) { core in
                                threadCell(core: core)
                            }
                        }
                    }
                }
            }
            
            // --- MIDDLE ROW: MEMORY / DISK & NETWORK ---
            HStack(spacing: 12) {
                // MEMORY & SWAP BOX
                bTopBox(title: "MEM  ·  MEMORY & STORAGE", accentColor: neonPurple) {
                    VStack(alignment: .leading, spacing: 8) {
                        let usedMem = Double(monitor.snapshot.memoryUsed ?? 0) / 1073741824.0
                        let totalMem = Double(max(1, monitor.snapshot.memoryTotal ?? 1)) / 1073741824.0
                        let ramPct = totalMem > 0 ? (usedMem / totalMem) : 0.0
                        
                        bTopProgressBar(label: "RAM", valStr: String(format: "%.1f / %.1f GB (%.0f%%)", usedMem, totalMem, ramPct * 100), fraction: ramPct, color: neonPurple)
                        
                        let gpuMemUsed = monitor.snapshot.gpuMemoryUsed ?? 0
                        let gpuMemTotal = monitor.snapshot.gpuMemoryTotal ?? 1
                        let gUsed = Double(gpuMemUsed) / 1073741824.0
                        let gTotal = Double(max(1, gpuMemTotal)) / 1073741824.0
                        let gFrac = gpuMemTotal > 0 ? (gUsed / gTotal) : 0.0
                        bTopProgressBar(label: "VRAM", valStr: String(format: "%.1f / %.1f GB", gUsed, gTotal), fraction: gFrac, color: neonGreen)
                        
                        let read = monitor.snapshot.diskReadHistory.last ?? 0.0
                        let write = monitor.snapshot.diskWriteHistory.last ?? 0.0
                        HStack {
                            Text("DISK IO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "R: %.1f MB/s  W: %.1f MB/s", read / 1048576.0, write / 1048576.0))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(neonCyan)
                        }
                    }
                    .frame(height: 78)
                }
                
                // NETWORK TRAFFIC BOX
                bTopBox(title: "NET  ·  BANDWIDTH TRAFFIC", accentColor: neonGreen) {
                    VStack(alignment: .leading, spacing: 6) {
                        let downRate = monitor.snapshot.netDownBytesPerSec
                        let upRate = monitor.snapshot.netUpBytesPerSec
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DOWNLOAD")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(formatOptionalBytes(downRate))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(neonCyan)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("UPLOAD")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(formatOptionalBytes(upRate))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(neonGreen)
                            }
                        }
                        
                        // Dual traffic sparkline (Padded to 24 samples using native Sparkline engine)
                        let rawDown = monitor.snapshot.netDownHistory
                        let downPoints: [Double] = rawDown.count >= 24 ? Array(rawDown.suffix(24)) : Array(repeating: 0.0, count: 24 - rawDown.count) + rawDown
                        let rawUp = monitor.snapshot.netUpHistory
                        let upPoints: [Double] = rawUp.count >= 24 ? Array(rawUp.suffix(24)) : Array(repeating: 0.0, count: 24 - rawUp.count) + rawUp
                        let peak = max(downPoints.max() ?? 0.0, upPoints.max() ?? 0.0)
                        let maxPeak = max(1.0, peak * 1.15)
                        
                        ZStack {
                            Sparkline(values: downPoints, color: neonCyan, maxValue: maxPeak, fillOpacity: 0.25, lineWidth: 1.5, showsZeroBaseline: true)
                            Sparkline(values: upPoints, color: neonGreen, maxValue: maxPeak, fillOpacity: 0.0, lineWidth: 1.5)
                        }
                        .frame(height: 34)
                    }
                    .frame(height: 78)
                }
            }
            
            // --- BOTTOM ROW: TOP PROCESSES LIST (PROC) ---
            bTopBox(title: "PROC  ·  PROCESS MANAGER", accentColor: neonOrange) {
                VStack(spacing: 8) {
                    HStack {
                        Text("SORT BY:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $procSortMode) {
                            ForEach(ProcSortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        
                        Spacer()
                        
                        Text("\(min(topProcesses.count, 10)) ACTIVE PROCESSES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // Table Header
                    HStack {
                        Text("PID").lineLimit(1).truncationMode(.tail).frame(width: 50, alignment: .leading)
                        Text("NAME").lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        Text("RESOURCE VALUE").lineLimit(1).truncationMode(.tail).frame(width: 120, alignment: .trailing)
                        Text("ACTION").lineLimit(1).truncationMode(.tail).frame(width: 60, alignment: .center)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(neonOrange)
                    .padding(.horizontal, 6)
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    // Process Rows (Fill vertical space gracefully, limited to top 10)
                    VStack(spacing: 4) {
                        ForEach(topProcesses.prefix(10)) { proc in
                            BTopProcessRow(proc: proc, procSortMode: procSortMode, neonCyan: neonCyan, neonOrange: neonOrange, neonPurple: neonPurple, neonPink: neonPink) {
                                refreshProcesses()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .onAppear {
            refreshProcesses()
            processTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                refreshProcesses()
            }
        }
        .onChange(of: procSortMode) { _, _ in
            refreshProcesses()
        }
        .onDisappear {
            processTimer?.invalidate()
            processTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .processUsageDidUpdate)) { _ in
            refreshProcesses()
        }
    }
    
    private func refreshProcesses() {
        switch procSortMode {
        case .cpu:
            self.topProcesses = ProcessUsageService.shared.topCPU(limit: 10)
        case .memory:
            self.topProcesses = ProcessUsageService.shared.topMemory(limit: 10)
        case .gpu:
            self.topProcesses = ProcessUsageService.shared.topGPU(limit: 10)
        }
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1073741824 { return String(format: "%.1f GB", bytes / 1073741824.0) }
        if bytes >= 1048576 { return String(format: "%.1f MB", bytes / 1048576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", bytes / 1024.0) }
        return String(format: "%.0f B", bytes)
    }

    private func formatOptionalBytes(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        return formatBytes(bytes) + "/s"
    }
    
    @ViewBuilder
    private func bTopBox<Content: View>(title: String, accentColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("┌─ \(title)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
                Spacer()
            }
            content()
        }
        .padding(10)
        .background(boxBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accentColor.opacity(0.3), lineWidth: 1))
    }
    
    @ViewBuilder
    private func statBadge(label: String, val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(val)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    @ViewBuilder
    private func threadCell(core: CoreSnapshot) -> some View {
        let load = core.loadPct
        let cellColor = load > 85 ? neonPink : (load > 50 ? neonOrange : neonGreen)
        let label = core.isLogical ? "T\(core.id + 1)" : "C\(core.id + 1)"
        
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(load))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(cellColor)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor)
                        .frame(width: max(0, geo.size.width * CGFloat(load / 100.0)))
                }
            }
            .frame(height: 3)
        }
        .padding(3)
        .background(Color.white.opacity(0.02))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func bTopProgressBar(label: String, valStr: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(valStr)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0, fraction)))))
                }
            }
            .frame(height: 6)
        }
    }
}

struct BTopProcessRow: View {
    let proc: ProcessUsage
    let procSortMode: BTopDashboardView.ProcSortMode
    let neonCyan: Color
    let neonOrange: Color
    let neonPurple: Color
    let neonPink: Color
    let onKill: () -> Void

    @State private var showingDetail = false

    var body: some View {
        HStack {
            Button {
                ProcessInspectorWindowController.shared.present(for: proc)
            } label: {
                HStack {
                    Text("\(proc.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Text(proc.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let valStr: String = {
                        switch procSortMode {
                        case .cpu: return String(format: "%.1f%% CPU", proc.value)
                        case .memory:
                            let valGB = proc.value / (1024 * 1024 * 1024)
                            return valGB >= 1.0 ? String(format: "%.1f GB", valGB) : String(format: "%.0f MB", proc.value / (1024 * 1024))
                        case .gpu: return String(format: "%.1f%% GPU", proc.value)
                        }
                    }()
                    let valColor = procSortMode == .cpu ? neonCyan : (procSortMode == .gpu ? neonOrange : neonPurple)

                    Text(valStr)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(valColor)
                        .frame(width: 120, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                kill(proc.pid, SIGTERM)
                onKill()
            }) {
                Text("KILL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(neonPink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(neonPink.opacity(0.15))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .frame(width: 60, alignment: .center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.03))
        .cornerRadius(4)
    }
}
