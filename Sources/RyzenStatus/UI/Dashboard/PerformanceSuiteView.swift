// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Modern Mac Performance Suite Dashboard Window supporting 5 dedicated views:
/// 1. Dashboard (System Overview & Topology)
/// 2. Insights (Automated Diagnostic Cards)
/// 3. Analytics (R² Regression & History Trends)
/// 4. Energy (Process Impact & Battery Flow)
/// 5. Network (Adapters & Device Scanner)
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

    @ObservedObject var l10n = L10n.shared

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        let strings = FeatureStrings.performanceSuite(l10n.language)
        VStack(spacing: 0) {
            // --- TOP HEADER BAR & TAB PICKER ---
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text(strings.title)
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()

                // Tab Selector
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 5) {
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
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()

            // --- TAB CONTENT AREA ---
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
        .onAppear {
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .processUsageDidUpdate)) { _ in
            refreshData()
        }
    }

    // MARK: - 1. Dashboard Tab Content
    @ViewBuilder
    private var dashboardTabContent: some View {
        VStack(spacing: 14) {
            BTopDashboardView(monitor: monitor)
        }
    }

    // MARK: - 2. Insights Tab Content
    @ViewBuilder
    private var insightsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Automated Diagnostic Cards")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(insightCards.count) Active Insights")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if insightCards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("All Systems Operating Normally")
                        .font(.system(size: 13, weight: .bold))
                    Text("No memory leaks, thermal throttling, or CPU runaway conditions detected.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
            } else {
                ForEach(insightCards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: card.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(card.severity == .critical ? .red : (card.severity == .warning ? .orange : .blue))

                        VStack(alignment: .leading, spacing: 4) {
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
                                Text("💡 \(hint)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - 3. Analytics Tab Content
    @ViewBuilder
    private var analyticsTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Linear Regression & Trend History")
                .font(.system(size: 14, weight: .bold))

            HStack(spacing: 12) {
                let now = Date()
                let count = monitor.snapshot.cpuHistory.count
                // CPU History Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("CPU Load Trend (Canvas)")
                        .font(.system(size: 12, weight: .semibold))
                    let cpuPoints = monitor.snapshot.cpuHistory.enumerated().map { (idx, val) in
                        TrendPoint(date: now.addingTimeInterval(Double(idx - count)), value: Double(val))
                    }
                    TrendChart(
                        series: [TrendSeries(points: cpuPoints, color: .cyan, filled: true)],
                        yDomain: 0...100
                    )
                    .frame(height: 120)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)

                // RAM History Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("RAM Footprint Trend (Canvas)")
                        .font(.system(size: 12, weight: .semibold))
                    let ramCount = monitor.snapshot.memoryHistory.count
                    let ramPoints = monitor.snapshot.memoryHistory.enumerated().map { (idx, val) in
                        TrendPoint(date: now.addingTimeInterval(Double(idx - ramCount)), value: Double(val))
                    }
                    TrendChart(
                        series: [TrendSeries(points: ramPoints, color: .purple, filled: true)],
                        yDomain: 0...100
                    )
                    .frame(height: 120)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 4. Energy Tab Content
    @ViewBuilder
    private var energyTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.batteryblock.fill")
                    .foregroundColor(.orange)
                Text("Process Energy Impact Scores")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            VStack(spacing: 4) {
                HStack {
                    Text("PID").frame(width: 50, alignment: .leading)
                    Text("APP / PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU%").frame(width: 60, alignment: .trailing)
                    Text("ENERGY IMPACT").frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

                Divider()

                ForEach(energyRecords.prefix(10)) { record in
                    HStack {
                        Text("\(record.pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Text(record.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.1f%%", record.cpuPct))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)

                        Text(String(format: "%.1f", record.energyScore))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(record.energyScore > 50.0 ? .red : (record.energyScore > 15.0 ? .orange : .green))
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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
                Image(systemName: "network")
                    .foregroundColor(.cyan)
                Text("Active Network Adapters & Throughput")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            ForEach(networkAdapters) { adapter in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(adapter.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Image(systemName: adapter.isUp ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(adapter.isUp ? .green : .red)
                                .font(.system(size: 10))
                        }
                        Text("IP: \(adapter.ipAddress)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    let downRate = monitor.snapshot.netDownBytesPerSec ?? 0.0
                    let upRate = monitor.snapshot.netUpBytesPerSec ?? 0.0

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↓ \(formatBytes(downRate))/s")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text("↑ \(formatBytes(upRate))/s")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
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
        if bytes >= 1073741824 { return String(format: "%.1f GB", bytes / 1073741824.0) }
        if bytes >= 1048576 { return String(format: "%.1f MB", bytes / 1048576.0) }
        if bytes >= 1024 { return String(format: "%.1f KB", bytes / 1024.0) }
        return String(format: "%.0f B", bytes)
    }
}
