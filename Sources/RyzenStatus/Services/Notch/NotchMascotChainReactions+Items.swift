// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What every thing worn makes of a chain: what it throws to start one (the
/// torch's fire, the balloon's water, the leaf blower's gust, the big red
/// button's who knows what), and what it makes of what is thrown at it,
/// before its figure or the plain way have a say. The popcorn pops, the egg
/// hatches, the seeds sprout, the boots shrug off the spark and the voodoo
/// doll sends it all somewhere else. Pure data, so every rule is tested.
extension NotchMascotChainReactions {
    // MARK: Luck of things worn

    /// The mystery egg was gold all along this often.
    static let eggGoldChance = 0.05
    /// The mystery egg hatches a baby dragon this often; a chick the rest of the time.
    static let eggDragonChance = 0.10
    /// Water on the seeds grows a beanstalk instead of a sprout this often.
    static let beanstalkChance = 0.08
    /// The piñata is a golden one this often.
    static let goldenPinataChance = 0.15
    /// The metal detector digs up real treasure, not a coin, this often.
    static let treasureChance = 0.05
    /// The voodoo doll sends it to its own holder this often.
    static let voodooCurseChance = 0.10
    /// The big red button does everything at once this often.
    static let bigBangChance = 0.03
    /// What the bubbling flask does to its drinker: it grows this often,
    /// vanishes the flask this often after that, and pulls a wild face the rest.
    static let flaskGrowChance = 1.0 / 3
    static let flaskVanishChance = 1.0 / 3

    // MARK: Gold of things worn

    /// What the golden egg pays, within the day's share of luck.
    static let goldenEggGold = 60
    /// What a plain piñata spills, and a golden one.
    static let pinataGold = 10
    static let goldenPinataGold = 60
    /// What the metal detector digs up: a coin, or treasure.
    static let coinGold = 5
    static let treasureGold = 60

    /// One stimulus out of all of them, by `random`, in their order.
    static func anyStimulus(_ random: Double) -> NotchMascotStimulus {
        let all = NotchMascotStimulus.allCases
        return all[min(all.count - 1, max(0, Int(random * Double(all.count))))]
    }

    // MARK: What a thing throws

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// What `item` throws to start a chain, and what its wearer does first:
    /// lights the torch, takes aim, sniffs the pepper, presses the button.
    static func itemEmission(_ item: NotchMascotAccessory) -> NotchMascotChainEmission? {
        switch item {
        case .torch:
            return NotchMascotChainEmission(.fire, [(0, .react(.ready)), (0.2, .sparks), (0.5, .burst(.smoke))])
        case .hotSauce:
            // A swig of it, and the fire comes out the other way.
            return NotchMascotChainEmission(.fire, [(0, .hide(1)), (0.2, .marker("GLUG")), (0.6, .burst(.smoke))])
        case .fireballSpell:
            return NotchMascotChainEmission(.fire, [(0, .react(.ready)), (0.3, .burst(.magic))])
        case .waterBalloon:
            return NotchMascotChainEmission(.water, [(0, .face(.mischievous, 0.8)), (0.3, .react(.ready))])
        case .waterPistol:
            return NotchMascotChainEmission(.water, [(0, .face(.mischievous, 0.6)), (0.3, .react(.ready))])
        case .leafBlower:
            return NotchMascotChainEmission(.wind, [(0, .react(.ready)), (0.2, .marker("VRRRM")),
                                                    (0.4, .symbol("~", .white, count: 2))])
        case .tornadoSpell:
            return NotchMascotChainEmission(.wind, [(0, .react(.ready)), (0.3, .symbol("~", .white, count: 2))])
        case .plasmaBall:
            return NotchMascotChainEmission(.shock, [(0, .react(.ready)), (0.2, .lightning), (0.5, .sparks)])
        case .freezeRay:
            return NotchMascotChainEmission(.frost, [(0, .face(.determined, 0.7)), (0.3, .symbol("❄", .blue, count: 1))])
        case .laserPointer:
            return NotchMascotChainEmission(.light, [(0, .face(.mischievous, 0.7)), (0.3, .sparks)])
        case .laserVisor:
            return NotchMascotChainEmission(.light, [(0, .react(.ready)), (0.3, .sparks)])
        case .tuningFork:
            return NotchMascotChainEmission(.sound, [(0, .react(.ready)), (0.2, .marker("TING")), (0.4, .move(.shiver))])
        case .airHorn:
            return NotchMascotChainEmission(.sound, [(0, .react(.ready)), (0.3, .marker("HOOONK")), (0.4, .move(.shiver))])
        case .megaphone:
            return NotchMascotChainEmission(.sound, [(0, .react(.ready)), (0.3, .marker("HEY YOU!"))])
        case .pepperShaker:
            return NotchMascotChainEmission(.pepper, [(0, .face(.mischievous, 0.7)), (0.2, .move(.shiver)),
                                                      (0.4, .symbol("·", .white, count: 2))])
        case .squeakyHammer:
            return NotchMascotChainEmission(.impact, [(0, .react(.ready)), (0.3, .marker("SQUEAK"))])
        case .slingshot:
            return NotchMascotChainEmission(.impact, [(0, .react(.ready)), (0.4, .marker("TWANG"))])
        case .bigRedButton:
            // The sign says not to. It presses it anyway.
            return NotchMascotChainEmission(.impact, [(0, .emote(.interrobang)), (0.4, .marker("CLICK")),
                                                      (0.5, .react(.surprised))])
        case .giantMagnet, .horseshoeMagnet:
            return NotchMascotChainEmission(.magnet, [(0, .react(.ready)), (0.2, .burst(.magic)), (0.4, .marker("VMMM"))])
        case .honeyJar:
            return NotchMascotChainEmission(.sweet, [(0, .face(.greedy, 0.6)), (0.3, .symbol("♥", .gold, count: 1))])
        case .cheeseWheel:
            // The smell does the throwing.
            return NotchMascotChainEmission(.sweet, [(0, .react(.perk)), (0.2, .symbol("~", .green, count: 2))])
        case .slimeBlaster:
            return NotchMascotChainEmission(.goo, [(0, .face(.mischievous, 0.6)), (0.3, .marker("BLORP"))])
        case .stickyHand:
            return NotchMascotChainEmission(.goo, [(0, .react(.ready)), (0.3, .marker("THWIP"))])
        case .creamPie:
            return NotchMascotChainEmission(.goo, [(0, .face(.mischievous, 0.7)), (0.4, .react(.ready))])
        case .hypnoSpiral:
            return NotchMascotChainEmission(.hypno, [(0, .face(.dizzy, 0.6)), (0.3, .burst(.magic))])
        case .tickleFeather:
            return NotchMascotChainEmission(.tickle, [(0, .face(.mischievous, 0.7)), (0.3, .symbol("~", .pink, count: 1))])
        default:
            return nil
        }
    }

    // MARK: What a thing makes of it

    /// What `item` makes of `stimulus`, if it has a way of its own; nil
    /// leaves it to the figure and then the plain way. `random` settles
    /// luck, drawn at most twice and always in the same order.
    static func itemReaction(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus,
                             random: () -> Double) -> Reaction? {
        if let any = reactionToAnything(item, to: stimulus, random: random) { return any }
        if let lucky = luckyReaction(item, to: stimulus, random: random) { return lucky }
        if let lab = labReaction(item, to: stimulus) { return lab }
        if let mayhem = mayhemReaction(item, to: stimulus) { return mayhem }
        return wardrobeReaction(item, to: stimulus)
    }

    // swiftlint:disable:next function_body_length
    /// The four that take anything at all: the flask, the voodoo doll, the
    /// ghost trap and the big red button.
    static func reactionToAnything(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus,
                                   random: () -> Double) -> Reaction? {
        let id = "\(item.rawValue).\(stimulus.rawValue)"
        let source = Reaction.Source.item(item)
        switch item {
        case .bubblingFlask:
            // It boils over into the wearer, does something to it nobody
            // could have said, and something just as unforeseen flies out.
            let mutation = random()
            let thrown = anyStimulus(random())
            if mutation < flaskGrowChance {
                return Reaction(id + ".grow", source, [(0, .react(.surprised)), (0.2, .burst(.magic)), (0.3, .marker("BLUBB")),
                                                       (0.5, .grow(4)), (0.8, .face(.starstruck, 1.2))],
                                emits: thrown, target: .random)
            }
            if mutation < flaskGrowChance + flaskVanishChance {
                return Reaction(id + ".vanish", source, [(0, .react(.surprised)), (0.2, .burst(.smoke)), (0.3, .marker("POOF")),
                                                         (0.4, .hide(4)), (0.7, .face(.confused, 1.2)), (0.9, .emote(.question))],
                                emits: thrown, target: .random)
            }
            return Reaction(id + ".wild", source, [(0, .react(.surprised)), (0.2, .burst(.magic)), (0.3, .marker("BLUBB")),
                                                   (0.5, .face(.dizzy, 1.4)), (0.6, .symbol("○", .green, count: 3))],
                            emits: thrown, target: .random)
        case .voodooDoll:
            // A pin in the doll and it lands on someone else; now and then
            // the doll remembers whose hand it is in.
            if random() < voodooCurseChance {
                return Reaction(id + ".curse", source, [(0, .react(.surprised)), (0.2, .marker("OUCH!")),
                                                        (0.3, .burst(stimulus.burst)), (0.5, .move(.shiver)),
                                                        (1.0, .face(.terrified, 1.2)), (1.1, .emote(.curse))],
                                rare: .voodooCurse)
            }
            return Reaction(id, source, [(0, .face(.mischievous, 1.2)), (0.2, .marker("POKE")), (0.4, .burst(.magic)),
                                         (0.6, .symbol("✦", .purple, count: 2)), (1.2, .react(.wave))],
                            emits: stimulus, target: .random)
        case .ghostTrap:
            // Whatever it was, the trap takes it for a ghost and opens.
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .burst(.door)), (0.3, .marker("SHLUUURP")),
                                         (0.5, .symbol("~", .white, count: 3)), (1.2, .face(.determined, 1.0))],
                            emits: .wind)
        case .bigRedButton:
            // Bumped, it gets pressed, and it sends something, anything,
            // to anyone; once in a long while it does everything at once.
            let bang = random() < bigBangChance
            let thrown = anyStimulus(random())
            if bang {
                return Reaction(id + ".bigbang", source, [(0, .react(.surprised)), (0.1, .marker("CLICK")), (0.4, .burst(.magic)),
                                                          (0.5, .grow(4)), (0.7, .burst(.confetti)),
                                                          (0.9, .marker("EVERYTHING!")), (1.1, .face(.starstruck, 1.2))],
                                emits: thrown, target: .everyone, rare: .bigBang)
            }
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .marker("CLICK")), (0.4, .emote(.interrobang)),
                                         (0.6, .burst(thrown.burst)), (1.0, .face(.mischievous, 1.2))],
                            emits: thrown, target: .random)
        default:
            return nil
        }
    }

    // swiftlint:disable:next function_body_length
    /// The ones luck has a say in: the egg, the seeds, the piñata and the
    /// metal detector.
    static func luckyReaction(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus,
                              random: () -> Double) -> Reaction? {
        let id = "\(item.rawValue).\(stimulus.rawValue)"
        let source = Reaction.Source.item(item)
        switch (item, stimulus) {
        case (.mysteryEgg, .fire), (.mysteryEgg, .shock):
            // Knock knock, a crack, and out comes a chick, mostly.
            let roll = random()
            if roll < eggGoldChance {
                return Reaction(id + ".gold", source, [(0, .move(.shiver)), (0.3, .marker("CRACK")), (0.8, .burst(.coins)),
                                                       (0.9, .gold(goldenEggGold)), (1.0, .face(.starstruck, 1.4))],
                                rare: .goldenEgg)
            }
            if roll < eggGoldChance + eggDragonChance {
                // A baby dragon, and the first thing it does is sneeze fire.
                return Reaction(id + ".dragon", source, [(0, .move(.shiver)), (0.3, .marker("CRACK")), (0.8, .burst(.magic)),
                                                         (0.9, .marker("RAWR!")), (1.0, .fling(.fireball, back: false)),
                                                         (1.2, .face(.starstruck, 1.2))],
                                emits: .fire, rare: .babyDragon)
            }
            return Reaction(id, source, [(0, .move(.shiver)), (0.3, .marker("CRACK")), (0.8, .marker("PEEP!")),
                                         (0.9, .symbol("♪", .gold, count: 2)), (1.2, .face(.love, 1.2))])
        case (.seedPacket, .water):
            if random() < beanstalkChance {
                return Reaction(id + ".beanstalk", source, [(0, .react(.surprised)), (0.2, .symbol("✿", .green, count: 4)),
                                                            (0.4, .grow(5)), (0.6, .marker("WHOA!")), (0.8, .move(.highJump)),
                                                            (1.4, .face(.starstruck, 1.2))],
                                rare: .beanstalk)
            }
            return Reaction(id, source, [(0, .react(.perk)), (0.2, .symbol("✿", .green, count: 2)), (0.4, .grow(2)),
                                         (0.6, .marker("SPROUT!")), (1.0, .face(.happy, 1.2))])
        case (.pinata, .impact):
            // It bursts and rains candy; a golden one rains gold.
            if random() < goldenPinataChance {
                return Reaction(id + ".golden", source, [(0, .react(.surprised)), (0.1, .marker("GOLD!")), (0.2, .burst(.coins)),
                                                         (0.3, .hide(6)), (0.5, .symbol("✦", .gold, count: 3)),
                                                         (0.8, .gold(goldenPinataGold)), (1.0, .face(.greedy, 1.4))],
                                rare: .goldenPinata)
            }
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .marker("CRACK")), (0.2, .burst(.confetti)),
                                         (0.3, .hide(6)), (0.5, .symbol("◆", .pink, count: 3)), (0.8, .gold(pinataGold)),
                                         (1.0, .react(.celebrate))])
        case (.metalDetector, .magnet):
            // Beep beep, a dig, and a coin; once in a while a whole chest.
            if random() < treasureChance {
                return Reaction(id + ".treasure", source, [(0, .marker("BEEP BEEP")), (0.3, .move(.sneak)), (0.9, .burst(.coins)),
                                                           (1.0, .marker("TREASURE")), (1.1, .gold(treasureGold)),
                                                           (1.3, .face(.greedy, 1.2))],
                                rare: .treasure)
            }
            return Reaction(id, source, [(0, .marker("BEEP BEEP")), (0.3, .move(.stomp)), (0.9, .burst(.coins)),
                                         (1.0, .gold(coinGold)), (1.2, .face(.happy, 1.0))])
        default:
            return nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// The lab's own: what pops, puts out, conducts, reflects, rings, swims,
    /// warms, skates, filters or springs at what reaches it.
    static func labReaction(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus) -> Reaction? {
        let id = "\(item.rawValue).\(stimulus.rawValue)"
        let source = Reaction.Source.item(item)
        switch (item, stimulus) {
        case (.torch, .water):
            return Reaction(id, source, [(0, .burst(.smoke)), (0.2, .marker("FSSS")), (0.4, .face(.crying, 1.2)),
                                         (0.8, .emote(.ellipsis))])
        case (.waterBalloon, .impact):
            // Burst right on its own head, and it shakes the wet off onto the next.
            return Reaction(id, source, [(0, .marker("SPLOOSH")), (0.1, .burst(.confetti)), (0.2, .hide(5)),
                                         (0.3, .symbol("•", .blue, count: 3)), (0.8, .face(.disgusted, 1.4))],
                            emits: .water)
        case (.waterBalloon, .frost):
            // The balloon freezes solid in its hand, and the floor with it.
            return Reaction(id, source, [(0, .face(.surprised, 1.4)), (0.1, .symbol("❄", .blue, count: 2)),
                                         (0.3, .marker("ICE BALL")), (0.6, .move(.slip))],
                            rare: .iceAge)
        case (.popcornBucket, .fire):
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .marker("POP POP POP")),
                                         (0.2, .symbol("•", .white, count: 3)), (0.5, .move(.hop)), (1.1, .face(.happy, 1.0))],
                            emits: .impact)
        case (.fireExtinguisher, .fire):
            return Reaction(id, source, [(0, .react(.panic)), (0.2, .marker("FSSSH")), (0.3, .symbol("○", .white, count: 3)),
                                         (0.8, .move(.slip)), (1.3, .face(.smug, 1.0))],
                            emits: .water)
        case (.lightningRod, .shock):
            // It takes the whole bolt, glows with it and sends it on stronger.
            return Reaction(id, source, [(0, .lightning), (0.1, .react(.flash)), (0.3, .burst(.magic)),
                                         (0.5, .marker("CHARGED!")), (0.7, .sparks), (0.9, .face(.starstruck, 1.2))],
                            emits: .shock)
        case (.rubberBoots, .shock), (.rubberBoots, .water):
            return Reaction(id, source, [(0, .move(.stomp)), (0.1, .burst(stimulus.burst)), (0.3, .marker("INSULATED")),
                                         (0.6, .face(.smug, 1.4)), (0.9, .emote(.ellipsis))])
        case (.pocketMirror, .light):
            return Reaction(id, source, [(0, .react(.flash)), (0.2, .marker("BLING")), (0.3, .symbol("✦", .white, count: 2)),
                                         (0.7, .move(.spin)), (1.3, .face(.smug, 1.0))],
                            emits: .light)
        case (.pocketMirror, .fire):
            return Reaction(id, source, [(0, .react(.panic)), (0.2, .marker("REFLECT!")), (0.4, .fling(.fireball, back: false)),
                                         (1.0, .face(.surprised, 1.0))],
                            emits: .fire)
        case (.windChime, .wind):
            return Reaction(id, source, [(0, .react(.relax)), (0.2, .symbol("♫", .gold, count: 3)), (0.4, .marker("TING TING")),
                                         (1.2, .face(.happy, 1.0))],
                            emits: .sound)
        case (.fishBowl, .water):
            // The fish takes the chance and leaps for the next one's head.
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .emote(.thought("><>"))), (0.4, .marker("SPLOOSH")),
                                         (0.6, .symbol("○", .blue, count: 2)), (1.2, .face(.confused, 1.0))],
                            emits: .water)
        case (.fishBowl, .frost):
            return Reaction(id, source, [(0, .face(.surprised, 1.6)), (0.1, .symbol("❄", .blue, count: 3)),
                                         (0.3, .marker("ICE CUBE")), (0.6, .move(.slip)), (1.6, .emote(.thought("><>")))],
                            rare: .iceAge)
        case (.fishBowl, .sound):
            return Reaction(id, source, [(0, .react(.groove)), (0.2, .emote(.thought("><>"))), (0.4, .symbol("♪", .blue, count: 2)),
                                         (0.6, .move(.spin)), (1.4, .marker("FISH DISCO"))])
        case (.hotCocoa, .frost):
            // Frost means nothing with a warm mug in both hands.
            return Reaction(id, source, [(0, .react(.sip)), (0.3, .symbol("♨", .white, count: 2)), (0.6, .marker("COZY")),
                                         (1.2, .face(.love, 1.2))])
        case (.hotCocoa, .fire):
            return Reaction(id, source, [(0, .react(.sip)), (0.4, .marker("HOT HOT!")), (0.5, .face(.crying, 1.2)),
                                         (0.6, .move(.hop)), (1.0, .burst(.smoke))])
        case (.iceSkates, .frost):
            // Fresh ice: a figure skated so fast it leaves a gust behind.
            return Reaction(id, source, [(0, .react(.celebrate)), (0.1, .move(.slip)), (0.4, .symbol("❄", .white, count: 2)),
                                         (1.2, .marker("10.0")), (1.3, .face(.smug, 1.0))],
                            emits: .wind)
        case (.gasMask, .pepper), (.gasMask, .sweet):
            return Reaction(id, source, [(0, .react(.hush)), (0.2, .marker("KSHHH")), (0.6, .face(.smug, 1.2)),
                                         (1.0, .emote(.ellipsis))])
        case (.jackInTheBox, .sound), (.jackInTheBox, .impact):
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .marker("BOING!")), (0.3, .move(.highJump)),
                                         (0.5, .emote(.exclaim)), (1.5, .face(.mischievous, 1.0))],
                            emits: .sound)
        default:
            return nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// Mayhem's own: what launches, pops, spins, charges, taps, wobbles,
    /// bounces, keeps dry, wards off, glows or melts at what reaches it.
    static func mayhemReaction(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus) -> Reaction? {
        let id = "\(item.rawValue).\(stimulus.rawValue)"
        let source = Reaction.Source.item(item)
        switch (item, stimulus) {
        case (.fireworkRocket, .fire):
            // Lit, it is gone into the sky, and the whole gang sees it burst.
            return Reaction(id, source, [(0, .react(.perk)), (0.1, .marker("FSSST")), (0.4, .hide(6)), (0.5, .burst(.smoke)),
                                         (0.8, .burst(.sparkles)), (0.9, .marker("BOOM!")), (1.1, .face(.starstruck, 1.2))],
                            emits: .light, target: .everyone)
        case (.bubbleWrap, .impact):
            return Reaction(id, source, [(0, .react(.celebrate)), (0.1, .marker("POP POP POP")),
                                         (0.2, .symbol("○", .white, count: 3)), (0.6, .move(.stomp)), (1.4, .face(.love, 1.0))],
                            emits: .sound)
        case (.compass, .magnet):
            // North is wherever the magnet is, and off it goes the wrong way.
            return Reaction(id, source, [(0, .move(.spin)), (0.2, .marker("N...S...?")), (0.6, .emote(.question)),
                                         (1.1, .move(.sneak)), (1.2, .face(.confused, 1.2))])
        case (.batteryPack, .shock):
            return Reaction(id, source, [(0, .lightning), (0.1, .marker("FULL!")), (0.3, .sparks), (0.5, .move(.charge)),
                                         (1.0, .face(.starstruck, 1.2))],
                            emits: .shock)
        case (.tapShoes, .sound):
            return Reaction(id, source, [(0, .react(.groove)), (0.1, .move(.stomp)), (0.3, .marker("TAP TAP")),
                                         (0.4, .symbol("♪", .gold, count: 2)), (1.2, .move(.bow))],
                            emits: .sound)
        case (.jelly, .impact), (.jelly, .sound):
            // It wobbles, and wobbles, and the wobble bounces on.
            return Reaction(id, source, [(0, .move(.shiver)), (0.1, .marker("WOBBLE")), (0.4, .grow(2)), (0.9, .move(.hop)),
                                         (1.5, .face(.happy, 1.0))],
                            emits: .impact)
        case (.trampoline, .impact):
            return Reaction(id, source, [(0, .react(.perk)), (0.1, .marker("SPROING")), (0.2, .move(.highJump)),
                                         (1.4, .burst(.sparkles)), (1.5, .face(.happy, 0.9))],
                            emits: .wind)
        case (.raincoat, .water), (.raincoat, .goo):
            return Reaction(id, source, [(0, .react(.wave)), (0.1, .burst(stimulus.burst)), (0.2, .marker("BONE DRY")),
                                         (0.4, .move(.spin)), (1.4, .face(.smug, 1.0))])
        case (.garlicNecklace, .hypno):
            // The spiral cannot get through the smell.
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .symbol("~", .green, count: 2)), (0.4, .marker("NOPE")),
                                         (0.8, .face(.disgusted, 1.2)), (1.0, .emote(.ellipsis))])
        case (.lavaLamp, .shock):
            return Reaction(id, source, [(0, .react(.flash)), (0.2, .burst(.sparkles)), (0.4, .marker("GLOW")),
                                         (0.6, .symbol("○", .purple, count: 3)), (1.4, .react(.relax))],
                            emits: .light)
        case (.icePop, .fire):
            return Reaction(id, source, [(0, .react(.panic)), (0.2, .marker("MELTING")), (0.4, .symbol("•", .blue, count: 2)),
                                         (0.8, .hide(5)), (1.0, .face(.crying, 1.4))])
        case (.icePop, .frost):
            return Reaction(id, source, [(0, .react(.celebrate)), (0.2, .symbol("❄", .white, count: 2)), (0.4, .grow(4)),
                                         (0.6, .marker("MEGA POP")), (0.8, .face(.love, 1.2))])
        default:
            return nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// What the older things of the wardrobe make of a chain: the dynamite
    /// goes off, balloons pop, the umbrella keeps dry or takes off, the
    /// sparkler lights, the fan blows the pepper back, the disco ball
    /// throws the light everywhere.
    static func wardrobeReaction(_ item: NotchMascotAccessory, to stimulus: NotchMascotStimulus) -> Reaction? {
        let id = "\(item.rawValue).\(stimulus.rawValue)"
        let source = Reaction.Source.item(item)
        switch (item, stimulus) {
        case (.dynamiteStick, .fire):
            // The fuse hisses, and there is nothing anyone can do.
            return Reaction(id, source, [(0, .react(.panic)), (0.1, .marker("TSSS")), (0.6, .marker("KABOOM")),
                                         (0.6, .burst(.smoke)), (0.7, .hide(8)), (0.8, .move(.backflip)),
                                         (1.4, .face(.dizzy, 1.2))],
                            emits: .impact, target: .everyone, rare: .kaboom)
        case (.marshmallowStick, .fire):
            return Reaction(id, source, [(0, .react(.perk)), (0.2, .burst(.smoke)), (0.4, .marker("TOASTY")),
                                         (0.8, .hide(4)), (1.0, .face(.love, 1.2)), (1.2, .emote(.heart))])
        case (.lonelyBalloon, .impact), (.lonelyBalloon, .fire), (.balloonDog, .impact), (.balloonDog, .fire):
            return Reaction(id, source, [(0, .marker("POP!")), (0.1, .burst(.confetti)), (0.2, .hide(6)),
                                         (0.4, .react(.surprised)), (0.9, .face(.crying, 1.4)), (1.1, .emote(.ellipsis))])
        case (.umbrella, .water):
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .symbol("☂", .blue, count: 1)), (0.4, .marker("DRY")),
                                         (0.8, .face(.smug, 1.2))])
        case (.umbrella, .wind):
            // Up it goes, held by the handle, the way a nanny does it.
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .move(.float)), (0.4, .marker("WHEEE")),
                                         (0.6, .symbol("~", .white, count: 2)), (1.5, .face(.happy, 1.0))])
        case (.kite, .wind):
            return Reaction(id, source, [(0, .react(.celebrate)), (0.2, .move(.highJump)), (0.4, .marker("SOARING")),
                                         (0.6, .symbol("~", .white, count: 2)), (1.5, .face(.starstruck, 1.0))])
        case (.pinwheel, .wind):
            return Reaction(id, source, [(0, .react(.perk)), (0.1, .move(.spin)), (0.3, .marker("WHIZZ")),
                                         (0.5, .symbol("✦", .pink, count: 2)), (1.2, .face(.happy, 1.0))],
                            emits: .wind)
        case (.stormCloud, .wind):
            return Reaction(id, source, [(0, .symbol("☁", .white, count: 1)), (0.3, .lightning), (0.4, .marker("KRAKOOM")),
                                         (0.6, .react(.flash)), (1.0, .face(.angry, 1.2))],
                            emits: .shock)
        case (.wateringCan, .fire):
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .symbol("•", .blue, count: 3)), (0.4, .marker("PSSSH")),
                                         (0.8, .burst(.smoke)), (1.2, .face(.smug, 1.0))],
                            emits: .water)
        case (.headphones, .sound):
            return Reaction(id, source, [(0, .react(.groove)), (0.2, .symbol("♪", .gold, count: 2)), (0.4, .marker("WHAT?")),
                                         (0.8, .face(.smug, 1.2)), (1.2, .emote(.ellipsis))])
        case (.tinfoilHat, .shock):
            return Reaction(id, source, [(0, .lightning), (0.1, .react(.flash)), (0.3, .sparks), (0.5, .marker("CONDUCTING")),
                                         (0.9, .face(.dizzy, 1.2))],
                            emits: .shock)
        case (.tinfoilHat, .hypno):
            // Exactly what the hat is for.
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .marker("NICE TRY")), (0.4, .burst(.sparkles)),
                                         (0.6, .face(.smug, 1.4)), (1.0, .emote(.exclaim))])
        case (.thunderTalisman, .shock):
            return Reaction(id, source, [(0, .lightning), (0.2, .burst(.magic)), (0.4, .marker("ABSORBED")),
                                         (0.6, .react(.relax)), (1.0, .face(.smug, 1.2))])
        case (.sparkler, .fire):
            return Reaction(id, source, [(0, .react(.perk)), (0.2, .sparks), (0.4, .marker("SPARKLE!")),
                                         (0.5, .symbol("✦", .gold, count: 3)), (1.0, .move(.spin))],
                            emits: .light)
        case (.iceCreamCone, .fire):
            return Reaction(id, source, [(0, .react(.panic)), (0.2, .marker("NOOO")), (0.3, .symbol("•", .pink, count: 2)),
                                         (0.8, .hide(5)), (1.0, .face(.crying, 1.4))])
        case (.iceCreamCone, .frost):
            return Reaction(id, source, [(0, .react(.celebrate)), (0.2, .symbol("❄", .white, count: 2)), (0.4, .grow(4)),
                                         (0.6, .marker("DOUBLE SCOOP")), (0.8, .face(.love, 1.2))])
        case (.crystalOrb, .sound), (.crystalSkull, .sound):
            return Reaction(id, source, [(0, .react(.hush)), (0.2, .marker("RINGGG")), (0.3, .burst(.magic)),
                                         (0.5, .symbol("✦", .purple, count: 3)), (1.0, .face(.starstruck, 1.2))])
        case (.pillow, .impact):
            // Feathers everywhere, and every one of them tickles.
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .marker("FWUMP")), (0.2, .burst(.confetti)),
                                         (0.3, .symbol("~", .white, count: 3)), (0.8, .face(.happy, 1.4))],
                            emits: .tickle)
        case (.rubberDuck, .water):
            return Reaction(id, source, [(0, .react(.celebrate)), (0.2, .move(.float)), (0.4, .marker("SQUEAK!")),
                                         (0.6, .symbol("○", .blue, count: 2)), (1.5, .face(.happy, 1.0))],
                            emits: .sound)
        case (.snowGlobe, .sound):
            return Reaction(id, source, [(0, .move(.shiver)), (0.2, .marker("SHAKE SHAKE")), (0.4, .symbol("❄", .white, count: 3)),
                                         (1.0, .burst(.sparkles)), (1.2, .face(.love, 1.0))],
                            emits: .frost)
        case (.spanishFan, .pepper):
            // A flick of the wrist and the pepper goes home.
            return Reaction(id, source, [(0, .react(.ready)), (0.1, .marker("OLE!")), (0.2, .move(.spin)),
                                         (0.6, .symbol("~", .pink, count: 2)), (1.3, .face(.smug, 1.0))],
                            emits: .pepper, target: .back)
        case (.discoBall, .light):
            return Reaction(id, source, [(0, .react(.groove)), (0.1, .burst(.sparkles)), (0.2, .marker("DISCO!")),
                                         (0.3, .symbol("✦", .white, count: 3)), (0.6, .move(.spin)), (1.7, .face(.starstruck, 0.8))],
                            emits: .light)
        case (.horseshoeMagnet, .magnet):
            // Magnet meets magnet, and they will not come apart.
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .move(.charge)), (0.6, .marker("CLUNK")),
                                         (1.0, .face(.embarrassed, 1.4)), (1.2, .emote(.interrobang))])
        case (.superCape, .wind):
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .move(.float)), (0.3, .marker("UP UP AWAY!")),
                                         (0.5, .burst(.sparkles)), (1.5, .face(.determined, 1.0))])
        case (.astronautHelmet, .pepper), (.astronautHelmet, .goo), (.astronautHelmet, .sweet):
            return Reaction(id, source, [(0, .react(.hush)), (0.2, .marker("SEALED")), (0.4, .burst(.sparkles)),
                                         (0.6, .face(.smug, 1.4)), (1.0, .emote(.ellipsis))])
        case (.whoopeeCushion, .impact):
            // Sat on, it speaks, and what it says hangs in the air for the next one.
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .marker("PFFFT")), (0.2, .burst(.smoke)),
                                         (0.4, .face(.embarrassed, 1.4)), (0.8, .symbol("~", .green, count: 2))],
                            emits: .pepper)
        case (.bananaPeel, .impact), (.bananaPeel, .goo):
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .move(.slip)), (0.3, .marker("WHOOPS")),
                                         (0.8, .symbol("★", .gold, count: 2)), (1.6, .face(.dizzy, 1.0))])
        case (.beeHalo, .sweet):
            // The bees smell it and go buzzing round the next one.
            return Reaction(id, source, [(0, .react(.celebrate)), (0.2, .marker("BZZZ")), (0.3, .symbol("•", .gold, count: 3)),
                                         (0.6, .move(.hop)), (1.3, .face(.happy, 1.0))],
                            emits: .tickle)
        case (.wizardStaff, .hypno), (.magicTome, .hypno):
            return Reaction(id, source, [(0, .react(.ready)), (0.2, .burst(.magic)), (0.4, .marker("AMATEUR")),
                                         (0.6, .face(.smug, 1.4)), (1.0, .emote(.ellipsis))])
        case (.cursedMask, .hypno):
            // The mask takes the spiral and stares it back at all of them, twice as deep.
            return Reaction(id, source, [(0, .face(.mischievous, 1.6)), (0.2, .burst(.magic)), (0.4, .marker("DOUBLE OOOH")),
                                         (0.6, .symbol("@", .purple, count: 2)), (1.2, .move(.float))],
                            emits: .hypno, target: .everyone)
        case (.snail, .goo):
            return Reaction(id, source, [(0, .react(.love)), (0.2, .marker("SLIMY!")), (0.4, .symbol("♥", .green, count: 2)),
                                         (1.0, .face(.love, 1.2))])
        case (.lantern, .wind):
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .burst(.smoke)), (0.3, .marker("PFF")),
                                         (0.6, .face(.crying, 1.2)), (1.0, .emote(.ellipsis))])
        case (.lantern, .fire):
            return Reaction(id, source, [(0, .react(.perk)), (0.2, .sparks), (0.4, .marker("LIT")),
                                         (0.5, .symbol("✦", .gold, count: 2)), (1.0, .face(.happy, 1.0))])
        case (.rollerSkates, .wind):
            return Reaction(id, source, [(0, .react(.surprised)), (0.1, .move(.charge)), (0.3, .marker("ZOOM")),
                                         (0.6, .symbol("~", .white, count: 2)), (1.6, .face(.dizzy, 1.0))])
        case (.confettiCannon, .fire):
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .marker("BANG!")), (0.3, .burst(.confetti)),
                                         (0.5, .burst(.confetti)), (0.7, .react(.celebrate))],
                            emits: .sound)
        case (.microphone, .sound):
            return Reaction(id, source, [(0, .react(.panic)), (0.2, .marker("SKREEE")), (0.4, .move(.shiver)),
                                         (0.6, .symbol("♫", .white, count: 2)), (1.3, .face(.embarrassed, 1.0))],
                            emits: .sound)
        case (.boomBox, .shock):
            return Reaction(id, source, [(0, .lightning), (0.2, .marker("BASS DROP")), (0.4, .move(.stomp)),
                                         (0.5, .symbol("♫", .purple, count: 3)), (1.5, .face(.starstruck, 1.0))],
                            emits: .sound)
        case (.kazoo, .wind):
            return Reaction(id, source, [(0, .react(.surprised)), (0.2, .marker("BZZRRT")), (0.4, .symbol("♪", .gold, count: 2)),
                                         (0.8, .face(.embarrassed, 1.2)), (1.0, .emote(.interrobang))],
                            emits: .sound)
        default:
            return nil
        }
    }
}
