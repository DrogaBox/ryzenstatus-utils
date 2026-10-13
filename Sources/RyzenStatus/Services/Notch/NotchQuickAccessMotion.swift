// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Only the transition owns animation state. No timer or display link survives
/// the reveal, and a reversed transition cannot enable a departing button.
final class NotchQuickAccessMotion: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var interactive = false
    @Published private(set) var configuration = NotchQuickAccessConfiguration(side: .left, actions: [.explore])
    @Published private(set) var placements: [NotchQuickAccessPlacement] = []
    private var bodyFrame = CGRect.zero
    private var visible = false
    private var generation = 0

    func configure(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat, animated: Bool) {
        let values = NotchQuickAccessLayout.placements(configuration, body: body, headerTop: headerTop)
        guard self.configuration != configuration || placements != values else { return }
        let spring = NotchMotion.sideSpring(from: bodyFrame.size, to: body.size)
        let animation: Animation? = animated && visible ? .spring(duration: spring.duration, bounce: spring.bounce) : nil
        bodyFrame = body
        withAnimation(animation) {
            self.configuration = configuration
            placements = values
        }
    }

    var hoverRects: [CGRect] {
        NotchQuickAccessSide.allCases.compactMap { side in
            let values = placements.filter { $0.side == side }
            guard let first = values.first else { return nil }
            return NotchQuickAccessLayout.hoverRect(count: values.count, edge: first.edge, top: first.top, side: side)
        }
    }

    func setVisible(_ visible: Bool, animated: Bool, delay: TimeInterval = 0) {
        guard self.visible != visible else { return }
        self.visible = visible
        generation += 1
        let token = generation
        interactive = false
        let animation: Animation? = animated
            ? (visible ? .spring(duration: 0.38, bounce: 0.12).delay(delay) : .easeIn(duration: NotchQuickAccessLayout.withdrawalDuration))
            : nil
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            progress = visible ? 1 : 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.interactive = visible
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        interactive && placements.contains { value in
            let center = value.center(progress: 1)
            return hypot(point.x - center.x, point.y - center.y) <= NotchQuickAccessLayout.diameter / 2
        }
    }
}
