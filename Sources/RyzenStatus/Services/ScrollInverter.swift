// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import CoreGraphics

/// Rewrites mouse wheel events only, leaving the trackpad on macOS natural
/// scrolling: a modifying tap at the HID level (before the window server
/// derives pixel deltas from the wheel ticks), appended at the tail. It caps
/// every event at one notch for linear scrolling, redirects modifier-held
/// vertical ticks when requested and flips the selected axis deltas; any of
/// those features keeps the tap alive.
///
/// Wheel detection: discrete events (`isContinuous == 0`) are wheels; events
/// flagged continuous are wheels only when they carry no gesture phase at all.
/// Toggling takes effect immediately. Requires Accessibility.
final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    /// True while the event tap is installed and inverting.
    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?
    /// Fractions of a line linear scrolling has yet to deliver, one per axis.
    /// Tap callback only, like the timestamp above.
    private var linearCarryVertical: Double = 0
    private var linearCarryHorizontal: Double = 0

    private init() {}
    /// Events this process posts carry our own pid; they are never inverted.
    private static let ownProcessID = Int64(getpid())

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let wanted = ScrollDirectionPreferences().isEnabled || Self.linearScrollWanted
        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    /// Linear scrolling keeps the tap alive on its own, next to the direction
    /// features; its keys survive the hub uninstalling it.
    private static var linearScrollWanted: Bool {
        AppFeature.linearScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.linearScrollEnabled)
    }

    /// Each list's source apps are tracked only while its feature is one the
    /// tap is up for, so a list left behind by the other feature costs nothing.
    private func setSourceTracking(_ running: Bool) {
        let exceptions = MouseAppExceptions.shared
        exceptions.setSourceTracking(running && ScrollDirectionPreferences().isEnabled, for: .scrollDirection)
        exceptions.setSourceTracking(running && Self.linearScrollWanted, for: .linearScroll)
    }

    private func start() {
        guard tap == nil else {
            setSourceTracking(true)
            isRunning = true
            return
        }
        setSourceTracking(true)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
                return inverter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            setSourceTracking(false)
            isRunning = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
        setSourceTracking(false)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        linearCarryVertical = 0
        linearCarryHorizontal = 0
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Smooth scrolling swallows the wheel before this tap and already
        // turned its glide around, so flipping the glide here would cancel
        // that out and inverting would look broken while both are on. The
        // process id is checked too: the only scroll events this app posts
        // are those glide frames.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              sourceProcessID != Self.ownProcessID else {
            return Unmanaged.passUnretained(event)
        }

        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = UInt64(event.timestamp)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }

        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        let direction = ScrollDirectionPreferences(defaults: defaults)
        let directionApplies = direction.isEnabled
            && !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection, at: event.location, sourceProcessID: sourceProcessID)
        // Control-wheel is native zoom. Only the explicit Control-to-horizontal
        // shortcut turns it into scrolling.
        let controlRedirects = directionApplies
            && direction.horizontalModifier == .control
            && event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) == .maskControl
            && ScrollWheelSupport.isVerticalOnly(event)
        let nativeZoom = event.flags.contains(.maskControl) && !controlRedirects
        if let linesPerNotch = nativeZoom ? nil : ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable,
            isExcepted: {
                MouseAppExceptions.shared.excludesPointerTarget(
                    .linearScroll, at: event.location, sourceProcessID: sourceProcessID)
            }) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let rawVertical = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            let rawHorizontal = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
            let linearVertical = ScrollWheelSupport.linearDelta(
                rawVertical, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryVertical)
            let linearHorizontal = ScrollWheelSupport.linearDelta(
                rawHorizontal, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryHorizontal)
            linearCarryVertical = linearVertical.carry
            linearCarryHorizontal = linearHorizontal.carry
            // A fraction of a notch is carried into the next event rather
            // than delivered as an event that moves nothing.
            if rawVertical.hasMovement || rawHorizontal.hasMovement,
               !linearVertical.delta.hasMovement, !linearHorizontal.delta.hasMovement {
                return nil
            }
            ScrollWheelSupport.writeLinear(
                vertical: rawVertical.hasMovement ? linearVertical.delta : nil,
                horizontal: rawHorizontal.hasMovement ? linearHorizontal.delta : nil,
                to: event, isContinuous: traits.isContinuous)
        } else {
            // A fraction belongs to the active linear stream. Do not let it
            // reappear after an excepted app or an off/uninstalled interval.
            linearCarryVertical = 0
            linearCarryHorizontal = 0
        }

        // The direction features read their own availability here: linear
        // scrolling may be what keeps this tap alive.
        if directionApplies {
            ScrollWheelSupport.applyDirection(
                to: event, isContinuous: traits.isContinuous,
                invertVertical: direction.invertVertical,
                invertHorizontal: direction.invertHorizontal,
                horizontalModifier: direction.horizontalModifier)
        }
        return Unmanaged.passUnretained(event)
    }
}
