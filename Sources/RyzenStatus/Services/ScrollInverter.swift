// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import CoreGraphics

/// Inverts the scroll direction of mouse wheels only, leaving the trackpad on
/// macOS natural scrolling: a modifying tap at the HID level (before the window
/// server derives pixel deltas from the
/// wheel ticks), appended at the tail, flipping the selected axis deltas.
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

    private init() {}
    /// Events this process posts carry our own pid; they are never inverted.
    private static let ownProcessID = Int64(getpid())

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.scrollInverter.isAvailable
            && (defaults.bool(forKey: DefaultsKey.scrollInverterEnabled)
                || defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled))
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

    private func start() {
        guard tap == nil else {
            MouseAppExceptions.shared.setSourceTracking(true, for: .scrollDirection)
            isRunning = true
            return
        }
        MouseAppExceptions.shared.setSourceTracking(true, for: .scrollDirection)
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
            MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
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
        MouseAppExceptions.shared.setSourceTracking(false, for: .scrollDirection)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
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

        if ScrollWheelSupport.isMouseWheel(traits,
                                           secondsSinceLastGesturePhase: secondsSinceGesturePhase),
           !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection,
                at: event.location,
                sourceProcessID: sourceProcessID) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let defaults = UserDefaults.standard
            let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
            let hasHorizontalMovement = horizontalLine != 0
                || horizontalPoint != 0
                || horizontalFixedPoint != 0
            let plan = ScrollWheelSupport.inversionPlan(
                hasVerticalMovement: hasVerticalMovement,
                hasHorizontalMovement: hasHorizontalMovement,
                shiftRedirectsVertical: !traits.isContinuous && event.flags.contains(.maskShift),
                invertVertical: defaults.bool(forKey: DefaultsKey.scrollInverterEnabled),
                invertHorizontal: defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            )
            if plan.vertical {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -verticalLine)
                // AUDIT E-09: high-resolution wheels emit discrete events whose
                // motion lives only in the fixed-point field (line reads 0).
                // Negating the captured fields whenever they are non-zero keeps
                // inversion lossless for those mice too; for events where the
                // line field is actually written, the system still rederives
                // the other fields, so guarding on non-zero avoids doubles.
                if traits.isContinuous || verticalPoint != 0 {
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                }
                if traits.isContinuous || verticalFixedPoint != 0 {
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
                }
            }
            if plan.horizontal {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
                if traits.isContinuous || horizontalPoint != 0 {
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -horizontalPoint)
                }
                if traits.isContinuous || horizontalFixedPoint != 0 {
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -horizontalFixedPoint)
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
