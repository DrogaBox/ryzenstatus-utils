// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The fair and the field: twenty-four things drawn, named in every
/// language, priced and sold, each worn its own way, used on its own,
/// taken their own way by some figures, and making combos with each other,
/// with the rest of the wardrobe, with a transformed one and with the right
/// figure. What they lure and the two rare things that come with them.
enum NotchMascotFairTests {
    static func run(_ suite: TestSuite) {
        catalog(suite)
        words(suite)
        drawings(suite)
        shop(suite)
        uses(suite)
        combos(suite)
        lures(suite)
    }

    private static let items = NotchMascotAccessory.fairItems

    private static func catalog(_ suite: TestSuite) {
        suite.expect(items.count == NotchMascotFairStrings.itemCount && Set(items).count == items.count
                     && items.allSatisfy { $0.isFairItem && $0.isPurchasable && $0.isPickable },
                     "the fair holds twenty-four things, all of them for sale and pickable")
        suite.expect(items.allSatisfy { !$0.isCraftItem && !$0.isOddity && !$0.isPartyItem && !$0.isToyItem },
                     "no fair thing belongs to another family")
        suite.expect(NotchMascotAccessory.hardHat.placement == .head && NotchMascotAccessory.astronautHelmet.placement == .head
                     && NotchMascotAccessory.binoculars.placement == .eyes && NotchMascotAccessory.superCape.placement == .back
                     && NotchMascotAccessory.stilts.placement == .feet && NotchMascotAccessory.fishingRod.placement == .hand,
                     "each fair thing sits where it belongs")
        suite.expect(NotchMascotWearables.behindBody(.superCape) && NotchMascotWearables.coversHead(.astronautHelmet)
                     && NotchMascotWearables.coversHead(.hardHat),
                     "the cape goes behind the body and the helmets cover the head")
        suite.expect(Array(NotchMascotAccessory.wardrobe.suffix(items.count)) == items,
                     "the fair comes last in the wardrobe, after the workshop")
    }

    private static func words(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let fair = FeatureStrings.notchMascotFair(language)
            suite.expect(fair.isComplete && Set(fair.items).count == items.count,
                         "\(language) names every fair thing apart")
            suite.expect(items.allSatisfy { fair.name(of: $0) != nil && fair.gag(of: $0) != nil },
                         "\(language) says what every fair thing does")
        }
        // The shop and the wardrobe read them in the app's language.
        let language = L10n.shared.language
        let fair = FeatureStrings.notchMascotFair(language)
        let life = FeatureStrings.notchMascotLife(language)
        let shop = FeatureStrings.notchMascotShop(language)
        suite.expect(items.allSatisfy { life.name(of: $0) == fair.name(of: $0) && shop.gag(of: $0) == fair.gag(of: $0) },
                     "the wardrobe and the shop word the fair as its own strings do")
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
                     "every fair thing costs what its rarity costs")
        suite.expect(Set(items.map(\.rarity)) == Set(NotchMascotRarity.allCases),
                     "the fair has something of every rarity")
        suite.expect(items.allSatisfy { NotchMascotShop.forSale.contains($0) },
                     "the shop can sell every fair thing")
        suite.expect(NotchMascotStyle.allCases.allSatisfy { style in
            NotchMascotShop.startingKit(for: style).allSatisfy { !$0.isFairItem }
        }, "the fair adds nothing to what a figure brings from home, so no kit changes")
    }

    private static func uses(_ suite: TestSuite) {
        for item in items {
            suite.expect(!NotchMascotItemTrait.of(item).isPlain, "\(item.rawValue) shows while it is worn")
            for roll in [0.0, 0.5, 0.99] {
                guard let use = NotchMascotItemUse.of(item, random: { roll }) else {
                    suite.expect(false, "\(item.rawValue) is used on its own")
                    continue
                }
                suite.expect(use.length > 0.5 && use.length < 15 && !use.islandBeats(byLeader: true).isEmpty,
                             "\(item.rawValue) plays out in a few seconds, in the island too")
                for step in use.steps {
                    if case .marker(let text) = step.action {
                        suite.expect(NotchMascotRPGShapes.cells(of: text) == text.count * 4 - 1,
                                     "\(item.rawValue) marker \(text) can be drawn in pixels")
                    }
                }
            }
        }
        suite.expect(NotchMascotItemTrait.of(.stilts).scale > 1 && NotchMascotItemTrait.of(.lollipop).gait > 1
                     && NotchMascotItemTrait.of(.astronautHelmet).hop > 1 && NotchMascotItemTrait.of(.astronautHelmet).gait < 1,
                     "stilts make it taller, sugar quicker, the helmet floaty")
        // Luck decides: a fish or a boot, a dunk or a miss, the ball's answer.
        suite.expect(NotchMascotItemUse.of(.fishingRod, random: { 0.1 }) != NotchMascotItemUse.of(.fishingRod, random: { 0.9 })
                     && NotchMascotItemUse.of(.basketball, random: { 0.1 }) != NotchMascotItemUse.of(.basketball, random: { 0.9 }),
                     "the rod and the ball can go either way")
        let answers = Set((0..<12).compactMap { index -> String? in
            NotchMascotItemUse.of(.answerBall, random: { Double(index) / 12 })?.steps.compactMap { step -> String? in
                if case .marker(let text) = step.action { return text } else { return nil }
            }.first
        })
        suite.expect(answers.count == NotchMascotItemUse.answers.count, "the answer ball gives every answer")
        let twists = NotchMascotItemTwists.pairs.filter { $0.item.isFairItem }
        suite.expect(twists.count >= 16 && Set(twists).count == twists.count,
                     "at least sixteen figures take a fair thing their own way")
        for pair in twists {
            suite.expect(NotchMascotItemUse.of(pair.item, style: pair.style) != NotchMascotItemUse.of(pair.item, random: { 0.1 }),
                         "the \(pair.style.rawValue) has its own take on the \(pair.item.rawValue)")
        }
        suite.expect(items.allSatisfy { NotchMascotItemSignature.of($0) != nil }, "every fair thing brings a move to a combo")
    }

    private static func combos(_ suite: TestSuite) {
        let fair = NotchMascotSynergyCatalog.synergies(in: .fair)
        suite.expect(fair.count >= 30, "the fair has a family of combos of its own")
        suite.expect(items.allSatisfy { item in
                         !NotchMascotSynergyCatalog.partners(of: item).isEmpty
                             || NotchMascotSynergyCatalog.all.contains { synergy in
                                 switch synergy.match {
                                 case .formWears(let a), .styleWears(_, let a), .twin(let a): return a == item
                                 default: return false
                                 }
                             }
                     },
                     "every fair thing makes a combo of some kind")
        let kinds = fair.map(\.match)
        suite.expect(kinds.contains { if case .styleWears = $0 { return true } else { return false } }
                     && kinds.contains { if case .twin = $0 { return true } else { return false } }
                     && kinds.contains { if case .pair(let a, let b) = $0 { return a.isFairItem != b.isFairItem } else { return false } },
                     "fair combos pair with old things, with twins and with the right figure")
        let forms = NotchMascotSynergyCatalog.synergies(in: .forms).filter {
            if case .formWears(let a) = $0.match { return a.isFairItem } else { return false }
        }
        suite.expect(forms.count >= 4, "a transformed one makes combos with fair things")
        let owed = ["sugarPlumGlissade", "theNutcrackerMarch", "blackSwanSeduction", "giselleWilis", "strictMaestro",
                    "theBarreFight", "mirrorExercise", "trustFallSuspension"]
        suite.expect(owed.allSatisfy { NotchMascotSynergyCatalog.synergy(id: $0)?.category == .dance },
                     "the stage scenes the company owed are on the bill")
        let context = NotchMascotIslandPlay.Context(since: .infinity, music: false, hour: 12, leaderWears: .trumpet,
                                                    friendWears: .drum, leaderStyle: .cat, friendStyle: .dog,
                                                    leaderForm: nil, friendForm: nil)
        suite.expect(NotchMascotIslandPlay.synergyKinds(in: context).contains(.synergy("brassBand")),
                     "the island offers the brass band to a trumpet and a drum")
    }

    private static func lures(_ suite: TestSuite) {
        for encounter in [NotchMascotEncounter.butterflies, .fishJump] {
            suite.expect(!encounter.grounded && encounter.weight > 0 && encounter.length > 5 && encounter.gathers == nil,
                         "\(encounter.rawValue) can come by and each just watches it")
        }
        suite.expect(!NotchMascotEncounter.butterflies.allowed(hour: 2, wearsItem: true)
                     && NotchMascotEncounter.butterflies.allowed(hour: 12, wearsItem: true),
                     "butterflies keep to the day")
        func picks(_ hour: Int, lure: NotchMascotAccessory) -> [NotchMascotEncounter] {
            stride(from: 0.0, to: 1.0, by: 0.002).compactMap {
                NotchMascotEncounters.pick(hour: hour, wearsItem: true, recent: [], random: $0, lure: lure)
            }
        }
        suite.expect(picks(2, lure: .butterflyNet).contains(.butterflies) && !picks(2, lure: .none).contains(.butterflies),
                     "a net brings the butterflies even at night")
        let rod = picks(12, lure: .fishingRod).filter { $0 == .fishJump }.count
        let bare = picks(12, lure: .none).filter { $0 == .fishJump }.count
        suite.expect(rod > bare * 2, "a rod brings the fish round more often")
        suite.expect(picks(12, lure: .astronautHelmet).contains(.meteorShower), "the helmet brings the sky's visitors by day")
        suite.expect(NotchMascotEncounters.lured(by: .telescope) == [.shootingStar, .meteorShower]
                     && NotchMascotEncounters.lured(by: .none).isEmpty,
                     "the telescope still brings the stars, and nothing worn lures nothing")
    }
}
