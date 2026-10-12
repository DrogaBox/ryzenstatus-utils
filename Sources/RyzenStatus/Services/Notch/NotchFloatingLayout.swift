// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The floating style's place on a display without a camera: below the
/// menu bar, never over it. Screen coordinates, y up, as AppKit's.
///
/// The island is a capsule drawn `margin` inside its window, above and below
/// its body, so the window starts that much above the island's visible top.
/// Pure arithmetic, shared by the island's geometry and the unit tests.
enum NotchFloatingLayout {
    /// Air between the bottom of the menu bar and the island's top edge.
    static let menuBarGap: CGFloat = 6

    /// How far the island's window hangs below the top of the display: the
    /// bar and the gap, less the margin the capsule keeps inside its window.
    static func drop(barHeight: CGFloat, margin: CGFloat) -> CGFloat {
        let bar = barHeight.isFinite ? max(0, barHeight) : 0
        let inset = margin.isFinite ? max(0, margin) : 0
        return max(0, bar + menuBarGap - inset)
    }

    /// The bottom of the menu bar.
    static func menuBarBottom(screen: CGRect, barHeight: CGFloat) -> CGFloat {
        screen.maxY - (barHeight.isFinite ? max(0, barHeight) : 0)
    }

    /// The visible top edge of the island, compact or open.
    static func islandTop(screen: CGRect, barHeight: CGFloat) -> CGFloat {
        menuBarBottom(screen: screen, barHeight: barHeight) - menuBarGap
    }

    /// The window of an island of `size`, centred on the display.
    static func windowFrame(screen: CGRect, barHeight: CGFloat, margin: CGFloat, size: CGSize) -> CGRect {
        let width = max(0, size.width), height = max(0, size.height)
        return CGRect(x: screen.midX - width / 2,
                      y: screen.maxY - drop(barHeight: barHeight, margin: margin) - height,
                      width: width, height: height)
    }

    /// The capsule's body inside that window: the window less its margin
    /// above and below.
    static func visibleFrame(screen: CGRect, barHeight: CGFloat, margin: CGFloat, size: CGSize) -> CGRect {
        let window = windowFrame(screen: screen, barHeight: barHeight, margin: margin, size: size)
        let inset = min(margin.isFinite ? max(0, margin) : 0, window.height / 2)
        return window.insetBy(dx: 0, dy: inset)
    }

    /// The invisible strip that opens an island with nothing to show: from
    /// the bottom of the menu bar down through the gap and the pill's own
    /// height, as wide as the pill, centred. It never reaches into the bar.
    static func hoverStrip(screen: CGRect, barHeight: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let width = max(0, width), height = max(0, height) + menuBarGap
        return CGRect(x: screen.midX - width / 2, y: menuBarBottom(screen: screen, barHeight: barHeight) - height,
                      width: width, height: height)
    }
}
