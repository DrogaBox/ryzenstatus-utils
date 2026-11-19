// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Rolling digits drawn by Core Animation. SwiftUI's `.numericText()` draws
/// every frame of its roll on the CPU at the display's full rate (144 Hz on a
/// fast monitor), about 36 rasterized frames for each 0.25 s change. Here each
/// glyph is drawn once into a cached image and a change only moves layers,
/// which the window server composites at the pace asked for.
///
/// As with `.numericText()`, a changed digit slides out while its new digit
/// slides in from the other side, upwards when the value grows; digits that
/// did not change stay still, and the text after a number that gains or loses
/// a digit glides to its new place.
enum RollingDigits {
    enum Token: Equatable {
        case digits(String)
        case text(String)
    }

    /// Runs of ASCII digits and the text between them.
    static func tokens(_ string: String) -> [Token] {
        var tokens: [Token] = []
        var run = "", inDigits = false
        for character in string {
            let digit = character.isASCII && character.isNumber
            if digit != inDigits, !run.isEmpty {
                tokens.append(inDigits ? .digits(run) : .text(run))
                run = ""
            }
            inDigits = digit
            run.append(character)
        }
        if !run.isEmpty { tokens.append(inDigits ? .digits(run) : .text(run)) }
        return tokens
    }

    /// What one place on the line is. Digits of a whole number are counted
    /// from its right end, so 9 -> 10 keeps the ones in place; digits after a
    /// decimal point are counted from its left.
    struct Slot: Equatable {
        enum Content: Equatable {
            case digit(Character)
            case text(String)
        }

        enum Identity: Hashable {
            case digit(run: Int, place: Int)
            case text(run: Int)
        }

        var identity: Identity
        var content: Content
    }

    static func slots(_ string: String, locale: Locale = .current) -> [Slot] {
        let tokens = tokens(string)
        var slots: [Slot] = []
        for (index, token) in tokens.enumerated() {
            switch token {
            case .text(let text):
                slots.append(Slot(identity: .text(run: index), content: .text(text)))
            case .digits(let digits):
                let fraction = index >= 1 && separator(at: index - 1, in: tokens, locale: locale) == .decimal
                let characters = Array(digits)
                for (offset, character) in characters.enumerated() {
                    let place = fraction ? offset : characters.count - 1 - offset
                    slots.append(Slot(identity: .digit(run: index, place: place), content: .digit(character)))
                }
            }
        }
        return slots
    }

    enum Separator { case decimal, grouping }

    /// What a "." or "," between two numbers is. A comma is a decimal point
    /// where the locale says so or where fewer or more than three digits
    /// follow it ("2,0 KB/s"); otherwise it groups thousands ("$1,234.56"). A
    /// point is a decimal point unless the locale groups with it and three
    /// digits follow ("1.234,5").
    static func separator(at index: Int, in tokens: [Token], locale: Locale) -> Separator? {
        guard index >= 1, index + 1 < tokens.count, case .digits = tokens[index - 1],
              case .digits(let next) = tokens[index + 1], case .text(let text) = tokens[index] else { return nil }
        let thousands = next.count == 3
        switch text {
        case ".": return locale.groupingSeparator == "." && thousands ? .grouping : .decimal
        case ",": return locale.decimalSeparator == "," || !thousands ? .decimal : .grouping
        default: return nil
        }
    }

    /// The text between the numbers. When it changes, as "…" becoming "45%"
    /// or a carousel moving to another reading, the line is swapped whole.
    static func skeleton(_ string: String) -> [String] {
        tokens(string).map { if case .text(let text) = $0 { return text }; return "#" }
    }

    enum Change: Equatable {
        case still
        case roll(from: Character)
        case enter
    }

    struct Plan: Equatable {
        /// False when the text between the numbers changed: the new line replaces the old at once.
        var rolls: Bool
        /// Upwards (the new digit comes from below) when the value grows.
        var up: Bool
        var slots: [Slot]
        var changes: [Change]
        /// Places the old line had and the new one has not.
        var leaving: [Slot.Identity]
    }

    static func plan(from old: String, to new: String, countsDown: Bool? = nil, locale: Locale = .current) -> Plan {
        let newSlots = slots(new, locale: locale)
        guard skeleton(old) == skeleton(new) else {
            return Plan(rolls: false, up: true, slots: newSlots, changes: newSlots.map { _ in .enter }, leaving: [])
        }
        let oldSlots = slots(old, locale: locale)
        let before = Dictionary(oldSlots.map { ($0.identity, $0.content) }, uniquingKeysWith: { first, _ in first })
        let changes: [Change] = newSlots.map { slot in
            guard let previous = before[slot.identity] else { return .enter }
            guard previous != slot.content, case .digit(let from) = previous else { return .still }
            return .roll(from: from)
        }
        let kept = Set(newSlots.map(\.identity))
        let up = countsDown.map { !$0 } ?? grows(from: old, to: new, locale: locale)
        return Plan(rolls: true, up: up, slots: newSlots, changes: changes,
                    leaving: oldSlots.map(\.identity).filter { !kept.contains($0) })
    }

    /// Whether the first number that changed grew: "↓ 1.2M · ↑ 90K" to
    /// "↓ 1.2M · ↑ 100K" grows, whatever the numbers before it read.
    static func grows(from old: String, to new: String, locale: Locale = .current) -> Bool {
        for (before, after) in zip(numbers(old, locale: locale), numbers(new, locale: locale)) where before != after {
            return after > before
        }
        return true
    }

    /// The numbers on a line, left to right: "1.9", "$1,234.56", "↓ 2,0 KB/s".
    static func numbers(_ string: String, locale: Locale = .current) -> [Double] {
        let tokens = tokens(string)
        var numbers: [Double] = []
        var current = ""
        for (index, token) in tokens.enumerated() {
            switch token {
            case .digits(let run): current += run
            case .text:
                switch separator(at: index, in: tokens, locale: locale) {
                case .decimal: current += "."
                case .grouping: continue
                case nil:
                    if let number = Double(current) { numbers.append(number) }
                    current = ""
                }
            }
        }
        if let number = Double(current) { numbers.append(number) }
        return numbers
    }
}

/// The font and colour a rolling line draws with.
struct RollingDigitsStyle: Hashable {
    enum Design: Hashable { case standard, rounded, monospaced }

    var size: CGFloat
    var weight: NSFont.Weight = .regular
    var design: Design = .standard
    /// A font given whole, such as the capsule's level font, used as it is.
    var given: NSFont? = nil

    init(size: CGFloat, weight: NSFont.Weight = .regular, design: Design = .standard) {
        self.size = size
        self.weight = weight
        self.design = design
    }

    /// `.system(size:weight:design: .rounded)` with `.monospacedDigit()`.
    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> Self { Self(size: size, weight: weight, design: .rounded) }

    static func font(_ font: NSFont) -> Self {
        var style = Self(size: font.pointSize)
        style.given = font
        return style
    }

    func font() -> NSFont {
        if let given { return given }
        // Every glyph as wide as the others, as design: .monospaced draws.
        if design == .monospaced { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        if design == .rounded, let roundedDescriptor = descriptor.withDesign(.rounded) { descriptor = roundedDescriptor }
        // Every digit as wide as the others, as .monospacedDigit() asks.
        descriptor = descriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// Glyph images drawn once and shared by every rolling line that uses them.
final class RollingDigitsGlyphs {
    static let shared = RollingDigitsGlyphs()

    struct Metrics {
        var lineHeight: CGFloat
        var descent: CGFloat
    }

    private let cache = NSCache<NSString, CGImage>()
    private var metrics: [String: Metrics] = [:]

    init() { cache.countLimit = 512 }
    static let cachedLength = 16

    func metrics(for font: NSFont) -> Metrics {
        let key = "\(font.fontName)-\(font.pointSize)"
        if let known = metrics[key] { return known }
        let measured = Metrics(lineHeight: ceil(NSLayoutManager().defaultLineHeight(for: font)),
                               descent: ceil(abs(font.descender)))
        metrics[key] = measured
        return measured
    }

    func width(of text: String, font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    /// The longest start of `text` that fits `width` with an ellipsis after it.
    func truncated(_ text: String, font: NSFont, width: CGFloat) -> String {
        guard self.width(of: text, font: font) > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters).trimmingCharacters(in: .whitespaces) + "…"
            if self.width(of: candidate, font: font) <= width { return candidate }
        }
        return "…"
    }

    func image(_ text: String, font: NSFont, color: CGColor, scale: CGFloat) -> CGImage? {
        let components = (color.components ?? []).map { String(format: "%.3f", $0) }.joined(separator: ",")
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(components)|\(scale)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let metrics = metrics(for: font)
        let size = CGSize(width: max(1, width(of: text, font: font)), height: metrics.lineHeight)
        guard let context = CGContext(data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Smoothed as AppKit and SwiftUI draw text on screen; without it the glyphs look thinner.
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: color) ?? .white,
        ]))
        context.textPosition = CGPoint(x: 0, y: metrics.descent)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        // Long lines, such as a song title or a line cut short every tick,
        // are drawn as they come and kept out, so they never push the
        // digits and short runs everybody shares out of the cache.
        if text.count <= Self.cachedLength { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A line of text whose digits roll as `.contentTransition(.numericText())`
/// rolls them, with Core Animation doing the motion.
///
/// It rolls when its text changes inside an animation, as numericText does:
/// the `.animation(_:value:)` a call site already has decides when, and a
/// change without one, under Reduce Motion or a transaction that disables
/// animations lands in place.
///
/// The colour is required: a layer does not inherit SwiftUI's foreground
/// style, so a call site that left it out would draw in some other colour
/// than the Text beside it.
struct RollingDigitsText: NSViewRepresentable {
    let text: String
    var style: RollingDigitsStyle
    var color: Color
    var countsDown: Bool? = nil
    var duration: TimeInterval = 0.25
    var minimumScaleFactor: CGFloat = 1
    var frameRates = RollingDigitsView.defaultFrameRates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rollingDigitsAnimation) private var hostAnimation
    @Environment(\.rollingDigitsActive) private var active

    init(_ text: String, style: RollingDigitsStyle, color: Color, countsDown: Bool? = nil,
         duration: TimeInterval = 0.25, minimumScaleFactor: CGFloat = 1,
         frameRates: CAFrameRateRange = RollingDigitsView.defaultFrameRates) {
        self.text = text
        self.style = style
        self.color = color
        self.countsDown = countsDown
        self.duration = duration
        self.minimumScaleFactor = minimumScaleFactor
        self.frameRates = frameRates
    }

    func makeNSView(context: Context) -> RollingDigitsView {
        let view = RollingDigitsView()
        view.configure(style: style, color: NSColor(color), duration: duration, frameRates: frameRates,
                       minimumScaleFactor: minimumScaleFactor, dark: colorScheme == .dark)
        view.show(text, animated: false, countsDown: countsDown)
        return view
    }

    func updateNSView(_ view: RollingDigitsView, context: Context) {
        view.configure(style: style, color: NSColor(color), duration: duration, frameRates: frameRates,
                       minimumScaleFactor: minimumScaleFactor, dark: colorScheme == .dark)
        view.active = active
        view.show(text, animated: active && Self.animates(reduceMotion: reduceMotion, transaction: context.transaction,
                                                          host: hostAnimation),
                  countsDown: countsDown)
    }

    /// Whether a change rolls: inside an animation that is not disabled, or
    /// inside a host, such as the scrolling marquee, that passes its own.
    static func animates(reduceMotion: Bool, transaction: Transaction, host: Animation?) -> Bool {
        guard !reduceMotion else { return false }
        if host != nil { return true }
        return transaction.animation != nil && !transaction.disablesAnimations
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RollingDigitsView, context: Context) -> CGSize? {
        // As Text: its own width when it fits, otherwise all the room it is offered.
        nsView.offer(proposal.width)
        let natural = nsView.naturalSize
        guard let width = proposal.width, width < natural.width else { return natural }
        return CGSize(width: width, height: natural.height)
    }
}

private struct RollingDigitsAnimationKey: EnvironmentKey {
    static let defaultValue: Animation? = nil
}

private struct RollingDigitsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The animation a host's change came in, for a host whose own update
    /// carries none, such as the marquee's scrolling copy.
    var rollingDigitsAnimation: Animation? {
        get { self[RollingDigitsAnimationKey.self] }
        set { self[RollingDigitsAnimationKey.self] = newValue }
    }

    /// False for a copy nobody sees, such as the marquee's sizing copy or its
    /// still line while the scrolling copy shows: it neither rolls nor draws
    /// an ellipsis. SwiftUI's opacity and hidden() leave the platform view
    /// itself visible, so the view cannot tell on its own.
    var rollingDigitsActive: Bool {
        get { self[RollingDigitsActiveKey.self] }
        set { self[RollingDigitsActiveKey.self] = newValue }
    }
}

final class RollingDigitsView: NSView {
    /// Sixty frames a second: a 0.25 s roll keeps 15 frames, against 36 at
    /// 144 Hz; the slide reads the same.
    static let defaultFrameRates = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)

    private var style = RollingDigitsStyle(size: 13)
    private var font = RollingDigitsStyle(size: 13).font()
    private var color: NSColor = .labelColor
    private var resolvedColor: CGColor = NSColor.white.cgColor
    private var duration: TimeInterval = 0.25
    private var frameRates = defaultFrameRates
    private var minimumScaleFactor: CGFloat = 1
    private let line = CALayer()
    private var layers: [RollingDigits.Slot.Identity: CALayer] = [:]
    private(set) var text = ""
    private(set) var naturalSize = CGSize.zero
    /// On screen: in a window that can be seen, not hidden. Out of sight a
    /// change snaps to the new text with nothing animated.
    private(set) var visible = false
    private var occlusionObserver: NSObjectProtocol?
    /// Animations added by the last change, for tests.
    private(set) var lastAnimations: [CAAnimation] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        // No clip here: a line that grew draws where it is going before SwiftUI
        // widens the view. Each digit's column clips its own slide.
        wantsLayer = true
        line.anchorPoint = .zero
        layer?.addSublayer(line)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // The parent names the value for VoiceOver; on its own the line reads as its text.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { text }

    /// `dark` is the colour scheme SwiftUI draws in, which the island sets
    /// whatever the system's appearance; nil follows this view's appearance.
    func configure(style: RollingDigitsStyle, color: NSColor, duration: TimeInterval, frameRates: CAFrameRateRange,
                   minimumScaleFactor: CGFloat, dark: Bool? = nil) {
        self.duration = duration
        self.frameRates = frameRates
        self.minimumScaleFactor = minimumScaleFactor
        guard style != self.style || color != self.color || dark != self.dark else { return }
        self.style = style
        self.color = color
        self.dark = dark
        font = style.font()
        resolveColor()
        redraw()
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private var dark: Bool?
    private func resolveColor() {
        var resolved = NSColor.white.cgColor
        let appearance = dark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? effectiveAppearance
        appearance.performAsCurrentDrawingAppearance { resolved = self.color.cgColor }
        resolvedColor = resolved
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColor()
        redraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in self?.syncVisibility() }
        }
        syncVisibility()
        redraw()
    }

    override func viewDidHide() { super.viewDidHide(); syncVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncVisibility() }

    private func syncVisibility() {
        setVisible(window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor)
    }

    /// Out of sight, a roll under way ends where it was going.
    func setVisible(_ visible: Bool) {
        self.visible = visible
        guard !visible else { return }
        settle()
    }

    private func settle() {
        dropLeaving()
        line.sublayers?.forEach { layer in
            layer.removeAllAnimations()
            layer.sublayers?.forEach { $0.removeAllAnimations() }
        }
    }

    /// Redraws the current text at once, as a new scale, colour or font asks.
    private func redraw() {
        let current = text
        text = ""
        dropLeaving()
        layers.values.forEach { $0.removeFromSuperlayer() }
        layers.removeAll()
        show(current, animated: false, countsDown: nil)
    }

    /// Glyphs and columns on their way out. They go when their slide ends,
    /// or at once when the view settles, redraws or swaps its line, so none
    /// is ever left standing on top of the new text.
    private(set) var leavingLayers: [CALayer] = []

    private func dropLeaving() {
        leavingLayers.forEach { $0.removeFromSuperlayer() }
        leavingLayers.removeAll()
    }

    private func leave(_ layer: CALayer, after delay: TimeInterval) {
        leavingLayers.append(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak layer] in
            guard let layer else { return }
            layer.removeFromSuperlayer()
            self?.leavingLayers.removeAll { $0 === layer }
        }
    }

    /// The vertical offset and opacity a glyph shows right now, mid-slide or at rest.
    private static func presented(_ layer: CALayer) -> (offset: CGFloat, opacity: Float) {
        let shown = layer.presentation() ?? layer
        let offset = (shown.value(forKeyPath: "transform.translation.y") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
        return (offset, shown.opacity)
    }

    private func width(of slot: RollingDigits.Slot) -> CGFloat {
        switch slot.content {
        case .digit(let digit): return RollingDigitsGlyphs.shared.width(of: String(digit), font: font)
        case .text(let text): return RollingDigitsGlyphs.shared.width(of: text, font: font)
        }
    }

    private func image(_ text: String) -> CGImage? {
        RollingDigitsGlyphs.shared.image(text, font: font, color: resolvedColor, scale: scale)
    }

    func show(_ newText: String, animated requested: Bool, countsDown: Bool?) {
        guard newText != text || layers.isEmpty && !newText.isEmpty else { return }
        let old = text
        text = newText
        let plan = RollingDigits.plan(from: old, to: newText, countsDown: countsDown)
        let animated = requested && visible && !old.isEmpty && duration > 0
        let metrics = RollingDigitsGlyphs.shared.metrics(for: font)
        let height = metrics.lineHeight
        lastAnimations = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !plan.rolls {
            dropLeaving()
            layers.values.forEach { $0.removeFromSuperlayer() }
            layers.removeAll()
        }
        for identity in plan.leaving {
            guard let gone = layers.removeValue(forKey: identity) else { continue }
            // The column is the clip: its glyph slides out inside it, so the
            // leaving digit never crosses its neighbours.
            if animated, let glyph = gone.sublayers?.first {
                let now = Self.presented(glyph)
                add(slide(from: now.offset, to: plan.up ? height : -height, fades: true, opacity: now.opacity),
                    to: glyph, key: "leave")
                leave(gone, after: settling)
            } else {
                gone.removeFromSuperlayer()
            }
        }
        var x: CGFloat = 0
        for (slot, change) in zip(plan.slots, plan.changes) {
            let slotWidth = width(of: slot)
            let frame = CGRect(x: x, y: 0, width: slotWidth, height: height)
            x += slotWidth
            let content: String
            switch slot.content {
            case .digit(let digit): content = String(digit)
            case .text(let text): content = text
            }
            if let column = layers[slot.identity] {
                let oldX = column.frame.minX
                column.frame = frame
                if animated, oldX != frame.minX {
                    add(move(fromX: oldX + frame.width / 2, toX: frame.midX), to: column, key: "glide")
                }
                guard case .roll = change, let glyph = column.sublayers?.first else { continue }
                // A change that comes mid-roll, as a held key or a dragged
                // slider brings, replaces the digit still leaving, and the one
                // that leaves now starts from where it is on screen.
                for older in column.sublayers?.dropFirst() ?? [] {
                    older.removeFromSuperlayer()
                    leavingLayers.removeAll { $0 === older }
                }
                let now = Self.presented(glyph)
                glyph.removeAllAnimations()
                if animated {
                    // The old digit leaves on a layer of its own; the new one takes its place.
                    let leaving = CALayer()
                    leaving.frame = glyph.frame
                    leaving.contents = glyph.contents
                    leaving.contentsScale = glyph.contentsScale
                    column.addSublayer(leaving)
                    add(slide(from: now.offset, to: plan.up ? height : -height, fades: true, opacity: now.opacity),
                        to: leaving, key: "leave")
                    leave(leaving, after: settling)
                }
                glyph.contents = image(content)
                glyph.contentsScale = scale
                glyph.frame = CGRect(x: 0, y: 0, width: frame.width, height: height)
                if animated {
                    add(slide(from: plan.up ? -height : height, to: 0, fades: false), to: glyph, key: "enter")
                }
            } else {
                let column = CALayer()
                column.frame = frame
                column.masksToBounds = true
                let glyph = CALayer()
                glyph.frame = CGRect(x: 0, y: 0, width: frame.width, height: height)
                glyph.contents = image(content)
                glyph.contentsScale = scale
                column.addSublayer(glyph)
                line.addSublayer(column)
                layers[slot.identity] = column
                if animated, change == .enter {
                    add(plan.rolls ? slide(from: plan.up ? -height : height, to: 0, fades: false) : fadeIn(), to: glyph,
                        key: "enter")
                }
            }
        }
        line.frame = CGRect(x: 0, y: 0, width: x, height: height)
        CATransaction.commit()
        let size = CGSize(width: x, height: height)
        if size != naturalSize {
            naturalSize = size
            invalidateIntrinsicContentSize()
        }
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize { naturalSize }

    // The text's own baseline, so `.firstTextBaseline` lines it up with the
    // Text beside it, where the line is drawn: centred and, too wide, shrunk.
    override var lastBaselineOffsetFromBottom: CGFloat {
        let descent = RollingDigitsGlyphs.shared.metrics(for: font).descent
        return lineOrigin(fit: currentFit).y + descent * currentFit
    }

    override var firstBaselineOffsetFromTop: CGFloat {
        let height = bounds.height > 0 ? bounds.height : naturalSize.height
        return height - lastBaselineOffsetFromBottom
    }

    /// How much the line is shrunk to fit the room SwiftUI offered.
    var currentFit: CGFloat {
        let room = self.room
        return naturalSize.width > room && room > 0 ? max(minimumScaleFactor, room / naturalSize.width) : 1
    }

    /// The room SwiftUI offered, which decides; the bounds take a later pass
    /// to catch up with a line that grew. Never offered a width, as under
    /// .fixedSize(), the line has all the room it needs.
    private var room: CGFloat { offeredWidth ?? .infinity }

    private func lineOrigin(fit: CGFloat) -> CGPoint {
        let height = bounds.height > 0 ? bounds.height : naturalSize.height
        return CGPoint(x: 0, y: (height - naturalSize.height * fit) / 2)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Too wide for its room, the line shrinks as minimumScaleFactor lets
        // Text shrink, by scaling its layers, not by drawing again.
        let room = self.room
        let fit = currentFit
        let transform = CGAffineTransform(scaleX: fit, y: fit)
        let origin = lineOrigin(fit: fit)
        line.setAffineTransform(transform)
        line.position = origin
        // Still too wide at its smallest, it ends in an ellipsis as Text
        // does, drawn whole, with nothing rolling. A copy nobody sees draws none.
        let truncates = active && room > 0 && naturalSize.width * fit > room + 0.5
        line.isHidden = truncates
        if truncates {
            if truncated.superlayer == nil { layer?.addSublayer(truncated) }
            let shown = RollingDigitsGlyphs.shared.truncated(text, font: font, width: room / fit)
            truncated.contents = image(shown)
            truncated.contentsScale = scale
            truncated.anchorPoint = .zero
            truncated.bounds = CGRect(x: 0, y: 0, width: RollingDigitsGlyphs.shared.width(of: shown, font: font),
                                      height: naturalSize.height)
            truncated.setAffineTransform(transform)
            truncated.position = origin
        }
        truncated.isHidden = !truncates
        CATransaction.commit()
    }

    /// The line cut short with an ellipsis, when it cannot fit.
    private let truncated = CALayer()
    /// The width SwiftUI last really offered.
    private(set) var offeredWidth: CGFloat? {
        didSet { if offeredWidth != oldValue { needsLayout = true } }
    }

    /// SwiftUI probes a view with several sizes while it lays out: none (its
    /// ideal size) and zero (its smallest) say nothing about its room, so
    /// only a real width is kept.
    func offer(_ width: CGFloat?) {
        guard let width, width > 0, width.isFinite else { return }
        offeredWidth = width
    }

    /// False for a copy nobody sees (`rollingDigitsActive`).
    var active = true {
        didSet { if active != oldValue { needsLayout = true } }
    }
    var isTruncated: Bool { line.isHidden }
    /// The layer the columns sit in, for tests.
    var lineLayer: CALayer { line }

    // MARK: Animations

    private func add(_ animation: CAAnimation, to layer: CALayer, key: String) {
        animation.preferredFrameRateRange = frameRates
        layer.add(animation, forKey: key)
        lastAnimations.append(animation)
    }

    /// SwiftUI's `.smooth(duration:)`: a spring with no bounce whose
    /// perceptual duration is `duration`, which settles in about twice that.
    static func spring(_ keyPath: String, duration: TimeInterval) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / duration, 2)
        spring.damping = 4 * .pi / duration
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        return spring
    }

    /// A glyph moving `from` -> `to` points up (positive) or down, fading out when it leaves.
    private func slide(from: CGFloat, to: CGFloat, fades: Bool, opacity: Float = 1) -> CAAnimation {
        let move = Self.spring("transform.translation.y", duration: duration)
        move.fromValue = from
        move.toValue = to
        // The old digit is mostly gone by the time the two cross, so the
        // middle of the slide never shows both of them sharp at once.
        let fade = Self.spring("opacity", duration: fades ? duration * 0.5 : duration)
        fade.fromValue = fades ? opacity : 0
        fade.toValue = fades ? 0 : 1
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = move.duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = !fades
        group.animations?.forEach { $0.preferredFrameRateRange = frameRates }
        return group
    }

    private func move(fromX: CGFloat, toX: CGFloat) -> CAAnimation {
        let glide = Self.spring("position.x", duration: duration)
        glide.fromValue = fromX
        glide.toValue = toX
        return glide
    }

    /// How long a leaving glyph stays before its layer goes.
    private var settling: TimeInterval { Self.spring("opacity", duration: duration).settlingDuration }

    private func fadeIn() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration * 0.6
        return fade
    }
}
