// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// Floating panels expand below the menu bar on notchless displays;
/// compact activities and the companion stay in the bar. Coordinates are
/// in screen points, y up, as AppKit's.
///
/// The island is a capsule drawn `margin` inside its window, above and below
/// its body, so the window starts that much above the island's visible top.
/// Pure arithmetic, shared by the island's geometry and the unit tests.
enum NotchFloatingLayout {
    /// Air between the bottom of the menu bar and the island's top edge.
    static let menuBarGap: CGFloat = 6

    /// How far the island's window hangs below the top of the display: the
    /// bar and the gap, less the margin the capsule keeps inside its window.
    static func drop(barHeight: CGFloat, margin: CGFloat, expanded: Bool = true) -> CGFloat {
        guard expanded else { return 0 }
        let bar = barHeight.isFinite ? max(0, barHeight) : 0
        let inset = margin.isFinite ? max(0, margin) : 0
        return max(0, bar + menuBarGap - inset)
    }

    /// The bottom of the menu bar.
    static func menuBarBottom(screen: CGRect, barHeight: CGFloat) -> CGFloat {
        screen.maxY - (barHeight.isFinite ? max(0, barHeight) : 0)
    }

    /// The visible top edge of the open island. Compact activities stay in
    /// the bar and do not use it.
    static func islandTop(screen: CGRect, barHeight: CGFloat) -> CGFloat {
        menuBarBottom(screen: screen, barHeight: barHeight) - menuBarGap
    }

    /// The window of an island of `size`, centred on the display.
    static func windowFrame(screen: CGRect, barHeight: CGFloat, margin: CGFloat, size: CGSize,
                            expanded: Bool = true) -> CGRect {
        let width = max(0, size.width), height = max(0, size.height)
        return CGRect(x: screen.midX - width / 2,
                      y: screen.maxY - drop(barHeight: barHeight, margin: margin, expanded: expanded) - height,
                      width: width, height: height)
    }

    /// The capsule's body inside that window: the window less its margin
    /// above and below.
    static func visibleFrame(screen: CGRect, barHeight: CGFloat, margin: CGFloat, size: CGSize,
                             expanded: Bool = true) -> CGRect {
        let window = windowFrame(screen: screen, barHeight: barHeight, margin: margin, size: size,
                                 expanded: expanded)
        let inset = min(margin.isFinite ? max(0, margin) : 0, window.height / 2)
        return window.insetBy(dx: 0, dy: inset)
    }

    /// The invisible strip that opens an island with nothing to show: from
    /// the bottom of the menu bar down through the gap and the pill's own
    /// height, as wide as the pill, centred. It never reaches into the bar.
    static func hoverStrip(screen: CGRect, barHeight: CGFloat, width: CGFloat, height: CGFloat,
                           expanded: Bool = true) -> CGRect {
        let width = width.isFinite ? max(0, width) : 0
        let body = height.isFinite ? max(0, height) : 0
        let bar = barHeight.isFinite ? max(0, barHeight) : 0
        let height = expanded ? body + menuBarGap : min(body, bar)
        let top = expanded ? menuBarBottom(screen: screen, barHeight: bar) : screen.maxY
        return CGRect(x: screen.midX - width / 2, y: top - height,
                      width: width, height: height)
    }
}
