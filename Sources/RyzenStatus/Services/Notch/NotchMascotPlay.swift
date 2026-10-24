// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// What the two companions out on the desktop get up to together now and
/// then, so that they seem to live there: duels with blades of light, blasts
/// of energy, powering up, dance-offs, high fives, tag, leapfrog, hugs, a
/// copying game, little gifts and naps. Each comes with its own twist, and
/// what they just did is less likely next, so they keep surprising. Pure, so
/// every rule is tested without a window.
enum NotchMascotPlay: Equatable {
    /// Blades of light crossed `clashes` times, then one wins or they bow.
    case duel(clashes: Int, outcome: Outcome)
    /// One gathers energy in its hands and lets it go at the other.
    case blast(byLeader: Bool, answer: BlastAnswer)
    /// One powers up in bursts of its aura; the other tries to match it.
    case powerUp(byLeader: Bool, matched: Bool)
    /// Turns at dancing, then both together.
    case danceOff(rounds: Int)
    /// They hop up to each other and slap hands.
    case highFive
    /// One runs over, tags the other and runs off; the other gives chase.
    case tag(byLeader: Bool)
    /// One jumps right over the other, who ducks.
    case leapfrog(byLeader: Bool)
    /// A hug, and hearts.
    case hug
    /// The friend copies what the companion does until it gets one wrong.
    case mimic(rounds: Int)
    /// One hands the other a little star.
    case gift(byLeader: Bool)
    /// A yawn goes round, and both doze off side by side for a while.
    case nap
    /// What they wear or are brings a play of its own, a combo of the
    /// catalog, a snack, a secret door or an ability: the same plays the
    /// closed island has, acted out here with their light and props.
    case choreography(NotchMascotIslandPlay)

    enum Outcome: Equatable { case leaderWins, friendWins, draw }

    /// What the one blasted does: holds it off with its own until both burst,
    /// takes it and is thrown back, jumps over it, or knocks it back at the
    /// one that let it go.
    enum BlastAnswer: Equatable { case struggle, hit, dodge, deflect }

    enum Kind: CaseIterable, Equatable {
        case duel, blast, powerUp, danceOff, highFive, tag, leapfrog, hug, mimic, gift, nap, choreography
    }

    var kind: Kind {
        switch self {
        case .duel: return .duel
        case .blast: return .blast
        case .powerUp: return .powerUp
        case .danceOff: return .danceOff
        case .highFive: return .highFive
        case .tag: return .tag
        case .leapfrog: return .leapfrog
        case .hug: return .hug
        case .mimic: return .mimic
        case .gift: return .gift
        case .nap: return .nap
        case .choreography: return .choreography
        }
    }

    // MARK: When

    /// At least this long between two plays, and before the first one.
    static let interval: TimeInterval = 45
    /// Once one is due, the share of chances it is taken: they also just
    /// wander, so a play comes when it is not quite expected.
    static let chance = 0.6
    /// Farther apart than this they do not play; one walks over first.
    static let reach: CGFloat = 480
    /// How many plays back still count as just done.
    static let memory = 4

    /// What they know as they might start one.
    struct Context: Equatable {
        /// How far apart their feet are.
        var distance: CGFloat
        /// A song is playing.
        var music: Bool
        /// Since the last play, or since they came out.
        var since: TimeInterval
        /// The hour of the day, 0 to 23.
        var hour: Int
        /// The plays they did lately, the latest last.
        var recent: [Kind] = []
        /// How each of them looks, and so what each wears and is.
        var leaderLook: NotchMascotLook = .standard
        var friendLook: NotchMascotLook = .standard
        /// Hearts, the hourglass, gold and the combos found.
        var rpg = NotchMascotRPGSnapshot()

        var leaderWears: NotchMascotAccessory { leaderLook.accessory }
        var friendWears: NotchMascotAccessory { friendLook.accessory }

        /// The context the island's plays are chosen in, for the same pair.
        var islandContext: NotchMascotIslandPlay.Context {
            NotchMascotIslandPlay.Context(since: .infinity, music: music, hour: hour, recent: [],
                                          leaderWears: leaderWears, friendWears: friendWears,
                                          leaderStyle: leaderLook.style, friendStyle: friendLook.style, rpg: rpg)
        }
    }

    /// How much each play is wanted now: music calls for dancing and the
    /// small hours for a nap, the play just done is never next, and one done
    /// lately is less likely.
    static func weight(of kind: Kind, in context: Context) -> Double {
        if context.recent.last == kind { return 0 }
        let night = context.hour >= 23 || context.hour < 6
        var weight: Double
        switch kind {
        case .duel: weight = 3
        case .blast: weight = 3
        case .powerUp: weight = 2
        case .danceOff: weight = context.music ? 7 : 0.6
        case .highFive: weight = 2
        case .tag: weight = 2
        case .leapfrog: weight = 1.5
        case .hug: weight = 1.5
        case .mimic: weight = 1.5
        case .gift: weight = 1.2
        case .nap: weight = night ? 5 : 0.4
        case .choreography:
            // What they wear or are, and a hungry one, call for their own plays.
            let island = context.islandContext
            let calls = !NotchMascotIslandPlay.synergyKinds(in: island).isEmpty || context.rpg.isHungry
            weight = calls ? 6 : 0.8
        }
        if context.recent.suffix(memory).contains(kind) { weight *= 0.3 }
        return weight
    }

    /// The play they start now, if any. `random` gives numbers in 0..<1.
    static func next(in context: Context, random: () -> Double) -> NotchMascotPlay? {
        guard context.since >= interval, context.distance <= reach, random() < chance else { return nil }
        let weights = Kind.allCases.map { ($0, weight(of: $0, in: context)) }.filter { $0.1 > 0 }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = random() * total
        for (kind, weight) in weights {
            if roll < weight { return chosen(kind, in: context, random: random) }
            roll -= weight
        }
        return weights.last.flatMap { chosen($0.0, in: context, random: random) }
    }

    /// `kind` as the pair plays it now; the choreography needs what they wear.
    private static func chosen(_ kind: Kind, in context: Context, random: () -> Double) -> NotchMascotPlay? {
        kind == .choreography ? choreography(in: context, random: random) : play(kind, random: random)
    }

    /// `kind` with its twist: who starts it, how long it lasts, how it ends.
    static func play(_ kind: Kind, random: () -> Double) -> NotchMascotPlay {
        func count(_ range: ClosedRange<Int>) -> Int {
            min(range.upperBound, range.lowerBound + Int(random() * Double(range.count)))
        }
        switch kind {
        case .duel:
            let clashes = count(2...4)
            let roll = random()
            return .duel(clashes: clashes, outcome: roll < 0.42 ? .leaderWins : roll < 0.84 ? .friendWins : .draw)
        case .blast:
            let leader = random() < 0.5
            let roll = random()
            return .blast(byLeader: leader,
                          answer: roll < 0.34 ? .struggle : roll < 0.6 ? .hit : roll < 0.82 ? .dodge : .deflect)
        case .powerUp:
            let leader = random() < 0.5
            return .powerUp(byLeader: leader, matched: random() < 0.6)
        case .danceOff: return .danceOff(rounds: count(2...3))
        case .highFive: return .highFive
        case .tag: return .tag(byLeader: random() < 0.5)
        case .leapfrog: return .leapfrog(byLeader: random() < 0.5)
        case .hug: return .hug
        case .mimic: return .mimic(rounds: count(2...4))
        case .gift: return .gift(byLeader: random() < 0.5)
        case .nap: return .nap
        case .choreography: return .nap
        }
    }

    /// A choreography of what they wear or are, or nil when the draw gives none.
    static func choreography(in context: Context, random: () -> Double) -> NotchMascotPlay? {
        NotchMascotIslandPlay.pick(in: context.islandContext, random: random).map { .choreography($0) }
    }

    // MARK: Where

    /// How far apart their feet stand for it; nil where they stay where they are.
    var spacing: CGFloat? {
        switch self {
        case .duel: return 72
        case .blast(_, let answer): return answer == .struggle ? 260 : 220
        case .powerUp: return 150
        case .danceOff: return 110
        case .highFive: return 40
        case .tag: return nil
        case .leapfrog: return 120
        case .hug: return 34
        case .mimic: return 110
        case .gift: return 100
        case .nap: return 64
        case .choreography: return 150
        }
    }

    /// Where the leader at `leaderX` and its friend at `friendX` stand to be
    /// `spacing` apart: about where they are, each on its own side, and both
    /// between `minX` and `maxX`.
    static func places(leaderX: CGFloat, friendX: CGFloat, spacing: CGFloat,
                       minX: CGFloat, maxX: CGFloat) -> (leader: CGFloat, friend: CGFloat) {
        let spacing = min(spacing, max(0, maxX - minX))
        let side: CGFloat = leaderX <= friendX ? -1 : 1
        let middle = min(maxX - spacing / 2, max(minX + spacing / 2, (leaderX + friendX) / 2))
        return (middle + side * spacing / 2, middle - side * spacing / 2)
    }

    // MARK: Between plays

    /// What the friend does a moment after the companion reacts to
    /// something: its own take on it rather than a copy, or nothing.
    static func echo(of reaction: NotchMascotReaction) -> NotchMascotReaction? {
        switch reaction {
        case .celebrate: return .bounce
        case .love: return .love
        case .surprised: return .peek
        case .flash: return .surprised
        case .confused: return .peek
        case .wakeUp: return .wave
        case .yawn: return .yawn
        case .perk: return .perk
        case .bounce: return .celebrate
        case .hush: return .hush
        case .ready: return .ready
        case .groove: return .groove
        case .sweat: return .peek
        case .panic: return .surprised
        case .relax: return .relax
        case .sip: return nil
        case .peek: return .lookAround
        case .wave: return .wave
        case .lookAround: return nil
        }
    }

    /// The friend's echo comes this long after.
    static let echoDelay: ClosedRange<TimeInterval> = 0.35...0.75

    /// What one does as the other is patted.
    enum PatResponse: Equatable {
        /// It walks over, far off as it is.
        case comesOver
        /// It hops up for a pat of its own.
        case wantsOne
        /// It cheers the other on.
        case cheers
    }

    static func patResponse(distance: CGFloat, random: Double) -> PatResponse {
        if distance > 160 { return .comesOver }
        return random < 0.55 ? .wantsOne : .cheers
    }

    /// Patted again within this long, the other no longer minds.
    static let patResponseInterval: TimeInterval = 6

    /// Dozing on its own this long, the other one yawns and joins it.
    static let dozeJoinDelay: TimeInterval = 8

    /// A nap together lasts this long, unless one is woken.
    static func napLength(random: Double) -> TimeInterval { 25 + random * 20 }

    // MARK: Looks

    /// The colour of its energy and its blade, red, green and blue in 0...1:
    /// its transformation's, or its own figure's before it has one.
    struct Energy: Equatable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
    }

    static func energy(for look: NotchMascotLook) -> Energy {
        switch look.form {
        case .golden?: return Energy(red: 1, green: 0.84, blue: 0.25)
        case .goldenLightning?: return Energy(red: 1, green: 0.95, blue: 0.45)
        case .goldenFury?: return Energy(red: 1, green: 0.6, blue: 0.12)
        case .divine?: return Energy(red: 0.55, green: 0.88, blue: 1)
        case nil: break
        }
        switch look.style {
        case .cristobal: return Energy(red: 0.3, green: 0.62, blue: 1)
        case .whiteRabbit: return Energy(red: 1, green: 0.4, blue: 0.62)
        case .cat: return Energy(red: 0.45, green: 1, blue: 0.5)
        case .robot: return Energy(red: 1, green: 0.3, blue: 0.3)
        case .ghost: return Energy(red: 0.72, green: 0.52, blue: 1)
        case .slime: return Energy(red: 0.66, green: 1, blue: 0.3)
        case .devourer: return Energy(red: 1, green: 0.55, blue: 0.78)
        case .shifter: return Energy(red: 0.72, green: 0.48, blue: 1)
        case .phoenix: return Energy(red: 1, green: 0.52, blue: 0.16)
        case .axolotl: return Energy(red: 1, green: 0.62, blue: 0.78)
        case .dog: return Energy(red: 0.86, green: 0.62, blue: 0.35)
        case .mouse: return Energy(red: 0.82, green: 0.78, blue: 0.88)
        case .capybara: return Energy(red: 0.95, green: 0.65, blue: 0.22)
        case .dragon: return Energy(red: 1, green: 0.35, blue: 0.15)
        case .frog: return Energy(red: 0.35, green: 0.92, blue: 0.42)
        case .fan: return Energy(red: 0.35, green: 0.95, blue: 1)
        case .chip: return Energy(red: 1, green: 0.7, blue: 0.25)
        case .minimal: return Energy(red: 0.62, green: 0.8, blue: 1)
        }
    }

    /// From the second golden form on, lightning crackles round its energy.
    static func crackles(_ look: NotchMascotLook) -> Bool {
        switch look.form {
        case .goldenLightning?, .goldenFury?, .divine?: return true
        case .golden?, nil: return false
        }
    }

    /// How big its energy grows with the bond: from 0.8 at the first level
    /// to 1.4 from level fifty on.
    static func power(level: Int) -> CGFloat {
        0.8 + min(1, max(0, CGFloat(level - 1) / 49)) * 0.6
    }
}
