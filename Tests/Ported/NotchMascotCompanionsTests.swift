// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// Each companion's own life: its own level, wardrobe and transformation,
/// never the island's companion's; the faces in the island; a fusion that
/// is rarer and stronger; what a thing worn does all the while it is on;
/// the workshop's things and the combos a transformation makes with what
/// the other wears.
enum NotchMascotCompanionsTests {
    static func run(_ suite: TestSuite) {
        ownProgression(suite)
        ownWardrobe(suite)
        faces(suite)
        fusion(suite)
        traits(suite)
        workshop(suite)
        formCombos(suite)
        weather(suite)
    }

    private static func look(_ style: NotchMascotStyle, _ item: NotchMascotAccessory = .none) -> NotchMascotLook {
        NotchMascotLook(style: style, shape: .ball, palette: .sky, accessory: item)
    }

    // MARK: Levels and forms of their own

    private static func ownProgression(_ suite: TestSuite) {
        typealias T = NotchMascotTransformation
        suite.expect(T.friendForm(own: "", companions: "auto", level: 1, style: .cat) == nil
                     && T.friendForm(own: nil, companions: "auto", level: 19, style: .cat) == nil,
                     "a friend at a low level shows no form, whatever the companion's level unlocks")
        suite.expect(T.friendForm(own: "", companions: "auto", level: 20, style: .cat) == .golden
                     && T.friendForm(own: "", companions: "auto", level: 50, style: .cat) == .divine,
                     "a friend's own level opens its own forms")
        suite.expect(T.friendForm(own: "none", companions: "auto", level: 50, style: .cat) == nil,
                     "a friend told to wear none wears none")
        suite.expect(T.friendForm(own: "goldenFury", companions: "auto", level: 25, style: .cat) == .golden,
                     "a form picked before its level falls back to the newest its level unlocks")
        suite.expect(T.friendForm(own: "", companions: "none", level: 50, style: .dog) == nil
                     && T.friendForm(own: "", companions: "goldenLightning", level: 50, style: .dog) == .goldenLightning,
                     "with no choice of its own the friend follows the companion's choice, against its own level")
        let named = Notification(name: .notchMascotTransforms, object: NotchMascotStyle.dog.rawValue)
        let everyone = Notification(name: .notchMascotTransforms, object: nil)
        suite.expect(T.concerns(named, style: .dog) && !T.concerns(named, style: .cat)
                     && T.concerns(everyone, style: .cat) && T.concerns(everyone, style: .dog),
                     "a transformation announced for one figure plays on that figure alone")
        suite.expect(NotchMascotGrowth.shownLevel(earned: 3, name: NotchMascotGrowth.unlockAllName) == NotchMascotGrowth.maxLevel
                     && NotchMascotGrowth.shownLevel(earned: 3, name: "Pip") == 3,
                     "the name that unlocks everything lifts the level it is asked about")
    }

    // MARK: Wardrobes of their own

    private static func ownWardrobe(_ suite: TestSuite) {
        for style in NotchMascotStyle.allCases {
            let kit = NotchMascotShop.startingKit(for: style)
            suite.expect(kit.count == NotchMascotShop.kitSize && Set(kit).count == kit.count
                         && kit.allSatisfy { $0.isPurchasable && ($0.isToyItem || $0.isPartyItem || $0.isOddity) }
                         && kit == NotchMascotShop.startingKit(for: style),
                         "\(style.rawValue) brings two things of its own along, the same every time")
        }
        suite.expect(Set(NotchMascotStyle.allCases.map { NotchMascotShop.startingKit(for: $0) }).count > 10,
                     "the figures do not all bring the same things")
        let owns: (NotchMascotAccessory) -> Bool = { $0 == .drum }
        let wardrobe = NotchMascotGangCasting.wardrobe(for: .cat, level: 5, owns: owns)
        suite.expect(wardrobe.contains(.drum) && !wardrobe.contains(.microphone) && wardrobe.contains(.bow)
                     && !wardrobe.contains(.crown) && !wardrobe.contains(.none),
                     "a guest wears what its own level unlocks and what it owns, nothing of anyone else's")
        var tick = 0.0
        let random: () -> Double = { tick += 0.173; return tick.truncatingRemainder(dividingBy: 1) }
        for _ in 0..<12 {
            let guest = NotchMascotGangCasting.look(for: .cat, level: 5, owns: owns, formChoice: "auto", random: random)
            suite.expect(wardrobe.contains(guest.accessory) && guest.form == nil,
                         "a guest comes dressed from its own wardrobe and untransformed at a low level")
        }
        let strong = NotchMascotGangCasting.look(for: .dog, level: 30, owns: { _ in false }, formChoice: "auto", random: random)
        suite.expect(strong.form == .goldenLightning, "a guest that grew to a form of its own comes transformed")
        suite.expect(NotchMascotWardrobe.friendAccessory(main: .flower, level: 18, style: .cat, chosen: .drum, owns: { _ in false }) == .none
                     && NotchMascotWardrobe.friendAccessory(main: .flower, level: 18, style: .cat, chosen: .drum, owns: { $0 == .drum }) == .drum,
                     "a thing given to the friend shows only once the friend owns it")
        let own = NotchMascotWardrobe.friendAccessory(main: .flower, level: 1, style: .cat, owns: { $0 == .kazoo })
        suite.expect(own == .kazoo, "with nothing unlocked by level the friend still wears what it owns")
        suite.expect(NotchMascotAccessory.bow.isUnlocked(level: 2, for: .cat) && !NotchMascotAccessory.crown.isUnlocked(level: 2, for: .cat),
                     "what a level earns is measured against that figure's level")
        suite.expect(NotchMascotShop.forSale.contains(.electricGuitar) && NotchMascotShop.forSale.contains(.pogoStick),
                     "the workshop is for sale")
        let kit = NotchMascotShop.startingKit(for: .frog)
        var counter = 0.0
        let stock = NotchMascotShop.roll(gold: 0, for: .frog, random: { counter += 0.137; return counter.truncatingRemainder(dividingBy: 1) })
        suite.expect(!stock.isEmpty && stock.allSatisfy { !kit.contains($0) }, "the shop never sells a figure what it brought along")
    }

    // MARK: Faces in the island

    private static func faces(_ suite: TestSuite) {
        typealias C = NotchMascotCreatures
        for style in [NotchMascotStyle.minimal, .robot, .chip, .fan] {
            suite.expect(!C.showsFaceOnly(look(style)) && C.faceFit(look(style)) == .identity,
                         "\(style.rawValue) is all face already")
        }
        for style in [NotchMascotStyle.cat, .dog, .dragon, .swan, .ballerina, .android, .frog, .phoenix, .cristobal, .whiteRabbit] {
            let fit = C.faceFit(look(style))
            let head = C.headOutline(style, size: 1)!.applying(fit)
            suite.expect(C.showsFaceOnly(look(style)) && fit.a > 1 && fit.a == fit.d
                         && abs(head.midX - 0.5) < 0.001 && abs(head.midY - C.faceCenterY) < 0.001
                         && head.width <= C.faceFill + 0.001 && head.height <= C.faceFill + 0.001,
                         "\(style.rawValue)'s head fills the box, centred, the same scale across and down")
            let mask = C.faceMask(look(style), size: 100)
            suite.expect(mask.contains(CGPoint(x: 50, y: 50)) && mask.contains(CGPoint(x: 50, y: 5))
                         && !mask.contains(CGPoint(x: 50, y: 99 + 40)),
                         "\(style.rawValue)'s portrait shows the face and room for a hat, and cuts the body off under the chin")
            let face = C.facedFace(look(style))
            suite.expect(face.leftEye.x < face.rightEye.x && face.leftEye.y > 0 && face.leftEye.y < 1,
                         "\(style.rawValue)'s eyes stay in the box where the portrait puts them")
        }
        suite.expect(C.faceShows(.topHat) && C.faceShows(.glasses) && C.faceShows(.scarf) && C.faceShows(.headphones)
                     && !C.faceShows(.legendSword) && !C.faceShows(.wingBoots) && !C.faceShows(.jetpack),
                     "a portrait shows what is on the head, the face, the ears and the neck, and nothing held or worn below")
    }

    // MARK: A rarer, stronger fusion

    private static func fusion(_ suite: TestSuite) {
        typealias F = NotchMascotFusion
        let due = F.interval + 1, played = NotchMascotPlay.interval + 1
        suite.expect(F.interval >= 1800 && F.chance <= 0.1, "a fusion of their own accord is rarer than a level")
        suite.expect(F.due(since: due, sincePlay: played, relation: nil, today: 0, random: 0)
                     && F.due(since: due, sincePlay: played, relation: nil, today: F.dailyCap - 1, random: 0)
                     && !F.due(since: due, sincePlay: played, relation: nil, today: F.dailyCap, random: 0),
                     "only so many fusions of their own accord a day")
        suite.expect(F.count(in: nil, day: "2026-11-07") == 0 && F.count(in: "2026-11-07:2", day: "2026-11-07") == 2
                     && F.count(in: "2026-11-06:2", day: "2026-11-07") == 0 && F.count(in: "junk", day: "2026-11-07") == 0,
                     "the day's count is read from its record, and another day's is nothing")
        suite.expect(F.recording(nil, day: "2026-11-07") == "2026-11-07:1"
                     && F.recording("2026-11-07:1", day: "2026-11-07") == "2026-11-07:2"
                     && F.recording("2026-11-06:5", day: "2026-11-07") == "2026-11-07:1",
                     "a fusion recorded counts one more today")
        let slow = F.moveGap(level: 1), quick = F.moveGap(level: 50)
        suite.expect(slow == F.moveGap && quick.lowerBound < slow.lowerBound && quick.upperBound < slow.upperBound
                     && quick.lowerBound >= slow.lowerBound * 0.5,
                     "the fused one of a stronger pair shows off more often")
        suite.expect(F.powerBoost > 1 && F.experience > 0 && F.gold > 0 && F.tapCooldown > 0,
                     "a fusion hits harder than the pair and pays both when it goes well")
    }

    // MARK: What a thing worn does all the while

    private static func traits(_ suite: TestSuite) {
        typealias Trait = NotchMascotItemTrait
        suite.expect(Trait.of(.none).isPlain && Trait.of(.glasses).isPlain, "a plain thing changes nothing")
        suite.expect(Trait.of(.wingBoots).gait > 1 && Trait.of(.wingBoots).hop > 1 && Trait.of(.skateboard).gait > 1.4,
                     "winged boots and a skateboard quicken it")
        suite.expect(Trait.of(.magicMushroom).scale > 1 && Trait.of(.sunglasses).face == .smug
                     && Trait.of(.sleepMask).face == .sleepy && Trait.of(.sleepMask).gait < 1,
                     "a mushroom keeps it bigger, sunglasses keep it smug, a sleep mask slows it")
        suite.expect(Trait.of(.headphones).trail == .notes && Trait.of(.flower).trail == .petals
                     && Trait.of(.stormCloud).trail == .drops && Trait.of(.bubbleWand).trail == .bubbles,
                     "what it wears leaves its mark behind it")
        for item in NotchMascotAccessory.allCases {
            let trait = Trait.of(item)
            suite.expect((0.5...2).contains(trait.gait) && (1...2).contains(trait.hop) && (1...1.3).contains(trait.scale),
                         "\(item.rawValue) keeps its pace, its jumps and its size within reason")
        }
        let shown = NotchMascotAccessory.allCases.filter { !Trait.of($0).isPlain }.count
        suite.expect(shown >= 60, "most things worn show all the while: \(shown)")
        suite.expect(Trait.Trail.sparks.symbol == nil && Trait.Trail.notes.symbol == "♪" && Trait.Trail.hearts.symbol == "♥",
                     "a trail is drawn as sparks or as a symbol")
    }

    // MARK: The workshop

    private static func workshop(_ suite: TestSuite) {
        let items = NotchMascotAccessory.craftItems
        suite.expect(items.count == NotchMascotCraftStrings.itemCount && items.allSatisfy(\.isCraftItem)
                     && items.allSatisfy(\.isPurchasable) && items.allSatisfy { NotchMascotAccessory.wardrobe.contains($0) },
                     "the workshop's eight are for sale and in the wardrobe")
        for language in AppLanguage.allCases {
            let words = FeatureStrings.notchMascotCraft(language)
            suite.expect(words.isComplete && Set(words.items).count == NotchMascotCraftStrings.itemCount
                         && items.allSatisfy { words.name(of: $0) != nil && words.gag(of: $0) != nil },
                         "\(language) names every workshop thing apart and says what it does")
        }
        let frame = NotchMascotWearableFrame(outline: CGRect(x: 20, y: 30, width: 60, height: 60), size: 100,
                                             leftEye: CGPoint(x: 38, y: 55), rightEye: CGPoint(x: 62, y: 55))
        for item in items {
            suite.expect(!NotchMascotWearableShapes.parts(for: item, in: frame).isEmpty, "\(item.rawValue) is drawn")
            suite.expect(NotchMascotItemSignature.of(item) != nil, "\(item.rawValue) brings a move to every combo")
            let use = NotchMascotItemUse.of(item)
            suite.expect(use != nil && (use?.length ?? 0) > 1 && (use?.length ?? 99) < 8
                         && use?.islandBeats(byLeader: true).isEmpty == false,
                         "\(item.rawValue) has a trick of its own, on the desktop and in the island")
            suite.expect(item.rarity.priceRange.contains(item.price), "\(item.rawValue) costs what its rarity costs")
            suite.expect(FeatureStrings.notchMascotLife(.es).name(of: item) == FeatureStrings.notchMascotCraft(.es).name(of: item)
                         && FeatureStrings.notchMascotShop(.es).gag(of: item) != nil,
                         "\(item.rawValue) is named and explained wherever things are")
        }
        suite.expect(NotchMascotItemUse.of(.matchaBowl, style: .capybara) != NotchMascotItemUse.of(.matchaBowl, style: .cat)
                     && NotchMascotItemUse.of(.shovel, style: .penguin) != NotchMascotItemUse.of(.shovel, style: .dog),
                     "some figures have their own way with the workshop's things")
        suite.expect(NotchMascotItemUse.of(.shovel)?.steps.contains { if case .gold = $0.action { return true } else { return false } } == true,
                     "digging may turn up treasure")
    }

    // MARK: A form meets what the other wears

    private static func formCombos(_ suite: TestSuite) {
        typealias Catalog = NotchMascotSynergyCatalog
        let forms = Catalog.synergies(in: .forms)
        suite.expect(forms.count == 12 && Catalog.synergies(in: .workshop).count == 8, "the new families hold their share")
        suite.expect(forms.allSatisfy { synergy in
            switch synergy.match {
            case .formWears, .bothFormed: return true
            default: return false
            }
        }, "every combo of the transformations needs a transformed one")
        let midas = Catalog.synergy(id: "midasTouch")!
        suite.expect(midas.matches(leaderWears: .none, friendWears: .goldBag, leaderStyle: .cat, friendStyle: .dog,
                                   leaderForm: .golden, friendForm: nil)
                     && midas.matches(leaderWears: .goldBag, friendWears: .none, leaderStyle: .cat, friendStyle: .dog,
                                      leaderForm: nil, friendForm: .divine)
                     && !midas.matches(leaderWears: .none, friendWears: .goldBag, leaderStyle: .cat, friendStyle: .dog)
                     && !midas.matches(leaderWears: .goldBag, friendWears: .none, leaderStyle: .cat, friendStyle: .dog,
                                       leaderForm: .golden, friendForm: nil),
                     "a form on one and the thing on the other make it, whichever way round; the thing on the transformed one alone does not")
        suite.expect(midas.starterIsLeader(leaderWears: .none, friendWears: .goldBag, leaderStyle: .cat, friendStyle: .dog,
                                           leaderForm: .golden, friendForm: nil, fallback: false)
                     && !midas.starterIsLeader(leaderWears: .goldBag, friendWears: .none, leaderStyle: .cat, friendStyle: .dog,
                                               leaderForm: nil, friendForm: .golden, fallback: true),
                     "the transformed one starts a combo of the forms")
        let both = Catalog.candidates(leaderWears: .none, friendWears: .none, leaderStyle: .cat, friendStyle: .dog,
                                      leaderForm: .golden, friendForm: .goldenFury)
        suite.expect(both.contains { $0.id == "sharedAura" }
                     && !Catalog.candidates(leaderWears: .none, friendWears: .none, leaderStyle: .cat, friendStyle: .dog,
                                            leaderForm: .golden, friendForm: nil).contains { $0.id == "sharedAura" },
                     "two transformed share their auras; one alone does not")
        let plain = Catalog.candidates(leaderWears: .goldBag, friendWears: .none, leaderStyle: .cat, friendStyle: .dog)
        suite.expect(!plain.contains { $0.id == "midasTouch" }, "without a form the old combos play as they did")
        suite.expect(Catalog.partners(of: .goldBag).contains { $0.item == .none && $0.synergy.id == "midasTouch" },
                     "the hint for a bag of gold names a transformed friend")
        for synergy in forms + Catalog.synergies(in: .workshop) {
            let play = synergy.play(starterIsLeader: true)
            suite.expect(!play.beats.isEmpty && play.length > 0 && play.length < 14, "\(synergy.id) plays out in a few seconds")
        }
        let context = NotchMascotIslandPlay.Context(since: .infinity, music: false, hour: 12, leaderWears: .none,
                                                    friendWears: .goldBag, leaderStyle: .cat, friendStyle: .dog,
                                                    leaderForm: .golden, friendForm: nil)
        suite.expect(NotchMascotIslandPlay.synergyKinds(in: context).contains(.synergy("midasTouch")),
                     "the island offers the combo a form makes with what the friend wears")
    }

    // MARK: The weather, and a star by day

    private static func weather(_ suite: TestSuite) {
        for encounter in [NotchMascotEncounter.zeroGravity, .rainShower] {
            suite.expect(encounter.allowed(hour: 3, wearsItem: false) && encounter.allowed(hour: 15, wearsItem: false)
                         && !encounter.grounded && encounter.weight > 0 && encounter.length > 5 && encounter.gathers == nil,
                         "\(encounter.rawValue) may come at any hour, on a window too, and each just watches it")
        }
        func picks(telescope: Bool) -> Set<NotchMascotEncounter> {
            Set(stride(from: 0.0, to: 1.0, by: 0.005).compactMap {
                NotchMascotEncounters.pick(hour: 12, wearsItem: true, recent: [], random: $0, telescope: telescope)
            })
        }
        suite.expect(picks(telescope: true).contains(.shootingStar) && !picks(telescope: false).contains(.shootingStar),
                     "with a telescope the stars come by day")
        suite.expect(picks(telescope: false).contains(.zeroGravity) && picks(telescope: false).contains(.rainShower),
                     "the weather comes round like the rest")
    }
}
