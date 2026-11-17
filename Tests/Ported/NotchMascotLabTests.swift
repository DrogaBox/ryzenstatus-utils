// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The lab and mayhem: forty-eight things drawn, named in every language,
/// priced and sold, each worn its own way, used on its own, taken their own
/// way by some figures, making combos and fusions, luring rare sights, and
/// each throwing or taking a stimulus in a chain at the odds it says.
enum NotchMascotLabTests {
    static func run(_ suite: TestSuite) {
        catalog(suite)
        words(suite)
        drawings(suite)
        shop(suite)
        uses(suite)
        combos(suite)
        fusions(suite)
        chainRoles(suite)
        luck(suite)
    }

    private static let lab = NotchMascotAccessory.labItems
    private static let mayhem = NotchMascotAccessory.mayhemItems
    private static let items = lab + mayhem

    /// Every letter is in the arcade font: a glyph is 4 cells, a space 2.
    private static func drawable(_ text: String) -> Bool {
        let spaces = text.filter { $0 == " " }.count
        return !text.isEmpty && NotchMascotRPGShapes.cells(of: text) == (text.count - spaces) * 4 + spaces * 2 - 1
    }

    private static func markers(_ steps: [NotchMascotItemUse.Step]) -> [String] {
        steps.compactMap { step -> String? in
            if case .marker(let text) = step.action { return text } else { return nil }
        }
    }

    private static func catalog(_ suite: TestSuite) {
        suite.expect(lab.count == 24 && mayhem.count == 24 && Set(items).count == 48,
                     "the lab and mayhem hold twenty-four things each, none twice")
        suite.expect(items.allSatisfy { $0.isPurchasable && $0.isPickable }, "all of them are sold and can be picked")
        suite.expect(lab.allSatisfy { $0.isLabItem && !$0.isMayhemItem } && mayhem.allSatisfy { $0.isMayhemItem && !$0.isLabItem },
                     "each belongs to its own family")
        var older = Set(NotchMascotAccessory.rpgItems)
        older.formUnion(NotchMascotAccessory.shopItems)
        older.formUnion(NotchMascotAccessory.danceItems)
        older.formUnion(NotchMascotAccessory.toyItems)
        older.formUnion(NotchMascotAccessory.partyItems)
        older.formUnion(NotchMascotAccessory.oddityItems)
        older.formUnion(NotchMascotAccessory.craftItems)
        older.formUnion(NotchMascotAccessory.fairItems)
        suite.expect(Set(items).isDisjoint(with: older), "no new thing belongs to an older family")
        suite.expect(NotchMascotAccessory.lightningRod.placement == .head && NotchMascotAccessory.gasMask.placement == .eyes
                     && NotchMascotAccessory.garlicNecklace.placement == .neck && NotchMascotAccessory.rubberBoots.placement == .feet
                     && NotchMascotAccessory.trampoline.placement == .feet && NotchMascotAccessory.batteryPack.placement == .back
                     && NotchMascotAccessory.raincoat.placement == .back && NotchMascotAccessory.torch.placement == .hand,
                     "each sits where it belongs")
        suite.expect(NotchMascotWearables.behindBody(.batteryPack) && NotchMascotWearables.behindBody(.raincoat)
                     && NotchMascotWearables.coversHead(.lightningRod),
                     "the battery and the raincoat go behind the body, the rod covers the head")
        suite.expect(Array(NotchMascotAccessory.wardrobe.suffix(items.count)) == items,
                     "the lab and then mayhem come last in the wardrobe")
        suite.expect(Set(items.map(\.rawValue)).count == 48
                     && items.allSatisfy { NotchMascotAccessory(rawValue: $0.rawValue) == $0 },
                     "each is kept by a name of its own, so what is bought is saved and read back")
    }

    private static func words(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.notchMascotLab(language)
            suite.expect(strings.isComplete && Set(strings.items).count == items.count,
                         "\(language) names every new thing apart")
            suite.expect(items.allSatisfy { strings.name(of: $0) != nil && strings.gag(of: $0) != nil },
                         "\(language) says what every new thing does")
        }
        let language = L10n.shared.language
        let strings = FeatureStrings.notchMascotLab(language)
        let life = FeatureStrings.notchMascotLife(language)
        let shop = FeatureStrings.notchMascotShop(language)
        suite.expect(items.allSatisfy { life.name(of: $0) == strings.name(of: $0) && shop.gag(of: $0) == strings.gag(of: $0) },
                     "the wardrobe and the shop word them as their own strings do")
    }

    private static func drawings(_ suite: TestSuite) {
        let round = NotchMascotWearableFrame(outline: CGRect(x: 4, y: 6, width: 20, height: 18), size: 28,
                                             leftEye: CGPoint(x: 11, y: 14), rightEye: CGPoint(x: 18, y: 14))
        for item in items {
            let parts = NotchMascotWearableShapes.parts(for: item, in: round)
            suite.expect(!parts.isEmpty && parts.allSatisfy { !$0.path.boundingBoxOfPath.isNull && !$0.path.isEmpty },
                         "\(item.rawValue) is drawn")
            let box = parts.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
            suite.expect(box.width > 1 && box.height > 1 && box.width < round.size * 4 && box.height < round.size * 4,
                         "\(item.rawValue) is drawn at the figure's scale")
        }
    }

    private static func shop(_ suite: TestSuite) {
        suite.expect(items.allSatisfy { $0.price > 0 && $0.rarity.priceRange.contains($0.price) },
                     "every new thing costs what its rarity costs")
        suite.expect(Set(lab.map(\.rarity)) == Set(NotchMascotRarity.allCases)
                     && Set(mayhem.map(\.rarity)) == Set(NotchMascotRarity.allCases),
                     "the lab and mayhem each have something of every rarity")
        suite.expect(NotchMascotAccessory.mysteryEgg.rarity == .legendary && NotchMascotAccessory.bigRedButton.rarity == .legendary
                     && NotchMascotAccessory.voodooDoll.rarity == .legendary && NotchMascotAccessory.torch.rarity == .common,
                     "the egg, the button and the doll are legendary; the torch is common")
        suite.expect(items.allSatisfy { NotchMascotShop.forSale.contains($0) }, "the shop can sell every new thing")
        suite.expect(NotchMascotStyle.allCases.allSatisfy { style in
            NotchMascotShop.startingKit(for: style).allSatisfy { !$0.isLabItem && !$0.isMayhemItem }
        }, "no figure's kit from home changes")
    }

    private static func uses(_ suite: TestSuite) {
        for item in items {
            suite.expect(!NotchMascotItemTrait.of(item).isPlain, "\(item.rawValue) shows while it is worn")
            suite.expect(NotchMascotItemSignature.of(item) != nil, "\(item.rawValue) opens a combo its own way")
            for roll in [0.0, 0.2, 0.5, 0.99] {
                guard let use = NotchMascotItemUse.of(item, random: { roll }) else {
                    suite.expect(false, "\(item.rawValue) is used on its own")
                    continue
                }
                suite.expect(use.length > 0.5 && use.length < 15 && !use.islandBeats(byLeader: true).isEmpty,
                             "\(item.rawValue) plays out in a few seconds, in the island too")
                for text in markers(use.steps) {
                    suite.expect(drawable(text), "\(item.rawValue) marker \(text) can be drawn in pixels")
                }
            }
        }
        let twists = NotchMascotItemTwists.pairs.filter { $0.item.isLabItem || $0.item.isMayhemItem }
        suite.expect(twists.count >= 16 && Set(twists).count == twists.count,
                     "at least sixteen figures take a new thing their own way: \(twists.count)")
        for pair in twists {
            suite.expect(NotchMascotItemUse.of(pair.item, style: pair.style) != NotchMascotItemUse.of(pair.item, random: { 0.1 }),
                         "the \(pair.style.rawValue) has its own take on the \(pair.item.rawValue)")
        }
        let lures = items.filter { !NotchMascotEncounters.lured(by: $0).isEmpty }
        suite.expect(lures.count >= 6, "some new things lure rare sights in: \(lures.count)")
    }

    private static func combos(_ suite: TestSuite) {
        let labCombos = NotchMascotSynergyCatalog.synergies(in: .lab)
        let mayhemCombos = NotchMascotSynergyCatalog.synergies(in: .mayhem)
        let all = NotchMascotSynergyCatalog.all
        suite.expect(labCombos.count >= 30 && mayhemCombos.count >= 30,
                     "the lab and mayhem bring thirty combos or more each: \(labCombos.count), \(mayhemCombos.count)")
        suite.expect(all.map(\.number) == Array(1...all.count) && Set(all.map(\.id)).count == all.count,
                     "the catalog is numbered without gaps, an id each")
        suite.expect(labCombos.first?.number == 418, "the lab's combos start at 418")
        suite.expect(SynergyCategory.lab.title == "The lab" && SynergyCategory.mayhem.titleES == "El caos",
                     "the new families are named")
        for synergy in labCombos + mayhemCombos {
            suite.expect(!synergy.name.isEmpty && !synergy.nameES.isEmpty && !synergy.description.isEmpty
                         && !synergy.descriptionES.isEmpty, "\(synergy.id) is named and told in both languages")
            let play = synergy.play(starterIsLeader: true)
            suite.expect(!play.beats.isEmpty && play.length < 20, "\(synergy.id) plays out")
            for beat in play.beats {
                if let marker = beat.marker { suite.expect(drawable(marker.text) || marker.text.contains("♥") || marker.text.contains("♪"),
                                                           "\(synergy.id) marker \(marker.text) is drawable") }
            }
        }
        // Each new pair finds its own combo, whoever wears which.
        for synergy in labCombos + mayhemCombos {
            guard case .pair(let a, let b) = synergy.match else { continue }
            let found = NotchMascotSynergyCatalog.candidates(leaderWears: a, friendWears: b, leaderStyle: .minimal,
                                                             friendStyle: .minimal)
            let swapped = NotchMascotSynergyCatalog.candidates(leaderWears: b, friendWears: a, leaderStyle: .minimal,
                                                               friendStyle: .minimal)
            suite.expect(found.contains(synergy) && swapped.contains(synergy), "\(a.rawValue) and \(b.rawValue) make \(synergy.id)")
        }
        let paired = Set((labCombos + mayhemCombos).flatMap { synergy -> [NotchMascotAccessory] in
            switch synergy.match {
            case .pair(let a, let b): return [a, b]
            case .twin(let a), .wears(let a), .styleWears(_, let a), .formWears(let a): return [a]
            default: return []
            }
        }).intersection(items)
        suite.expect(paired.count >= 36, "most new things are in a combo: \(paired.count) of 48")
    }

    private static func fusions(_ suite: TestSuite) {
        let fused = NotchMascotFusion.labFusions
        suite.expect(fused.count >= 8, "the new things bring their own fusions: \(fused.count)")
        suite.expect(fused.allSatisfy { $0.item.map { $0.isLabItem || $0.isMayhemItem } == true },
                     "each needs one of the new things on")
        suite.expect(Set(fused.map(\.name)).count == fused.count
                     && Set(NotchMascotFusion.catalog.map(\.name)).count == NotchMascotFusion.catalog.count,
                     "every fusion has a name of its own")
        for special in fused {
            guard let item = special.item, let style = special.styles.first else { continue }
            let a = NotchMascotLook(style: style, shape: .ball, palette: .pearl, accessory: item)
            let b = NotchMascotLook(style: special.styles.count > 1 ? special.styles[1] : .minimal, shape: .ball, palette: .pearl)
            let hour = special.night ? 2 : 14
            suite.expect(NotchMascotFusion.special(a, b, hour: hour)?.name == special.name,
                         "\(special.name) comes of a \(style.rawValue) with the \(item.rawValue)")
        }
    }

    /// Every new thing has a part to play in a chain: it throws something,
    /// or makes something of what is thrown at it.
    private static func chainRoles(_ suite: TestSuite) {
        let reactions = NotchMascotChainReactions.self
        for item in items {
            let throwsIt = reactions.itemEmission(item) != nil
            let takesIt = NotchMascotStimulus.allCases.contains { reactions.itemReaction(item, to: $0, random: { 0.5 }) != nil }
            suite.expect(throwsIt || takesIt, "\(item.rawValue) plays a part in chains")
        }
        let throwers: [(NotchMascotAccessory, NotchMascotStimulus)] = [
            (.torch, .fire), (.waterBalloon, .water), (.leafBlower, .wind), (.plasmaBall, .shock), (.freezeRay, .frost),
            (.laserPointer, .light), (.tuningFork, .sound), (.pepperShaker, .pepper), (.squeakyHammer, .impact),
            (.giantMagnet, .magnet), (.honeyJar, .sweet), (.slimeBlaster, .goo), (.airHorn, .sound), (.hypnoSpiral, .hypno),
            (.tickleFeather, .tickle), (.hotSauce, .fire), (.cheeseWheel, .sweet), (.stickyHand, .goo),
        ]
        for (item, stimulus) in throwers {
            suite.expect(reactions.itemEmission(item)?.stimulus == stimulus, "the \(item.rawValue) throws \(stimulus)")
        }
        func take(_ item: NotchMascotAccessory, _ stimulus: NotchMascotStimulus, roll: Double = 0.5) -> NotchMascotChainReaction? {
            reactions.itemReaction(item, to: stimulus, random: { roll })
        }
        suite.expect(take(.rubberBoots, .shock)?.stops == true && take(.rubberBoots, .water)?.stops == true,
                     "rubber boots stop a spark and water")
        suite.expect(take(.gasMask, .pepper)?.stops == true, "the gas mask stops a sneeze")
        suite.expect(take(.raincoat, .water)?.stops == true && take(.umbrella, .water)?.stops == true,
                     "the raincoat and the umbrella stay dry")
        suite.expect(take(.lightningRod, .shock)?.emits == .shock && take(.pocketMirror, .light)?.emits == .light,
                     "the rod passes a spark on, the mirror the light")
        suite.expect(take(.fireExtinguisher, .fire)?.emits == .water && take(.windChime, .wind)?.emits == .sound
                     && take(.popcornBucket, .fire)?.emits == .impact,
                     "foam out of fire, a tune out of wind, kernels out of fire")
        suite.expect(take(.dynamiteStick, .fire)?.target == .everyone && take(.dynamiteStick, .fire)?.rare == .kaboom,
                     "dynamite and fire reach everyone")
        suite.expect(take(.spanishFan, .pepper)?.target == .back, "the fan blows the pepper back")
        suite.expect(take(.voodooDoll, .fire, roll: 0.5)?.target == .random, "the doll sends it anywhere")
        suite.expect(take(.fireworkRocket, .fire)?.target == .everyone && take(.fireworkRocket, .fire)?.emits == .light,
                     "the rocket lights up everyone")
        // A thing worn decides before the figure: boots on a robot stop the spark.
        let robot = NotchMascotChainMember(.rubberBoots, .robot, x: 0)
        suite.expect(NotchMascotChain.reaction(of: robot, to: .shock, random: { 0 }).source == .item(.rubberBoots),
                     "what it wears comes before its figure")
        // Old things join in.
        suite.expect(take(.kite, .wind) != nil && take(.umbrella, .wind) != nil && take(.stormCloud, .wind)?.emits == .shock
                     && take(.marshmallowStick, .fire) != nil && take(.pillow, .impact) != nil,
                     "the kite, the umbrella, the storm cloud, the marshmallow and the pillow join chains")
    }

    /// The odds of the lucky outcomes, at their exact thresholds.
    private static func luck(_ suite: TestSuite) {
        func rare(_ item: NotchMascotAccessory, _ stimulus: NotchMascotStimulus, _ roll: Double) -> NotchMascotChainRare? {
            NotchMascotChainReactions.itemReaction(item, to: stimulus, random: { roll })?.rare
        }
        suite.expect(rare(.mysteryEgg, .fire, 0.5) == nil, "most eggs hatch a chick")
        suite.expect(rare(.pinata, .impact, 0.5) == nil && rare(.seedPacket, .water, 0.5) == nil,
                     "most piñatas and seeds are plain")
        let rolls = (0..<1000).map { (Double($0) + 0.5) / 1000 }
        func share(_ item: NotchMascotAccessory, _ stimulus: NotchMascotStimulus, _ wanted: NotchMascotChainRare) -> Double {
            Double(rolls.filter { roll in rare(item, stimulus, roll) == wanted }.count) / Double(rolls.count)
        }
        suite.expectClose(share(.mysteryEgg, .fire, .babyDragon), 0.10, "a baby dragon one egg in ten", tol: 0.011)
        suite.expectClose(share(.mysteryEgg, .fire, .goldenEgg), 0.05, "a golden egg one in twenty", tol: 0.011)
        suite.expectClose(share(.seedPacket, .water, .beanstalk), 0.08, "a beanstalk 8 %", tol: 0.011)
        suite.expectClose(share(.pinata, .impact, .goldenPinata), 0.15, "a golden piñata 15 %", tol: 0.011)
        suite.expectClose(share(.voodooDoll, .fire, .voodooCurse), 0.10, "the doll curses its holder 10 %", tol: 0.011)
        suite.expectClose(share(.metalDetector, .magnet, .treasure), 0.05, "treasure 5 %", tol: 0.011)
        suite.expectClose(share(.bigRedButton, .impact, .bigBang), 0.03, "the big bang 3 %", tol: 0.011)
        suite.expect(rare(.fishBowl, .frost, 0.5) == .iceAge, "frost on the fish bowl is an ice age")
    }
}
