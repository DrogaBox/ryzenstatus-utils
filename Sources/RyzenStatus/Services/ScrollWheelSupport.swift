// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

struct ScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
}

struct ScrollWheelInversionPlan: Equatable {
    let vertical: Bool
    let horizontal: Bool
}

/// Tells mouse wheels apart from touch devices, shared by the scroll
/// inverter and smooth scrolling so both features classify events the same
/// way: discrete events are wheels; events flagged continuous are wheels
/// only when they carry no gesture phase at all (how some mouse drivers
/// report their wheels).
enum ScrollWheelSupport {
    /// How long after a gesture-phased event a phaseless continuous event is
    /// still attributed to the same touch device.
    static let touchGestureGraceSeconds: TimeInterval = 1.0

    /// Marks the smooth glide so neither feature handles it twice. Events a
    /// process posts come back through that same process's taps (measured at
    /// every tap location), so without the mark the inverter would turn the
    /// glide around again and cancel the flip smooth scrolling already
    /// applied.
    static let syntheticTag: Int64 = 0x564F5253  // "VORS"

    /// Points in one scroll line. The window server measures the fixed-point
    /// delta in lines, so an event that moved forty points reports four;
    /// replaying that number as pixels would travel a tenth of the distance.
    static let pointsPerLine: Double = 10

    static func isMouseWheel(_ traits: ScrollWheelEventTraits,
                             secondsSinceLastGesturePhase: TimeInterval?) -> Bool {
        if !traits.isContinuous {
            return true
        }
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }
        // Trackpads/Magic Mouse can emit a phaseless transition event between
        // gesture end and momentum start that still carries the gesture's
        // scrollCount. Mouse wheels that report continuous never emit phases,
        // so only events right after a phased one are treated as touch.
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }
        return true
    }

    /// Shift redirects a discrete vertical wheel tick sideways above the event tap.
    /// Select the setting for the direction the user will see, while leaving
    /// genuine two-axis events independent.
    static func inversionPlan(hasVerticalMovement: Bool,
                              hasHorizontalMovement: Bool,
                              shiftRedirectsVertical: Bool,
                              invertVertical: Bool,
                              invertHorizontal: Bool) -> ScrollWheelInversionPlan {
        let shiftRedirectsVertically = shiftRedirectsVertical
            && hasVerticalMovement
            && !hasHorizontalMovement
        return ScrollWheelInversionPlan(
            vertical: hasVerticalMovement
                && (shiftRedirectsVertically ? invertHorizontal : invertVertical),
            horizontal: hasHorizontalMovement && invertHorizontal
        )
    }

    /// Movement on the vertical axis only, as a plain mouse wheel sends it.
    static func isVerticalOnly(_ event: CGEvent) -> Bool {
        (event.getIntegerValueField(.scrollWheelEventDeltaAxis1) != 0
            || event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0
            || event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) != 0)
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0
            && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0
    }

    /// Moves a vertical-only event to the horizontal axis, keeping its sign
    /// as Shift does.
    static func moveVerticalToHorizontal(_ event: CGEvent) {
        let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        // Line writes can rederive pixel fields; restore the captured precision
        // only after both line axes have been written.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point)
    }

    /// A mouse wheel only turns vertically, so a strip that scrolls only
    /// sideways could not be moved with one. The wheel moves the strip when
    /// nothing around it scrolls down; a list around it keeps the wheel.
    static func wheelMovesStripSideways(stripScrollsHorizontally: Bool, stripScrollsVertically: Bool,
                                        enclosingScrollsVertically: Bool) -> Bool {
        stripScrollsHorizontally && !stripScrollsVertically && !enclosingScrollsVertically
    }
}

// MARK: - Sideways scrolling and linear scrolling (ported from upstream)

enum ScrollHorizontalModifier: String, CaseIterable {
    case shift, option, control, command

    init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .shift
    }

    var flag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

/// Both independently installed direction features share one tap. Resolve their
/// effective settings once so raw and smoothed wheels honor removal identically.
struct ScrollDirectionPreferences {
    let invertVertical: Bool
    let invertHorizontal: Bool
    let horizontalModifier: ScrollHorizontalModifier?

    var isEnabled: Bool { invertVertical || invertHorizontal || horizontalModifier != nil }

    init(isAvailable: (AppFeature) -> Bool,
         boolFor: (String) -> Bool,
         stringFor: (String) -> String?) {
        invertVertical = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterEnabled)
        invertHorizontal = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterHorizontalEnabled)
        horizontalModifier = isAvailable(.scrollHorizontal) && boolFor(DefaultsKey.scrollHorizontalEnabled)
            ? ScrollHorizontalModifier(storageValue: stringFor(DefaultsKey.scrollHorizontalModifier)) : nil
    }

    init(defaults: UserDefaults = .standard) {
        self.init(isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                  boolFor: { defaults.bool(forKey: $0) },
                  stringFor: { defaults.string(forKey: $0) })
    }
}

/// The three delta fields a scroll event carries per axis: the line count,
/// the point count and the fixed-point line count.
struct ScrollWheelAxisDelta: Equatable {
    var line: Int64
    var point: Int64
    var fixedPoint: Double

    var hasMovement: Bool { line != 0 || point != 0 || fixedPoint != 0 }
}


extension ScrollWheelSupport {
    /// A redirected vertical wheel is not a physical side wheel. The session
    /// tap uses this marker to leave it out of side-wheel shortcut matching.
    static let horizontalRedirectTag: Int64 = 0x52534844  // "RSHD"

    /// Called only after wheel classification and the scroll-direction exception
    /// check. Consume the modifier so the receiving app cannot redirect or zoom
    /// the transformed event a second time. Other shortcut combinations keep
    /// their native meaning, as do wheels already supplying a horizontal axis.
    @discardableResult
    static func redirectVerticalScroll(_ event: CGEvent, modifier: ScrollHorizontalModifier) -> Bool {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        guard event.flags.intersection(shortcutFlags) == modifier.flag else { return false }
        guard isVerticalOnly(event) else { return false }
        moveVerticalToHorizontal(event)
        event.flags.remove(modifier.flag)
        event.setIntegerValueField(.eventSourceUserData, value: horizontalRedirectTag)
        return true
    }
}

// MARK: - Linear scrolling

/// Every notch of a mouse wheel worth the same distance, however fast the
/// wheel spins. macOS keeps its wheel acceleration inside the delta itself,
/// so a fast spin arrives as several lines in one event; capping an event at
/// one notch is what takes it out again. Shared by both wheel taps, so the
/// glide and the raw wheel agree on what a notch is worth.
extension ScrollWheelSupport {
    /// Lines one notch scrolls. The default of three moves a few lines of
    /// text per notch: a long page still goes by quickly, and the line being
    /// read stays on screen.
    static let linesPerNotchRange = 1...10
    static let defaultLinesPerNotch = 3

    /// Lines per notch while linear scrolling applies to this event, or nil
    /// when it is off, uninstalled or the app under the pointer is on its own
    /// exception list. Both wheel taps ask it the same way; the exception
    /// list is only consulted while the feature is on.
    static func linearLinesPerNotch(defaults: UserDefaults, isAvailable: Bool,
                                    isExcepted: () -> Bool) -> Int? {
        guard isAvailable, defaults.bool(forKey: DefaultsKey.linearScrollEnabled), !isExcepted() else {
            return nil
        }
        return sanitizedLinesPerNotch(defaults.integer(forKey: DefaultsKey.linearScrollLines))
    }

    /// Clamps the persisted value to its allowed range (0 or garbage falls
    /// back to the default).
    static func sanitizedLinesPerNotch(_ value: Int) -> Int {
        guard value != 0 else { return defaultLinesPerNotch }
        return min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    /// The notch count of a discrete wheel event. macOS scales every notch by
    /// how fast the wheel turns, in both directions: a slow notch can arrive as
    /// a tenth of a line while its line count still reads one. Any event whose
    /// line count moves is therefore one whole notch; only a high-resolution
    /// wheel's fraction, which leaves the line count at zero, stays a fraction.
    /// Some drivers provide only points, so use those when both line fields
    /// are empty rather than dropping a real wheel event.
    static func discreteTicks(line: Int64, fixedPoint: Double, point: Int64) -> Double {
        if line != 0 { return line > 0 ? 1 : -1 }
        if fixedPoint.isFinite, fixedPoint != 0 { return fixedPoint }
        return Double(point) / pointsPerLine
    }

    /// The notch count of a continuous wheel event, in lines. The point field
    /// is what apps read, so it wins; the fixed-point field already counts
    /// lines and only stands in when the driver left the points empty.
    static func continuousTicks(fixedPointDelta: Double, pointDelta: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite else { return 0 }
        return pointDelta != 0 ? pointDelta / pointsPerLine : fixedPointDelta
    }

    /// The lines an event scrolls under linear scrolling: at most one notch,
    /// multiplied out. A high-resolution wheel's fraction of a notch stays a
    /// fraction, and the sign is untouched.
    static func linearLines(ticks: Double, linesPerNotch: Int) -> Double {
        guard ticks.isFinite, ticks != 0 else { return 0 }
        let lines = min(abs(ticks), 1) * Double(sanitizedLinesPerNotch(linesPerNotch))
        return ticks < 0 ? -lines : lines
    }

    /// The fields to write back into a wheel event under linear scrolling,
    /// plus the fraction of a line to carry into the next event. A discrete
    /// event gets only its line count, since the system rederives the other
    /// two fields from it; a continuous event gets all three, with the point
    /// count kept whole. The carry keeps sub-notch events from being lost and
    /// is dropped on a reversal, like the glide's.
    static func linearDelta(_ delta: ScrollWheelAxisDelta,
                            isContinuous: Bool,
                            linesPerNotch: Int,
                            carry: Double) -> (delta: ScrollWheelAxisDelta, carry: Double) {
        let ticks = isContinuous
            ? continuousTicks(fixedPointDelta: delta.fixedPoint, pointDelta: Double(delta.point))
            : discreteTicks(line: delta.line, fixedPoint: delta.fixedPoint, point: delta.point)
        let lines = linearLines(ticks: ticks, linesPerNotch: linesPerNotch)
        let kept = SmoothScrollSupport.carry(carry, continuing: lines)
        if isContinuous {
            let points = SmoothScrollSupport.wholePixels(lines * pointsPerLine,
                                                         carry: kept * pointsPerLine)
            let wholeLines = points.pixels / pointsPerLine
            return (ScrollWheelAxisDelta(line: Int64(wholeLines.rounded(.towardZero)),
                                         point: Int64(points.pixels),
                                         fixedPoint: wholeLines),
                    points.carry / pointsPerLine)
        }
        let wholeLines = SmoothScrollSupport.wholePixels(lines, carry: kept)
        return (ScrollWheelAxisDelta(line: Int64(wholeLines.pixels), point: 0, fixedPoint: 0),
                wholeLines.carry)
    }

    /// Writes linear scrolling's fields into a wheel event; an axis passed as
    /// nil did not move and is left alone. Both line counts go in first,
    /// since a line write can rederive the pixel fields; a continuous event's
    /// point and fixed-point counts follow once both lines are set.
    static func writeLinear(vertical: ScrollWheelAxisDelta?, horizontal: ScrollWheelAxisDelta?,
                            to event: CGEvent, isContinuous: Bool) {
        if let vertical { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: vertical.line) }
        if let horizontal { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: horizontal.line) }
        guard isContinuous else { return }
        if let vertical {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: vertical.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical.fixedPoint)
        }
        if let horizontal {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal.fixedPoint)
        }
    }
}

extension ScrollWheelSupport {
    /// The raw wheel path: redirects a modifier-held vertical tick sideways
    /// when asked, then applies inversion to the axis the user will actually
    /// scroll.
    static func applyDirection(to event: CGEvent, isContinuous: Bool,
                               invertVertical: Bool, invertHorizontal: Bool,
                               horizontalModifier: ScrollHorizontalModifier?) {
        let redirected = event.getIntegerValueField(.eventSourceUserData) == horizontalRedirectTag
            || (horizontalModifier.map { redirectVerticalScroll(event, modifier: $0) } ?? false)
        // Capture both axes before any set: writing a line delta makes the
        // system rederive its point and fixed-point fields.
        let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
        let hasHorizontalMovement = horizontalLine != 0 || horizontalPoint != 0 || horizontalFixedPoint != 0
        let plan = inversionPlan(
            hasVerticalMovement: hasVerticalMovement,
            hasHorizontalMovement: hasHorizontalMovement,
            shiftRedirectsVertical: !isContinuous && event.flags.contains(.maskShift),
            invertVertical: invertVertical,
            invertHorizontal: invertHorizontal
        )
        if plan.vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -verticalLine)
            // A zero whole-line field cannot reconstruct a high-resolution tick.
            if isContinuous || redirected || verticalLine == 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
            }
        }
        if plan.horizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
            if isContinuous || redirected || horizontalLine == 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -horizontalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -horizontalFixedPoint)
            }
        }
    }
}
