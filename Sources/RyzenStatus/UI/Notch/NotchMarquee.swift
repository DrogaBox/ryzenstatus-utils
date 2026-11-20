// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// A line too long for its room slides along, resting at its start each time
/// round and fading at the edges; a line that fits stays still, and with
/// reduced motion a long one is cut short instead.
///
/// Core Animation moves the line: it is drawn when it changes and only its
/// layer moves, where a SwiftUI timeline drew the faded line again on the CPU
/// for every frame of the scroll.
///
/// The scrolling copy never animates in SwiftUI: a numericText roll there
/// was drawn on the CPU at the display's full rate (46 % of a core for a
/// capsule scrolling several readings). Readings drawn by RollingDigitsText
/// roll anyway, with the change they came in, since Core Animation moves
/// their digits without drawing them again.
struct NotchMarquee<Content: View>: View {
    /// Points per second.
    var speed: CGFloat = 26
    var pause: TimeInterval = 1.8
    var gap: CGFloat = 32
    /// What the line says, such as its text. The scrolling copy is drawn again
    /// only when this changes; without it, every update of the island redraws it.
    var key: AnyHashable? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineWidth: CGFloat = 0
    @State private var room: CGFloat = 0

    private var scrolls: Bool { !reduceMotion && room > 0 && lineWidth > room + 1 }

    var body: some View {
        content()
            .lineLimit(1)
            .truncationMode(.tail)
            // Under the scrolling copy, the still line rolls and cuts nothing.
            .environment(\.rollingDigitsActive, !scrolls)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .background(alignment: .leading) {
                content().lineLimit(1).fixedSize().environment(\.rollingDigitsActive, false).hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    NotchMarqueeScroller(row: HStack(spacing: gap) {
                        content().lineLimit(1).fixedSize()
                        content().lineLimit(1).fixedSize()
                    }, key: key, motion: NotchMarqueeMotion(lineWidth: lineWidth, gap: gap, speed: speed, pause: pause))
                    .frame(width: room)
                    .accessibilityHidden(true)
                }
            }
            // Starting or stopping the scroll swaps lines at once: no half-rolled
            // or half-faded frame of the still line shows as the moving one takes over.
            .animation(nil, value: scrolls)
    }
}

/// One turn of the line: a rest at its start, then the whole line plus the
/// gap at `speed`, which leaves the copy behind it exactly where it began.
struct NotchMarqueeMotion: Equatable {
    var lineWidth: CGFloat
    var gap: CGFloat
    var speed: CGFloat
    var pause: TimeInterval

    /// The marquee scrolled at thirty frames a second before; a step every
    /// other frame of a fast display still reads as the same glide. Never
    /// below 24, the floor the companion's walk has: at 15 the glide would
    /// step almost two points a frame.
    static let frameRates = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)

    var travel: CGFloat { lineWidth + gap }
    var cycle: TimeInterval { pause + Double(travel / max(speed, 1)) }
    /// Where in a cycle the rest ends and the slide begins, from 0 to 1.
    var restFraction: Double { cycle > 0 ? pause / cycle : 0 }

    func animation() -> CAKeyframeAnimation {
        let move = CAKeyframeAnimation(keyPath: "transform.translation.x")
        move.values = [0, 0, -travel]
        move.keyTimes = [0, NSNumber(value: restFraction), 1]
        move.calculationMode = .linear
        move.duration = cycle
        move.repeatCount = .infinity
        move.preferredFrameRateRange = Self.frameRates
        return move
    }
}

/// The line in a hosting view of its own, so moving it never redraws it.
/// That view inherits only the colour scheme, the locale and the layout
/// direction: the line names its own font and colour, as both callers do.
private struct NotchMarqueeScroller<Row: View>: NSViewRepresentable {
    let row: Row
    let key: AnyHashable?
    let motion: NotchMarqueeMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    private var rootView: AnyView {
        AnyView(row.environment(\.colorScheme, colorScheme).environment(\.locale, locale)
            .environment(\.layoutDirection, layoutDirection))
    }

    /// What the line shows: the caller's key and what it inherits. Without a
    /// key every update is taken as a new line.
    private var lineKey: AnyHashable? {
        key.map { AnyHashable([$0, AnyHashable(colorScheme), AnyHashable(locale.identifier),
                               AnyHashable(layoutDirection)]) }
    }

    func makeNSView(context: Context) -> NotchMarqueeScrollView {
        NotchMarqueeScrollView(rootView: rootView)
    }

    func updateNSView(_ view: NotchMarqueeScrollView, context: Context) {
        // A rolling reading inside rolls with the change it came in; the copy itself never animates.
        let animation = context.transaction.disablesAnimations ? nil : context.transaction.animation
        view.show(AnyView(rootView.environment(\.rollingDigitsAnimation, animation)), key: lineKey)
        view.run(motion)
    }
}

final class NotchMarqueeScrollView: NSView {
    let hosting: NSHostingView<AnyView>
    private let fade = CAGradientLayer()
    private var shownKey: AnyHashable?
    private(set) var running: NotchMarqueeMotion?
    /// On screen: in a window that can be seen, not hidden. Out of sight the
    /// scroll is taken off, so an island ordered out keeps nothing running.
    private(set) var visible = false
    private var occlusionObserver: NSObjectProtocol?

    init(rootView: AnyView) {
        hosting = NSHostingView(rootView: Self.still(rootView))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fade
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    /// The pointer belongs to the strip under the line.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let size = hosting.fittingSize
        hosting.frame = CGRect(x: 0, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit owns this view's layer and may hand it a new one; the clip and
        // the fading edges go with whichever layer is there now.
        if let layer {
            if !layer.masksToBounds { layer.masksToBounds = true }
            if layer.mask !== fade { layer.mask = fade }
        }
        // A new reading lays the line out again; the edges change only with the size or the scale.
        let scale = window?.backingScaleFactor ?? fade.contentsScale
        if fade.frame != bounds || fade.contentsScale != scale || fade.locations == nil {
            fade.frame = bounds
            fade.contentsScale = scale
            // Fading eight points at each edge, as the line always has.
            let edge = bounds.width > 0 ? min(0.2, 8 / bounds.width) : 0
            fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.syncVisibility()
            }
        }
        syncVisibility()
    }

    override func viewDidHide() { super.viewDidHide(); syncVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncVisibility() }

    private func syncVisibility() {
        setVisible(window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor)
    }

    /// Puts the scroll on while the line can be seen and takes it off when it
    /// cannot; it starts again from the line's beginning when it returns.
    func setVisible(_ visible: Bool) {
        self.visible = visible
        guard let layer = hosting.layer else { return }
        if visible, let running {
            if layer.animation(forKey: Self.scrollKey) == nil { layer.add(running.animation(), forKey: Self.scrollKey) }
        } else {
            layer.removeAnimation(forKey: Self.scrollKey)
        }
    }

    /// The line as its parent drew it now. A new reading replaces the old one
    /// with no animation, so no rolling digits are drawn while the line moves.
    /// The same line again, as most updates of the island bring, changes nothing.
    func show(_ row: AnyView, key: AnyHashable?) {
        guard key == nil || key != shownKey else { return }
        shownKey = key
        // A new root, not a published change, so nothing is published while
        // SwiftUI updates the view this one sits in.
        hosting.rootView = Self.still(row)
        needsLayout = true
    }

    /// No animation, and none a view inside may ask for, such as a roll.
    static var stillTransaction: Transaction {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return transaction
    }

    private static func still(_ row: AnyView) -> AnyView {
        AnyView(row.transaction { $0 = stillTransaction })
    }

    /// A new line, or a line of another width, starts again from its beginning.
    func run(_ motion: NotchMarqueeMotion) {
        guard motion != running else { return }
        running = motion
        needsLayout = true
        hosting.layer?.removeAnimation(forKey: Self.scrollKey)
        setVisible(visible)
    }

    static let scrollKey = "marquee"
}
