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

    @AppStorage(DefaultsKey.menuBarCombineTemperatures) private var combineTemperatures = true
    @AppStorage(DefaultsKey.menuBarSeparateMetrics) private var separateMetrics = false
    @AppStorage(DefaultsKey.menuBarMetricSpacing) private var metricSpacing = "standard"
    @AppStorage(DefaultsKey.menuBarMetricAppearance) private var metricAppearance = "values"
    @AppStorage(DefaultsKey.menuBarHideIconWithMetrics) private var hideIconWithMetrics = false
    @AppStorage(DefaultsKey.menuBarGraphShowsValue) private var graphShowsValue = false
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
    @AppStorage(DefaultsKey.menuBarMetricAppearanceCPU) private var appCPU = "values"
    @AppStorage(DefaultsKey.menuBarMetricAppearanceGPU) private var appGPU = "values"
    @AppStorage(DefaultsKey.menuBarMetricAppearanceMemory) private var appRAM = "values"
    @AppStorage(DefaultsKey.menuBarMetricAppearanceNetwork) private var appNet = "values"
    @AppStorage(DefaultsKey.menuBarMetricAppearanceDiskUsage) private var appDisk = "values"

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
                    menuBarCard
                    menuBarStyleCard
                    menuBarLayoutCard
                    groupHeading(l10n.s.monitorPanelSection, symbol: "macwindow")
                    panelCard
                    graphsCard
                    groupHeading(FeatureStrings.monitorLayout(l10n.language).shared, symbol: "slider.horizontal.3")
                    readingsCard
                    alertsCard
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
            metricAppearance = Defaults.sanitizedMenuBarMetricAppearance(metricAppearance)
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

    private var appearance: MenuBarMetricAppearance {
        MenuBarMetricAppearance(rawValue: Defaults.sanitizedMenuBarMetricAppearance(metricAppearance)) ?? .values
    }

    /// What sits in the menu bar, in the order it appears there.
    private var menuBarCard: some View {
        SettingsCard {
            Text(l10n.s.monitorMenuBarCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarMetricOrderEditor()
        }
    }

    /// How each usage reading is drawn, and the palettes the graphs use.
    private var menuBarStyleCard: some View {
        SettingsCard(title: appearanceStrings.label) {
            styleRow(MenuBarMetric.cpu.title(l10n.s), symbol: "cpu", selection: $appCPU,
                     options: ["values", "bars", "pie", "sparkline", "histogram", "classic"])
            styleRow(MenuBarMetric.gpu.title(l10n.s), symbol: "display", selection: $appGPU,
                     options: ["values", "bars", "pie", "sparkline", "classic"])
            styleRow(MenuBarMetric.memory.title(l10n.s), symbol: "memorychip", selection: $appRAM,
                     options: ["values", "bars", "pie", "sparkline"])
            styleRow(MenuBarMetric.network.title(l10n.s), symbol: "network", selection: $appNet,
                     options: ["values", "sparkline"])
            styleRow(MenuBarMetric.diskUsage.title(l10n.s), symbol: "internaldrive", selection: $appDisk,
                     options: ["values", "bars"])
            Text(appearanceStrings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            MenuBarUsageBarSettings(strings: appearanceStrings)
            MenuBarGraphThemeSettings(strings: FeatureStrings.menuBarGraphTheme(l10n.language))
            SettingsRow(symbol: "number", title: l10n.s.graphShowsNumericValue) {
                Toggle(l10n.s.graphShowsNumericValue, isOn: $graphShowsValue).labelsHidden()
            }
        }
    }

    /// How the readings share the menu bar with the icon and with each other.
    private var menuBarLayoutCard: some View {
        SettingsCard {
            if appearance != .bars {
                SettingsRow(symbol: "thermometer.medium", title: l10n.s.monitorCombineTemperatures,
                            caption: l10n.s.monitorCombineTemperaturesCaption) {
                    Toggle(l10n.s.monitorCombineTemperatures, isOn: $combineTemperatures).labelsHidden()
                }
            }
            SettingsRow(symbol: "arrow.left.and.right", title: l10n.s.menuBarSpacingLabel) {
                Picker(l10n.s.menuBarSpacingLabel, selection: $metricSpacing) {
                    Text(l10n.s.menuBarSpacingStandard).tag("standard")
                    Text(l10n.s.menuBarSpacingCompact).tag("compact")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(symbol: "eye.slash", title: l10n.s.menuBarHideIconToggle,
                        caption: l10n.s.menuBarHideIconCaption) {
                Toggle(l10n.s.menuBarHideIconToggle, isOn: $hideIconWithMetrics).labelsHidden()
            }
            SettingsRow(symbol: "rectangle.split.3x1", title: l10n.s.monitorSeparateMenuBarMetrics,
                        caption: appearance.allowsCombinedTemperatures
                            ? l10n.s.monitorSeparateMenuBarMetricsCaption : nil) {
                Toggle(l10n.s.monitorSeparateMenuBarMetrics, isOn: $separateMetrics).labelsHidden()
            }
        }
    }

    private func styleRow(_ title: String, symbol: String, selection: Binding<String>,
                          options: [String]) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(styleTitle(option)).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func styleTitle(_ option: String) -> String {
        switch option {
        case "bars": return appearanceStrings.bars
        case "pie": return appearanceStrings.pie
        case "sparkline": return appearanceStrings.sparkline
        case "histogram": return appearanceStrings.histogram
        case "classic": return Self.classicTitle(l10n.language)
        default: return appearanceStrings.values
        }
    }

    /// The classic menu bar style's name in each language.
    private static func classicTitle(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Classic"
        case .ptBR: return "Clássico"
        case .tr: return "Klasik"
        case .ru: return "Классика"
        case .es: return "Clásico"
        case .sk: return "Klasický"
        case .de: return "Klassisch"
        case .fr: return "Classique"
        case .it: return "Classico"
        case .ja: return "クラシック"
        case .ko: return "클래식"
        case .uk: return "Класика"
        case .zhHans: return "经典"
        case .zhTW, .zhHK: return "經典"
        }
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

private struct MenuBarUsageBarSettings: View {
    let strings: MenuBarAppearanceStrings

    @AppStorage(DefaultsKey.menuBarUsageBarNormalColor) private var normalColor = MenuBarUsageBarSupport.defaultNormalColor
    @AppStorage(DefaultsKey.menuBarUsageBarElevatedColor) private var elevatedColor = MenuBarUsageBarSupport.defaultElevatedColor
    @AppStorage(DefaultsKey.menuBarUsageBarCriticalColor) private var criticalColor = MenuBarUsageBarSupport.defaultCriticalColor
    @AppStorage(DefaultsKey.menuBarUsageBarMediumThreshold) private var mediumThreshold = MenuBarUsageBarSupport.defaultMediumThreshold
    @AppStorage(DefaultsKey.menuBarUsageBarHighThreshold) private var highThreshold = MenuBarUsageBarSupport.defaultHighThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(strings.customize)
                .font(.subheadline.weight(.semibold))

            ColorPicker(strings.normalColor,
                        selection: colorBinding($normalColor,
                                                fallback: MenuBarUsageBarSupport.defaultNormalColor),
                        supportsOpacity: false)
            ColorPicker(strings.mediumColor,
                        selection: colorBinding($elevatedColor,
                                                fallback: MenuBarUsageBarSupport.defaultElevatedColor),
                        supportsOpacity: false)
            ColorPicker(strings.highColor,
                        selection: colorBinding($criticalColor,
                                                fallback: MenuBarUsageBarSupport.defaultCriticalColor),
                        supportsOpacity: false)

            Divider()

            Stepper(value: mediumBinding, in: 1...99) {
                HStack {
                    Text(strings.mediumFrom)
                    Spacer()
                    Text("\(mediumThreshold)%")
                        .monospacedDigit()
                }
            }
            Stepper(value: highBinding, in: 2...100) {
                HStack {
                    Text(strings.highFrom)
                    Spacer()
                    Text("\(highThreshold)%")
                        .monospacedDigit()
                }
            }
        }
        .padding(.leading, 12)
        .onAppear(perform: sanitize)
    }

    private var mediumBinding: Binding<Int> {
        Binding(get: { mediumThreshold },
                set: { mediumThreshold = min(max(1, $0), max(1, highThreshold - 1)) })
    }

    private var highBinding: Binding<Int> {
        Binding(get: { highThreshold },
                set: { highThreshold = min(100, max(mediumThreshold + 1, $0)) })
    }

    private func colorBinding(_ storage: Binding<String>, fallback: String) -> Binding<Color> {
        Binding {
            let rgb = MenuBarUsageBarSupport.rgb(for: storage.wrappedValue, fallback: fallback)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { color in
            guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
            storage.wrappedValue = MenuBarUsageBarSupport.hex(red: Double(converted.redComponent),
                                                              green: Double(converted.greenComponent),
                                                              blue: Double(converted.blueComponent))
        }
    }

    private func sanitize() {
        normalColor = MenuBarUsageBarSupport.sanitizedColorHex(normalColor,
                                                               fallback: MenuBarUsageBarSupport.defaultNormalColor)
        elevatedColor = MenuBarUsageBarSupport.sanitizedColorHex(elevatedColor,
                                                                 fallback: MenuBarUsageBarSupport.defaultElevatedColor)
        criticalColor = MenuBarUsageBarSupport.sanitizedColorHex(criticalColor,
                                                                 fallback: MenuBarUsageBarSupport.defaultCriticalColor)
        let thresholds = MenuBarUsageBarSupport.thresholds(medium: mediumThreshold,
                                                           high: highThreshold)
        mediumThreshold = thresholds.medium
        highThreshold = thresholds.high
    }
}

/// Theme and shape of the history, core, ring and network graphs. Light and
/// dark menu bars choose separately; the live preview above shows the result.
private struct MenuBarGraphThemeSettings: View {
    let strings: MenuBarGraphThemeStrings

    @AppStorage(DefaultsKey.menuBarGraphThemeLight) private var lightTheme = MenuBarGraphTheme.system.rawValue
    @AppStorage(DefaultsKey.menuBarGraphThemeDark) private var darkTheme = MenuBarGraphTheme.system.rawValue
    @AppStorage(DefaultsKey.menuBarGraphLightBackground) private var lightBackground = MenuBarGraphLightBackground.filled.rawValue
    @AppStorage(DefaultsKey.menuBarGraphHistoryWidth) private var historyWidth = MenuBarGraphHistoryWidth.standard.rawValue
    @AppStorage(DefaultsKey.menuBarGraphHistorySpaced) private var historySpaced = false
    @AppStorage(DefaultsKey.menuBarNetworkGraphLayout) private var networkLayout = MenuBarNetworkGraphLayout.mirrored.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(strings.title)
                .font(.subheadline.weight(.semibold))

            themePicker(strings.lightMode, selection: $lightTheme)
            themePicker(strings.darkMode, selection: $darkTheme)
            Picker(strings.lightBackground, selection: $lightBackground) {
                Text(strings.backgroundFilled).tag(MenuBarGraphLightBackground.filled.rawValue)
                Text(strings.backgroundOutline).tag(MenuBarGraphLightBackground.outline.rawValue)
            }
            .pickerStyle(.segmented)

            Divider()

            Picker(strings.historyWidth, selection: $historyWidth) {
                Text(strings.widthNarrow).tag(MenuBarGraphHistoryWidth.narrow.rawValue)
                Text(strings.widthStandard).tag(MenuBarGraphHistoryWidth.standard.rawValue)
                Text(strings.widthWide).tag(MenuBarGraphHistoryWidth.wide.rawValue)
            }
            .pickerStyle(.segmented)
            Toggle(strings.spacedColumns, isOn: $historySpaced)
            Picker(strings.networkLayout, selection: $networkLayout) {
                Text(strings.networkMirrored).tag(MenuBarNetworkGraphLayout.mirrored.rawValue)
                Text(strings.networkSplit).tag(MenuBarNetworkGraphLayout.split.rawValue)
                Text(strings.networkRising).tag(MenuBarNetworkGraphLayout.rising.rawValue)
            }
            Text(strings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .onAppear(perform: sanitize)
    }

    private func themePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(MenuBarGraphTheme.allCases, id: \.self) { theme in
                Label {
                    Text(strings.name(of: theme))
                } icon: {
                    Image(nsImage: Self.swatch(for: theme))
                }
                .tag(theme.rawValue)
            }
        }
    }

    /// Three dots with the theme's colors, so the menu shows each pairing
    /// before it is picked. Mono shows gray because its real tone depends
    /// on the menu bar it lands on.
    private static func swatch(for theme: MenuBarGraphTheme) -> NSImage {
        let colors = MenuBarGraphPalette.colors(for: theme,
                                                accent: MenuBarGraphPainter.accentRGB(),
                                                mono: MenuBarUsageBarSupport.RGB(red: 0.55, green: 0.55, blue: 0.55))
        let dots = [colors.primary, colors.secondary, colors.tertiary]
        let diameter: CGFloat = 8
        let image = NSImage(size: NSSize(width: diameter * 2.5, height: diameter), flipped: false) { _ in
            for (index, rgb) in dots.enumerated().reversed() {
                NSColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: CGFloat(index) * diameter * 0.75, y: 0,
                                            width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func sanitize() {
        lightTheme = Defaults.sanitizedMenuBarGraphTheme(lightTheme)
        darkTheme = Defaults.sanitizedMenuBarGraphTheme(darkTheme)
        lightBackground = Defaults.sanitizedMenuBarGraphLightBackground(lightBackground)
        historyWidth = Defaults.sanitizedMenuBarGraphHistoryWidth(historyWidth)
        networkLayout = Defaults.sanitizedMenuBarNetworkGraphLayout(networkLayout)
    }
}

/// Drag-to-reorder and show/hide list for the menu bar metrics. The order stays
/// independent from which metrics are visible, so toggles do not reshuffle it.
private struct MenuBarMetricOrderEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.menuBarMetricOrder) private var metricOrder = ""
    @State private var order: [MenuBarMetric] = MenuBarMetric.order(in: .standard)
    @State private var dragging: MenuBarMetric?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(visibleOrder) { metric in
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            Image(systemName: metric.symbolName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(metric.title(l10n.s))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .opacity(dragging == metric ? 0.45 : 1)
                        .onDrag {
                            dragging = metric
                            return NSItemProvider(object: metric.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text],
                                delegate: MenuBarMetricOrderDropDelegate(target: metric,
                                                                         order: $order,
                                                                         dragging: $dragging))

                        MenuBarMetricVisibilityToggle(metric: metric)
                    }
                    .frame(height: 32)

                    if metric == .memory {
                        MemoryMenuBarOrderOption()
                    }

                    if metric == .network {
                        NetworkMenuBarOrderOption()
                    }

                    if metric != visibleOrder.last {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear { order = MenuBarMetric.order(in: .standard) }
        .onChange(of: metricOrder) { _, _ in order = MenuBarMetric.order(in: .standard) }
    }

    /// Metrics whose family left the hub keep their saved slot but stay out
    /// of the editor until they return.
    private var visibleOrder: [MenuBarMetric] {
        order.filter { $0.feature.isAvailable }
    }
}

// Contributed in PR #179: the memory pressure-dot option lives under the
// Memory row, matching the Network row's inline option.
/// Inline per-metric option row: caption on the left, a switch on the right,
/// indented under its metric. The switch is a hand-rolled capsule Button on
/// purpose: a native Toggle inside the reorderable metric list never receives
/// the click (the row's drag handling swallows it), while a plain Button does.
private struct MetricRowOptionToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                isOn.toggle()
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: 28, height: 16)
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 12, height: 12)
                        .padding(2)
                }
                .frame(width: 30, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(label)
            // VoiceOver reads it as the switch it draws, with its on/off value.
            .accessibilityRepresentation {
                Toggle(label, isOn: $isOn)
            }
        }
        .padding(.leading, 58)
        .padding(.trailing, 4)
        .padding(.bottom, 7)
    }
}

private struct MemoryMenuBarOrderOption: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.menuBarMemory) private var menuBarMemory = true
    @AppStorage(DefaultsKey.menuBarMemoryStyle) private var memoryStyle = "percent"

    var body: some View {
        if menuBarMemory {
            MetricRowOptionToggle(label: l10n.s.monitorMemoryPressureDot,
                                  isOn: Binding(
                                      get: { Defaults.sanitizedMenuBarMemoryStyle(memoryStyle) != "percent" },
                                      set: { memoryStyle = $0 ? "both" : "percent" }))
                .onAppear {
                    memoryStyle = Defaults.sanitizedMenuBarMemoryStyle(memoryStyle)
                }
        }
    }
}

private struct NetworkMenuBarOrderOption: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.menuBarNetwork) private var menuBarNetwork = true
    @AppStorage(DefaultsKey.menuBarNetworkUploadFirst) private var uploadFirst = false

    var body: some View {
        if menuBarNetwork {
            MetricRowOptionToggle(label: l10n.s.monitorNetworkUploadFirst, isOn: $uploadFirst)
        }
    }
}

private struct MenuBarMetricVisibilityToggle: View {
    @ObservedObject private var l10n = L10n.shared
    let metric: MenuBarMetric
    @AppStorage private var shown: Bool

    init(metric: MenuBarMetric) {
        self.metric = metric
        _shown = AppStorage(wrappedValue: false, metric.defaultsKey)
    }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: shown ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shown ? l10n.s.panelHideItem : l10n.s.panelShowItem)
        // The metric is the label and its visibility the value; the action
        // the click takes is the hint.
        .accessibilityRepresentation {
            Toggle(metric.title(l10n.s), isOn: $shown)
        }
        .accessibilityHint(shown ? l10n.s.panelHideItem : l10n.s.panelShowItem)
    }
}

private struct MenuBarMetricOrderDropDelegate: DropDelegate {
    let target: MenuBarMetric
    @Binding var order: [MenuBarMetric]
    @Binding var dragging: MenuBarMetric?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        MenuBarMetric.setOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        MenuBarMetric.setOrder(order)
        return true
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
