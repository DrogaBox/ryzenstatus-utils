// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What a combo asks of the two bodies out on the desktop. In the closed
/// island, where they cannot leave their places, the reaction that goes with
/// each move plays in its stead.
enum NotchMascotBodyMove: String, CaseIterable, Equatable {
    // One of them alone.
    case hop, highJump, spin, charge, backflip, stomp, bow, sneak, slip, shiver, strut, float
    // The two together, as a finale.
    case jumpTogether, swap, leapOver, bump, bowTogether, spinTogether, chase, hopRound

    /// Whether both of them take part.
    var together: Bool {
        switch self {
        case .jumpTogether, .swap, .leapOver, .bump, .bowTogether, .spinTogether, .chase, .hopRound: return true
        default: return false
        }
    }

    /// How long it takes on the desktop, landing included.
    var length: TimeInterval {
        switch self {
        case .hop, .bow, .shiver: return 0.9
        case .spin, .stomp, .jumpTogether, .bowTogether, .spinTogether: return 1.1
        case .highJump, .backflip, .float, .swap, .leapOver: return 1.3
        case .charge, .sneak, .slip, .strut, .bump, .hopRound: return 1.5
        case .chase: return 1.9
        }
    }

    /// What it looks like where they cannot move: in the island.
    var reaction: NotchMascotReaction {
        switch self {
        case .hop, .stomp, .hopRound: return .bounce
        case .highJump, .jumpTogether, .float: return .perk
        case .spin, .spinTogether: return .groove
        case .charge, .bump, .chase: return .ready
        case .backflip, .leapOver, .swap: return .celebrate
        case .bow, .bowTogether: return .hush
        case .sneak: return .peek
        case .slip: return .confused
        case .shiver: return .sweat
        case .strut: return .wave
        }
    }
}

/// What a thing worn brings to every combo it is part of: how its wearer
/// moves, what it sends across, what bursts over it and its face.
struct NotchMascotItemSignature: Equatable {
    typealias Thing = NotchMascotIslandPlay.Thing
    typealias Burst = NotchMascotIslandPlay.Burst

    var move: NotchMascotBodyMove
    var thing: Thing
    var burst: Burst
    var reaction: NotchMascotReaction

    init(_ move: NotchMascotBodyMove, _ thing: Thing, _ burst: Burst, _ reaction: NotchMascotReaction) {
        self.move = move
        self.thing = thing
        self.burst = burst
        self.reaction = reaction
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func of(_ item: NotchMascotAccessory) -> NotchMascotItemSignature? {
        switch item {
        case .none: return nil
        case .bow: return .init(.bow, .flower, .hearts, .love)
        case .glasses: return .init(.sneak, .star, .sparkles, .peek)
        case .scarf: return .init(.spin, .snowball, .sparkles, .relax)
        case .headphones: return .init(.stomp, .note, .confetti, .groove)
        case .beanie: return .init(.shiver, .snowball, .sparkles, .perk)
        case .flower: return .init(.spin, .flower, .hearts, .love)
        case .topHat: return .init(.bow, .star, .magic, .flash)
        case .sunglasses: return .init(.strut, .star, .sparkles, .ready)
        case .crown: return .init(.bow, .coin, .coins, .celebrate)
        case .cap: return .init(.charge, .ball, .confetti, .ready)
        case .bowTie: return .init(.bow, .heart, .sparkles, .wave)
        case .monocle: return .init(.sneak, .key, .sparkles, .peek)
        case .cowboyHat: return .init(.strut, .coin, .smoke, .ready)
        case .halo: return .init(.float, .heart, .hearts, .relax)
        case .horns: return .init(.charge, .fireball, .smoke, .ready)
        case .chefHat: return .init(.stomp, .pie, .confetti, .celebrate)
        case .eyePatch: return .init(.sneak, .coin, .coins, .peek)
        case .witchHat: return .init(.float, .potion, .magic, .flash)
        case .santaHat: return .init(.hop, .cookie, .confetti, .celebrate)
        case .partyHat: return .init(.hop, .balloon, .confetti, .celebrate)
        case .headband: return .init(.charge, .ball, .sparkles, .ready)
        case .legendSword: return .init(.charge, .sword, .sparkles, .ready)
        case .legendShield: return .init(.bow, .spark, .sparkles, .ready)
        case .wingBoots: return .init(.highJump, .star, .sparkles, .bounce)
        case .knightHelm: return .init(.strut, .sword, .sparkles, .ready)
        case .katana: return .init(.spin, .sword, .sparkles, .flash)
        case .vikingHelm: return .init(.stomp, .ball, .smoke, .celebrate)
        case .wizardStaff: return .init(.float, .spark, .magic, .flash)
        case .magicTome: return .init(.bow, .star, .magic, .peek)
        case .crystalOrb: return .init(.float, .spark, .magic, .peek)
        case .rangerBow: return .init(.backflip, .arrow, .sparkles, .ready)
        case .kingScepter: return .init(.strut, .bolt, .magic, .celebrate)
        case .boomerang: return .init(.spin, .boomerang, .sparkles, .perk)
        case .fireballSpell: return .init(.charge, .fireball, .smoke, .flash)
        case .tornadoSpell: return .init(.spin, .tornado, .smoke, .flash)
        case .thunderTalisman: return .init(.highJump, .bolt, .magic, .flash)
        case .goldenKey: return .init(.sneak, .key, .coins, .peek)
        case .hourglass: return .init(.float, .star, .magic, .relax)
        case .heartPotion: return .init(.hop, .potion, .hearts, .love)
        case .goldBag: return .init(.stomp, .bag, .coins, .celebrate)
        case .iceCreamCone: return .init(.hop, .snack(.iceCream), .hearts, .love)
        case .onigiri: return .init(.hop, .snack(.onigiri), .confetti, .celebrate)
        case .ramenBowl: return .init(.bow, .snack(.ramen), .smoke, .relax)
        case .bobaTea: return .init(.spin, .snack(.bobaTea), .hearts, .sip)
        case .sleepMask: return .init(.bow, .star, .magic, .yawn)
        case .pacifier: return .init(.slip, .heart, .hearts, .love)
        case .bardLute: return .init(.strut, .note, .confetti, .groove)
        case .dumbbells: return .init(.stomp, .ball, .sparkles, .sweat)
        case .detectiveLens: return .init(.sneak, .key, .sparkles, .peek)
        case .laserVisor: return .init(.backflip, .bolt, .sparkles, .flash)
        case .jetpack: return .init(.highJump, .spark, .smoke, .perk)
        case .gameController: return .init(.hop, .star, .coins, .ready)
        case .angelWings: return .init(.float, .heart, .hearts, .relax)
        case .rubberDuck: return .init(.hop, .duck, .confetti, .surprised)
        case .bananaPeel: return .init(.slip, .peel, .smoke, .confused)
        case .clownNose: return .init(.spin, .pie, .confetti, .celebrate)
        case .creamPie: return .init(.charge, .pie, .confetti, .surprised)
        case .whoopeeCushion: return .init(.stomp, .balloon, .smoke, .surprised)
        case .fakeMustache: return .init(.sneak, .coin, .sparkles, .peek)
        case .trafficCone: return .init(.shiver, .ball, .smoke, .confused)
        case .piggyBank: return .init(.stomp, .coin, .coins, .celebrate)
        case .alarmClock: return .init(.shiver, .star, .smoke, .surprised)
        case .stormCloud: return .init(.shiver, .bolt, .smoke, .sweat)
        case .wiltedFlower: return .init(.bow, .flower, .smoke, .relax)
        case .lonelyBalloon: return .init(.float, .balloon, .hearts, .wave)
        case .teddyBear: return .init(.spin, .heart, .hearts, .love)
        case .tissueBox: return .init(.bow, .heart, .sparkles, .hush)
        case .brokenLocket: return .init(.sneak, .heart, .sparkles, .hush)
        case .tinfoilHat: return .init(.shiver, .bolt, .sparkles, .confused)
        case .magicMushroom: return .init(.highJump, .star, .magic, .bounce)
        case .discoBall: return .init(.spin, .note, .confetti, .groove)
        case .alienAntenna: return .init(.float, .spark, .magic, .surprised)
        case .dynamiteStick: return .init(.backflip, .dynamite, .smoke, .panic)
        case .mimicChest: return .init(.sneak, .coin, .coins, .surprised)
        case .crystalSkull: return .init(.float, .spark, .magic, .panic)
        case .cursedMask: return .init(.shiver, .fireball, .smoke, .panic)
        case .unicornHorn: return .init(.charge, .star, .sparkles, .celebrate)
        case .rosinBox: return .init(.stomp, .spark, .smoke, .ready)
        case .pointeShoes: return .init(.spin, .flower, .sparkles, .celebrate)
        case .warmUpBooties: return .init(.stomp, .heart, .hearts, .relax)
        case .icePack: return .init(.shiver, .snowball, .sparkles, .relax)
        case .plantarBall: return .init(.hop, .ball, .sparkles, .relax)
        case .spanishFan: return .init(.spin, .flower, .confetti, .groove)
        case .swanCrown: return .init(.bow, .flower, .sparkles, .celebrate)
        case .propellerCap: return .init(.float, .star, .sparkles, .perk)
        case .parrot: return .init(.strut, .note, .sparkles, .peek)
        case .springShoes: return .init(.highJump, .ball, .confetti, .bounce)
        case .skateboard: return .init(.charge, .star, .smoke, .ready)
        case .umbrella: return .init(.strut, .snowball, .sparkles, .relax)
        case .yoyo: return .init(.spin, .ball, .confetti, .perk)
        case .bubbleWand: return .init(.float, .balloon, .sparkles, .love)
        case .horseshoeMagnet: return .init(.charge, .coin, .coins, .surprised)
        case .luckyDice: return .init(.spin, .star, .coins, .bounce)
        case .fortuneCookie: return .init(.bow, .cookie, .sparkles, .peek)
        case .snowGlobe: return .init(.shiver, .snowball, .magic, .love)
        case .instantCamera: return .init(.strut, .star, .sparkles, .flash)
        }
    }
}

/// How a combo is staged: what each of the two wears opens it with its own
/// move, the combo's own exchange follows, and a finale of the two together
/// that is the combo's own closes it. Two combos made of different things
/// never open alike, and the finale is drawn from the combo's name, so the
/// same pair always ends the same way.
enum NotchMascotComboChoreography {
    typealias Score = NotchMascotIslandPlay.Score

    /// What the starter and the other wear for `match`, as far as it says:
    /// the starter wears the first thing named.
    static func cast(of match: NotchMascotSynergyMatch) -> (starter: NotchMascotAccessory?, other: NotchMascotAccessory?) {
        switch match {
        case .pair(let a, let b): return (a, b)
        case .twin(let a): return (a, a)
        case .wears(let a), .styleWears(_, let a): return (a, nil)
        case .styles, .style, .quest: return (nil, nil)
        }
    }

    /// The finales that suit a combo's exchange.
    static func finales(for script: NotchMascotSynergyScript) -> [NotchMascotBodyMove] {
        switch script {
        case .give: return [.swap, .jumpTogether, .hopRound, .leapOver]
        case .volley: return [.chase, .leapOver, .hopRound]
        case .duel: return [.bump, .leapOver, .chase]
        case .ritual: return [.spinTogether, .bowTogether, .jumpTogether, .swap]
        case .chorus: return [.spinTogether, .hopRound, .jumpTogether]
        case .calm: return [.bowTogether, .spinTogether]
        case .door: return []
        }
    }

    /// The combo's own finale, the same every time for the same name.
    static func finale(id: String, script: NotchMascotSynergyScript) -> NotchMascotBodyMove? {
        let choices = finales(for: script)
        guard !choices.isEmpty else { return nil }
        // A hash of its own: Swift's changes from one launch to the next.
        let seed = id.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return choices[Int(seed % UInt32(choices.count))]
    }

    static func write(id: String, script: NotchMascotSynergyScript, match: NotchMascotSynergyMatch,
                      into score: inout Score) {
        if case .door = script {
            script.write(into: &score)
            return
        }
        let cast = cast(of: match)
        let first = cast.starter.flatMap(NotchMascotItemSignature.of)
        let second = cast.other.flatMap(NotchMascotItemSignature.of)
        var start: TimeInterval = 0
        if let first, second != nil, cast.starter == cast.other {
            // Twins move as one, mirrored.
            score.move(0, first.move, onStarter: true)
            score.move(0, first.move, onStarter: false)
            score.act(0, starter: first.reaction, other: first.reaction)
            score.burst(first.move.length * 0.6, first.burst, onStarter: true)
            start = first.move.length + 0.2
        } else {
            if let first {
                score.move(0, first.move, onStarter: true)
                score.act(0, starter: first.reaction)
                score.burst(first.move.length * 0.6, first.burst, onStarter: true)
                start = first.move.length + 0.15
            }
            if let second {
                score.move(start, second.move, onStarter: false)
                score.act(start, other: second.reaction)
                score.burst(start + second.move.length * 0.6, second.burst, onStarter: false)
                start += second.move.length + 0.15
            } else if first != nil {
                // The other takes in what it was shown.
                score.act(start - 0.1, other: .surprised)
                start += 0.5
            }
        }
        var exchange = Score(byLeader: score.byLeader)
        script.write(into: &exchange)
        score.append(exchange, after: start)
        let end = start + NotchMascotIslandPlay(kind: .synergy(id), beats: exchange.beats).length + 0.1
        guard let finale = finale(id: id, script: script) else { return }
        score.move(end, finale, onStarter: true)
        score.act(end, starter: finale.reaction, other: finale.reaction)
        score.act(end + finale.length, starter: .celebrate, other: .celebrate)
        if let burst = first?.burst ?? second?.burst {
            score.burst(end + finale.length * 0.7, burst, onStarter: true)
            score.burst(end + finale.length * 0.7 + 0.15, burst, onStarter: false)
        }
    }
}
