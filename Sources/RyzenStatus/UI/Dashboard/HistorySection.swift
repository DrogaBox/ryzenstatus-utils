// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Charts
import Combine
import SwiftUI

/// What the History chart can show, mapped onto the long history's metrics.
enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, cpuTemperature, gpuTemperature, systemPower
    /// From the AMD kext only; on other Macs the chart says there is no data.
    case cpuPower, cpuClock

    static let defaultsKey = "monitorHistoryMetric"
    static var stored: HistoryMetric {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(HistoryMetric.init(rawValue:)) ?? .cpu
    }

    var id: String { rawValue }

    /// One series, or two for traffic (down/read first).
    var series: [LongHistoryMetric] {
        switch self {
        case .cpu: return [.cpu]
        case .gpu: return [.gpu]
        case .memory: return [.memory]
        case .network: return [.networkDown, .networkUp]
        case .disk: return [.diskRead, .diskWrite]
        case .cpuTemperature: return [.cpuTemperature]
        case .gpuTemperature: return [.gpuTemperature]
        case .systemPower: return [.systemPower]
        case .cpuPower: return [.cpuPower]
        case .cpuClock: return [.cpuClock]
        }
    }

    /// The live family the metric needs, so the newest columns fill while
    /// you look at them (the long history never samples on its own).
    func addNeeds(to needs: inout SystemMonitorPanelNeeds) {
        switch self {
        // The window always samples the CPU, and the kext read that comes
        // with it carries the package power and the core clocks.
        case .cpu, .gpu, .memory, .network, .cpuPower, .cpuClock: break
        case .disk: needs.disk = true
        case .cpuTemperature: needs.cpuTemperature = true
        case .gpuTemperature: needs.gpuTemperature = true
        case .systemPower: needs.power = true
        }
    }

    var isPercent: Bool { self == .cpu || self == .gpu || self == .memory }
}

/// The ranges offered, Battery-style: short to long.
private let historyRanges: [LongHistoryRange] = [.tenMinutes, .oneHour, .oneDay, .sevenDays, .thirtyDays]

/// Reads the long history for the chart on screen: when it opens, when the
/// range or metric changes, and then about once per column width (at least
/// every 5 s, at most every 60 s), driven by the monitor's own tick, never
/// by a timer of its own.
@MainActor
final class HistoryFeed: ObservableObject {
    struct Point: Identifiable, Equatable {
        let id: Int
        let date: Date
        let value: Double
        let series: Int
        let segment: Int
    }

    @Published private(set) var points: [Point] = []
    @Published private(set) var values: [[Double]] = []
    @Published private(set) var end = Date()
    /// The top of the value axis, worked out once per read, not per redraw.
    @Published private(set) var ceiling: Double = 100

    private var range: LongHistoryRange = .oneHour
    private var metric: HistoryMetric = .cpu
    private var lastRead = Date.distantPast
    private var active = false
    private var subscription: AnyCancellable?

    init() {
        subscription = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readIfDue() }
    }

    func show(range: LongHistoryRange, metric: HistoryMetric, active: Bool) {
        let changed = range != self.range || metric != self.metric || (active && !self.active)
        self.range = range
        self.metric = metric
        self.active = active
        if changed && active { read() }
    }

    private var cadence: TimeInterval {
        min(60, max(5, range.duration / Double(LongHistoryStore.bucketCount)))
    }

    private func readIfDue() {
        guard active, Date().timeIntervalSince(lastRead) >= cadence else { return }
        read()
    }

    private func read() {
        let now = Date()
        lastRead = now
        let store = LongHistoryStore.shared
        let series = metric.series.map { store.averages($0, range: range, end: now.timeIntervalSince1970) }
        let scale = metric.isPercent ? 100.0 : 1.0
        let width = range.duration / Double(LongHistoryStore.bucketCount)
        let start = now.timeIntervalSince1970 - range.duration
        var built: [Point] = []
        for (seriesIndex, buckets) in series.enumerated() {
            var segment = 0
            var previousFinite = false
            for (index, value) in buckets.enumerated() {
                guard value.isFinite else {
                    if previousFinite { segment += 1 }
                    previousFinite = false
                    continue
                }
                previousFinite = true
                built.append(Point(id: seriesIndex * 10_000 + index,
                                   date: Date(timeIntervalSince1970: start + (Double(index) + 0.5) * width),
                                   value: value * scale, series: seriesIndex, segment: segment))
            }
        }
        end = now
        values = series.map { $0.map { $0 * scale } }
        let peak = built.map(\.value).max() ?? 0
        switch metric {
        case .cpu, .gpu, .memory: ceiling = 100
        case .cpuTemperature, .gpuTemperature: ceiling = max(100, TrendChart.niceCeiling(peak))
        default: ceiling = TrendChart.niceCeiling(peak * 1.1, minimum: 1)
        }
        if built != points { points = built }
    }
}

/// History, like System Settings › Battery: a range control, a metric menu,
/// a headline with the period's average and peak, and the chart, whose whole
/// plot area answers the pointer with the value and the time (HIG Charts).
struct HistorySection: View {
    @ObservedObject var state: MonitorWindowState
    @StateObject private var feed = HistoryFeed()
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("monitorHistoryRange") private var rangeRaw = LongHistoryRange.oneHour.rawValue
    @AppStorage(HistoryMetric.defaultsKey) private var metricRaw = HistoryMetric.cpu.rawValue
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @State private var hovered: Date?

    private var range: LongHistoryRange { LongHistoryRange(rawValue: rangeRaw) ?? .oneHour }
    private var metric: HistoryMetric { HistoryMetric(rawValue: metricRaw) ?? .cpu }
    private var unit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }

    var body: some View {
        let strings = MonitorWindowStrings.localized(l10n.language)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker(strings.history, selection: $rangeRaw) {
                    ForEach(historyRanges) { range in
                        Text(Self.rangeLabel(range, language: l10n.language)).tag(range.rawValue)
                            .accessibilityLabel(Self.spokenRange(range, language: l10n.language))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Picker(strings.metric, selection: $metricRaw) {
                    ForEach(HistoryMetric.allCases) { metric in
                        Text(name(metric)).tag(metric.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name(metric)).font(.headline)
                Text(headline(strings))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if feed.points.isEmpty {
                ContentUnavailableView(strings.noHistory, systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
                if metric.series.count > 1 {
                    ChartLegend(items: seriesNames.enumerated().map { ($0.element, color($0.offset)) })
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { update() }
        .onDisappear { feed.show(range: range, metric: metric, active: false) }
        .onChange(of: rangeRaw) { _, _ in update() }
        .onChange(of: metricRaw) { _, _ in
            update()
            state.historyMetricChanged()
        }
        .onChange(of: state.isVisible) { _, _ in update() }
    }

    private func update() {
        feed.show(range: range, metric: metric, active: state.isVisible)
    }

    private var chart: some View {
        let ceiling = feed.ceiling
        // Axis and series names VoiceOver reads, in the app's language.
        let timeLabel = MonitorWindowStrings.localized(l10n.language).chartTime
        let valueLabel = name(metric)
        let names = seriesNames
        return Chart {
            ForEach(feed.points) { point in
                LineMark(x: .value(timeLabel, point.date),
                         y: .value(valueLabel, point.value),
                         series: .value(valueLabel, names[min(point.series, names.count - 1)] + " \(point.segment)"))
                    .foregroundStyle(color(point.series))
                    // The second series is dashed, so two lines never rely on
                    // color alone (HIG Charts).
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                           dash: point.series == 0 ? [] : [4, 3]))
                    // The series value only splits the line at gaps; VoiceOver
                    // hears the series name and the value instead.
                    .accessibilityLabel(names[min(point.series, names.count - 1)])
                    .accessibilityValue(format(point.value))
                if metric.series.count == 1 {
                    AreaMark(x: .value(timeLabel, point.date),
                             y: .value(valueLabel, point.value),
                             series: .value(valueLabel, names[min(point.series, names.count - 1)] + " \(point.segment)"))
                        .foregroundStyle(color(point.series).opacity(0.15))
                        .accessibilityHidden(true)
                }
            }
            if let hovered {
                RuleMark(x: .value(timeLabel, hovered))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: 0...ceiling)
        .chartXScale(domain: feed.end.addingTimeInterval(-range.duration)...feed.end)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, ceiling / 2, ceiling]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(format(number, compact: true)) }
                }
            }
        }
        .chartXAxis {
            // Three marks inside the range, so no label is clipped at an edge.
            AxisMarks(values: (1...3).map { feed.end.addingTimeInterval(-range.duration * Double(4 - $0) / 4) }) { _ in
                AxisGridLine()
                AxisValueLabel(format: range.duration > 86_400 ? .dateTime.month(.abbreviated).day()
                                                               : .dateTime.hour().minute())
            }
        }
        .chartXSelection(value: $hovered)
        // A Mac pointer only passing over the plot shows the value and time
        // too, with no click (the whole plot area answers, HIG Charts).
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geometry[plot].origin.x
                            hovered = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityLabel(name(metric))
        .frame(maxHeight: .infinity)
    }

    private var seriesNames: [String] {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        switch metric {
        case .network: return [suite.rxColumn, suite.txColumn]
        case .disk: return [l10n.s.diskRead, l10n.s.diskWrite]
        default: return [name(metric)]
        }
    }

    private func color(_ series: Int) -> Color {
        switch metric {
        case .cpu: return MonitorPalette.cpu
        case .gpu: return MonitorPalette.gpu
        case .memory: return MonitorPalette.memory
        case .network: return series == 0 ? MonitorPalette.networkDown : MonitorPalette.networkUp
        case .disk: return series == 0 ? MonitorPalette.diskRead : MonitorPalette.diskWrite
        case .cpuTemperature, .gpuTemperature: return MonitorPalette.temperature
        case .systemPower, .cpuPower, .cpuClock: return MonitorPalette.cpu
        }
    }

    private func name(_ metric: HistoryMetric) -> String {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let strings = MonitorWindowStrings.localized(l10n.language)
        switch metric {
        case .cpu: return suite.cpuUtilization
        case .gpu: return l10n.dashboard.gpuCompute
        case .memory: return suite.memoryFootprint
        case .network: return suite.networkIO
        case .disk: return l10n.dashboard.diskIO
        case .cpuTemperature: return strings.cpuTemperature
        case .gpuTemperature: return strings.gpuTemperature
        case .systemPower: return strings.systemPower
        case .cpuPower: return strings.cpuPower
        case .cpuClock: return strings.cpuClock
        }
    }

    private func format(_ value: Double, compact: Bool = false) -> String {
        switch metric {
        case .cpu, .gpu, .memory: return MetricFormat.fixed(value, decimals: compact ? 0 : 1, unit: "%")
        case .network: return compact ? MetricFormat.networkRateCompact(value) : MetricFormat.networkRate(value)
        case .disk: return compact ? MetricFormat.bytesPerSecCompact(value) : MetricFormat.bytesPerSec(value)
        case .cpuTemperature, .gpuTemperature: return MetricFormat.temperatureCompact(value, unit: unit)
        case .systemPower, .cpuPower: return MetricFormat.fixed(value, decimals: compact ? 0 : 1, unit: "W")
        // Stored in MHz, read in GHz like the live clock graph.
        case .cpuClock: return MetricFormat.fixed(value / 1000, decimals: compact ? 1 : 2, unit: "GHz")
        }
    }

    /// The hovered column's value(s) and time, or the period's average and
    /// peak of the first series.
    private func headline(_ strings: MonitorWindowStrings) -> String {
        if let hovered, let index = bucketIndex(for: hovered),
           case let values = feed.values.map({ index < $0.count ? $0[index] : .nan }),
           values.contains(where: \.isFinite) {
            let text = values.map { $0.isFinite ? format($0) : "—" }.joined(separator: " · ")
            return hovered.formatted(range.duration > 86_400 ? .dateTime.month().day().hour().minute()
                                                             : .dateTime.hour().minute()) + " — " + text
        }
        guard let first = feed.values.first, let summary = MetricSeriesSummary.summary(first) else {
            return strings.noHistory
        }
        return String(format: strings.averagePeakFormat, format(summary.average), format(summary.peak))
    }

    private func bucketIndex(for date: Date) -> Int? {
        let start = feed.end.timeIntervalSince1970 - range.duration
        let index = Int(((date.timeIntervalSince1970 - start) / range.duration * Double(LongHistoryStore.bucketCount))
            .rounded(.down))
        return (0..<LongHistoryStore.bucketCount).contains(index) ? index : nil
    }

    /// The range labels, built once per range and language: a hover redraw
    /// must not build date formatters.
    private static var labelCache: [String: String] = [:]

    static func rangeLabel(_ range: LongHistoryRange, language: AppLanguage) -> String {
        let key = "short.\(range.rawValue).\(language.rawValue)"
        if let cached = labelCache[key] { return cached }
        let label = range.label(language)
        labelCache[key] = label
        return label
    }

    /// "10 minutes", not "10m", for VoiceOver (HIG Charts).
    static func spokenRange(_ range: LongHistoryRange, language: AppLanguage) -> String {
        let key = "spoken.\(range.rawValue).\(language.rawValue)"
        if let cached = labelCache[key] { return cached }
        let label = makeSpokenRange(range, language: language)
        labelCache[key] = label
        return label
    }

    private static func makeSpokenRange(_ range: LongHistoryRange, language: AppLanguage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language.rawValue)
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.maximumUnitCount = 1
        return formatter.string(from: range.duration) ?? range.label(language)
    }
}
