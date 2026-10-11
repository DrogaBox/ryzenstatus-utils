// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import CoreGraphics

/// Turns the mouse wheel's discrete jumps into short glides: a tap swallows
/// each wheel tick and replays its distance as a stream of continuous pixel
/// events that ease out, like a touch device would produce.
///
/// Wheel detection matches the scroll inverter (`ScrollWheelSupport`), so
/// mice whose drivers report the wheel as continuous pixel events (issue
/// #267) glide too; trackpads, Magic Mouse and momentum
/// are passed through untouched. The tap sits at the head
/// so the scroll inverter (appended at the tail) still sees the synthetic
/// stream and can flip it — both features compose. Nothing (tap or timer)
/// exists while the feature is off. Requires Accessibility.
final class SmoothScrollService: ObservableObject {
    static let shared = SmoothScrollService()

    /// True while the event tap is installed.
    @Published private(set) var isRunning = false

    /// Marks the synthetic events so the tap never re-processes its own output.
    private static let syntheticTag: Int64 = 0x564F5253  // "VORS"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var frameTimer: Timer?
    /// Remaining glide distance per axis, in pixels. Touched only on the main
    /// thread (tap callback and timer both live on the main run loop).
    private var remainingVertical: Double = 0
    private var remainingHorizontal: Double = 0
    // Carry forward sub-pixel fractions so low-speed glides
    // and high-resolution wheel ticks never drop distance to frame rounding.
    private var carryVertical: Double = 0
    private var carryHorizontal: Double = 0
    /// Modifiers of the wheel event that started or fed the glide, replayed on
    /// the synthetic events so apps can still react to them.
    private var currentFlags: CGEventFlags = []
    /// Sign correction for the system's natural scroll direction, sampled
    /// when a glide starts or the feeding device type changes.
    private var postSign: Double = 1
    /// Whether the glide is fed by ticks redirected sideways with the
    /// sideways-scrolling key; switching drops the old tail.
    private var currentScrollRedirected = false
    /// Whether the glide is being fed by continuous wheel events; discrete
    /// and continuous sources need different sign handling, so switching
    /// devices mid-glide drops the tail and resamples.
    private var glideFromContinuous = false
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?

    private init() {}

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let wanted = AppFeature.smoothScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.smoothScrollEnabled)
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
            isRunning = true
            return
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<SmoothScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
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
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        stopGlide()
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        // Our own glide stream coming back through the tap.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag else {
            return Unmanaged.passUnretained(event)
        }
        // Touch devices are already smooth; only mouse wheels glide. The
        // classification is shared with the scroll inverter, so mice that
        // report the wheel as continuous events (issue #267) are wheels too.
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
        // The head tap swallows the tick before the inverter's tail tap can
        // reach it, so the direction features (flip and sideways scrolling
        // with a held key) and linear scrolling's cap are applied here,
        // each honoring its own exception list.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let defaults = UserDefaults.standard
        let direction = ScrollDirectionPreferences(defaults: defaults)
        let adjustDirectionHere = direction.isEnabled
            && !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection, at: event.location, sourceProcessID: sourceProcessID)
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        var replayFlags = event.flags
        var redirectSideways = false
        if adjustDirectionHere, let modifier = direction.horizontalModifier,
           event.flags.intersection(shortcutFlags) == modifier.flag,
           ScrollWheelSupport.isVerticalOnly(event) {
            redirectSideways = true
            replayFlags.remove(modifier.flag)
        }
        // Control-scroll drives screen zoom; keep its stepping predictable,
        // unless the sideways-scrolling key is Control and consumed above.
        guard !replayFlags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }
        let linearLinesPerNotch = ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable,
            isExcepted: {
                MouseAppExceptions.shared.excludesPointerTarget(
                    .linearScroll, at: event.location, sourceProcessID: sourceProcessID)
            })

        // A process's own posted events skip its own taps (verified), so the
        // scroll inverter never sees the glide stream: when it is on, the
        // wheel's vertical flip is applied here instead.
        let invert = adjustDirectionHere && direction.invertVertical ? -1.0 : 1.0
        let shiftPressed = replayFlags.contains(.maskShift) || redirectSideways
        let vertical: Double
        let horizontal: Double
        let step: Double
        if traits.isContinuous {
            // The event already measures pixels; the glide replays that same
            // distance, only re-timed, so the step setting does not scale it.
            // No Shift redirect either: the system never translates
            // continuous events, apps react to the replayed Shift flag.
            var rawVertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            var rawHorizontal = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            if let linearLinesPerNotch {
                rawVertical = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.continuousTicks(
                        fixedPointDelta: rawVertical,
                        pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))),
                    linesPerNotch: linearLinesPerNotch) * ScrollWheelSupport.pointsPerLine
                rawHorizontal = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.continuousTicks(
                        fixedPointDelta: rawHorizontal,
                        pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))),
                    linesPerNotch: linearLinesPerNotch) * ScrollWheelSupport.pointsPerLine
            }
            if redirectSideways {
                vertical = 0
                horizontal = rawVertical
            } else {
                vertical = rawVertical * invert
                horizontal = rawHorizontal
            }
            step = 1
        } else {
            // The fixed-point field carries the fractional ticks that
            // high-resolution wheels report while the integer field reads 0.
            let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            var verticalTicks = SmoothScrollSupport.ticks(line: Double(verticalLine),
                                                          fixedPoint: verticalFixedPoint)
            var horizontalTicks = SmoothScrollSupport.ticks(line: Double(horizontalLine),
                                                            fixedPoint: horizontalFixedPoint)
            // Linear scrolling counts notches, not the distance macOS scaled
            // them to, so a slow notch weighs as much as a fast one.
            if let linearLinesPerNotch {
                verticalTicks = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.discreteTicks(
                        line: verticalLine, fixedPoint: verticalFixedPoint,
                        point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                    linesPerNotch: linearLinesPerNotch)
                horizontalTicks = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.discreteTicks(
                        line: horizontalLine, fixedPoint: horizontalFixedPoint,
                        point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                    linesPerNotch: linearLinesPerNotch)
            }
            // A redirected tick travels sideways exactly like a Shift-held one.
            let axes = SmoothScrollSupport.axes(
                vertical: verticalTicks * (redirectSideways ? 1 : invert),
                horizontal: horizontalTicks,
                shiftPressed: shiftPressed
            )
            vertical = axes.vertical
            horizontal = axes.horizontal
            step = Double(SmoothScrollSupport.sanitizedStep(
                defaults.integer(forKey: DefaultsKey.smoothScrollStep)))
        }
        guard vertical != 0 || horizontal != 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Switching Shift while a glide is active changes the intended axis,
        // and switching between a discrete and a continuous wheel changes the
        // sign handling. Drop the old tail instead of fighting it.
        if currentFlags.contains(.maskShift) != replayFlags.contains(.maskShift)
            || currentScrollRedirected != redirectSideways
            || glideFromContinuous != traits.isContinuous {
            remainingVertical = 0
            remainingHorizontal = 0
        }
        remainingVertical = SmoothScrollSupport.remaining(afterTicks: vertical,
                                                          step: step,
                                                          current: remainingVertical)
        remainingHorizontal = SmoothScrollSupport.remaining(afterTicks: horizontal,
                                                            step: step,
                                                            current: remainingHorizontal)
        currentFlags = replayFlags
        currentScrollRedirected = redirectSideways
        if frameTimer == nil || glideFromContinuous != traits.isContinuous {
            // The system applies the natural scroll direction to continuous
            // events only, so a swallowed discrete tick needs the pre-flip
            // while a swallowed continuous event, replayed as the same kind,
            // does not.
            postSign = traits.isContinuous
                ? 1
                : SmoothScrollSupport.postedDelta(1, naturalScrolling: Self.naturalScrollingOn())
        }
        glideFromContinuous = traits.isContinuous
        startGlideIfNeeded()
        // The tick itself is swallowed; the glide replays its distance.
        return nil
    }

    // MARK: - Glide

    private func startGlideIfNeeded() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: SmoothScrollSupport.frameInterval, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        emitFrame()
    }

    private func stopGlide() {
        frameTimer?.invalidate()
        frameTimer = nil
        remainingVertical = 0
        remainingHorizontal = 0
        carryVertical = 0
        carryHorizontal = 0
    }

    private func emitFrame() {
        let rawVertical = SmoothScrollSupport.frameDelta(remaining: remainingVertical)
        let rawHorizontal = SmoothScrollSupport.frameDelta(remaining: remainingHorizontal)
        remainingVertical -= rawVertical
        remainingHorizontal -= rawHorizontal

        let isFinalVertical = remainingVertical == 0
        let isFinalHorizontal = remainingHorizontal == 0

        let postVertical: Double
        if isFinalVertical {
            postVertical = SmoothScrollSupport.finalPixels(rawVertical, carry: carryVertical)
            carryVertical = 0
        } else {
            let split = SmoothScrollSupport.wholePixels(rawVertical, carry: carryVertical)
            postVertical = split.pixels
            carryVertical = split.carry
        }

        let postHorizontal: Double
        if isFinalHorizontal {
            postHorizontal = SmoothScrollSupport.finalPixels(rawHorizontal, carry: carryHorizontal)
            carryHorizontal = 0
        } else {
            let split = SmoothScrollSupport.wholePixels(rawHorizontal, carry: carryHorizontal)
            postHorizontal = split.pixels
            carryHorizontal = split.carry
        }

        if postVertical != 0 || postHorizontal != 0 {
            post(vertical: postVertical, horizontal: postHorizontal)
        }
        if isFinalVertical, isFinalHorizontal {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func post(vertical: Double, horizontal: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: Int32((vertical * postSign).rounded()),
                                  wheel2: Int32((horizontal * postSign).rounded()),
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        event.flags = currentFlags
        event.post(tap: .cghidEventTap)
    }

    /// The user's "natural scrolling" system preference (macOS default: on).
    private static func naturalScrollingOn() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool) ?? true
    }
}
