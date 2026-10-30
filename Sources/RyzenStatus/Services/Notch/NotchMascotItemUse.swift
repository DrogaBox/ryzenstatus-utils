// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// One thing the companion does with what it wears, on its own.
enum NotchMascotItemAction: Equatable {
    /// The colour of a symbol floating up.
    enum Tint: Equatable { case gold, pink, blue, white, green, purple }

    case react(NotchMascotReaction)
    case move(NotchMascotBodyMove)
    /// A burst over its head.
    case burst(NotchMascotIslandPlay.Burst)
    /// An arcade marker rising over it: `1UP`, `+1`.
    case marker(String)
    /// `count` of `symbol` floating up off its head.
    case symbol(String, Tint, count: Int)
    /// Thrown far ahead along an arc, and back into its hand when `back`.
    case fling(NotchMascotIslandPlay.Thing, back: Bool)
    /// Tossed over its head from one hand to the other.
    case juggle(NotchMascotIslandPlay.Thing)
    /// A blade drawn and swung.
    case slash
    case lightning
    /// Sparks off its hand.
    case sparks
    /// What it wears is gone a while: eaten, drunk, put in its face.
    case hide(TimeInterval)
    /// It grows half again its size a while, and shrinks back.
    case grow(TimeInterval)
    /// It dozes off a while.
    case doze(TimeInterval)
    /// Luck pays out this much gold, within the day's share (see `NotchMascotLuck`).
    case gold(Int)

    /// How long it keeps it busy. What lasts on its own, the thing gone or
    /// the size grown, does not: it goes about its life meanwhile.
    var length: TimeInterval {
        switch self {
        case .react(let reaction): return reaction.length
        case .move(let move): return move.length
        case .burst: return NotchMascotIslandPlay.burstLength
        case .marker, .gold: return NotchMascotIslandPlay.markerLength
        case .symbol(_, _, let count): return 1.3 + Double(max(0, count - 1)) * 0.35
        case .fling(_, let back): return back ? NotchMascotItemUse.flingLength * 2 + 0.1 : NotchMascotItemUse.flingLength
        case .juggle: return NotchMascotItemUse.juggleLength
        case .slash: return 0.7
        case .lightning: return 0.5
        case .sparks: return 0.45
        case .hide, .grow: return 0
        case .doze(let length): return length
        }
    }
}

/// What the companion does now and then with the thing it wears, alone:
/// the lute plays, the boomerang goes out and comes back, the banana peel
/// slips it up, the ice cream gives it brain freeze and the magic mushroom,
/// eaten, makes it grow a while. Every thing worn has its own.
struct NotchMascotItemUse: Equatable {
    struct Step: Equatable {
        var at: TimeInterval
        var action: NotchMascotItemAction
    }

    var steps: [Step]

    /// Until it is free again.
    var length: TimeInterval { steps.map { $0.at + $0.action.length }.max() ?? 0 }

    /// Out on the desktop, at least this long between two, and the chance of
    /// one each time it looks for something to do after that.
    static let desktopInterval: TimeInterval = 70
    static let desktopChance = 0.4
    /// Resting in the island, where it has less to do.
    static let islandInterval: TimeInterval = 150
    static let islandChance = 0.5
    static let flingLength: TimeInterval = 0.8
    static let juggleLength: TimeInterval = 0.8
    /// How much bigger the mushroom makes it.
    static let growth: CGFloat = 1.6

    static func shouldStart(since: TimeInterval, interval: TimeInterval, chance: Double, random: Double) -> Bool {
        since >= interval && random < chance
    }

    /// The same, as beats of a play in the island, by the leader when
    /// `byLeader`: where it cannot leave its place, a move shows as its
    /// reaction, and what it throws, swings or eats stays with it.
    func islandBeats(byLeader: Bool) -> [NotchMascotIslandPlay.Beat] {
        var score = NotchMascotIslandPlay.Score(byLeader: byLeader)
        for step in steps {
            switch step.action {
            case .react(let reaction): score.act(step.at, starter: reaction)
            case .move(let move): score.act(step.at, starter: move.reaction)
            case .burst(let burst): score.burst(step.at, burst, onStarter: true)
            case .marker(let text): score.marker(step.at, text, onStarter: true)
            case .slash: score.act(step.at, starter: .ready)
            case .lightning: score.burst(step.at, .magic, onStarter: true)
            case .doze: score.act(step.at, starter: .yawn)
            case .gold(let amount):
                score.burst(step.at, .coins, onStarter: true)
                score.marker(step.at, "+\(amount)", onStarter: true)
            case .symbol, .fling, .juggle, .sparks, .hide, .grow: break
            }
        }
        return score.beats.sorted { $0.at < $1.at }
    }

    /// The same, with its luck settled as it starts: gold the day still has a
    /// payout for is paid and shown, and once the day's luck is spent the
    /// gold is left out rather than shown and not given.
    func settled(pay: (Int) -> Int = { NotchMascotLuck.pay($0) },
                 collect: (Int) -> Void = { NotchMascotRPG.collect(gold: $0) }) -> NotchMascotItemUse {
        var copy = self
        copy.steps = steps.compactMap { step in
            guard case .gold(let amount) = step.action else { return step }
            let paid = pay(amount)
            guard paid > 0 else { return nil }
            collect(paid)
            return Step(at: step.at, action: .gold(paid))
        }
        return copy
    }

    private init(_ steps: [(TimeInterval, NotchMascotItemAction)]) {
        self.steps = steps.map { Step(at: $0.0, action: $0.1) }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// `random` decides what luck brings: the dice's roll, the cookie's fortune.
    static func of(_ item: NotchMascotAccessory,
                   random: () -> Double = { Double.random(in: 0..<1) }) -> NotchMascotItemUse? {
        switch item {
        case .none: return nil
        case .bow: return .init([(0, .move(.bow)), (0, .react(.love)), (0.8, .symbol("♥", .pink, count: 2))])
        case .glasses:
            return .init([(0, .react(.peek)), (0.2, .symbol("?", .white, count: 1)), (0.3, .move(.sneak)),
                          (1.8, .symbol("!", .gold, count: 1)), (1.8, .react(.perk))])
        case .scarf:
            return .init([(0, .move(.shiver)), (0, .react(.sweat)), (1.0, .react(.relax)), (1.0, .symbol("~", .white, count: 2))])
        case .headphones:
            return .init([(0, .react(.groove)), (0, .symbol("♪", .gold, count: 3)), (0.4, .move(.stomp)), (1.6, .move(.hop))])
        case .beanie: return .init([(0, .juggle(.snowball)), (1.0, .burst(.sparkles)), (1.0, .react(.perk))])
        case .flower: return .init([(0, .react(.love)), (0.3, .symbol("✿", .pink, count: 3)), (1.0, .move(.spin))])
        case .topHat:
            return .init([(0, .move(.bow)), (0.6, .burst(.magic)), (0.9, .fling(.star, back: false)), (0.9, .react(.flash))])
        case .sunglasses:
            return .init([(0, .move(.strut)), (0, .react(.ready)), (1.5, .sparks), (1.5, .symbol("✦", .white, count: 1))])
        case .crown:
            return .init([(0, .react(.celebrate)), (0.2, .burst(.coins)), (0.9, .move(.bow)), (1.2, .marker("+100"))])
        case .cap: return .init([(0, .juggle(.ball)), (0.9, .juggle(.ball)), (1.8, .react(.ready))])
        case .bowTie:
            return .init([(0, .move(.strut)), (0, .react(.wave)), (1.5, .move(.bow)), (1.6, .burst(.sparkles))])
        case .monocle:
            return .init([(0, .react(.peek)), (0.3, .symbol("?", .gold, count: 2)), (1.0, .move(.sneak)),
                          (2.5, .react(.surprised))])
        case .cowboyHat:
            return .init([(0, .move(.strut)), (0, .react(.ready)), (1.4, .juggle(.coin)), (2.3, .burst(.smoke))])
        case .halo: return .init([(0, .move(.float)), (0, .react(.relax)), (0.4, .symbol("✦", .gold, count: 3))])
        case .horns:
            return .init([(0, .react(.ready)), (0, .move(.charge)), (0.6, .burst(.smoke)), (1.4, .fling(.fireball, back: false))])
        case .chefHat:
            return .init([(0, .juggle(.pie)), (0.9, .juggle(.pie)), (1.9, .burst(.confetti)), (1.9, .react(.celebrate))])
        case .eyePatch:
            return .init([(0, .move(.sneak)), (0, .react(.peek)), (1.5, .burst(.coins)), (1.5, .marker("+50"))])
        case .witchHat:
            return .init([(0, .move(.float)), (0.3, .burst(.magic)), (0.8, .fling(.potion, back: false)), (1.2, .react(.flash))])
        case .santaHat:
            return .init([(0, .react(.celebrate)), (0.2, .fling(.cookie, back: false)), (0.9, .symbol("❄", .white, count: 3)),
                          (0.9, .move(.hop))])
        case .partyHat:
            return .init([(0, .move(.hop)), (0, .burst(.confetti)), (0.8, .react(.celebrate)), (0.9, .symbol("✦", .gold, count: 2))])
        case .headband:
            return .init([(0, .react(.ready)), (0, .move(.stomp)), (1.1, .move(.highJump)), (1.3, .sparks), (1.4, .react(.sweat))])
        case .legendSword:
            return .init([(0, .react(.ready)), (0.2, .slash), (0.8, .slash), (1.4, .sparks), (1.4, .marker("+100"))])
        case .legendShield:
            return .init([(0, .move(.bow)), (0.3, .sparks), (0.3, .react(.ready)), (1.0, .sparks), (1.0, .burst(.sparkles))])
        case .wingBoots:
            return .init([(0, .react(.perk)), (0.4, .move(.highJump)), (1.7, .move(.highJump)), (1.9, .burst(.sparkles))])
        case .knightHelm: return .init([(0, .move(.strut)), (0.2, .react(.ready)), (1.5, .slash), (2.1, .move(.bow))])
        case .katana:
            return .init([(0, .move(.spin)), (0.4, .slash), (1.0, .slash), (1.0, .react(.flash)), (1.5, .burst(.sparkles))])
        case .vikingHelm:
            return .init([(0, .move(.stomp)), (0, .react(.celebrate)), (1.1, .juggle(.ball)), (2.0, .burst(.smoke))])
        case .wizardStaff:
            return .init([(0, .react(.flash)), (0.3, .lightning), (0.4, .burst(.magic)), (1.0, .move(.float))])
        case .magicTome:
            return .init([(0, .react(.peek)), (0.6, .symbol("✦", .purple, count: 3)), (1.4, .burst(.magic)),
                          (1.4, .react(.surprised))])
        case .crystalOrb:
            return .init([(0, .react(.peek)), (0.3, .burst(.magic)), (1.0, .symbol("?", .purple, count: 1)),
                          (1.6, .symbol("!", .purple, count: 1)), (1.6, .react(.perk))])
        case .rangerBow:
            return .init([(0, .react(.ready)), (0.4, .fling(.arrow, back: false)), (1.3, .fling(.arrow, back: false)),
                          (2.2, .react(.celebrate))])
        case .kingScepter:
            return .init([(0, .move(.strut)), (0.6, .lightning), (0.6, .burst(.magic)), (1.6, .react(.celebrate))])
        case .boomerang:
            return .init([(0, .react(.ready)), (0.2, .fling(.boomerang, back: true)), (1.9, .react(.celebrate))])
        case .fireballSpell:
            return .init([(0, .react(.flash)), (0.1, .move(.charge)), (0.5, .fling(.fireball, back: false)), (1.3, .burst(.smoke))])
        case .tornadoSpell:
            return .init([(0, .move(.spin)), (0.3, .fling(.tornado, back: true)), (0.3, .react(.flash)), (2.0, .react(.confused))])
        case .thunderTalisman:
            return .init([(0, .move(.highJump)), (0.6, .lightning), (0.6, .react(.flash)), (1.3, .lightning), (1.3, .burst(.magic))])
        case .goldenKey:
            return .init([(0, .move(.sneak)), (0, .react(.peek)), (1.5, .juggle(.key)), (2.4, .burst(.coins))])
        case .hourglass:
            return .init([(0, .react(.relax)), (0.3, .symbol("z", .white, count: 2)), (1.2, .move(.float)), (1.2, .burst(.magic))])
        case .heartPotion:
            return .init([(0, .react(.sip)), (0.3, .hide(10)), (1.2, .burst(.hearts)), (1.2, .react(.love)), (1.4, .marker("HP+"))])
        case .goldBag:
            return .init([(0, .move(.stomp)), (0.4, .juggle(.bag)), (1.3, .burst(.coins)), (1.3, .marker("+10"))])
        case .iceCreamCone:
            // Eaten too fast: brain freeze.
            return .init([(0, .react(.sip)), (0.3, .hide(8)), (0.6, .symbol("♥", .pink, count: 2)), (1.8, .move(.shiver)),
                          (1.8, .react(.surprised))])
        case .onigiri:
            return .init([(0, .react(.perk)), (0.3, .hide(8)), (0.6, .burst(.confetti)), (1.2, .move(.hop)), (1.2, .react(.celebrate))])
        case .ramenBowl:
            return .init([(0, .react(.relax)), (0.3, .hide(9)), (0.4, .burst(.smoke)), (1.0, .symbol("~", .white, count: 3)),
                          (2.2, .react(.love))])
        case .bobaTea:
            return .init([(0, .react(.sip)), (1.6, .symbol("♥", .pink, count: 1)), (1.6, .move(.spin)), (1.6, .react(.bounce))])
        case .sleepMask: return .init([(0, .react(.yawn)), (1.0, .doze(12)), (1.2, .symbol("z", .blue, count: 3))])
        case .pacifier:
            return .init([(0, .react(.love)), (0.3, .move(.slip)), (1.6, .doze(8)), (1.8, .symbol("z", .pink, count: 2))])
        case .bardLute:
            return .init([(0, .react(.groove)), (0, .move(.strut)), (0.2, .symbol("♫", .gold, count: 4)), (1.6, .burst(.confetti))])
        case .dumbbells:
            return .init([(0, .move(.stomp)), (0, .react(.sweat)), (1.1, .move(.stomp)), (1.1, .marker("+1")),
                          (2.2, .marker("+1")), (2.2, .react(.celebrate))])
        case .detectiveLens:
            return .init([(0, .move(.sneak)), (0, .symbol("?", .white, count: 2)), (1.6, .react(.surprised)),
                          (1.6, .symbol("!", .gold, count: 1)), (1.7, .juggle(.key))])
        case .laserVisor:
            return .init([(0, .react(.flash)), (0.2, .fling(.bolt, back: false)), (0.6, .fling(.bolt, back: false)),
                          (1.0, .move(.backflip))])
        case .jetpack:
            return .init([(0, .react(.perk)), (0.2, .burst(.smoke)), (0.3, .move(.float)), (0.6, .burst(.smoke)),
                          (1.6, .react(.celebrate))])
        case .gameController:
            return .init([(0, .react(.ready)), (0.4, .symbol("!", .white, count: 2)), (1.4, .marker("GG")),
                          (1.4, .react(.celebrate)), (1.5, .move(.hop))])
        case .angelWings:
            return .init([(0, .move(.float)), (0, .burst(.hearts)), (1.3, .move(.float)), (1.3, .react(.relax))])
        case .rubberDuck:
            // Squeezed: it squeaks, twice.
            return .init([(0, .react(.surprised)), (0, .symbol("♪", .gold, count: 1)), (0.5, .symbol("♪", .gold, count: 1)),
                          (1.0, .move(.hop)), (1.0, .juggle(.duck))])
        case .bananaPeel:
            return .init([(0, .react(.perk)), (0.3, .move(.slip)), (0.7, .burst(.smoke)), (1.5, .react(.confused)),
                          (1.6, .symbol("✦", .gold, count: 3))])
        case .clownNose:
            return .init([(0, .react(.celebrate)), (0.2, .marker("HONK")), (0.6, .move(.spin)), (1.2, .burst(.confetti))])
        case .creamPie:
            // Right in its own face.
            return .init([(0, .react(.perk)), (0.4, .hide(6)), (0.5, .burst(.smoke)), (0.5, .react(.surprised)),
                          (1.4, .symbol("?", .white, count: 1))])
        case .whoopeeCushion:
            return .init([(0, .move(.stomp)), (0.4, .marker("PFFT")), (0.4, .burst(.smoke)), (0.6, .react(.surprised)),
                          (1.6, .react(.celebrate))])
        case .fakeMustache:
            return .init([(0, .move(.sneak)), (0, .react(.peek)), (1.5, .move(.strut)), (1.5, .symbol("?", .gold, count: 2))])
        case .trafficCone:
            return .init([(0, .react(.confused)), (0.2, .move(.shiver)), (1.2, .symbol("!", .gold, count: 3)), (1.2, .move(.stomp))])
        case .piggyBank:
            return .init([(0, .move(.shiver)), (1.0, .burst(.coins)), (1.0, .react(.celebrate)), (1.1, .marker("+5"))])
        case .alarmClock:
            return .init([(0, .react(.surprised)), (0, .move(.shiver)), (0, .symbol("!", .gold, count: 3)), (1.2, .react(.panic)),
                          (1.4, .move(.hop))])
        case .stormCloud:
            // Rained on, and struck.
            return .init([(0, .react(.sweat)), (0.3, .lightning), (0.5, .symbol("•", .blue, count: 4)), (1.0, .move(.shiver)),
                          (1.6, .lightning)])
        case .wiltedFlower:
            return .init([(0, .move(.bow)), (0, .react(.hush)), (0.6, .symbol("•", .blue, count: 2)), (1.8, .burst(.smoke))])
        case .lonelyBalloon:
            return .init([(0, .react(.wave)), (0.3, .move(.float)), (0.3, .symbol("♥", .pink, count: 1)), (1.6, .react(.hush))])
        case .teddyBear:
            return .init([(0, .react(.love)), (0.2, .burst(.hearts)), (0.8, .move(.spin)), (1.0, .symbol("♥", .pink, count: 2))])
        case .tissueBox:
            // A sneeze.
            return .init([(0, .react(.hush)), (0.4, .symbol("•", .blue, count: 3)), (1.4, .move(.hop)), (1.4, .react(.surprised)),
                          (1.4, .burst(.smoke))])
        case .brokenLocket:
            return .init([(0, .move(.sneak)), (0, .react(.hush)), (1.5, .symbol("♥", .pink, count: 1)),
                          (1.5, .symbol("•", .blue, count: 2))])
        case .tinfoilHat:
            return .init([(0, .react(.confused)), (0.2, .lightning), (0.3, .symbol("?", .green, count: 3)), (1.0, .move(.shiver))])
        case .magicMushroom:
            // Eaten: it grows a while, as in the old games.
            return .init([(0, .react(.perk)), (0.3, .hide(18.6)), (0.3, .symbol("♥", .gold, count: 1)), (0.6, .grow(18)),
                          (0.6, .burst(.magic)), (0.6, .marker("1UP")), (1.0, .react(.celebrate)), (1.7, .move(.highJump))])
        case .discoBall:
            return .init([(0, .react(.groove)), (0, .sparks), (0.3, .symbol("♪", .gold, count: 3)), (0.5, .move(.spin)),
                          (1.5, .burst(.confetti))])
        case .alienAntenna:
            return .init([(0, .react(.surprised)), (0.2, .lightning), (0.4, .symbol("?", .green, count: 2)), (0.8, .move(.float)),
                          (2.0, .react(.wave))])
        case .dynamiteStick:
            return .init([(0, .react(.panic)), (0.2, .sparks), (0.8, .sparks), (1.4, .burst(.smoke)), (1.4, .move(.backflip)),
                          (2.5, .react(.confused))])
        case .mimicChest:
            return .init([(0, .move(.sneak)), (1.5, .react(.surprised)), (1.5, .marker("CHOMP")), (1.6, .move(.hop)),
                          (1.7, .burst(.coins))])
        case .crystalSkull:
            return .init([(0, .react(.panic)), (0.3, .burst(.magic)), (0.4, .move(.shiver)), (1.3, .symbol("!", .purple, count: 2))])
        case .cursedMask:
            return .init([(0, .move(.shiver)), (0.4, .burst(.smoke)), (0.4, .lightning), (1.3, .react(.panic))])
        case .unicornHorn:
            return .init([(0, .move(.charge)), (0.4, .burst(.sparkles)), (0.9, .fling(.star, back: false)),
                          (1.5, .react(.celebrate))])
        case .rosinBox: return .init([(0, .move(.stomp)), (0.2, .burst(.smoke)), (1.2, .move(.spin)), (1.2, .react(.ready))])
        case .pointeShoes:
            return .init([(0, .move(.spin)), (0.9, .move(.spin)), (1.8, .move(.bow)), (1.8, .react(.celebrate)),
                          (1.9, .symbol("✿", .pink, count: 2))])
        case .warmUpBooties:
            return .init([(0, .move(.stomp)), (0, .react(.relax)), (1.2, .symbol("~", .white, count: 2)), (1.4, .move(.hop))])
        case .icePack:
            return .init([(0, .react(.sweat)), (0.3, .symbol("❄", .blue, count: 2)), (0.4, .move(.shiver)), (1.4, .react(.relax))])
        case .plantarBall: return .init([(0, .react(.relax)), (0.3, .fling(.ball, back: true)), (2.0, .move(.hop))])
        case .spanishFan:
            return .init([(0, .react(.groove)), (0, .move(.spin)), (0.6, .symbol("♪", .pink, count: 2)), (1.2, .move(.stomp)),
                          (1.8, .symbol("✿", .pink, count: 1))])
        case .swanCrown:
            return .init([(0, .move(.bow)), (1.0, .move(.spin)), (1.0, .symbol("✦", .white, count: 2)), (2.0, .react(.celebrate))])
        case .propellerCap:
            return .init([(0, .move(.float)), (0, .symbol("~", .white, count: 3)), (1.2, .move(.hop)), (1.4, .react(.perk))])
        case .parrot:
            return .init([(0, .react(.peek)), (0.3, .marker("SQUAWK!")), (0.4, .symbol("♪", .green, count: 2)),
                          (1.4, .move(.hop)), (1.6, .react(.celebrate))])
        case .springShoes:
            return .init([(0, .move(.highJump)), (0.9, .move(.highJump)), (1.8, .marker("BOING")), (1.9, .move(.hop))])
        case .skateboard:
            return .init([(0, .move(.charge)), (0.6, .move(.spin)), (1.4, .marker("OLLIE!")), (1.5, .move(.highJump)),
                          (2.4, .react(.ready))])
        case .umbrella:
            return .init([(0, .react(.sweat)), (0.3, .symbol("☂", .blue, count: 1)), (0.5, .symbol("·", .blue, count: 3)),
                          (1.6, .react(.relax)), (1.7, .move(.strut))])
        case .yoyo:
            return .init([(0, .fling(.ball, back: true)), (1.8, .fling(.ball, back: true)), (3.6, .react(.celebrate))])
        case .bubbleWand:
            return .init([(0, .react(.relax)), (0.2, .symbol("○", .blue, count: 4)), (1.5, .move(.spin)),
                          (2.2, .symbol("○", .white, count: 2)), (2.6, .react(.love))])
        case .horseshoeMagnet:
            return .init([(0, .move(.charge)), (0.4, .sparks), (0.8, .juggle(.coin)), (1.6, .burst(.coins)),
                          (1.6, .react(.surprised))])
        case .luckyDice:
            return .init(NotchMascotLuck.roll(face: NotchMascotLuck.face(random: random())))
        case .fortuneCookie:
            return .init(NotchMascotLuck.fortune(NotchMascotLuck.Fortune.pick(random: random())))
        case .snowGlobe:
            return .init([(0, .move(.shiver)), (0.3, .symbol("❄", .white, count: 4)), (1.5, .react(.love)),
                          (1.6, .burst(.sparkles))])
        case .instantCamera:
            return .init([(0, .react(.ready)), (0.6, .react(.flash)), (0.6, .burst(.sparkles)), (1.0, .marker("CLICK!")),
                          (1.5, .symbol("★", .gold, count: 1)), (1.8, .move(.strut))])
        }
    }
}

/// What the lucky dice and the fortune cookie bring: a roll of one to six,
/// a fortune of six, and now and then a little gold. Luck pays out only a
/// few times a day, however often the thing is tried.
enum NotchMascotLuck {
    /// Payouts a day.
    static let paidPerDay = 3

    static func face(random: Double) -> Int { min(6, max(1, Int(random * 6) + 1)) }

    /// The roll, then what the face brings: a six pays.
    static func roll(face: Int) -> [(TimeInterval, NotchMascotItemAction)] {
        let opening: [(TimeInterval, NotchMascotItemAction)] = [(0, .react(.ready)), (0.2, .juggle(.star)),
                                                                (1.0, .marker("ROLL"))]
        let result: [(TimeInterval, NotchMascotItemAction)]
        switch face {
        case 1: result = [(1.8, .marker("1")), (1.8, .burst(.smoke)), (2.0, .react(.confused))]
        case 2: result = [(1.8, .marker("2")), (2.0, .react(.wave))]
        case 3: result = [(1.8, .marker("3")), (1.9, .symbol("✦", .white, count: 2))]
        case 4: result = [(1.8, .marker("4")), (1.9, .burst(.sparkles)), (2.0, .react(.perk))]
        case 5: result = [(1.8, .marker("5")), (1.9, .burst(.confetti)), (2.0, .react(.celebrate))]
        default: result = [(1.8, .marker("6!")), (2.0, .gold(30)), (2.1, .move(.backflip)), (2.4, .react(.celebrate))]
        }
        return opening + result
    }

    enum Fortune: CaseIterable {
        case lucky, love, soon, yes, beware, gold

        static func pick(random: Double) -> Fortune {
            allCases[min(allCases.count - 1, max(0, Int(random * Double(allCases.count))))]
        }

        var text: String {
            switch self {
            case .lucky: return "LUCKY!"
            case .love: return "LOVE ♥"
            case .soon: return "SOON..."
            case .yes: return "YES!"
            case .beware: return "BEWARE"
            case .gold: return "GOLD!"
            }
        }
    }

    /// The cookie cracks, the slip reads, and it takes it to heart.
    static func fortune(_ fortune: Fortune) -> [(TimeInterval, NotchMascotItemAction)] {
        let opening: [(TimeInterval, NotchMascotItemAction)] = [(0, .react(.peek)), (0.3, .burst(.sparkles)),
                                                                (0.8, .marker(fortune.text))]
        switch fortune {
        case .lucky: return opening + [(1.6, .react(.celebrate)), (1.7, .symbol("✦", .gold, count: 2))]
        case .love: return opening + [(1.6, .react(.love)), (1.7, .symbol("♥", .pink, count: 2))]
        case .soon: return opening + [(1.6, .react(.lookAround))]
        case .yes: return opening + [(1.6, .react(.perk)), (1.7, .move(.hop))]
        case .beware: return opening + [(1.6, .react(.panic)), (1.7, .move(.shiver))]
        case .gold: return opening + [(1.6, .gold(15)), (1.8, .react(.celebrate))]
        }
    }

    /// Gold `amount` paid now when the day still has a payout left; what was
    /// paid, zero once the day's luck is spent.
    static func pay(_ amount: Int, defaults: UserDefaults = .standard, now: Date = Date()) -> Int {
        let today = NotchMascotSpecialDays.key(for: now)
        let saved = (defaults.string(forKey: DefaultsKey.notchMascotLuckPaid) ?? "").split(separator: ":")
        let paid = saved.count == 2 && String(saved[0]) == today ? Int(saved[1]) ?? 0 : 0
        guard paid < paidPerDay, amount > 0 else { return 0 }
        defaults.set("\(today):\(paid + 1)", forKey: DefaultsKey.notchMascotLuckPaid)
        return amount
    }
}
