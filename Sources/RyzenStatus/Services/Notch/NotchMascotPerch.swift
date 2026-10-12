// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// Where the companion perches in the menu bar while a floating island is
/// open below it: the middle of the bar, where it rests in the closed
/// capsule, walking a little way after the pointer.
enum NotchMascotPerchLayout {
    /// The farthest it walks either way of the bar's middle.
    static let maximumReach: CGFloat = 72
    /// It walks only once the pointer is this far from where it stands, so
    /// small movements turn its eyes and not its feet.
    static let stride: CGFloat = 18

    /// Its window: wide enough for its props and hops, as tall as the bar,
    /// centred on `centerX` along the top of `screen`.
    static func frame(screen: CGRect, barHeight: CGFloat, centerX: CGFloat, size: CGFloat) -> CGRect {
        let width = (size * 2.4).rounded(.up)
        let height = max(barHeight, size + 4).rounded(.up)
        return CGRect(x: (centerX - width / 2).rounded(), y: screen.maxY - height, width: width, height: height)
    }

    /// How far it may walk: no farther than the free bar beside the closed
    /// capsule, measured as the island measures it.
    static func reach(cameraWidth: CGFloat, sideRoom: CGFloat?, windowWidth: CGFloat) -> CGFloat {
        let free = cameraWidth / 2 + max(0, sideRoom ?? 0) - windowWidth / 2
        return max(0, min(maximumReach, free.isFinite ? free : 0))
    }

    /// Where it walks for a pointer at `pointerX`: after it, within `reach`
    /// of `middle`, or nil while the pointer is less than a stride away.
    static func walkTarget(pointerX: CGFloat, standing: CGFloat, middle: CGFloat, reach: CGFloat) -> CGFloat? {
        guard pointerX.isFinite else { return nil }
        let target = min(middle + reach, max(middle - reach, pointerX)).rounded()
        return abs(target - standing) >= stride ? target : nil
    }
}

/// The companion in the menu bar while the floating island is open below
/// it. Its eyes follow the pointer over the island, it walks a little way
/// after it, a click gets a small hop and a new page a glance. Nothing runs
/// while the pointer rests: each move is one short animation, as in the
/// island, and it keeps its own blinks and dozes. It never takes a click.
final class NotchMascotPerch {
    /// Between two hops, so a run of clicks does not keep it bouncing.
    static let hopInterval: CFTimeInterval = 2
    /// Between two walks, so a sweeping pointer is followed, not chased.
    static let walkInterval: CFTimeInterval = 0.3

    private var panel: NSPanel?
    private var host: NotchMascotHostView?
    private var monitors: [Any] = []
    private var middle: CGFloat = 0
    private var reach: CGFloat = 0
    private var standing: CGFloat = 0
    private var size: CGFloat = 0
    private var lastHop: CFTimeInterval = -.infinity
    private var lastWalk: CFTimeInterval = -.infinity
    private var cueID = 0
    private var hideWork: DispatchWorkItem?

    var isShown: Bool { panel?.isVisible == true && hideWork == nil }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shows it over `geometry`'s bar, or keeps it there with a new look or
    /// mood. A perch already up stays where it walked to.
    func show(geometry: NotchGeometry, look: NotchMascotLook, mood: NotchMascotMood, visibleInCaptures: Bool) {
        // Opened again while it was fading out: it comes back where it was.
        let returning = hideWork != nil
        hideWork?.cancel(); hideWork = nil
        let size = NotchMascotSupport.size(stripHeight: geometry.stripBodyHeight, floats: true)
        let middle = geometry.screen.midX
        let frame = NotchMascotPerchLayout.frame(screen: geometry.screen, barHeight: geometry.menuBarHeight,
                                                 centerX: middle, size: size)
        let panel = self.panel ?? makePanel()
        let host = self.host ?? NotchMascotHostView(frame: CGRect(origin: .zero, size: frame.size))
        if self.host == nil {
            host.autoresizingMask = [.width, .height]
            // It keeps the moods the companion has at rest: notes with music,
            // a coffee while the Mac is kept awake.
            host.followsAutomation = true
            panel.contentView = host
            self.host = host
        }
        panel.sharingType = visibleInCaptures ? .readOnly : .none
        let arriving = !panel.isVisible
        // A new display or bar height starts it over in the middle.
        if arriving || middle != self.middle || size != self.size || panel.frame.height != frame.height {
            self.middle = middle
            self.size = size
            standing = middle
            panel.setFrame(frame, display: false)
        }
        reach = NotchMascotPerchLayout.reach(cameraWidth: geometry.cameraWidth, sideRoom: geometry.compactSideRoom,
                                             windowWidth: frame.width)
        host.configure(look: look, size: size, mood: mood, idles: true, reduceMotion: reduceMotion,
                       animated: !arriving)
        host.place(at: nil, visible: nil)
        if returning, !arriving {
            panel.animator().alphaValue = 1
            installMonitors()
        }
        guard arriving else { return }
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
        installMonitors()
        attend(to: NSEvent.mouseLocation)
    }

    func hide(animated: Bool = true) {
        removeMonitors()
        guard let panel, panel.isVisible, hideWork == nil else { return }
        guard animated, !reduceMotion else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hideWork = nil
            self?.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    /// Its eyes dart about: the island turned to another page.
    func glance() {
        guard isShown, let host else { return }
        cueID += 1
        host.play(.glance, id: cueID)
    }

    // MARK: Following

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.attend(to: NSEvent.mouseLocation)
        }) { monitors.append(global) }
        // The island is this app's own window, so its moves and clicks come here.
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves.union(.leftMouseDown), handler: { [weak self] event in
            self?.attend(to: NSEvent.mouseLocation)
            if event.type == .leftMouseDown { self?.hop() }
            return event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func attend(to point: NSPoint) {
        guard isShown, let host else { return }
        host.attend(toScreenPoint: point)
        walk(toward: point.x)
    }

    private func walk(toward x: CGFloat) {
        guard !reduceMotion, let panel else { return }
        let now = CACurrentMediaTime()
        guard now - lastWalk >= Self.walkInterval,
              let target = NotchMascotPerchLayout.walkTarget(pointerX: x, standing: standing,
                                                             middle: middle, reach: reach) else { return }
        lastWalk = now
        standing = target
        let origin = CGPoint(x: (target - panel.frame.width / 2).rounded(), y: panel.frame.minY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(origin)
        }
    }

    /// A click in the island: a small hop with wide eyes, now and then.
    private func hop() {
        guard isShown, let host, !reduceMotion, NotchMascotSupport.reacts() else { return }
        let now = CACurrentMediaTime()
        guard now - lastHop >= Self.hopInterval else { return }
        lastHop = now
        host.react(NotchMascotReactionEvent(id: UUID(), reaction: .perk, start: now), lift: size * 0.25)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.setAccessibilityElement(false)
        self.panel = panel
        return panel
    }
}
