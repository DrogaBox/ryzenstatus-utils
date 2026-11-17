// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The wardrobe browser: every thing worn sits in exactly one family and one
/// spot, the families follow the wardrobe, its words are there in every
/// language, and what it says a thing does in a chain is what the chain does.
enum NotchMascotWardrobeTests {
    static func run(_ suite: TestSuite) {
        families(suite)
        words(suite)
        chainFacts(suite)
    }

    private typealias Family = NotchMascotWardrobeFamily

    private static func families(_ suite: TestSuite) {
        let catalog = NotchMascotWardrobeBrowser.catalog
        suite.expect(catalog.count == NotchMascotAccessory.wardrobe.count - 1 && !catalog.contains(.none),
                     "the browser shows every thing worn, and nothing is not one")
        let grouped = Family.allCases.flatMap(\.items)
        suite.expect(grouped.count == catalog.count && Set(grouped) == Set(catalog),
                     "every thing worn sits in exactly one family: \(grouped.count) of \(catalog.count)")
        for item in catalog {
            suite.expect(Family.of(item).map { $0.items.contains(item) } == true, "\(item.rawValue) knows its family")
        }
        suite.expect(Family.of(.torch) == .lab && Family.of(.voodooDoll) == .mayhem && Family.of(.crown) == .levels,
                     "the torch is in the lab, the doll in the mayhem, the crown a level reward")
        suite.expect(Family.levels.items.allSatisfy { !$0.isPurchasable }
                     && Family.allCases.filter { $0 != .levels }.allSatisfy { $0.items.allSatisfy(\.isPurchasable) },
                     "level rewards are earned, every other family is bought")
        suite.expect(NotchMascotWardrobeSpot.of(.headphones) == .head && NotchMascotWardrobeSpot.of(.gasMask) == .eyes
                     && NotchMascotWardrobeSpot.of(.garlicNecklace) == .neck && NotchMascotWardrobeSpot.of(.trampoline) == .feet
                     && NotchMascotWardrobeSpot.of(.batteryPack) == .back && NotchMascotWardrobeSpot.of(.torch) == .hand,
                     "each thing is found where it is worn")
    }

    private static func words(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let words = FeatureStrings.notchMascotWardrobe(language)
            suite.expect(words.families.count == Family.allCases.count && words.families.allSatisfy { !$0.isEmpty },
                         "\(language.rawValue) names every family")
            suite.expect(words.spots.count == NotchMascotWardrobeSpot.allCases.count
                         && words.sorts.count == NotchMascotWardrobeSort.allCases.count,
                         "\(language.rawValue) names every spot and every sort")
            suite.expect(words.stimuli.count == NotchMascotStimulus.allCases.count && words.stimuli.allSatisfy { !$0.isEmpty },
                         "\(language.rawValue) names every stimulus")
            let shown = words.shown(12, of: 204)
            suite.expect(shown.contains("12") && shown.contains("204"), "\(language.rawValue) says how many are shown: \(shown)")
            suite.expect(!words.search.isEmpty && !words.chainTitle.isEmpty && !words.unknownRare.isEmpty,
                         "\(language.rawValue) has the search, the chains and the unknown rare")
        }
    }

    private static func chainFacts(_ suite: TestSuite) {
        suite.expect(NotchMascotChainFacts(.none).isEmpty, "nothing worn does nothing in a chain")
        let torch = NotchMascotChainFacts(.torch)
        suite.expect(torch.emits == .fire, "the card says the torch throws fire")
        let boots = NotchMascotChainFacts(.rubberBoots)
        suite.expect(boots.reactions.contains { $0.stimulus == .shock && $0.thrown == nil },
                     "the card says the boots take a spark and stop it")
        let rod = NotchMascotChainFacts(.lightningRod)
        suite.expect(rod.reactions.contains { $0.stimulus == .shock && $0.thrown == .shock },
                     "the card says the rod passes the spark on")
        let told = NotchMascotWardrobeBrowser.catalog.filter { !NotchMascotChainFacts($0).isEmpty }.count
        suite.expect(told >= 85, "most things worn have something to say about chains: \(told)")
    }
}
