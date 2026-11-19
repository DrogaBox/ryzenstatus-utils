// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// Scans the network adapters while the Network section is on screen. The
/// per-adapter rates are deltas between two scans, so a scan every two
/// seconds keeps them near live; the scan runs off the main thread and
/// never overlaps another.
@MainActor
final class MonitorNetworkFeed: ObservableObject {
    struct Totals: Equatable {
        var down: Double?
        var up: Double?
    }

    @Published private(set) var adapters: [NetworkAdapterInfo] = []
    @Published private(set) var totals = Totals()
    @Published private(set) var scanned = false

    private var active = false
    private var scanning = false
    private var lastScan = Date.distantPast
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        // The rescan follows the monitor's tick, not changes in the totals:
        // with no traffic, or with only the adapter list sampled, the totals
        // never change and the list would freeze. Nothing runs while the
        // window is hidden or minimized.
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self, self.active else { return }
                self.setTotals(snapshot)
                self.scanIfDue()
            }
            .store(in: &subscriptions)
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        guard active else { return }
        setTotals(SystemMonitor.shared.snapshot)
        scanIfDue()
    }

    private func setTotals(_ snapshot: SystemSnapshot) {
        let next = Totals(down: snapshot.netDownBytesPerSec, up: snapshot.netUpBytesPerSec)
        if next != totals { totals = next }
    }

    private func scanIfDue() {
        guard active, !scanning, Date().timeIntervalSince(lastScan) >= 2 else { return }
        scanning = true
        lastScan = Date()
        Task.detached(priority: .utility) {
            let found = NetworkScannerService.shared.activeAdapters()
            await MainActor.run {
                self.scanning = false
                self.scanned = true
                if self.adapters != found { self.adapters = found }
            }
        }
    }
}

/// The Network section: totals on top, then every adapter in a native table
/// with its address selectable for copying (HIG Labels).
struct MonitorNetworkSection: View {
    let isVisible: Bool
    @StateObject private var feed = MonitorNetworkFeed()
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let strings = MonitorWindowStrings.localized(l10n.language)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                total(suite.rxColumn, feed.totals.down, systemImage: "arrow.down", color: MonitorPalette.networkDown)
                total(suite.txColumn, feed.totals.up, systemImage: "arrow.up", color: MonitorPalette.networkUp)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Table(feed.adapters) {
                TableColumn(strings.interfaceColumn) { adapter in
                    Label(adapter.name, systemImage: "network")
                }
                .width(min: 100, ideal: 140)
                TableColumn(strings.addressColumn) { adapter in
                    Text(adapter.ipAddress).monospacedDigit().textSelection(.enabled)
                }
                .width(min: 120, ideal: 160)
                TableColumn(strings.statusColumn) { adapter in
                    HStack(spacing: 5) {
                        Circle().fill(adapter.isUp ? Color.green : Color.secondary).frame(width: 7, height: 7)
                        Text(adapter.isUp ? strings.statusUp : strings.statusDown)
                    }
                    .accessibilityElement(children: .combine)
                }
                .width(min: 80, ideal: 100)
                TableColumn(suite.rxColumn) { adapter in
                    rateText(adapter.rxBytesPerSec)
                }
                .width(min: 80, ideal: 100)
                TableColumn(suite.txColumn) { adapter in
                    rateText(adapter.txBytesPerSec)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if feed.scanned && feed.adapters.isEmpty {
                    ContentUnavailableView(suite.noNetworkAdapters, systemImage: "network.slash")
                }
            }
        }
        .onAppear { feed.setActive(isVisible) }
        .onDisappear { feed.setActive(false) }
        .onChange(of: isVisible) { _, visible in feed.setActive(visible) }
    }

    private func total(_ title: String, _ value: Double?, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value.map { $0.isFinite && $0 >= 0 ? MetricFormat.networkRate($0) : "—" } ?? "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private func rateText(_ value: Double) -> some View {
        Text(MetricFormat.networkRate(value))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
