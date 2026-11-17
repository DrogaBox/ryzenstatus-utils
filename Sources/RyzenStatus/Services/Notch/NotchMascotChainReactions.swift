// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What each one makes of what reaches it in a chain: the plain way anyone
/// takes it, the way some figures take it, and (in
/// `NotchMascotChainReactions+Items.swift`) what every thing worn makes
/// of it. Pure data, so every rule is tested.
enum NotchMascotChainReactions {
    typealias Reaction = NotchMascotChainReaction

    // MARK: Luck

    /// A soaked one shakes itself off onto the next this often.
    static let splashChance = 0.3
    /// A shock goes on through a plain one this often.
    static let shockChance = 0.4
    /// A sneeze makes the next one sneeze this often.
    static let sneezeChance = 0.7
    /// A laugh is catching this often.
    static let laughChance = 0.6
    /// A hypnotised one hypnotises the next this often.
    static let hypnoChance = 0.5
    /// A dancer gets the next one dancing this often.
    static let danceChance = 0.25

    // MARK: The plain way

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// How anyone takes `stimulus` with nothing to make anything else of it.
    static func plainReaction(to stimulus: NotchMascotStimulus, random: () -> Double) -> Reaction {
        let id = "plain.\(stimulus.rawValue)"
        switch stimulus {
        case .fire:
            // A hot foot: hops about, smoke off its tail.
            return Reaction(id, .plain, [(0, .react(.panic)), (0.1, .marker("HOT!")), (0.2, .move(.hop)),
                                         (0.4, .burst(.smoke)), (0.7, .move(.hop)), (1.1, .face(.terrified, 1.2))])
        case .water:
            let pass = random() < splashChance
            return Reaction(id, .plain, [(0, .react(.surprised)), (0.2, .symbol("•", .blue, count: 4)),
                                         (0.6, .move(.shiver)), (1.2, .face(.disgusted, 1.2))],
                            emits: pass ? .water : nil)
        case .wind:
            return Reaction(id, .plain, [(0, .react(.surprised)), (0.1, .move(.slip)), (0.4, .symbol("~", .white, count: 3)),
                                         (1.0, .face(.dizzy, 1.2))])
        case .shock:
            let pass = random() < shockChance
            return Reaction(id, .plain, [(0, .lightning), (0.05, .react(.flash)), (0.3, .move(.shiver)),
                                         (0.8, .face(.dizzy, 1.4)), (0.9, .emote(.curse))],
                            emits: pass ? .shock : nil)
        case .frost:
            // Frozen stiff a while, then a shiver to thaw.
            return Reaction(id, .plain, [(0, .face(.surprised, 1.8)), (0.1, .symbol("❄", .blue, count: 3)),
                                         (0.2, .burst(.sparkles)), (1.9, .move(.shiver)), (2.0, .marker("BRRR"))])
        case .light:
            return Reaction(id, .plain, [(0, .react(.flash)), (0.2, .face(.dizzy, 1.2)), (0.4, .symbol("✦", .gold, count: 2)),
                                         (1.3, .emote(.question))])
        case .sound:
            let pass = random() < danceChance
            return Reaction(id, .plain, [(0, .react(.groove)), (0.2, .symbol("♪", .gold, count: 2)), (0.6, .move(.spin)),
                                         (1.4, .face(.happy, 1.0))],
                            emits: pass ? .sound : nil)
        case .pepper:
            // Ah… ah… ACHOO, and it sails back with the force of it.
            let pass = random() < sneezeChance
            return Reaction(id, .plain, [(0, .face(.thinking, 0.8)), (0.3, .marker("AH...")), (0.9, .marker("ACHOO!")),
                                         (0.9, .move(.slip)), (1.0, .burst(.smoke)), (1.4, .face(.embarrassed, 1.0))],
                            emits: pass ? .pepper : nil)
        case .impact:
            return Reaction(id, .plain, [(0, .react(.surprised)), (0.05, .marker("BONK")), (0.2, .symbol("★", .gold, count: 3)),
                                         (0.4, .face(.dizzy, 1.6))])
        case .magnet:
            // Pulled toward the magnet a step, feet sliding.
            return Reaction(id, .plain, [(0, .react(.surprised)), (0.1, .move(.charge)), (0.6, .marker("CLANK")),
                                         (0.8, .face(.confused, 1.2))])
        case .sweet:
            return Reaction(id, .plain, [(0, .react(.perk)), (0.2, .face(.greedy, 1.4)), (0.4, .symbol("~", .pink, count: 3)),
                                         (1.2, .move(.hop)), (1.4, .emote(.heart))])
        case .goo:
            // Stuck to the floor, and tugging to get free.
            return Reaction(id, .plain, [(0, .marker("SPLAT")), (0.1, .face(.disgusted, 1.8)), (0.4, .move(.shiver)),
                                         (1.2, .move(.shiver)), (2.0, .move(.hop))])
        case .hypno:
            let pass = random() < hypnoChance
            return Reaction(id, .plain, [(0, .face(.dizzy, 2.2)), (0.2, .emote(.thought("@"))), (0.5, .move(.sneak)),
                                         (1.5, .marker("OBEY")), (2.0, .react(.wakeUp))],
                            emits: pass ? .hypno : nil)
        case .tickle:
            let pass = random() < laughChance
            return Reaction(id, .plain, [(0, .react(.celebrate)), (0.1, .marker("HAHA")), (0.3, .move(.spin)),
                                         (0.8, .face(.happy, 1.6)), (1.0, .symbol("♪", .pink, count: 2))],
                            emits: pass ? .tickle : nil)
        }
    }

    // MARK: Figures

    /// The figures that machines are made of.
    static let machines: Set<NotchMascotStyle> = [.robot, .chip, .android, .hologram]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// How some figures take a stimulus their own way, before the plain
    /// way: fire feeds a dragon or a phoenix, frost delights a penguin,
    /// light sends a cat or a dog after the dot, a spark overcharges a
    /// machine, water is a treat for the pond's own, a bonk goes through a
    /// ghost and into a slime, and a fan blows a spark on as a gust.
    static func styleReaction(_ style: NotchMascotStyle, to stimulus: NotchMascotStimulus,
                              random: () -> Double) -> Reaction? {
        let id = "\(style.rawValue).\(stimulus.rawValue)"
        switch (style, stimulus) {
        case (.dragon, .fire), (.phoenix, .fire):
            // It swallows the fire and breathes it on, bigger.
            return Reaction(id, .style(style), [(0, .face(.greedy, 0.8)), (0.2, .marker("GULP")), (0.6, .react(.ready)),
                                                (0.8, .burst(.smoke)), (0.9, .fling(.fireball, back: false)),
                                                (1.1, .face(.smug, 1.2))], emits: .fire)
        case (.penguin, .frost):
            return Reaction(id, .style(style), [(0, .react(.celebrate)), (0.2, .move(.slip)), (0.6, .symbol("❄", .white, count: 3)),
                                                (1.2, .marker("COOL!")), (1.4, .face(.love, 1.4))])
        case (.penguin, .fire), (.swan, .fire):
            return Reaction(id, .style(style), [(0, .react(.panic)), (0.2, .marker("MELTING")), (0.4, .move(.hop)),
                                                (0.8, .symbol("•", .blue, count: 3)), (1.2, .face(.crying, 1.4))])
        case (.cat, .light), (.dog, .light):
            // After the dot, round and round, and pounce.
            return Reaction(id, .style(style), [(0, .react(.perk)), (0.2, .move(.charge)), (0.8, .move(.spin)),
                                                (1.4, .move(.highJump)), (1.8, .marker("GOT IT?")), (2.0, .face(.confused, 1.2))])
        case (.robot, .shock), (.chip, .shock), (.android, .shock), (.hologram, .shock):
            return Reaction(id, .style(style), [(0, .lightning), (0.1, .react(.flash)), (0.3, .marker("OVERCLOCK")),
                                                (0.5, .sparks), (0.7, .move(.stomp)), (1.0, .face(.starstruck, 1.2))],
                            emits: .shock)
        case (.robot, .water), (.chip, .water), (.android, .water):
            return Reaction(id, .style(style), [(0, .react(.panic)), (0.2, .sparks), (0.3, .marker("ERROR")),
                                                (0.5, .move(.shiver)), (1.1, .face(.dizzy, 1.4))], emits: .shock)
        case (.robot, .magnet), (.chip, .magnet), (.android, .magnet):
            return Reaction(id, .style(style), [(0, .react(.surprised)), (0.1, .move(.charge)), (0.5, .marker("STUCK")),
                                                (0.7, .move(.shiver)), (1.4, .face(.embarrassed, 1.2))])
        case (.axolotl, .water), (.frog, .water), (.capybara, .water), (.swan, .water), (.penguin, .water):
            return Reaction(id, .style(style), [(0, .react(.celebrate)), (0.2, .symbol("○", .blue, count: 3)), (0.6, .move(.spin)),
                                                (1.2, .marker("SPA")), (1.4, .face(.love, 1.4))])
        case (.ghost, .impact):
            // It goes right through.
            return Reaction(id, .style(style), [(0, .face(.smug, 1.2)), (0.1, .marker("MISS")), (0.3, .move(.float)),
                                                (1.0, .emote(.ellipsis))])
        case (.slime, .impact), (.slime, .goo):
            return Reaction(id, .style(style), [(0, .move(.shiver)), (0.2, .marker("BLORP")), (0.4, .grow(4)),
                                                (0.8, .face(.happy, 1.2))])
        case (.fan, .shock), (.fan, .wind):
            return Reaction(id, .style(style), [(0, .react(.ready)), (0.1, .move(.spin)), (0.5, .symbol("~", .white, count: 3)),
                                                (0.9, .marker("WHIRR"))], emits: .wind)
        case (.devourer, .sweet), (.mouse, .sweet):
            return Reaction(id, .style(style), [(0, .react(.perk)), (0.1, .move(.charge)), (0.6, .face(.greedy, 1.0)),
                                                (0.9, .marker("NOM NOM")), (1.2, .burst(.hearts))])
        case (.kitsune, .fire):
            return Reaction(id, .style(style), [(0, .react(.ready)), (0.2, .burst(.magic)), (0.4, .marker("FOXFIRE")),
                                                (0.6, .fling(.fireball, back: false))], emits: .fire)
        case (.ghost, .light):
            return Reaction(id, .style(style), [(0, .react(.panic)), (0.1, .marker("EEK")), (0.3, .move(.backflip)),
                                                (1.0, .hide(4)), (1.2, .face(.terrified, 1.2))])
        case (.capybara, _) where stimulus == .pepper || stimulus == .tickle || stimulus == .hypno:
            // Nothing moves a capybara.
            return Reaction(id, .style(style), [(0, .react(.relax)), (0.4, .marker("ZEN")), (0.6, .emote(.ellipsis))])
        default:
            return nil
        }
    }

    /// What a figure throws to start a chain with nothing in hand: a
    /// dragon or a phoenix breathes fire, the fan blows, the penguin flings
    /// a snowball, a machine sparks and the kitsune sends foxfire.
    static func styleEmission(_ style: NotchMascotStyle) -> NotchMascotChainEmission? {
        switch style {
        case .dragon, .phoenix, .kitsune:
            return NotchMascotChainEmission(.fire, [(0, .react(.ready)), (0.3, .burst(.smoke))])
        case .fan:
            return NotchMascotChainEmission(.wind, [(0, .move(.spin)), (0.3, .symbol("~", .white, count: 2))])
        case .penguin:
            return NotchMascotChainEmission(.frost, [(0, .react(.ready)), (0.2, .juggle(.snowball))])
        case .robot, .chip, .android:
            return NotchMascotChainEmission(.shock, [(0, .react(.ready)), (0.3, .sparks)])
        default:
            return nil
        }
    }
}
