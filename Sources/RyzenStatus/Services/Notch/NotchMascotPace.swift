// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import QuartzCore

/// The companion's endless loops: breathing, flickers, bobs, sprite frames.
/// Left alone, Core Animation runs them at the display's full rate, 144 Hz on
/// a fast monitor, and the window server composites the island again every
/// one of those frames for motion of a point or two. Thirty frames a second,
/// what its walk already uses, looks the same and costs a fraction.
///
/// Not every loop can take it. A cycle shorter than about 0.3 s gets only a
/// few frames a turn and goes uneven, and a fast spin steps far enough per
/// frame to seem to turn the other way. Those pass `paced: false`.
enum NotchMascotPace {
    static let loop = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
}

extension CAAnimation {
    /// Repeats for ever, at the companion's loop pace unless `paced` is false,
    /// which leaves the display's own rate.
    func loopsForever(paced: Bool = true) {
        repeatCount = .infinity
        guard paced else { return }
        preferredFrameRateRange = NotchMascotPace.loop
        // A group's own animations ask for their rate too.
        (self as? CAAnimationGroup)?.animations?.forEach { $0.preferredFrameRateRange = NotchMascotPace.loop }
    }
}
