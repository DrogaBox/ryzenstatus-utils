// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Where a cover sits on the island: its centre's offset from the display's
/// centre, its centre's depth below the island's top, its side and its corner
/// radius. Kept apart from the window's frame, which changes around it.
struct NotchCoverSpot: Equatable {
    var offset: CGFloat
    var top: CGFloat
    var side: CGFloat
    var radius: CGFloat
}

/// Opening onto the music page, the closed strip's cover flies into the
/// page's artwork instead of fading out on one side as another fades in on
/// the other, so the eye follows the song into the island.
enum NotchCoverFlight {
    /// A quick spring that settles with a little give, as a cover lifted out
    /// of the strip lands in the page.
    static let response: CGFloat = 0.42
    static let dampingRatio: CGFloat = 0.72
    /// The page's own artwork takes over from the flying copy over this long.
    static let handOver: CFTimeInterval = 0.14
    /// A paused page draws its artwork a little smaller.
    static let pausedScale: CGFloat = 0.94

    /// The spring for Core Animation, from the response and damping ratio
    /// SwiftUI uses, with a mass of one.
    static func spring(response: CGFloat = response, dampingRatio: CGFloat = dampingRatio)
        -> (stiffness: CGFloat, damping: CGFloat) {
        let stiffness = pow(2 * .pi / response, 2)
        let damping = 4 * .pi * dampingRatio / response
        return (stiffness, damping)
    }

    /// Only a cover that really travels flies; a few points would only flicker.
    static func flies(from: NotchCoverSpot, to: NotchCoverSpot) -> Bool {
        guard [from.offset, from.top, from.side, to.offset, to.top, to.side].allSatisfy(\.isFinite),
              from.side > 0, to.side > 0 else { return false }
        return hypot(to.offset - from.offset, to.top - from.top) > 8 || abs(to.side - from.side) > 8
    }

    /// The page artwork's corner, as `NotchArtwork` draws it.
    static func pageRadius(side: CGFloat) -> CGFloat { side * 0.19 }
}

/// Whether a cover is on its way, which keeps the page's own artwork out of
/// sight until the flying copy lands on it.
final class NotchCoverFlightState: ObservableObject {
    static let shared = NotchCoverFlightState()
    @Published var inFlight = false
    private init() {}
}

/// A clear view behind a cover, through which the island reads where the
/// cover is on screen at the moment it needs to.
struct NotchCoverProbe: NSViewRepresentable {
    enum Role { case strip, page }
    let role: Role

    func makeNSView(context: Context) -> NotchCoverProbeView {
        let view = NotchCoverProbeView()
        NotchService.shared.registerCoverProbe(view, role: role)
        return view
    }

    func updateNSView(_ view: NotchCoverProbeView, context: Context) {
        NotchService.shared.registerCoverProbe(view, role: role)
    }
}

final class NotchCoverProbeView: NSView {
    /// The cover's frame on screen, while it is in a window.
    var screenFrame: CGRect? {
        guard let window, !isHiddenOrHasHiddenAncestor, bounds.width > 0, bounds.height > 0 else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
