// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Monitor: start or stop the continuous CSV log, and save the
/// long history as CSV.
struct MonitorCSVControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var logger = MonitorCSVLogger.shared
    @State private var exportRange: LongHistoryRange = .oneDay

    private var strings: MonitorCSVFeatureStrings { FeatureStrings.monitorCSV(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.section) {
            if let url = logger.fileURL {
                SettingsRow(symbol: "record.circle", title: url.lastPathComponent,
                            caption: String(format: strings.rowsWritten,
                                            logger.rowCount.formatted(.number.locale(Locale(identifier: l10n.language.rawValue))))) {
                    Button(strings.stop) { logger.stop() }
                }
            } else {
                SettingsRow(symbol: "tablecells", title: strings.logTitle, caption: strings.logCaption) {
                    Button(strings.logButton, action: chooseLogFile)
                }
            }
            SettingsRow(symbol: "clock.arrow.circlepath", title: strings.exportTitle, caption: strings.exportCaption) {
                HStack(spacing: 8) {
                    Picker(strings.rangeLabel, selection: $exportRange) {
                        ForEach(LongHistoryRange.allCases) { range in
                            Text(range.label(l10n.language)).tag(range)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(strings.rangeLabel)
                    Button(strings.exportButton, action: chooseExportFile)
                }
            }
        }
    }

    private func savePanel(defaultName: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel
    }

    private func chooseLogFile() {
        let panel = savePanel(defaultName: MonitorCSVLogger.defaultFileName())
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in MonitorCSVLogger.shared.start(url: url) }
        }
    }

    private func chooseExportFile() {
        let range = exportRange
        let panel = savePanel(defaultName: MonitorCSVLogger.defaultFileName(prefix: "RyzenStatus-History"))
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MonitorCSVLogger.exportHistory(range: range, to: url)
        }
    }
}
