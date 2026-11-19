// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// Evaluates the insight rules while Diagnostics is on screen, every other
/// monitor tick, off the main thread. The process list it reads is the one
/// the service already caches, so the rules add no `ps` run of their own.
@MainActor
final class DiagnosticsFeed: ObservableObject {
    @Published private(set) var cards: [InsightCard] = []
    @Published private(set) var evaluated = false

    private var active = false
    private var evaluating = false
    private var tick = 0
    private var subscription: AnyCancellable?

    init() {
        subscription = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.evaluate(snapshot) }
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            tick = 0
            evaluate(SystemMonitor.shared.snapshot)
        }
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        guard active, !evaluating else { return }
        defer { tick &+= 1 }
        guard tick % 2 == 0 else { return }
        evaluating = true
        let language = L10n.shared.language
        Task.detached(priority: .utility) {
            let processes = ProcessUsageService.shared.topCPU(limit: 20)
            let cards = InsightEngine.shared.evaluate(snapshot: snapshot, processes: processes, language: language)
            await MainActor.run {
                self.evaluating = false
                self.evaluated = true
                // Ids are stable per condition, so an unchanged list is not
                // redrawn because its timestamps moved.
                if self.cards.map(\.id) != cards.map(\.id) || self.cards.map(\.detail) != cards.map(\.detail) {
                    self.cards = cards
                }
            }
        }
    }
}

/// Diagnostics (formerly Insights): one row per active notice, its severity
/// said in words as well as by symbol and color (HIG Color: never color
/// alone), with the hint and an Inspect button when a process is involved.
struct DiagnosticsSection: View {
    let isVisible: Bool
    @StateObject private var feed = DiagnosticsFeed()
    @ObservedObject private var l10n = L10n.shared
    @State private var filter = ""
    @State private var processGone = false

    var body: some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let strings = MonitorWindowStrings.localized(l10n.language)
        let categories = Array(Set(feed.cards.map(\.categoryName))).sorted()
        let shown = feed.cards.filter { filter.isEmpty || $0.categoryName == filter }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suite.insightsTitle).font(.headline)
                    Text(suite.insightsSubtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if categories.count > 1 {
                    Picker(suite.insightsTitle, selection: $filter) {
                        Text(suite.filterAll).tag("")
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if shown.isEmpty && feed.evaluated {
                ContentUnavailableView {
                    Label(suite.noInsights, systemImage: "checkmark.circle")
                } description: {
                    Text(suite.noInsightsSubtitle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { card in
                    row(card, suite: suite, strings: strings)
                }
                .listStyle(.inset)
            }
        }
        .alert(suite.inspectButton, isPresented: $processGone) {
            Button(strings.ok) {}
        } message: {
            Text(strings.processGone)
        }
        .onAppear { feed.setActive(isVisible) }
        .onDisappear { feed.setActive(false) }
        .onChange(of: isVisible) { _, visible in feed.setActive(visible) }
        .onChange(of: categories) { _, now in
            if !filter.isEmpty && !now.contains(filter) { filter = "" }
        }
    }

    private func row(_ card: InsightCard, suite: PerformanceSuiteFeatureStrings, strings: MonitorWindowStrings) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(card.severity))
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(color(card.severity))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.title).font(.headline)
                    Spacer()
                    Text(severity(card.severity, strings) + " · " + card.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(card.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if card.actionHint != nil || card.pid != nil {
                    HStack(alignment: .firstTextBaseline) {
                        if let hint = card.actionHint {
                            Label(hint, systemImage: "lightbulb")
                                .font(.callout)
                        }
                        Spacer()
                        if let pid = card.pid {
                            Button(suite.inspectButton) {
                                // The Inspector can force quit: it opens only for
                                // a pid that is still the app the notice named.
                                if let name = card.processName, ProcessKillRequest.current(pid: pid, name: name) != nil {
                                    ProcessInspectorWindowController.shared.present(
                                        for: ProcessUsage(pid: pid, name: name, value: 0))
                                } else {
                                    processGone = true
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func symbol(_ severity: InsightSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: InsightSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }

    private func severity(_ severity: InsightSeverity, _ strings: MonitorWindowStrings) -> String {
        switch severity {
        case .critical: return strings.severityCritical
        case .warning: return strings.severityWarning
        case .info: return strings.severityInfo
        }
    }
}
