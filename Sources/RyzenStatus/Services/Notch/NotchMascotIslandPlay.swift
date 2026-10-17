// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import QuartzCore

/// What the companion and its friend get up to together while both rest in
/// the closed island. They cannot walk over to each other there, so they
/// play across the room between them: they wave, toss hearts, stars and
/// notes back and forth, rally a spark, copy each other, dance and doze off,
/// and what each one wears brings a play of its own: a magic trick from the
/// top hat, a bow to the crown, a snowball fight from the beanie. Pure, so
/// every rule is tested without a window.
struct NotchMascotIslandPlay: Equatable {
    let kind: Kind
    let beats: [Beat]

    enum Kind: Hashable {
        case greet, toss, rally, mimic, dance, doze, peekaboo
        /// The play what one of them wears brings.
        case item(NotchMascotAccessory)
    }

    /// What flies from one to the other.
    enum Thing: Equatable { case heart, star, note, spark, snowball, flower, cookie, coin, ball }

    /// A little burst over one of them.
    enum Burst: Equatable { case confetti, sparkles, hearts, magic }

    struct Flight: Equatable {
        var thing: Thing
        /// From the companion to its friend, or back.
        var fromLeader: Bool
        var duration: TimeInterval = NotchMascotIslandPlay.flightLength
        /// It drops short of the other instead of reaching it.
        var falls = false
    }

    struct BurstAt: Equatable {
        var burst: Burst
        var onLeader: Bool
    }

    /// What each of them does `at` seconds in, and what flies or bursts.
    struct Beat: Equatable {
        var at: TimeInterval
        var leader: NotchMascotReaction? = nil
        var friend: NotchMascotReaction? = nil
        var flight: Flight? = nil
        var burst: BurstAt? = nil
    }

    /// How long it lasts: until its last beat has played out.
    var length: TimeInterval {
        beats.map { beat in
            beat.at + max(beat.leader?.length ?? 0, beat.friend?.length ?? 0,
                          beat.flight?.duration ?? 0, beat.burst == nil ? 0 : Self.burstLength)
        }.max() ?? 0
    }

    // MARK: When

    /// At least this long between two plays, and before the first one.
    static let interval: TimeInterval = 28
    /// Once one is due, the share of chances it is taken, so it comes when
    /// it is not quite expected.
    static let chance = 0.6
    /// How many plays back still count as just done.
    static let memory = 4
    static let flightLength: TimeInterval = 0.85
    static let burstLength: TimeInterval = 1.0

    /// What they know as they might start one.
    struct Context: Equatable {
        /// Since the last play, or since they came to rest together.
        var since: TimeInterval
        /// A song is playing.
        var music: Bool
        /// The hour of the day, 0 to 23.
        var hour: Int
        /// The plays they did lately, the latest last.
        var recent: [Kind] = []
        var leaderWears: NotchMascotAccessory = .none
        var friendWears: NotchMascotAccessory = .none
    }

    /// The items worn that bring a play, with whether the companion wears it.
    static func itemPlays(in context: Context) -> [(item: NotchMascotAccessory, byLeader: Bool)] {
        var items: [(NotchMascotAccessory, Bool)] = []
        if context.leaderWears != .none { items.append((context.leaderWears, true)) }
        if context.friendWears != .none, context.friendWears != context.leaderWears {
            items.append((context.friendWears, false))
        }
        return items
    }

    /// How much each play is wanted now: music calls for dancing and passing
    /// notes, the small hours for dozing, what they wear for its own play;
    /// the play just done is never next, and one done lately is less likely.
    static func weight(of kind: Kind, in context: Context) -> Double {
        if context.recent.last == kind { return 0 }
        let night = context.hour >= 23 || context.hour < 6
        var weight: Double
        switch kind {
        case .greet: weight = 2
        case .toss: weight = 2.5
        case .rally: weight = 1.5
        case .mimic: weight = 1.2
        case .dance: weight = context.music ? 5 : 0
        case .doze: weight = night ? 4 : 0.3
        case .peekaboo: weight = 1.2
        case .item(let item):
            guard itemPlays(in: context).contains(where: { $0.item == item }) else { return 0 }
            weight = item == .headphones && context.music ? 5 : 3
        }
        if context.recent.suffix(memory).contains(kind) { weight *= 0.3 }
        return weight
    }

    /// The play they start now, if any. `random` gives numbers in 0..<1.
    static func next(in context: Context, random: () -> Double) -> NotchMascotIslandPlay? {
        guard context.since >= interval, random() < chance else { return nil }
        let kinds: [Kind] = [.greet, .toss, .rally, .mimic, .dance, .doze, .peekaboo]
            + itemPlays(in: context).map { .item($0.item) }
        let weights = kinds.map { ($0, weight(of: $0, in: context)) }.filter { $0.1 > 0 }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = random() * total
        for (kind, weight) in weights {
            if roll < weight { return play(kind, in: context, random: random) }
            roll -= weight
        }
        return weights.last.map { play($0.0, in: context, random: random) }
    }

    // MARK: How

    /// `kind` with its twist: who starts it, what flies, how it ends.
    static func play(_ kind: Kind, in context: Context, random: () -> Double) -> NotchMascotIslandPlay {
        func pick<T>(_ options: [T]) -> T { options[min(options.count - 1, Int(random() * Double(options.count)))] }
        func count(_ range: ClosedRange<Int>) -> Int { pick(Array(range)) }
        let byLeader = random() < 0.5
        var score = Score(byLeader: byLeader)
        switch kind {
        case .greet:
            score.act(0, starter: .wave)
            score.act(1.0, other: pick([.wave, .perk, .love] as [NotchMascotReaction]))

        case .toss:
            let thing: Thing = context.music && random() < 0.5 ? .note : pick([Thing.heart, .star, .spark])
            // A heart is always caught.
            let caught = thing == .heart || random() < 0.75
            let windup: NotchMascotReaction
            let catches: NotchMascotReaction
            switch thing {
            case .heart: (windup, catches) = (.love, .love)
            case .star: (windup, catches) = (.ready, .celebrate)
            case .note: (windup, catches) = (.groove, .groove)
            default: (windup, catches) = (.perk, .bounce)
            }
            score.act(0, starter: windup)
            score.toss(0.35, thing, fromStarter: true, falls: !caught)
            let lands = 0.35 + flightLength
            if caught {
                score.act(lands, other: catches)
            } else {
                score.act(lands, other: .surprised)
                score.act(lands + 0.5, starter: .confused)
            }

        case .rally:
            let volleys = count(2...4)
            score.act(0, starter: .ready)
            for volley in 0..<volleys {
                let fromStarter = volley % 2 == 0
                let start = 0.3 + Double(volley) * 1.05
                let last = volley == volleys - 1
                score.toss(start, .spark, fromStarter: fromStarter, falls: last)
                let lands = start + flightLength
                if !last {
                    score.act(lands - 0.1, starter: fromStarter ? nil : .perk, other: fromStarter ? .perk : nil)
                } else {
                    // The one it was sent to misses it; the sender cheers.
                    score.act(lands, starter: fromStarter ? .celebrate : .surprised,
                              other: fromStarter ? .surprised : .celebrate)
                }
            }

        case .mimic:
            // The companion leads; its friend copies until it slips.
            score = Score(byLeader: true)
            let pool: [NotchMascotReaction] = [.wave, .bounce, .perk, .lookAround, .groove, .ready]
            let rounds = count(2...4)
            var moves: [NotchMascotReaction] = []
            for _ in 0..<rounds {
                let options = pool.filter { $0 != moves.last }
                moves.append(pick(options))
            }
            let slip = pick(pool.filter { $0 != moves.last })
            for (round, move) in moves.enumerated() {
                let at = Double(round) * 1.9
                score.act(at, starter: move)
                score.act(at + 0.95, other: round == rounds - 1 ? slip : move)
            }
            score.act(Double(rounds) * 1.9 + 0.2, starter: .celebrate, other: .confused)

        case .dance:
            score.act(0, starter: .groove)
            score.act(1.7, other: .groove)
            score.act(3.4, starter: .groove, other: .groove)
            score.act(5.1, starter: .celebrate, other: .celebrate)

        case .doze:
            score.act(0, starter: .yawn)
            score.act(1.4, other: .yawn)
            score.act(2.9, starter: .hush, other: .hush)

        case .peekaboo:
            score.act(0, starter: .hush)
            score.act(1.0, other: .lookAround)
            score.act(2.6, starter: .bounce, other: .surprised)
            score.act(3.9, starter: .celebrate, other: .celebrate)

        case .item(let item):
            let wearer = itemPlays(in: context).first { $0.item == item }?.byLeader ?? byLeader
            score = Score(byLeader: wearer)
            itemPlay(item, into: &score, random: random)
        }
        return NotchMascotIslandPlay(kind: kind, beats: score.beats)
    }

    /// The play `item` brings, started by the one wearing it.
    private static func itemPlay(_ item: NotchMascotAccessory, into score: inout Score, random: () -> Double) {
        let lands = flightLength
        switch item {
        case .topHat:
            // A magic trick: a star out of the hat.
            score.act(0, starter: .ready)
            score.burst(0.5, .magic, onStarter: true)
            score.toss(0.8, .star, fromStarter: true)
            score.act(0.8 + lands, other: .celebrate)
            score.burst(0.8 + lands, .sparkles, onStarter: false)
        case .crown:
            // A royal nod, a bow back, and a blessing.
            score.act(0, starter: .ready)
            score.act(0.9, other: .hush)
            score.act(2.0, starter: .love)
            score.burst(2.0, .sparkles, onStarter: false)
        case .headphones:
            // It shares the beat.
            score.act(0, starter: .groove)
            score.toss(0.4, .note, fromStarter: true)
            score.act(0.4 + lands, other: .groove)
            score.toss(2.0, .note, fromStarter: false)
            score.act(2.0 + lands, starter: .groove, other: .groove)
        case .sunglasses:
            // Too cool: a glint, a gasp, and the other plays it cool too.
            score.act(0, starter: .ready)
            score.burst(0.2, .sparkles, onStarter: true)
            score.act(0.9, other: .surprised)
            score.act(1.9, other: .ready)
            score.act(3.0, starter: .bounce, other: .bounce)
        case .glasses:
            // It studies the other, and has an idea.
            score.act(0, starter: .peek)
            score.act(1.3, other: .lookAround)
            score.act(2.6, starter: .surprised)
            score.burst(2.6, .sparkles, onStarter: true)
            score.act(3.4, other: .bounce)
        case .monocle:
            // A long look through the monocle, and a nod of approval.
            score.act(0, starter: .peek)
            score.act(1.3, other: .confused)
            score.act(2.4, starter: .ready)
            score.act(3.2, other: .relax)
        case .flower:
            // It hands over its flower.
            score.act(0, starter: .love)
            score.toss(0.5, .flower, fromStarter: true)
            score.act(0.5 + lands, other: .love)
            score.burst(0.5 + lands, .hearts, onStarter: false)
        case .bow:
            // A twirl and a curtsy.
            score.act(0, starter: .bounce)
            score.act(1.0, other: .love)
            score.burst(1.0, .hearts, onStarter: true)
        case .scarf:
            // Cosy: one settles in, the other yawns, and both feel warm.
            score.act(0, starter: .relax)
            score.act(1.2, other: .yawn)
            score.act(2.5, starter: .love, other: .relax)
        case .beanie:
            // A snowball fight.
            score.act(0, starter: .ready)
            score.toss(0.3, .snowball, fromStarter: true)
            score.act(0.3 + lands, other: .surprised)
            score.burst(0.3 + lands, .sparkles, onStarter: false)
            score.toss(1.9, .snowball, fromStarter: false)
            score.act(1.9 + lands, starter: .surprised)
            score.burst(1.9 + lands, .sparkles, onStarter: true)
            score.act(3.6, starter: .celebrate, other: .celebrate)
        case .cap:
            // A game of catch.
            score.act(0, starter: .ready)
            score.toss(0.3, .ball, fromStarter: true)
            score.act(0.3 + lands, other: .celebrate)
            score.toss(1.7, .ball, fromStarter: false)
            score.act(1.7 + lands, starter: .celebrate)
        case .bowTie:
            // A formal bow, returned.
            score.act(0, starter: .hush)
            score.act(1.0, other: .hush)
            score.act(2.2, starter: .love, other: .love)
        case .cowboyHat:
            // A quickdraw at high noon: whoever draws first wins.
            let starterWins = random() < 0.6
            score.act(0, starter: .ready, other: .ready)
            score.act(1.4, starter: .flash, other: .flash)
            score.toss(1.5, .spark, fromStarter: starterWins)
            score.act(1.5 + lands, starter: starterWins ? .celebrate : .surprised,
                      other: starterWins ? .surprised : .celebrate)
        case .halo:
            // A blessing.
            score.act(0, starter: .love)
            score.burst(0.7, .sparkles, onStarter: false)
            score.act(0.9, other: .relax)
            score.act(2.0, other: .love)
        case .horns:
            // A prank: a spark out of nowhere, and a giggle.
            score.act(0, starter: .peek)
            score.toss(0.6, .spark, fromStarter: true)
            score.act(0.6 + lands, other: .surprised)
            score.act(2.5, starter: .celebrate, other: .confused)
        case .chefHat:
            // Something fresh out of the oven.
            score.act(0, starter: .ready)
            score.burst(0.4, .sparkles, onStarter: true)
            score.toss(0.9, .cookie, fromStarter: true)
            score.act(0.9 + lands, other: .love)
            score.burst(0.9 + lands, .hearts, onStarter: false)
        case .eyePatch:
            // Treasure, shared.
            score.act(0, starter: .peek)
            score.act(1.0, starter: .bounce)
            score.toss(1.2, .coin, fromStarter: true)
            score.act(1.2 + lands, other: .celebrate)
            score.burst(1.2 + lands, .sparkles, onStarter: false)
        case .witchHat:
            // A spell that goes a little wrong.
            score.act(0, starter: .ready)
            score.burst(0.4, .magic, onStarter: true)
            score.toss(0.6, .spark, fromStarter: true)
            score.act(0.6 + lands, other: .surprised)
            score.burst(0.6 + lands, .magic, onStarter: false)
            score.act(2.4, other: .confused)
        case .santaHat:
            // A present.
            score.act(0, starter: .wave)
            score.toss(0.5, .star, fromStarter: true)
            score.act(0.5 + lands, other: .celebrate)
            score.burst(0.5 + lands, .confetti, onStarter: false)
        case .partyHat:
            // A party.
            score.act(0, starter: .celebrate, other: .celebrate)
            score.burst(0, .confetti, onStarter: true)
            score.burst(0.3, .confetti, onStarter: false)
            score.act(1.5, starter: .bounce, other: .bounce)
        case .headband:
            // A gaming match: both focused, then one wins.
            score.act(0, starter: .ready, other: .ready)
            score.act(1.3, starter: .sweat, other: .sweat)
            score.act(2.8, starter: .celebrate, other: .confused)
        case .none:
            score.act(0, starter: .wave)
            score.act(1.0, other: .wave)
        }
    }

    /// Beats written as the one who starts and the other, then laid out as
    /// the companion and its friend.
    private struct Score {
        let byLeader: Bool
        var beats: [Beat] = []

        mutating func act(_ at: TimeInterval, starter: NotchMascotReaction? = nil, other: NotchMascotReaction? = nil) {
            beats.append(Beat(at: at, leader: byLeader ? starter : other, friend: byLeader ? other : starter))
        }

        mutating func toss(_ at: TimeInterval, _ thing: Thing, fromStarter: Bool, falls: Bool = false) {
            beats.append(Beat(at: at, flight: Flight(thing: thing, fromLeader: fromStarter == byLeader, falls: falls)))
        }

        mutating func burst(_ at: TimeInterval, _ burst: Burst, onStarter: Bool) {
            beats.append(Beat(at: at, burst: BurstAt(burst: burst, onLeader: onStarter == byLeader)))
        }
    }
}

/// Something flying between the two in the island, from `start` on the media clock.
struct NotchMascotIslandFlightEvent: Equatable {
    let id: UUID
    let flight: NotchMascotIslandPlay.Flight
    let start: CFTimeInterval
}

/// A burst over one of the two in the island, from `start` on the media clock.
struct NotchMascotIslandBurstEvent: Equatable {
    let id: UUID
    let burst: NotchMascotIslandPlay.BurstAt
    let start: CFTimeInterval
}
