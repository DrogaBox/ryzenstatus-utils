// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// One decision per physical scroll sequence. No timer is needed for wheel
/// devices without phases: the next event itself expires an old sequence.
struct NotchGestureSupport {
    /// A sideways swipe means forward or back through whatever the surface
    /// under it steps through: songs over the music, otherwise the closed
    /// island's activities.
    ///
    /// A pull on a trackpad answers as it travels: `pull` carries how far the
    /// island's lower edge follows the fingers, down from a closed island or
    /// up into an open one, and `retract` sends it back when the fingers lift
    /// without carrying it far or fast enough to open or close.
    enum Action: Equatable { case open, close, dismiss, forward, back, pull(Double), retract }
    private enum Axis { case horizontal, vertical }
    private struct Origin {
        let vertical: Bool
        let horizontal: Bool
        let expanded: Bool
        let dismissible: Bool
        let pull: Bool
    }
    private var origin: Origin?
    private var axis: Axis?
    private var pulling = false
    private var pullVelocity = NotchPullVelocity()
    private var pendingX = 0.0
    private var pendingY = 0.0
    private var distance = 0.0
    private var fired = false
    private var coasting = false
    private var lastTimestamp: TimeInterval?
    private static let verticalThreshold = 16.0

    /// Whether the island is following a pull right now.
    var isPulling: Bool { pulling }

    static func nativeInteraction(at view: NSView?) -> (control: Bool, scroll: Bool) {
        var control = false
        var scroll = false
        var view = view
        while let current = view {
            // The transparent opening button is the gesture surface itself.
            if (current is NSControl && !(current is NotchActivationButton)) || current is NSTextView {
                control = true
            }
            if current is NSScrollView { scroll = true }
            view = current.superview
        }
        return (control, scroll)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchGestures.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchGesturesEnabled)
    }

    static func movement(_ delta: Double, precise: Bool, inverted: Bool) -> Double {
        guard delta.isFinite else { return 0 }
        return delta * (inverted ? 1 : -1) * (precise ? 1 : 24)
    }

    static func allowsVertical(expanded: Bool, inHeader: Bool, musicSurface: Bool,
                               control: Bool, scroll: Bool) -> Bool {
        !control && (!expanded || inHeader || (musicSurface && !scroll))
    }

    mutating func handle(x: Double, y: Double, timestamp: TimeInterval,
                         began: Bool, ended: Bool, momentum: Bool, precise: Bool, hasPhase: Bool,
                         allowVertical: Bool, allowHorizontal: Bool, expanded: Bool,
                         dismissible: Bool = false, pull: Bool = false, cancelled: Bool = false) -> Action? {
        guard timestamp.isFinite, x.isFinite, y.isFinite else {
            let wasPulling = pulling
            self = Self()
            return wasPulling ? .retract : nil
        }
        // A quick flick lifts the fingers before the swipe has travelled far
        // enough. Its momentum can finish the opening or closing it began,
        // never a track change. Trackpads can send one phaseless event between
        // the lift and the momentum; it belongs to the same flick. Momentum
        // that pauses, or turns sideways like the end of a track swipe, stops.
        let transition = coasting && !momentum && !hasPhase && precise
            && lastTimestamp.map({ timestamp >= $0 && timestamp - $0 <= 0.35 }) == true
        if momentum || transition {
            guard coasting, !fired, let origin, let last = lastTimestamp,
                  timestamp >= last, timestamp - last <= 0.35, abs(y) >= abs(x) * 1.5 else {
                self = Self(); return nil
            }
            lastTimestamp = timestamp
            distance += y
            return verticalAction(expanded: origin.expanded, dismissible: origin.dismissible)
        }
        if ended, pulling {
            // The fingers lifted from a pull: their speed decides, or where
            // that speed would carry the island in a moment.
            let release = pulled(at: timestamp, cancelled: cancelled)
            self = Self()
            return release
        }
        if ended {
            coasting = origin != nil && axis == .vertical && !fired
            if coasting { lastTimestamp = timestamp } else { self = Self() }
            return nil
        }
        if coasting { self = Self() }
        if hasPhase {
            if began {
                self = Self()
                origin = Origin(vertical: allowVertical, horizontal: allowHorizontal, expanded: expanded,
                                dismissible: dismissible, pull: pull && precise)
                pullVelocity.record(travel: 0, at: timestamp)
            }
            // AppKit keeps a phased scroll attached to its original view.
            // A blocked beginning stays blocked, and an interrupted sequence
            // cannot restart from a later changed event under another view.
            guard origin != nil else { return nil }
            if lastTimestamp.map({ timestamp < $0 }) == true { self = Self(); return nil }
        } else if origin != nil || began
                    || lastTimestamp.map({ timestamp < $0 || timestamp - $0 > 0.35 }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        guard !fired else { return nil }
        let allowVertical = origin?.vertical ?? allowVertical
        let allowHorizontal = origin?.horizontal ?? allowHorizontal
        let expanded = origin?.expanded ?? expanded
        let dismissible = origin?.dismissible ?? dismissible
        if axis == nil {
            // Establish intent from a little accumulated travel, not the first
            // fraction of a point as the fingers touch the trackpad.
            pendingX += x
            pendingY += y
            if precise, allowHorizontal, abs(pendingX) >= 4, abs(pendingX) >= abs(pendingY) * 1.5 {
                axis = .horizontal
                distance = pendingX
            }
            else if allowVertical, abs(pendingY) >= 4, abs(pendingY) >= abs(pendingX) * 1.5 {
                axis = .vertical
                distance = pendingY
                pulling = origin?.pull == true
            }
            else { return nil }
        } else {
            distance += axis == .horizontal ? x : y
        }
        switch axis {
        case .horizontal where allowHorizontal:
            guard abs(distance) >= 40 else { return nil }
            fired = true
            return distance < 0 ? .forward : .back
        case .vertical where allowVertical && pulling:
            // Up over a notice still flicks it away at once; otherwise the
            // island follows the fingers and decides when they lift.
            if distance <= -Self.verticalThreshold, !expanded, dismissible {
                fired = true
                pulling = false
                return .dismiss
            }
            let travel = expanded ? -distance : distance
            pullVelocity.record(travel: travel, at: timestamp)
            return .pull(NotchPull.displacement(travel: travel, expanded: expanded))
        case .vertical where allowVertical:
            return verticalAction(expanded: expanded, dismissible: dismissible)
        default:
            return nil
        }
    }

    private func pulled(at timestamp: TimeInterval, cancelled: Bool) -> Action {
        guard !cancelled, let origin, let travel = pullVelocity.travel,
              NotchPull.commits(travel: travel, velocity: pullVelocity.velocity(at: timestamp)) else { return .retract }
        return origin.expanded ? .close : .open
    }

    /// Down opens and up closes. Up over a closed island showing a notice
    /// sends the notice away, as flicking a banner off the top of the screen.
    private mutating func verticalAction(expanded: Bool, dismissible: Bool) -> Action? {
        guard abs(distance) >= Self.verticalThreshold else { return nil }
        fired = true
        if distance > 0, !expanded { return .open }
        if distance < 0, expanded { return .close }
        if distance < 0, dismissible { return .dismiss }
        return nil
    }
}

/// How a pull on the island answers before it opens or closes it. The
/// stretch saturates, as rubber does, so a long pull never runs away from
/// the island's shape; the decision waits for the fingers to lift.
enum NotchPull {
    /// The finger travel that would carry the island the whole way. Half of
    /// it, left to rest, opens or closes; a flick needs far less.
    static let fullTravel = 200.0
    /// Raw progress may pass either end a little, as the rubber gives.
    static let progressRange = -0.25...1.35
    /// The farthest a closed island stretches down after the fingers.
    static let maximumStretch = 28.0
    /// The farthest an open island gives way upward: a hint, not a close.
    static let maximumShrink = 14.0
    /// The travel over which the stretch reaches about 63% of its maximum.
    static let softness = 80.0
    /// Faster than this, in points per second, the direction alone decides.
    static let flickSpeed = 500.0
    /// How far ahead a slower release is projected, in seconds.
    static let projection = 0.13
    /// Room reserved below the island for its stretch, in whole points.
    static let reservation = CGFloat(maximumStretch.rounded(.up) + 2)

    /// Progress toward the other state, from finger travel in its direction.
    static func progress(travel: Double) -> Double {
        guard travel.isFinite else { return 0 }
        return min(max(travel / fullTravel, progressRange.lowerBound), progressRange.upperBound)
    }

    /// `maximum · (1 − e^(−travel / softness))`; travel the other way stays put.
    static func stretch(travel: Double, maximum: Double = maximumStretch) -> Double {
        guard travel.isFinite, travel > 0, maximum > 0 else { return 0 }
        return maximum * (1 - exp(-travel / softness))
    }

    /// How far the island's lower edge moves: down from a closed island, up
    /// into an open one.
    static func displacement(travel: Double, expanded: Bool) -> Double {
        expanded ? -stretch(travel: travel, maximum: maximumShrink) : stretch(travel: travel)
    }

    /// The heights a released pull passes through on its way back to rest,
    /// at 120 a second, ending exactly there. A stretched island swings a
    /// little past rest, up toward the screen's edge; an open one that gave
    /// way returns without passing its resting edge, below which its window
    /// has no room.
    static func retraction(from start: CGFloat, to rest: CGFloat)
        -> (heights: [CGFloat], keyTimes: [Double], duration: TimeInterval) {
        guard start.isFinite, rest.isFinite, start != rest else { return ([rest], [0], 0) }
        let spring = start > rest
            ? NotchMotion.Spring(duration: 0.38, bounce: 0.2).limited(travel: start - rest, limit: 3)
            : NotchMotion.Spring(duration: 0.3, bounce: 0)
        func height(at time: TimeInterval) -> CGFloat {
            start + (rest - start) * CGFloat(spring.progress(at: time))
        }
        let step = 1.0 / 240
        var duration = step
        var time = step
        while time < 2 {
            if abs(height(at: time) - rest) > NotchMotion.settledDistance { duration = time + step }
            time += step
        }
        let count = max(1, Int((duration * 120).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        return (keyTimes.map { $0 == 1 ? rest : max(0, height(at: duration * $0)) }, keyTimes, duration)
    }

    /// Whether lifting the fingers opens or closes. A flick goes its own way;
    /// a slower release goes where it would be a moment later.
    static func commits(travel: Double, velocity: Double) -> Bool {
        guard travel.isFinite else { return false }
        let velocity = velocity.isFinite ? velocity : 0
        if abs(velocity) > flickSpeed { return velocity > 0 }
        return progress(travel: travel) + velocity * projection / fullTravel > 0.5
    }
}

/// The fingers' speed as they lift, from the last stretch of travel. A pull
/// held still before lifting has no speed left, even though no event said so.
struct NotchPullVelocity {
    private var samples: [(time: TimeInterval, travel: Double)] = []
    /// How far back the speed is measured.
    static let window: TimeInterval = 0.06

    var travel: Double? { samples.last?.travel }

    mutating func record(travel: Double, at time: TimeInterval) {
        guard travel.isFinite, time.isFinite else { return }
        if let last = samples.last, time < last.time { samples.removeAll() }
        samples.append((time, travel))
        // Only the newest sample older than the window is ever the reference.
        if let keep = samples.lastIndex(where: { $0.time <= time - Self.window }), keep > 0 {
            samples.removeFirst(keep)
        }
    }

    func velocity(at release: TimeInterval) -> Double {
        guard let last = samples.last, release.isFinite, release >= last.time else { return 0 }
        let reference = samples.last { $0.time <= release - Self.window } ?? samples[0]
        let elapsed = max(release - reference.time, 1.0 / 120)
        return (last.travel - reference.travel) / elapsed
    }
}

/// An opening or closing a pull committed to, until the island settles.
/// Each commit has its own token: a late report from an earlier one never
/// releases a newer one, and no new pull starts over a moving island.
struct NotchPullCommit {
    private var latest = 0
    private var pending: Int?

    var isSettling: Bool { pending != nil }

    mutating func begin() -> Int {
        latest &+= 1
        pending = latest
        return latest
    }

    /// Returns whether `token` was the commit still settling.
    @discardableResult
    mutating func finish(_ token: Int) -> Bool {
        guard pending == token else { return false }
        pending = nil
        return true
    }
}
