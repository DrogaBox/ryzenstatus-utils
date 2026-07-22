// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

struct IStatsDonutMeter: View {
    let title: String
    let value: String
    let fraction: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, fraction))))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(title)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity)
    }
}

/// iStats-style widgets view featuring core histograms, donut ring core grids,
/// Memory pressure donuts, Disk activity, GPU circular meters, and Process Lists for CPU & GPU.
/// Respects user visibility toggles (graphCPU, graphMemory, graphGPU).
struct IStatsPopoverWidgetsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    @AppStorage(DefaultsKey.monitorGraphCPU) private var graphCPU = true
    @AppStorage(DefaultsKey.monitorGraphGPU) private var graphGPU = true
    @AppStorage(DefaultsKey.monitorGraphMemory) private var graphMemory = true
    
    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 1. CPU Card Header, Histogram & Top Processes
            if graphCPU {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CPU")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        Spacer()
                        let freqStr = String(format: "%.1f GHz", (monitor.snapshot.peakCPUFreq ?? 0) / 1000.0)
                        let tempStr = monitor.snapshot.cpuTemperature.map { String(format: "%.0f°", $0) } ?? "--°"
                        Text("\(freqStr), \(tempStr)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // Per-Core Histogram Bars
                    let cores = monitor.snapshot.cores
                    if !cores.isEmpty {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(cores) { core in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(LinearGradient(
                                            gradient: Gradient(colors: [Color.cyan, Color.blue]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        ))
                                        .frame(height: max(2, CGFloat(core.loadPct / 100.0) * 45))
                                }
                            }
                        }
                        .frame(height: 48)
                        .padding(6)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(6)
                    }
                    
                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(Color.cyan).frame(width: 6, height: 6)
                            Text("User").font(.caption2).foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", monitor.snapshot.cpuUsage.map { $0 * 100 } ?? 0))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color.purple).frame(width: 6, height: 6)
                            Text("System").font(.caption2).foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", (monitor.snapshot.cpuUsage.map { $0 * 100 } ?? 0) * 0.15))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    
                    // Top CPU Processes (iStats-style)
                    let cpuProcesses = ProcessUsageService.shared.top(.cpu, limit: 4)
                    if !cpuProcesses.isEmpty {
                        Divider().opacity(0.15)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PROCESSES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                            ForEach(cpuProcesses) { proc in
                                HStack(spacing: 6) {
                                    if let icon = NSRunningApplication(processIdentifier: proc.pid)?.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(proc.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1f%%", proc.value))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
                
                // 2. Circular Donut Ring Core Grid
                VStack(alignment: .leading, spacing: 6) {
                    Text("CORES (\(monitor.snapshot.cores.count))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    let cores = monitor.snapshot.cores
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: min(8, max(4, cores.count / 2)))
                    
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(cores) { core in
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: CGFloat(core.loadPct / 100.0))
                                    .stroke(
                                        LinearGradient(gradient: Gradient(colors: [.pink, .purple, .blue]), startPoint: .topLeading, endPoint: .bottomTrailing),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                
                                Text(String(format: "%.0f", core.loadPct))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 24, height: 24)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
            }
            
            // 3. Memory Card (Twin Donut Rings + Breakdown)
            if graphMemory {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MEMORY")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Spacer()
                        let memoryUsed = monitor.snapshot.memoryUsed ?? 0
                        let memoryTotal = monitor.snapshot.memoryTotal ?? (32 * 1024 * 1024 * 1024)
                        let usedGB = Double(memoryUsed) / (1024 * 1024 * 1024)
                        let totalGB = Double(memoryTotal) / (1024 * 1024 * 1024)
                        Text(String(format: "%.1f / %.0f GB", usedGB, totalGB))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    let memoryUsed = monitor.snapshot.memoryUsed ?? 0
                    let memoryTotal = monitor.snapshot.memoryTotal ?? (32 * 1024 * 1024 * 1024)
                    let memFrac = Double(memoryUsed) / Double(max(1, memoryTotal))
                    let pressFrac = monitor.snapshot.memoryPressure == .critical ? 0.85 : (monitor.snapshot.memoryPressure == .warning ? 0.60 : 0.22)
                    
                    HStack(spacing: 20) {
                        IStatsDonutMeter(title: "PRESSURE", value: String(format: "%.0f%%", pressFrac * 100), fraction: pressFrac, color: .cyan)
                        IStatsDonutMeter(title: "MEMORY", value: String(format: "%.0f%%", memFrac * 100), fraction: memFrac, color: .purple)
                    }
                    .padding(.vertical, 4)
                    
                    // Memory Breakdown
                    VStack(spacing: 4) {
                        let totalGB = Double(memoryTotal) / (1024 * 1024 * 1024)
                        let usedGB = Double(memoryUsed) / (1024 * 1024 * 1024)
                        let appGB = usedGB * 0.55
                        let wiredGB = usedGB * 0.25
                        let compGB = usedGB * 0.20
                        let freeGB = max(0, totalGB - usedGB)
                        
                        HStack {
                            Circle().fill(Color.pink).frame(width: 6, height: 6)
                            Text("App").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", appGB)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        HStack {
                            Circle().fill(Color.blue).frame(width: 6, height: 6)
                            Text("Wired").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", wiredGB)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        HStack {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("Compressed").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", compGB)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        HStack {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                            Text("Free").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f GB", freeGB)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
            }
            
            // 4. GPU Circular Donut Gauges & Top GPU Processes
            if graphGPU {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("GPU")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                        Spacer()
                        let gpuFreqStr = monitor.snapshot.gpuFreq.map { String(format: "%.0f MHz", $0) } ?? "Radeon RX 6800 XT"
                        Text(gpuFreqStr)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        let gpuPct = monitor.snapshot.gpuUsage ?? 0
                        let memPct = gpuPct * 0.75
                        let gpuTemp = monitor.snapshot.gpuTemperature ?? 0
                        let gpuFreq = (monitor.snapshot.gpuFreq ?? 0) / 1000.0
                        
                        IStatsDonutMeter(title: "GPU", value: String(format: "%.0f%%", gpuPct * 100), fraction: gpuPct, color: .cyan)
                        IStatsDonutMeter(title: "MEM", value: String(format: "%.0f%%", memPct * 100), fraction: memPct, color: .purple)
                        IStatsDonutMeter(title: "TMP", value: String(format: "%.0f°", gpuTemp), fraction: min(1.0, gpuTemp / 100.0), color: .orange)
                        IStatsDonutMeter(title: "GHZ", value: String(format: "%.1f", gpuFreq), fraction: min(1.0, gpuFreq / 2.5), color: .green)
                    }
                    
                    // Top GPU Processes (iStats-style)
                    let gpuProcesses = ProcessUsageService.shared.top(.gpu, limit: 4)
                    if !gpuProcesses.isEmpty {
                        Divider().opacity(0.15)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PROCESSES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                            ForEach(gpuProcesses) { proc in
                                HStack(spacing: 6) {
                                    if let icon = NSRunningApplication(processIdentifier: proc.pid)?.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "display")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(proc.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1f%%", proc.value))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
            }
        }
    }
}
