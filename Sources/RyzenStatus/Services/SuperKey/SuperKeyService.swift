// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import ApplicationServices
import Carbon
import Combine
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// Turns Caps Lock into one key that holds Shift, Control, Option and Command
/// together, so shortcuts built on it collide with nothing else.
///
/// Two halves make it work. The keyboard mapping table turns Caps Lock into
/// F18, because a lock key never reports going down and up and so can never be
/// held; the event tap then keeps that key to itself and adds the four
/// modifiers to whatever is pressed while it is down. Nothing is installed
/// while the feature is off, and the mapping is always taken back out, both
/// when the feature goes off and when the app quits. Requires Accessibility:
/// without it the tap cannot modify events, and the mapping is not applied
/// either, so Caps Lock is never left as a key that does nothing.
final class SuperKeyService: ObservableObject {
    static let shared = SuperKeyService()

    /// True while the key is actually working: tap up and mapping applied.
    @Published private(set) var isRunning = false

    /// Read by the shortcut recording tap, which sits ahead of this one while a
    /// field is listening and would otherwise see the bare trigger key instead
    /// of the combination it stands for. Written and read on the main thread.
    private(set) static var isEngaged = false

    /// A held gesture can follow this virtual modifier. True means the key was
    /// released; false means the hold was cancelled by teardown or recovery.
    var onHoldEnded: ((_ released: Bool) -> Void)?
    var isHeld: Bool { stateLock.withLock { state.isHeld } }

    private let hidutilPath = "/usr/bin/hidutil"
    /// Matches every keyboard, including one plugged in later.
    private let keyboardMatch = "keyboard"

    private static let mouseDownTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    private static let mouseEventsMask: CGEventMask = mouseDownTypes.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    // The active tap must answer every key before the window server can deliver
    // it. A user-interactive run loop keeps that answer independent from UI,
    // window enumeration and every other main-thread task.
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var mouseTap: CFMachPort?
    private var mouseTapRefusals = 0
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false
    private let stateLock = NSLock()
    private var state = SuperKeySupport.State()
    private var soloAction: SuperKeySoloAction = .none
    private var wakeObserver: NSObjectProtocol?
    /// The mapping is written off the main thread, and in the order it was
    /// asked for: a queue of one keeps an apply and a clear from crossing.
    private let mappingQueue = DispatchQueue(label: "com.ryzenstatus.utils.superkey-mapping")
    /// When the last mapping went in, so a keyboard that arrives without one
    /// is repaired once and not on every keystroke.
    private var lastMappingAt: TimeInterval = 0
    private let mappingRepairInterval: TimeInterval = 3
    /// Lets go of a press whose release never arrived. Without it the four
    /// modifiers would ride every keystroke from then on, with no way back but
    /// pressing the key again, and typing would be dead in the meantime.
    private var heldKeyWatchdog: DispatchWorkItem?
    /// How long the press may go without a repeat before it is let go. A key
    /// really held repeats, so this is pushed out again and again and never
    /// runs; it only decides how long a press whose release was lost can hold
    /// the modifiers down. Taken from the keyboard's own first-repeat delay, so
    /// a slow setting is never fought, and bounded at both ends: never so short
    /// that a hold is cut off, never so long that the keyboard stays unusable
    /// when repeat is switched off and no repeat is ever coming.
    private var heldKeyTimeout: TimeInterval {
        let firstRepeat = NSEvent.keyRepeatDelay
        guard firstRepeat.isFinite, firstRepeat > 0 else { return 3 }
        return min(30, max(3, firstRepeat * 2))
    }

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let action = SuperKeySoloAction.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySoloAction)
        )
        stateLock.withLock { soloAction = action }
        let enabled = AppFeature.superKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.superKeyEnabled)
        guard enabled else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and granted again)
        // never revives on its own; rebuild it instead of keeping the corpse.
        if let tap = lifecycleLock.withLock({ tap }), !CGEvent.tapIsEnabled(tap: tap) {
            stop()
        }
        start()
    }

    /// Quitting takes the mapping out on the spot: the process is about to go
    /// away, and a mapping left behind would leave Caps Lock doing nothing.
    func suspend() {
        stop(synchronously: true)
    }

    private func start() {
        let tapExists = lifecycleLock.withLock { tap != nil && !shouldStopTapThread }
        guard !tapExists else { return }
        // Without Accessibility the tap cannot add the modifiers, and a
        // mapping alone would turn Caps Lock into a dead key. One left by a
        // run that was killed comes out here too: with the feature still
        // enabled, the launch-time stop() that normally clears it never runs.
        guard AXIsProcessTrusted() else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        forgetHeldKey()
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "RyzenStatus Super Key"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop(synchronously: Bool = false) {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        forgetHeldKey()
        Self.isEngaged = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        clearLeftoverMapping(synchronously: synchronously)
        isRunning = false
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let stillStopped = self.lifecycleLock.withLock {
                        self.tap == nil && self.tapThread == nil
                    }
                    guard stillStopped else { return }
                    self.clearLeftoverMapping()
                    self.isRunning = false
                    Self.isEngaged = false
                }
                return
            }

            let mouseTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.mouseEventsMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            var mouseSource: CFRunLoopSource?
            lifecycleLock.withLock {
                self.mouseTap = mouseTap
                self.mouseTapRefusals = mouseTap == nil ? self.mouseTapRefusals + 1 : 0
            }
            if let mouseTap {
                mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
                CFRunLoopAddSource(runLoop, mouseSource, .commonModes)
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: false)
                if let mouseSource { CFRunLoopRemoveSource(runLoop, mouseSource, .commonModes) }
                CFMachPortInvalidate(mouseTap)
            }
            if clearEventTapThread() { startOnMain() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            mouseTap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = lifecycleLock.withLock {
            tap === startedTap && !shouldStopTapThread
        }
        guard active else { return }
        applyMapping(true)
        // Caps Lock left on would have no way back once the key stops locking.
        setCapsLock(false)
        observeWake()
        isRunning = true
        Self.isEngaged = true
    }

    /// The mapping is cleared even when this service never applied it: an
    /// app that was killed while the feature was on leaves one behind, and
    /// every path that ends without a live tap takes it out, so Caps Lock is
    /// never left as a key that does nothing.
    private func clearLeftoverMapping(synchronously: Bool = false) {
        if UserDefaults.standard.bool(forKey: DefaultsKey.superKeyMappingApplied) {
            applyMapping(false, synchronously: synchronously)
        }
    }

    /// Sleep can bring the keyboard back without the mapping, and so can
    /// plugging in another one. Waking is the cheap moment to put it back.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  self.lifecycleLock.withLock({ self.tap != nil && !self.shouldStopTapThread })
            else { return }
            self.applyMapping(true)
        }
    }

    // MARK: - The key mapping

    private func applyMapping(_ enabled: Bool, synchronously: Bool = false) {
        stateLock.withLock {
            lastMappingAt = ProcessInfo.processInfo.systemUptime
        }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.superKeyMappingApplied)
        let work = { [hidutilPath, keyboardMatch] in
            let includeNoAction: Bool
            if enabled {
                let modifierReport = Shell.run(
                    hidutilPath,
                    ["property", "--matching", keyboardMatch,
                     "--get", "HIDKeyboardModifierMappingPairs"]
                )
                includeNoAction = SuperKeySupport.canMapNoAction(
                    from: SuperKeySupport.parseMappings(modifierReport.output)
                )
            } else {
                includeNoAction = false
            }
            let report = Shell.run(hidutilPath,
                                   ["property", "--matching", keyboardMatch, "--get", "UserKeyMapping"])
            let existing = SuperKeySupport.parseMappings(report.output)
            let wanted = SuperKeySupport.mappings(
                enablingSuperKey: enabled,
                existing: existing,
                includeNoAction: includeNoAction
            )
            Shell.run(hidutilPath,
                      ["property", "--matching", keyboardMatch,
                       "--set", SuperKeySupport.mappingArgument(wanted)])
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    /// A keyboard that arrives after the mapping was applied still locks; the
    /// first press on it is the signal to map it too. Repaired at most once
    /// every few seconds, so a keyboard that refuses the mapping cannot turn
    /// typing into a stream of commands.
    private func repairMappingIfStale() {
        lifecycleLock.withLock {
            guard tap != nil, !shouldStopTapThread else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let shouldRepair = stateLock.withLock {
                now - lastMappingAt >= mappingRepairInterval
            }
            if shouldRepair { applyMapping(true) }
        }
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTaps = lifecycleLock.withLock {
                shouldStopTapThread ? (nil, nil) : (tap, mouseTap)
            }
            if let currentTap = currentTaps.0 { CGEvent.tapEnable(tap: currentTap, enable: true) }
            if let currentMouseTap = currentTaps.1 { CGEvent.tapEnable(tap: currentMouseTap, enable: true) }
            forgetHeldKey()
            return Unmanaged.passUnretained(event)
        }
        let event0 = SuperKeyService.classify(type: type, event: event)
        let decision = stateLock.withLock { state.decide(event0) }
        // Only the key's own events say it is still down: the first press and
        // the repeats the system sends while it is held. Keys pressed meanwhile
        // must NOT push the deadline out. Someone whose keyboard is stuck under
        // a press that never lifted is typing, and letting that typing hold the
        // deadline open would keep it stuck for exactly as long as they kept
        // trying to get out of it.
        switch event0 {
        case .triggerDown:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      }),
                      self.stateLock.withLock({ self.state.isHeld })
                else { return }
                self.armHeldKeyWatchdog()
            }
        case .triggerUp:
            DispatchQueue.main.async { [weak self] in
                self?.cancelHeldKeyWatchdog()
                self?.onHoldEnded?(true)
            }
        case .otherKey, .otherModifier, .capsLock:
            break
        }
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .addModifiers:
            event.flags = event.flags.union(SuperKeyService.superFlags)
            return Unmanaged.passUnretained(event)
        case .soloTap:
            DispatchQueue.main.async { [weak self] in self?.performSoloAction() }
            return nil
        case .remapNeeded:
            repairMappingIfStale()
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - A press whose release never came

    private func armHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.forgetHeldKey() }
        heldKeyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + heldKeyTimeout, execute: work)
    }

    private func cancelHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        heldKeyWatchdog = nil
    }

    /// Back to the key being up. State resets synchronously; UI callbacks stay
    /// on the main thread.
    private func forgetHeldKey() {
        let wasHeld = stateLock.withLock { () -> Bool in
            let held = state.isHeld
            state.reset()
            return held
        }
        let notify = { [weak self] in
            self?.cancelHeldKeyWatchdog()
            if wasHeld { self?.onHoldEnded?(false) }
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    private static func classify(type: CGEventType, event: CGEvent) -> SuperKeySupport.Event {
        if mouseDownTypes.contains(type) { return .otherKey }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            return keyCode == SuperKeySupport.capsLockKeyCode ? .capsLock : .otherModifier
        }
        guard keyCode == SuperKeySupport.triggerKeyCode else { return .otherKey }
        if type == .keyDown {
            return .triggerDown(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        }
        return .triggerUp
    }

    private static let superFlags: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]

    // MARK: - Tapped on its own

    private func performSoloAction() {
        let action = stateLock.withLock { soloAction }
        switch action {
        case .none:
            return
        case .escape:
            runOnMainIfNeeded { self.postEscape() }
        case .capsLock:
            runOnMainIfNeeded { self.setCapsLock(!self.capsLockIsOn()) }
        case .inputSource:
            // Must finish before this tap returns: the next keystroke is already
            // in flight, and hopping to main (or waiting on Accessibility) left
            // that character in the old source.
            Self.selectNextInputSource()
        }
    }

    private func runOnMainIfNeeded(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else { return }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// Cycle enabled keyboard sources through TIS before the tap lets the next
    /// key through. Selecting the next source directly lets the input method
    /// commit or cancel on its own, the same way the Input menu does.
    private static func selectNextInputSource() {
        let apply = {
            let sources = selectableInputSources()
            let ids = sources.compactMap { inputSourceString($0, property: kTISPropertyInputSourceID) }
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
            let currentID = inputSourceString(current, property: kTISPropertyInputSourceID)
            guard let nextID = SuperKeySupport.nextInputSourceID(currentID: currentID,
                                                                 enabledIDs: ids),
                  let next = sources.first(where: {
                      inputSourceString($0, property: kTISPropertyInputSourceID) == nextID
                  })
            else { return }
            _ = TISSelectInputSource(next)
        }
        // TIS talks to the text-input server from the main thread. sync (not
        // async) keeps the switch ahead of the next keystroke this tap is
        // about to let through.
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    private static func selectableInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            inputSourceString($0, property: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && inputSourceBool($0, property: kTISPropertyInputSourceIsSelectCapable)
        }
    }

    private static func inputSourceString(_ source: TISInputSource,
                                          property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func inputSourceBool(_ source: TISInputSource,
                                        property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }


    // MARK: - Caps Lock itself

    /// The lock state lives with the system's own keyboard service, which is
    /// also what lights the key.
    private func withHIDSystem<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    private func capsLockIsOn() -> Bool {
        withHIDSystem { connection in
            var state = false
            guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS
            else { return nil }
            return state
        } ?? false
    }

    private func setCapsLock(_ on: Bool) {
        _ = withHIDSystem { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), on)
        }
    }
}
