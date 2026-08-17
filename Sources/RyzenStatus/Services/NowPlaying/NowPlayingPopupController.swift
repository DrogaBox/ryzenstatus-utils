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
    /// the morph driver. The regular card adapts to the artwork size setting:
    /// the width follows the tile (never narrower than 410pt), the height
    /// keeps the 18pt chrome, the tile ring and the transport row constant.
    static let minimumRegularWidth: CGFloat = 410
    static let regularChrome: CGFloat = 96
    static let miniSize = NSSize(width: 380, height: 470)
    /// The lyrics/credits details pane grows the regular card by this much;
    /// the same value is the pane's fixed height inside the card.
    static let detailsPaneHeight: CGFloat = 172

    /// The popup artwork tile size from settings, clamped to 120–260pt.
    static var artworkTileSize: CGFloat {
        let raw = UserDefaults.standard.double(forKey: DefaultsKey.nowPlayingArtworkSize)
        let value = raw >= 1 ? raw : 140
        return min(max(CGFloat(value), 120), 260)
    }

    static var regularSize: NSSize {
        let tile = artworkTileSize
        return NSSize(width: max(minimumRegularWidth, tile + 330),
                      height: tile + regularChrome)
    }

    /// Size presets of the detached window: proportional cards where the
    /// artwork, metadata, progress slider, and transport controls fit completely.
    enum DetachedSize: Int, CaseIterable {
        case small = 0, medium = 1, large = 2

        var width: CGFloat {
            switch self {
            case .small: return 320
            case .medium: return 380
            case .large: return 440
            }
        }

        var height: CGFloat {
            switch self {
            case .small: return 410
            case .medium: return 470
            case .large: return 530
            }
        }

        var size: NSSize {
            NSSize(width: width, height: height)
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

    /// The expandable lyrics/credits pane under the hero. Only the regular
    /// popover layout hosts it; the expansion persists across popup opens
    /// (and the unload-when-hidden rehost) through UserDefaults.
    @Published var detailsExpanded: Bool {
        didSet {
            guard detailsExpanded != oldValue else { return }
            UserDefaults.standard.set(detailsExpanded, forKey: DefaultsKey.nowPlayingDetailsPane)
        }
    }
    @Published var detailsTab: NowPlayingDetailsTab

    var popoverContentSize: NSSize {
        if isMini { return Self.miniSize }
        var size = Self.regularSize
        if detailsExpanded {
            size.height += Self.detailsPaneHeight
        }
        return size
    }

    /// The artwork size setting changed: while the popover is open in the
    /// regular layout, glide its window to the new card size the same way
    /// the mini morph does.
    func applyArtworkSizeChange() {
        guard let popover, popover.isShown, !isMini,
              let window = popover.contentViewController?.view.window else { return }
        animatePopoverFrame(of: popover, window: window, to: popoverContentSize)
    }

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
        detailsExpanded = defaults.bool(forKey: DefaultsKey.nowPlayingDetailsPane)
        detailsTab = .lyrics
    }

    // MARK: - Details pane

    /// Toggles the details pane to a tab: tapping the active tab's button
    /// collapses it, any other tab switches or expands. While the popover is
    /// visible the window frame glides to the new card size with the same
    /// morph driver, clamped to the space under the status item.
    func toggleDetailsPane(tab: NowPlayingDetailsTab) {
        if detailsExpanded && detailsTab == tab {
            detailsExpanded = false
        } else {
            detailsTab = tab
            detailsExpanded = true
        }
        animateDetailsPaneChange()
    }

    private func animateDetailsPaneChange() {
        guard let popover, popover.isShown, !isMini,
              let window = popover.contentViewController?.view.window else { return }
        var target = popoverContentSize
        if let maxHeight = availableHeight(under: anchorButton) {
            target.height = min(target.height, maxHeight)
        }
        animatePopoverFrame(of: popover, window: window, to: target)
    }

    // MARK: - Mini mode morph

    /// Flips the layout and, while the popover is visible, drives its window
    /// frame between the two card sizes along the morph curve. The SwiftUI
    /// side crossfades the layouts off the same `isMini` change.
    func toggleMini() {
        isMini.toggle()
        // The details pane lives in the regular layout alone; entering mini
        // folds it away so the two card sizes never disagree.
        if isMini, detailsExpanded {
            detailsExpanded = false
        }
        guard let popover, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        var target = popoverContentSize
        // The same vertical clamp presentation applies: the morph must never
        // drive the card past the space under the item.
        if let maxHeight = availableHeight(under: anchorButton) {
            target.height = min(target.height, maxHeight)
        }
        animatePopoverFrame(of: popover, window: window, to: target)
    }

    /// The free vertical space under the status item, minus a 6pt margin —
    /// mirrors AppDelegate.availableHeight(under:) used at presentation.
    private func availableHeight(under button: NSStatusBarButton?) -> CGFloat? {
        guard let button, let buttonWindow = button.window else { return nil }
        let onScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor = NSPoint(x: onScreen.midX, y: onScreen.minY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }
        return max(140, onScreen.minY - visible.minY - 6)
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

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak popover, weak window] timer in
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

        let size = detachedSize.size
        let panel = NowPlayingDetachedPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height))
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

    /// Whether the detached floating window is currently live; the anchored
    /// popup and this window are the same surface and never show together.
    var isDetachedVisible: Bool { detachedPanel?.isVisible == true }

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
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil
        closeDetached()
    }

    deinit {
        tearDown()
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
        let size = detachedSize.size
        var frame = panel.frame
        let midX = frame.midX
        let maxY = frame.maxY
        frame.size = size
        // Growing downward with a fixed maxY can push the card off-screen;
        // clamp the new frame before animating.
        frame.origin = clampToScreen(NSPoint(x: midX - size.width / 2, y: maxY - size.height),
                                     size: frame.size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

/// The two pages of the expandable details pane under the hero.
enum NowPlayingDetailsTab: Int {
    case lyrics = 0
    case credits = 1
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
