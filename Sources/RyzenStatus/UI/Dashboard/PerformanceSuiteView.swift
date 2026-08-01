// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// World-Class RyzenStatus Performance Suite Dashboard View porting the full rich UI
/// suite from mac-performance-monitor into RyzenStatus's Modular Feature Catalog.
struct PerformanceSuiteView: View {
    @ObservedObject var monitor: SystemMonitor

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case insights = "Insights"
        case analytics = "Analytics"
        case energy = "Energy"
        case network = "Network"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .insights: return "lightbulb.fill"
            case .analytics: return "chart.xyaxis.line"
            case .energy: return "bolt.batteryblock.fill"
            case .network: return "network"
            }
        }
    }

    @State private var selectedTab: Tab = .dashboard
    @State private var topProcesses: [ProcessUsage] = []
    @State private var insightCards: [InsightCard] = []
    @State private var energyRecords: [ProcessEnergyRecord] = []
    @State private var networkAdapters: [NetworkAdapterInfo] = []
    @State private var selectedInsightFilter: String = "All"
    @State private var selectedProcess: ProcessUsage? = nil

    @ObservedObject var l10n = L10n.shared

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    @ObservedObject private var runtime = FeatureRuntime.shared

    private var availableTabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .dashboard:
                return true
            case .insights:
                return AppFeature.monitorInsights.isAvailable
            case .analytics:
                return AppFeature.monitorAnalytics.isAvailable
            case .energy:
                return AppFeature.monitorEnergy.isAvailable
            case .network:
                return AppFeature.monitorNetworkDetails.isAvailable || AppFeature.monitorNetwork.isAvailable
            }
        }
    }

    var body: some View {
        let strings = FeatureStrings.performanceSuite(l10n.language)
        VStack(spacing: 0) {
            // --- TOP NAVIGATION & HEADER BAR ---
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(strings.title)
                            .font(.system(size: 15, weight: .bold))
                        Text(cpuBrandSubtitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()

                // Tab Selector Buttons
                HStack(spacing: 4) {
                    ForEach(availableTabs) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                let title: String = {
                                    switch tab {
                                    case .dashboard: return strings.dashboardTab
                                    case .insights: return strings.insightsTab
                                    case .analytics: return strings.analyticsTab
                                    case .energy: return strings.energyTab
                                    case .network: return strings.networkTab
                                    }
                                }()
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()

            // --- MAIN CONTENT RAIL ---
            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .dashboard:
                        dashboardTabContent
                    case .insights:
                        insightsTabContent
                    case .analytics:
                        analyticsTabContent
                    case .energy:
                        energyTabContent
                    case .network:
                        networkTabContent
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshData() }
        .onChange(of: selectedProcess) { _, proc in
            if let proc = proc {
                ProcessInspectorWindowController.shared.present(for: proc)
                selectedProcess = nil
            }
        }
    }

    // MARK: - 1. Dashboard Tab Content
    @ViewBuilder
    private var dashboardTabContent: some View {
        VStack(spacing: 16) {
            // Headline Metric Cards Row
            headlineMetricCardsGrid

            // BTop Cyberpunk Matrix & Process Manager
            BTopDashboardView(monitor: monitor)
        }
    }

    // Headline 4 Metric Cards Grid
    private var headlineMetricCardsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Card 1: CPU Total
            let cpuVal = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
            let cpuTemp = monitor.snapshot.cpuTemperature
            let cpuPwr = monitor.snapshot.cpuPower
            suiteMetricCard(
                title: "CPU TOTAL",
                value: String(format: "%.1f%%", cpuVal),
                subtitle: cpuTemp.map { String(format: "%.1f°C", $0) } ?? "AMD Zen 3",
                extraInfo: cpuPwr.map { String(format: "%.1f W", $0) } ?? "16C / 32T",
                accentColor: .cyan,
                history: monitor.snapshot.cpuHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 2: Memory Footprint
            let usedRAM = Double(monitor.snapshot.memoryUsed ?? 0) / 1_073_741_824.0
            let totalRAM = Double(monitor.snapshot.memoryTotal ?? 34_359_738_368) / 1_073_741_824.0
            let ramPct = totalRAM > 0 ? (usedRAM / totalRAM * 100.0) : 0.0
            suiteMetricCard(
                title: "RAM FOOTPRINT",
                value: String(format: "%.1f GB", usedRAM),
                subtitle: String(format: "%.0f%% Used", ramPct),
                extraInfo: String(format: "%.1f GB Total", totalRAM),
                accentColor: .purple,
                history: monitor.snapshot.memoryHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 3: GPU Compute
            let gpuVal = (monitor.snapshot.gpuUsage ?? 0.0) * 100.0
            let gpuTemp = monitor.snapshot.gpuTemperature
            let gpuPwr = monitor.snapshot.gpuPower
            suiteMetricCard(
                title: "GPU NAVI 21",
                value: String(format: "%.1f%%", gpuVal),
                subtitle: gpuTemp.map { String(format: "%.1f°C", $0) } ?? "RX 6800 XT",
                extraInfo: gpuPwr.map { String(format: "%.1f W", $0) } ?? "16GB VRAM",
                accentColor: .orange,
                history: monitor.snapshot.gpuHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 4: Network Live
            let netDown = monitor.snapshot.netDownBytesPerSec ?? 0.0
            let netUp = monitor.snapshot.netUpBytesPerSec ?? 0.0
            let netHistory = monitor.snapshot.netDownHistory.map { Double($0) }
            let maxNet = max(1000.0, netHistory.max() ?? 1000.0)
            suiteMetricCard(
                title: "NET BANDWIDTH",
                value: formatBytes(netDown) + "/s",
                subtitle: "↓ " + formatBytes(netDown) + "/s",
                extraInfo: "↑ " + formatBytes(netUp) + "/s",
                accentColor: .green,
                history: netHistory,
                maxDomain: maxNet
            )
        }
    }

    @ViewBuilder
    private func suiteMetricCard(title: String, value: String, subtitle: String, extraInfo: String, accentColor: Color, history: [Double], maxDomain: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(extraInfo)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(accentColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            let now = Date()
            let count = max(1, history.count)
            let points = history.enumerated().map { (idx, val) in
                TrendPoint(date: now.addingTimeInterval(Double(idx - count)), value: val)
            }

            TrendChart(
                series: [TrendSeries(points: points, color: accentColor, filled: true)],
                yDomain: 0...maxDomain
            )
            .frame(height: 38)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    // MARK: - 2. Insights Tab Content
    @ViewBuilder
    private var insightsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header & Filter Capsules
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Automated Diagnostic Engine")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Ranked findings from LeakDetector, memory pressure events, and process telemetries.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(["All", "Memory", "CPU", "Thermal", "Architecture"], id: \.self) { filter in
                        Button {
                            selectedInsightFilter = filter
                        } label: {
                            Text(filter)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedInsightFilter == filter ? Color.accentColor.opacity(0.2) : Color.clear)
                                .foregroundColor(selectedInsightFilter == filter ? .accentColor : .secondary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let filteredCards = insightCards.filter { card in
                selectedInsightFilter == "All" || card.categoryName.equalsIgnoreCase(selectedInsightFilter)
            }

            if filteredCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.green)
                    Text("System Operating at Peak Efficiency")
                        .font(.system(size: 14, weight: .bold))
                    Text("No continuous memory leaks, thermal throttling, or runaway CPU conditions detected.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
            } else {
                ForEach(filteredCards) { card in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(cardColor(for: card.severity).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: cardIcon(for: card.severity))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(cardColor(for: card.severity))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(card.title)
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text(card.categoryName.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                            }

                            Text(card.detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if let hint = card.actionHint {
                                HStack(spacing: 8) {
                                    Text("💡 \(hint)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                    
                                    Spacer()

                                    Button("Inspect Process") {
                                        if let pid = card.pid, let proc = topProcesses.first(where: { $0.pid == pid }) {
                                            selectedProcess = proc
                                        } else {
                                            selectedProcess = ProcessUsage(pid: card.pid ?? 0, name: card.title, value: 0.0)
                                        }
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(10)
                }
            }

            // Top Active Processes Inspector Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ACTIVE APPLICATIONS & PROCESS INSPECTOR")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(topProcesses.count) Active")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text("PID").frame(width: 55, alignment: .leading)
                        Text("PROCESS / APP NAME").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CATEGORY").frame(width: 140, alignment: .leading)
                        Text("CPU %").frame(width: 70, alignment: .trailing)
                        Text("ACTION").frame(width: 80, alignment: .center)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                    Divider()

                    ForEach(topProcesses.prefix(15)) { proc in
                        let entry = ProcessGlossary.resolve(name: proc.name, pid: proc.pid)
                        let catName = entry.category.rawValue.capitalized
                        HStack {
                            Text("\(proc.pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 55, alignment: .leading)

                            Text(proc.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(catName)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)

                            Text(String(format: "%.1f%%", proc.value))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(proc.value > 80.0 ? .red : (proc.value > 20.0 ? .orange : .primary))
                                .frame(width: 70, alignment: .trailing)

                            Button("Inspect") {
                                selectedProcess = proc
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .frame(width: 80, alignment: .center)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(4)
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(10)
        }
    }

    // MARK: - 3. Analytics Tab Content
    @ViewBuilder
    private var analyticsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Linear Regression & Long-Term Trend Analytics")
                    .font(.system(size: 14, weight: .bold))
                Text("R² confidence slope statistics and downsampled historical timeline curves.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                // Chart 1: CPU Load History (scaled to 0...100%)
                analyticsChartCard(
                    title: "CPU LOAD HISTORICAL TREND",
                    data: monitor.snapshot.cpuHistory.map { Double($0) * 100.0 },
                    lineColor: .cyan,
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 2: RAM Footprint History (scaled to 0...100%)
                analyticsChartCard(
                    title: "RAM FOOTPRINT TREND",
                    data: monitor.snapshot.memoryHistory.map { Double($0) * 100.0 },
                    lineColor: .purple,
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 3: GPU Compute History (scaled to 0...100%)
                analyticsChartCard(
                    title: "GPU COMPUTE TREND",
                    data: monitor.snapshot.gpuHistory.map { Double($0) * 100.0 },
                    lineColor: .orange,
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 4: Network Download Rate
                let netHist = monitor.snapshot.netDownHistory.map { Double($0) }
                let maxNet = max(1000.0, netHist.max() ?? 1000.0)
                analyticsChartCard(
                    title: "NETWORK DOWNLOAD BANDWIDTH",
                    data: netHist,
                    lineColor: .green,
                    yUnit: "B/s",
                    maxDomain: maxNet,
                    isBytes: true
                )
            }
        }
    }

    @ViewBuilder
    private func analyticsChartCard(title: String, data: [Double], lineColor: Color, yUnit: String, maxDomain: Double, isBytes: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                let avg = data.isEmpty ? 0.0 : (data.reduce(0, +) / Double(data.count))
                let avgText = isBytes ? (formatBytes(avg) + "/s") : String(format: "AVG: %.1f\(yUnit)", avg)
                Text(avgText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(lineColor)
            }

            let now = Date()
            let count = max(1, data.count)
            let points = data.enumerated().map { (idx, val) in
                TrendPoint(date: now.addingTimeInterval(Double(idx - count)), value: val)
            }

            TrendChart(
                series: [TrendSeries(points: points, color: lineColor, filled: true)],
                yDomain: 0...maxDomain,
                showsTimeAxis: true
            )
            .frame(height: 140)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - 4. Energy Tab Content
    @ViewBuilder
    private var energyTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "bolt.batteryblock.fill")
                            .foregroundColor(.orange)
                        Text("Process Energy Impact & Power Distribution")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Calculated power draw impact (CPU, GPU, and disk wakeups) per process.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Top Energy Impact Table
            VStack(spacing: 4) {
                HStack {
                    Text("PID").frame(width: 50, alignment: .leading)
                    Text("APPLICATION / PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("TYPE").frame(width: 80, alignment: .center)
                    Text("CPU %").frame(width: 70, alignment: .trailing)
                    Text("ENERGY IMPACT").frame(width: 120, alignment: .trailing)
                    Text("ACTION").frame(width: 70, alignment: .center)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

                Divider()

                ForEach(energyRecords.prefix(15)) { record in
                    HStack {
                        Text("\(record.pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Text(record.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(record.isApp ? "App" : "Daemon")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(record.isApp ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                            .foregroundColor(record.isApp ? .blue : .secondary)
                            .cornerRadius(4)
                            .frame(width: 80, alignment: .center)

                        Text(String(format: "%.1f%%", record.cpuPct))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 70, alignment: .trailing)

                        Text(String(format: "%.1f", record.energyScore))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(record.energyScore > 50.0 ? .red : (record.energyScore > 15.0 ? .orange : .green))
                            .frame(width: 120, alignment: .trailing)

                        Button("Inspect") {
                            selectedProcess = ProcessUsage(pid: record.pid, name: record.name, value: record.cpuPct)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .frame(width: 70, alignment: .center)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - 5. Network Tab Content
    @ViewBuilder
    private var networkTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.cyan)
                        Text("Active Network Adapters & Device Scanner")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Local network interfaces, assigned IP addresses, and active throughput.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(networkAdapters) { adapter in
                    HStack {
                        ZStack {
                            Circle()
                                .fill(adapter.isUp ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "network")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(adapter.isUp ? .green : .red)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(adapter.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("IP: \(adapter.ipAddress)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        let downRate = monitor.snapshot.netDownBytesPerSec ?? 0.0
                        let upRate = monitor.snapshot.netUpBytesPerSec ?? 0.0

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("↓ " + formatBytes(downRate) + "/s")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                            Text("↑ " + formatBytes(upRate) + "/s")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func refreshData() {
        topProcesses = ProcessUsageService.shared.topCPU(limit: 20)
        insightCards = InsightEngine.shared.evaluate(snapshot: monitor.snapshot, processes: topProcesses)
        energyRecords = EnergyImpactService.shared.calculateEnergyImpact(processes: topProcesses)
        networkAdapters = NetworkScannerService.shared.activeAdapters()
    }

    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", bytes / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", bytes / 1_048_576.0) }
        if bytes >= 1_024 { return String(format: "%.1f KB", bytes / 1_024.0) }
        return String(format: "%.0f B", bytes)
    }

    private var cpuBrandSubtitle: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        let brandName: String = {
            if size > 0 {
                var data = [CChar](repeating: 0, count: size)
                sysctlbyname("machdep.cpu.brand_string", &data, &size, nil, 0)
                let brand = String(cString: data).trimmingCharacters(in: .whitespacesAndNewlines)
                if !brand.isEmpty { return brand }
            }
            return "AMD Ryzen Processor"
        }()
        let threads = ProcessInfo.processInfo.processorCount
        let cores = max(1, threads / 2)
        return "\(brandName)  ·  \(cores)-Core / \(threads)-Thread"
    }

    private func cardColor(for severity: InsightSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func cardIcon(for severity: InsightSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

private extension String {
    func equalsIgnoreCase(_ other: String) -> Bool {
        return self.lowercased() == other.lowercased()
    }
}
