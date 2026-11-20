// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// One row of the process table: an app with its helpers summed in, the way
/// the old process manager listed them.
struct ProcessTableRow: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let cpu: Double
    let memory: Double
    /// Nil until the accelerator has given two samples to compare.
    let gpu: Double?
    let category: ProcessCategory

    var id: pid_t { pid }
    var gpuSortValue: Double { gpu ?? -1 }
    /// The same estimate the Energy tab showed: CPU plus 1.5 × GPU.
    var energy: Double { EnergyImpactService.score(cpuPct: cpu, gpuPct: gpu ?? 0) }
}

/// Feeds the process table while it is on screen: one `ps` listing every two
/// seconds gives every app's CPU and memory, the accelerator walk for GPU
/// runs every fourth tick, and the rows change only when a listing arrives.
/// Nothing runs while the section is off screen or the window is hidden.
@MainActor
final class ProcessesFeed: ObservableObject {
    @Published private(set) var rows: [ProcessTableRow] = []
    @Published private(set) var loaded = false
    @Published var sortOrder = [KeyPathComparator(\ProcessTableRow.cpu, order: .reverse)] {
        didSet { rebuild() }
    }
    @Published var search = "" {
        didSet { if search != oldValue { rebuild() } }
    }
    /// CPU load split as the kernel reports it, for the line above the table.
    @Published private(set) var cpuLoad: (user: Double, system: Double, total: Double)?

    private var apps: [AppUsage] = []
    private var gpuByApp: [pid_t: Double] = [:]
    private var categories: [pid_t: (name: String, category: ProcessCategory)] = [:]
    private var tick = 0
    private var active = false
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.poll(snapshot) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .processUsageDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.read() }
            .store(in: &subscriptions)
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            tick = 0
            poll(SystemMonitor.shared.snapshot)
        }
    }

    /// After a terminate, or a row that turned out stale: a listing now,
    /// past the freshness wait, so the row goes away.
    func refreshNow() {
        guard active else { return }
        _ = ProcessUsageService.shared.appUsage(force: true)
    }

    /// Called on every monitor tick. Every other tick it asks for a fresh
    /// listing (the service starts at most one `ps` at a time), so the table
    /// refreshes every two seconds; the rows are rebuilt when the listing
    /// arrives, not here. GPU time is read every fourth tick.
    private func poll(_ snapshot: SystemSnapshot) {
        guard active else { return }
        defer { tick &+= 1 }
        let load = snapshot.cpuUsage.map { total -> (user: Double, system: Double, total: Double) in
            let system = min(total, max(0, snapshot.cpuSystemHistory.last ?? 0))
            return (total - system, system, total)
        }
        if load.map({ [$0.user, $0.system, $0.total] }) != cpuLoad.map({ [$0.user, $0.system, $0.total] }) {
            cpuLoad = load
        }
        if tick % 4 == 0 {
            gpuByApp = Dictionary(ProcessUsageService.shared.topGPU(limit: 60).map { ($0.pid, $0.value) },
                                  uniquingKeysWith: { first, _ in first })
        }
        guard tick % 2 == 0 else { return }
        // A newer listing than the one shown (another surface ran `ps`
        // while this section was hidden) is shown at once.
        let cached = ProcessUsageService.shared.appUsage()
        if !cached.isEmpty && cached != apps {
            apps = cached
            rebuild()
        }
    }

    /// A listing (or a GPU walk) arrived: read the cache without asking for
    /// another run.
    private func read() {
        guard active else { return }
        apps = ProcessUsageService.shared.cachedAppUsage()
        gpuByApp = Dictionary(ProcessUsageService.shared.cachedGPU(limit: 60).map { ($0.pid, $0.value) },
                              uniquingKeysWith: { first, _ in first })
        rebuild()
    }

    private func rebuild() {
        let gpuKnown = ProcessUsageService.shared.hasGPUDeltaSample
        var all = Self.matching(apps, search: search).map { app in
            ProcessTableRow(pid: app.pid, name: app.name, cpu: app.cpuPercent, memory: app.memoryBytes,
                            gpu: gpuKnown ? gpuByApp[app.pid] ?? 0 : nil,
                            category: category(pid: app.pid, name: app.name))
        }
        all.sort(using: sortOrder)
        if !apps.isEmpty { loaded = true }
        if all != rows { rows = all }
    }

    /// The apps whose name contains the search text; all of them for an
    /// empty search.
    nonisolated static func matching(_ apps: [AppUsage], search: String) -> [AppUsage] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// The glossary lookup asks AppKit about the process, so it runs once per
    /// app, not on every refresh; apps that left are forgotten.
    private func category(pid: pid_t, name: String) -> ProcessCategory {
        if let cached = categories[pid], cached.name == name { return cached.category }
        let category = ProcessGlossary.resolve(name: name, pid: pid).category
        categories[pid] = (name, category)
        if categories.count > apps.count + 200 {
            let live = Set(apps.map(\.pid))
            categories = categories.filter { live.contains($0.key) }
        }
        return category
    }
}

/// A terminate request, read when it was asked for: the kill goes only to
/// the process that still has this start time, never to a reused pid.
struct ProcessKillRequest: Identifiable {
    let pid: pid_t
    let name: String
    let startedAt: UInt64
    var id: pid_t { pid }

    /// The request for a row, or nil when the row no longer names the app
    /// it was read for (it quit, or its pid now belongs to another one).
    static func make(pid: pid_t, name: String, startedAt: UInt64?, currentName: String) -> Self? {
        guard let startedAt, !name.isEmpty, currentName == name else { return nil }
        return Self(pid: pid, name: name, startedAt: startedAt)
    }

    /// Reads the pid now. The live name is read with an empty fallback, so a
    /// process whose name cannot be read never passes for the expected app.
    static func current(pid: pid_t, name: String) -> Self? {
        make(pid: pid, name: name, startedAt: KillProcessService.startTime(for: pid),
             currentName: ResponsibleProcess.displayName(pid: pid, fallback: ""))
    }
}

/// The Processes section: one native table in place of the old process
/// manager, the Insights process list and the Energy list (HIG Lists and
/// tables › macOS: sortable, resizable columns, alternating rows), with
/// every app listed (the table is lazy) and a search field.
struct ProcessesSection: View {
    @ObservedObject var state: MonitorWindowState
    @StateObject private var feed = ProcessesFeed()
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var runtime = FeatureRuntime.shared
    @State private var selection: pid_t?
    @State private var killRequest: ProcessKillRequest?
    @State private var killUnavailable = false
    @State private var processGone = false
    @AppStorage("monitorProcessColumns") private var columnData = Data()
    /// Set while the energy column is hidden because its feature is off, so
    /// turning the feature back on restores it, and only then.
    @AppStorage("monitorEnergyHiddenByGate") private var energyHiddenByGate = false
    @State private var columns = TableColumnCustomization<ProcessTableRow>()

    var body: some View {
        let suite = FeatureStrings.performanceSuite(l10n.language)
        let strings = MonitorWindowStrings.localized(l10n.language)
        let dash = l10n.dashboard
        let energyAvailable = AppFeature.monitorEnergy.isAvailable
        VStack(spacing: 0) {
            // The CPU split, one line above the table (the approved plan).
            Text(feed.cpuLoad.map { load in
                String(format: strings.cpuLoadFormat,
                       MetricFormat.fixed(load.user * 100, decimals: 1, unit: "%"),
                       MetricFormat.fixed(load.system * 100, decimals: 1, unit: "%"),
                       MetricFormat.fixed(load.total * 100, decimals: 1, unit: "%"))
            } ?? " ")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()
            Table(feed.rows, selection: $selection, sortOrder: $feed.sortOrder, columnCustomization: $columns) {
                TableColumn(suite.processColumn, value: \.name) { row in
                    HStack(spacing: 6) {
                        Image(nsImage: ResponsibleProcess.icon(for: row.pid, pointSize: 16))
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                .width(min: 160, ideal: 240)
                .customizationID("name")
                .disabledCustomizationBehavior(.visibility)

                TableColumn(suite.cpuColumn, value: \.cpu) { row in
                    number(MetricFormat.fixed(row.cpu, decimals: 1, unit: ""))
                }
                .width(min: 56, ideal: 70)
                .customizationID("cpu")

                TableColumn(suite.memoryColumn, value: \.memory) { row in
                    number(row.memory > 0 ? MetricFormat.bytes(UInt64(row.memory)) : "—")
                }
                .width(min: 70, ideal: 90)
                .customizationID("memory")

                TableColumn(strings.gpuColumn, value: \.gpuSortValue) { row in
                    number(row.gpu.map { MetricFormat.fixed($0, decimals: 1, unit: "") } ?? "—")
                }
                .width(min: 56, ideal: 70)
                .customizationID("gpu")

                TableColumn(suite.energyScoreColumn, value: \.energy) { row in
                    number(MetricFormat.fixed(row.energy, decimals: 1, unit: ""))
                }
                .width(min: 70, ideal: 100)
                .customizationID("energy")
                // With its feature off the column is neither shown nor offered.
                .disabledCustomizationBehavior(energyAvailable ? [] : .visibility)

                TableColumn(suite.typeColumn) { row in
                    Text(category(row.category)).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 100)
                .customizationID("type")

                TableColumn(suite.pidColumn, value: \.pid) { row in
                    number(String(row.pid)).foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 60)
                .customizationID("pid")
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: pid_t.self) { pids in
                if let row = row(pids) {
                    Button(suite.inspectButton) { inspect(row) }
                    if canKill(row) {
                        Divider()
                        Button(suite.killButton + "…") { requestKill(row) }
                    }
                }
            } primaryAction: { pids in
                if let row = row(pids) { inspect(row) }
            }
            .overlay {
                if !feed.loaded {
                    ProgressView(dash.loadingProcesses).controlSize(.small)
                } else if feed.sortOrder.first?.keyPath == \ProcessTableRow.gpuSortValue,
                          !feed.rows.isEmpty, feed.rows.allSatisfy({ ($0.gpu ?? 0) == 0 }),
                          ProcessUsageService.shared.hasGPUDeltaSample {
                    // A driver that bills GPU time to no process says so,
                    // instead of a column of zeros that reads as "idle".
                    Text(dash.noGPUProcesses)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // A one-line status bar, like Finder's: the count shown.
            Divider()
            Text(String(format: dash.processCountFormat, feed.rows.count))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .searchable(text: $state.processSearch, placement: .toolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let row = selectedRow { inspect(row) }
                } label: {
                    Label(suite.inspectButton, systemImage: "info.circle")
                }
                .help(suite.inspectButton)
                .disabled(selectedRow == nil)

                Button {
                    if let row = selectedRow { requestKill(row) }
                } label: {
                    Label(suite.killButton, systemImage: "xmark.octagon")
                }
                .help(suite.killButton)
                .disabled(selectedRow.map { !canKill($0) } ?? true)
            }
        }
        .confirmationDialog(suite.killConfirmTitle, isPresented: Binding(
            get: { killRequest != nil }, set: { if !$0 { killRequest = nil } }
        ), titleVisibility: .visible, presenting: killRequest) { request in
            Button(suite.killButton, role: .destructive) {
                KillProcessService.shared.kill(pid: request.pid, name: request.name,
                                               startedAt: request.startedAt, force: false) {
                    Task { @MainActor in feed.refreshNow() }
                }
            }
            Button(suite.killCancel, role: .cancel) {}
        } message: { request in
            Text(String(format: suite.killConfirmMessage, request.name, Int(request.pid)))
        }
        .alert(suite.killButton, isPresented: $killUnavailable) {
            Button(strings.ok) {}
        } message: {
            Text(strings.killUnavailable)
        }
        .alert(suite.inspectButton, isPresented: $processGone) {
            Button(strings.ok) {}
        } message: {
            Text(strings.processGone)
        }
        .onAppear {
            loadColumns()
            feed.search = state.processSearch
            feed.setActive(state.isVisible)
            publishSelection()
        }
        .onDisappear {
            feed.setActive(false)
            state.canInspectSelection = false
            state.canTerminateSelection = false
        }
        .onChange(of: state.isVisible) { _, visible in feed.setActive(visible) }
        .onChange(of: state.processSearch) { _, search in feed.search = search }
        .onChange(of: selection) { _, _ in publishSelection() }
        .onChange(of: feed.rows) { _, _ in publishSelection() }
        .onReceive(state.commands) { command in
            guard let row = selectedRow else { return }
            switch command {
            case .inspect: inspect(row)
            case .terminate: requestKill(row)
            }
        }
        .onChange(of: columns) { _, value in
            if let data = try? JSONEncoder().encode(value) { columnData = data }
        }
        .onChange(of: runtime.revision) { _, _ in applyEnergyGate() }
    }

    /// What the View menu may offer for the current selection.
    private func publishSelection() {
        state.canInspectSelection = selectedRow != nil
        state.canTerminateSelection = selectedRow.map(canKill) ?? false
    }

    private var selectedRow: ProcessTableRow? {
        selection.flatMap { pid in feed.rows.first { $0.pid == pid } }
    }

    private func row(_ pids: Set<pid_t>) -> ProcessTableRow? {
        pids.first.flatMap { pid in feed.rows.first { $0.pid == pid } }
    }

    private func number(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func category(_ category: ProcessCategory) -> String {
        FeatureStrings.processInspector(l10n.language).categoryName(category)
    }

    /// The Inspector can force quit, so it opens only for a pid that is
    /// still the app the row names.
    private func inspect(_ row: ProcessTableRow) {
        guard let checked = ProcessKillRequest.current(pid: row.pid, name: row.name) else {
            processGone = true
            feed.refreshNow()
            return
        }
        ProcessInspectorWindowController.shared.present(for: ProcessUsage(pid: row.pid, name: row.name, value: row.cpu),
                                                        startedAt: checked.startedAt)
    }

    /// The same gate the process manager had: the feature is on and the
    /// process is not one the system needs.
    private func canKill(_ row: ProcessTableRow) -> Bool {
        AppFeature.killProcess.isAvailable && !KillProcessService.isProtected(pid: row.pid, name: row.name)
    }

    /// The row's pid can be a cached one; the request is made only if it
    /// still names the same app, and it carries the start time read now.
    /// When it cannot act, it says so instead of doing nothing.
    private func requestKill(_ row: ProcessTableRow) {
        guard canKill(row) else { return }
        if let request = ProcessKillRequest.current(pid: row.pid, name: row.name) {
            killRequest = request
        } else {
            killUnavailable = true
            feed.refreshNow()
        }
    }

    private func loadColumns() {
        if let saved = try? JSONDecoder().decode(TableColumnCustomization<ProcessTableRow>.self, from: columnData) {
            columns = saved
        }
        applyEnergyGate()
    }

    /// The energy estimate shows only while its feature is on, as the Energy
    /// tab did. The user's own choice to hide or show it is left alone.
    private func applyEnergyGate() {
        let step = Self.energyGate(available: AppFeature.monitorEnergy.isAvailable,
                                   hidden: columns[visibility: "energy"] == .hidden,
                                   hiddenByGate: energyHiddenByGate)
        if let hide = step.hide { columns[visibility: "energy"] = hide ? .hidden : .automatic }
        energyHiddenByGate = step.hiddenByGate
    }

    /// What the energy column does when the feature or the window changes:
    /// hidden while the feature is off (and remembered as the gate's doing),
    /// shown again when the feature returns only if the gate hid it.
    /// `hide` is nil when the column stays as the user left it.
    nonisolated static func energyGate(available: Bool, hidden: Bool,
                                       hiddenByGate: Bool) -> (hide: Bool?, hiddenByGate: Bool) {
        if !available { return (hidden ? nil : true, hiddenByGate || !hidden) }
        if hiddenByGate { return (false, false) }
        return (nil, false)
    }
}
