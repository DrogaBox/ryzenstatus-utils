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
    /// On screen in a visible Settings window; no process or adapter work
    /// runs otherwise.
    @State private var isActive = false
    /// Observed mirror of the three PM-column toggle keys. Plain
    /// UserDefaults writes don't re-render SwiftUI, so the toggles bump
    /// this counter to repaint the grid instantly (the popover's own
    /// @AppStorage observes the same keys — both surfaces stay in sync).
    @State private var pmColumnsRevision = 0

    @ObservedObject var l10n = L10n.shared
    @ObservedObject private var runtime = FeatureRuntime.shared
    /// Live SMU PM-table decode (kext 3.34.11+, Vermeer 0x380804/05/904/905).
    /// Synced on the same 3 s cadence the AMD section uses; nil on old kexts
    /// or undecodable table versions — the whole section then stays hidden.
    @ObservedObject private var amdControls = AmdPowerControlsModel.shared
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
                    Picker(strings.title, selection: $selectedTab) {
                        ForEach(availableTabs) { tab in
                            Text(tab.localizedTitle(strings: strings)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
        // The monitor client and the shared 3 s kext poll (which keeps the
        // SMU decode fresh) run only while the page is on screen in a
        // visible Settings window; so do the process and adapter refreshes.
        .settingsPageActivity(.performanceSuite, activate: {
            isActive = true
            refreshData()
        }, deactivate: {
            isActive = false
        })
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
    }

    // MARK: - 1. Dashboard Tab Content
    @ViewBuilder
    private func dashboardTabContent(strings: PerformanceSuiteFeatureStrings) -> some View {
        VStack(spacing: 14) {
            // CPU brand hardware caption
            HStack {
                Text(cpuBrandSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 2)

            // Headline Metric Cards Row
            headlineMetricCardsGrid(strings: strings)

            // SMU PM-table telemetry — socket power, peak temp, fabric
            // clocks and the per-core effective-clock grid, straight from the
            // kext's 1 Hz snapshot. Zero new polling on top of the shared
            // 3 s sync tick.
            if let decoded = amdControls.pmTableDecoded {
                smuTelemetrySection(decoded: decoded, strings: strings)
            }

            // Activity Monitor Matrix & Process Manager
            BTopDashboardView(monitor: monitor, showCpuOverview: amdControls.pmTableDecoded == nil, isActive: isActive)
        }
    }

    // Headline 4 Metric Cards Grid
    @ViewBuilder
    private func headlineMetricCardsGrid(strings: PerformanceSuiteFeatureStrings) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Card 1: CPU Total
            let dash = l10n.dashboard
            // No reading yet (launch, wake) is a dash, never 0 %.
            let cpuVal = monitor.snapshot.cpuUsage.map { String(format: "%.1f%%", $0 * 100.0) } ?? "—"
            let cpuTemp = monitor.snapshot.cpuTemperature
            let cpuPwr = monitor.snapshot.cpuPower
            let cpuThreads = ProcessInfo.processInfo.processorCount
            let cpuCores = SystemMonitor.hostPhysicalCoreCount
            let tempUnit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
            let cpuColor = PanelMetricColor.cyan(for: colorScheme)
            suiteMetricCard(
                title: strings.cpuTotal,
                value: cpuVal,
                subtitle: cpuTemp.map { MetricFormat.temperatureCompact($0, unit: tempUnit) } ?? "—",
                extraInfo: cpuPwr.map { String(format: "%.1f W", $0) } ?? "\(cpuCores)C / \(cpuThreads)T",
                accentColor: cpuColor,
                history: monitor.snapshot.cpuHistory.map { Double($0) * 100.0 },
                maxDomain: 100.0
            )

            // Card 2: Memory Footprint (RAM Used)
            let usedRAM = monitor.snapshot.memoryUsed
            let totalRAM = monitor.snapshot.memoryTotal
            let valStr = usedRAM.map { MetricFormat.bytes($0) } ?? "—"
            let subStr: String = {
                guard let usedRAM, let totalRAM, totalRAM > 0 else { return "—" }
                let pct = String(format: "%.0f%%", Double(usedRAM) / Double(totalRAM) * 100.0)
                return String(format: dash.memoryUsedPercentFormat, pct)
            }()
            let extraStr = totalRAM.map { String(format: dash.memoryTotalFormat, MetricFormat.bytes($0)) } ?? "—"
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
            let gpuVRAM = monitor.snapshot.gpuMemoryTotal
            let gpuColor = PanelMetricColor.orange(for: colorScheme)
            suiteMetricCard(
                title: "GPU",
                value: gpuVal,
                subtitle: gpuTemp.map { MetricFormat.temperatureCompact($0, unit: tempUnit) } ?? "—",
                extraInfo: gpuPwr.map { String(format: "%.1f W", $0) }
                    ?? gpuVRAM.map { String(format: dash.vramTotalFormat, MetricFormat.bytes($0)) }
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
                value: "↓ " + rate(netDown),
                subtitle: "↑ " + rate(netUp),
                extraInfo: "",
                accentColor: netColor,
                history: netHistory,
                maxDomain: maxNet,
                summaryFormat: { MetricFormat.networkRate($0) }
            )
        }
    }

    @ViewBuilder
    private func suiteMetricCard(title: String, value: String, subtitle: String, extraInfo: String, accentColor: Color, history: [Double], maxDomain: Double,
                                 summaryFormat: @escaping (Double) -> String = { String(format: "%.0f%%", $0) }) -> some View {
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

            ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(history, ceiling: maxDomain)],
                               inks: [.fixed(accentColor)])
                .frame(height: 36)
        }
        .suiteCard(padding: 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(historySummary(history, format: summaryFormat))
    }

    // MARK: - 1b. SMU PM-table Telemetry

    /// SMU-native telemetry row: package power / peak temp / fabric clocks
    /// cards plus the per-core effective-clock grid. Values come straight
    /// from the PM table snapshot the kext's 1 Hz timer maintains — the same
    /// source the AMD panel section renders. Hidden entirely when no table
    /// version decodes (old kext, non-Vermeer, unknown version).
    @ViewBuilder
    private func smuTelemetrySection(decoded: AMDSmuPMTable.Decoded, strings: PerformanceSuiteFeatureStrings) -> some View {
        let amdStrings = L10n.shared.amdPower
        let tempUnit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
        let presentCores = decoded.cores.filter { $0.isPresent }
        let corePeak = presentCores.map { Double($0.tempC) }.max()
        let activeCount = presentCores.filter { !$0.isSleeping }.count
        let clockColor = PanelMetricColor.cyan(for: colorScheme)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(amdStrings.smuPmTableTelemetryHeader)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%@ · %d/%d", amdStrings.panelPmTableCores, activeCount, presentCores.count))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Socket power with the model's rolling history (3 s cadence).
                smuMetricCard(
                    title: amdStrings.packagePowerLabel,
                    value: String(format: "%.1f W", decoded.summary.socketPowerW),
                    accentColor: clockColor,
                    history: amdControls.packagePowerHistory,
                    maxDomain: max(60, Double(decoded.summary.pptLimitW) * 1.05)
                )
                // Package temperature (THM_VALUE) vs hottest core.
                smuMetricCard(
                    title: amdStrings.packageTempLabel,
                    value: MetricFormat.temperatureCompact(Double(decoded.summary.thmValueC), unit: tempUnit),
                    extraInfo: corePeak.map { String(format: l10n.dashboard.hottestCoreFormat,
                                                     MetricFormat.temperatureCompact($0, unit: tempUnit)) } ?? "",
                    accentColor: PanelMetricColor.orange(for: colorScheme),
                    history: amdControls.packageTempHistory,
                    maxDomain: 100.0
                )
                // Fabric clocks (MHz) — technical labels by convention.
                smuFabricCard(fclk: decoded.summary.fclkMHz,
                              uclk: decoded.summary.uclkMHz,
                              memclk: decoded.summary.memclkMHz)
            }

            // Per-core grid — same data the panel disclosure renders, with the
            // same per-field column toggles (voltage / C0 / CC6) sharing the
            // popover's persisted @AppStorage keys, so both surfaces stay in
            // sync app-wide. Sleeping cores dim with a dash.
            HStack(spacing: 10) {
                smuColumnToggle("bolt.fill", color: .yellow,
                                isOn: Binding(get: { UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreVoltage) },
                                              set: { UserDefaults.standard.set($0, forKey: DefaultsKey.showPmCoreVoltage); pmColumnsRevision += 1 }),
                                help: l10n.dashboard.pmVoltageHelp)
                smuColumnToggle("cpu", color: .green,
                                isOn: Binding(get: { UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreC0) },
                                              set: { UserDefaults.standard.set($0, forKey: DefaultsKey.showPmCoreC0); pmColumnsRevision += 1 }),
                                help: l10n.dashboard.pmC0Help)
                smuColumnToggle("moon.zzz.fill", color: .purple,
                                isOn: Binding(get: { UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreCC6) },
                                              set: { UserDefaults.standard.set($0, forKey: DefaultsKey.showPmCoreCC6); pmColumnsRevision += 1 }),
                                help: l10n.dashboard.pmCC6Help)
                Spacer()
                if presentCores.contains(where: { $0.isSleeping }) {
                    // Sleeping legend — mirrors the disclosure's dash cell.
                    Text(l10n.dashboard.coreParkedLegend).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(presentCores, id: \.slot) { core in
                    smuCoreCell(core: core,
                                showsVoltage: UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreVoltage),
                                showsC0: UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreC0),
                                showsCC6: UserDefaults.standard.bool(forKey: DefaultsKey.showPmCoreCC6),
                                tempUnit: tempUnit)
                }
            }
            .id(pmColumnsRevision)
        }
        .suiteCard(padding: 10)
    }

    /// One per-core SMU cell in the dashboard grid: slot, effective clock,
    /// temp, power — plus the toggleable V / C0 / CC6 columns shared with the
    /// panel disclosure. Layout matches the panel row's color language.
    @ViewBuilder
    private func smuCoreCell(core: AMDSmuPMTable.CoreRow,
                             showsVoltage: Bool, showsC0: Bool, showsCC6: Bool,
                             tempUnit: TemperatureUnit) -> some View {
        let tempColor: Color = core.tempC >= 70 ? .red : (core.tempC >= 50 ? .orange : .secondary)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(String(format: "%02d", core.slot))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Text(core.isSleeping ? "—" : String(format: "%.0f MHz", core.freqMHz))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(core.isSleeping ? .secondary.opacity(0.5) : .primary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Spacer()
                Text(MetricFormat.temperatureCompact(Double(core.tempC), unit: tempUnit))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(tempColor)
                    .monospacedDigit()
                Spacer()
                Text(String(format: "%.1f W", core.powerW))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            if showsVoltage || showsC0 || showsCC6 {
                HStack(spacing: 4) {
                    if showsVoltage {
                        Text(String(format: "%.2f V", core.voltageRaw))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    if showsC0 {
                        Text(String(format: "C0 %.0f", core.c0Percent))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    if showsCC6 {
                        Text(String(format: "CC6 %.0f", core.cc6Percent))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))
        .help(String(format: l10n.dashboard.coreLabelFormat, core.slot)
              + String(format: " · %.0f MHz eff · ", core.freqMHz)
              + MetricFormat.temperaturePrecise(Double(core.tempC), unit: tempUnit)
              + String(format: " · %.2f W · C0 %.1f%% · CC6 %.1f%%", core.powerW, core.c0Percent, core.cc6Percent))
    }

    /// Icon-only column toggle — same language as the panel disclosure's
    /// `pmColumnToggle` (meaning in the tooltip, color matches the column).
    @ViewBuilder
    private func smuColumnToggle(_ icon: String, color: Color, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isOn.wrappedValue ? color : .secondary.opacity(0.45))
                .frame(width: 20, height: 16)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(isOn.wrappedValue ? color.opacity(0.15) : Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    /// One SMU metric card mirroring `suiteMetricCard`'s anatomy at a smaller
    /// footprint (3-across instead of 4-across row).
    @ViewBuilder
    private func smuMetricCard(title: String, value: String, extraInfo: String = "", accentColor: Color, history: [Double], maxDomain: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if !extraInfo.isEmpty {
                    Text(extraInfo)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if history.count >= 2 {
                ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(history, ceiling: maxDomain)],
                                   inks: [.fixed(accentColor)])
                    .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(historySummary(history, format: { String(format: "%.0f", $0) }))
    }

    /// Fabric clock readout (FCLK/UCLK/MEMCLK in MHz). Language-neutral
    /// technical labels, matching the PM-table section convention.
    @ViewBuilder
    private func smuFabricCard(fclk: Float, uclk: Float, memclk: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l10n.dashboard.fabricClocksTitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                smuFabricValue("FCLK", fclk)
                smuFabricValue("UCLK", uclk)
                smuFabricValue("MEM", memclk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smuFabricValue(_ label: String, _ mhz: Float) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            Text(String(format: "%.0f", mhz))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.primary)
        }
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
                            .accessibilityAddTraits(selectedInsightFilter == filter ? .isSelected : [])
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
                    Text(String(format: l10n.dashboard.processCountFormat, topProcesses.count))
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
                        let catName = categoryName(entry.category)
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
                    title: l10n.dashboard.gpuCompute,
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
                // An empty history has no average: a dash, not 0.
                let format: (Double) -> String = { isBytes ? MetricFormat.networkRate($0) : String(format: "%.1f", $0) + yUnit }
                let avgText = MetricSeriesSummary.summary(data)
                    .map { String(format: l10n.dashboard.averageFormat, format($0.average)) } ?? "—"
                Text(avgText)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(lineColor)
            }

            // Columns over faint quarter lines, the scale's top in the corner.
            ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(data, ceiling: maxDomain)],
                               inks: [.fixed(lineColor)],
                               gridFractions: [0.25, 0.5, 0.75, 1])
                .overlay(alignment: .topLeading) {
                    Text(isBytes ? MetricFormat.networkRate(maxDomain) : String(format: "%.0f", maxDomain) + yUnit)
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .frame(height: 130)
        }
        .suiteCard(padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(historySummary(data, format: { isBytes ? MetricFormat.networkRate($0) : String(format: "%.1f", $0) + yUnit }))
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

                        Text(record.isApp ? l10n.dashboard.categoryApp : l10n.dashboard.categoryBackground)
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
                    Text(rate(downRate))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(PanelMetricColor.cyan(for: colorScheme))
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.txColumn)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(rate(upRate))
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
                                Text(String(format: l10n.dashboard.ipAddressFormat, adapter.ipAddress))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("↓ " + rate(adapter.rxBytesPerSec))
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(PanelMetricColor.cyan(for: colorScheme))
                                Text("↑ " + rate(adapter.txBytesPerSec))
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
        guard isActive, !refreshInFlight else { return }
        refreshInFlight = true
        let currentTab = selectedTab
        let language = l10n.language
        // The adapter rates are deltas between two scans, so a 2 s rescan
        // keeps them close to live.
        let adaptersStale = Date().timeIntervalSince(lastAdaptersRefresh) >= 2
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
                // The process manager on this tab keeps its own list; storing
                // one here too would redraw the whole page on every snapshot.
                _ = ProcessUsageService.shared.topMemory(limit: 10) // D4: feed LeakDetector
            case .insights:
                procs = ProcessUsageService.shared.topCPU(limit: 20)
                cards = InsightEngine.shared.evaluate(snapshot: snapshot, processes: procs, language: language)
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
                if adaptersStale && currentTab == .network {
                    // Stamped on every scan, changed or not, so an unchanged
                    // list is not rescanned on every snapshot.
                    self.cachedAdapters = outAdapters
                    self.lastAdaptersRefresh = Date()
                    if self.networkAdapters != outAdapters {
                        self.networkAdapters = outAdapters
                    }
                }
                self.refreshInFlight = false
            }
        }
    }

    /// A rate in the user's bits or bytes preference, or a dash when there
    /// is no reading.
    private func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return MetricFormat.networkRate(value)
    }

    /// The spoken summary of a history graph: average, peak and latest.
    private func historySummary(_ values: [Double], format: (Double) -> String) -> String {
        guard let summary = MetricSeriesSummary.summary(values) else { return "" }
        return String(format: l10n.dashboard.chartSummaryFormat,
                      format(summary.average), format(summary.peak), format(summary.last))
    }

    private func categoryName(_ category: ProcessCategory) -> String {
        let dash = l10n.dashboard
        switch category {
        case .system: return dash.categorySystem
        case .app: return dash.categoryApp
        case .helper: return dash.categoryHelper
        case .background: return dash.categoryBackground
        case .developer: return dash.categoryDeveloper
        case .security: return dash.categorySecurity
        }
    }

    private func networkChartMax(_ values: [Double]) -> Double {
        let peak = values.filter { $0.isFinite && $0 >= 0 }.max() ?? 0
        return max(1.0, peak * 1.15)
    }

    private var cpuBrandSubtitle: String {
        "\(Self.cpuBrandName)  ·  " + String(format: l10n.dashboard.cpuTopologyFormat,
                                               SystemMonitor.hostPhysicalCoreCount,
                                               ProcessInfo.processInfo.processorCount)
    }

    private static let cpuBrandName: String = {
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
        return brandName
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

/// Average, peak and latest value of a history series, for the charts'
/// spoken summaries and the average caption. Non-finite samples are ignored;
/// nil for a series with no finite sample.
enum MetricSeriesSummary {
    static func summary(_ values: [Double]) -> (average: Double, peak: Double, last: Double)? {
        let finite = values.filter(\.isFinite)
        guard let last = finite.last, let peak = finite.max() else { return nil }
        return (finite.reduce(0, +) / Double(finite.count), peak, last)
    }
}
