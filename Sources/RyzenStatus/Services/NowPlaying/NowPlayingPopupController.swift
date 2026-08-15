// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import SwiftUI

/// Presentation controller for the now-playing popup: owns the regular↔mini
/// morph of the anchored popover and the detachable floating window.
///
/// The morph drives the popover's window frame with a 120 Hz timer (the
/// display-link role) along a steep ease curve while the SwiftUI side
/// crossfades the two layouts. The detached window follows the house pattern
/// for floating panels (borderless, non-activating, clear background),
/// content-hosting the same popup view in its mini presentation.
final class NowPlayingPopupController: ObservableObject {
    static let shared = NowPlayingPopupController()

    /// Fixed popup card sizes per layout; the width never animates outside
    /// the morph driver.
    static let regularSize = NSSize(width: 420, height: 236)
    static let miniSize = NSSize(width: 380, height: 380)

    /// Size presets of the detached window. The card is square: the artwork
    /// tile takes the width minus the chrome margin, the rest stacks below.
    enum DetachedSize: Int, CaseIterable {
        case small = 0, medium = 1, large = 2

        var width: CGFloat {
            switch self {
            case .small: return 320
            case .medium: return 380
            case .large: return 460
            }
        }
    }

    @Published var isMini: Bool {
        didSet {
            guard isMini != oldValue else { return }
            UserDefaults.standard.set(isMini, forKey: DefaultsKey.nowPlayingMiniMode)
        }
    }
    @Published var detachedOnTop: Bool {
        didSet {
            guard detachedOnTop != oldValue else { return }
            UserDefaults.standard.set(detachedOnTop, forKey: DefaultsKey.nowPlayingDetachedOnTop)
            detachedPanel?.level = detachedOnTop ? .floating : .normal
        }
    }
    @Published var detachedSize: DetachedSize {
        didSet {
            guard detachedSize != oldValue else { return }
            UserDefaults.standard.set(detachedSize.rawValue, forKey: DefaultsKey.nowPlayingDetachedSize)
            resizeDetachedPanel()
        }
    }

    var popoverContentSize: NSSize { isMini ? Self.miniSize : Self.regularSize }

    /// Set by AppDelegate when it builds the popup popover.
    weak var popover: NSPopover?
    /// The last status item button that opened the popup; the detached window
    /// anchors its first appearance under it.
    weak var anchorButton: NSStatusBarButton?

    private var detachedPanel: NSPanel?
    private var morphTimer: Timer?
    private var moveObserver: NSObjectProtocol?

    private init() {
        let defaults = UserDefaults.standard
        isMini = defaults.bool(forKey: DefaultsKey.nowPlayingMiniMode)
        detachedOnTop = defaults.bool(forKey: DefaultsKey.nowPlayingDetachedOnTop)
        detachedSize = DetachedSize(rawValue: defaults.integer(forKey: DefaultsKey.nowPlayingDetachedSize)) ?? .medium
    }

    // MARK: - Mini mode morph

    /// Flips the layout and, while the popover is visible, drives its window
    /// frame between the two card sizes along the morph curve. The SwiftUI
    /// side crossfades the layouts off the same `isMini` change.
    func toggleMini() {
        isMini.toggle()
        guard let popover, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        animatePopoverFrame(of: popover, window: window, to: popoverContentSize)
    }

    /// The morph curve: fast lift, long settle (cubic-bezier 0.30, 0.90,
    /// 0.35, 1.00), evaluated by a Newton/bisection solver.
    private static let morphBezier = UnitBezier(control1: CGPoint(x: 0.30, y: 0.90),
                                                control2: CGPoint(x: 0.35, y: 1.00))
    private static let morphDuration: TimeInterval = 0.32

    private func animatePopoverFrame(of popover: NSPopover,
                                     window: NSWindow,
                                     to target: NSSize) {
        morphTimer?.invalidate()
        let startFrame = window.frame
        let startContent = popover.contentSize
        let topY = startFrame.maxY
        let midX = startFrame.midX
        let deltaW = target.width - startContent.width
        let deltaH = target.height - startContent.height
        let startTime = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak popover, weak window] timer in
            guard let popover, let window else {
                timer.invalidate()
                self?.morphTimer = nil
                return
            }
            let progress = min(1, (CACurrentMediaTime() - startTime) / Self.morphDuration)
            let eased = CGFloat(Self.morphBezier.solve(progress))
            let contentW = max(1, startContent.width + deltaW * eased)
            let contentH = max(1, startContent.height + deltaH * eased)
            popover.contentSize = NSSize(width: contentW, height: contentH)
            let frameW = max(1, startFrame.width + deltaW * eased)
            let frameH = max(1, startFrame.height + deltaH * eased)
            // Top-center anchored: the card stays glued under the menu bar
            // item while it grows or shrinks.
            window.setFrame(NSRect(x: midX - frameW / 2,
                                   y: topY - frameH,
                                   width: frameW,
                                   height: frameH),
                            display: true)
            if progress >= 1 {
                timer.invalidate()
                self?.morphTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        morphTimer = timer
    }

    // MARK: - Detached window

    /// The detached presentation is a real floating window: borderless and
    /// movable, mirroring the house pattern for floating panels.
    private func ensureDetachedPanel() -> NSPanel {
        if let detachedPanel { return detachedPanel }

        let size = detachedSize.width
        let panel = NowPlayingDetachedPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size))
        panel.level = detachedOnTop ? .floating : .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = NSHostingController(
            rootView: NowPlayingPopupView(cluster: .detached))
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow, window.isVisible else { return }
            UserDefaults.standard.set(Double(window.frame.origin.x),
                                      forKey: DefaultsKey.nowPlayingDetachedOriginX)
            UserDefaults.standard.set(Double(window.frame.origin.y),
                                      forKey: DefaultsKey.nowPlayingDetachedOriginY)
        }
        detachedPanel = panel
        return panel
    }

    func showDetached() {
        let panel = ensureDetachedPanel()
        panel.setFrameOrigin(detachedOrigin(for: panel))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Detach from the popover: the popup closes and the floating window
    /// takes over with the same track state.
    func detachPopover() {
        popover?.performClose(nil)
        showDetached()
    }

    func closeDetached() {
        guard let panel = detachedPanel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func tearDown() {
        morphTimer?.invalidate()
        morphTimer = nil
        closeDetached()
    }

    /// Where the detached window appears: the persisted origin once the user
    /// has moved it, otherwise 8pt under the now-playing status item.
    private func detachedOrigin(for panel: NSPanel) -> NSPoint {
        let size = panel.frame.size
        let defaults = UserDefaults.standard
        if let x = defaults.object(forKey: DefaultsKey.nowPlayingDetachedOriginX) as? Double,
           let y = defaults.object(forKey: DefaultsKey.nowPlayingDetachedOriginY) as? Double {
            return clampToScreen(NSPoint(x: x, y: y), size: size)
        }
        if let button = anchorButton, let buttonWindow = button.window {
            let onScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let origin = NSPoint(x: onScreen.midX - size.width / 2,
                                 y: onScreen.minY - 8 - size.height)
            return clampToScreen(origin, size: size)
        }
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: visible.midX - size.width / 2,
                       y: visible.maxY - size.height - 40)
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        var origin = origin
        let anchor = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        origin.x = min(max(origin.x, visible.minX + 6),
                       visible.maxX - size.width - 6)
        origin.y = min(max(origin.y, visible.minY + 6),
                       visible.maxY - size.height - 6)
        return origin
    }

    /// Resizes the visible detached window around its center; the SwiftUI
    /// content follows through the published `detachedSize`.
    private func resizeDetachedPanel() {
        guard let panel = detachedPanel, panel.isVisible else { return }
        let width = detachedSize.width
        var frame = panel.frame
        let midX = frame.midX
        let maxY = frame.maxY
        frame.size = NSSize(width: width, height: width)
        frame.origin = NSPoint(x: midX - width / 2, y: maxY - width)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

/// The detached window hosts interactive controls (sliders, menus), which a
/// plain borderless panel refuses to key for.
private final class NowPlayingDetachedPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Classic WebKit-style cubic-bezier evaluator: parametric curve sampled by
/// Newton iteration on x with a bisection fallback.
struct UnitBezier {
    private let ax: Double, bx: Double, cx: Double
    private let ay: Double, by: Double, cy: Double

    init(control1: CGPoint, control2: CGPoint) {
        cx = 3 * Double(control1.x)
        bx = 3 * (Double(control2.x) - Double(control1.x)) - cx
        ax = 1 - cx - bx
        cy = 3 * Double(control1.y)
        by = 3 * (Double(control2.y) - Double(control1.y)) - cy
        ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func sampleDerivativeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    func solve(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return sampleY(t) }
            let derivative = sampleDerivativeX(t)
            if abs(derivative) < 1e-6 { break }
            t -= error / derivative
        }
        var low = 0.0
        var high = 1.0
        t = x
        while high - low > 1e-6 {
            if sampleX(t) < x {
                low = t
            } else {
                high = t
            }
            t = (low + high) / 2
        }
        return sampleY(t)
    }
}
