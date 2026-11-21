// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// While the island waits out of sight, a global monitor hears every mouse
/// move on every display. Nearly all of them are far from the island, where
/// the full hover path would change nothing, so a test against the island's
/// reach answers those: the union of up to four frames and the child
/// windows', then one containment check.
enum NotchHiddenHover {
    /// What the hover path is in the middle of. With any of it under way a
    /// move always goes through the full path.
    struct Pending: Equatable {
        var inside = false
        var emphasized = false
        var suppressed = false
        var capture = false
        var captureControls = false
        var hoverWork = false
        var exitWatch = false

        var any: Bool { inside || emphasized || suppressed || capture || captureControls || hoverWork || exitWatch }
    }

    /// Everything the hover path can count as the island: its hidden place,
    /// the strip under the bar, its window and any child window, with a few
    /// points to spare.
    static func reach(collapsed: CGRect, strip: CGRect?, window: CGRect?, children: [CGRect]) -> CGRect {
        var reach = collapsed
        if let strip { reach = reach.union(strip) }
        if let window { reach = reach.union(window) }
        for child in children { reach = reach.union(child) }
        return reach.insetBy(dx: -4, dy: -4)
    }

    /// Whether a move at `point` can skip the hover path.
    static func skips(_ point: CGPoint, reach: CGRect, pending: Pending) -> Bool {
        !pending.any && !reach.contains(point)
    }
}
