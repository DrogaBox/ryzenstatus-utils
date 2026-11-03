// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The companions across more than one display: which display a walk to
/// an edge leads into, the floor on the other side, the hop up onto it,
/// where a flight may go on, the way to a display some legs off, and
/// where the gang meets and guests arrive.
enum NotchMascotDisplaysTests {
    typealias Displays = NotchMascotDisplays

    static func run(_ suite: TestSuite) {
        walking(suite)
        flying(suite)
        hopping(suite)
        routes(suite)
        gang(suite)
    }

    private static func display(_ frame: CGRect, dock: CGFloat = 0, menu: CGFloat = 0) -> Displays.Display {
        Displays.Display(frame: frame, area: CGRect(x: frame.minX, y: frame.minY + dock, width: frame.width,
                                                    height: frame.height - dock - menu))
    }

    /// The main display with the Dock and the menu bar, and a taller one to
    /// its right with neither.
    private static let main = display(CGRect(x: 0, y: 0, width: 1440, height: 900), dock: 70, menu: 25)
    private static let right = display(CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    private static let height: CGFloat = 46

    private static func walking(_ suite: TestSuite) {
        let pair = [main, right]
        let off = Displays.way(from: 0, toward: 1, floor: main.area.minY, height: height, in: pair)
        suite.expect(off == Displays.Way(to: 1, rise: -70) && off?.level == true,
                     "off the Dock's floor it walks on into the display beside, a little lower")
        let up = Displays.way(from: 1, toward: -1, floor: 0, height: height, in: pair)
        suite.expect(up == Displays.Way(to: 0, rise: 70) && up?.level == false,
                     "back it hops up onto the Dock's floor")
        suite.expect(Displays.way(from: 1, toward: 1, floor: 0, height: height, in: pair) == nil
                     && Displays.way(from: 0, toward: -1, floor: 70, height: height, in: pair) == nil,
                     "where no display adjoins it turns back")
        let high = display(CGRect(x: 1440, y: 400, width: 1920, height: 1080))
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, high]) == nil,
                     "a floor beside it higher than it can hop is a wall")
        let deep = display(CGRect(x: 1440, y: -1000, width: 1920, height: 1080))
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, deep]) == nil,
                     "a floor beside it lower than it may fall is a cliff it keeps from")
        let apart = display(CGRect(x: 1500, y: 0, width: 1920, height: 1080))
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, apart]) == nil,
                     "displays with a gap between them do not adjoin")
        let level = display(CGRect(x: 1440, y: 0, width: 1280, height: 800), dock: 72)
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, level])?.level == true,
                     "a floor a stride higher it walks straight onto")
        let nearer = display(CGRect(x: 1440, y: 40, width: 1280, height: 800))
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, deep, nearer])?.to == 2,
                     "of two displays beside it, the floor nearest its own")
        let low = display(CGRect(x: 1440, y: -200, width: 1280, height: 230))
        suite.expect(Displays.way(from: 0, toward: 1, floor: 70, height: height, in: [main, low]) == nil,
                     "no room above the floor there, no way on")
    }

    private static func flying(_ suite: TestSuite) {
        let pair = [main, right]
        let open = Displays.flightArea(at: CGPoint(x: 1400, y: 500), width: 46, height: height, throughFloor: false,
                                       in: pair)
        suite.expect((open?.maxX ?? 0) >= right.area.maxX && open?.minX == main.area.minX && open?.minY == main.area.minY,
                     "flying, it goes on into the display beside at its height")
        let short = display(CGRect(x: 1440, y: 0, width: 1280, height: 600))
        let shut = Displays.flightArea(at: CGPoint(x: 1400, y: 700), width: 46, height: height, throughFloor: false,
                                       in: [main, short])
        suite.expect(shut?.maxX == main.area.maxX, "above the display beside, the side is a wall")
        let back = Displays.flightArea(at: CGPoint(x: 1500, y: 20), width: 46, height: height, throughFloor: false,
                                       in: pair)
        suite.expect(back?.minX == right.area.minX, "under the Dock's floor beside it, the side is a wall")
        let under = display(CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let stack = [main, under]
        let floor = Displays.flightArea(at: CGPoint(x: 500, y: 100), width: 46, height: height, throughFloor: false,
                                        in: stack)
        let through = Displays.flightArea(at: CGPoint(x: 500, y: 100), width: 46, height: height, throughFloor: true,
                                          in: stack)
        suite.expect(floor?.minY == main.area.minY && through?.minY == under.area.minY,
                     "the floor over a display lets it through only when thrown down")
        let top = Displays.flightArea(at: CGPoint(x: 500, y: -200), width: 46, height: height, throughFloor: false,
                                      in: stack)
        suite.expect(top?.maxY == main.area.maxY, "thrown up, it flies on into the display above")
        let edge = Displays.flightArea(at: CGPoint(x: 1700, y: -200), width: 46, height: height, throughFloor: false,
                                       in: stack)
        suite.expect(edge?.maxY == under.area.maxY, "where no display is above, the top holds")
        suite.expect(Displays.flightArea(at: .zero, width: 46, height: height, throughFloor: false, in: []) == nil,
                     "with no display, nowhere")
        suite.expect(Displays.index(for: CGPoint(x: 1500, y: 2000), in: pair) == 1
                     && Displays.index(for: CGPoint(x: 10, y: 10), in: pair) == 0,
                     "off every display, the nearest one")
    }

    /// Flies `velocity` from `start` with nothing in the way, and says how
    /// high it was crossing `edge` and where it came down to `ground`.
    private static func flight(from start: CGPoint, _ velocity: CGVector, edge: CGFloat,
                               ground: CGFloat) -> (atEdge: CGFloat?, landed: CGFloat?) {
        var body = NotchMascotRoam.Body(position: start, velocity: velocity, airborne: true)
        let sky = CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)
        var atEdge: CGFloat?
        for _ in 0..<600 {
            let before = body.position
            _ = NotchMascotRoam.step(&body, by: 1.0 / 60, in: sky, width: 46)
            if atEdge == nil, (before.x - edge) * (body.position.x - edge) <= 0, before.x != body.position.x {
                atEdge = before.y + (body.position.y - before.y) * (edge - before.x) / (body.position.x - before.x)
            }
            if body.velocity.dy < 0, body.position.y <= ground { return (atEdge, body.position.x) }
        }
        return (atEdge, nil)
    }

    private static func hopping(_ suite: TestSuite) {
        for (start, ground) in [(CGPoint(x: 1416, y: 0), CGFloat(70)), (CGPoint(x: 1380, y: 0), CGFloat(140)),
                                (CGPoint(x: 1439, y: 0), CGFloat(8))] {
            let velocity = Displays.hop(from: start, over: 1440, onto: ground, width: 46)
            let flown = flight(from: start, velocity, edge: 1440, ground: ground)
            suite.expect((flown.atEdge ?? -1) >= ground,
                         "hopping up \(ground), it clears the wall under the floor beside")
            suite.expect((flown.landed ?? 0) >= 1440 + 23,
                         "hopping up \(ground), it lands with its whole body over the floor beside")
            suite.expect((flown.landed ?? .infinity) <= 1440 + 200,
                         "hopping up \(ground), it does not overshoot far")
        }
        let leftward = Displays.hop(from: CGPoint(x: 1460, y: 0), over: 1440, onto: 70, width: 46)
        suite.expect(leftward.dx < 0 && leftward.dy > 0, "it hops the way the edge is")
    }

    private static func routes(_ suite: TestSuite) {
        let far = display(CGRect(x: 3360, y: 0, width: 1280, height: 1080))
        let row = [main, right, far]
        suite.expect(Displays.route(from: 0, to: 2, width: 46, height: height, in: row)
                     == [.walk(direction: 1, to: 1), .walk(direction: 1, to: 2)],
                     "two displays off, it walks across the one between")
        suite.expect(Displays.route(from: 2, to: 0, width: 46, height: height, in: row)
                     == [.walk(direction: -1, to: 1), .walk(direction: -1, to: 0)],
                     "and back the other way")
        suite.expect(Displays.route(from: 1, to: 1, width: 46, height: height, in: row) == [],
                     "already there, no legs")
        let under = display(CGRect(x: 200, y: -1080, width: 1920, height: 1080))
        let stack = [main, under]
        let down = Displays.route(from: 0, to: 1, width: 46, height: height, in: stack)
        suite.expect(down == [.drop(over: (200 + 23)...(1440 - 23), to: 1)],
                     "to the display below, it drops through the floor over it")
        suite.expect(Displays.route(from: 1, to: 0, width: 46, height: height, in: stack) == nil,
                     "never up into the display above on foot")
        suite.expect(Displays.reachable(from: 0, width: 46, height: height, in: stack) == [1]
                     && Displays.reachable(from: 1, width: 46, height: height, in: stack).isEmpty,
                     "where it can wander to")
        let aside = display(CGRect(x: 1440, y: -1080, width: 1920, height: 1080))
        suite.expect(Displays.dropSpan(from: 0, into: 1, width: 46, in: [main, aside]) == nil,
                     "a display below and to the side is no drop")
        suite.expect(Displays.walkLength(to: 440, speed: 44, width: 46) > 10
                     && Displays.walkLength(to: 0, speed: 44, width: 46) > 0,
                     "a walk to the edge runs a few strides past it")
    }

    private static func gang(_ suite: TestSuite) {
        suite.expect(Displays.gathering([1, 3, 0]) == 1, "the gang meets where most of it is")
        suite.expect(Displays.gathering([2, 2], preferring: 1) == 1 && Displays.gathering([2, 2]) == 0,
                     "on a tie, where the one asking is")
        suite.expect(Displays.gathering([0, 0]) == nil, "no one out, nowhere")
        let rolls = stride(from: 0.0, to: 1.0, by: 0.001).compactMap { Displays.arrival([3, 0], random: $0) }
        let elsewhere = Double(rolls.filter { $0 == 1 }.count) / Double(rolls.count)
        suite.expect(elsewhere > 0.05 && elsewhere < 0.25,
                     "guests mostly arrive where the others are, now and then elsewhere")
        suite.expect(Displays.arrival([0, 0, 0], random: 0.99) == 2 && Displays.arrival([], random: 0.5) == nil,
                     "with no one out, any display")
        suite.expect(!Displays.wanders(wanderlust: 2, since: Displays.wanderInterval - 1, random: 0)
                     && Displays.wanders(wanderlust: 1, since: Displays.wanderInterval, random: 0),
                     "it sets off on its own only so often")
        suite.expect(Displays.wanders(wanderlust: 2, since: 1000, random: Displays.wanderChance * 1.5)
                     && !Displays.wanders(wanderlust: 1, since: 1000, random: Displays.wanderChance * 1.5),
                     "the more it likes to wander, the likelier")
        suite.expect(NotchMascotPersonality.prankster.wanderlust > NotchMascotPersonality.glutton.wanderlust
                     && NotchMascotPersonality.sleepy.wanderlust < NotchMascotPersonality.shy.wanderlust
                     && NotchMascotPersonality.allCases.allSatisfy { $0.wanderlust > 0 },
                     "a prankster wanders off most, a sleepy one least")
        suite.expect(!Displays.joins(since: Displays.joinInterval - 1, random: 0)
                     && Displays.joins(since: Displays.joinInterval, random: 0)
                     && !Displays.joins(since: 1000, random: Displays.joinChance),
                     "alone, it goes over to the others now and then")
    }
}
