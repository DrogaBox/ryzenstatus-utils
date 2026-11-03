// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// A companion's life across more than one display: where it is going, and
/// how its last throw or drop treats the floors between displays.
struct NotchMascotRoaming {
    /// A walk to another display, as `NotchMascotDesktop.travel` sets out on.
    struct Trip {
        /// The display it walks to, by its frame, which outlasts a display change.
        var frame: CGRect
        /// Where along that display's floor it means to stand, if anywhere.
        var x: CGFloat?
        var pace: CGFloat
        /// Runs once it is there, or gave up: true when it got there.
        var done: ((Bool) -> Void)?
        /// Gives up the walk once it has taken too long.
        var limit: DispatchWorkItem?
    }

    var trip: Trip?
    /// How readily it sets off for another display on its own.
    var wanderlust: Double = 1
    /// When it last set off on its own, or went over to join the others.
    var lastWander = CACurrentMediaTime()
    var lastJoin: CFTimeInterval = -.infinity
    /// Thrown down, or dropping on purpose: the floor lets it through where
    /// a display sits under it, until it first lands.
    var fallsAcross = false
    /// Dropping into the display below on purpose: it lands without getting dizzy.
    var softLanding = false

    /// Let go at `velocity`: hard down, the floor over a display opens.
    mutating func letGo(at velocity: CGVector) {
        fallsAcross = velocity.dy < -NotchMascotDisplays.throwDown
        softLanding = false
    }

    /// It touched a floor or a window: the next floor holds again.
    mutating func landed() { fallsAcross = false }

    /// It came to rest.
    mutating func settled() {
        fallsAcross = false
        softLanding = false
    }
}

/// How a walk goes on at the end of the floor.
enum NotchMascotOnward {
    /// It turns back, as at any edge.
    case back
    /// It walks on, into the display beside or in from it.
    case on
    /// It hopped up onto the higher floor beside.
    case leapt
}

/// Walking across, flying across, setting off for another display, and the
/// way home from one, for a companion out on the desktop.
extension NotchMascotDesktop {
    /// Every display, in the global desktop layout.
    static var displays: [NotchMascotDisplays.Display] {
        NSScreen.screens.map { NotchMascotDisplays.Display(frame: $0.frame, area: $0.visibleFrame) }
    }

    /// On its way to another display.
    var isTravelling: Bool { roaming.trip != nil }

    private var bodyWidth: CGFloat { yardFigure.width }

    // MARK: Walking across

    /// Walking the floor toward `direction` past `low` or `high`, the ends of
    /// its display's floor: in from a display beside it, it walks on; out
    /// toward one whose floor goes on near its own height, it walks on into
    /// it, or hops up where that floor is a step higher; anywhere else it
    /// turns back.
    func walksOn(_ direction: CGFloat, low: CGFloat, high: CGFloat) -> NotchMascotOnward {
        let feet = yardFeet
        let inward = (feet.x <= low && direction > 0) || (feet.x >= high && direction < 0)
        guard !inward else { return .on }
        guard !inPlay, yardPlay == nil, NSScreen.screens.count > 1 else { return .back }
        let displays = Self.displays
        guard let here = NotchMascotDisplays.index(for: feet, in: displays),
              let way = NotchMascotDisplays.way(from: here, toward: direction, floor: feet.y, height: figureSize,
                                                in: displays)
        else {
            // The way it meant to go is shut now, as when the Dock came up.
            if isTravelling { endTrip(arrived: false) }
            return .back
        }
        guard !way.level else { return .on }
        let edge = direction > 0 ? displays[here].frame.maxX : displays[here].frame.minX
        let velocity = NotchMascotDisplays.hop(from: feet, over: edge, onto: displays[way.to].area.minY,
                                               width: bodyWidth)
        hop(dx: velocity.dx, dy: velocity.dy)
        return .leapt
    }

    // MARK: Flying across

    /// The part of the desktop it flies in from `area`, its display's: open
    /// toward a display beside it at its height, above it, and below it
    /// when thrown down hard or dropping on purpose.
    func flightArea(around area: CGRect) -> CGRect {
        guard !inPlay, yardPlay == nil, NSScreen.screens.count > 1 else { return area }
        return NotchMascotDisplays.flightArea(at: yardFeet, width: bodyWidth, height: figureSize,
                                              throughFloor: roaming.fallsAcross, in: Self.displays) ?? area
    }

    // MARK: Going somewhere

    /// Walks to the display that is `screen`, standing at `x` there if given,
    /// at `pace` times its walking pace, along the floors and down through
    /// them; it gives up after `limit` seconds. `done` runs once it is
    /// there, with true, or once it gives up. False when there is no way
    /// there on foot or it cannot set off now.
    @discardableResult
    func travel(to screen: NSScreen, x: CGFloat? = nil, pace: CGFloat = 1,
                within limit: TimeInterval = NotchMascotDisplays.tripLimit,
                then done: ((Bool) -> Void)? = nil) -> Bool {
        travel(toFrame: screen.frame, x: x, pace: pace, within: limit, then: done)
    }

    private func travel(toFrame frame: CGRect, x: CGFloat?, pace: CGFloat, within limit: TimeInterval,
                        then done: ((Bool) -> Void)?) -> Bool {
        guard isOut, !isTravelling, standsIdle, let feet else { return false }
        let displays = Self.displays
        guard let here = NotchMascotDisplays.index(for: feet, in: displays),
              let goal = displays.firstIndex(where: { $0.frame == frame }), goal != here,
              NotchMascotDisplays.route(from: here, to: goal, width: bodyWidth, height: figureSize,
                                        in: displays) != nil
        else { return false }
        let work = DispatchWorkItem { [weak self] in self?.endTrip(arrived: false) }
        // What waits on the walk hears of it only once it is under way.
        roaming.trip = NotchMascotRoaming.Trip(frame: frame, x: x, pace: pace, done: nil, limit: work)
        guard continueTrip(), roaming.trip != nil else {
            abandonTrip()
            return false
        }
        roaming.trip?.done = done
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)
        return true
    }

    /// The next stretch of its way to another display, once it stands with
    /// nothing else to do: on along the floor toward the edge, over to where
    /// it drops through, or down; there at last, over to where it meant to
    /// stand. False when it is not on its way, or stopped.
    func continueTrip() -> Bool {
        guard let trip = roaming.trip else { return false }
        guard isOut, standsIdle, let feet else {
            endTrip(arrived: false)
            return false
        }
        let displays = Self.displays
        guard let here = NotchMascotDisplays.index(for: feet, in: displays),
              let goal = displays.firstIndex(where: { $0.frame == trip.frame })
        else {
            endTrip(arrived: false)
            return false
        }
        if here == goal {
            let walk = trip.x.map { stroll(to: $0, pace: trip.pace) } ?? 0
            endTrip(arrived: true, after: walk)
            return walk > 0
        }
        guard let leg = NotchMascotDisplays.route(from: here, to: goal, width: bodyWidth, height: figureSize,
                                                  in: displays)?.first
        else {
            endTrip(arrived: false)
            return false
        }
        switch leg {
        case .walk(let direction, _):
            let edge = direction > 0 ? displays[here].frame.maxX : displays[here].frame.minX
            let length = NotchMascotDisplays.walkLength(to: abs(edge - feet.x),
                                                        speed: NotchMascotRoam.walkSpeed * trip.pace,
                                                        width: bodyWidth)
            guard wander(toward: direction, for: length, pace: trip.pace) else {
                endTrip(arrived: false)
                return false
            }
        case .drop(let span, _):
            if span.contains(feet.x) {
                roaming.fallsAcross = true
                roaming.softLanding = true
                hop(dx: (feet.x < (span.lowerBound + span.upperBound) / 2 ? 1 : -1) * 40, dy: 320)
                emote(.exclaim)
            } else if stroll(to: min(span.upperBound, max(span.lowerBound, feet.x)), pace: trip.pace) == 0 {
                endTrip(arrived: false)
                return false
            }
        }
        return true
    }

    /// The walk to another display is over: `done` runs once what it is
    /// doing now is through, `delay` seconds later when it still walks to
    /// its spot.
    func endTrip(arrived: Bool, after delay: TimeInterval = 0) {
        guard let trip = roaming.trip else { return }
        roaming.trip = nil
        trip.limit?.cancel()
        guard let done = trip.done else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay > 0 ? delay + 0.2 : 0)) { done(arrived) }
    }

    /// Off home or gone: the walk is forgotten, and what waited on it is
    /// not told.
    func abandonTrip() {
        roaming.trip?.limit?.cancel()
        roaming.trip = nil
    }

    /// Now and then, on its own, it sets off for another display it can
    /// walk to: more often the more it likes to wander. True when it does.
    func maybeWander() -> Bool {
        guard !isTravelling, NSScreen.screens.count > 1, standsIdle, let feet else { return false }
        let now = CACurrentMediaTime()
        guard NotchMascotDisplays.wanders(wanderlust: roaming.wanderlust, since: now - roaming.lastWander,
                                          random: Double.random(in: 0..<1))
        else { return false }
        roaming.lastWander = now
        let displays = Self.displays
        guard let here = NotchMascotDisplays.index(for: feet, in: displays),
              let goal = NotchMascotDisplays.reachable(from: here, width: bodyWidth, height: figureSize,
                                                       in: displays).randomElement()
        else { return false }
        let area = displays[goal].area
        let margin = min(area.width / 3, bodyWidth * 1.5)
        let x = CGFloat.random(in: (area.minX + margin)...max(area.minX + margin, area.maxX - margin))
        guard travel(toFrame: displays[goal].frame, x: x, pace: gait, within: NotchMascotDisplays.tripLimit,
                     then: nil)
        else { return false }
        emote(.idea)
        return true
    }

    /// Alone on its display, it sets off to `screen` to stand by `x`, as
    /// often as it may. True when it does.
    func join(on screen: NSScreen, by x: CGFloat, then done: ((Bool) -> Void)? = nil) -> Bool {
        let now = CACurrentMediaTime()
        guard NotchMascotDisplays.joins(since: now - roaming.lastJoin, random: Double.random(in: 0..<1)) else { return false }
        roaming.lastJoin = now
        let side: CGFloat = Bool.random() ? 1 : -1
        guard travel(to: screen, x: x + side * figureSize * 1.4, pace: 1.3, then: done) else { return false }
        roaming.lastWander = now
        return true
    }

    // MARK: Home

    /// Its time out is over: on another display than the island's, it walks
    /// back to the island's first where it can, then goes in; else it flies
    /// home from where it is.
    func headHome() {
        guard NSScreen.screens.count > 1, !isTravelling, standsIdle, let feet, let rest = restingPlace?() else {
            goHome()
            return
        }
        let displays = Self.displays
        guard let home = NotchMascotDisplays.index(for: rest.center, in: displays),
              let here = NotchMascotDisplays.index(for: feet, in: displays), here != home,
              travel(toFrame: displays[home].frame, x: rest.center.x, pace: 1.3, within: 40,
                     then: { [weak self] _ in self?.goHome() })
        else {
            goHome()
            return
        }
    }
}
