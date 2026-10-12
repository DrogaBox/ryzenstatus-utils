// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// Geometry shared by the menu bar graphs, free of drawing so tests can pin it.
enum MenuBarGraphGeometry {
    static let boxCornerRadius: CGFloat = 3
    static let plotInset: CGFloat = 2
    static let ringLineWidth: CGFloat = 3
    /// Below this the network graph stops zooming in, so an idle link reads
    /// as idle instead of magnifying a few stray packets to full height.
    static let networkScaleFloor: Double = 1024

    /// One sample per point of plot width, or one every other point when the
    /// columns are spaced out.
    static func historySampleCount(plotWidth: CGFloat, spaced: Bool) -> Int {
        let width = max(0, Int(plotWidth.rounded(.down)))
        return spaced ? (width + 1) / 2 : width
    }

    /// Zero draws nothing; any activity at all keeps at least one point, so a
    /// light but real load never looks identical to an idle one.
    static func columnHeight(fraction: Double, plotHeight: CGFloat) -> CGFloat {
        guard fraction.isFinite, fraction > 0, plotHeight > 0 else { return 0 }
        return max(1, plotHeight * CGFloat(min(1, fraction)))
    }

    /// The full-height value for one direction of the network graph: the
    /// busiest visible sample, never below `networkScaleFloor`.
    static func dualScale(_ samples: [Double]) -> Double {
        max(networkScaleFloor, samples.filter(\.isFinite).max() ?? 0)
    }

    /// Bars narrow as core counts grow so the box stays a sane width.
    static func coreBarWidth(coreCount: Int) -> CGFloat {
        if coreCount <= 7 { return 4 }
        if coreCount <= 15 { return 3 }
        return 2
    }

    /// A box that holds `coreCount` bars with one point between them.
    static func coreBoxWidth(coreCount: Int) -> CGFloat {
        let count = max(1, coreCount)
        return CGFloat(count) * (coreBarWidth(coreCount: count) + 1) - 1 + plotInset * 2
    }

    /// The user part of each CPU sample: the total minus its system share,
    /// aligned from the newest sample. A missing share (the system history
    /// can be shorter right after a reset) counts as user time.
    static func userShares(total: [Double], system: [Double]) -> [Double] {
        let offset = total.count - system.count
        return total.indices.map { index in
            let systemIndex = index - offset
            let systemShare = systemIndex >= 0 && systemIndex < system.count ? system[systemIndex] : 0
            return max(0, total[index] - (systemShare.isFinite ? systemShare : 0))
        }
    }

    /// One value per physical core, 0...1, read from `percent` (load by
    /// default). SMT siblings follow their physical core in the snapshot, so
    /// each run of logical threads folds into the physical core before it;
    /// two bars per core would double the box width for no extra insight.
    static func physicalCoreLoads(_ cores: [CoreSnapshot],
                                  percent: (CoreSnapshot) -> Float = { $0.loadPct }) -> [Double] {
        var groups: [[Double]] = []
        for core in cores {
            let load = min(1, max(0, Double(percent(core)) / 100))
            if core.isLogical, !groups.isEmpty {
                groups[groups.count - 1].append(load)
            } else {
                groups.append([load])
            }
        }
        return groups.map { $0.reduce(0, +) / Double($0.count) }
    }
}

/// Draws the menu bar graph boxes and their contents in the image's own
/// (unflipped) coordinates.
enum MenuBarGraphPainter {
    struct Style {
        let isDark: Bool
        /// The dark pill behind graphs on a light menu bar.
        let filledBox: Bool
        let colors: MenuBarGraphColors

        var primary: NSColor { color(colors.primary) }
        var secondary: NSColor { color(colors.secondary) }
        var tertiary: NSColor { color(colors.tertiary) }

        /// Numbers drawn over a plot follow the box, not the menu bar: on the
        /// pill they must be light even though the bar around it is light.
        var overlaysOnDarkSurface: Bool { isDark || filledBox }

        private func color(_ rgb: MenuBarUsageBarSupport.RGB) -> NSColor {
            NSColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1)
        }
    }

    /// Call from inside an image drawing handler: there the current drawing
    /// appearance is the status button's, which is what the menu bar shows
    /// over the wallpaper, rather than the app's own appearance.
    static func currentStyle(defaults: UserDefaults = .standard) -> Style {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let filled = !dark && MenuBarGraphLightBackground.current(defaults) == .filled
        let monoTone: Double = (dark || filled) ? 1 : 0
        let colors = MenuBarGraphPalette.colors(
            for: MenuBarGraphTheme.current(dark: dark, defaults: defaults),
            accent: accentRGB(),
            mono: MenuBarUsageBarSupport.RGB(red: monoTone, green: monoTone, blue: monoTone))
        return Style(isDark: dark, filledBox: filled, colors: colors)
    }

    /// Everything besides the samples that changes a graph's pixels, for
    /// image cache keys. The theme of both appearances is included because
    /// which one applies is only known at draw time.
    static func cacheToken(defaults: UserDefaults = .standard) -> String {
        let accent = accentRGB()
        return [
            MenuBarGraphTheme.current(dark: false, defaults: defaults).rawValue,
            MenuBarGraphTheme.current(dark: true, defaults: defaults).rawValue,
            MenuBarGraphLightBackground.current(defaults).rawValue,
            MenuBarUsageBarSupport.hex(red: accent.red, green: accent.green, blue: accent.blue),
        ].joined(separator: ",")
    }

    static func accentRGB() -> MenuBarUsageBarSupport.RGB {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
            return MenuBarGraphPalette.blue
        }
        return MenuBarUsageBarSupport.RGB(red: Double(accent.redComponent),
                                          green: Double(accent.greenComponent),
                                          blue: Double(accent.blueComponent))
    }

    // MARK: Box

    static func drawBox(_ box: NSRect, style: Style, circular: Bool = false) {
        let path = circular
            ? NSBezierPath(ovalIn: box)
            : NSBezierPath(roundedRect: box,
                           xRadius: MenuBarGraphGeometry.boxCornerRadius,
                           yRadius: MenuBarGraphGeometry.boxCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if style.filledBox {
            NSGradient(starting: NSColor(white: 0.10, alpha: 1),
                       ending: NSColor(white: 0.14, alpha: 1))?.draw(in: path, angle: 90)
        } else {
            // A 2 pt stroke clipped to its own path leaves a crisp 1 pt edge
            // fully inside the box, so neighbors never see a half pixel bleed.
            (style.isDark ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.7)).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func withPlotClip(_ box: NSRect, _ draw: (NSRect) -> Void) {
        let plot = box.insetBy(dx: MenuBarGraphGeometry.plotInset, dy: MenuBarGraphGeometry.plotInset)
        guard plot.width > 0, plot.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: plot, xRadius: 1, yRadius: 1).addClip()
        draw(plot)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Graphs

    /// One-point columns with the newest sample at the right edge. `series`
    /// holds cumulative fractions drawn in order, so each later and smaller
    /// layer paints over the one before it: [total, part] shows the part at
    /// the bottom in its own color and the rest of the total above it.
    static func drawHistory(series: [[Double]], colors: [NSColor], in box: NSRect, spaced: Bool) {
        withPlotClip(box) { plot in
            let count = MenuBarGraphGeometry.historySampleCount(plotWidth: plot.width, spaced: spaced)
            let step: CGFloat = spaced ? 2 : 1
            for (values, color) in zip(series, colors) {
                let path = NSBezierPath()
                var x = plot.maxX - 1
                for value in values.suffix(count).reversed() {
                    let height = MenuBarGraphGeometry.columnHeight(fraction: value, plotHeight: plot.height)
                    if height > 0 {
                        path.appendRect(NSRect(x: x, y: plot.minY, width: 1, height: height))
                    }
                    x -= step
                }
                color.setFill()
                path.fill()
            }
        }
    }

    /// Upload in the top half and download in the bottom half, with a one
    /// point seam between them. Both take fractions of their own half;
    /// `MenuBarGraphGeometry.dualScale` gives each direction its scale.
    static func drawDualHistory(upload: [Double],
                                download: [Double],
                                layout: MenuBarNetworkGraphLayout,
                                uploadColor: NSColor,
                                downloadColor: NSColor,
                                in box: NSRect,
                                spaced: Bool) {
        withPlotClip(box) { plot in
            let count = MenuBarGraphGeometry.historySampleCount(plotWidth: plot.width, spaced: spaced)
            let step: CGFloat = spaced ? 2 : 1
            let ups = Array(upload.suffix(count))
            let downs = Array(download.suffix(count))
            let half = (plot.height - 1) / 2
            let topHalfFloor = plot.maxY - half
            let bottomHalfCeiling = plot.minY + half
            let upPath = NSBezierPath()
            let downPath = NSBezierPath()
            var x = plot.maxX - 1
            for offset in 0..<count {
                let up = offset < ups.count ? ups[ups.count - 1 - offset] : 0
                let down = offset < downs.count ? downs[downs.count - 1 - offset] : 0
                let upHeight = MenuBarGraphGeometry.columnHeight(fraction: up, plotHeight: half)
                let downHeight = MenuBarGraphGeometry.columnHeight(fraction: down, plotHeight: half)
                if upHeight > 0 {
                    let y = layout == .split ? plot.maxY - upHeight : topHalfFloor
                    upPath.appendRect(NSRect(x: x, y: y, width: 1, height: upHeight))
                }
                if downHeight > 0 {
                    let y = layout == .mirrored ? bottomHalfCeiling - downHeight : plot.minY
                    downPath.appendRect(NSRect(x: x, y: y, width: 1, height: downHeight))
                }
                x -= step
            }
            uploadColor.setFill()
            upPath.fill()
            downloadColor.setFill()
            downPath.fill()
        }
    }

    /// One bar per core. Like `drawHistory`, `series` holds cumulative loads
    /// drawn in order, so [total, user] paints the user part over the total.
    static func drawCoreBars(series: [[Double]], colors: [NSColor], in box: NSRect) {
        let barWidth = MenuBarGraphGeometry.coreBarWidth(coreCount: series.first?.count ?? 0)
        withPlotClip(box) { plot in
            for (loads, color) in zip(series, colors) {
                let path = NSBezierPath()
                var x = plot.minX
                for load in loads {
                    let height = MenuBarGraphGeometry.columnHeight(fraction: load, plotHeight: plot.height)
                    if height > 0 {
                        path.appendRect(NSRect(x: x, y: plot.minY, width: barWidth, height: height))
                    }
                    x += barWidth + 1
                }
                color.setFill()
                path.fill()
            }
        }
    }

    /// Arcs clockwise from twelve o'clock. Like `drawHistory`, values are
    /// cumulative and drawn in order.
    static func drawRing(values: [Double], colors: [NSColor], in box: NSRect) {
        let lineWidth = MenuBarGraphGeometry.ringLineWidth
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = box.width / 2 - lineWidth / 2 - MenuBarGraphGeometry.plotInset
        guard radius > 0 else { return }
        for (value, color) in zip(values, colors) {
            guard value.isFinite, value > 0 else { continue }
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center,
                          radius: radius,
                          startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(min(1, value)),
                          clockwise: true)
            arc.lineWidth = lineWidth
            color.setStroke()
            arc.stroke()
        }
    }
}
