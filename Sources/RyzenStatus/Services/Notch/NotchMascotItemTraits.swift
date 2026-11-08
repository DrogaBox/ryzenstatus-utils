// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// What a thing worn does to the companion all the while it is on, out on
/// the desktop, besides the tricks it plays with it now and then: winged
/// boots quicken its step and lift its jumps, a skateboard rolls it along
/// faster, a mushroom keeps it a little bigger, sunglasses keep a smug face
/// on it, headphones leave notes behind it as it walks. So a thing bought
/// is seen the moment it is on, and keeps being seen. Pure data, so every
/// rule is tested without a window.
struct NotchMascotItemTrait: Equatable {
    /// What it leaves behind it as it walks.
    enum Trail: Equatable {
        case sparks, notes, bubbles, petals, snow, hearts, dust, stars, drops

        /// The symbol that floats up, where the trail is drawn as one.
        var symbol: String? {
            switch self {
            case .notes: return "♪"
            case .bubbles: return "○"
            case .petals: return "✿"
            case .snow: return "❄"
            case .hearts: return "♥"
            case .stars: return "✦"
            case .drops: return "•"
            case .sparks, .dust: return nil
            }
        }
    }

    /// How many times its usual pace it walks at.
    var gait: CGFloat = 1
    /// How many times as high it jumps.
    var hop: CGFloat = 1
    /// How many times its usual size it stands.
    var scale: CGFloat = 1
    /// The face it keeps while it wears it, if the thing calls for one.
    var face: NotchMascotMood?
    var trail: Trail?

    /// A thing that changes nothing of how it goes about.
    static let plain = NotchMascotItemTrait()

    /// Between two marks of a trail as it walks.
    static let trailStep: TimeInterval = 0.42
    /// How long a face it keeps is pulled again for, each time it sets off.
    static let faceLength: TimeInterval = 6

    /// Whether this trait shows at all.
    var isPlain: Bool { self == Self.plain }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func of(_ item: NotchMascotAccessory) -> NotchMascotItemTrait {
        switch item {
        // Feet: faster, higher.
        case .wingBoots: return .init(gait: 1.25, hop: 1.35, trail: .sparks)
        case .springShoes: return .init(hop: 1.6, trail: .dust)
        case .pogoStick: return .init(gait: 0.8, hop: 1.5, trail: .dust)
        case .skateboard, .rollerSkates: return .init(gait: 1.6, trail: .sparks)
        case .pointeShoes: return .init(gait: 1.1, hop: 1.2)
        case .warmUpBooties: return .init(gait: 0.9)
        // Back and head: things that lift it.
        case .jetpack: return .init(gait: 1.2, hop: 1.5, trail: .dust)
        case .angelWings: return .init(hop: 1.3, trail: .stars)
        case .propellerCap: return .init(hop: 1.3)
        case .lonelyBalloon: return .init(gait: 0.9, hop: 1.25, trail: .hearts)
        // Size.
        case .magicMushroom: return .init(scale: 1.12)
        // Faces it keeps.
        case .sunglasses: return .init(face: .smug)
        case .crown, .kingScepter: return .init(gait: 0.85, face: .smug, trail: .stars)
        case .dumbbells: return .init(gait: 0.8, face: .determined)
        case .karateBelt: return .init(gait: 1.1, face: .determined)
        case .boxingGloves: return .init(hop: 1.15, face: .determined)
        case .knightHelm, .vikingHelm, .legendSword, .katana: return .init(face: .determined)
        case .clownNose, .whoopeeCushion, .rubberChicken: return .init(face: .mischievous)
        case .sleepMask: return .init(gait: 0.6, face: .sleepy)
        case .pacifier: return .init(gait: 0.8, face: .happy)
        case .alarmClock: return .init(gait: 1.15, face: .alert)
        case .detectiveLens, .telescope: return .init(face: .searching, trail: .stars)
        case .monocle, .wizardBeard, .magicTome: return .init(gait: 0.9, face: .thinking)
        case .tinfoilHat: return .init(face: .confused)
        case .cursedMask: return .init(face: .angry, trail: .dust)
        case .stormCloud: return .init(face: .bored, trail: .drops)
        case .matchaBowl: return .init(gait: 0.7, face: .happy)
        case .wiltedFlower, .brokenLocket, .tissueBox: return .init(gait: 0.85, face: .crying)
        case .crystalOrb, .unicornHorn, .crystalSkull: return .init(face: .starstruck, trail: .stars)
        // Music.
        case .headphones, .bardLute, .electricGuitar, .kazoo, .maracas, .drum, .microphone: return .init(trail: .notes)
        case .discoBall: return .init(gait: 1.1, face: .happy, trail: .stars)
        // Water and air.
        case .bubbleWand, .bubbleGum, .snorkelMask, .rubberDuck: return .init(trail: .bubbles)
        case .flower, .featherBoa, .spanishFan: return .init(trail: .petals)
        case .icePack, .snowGlobe, .beanie: return .init(trail: .snow)
        case .teddyBear, .heartPotion, .bow: return .init(trail: .hearts)
        case .lantern, .fireballSpell, .thunderTalisman, .laserVisor: return .init(trail: .sparks)
        case .shovel: return .init(gait: 0.9, trail: .dust)
        case .halo: return .init(gait: 0.95, face: .happy, trail: .stars)
        case .horns: return .init(gait: 1.1, face: .mischievous)
        default: return .plain
        }
    }
}

extension NotchMascotItemUse {
    // swiftlint:disable:next function_body_length
    /// The workshop's things, each with its own little show: a solo, a
    /// kata, a painting, a tea, a bout, a star, a dig and a bounce.
    static func craftUse(_ item: NotchMascotAccessory) -> NotchMascotItemUse? {
        switch item {
        case .electricGuitar:
            // A solo: a strut, sparks off the strings, and the pose at the end.
            return .init([(0, .react(.groove)), (0, .move(.strut)), (0.3, .symbol("♪", .gold, count: 4)), (1.2, .sparks),
                          (1.5, .move(.highJump)), (1.7, .marker("SOLO!")), (2.4, .face(.smug, 1.8)), (2.6, .burst(.confetti))])
        case .karateBelt:
            // A kata: three stomps, a chop, a shout and a bow.
            return .init([(0, .face(.determined, 2.6)), (0, .move(.stomp)), (1.1, .slash), (1.4, .marker("HIYA!")),
                          (1.5, .sparks), (2.2, .move(.bow)), (2.4, .react(.relax))])
        case .painterBeret:
            // It paints what it sees, on the floor, and signs it.
            return .init([(0, .face(.thinking, 1.4)), (0.2, .emote(.ellipsis)), (1.0, .move(.bow)), (1.1, .symbol("✿", .pink, count: 3)),
                          (1.6, .symbol("✦", .blue, count: 2)), (2.2, .emote(.idea)), (2.4, .marker("ART")), (2.6, .react(.celebrate))])
        case .matchaBowl:
            // Whisked, sipped, and a deep breath out.
            return .init([(0, .move(.bow)), (0.4, .symbol("~", .green, count: 3)), (1.2, .react(.sip)), (2.0, .face(.happy, 2.4)),
                          (2.2, .react(.relax)), (2.4, .emote(.ellipsis))])
        case .boxingGloves:
            // Shadow boxing, a hop on its toes, and the knockout pose.
            return .init([(0, .face(.determined, 2.8)), (0, .move(.hop)), (0.6, .move(.charge)), (1.3, .sparks),
                          (1.6, .marker("ONE-TWO")), (2.2, .move(.highJump)), (2.6, .marker("K.O.")), (2.8, .face(.smug, 1.6))])
        case .telescope:
            // A look at the sky, and a star found, whatever the hour.
            return .init([(0, .move(.sneak)), (0, .react(.peek)), (0.8, .symbol("?", .white, count: 1)), (1.6, .emote(.exclaim)),
                          (1.7, .fling(.star, back: false)), (1.9, .burst(.magic)), (2.2, .face(.starstruck, 2.0)), (2.4, .marker("STAR!"))])
        case .shovel:
            // It digs, and digs, and now and then there is treasure.
            return .init([(0, .face(.determined, 2.0)), (0, .move(.stomp)), (0.4, .burst(.smoke)), (1.0, .move(.stomp)),
                          (1.4, .burst(.smoke)), (2.0, .react(.surprised)), (2.1, .gold(20)), (2.2, .emote(.exclaim)),
                          (2.4, .react(.celebrate))])
        case .pogoStick:
            // Boing, boing, boing, and one more than it meant.
            return .init([(0, .react(.perk)), (0.2, .move(.hop)), (0.9, .move(.hop)), (1.6, .move(.highJump)),
                          (1.8, .marker("BOING")), (2.6, .move(.hop)), (3.0, .face(.dizzy, 1.4)), (3.1, .emote(.question))])
        default:
            return nil
        }
    }
}
