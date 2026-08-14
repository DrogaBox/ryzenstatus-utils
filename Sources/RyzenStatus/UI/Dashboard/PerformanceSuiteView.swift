// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// RyzenStatus Performance Suite Dashboard View porting rich monitoring features
/// into a native, unified Apple HIG design system matching Theme.swift.
struct PerformanceSuiteView: View {
    @ObservedObject var monitor: SystemMonitor

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case insights = "Insights"
        case analytics = "Analytics"
        case energy = "Energy"
        case network = "Network"

        var id: String { rawValue }

        func localizedTitle(strings: PerformanceSuiteFeatureStrings) -> String {
            switch self {
            case .dashboard: return strings.dashboardTab
            case .insights: return strings.insightsTab
            case .analytics: return strings.analyticsTab
            case .energy: return strings.energyTab
            case .network: return strings.networkTab
            }
        }

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

    @State private var cachedAdapters: [NetworkAdapterInfo] = []
    @State private var lastAdaptersRefresh = Date.distantPast
    @State private var refreshInFlight = false

    @ObservedObject var l10n = L10n.shared
    @ObservedObject private var runtime = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

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
        VStack(spacing: 12) {
            // --- TOP NAVIGATION & HEADER BAR ---
            HStack {
                Text(strings.title)
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                if availableTabs.count > 1 {
                    Picker("", selection: $selectedTab) {
                        ForEach(availableTabs) { tab in
                            Text(tab.localizedTitle(strings: strings)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 540)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // --- SCROLLABLE TAB CONTENT ---
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch selectedTab {
                    case .dashboard:
                        dashboardTabContent(strings: strings)
                    case .insights:
                        insightsTabContent(strings: strings)
                    case .analytics:
                        analyticsTabContent(strings: strings)
                    case .energy:
                        energyTabContent(strings: strings)
                    case .network:
                        networkTabContent(strings: strings)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            SystemMonitor.shared.panelDidAppear()
            refreshData()
        }
        .onDisappear {
            SystemMonitor.shared.panelDidDisappear()
        }
        .onChange(of: selectedTab) { _, _ in
            refreshData()
        }
        .onChange(of: runtime.revision) { _, _ in
            if !availableTabs.contains(selectedTab) {
                selectedTab = .dashboard
            }
            refreshData()
        }
        .onReceive(monitor.$snapshot) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .processUsageDidUpdate)) { _ in
            refreshData()
        }
    }

    // MARK: - 1. Dashboard Tab Content
    @ViewBuilder
    private func dashboardTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(spacing: 14) {
            // CPU brand hardware caption
            HStack {
                Text(Self.cpuBrandSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 2)

            // Headline Metric Cards Row
            headlineMetricCardsGrid(strings: strings)

            // Activity Monitor Matrix & Process Manager
            BTopDashboardView(monitor: monitor)
        }
    }

    // Headline 4 Metric Cards Grid
    @ViewBuilder
    private func headlineMetricCardsGrid(strings: PerformanceSuiteFeatureStrings) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Card 1: CPU Total
            let cpuVal = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
            let cpuTemp = monitor.snapshot.cpuTemperature
            let cpuPwr = monitor.snapshot.cpuPower
            let cpuThreads = ProcessInfo.processInfo.processorCount
            let cpuCores = max(1, cpuThreads / 2)
            let tempUnit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
            let cpuColor = PanelMetricColor.cyan(for: colorScheme)
            suiteMetricCard(
                title: strings.cpuTotal,
                value: String(format: "%.1f%%", cpuVal),
                subtitle: cpuTemp.map { MetricFormat.temperatureCompact($0, unit: tempUnit) } ?? "—",
                extraInfo: cpuPwr.map { String(format: "%.1f W", $0) } ?? "\(cpuCores)C / \(cpuThreads)T",
                accentColor: cpuColor,
                history: monitor.snapshot.cpuHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 2: Memory Footprint (RAM Used)
            let usedRAM = monitor.snapshot.memoryUsed.map { Double($0) / 1_073_741_824.0 }
            let totalRAM = monitor.snapshot.memoryTotal.map { Double($0) / 1_073_741_824.0 }
            let ramPct = (usedRAM != nil && totalRAM != nil && totalRAM! > 0) ? (usedRAM! / totalRAM! * 100.0) : 0.0
            let valStr = usedRAM.map { String(format: "%.1f GB", $0) } ?? "—"
            let subStr = usedRAM != nil ? String(format: "%.0f%% Used", ramPct) : "—"
            let extraStr = totalRAM.map { String(format: "%.1f GB Total", $0) } ?? "—"
            let memColor = PanelMetricColor.purple(for: colorScheme)
            suiteMetricCard(
                title: strings.memoryFootprint,
                value: valStr,
                subtitle: subStr,
                extraInfo: extraStr,
                accentColor: memColor,
                history: monitor.snapshot.memoryHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 3: GPU Compute
            let gpuVal = monitor.snapshot.gpuUsage.map { String(format: "%.1f%%", $0 * 100.0) } ?? "—"
            let gpuTemp = monitor.snapshot.gpuTemperature
            let gpuPwr = monitor.snapshot.gpuPower
            let gpuVRAMGB = monitor.snapshot.gpuMemoryTotal.map { Double($0) / 1_073_741_824.0 }
            let gpuColor = PanelMetricColor.orange(for: colorScheme)
            suiteMetricCard(
                title: "GPU",
                value: gpuVal,
                subtitle: gpuTemp.map { MetricFormat.temperatureCompact($0, unit: tempUnit) } ?? "—",
                extraInfo: gpuPwr.map { String(format: "%.1f W", $0) }
                    ?? gpuVRAMGB.map { String(format: "%.0f GB VRAM", $0) }
                    ?? "—",
                accentColor: gpuColor,
                history: monitor.snapshot.gpuHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 4: Network Live
            let netDown = monitor.snapshot.netDownBytesPerSec
            let netUp = monitor.snapshot.netUpBytesPerSec
            let netHistory = monitor.snapshot.netDownHistory.map { Double($0) }
            let maxNet = networkChartMax(netHistory)
            let netColor = PanelMetricColor.green(for: colorScheme)
            suiteMetricCard(
                title: strings.networkIO,
                value: formatOptionalBytes(netDown),
                subtitle: "↓ " + formatOptionalBytes(netDown),
                extraInfo: "↑ " + formatOptionalBytes(netUp),
                accentColor: netColor,
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(extraInfo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            let now = Date()
            let count = max(1, history.count)
            let points = history.enumerated().map { (idx, val) in
                TrendPoint(date: now.addingTimeInterval(Double(idx - count)), value: val)
            }

            TrendChart(
                series: [TrendSeries(points: points, color: accentColor, filled: true, lineWidth: 1.5)],
                yDomain: 0...maxDomain,
                showsYAxis: false
            )
            .frame(height: 36)
        }
        .suiteCard(padding: 10)
    }

    // MARK: - 2. Insights Tab Content
    @ViewBuilder
    private func insightsTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header & Filter Capsules
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(PanelMetricColor.yellow(for: colorScheme))
                        Text(strings.insightsTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(strings.insightsSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // D8: Dynamic categories based on active cards
                let availableFilters = ["All"] + Set(insightCards.map(\.categoryName)).sorted()
                if availableFilters.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(availableFilters, id: \.self) { filter in
                            Button {
                                selectedInsightFilter = filter
                            } label: {
                                Text(filter == "All" ? strings.filterAll : filter)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(selectedInsightFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .foregroundColor(selectedInsightFilter == filter ? .accentColor : .secondary)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let filteredCards = insightCards.filter { card in
                selectedInsightFilter == "All" || card.categoryName.equalsIgnoreCase(selectedInsightFilter)
            }

            if filteredCards.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(PanelMetricColor.green(for: colorScheme))
                    Text(strings.noInsights)
                        .font(.system(size: 13, weight: .semibold))
                    Text(strings.noInsightsSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .suiteCard()
            } else {
                ForEach(filteredCards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(cardColor(for: card.severity).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: cardIcon(for: card.severity))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(cardColor(for: card.severity))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(card.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(card.categoryName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                            }

                            Text(card.detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if let hint = card.actionHint {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb")
                                        .font(.system(size: 10))
                                    Text(hint)
                                        .font(.system(size: 10, weight: .medium))
                                    Spacer()

                                    if let pid = card.pid {
                                        Button(strings.inspectButton) {
                                            let proc = topProcesses.first(where: { $0.pid == pid })
                                                ?? ProcessUsage(pid: pid, name: card.title, value: 0.0)
                                            ProcessInspectorWindowController.shared.present(for: proc)
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .foregroundColor(.accentColor)
                                .padding(.top, 2)
                            }
                        }
                    }
                    .suiteCard(padding: 10)
                }
            }

            // Top Active Processes Inspector Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(strings.processColumn)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(topProcesses.count) Active")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text(strings.pidColumn).lineLimit(1).frame(width: 55, alignment: .leading)
                        Text(strings.processColumn).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(strings.typeColumn).lineLimit(1).frame(width: 120, alignment: .leading)
                        Text(strings.cpuColumn).lineLimit(1).frame(width: 70, alignment: .trailing)
                        Text(strings.actionColumn).lineLimit(1).frame(width: 70, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)

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
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(catName)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)

                            Text(String(format: "%.1f%%", proc.value))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(proc.value > 80.0 ? PanelMetricColor.red(for: colorScheme) : (proc.value > 20.0 ? PanelMetricColor.orange(for: colorScheme) : .primary))
                                .frame(width: 70, alignment: .trailing)

                            Button(strings.inspectButton) {
                                ProcessInspectorWindowController.shared.present(for: proc)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .frame(width: 70, alignment: .center)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(4)
                    }
                }
            }
            .suiteCard(padding: 12)
        }
    }

    // MARK: - 3. Analytics Tab Content
    @ViewBuilder
    private func analyticsTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.analyticsTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(strings.analyticsSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Chart 1: CPU Load History
                analyticsChartCard(
                    title: strings.cpuUtilization,
                    data: monitor.snapshot.cpuHistory.map { Double($0) * 100.0 },
                    lineColor: PanelMetricColor.cyan(for: colorScheme),
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 2: RAM Footprint History
                analyticsChartCard(
                    title: strings.memoryFootprint,
                    data: monitor.snapshot.memoryHistory.map { Double($0) * 100.0 },
                    lineColor: PanelMetricColor.purple(for: colorScheme),
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 3: GPU Compute History
                analyticsChartCard(
                    title: "GPU Compute",
                    data: monitor.snapshot.gpuHistory.map { Double($0) * 100.0 },
                    lineColor: PanelMetricColor.orange(for: colorScheme),
                    yUnit: "%",
                    maxDomain: 100.0
                )

                // Chart 4: Network Download Rate
                let netHist = monitor.snapshot.netDownHistory.map { Double($0) }
                let maxNet = networkChartMax(netHist)
                analyticsChartCard(
                    title: strings.networkIO,
                    data: netHist,
                    lineColor: PanelMetricColor.green(for: colorScheme),
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                let avg = data.isEmpty ? 0.0 : (data.reduce(0, +) / Double(data.count))
                let avgText = isBytes ? (formatBytes(avg) + "/s") : String(format: "AVG: %.1f\(yUnit)", avg)
                Text(avgText)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(lineColor)
            }

            let now = Date()
            let count = max(1, data.count)
            let points = data.enumerated().map { (idx, val) in
                TrendPoint(date: now.addingTimeInterval(Double(idx - count)), value: val)
            }

            TrendChart(
                series: [TrendSeries(points: points, color: lineColor, filled: true, lineWidth: 1.5)],
                yDomain: 0...maxDomain,
                showsTimeAxis: true
            )
            .frame(height: 130)
        }
        .suiteCard(padding: 12)
    }

    // MARK: - 4. Energy Tab Content
    @ViewBuilder
    private func energyTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.batteryblock.fill")
                            .foregroundColor(PanelMetricColor.yellow(for: colorScheme))
                        Text(strings.energyTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(strings.energySubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Top Energy Impact Table in suiteCard
            VStack(spacing: 4) {
                HStack {
                    Text(strings.pidColumn).lineLimit(1).frame(width: 55, alignment: .leading)
                    Text(strings.processColumn).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(strings.typeColumn).lineLimit(1).frame(width: 80, alignment: .center)
                    Text(strings.cpuColumn).lineLimit(1).frame(width: 70, alignment: .trailing)
                    Text(strings.energyScoreColumn).lineLimit(1).frame(width: 110, alignment: .trailing)
                    Text(strings.actionColumn).lineLimit(1).frame(width: 70, alignment: .center)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)

                Divider()

                ForEach(energyRecords.prefix(15)) { record in
                    HStack {
                        Text("\(record.pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .leading)

                        Text(record.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(record.isApp ? "App" : "Daemon")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(record.isApp ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                            .foregroundColor(record.isApp ? .blue : .secondary)
                            .cornerRadius(4)
                            .frame(width: 80, alignment: .center)

                        Text(String(format: "%.1f%%", record.cpuPct))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)

                        Text(String(format: "%.1f", record.energyScore))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(record.energyScore > 50.0 ? PanelMetricColor.red(for: colorScheme) : (record.energyScore > 15.0 ? PanelMetricColor.orange(for: colorScheme) : PanelMetricColor.green(for: colorScheme)))
                            .frame(width: 110, alignment: .trailing)

                        Button(strings.inspectButton) {
                            let proc = ProcessUsage(pid: record.pid, name: record.name, value: record.cpuPct)
                            ProcessInspectorWindowController.shared.present(for: proc)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .frame(width: 70, alignment: .center)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(4)
                }
            }
            .suiteCard(padding: 12)
        }
    }

    // MARK: - 5. Network Tab Content
    @ViewBuilder
    private func networkTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .foregroundColor(PanelMetricColor.green(for: colorScheme))
                        Text(strings.networkTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(strings.networkSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Summary Card
            let downRate = monitor.snapshot.netDownBytesPerSec
            let upRate = monitor.snapshot.netUpBytesPerSec
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.rxColumn)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatOptionalBytes(downRate))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(PanelMetricColor.cyan(for: colorScheme))
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.txColumn)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatOptionalBytes(upRate))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(PanelMetricColor.green(for: colorScheme))
                }
                Spacer()
            }
            .suiteCard(padding: 12)

            if networkAdapters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(strings.noNetworkAdapters)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .suiteCard()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(networkAdapters) { adapter in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(adapter.isUp ? PanelMetricColor.green(for: colorScheme).opacity(0.15) : PanelMetricColor.red(for: colorScheme).opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "network")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(adapter.isUp ? PanelMetricColor.green(for: colorScheme) : PanelMetricColor.red(for: colorScheme))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(adapter.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("IP: \(adapter.ipAddress)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("↓ " + formatOptionalBytes(adapter.rxBytesPerSec))
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(PanelMetricColor.cyan(for: colorScheme))
                                Text("↑ " + formatOptionalBytes(adapter.txBytesPerSec))
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(PanelMetricColor.green(for: colorScheme))
                            }
                        }
                        .suiteCard(padding: 10)
                    }
                }
            }
        }
    }

    private func refreshData() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let currentTab = selectedTab
        let adaptersStale = Date().timeIntervalSince(lastAdaptersRefresh) >= 10
        let cached = cachedAdapters

        Task.detached(priority: .userInitiated) {
            var procs: [ProcessUsage] = []
            var cards: [InsightCard] = []
            var energy: [ProcessEnergyRecord] = []
            var adapters: [NetworkAdapterInfo] = cached

            let snapshot = await MainActor.run { SystemMonitor.shared.snapshot }

            // P2: Gate heavy work by active tab
            switch currentTab {
            case .dashboard:
                procs = ProcessUsageService.shared.topCPU(limit: 20)
                _ = ProcessUsageService.shared.topMemory(limit: 10) // D4: feed LeakDetector
            case .insights:
                procs = ProcessUsageService.shared.topCPU(limit: 20)
                cards = InsightEngine.shared.evaluate(snapshot: snapshot, processes: procs)
            case .analytics:
                break
            case .energy:
                procs = ProcessUsageService.shared.topCPU(limit: 20)
                energy = EnergyImpactService.shared.calculateEnergyImpact(processes: procs)
            case .network:
                if adaptersStale {
                    adapters = NetworkScannerService.shared.activeAdapters()
                }
            }

            let outProcs = procs
            let outCards = cards
            let outEnergy = energy
            let outAdapters = adapters

            await MainActor.run {
                if !outProcs.isEmpty && self.topProcesses != outProcs {
                    self.topProcesses = outProcs
                }
                if self.insightCards != outCards {
                    self.insightCards = outCards
                }
                if self.energyRecords != outEnergy {
                    self.energyRecords = outEnergy
                }
                if adaptersStale && self.networkAdapters != outAdapters {
                    self.networkAdapters = outAdapters
                    self.cachedAdapters = outAdapters
                    self.lastAdaptersRefresh = Date()
                }
                self.refreshInFlight = false
            }
        }
    }

    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", bytes / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", bytes / 1_048_576.0) }
        if bytes >= 1_024 { return String(format: "%.1f KB", bytes / 1_024.0) }
        return String(format: "%.0f B", bytes)
    }

    private func formatOptionalBytes(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        return formatBytes(bytes) + "/s"
    }

    private func networkChartMax(_ values: [Double]) -> Double {
        let peak = values.filter { $0.isFinite && $0 >= 0 }.max() ?? 0
        return max(1.0, peak * 1.15)
    }

    private static let cpuBrandSubtitle: String = {
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
    }()

    private func cardColor(for severity: InsightSeverity) -> Color {
        switch severity {
        case .critical: return PanelMetricColor.red(for: colorScheme)
        case .warning: return PanelMetricColor.orange(for: colorScheme)
        case .info: return PanelMetricColor.cyan(for: colorScheme)
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
