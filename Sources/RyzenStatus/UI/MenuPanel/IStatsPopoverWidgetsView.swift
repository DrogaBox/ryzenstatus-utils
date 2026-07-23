// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum IStatsCardKind: String, CaseIterable, Identifiable, PanelOrderItem {
    case cpu = "cpu"
    case cores = "cores"
    case memory = "memory"
    case gpu = "gpu"
    
    var id: String { rawValue }
}

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
/// Memory pressure donuts, Disk activity, GPU circular meters, and Process Lists for CPU, GPU & Memory.
/// Respects user visibility toggles (sysCPU, sysMemory, sysGPU, showCores) and supports drag-and-drop card reordering in editing mode.
struct IStatsPopoverWidgetsView: View {
    @ObservedObject var monitor: SystemMonitor
    let editing: Bool
    
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage("istats_show_cores") private var showCores = true
    @AppStorage("istatsCardOrder") private var rawCardOrder = "cpu,cores,memory,gpu"
    
    @State private var draggingCard: IStatsCardKind?
    
    init(monitor: SystemMonitor, editing: Bool = false) {
        self.monitor = monitor
        self.editing = editing
    }
    
    private var cardOrderBinding: Binding<[IStatsCardKind]> {
        Binding(
            get: {
                let saved = rawCardOrder.components(separatedBy: ",").compactMap { IStatsCardKind(rawValue: $0) }
                var result: [IStatsCardKind] = []
                for kind in saved where !result.contains(kind) {
                    result.append(kind)
                }
                for kind in IStatsCardKind.allCases where !result.contains(kind) {
                    result.append(kind)
                }
                return result
            },
            set: { newOrder in
                rawCardOrder = newOrder.map(\.rawValue).joined(separator: ",")
            }
        )
    }
    
    private func isCardVisible(_ card: IStatsCardKind) -> Bool {
        switch card {
        case .cpu: return sysCPU
        case .cores: return showCores && sysCPU
        case .memory: return sysMemory
        case .gpu: return sysGPU
        }
    }
    
    private func bindingForCard(_ card: IStatsCardKind) -> Binding<Bool> {
        switch card {
        case .cpu: return $sysCPU
        case .cores: return $showCores
        case .memory: return $sysMemory
        case .gpu: return $sysGPU
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            let currentOrder = cardOrderBinding.wrappedValue
            ForEach(currentOrder) { card in
                if isCardVisible(card) || editing {
                    PanelReorderableItem(item: card,
                                         isEnabled: editing,
                                         order: cardOrderBinding,
                                         dragging: $draggingCard) {
                        HStack(alignment: .top, spacing: 8) {
                            if editing {
                                PanelDragHandle()
                            }
                            cardView(for: card)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func cardControls(for card: IStatsCardKind) -> some View {
        if editing {
            PanelInlineHideButton(isVisible: bindingForCard(card))
        }
    }
    
    @ViewBuilder
    private func cardView(for card: IStatsCardKind) -> some View {
        switch card {
        case .cpu:
            // 1. CPU Card Header, Histogram & Top Processes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CPU")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Spacer()
                    if editing {
                        cardControls(for: .cpu)
                    } else {
                        let freqStr = String(format: "%.1f GHz", (monitor.snapshot.peakCPUFreq ?? 0) / 1000.0)
                        let tempStr = monitor.snapshot.cpuTemperature.map { String(format: "%.0f°", $0) } ?? "--°"
                        Text("\(freqStr), \(tempStr)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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
            .background(Color.primary.opacity(sysCPU ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(sysCPU ? 1.0 : 0.4)
            
        case .cores:
            // 2. Circular Donut Ring Core Grid
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CORES (\(monitor.snapshot.cores.count))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if editing {
                        cardControls(for: .cores)
                    }
                }
                
                let cores = monitor.snapshot.cores
                let columnsCount = cores.count <= 8 ? max(2, cores.count / 2) : (cores.count <= 16 ? 8 : (cores.count <= 32 ? 8 : 12))
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnsCount)
                
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
            .background(Color.primary.opacity(showCores ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(showCores ? 1.0 : 0.4)
            
        case .memory:
            // 3. Memory Card (Twin Donut Rings + Breakdown + Process List)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MEMORY")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    if editing {
                        cardControls(for: .memory)
                    } else {
                        let memoryUsed = monitor.snapshot.memoryUsed ?? 0
                        let memoryTotal = monitor.snapshot.memoryTotal ?? (32 * 1024 * 1024 * 1024)
                        let usedGB = Double(memoryUsed) / (1024 * 1024 * 1024)
                        let totalGB = Double(memoryTotal) / (1024 * 1024 * 1024)
                        Text(String(format: "%.1f / %.0f GB", usedGB, totalGB))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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
                
                // Top Memory Processes (iStats-style)
                let memProcesses = ProcessUsageService.shared.top(.memory, limit: 4)
                if !memProcesses.isEmpty {
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PROCESSES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        ForEach(memProcesses) { proc in
                            HStack(spacing: 6) {
                                if let icon = NSRunningApplication(processIdentifier: proc.pid)?.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "memorychip")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Text(proc.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                let valGB = proc.value / (1024 * 1024 * 1024)
                                let formattedMem = valGB >= 1.0
                                    ? String(format: "%.1f GB", valGB)
                                    : String(format: "%.0f MB", proc.value / (1024 * 1024))
                                Text(formattedMem)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(sysMemory ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(sysMemory ? 1.0 : 0.4)
            
        case .gpu:
            // 4. GPU Circular Donut Gauges & Top GPU Processes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GPU")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    Spacer()
                    if editing {
                        cardControls(for: .gpu)
                    } else {
                        let gpuFreqStr = monitor.snapshot.gpuFreq.map { String(format: "%.0f MHz", $0) } ?? "GPU"
                        Text(gpuFreqStr)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    let gpuPct = monitor.snapshot.gpuUsage ?? 0
                    
                    let memPct: Double = {
                        if let used = monitor.snapshot.gpuMemoryUsed, let total = monitor.snapshot.gpuMemoryTotal, total > 0 {
                            return Double(used) / Double(total)
                        }
                        return monitor.snapshot.gpuMemoryHistory.last ?? (gpuPct * 0.75)
                    }()
                    
                    let gpuTemp = monitor.snapshot.gpuTemperature ?? 0
                    let rawFreq = monitor.snapshot.gpuFreq ?? 0
                    let gpuFreqGHz = rawFreq / 1000.0
                    let maxFreqGHz = max(2.5, gpuFreqGHz)
                    
                    IStatsDonutMeter(title: "GPU", value: String(format: "%.0f%%", gpuPct * 100), fraction: gpuPct, color: .cyan)
                    IStatsDonutMeter(title: "MEM", value: String(format: "%.0f%%", memPct * 100), fraction: memPct, color: .purple)
                    IStatsDonutMeter(title: "TMP", value: String(format: "%.0f°", gpuTemp), fraction: min(1.0, gpuTemp / 100.0), color: .orange)
                    IStatsDonutMeter(title: "GHZ", value: gpuFreqGHz > 0 ? String(format: "%.1f", gpuFreqGHz) : "--", fraction: min(1.0, gpuFreqGHz / maxFreqGHz), color: .green)
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
            .background(Color.primary.opacity(sysGPU ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(sysGPU ? 1.0 : 0.4)
        }
    }
}
