// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The lowest and highest CPU readings since launch (or the last Reset),
/// under the expanded CPU row. A disclosure whose header says since when,
/// with Reset at its end; one plain row per reading.
struct SessionPeaksRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var tracker = SessionPeaksTracker.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.panelSessionPeaksExpanded) private var isExpanded = true
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @State private var windowVisible = false
    @State private var isPollingFans = false

    private var text: SessionPeakStrings { FeatureStrings.sessionPeaks(l10n.language) }

    private var unit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    private var startText: String {
        tracker.peaks.startedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(Locale(identifier: l10n.language.rawValue)))
    }

    var body: some View {
        let peaks = tracker.peaks
        HeaderDisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                row(text.temperature, SessionPeaks.rangeText(peaks.temperature) {
                    MetricFormat.temperature($0, unit: unit)
                })
                row(text.power, SessionPeaks.rangeText(peaks.power) { MetricFormat.watts($0) })
                row(text.clock, SessionPeaks.rangeText(peaks.clock) {
                    MetricFormat.fixed($0, decimals: 1, unit: "GHz")
                })
                if peaks.fan != nil {
                    row(text.fan, SessionPeaks.rangeText(peaks.fan) {
                        MetricFormat.fixed($0, decimals: 0, unit: "RPM")
                    })
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 8) {
                Text(text.since(startText))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(text.reset) { tracker.reset() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 10.5))
                    .help(text.resetHelp)
            }
        }
        .padding(.leading, 16)
        .background(WindowVisibilityReader { windowVisible = $0 })
        .onAppear { updateFanPolling() }
        .onDisappear { setFanPolling(false) }
        .onChange(of: windowVisible) { _, _ in updateFanPolling() }
        .onChange(of: isExpanded) { _, _ in updateFanPolling() }
        .onChange(of: monitor.snapshot.isKextAvailable) { _, _ in updateFanPolling() }
    }

    /// A reading's name on the left and its range on the right, like the
    /// other detail rows under the CPU row.
    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// The fan controller reads the fans only while someone shows them.
    /// These rows are one such view while they are open and on screen, and
    /// only where the processor kext that reads the fans is loaded.
    private func updateFanPolling() {
        setFanPolling(windowVisible && isExpanded && monitor.snapshot.isKextAvailable)
    }

    private func setFanPolling(_ on: Bool) {
        guard on != isPollingFans else { return }
        isPollingFans = on
        if on { FanCurveController.shared.startPolling() } else { FanCurveController.shared.stopPolling() }
    }
}
