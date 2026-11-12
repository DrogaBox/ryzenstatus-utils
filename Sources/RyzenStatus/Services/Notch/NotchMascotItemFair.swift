// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The fair and the field. Each of the twenty-four has what it does to the
/// companion all the while it is worn (a sugar rush from the lollipop, a
/// slow drifting step under the astronaut's helmet, stilts that make it
/// taller and wobblier), a little show it puts on now and then, out on the
/// desktop or resting in the island, and, for some figures, a show of their
/// own. Pure data, so every rule is tested without a window.
extension NotchMascotItemTrait {
    // swiftlint:disable:next cyclomatic_complexity
    static func fair(_ item: NotchMascotAccessory) -> NotchMascotItemTrait? {
        switch item {
        case .fishingRod: return .init(gait: 0.9, face: .thinking, trail: .drops)
        case .butterflyNet: return .init(gait: 1.15, hop: 1.1, trail: .petals)
        case .wateringCan: return .init(gait: 0.9, trail: .drops)
        case .pottedCactus: return .init(gait: 0.85, face: .embarrassed)
        case .fryingPan: return .init(face: .determined, trail: .dust)
        case .cupcake: return .init(face: .happy, trail: .hearts)
        // A sugar rush: quicker, bouncier, and very pleased about it.
        case .lollipop: return .init(gait: 1.3, hop: 1.2, face: .happy)
        case .trumpet: return .init(gait: 1.05, trail: .notes)
        case .violin: return .init(gait: 0.85, face: .bored, trail: .notes)
        case .basketball: return .init(hop: 1.3, trail: .dust)
        case .puzzleCube: return .init(gait: 0.9, face: .thinking)
        case .answerBall: return .init(face: .searching, trail: .stars)
        case .pinwheel: return .init(gait: 1.2, trail: .sparks)
        case .slingshot: return .init(face: .mischievous)
        case .balloonDog: return .init(hop: 1.15, trail: .hearts)
        case .sparkler: return .init(face: .starstruck, trail: .sparks)
        case .boomBox: return .init(gait: 1.1, face: .smug, trail: .notes)
        case .hardHat: return .init(gait: 0.9, face: .determined, trail: .dust)
        // Low gravity: a slow, drifting step and jumps that hang in the air.
        case .astronautHelmet: return .init(gait: 0.8, hop: 1.5, trail: .stars)
        case .graduationCap: return .init(face: .smug, trail: .stars)
        case .flowerCrown: return .init(face: .happy, trail: .petals)
        case .binoculars: return .init(face: .searching)
        case .superCape: return .init(gait: 1.3, hop: 1.4, face: .determined, trail: .stars)
        // Taller on stilts, and slower about it.
        case .stilts: return .init(gait: 0.75, scale: 1.12)
        default: return nil
        }
    }
}

extension NotchMascotItemUse {
    /// The magic ball's answers, as arcade markers.
    static let answers = ["YES", "NO", "MAYBE", "LATER", "SURELY", "NOPE"]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// The fair's things, each with its own little show. `random` decides
    /// what luck brings: a fish or a boot, a dunk or a miss, the ball's answer.
    static func fairUse(_ item: NotchMascotAccessory,
                        random: () -> Double = { Double.random(in: 0..<1) }) -> NotchMascotItemUse? {
        switch item {
        case .fishingRod:
            // A cast, a long wait, a bite: a fish now and then, else an old boot.
            if random() < 0.6 {
                return .init([(0, .move(.sneak)), (0.2, .react(.peek)), (0.6, .symbol("~", .blue, count: 2)),
                              (1.6, .emote(.exclaim)), (1.7, .move(.hop)), (1.9, .marker("FISH!")),
                              (2.3, .emote(.thought("><>"))), (2.4, .gold(15)), (2.6, .react(.celebrate))])
            }
            return .init([(0, .move(.sneak)), (0.2, .react(.peek)), (0.6, .symbol("~", .blue, count: 2)),
                          (1.6, .emote(.exclaim)), (1.7, .move(.hop)), (2.0, .marker("BOOT?")),
                          (2.2, .face(.disgusted, 1.6)), (2.4, .emote(.ellipsis))])
        case .butterflyNet:
            // A chase, a leap, a catch, and it lets the butterfly go.
            return .init([(0, .react(.perk)), (0.2, .move(.charge)), (0.5, .symbol("✿", .pink, count: 2)),
                          (1.3, .move(.highJump)), (1.6, .marker("GOTCHA")), (2.0, .face(.love, 1.6)),
                          (2.2, .symbol("♥", .pink, count: 1))])
        case .wateringCan:
            // It waters the floor, and a flower comes up.
            return .init([(0, .move(.bow)), (0.2, .symbol("•", .blue, count: 4)), (1.4, .symbol("✿", .green, count: 3)),
                          (1.8, .emote(.exclaim)), (2.0, .face(.happy, 1.6)), (2.1, .burst(.sparkles))])
        case .pottedCactus:
            // A hug for its prickly friend, and the price of it.
            return .init([(0, .react(.love)), (0.4, .emote(.heart)), (1.0, .marker("OUCH!")), (1.0, .react(.surprised)),
                          (1.1, .move(.hop)), (1.4, .face(.crying, 1.6)), (2.2, .emote(.ellipsis))])
        case .fryingPan:
            // A pancake in the air: caught most times, on its head the rest.
            if random() < 0.7 {
                return .init([(0, .face(.determined, 1.6)), (0.3, .fling(.cookie, back: true)), (2.0, .marker("FLIP!")),
                              (2.2, .react(.celebrate))])
            }
            return .init([(0, .face(.determined, 1.6)), (0.3, .fling(.cookie, back: false)), (1.2, .marker("SPLAT")),
                          (1.3, .react(.surprised)), (1.5, .face(.embarrassed, 1.6))])
        case .cupcake:
            // A candle, a wish, and the cupcake is gone in one bite.
            return .init([(0, .react(.perk)), (0.3, .sparks), (0.8, .emote(.thought("★"))), (1.5, .marker("WISH")),
                          (1.8, .hide(8)), (2.0, .face(.happy, 1.6)), (2.1, .symbol("♥", .pink, count: 2))])
        case .lollipop:
            // One lick and off it goes, faster and faster, and dizzy.
            return .init([(0, .react(.perk)), (0.3, .symbol("~", .pink, count: 2)), (1.0, .move(.charge)),
                          (1.6, .move(.spin)), (2.2, .marker("SUGAR!")), (2.4, .face(.dizzy, 1.4))])
        case .trumpet:
            return .init([(0, .move(.strut)), (0.2, .marker("TA-DAA!")), (0.3, .symbol("♪", .gold, count: 3)),
                          (1.3, .burst(.confetti)), (1.6, .move(.bow))])
        case .violin:
            // The saddest song, and it moves itself to tears.
            return .init([(0, .react(.relax)), (0.2, .symbol("♪", .blue, count: 3)), (1.2, .face(.crying, 2.0)),
                          (1.4, .emote(.ellipsis)), (2.6, .move(.bow))])
        case .basketball:
            // A dribble, a leap for the dunk: swish, or clank off the rim.
            if random() < 0.65 {
                return .init([(0, .react(.ready)), (0.2, .juggle(.ball)), (1.0, .move(.highJump)), (1.3, .marker("SWISH!")),
                              (1.4, .burst(.confetti)), (1.8, .face(.smug, 1.4))])
            }
            return .init([(0, .react(.ready)), (0.2, .juggle(.ball)), (1.0, .move(.highJump)), (1.3, .marker("CLANK")),
                          (1.5, .face(.embarrassed, 1.4)), (1.6, .emote(.curse))])
        case .puzzleCube:
            // It twists and twists: solved now and then, else it gives up.
            if random() < 0.5 {
                return .init([(0, .face(.thinking, 2.2)), (0.3, .emote(.ellipsis)), (1.2, .symbol("✦", .white, count: 2)),
                              (2.2, .emote(.idea)), (2.4, .marker("SOLVED!")), (2.5, .react(.celebrate))])
            }
            return .init([(0, .face(.thinking, 2.2)), (0.3, .emote(.ellipsis)), (1.6, .face(.angry, 1.4)),
                          (1.8, .emote(.curse)), (2.2, .marker("ARGH"))])
        case .answerBall:
            // Shaken, asked, and its answer rises out of the ball.
            let answer = answers[min(answers.count - 1, Int(random() * Double(answers.count)))]
            return .init([(0, .move(.shiver)), (0.8, .emote(.thought("8"))), (1.4, .marker(answer)),
                          (1.6, .react(answer == "NO" || answer == "NOPE" ? .confused : .perk))])
        case .pinwheel:
            return .init([(0, .move(.charge)), (0.3, .symbol("✦", .white, count: 2)), (1.2, .move(.spin)),
                          (2.0, .react(.celebrate)), (2.1, .marker("WHEEE"))])
        case .slingshot:
            // It aims at nothing, hits something, and whistles innocently.
            return .init([(0, .face(.mischievous, 1.6)), (0.4, .fling(.ball, back: false)), (1.3, .marker("PLINK")),
                          (1.4, .emote(.exclaim)), (1.6, .move(.sneak))])
        case .balloonDog:
            // Twisted into a dog, loved, and popped.
            return .init([(0, .react(.perk)), (0.3, .symbol("~", .pink, count: 2)), (1.2, .marker("SQUEAK")),
                          (1.6, .react(.love)), (2.2, .marker("POP!")), (2.3, .react(.surprised)), (2.4, .hide(10)),
                          (2.6, .face(.crying, 1.4))])
        case .sparkler:
            return .init([(0, .react(.perk)), (0.2, .sparks), (0.5, .symbol("✦", .gold, count: 4)), (1.4, .move(.spin)),
                          (1.6, .sparks), (2.0, .burst(.sparkles)), (2.2, .face(.starstruck, 1.4))])
        case .boomBox:
            // It drops the beat, spins on its head and lands the freeze.
            return .init([(0, .react(.groove)), (0.2, .symbol("♫", .purple, count: 3)), (0.8, .move(.spin)),
                          (1.6, .move(.backflip)), (2.6, .marker("FRESH!")), (2.7, .face(.smug, 1.6))])
        case .hardHat:
            // Bonk, bonk: a tower goes up, and comes down.
            return .init([(0, .face(.determined, 2.0)), (0.2, .move(.stomp)), (0.5, .marker("BONK")), (1.0, .move(.stomp)),
                          (1.3, .marker("BONK")), (1.8, .burst(.smoke)), (2.0, .react(.surprised)), (2.2, .emote(.curse))])
        case .astronautHelmet:
            // One small step, floating, and a giant leap.
            return .init([(0, .react(.perk)), (0.3, .move(.float)), (0.5, .symbol("✦", .white, count: 3)),
                          (1.8, .marker("LIFTOFF")), (2.2, .move(.highJump)), (2.6, .face(.starstruck, 1.6))])
        case .graduationCap:
            // A bow, the cap thrown to the sky and caught again.
            return .init([(0, .move(.bow)), (0.6, .fling(.star, back: true)), (1.2, .burst(.confetti)),
                          (1.4, .marker("GRAD!")), (2.0, .face(.smug, 1.6))])
        case .flowerCrown:
            return .init([(0, .react(.love)), (0.2, .symbol("✿", .pink, count: 3)), (1.0, .move(.spin)),
                          (1.6, .emote(.heart)), (1.8, .face(.happy, 1.6))])
        case .binoculars:
            // A long look about, and a bird spotted far away.
            return .init([(0, .react(.peek)), (0.3, .move(.sneak)), (1.0, .symbol("?", .white, count: 1)),
                          (1.8, .emote(.exclaim)), (1.9, .marker("BIRD!")), (2.1, .react(.surprised))])
        case .superCape:
            // Up, up and away, and the pose a hero lands in.
            return .init([(0, .face(.determined, 1.4)), (0.2, .marker("UP!")), (0.3, .move(.highJump)),
                          (0.9, .move(.float)), (1.6, .symbol("✦", .gold, count: 3)), (2.2, .move(.strut)),
                          (2.4, .face(.smug, 1.4))])
        case .stilts:
            // Proud up there, a wobble, and down it comes.
            return .init([(0, .react(.perk)), (0.3, .move(.strut)), (1.0, .move(.shiver)), (1.4, .marker("WOBBLE")),
                          (1.8, .move(.slip)), (2.0, .burst(.smoke)), (2.1, .face(.dizzy, 1.4))])
        default:
            return nil
        }
    }
}

extension NotchMascotItemTwists {
    // swiftlint:disable:next function_body_length
    /// The figures with a way of their own with a thing from the fair.
    static let fairTable: [(pair: Pair, steps: [(TimeInterval, NotchMascotItemAction)])] = [
        // The cat fishes, and the fish never gets as far as the bucket.
        (Pair(style: .cat, item: .fishingRod),
         [(0, .move(.sneak)), (0.4, .face(.mischievous, 1.4)), (1.4, .emote(.exclaim)), (1.6, .marker("FISH!")),
          (1.8, .hide(8)), (2.0, .marker("NOM")), (2.2, .face(.smug, 1.8))]),
        // The penguin needs no rod: in it dives, and out it comes with dinner.
        (Pair(style: .penguin, item: .fishingRod),
         [(0, .react(.perk)), (0.3, .move(.slip)), (0.8, .symbol("○", .blue, count: 3)), (1.6, .move(.highJump)),
          (1.9, .emote(.thought("><>"))), (2.0, .gold(20)), (2.2, .react(.celebrate))]),
        // The frog drops the net and catches the butterfly its own way.
        (Pair(style: .frog, item: .butterflyNet),
         [(0, .react(.peek)), (0.6, .face(.mischievous, 1.2)), (1.0, .marker("SHLURP")), (1.2, .react(.surprised)),
          (1.6, .emote(.question)), (2.0, .face(.embarrassed, 1.4))]),
        // A dragon lights the sparkler with a breath, and singes its own nose.
        (Pair(style: .dragon, item: .sparkler),
         [(0, .react(.ready)), (0.3, .sparks), (0.4, .burst(.smoke)), (0.8, .symbol("✦", .gold, count: 5)),
          (1.6, .marker("FWOOSH")), (1.8, .face(.terrified, 1.2)), (2.2, .react(.celebrate))]),
        // The kitsune's sparkler burns blue with foxfire.
        (Pair(style: .kitsune, item: .sparkler),
         [(0, .react(.perk)), (0.3, .burst(.magic)), (0.5, .symbol("✦", .blue, count: 4)), (1.4, .move(.spin)),
          (2.0, .marker("FOXFIRE")), (2.2, .face(.starstruck, 1.4))]),
        // The robot solves the cube before anyone can blink.
        (Pair(style: .robot, item: .puzzleCube),
         [(0, .face(.determined, 0.8)), (0.2, .sparks), (0.5, .marker("0.3S")), (0.7, .burst(.sparkles)),
          (1.0, .face(.smug, 1.8)), (1.2, .move(.bow))]),
        // The chip asks the ball and gets an error back.
        (Pair(style: .chip, item: .answerBall),
         [(0, .move(.shiver)), (0.6, .lightning), (0.8, .marker("ERR-8")), (1.0, .react(.confused)),
          (1.6, .emote(.interrobang))]),
        // The axolotl waters itself first, and is very happy about it.
        (Pair(style: .axolotl, item: .wateringCan),
         [(0, .react(.perk)), (0.3, .symbol("•", .blue, count: 4)), (1.0, .move(.spin)), (1.4, .marker("SPLASH")),
          (1.8, .face(.love, 1.8)), (2.0, .symbol("○", .blue, count: 2))]),
        // The capybara waters the orange on its head. It grows.
        (Pair(style: .capybara, item: .wateringCan),
         [(0, .react(.relax)), (0.4, .symbol("•", .blue, count: 3)), (1.4, .grow(5)), (1.6, .marker("ZEN")),
          (2.0, .face(.happy, 1.8))]),
        // The slime hugs the cactus and simply absorbs it.
        (Pair(style: .slime, item: .pottedCactus),
         [(0, .react(.love)), (0.4, .move(.shiver)), (1.0, .marker("GLORP")), (1.1, .hide(9)), (1.6, .face(.smug, 1.6)),
          (2.0, .emote(.question))]),
        // The devourer does not wait for a wish: the cupcake, the plate, all of it.
        (Pair(style: .devourer, item: .cupcake),
         [(0, .react(.perk)), (0.3, .face(.greedy, 1.4)), (0.8, .marker("GULP")), (0.9, .hide(10)), (1.2, .burst(.hearts)),
          (1.8, .marker("+500"))]),
        // The mouse finds the cupcake is cheesecake, and is overjoyed.
        (Pair(style: .mouse, item: .cupcake),
         [(0, .react(.peek)), (0.4, .face(.greedy, 1.4)), (1.0, .marker("CHEESE!")), (1.2, .hide(8)),
          (1.4, .face(.love, 1.8)), (1.6, .symbol("♥", .pink, count: 3))]),
        // The dog brings the basketball back. Every time.
        (Pair(style: .dog, item: .basketball),
         [(0, .react(.perk)), (0.2, .fling(.ball, back: true)), (2.0, .marker("FETCH!")), (2.2, .react(.love)),
          (2.4, .fling(.ball, back: true))]),
        // The fan blows its own wind into the pinwheel, far too hard.
        (Pair(style: .fan, item: .pinwheel),
         [(0, .react(.ready)), (0.3, .move(.spin)), (0.8, .symbol("✦", .white, count: 4)), (1.4, .marker("WHIRR")),
          (1.6, .move(.spin)), (2.2, .face(.dizzy, 1.4))]),
        // The android drops the beat and dances like a machine.
        (Pair(style: .android, item: .boomBox),
         [(0, .react(.groove)), (0.2, .symbol("♫", .blue, count: 3)), (0.8, .move(.stomp)), (1.4, .move(.stomp)),
          (2.0, .marker("BEEP-BOP")), (2.2, .face(.smug, 1.4))]),
        // The hologram in a helmet: a spacewalk in light.
        (Pair(style: .hologram, item: .astronautHelmet),
         [(0, .react(.perk)), (0.3, .move(.float)), (0.6, .burst(.magic)), (1.2, .symbol("✦", .blue, count: 4)),
          (2.0, .marker("ORBIT")), (2.4, .face(.starstruck, 1.6))]),
        // The swan in a crown of flowers glides, and bows.
        (Pair(style: .swan, item: .flowerCrown),
         [(0, .move(.float)), (0.4, .symbol("✿", .pink, count: 3)), (1.4, .move(.bow)), (1.6, .marker("GRACE")),
          (2.0, .face(.love, 1.6))]),
        // The phoenix in a cape: it hardly needs one, and flies anyway.
        (Pair(style: .phoenix, item: .superCape),
         [(0, .react(.ready)), (0.3, .move(.highJump)), (0.8, .burst(.smoke)), (1.0, .sparks), (1.4, .move(.float)),
          (2.0, .marker("BLAZE")), (2.2, .face(.smug, 1.4))]),
        // The ballerina on stilts keeps her balance, en pointe, of course.
        (Pair(style: .ballerina, item: .stilts),
         [(0, .react(.perk)), (0.3, .move(.spin)), (1.2, .move(.bow)), (1.4, .marker("POINTE")),
          (1.8, .face(.smug, 1.4))]),
        // The ghost with binoculars spots another ghost, and is terrified.
        (Pair(style: .ghost, item: .binoculars),
         [(0, .react(.peek)), (0.6, .move(.sneak)), (1.4, .emote(.exclaim)), (1.5, .face(.terrified, 1.6)),
          (1.6, .marker("BOO?")), (2.2, .move(.backflip))]),
    ]
}
