// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// What the Overview shows, cut from the monitor snapshot and republished
/// only when it changed.
@MainActor
final class SummaryFeed: ObservableObject {
    struct Slice: Equatable {
        var cpuUsage: Double?
        var cpuHistory: [Double] = []
        var cpuTemperature: Double?
        var cpuPower: Double?
        var memoryUsed: UInt64?
        var memoryTotal: UInt64?
        var memoryHistory: [Double] = []
        var memoryPressure: MemoryPressure = .unknown
        var gpuUsage: Double?
        var gpuHistory: [Double] = []
        var gpuTemperature: Double?
        var gpuPower: Double?
        var vramUsed: UInt64?
        var vramTotal: UInt64?
        var netDown: Double?
        var netUp: Double?
        var netDownHistory: [Double] = []
        var netUpHistory: [Double] = []
        var diskRead: Double?
        var diskWrite: Double?
    }

    @Published private(set) var slice = Slice()
    private var active = false
    private var subscription: AnyCancellable?

    init() {
        subscription = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self, self.active else { return }
                self.update(snapshot)
            }
    }

    /// Nothing is cut or redrawn while the window is hidden or minimized.
    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active { update(SystemMonitor.shared.snapshot) }
    }

    private func update(_ snapshot: SystemSnapshot) {
        // This tick's disk rates, not the last history push.
        let devices = snapshot.disk?.uniqueIODevices ?? []
        let reads = devices.compactMap(\.readBytesPerSec)
        let writes = devices.compactMap(\.writeBytesPerSec)
        let next = Slice(cpuUsage: snapshot.cpuUsage, cpuHistory: snapshot.cpuHistory,
                         cpuTemperature: snapshot.cpuTemperature, cpuPower: snapshot.cpuPower,
                         memoryUsed: snapshot.memoryUsed, memoryTotal: snapshot.memoryTotal,
                         memoryHistory: snapshot.memoryHistory, memoryPressure: snapshot.memoryPressure,
                         gpuUsage: snapshot.gpuUsage, gpuHistory: snapshot.gpuHistory,
                         gpuTemperature: snapshot.gpuTemperature, gpuPower: snapshot.gpuPower,
                         vramUsed: snapshot.gpuMemoryUsed, vramTotal: snapshot.gpuMemoryTotal,
                         netDown: snapshot.netDownBytesPerSec, netUp: snapshot.netUpBytesPerSec,
                         netDownHistory: snapshot.netDownHistory, netUpHistory: snapshot.netUpHistory,
                         diskRead: reads.isEmpty ? nil : reads.reduce(0, +),
                         diskWrite: writes.isEmpty ? nil : writes.reduce(0, +))
        if next != slice { slice = next }
    }
}

/// The Overview: the four families in system boxes, two by two, each with
/// its value, its detail and a live two-minute chart. Replaces the old
/// metric cards and the Analytics charts.
struct SummarySection: View {
    let isVisible: Bool
    @StateObject private var feed = SummaryFeed()
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }

    var body: some View {
        let slice = feed.slice
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProcessorHeader()
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        cpuBox(slice).frame(maxHeight: .infinity, alignment: .top)
                        memoryBox(slice).frame(maxHeight: .infinity, alignment: .top)
                    }
                    GridRow {
                        gpuBox(slice).frame(maxHeight: .infinity, alignment: .top)
                        networkBox(slice).frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { feed.setActive(isVisible) }
        .onDisappear { feed.setActive(false) }
        .onChange(of: isVisible) { _, visible in feed.setActive(visible) }
    }

    private func percent(_ fraction: Double?) -> String {
        fraction.map { MetricFormat.fixed($0 * 100, decimals: 1, unit: "%") } ?? "—"
    }

    private func percentAxis(_ value: Double) -> String { MetricFormat.fixed(value, decimals: 0, unit: "%") }

    private func watts(_ value: Double?) -> String? { value.map { MetricFormat.fixed($0, decimals: 1, unit: "W") } }

    private func joined(_ parts: [String?]) -> String { parts.compactMap { $0 }.joined(separator: " · ") }

    private func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return MetricFormat.networkRate(value)
    }

    private func cpuBox(_ slice: SummaryFeed.Slice) -> some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        return MetricBox(title: suite.cpuUtilization, systemImage: "cpu",
                         value: percent(slice.cpuUsage),
                         detail: joined([slice.cpuTemperature.map { MetricFormat.temperatureCompact($0, unit: unit) },
                                         watts(slice.cpuPower)]),
                         series: [.init(values: slice.cpuHistory.map { $0 * 100 }, color: MonitorPalette.cpu)],
                         ceiling: 100, gridLabel: percentAxis,
                         summaryFormat: { MetricFormat.fixed($0, decimals: 1, unit: "%") }, chartHeight: 110)
    }

    private func memoryBox(_ slice: SummaryFeed.Slice) -> some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let s = l10n.s
        let fraction: Double? = {
            guard let used = slice.memoryUsed, let total = slice.memoryTotal, total > 0 else { return nil }
            return Double(used) / Double(total)
        }()
        let pressure: String? = {
            switch slice.memoryPressure {
            case .normal: return s.pressureNormal
            case .warning: return s.pressureWarning
            case .critical: return s.pressureCritical
            case .unknown: return nil
            }
        }()
        return MetricBox(title: suite.memoryFootprint, systemImage: "memorychip",
                         value: slice.memoryUsed.map { MetricFormat.bytes($0) } ?? "—",
                         detail: joined([fraction.map { MetricFormat.fixed($0 * 100, decimals: 0, unit: "%") },
                                         pressure.map { s.memoryPressure + ": " + $0 }]),
                         series: [.init(values: slice.memoryHistory.map { $0 * 100 }, color: MonitorPalette.memory)],
                         ceiling: 100, gridLabel: percentAxis,
                         summaryFormat: { MetricFormat.fixed($0, decimals: 0, unit: "%") }, chartHeight: 110) {
            capacityRow("RAM", used: slice.memoryUsed, total: slice.memoryTotal)
            capacityRow("VRAM", used: slice.vramUsed, total: slice.vramTotal)
        }
    }

    private func gpuBox(_ slice: SummaryFeed.Slice) -> some View {
        let dash = l10n.dashboard
        return MetricBox(title: dash.gpuCompute, systemImage: "rectangle.3.group",
                         value: percent(slice.gpuUsage),
                         detail: joined([slice.gpuTemperature.map { MetricFormat.temperatureCompact($0, unit: unit) },
                                         // No power reading: the VRAM size, as the old card did.
                                         watts(slice.gpuPower)
                                            ?? slice.vramTotal.map { String(format: dash.vramTotalFormat, MetricFormat.bytes($0)) }]),
                         series: [.init(values: slice.gpuHistory.map { $0 * 100 }, color: MonitorPalette.gpu)],
                         ceiling: 100, gridLabel: percentAxis,
                         summaryFormat: { MetricFormat.fixed($0, decimals: 1, unit: "%") }, chartHeight: 110)
    }

    private func networkBox(_ slice: SummaryFeed.Slice) -> some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let dash = l10n.dashboard
        let peak = (slice.netDownHistory + slice.netUpHistory).filter { $0.isFinite && $0 >= 0 }.max() ?? 0
        let ceiling = TrendChart.niceCeiling(peak * 1.1, minimum: 1024)
        return MetricBox(title: suite.networkIO, systemImage: "network",
                         value: rate(slice.netDown),
                         detail: suite.txColumn + " " + rate(slice.netUp),
                         series: [.init(values: slice.netDownHistory, color: MonitorPalette.networkDown,
                                        name: suite.rxColumn),
                                  .init(values: slice.netUpHistory, color: MonitorPalette.networkUp,
                                        name: suite.txColumn, dashed: true)],
                         ceiling: ceiling,
                         gridLabel: { MetricFormat.networkRateCompact($0) },
                         summaryFormat: { MetricFormat.networkRate($0) }, chartHeight: 110) {
            ChartLegend(items: [(suite.rxColumn, MonitorPalette.networkDown), (suite.txColumn, MonitorPalette.networkUp)])
            HStack {
                Text(dash.diskIO).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: dash.diskReadWriteFormat,
                            slice.diskRead.map { MetricFormat.bytesPerSec($0) } ?? "—",
                            slice.diskWrite.map { MetricFormat.bytesPerSec($0) } ?? "—"))
                    .monospacedDigit()
            }
            .font(.callout)
        }
    }

    /// Used of total with the system capacity indicator; an unknown size
    /// stays unknown, with no bar and no borrowed total.
    private func capacityRow(_ label: String, used: UInt64?, total: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(used.map { used in
                    total.map { "\(MetricFormat.bytes(used)) / \(MetricFormat.bytes($0))" } ?? MetricFormat.bytes(used)
                } ?? "—")
                .monospacedDigit()
            }
            .font(.callout)
            if let used, let total, total > 0 {
                LevelIndicator(value: Double(used) / Double(total), maximum: 1, warning: 0.8, critical: 0.95)
                    .frame(height: 12)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
