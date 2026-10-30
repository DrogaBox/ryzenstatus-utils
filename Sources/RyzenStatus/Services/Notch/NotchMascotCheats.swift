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
        )
    ]

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

/// Visual pill view with retro dark styling, glowing border and glowing text.
final class NotchMascotCheatPillView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupView()
    }

    private func setupView() {
        guard let layer else { return }
        layer.masksToBounds = false
        layer.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.94).cgColor
        layer.borderColor = NSColor(red: 0.3, green: 0.95, blue: 0.7, alpha: 0.4).cgColor
        layer.borderWidth = 1.2
        layer.shadowColor = NSColor(red: 0.1, green: 0.9, blue: 0.6, alpha: 0.45).cgColor
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.85
        layer.shadowOffset = .zero

        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14)
        ])
    }

    func configure(text: String, cornerRadius: CGFloat) {
        layer?.cornerRadius = cornerRadius
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(red: 0.1, green: 0.9, blue: 0.6, alpha: 0.7)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = .zero

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor(red: 0.88, green: 1.0, blue: 0.94, alpha: 1.0),
                .shadow: shadow
            ]
        )
        label.attributedStringValue = attributed
    }
}

/// Visual toast presenter for cheat code discoveries.
@MainActor
final class NotchMascotCheatToast {
    static let shared = NotchMascotCheatToast()

    private var currentPanel: NotchMascotCheatPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(cheat: NotchMascotCheat) {
        // Audio sound cue
        NotchMascotSound.play(cheat.soundEffect)

        // Mascot celebration if active
        NotchService.shared.celebrateCheat()
        if cheat == .xyzzy { NotchService.shared.summonMascotEncounter() }
        if cheat == .plugh { NotchService.shared.previewMascotOccasion() }

        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if let existing = currentPanel {
            existing.orderOut(nil)
            existing.close()
            currentPanel = nil
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.frame

        let badgeText = cheat.badge
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: 0.25, green: 1.0, blue: 0.75, alpha: 1.0)
        ]
        let textSize = (badgeText as NSString).size(withAttributes: textAttributes)
        let pillWidth = max(160, ceil(textSize.width) + 36)
        let pillHeight: CGFloat = 38
        let cornerRadius = pillHeight / 2

        let targetX = screenFrame.minX + (screenFrame.width - pillWidth) / 2
        let targetY = screenFrame.maxY - 85 - pillHeight
        let startY = targetY - 15

        let startRect = NSRect(x: targetX, y: startY, width: pillWidth, height: pillHeight)
        let targetRect = NSRect(x: targetX, y: targetY, width: pillWidth, height: pillHeight)

        let panel = NotchMascotCheatPanel(
            contentRect: startRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.setAccessibilityElement(false)

        let pillView = NotchMascotCheatPillView(frame: NSRect(origin: .zero, size: CGSize(width: pillWidth, height: pillHeight)))
        pillView.configure(text: badgeText, cornerRadius: cornerRadius)
        panel.contentView = pillView

        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
        self.currentPanel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 1.0
        }

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                DispatchQueue.main.async { [weak self, weak panel] in
                    guard let panel else { return }
                    panel.orderOut(nil)
                    panel.close()
                    if self?.currentPanel === panel {
                        self?.currentPanel = nil
                    }
                }
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + 1.8, execute: work)
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
                NotchMascotCheatToast.shared.show(cheat: cheat)
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
