// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The theme color a graph layer is drawn in. The panel, the island and the
/// dashboard use the same graph theme as the menu bar, picked for the light
/// or dark appearance they are shown in.
enum GraphInk: Equatable {
    case primary, secondary, tertiary
    case fixed(Color)
}

/// Sizing and scaling of the column graphs outside the menu bar: two-point
/// columns one point apart, newest on the right, the oldest sliding off the
/// left edge. Kept apart from the views so it can be tested.
enum ColumnGraphGeometry {
    static let columnWidth: CGFloat = 2
    static let spacing: CGFloat = 1
    /// Traffic is compressed so a small transfer keeps some height next to a
    /// burst instead of disappearing under one point.
    static let trafficExponent = 0.75
    /// Network and disk scales never drop below 1 KB/s, so idle noise does
    /// not fill the graph.
    static let trafficFloor = 1024.0

    /// How many columns fit across `width`.
    static func visibleCount(width: CGFloat,
                             columnWidth: CGFloat = columnWidth,
                             spacing: CGFloat = spacing) -> Int {
        guard width.isFinite, columnWidth > 0, width >= columnWidth else { return 0 }
        return Int(((width + spacing) / (columnWidth + spacing)).rounded(.down))
    }

    /// A column's height for `fraction` of the plot: nothing for zero or an
    /// invalid reading, at least one point for any activity.
    static func columnHeight(fraction: Double, plotHeight: CGFloat) -> CGFloat {
        MenuBarGraphGeometry.columnHeight(fraction: fraction, plotHeight: plotHeight)
    }

    /// `values` as fractions of `ceiling`, clamped to 0...1. Invalid readings
    /// and a missing ceiling give 0, which draws no column.
    static func fractions(_ values: [Double], ceiling: Double) -> [Double] {
        guard ceiling.isFinite, ceiling > 0 else { return values.map { _ in 0 } }
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            return min(1, value / ceiling)
        }
    }

    /// One direction of network or disk traffic over the columns that are
    /// visible: scaled to its own busiest visible sample (never below the
    /// floor) and compressed. Returns the scale too, for its label.
    static func trafficFractions(_ values: [Double],
                                 visible: Int,
                                 floor: Double = trafficFloor) -> (fractions: [Double], peak: Double) {
        let window = Array(values.suffix(max(0, visible)))
        let peak = max(floor, window.filter(\.isFinite).max() ?? 0)
        let fractions = window.map { value -> Double in
            guard value.isFinite, value > 0 else { return 0 }
            return min(1, pow(value / peak, trafficExponent))
        }
        return (fractions, peak)
    }

    /// A steady top for readings without a natural ceiling, such as watts:
    /// the busiest sample rounded up to the next `step`, never below
    /// `minimum`. The scale only moves when the peak crosses a step.
    static func roundedCeiling(peak: Double, step: Double, minimum: Double) -> Double {
        guard peak.isFinite, peak > 0, step > 0 else { return minimum }
        return max(minimum, (peak / step).rounded(.up) * step)
    }

    /// The x of the newest column's left edge. Pinned to a whole point so the
    /// columns stay sharp whatever the view's width.
    static func newestColumnX(in rect: CGRect, columnWidth: CGFloat = columnWidth) -> CGFloat {
        rect.minX + max(0, (rect.width - columnWidth).rounded(.down))
    }
}

/// The theme's three graph colors for one appearance.
struct GraphThemeColors {
    let primary: Color
    let secondary: Color
    let tertiary: Color

    init(theme: MenuBarGraphTheme, dark: Bool) {
        let tone: Double = dark ? 1 : 0
        let colors = MenuBarGraphPalette.colors(
            for: theme,
            accent: MenuBarGraphPainter.accentRGB(),
            mono: MenuBarUsageBarSupport.RGB(red: tone, green: tone, blue: tone))
        primary = Self.color(colors.primary)
        secondary = Self.color(colors.secondary)
        tertiary = Self.color(colors.tertiary)
    }

    func color(_ ink: GraphInk) -> Color {
        switch ink {
        case .primary: return primary
        case .secondary: return secondary
        case .tertiary: return tertiary
        case .fixed(let color): return color
        }
    }

    private static func color(_ rgb: MenuBarUsageBarSupport.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Reads the graph theme for the appearance a view is shown in, and redraws
/// the view when either theme changes in Settings. Legends use it too, so
/// their dots match the columns.
struct GraphThemeReader<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.menuBarGraphThemeLight) private var lightTheme = MenuBarGraphTheme.system.rawValue
    @AppStorage(DefaultsKey.menuBarGraphThemeDark) private var darkTheme = MenuBarGraphTheme.system.rawValue
    let content: (GraphThemeColors) -> Content

    init(@ViewBuilder content: @escaping (GraphThemeColors) -> Content) {
        self.content = content
    }

    var body: some View {
        let dark = colorScheme == .dark
        let theme = MenuBarGraphTheme(rawValue: dark ? darkTheme : lightTheme) ?? .system
        content(GraphThemeColors(theme: theme, dark: dark))
    }
}

/// A history drawn as filled columns, newest on the right. Each layer is a
/// series of fractions (0...1) and layers are drawn back to front, so a
/// stacked reading passes its running totals: CPU passes the total, then
/// user time on top of it, leaving system time showing in the layer behind.
struct ColumnHistoryGraph: View {
    var layers: [[Double]]
    var inks: [GraphInk]
    var columnWidth: CGFloat = ColumnGraphGeometry.columnWidth
    var spacing: CGFloat = ColumnGraphGeometry.spacing
    /// A faint line along the bottom, so an idle graph still reads as a graph.
    var showsBaseline = true
    /// Fractions of the height that get a faint guide line, for larger graphs
    /// that carry a scale.
    var gridFractions: [Double] = []

    var body: some View {
        GraphThemeReader { colors in
            let fills = inks.map(colors.color)
            Canvas { context, size in
                let plot = CGRect(origin: .zero, size: size)
                for fraction in gridFractions where fraction.isFinite && fraction > 0 && fraction <= 1 {
                    let y = (plot.maxY - plot.height * CGFloat(fraction)).rounded(.down)
                    context.fill(Path(CGRect(x: 0, y: y, width: plot.width, height: 0.5)),
                                 with: .color(.secondary.opacity(0.15)))
                }
                if showsBaseline {
                    context.fill(Path(CGRect(x: 0, y: plot.maxY - 0.5, width: plot.width, height: 0.5)),
                                 with: .color(.secondary.opacity(0.25)))
                }
                for (layer, fill) in zip(layers, fills) {
                    let path = Self.columns(layer, in: plot, columnWidth: columnWidth, spacing: spacing,
                                            anchor: .bottom)
                    context.fill(path, with: .color(fill))
                }
            }
        }
        .accessibilityHidden(true)
    }

    enum Anchor { case bottom, top }

    /// Columns for `fractions`, newest at the right edge, growing up from the
    /// bottom of `rect` or hanging down from its top.
    static func columns(_ fractions: [Double],
                        in rect: CGRect,
                        columnWidth: CGFloat,
                        spacing: CGFloat,
                        anchor: Anchor) -> Path {
        var path = Path()
        let count = min(fractions.count,
                        ColumnGraphGeometry.visibleCount(width: rect.width, columnWidth: columnWidth, spacing: spacing))
        guard count > 0 else { return path }
        var x = ColumnGraphGeometry.newestColumnX(in: rect, columnWidth: columnWidth)
        for fraction in fractions.suffix(count).reversed() {
            let height = ColumnGraphGeometry.columnHeight(fraction: fraction, plotHeight: rect.height)
            if height > 0 {
                let y = anchor == .bottom ? rect.maxY - height : rect.minY
                path.addRect(CGRect(x: x, y: y, width: columnWidth, height: height))
            }
            x -= columnWidth + spacing
        }
        return path
    }
}

/// Two directions of traffic (network upload and download, disk write and
/// read) in one graph, laid out like the menu bar network graph. Each side
/// is scaled to its own busiest visible sample and compressed, so a quiet
/// direction still shows next to a busy one.
struct DualColumnHistoryGraph: View {
    var upper: [Double]
    var lower: [Double]
    var upperInk: GraphInk = .secondary
    var lowerInk: GraphInk = .primary
    var columnWidth: CGFloat = ColumnGraphGeometry.columnWidth
    var spacing: CGFloat = ColumnGraphGeometry.spacing
    @AppStorage(DefaultsKey.menuBarNetworkGraphLayout) private var layoutRaw = MenuBarNetworkGraphLayout.mirrored.rawValue

    var body: some View {
        GraphThemeReader { colors in
            let upperFill = colors.color(upperInk)
            let lowerFill = colors.color(lowerInk)
            let layout = MenuBarNetworkGraphLayout(rawValue: layoutRaw) ?? .mirrored
            Canvas { context, size in
                let visible = ColumnGraphGeometry.visibleCount(width: size.width, columnWidth: columnWidth, spacing: spacing)
                let ups = ColumnGraphGeometry.trafficFractions(upper, visible: visible).fractions
                let downs = ColumnGraphGeometry.trafficFractions(lower, visible: visible).fractions
                // One point between the halves keeps the two directions apart.
                let half = max(0, (size.height - 1) / 2)
                let top = CGRect(x: 0, y: 0, width: size.width, height: half)
                let bottom = CGRect(x: 0, y: size.height - half, width: size.width, height: half)
                let middle = CGRect(x: 0, y: half, width: size.width, height: max(0, size.height - half * 2))
                context.fill(Path(middle), with: .color(.secondary.opacity(0.25)))

                let upperAnchor: ColumnHistoryGraph.Anchor
                let lowerAnchor: ColumnHistoryGraph.Anchor
                switch layout {
                case .mirrored: (upperAnchor, lowerAnchor) = (.bottom, .top)
                case .split: (upperAnchor, lowerAnchor) = (.top, .bottom)
                case .rising: (upperAnchor, lowerAnchor) = (.bottom, .bottom)
                }
                context.fill(ColumnHistoryGraph.columns(ups, in: top, columnWidth: columnWidth,
                                                        spacing: spacing, anchor: upperAnchor),
                             with: .color(upperFill))
                context.fill(ColumnHistoryGraph.columns(downs, in: bottom, columnWidth: columnWidth,
                                                        spacing: spacing, anchor: lowerAnchor),
                             with: .color(lowerFill))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A ring gauge in the menu bar ring's style: values stack from twelve
/// o'clock, clockwise, back to front, over a faint track.
struct GraphRing: View {
    var values: [Double]
    var inks: [GraphInk]
    var lineWidth: CGFloat = 4

    var body: some View {
        GraphThemeReader { colors in
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
                ForEach(Array(zip(values, inks).enumerated()), id: \.offset) { _, entry in
                    let value = entry.0.isFinite ? min(1, max(0, entry.0)) : 0
                    Circle()
                        .trim(from: 0, to: CGFloat(value))
                        .stroke(colors.color(entry.1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(lineWidth / 2)
        }
        .accessibilityHidden(true)
    }
}

/// One bar per core, stacked back to front like `ColumnHistoryGraph`
/// layers (CPU passes total load, then user load). Bars share the width
/// with one point between them.
struct CoreBarsGraph: View {
    var layers: [[Double]]
    var inks: [GraphInk]
    var spacing: CGFloat = 1

    var body: some View {
        GraphThemeReader { colors in
            let fills = inks.map(colors.color)
            Canvas { context, size in
                let count = layers.map(\.count).max() ?? 0
                guard count > 0 else { return }
                let width = max(1, ((size.width + spacing) / CGFloat(count) - spacing).rounded(.down))
                let used = CGFloat(count) * (width + spacing) - spacing
                let left = ((size.width - used) / 2).rounded(.down)
                for index in 0..<count {
                    let x = left + CGFloat(index) * (width + spacing)
                    context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                                 with: .color(.primary.opacity(0.08)))
                }
                for (layer, fill) in zip(layers, fills) {
                    var path = Path()
                    for (index, fraction) in layer.enumerated() {
                        let height = ColumnGraphGeometry.columnHeight(fraction: fraction, plotHeight: size.height)
                        guard height > 0 else { continue }
                        let x = left + CGFloat(index) * (width + spacing)
                        path.addRect(CGRect(x: x, y: size.height - height, width: width, height: height))
                    }
                    context.fill(path, with: .color(fill))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
