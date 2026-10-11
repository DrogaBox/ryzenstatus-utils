// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Steps small looping decorations, the music bars and an agent's pulse, a
/// limited number of times a second.
final class NotchDecorativeClock {
    static let rate: Float = 30

    private let step: (CFTimeInterval) -> Void
    private var link: CADisplayLink?

    init(step: @escaping (CFTimeInterval) -> Void) {
        self.step = step
    }

    var isRunning: Bool { link != nil }
    var displayLink: CADisplayLink? { link }

    func start(in view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: Target(clock: self), selector: #selector(Target.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Self.rate / 2, maximum: Self.rate,
                                                        preferred: Self.rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit { link?.invalidate() }

    private final class Target: NSObject {
        weak var clock: NotchDecorativeClock?
        init(clock: NotchDecorativeClock) { self.clock = clock }
        @objc func fire(_ link: CADisplayLink) { clock?.step(link.targetTimestamp) }
    }

    static func swing(_ phase: Double) -> Double {
        let half = phase.truncatingRemainder(dividingBy: 2)
        let travelled = half < 0 ? half + 2 : half
        let out = travelled <= 1 ? travelled : 2 - travelled
        return (1 - cos(.pi * out)) / 2
    }

    static func pulse(_ elapsed: Double, period: Double) -> Double {
        guard period > 0 else { return 0 }
        let cycle = elapsed.truncatingRemainder(dividingBy: period)
        let progress = (cycle < 0 ? cycle + period : cycle) / period
        return sin(.pi / 2 * progress)
    }
}
