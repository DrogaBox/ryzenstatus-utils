// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The lab and the mayhem. Each of the forty-eight has its price in the
/// shop, what it does to the companion all the while it is worn (a slow
/// sticky step with the honey, a giddy rush with the battery pack, sky-high
/// jumps on the trampoline), a little show it puts on now and then, and for
/// some figures a show of their own: the dragon swallows the torch's flame,
/// the cat loses its mind over the red dot, the ghost is sucked into its own
/// trap. Some things draw visitors in, and some make a fusion of their own.
/// Pure data, so every rule is tested without a window.
extension NotchMascotAccessory {
    // swiftlint:disable:next cyclomatic_complexity
    /// How rare the lab's and the mayhem's things are in the shop; nil for
    /// everything else, which keeps the rarity it always had.
    static func labRarity(_ item: NotchMascotAccessory) -> NotchMascotRarity? {
        switch item {
        case .torch, .waterBalloon, .pepperShaker, .squeakyHammer, .popcornBucket, .seedPacket, .rubberBoots,
             .windChime, .hotCocoa, .honeyJar, .airHorn, .tickleFeather, .stickyHand, .bubbleWrap, .compass,
             .jelly, .raincoat, .garlicNecklace, .icePop:
            return .common
        case .leafBlower, .laserPointer, .tuningFork, .fireExtinguisher, .pocketMirror, .fishBowl, .iceSkates,
             .gasMask, .jackInTheBox, .slimeBlaster, .hotSauce, .metalDetector, .tapShoes, .cheeseWheel, .lavaLamp:
            return .uncommon
        case .plasmaBall, .freezeRay, .lightningRod, .pinata, .bubblingFlask, .giantMagnet, .hypnoSpiral,
             .fireworkRocket, .batteryPack, .trampoline, .ghostTrap:
            return .rare
        case .mysteryEgg, .bigRedButton, .voodooDoll:
            return .legendary
        default:
            return nil
        }
    }
}

extension NotchMascotItemTrait {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func lab(_ item: NotchMascotAccessory) -> NotchMascotItemTrait? {
        switch item {
        // The lab.
        case .torch: return .init(face: .searching, trail: .sparks)
        // Heavy and wobbling: it walks carefully, with mischief in mind.
        case .waterBalloon: return .init(gait: 0.9, face: .mischievous, trail: .drops)
        case .leafBlower: return .init(gait: 1.15, face: .determined, trail: .dust)
        case .plasmaBall: return .init(face: .starstruck, trail: .sparks)
        case .freezeRay: return .init(gait: 0.9, face: .mischievous, trail: .snow)
        // Forever after the red dot.
        case .laserPointer: return .init(gait: 1.25, hop: 1.1, face: .searching, trail: .sparks)
        case .tuningFork: return .init(gait: 0.95, face: .thinking, trail: .notes)
        // A sneeze always on its way.
        case .pepperShaker: return .init(gait: 0.95, face: .embarrassed, trail: .dust)
        case .squeakyHammer: return .init(hop: 1.1, face: .mischievous, trail: .stars)
        case .popcornBucket: return .init(gait: 0.9, face: .greedy)
        // It carries the egg as if it might break, and listens to it.
        case .mysteryEgg: return .init(gait: 0.8, face: .searching)
        case .seedPacket: return .init(gait: 0.9, trail: .petals)
        case .fireExtinguisher: return .init(gait: 0.85, face: .alert, trail: .bubbles)
        // The rod makes it a little taller, and it keeps one eye on the sky.
        case .lightningRod: return .init(scale: 1.06, face: .alert, trail: .sparks)
        // Big boots: a heavy step and short jumps.
        case .rubberBoots: return .init(gait: 0.8, trail: .drops)
        case .pocketMirror: return .init(face: .smug, trail: .stars)
        case .windChime: return .init(gait: 0.9, face: .happy, trail: .notes)
        case .fishBowl: return .init(gait: 0.8, trail: .bubbles)
        case .hotCocoa: return .init(gait: 0.8, face: .happy, trail: .hearts)
        // On blades it glides.
        case .iceSkates: return .init(gait: 1.4, trail: .snow)
        case .gasMask: return .init(gait: 0.9, face: .determined, trail: .dust)
        case .pinata: return .init(gait: 0.9, hop: 1.1, face: .happy)
        case .bubblingFlask: return .init(face: .mischievous, trail: .bubbles)
        case .jackInTheBox: return .init(gait: 0.95, face: .alert, trail: .notes)
        // The mayhem.
        case .giantMagnet: return .init(gait: 0.85, face: .greedy, trail: .sparks)
        // Sticky feet: the slowest walk there is, and a happy one.
        case .honeyJar: return .init(gait: 0.75, face: .love, trail: .drops)
        case .slimeBlaster: return .init(face: .mischievous, trail: .drops)
        case .airHorn: return .init(gait: 1.1, hop: 1.1, face: .mischievous)
        // Hypnotised: a slow zombie shuffle with stars in its head.
        case .hypnoSpiral: return .init(gait: 0.7, face: .dizzy, trail: .stars)
        case .tickleFeather: return .init(gait: 1.1, hop: 1.15, face: .happy)
        // Fire in its mouth, and it runs about with it.
        case .hotSauce: return .init(gait: 1.2, face: .angry, trail: .sparks)
        // It carries the button as if it were a bomb, and it might be.
        case .bigRedButton: return .init(gait: 0.9, face: .alert)
        case .stickyHand: return .init(gait: 1.05, face: .mischievous, trail: .drops)
        case .fireworkRocket: return .init(gait: 1.1, face: .starstruck, trail: .sparks)
        case .bubbleWrap: return .init(face: .happy, trail: .bubbles)
        case .metalDetector: return .init(gait: 0.8, face: .searching, trail: .dust)
        case .compass: return .init(gait: 0.9, face: .confused)
        // Fully charged: quick and springy.
        case .batteryPack: return .init(gait: 1.25, hop: 1.1, trail: .sparks)
        case .tapShoes: return .init(gait: 1.1, hop: 1.1, trail: .notes)
        case .jelly: return .init(hop: 1.2, face: .happy)
        // Every jump goes sky-high.
        case .trampoline: return .init(hop: 1.7, trail: .dust)
        case .raincoat: return .init(gait: 0.95, face: .smug, trail: .drops)
        case .garlicNecklace: return .init(gait: 0.9, face: .disgusted)
        case .voodooDoll: return .init(gait: 0.85, face: .mischievous)
        // A whole wheel of cheese is no light thing to carry.
        case .cheeseWheel: return .init(gait: 0.8, face: .greedy)
        case .ghostTrap: return .init(gait: 0.9, face: .determined, trail: .sparks)
        case .lavaLamp: return .init(gait: 0.75, face: .happy, trail: .bubbles)
        case .icePop: return .init(face: .happy, trail: .snow)
        default: return nil
        }
    }
}

extension NotchMascotItemUse {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// The lab's and the mayhem's things, each with its own little show.
    /// `random` decides what luck brings: a dry catch or a soaking, a coin or
    /// a bottle cap, what the big red button does this time.
    static func labUse(_ item: NotchMascotAccessory,
                       random: () -> Double = { Double.random(in: 0..<1) }) -> NotchMascotItemUse? {
        switch item {
        case .torch:
            // Shadow puppets on the wall: a bird, a dog, and the dog barks.
            return .init([(0, .react(.perk)), (0.2, .sparks), (0.5, .symbol("♪", .white, count: 1)),
                          (1.2, .symbol("!", .white, count: 1)), (1.9, .marker("WOOF")), (2.1, .sparks),
                          (2.3, .face(.smug, 1.4))])
        case .waterBalloon:
            // Up and caught, up and caught, and now and then right on its head.
            if random() < 0.25 {
                return .init([(0, .face(.mischievous, 1.0)), (0.2, .juggle(.drop)), (1.0, .juggle(.drop)),
                              (1.8, .marker("SPLOOSH")), (1.9, .symbol("•", .blue, count: 5)), (2.0, .react(.surprised)),
                              (2.2, .face(.crying, 1.6)), (2.6, .move(.shiver))])
            }
            return .init([(0, .face(.mischievous, 1.0)), (0.2, .juggle(.drop)), (1.0, .juggle(.drop)),
                          (1.8, .marker("CATCH")), (2.0, .face(.smug, 1.4)), (2.1, .emote(.exclaim))])
        case .leafBlower:
            // The leaves go one way and the companion, by the recoil, the other.
            return .init([(0, .face(.determined, 1.2)), (0.2, .marker("VRRRM")), (0.3, .symbol("❦", .gold, count: 4)),
                          (1.0, .move(.slip)), (1.4, .burst(.smoke)), (1.8, .react(.surprised)), (2.2, .face(.dizzy, 1.4))])
        case .plasmaBall:
            // One finger on the glass: the hair stands up and the eyes fill with stars.
            return .init([(0, .react(.peek)), (0.4, .lightning), (0.5, .move(.shiver)), (0.6, .marker("ZZZAP")),
                          (1.2, .lightning), (1.4, .symbol("⚡", .purple, count: 3)), (2.0, .face(.starstruck, 1.6))])
        case .freezeRay:
            // A careless aim, a frozen foot, and down it goes.
            return .init([(0, .face(.mischievous, 1.0)), (0.3, .symbol("❄", .blue, count: 3)), (0.8, .marker("OOPS")),
                          (1.0, .face(.surprised, 1.0)), (1.2, .move(.shiver)), (2.0, .move(.slip)), (2.4, .face(.dizzy, 1.4))])
        case .laserPointer:
            // Round and round after its own red dot, and never catching it.
            return .init([(0, .react(.perk)), (0.2, .symbol("•", .pink, count: 1)), (0.4, .move(.charge)),
                          (1.9, .move(.spin)), (2.2, .marker("DOT!")), (3.0, .move(.spin)), (3.2, .face(.dizzy, 1.4))])
        case .tuningFork:
            // Struck once, it hums, and the companion hums along to the bone.
            return .init([(0, .react(.ready)), (0.2, .marker("TING")), (0.3, .symbol("♪", .white, count: 2)),
                          (0.8, .move(.shiver)), (1.7, .move(.shiver)), (2.0, .marker("MMMMM")), (2.6, .face(.dizzy, 1.2))])
        case .pepperShaker:
            // A sniff, the long breath in, and a sneeze that blows it backwards.
            return .init([(0, .react(.peek)), (0.3, .symbol("·", .white, count: 3)), (0.8, .marker("AH...")),
                          (1.2, .face(.embarrassed, 0.6)), (1.6, .marker("ACHOO!")), (1.6, .burst(.smoke)),
                          (1.7, .move(.slip)), (2.4, .face(.dizzy, 1.4))])
        case .squeakyHammer:
            // A bonk on its own head, a squeak, and stars going round.
            return .init([(0, .face(.mischievous, 1.0)), (0.5, .move(.hop)), (0.6, .marker("SQUEAK")),
                          (0.7, .symbol("✦", .gold, count: 3)), (1.4, .react(.surprised)), (1.6, .face(.dizzy, 1.6)),
                          (2.4, .emote(.question))])
        case .popcornBucket:
            // Munching away, until one kernel pops right in its face.
            return .init([(0, .react(.sip)), (0.2, .symbol("☁", .white, count: 3)), (1.0, .face(.happy, 0.8)),
                          (1.6, .marker("POP!")), (1.7, .react(.surprised)), (1.9, .move(.hop)), (2.4, .face(.embarrassed, 1.2))])
        case .mysteryEgg:
            // An ear to the shell: it wobbles and something knocks. Once in a
            // while a crack shows instead, and then nothing more happens.
            if random() < 0.1 {
                return .init([(0, .react(.peek)), (0.3, .face(.searching, 1.4)), (1.0, .move(.shiver)),
                              (1.6, .marker("CRACK?")), (1.8, .burst(.sparkles)), (2.0, .face(.starstruck, 1.0)),
                              (2.8, .emote(.ellipsis))])
            }
            return .init([(0, .react(.peek)), (0.3, .face(.searching, 1.4)), (1.0, .move(.shiver)),
                          (1.4, .marker("KNOCK")), (2.2, .marker("KNOCK")), (2.4, .emote(.interrobang)),
                          (2.6, .react(.surprised))])
        case .seedPacket:
            // A seed in the ground, a wait, a longer wait, and a sprout the size of a pin.
            return .init([(0, .move(.bow)), (0.3, .symbol("•", .gold, count: 1)), (1.0, .emote(.ellipsis)),
                          (1.4, .face(.bored, 0.8)), (2.2, .symbol("✿", .green, count: 1)), (2.4, .marker("SPROUT")),
                          (2.6, .face(.starstruck, 1.4))])
        case .fireExtinguisher:
            // The pin comes out by accident, and the foam goes everywhere.
            return .init([(0, .react(.peek)), (0.4, .marker("PING")), (0.6, .emote(.exclaim)), (1.0, .marker("FWOOSH")),
                          (1.0, .symbol("○", .white, count: 5)), (1.1, .move(.slip)), (1.9, .burst(.smoke)),
                          (2.3, .face(.embarrassed, 1.6))])
        case .lightningRod:
            // Out of a clear sky a spark finds the rod, and its hair stands on end.
            return .init([(0, .react(.lookAround)), (0.8, .lightning), (0.9, .react(.surprised)), (1.0, .marker("ZAP!")),
                          (1.2, .move(.shiver)), (1.4, .sparks), (2.2, .face(.starstruck, 1.4))])
        case .rubberBoots:
            // Every puddle stomped, one after the other.
            return .init([(0, .face(.happy, 1.0)), (0.2, .move(.stomp)), (0.4, .symbol("•", .blue, count: 3)),
                          (1.3, .move(.stomp)), (1.5, .marker("SPLASH")), (1.6, .symbol("•", .blue, count: 3)),
                          (2.4, .move(.hop)), (2.6, .face(.smug, 1.4))])
        case .pocketMirror:
            // It admires itself, and the sun bounces off the glass into its eyes.
            return .init([(0, .face(.smug, 1.2)), (0.2, .emote(.heart)), (0.6, .symbol("✦", .white, count: 2)),
                          (1.2, .react(.flash)), (1.3, .burst(.sparkles)), (1.4, .marker("BLIND!")),
                          (1.6, .face(.dizzy, 1.6)), (2.0, .move(.hop))])
        case .windChime:
            // A gentle tinkle, and it is so relaxed it nods off.
            return .init([(0, .react(.relax)), (0.2, .symbol("♪", .white, count: 3)), (1.0, .marker("TINKLE")),
                          (1.4, .move(.float)), (2.0, .face(.happy, 1.0)), (2.8, .doze(4))])
        case .fishBowl:
            // The fish blows bubbles, and kisses the glass where its face is.
            return .init([(0, .react(.peek)), (0.3, .symbol("○", .blue, count: 3)), (1.2, .emote(.thought("><>"))),
                          (1.4, .marker("BLUB")), (2.2, .marker("MWAH")), (2.3, .symbol("♥", .pink, count: 1)),
                          (2.4, .face(.love, 1.4))])
        case .hotCocoa:
            // A sip, a marshmallow, and the happiest sigh.
            return .init([(0, .react(.sip)), (0.4, .symbol("~", .white, count: 2)), (1.0, .symbol("☁", .white, count: 1)),
                          (1.4, .marker("MMM")), (1.6, .face(.love, 1.6)), (2.4, .react(.relax))])
        case .iceSkates:
            // A perfect pirouette, a smug look, and then the wobble.
            return .init([(0, .move(.spin)), (0.3, .symbol("❄", .white, count: 2)), (1.1, .marker("TA-DA")),
                          (1.2, .face(.smug, 0.6)), (1.6, .move(.shiver)), (2.4, .move(.slip)), (2.8, .face(.embarrassed, 1.4))])
        case .gasMask:
            // Muffled breathing, and a friendly wave from behind the glass.
            return .init([(0, .react(.wave)), (0.3, .marker("KSHHH")), (0.6, .symbol("○", .white, count: 2)),
                          (1.3, .marker("KOOOH")), (1.6, .move(.sneak)), (3.1, .react(.wave))])
        case .pinata:
            // It hugs its friend on the stick, and swings it round and round.
            return .init([(0, .react(.love)), (0.4, .emote(.heart)), (1.0, .move(.spin)), (1.4, .marker("WHEE")),
                          (1.6, .symbol("✦", .gold, count: 2)), (2.2, .face(.happy, 1.4))])
        case .bubblingFlask:
            // Down in one, and the brew decides: bigger, a burp, or a head full of sparks.
            let roll = random()
            let drink: [(TimeInterval, NotchMascotItemAction)] = [
                (0, .react(.sip)), (0.3, .hide(6)), (0.5, .symbol("○", .green, count: 3)), (1.0, .emote(.ellipsis))]
            let effect: [(TimeInterval, NotchMascotItemAction)]
            if roll < 0.34 {
                effect = [(1.4, .grow(6)), (1.4, .burst(.magic)), (1.6, .marker("BIG!")), (1.8, .react(.celebrate))]
            } else if roll < 0.67 {
                effect = [(1.4, .burst(.smoke)), (1.5, .marker("BURP")), (1.6, .face(.embarrassed, 1.4))]
            } else {
                effect = [(1.4, .lightning), (1.5, .marker("WHAT?")), (1.6, .face(.dizzy, 1.6)), (2.0, .move(.spin))]
            }
            return .init(drink + effect)
        case .jackInTheBox:
            // Wound up, the tune plays, and the jack frightens the one who wound it.
            return .init([(0, .react(.ready)), (0.2, .symbol("♪", .gold, count: 3)), (1.4, .emote(.ellipsis)),
                          (1.8, .marker("BOING!")), (1.8, .react(.surprised)), (1.9, .move(.highJump)),
                          (2.2, .face(.terrified, 1.4))])
        case .giantMagnet:
            // Coins come flying to it now and then; a fork, the rest of the time, to its nose.
            if random() < 0.4 {
                return .init([(0, .react(.ready)), (0.3, .sparks), (0.6, .fling(.coin, back: true)), (2.4, .gold(5)),
                              (2.6, .face(.greedy, 1.4))])
            }
            return .init([(0, .react(.ready)), (0.3, .sparks), (0.6, .fling(.key, back: true)), (2.4, .marker("CLANK")),
                          (2.5, .react(.surprised)), (2.7, .face(.embarrassed, 1.2))])
        case .honeyJar:
            // A finger in the honey, a finger stuck to everything, and a long lick.
            return .init([(0, .face(.greedy, 1.0)), (0.3, .symbol("•", .gold, count: 2)), (1.0, .marker("STICKY")),
                          (1.2, .move(.shiver)), (2.2, .marker("SLURP")), (2.4, .face(.love, 1.6))])
        case .slimeBlaster:
            // It fires, and the goo comes straight back into its face.
            return .init([(0, .face(.mischievous, 1.2)), (0.4, .marker("BLAM")), (0.5, .fling(.goo, back: true)),
                          (2.2, .marker("SPLAT")), (2.3, .react(.surprised)), (2.4, .symbol("•", .green, count: 4)),
                          (2.6, .face(.disgusted, 1.6))])
        case .airHorn:
            // One honk, and it jumps clean out of its own skin.
            return .init([(0, .face(.mischievous, 0.4)), (0.4, .marker("HOOONK")), (0.4, .symbol("!", .gold, count: 3)),
                          (0.5, .face(.terrified, 1.2)), (0.5, .move(.highJump)), (1.9, .move(.shiver)),
                          (2.6, .emote(.curse))])
        case .hypnoSpiral:
            // It looks too long into the spiral and shuffles off, a zombie, until it snaps out of it.
            return .init([(0, .react(.peek)), (0.3, .symbol("@", .purple, count: 3)), (1.2, .face(.dizzy, 2.4)),
                          (1.4, .marker("OBEY.")), (1.6, .move(.sneak)), (3.2, .react(.wakeUp)), (3.4, .emote(.question))])
        case .tickleFeather:
            // It tickles itself, and cannot stop laughing.
            return .init([(0, .face(.mischievous, 0.8)), (0.3, .marker("HEE")), (0.6, .move(.shiver)),
                          (1.2, .marker("HAHA!")), (1.5, .move(.spin)), (2.0, .face(.happy, 1.4)),
                          (2.2, .symbol("♥", .pink, count: 2)), (2.7, .move(.hop))])
        case .hotSauce:
            // One drop: a red face, fire out of its mouth, and tears.
            return .init([(0, .react(.sip)), (0.4, .face(.surprised, 0.5)), (0.9, .face(.angry, 1.0)),
                          (1.0, .marker("HOT!")), (1.2, .fling(.fireball, back: false)), (1.3, .burst(.smoke)),
                          (2.0, .face(.crying, 1.6)), (2.2, .move(.hop))])
        case .bigRedButton:
            // Do not press it. It presses it: confetti, a trapdoor, or nothing at all.
            let roll = random()
            let press: [(TimeInterval, NotchMascotItemAction)] = [
                (0, .face(.mischievous, 1.0)), (0.3, .marker("DONT")), (1.0, .react(.ready)), (1.1, .marker("CLICK"))]
            let outcome: [(TimeInterval, NotchMascotItemAction)]
            if roll < 0.4 {
                outcome = [(1.7, .burst(.confetti)), (1.8, .react(.celebrate)), (2.2, .face(.starstruck, 1.4))]
            } else if roll < 0.7 {
                outcome = [(1.7, .burst(.door)), (1.8, .face(.terrified, 1.0)), (1.8, .move(.slip)),
                           (2.4, .emote(.interrobang))]
            } else {
                outcome = [(1.8, .emote(.ellipsis)), (2.2, .face(.bored, 1.4)), (2.4, .marker("..."))]
            }
            return .init(press + outcome)
        case .stickyHand:
            // A slap at the floor, and the hand will not come off it.
            return .init([(0, .face(.mischievous, 1.0)), (0.3, .fling(.goo, back: false)), (1.1, .marker("THWAP")),
                          (1.3, .move(.shiver)), (2.0, .marker("STUCK")), (2.1, .face(.embarrassed, 1.4)),
                          (2.4, .move(.slip))])
        case .fireworkRocket:
            // Lit, it fizzles, it grows bored of waiting, and then it goes off.
            return .init([(0, .react(.ready)), (0.2, .sparks), (0.8, .emote(.ellipsis)), (1.4, .face(.bored, 1.0)),
                          (2.4, .marker("BOOM!")), (2.4, .burst(.confetti)), (2.5, .move(.highJump)),
                          (2.6, .face(.terrified, 1.4))])
        case .bubbleWrap:
            // One bubble at a time, in bliss.
            return .init([(0, .react(.relax)), (0.3, .marker("POP")), (0.9, .marker("POP")), (1.5, .marker("POP")),
                          (1.8, .symbol("○", .white, count: 2)), (2.1, .face(.love, 1.6)), (2.6, .react(.relax))])
        case .metalDetector:
            // Sweeping the floor, a beep, a dig: a coin now and then, a bottle cap the rest.
            let sweep: [(TimeInterval, NotchMascotItemAction)] = [
                (0, .move(.sneak)), (0.4, .marker("BEEP")), (1.2, .marker("BEEP!")), (1.6, .move(.stomp))]
            let find: [(TimeInterval, NotchMascotItemAction)] = random() < 0.4
                ? [(2.2, .gold(5)), (2.4, .face(.greedy, 1.4))]
                : [(2.2, .marker("CAP?")), (2.4, .face(.bored, 1.4))]
            return .init(sweep + find)
        case .compass:
            // North is that way. No, that way. Lost.
            return .init([(0, .face(.searching, 1.2)), (0.4, .move(.spin)), (1.5, .move(.spin)), (2.6, .marker("NORTH?")),
                          (2.7, .face(.confused, 1.4)), (3.0, .emote(.question))])
        case .batteryPack:
            // Low battery: it drags along, then a zap, and off it shoots.
            return .init([(0, .marker("LOW")), (0.2, .face(.sleepy, 1.4)), (0.2, .move(.sneak)), (1.7, .lightning),
                          (1.8, .marker("FULL!")), (1.9, .move(.charge)), (2.2, .face(.starstruck, 1.4))])
        case .tapShoes:
            // A tap routine, a flourish and a bow.
            return .init([(0, .react(.groove)), (0.2, .move(.stomp)), (0.4, .symbol("♪", .gold, count: 3)),
                          (1.3, .move(.stomp)), (1.5, .marker("TAPTAP")), (2.4, .move(.bow)), (2.6, .face(.smug, 1.4))])
        case .jelly:
            // It wobbles, it wobbles, and it is gone in one gulp.
            return .init([(0, .react(.peek)), (0.2, .move(.shiver)), (0.6, .marker("WOBBLE")), (1.1, .move(.shiver)),
                          (2.0, .marker("NOM")), (2.0, .hide(8)), (2.2, .face(.happy, 1.4))])
        case .trampoline:
            // Bounce, higher, a backflip: a ten most times, a face plant the rest.
            if random() < 0.8 {
                return .init([(0, .move(.hop)), (0.9, .move(.highJump)), (2.2, .move(.backflip)), (2.6, .marker("10.0")),
                              (2.8, .face(.smug, 1.4))])
            }
            return .init([(0, .move(.hop)), (0.9, .move(.highJump)), (2.2, .move(.backflip)), (2.8, .marker("OOF")),
                          (2.9, .burst(.smoke)), (3.0, .face(.dizzy, 1.4))])
        case .raincoat:
            // A twirl in the coat, a puddle stomped, and not a drop gets through.
            return .init([(0, .react(.perk)), (0.2, .move(.spin)), (0.4, .symbol("•", .blue, count: 3)),
                          (1.3, .move(.stomp)), (1.5, .marker("SPLASH")), (2.0, .face(.smug, 1.6))])
        case .garlicNecklace:
            // One sniff of its own necklace is enough.
            return .init([(0, .react(.peek)), (0.3, .symbol("~", .green, count: 3)), (1.0, .face(.disgusted, 1.6)),
                          (1.2, .marker("PEE-YEW")), (1.8, .move(.shiver)), (2.7, .emote(.ellipsis))])
        case .voodooDoll:
            // A poke at the doll, and somebody somewhere says ouch. Now and then, it does.
            if random() < 0.3 {
                return .init([(0, .face(.mischievous, 1.0)), (0.4, .marker("POKE")), (1.0, .react(.surprised)),
                              (1.2, .marker("OUCH!")), (1.3, .move(.hop)), (1.8, .face(.crying, 1.4)),
                              (2.4, .emote(.interrobang))])
            }
            return .init([(0, .face(.mischievous, 1.0)), (0.4, .marker("POKE")), (1.3, .symbol("ouch!", .purple, count: 1)),
                          (2.0, .face(.smug, 1.4)), (2.4, .emote(.question))])
        case .cheeseWheel:
            // A huge bite, and the smell rises off the wheel in green lines.
            return .init([(0, .face(.greedy, 1.0)), (0.4, .marker("CHOMP")), (0.6, .symbol("~", .green, count: 3)),
                          (1.4, .face(.love, 1.2)), (1.8, .marker("STINKY")), (2.0, .move(.shiver)),
                          (2.6, .face(.happy, 1.2))])
        case .ghostTrap:
            // The trap opens, and the first thing it tries to suck in is the one holding it.
            return .init([(0, .face(.determined, 1.0)), (0.3, .marker("CLACK")), (0.5, .symbol("~", .white, count: 3)),
                          (0.6, .move(.slip)), (1.2, .marker("SHLOOP")), (1.3, .burst(.smoke)), (1.5, .react(.surprised)),
                          (2.0, .face(.embarrassed, 1.6))])
        case .lavaLamp:
            // The blobs rise and fall, and so, slowly, does it.
            return .init([(0, .react(.relax)), (0.3, .symbol("●", .pink, count: 3)), (1.4, .face(.starstruck, 1.2)),
                          (2.0, .marker("GROOVY")), (2.2, .move(.float)), (3.0, .emote(.ellipsis))])
        case .icePop:
            // A lick, a bigger lick, and brain freeze.
            return .init([(0, .react(.sip)), (0.3, .symbol("♥", .blue, count: 1)), (0.8, .face(.happy, 0.6)),
                          (1.4, .marker("FREEZE!")), (1.4, .move(.shiver)), (1.5, .face(.dizzy, 1.4)),
                          (1.6, .symbol("❄", .white, count: 3)), (2.6, .emote(.curse))])
        default:
            return nil
        }
    }
}

extension NotchMascotItemTwists {
    // swiftlint:disable:next function_body_length
    /// The figures with a way of their own with a thing from the lab or the mayhem.
    static let labTable: [(pair: Pair, steps: [(TimeInterval, NotchMascotItemAction)])] = [
        // The dragon has no use for a torch: it eats the flame, and burps it back.
        (Pair(style: .dragon, item: .torch),
         [(0, .face(.greedy, 1.0)), (0.3, .sparks), (0.6, .marker("GULP")), (0.8, .react(.surprised)),
          (1.2, .burst(.smoke)), (1.4, .fling(.fireball, back: false)), (2.0, .marker("BURP")), (2.2, .face(.smug, 1.4))]),
        // The kitsune's torch burns blue, and its shadow puppet is a fox.
        (Pair(style: .kitsune, item: .torch),
         [(0, .react(.perk)), (0.2, .burst(.magic)), (0.4, .symbol("✦", .blue, count: 4)),
          (1.2, .symbol("✦", .white, count: 1)), (1.4, .marker("KON!")), (1.8, .move(.spin)), (2.4, .face(.smug, 1.4))]),
        // The cat sees the red dot and is lost to the world.
        (Pair(style: .cat, item: .laserPointer),
         [(0, .face(.mischievous, 0.8)), (0.2, .symbol("•", .pink, count: 1)), (0.3, .move(.charge)),
          (1.8, .move(.highJump)), (2.1, .marker("POUNCE!")), (3.1, .emote(.question)), (3.2, .move(.spin)),
          (4.0, .face(.dizzy, 1.4))]),
        // The ghost opens the trap, and in it goes.
        (Pair(style: .ghost, item: .ghostTrap),
         [(0, .react(.peek)), (0.3, .marker("CLACK")), (0.5, .face(.terrified, 1.2)), (0.6, .move(.slip)),
          (1.1, .symbol("~", .white, count: 3)), (1.4, .marker("SHLOOP")), (1.5, .burst(.smoke)), (2.2, .emote(.interrobang))]),
        // A ghost in garlic runs from the only ghost in sight: itself.
        (Pair(style: .ghost, item: .garlicNecklace),
         [(0, .react(.peek)), (0.3, .face(.disgusted, 0.5)), (0.8, .face(.terrified, 1.4)), (1.0, .move(.charge)),
          (2.6, .marker("EWWW")), (2.7, .emote(.interrobang))]),
        // The mouse and the wheel: it eats until it is round.
        (Pair(style: .mouse, item: .cheeseWheel),
         [(0, .face(.greedy, 1.2)), (0.3, .emote(.heart)), (0.6, .move(.charge)), (1.4, .marker("NOMNOM")),
          (1.6, .hide(10)), (1.8, .grow(5)), (2.0, .face(.love, 1.6)), (2.2, .symbol("♥", .pink, count: 3))]),
        // The penguin freezes itself on purpose and slides off on its belly.
        (Pair(style: .penguin, item: .freezeRay),
         [(0, .react(.perk)), (0.2, .symbol("❄", .blue, count: 4)), (0.8, .marker("BRRR")), (1.0, .face(.love, 1.4)),
          (1.2, .move(.charge)), (2.6, .marker("WHEEE")), (2.8, .face(.starstruck, 1.4))]),
        // The robot grabs the plasma ball and overclocks.
        (Pair(style: .robot, item: .plasmaBall),
         [(0, .react(.ready)), (0.2, .lightning), (0.4, .sparks), (0.6, .marker("OVERCLOCK")), (0.8, .move(.spin)),
          (1.9, .lightning), (2.0, .grow(4)), (2.2, .face(.starstruck, 1.4))]),
        // The slime takes the backfire as a gift: it soaks the goo up and grows.
        (Pair(style: .slime, item: .slimeBlaster),
         [(0, .face(.mischievous, 1.0)), (0.3, .fling(.goo, back: true)), (2.0, .marker("GLORP")), (2.1, .grow(5)),
          (2.3, .face(.love, 1.4)), (2.5, .move(.shiver))]),
        // The frog's tongue goes for the fish, and the fish ducks.
        (Pair(style: .frog, item: .fishBowl),
         [(0, .face(.greedy, 1.0)), (0.4, .marker("THWIP")), (0.6, .symbol("○", .blue, count: 3)), (1.2, .react(.surprised)),
          (1.4, .emote(.thought("><>"))), (1.8, .marker("MISSED")), (2.0, .face(.embarrassed, 1.4))]),
        // The capybara sips its cocoa, floats off into bliss and falls asleep.
        (Pair(style: .capybara, item: .hotCocoa),
         [(0, .react(.sip)), (0.4, .symbol("~", .white, count: 2)), (1.2, .marker("AHHH")), (1.4, .face(.love, 1.2)),
          (2.0, .move(.float)), (3.0, .doze(5)), (3.2, .symbol("z", .white, count: 2))]),
        // The chip plugs into the battery and runs at five gigahertz.
        (Pair(style: .chip, item: .batteryPack),
         [(0, .react(.perk)), (0.2, .lightning), (0.4, .marker("5GHZ")), (0.6, .move(.charge)), (2.1, .move(.spin)),
          (2.4, .sparks), (2.6, .face(.starstruck, 1.4))]),
        // The devourer swallows the whole bucket, and it keeps popping inside.
        (Pair(style: .devourer, item: .popcornBucket),
         [(0, .face(.greedy, 0.8)), (0.3, .marker("GULP")), (0.4, .hide(12)), (0.8, .grow(4)), (1.2, .marker("POPPOP")),
          (1.3, .move(.shiver)), (2.2, .burst(.confetti)), (2.4, .face(.embarrassed, 1.4))]),
        // A phoenix with an extinguisher puts itself out, panics, and flares up again.
        (Pair(style: .phoenix, item: .fireExtinguisher),
         [(0, .react(.peek)), (0.4, .marker("PSSHH")), (0.5, .symbol("○", .white, count: 4)), (0.6, .face(.terrified, 1.6)),
          (0.8, .move(.charge)), (2.4, .burst(.smoke)), (2.5, .marker("FWOOSH")), (2.7, .face(.smug, 1.4))]),
        // The axolotl bursts the balloon on its own head, on purpose, and loves it.
        (Pair(style: .axolotl, item: .waterBalloon),
         [(0, .react(.perk)), (0.2, .juggle(.drop)), (1.0, .marker("SPLOOSH")), (1.1, .symbol("•", .blue, count: 5)),
          (1.4, .move(.spin)), (2.2, .face(.love, 1.6)), (2.4, .symbol("○", .blue, count: 2))]),
        // Every squeak is music to the dog, and off it runs with the hammer.
        (Pair(style: .dog, item: .squeakyHammer),
         [(0, .react(.perk)), (0.3, .marker("SQUEAK")), (0.6, .face(.love, 1.0)), (1.0, .move(.hop)),
          (1.6, .marker("SQUEAK")), (1.9, .move(.charge)), (3.4, .hide(6)), (3.5, .react(.love))]),
        // The ballerina tries tap, frowns, and turns it into ballet.
        (Pair(style: .ballerina, item: .tapShoes),
         [(0, .move(.stomp)), (1.1, .marker("TAP?")), (1.3, .face(.disgusted, 1.0)), (1.6, .move(.spin)),
          (2.7, .move(.bow)), (2.9, .marker("PLIE")), (3.0, .face(.smug, 1.4))]),
        // The danseur on the trampoline: a double tour en l'air, and applause.
        (Pair(style: .danseur, item: .trampoline),
         [(0, .move(.hop)), (0.9, .move(.highJump)), (2.2, .move(.spin)), (3.3, .move(.bow)), (3.5, .marker("BRAVO!")),
          (3.6, .burst(.confetti))]),
        // The hologram takes the lamp's colours, and the two glow in time.
        (Pair(style: .hologram, item: .lavaLamp),
         [(0, .react(.relax)), (0.3, .symbol("●", .pink, count: 3)), (1.0, .burst(.magic)), (1.2, .marker("SYNC")),
          (1.4, .move(.float)), (2.2, .burst(.sparkles)), (2.4, .face(.starstruck, 1.4))]),
        // The swan on skates: no wobble at all, and a perfect six.
        (Pair(style: .swan, item: .iceSkates),
         [(0, .move(.float)), (0.4, .symbol("❄", .white, count: 3)), (1.3, .move(.spin)), (2.4, .move(.bow)),
          (2.6, .marker("6.0")), (2.8, .face(.smug, 1.4))]),
        // The android checks the button is safe, presses it, and reboots.
        (Pair(style: .android, item: .bigRedButton),
         [(0, .face(.thinking, 1.2)), (0.4, .marker("SCAN")), (1.2, .marker("SAFE")), (1.4, .react(.ready)),
          (1.6, .lightning), (1.8, .doze(2)), (3.8, .react(.wakeUp)), (4.0, .marker("REBOOT"))]),
        // The fan adds its own wind to the blower and spins itself silly.
        (Pair(style: .fan, item: .leafBlower),
         [(0, .react(.ready)), (0.2, .marker("VRRRM")), (0.4, .symbol("❦", .gold, count: 4)), (0.8, .move(.spin)),
          (1.9, .move(.spin)), (3.0, .marker("TURBO")), (3.2, .face(.dizzy, 1.4))]),
        // The shifter copies the one in the mirror, who copies it back.
        (Pair(style: .shifter, item: .pocketMirror),
         [(0, .react(.peek)), (0.4, .burst(.magic)), (0.6, .marker("COPY")), (1.0, .emote(.question)),
          (1.4, .burst(.magic)), (1.6, .marker("COPY?")), (2.2, .face(.dizzy, 1.4))]),
    ]
}

extension NotchMascotItemSignature {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// The lab and the mayhem in a combo: a flicker, a splash, a gust, a
    /// zap, a freeze, a dot, a hum, a sneeze, a bonk, a pop, a knock, a
    /// sprout, foam, a strike, a stomp, a flash, a tinkle, a bubble, a sip,
    /// a glide, a hiss, a swing, a brew and a boing; then a pull, a lick, a
    /// splat, a honk, a stare, a giggle, a burn, a button, a slap, a rocket,
    /// a pop, a beep, a turn, a charge, a tap, a wobble, a bounce, a twirl,
    /// a sniff, a poke, a bite, a vacuum, a glow and a brain freeze.
    static func lab(_ item: NotchMascotAccessory) -> NotchMascotItemSignature? {
        switch item {
        case .torch: return .init(.sneak, .spark, .sparkles, .peek)
        case .waterBalloon: return .init(.hop, .drop, .confetti, .surprised)
        case .leafBlower: return .init(.charge, .tornado, .smoke, .ready)
        case .plasmaBall: return .init(.shiver, .bolt, .magic, .flash)
        case .freezeRay: return .init(.slip, .snowball, .sparkles, .flash)
        case .laserPointer: return .init(.charge, .spark, .sparkles, .perk)
        case .tuningFork: return .init(.shiver, .note, .sparkles, .hush)
        case .pepperShaker: return .init(.slip, .pepper, .smoke, .surprised)
        case .squeakyHammer: return .init(.stomp, .star, .confetti, .confused)
        case .popcornBucket: return .init(.hop, .cookie, .confetti, .sip)
        case .mysteryEgg: return .init(.bow, .star, .magic, .surprised)
        case .seedPacket: return .init(.bow, .flower, .sparkles, .relax)
        case .fireExtinguisher: return .init(.slip, .drop, .smoke, .panic)
        case .lightningRod: return .init(.highJump, .bolt, .magic, .flash)
        case .rubberBoots: return .init(.stomp, .drop, .confetti, .bounce)
        case .pocketMirror: return .init(.strut, .star, .sparkles, .flash)
        case .windChime: return .init(.float, .note, .sparkles, .relax)
        case .fishBowl: return .init(.float, .drop, .sparkles, .love)
        case .hotCocoa: return .init(.bow, .heart, .hearts, .sip)
        case .iceSkates: return .init(.spin, .snowball, .sparkles, .celebrate)
        case .gasMask: return .init(.sneak, .pepper, .smoke, .ready)
        case .pinata: return .init(.spin, .coin, .confetti, .celebrate)
        case .bubblingFlask: return .init(.shiver, .potion, .magic, .surprised)
        case .jackInTheBox: return .init(.highJump, .note, .confetti, .panic)
        case .giantMagnet: return .init(.charge, .coin, .coins, .surprised)
        case .honeyJar: return .init(.sneak, .heart, .hearts, .love)
        case .slimeBlaster: return .init(.charge, .goo, .smoke, .surprised)
        case .airHorn: return .init(.highJump, .note, .smoke, .panic)
        case .hypnoSpiral: return .init(.float, .spiral, .magic, .confused)
        case .tickleFeather: return .init(.spin, .feather, .confetti, .celebrate)
        case .hotSauce: return .init(.charge, .fireball, .smoke, .panic)
        case .bigRedButton: return .init(.backflip, .dynamite, .confetti, .surprised)
        case .stickyHand: return .init(.slip, .goo, .smoke, .confused)
        case .fireworkRocket: return .init(.highJump, .star, .confetti, .celebrate)
        case .bubbleWrap: return .init(.stomp, .balloon, .confetti, .relax)
        case .metalDetector: return .init(.sneak, .coin, .coins, .peek)
        case .compass: return .init(.spin, .key, .sparkles, .confused)
        case .batteryPack: return .init(.charge, .bolt, .sparkles, .perk)
        case .tapShoes: return .init(.stomp, .note, .confetti, .groove)
        case .jelly: return .init(.shiver, .heart, .hearts, .bounce)
        case .trampoline: return .init(.highJump, .ball, .confetti, .bounce)
        case .raincoat: return .init(.strut, .drop, .sparkles, .relax)
        case .garlicNecklace: return .init(.sneak, .flower, .smoke, .hush)
        case .voodooDoll: return .init(.sneak, .spark, .magic, .peek)
        case .cheeseWheel: return .init(.stomp, .cookie, .hearts, .celebrate)
        case .ghostTrap: return .init(.slip, .tornado, .magic, .panic)
        case .lavaLamp: return .init(.float, .spark, .magic, .relax)
        case .icePop: return .init(.shiver, .snack(.iceCream), .sparkles, .surprised)
        default: return nil
        }
    }
}

extension NotchMascotEncounters {
    // swiftlint:disable:next cyclomatic_complexity
    /// What the lab and the mayhem draw in: a torch the fireflies, a fish
    /// bowl the fish and the ducks, a red dot the saucer, a lightning rod
    /// the rain, seeds the butterflies and the rainbow, a detector the
    /// magpie and the mimic, a magnet the satellite, honey the butterflies,
    /// a trap the ghost, a spiral the glitch and a mystery egg, perhaps,
    /// its mother.
    static func labLured(_ item: NotchMascotAccessory) -> Set<NotchMascotEncounter> {
        switch item {
        case .torch: return [.fireflies]
        case .waterBalloon, .bubblingFlask: return [.bubble]
        case .leafBlower, .cheeseWheel: return [.trashCan]
        case .plasmaBall, .hypnoSpiral: return [.glitch]
        case .laserPointer: return [.ufo]
        case .mysteryEgg: return [.dinosaur]
        case .seedPacket: return [.butterflies, .rainbow]
        case .lightningRod, .rubberBoots, .raincoat: return [.rainShower]
        case .fishBowl: return [.fishJump, .ducklings]
        case .pinata: return [.lostBalloon]
        case .giantMagnet, .batteryPack: return [.satellite]
        case .honeyJar: return [.butterflies]
        case .fireworkRocket: return [.shootingStar, .meteorShower]
        case .metalDetector: return [.magpie, .mimic]
        case .compass: return [.merchant]
        case .trampoline: return [.zeroGravity]
        case .ghostTrap, .voodooDoll: return [.ghost]
        default: return []
        }
    }
}

extension NotchMascotFusion {
    /// The fusions that need a thing from the lab or the mayhem on one of the two.
    static let labFusions: [Special] = [
        // A robot holding lightning in a ball.
        Special(name: "Volt Rex", styles: [.robot], item: .plasmaBall, body: .robot, primary: 0x7A3CFF,
                secondary: 0x39F0FF, split: true, aura: .storm, mark: .earrings, signature: .overclock, scale: 1.45),
        // A chip cooled until it frosts over.
        Special(name: "Frostbyte", styles: [.chip], item: .freezeRay, body: .chip, primary: 0x8FE3FF,
                secondary: 0x1E5BFF, split: true, aura: .frost, mark: .gem, signature: .iceSlide, scale: 1.4),
        // A slime that drank the flask, and the doctor it became.
        Special(name: "Dr. Glorp", styles: [.slime], item: .bubblingFlask, body: .slime, primary: 0x7CFF4F,
                secondary: 0xB04BFF, split: true, aura: .bubbles, mark: .gem, signature: .gulp, scale: 1.45),
        // A girl of light split into every colour by the laser.
        Special(name: "Prism", styles: [.hologram], item: .laserPointer, body: .hologram, primary: 0xFF3B6B,
                secondary: 0x6BFFB8, split: true, aura: .glitch, mark: .gem, signature: .glitchStep, scale: 1.4),
        // What hatched from the mystery egg in a dragon's arms.
        Special(name: "Kaiju Chick", styles: [.dragon], item: .mysteryEgg, body: .dragon, primary: 0xFFE066,
                secondary: 0x3FBF6E, split: true, aura: .blaze, mark: .earrings, signature: .inferno, scale: 1.6),
        // A dog that drank the hot sauce.
        Special(name: "Hot Dog", styles: [.dog], item: .hotSauce, body: .dog, primary: 0xE23B2E,
                secondary: 0xFFB347, split: true, aura: .blaze, mark: .earrings, signature: .pounce, scale: 1.4),
        // A mouse with the whole wheel to itself.
        Special(name: "Big Cheese", styles: [.mouse], item: .cheeseWheel, body: .mouse, primary: 0xF7C548,
                secondary: 0xB98A4E, split: false, aura: .stardust, mark: .gem, signature: .scurry, scale: 1.5),
        // A frog that stared into the spiral, and now everyone stares at it.
        Special(name: "Hypnotoad", styles: [.frog], item: .hypnoSpiral, body: .frog, primary: 0x6B3FA0,
                secondary: 0x9BE15D, split: true, aura: .spirit, mark: .gem, signature: .zenRipple, scale: 1.45),
        // A ghost with a trap of its own, out in the small hours after the others.
        Special(name: "Ghostbuster", styles: [.ghost], item: .ghostTrap, night: true, body: .ghost, primary: 0xE8ECEF,
                secondary: 0xFF4A3D, split: true, aura: .spirit, mark: .earrings, signature: .teleport, scale: 1.4),
        // The phoenix charged to bursting: its fire turned to thunder.
        Special(name: "Thunderbird", styles: [.phoenix], item: .batteryPack, body: .phoenix, primary: 0x1FA2FF,
                secondary: 0xFFEA3D, split: true, aura: .storm, mark: .earrings, signature: .overclock, scale: 1.5),
    ]
}
