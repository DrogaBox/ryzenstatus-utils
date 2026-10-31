// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// A row of a companion's sprite sheet: what it is doing.
///
/// The sheets follow the Codex pet layout, eight columns of 192×208 cells
/// with one state to a row in this order, so a figure drawn for it plays here
/// as its author saw it, and one of ours plays there.
enum NotchMascotSpriteState: Int, CaseIterable {
    case idle
    case runRight
    case runLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
}

/// One frame of a row: its column, and how long it holds.
struct NotchMascotSpriteFrame: Equatable {
    let column: Int
    let duration: TimeInterval
}

/// A companion drawn from a sprite sheet rather than shapes.
struct NotchMascotSpriteSheet: Equatable {
    static let columns = 8
    static let cellWidth = 192
    static let cellHeight = 208

    /// The PNG in the app's `Images` resources.
    let resource: String
    /// How many frames each row holds, in `NotchMascotSpriteState` order.
    let frameCounts: [Int]
    /// The part of a cell the figure covers in any frame, in pixels from the
    /// cell's top left corner, so every frame is cut and placed alike.
    let figure: CGRect
    /// The figure's top, for a companion drawn small: head and hands, where
    /// the island's few points show what it is and what it does. Nil keeps
    /// the whole figure at any size.
    var bust: CGRect? = nil
    /// How tall it stands beside the others on the desktop, Cristóbal's
    /// height being 1. Each fills its own place in the island.
    var stature: CGFloat = 1
    /// The rows that say what it is about, where a figure's drawing says
    /// something else in the row the layout names: the White Rabbit's
    /// review row holds up "done, take a look", so it thinks under its
    /// "thinking" sign instead.
    var thinking: NotchMascotSpriteState = .review
    /// Looking about, or peeking out.
    var looking: NotchMascotSpriteState = .review
    /// Yawning, or hushed as the microphone mutes.
    var waiting: NotchMascotSpriteState = .waiting
    /// A sign it holds up, lettered in the sheet in Spanish and written
    /// anew in any other language.
    var signs: NotchMascotSpriteSigns? = nil

    /// Drawn shorter than this, in points, it shows its bust.
    static let bustBelow: CGFloat = 32

    /// The part of each cell to show for a companion `size` points tall.
    func framing(for size: CGFloat) -> CGRect {
        size < Self.bustBelow ? bust ?? figure : figure
    }

    /// The frames of `state`, timed so a row's last frame holds a little
    /// longer, as the beat before it starts over.
    func frames(for state: NotchMascotSpriteState) -> [NotchMascotSpriteFrame] {
        let count = max(1, frameCounts[safe: state.rawValue] ?? 1)
        let (step, last) = Self.timing(state)
        return (0..<count).map { NotchMascotSpriteFrame(column: $0, duration: $0 == count - 1 ? last : step) }
    }

    /// How long one pass of `state`'s row lasts.
    func cycle(of state: NotchMascotSpriteState) -> TimeInterval {
        frames(for: state).reduce(0) { $0 + $1.duration }
    }

    /// Seconds per frame, and for the last one.
    static func timing(_ state: NotchMascotSpriteState) -> (step: TimeInterval, last: TimeInterval) {
        switch state {
        case .idle: return (0.16, 0.32)
        case .runRight, .runLeft, .running: return (0.12, 0.22)
        case .waving, .jumping: return (0.14, 0.28)
        case .failed: return (0.14, 0.24)
        case .waiting: return (0.15, 0.26)
        case .review: return (0.15, 0.28)
        }
    }

    /// Where `state`'s frame `column` lies in the whole sheet, in pixels from
    /// its top left corner: `framing`'s part of that cell, the whole figure
    /// unless told otherwise.
    func crop(_ state: NotchMascotSpriteState, column: Int, framing: CGRect? = nil) -> CGRect {
        (framing ?? figure).offsetBy(dx: CGFloat(column * Self.cellWidth), dy: CGFloat(state.rawValue * Self.cellHeight))
    }

    /// The figure's width for a height of 1.
    var aspect: CGFloat { Self.aspect(of: figure) }

    /// `framing`'s width for a height of 1.
    static func aspect(of framing: CGRect) -> CGFloat {
        framing.height > 0 ? framing.width / framing.height : 1
    }

    /// Cristóbal Sincronía, coffee in hand, from the comic of the same name.
    /// Small, he shows down to his mug.
    static let cristobal = NotchMascotSpriteSheet(resource: "pet-cristobal", frameCounts: [6, 8, 8, 4, 5, 8, 6, 6, 6],
                                                  figure: CGRect(x: 34, y: 2, width: 123, height: 201),
                                                  bust: CGRect(x: 34, y: 2, width: 123, height: 128))
    /// The White Rabbit from the same comic, with its apron and cardboard
    /// sign, half Cristóbal's height. It stays whole at any size: the sign
    /// is what it says, and it holds it at its waist or over its head.
    static let whiteRabbit = NotchMascotSpriteSheet(resource: "pet-conejo-blanco", frameCounts: [6, 8, 8, 4, 5, 8, 6, 6, 6],
                                                    figure: CGRect(x: 17, y: 2, width: 157, height: 201),
                                                    stature: 0.5, thinking: .waiting, looking: .idle, waiting: .idle,
                                                    signs: .whiteRabbit)
}

/// The sign a sprite figure holds up: the same sheet with its signs left
/// blank, and where the sign's face is in every frame, so the app writes
/// the words in the language the Mac speaks.
struct NotchMascotSpriteSigns: Equatable {
    /// The blank sheet in the app's `Images` resources.
    let resource: String
    /// The sign's face in each frame, in pixels from its cell's top left,
    /// row by row in `NotchMascotSpriteState` order.
    let boxes: [[CGRect]]

    /// The sheet's own lettering is Spanish; every other language is written.
    static func writes(_ language: AppLanguage) -> Bool { language != .es }

    /// The face of `state`'s sign in frame `column`, or nil without one.
    func box(_ state: NotchMascotSpriteState, column: Int) -> CGRect? {
        boxes[safe: state.rawValue]?[safe: column]
    }

    init(resource: String, boxes: [[(Int, Int, Int, Int)]]) {
        self.resource = resource
        self.boxes = boxes.map { $0.map { CGRect(x: $0.0, y: $0.1, width: $0.2, height: $0.3) } }
    }

    /// The White Rabbit's cardboard sign, measured off its sheet.
    static let whiteRabbit = NotchMascotSpriteSigns(resource: "pet-conejo-blanco-signless", boxes: [
        // idle
        [(57, 126, 77, 37), (58, 126, 76, 37), (57, 126, 76, 37), (57, 126, 77, 37), (58, 126, 76, 37), (57, 126, 77, 37)],
        // runRight
        [(92, 120, 71, 38), (92, 117, 71, 38), (92, 113, 71, 37), (92, 113, 69, 36), (92, 113, 71, 37), (92, 113, 71, 37), (92, 113, 71, 37), (92, 115, 69, 36)],
        // runLeft
        [(29, 118, 72, 38), (29, 118, 72, 38), (29, 118, 72, 37), (29, 118, 72, 38), (31, 118, 71, 35), (29, 119, 72, 36), (29, 118, 73, 38), (29, 120, 72, 36)],
        // waving
        [(67, 126, 84, 36), (59, 126, 85, 36), (67, 126, 83, 36), (61, 126, 83, 36)],
        // jumping
        [(58, 121, 75, 37), (58, 102, 75, 37), (59, 5, 74, 37), (59, 5, 75, 36), (59, 6, 75, 38)],
        // failed
        [(46, 107, 104, 50), (45, 107, 106, 50), (42, 107, 109, 50), (43, 107, 107, 50), (44, 107, 106, 50), (43, 107, 107, 50), (43, 107, 107, 50), (41, 107, 109, 50)],
        // waiting
        [(39, 151, 129, 46), (40, 151, 129, 46), (39, 151, 129, 46), (41, 151, 127, 48), (40, 151, 129, 48), (39, 151, 129, 48)],
        // running
        [(70, 106, 97, 55), (66, 106, 97, 55), (67, 106, 97, 55), (70, 106, 97, 55), (68, 106, 95, 55), (66, 106, 97, 55)],
        // review
        [(29, 10, 134, 57), (28, 10, 134, 57), (31, 10, 132, 57), (29, 10, 133, 57), (29, 10, 133, 57), (29, 10, 134, 57)],
    ])
}

extension NotchMascotStyle {
    /// The sheet a sprite companion is drawn from. None is any more: the
    /// comic's two are drawn with shapes like the rest, so they take a
    /// colour and wear items; the sheets stay for a figure that comes whole.
    var sprite: NotchMascotSpriteSheet? { nil }

    /// Drawn with shapes, so the palette colours it.
    var takesPalette: Bool { sprite == nil }

    /// Drawn companions wear accessories; sprite companions are complete figures.
    var takesAccessory: Bool { sprite == nil }
}

/// What a sprite companion plays for the moods and reactions a drawn one
/// shows with its face.
enum NotchMascotSpriteChoreography {
    /// The row `sheet`'s figure keeps for a lasting mood, and how fast: a
    /// doze slows its idle to half.
    static func loop(for mood: NotchMascotMood, in sheet: NotchMascotSpriteSheet) -> (state: NotchMascotSpriteState, speed: Float) {
        switch mood {
        case .idle, .alert, .wink: return (.idle, 1)
        case .happy, .love: return (.waving, 1)
        case .sleepy: return (.idle, 0.45)
        case .determined: return (.running, 1)
        case .surprised: return (.jumping, 1)
        case .searching, .thinking: return (sheet.thinking, 1)
        case .confused: return (.failed, 1)
        }
    }

    /// The row a reaction plays over its mood, or nil to keep the mood's,
    /// as the camera flash, a blink, does. Something finished well plays
    /// the review row, as the layout means it: done, take a look.
    static func state(for reaction: NotchMascotReaction, in sheet: NotchMascotSpriteSheet) -> NotchMascotSpriteState? {
        switch reaction {
        case .celebrate: return .review
        case .perk, .bounce, .wakeUp, .surprised, .groove: return .jumping
        case .love, .wave: return .waving
        case .confused, .panic: return .failed
        case .yawn, .hush: return sheet.waiting
        case .ready, .sweat: return .running
        case .peek, .lookAround: return sheet.looking
        case .flash, .relax, .sip: return nil
        }
    }

    /// The row for moving `dx` points: running the way it goes, or its idle
    /// when it hardly moves.
    static func walking(dx: CGFloat) -> NotchMascotSpriteState {
        abs(dx) < 0.5 ? .idle : dx > 0 ? .runRight : .runLeft
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
