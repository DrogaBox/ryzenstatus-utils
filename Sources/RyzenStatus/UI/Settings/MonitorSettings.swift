// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Monitor" settings page: pick what shows next to the menu bar icon, how
/// often it refreshes, which blocks appear in the panel, and which metrics draw
/// a history graph. Everything is opt-in or reversible, so users keep only what
/// they find useful.
struct MonitorSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    @AppStorage(DefaultsKey.monitorInterval) private var interval = 1.0
    @AppStorage(DefaultsKey.processListRefreshInterval) private var processListInterval = 1.0
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.networkSpeedUnit) private var networkSpeedUnit = NetworkSpeedUnit.bytes

    @AppStorage(DefaultsKey.monitorGraphCPU) private var graphCPU = true
    @AppStorage(DefaultsKey.monitorGraphGPU) private var graphGPU = true
    @AppStorage(DefaultsKey.monitorGraphMemory) private var graphMemory = true
    @AppStorage(DefaultsKey.monitorGraphNetwork) private var graphNetwork = true
    @AppStorage(DefaultsKey.monitorGraphDisk) private var graphDisk = true
    @AppStorage(DefaultsKey.monitorGraphPower) private var graphPower = true
    @AppStorage(DefaultsKey.monitorGraphBattery) private var graphBattery = true
    @AppStorage(DefaultsKey.panelViewStyle) private var panelViewStyle = "cards"

    var body: some View {
        // A plain stack, not a lazy one: a lazy stack estimates the rows it
        // has not built yet, and with the taller Bars options this page kept
        // it re-measuring and re-anchoring without ever settling, which hung
        // Settings on the first scroll. Pinned headers exist only on lazy
        // stacks, so the preview sits above the scroll view instead, where it
        // also stays in view for the shared units further down that change it.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.s.monitorMenuBarPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MenuBarMetricsPreview()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.s.tabMonitor).font(.title2.bold())
                        Text(FeatureStrings.settingsPages(l10n.language).monitorDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    groupHeading(l10n.s.monitorMenuBarSection, symbol: "menubar.rectangle")
                    MenuBarSettings()
                    groupHeading(l10n.s.monitorPanelSection, symbol: "macwindow")
                    panelCard
                    graphsCard
                    groupHeading(FeatureStrings.monitorLayout(l10n.language).shared, symbol: "slider.horizontal.3")
                    readingsCard
                    MonitorCSVControls()
                    alertsCard.settingsSectionAnchor(.monitorAlerts, cornerRadius: 16)
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(22)
            }
        }
        .toggleStyle(.switch)
        // The live preview samples only while the page is on screen in a
        // visible Settings window.
        .settingsPageActivity(.monitorSettings)
        .onAppear {
            interval = Defaults.sanitizedMonitorInterval(interval)
            if TemperatureUnit(rawValue: temperatureUnit) == nil {
                temperatureUnit = TemperatureUnit.celsius.rawValue
            }
        }
    }

    /// Splits the page into what the menu bar shows, what the panel shows,
    /// and what both share, so an option is never read as the other's.
    private func groupHeading(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    private var appearanceStrings: MenuBarAppearanceStrings {
        FeatureStrings.menuBarAppearance(l10n.language)
    }

    /// What the panel opens on, its style and what each block shows.
    private var panelCard: some View {
        SettingsCard {
            SettingsRow(symbol: "rectangle.grid.2x2", title: appearanceStrings.popoverStyle) {
                Picker(appearanceStrings.popoverStyle, selection: $panelViewStyle) {
                    Text(appearanceStrings.classicCards).tag("cards")
                    Text(appearanceStrings.iStatsWidgets).tag("istats")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            MonitorPanelConfig()
            Text(l10n.s.monitorPanelConfigHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Which readings keep a history graph in the panel.
    private var graphsCard: some View {
        SettingsCard(title: l10n.s.monitorGraphsSection) {
            if AppFeature.monitorCPU.isAvailable {
                graphRow(l10n.s.monitorShowCPU, symbol: "cpu", isOn: $graphCPU)
            }
            if AppFeature.monitorGPU.isAvailable {
                graphRow(l10n.s.monitorShowGPU, symbol: "display", isOn: $graphGPU)
            }
            if AppFeature.monitorMemory.isAvailable {
                graphRow(l10n.s.monitorShowMemory, symbol: "memorychip", isOn: $graphMemory)
            }
            if AppFeature.monitorNetwork.isAvailable {
                graphRow(l10n.s.monitorShowNetwork, symbol: "network", isOn: $graphNetwork)
            }
            if AppFeature.monitorDisk.isAvailable {
                graphRow(l10n.s.diskSection, symbol: "internaldrive", isOn: $graphDisk)
            }
            if AppFeature.monitorPower.isAvailable {
                graphRow(l10n.s.monitorShowPowerLabel, symbol: "bolt.fill", isOn: $graphPower)
                if PowerSampler.hasInternalBattery {
                    graphRow(l10n.s.batteryLabel, symbol: "battery.75percent", isOn: $graphBattery)
                }
            }
            Text(l10n.s.monitorGraphsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func graphRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }

    /// Settings both surfaces read.
    private var readingsCard: some View {
        SettingsCard {
            SettingsRow(symbol: "timer", title: l10n.s.monitorIntervalLabel) {
                Picker(l10n.s.monitorIntervalLabel, selection: $interval) {
                    Text(l10n.s.monitorInterval1).tag(1.0)
                    Text(l10n.s.monitorInterval2).tag(2.0)
                    Text(l10n.s.monitorInterval5).tag(5.0)
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(symbol: "list.bullet.rectangle", title: l10n.s.processListRefreshIntervalLabel) {
                Picker(l10n.s.processListRefreshIntervalLabel, selection: $processListInterval) {
                    Text(l10n.s.monitorInterval1).tag(1.0)
                    Text(l10n.s.monitorInterval2).tag(2.0)
                    Text(l10n.dashboard.intervalThreeSeconds).tag(3.0)
                    Text(l10n.s.monitorInterval5).tag(5.0)
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(symbol: "thermometer.medium", title: l10n.s.temperatures) {
                Picker(l10n.s.temperatures, selection: $temperatureUnit) {
                    Text("°C").tag(TemperatureUnit.celsius.rawValue)
                    Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if AppFeature.monitorNetwork.isAvailable {
                let title = FeatureStrings.monitorLayout(l10n.language).networkSpeedUnit
                SettingsRow(symbol: "network", title: title) {
                    Picker(title, selection: $networkSpeedUnit) {
                        Text("MB/s").tag(NetworkSpeedUnit.bytes)
                        Text("Mbps").tag(NetworkSpeedUnit.bits)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private var alertsCard: some View {
        SettingsCard(title: FeatureStrings.monitorAlerts(l10n.language).section) {
            MonitorAlertsControls(compact: false)
        }
    }
}

/// Drag-to-reorder and show/hide list for the panel's major sections. Writes the
/// order to `PanelLayout` and each section's visibility to its own key, both of
/// which the live panel observes. A bounded, non-scrolling list so it sits inside
/// the grouped Form without its own scroll area.
/// Lives on the General page (the panel hosts more than monitoring); also
/// consulted by the Monitor page for the fan beta toggle placement.
struct PanelOrderEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var order: [PanelSectionID] = PanelLayout.order
    @State private var dragging: PanelSectionID?
    /// Bumped whenever a section is shown/hidden so the dimmed titles and the
    /// "can't hide the last one" guard recompute.
    @State private var visibilityChanges = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(editableOrder) { id in
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Text(id.title(l10n.s))
                                .foregroundStyle(isShown(id) ? .primary : .secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .opacity(dragging == id ? 0.45 : 1)
                        .onDrag {
                            dragging = id
                            return NSItemProvider(object: id.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: PanelOrderDropDelegate(target: id,
                                                                 order: $order,
                                                                 dragging: $dragging))

                        SectionVisibilityEye(id: id,
                                             canHide: visibleCount > 1,
                                             onChange: { visibilityChanges += 1 })
                    }
                    .frame(height: 32)

                    if id != editableOrder.last {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { order = PanelLayout.order }
    }

    private var editableOrder: [PanelSectionID] {
        order.filter { $0.isAvailable }
    }

    private func isShown(_ id: PanelSectionID) -> Bool {
        _ = visibilityChanges
        return PanelLayout.isShown(id)
    }

    /// How many sections are currently visible in the panel, so the last one
    /// can't be hidden (which would leave an empty panel).
    private var visibleCount: Int {
        _ = visibilityChanges
        return editableOrder.reduce(0) { $0 + (PanelLayout.isShown($1) ? 1 : 0) }
    }
}

/// An eye button that shows/hides one panel section, backed by that section's
/// own visibility key so the live panel updates immediately.
private struct SectionVisibilityEye: View {
    @ObservedObject private var l10n = L10n.shared
    let id: PanelSectionID
    let canHide: Bool
    let onChange: () -> Void
    @AppStorage private var shown: Bool

    init(id: PanelSectionID, canHide: Bool, onChange: @escaping () -> Void) {
        self.id = id
        self.canHide = canHide
        self.onChange = onChange
        _shown = AppStorage(wrappedValue: id.shownByDefault, id.visibilityKey)
    }

    var body: some View {
        Button {
            shown.toggle()
            onChange()
        } label: {
            Image(systemName: shown ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep at least one section visible.
        .disabled(shown && !canHide)
        .help(shown ? l10n.s.panelHideItem : l10n.s.panelShowItem)
        .accessibilityLabel(shown ? l10n.s.panelHideItem : l10n.s.panelShowItem)
    }
}

private struct PanelOrderDropDelegate: DropDelegate {
    let target: PanelSectionID
    @Binding var order: [PanelSectionID]
    @Binding var dragging: PanelSectionID?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        PanelLayout.setOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        PanelLayout.setOrder(order)
        return true
    }
}
