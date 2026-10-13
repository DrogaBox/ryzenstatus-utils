// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// Behind the open island, the top of the screen blurs and darkens, most at
/// the edge and fading out below the island, so what it shows reads over a
/// busy window without a hard band. It is a separate window that never takes
/// a click, ordered just beneath the island's own. Main thread only, as the
/// island's service is.
final class NotchBlurBackdrop {
    /// How far the blur reaches below the island before it has faded out.
    static let reach: CGFloat = 80

    private var window: NSPanel?
    private var effect: NSVisualEffectView?
    private var shown = false

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchProgressiveBlur)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// `islandBottom` is how far the open island reaches below the screen's top.
    func update(visible: Bool, screen: CGRect, islandBottom: CGFloat, above island: NSWindow?) {
        guard visible, let island, islandBottom > 0 else { hide(); return }
        let height = min(screen.height, islandBottom + Self.reach)
        let frame = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        let window = self.window ?? makeWindow()
        if window.level != island.level { window.level = island.level }
        if window.sharingType != island.sharingType { window.sharingType = island.sharingType }
        effect?.maskImage = Self.mask(fadingFrom: islandBottom / height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !shown {
            window.setFrame(frame, display: false)
            window.alphaValue = reduceMotion ? 1 : 0
            window.order(.below, relativeTo: island.windowNumber)
            shown = true
            guard !reduceMotion else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                window.animator().alphaValue = 1
            }
        } else {
            if window.frame != frame { window.setFrame(frame, display: true, animate: false) }
            window.order(.below, relativeTo: island.windowNumber)
        }
    }

    func hide() {
        guard shown, let window else { return }
        shown = false
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { window.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.shown else { return }
            window.orderOut(nil)
        })
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        // The island is black in either appearance; so is the shade behind it.
        panel.appearance = NSAppearance(named: .darkAqua)
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        panel.contentView = effect
        self.effect = effect
        window = panel
        return panel
    }

    /// Solid down to `solid` (a fraction of the height from the top), then
    /// fading to nothing at the bottom edge.
    private static func mask(fadingFrom solid: CGFloat) -> NSImage {
        let stop = min(0.95, max(0, solid))
        let image = NSImage(size: CGSize(width: 1, height: 64), flipped: false) { rect in
            // Drawn bottom to top: clear at the bottom, solid from the island up.
            let gradient = NSGradient(colorsAndLocations:
                (.clear, 0), (.black, 1 - stop), (.black, 1))
            gradient?.draw(in: rect, angle: 90)
            return true
        }
        image.resizingMode = .stretch
        return image
    }
}
