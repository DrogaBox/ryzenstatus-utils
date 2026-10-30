// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The companion out on the desktop: how it is held, thrown, falls and lands,
/// and what it does on its own in between. Pure, so every rule is tested
/// without a window. Points are the screen's, y growing upward, and the
/// body's position is the middle of its feet.
enum NotchMascotRoam {
    /// A drawn companion's square on the desktop.
    static let drawnSize: CGFloat = 46
    /// A full-height sprite figure's height on the desktop: its sheet's
    /// cells at half their pixels, sharp on a Retina display.
    static let spriteSize: CGFloat = 104

    /// Its size on the desktop with `look`: a sprite as tall as it stands
    /// beside the others.
    static func size(for look: NotchMascotLook) -> CGFloat {
        guard let sheet = look.style.sprite else { return drawnSize }
        return (spriteSize * sheet.stature).rounded()
    }

    /// Its window: room around it to lean, hop and show its hearts.
    static func windowSize(for size: CGFloat) -> CGSize {
        CGSize(width: (size * 2).rounded(.up), height: (size * 1.75).rounded(.up))
    }

    /// From the window's bottom edge to its feet.
    static func footInset(for size: CGFloat) -> CGFloat { (size * 0.12).rounded() }

    // MARK: Gestures

    /// A press let go within this long, having moved less than `tapSlop`,
    /// is a pat rather than a grab.
    static let tapDuration: TimeInterval = 0.4
    static let tapSlop: CGFloat = 3

    static func isTap(held: TimeInterval, moved: CGFloat) -> Bool {
        held <= tapDuration && moved < tapSlop
    }

    /// Positions this recent count toward the velocity it is let go with.
    static let sampleWindow: TimeInterval = 0.1
    /// It keeps at most this many positions.
    static let sampleLimit = 16

    struct Sample: Equatable {
        var point: CGPoint
        var time: TimeInterval
    }

    /// Adds `sample` to `samples`, dropping those too old to count and the
    /// oldest past the limit.
    static func record(_ sample: Sample, into samples: inout [Sample]) {
        samples.removeAll { sample.time - $0.time > sampleWindow }
        samples.append(sample)
        if samples.count > sampleLimit { samples.removeFirst(samples.count - sampleLimit) }
    }

    /// The velocity over the recent samples, in points a second, or nil when
    /// they span too short a time to say: under a frame and a half.
    static func velocity(of samples: [Sample], at now: TimeInterval) -> CGVector? {
        let recent = samples.filter { now - $0.time <= sampleWindow }
        guard let first = recent.first, let last = recent.last else { return nil }
        let span = last.time - first.time
        guard span >= 0.017 else { return nil }
        let velocity = CGVector(dx: (last.point.x - first.point.x) / span, dy: (last.point.y - first.point.y) / span)
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > maximumThrow else { return velocity }
        return CGVector(dx: velocity.dx * maximumThrow / speed, dy: velocity.dy * maximumThrow / speed)
    }

    /// Faster than this, held or flying, it runs the way it goes.
    static let runSpeed: CGFloat = 60
    /// Slower than this in both directions while held, it hangs still.
    static let stillSpeed: CGFloat = 20

    /// How far it leans for a horizontal speed: into the swing, at most a
    /// fifth of a turn's quarter.
    static func lean(forSpeed speed: CGFloat) -> CGFloat {
        let limit: CGFloat = 0.32
        return max(-limit, min(limit, -speed / 2400))
    }

    // MARK: Flight

    static let gravity: CGFloat = 2600
    /// Speed kept every 16 ms sliding on the floor and flying.
    static let floorFriction: CGFloat = 0.88
    static let airDrag: CGFloat = 0.995
    /// Share of its speed a landing or a wall gives back.
    static let floorBounce: CGFloat = 0.32
    static let wallBounce: CGFloat = 0.45
    /// Coming down slower than this, it lands rather than bounces.
    static let bounceSpeed: CGFloat = 320
    /// Sliding slower than this, it stops.
    static let restSpeed: CGFloat = 40
    static let maximumThrow: CGFloat = 4200
    /// A landing or a bump this hard dizzies it.
    static let dizzySpeed: CGFloat = 1500

    /// Tracks rapid back-and-forth movement while held to dizzy the companion on release.
    struct ShakeTracker: Equatable {
        private(set) var reversals: Int = 0
        private var lastDirection: CGFloat = 0
        private var lastReversalTime: TimeInterval = 0
        private var spanSinceReversal: CGFloat = 0

        /// How many rapid direction reversals count as shaken dizzy.
        static let dizzyReversals: Int = 4
        /// Maximum time between reversals to count as a shake sequence.
        static let maxReversalInterval: TimeInterval = 0.45
        /// Minimum travel distance in one direction before a reversal counts.
        static let minTravel: CGFloat = 16

        mutating func track(deltaX: CGFloat, time: TimeInterval) {
            let dir: CGFloat = deltaX > 0.5 ? 1 : (deltaX < -0.5 ? -1 : 0)
            guard dir != 0 else { return }
            spanSinceReversal += abs(deltaX)
            if lastDirection != 0 && dir != lastDirection {
                if time - lastReversalTime <= Self.maxReversalInterval && spanSinceReversal >= Self.minTravel {
                    reversals += 1
                } else {
                    reversals = 1
                }
                lastReversalTime = time
                spanSinceReversal = 0
            } else if lastDirection == 0 {
                lastReversalTime = time
            }
            lastDirection = dir
        }

        var isDizzy: Bool { reversals >= Self.dizzyReversals }

        mutating func reset() {
            reversals = 0
            lastDirection = 0
            lastReversalTime = 0
            spanSinceReversal = 0
        }
    }

    struct Body: Equatable {
        var position: CGPoint
        var velocity: CGVector = .zero
        var airborne = true
    }

    enum Event: Equatable {
        /// It touched the floor coming down this fast.
        case landed(CGFloat)
        /// It hit a side of the screen going this fast.
        case bumped(CGFloat)
        /// It came to rest on the floor.
        case settled
    }

    /// Moves `body` on by `dt` seconds inside `area`, the part of the screen
    /// it may be in: falling, bouncing off its sides and the top, landing on
    /// its bottom or on one of `ledges`, the tops of windows, and sliding to
    /// a stop there. `width` is the body's.
    static func step(_ body: inout Body, by dt: TimeInterval, in area: CGRect, width: CGFloat,
                     ledges: [NotchMascotLedges.Ledge] = []) -> [Event] {
        guard dt > 0 else { return [] }
        let previous = body.position
        let dt = CGFloat(min(dt, 0.05))
        let frames = dt * 1000 / 16
        var events: [Event] = []
        let rising = body.velocity.dy
        if body.airborne {
            body.velocity.dy -= gravity * dt
            let drag = pow(airDrag, frames)
            body.velocity.dx *= drag
        } else {
            let friction = pow(floorFriction, frames)
            body.velocity.dx *= friction
            body.velocity.dy = 0
        }
        body.position.x += body.velocity.dx * dt
        // The mean of the speeds before and after: exact under gravity, so a
        // leap peaks as high at 60 frames a second, or across a dropped
        // frame, as at 120, and still clears the edge it was aimed over.
        body.position.y += (body.airborne ? (rising + body.velocity.dy) / 2 : body.velocity.dy) * dt
        let half = width / 2
        if body.position.x < area.minX + half {
            body.position.x = area.minX + half
            if body.velocity.dx < 0 {
                events.append(.bumped(-body.velocity.dx))
                body.velocity.dx = -body.velocity.dx * wallBounce
            }
        } else if body.position.x > area.maxX - half {
            body.position.x = area.maxX - half
            if body.velocity.dx > 0 {
                events.append(.bumped(body.velocity.dx))
                body.velocity.dx = -body.velocity.dx * wallBounce
            }
        }
        if body.position.y > area.maxY {
            body.position.y = area.maxY
            if body.velocity.dy > 0 { body.velocity.dy = -body.velocity.dy * wallBounce }
        }
        let ledge = body.airborne && body.velocity.dy <= 0
            ? NotchMascotLedges.landing(from: previous, to: body.position, in: ledges) : nil
        if body.airborne, let floor = ledge?.y ?? (body.position.y <= area.minY ? area.minY : nil) {
            body.position.y = floor
            let impact = -body.velocity.dy
            events.append(.landed(impact))
            if impact > bounceSpeed {
                body.velocity.dy = impact * floorBounce
            } else {
                body.velocity.dy = 0
                body.airborne = false
            }
        } else if !body.airborne, body.position.y > area.minY,
                  NotchMascotLedges.ledge(under: body.position, in: ledges) == nil {
            // The floor went away under it, as a Dock that hides or a window
            // it stood on that closed or moved off.
            body.airborne = true
        }
        if !body.airborne, abs(body.velocity.dx) < restSpeed {
            body.velocity = .zero
            events.append(.settled)
        }
        return events
    }

    // MARK: On its own

    /// Walking pace, in points a second.
    static let walkSpeed: CGFloat = 44

    enum Activity: Equatable {
        /// It stands where it is this long.
        case stand(TimeInterval)
        /// It walks `direction`, right when positive, this long.
        case walk(direction: CGFloat, duration: TimeInterval)
        /// It looks one way and the other.
        case lookAround
    }

    /// What it does next standing on the floor at `x`, between `minX` and
    /// `maxX`. It walks away from an edge it is close to, stands more than it
    /// walks, and now and then looks about. With a friend out at `friendX`
    /// and far off, it walks over to it. `random` gives numbers in 0..<1.
    static func nextActivity(x: CGFloat, minX: CGFloat, maxX: CGFloat, friendX: CGFloat? = nil,
                             random: () -> Double) -> Activity {
        let roll = random()
        if roll < 0.5 {
            return .stand(4 + random() * 10)
        }
        if roll < 0.62 {
            return .lookAround
        }
        if let friendX, abs(friendX - x) > farApart {
            return .walk(direction: friendX > x ? 1 : -1, duration: 3 + random() * 4)
        }
        let room = maxX - minX
        let nearLeft = x - minX < room * 0.15
        let nearRight = maxX - x < room * 0.15
        let direction: CGFloat = nearLeft ? 1 : nearRight ? -1 : (random() < 0.5 ? -1 : 1)
        return .walk(direction: direction, duration: 2 + random() * 4)
    }

    /// Out on its own, it goes back into the island after a while.
    static func excursionLength(random: Double) -> TimeInterval { 60 + random * 120 }

    // MARK: A friend

    /// A second companion hops out of the island this long after the first.
    static let friendDelay: TimeInterval = 0.8
    /// Farther apart than this, one walks over to the other.
    static let farApart: CGFloat = 360
    /// Walking toward its friend, it stops this close.
    static let meetDistance: CGFloat = 70
    /// This close, they wave at each other, at most this often.
    static let greetDistance: CGFloat = 120
    static let greetInterval: TimeInterval = 40

    /// Whether the friend comes out after the companion: on a walk of the
    /// companion's own, and pulled out too where the island keeps no place
    /// for the friend to wait in, as a capsule.
    static func friendComesAlong(grabbed: Bool, friendRestsInIsland: Bool) -> Bool {
        !grabbed || !friendRestsInIsland
    }

    /// Whether walking `direction` from `x` it has reached its friend at
    /// `friendX`: close, and the friend ahead of it rather than behind.
    static func meets(walking direction: CGFloat, from x: CGFloat, friendX: CGFloat) -> Bool {
        direction * (friendX - x) >= 0 && abs(friendX - x) <= meetDistance
    }

    /// Whether two companions `distance` apart, the last wave `since` seconds
    /// ago, wave at each other.
    static func greets(distance: CGFloat, since: TimeInterval) -> Bool {
        distance <= greetDistance && since >= greetInterval
    }

    // MARK: Home

    /// Let go this close below the island's top edge, near where it rests
    /// there, it goes back in.
    static let homeReach = CGSize(width: 90, height: 48)

    static func dropsHome(at point: CGPoint, rest: CGPoint, screenTop: CGFloat) -> Bool {
        abs(point.x - rest.x) <= homeReach.width && screenTop - point.y <= homeReach.height
    }

    /// The way back into the island: an arc from `start` up to `end`, rising
    /// above both. `t` runs from 0 to 1.
    static func homeArc(from start: CGPoint, to end: CGPoint, at t: CGFloat) -> CGPoint {
        let t = max(0, min(1, t))
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 140)
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }

    /// How long the way back takes for a distance.
    static func homeDuration(distance: CGFloat) -> TimeInterval {
        min(1.1, max(0.55, TimeInterval(distance) / 1600))
    }
}
