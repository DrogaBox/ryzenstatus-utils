// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

// MARK: - Native Activity Monitor / BTop Dashboard View
struct BTopDashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var topProcesses: [ProcessUsage] = []
    @State private var procSortMode: ProcSortMode = .cpu
    @Environment(\.colorScheme) private var colorScheme

    enum ProcSortMode: String, CaseIterable, Identifiable {
        case cpu = "CPU %"
        case memory = "MEM Usage"
        case gpu = "GPU %"
        var id: String { rawValue }
    }

    private var cpuColor: Color { PanelMetricColor.cyan(for: colorScheme) }
    private var memColor: Color { PanelMetricColor.purple(for: colorScheme) }
    private var netColor: Color { PanelMetricColor.green(for: colorScheme) }
    private var gpuColor: Color { PanelMetricColor.orange(for: colorScheme) }
    private var critColor: Color { PanelMetricColor.red(for: colorScheme) }

    /// Hardware-derived box title (brand + core/thread counts), computed once.
    private static let cpuBoxTitle: String = {
        let brand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let threads = ProcessInfo.processInfo.processorCount
        let cores = max(1, threads / 2)
        let name = brand.isEmpty ? "AMD Ryzen" : brand
        return "CPU · \(name) (\(cores)-Core / \(threads)-Thread)"
    }()

    var body: some View {
        VStack(spacing: 12) {
            // --- TOP ROW: CPU & SYSTEM OVERVIEW ---
            suiteBox(title: Self.cpuBoxTitle, icon: "cpu", accentColor: cpuColor) {
                HStack(spacing: 16) {
                    // Left: Total Load gauge + Sparkline
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Total Utilization")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            let cpuPct = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
                            Text(String(format: "%.1f%%", cpuPct))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(cpuColor)
                        }

                        // Load sparkline using TrendChart Canvas engine
                        if monitor.snapshot.cpuHistory.isEmpty {
                            Rectangle().fill(Color.clear).frame(height: 32)
                        } else {
                            let history = monitor.snapshot.cpuHistory
                            let now = Date()
                            let count = history.count
                            let points = history.enumerated().map {
                                TrendPoint(date: now.addingTimeInterval(Double($0.offset - count)), value: $0.element)
                            }
                            let series = TrendSeries(points: points, color: cpuColor, filled: true, lineWidth: 1.5)
                            TrendChart(series: [series], showsYAxis: false)
                                .frame(height: 32)
                        }

                        // Stats Badges
                        HStack(spacing: 10) {
                            if let temp = monitor.snapshot.cpuTemperature {
                                let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                                let tempStr = MetricFormat.temperatureCompact(temp, unit: unit)
                                statBadge(label: "Temp", val: tempStr, color: temp > 80 ? critColor : (temp > 65 ? gpuColor : netColor))
                            }
                            if let freq = monitor.snapshot.cpuFreqHistory.last {
                                statBadge(label: "Freq", val: String(format: "%.2f GHz", freq), color: cpuColor)
                            }
                            if let pwr = monitor.snapshot.cpuPower {
                                statBadge(label: "Power", val: String(format: "%.1f W", pwr), color: memColor)
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

            // --- MIDDLE ROW: MEMORY & NETWORK ---
            HStack(spacing: 12) {
                // MEMORY & STORAGE BOX
                suiteBox(title: "Memory & Storage", icon: "memorychip", accentColor: memColor) {
                    VStack(alignment: .leading, spacing: 8) {
                        let usedMem = monitor.snapshot.memoryUsed.map { Double($0) / 1073741824.0 }
                        let totalMem = monitor.snapshot.memoryTotal.map { Double($0) / 1073741824.0 }
                        let ramPct = (usedMem != nil && totalMem != nil && totalMem! > 0) ? (usedMem! / totalMem!) : 0.0
                        let ramStr = (usedMem != nil && totalMem != nil)
                            ? String(format: "%.1f / %.1f GB (%.0f%%)", usedMem!, totalMem!, ramPct * 100)
                            : "—"

                        nativeProgressBar(label: "RAM", valStr: ramStr, fraction: ramPct, color: memColor)

                        let gpuMemUsed = monitor.snapshot.gpuMemoryUsed
                        let gpuMemTotal = monitor.snapshot.gpuMemoryTotal
                        let gUsed = gpuMemUsed.map { Double($0) / 1073741824.0 }
                        let gTotal = gpuMemTotal.map { Double($0) / 1073741824.0 }
                        let gFrac = (gUsed != nil && gTotal != nil && gTotal! > 0) ? (gUsed! / gTotal!) : 0.0
                        let vramStr = (gUsed != nil && gTotal != nil)
                            ? String(format: "%.1f / %.1f GB", gUsed!, gTotal!)
                            : "—"
                        nativeProgressBar(label: "VRAM", valStr: vramStr, fraction: gFrac, color: gpuColor)

                        let read = monitor.snapshot.diskReadHistory.last ?? 0.0
                        let write = monitor.snapshot.diskWriteHistory.last ?? 0.0
                        HStack {
                            Text("Disk I/O")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "R: %.1f MB/s  W: %.1f MB/s", read / 1048576.0, write / 1048576.0))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(height: 80)
                }

                // NETWORK TRAFFIC BOX
                suiteBox(title: "Bandwidth & Traffic", icon: "network", accentColor: netColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        let downRate = monitor.snapshot.netDownBytesPerSec
                        let upRate = monitor.snapshot.netUpBytesPerSec

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(formatOptionalBytes(downRate))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(cpuColor)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Upload")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(formatOptionalBytes(upRate))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(netColor)
                            }
                        }

                        // Dual traffic sparkline
                        let rawDown = monitor.snapshot.netDownHistory
                        let downPoints: [Double] = rawDown.count >= 24 ? Array(rawDown.suffix(24)) : Array(repeating: 0.0, count: 24 - rawDown.count) + rawDown
                        let rawUp = monitor.snapshot.netUpHistory
                        let upPoints: [Double] = rawUp.count >= 24 ? Array(rawUp.suffix(24)) : Array(repeating: 0.0, count: 24 - rawUp.count) + rawUp
                        let peak = max(downPoints.max() ?? 0.0, upPoints.max() ?? 0.0)
                        let maxPeak = max(1.0, peak * 1.15)

                        ZStack {
                            Sparkline(values: downPoints, color: cpuColor, maxValue: maxPeak, fillOpacity: 0.20, lineWidth: 1.5, showsZeroBaseline: true)
                            Sparkline(values: upPoints, color: netColor, maxValue: maxPeak, fillOpacity: 0.0, lineWidth: 1.5)
                        }
                        .frame(height: 32)
                    }
                    .frame(height: 80)
                }
            }

            // --- BOTTOM ROW: TOP PROCESSES LIST ---
            suiteBox(title: "Process Manager", icon: "list.bullet.rectangle", accentColor: gpuColor) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Sort by:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $procSortMode) {
                            ForEach(ProcSortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)

                        Spacer()

                        Text("\(min(topProcesses.count, 10)) active processes")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Table Header
                    HStack {
                        Text("PID").lineLimit(1).frame(width: 55, alignment: .leading)
                        Text("Name").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Resource Value").lineLimit(1).frame(width: 120, alignment: .trailing)
                        Text("Action").lineLimit(1).frame(width: 60, alignment: .center)
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
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 6)
                                Text("Loading active processes...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
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
    }

    private func refreshProcesses() {
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
        let load = core.loadPct
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
                    .frame(width: max(0, 36 * CGFloat(load / 100.0)), height: 3)
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

    @State private var showingKillConfirm = false
    @Environment(\.colorScheme) private var colorScheme

    private var isProtectedPID: Bool {
        proc.pid <= 1 || proc.pid == getpid()
    }

    var body: some View {
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
                        case .memory:
                            let valGB = proc.value / (1024 * 1024 * 1024)
                            return valGB >= 1.0 ? String(format: "%.1f GB", valGB) : String(format: "%.0f MB", proc.value / (1024 * 1024))
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

            if !isProtectedPID {
                Button(action: {
                    showingKillConfirm = true
                }) {
                    Text("Kill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelMetricColor.red(for: colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PanelMetricColor.red(for: colorScheme).opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .frame(width: 60, alignment: .center)
                .confirmationDialog(
                    "Terminate \(proc.name) (PID: \(proc.pid))?",
                    isPresented: $showingKillConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Terminate", role: .destructive) {
                        if kill(proc.pid, SIGTERM) == 0 {
                            onKill()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to terminate this process?")
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
            Button("Inspect Process") {
                ProcessInspectorWindowController.shared.present(for: proc)
            }
            if !isProtectedPID {
                Divider()
                Button("Terminate Process", role: .destructive) {
                    showingKillConfirm = true
                }
            }
        }
    }
}
