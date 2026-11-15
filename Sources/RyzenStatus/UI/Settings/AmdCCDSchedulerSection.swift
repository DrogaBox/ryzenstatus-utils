// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings › AMD Ryzen Power › CCD scheduler: state, counters and the live
/// switch of AMDCCDScheduler.kext. Hidden on single-CCD CPUs without the kext.
struct AmdCCDSchedulerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var status: CCDSchedulerStatus?
    @State private var log: String?
    @State private var domains = 1
    @State private var loaded = false
    @State private var busy = false
    @State private var failed = false
    @State private var showLog = false

    /// Fixed data instead of the sysctls, for offscreen renders of each state.
    struct Preview {
        var status: CCDSchedulerStatus?
        var log: String?
        var domains: Int
    }
    private let preview: Preview?

    /// The first values are read here, not in `.task`: the section is hidden
    /// until it knows there is something to show, and a hidden view never runs
    /// its task, so a late first read would keep it hidden for good. Both reads
    /// are single sysctls.
    init(preview: Preview? = nil) {
        self.preview = preview
        if let preview {
            _status = State(initialValue: preview.status)
            _log = State(initialValue: preview.log)
            _domains = State(initialValue: preview.domains)
        } else {
            _status = State(initialValue: CCDSchedulerService.readStatus())
            _log = State(initialValue: CCDSchedulerService.readLog())
            _domains = State(initialValue: CCDSchedulerService.l3Domains())
        }
        _loaded = State(initialValue: true)
    }

    var body: some View {
        Group {
            if status != nil || domains > 1 {
                Section {
                    content
                } header: {
                    Text(l10n.ccdScheduler.header)
                } footer: {
                    Text(l10n.ccdScheduler.footer)
                }
            }
        }
        .task {
            if preview != nil { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let s = l10n.ccdScheduler
        if let status {
            HStack(spacing: 8) {
                Image(systemName: status.isActive ? "square.split.2x1.fill" : "square.split.2x1")
                    .foregroundColor(status.isActive ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateText(status))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(status.isActive ? .green : (status.isHooked ? .primary : .orange))
                    Text(String(format: s.ccdCount, max(status.psets, domains)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if status.isHooked {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(s.toggle, isOn: Binding(
                        get: { status.mode == 1 },
                        set: { setMode($0) }
                    ))
                    .disabled(busy)
                    Text(failed ? s.toggleFailed : s.toggleNote)
                        .font(.caption)
                        .foregroundColor(failed ? .red : .secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    statRow(s.statNew, status.newThreads)
                    statRow(s.statKept, status.keptHome)
                    statRow(s.statSame, status.sameAnyway)
                    statRow(s.statFirst, status.noHint)
                    if let busy = status.busyHome {
                        statRow(s.statFull, busy)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
            }

            if let log, !log.isEmpty {
                // The whole row toggles, not only the arrow (a plain DisclosureGroup
                // on macOS only reacts to its small chevron).
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showLog.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(showLog ? 90 : 0))
                            Text(s.logTitle)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showLog {
                        Text(log)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if loaded {
            Text(String(format: s.notLoadedHint, domains))
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private func statRow(_ title: String, _ value: UInt64) -> some View {
        GridRow {
            Text(title).foregroundColor(.secondary)
            Text(value.formatted())
        }
    }

    private func stateText(_ status: CCDSchedulerStatus) -> String {
        let s = l10n.ccdScheduler
        switch status.state {
        case .installed: return status.mode == 1 ? s.statusActive : (status.mode == 2 ? s.statusLegacy : s.statusOff)
        case .notRun: return s.statusNotRun
        case .symbolMissing: return s.statusSymbolMissing
        case .layoutMismatch: return s.statusLayoutMismatch
        case .routeFailed: return s.statusRouteFailed
        case .singleL3: return s.statusSingleL3
        case nil: return s.statusUnknown
        }
    }

    private func refresh() async {
        let (st, lg, d) = await Task.detached(priority: .utility) {
            (CCDSchedulerService.readStatus(), CCDSchedulerService.readLog(), CCDSchedulerService.l3Domains())
        }.value
        status = st
        log = lg
        domains = d
        loaded = true
    }

    private func setMode(_ on: Bool) {
        busy = true
        failed = false
        let prompt = l10n.ccdScheduler.adminPrompt
        Task {
            let ok = await Task.detached(priority: .userInitiated) {
                CCDSchedulerService.setMode(on, prompt: prompt)
            }.value
            await refresh()
            failed = !ok || (status?.mode == 1) != on
            busy = false
        }
    }
}
