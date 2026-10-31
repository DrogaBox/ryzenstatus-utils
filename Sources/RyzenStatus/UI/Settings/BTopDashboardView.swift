// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

// MARK: - Native Activity Monitor / BTop Dashboard View
struct BTopDashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    var showCpuOverview: Bool = true
    /// False while the page is off screen or the Settings window is hidden:
    /// no `ps` refresh runs for nobody.
    var isActive: Bool = true
    @ObservedObject private var l10n = L10n.shared
    @State private var topProcesses: [ProcessUsage] = []
    @State private var procSortMode: ProcSortMode = .cpu
    @Environment(\.colorScheme) private var colorScheme

    enum ProcSortMode: String, CaseIterable, Identifiable {
        case cpu
        case memory
        case gpu
        var id: String { rawValue }

        func title(_ strings: PerformanceSuiteFeatureStrings) -> String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return strings.memoryColumn
            case .gpu: return "GPU"
            }
        }
    }

    private var cpuColor: Color { PanelMetricColor.cyan(for: colorScheme) }
    private var memColor: Color { PanelMetricColor.purple(for: colorScheme) }
    private var netColor: Color { PanelMetricColor.green(for: colorScheme) }
    private var gpuColor: Color { PanelMetricColor.orange(for: colorScheme) }
    private var critColor: Color { PanelMetricColor.red(for: colorScheme) }

    private static let cpuBrand: String = {
        let brand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "AMD Ryzen" : brand
    }()

    /// Hardware-derived box title: brand plus the kernel's core and thread
    /// counts (cores are not threads / 2 once SMT is off).
    private var cpuBoxTitle: String {
        "CPU · \(Self.cpuBrand) (" + String(format: l10n.dashboard.cpuTopologyFormat,
                                            SystemMonitor.hostPhysicalCoreCount,
                                            ProcessInfo.processInfo.processorCount) + ")"
    }

    var body: some View {
        let strings = l10n.dashboard
        let suite = FeatureStrings.performanceSuite(l10n.language)
        VStack(spacing: 12) {
            if showCpuOverview {
                // --- TOP ROW: CPU & SYSTEM OVERVIEW ---
                suiteBox(title: cpuBoxTitle, icon: "cpu", accentColor: cpuColor) {
                HStack(spacing: 16) {
                    // Left: Total Load gauge + load history
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(strings.totalUtilization)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            // No reading yet (launch, wake) is a dash, never 0 %.
                            Text(monitor.snapshot.cpuUsage.map { String(format: "%.1f%%", $0 * 100.0) } ?? "—")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(cpuColor)
                        }

                        // Load history as columns
                        if monitor.snapshot.cpuHistory.isEmpty {
                            Rectangle().fill(Color.clear).frame(height: 32)
                        } else {
                            ColumnHistoryGraph(layers: [monitor.snapshot.cpuHistory], inks: [.fixed(cpuColor)])
                                .frame(height: 32)
                        }

                        // Stats Badges
                        HStack(spacing: 10) {
                            if let temp = monitor.snapshot.cpuTemperature {
                                let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                                let tempStr = MetricFormat.temperatureCompact(temp, unit: unit)
                                statBadge(label: strings.temperatureShort, val: tempStr, color: temp > 80 ? critColor : (temp > 65 ? gpuColor : netColor))
                            }
                            if let freq = monitor.snapshot.cpuFreqHistory.last {
                                statBadge(label: strings.frequencyShort, val: String(format: "%.2f GHz", freq), color: cpuColor)
                            }
                            if let pwr = monitor.snapshot.cpuPower {
                                statBadge(label: strings.powerShort, val: String(format: "%.1f W", pwr), color: memColor)
                            }
                        }
                    }
                    .frame(maxWidth: 240)

                    Divider()

                    // Right: Multi-Thread Grid (4 columns)
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

            // --- MIDDLE ROW: MEMORY & NETWORK ---
            HStack(spacing: 12) {
                // MEMORY & STORAGE BOX
                suiteBox(title: strings.memoryAndStorage, icon: "memorychip", accentColor: memColor) {
                    VStack(alignment: .leading, spacing: 8) {
                        let usedMem = monitor.snapshot.memoryUsed
                        let totalMem = monitor.snapshot.memoryTotal
                        let ramFraction = usedMem.flatMap { used in
                            totalMem.flatMap { $0 > 0 ? Double(used) / Double($0) : nil }
                        }
                        let ramStr = usedAndTotal(usedMem, totalMem, fraction: ramFraction)
                        nativeProgressBar(label: "RAM", valStr: ramStr, fraction: ramFraction ?? 0, color: memColor)

                        // An unknown VRAM size stays unknown: no bar, no
                        // borrowed total.
                        let gpuMemUsed = monitor.snapshot.gpuMemoryUsed
                        let gpuMemTotal = monitor.snapshot.gpuMemoryTotal
                        let vramFraction = gpuMemUsed.flatMap { used in
                            gpuMemTotal.flatMap { $0 > 0 ? Double(used) / Double($0) : nil }
                        }
                        let vramStr = usedAndTotal(gpuMemUsed, gpuMemTotal, fraction: nil)
                        nativeProgressBar(label: "VRAM", valStr: vramStr, fraction: vramFraction ?? 0, color: gpuColor)

                        HStack {
                            Text(strings.diskIO)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(diskRates(strings))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(height: 80)
                }

                // NETWORK TRAFFIC BOX
                suiteBox(title: strings.networkTraffic, icon: "network", accentColor: netColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        let downRate = monitor.snapshot.netDownBytesPerSec
                        let upRate = monitor.snapshot.netUpBytesPerSec

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suite.rxColumn)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(rate(downRate))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(cpuColor)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(suite.txColumn)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(rate(upRate))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(netColor)
                            }
                        }

                        // Upload above, download below, each on its own scale.
                        DualColumnHistoryGraph(upper: monitor.snapshot.netUpHistory,
                                               lower: monitor.snapshot.netDownHistory,
                                               upperInk: .fixed(netColor),
                                               lowerInk: .fixed(cpuColor))
                            .frame(height: 32)
                    }
                    .frame(height: 80)
                }
            }

            // --- BOTTOM ROW: TOP PROCESSES LIST ---
            suiteBox(title: strings.processManager, icon: "list.bullet.rectangle", accentColor: gpuColor) {
                VStack(spacing: 8) {
                    HStack {
                        Text(strings.sortBy)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker(strings.sortBy, selection: $procSortMode) {
                            ForEach(ProcSortMode.allCases) { mode in
                                Text(mode.title(suite)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)

                        Spacer()

                        Text(String(format: strings.processCountFormat, min(topProcesses.count, 10)))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Table Header
                    HStack {
                        Text("PID").lineLimit(1).frame(width: 55, alignment: .leading)
                        Text(suite.processColumn).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(strings.usageColumn).lineLimit(1).frame(width: 120, alignment: .trailing)
                        Text(suite.actionColumn).lineLimit(1).frame(width: 60, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)

                    Divider()

                    // Process Rows
                    VStack(spacing: 4) {
                        if topProcesses.isEmpty {
                            HStack {
                                Spacer()
                                // A GPU whose driver attributes no time to any
                                // process says so, once a real delta sample
                                // exists; before that the list is still loading.
                                if procSortMode == .gpu && ProcessUsageService.shared.hasGPUDeltaSample {
                                    Text(strings.noGPUProcesses)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 6)
                                    Text(strings.loadingProcesses)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        } else {
                            ForEach(topProcesses.prefix(10)) { proc in
                                BTopProcessRow(proc: proc, procSortMode: procSortMode, accentColor: gpuColor) {
                                    refreshProcesses()
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshProcesses()
        }
        .onReceive(monitor.$snapshot) { _ in
            refreshProcesses()
        }
        .onChange(of: procSortMode) { _, _ in
            refreshProcesses()
        }
        .onChange(of: isActive) { _, active in
            if active { refreshProcesses() }
        }
    }

    private func refreshProcesses() {
        guard isActive else { return }
        let procs: [ProcessUsage]
        switch procSortMode {
        case .cpu:
            procs = ProcessUsageService.shared.topCPU(limit: 10)
        case .memory:
            procs = ProcessUsageService.shared.topMemory(limit: 10)
        case .gpu:
            procs = ProcessUsageService.shared.topGPU(limit: 10)
        }
        if self.topProcesses != procs {
            self.topProcesses = procs
        }
    }

    /// A rate in the user's bits or bytes preference, or a dash when there
    /// is no reading.
    private func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return MetricFormat.networkRate(value)
    }

    /// "used / total (pct)", or a dash while either side is unknown.
    private func usedAndTotal(_ used: UInt64?, _ total: UInt64?, fraction: Double?) -> String {
        guard let used, let total, total > 0 else { return "—" }
        let text = "\(MetricFormat.bytes(used)) / \(MetricFormat.bytes(total))"
        guard let fraction else { return text }
        return text + String(format: " (%.0f%%)", fraction * 100)
    }

    /// This tick's disk rates from the snapshot, not the last history push
    /// (which can be an old sample); a dash when no device reports one.
    private func diskRates(_ strings: DashboardFeatureStrings) -> String {
        let devices = monitor.snapshot.disk?.uniqueIODevices ?? []
        let reads = devices.compactMap(\.readBytesPerSec)
        let writes = devices.compactMap(\.writeBytesPerSec)
        guard !reads.isEmpty || !writes.isEmpty else { return "—" }
        return String(format: strings.diskReadWriteFormat,
                      reads.isEmpty ? "—" : MetricFormat.bytesPerSec(reads.reduce(0, +)),
                      writes.isEmpty ? "—" : MetricFormat.bytesPerSec(writes.reduce(0, +)))
    }

    @ViewBuilder
    private func suiteBox<Content: View>(title: String, icon: String, accentColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            content()
        }
        .suiteCard(padding: 12)
    }

    @ViewBuilder
    private func statBadge(label: String, val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(val)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private func threadCell(core: CoreSnapshot) -> some View {
        // Clamped so a bad sample can never draw past the cell.
        let load = min(100, max(0, core.loadPct))
        let cellColor = load > 85 ? critColor : (load > 50 ? gpuColor : netColor)
        let label = core.isLogical ? "T\(core.id + 1)" : "C\(core.id + 1)"

        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(load))%")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundColor(cellColor)
            }

            // High performance progress bar without GeometryReader
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(cellColor)
                    .frame(width: 36 * CGFloat(load / 100.0), height: 3)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func nativeProgressBar(label: String, valStr: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(valStr)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0, fraction)))))
                }
            }
            .frame(height: 5)
        }
    }
}

struct BTopProcessRow: View {
    let proc: ProcessUsage
    let procSortMode: BTopDashboardView.ProcSortMode
    let accentColor: Color
    let onKill: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var showingKillConfirm = false
    /// The kernel start time read when the user asked to terminate: the
    /// kill goes only to that exact process, never to a reused pid.
    @State private var killStartTime: UInt64?
    @Environment(\.colorScheme) private var colorScheme

    /// The same gate as the process manager: the feature is on and the
    /// process is not one the system needs.
    private var canKill: Bool {
        AppFeature.killProcess.isAvailable && !KillProcessService.isProtected(pid: proc.pid, name: proc.name)
    }

    /// The row's pid can be a cached one; it is killed only if it still
    /// names the same app, through KillProcessService's safe path.
    private func requestKill() {
        guard let startedAt = KillProcessService.startTime(for: proc.pid),
              ResponsibleProcess.displayName(pid: proc.pid, fallback: proc.name) == proc.name else {
            onKill()
            return
        }
        killStartTime = startedAt
        showingKillConfirm = true
    }

    var body: some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        HStack {
            Button {
                ProcessInspectorWindowController.shared.present(for: proc)
            } label: {
                HStack {
                    Text("\(proc.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .leading)

                    Text(proc.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let valStr: String = {
                        switch procSortMode {
                        case .cpu: return String(format: "%.1f%% CPU", proc.value)
                        case .memory: return MetricFormat.bytes(UInt64(max(0, proc.value)))
                        case .gpu: return String(format: "%.1f%% GPU", proc.value)
                        }
                    }()

                    Text(valStr)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canKill {
                Button(action: requestKill) {
                    Text(l10n.dashboard.killShort)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelMetricColor.red(for: colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PanelMetricColor.red(for: colorScheme).opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .frame(width: 60, alignment: .center)
                .accessibilityLabel(suite.killButton)
                .confirmationDialog(
                    suite.killConfirmTitle,
                    isPresented: $showingKillConfirm,
                    titleVisibility: .visible
                ) {
                    Button(suite.killButton, role: .destructive) {
                        guard let startedAt = killStartTime else { return }
                        KillProcessService.shared.kill(pid: proc.pid, name: proc.name,
                                                       startedAt: startedAt, force: false) {
                            onKill()
                        }
                    }
                    Button(suite.killCancel, role: .cancel) {}
                } message: {
                    Text(String(format: suite.killConfirmMessage, proc.name, Int(proc.pid)))
                }
            } else {
                Spacer().frame(width: 60)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(4)
        .contextMenu {
            Button(suite.inspectButton) {
                ProcessInspectorWindowController.shared.present(for: proc)
            }
            if canKill {
                Divider()
                Button(suite.killButton, role: .destructive) {
                    requestKill()
                }
            }
        }
    }
}
