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
    /// Stacked from twelve o'clock, back to front, like the menu bar ring.
    let values: [Double]
    let inks: [GraphInk]

    init(title: String, value: String, values: [Double], inks: [GraphInk]) {
        self.title = title
        self.value = value
        self.values = values
        self.inks = inks
    }

    init(title: String, value: String, fraction: Double, ink: GraphInk = .primary) {
        self.init(title: title, value: value, values: [fraction], inks: [ink])
    }

    var body: some View {
        ZStack {
            GraphRing(values: values, inks: inks, lineWidth: 4)
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
}

/// iStats-style widgets view featuring core histograms, donut ring core grids,
/// Memory pressure donuts, Disk activity, GPU circular meters, and Process Lists for CPU, GPU & Memory.
/// Respects user visibility toggles (sysCPU, sysMemory, sysGPU, showCores) and supports drag-and-drop card reordering in editing mode.
struct IStatsPopoverWidgetsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject var monitor: SystemMonitor
    let editing: Bool
    let isDashboard: Bool
    
    @AppStorage("istats_show_cpu") private var showCPU = true
    @AppStorage("istats_show_gpu") private var showGPU = true
    @AppStorage("istats_show_memory") private var showMemory = true
    @AppStorage("istats_show_cores") private var showCores = true
    @AppStorage("istatsCardOrder") private var rawCardOrder = "cpu,cores,memory,gpu"
    
    @State private var draggingCard: IStatsCardKind?
    @State private var cpuProcesses: [ProcessUsage] = []
    @State private var memProcesses: [ProcessUsage] = []
    @State private var gpuProcesses: [ProcessUsage] = []
    
    init(monitor: SystemMonitor, editing: Bool = false, isDashboard: Bool = false) {
        self.monitor = monitor
        self.editing = editing
        self.isDashboard = isDashboard
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
        case .cpu: return showCPU
        case .cores: return showCores && showCPU
        case .memory: return showMemory
        case .gpu: return showGPU
        }
    }
    
    private func bindingForCard(_ card: IStatsCardKind) -> Binding<Bool> {
        switch card {
        case .cpu: return $showCPU
        case .cores: return $showCores
        case .memory: return $showMemory
        case .gpu: return $showGPU
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
        .onAppear {
            updateProcesses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .processUsageDidUpdate)) { _ in
            updateProcesses()
        }
    }
    
    private func updateProcesses() {
        let newCPU = ProcessUsageService.shared.top(.cpu, limit: 4)
        if !newCPU.isEmpty {
            cpuProcesses = newCPU
        }
        let newMem = ProcessUsageService.shared.top(.memory, limit: 4)
        if !newMem.isEmpty {
            memProcesses = newMem
        }
        let newGPU = ProcessUsageService.shared.top(.gpu, limit: 4)
        if !newGPU.isEmpty {
            gpuProcesses = newGPU
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
                
                // History and one bar per thread, system time in the theme's
                // second color behind user time in its main color.
                let total = monitor.snapshot.cpuHistory
                if total.count >= 2 {
                    ColumnHistoryGraph(layers: [total, MenuBarGraphGeometry.userShares(total: total,
                                                                                       system: monitor.snapshot.cpuSystemHistory)],
                                       inks: [.secondary, .primary])
                        .frame(height: 40)
                }
                let cores = monitor.snapshot.cores
                if !cores.isEmpty {
                    CoreBarsGraph(layers: [cores.map { Double($0.loadPct) / 100 },
                                           cores.map { Double(max(0, $0.loadPct - $0.systemPct)) / 100 }],
                                  inks: [.secondary, .primary])
                        .frame(height: 32)
                }

                let usage = monitor.snapshot.cpuUsage ?? 0
                let system = min(usage, monitor.snapshot.cpuSystemUsage ?? 0)
                GraphThemeReader { colors in
                    HStack {
                        legendItem(color: colors.primary, label: l10n.s.istatsUser,
                                   value: String(format: "%.0f%%", max(0, usage - system) * 100))
                        Spacer()
                        legendItem(color: colors.secondary, label: l10n.s.istatsSystem,
                                   value: String(format: "%.0f%%", system * 100))
                        Spacer()
                        legendItem(color: nil, label: l10n.s.istatsCores.localizedCapitalized,
                                   value: "\(cores.count)")
                    }
                }

                // Top CPU Processes (iStats-style)
                if !cpuProcesses.isEmpty {
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.s.istatsProcesses)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        ForEach(cpuProcesses) { proc in
                            IStatsProcessRow(proc: proc, formattedValue: String(format: "%.1f%%", proc.value), fallbackIconName: "cpu")
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(showCPU ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(showCPU ? 1.0 : 0.4)
            
        case .cores:
            // 2. Core Grid/Histograms
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(l10n.s.istatsCores) (\(monitor.snapshot.cores.count))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                    Spacer()
                    if editing {
                        cardControls(for: .cores)
                    }
                }
                
                let cores = monitor.snapshot.cores
                let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(cores) { core in
                        let load = Double(core.loadPct) / 100
                        IStatsDonutMeter(
                            title: "C\(core.id)",
                            value: String(format: "%.0f%%", load * 100),
                            values: [load, Double(max(0, core.loadPct - core.systemPct)) / 100],
                            inks: [.secondary, .primary]
                        )
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(showCores ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(showCores ? 1.0 : 0.4)
            
        case .memory:
            // 3. Memory Pressure Donut & Storage Breakdown + Top RAM Processes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l10n.s.memorySection.localizedUppercase)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    if editing {
                        cardControls(for: .memory)
                    } else {
                        let usedGB = Double(monitor.snapshot.memoryUsed ?? 0) / (1024 * 1024 * 1024)
                        let totalGB = Double(monitor.snapshot.memoryTotal ?? 1) / (1024 * 1024 * 1024)
                        Text(String(format: "%.1f / %.0f GB", usedGB, totalGB))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                let used = Double(monitor.snapshot.memoryUsed ?? 0)
                let total = Double(max(1, monitor.snapshot.memoryTotal ?? 1))
                let app = min(used, Double(monitor.snapshot.memoryAppUsed ?? 0))
                let compressed = Double(monitor.snapshot.memoryCompressed ?? 0)
                let ramFrac = min(1.0, max(0.0, used / total))

                HStack(spacing: 16) {
                    IStatsDonutMeter(
                        title: "RAM",
                        value: String(format: "%.0f%%", ramFrac * 100),
                        values: [ramFrac, app / total],
                        inks: [.secondary, .primary]
                    )

                    GraphThemeReader { colors in
                        VStack(alignment: .leading, spacing: 4) {
                            memoryRow(color: colors.primary, label: l10n.s.istatsAppMemory, bytes: app)
                            memoryRow(color: colors.secondary, label: l10n.s.memoryMetricUsed, bytes: used)
                            memoryRow(color: nil, label: l10n.s.istatsCompressedMemory, bytes: compressed)
                            memoryRow(color: nil, label: l10n.s.istatsFreeMemory, bytes: max(0, total - used))
                        }
                    }
                }

                let usedHistory = monitor.snapshot.memoryHistory
                if usedHistory.count >= 2 {
                    ColumnHistoryGraph(layers: [usedHistory, monitor.snapshot.memoryAppHistory],
                                       inks: [.secondary, .primary])
                        .frame(height: 32)
                }

                // Top Memory Processes
                if !memProcesses.isEmpty {
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.s.istatsProcesses)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        ForEach(memProcesses) { proc in
                            let valGB = proc.value / (1024 * 1024 * 1024)
                            let formattedMem = valGB >= 1.0
                                ? String(format: "%.1f GB", valGB)
                                : String(format: "%.0f MB", proc.value / (1024 * 1024))
                            IStatsProcessRow(proc: proc, formattedValue: formattedMem, fallbackIconName: "memorychip")
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(showMemory ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(showMemory ? 1.0 : 0.4)
            
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
                
                let gpuPct = monitor.snapshot.gpuUsage ?? 0
                let memPct: Double? = {
                    if let used = monitor.snapshot.gpuMemoryUsed, let total = monitor.snapshot.gpuMemoryTotal, total > 0 {
                        return Double(used) / Double(total)
                    }
                    return nil
                }()
                let gpuTemp = monitor.snapshot.gpuTemperature ?? 0
                let rawFreq = monitor.snapshot.gpuFreq ?? 0
                let gpuFreqGHz = rawFreq / 1000.0
                let maxFreqGHz = max(2.5, gpuFreqGHz)
                
                HStack {
                    Spacer()
                    IStatsDonutMeter(title: "GPU", value: String(format: "%.0f%%", gpuPct * 100), fraction: gpuPct, ink: .primary)
                    Spacer()
                    IStatsDonutMeter(title: "MEM", value: memPct.map { String(format: "%.0f%%", $0 * 100) } ?? "--", fraction: memPct ?? 0, ink: .secondary)
                    Spacer()
                    IStatsDonutMeter(title: "TMP", value: gpuTemp > 0 ? String(format: "%.0f°", gpuTemp) : "--", fraction: min(1.0, gpuTemp / 100.0), ink: .tertiary)
                    Spacer()
                    IStatsDonutMeter(title: "GHZ", value: gpuFreqGHz > 0 ? String(format: "%.1f", gpuFreqGHz) : "--", fraction: min(1.0, gpuFreqGHz / maxFreqGHz), ink: .primary)
                    Spacer()
                }

                if monitor.snapshot.gpuHistory.count >= 2 {
                    ColumnHistoryGraph(layers: [monitor.snapshot.gpuHistory], inks: [.primary])
                        .frame(height: 32)
                }
                
                // Top GPU Processes (iStats-style)
                if !gpuProcesses.isEmpty {
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.s.istatsProcesses)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                        ForEach(gpuProcesses) { proc in
                            IStatsProcessRow(proc: proc, formattedValue: String(format: "%.1f%%", proc.value), fallbackIconName: "display")
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(showGPU ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(showGPU ? 1.0 : 0.4)
        }
    }

    /// A legend entry: the graph color's dot (none for a plain count), the
    /// label and the value.
    private func legendItem(color: Color?, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }

    private func memoryRow(color: Color?, label: String, bytes: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color ?? Color.primary.opacity(0.15)).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.1f GB", bytes / (1024 * 1024 * 1024)))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }
}

struct IStatsProcessRow: View {
    let proc: ProcessUsage
    let formattedValue: String
    let fallbackIconName: String
    @State private var showingDetail = false

    var body: some View {
        Button {
            ProcessInspectorWindowController.shared.present(for: proc)
        } label: {
            HStack(spacing: 6) {
                if let icon = NSRunningApplication(processIdentifier: proc.pid)?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: fallbackIconName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text(proc.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
