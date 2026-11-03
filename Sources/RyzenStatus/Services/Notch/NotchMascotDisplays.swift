// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The companions' way across more than one display: where the floor goes on
/// into the display beside, where a step up or a drop down is in reach, where
/// a thrown one may fly on, and which display the gang meets on. Pure, so
/// every rule is tested without a screen. Frames are in the global desktop
/// layout, y growing upward, and a body's position is the middle of its feet.
enum NotchMascotDisplays {
    /// One display: its whole frame, and the area a companion may be in,
    /// above the Dock and below the menu bar.
    struct Display: Equatable {
        var frame: CGRect
        var area: CGRect
    }

    /// Frames this close share an edge.
    static let touch: CGFloat = 2
    /// A floor this much higher beside it is walked onto in a stride.
    static let stride: CGFloat = 6
    /// A floor at most this much higher beside it is hopped up onto.
    static let climb: CGFloat = 140
    /// A floor at most this much lower beside it is walked off onto: little
    /// enough to land without getting dizzy.
    static let fall: CGFloat = 360
    /// Of its height, the share that must fit under the top of the display
    /// beside it for the body to pass there.
    static let headroom: CGFloat = 0.6
    /// Thrown down faster than this, a floor with a display under it lets
    /// the body through.
    static let throwDown: CGFloat = 700

    // MARK: Where it is

    /// The display that holds `point`, else the nearest one; nil with none.
    static func index(for point: CGPoint, in displays: [Display]) -> Int? {
        NotchMascotRoam.screenIndex(for: point, in: displays.map(\.frame))
    }

    // MARK: Beside, above and below

    /// Whether `other` adjoins `display` on its side toward `direction`,
    /// right when positive.
    static func adjoins(_ other: Display, _ display: Display, toward direction: CGFloat) -> Bool {
        direction > 0 ? abs(other.frame.minX - display.frame.maxX) <= touch
            : abs(other.frame.maxX - display.frame.minX) <= touch
    }

    /// Whether a body `height` tall with its feet at `y` fits through into
    /// `other`: on or above its floor and under its top.
    static func takes(_ other: Display, feetAt y: CGFloat, height: CGFloat) -> Bool {
        y >= other.area.minY - 0.5 && y + height * headroom <= other.area.maxY
    }

    /// The display beside `index` toward `direction` that a body `height`
    /// tall with its feet at `y` passes into as it goes, flying or walking.
    static func beside(_ index: Int, toward direction: CGFloat, feetAt y: CGFloat, height: CGFloat,
                       in displays: [Display]) -> Int? {
        guard displays.indices.contains(index) else { return nil }
        let here = displays[index]
        return displays.indices.first { other in
            other != index && adjoins(displays[other], here, toward: direction)
                && takes(displays[other], feetAt: y, height: height)
        }
    }

    /// The display right above `index` over `x`, with room for a body
    /// `width` wide.
    static func above(_ index: Int, at x: CGFloat, width: CGFloat, in displays: [Display]) -> Int? {
        guard displays.indices.contains(index) else { return nil }
        let here = displays[index]
        return displays.indices.first { other in
            let there = displays[other]
            return other != index && abs(there.frame.minY - here.frame.maxY) <= touch
                && x - width / 2 >= there.area.minX && x + width / 2 <= there.area.maxX
        }
    }

    /// The display right under `index` below `x`, with room for a body
    /// `width` wide.
    static func below(_ index: Int, at x: CGFloat, width: CGFloat, in displays: [Display]) -> Int? {
        guard displays.indices.contains(index) else { return nil }
        let here = displays[index]
        return displays.indices.first { other in
            let there = displays[other]
            return other != index && abs(there.frame.maxY - here.frame.minY) <= touch
                && x - width / 2 >= there.area.minX && x + width / 2 <= there.area.maxX
        }
    }

    // MARK: Walking

    /// The way on from a floor at the edge of a display.
    struct Way: Equatable {
        /// The display it walks into.
        var to: Int
        /// How much higher the floor is there; below zero when lower.
        var rise: CGFloat

        /// No more than a stride higher: it walks straight on, off a lower
        /// floor too, rather than hop.
        var level: Bool { rise <= stride }
    }

    /// Walking the floor at `y` of display `index` to its edge toward
    /// `direction`, the display it goes on into: one beside it whose floor
    /// is at most `climb` higher, to hop up onto, or at most `fall` lower,
    /// to walk off onto, with room above that floor for its `height`. The
    /// nearest floor wins; nil where it turns back.
    static func way(from index: Int, toward direction: CGFloat, floor y: CGFloat, height: CGFloat,
                    in displays: [Display]) -> Way? {
        guard displays.indices.contains(index) else { return nil }
        let here = displays[index]
        let ways = displays.indices.compactMap { other -> Way? in
            let there = displays[other]
            guard other != index, adjoins(there, here, toward: direction) else { return nil }
            let rise = there.area.minY - y
            guard rise <= climb, rise >= -fall, max(y, there.area.minY) + height * headroom <= there.area.maxY
            else { return nil }
            return Way(to: other, rise: rise)
        }
        return ways.min { abs($0.rise) < abs($1.rise) }
    }

    /// Where along the floor of display `index` it may drop down into the
    /// display `under` it: the feet's span over both, `width` wide; nil when
    /// `under` is not right below or the two overlap too little.
    static func dropSpan(from index: Int, into under: Int, width: CGFloat,
                         in displays: [Display]) -> ClosedRange<CGFloat>? {
        guard displays.indices.contains(index), displays.indices.contains(under), index != under else { return nil }
        let here = displays[index], there = displays[under]
        guard abs(there.frame.maxY - here.frame.minY) <= touch else { return nil }
        let low = max(here.area.minX, there.area.minX) + width / 2
        let high = min(here.area.maxX, there.area.maxX) - width / 2
        return low <= high ? low...high : nil
    }

    /// The hop over the edge at `edgeX` from `start` up onto a floor at
    /// `ground` on the other side: already above that floor as it passes
    /// the edge, so it never meets the wall under it, and landing `width`
    /// past the edge, as low an arc as does both. Points a second.
    static func hop(from start: CGPoint, over edgeX: CGFloat, onto ground: CGFloat, width: CGFloat,
                    gravity: CGFloat = NotchMascotRoam.gravity, drag: CGFloat = NotchMascotRoam.airDrag) -> CGVector {
        let direction: CGFloat = edgeX >= start.x ? 1 : -1
        let toEdge = max(0, abs(edgeX - start.x))
        let past = toEdge + width
        let above = ground + 4 - start.y
        var hop = CGVector.zero
        for clearance: CGFloat in [24, 40, 64, 96, 140, 200, 280] {
            let apex = max(start.y, ground) + clearance
            let up = (2 * gravity * (apex - start.y)).squareRoot()
            let falling = (2 * (apex - ground) / gravity).squareRoot()
            // How soon it is clear of the floor beside, on its way up.
            let clear = above <= 0 ? 0 : (up - max(0, up * up - 2 * gravity * above).squareRoot()) / gravity
            let speed = past / reach(over: up / gravity + falling, drag: drag)
            hop = CGVector(dx: direction * speed, dy: up)
            guard speed * reach(over: clear, drag: drag) > toEdge else { return hop }
            // Too flat: it would reach the edge before it is clear. Slower,
            // it passes the edge clear of the floor but lands short; higher
            // still, maybe both.
            hop.dx = direction * toEdge / max(0.01, reach(over: clear, drag: drag))
        }
        return hop
    }

    /// How far one point a second carries over `time` under `drag`, as
    /// `NotchMascotLedges.leap` counts it.
    private static func reach(over time: CGFloat, drag: CGFloat) -> CGFloat {
        let rate = log(drag) / 0.016
        return max(0.01, rate == 0 ? time : (exp(rate * time) - 1) / rate)
    }

    // MARK: Flying

    /// Where a body in flight at `point`, `width` wide and `height` tall,
    /// may go: the area of its display, opened on a side where the display
    /// beside takes it at its height, at the top where a display sits right
    /// above, and at the bottom where one sits right below and it comes
    /// `throughFloor`. Nil with no display.
    static func flightArea(at point: CGPoint, width: CGFloat, height: CGFloat, throughFloor: Bool,
                           in displays: [Display]) -> CGRect? {
        guard let index = index(for: point, in: displays) else { return nil }
        let here = displays[index]
        var minX = here.area.minX, maxX = here.area.maxX, minY = here.area.minY, maxY = here.area.maxY
        if let right = beside(index, toward: 1, feetAt: point.y, height: height, in: displays) {
            maxX = max(here.frame.maxX + width, displays[right].area.maxX)
        }
        if let left = beside(index, toward: -1, feetAt: point.y, height: height, in: displays) {
            minX = min(here.frame.minX - width, displays[left].area.minX)
        }
        if let up = above(index, at: point.x, width: width, in: displays) {
            maxY = displays[up].area.maxY
        }
        if throughFloor, let down = below(index, at: point.x, width: width, in: displays) {
            minY = displays[down].area.minY
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Journeys

    /// One stretch of the way to another display.
    enum Leg: Equatable {
        /// Along the floor toward `direction` and on into display `to`.
        case walk(direction: CGFloat, to: Int)
        /// Down through the floor into display `to`, from anywhere in `over`.
        case drop(over: ClosedRange<CGFloat>, to: Int)

        var to: Int {
            switch self {
            case .walk(_, let to), .drop(_, let to): return to
            }
        }
    }

    /// The legs from display `start` to display `goal` for a body `width`
    /// wide and `height` tall, fewest first: along the floors and down
    /// through them, never up. Empty when already there; nil when there is
    /// no way there on foot.
    static func route(from start: Int, to goal: Int, width: CGFloat, height: CGFloat,
                      in displays: [Display]) -> [Leg]? {
        guard displays.indices.contains(start), displays.indices.contains(goal) else { return nil }
        guard start != goal else { return [] }
        var came: [Int: (from: Int, leg: Leg)] = [start: (start, .walk(direction: 0, to: start))]
        var queue = [start]
        while !queue.isEmpty {
            let here = queue.removeFirst()
            for leg in legs(from: here, width: width, height: height, in: displays) where came[leg.to] == nil {
                came[leg.to] = (here, leg)
                guard leg.to != goal else {
                    var path: [Leg] = []
                    var at = goal
                    while at != start, let step = came[at] {
                        path.insert(step.leg, at: 0)
                        at = step.from
                    }
                    return path
                }
                queue.append(leg.to)
            }
        }
        return nil
    }

    /// Every display one leg away from `index`.
    static func legs(from index: Int, width: CGFloat, height: CGFloat, in displays: [Display]) -> [Leg] {
        guard displays.indices.contains(index) else { return [] }
        let floor = displays[index].area.minY
        var legs: [Leg] = []
        for direction: CGFloat in [-1, 1] {
            if let way = way(from: index, toward: direction, floor: floor, height: height, in: displays) {
                legs.append(.walk(direction: direction, to: way.to))
            }
        }
        for other in displays.indices {
            if let span = dropSpan(from: index, into: other, width: width, in: displays) {
                legs.append(.drop(over: span, to: other))
            }
        }
        return legs
    }

    /// The displays a body can get to on foot from `index`, itself left out.
    static func reachable(from index: Int, width: CGFloat, height: CGFloat, in displays: [Display]) -> [Int] {
        displays.indices.filter {
            $0 != index && route(from: index, to: $0, width: width, height: height, in: displays) != nil
        }
    }

    // MARK: The gang

    /// The display where most of `counts` are, `preferring` it on a tie;
    /// nil when no one is anywhere.
    static func gathering(_ counts: [Int], preferring: Int? = nil) -> Int? {
        guard let most = counts.max(), most > 0 else { return nil }
        if let preferring, counts.indices.contains(preferring), counts[preferring] == most { return preferring }
        return counts.firstIndex(of: most)
    }

    /// Where a guest arrives, `counts` out on each display: mostly where
    /// the others already are, now and then somewhere else.
    static func arrival(_ counts: [Int], random: Double) -> Int? {
        guard !counts.isEmpty else { return nil }
        let weights = counts.map { $0 > 0 ? 2 + 2 * Double($0) : 1 }
        let total = weights.reduce(0, +)
        var roll = max(0, min(0.999_999, random)) * total
        for (index, weight) in weights.enumerated() {
            if roll < weight { return index }
            roll -= weight
        }
        return counts.count - 1
    }

    /// Between two walks of its own to another display, at least this long.
    static let wanderInterval: TimeInterval = 90
    /// Each time it thinks what to do next, the odds it sets off for
    /// another display, times its wanderlust.
    static let wanderChance = 0.05
    /// Alone on a display, the odds each time it thinks that it goes over
    /// to the others, and how long it waits before it may again.
    static let joinChance = 0.3
    static let joinInterval: TimeInterval = 25
    /// How long a walk to another display may take before it gives up, and
    /// how long a play waits for those walking over to it.
    static let tripLimit: TimeInterval = 45
    static let rallyWait: TimeInterval = 30

    /// Whether it sets off for another display now, with `wanderlust`.
    static func wanders(wanderlust: Double, since: TimeInterval, random: Double) -> Bool {
        since >= wanderInterval && random < wanderChance * wanderlust
    }

    /// Whether, alone on its display, it goes over to the others now.
    static func joins(since: TimeInterval, random: Double) -> Bool {
        since >= joinInterval && random < joinChance
    }

    /// How long a walk toward an edge `distance` away runs: to the edge
    /// and a few strides past it, at `speed` points a second.
    static func walkLength(to distance: CGFloat, speed: CGFloat, width: CGFloat) -> TimeInterval {
        TimeInterval((max(0, distance) + width * 2.5) / max(1, speed))
    }
}

extension NotchMascotPersonality {
    /// How readily it wanders off to another display: a prankster or a
    /// show-off often, a shy or sleepy one hardly ever.
    var wanderlust: Double {
        switch self {
        case .prankster: return 2
        case .showOff: return 1.6
        case .glutton: return 1
        case .grumpy: return 0.6
        case .shy: return 0.5
        case .sleepy: return 0.35
        }
    }
}
