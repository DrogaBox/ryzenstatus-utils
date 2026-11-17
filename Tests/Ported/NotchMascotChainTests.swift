// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation
import QuartzCore

/// Chain reactions: what flies for each stimulus, how anyone takes each
/// one and with what odds it is passed on, how some figures take them their
/// own way, which goes first, how a chain runs down the line, where it
/// stops, what rare things it sets off, how it plays in the island and what
/// is kept of it.
enum NotchMascotChainTests {
    static func run(_ suite: TestSuite) {
        stimuli(suite)
        plain(suite)
        figures(suite)
        everyReaction(suite)
        planning(suite)
        rares(suite)
        island(suite)
        luckAndLog(suite)
        idleStage(suite)
    }
    /// A stage the chains, combos and items draw on puts itself away once
    /// nothing shows on it, so no empty window lies over the whole screen.
    private static func idleStage(_ suite: TestSuite) {
        typealias Stage = NotchMascotPlayStage
        suite.expect(Stage.idleClose <= 10 && Stage.idleCheck <= Stage.idleClose, "an idle stage goes within seconds")
        suite.expect(Stage.shouldClose(idleFor: Stage.idleClose, showing: false), "idle and empty: put away")
        suite.expect(!Stage.shouldClose(idleFor: Stage.idleClose - 1, showing: false), "just drawn on: kept a moment")
        suite.expect(!Stage.shouldClose(idleFor: 60, showing: true), "still showing something: kept however long")
        let canvas = CALayer()
        suite.expect(!Stage.shows(canvas), "an empty canvas shows nothing")
        let group = CALayer()
        canvas.addSublayer(group)
        suite.expect(!Stage.shows(canvas), "a bare group shows nothing")
        let mark = CAShapeLayer()
        group.addSublayer(mark)
        suite.expect(Stage.shows(canvas), "a shape inside a group shows")
        mark.opacity = 0
        suite.expect(!Stage.shows(canvas), "a faded-out shape does not")
        let glow = CALayer()
        glow.backgroundColor = CGColor(gray: 1, alpha: 1)
        glow.isHidden = true
        canvas.addSublayer(glow)
        suite.expect(!Stage.shows(canvas), "a hidden glow does not")
        glow.isHidden = false
        suite.expect(Stage.shows(canvas), "a glow in sight does")
    }

    private typealias Chain = NotchMascotChain
    private typealias Member = NotchMascotChainMember
    private typealias Reactions = NotchMascotChainReactions

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

    private static func emitted(_ stimulus: NotchMascotStimulus, roll: Double) -> NotchMascotStimulus? {
        Reactions.plainReaction(to: stimulus, random: { roll }).emits
    }

    private static func stimuli(_ suite: TestSuite) {
        suite.expect(NotchMascotStimulus.allCases.count == 14, "fourteen stimuli")
        let things = NotchMascotStimulus.allCases.map(\.thing)
        suite.expect(things.indices.allSatisfy { index in !things[(index + 1)...].contains(things[index]) },
                     "each stimulus flies as a thing of its own")
        suite.expect(NotchMascotStimulus.allCases.allSatisfy {
            !NotchMascotPlayEffects.thingParts($0.thing, side: 20, energy: NotchMascotPlay.Energy(red: 1, green: 1, blue: 1)).isEmpty
                || NotchMascotRPGShapes.prop($0.thing, at: CGPoint(x: 10, y: 10), side: 20) != nil
        }, "everything a chain throws is drawn in flight")
        suite.expect(NotchMascotStimulus.allCases.allSatisfy { drawable($0.marker) }, "every stimulus marker is drawn in pixels")
        suite.expect(NotchMascotChainRare.allCases.allSatisfy { drawable($0.marker) && !$0.name.isEmpty && !$0.nameES.isEmpty },
                     "every rare thing has a marker that can be drawn and a name in both languages")
        suite.expect(Set(NotchMascotChainRare.allCases.map(\.marker)).count == NotchMascotChainRare.allCases.count,
                     "no two rare things share a marker")
        suite.expect(Chain.interval == 75 && Chain.chance == 0.35 && Chain.islandChance == 0.4 && Chain.maxLinks == 8,
                     "a chain is due every 75 s, taken a third of the time, 40 % in the island, at most 8 throws")
        suite.expect(Chain.shouldStart(since: 75, random: 0.34) && !Chain.shouldStart(since: 75, random: 0.35)
                     && !Chain.shouldStart(since: 74.9, random: 0), "a chain starts only when due and lucky")
    }

    /// The plain way passes on water, a shock, a dance, a sneeze, a laugh
    /// and a trance at their own odds, exactly at the threshold; the rest never.
    private static func plain(_ suite: TestSuite) {
        let odds: [(NotchMascotStimulus, Double)] = [(.water, 0.3), (.shock, 0.4), (.sound, 0.25), (.pepper, 0.7),
                                                    (.tickle, 0.6), (.hypno, 0.5)]
        suite.expect(Reactions.splashChance == 0.3 && Reactions.shockChance == 0.4 && Reactions.danceChance == 0.25
                     && Reactions.sneezeChance == 0.7 && Reactions.laughChance == 0.6 && Reactions.hypnoChance == 0.5,
                     "the plain odds are pinned")
        for (stimulus, chance) in odds {
            suite.expect(emitted(stimulus, roll: chance - 0.001) == stimulus && emitted(stimulus, roll: chance) == nil,
                         "\(stimulus) is passed on below \(chance) and held from it")
        }
        for stimulus in NotchMascotStimulus.allCases where !odds.contains(where: { $0.0 == stimulus }) {
            suite.expect(emitted(stimulus, roll: 0) == nil, "the plain way never passes \(stimulus) on")
        }
        for stimulus in NotchMascotStimulus.allCases {
            let reaction = Reactions.plainReaction(to: stimulus, random: { 0 })
            suite.expect(reaction.id == "plain.\(stimulus.rawValue)" && reaction.source == .plain && reaction.target == .next,
                         "the plain \(stimulus) is named and goes to the next")
        }
    }

    private static func figures(_ suite: TestSuite) {
        func figure(_ style: NotchMascotStyle, _ stimulus: NotchMascotStimulus) -> NotchMascotChainReaction? {
            Reactions.styleReaction(style, to: stimulus, random: { 0.5 })
        }
        suite.expect(figure(.dragon, .fire)?.emits == .fire && figure(.phoenix, .fire)?.emits == .fire
                     && figure(.kitsune, .fire)?.emits == .fire, "fire feeds the dragon, the phoenix and the kitsune, and goes on")
        suite.expect(figure(.penguin, .frost)?.stops == true && figure(.penguin, .fire) != nil,
                     "the penguin loves frost and melts at fire")
        suite.expect(figure(.cat, .light) != nil && figure(.dog, .light) != nil, "the cat and the dog chase the light")
        suite.expect(Reactions.machines.allSatisfy { figure($0, .shock)?.emits == .shock },
                     "a spark overcharges a machine, which passes it on")
        suite.expect(figure(.robot, .water)?.emits == .shock, "water shorts a robot out into a spark")
        suite.expect(figure(.ghost, .impact)?.stops == true && figure(.slime, .impact)?.stops == true,
                     "a bonk goes through a ghost and into a slime")
        suite.expect(figure(.fan, .shock)?.emits == .wind && figure(.fan, .wind)?.emits == .wind, "the fan blows a spark on as a gust")
        suite.expect([NotchMascotStimulus.pepper, .tickle, .hypno].allSatisfy { figure(.capybara, $0)?.stops == true },
                     "nothing catching moves a capybara")
        suite.expect(figure(.minimal, .fire) == nil && figure(.cat, .fire) == nil, "most figures take fire the plain way")
        suite.expect(Reactions.styleEmission(.dragon)?.stimulus == .fire && Reactions.styleEmission(.fan)?.stimulus == .wind
                     && Reactions.styleEmission(.penguin)?.stimulus == .frost && Reactions.styleEmission(.robot)?.stimulus == .shock
                     && Reactions.styleEmission(.cat) == nil, "some figures throw with nothing in hand")
        // What it wears is asked first; a figure that takes nothing worn goes by its figure.
        let bare = Member(.none, .dragon, x: 0)
        suite.expect(Chain.reaction(of: bare, to: .fire, random: { 0 }).source == .style(.dragon),
                     "with nothing worn, the figure decides")
        suite.expect(Chain.reaction(of: Member(.none, .minimal, x: 0), to: .fire, random: { 0 }).source == .plain,
                     "with nothing worn and nothing of its own, the plain way")
    }

    /// Every reaction any thing, figure or the plain way makes, at every
    /// roll, plays out in a few seconds, says only what can be drawn, and
    /// is named after what decided it.
    private static func everyReaction(_ suite: TestSuite) {
        var ids = Set<String>()
        var bad: [String] = []
        for item in NotchMascotAccessory.allCases where item != .none {
            for stimulus in NotchMascotStimulus.allCases {
                for roll in [0.0, 0.02, 0.07, 0.12, 0.5, 0.9, 0.999] {
                    guard let reaction = Reactions.itemReaction(item, to: stimulus, random: { roll }) else { continue }
                    ids.insert(reaction.id)
                    if !(reaction.length > 0.3 && reaction.length < 8) { bad.append("\(reaction.id) length \(reaction.length)") }
                    if reaction.source != .item(item) { bad.append("\(reaction.id) source") }
                    if !reaction.id.hasPrefix("\(item.rawValue).\(stimulus.rawValue)") { bad.append("\(reaction.id) id") }
                    for text in markers(reaction.steps) where !drawable(text) { bad.append("\(reaction.id) marker \(text)") }
                }
            }
            if let thrown = Reactions.itemEmission(item) {
                if !(thrown.release > 0 && thrown.release < 3) { bad.append("\(item.rawValue) windup") }
                for text in markers(thrown.windup) where !drawable(text) { bad.append("\(item.rawValue) windup marker \(text)") }
            }
        }
        for style in NotchMascotStyle.allCases {
            for stimulus in NotchMascotStimulus.allCases {
                guard let reaction = Reactions.styleReaction(style, to: stimulus, random: { 0.5 }) else { continue }
                if !(reaction.length > 0.3 && reaction.length < 8) { bad.append("\(reaction.id) length") }
                for text in markers(reaction.steps) where !drawable(text) { bad.append("\(reaction.id) marker \(text)") }
            }
        }
        for stimulus in NotchMascotStimulus.allCases {
            let reaction = Reactions.plainReaction(to: stimulus, random: { 0 })
            for text in markers(reaction.steps) where !drawable(text) { bad.append("\(reaction.id) marker \(text)") }
        }
        suite.expect(bad.isEmpty, "every reaction plays well: \(bad.prefix(8))")
        suite.expect(ids.count >= 120, "well over a hundred reactions of things worn: \(ids.count)")
        let emitters = NotchMascotAccessory.allCases.filter { Reactions.itemEmission($0) != nil }
        suite.expect(emitters.count >= 25, "a couple of dozen things throw something: \(emitters.count)")
        let thrown = Set(emitters.compactMap { Reactions.itemEmission($0)?.stimulus })
        suite.expect(thrown == Set(NotchMascotStimulus.allCases), "every stimulus has something that throws it")
    }

    private static func planning(_ suite: TestSuite) {
        // A sneeze goes to the nearest not reached yet, each once.
        let line = [Member(.none, .cat, x: 0), Member(.none, .dog, x: 100), Member(.none, .mouse, x: 50),
                    Member(.none, .frog, x: 300)]
        var sneezers = line
        sneezers[0] = Member(.pepperShaker, .cat, x: 0)
        if let plan = Chain.plan(sneezers, starter: 0, random: { 0 }) {
            suite.expect(plan.emission.stimulus == .pepper, "the pepper shaker throws pepper")
            suite.expect(plan.links.map(\.to) == [2, 1, 3] && plan.links.map(\.from) == [0, 2, 1],
                         "the sneeze goes nearest first, down the line: \(plan.links.map(\.to))")
            suite.expect(plan.reached == [0, 1, 2, 3] && plan.rares.contains(.perfectChain),
                         "reaching all four is a perfect chain")
        } else {
            suite.expect(false, "a pepper shaker sets off a chain")
        }
        // Held at once: one link, no rare.
        if let plan = Chain.plan(sneezers, starter: 0, random: { 0.99 }) {
            suite.expect(plan.links.count == 1 && plan.rares.isEmpty, "a sneeze not caught stops there")
        }
        suite.expect(Chain.plan(line, starter: 0) == nil, "nothing to throw, no chain")
        suite.expect(Chain.plan([sneezers[0]], starter: 0) == nil, "alone, no chain")
        suite.expect(Chain.plan(sneezers, starter: 7) == nil, "no such starter, no chain")
        // Never longer than the cap, even when it could go round for ever.
        let crowd = (0..<12).map { Member(.pepperShaker, .minimal, x: CGFloat($0) * 40) }
        if let plan = Chain.plan(crowd, starter: 0, random: { 0 }) {
            suite.expect(plan.links.count <= Chain.maxLinks, "at most \(Chain.maxLinks) throws")
            suite.expect(Set(plan.links.map(\.to)).count == plan.links.count, "nobody is reached twice down the line")
        }
        // A dragon takes fire and breathes it on; a minimal one takes it the plain way and it ends.
        let fire = [Member(.torch, .minimal, x: 0), Member(.none, .dragon, x: 60), Member(.none, .minimal, x: 120)]
        if let plan = Chain.plan(fire, starter: 0, random: { 0.5 }) {
            suite.expect(plan.emission.stimulus == .fire && plan.links.map(\.to) == [1, 2]
                         && plan.links[1].stimulus == .fire && plan.links.last?.reaction.stops == true,
                         "the torch lights the dragon, who breathes it on to the last, who hops about")
        } else {
            suite.expect(false, "a torch sets off a chain")
        }
        // The nearest helper.
        suite.expect(Chain.nearest(to: 0, among: line, excluding: [0]) == 2 && Chain.nearest(to: 0, among: line, excluding: [0, 1, 2, 3]) == nil,
                     "the nearest not reached")
    }

    private static func rares(_ suite: TestSuite) {
        let five = (0..<5).map { Member(.none, .minimal, x: CGFloat($0) * 80) }
        var sneeze = five
        sneeze[0] = Member(.pepperShaker, .minimal, x: 0)
        let storm = Chain.plan(sneeze, starter: 0, random: { 0 })
        suite.expect(storm?.rares.contains(.sneezeStorm) == true && storm?.rares.contains(.perfectChain) == true,
                     "a sneeze round five is a storm and a perfect chain")
        var tickle = five
        tickle[0] = Member(.tickleFeather, .minimal, x: 0)
        suite.expect(Chain.plan(tickle, starter: 0, random: { 0 })?.rares.contains(.laughingFit) == true,
                     "a laugh round three or more is a laughing fit")
        var trance = five
        trance[0] = Member(.hypnoSpiral, .minimal, x: 0)
        suite.expect(Chain.plan(trance, starter: 0, random: { 0 })?.rares.contains(.zombieConga) == true,
                     "a trance round three or more is a zombie conga")
        let three = Array(sneeze.prefix(3))
        suite.expect(Chain.plan(three, starter: 0, random: { 0 })?.rares.contains(.perfectChain) == false,
                     "three reached is not enough for a perfect chain")
        // A spark through the plasma ball, a lightning rod and a robot.
        let grid = [Member(.plasmaBall, .minimal, x: 0), Member(.lightningRod, .minimal, x: 60), Member(.none, .robot, x: 120)]
        if let plan = Chain.plan(grid, starter: 0, random: { 0 }) {
            suite.expect(plan.rares.contains(.blackout), "the plasma ball, the rod and a robot black the screen out: \(plan.rares)")
        } else {
            suite.expect(false, "the plasma ball sets off a chain")
        }
        let noMachine = [Member(.plasmaBall, .minimal, x: 0), Member(.lightningRod, .minimal, x: 60), Member(.none, .cat, x: 120)]
        suite.expect(Chain.plan(noMachine, starter: 0, random: { 0 })?.rares.contains(.blackout) != true,
                     "no machine, no blackout")
        // Light off two mirrors.
        let mirrors = [Member(.laserPointer, .minimal, x: 0), Member(.pocketMirror, .minimal, x: 60),
                       Member(.pocketMirror, .minimal, x: 120), Member(.none, .minimal, x: 180)]
        suite.expect(Chain.plan(mirrors, starter: 0, random: { 0 })?.rares.contains(.supernova) == true,
                     "light bounced off two mirrors is a supernova")
        // Dynamite and fire.
        let boom = [Member(.torch, .minimal, x: 0), Member(.dynamiteStick, .minimal, x: 60), Member(.none, .minimal, x: 120)]
        if let plan = Chain.plan(boom, starter: 0, random: { 0.5 }) {
            suite.expect(plan.rares.contains(.kaboom) && plan.links.contains { $0.fanOut },
                         "the torch sets the dynamite off and the blast reaches everyone")
        } else {
            suite.expect(false, "a torch and dynamite make a chain")
        }
        // A torch lighting the rocket is a fireworks display.
        let show = [Member(.torch, .minimal, x: 0), Member(.fireworkRocket, .minimal, x: 60), Member(.none, .minimal, x: 120)]
        if let plan = Chain.plan(show, starter: 0, random: { 0.5 }) {
            suite.expect(plan.rares.contains(.fireworks), "the torch lights the rocket: fireworks")
        } else {
            suite.expect(false, "a torch and a rocket make a chain")
        }
        let dark = [Member(.none, .minimal, x: 0), Member(.fireworkRocket, .minimal, x: 60)]
        suite.expect(Chain.plan(dark, starter: 0, random: { 0.5 })?.rares.contains(.fireworks) != true,
                     "no fire, no fireworks")
    }

    private static func island(_ suite: TestSuite) {
        let two = [Member(.waterBalloon, .minimal, x: 0), Member(.none, .axolotl, x: 1)]
        guard let plan = Chain.plan(two, starter: 0, random: { 0.5 }) else {
            suite.expect(false, "the water balloon sets off a chain in the island")
            return
        }
        let play = Chain.islandPlay(plan, item: .waterBalloon)
        suite.expect(play.kind == .item(.waterBalloon) && play.length > 1 && play.length < 15,
                     "the island chain plays in a few seconds")
        suite.expect(play.beats.contains { $0.flight?.thing == .drop && $0.flight?.fromLeader == true },
                     "the water flies from the companion to its friend")
        suite.expect(play.beats.contains { $0.friend != nil }, "the friend takes it")
        suite.expect(zip(play.beats, play.beats.dropFirst()).allSatisfy { $0.at <= $1.at }, "beats in order")
        let back = Chain.islandPlay(Chain.plan(two.reversed().map { $0 }, starter: 1, random: { 0.5 }) ?? plan, item: .waterBalloon)
        suite.expect(back.beats.contains { $0.flight?.fromLeader == false }, "thrown by the friend, it flies the other way")
    }

    private static func luckAndLog(_ suite: TestSuite) {
        // Gold is paid within the day's share; what it cannot pay is left out.
        let treasure = NotchMascotChainReaction("test.gold", .plain, [(0, .marker("GOLD")), (0.4, .gold(30))])
        let link = NotchMascotChainLink(from: 0, to: 1, stimulus: .magnet, reaction: treasure)
        let plan = NotchMascotChainPlan(starter: 0, emission: NotchMascotChainEmission(.magnet, [(0, .react(.ready))]),
                                        links: [link], rares: [])
        var paid = 0
        let rich = plan.settled(pay: { $0 }, collect: { paid += $0 })
        suite.expect(paid == 30 && rich.links[0].reaction.steps.count == 2, "luck pays the gold out")
        let poor = plan.settled(pay: { _ in 0 }, collect: { _ in })
        suite.expect(poor.links[0].reaction.steps.count == 1, "spent luck leaves the gold out rather than showing it")

        let defaults = UserDefaults(suiteName: "NotchMascotChainTests-\(UUID().uuidString)") ?? .standard
        var found = plan
        found.rares = [.perfectChain]
        let first = NotchMascotChainLog.record(found, in: defaults)
        let again = NotchMascotChainLog.record(found, in: defaults)
        suite.expect(first.reactions == 1 && first.rares == [.perfectChain] && again.reactions == 0 && again.rares.isEmpty,
                     "the log keeps each reaction and rare thing once")
        suite.expect(NotchMascotChainLog.found(in: defaults) == ["test.gold"] && NotchMascotChainLog.rares(in: defaults) == [.perfectChain],
                     "and reads them back")
        suite.expect(NotchMascotCheat.allCases.contains(.chainreaction), "the cheat for a chain is there")
    }
}
