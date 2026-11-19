// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Everything the menu bar shows, on the Monitor page: which readings, in
/// which order and style (items), how they look (appearance), and how they
/// share the bar with the app's icon (behavior).
struct MenuBarSettings: View {
    @ObservedObject private var l10n = L10n.shared

    @AppStorage(DefaultsKey.menuBarCombineTemperatures) private var combineTemperatures = true
    @AppStorage(DefaultsKey.menuBarSeparateMetrics) private var separateMetrics = false
    @AppStorage(DefaultsKey.menuBarMetricSpacing) private var metricSpacing = "compact"
    @AppStorage(DefaultsKey.menuBarHideIconWithMetrics) private var hideIconWithMetrics = false
    @AppStorage(DefaultsKey.menuBarGraphShowsValue) private var graphShowsValue = false
    @AppStorage(DefaultsKey.menuBarGraphMonochrome) private var graphMonochrome = false
    @AppStorage(DefaultsKey.menuBarHighlightHighValues) private var highlightHighValues = false
    @AppStorage(DefaultsKey.menuBarNarrowText) private var narrowText = false
    /// Re-evaluates which graph options apply when any style changes.
    @StateObject private var styles = MenuBarStyleState()

    private var strings: MenuBarAppearanceStrings { FeatureStrings.menuBarAppearance(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            itemsCard
            appearanceCard
            behaviorCard
        }
    }

    /// What sits in the menu bar, in the order it appears there, and how
    /// each reading is drawn.
    private var itemsCard: some View {
        SettingsCard(title: strings.itemsTitle) {
            Text(l10n.s.monitorMenuBarCaption + " " + strings.caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarMetricOrderEditor()
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: strings.appearanceTitle) {
            SettingsRow(symbol: "arrow.left.and.right", title: strings.itemWidth, caption: strings.widthCaption) {
                Picker(strings.itemWidth, selection: $metricSpacing) {
                    Text(strings.widthFixed).tag("standard")
                    Text(strings.widthFit).tag("compact")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(symbol: "textformat.size.smaller", title: strings.narrowText, caption: strings.narrowCaption) {
                Toggle(strings.narrowText, isOn: $narrowText).labelsHidden()
            }
            SettingsRow(symbol: "exclamationmark.circle", title: strings.highlightHighValues,
                        caption: strings.highlightCaption) {
                Toggle(strings.highlightHighValues, isOn: $highlightHighValues).labelsHidden()
            }
            if styles.usesGraphs {
                SettingsRow(symbol: "paintpalette", title: strings.graphColor) {
                    Picker(strings.graphColor, selection: $graphMonochrome) {
                        Text(strings.monochrome).tag(true)
                        Text(strings.colorful).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            // Only a usage ring, history or core graph draws a value inside;
            // bars and the network graph never do.
            if styles.usesValueGraphs {
                SettingsRow(symbol: "number", title: l10n.s.graphShowsNumericValue) {
                    Toggle(l10n.s.graphShowsNumericValue, isOn: $graphShowsValue).labelsHidden()
                }
            }
            // The thresholds feed the bars and the highlighted values; the
            // colors only the bars.
            if (styles.usesBars && !graphMonochrome) || highlightHighValues {
                Divider()
                MenuBarUsageBarSettings(strings: strings, showsColors: styles.usesBars && !graphMonochrome)
            }
            // The theme also colors the panel's graphs, so it stays even when
            // the menu bar draws its own in monochrome.
            Divider()
            MenuBarGraphThemeSettings(strings: FeatureStrings.menuBarGraphTheme(l10n.language))
        }
    }

    /// How the readings share the menu bar with the icon and with each other.
    private var behaviorCard: some View {
        SettingsCard(title: strings.behaviorTitle) {
            if styles.combineApplies {
                SettingsRow(symbol: "thermometer.medium", title: l10n.s.monitorCombineTemperatures,
                            caption: l10n.s.monitorCombineTemperaturesCaption) {
                    Toggle(l10n.s.monitorCombineTemperatures, isOn: $combineTemperatures).labelsHidden()
                }
            }
            SettingsRow(symbol: "eye.slash", title: l10n.s.menuBarHideIconToggle,
                        caption: l10n.s.menuBarHideIconCaption) {
                Toggle(l10n.s.menuBarHideIconToggle, isOn: $hideIconWithMetrics).labelsHidden()
            }
            SettingsRow(symbol: "rectangle.split.3x1", title: l10n.s.monitorSeparateMenuBarMetrics,
                        caption: l10n.s.monitorSeparateMenuBarMetricsCaption) {
                Toggle(l10n.s.monitorSeparateMenuBarMetrics, isOn: $separateMetrics).labelsHidden()
            }
        }
    }
}

/// Which kinds of style the pinned readings use, so options that apply only
/// to graphs or bars show only when something draws one.
@MainActor
private final class MenuBarStyleState: ObservableObject {
    @Published private(set) var usesGraphs = false
    @Published private(set) var usesBars = false
    /// A usage ring, history or core graph is pinned (they can draw a value).
    @Published private(set) var usesValueGraphs = false
    /// Combining applies only while CPU or GPU usage is text, or to a
    /// built-in battery.
    @Published private(set) var combineApplies = true
    /// Read from deinit, which is not on the main actor.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func reload() {
        let defaults = UserDefaults.standard
        let styles = MenuBarMetric.enabled(in: defaults).map { MenuBarMetricAppearance.stored(for: $0, in: defaults) }
        let graphs = styles.contains { !$0.isText }
        let bars = styles.contains(.bars)
        if graphs != usesGraphs { usesGraphs = graphs }
        if bars != usesBars { usesBars = bars }
        let valueGraphs = MenuBarMetric.enabled(in: defaults).contains {
            $0 != .network && [.pie, .sparkline, .histogram].contains(MenuBarMetricAppearance.stored(for: $0, in: defaults))
        }
        if valueGraphs != usesValueGraphs { usesValueGraphs = valueGraphs }
        let combine = MenuBarMetricAppearance.combineApplies(in: defaults, hasBattery: PowerSampler.hasInternalBattery)
        if combine != combineApplies { combineApplies = combine }
    }
}

/// The style picker at the end of a metric's row: only the styles the
/// metric offers, text styles first, then the graphs.
private struct MenuBarMetricStylePicker: View {
    @ObservedObject private var l10n = L10n.shared
    let metric: MenuBarMetric
    @AppStorage private var stored: String
    /// A hidden reading keeps its style, dimmed until it is shown again.
    @AppStorage private var shown: Bool
    /// What decides whether a temperature rides in its usage block.
    @AppStorage(DefaultsKey.menuBarCombineTemperatures) private var combine = true
    @AppStorage(DefaultsKey.menuBarCPU) private var cpuShown = true
    @AppStorage(DefaultsKey.menuBarGPU) private var gpuShown = true
    @AppStorage(DefaultsKey.menuBarBattery) private var batteryShown = false
    @AppStorage(MenuBarMetric.cpu.styleKey) private var cpuStyle = "values"
    @AppStorage(MenuBarMetric.gpu.styleKey) private var gpuStyle = "values"

    /// The temperature is drawn inside its usage block, so its own style
    /// does not apply right now.
    private var drawnWithUsage: Bool {
        _ = (combine, cpuShown, gpuShown, batteryShown, cpuStyle, gpuStyle, shown)
        return MenuBarMetricAppearance.drawnWithUsage(metric)
    }

    init(metric: MenuBarMetric) {
        self.metric = metric
        _stored = AppStorage(wrappedValue: MenuBarMetricAppearance.defaultStyle(for: metric).rawValue,
                             metric.styleKey)
        _shown = AppStorage(wrappedValue: false, metric.defaultsKey)
    }

    private var strings: MenuBarAppearanceStrings { FeatureStrings.menuBarAppearance(l10n.language) }

    private var current: MenuBarMetricAppearance {
        let defaults = UserDefaults.standard
        _ = stored
        return MenuBarMetricAppearance.stored(for: metric, in: defaults)
    }

    var body: some View {
        let options = MenuBarMetricAppearance.allowed(for: metric)
        let textStyles = options.filter(\.isText)
        let graphStyles = options.filter { !$0.isText }
        // A Menu of buttons rather than a Picker: inside the reorderable list
        // native controls may lose the click to the row's drag handling,
        // while buttons do not (see MetricRowOptionToggle).
        Menu {
            ForEach(textStyles, id: \.self) { style in
                choice(style)
            }
            if !graphStyles.isEmpty {
                Divider()
                ForEach(graphStyles, id: \.self) { style in
                    choice(style)
                }
            }
        } label: {
            Text(title(current))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .disabled(!shown || drawnWithUsage)
        .help(drawnWithUsage ? strings.combinedWithUsage : strings.styleMenuHelp)
        .accessibilityLabel(strings.styleMenuHelp)
        .accessibilityValue(title(current))
    }

    private func choice(_ style: MenuBarMetricAppearance) -> some View {
        Button {
            stored = style.rawValue
        } label: {
            if style == current {
                Label(title(style), systemImage: "checkmark")
            } else {
                Text(title(style))
            }
        }
    }

    private func title(_ style: MenuBarMetricAppearance) -> String {
        let dual = MenuBarMetricAppearance.isDual(metric)
        switch style {
        case .values, .classic: return dual ? strings.styleTwoLinesNamed : strings.styleLabelAbove
        case .inline: return strings.styleInline
        case .valueOnly: return dual ? strings.styleTwoLines : strings.styleValueOnly
        case .iconValue: return strings.styleIconValue
        case .bars: return strings.bars
        case .pie: return strings.pie
        case .sparkline: return strings.sparkline
        case .histogram: return strings.histogram
        }
    }
}

private struct MenuBarUsageBarSettings: View {
    let strings: MenuBarAppearanceStrings
    /// The colors apply only to bars drawn in color; highlighted values use
    /// the system's orange and red, so then only the limits show.
    var showsColors = true

    @AppStorage(DefaultsKey.menuBarUsageBarNormalColor) private var normalColor = MenuBarUsageBarSupport.defaultNormalColor
    @AppStorage(DefaultsKey.menuBarUsageBarElevatedColor) private var elevatedColor = MenuBarUsageBarSupport.defaultElevatedColor
    @AppStorage(DefaultsKey.menuBarUsageBarCriticalColor) private var criticalColor = MenuBarUsageBarSupport.defaultCriticalColor
    @AppStorage(DefaultsKey.menuBarUsageBarMediumThreshold) private var mediumThreshold = MenuBarUsageBarSupport.defaultMediumThreshold
    @AppStorage(DefaultsKey.menuBarUsageBarHighThreshold) private var highThreshold = MenuBarUsageBarSupport.defaultHighThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsColors {
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
            }

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

                        MenuBarMetricStylePicker(metric: metric)
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
        order.filter { $0.feature.isAvailable && $0.isAvailableOnCurrentHardware }
    }
}

// The memory pressure-dot option lives under the Memory row, matching the
// Network row's inline option.
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
    @AppStorage(MenuBarMetric.memory.styleKey) private var style = "values"

    /// The dot is drawn beside a value or a bar, not with a symbol or a graph.
    private var dotApplies: Bool {
        _ = style
        return [.values, .inline, .valueOnly, .bars].contains(MenuBarMetricAppearance.stored(for: .memory))
    }

    var body: some View {
        if menuBarMemory && dotApplies {
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
    @AppStorage(MenuBarMetric.network.styleKey) private var style = "values"

    /// The graph draws upload and download in fixed places.
    private var orderApplies: Bool {
        _ = style
        return MenuBarMetricAppearance.stored(for: .network) != .sparkline
    }

    var body: some View {
        if menuBarNetwork && orderApplies {
            MetricRowOptionToggle(label: l10n.s.monitorNetworkUploadFirst, isOn: $uploadFirst)
        }
    }
}

private struct MenuBarMetricVisibilityToggle: View {
    @ObservedObject private var l10n = L10n.shared
    let metric: MenuBarMetric
    @AppStorage private var shown: Bool

    private var strings: MenuBarAppearanceStrings { FeatureStrings.menuBarAppearance(l10n.language) }

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
        .help(shown ? strings.hideFromMenuBar : strings.showInMenuBar)
        // The metric is the label and its visibility the value; the action
        // the click takes is the hint.
        .accessibilityRepresentation {
            Toggle(metric.title(l10n.s), isOn: $shown)
        }
        .accessibilityHint(shown ? strings.hideFromMenuBar : strings.showInMenuBar)
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
