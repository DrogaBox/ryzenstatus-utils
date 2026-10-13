// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The Connected Devices row of the panel's System card: the count of
/// external USB devices, expanding in place into the list.
///
/// Upstream opens a metric detail page fed by `SystemMonitor`'s snapshot.
/// This fork keeps the AMD-adapted monitor out of it, so the row reads the
/// standalone `ConnectedDevicesMonitor` and expands inline instead. While
/// editing it is only a row to reorder or hide, so a drag cannot expand it.
struct PanelConnectedDevicesRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = ConnectedDevicesMonitor.shared
    @State private var expanded = false
    let editing: Bool
    @Binding var isVisible: Bool

    private var strings: ConnectedDevicesFeatureStrings { FeatureStrings.connectedDevices(l10n.language) }

    var body: some View {
        Group {
            if !isVisible {
                PanelHiddenItemRow(title: strings.title, systemImage: "cable.connector",
                                   isVisible: $isVisible)
            } else if editing {
                rowContent(isInteractive: false) {
                    PanelInlineHideButton(isVisible: $isVisible)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        rowContent(isInteractive: true) { EmptyView() }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.title)
                    .accessibilityValue(strings.formattedCount(monitor.count))
                    if expanded {
                        deviceList
                    }
                }
            }
        }
        .onAppear { monitor.beginWatching() }
        .onDisappear { monitor.endWatching() }
    }

    private func rowContent<Trailing: View>(isInteractive: Bool,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: "cable.connector")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
            Text(monitor.hasLoadedOnce ? "\(monitor.count)" : "-")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: expanded && !editing ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(isInteractive ? 1 : 0.35)
            trailing()
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        if monitor.devices.isEmpty {
            Text(monitor.hasLoadedOnce ? strings.noDevices : " ")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.devices) { device in
                    deviceRow(device)
                }
            }
            .padding(.leading, 22)
        }
    }

    private func deviceRow(_ device: ConnectedUSBDevice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cable.connector")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(device.name.isEmpty ? strings.unnamedDevice : device.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let vendor = device.vendorName {
                Text(vendor)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(String(format: "%04lX:%04lX", device.vendorId, device.productId))
        .accessibilityElement(children: .combine)
    }
}
