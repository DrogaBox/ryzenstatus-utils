// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import QuartzCore

/// Supported gamer cheat codes.
enum NotchMascotCheat: String, CaseIterable, Equatable {
    case konami
    case idkfa
    case iddqd
    case idclip
    case roll
    case motherlode
    /// The old adventure's magic word: something rare comes by.
    case xyzzy
    /// Its echo in the same old cave: the Mac's and the calendar's moments, one by one.
    case plugh
    /// The whole gang is called out, and confetti flies. Spelled "partyhard",
    /// since "party" alone turns up in ordinary typing.
    case party
    /// Big-head mode, a good while.
    case bighead
    /// Falling green code, and slow motion a while.
    case thereisnospoon
    /// Low gravity a while, and a walk backwards that slides.
    case moonwalk

    var badge: String {
        switch self {
        case .konami: return "👾 30 LIVES"
        case .idkfa: return "🔫 FULL ARSENAL"
        case .iddqd: return "👁️ GOD MODE"
        case .idclip: return "👻 NO CLIP"
        case .roll: return "🔄 BARREL ROLL"
        case .motherlode: return "💸 +10,000 GOLD"
        case .xyzzy: return "✨ SOMETHING STIRS"
        case .plugh: return "🪄 A HOLLOW VOICE"
        case .party: return "🎉 PARTY TIME"
        case .bighead: return "🎈 BIG HEAD MODE"
        case .thereisnospoon: return "🥄 THERE IS NO SPOON"
        case .moonwalk: return "🌙 MOONWALK"
        }
    }

    var soundEffect: NotchMascotSoundEffect {
        switch self {
        case .konami: return .magic
        case .idkfa: return .clash
        case .iddqd: return .magic
        case .idclip: return .poof
        case .roll: return .whoosh
        case .motherlode: return .coin
        case .xyzzy: return .magic
        case .plugh: return .chime
        case .party: return .toot
        case .bighead: return .boing
        case .thereisnospoon: return .bleep
        case .moonwalk: return .warble
        }
    }
    /// What is heard as its banner comes in: its own sound, then an arcade
    /// flourish of its own, one sound a moment after the other.
    var fanfare: [(effect: NotchMascotSoundEffect, at: TimeInterval)] {
        let flourish: [NotchMascotSoundEffect]
        switch self {
        case .konami: flourish = [.coin, .chime, .magic, .bleep]
        case .idkfa: flourish = [.boom, .clash, .zap, .boom]
        case .iddqd: flourish = [.chime, .magic, .chime, .alert]
        case .idclip: flourish = [.whoosh, .warble, .poof]
        case .roll: flourish = [.whoosh, .boing, .whoosh]
        case .motherlode: flourish = [.chime, .coin, .chime, .coin]
        case .xyzzy: flourish = [.chime, .warble, .magic]
        case .plugh: flourish = [.hoot, .warble, .chime]
        case .party: flourish = [.pop, .giggle, .pop, .toot]
        case .bighead: flourish = [.squeak, .boing, .giggle]
        case .thereisnospoon: flourish = [.warble, .whoosh, .bleep]
        case .moonwalk: flourish = [.whoosh, .chirp, .warble]
        }
        return ([soundEffect] + flourish).enumerated().map { (effect: $0.element, at: Double($0.offset) * 0.17) }
    }
    /// The colour its banner glows in.
    var glow: NSColor {
        switch self {
        case .konami: return NSColor(srgbRed: 0.3, green: 1, blue: 0.45, alpha: 1)
        case .idkfa: return NSColor(srgbRed: 1, green: 0.42, blue: 0.2, alpha: 1)
        case .iddqd: return NSColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1)
        case .idclip: return NSColor(srgbRed: 0.6, green: 0.85, blue: 1, alpha: 1)
        case .roll: return NSColor(srgbRed: 0.35, green: 0.65, blue: 1, alpha: 1)
        case .motherlode: return NSColor(srgbRed: 1, green: 0.8, blue: 0.2, alpha: 1)
        case .xyzzy: return NSColor(srgbRed: 0.75, green: 0.5, blue: 1, alpha: 1)
        case .plugh: return NSColor(srgbRed: 0.55, green: 0.95, blue: 0.85, alpha: 1)
        case .party: return NSColor(srgbRed: 1, green: 0.4, blue: 0.7, alpha: 1)
        case .bighead: return NSColor(srgbRed: 1, green: 0.55, blue: 0.3, alpha: 1)
        case .thereisnospoon: return NSColor(srgbRed: 0.25, green: 1, blue: 0.4, alpha: 1)
        case .moonwalk: return NSColor(srgbRed: 0.8, green: 0.85, blue: 1, alpha: 1)
        }
    }
}

/// A normalized keystroke input for cheat matching.
struct CheatInput: Equatable {
    let keyCode: UInt16
    let character: Character?

    init(keyCode: UInt16 = 0xFFFF, character: Character? = nil) {
        self.keyCode = keyCode
        self.character = character.flatMap { String($0).lowercased().first }
    }
}

/// A single step condition in a cheat sequence pattern.
struct CheatStep {
    let matches: (CheatInput) -> Bool

    static func key(_ code: UInt16) -> CheatStep {
        CheatStep { $0.keyCode == code }
    }

    static func char(_ c: Character, keycode: UInt16? = nil) -> CheatStep {
        let lower = Character(String(c).lowercased())
        return CheatStep { input in
            if let kc = keycode, input.keyCode == kc { return true }
            if let ch = input.character, ch == lower { return true }
            return false
        }
    }

    static func arrow(code: UInt16, char: Character) -> CheatStep {
        CheatStep { input in
            input.keyCode == code || input.character == char
        }
    }
}

/// Pure sequence matching engine for gamer cheat codes.
final class NotchMascotCheatEngine {
    private var buffer: [CheatInput] = []
    private(set) var lastKeystrokeTime: TimeInterval?
    let silenceTimeout: TimeInterval

    private static let cheatDefinitions: [(NotchMascotCheat, [CheatStep])] = [
        (
            .konami,
            [
                .arrow(code: 126, char: "\u{F700}"), // Up
                .arrow(code: 126, char: "\u{F700}"), // Up
                .arrow(code: 125, char: "\u{F701}"), // Down
                .arrow(code: 125, char: "\u{F701}"), // Down
                .arrow(code: 123, char: "\u{F702}"), // Left
                .arrow(code: 124, char: "\u{F703}"), // Right
                .arrow(code: 123, char: "\u{F702}"), // Left
                .arrow(code: 124, char: "\u{F703}"), // Right
                .char("b", keycode: 11),              // B
                .char("a", keycode: 0)                // A
            ]
        ),
        (
            .idkfa,
            [
                .char("i", keycode: 34),
                .char("d", keycode: 2),
                .char("k", keycode: 40),
                .char("f", keycode: 3),
                .char("a", keycode: 0)
            ]
        ),
        (
            .iddqd,
            [
                .char("i", keycode: 34),
                .char("d", keycode: 2),
                .char("d", keycode: 2),
                .char("q", keycode: 12),
                .char("d", keycode: 2)
            ]
        ),
        (
            .idclip,
            [
                .char("i", keycode: 34),
                .char("d", keycode: 2),
                .char("c", keycode: 8),
                .char("l", keycode: 37),
                .char("i", keycode: 34),
                .char("p", keycode: 35)
            ]
        ),
        (
            .roll,
            [
                .char("r", keycode: 15),
                .char("o", keycode: 31),
                .char("l", keycode: 37),
                .char("l", keycode: 37)
            ]
        ),
        (
            .motherlode,
            [
                .char("m", keycode: 46),
                .char("o", keycode: 31),
                .char("t", keycode: 17),
                .char("h", keycode: 4),
                .char("e", keycode: 14),
                .char("r", keycode: 15),
                .char("l", keycode: 37),
                .char("o", keycode: 31),
                .char("d", keycode: 2),
                .char("e", keycode: 14)
            ]
        ),
        (
            .xyzzy,
            [
                .char("x", keycode: 7),
                .char("y", keycode: 16),
                .char("z", keycode: 6),
                .char("z", keycode: 6),
                .char("y", keycode: 16)
            ]
        ),
        (
            .plugh,
            [
                .char("p", keycode: 35),
                .char("l", keycode: 37),
                .char("u", keycode: 32),
                .char("g", keycode: 5),
                .char("h", keycode: 4)
            ]
        ),
        (.party, spelled("partyhard")),
        (.bighead, spelled("bighead")),
        (.thereisnospoon, spelled("thereisnospoon")),
        (.moonwalk, spelled("moonwalk"))
    ]
    /// The ANSI key of each letter, matched as well as the letter typed.
    private static let letterKeys: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
        "m": 46,
    ]
    /// The steps that type `word`, letter by letter.
    private static func spelled(_ word: String) -> [CheatStep] {
        word.map { CheatStep.char($0, keycode: letterKeys[$0]) }
    }

    init(silenceTimeout: TimeInterval = 2.5) {
        self.silenceTimeout = silenceTimeout
    }

    func reset() {
        buffer.removeAll()
        lastKeystrokeTime = nil
    }

    var bufferCount: Int {
        buffer.count
    }

    @discardableResult
    func receive(
        keyCode: UInt16 = 0xFFFF,
        character: Character? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NotchMascotCheat? {
        let active = modifiers.intersection(.deviceIndependentFlagsMask)
        if active.contains(.command) || active.contains(.control) || active.contains(.option) {
            return nil
        }

        if let last = lastKeystrokeTime, (timestamp - last) > silenceTimeout {
            buffer.removeAll()
        }
        lastKeystrokeTime = timestamp

        let input = CheatInput(keyCode: keyCode, character: character)
        buffer.append(input)

        if buffer.count > 32 {
            buffer.removeFirst(buffer.count - 32)
        }

        for (cheat, steps) in Self.cheatDefinitions {
            if buffer.count >= steps.count {
                let suffix = buffer.suffix(steps.count)
                var matched = true
                for (item, step) in zip(suffix, steps) {
                    if !step.matches(item) {
                        matched = false
                        break
                    }
                }
                if matched {
                    buffer.removeAll()
                    return cheat
                }
            }
        }

        return nil
    }

    @discardableResult
    func receive(
        character: Character,
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NotchMascotCheat? {
        receive(keyCode: 0xFFFF, character: character, modifiers: modifiers, timestamp: timestamp)
    }

    @discardableResult
    func receive(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NotchMascotCheat? {
        receive(keyCode: keyCode, character: nil, modifiers: modifiers, timestamp: timestamp)
    }

    @discardableResult
    func receive(
        text: String,
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NotchMascotCheat? {
        var lastTriggered: NotchMascotCheat?
        for char in text {
            if let cheat = receive(keyCode: 0xFFFF, character: char, modifiers: modifiers, timestamp: timestamp) {
                lastTriggered = cheat
            }
        }
        return lastTriggered
    }
}

/// A non-activating floating panel that strictly ignores all mouse clicks and focus.
final class NotchMascotCheatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A cheat's arcade banner: its title huge and glowing across the screen in
/// use, slammed in with a shake over a dark band between two neon lines, a
/// white flash over that screen and a fanfare of several sounds. It takes no
/// clicks and no focus, and goes after three seconds. With Reduce Motion it
/// only fades in and out, and nothing flashes.
@MainActor
final class NotchMascotCheatBanner {
    static let shared = NotchMascotCheatBanner()

    /// How long it shows, from the slam to the moment it starts to go.
    nonisolated static let length: TimeInterval = 2.7

    private var panels: [NotchMascotCheatPanel] = []
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func show(cheat: NotchMascotCheat) {
        for cue in cheat.fanfare {
            NotchMascotSound.play(cue.effect, after: cue.at)
        }
        NotchService.shared.playMascotCheat(cheat)
        dismissWork?.cancel()
        dismissWork = nil
        close()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !calm { flash(over: screen) }
        banner(for: cheat, over: screen, calm: calm)
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.length + 0.4, execute: work)
    }

    private func close() {
        panels.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        panels.removeAll()
    }

    private func makePanel(_ frame: CGRect) -> (panel: NotchMascotCheatPanel, layer: CALayer)? {
        let panel = NotchMascotCheatPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        panel.setAccessibilityElement(false)
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        panel.contentView = view
        guard let layer = view.layer else { return nil }
        layer.masksToBounds = false
        panels.append(panel)
        return (panel, layer)
    }

    /// White over the whole of `screen` for a blink, fading fast.
    private func flash(over screen: NSScreen) {
        guard let (panel, layer) = makePanel(screen.frame) else { return }
        let white = CALayer()
        white.frame = layer.bounds
        white.backgroundColor = CGColor(gray: 1, alpha: 1)
        white.opacity = 0
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 0.7, 0]
        blink.keyTimes = [0, 0.12, 1]
        blink.duration = 0.45
        white.add(blink, forKey: "flash")
        layer.addSublayer(white)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            panel.close()
            self?.panels.removeAll { $0 === panel }
        }
    }

    // swiftlint:disable:next function_body_length
    private func banner(for cheat: NotchMascotCheat, over screen: NSScreen, calm: Bool) {
        let height = min(320, screen.frame.height * 0.38)
        let frame = CGRect(x: screen.frame.minX, y: screen.frame.minY + screen.frame.height * 0.56 - height / 2,
                           width: screen.frame.width, height: height)
        guard let (panel, layer) = makePanel(frame) else { return }
        let scale = screen.backingScaleFactor
        let glow = cheat.glow
        let bounds = layer.bounds

        let band = CAGradientLayer()
        band.frame = bounds
        band.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.78), CGColor(gray: 0, alpha: 0.78),
                       CGColor(gray: 0, alpha: 0)]
        band.locations = [0, 0.24, 0.76, 1]
        layer.addSublayer(band)

        let content = CALayer()
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.addSublayer(content)
        var lines: [CALayer] = []
        for y in [bounds.height * 0.2, bounds.height * 0.8] {
            let line = CALayer()
            line.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.9, height: 3)
            line.position = CGPoint(x: bounds.midX, y: y)
            line.backgroundColor = glow.cgColor
            line.shadowColor = glow.cgColor
            line.shadowOpacity = 1
            line.shadowRadius = 10
            line.shadowOffset = .zero
            content.addSublayer(line)
            lines.append(line)
        }

        let title = Self.textLayer(Self.titleText(cheat.badge, glow: glow, width: bounds.width * 0.86,
                                                  height: bounds.height * 0.46), scale: scale)
        let subtitle = Self.textLayer(Self.subtitleText(FeatureStrings.notchMascotCheats(L10n.shared.language).activated,
                                                        glow: glow), scale: scale)
        // The subtitle sits on the lower line and the title fills the band over it.
        subtitle.position = CGPoint(x: bounds.midX, y: bounds.height * 0.2 + 22)
        title.position = CGPoint(x: bounds.midX, y: bounds.height * 0.5 + 16)
        title.shadowColor = glow.cgColor
        title.shadowOpacity = 0.9
        title.shadowRadius = 16
        title.shadowOffset = .zero
        content.addSublayer(title)
        content.addSublayer(subtitle)

        panel.orderFrontRegardless()
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = calm ? 0.3 : 0.18
        layer.add(fadeIn, forKey: "in")
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.beginTime = CACurrentMediaTime() + Self.length
        fadeOut.duration = 0.35
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "out")
        guard !calm else { return }

        // Slammed in from huge, a bounce, a shake, and away bigger still.
        let slam = CAKeyframeAnimation(keyPath: "transform.scale")
        slam.values = [3.4, 0.9, 1.07, 1]
        slam.keyTimes = [0, 0.55, 0.8, 1]
        slam.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeInEaseOut)]
        slam.duration = 0.42
        content.add(slam, forKey: "slam")
        let shake = CAKeyframeAnimation(keyPath: "position")
        shake.values = (0...8).map { step -> NSValue in
            let fade = 1 - CGFloat(step) / 8
            guard step > 0, step < 8 else { return NSValue(point: .zero) }
            return NSValue(point: CGPoint(x: (step.isMultiple(of: 2) ? 1 : -1) * 16 * fade, y: CGFloat.random(in: -6...6) * fade))
        }
        shake.beginTime = CACurrentMediaTime() + 0.24
        shake.duration = 0.42
        shake.isAdditive = true
        content.add(shake, forKey: "shake")
        let away = CABasicAnimation(keyPath: "transform.scale")
        away.fromValue = 1
        away.toValue = 1.3
        away.beginTime = CACurrentMediaTime() + Self.length
        away.duration = 0.35
        away.fillMode = .forwards
        away.isRemovedOnCompletion = false
        away.timingFunction = CAMediaTimingFunction(name: .easeIn)
        content.add(away, forKey: "away")
        for line in lines {
            let draw = CABasicAnimation(keyPath: "transform.scale.x")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = 0.35
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            line.add(draw, forKey: "draw")
        }
        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = 10
        pulse.toValue = 28
        pulse.duration = 0.45
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        title.add(pulse, forKey: "pulse")
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0.25, 1]
        blink.duration = 0.5
        blink.repeatCount = .infinity
        blink.beginTime = CACurrentMediaTime() + 0.45
        subtitle.add(blink, forKey: "blink")
    }

    /// The title in heavy capitals, white edged in `glow` and glowing in
    /// it, as large as fits in `width` by `height`.
    private static func titleText(_ text: String, glow: NSColor, width: CGFloat, height: CGFloat) -> [NSAttributedString] {
        var size: CGFloat = 104
        func styled(_ size: CGFloat, blur: CGFloat, shadow: NSColor) -> NSAttributedString {
            let glowing = NSShadow()
            glowing.shadowColor = shadow
            glowing.shadowBlurRadius = blur
            glowing.shadowOffset = .zero
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .black),
                .foregroundColor: NSColor.white,
                .strokeColor: glow,
                .strokeWidth: -3.5,
                .kern: size * 0.04,
                .shadow: glowing,
            ])
        }
        while size > 28 {
            let measured = styled(size, blur: 0, shadow: .clear).size()
            if measured.width <= width, measured.height <= height { break }
            size -= 4
        }
        return [styled(size, blur: size * 0.4, shadow: glow), styled(size, blur: size * 0.12, shadow: .white)]
    }

    private static func subtitleText(_ text: String, glow: NSColor) -> [NSAttributedString] {
        let glowing = NSShadow()
        glowing.shadowColor = glow
        glowing.shadowBlurRadius = 8
        glowing.shadowOffset = .zero
        return [NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: glow.blended(withFraction: 0.45, of: .white) ?? glow,
            .kern: 6,
            .shadow: glowing,
        ])]
    }

    /// A layer showing `passes` drawn over one another, with room around
    /// them for their glow.
    private static func textLayer(_ passes: [NSAttributedString], scale: CGFloat) -> CALayer {
        let text = passes.first?.size() ?? .zero
        let pad: CGFloat = 48
        let size = CGSize(width: ceil(text.width + pad * 2), height: ceil(text.height + pad * 2))
        let image = NSImage(size: size, flipped: false) { _ in
            for pass in passes { pass.draw(at: NSPoint(x: pad, y: pad)) }
            return true
        }
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = image.recommendedLayerContentsScale(scale)
        layer.contents = image.layerContents(forContentsScale: layer.contentsScale)
        return layer
    }
}

/// Passive gamer cheat detector.
final class NotchMascotCheats {
    static let shared = NotchMascotCheats()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var silenceWorkItem: DispatchWorkItem?

    let engine = NotchMascotCheatEngine()

    private init() {}

    func start() {
        if Thread.isMainThread {
            startListening()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startListening()
            }
        }
    }

    func stop() {
        if Thread.isMainThread {
            stopListening()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopListening()
            }
        }
    }

    private func startListening() {
        guard globalMonitor == nil && localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func stopListening() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        engine.reset()
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return
        }

        let char = event.charactersIgnoringModifiers?.lowercased().first
        if let cheat = engine.receive(keyCode: event.keyCode, character: char, modifiers: flags, timestamp: event.timestamp) {
            silenceWorkItem?.cancel()
            silenceWorkItem = nil
            DispatchQueue.main.async {
                NotchMascotCheatBanner.shared.show(cheat: cheat)
            }
        } else {
            scheduleSilenceReset()
        }
    }

    private func scheduleSilenceReset() {
        silenceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.engine.reset()
        }
        silenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
