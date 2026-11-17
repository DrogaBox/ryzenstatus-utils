// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The fusion of two companions: when it comes, which pairs make a fusion
/// of their own and which follow the rule, what a fusion gone wrong looks
/// like, the fused one's look and moves, and how two names run into one.
enum NotchMascotFusionTests {
    typealias Fusion = NotchMascotFusion

    static func run(_ suite: TestSuite) {
        pacing(suite)
        catalog(suite)
        specials(suite)
        generic(suite)
        flops(suite)
        looks(suite)
        moves(suite)
        names(suite)
    }

    private static func look(_ style: NotchMascotStyle, _ item: NotchMascotAccessory = .none,
                             _ palette: NotchMascotPalette = .sky) -> NotchMascotLook {
        NotchMascotLook(style: style, shape: .ball, palette: palette, accessory: item)
    }

    /// Never a flop: the first number drawn decides it.
    private static let sure: () -> Double = { 0.99 }

    private static func fuse(_ a: NotchMascotLook, _ b: NotchMascotLook, hour: Int = 12) -> Fusion.Fused {
        Fusion.fuse(a, b, names: (a.style.rawValue.capitalized, b.style.rawValue.capitalized), hour: hour, random: sure)
    }

    private static func pacing(_ suite: TestSuite) {
        let due = Fusion.interval + 1, played = NotchMascotPlay.interval + 1
        suite.expect(Fusion.due(since: due, sincePlay: played, relation: nil, random: 0),
                     "the island's own two fuse once one is due")
        suite.expect(Fusion.due(since: due, sincePlay: played, relation: .friends, random: 0)
                     && Fusion.due(since: due, sincePlay: played, relation: .crush, random: 0),
                     "friends and a crush fuse")
        suite.expect(!Fusion.due(since: due, sincePlay: played, relation: .rivals, random: 0)
                     && !Fusion.due(since: due, sincePlay: played, relation: .strangers, random: 0),
                     "rivals and strangers never fuse of their own accord")
        suite.expect(!Fusion.due(since: Fusion.interval - 1, sincePlay: played, relation: nil, random: 0),
                     "not before the last one is long enough ago")
        suite.expect(!Fusion.due(since: due, sincePlay: NotchMascotPlay.interval - 1, relation: nil, random: 0),
                     "not before a play would be due either")
        suite.expect(!Fusion.due(since: due, sincePlay: played, relation: nil, random: Fusion.chance),
                     "only now and then, when due")
        suite.expect(!Fusion.allowed(reduceMotion: true, lowPower: false) && !Fusion.allowed(reduceMotion: false, lowPower: true)
                     && Fusion.allowed(reduceMotion: false, lowPower: false),
                     "never with Reduce Motion or Low Power Mode")
        let fused = fuse(look(.cat), look(.ghost))
        suite.expect(Fusion.length.contains(Fusion.duration(of: fused, random: 0))
                     && Fusion.length.contains(Fusion.duration(of: fused, random: 0.999))
                     && Fusion.length.lowerBound >= 45 && Fusion.length.upperBound <= 90,
                     "a fusion lasts between 45 and 90 seconds")
        let flop = Fusion.flopped(look(.cat), look(.dog), names: ("Cat", "Dog"), flop: .chubby, bodyIsFirst: true)
        suite.expect(Fusion.duration(of: flop, random: 0.999) < Fusion.length.lowerBound,
                     "a fusion gone wrong is over sooner")
    }

    private static func catalog(_ suite: TestSuite) {
        let pairs = Fusion.catalog.filter { $0.styles.count == 2 }
        suite.expect(Set(pairs.map { Set($0.styles) }).count >= 20, "at least twenty pairs have a fusion of their own")
        suite.expect(Fusion.catalog.allSatisfy { $0.styles.contains($0.body) }, "the body is always one of the pair")
        suite.expect(Set(Fusion.catalog.map(\.name)).count == Fusion.catalog.count, "every special one has its own name")
        let keys = Fusion.catalog.map {
            "\($0.styles.map(\.rawValue).sorted())|\(String(describing: $0.item))|\($0.night)"
        }
        suite.expect(Set(keys).count == keys.count, "no two specials ask for the same thing")
        suite.expect(Fusion.catalog.contains { $0.night } && Fusion.catalog.contains { $0.item != nil },
                     "some only come at night, some only with a thing on")
        suite.expect(Fusion.catalog.allSatisfy { $0.scale > 1 && $0.aura != .fizzle && !Fusion.flopMoves.contains($0.signature) },
                     "a special one is bigger, blazes, and has a real signature")
    }

    private static func specials(_ suite: TestSuite) {
        suite.expect(fuse(look(.dragon), look(.phoenix)).name == "Infernix" && fuse(look(.phoenix), look(.dragon)).name == "Infernix",
                     "a pair makes the same whichever comes first")
        let infernix = fuse(look(.phoenix), look(.dragon))
        suite.expect(!infernix.bodyIsFirst && fuse(look(.dragon), look(.phoenix)).bodyIsFirst,
                     "the catalog says whose body it is, whoever asked")
        suite.expect(fuse(look(.dragon), look(.phoenix), hour: 23).name == "Eclipse Wyrm"
                     && fuse(look(.dragon), look(.phoenix), hour: 3).name == "Eclipse Wyrm"
                     && fuse(look(.dragon), look(.phoenix), hour: 15).name == "Infernix",
                     "the night form only comes in the small hours")
        suite.expect(fuse(look(.swan), look(.ballerina)).name == "Odette" && fuse(look(.swan), look(.ballerina), hour: 22).name == "Odile",
                     "the white swan by day, the black one by night")
        suite.expect(fuse(look(.frog), look(.cat, .crown)).name == "Frog Prince" && fuse(look(.frog, .crown), look(.dog)).name == "Frog Prince"
                     && fuse(look(.frog), look(.cat)).special == false,
                     "a crown on either makes the frog a prince, and without it there is none")
        suite.expect(fuse(look(.axolotl, .crown), look(.frog)).name == "Frog Prince",
                     "a thing asked for wins over the plain pair")
        suite.expect(fuse(look(.ghost), look(.cat, .cursedMask), hour: 12).name != "Poltergeist"
                     && fuse(look(.ghost), look(.cat, .cursedMask), hour: 0).name == "Poltergeist",
                     "the cursed mask only works at night")
        suite.expect(fuse(look(.mouse), look(.cat)).signature == .scurry, "a cat and a mouse in one body make chaos")
        suite.expect(fuse(look(.hologram), look(.android)).look.aura == .glitch, "the hologram and the android glitch")
        suite.expect(fuse(look(.cat), look(.dog)).look.mark == .earrings && fuse(look(.kitsune), look(.ghost)).look.mark == .gem,
                     "earrings for some, a gem on the brow for others")
    }

    private static func generic(_ suite: TestSuite) {
        let fused = fuse(look(.cat), look(.chip))
        suite.expect(!fused.special && fused.bodyIsFirst && fused.look.mark == .earrings && fused.flop == nil,
                     "any other pair: the first one's body and a pair of earrings")
        suite.expect(fused.look.scale > 1, "the fused one stands bigger")
        suite.expect(fused.signature == Fusion.element(of: .chip).move, "it brings the move of the one that went in")
        suite.expect(fused.look.aura == .storm, "the stronger aura of the two")
        suite.expect(!fuse(look(.minimal), look(.ghost)).bodyIsFirst && fuse(look(.minimal), look(.minimal)).bodyIsFirst,
                     "the plain shape gives up its body to a figure")
        let close = Fusion.generic(look(.minimal, .none, .sky), look(.minimal, .none, .lilac), names: ("A", "B"))
        suite.expect(!close.look.split, "close colours blend")
        var red = look(.robot)
        red.customColor = NotchMascotColor(red: 1, green: 0, blue: 0)
        var blue = look(.robot)
        blue.customColor = NotchMascotColor(red: 0, green: 0.2, blue: 1)
        let apart = Fusion.generic(red, blue, names: ("A", "B"))
        suite.expect(apart.look.split && apart.look.primary == red.customColor && apart.look.secondary == blue.customColor,
                     "far colours split, half each")
        suite.expect(fuse(look(.cat), look(.ghost)).name == Fusion.portmanteau("Cat", "Ghost"), "its name runs theirs together")
        suite.expect(NotchMascotStyle.allCases.allSatisfy { a in
            NotchMascotStyle.allCases.allSatisfy { b in fuse(look(a), look(b)).look.aura != .fizzle }
        }, "every pair fuses into something")
    }

    private static func flops(_ suite: TestSuite) {
        var draws = [0.05, 0.4, 0.9]
        let flopped = Fusion.fuse(look(.dragon), look(.phoenix), names: ("Dragon", "Phoenix"), hour: 12) {
            draws.isEmpty ? 0.5 : draws.removeFirst()
        }
        suite.expect(flopped.flop == .scrawny && !flopped.bodyIsFirst, "now and then the poses do not match, even for a special pair")
        suite.expect(flopped.look.aura == .fizzle && flopped.look.mark == .none && flopped.signature == .fizzle,
                     "a flop fizzles, without earrings")
        suite.expect(flopped.name == Fusion.portmanteau("Phoenix", "Dragon"), "and its name comes out the wrong way round")
        suite.expect(Fusion.Flop.allCases.allSatisfy { $0.stretch != CGSize(width: 1, height: 1) },
                     "every flop is out of shape")
        suite.expect(Fusion.Flop.chubby.stretch.width > 1 && Fusion.Flop.scrawny.stretch.height > 1 && Fusion.Flop.wonky.shear != 0,
                     "chubby is wide, scrawny is tall, wonky leans")
    }

    private static func looks(_ suite: TestSuite) {
        let first = look(.cat, .crown), second = look(.dog, .bowTie)
        let fused = fuse(first, second)
        let worn = Fusion.look(of: fused, first: first, second: second)
        suite.expect(worn.style == .dog && worn.accessory == .crown, "the body of one, the thing of the other")
        suite.expect(worn.fusion == fused.look && worn.form == nil && worn.customColor == fused.look.primary,
                     "painted in the fusion's colours, whatever form it had")
        let bare = Fusion.look(of: fuse(look(.cat, .crown), look(.ghost)), first: look(.cat, .crown), second: look(.ghost))
        suite.expect(bare.accessory == .crown, "with nothing on the other, it keeps its own")
        suite.expect(NotchMascotRoam.size(for: worn) > NotchMascotRoam.size(for: second), "it stands bigger on the desktop")
        suite.expect(fused.look.bodyColors.count == (fused.look.split ? 4 : 2)
                     && (fused.look.bodyLocations?.count ?? 2) == fused.look.bodyColors.count,
                     "its body colours and where they change agree")
    }

    private static func moves(_ suite: TestSuite) {
        let fused = fuse(look(.dragon), look(.phoenix))
        var recent: [Fusion.Move] = []
        var seen = Set<Fusion.Move>()
        var repeated = false
        for step in 0..<60 {
            let move = Fusion.nextMove(for: fused, recent: recent, random: { Double((step * 37) % 100) / 100 })
            if recent.last == move { repeated = true }
            recent.append(move)
            seen.insert(move)
        }
        suite.expect(!repeated, "never the same move twice in a row")
        suite.expect(seen.contains(.inferno) && seen.isSubset(of: Set(Fusion.common + [.inferno])),
                     "its signature and the common moves, nothing else")
        let flop = Fusion.flopped(look(.cat), look(.dog), names: ("Cat", "Dog"), flop: .wonky, bodyIsFirst: true)
        suite.expect(Set((0..<10).map { step in Fusion.nextMove(for: flop, recent: [], random: { Double(step) / 10 }) })
                         .isSubset(of: Set(Fusion.flopMoves)),
                     "a flop only manages its sad moves")
    }

    private static func names(_ suite: TestSuite) {
        suite.expect(Fusion.portmanteau("Cat", "Dog") == "Catdog", "short names join whole")
        suite.expect(Fusion.portmanteau("Frog", "Axolotl") == "Froglotl", "the second from a syllable near its middle")
        suite.expect(Fusion.portmanteau("Dragon", "Phoenix") == "Dragnix", "the first cut after a closed syllable")
        suite.expect(Fusion.portmanteau("Swan", "Penguin") == "Swanguin", "penguins too")
        let rabbit = Fusion.portmanteau("Conejo Blanco", "Gato")
        suite.expect(rabbit.hasPrefix("Con") && !rabbit.contains("lanc") && rabbit.hasSuffix("to"),
                     "only the first word of the first name")
        let kana = Fusion.portmanteau("ドラゴン", "フェニックス")
        suite.expect(kana == "ドラックス", "a script without vowels takes half of each")
        suite.expect(Fusion.portmanteau("", "Cat") == "Cat" && Fusion.portmanteau("Cat", "") == "Cat", "an empty name leaves the other")
        suite.expect(Fusion.portmanteau("fénix", "dragón").first?.isUppercase == true, "it starts with a capital")
    }
}
