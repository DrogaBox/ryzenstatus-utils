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

    /// The four cards' switches, as stored.
    struct Switches: Equatable {
        var cpu = true
        var cores = true
        var memory = true
        var gpu = true
    }

    /// The metric families the hub leaves on. A card whose family is off
    /// leaves the panel entirely, its row in the edit mode included.
    struct Families: Equatable {
        var cpu = true
        var memory = true
        var gpu = true

        static var current: Families {
            Families(cpu: AppFeature.monitorCPU.isAvailable, memory: AppFeature.monitorMemory.isAvailable,
                     gpu: AppFeature.monitorGPU.isAvailable)
        }
    }

    func isAvailable(_ families: Families) -> Bool {
        switch self {
        case .cpu, .cores: return families.cpu
        case .memory: return families.memory
        case .gpu: return families.gpu
        }
    }

    /// The core grid belongs to the CPU card: hiding the CPU hides it too.
    func isVisible(_ switches: Switches, families: Families = Families()) -> Bool {
        guard isAvailable(families) else { return false }
        switch self {
        case .cpu: return switches.cpu
        case .cores: return switches.cores && switches.cpu
        case .memory: return switches.memory
        case .gpu: return switches.gpu
        }
    }

    /// Whether the widget style has anything to show. The panel asks this,
    /// not the classic cards' switches, to decide if the widgets get a place.
    static func anyVisible(_ switches: Switches, families: Families = Families()) -> Bool {
        allCases.contains { $0.isVisible(switches, families: families) }
    }
}

/// When the widgets' process lists read, and which ones. Listing every
/// process is the dear part of the panel, so a list that is not on screen
/// is not read, and nothing is read between two beats.
enum IStatsProcessRefresh {
    static func interval(configured: Double) -> TimeInterval { max(0.5, configured) }

    static func isDue(last: Date?, now: Date, configured: Double) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        // A clock set back must not freeze the lists.
        return elapsed >= interval(configured: configured) || elapsed < 0
    }

    /// CPU and memory come out of one listing; the GPU costs a reading of
    /// its own. While the panel is arranged every card that can show does.
    static func kinds(_ switches: IStatsCardKind.Switches, families: IStatsCardKind.Families,
                      editing: Bool) -> [BreakdownKind] {
        func shows(_ card: IStatsCardKind) -> Bool {
            editing ? card.isAvailable(families) : card.isVisible(switches, families: families)
        }
        var kinds: [BreakdownKind] = []
        if shows(.cpu) { kinds.append(.cpu) }
        if shows(.memory) { kinds.append(.memory) }
        if shows(.gpu) { kinds.append(.gpu) }
        return kinds
    }
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
        // One element, the gauge's name and reading, instead of two loose texts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
    
    @AppStorage(DefaultsKey.panelWidgetShowCPU) private var showCPU = true
    @AppStorage(DefaultsKey.panelWidgetShowGPU) private var showGPU = true
    @AppStorage(DefaultsKey.panelWidgetShowMemory) private var showMemory = true
    @AppStorage(DefaultsKey.panelWidgetShowCores) private var showCores = true
    @AppStorage(DefaultsKey.panelWidgetOrder) private var rawCardOrder = "cpu,cores,memory,gpu"
    @AppStorage(DefaultsKey.processListRefreshInterval) private var processListRefreshInterval = 1.0
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    
    @State private var draggingCard: IStatsCardKind?
    @State private var cpuProcesses: [ProcessUsage] = []
    @State private var memProcesses: [ProcessUsage] = []
    @State private var gpuProcesses: [ProcessUsage] = []
    @State private var lastProcessRefresh: Date?
    
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
        card.isVisible(switches, families: families)
    }

    private var switches: IStatsCardKind.Switches {
        .init(cpu: showCPU, cores: showCores, memory: showMemory, gpu: showGPU)
    }

    private var families: IStatsCardKind.Families { .current }

    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    
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
                if isCardVisible(card) || (editing && card.isAvailable(families)) {
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
            refreshProcesses(force: true)
        }
        // The lists used to read only when they appeared, so they showed
        // whatever ran while the panel opened. The monitor's beat keeps them
        // current, and only while the panel is on this section.
        .onReceive(monitor.$snapshot) { _ in
            refreshProcesses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .processUsageDidUpdate)) { _ in
            updateProcesses()
        }
    }

    private func refreshProcesses(force: Bool = false) {
        let now = Date()
        guard force || (SystemMonitor.shared.menuPanelShowsSystem
            && IStatsProcessRefresh.isDue(last: lastProcessRefresh, now: now,
                                          configured: processListRefreshInterval)) else { return }
        lastProcessRefresh = now
        updateProcesses()
    }
    
    private func updateProcesses() {
        // Only the lists on screen, and no redraw for rows that did not change.
        for kind in IStatsProcessRefresh.kinds(switches, families: families, editing: editing) {
            let rows = ProcessUsageService.shared.top(kind, limit: 4)
            guard !rows.isEmpty else { continue }
            switch kind {
            case .cpu: if cpuProcesses != rows { cpuProcesses = rows }
            case .memory: if memProcesses != rows { memProcesses = rows }
            case .gpu: if gpuProcesses != rows { gpuProcesses = rows }
            case .energy, .network: break
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
                        // A reading that is not there says nothing, instead of 0.0 GHz.
                        let freqStr = monitor.snapshot.peakCPUFreq.flatMap { $0 > 0 ? String(format: "%.1f GHz", $0 / 1000.0) : nil }
                        let tempStr = monitor.snapshot.cpuTemperature.map {
                            MetricFormat.temperatureCompact($0, unit: temperatureUnit)
                        }
                        Text([freqStr, tempStr].compactMap { $0 }.joined(separator: ", "))
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
                            IStatsProcessRow(proc: proc, formattedValue: String(format: "%.1f%%", proc.value))
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
            // Hidden with the CPU card too: the grid goes where that one goes.
            .background(Color.primary.opacity(isCardVisible(.cores) ? 0.05 : 0.02))
            .cornerRadius(10)
            .opacity(isCardVisible(.cores) ? 1.0 : 0.4)
            
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
                            IStatsProcessRow(proc: proc, formattedValue: formattedMem)
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
                        let gpuFreqStr = monitor.snapshot.gpuFreq.flatMap { $0 > 0 ? String(format: "%.0f MHz", $0) : nil }
                        Text(gpuFreqStr ?? "")
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
                    IStatsDonutMeter(title: "TMP", value: gpuTemp > 0 ? MetricFormat.temperatureCompact(gpuTemp, unit: temperatureUnit) : "--", fraction: min(1.0, gpuTemp / 100.0), ink: .tertiary)
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
                            IStatsProcessRow(proc: proc, formattedValue: String(format: "%.1f%%", proc.value))
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

    var body: some View {
        Button {
            ProcessInspectorWindowController.shared.present(for: proc)
        } label: {
            HStack(spacing: 6) {
                // The cached icon the classic rows use: looking the app up on
                // every redraw of every row was the costly way.
                Image(nsImage: ResponsibleProcess.icon(for: proc.pid, pointSize: 14))
                    .resizable()
                    .frame(width: 14, height: 14)
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
        .help(proc.name)
    }
}
