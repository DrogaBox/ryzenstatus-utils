// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

final class NotchBackdropPresentation: ObservableObject {
    @Published var contour = Path()
    @Published var usesGlass = false
    /// The camera strip's height in points, which the translucent background
    /// keeps black at every island height.
    @Published var stripHeight: CGFloat = 0
    @Published private(set) var fade = NotchGlassFade.open
    /// The menu bar a floating capsule leaves below itself, part of the
    /// surface height a fade is planned in.
    var floatingGap: CGFloat = 0

    /// Measured from the top edge, as the fade is planned: a floating
    /// capsule's contour starts below it and ends above the surface's bottom.
    var openness: Double { Double(fade.openness(atHeight: contourBottom + floatingGap)) }
    var contourBottom: CGFloat { contour.boundingRect.isNull ? 0 : contour.boundingRect.maxY }

    /// How much of the resting black still lies beneath the glass. It lets go
    /// as the glass opens and is gone once the glass is fully open, so an
    /// opening never settles over a black that then vanishes at once.
    var restingBlack: Double { 1 - openness }

    /// Plans a resize from `start` to `end` from what is on screen now.
    func planFade(from start: CGFloat, to end: CGFloat, endsInGlass: Bool) {
        setFade(.plan(from: start, to: end, endsInGlass: endsInGlass,
                      current: usesGlass ? fade.openness(atHeight: start) : 0))
    }

    func openFully() { setFade(.open) }

    /// The fade follows the moving contour frame by frame; SwiftUI must not
    /// add an animation of its own on top.
    private func setFade(_ next: NotchGlassFade) {
        guard fade != next else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fade = next }
    }
}

struct NotchBackdropShape: Shape {
    var contour: Path
    func path(in rect: CGRect) -> Path { contour }
}
