// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// What the Processor section shows, taken from the monitor snapshot and the
/// AMD model and republished only when it changed. No view in the section
/// observes either source directly, so a monitor tick that changes nothing
/// shown here redraws nothing.
@MainActor
final class ProcessorFeed: ObservableObject {
    struct Thread: Equatable, Identifiable {
        let id: Int
        let isLogical: Bool
        let load: Double
    }

    /// The kernel's view, used when no PM table decodes.
    struct Fallback: Equatable {
        var usage: Double?
        var history: [Double] = []
        var temperature: Double?
        var frequencyGHz: Double?
        var power: Double?
        var threads: [Thread] = []
    }

    struct Slice: Equatable {
        var table: AMDSmuPMTable.Decoded?
        var powerHistory: [Double] = []
        var temperatureHistory: [Double] = []
        var fallback = Fallback()
    }

    @Published private(set) var slice = Slice()
    private var active = false
    private var subscription: AnyCancellable?

    init() {
        let amd = AmdPowerControlsModel.shared
        subscription = Publishers.CombineLatest4(amd.$pmTableDecoded, amd.$packagePowerHistory,
                                                 amd.$packageTempHistory, SystemMonitor.shared.$snapshot)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] table, power, temperature, snapshot in
                guard let self, self.active else { return }
                self.update(table: table, power: power, temperature: temperature, snapshot: snapshot)
            }
    }

    /// Nothing is read or redrawn while the window is hidden or minimized.
    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        guard active else { return }
        let amd = AmdPowerControlsModel.shared
        update(table: amd.pmTableDecoded, power: amd.packagePowerHistory,
               temperature: amd.packageTempHistory, snapshot: SystemMonitor.shared.snapshot)
    }

    private func update(table: AMDSmuPMTable.Decoded?, power: [Double], temperature: [Double],
                        snapshot: SystemSnapshot) {
        let next: Slice
        if let table {
            // With a table the kernel's view is not shown: its cores are not
            // even read, and its 1 Hz changes never reach the views.
            next = Slice(table: table, powerHistory: power, temperatureHistory: temperature)
        } else {
            next = Slice(fallback: Fallback(
                usage: snapshot.cpuUsage,
                history: snapshot.cpuHistory,
                temperature: snapshot.cpuTemperature,
                frequencyGHz: snapshot.cpuFreqHistory.last,
                power: snapshot.cpuPower,
                threads: snapshot.cores.map {
                    Thread(id: $0.id, isLogical: $0.isLogical, load: Double(min(100, max(0, $0.loadPct))))
                }))
        }
        if next != slice { slice = next }
    }
}

/// The Processor section: what only RyzenStatus shows. With the SMU PM
/// table, package power and temperature with their history, the fabric
/// clocks and every core on one screen; without it, the kernel's load per
/// thread.
struct ProcessorSection: View {
    let isVisible: Bool
    @StateObject private var feed = ProcessorFeed()
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.showPmCoreVoltage) private var showsVoltage = false
    @AppStorage(DefaultsKey.showPmCoreC0) private var showsC0 = false
    @AppStorage(DefaultsKey.showPmCoreCC6) private var showsCC6 = false
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue

    private var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProcessorHeader()
                if let table = feed.slice.table {
                    tableContent(table)
                } else {
                    fallbackContent(feed.slice.fallback)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { feed.setActive(isVisible) }
        .onDisappear { feed.setActive(false) }
        .onChange(of: isVisible) { _, visible in feed.setActive(visible) }
    }

    // MARK: PM table

    @ViewBuilder
    private func tableContent(_ table: AMDSmuPMTable.Decoded) -> some View {
        let amd = l10n.amdPower
        let dash = l10n.dashboard
        let strings = MonitorWindowStrings.localized(l10n.language)
        let present = table.cores.filter(\.isPresent)
        let hottest = present.map { Double($0.tempC) }.max()
        let powerCeiling = TrendChart.niceCeiling(max(60, Double(table.summary.pptLimitW) * 1.05))

        // One row per SMU reading, each with its history at the end, then
        // the fabric clocks: rows, not cards (the approved plan).
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                telemetryRow(amd.packagePowerLabel, systemImage: "bolt",
                             value: MetricFormat.fixed(Double(table.summary.socketPowerW), decimals: 1, unit: "W"),
                             detail: String(format: strings.pptLimitFormat,
                                            MetricFormat.fixed(Double(table.summary.pptLimitW), decimals: 0, unit: "W")),
                             history: feed.slice.powerHistory, color: MonitorPalette.cpu, ceiling: powerCeiling,
                             format: { MetricFormat.fixed($0, decimals: 0, unit: "W") })
                Divider()
                telemetryRow(amd.packageTempLabel, systemImage: "thermometer.medium",
                             value: MetricFormat.temperatureCompact(Double(table.summary.thmValueC), unit: temperatureUnit),
                             detail: hottest.map { String(format: dash.hottestCoreFormat,
                                                          MetricFormat.temperatureCompact($0, unit: temperatureUnit)) } ?? "",
                             history: feed.slice.temperatureHistory, color: MonitorPalette.temperature, ceiling: 100,
                             format: { MetricFormat.temperatureCompact($0, unit: temperatureUnit) })
                Divider()
                fabricRow(table.summary)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(amd.smuPmTableTelemetryHeader, systemImage: "cpu")
                .font(.headline)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(String(format: strings.activeCoresFormat,
                                present.filter { !$0.isSleeping }.count, present.count))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle(strings.voltage, isOn: $showsVoltage).help(dash.pmVoltageHelp)
                    Toggle("C0", isOn: $showsC0).help(dash.pmC0Help)
                    Toggle("CC6", isOn: $showsCC6).help(dash.pmCC6Help)
                }
                // Column switches, not actions: checkboxes, as in Activity
                // Monitor's column choices.
                .toggleStyle(.checkbox)
                .controlSize(.small)
                coreGrid(present)
                if present.contains(where: \.isSleeping) {
                    Text(dash.coreParkedLegend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Label(strings.cores, systemImage: "square.grid.3x3")
                .font(.headline)
        }
    }

    /// Name, value, detail and the reading's live history, in one grid row.
    private func telemetryRow(_ title: String, systemImage: String, value: String, detail: String,
                              history: [Double], color: Color, ceiling: Double,
                              format: @escaping (Double) -> String) -> some View {
        GridRow(alignment: .center) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
            TrendChart(series: [.init(values: history, color: color)], ceiling: ceiling, gridLabel: format)
                .frame(minWidth: 160, maxWidth: .infinity)
                .frame(height: 36)
                .accessibilityElement()
                .accessibilityLabel(title)
                .accessibilityValue(spokenSummary(history, format: format))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func spokenSummary(_ values: [Double], format: (Double) -> String) -> String {
        guard let summary = MetricSeriesSummary.summary(values) else { return "" }
        return String(format: l10n.dashboard.chartSummaryFormat,
                      format(summary.average), format(summary.peak), format(summary.last))
    }

    /// The three fabric clocks on one row, so all sixteen cores still fit
    /// below without scrolling. Technical labels, as in the AMD pages.
    private func fabricRow(_ summary: AMDSmuPMTable.Summary) -> some View {
        GridRow {
            Label("FCLK · UCLK · MEMCLK", systemImage: "memorychip")
                .foregroundStyle(.secondary)
            Text([summary.fclkMHz, summary.uclkMHz, summary.memclkMHz]
                .map { MetricFormat.fixed(Double($0), decimals: 0, unit: "").trimmingCharacters(in: .whitespaces) }
                .joined(separator: " · ") + " MHz")
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
                .gridCellColumns(3)
        }
        .font(.callout)
    }
    /// Four columns, so sixteen cores fit without scrolling; rows are split
    /// by separators, not boxed (HIG Boxes: no box inside a box).
    private func coreGrid(_ cores: [AMDSmuPMTable.CoreRow]) -> some View {
        let columns = 4
        let rows = stride(from: 0, to: cores.count, by: columns).map { Array(cores[$0..<min($0 + columns, cores.count)]) }
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 { Divider() }
                GridRow {
                    ForEach(rows[index], id: \.slot) { core in
                        coreCell(core)
                    }
                    // Short last row: keep the columns their width.
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func coreCell(_ core: AMDSmuPMTable.CoreRow) -> some View {
        let dash = l10n.dashboard
        let temperature = MetricFormat.temperatureCompact(Double(core.tempC), unit: temperatureUnit)
        let power = MetricFormat.fixed(Double(core.powerW), decimals: 1, unit: "W")
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: dash.coreLabelFormat, core.slot + 1))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(core.isSleeping ? "—" : MetricFormat.fixed(Double(core.freqMHz), decimals: 0, unit: "MHz"))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(core.isSleeping ? .tertiary : .primary)
            HStack(spacing: 4) {
                Text(temperature).foregroundStyle(MonitorPalette.temperatureStyle(Double(core.tempC)))
                Text("·").foregroundStyle(.tertiary)
                Text(power).foregroundStyle(.secondary)
            }
            .font(.caption)
            .monospacedDigit()
            if showsVoltage || showsC0 || showsCC6 {
                HStack(spacing: 6) {
                    if showsVoltage { Text(MetricFormat.fixed(Double(core.voltageRaw), decimals: 2, unit: "V")) }
                    if showsC0 { Text("C0 " + MetricFormat.fixed(Double(core.c0Percent), decimals: 0, unit: "%")) }
                    if showsCC6 { Text("CC6 " + MetricFormat.fixed(Double(core.cc6Percent), decimals: 0, unit: "%")) }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help(String(format: dash.coreLabelFormat, core.slot + 1)
              + " · " + MetricFormat.fixed(Double(core.freqMHz), decimals: 0, unit: "MHz")
              + " · " + MetricFormat.temperaturePrecise(Double(core.tempC), unit: temperatureUnit)
              + " · " + power
              + " · C0 " + MetricFormat.fixed(Double(core.c0Percent), decimals: 1, unit: "%")
              + " · CC6 " + MetricFormat.fixed(Double(core.cc6Percent), decimals: 1, unit: "%"))
    }

    // MARK: Without a PM table

    @ViewBuilder
    private func fallbackContent(_ fallback: ProcessorFeed.Fallback) -> some View {
        let dash = l10n.dashboard
        MetricBox(title: dash.totalUtilization, systemImage: "cpu",
                  value: fallback.usage.map { MetricFormat.fixed($0 * 100, decimals: 1, unit: "%") } ?? "—",
                  detail: [fallback.temperature.map { MetricFormat.temperatureCompact($0, unit: temperatureUnit) },
                           fallback.frequencyGHz.map { MetricFormat.fixed($0, decimals: 2, unit: "GHz") },
                           fallback.power.map { MetricFormat.fixed($0, decimals: 1, unit: "W") }]
                      .compactMap { $0 }.joined(separator: " · "),
                  series: [.init(values: fallback.history.map { $0 * 100 }, color: MonitorPalette.cpu)],
                  ceiling: 100,
                  gridLabel: { MetricFormat.fixed($0, decimals: 0, unit: "%") },
                  summaryFormat: { MetricFormat.fixed($0, decimals: 1, unit: "%") })

        GroupBox {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(fallback.threads) { thread in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(thread.isLogical ? "T\(thread.id + 1)" : "C\(thread.id + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(MetricFormat.fixed(thread.load, decimals: 0, unit: "%"))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        LevelIndicator(value: thread.load, maximum: 100, warning: 50, critical: 85)
                            .frame(height: 12)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(4)
        } label: {
            Label(MonitorWindowStrings.localized(l10n.language).cores, systemImage: "square.grid.3x3")
                .font(.headline)
        }
    }
}

/// The CPU name and topology, said once at the top of the section, the way
/// About This Mac names the chip.
struct ProcessorHeader: View {
    @ObservedObject private var l10n = L10n.shared

    private static let brand: String = {
        let brand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "AMD Ryzen" : brand
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.brand)
                    .font(.title3.weight(.semibold))
                Text(String(format: l10n.dashboard.cpuTopologyFormat,
                            SystemMonitor.hostPhysicalCoreCount, ProcessInfo.processInfo.processorCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One metric in a system box: its name, the value in large fixed-width
/// figures, one line of detail, its live chart and an optional footer.
struct MetricBox<Footer: View>: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String
    let series: [TrendChart.Series]
    let ceiling: Double
    let gridLabel: (Double) -> String
    let summaryFormat: (Double) -> String
    let footer: Footer
    var chartHeight: CGFloat = 64

    @ObservedObject private var l10n = L10n.shared

    init(title: String, systemImage: String, value: String, detail: String,
         series: [TrendChart.Series], ceiling: Double,
         gridLabel: @escaping (Double) -> String, summaryFormat: @escaping (Double) -> String,
         chartHeight: CGFloat = 64, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.detail = detail
        self.series = series
        self.ceiling = ceiling
        self.gridLabel = gridLabel
        self.summaryFormat = summaryFormat
        self.chartHeight = chartHeight
        self.footer = footer()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TrendChart(series: series, ceiling: ceiling, gridLabel: gridLabel)
                    .frame(height: chartHeight)
                    .accessibilityElement()
                    .accessibilityLabel(title)
                    .accessibilityValue(spokenSummary)
                footer
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    /// Every series' average, peak and latest, each after its name when
    /// the chart has more than one.
    private var spokenSummary: String {
        series.compactMap { item -> String? in
            guard let summary = MetricSeriesSummary.summary(item.values) else { return nil }
            let text = String(format: l10n.dashboard.chartSummaryFormat,
                              summaryFormat(summary.average), summaryFormat(summary.peak), summaryFormat(summary.last))
            return series.count > 1 && !item.name.isEmpty ? item.name + ": " + text : text
        }
        .joined(separator: ". ")
    }
}

extension MetricBox where Footer == EmptyView {
    init(title: String, systemImage: String, value: String, detail: String,
         series: [TrendChart.Series], ceiling: Double,
         gridLabel: @escaping (Double) -> String, summaryFormat: @escaping (Double) -> String,
         chartHeight: CGFloat = 64) {
        self.init(title: title, systemImage: systemImage, value: value, detail: detail,
                  series: series, ceiling: ceiling, gridLabel: gridLabel, summaryFormat: summaryFormat,
                  chartHeight: chartHeight) {
            EmptyView()
        }
    }
}

/// A series name next to its color, so a chart with two lines never relies
/// on color alone (HIG Charts).
struct ChartLegend: View {
    let items: [(name: String, color: Color)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Capsule().fill(items[index].color).frame(width: 10, height: 3)
                    Text(items[index].name)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One system color per kind of reading across the whole window (HIG Color:
/// never the same color for two meanings). Yellow, orange and red are kept
/// for state, never for a metric.
enum MonitorPalette {
    static let cpu = Color.blue
    static let memory = Color.green
    static let gpu = Color.purple
    static let networkDown = Color.teal
    static let networkUp = Color.indigo
    static let diskRead = Color.cyan
    static let diskWrite = Color.mint
    static let temperature = Color.pink

    /// The colour a temperature takes as it climbs; the thresholds are the
    /// ones the old per-core grid used.
    static func temperatureStyle(_ celsius: Double) -> AnyShapeStyle {
        if celsius >= 70 { return AnyShapeStyle(Color.red) }
        if celsius >= 50 { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(.secondary)
    }
}
