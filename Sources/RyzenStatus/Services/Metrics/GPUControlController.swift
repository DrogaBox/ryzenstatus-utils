// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// What the app asks GPUSensors.kext to hold.
enum GPUControlRequest: Equatable, Hashable, Sendable {
    /// A lower power limit in watts.
    case power(watts: UInt32)
    /// The whole OD8 state: fan curve, zero RPM and GFX maximum together.
    case od8(GPUControlOD8Want)
    /// Back to the start-up values: `release`, never a change.
    case startUp

    /// The stock OD8 state is the way back too.
    var normalized: GPUControlRequest {
        if case .od8(let want) = self, want.isStock { return .startUp }
        return self
    }

    var isPower: Bool { if case .power = self { return true } else { return false } }
    var isOD8: Bool { if case .od8 = self { return true } else { return false } }
}

/// Why the controller makes no more calls until the app starts again.
enum GPUControlStop: Equatable, Sendable {
    /// No channel was given: the controller cannot open anything.
    case noChannel
    case noService
    case openRefused(Int32)
    /// A call failed: the connection is closed, and the kext went back.
    case connectionFailed
    /// The kext speaks this version of the channel, the app version 2.
    case otherVersion(UInt64)
    /// Writing is off until restart (`GPUControlWriteOff`).
    case writingOff(UInt64)
    case shutDown
}

/// What made a request wait before it is tried again.
enum GPUControlWait: Equatable, Sendable {
    case reply(GPUControlReply)
    /// `status` without ready.
    case notReady
    case sleeping
    /// A way back runs, or a change of the other kind is going back.
    case reverting
}

/// Something the app tells the owner about even without the page open
/// (plan section 6: a failure or the watchdog while the app held a change).
enum GPUControlNotice: Equatable, Sendable {
    case writingOff(GPUControlWriteOff?)
}

/// "Close changes" (`disarm`, kext 0.8.0): where it stands. The app first
/// gives back what it holds and waits for the way back, then asks once.
enum GPUControlClosing: Equatable, Sendable {
    /// Going back to the start-up values first, or about to ask.
    case waiting
    /// Closed: `arm` is needed again (also when it was closed already).
    case closed
    /// The kext said no; `stillApplied` while another program holds a change.
    case refused(GPUControlAnswer)
    /// A 0.7.x kext: it has no `disarm`; restarting the Mac closes writing.
    case notSupported
}

/// Where a request came from. A remembered one (phase 2: after launch and
/// after a wake) never replaces a choice the owner made.
enum GPUControlOrigin: Equatable, Sendable {
    case owner
    case remembered
}

/// What the controller knows, for the page. `held` comes from `status`
/// (mine, and the values match), never from what was asked.
struct GPUControlSnapshot: Equatable, Sendable {
    enum Activity: Equatable, Sendable {
        case none
        /// The call is out; the control waits for its answer.
        case applying(GPUControlRequest)
        case retrying(GPUControlRequest, GPUControlWait)
        /// The change of the other kind goes back first.
        case switching(GPUControlRequest)
        /// After a wake: the kext goes back on its own first.
        case afterWake(GPUControlRequest)
    }

    enum Outcome: Equatable, Sendable {
        /// The kext refused; nothing is held for this request.
        case refused(GPUControlRequest, GPUControlAnswer)
        /// Still not taken after a minute of tries.
        case gaveUp(GPUControlRequest, GPUControlWait)
        /// Not sent: writing is not opened since the restart.
        case closed
        /// Not sent: another program holds the control.
        case otherProgram
        /// Not sent: OD8 was not read cleanly since boot.
        case od8NotRead
        /// No answer in 5 s: the app released, as `gpucontrol` does.
        case timedOut
        /// The kext answered "ok" but `status` did not show it: released.
        case notConfirmed
        /// The kext went back without being asked (30 s without a word, or
        /// it says this program holds nothing).
        case lost
        /// The Mac woke: the kext goes back to the start-up values.
        case backAfterWake
        /// Asked for the start-up values (or the start-up limit): released,
        /// and `status` no longer names this program.
        case backToStartUp
        /// Asked for the start-up values (or the start-up limit) with nothing
        /// held and no other program holding: nothing to give back.
        case alreadyAtStartUp
    }

    var status: GPUControlChannelStatus?
    var held: GPUControlRequest?
    var activity: Activity = .none
    var outcome: Outcome?
    var stopped: GPUControlStop?
    /// The last "close changes", nil until one is asked for (and again after
    /// a new choice).
    var closing: GPUControlClosing?
}

/// The rules of plan section 6, without threads: every call goes through
/// the one channel it was given, on the caller's thread. Times come from
/// `clock` (milliseconds, monotonic), so a test drives it with the fake
/// kext's clock. `GPUControlController` runs it on its own queue.
final class GPUControlEngine {
    /// `alive` and `status` while something is held; also the spacing of
    /// tries for a request that has to wait.
    static let pollMs: UInt64 = 5_000
    /// While a change of the other kind goes back: `status` once a second.
    static let switchPollMs: UInt64 = 1_000
    /// A request that has to wait is tried for this long, then given up.
    static let retryWindowMs: UInt64 = 60_000
    /// After a wake the kext goes back 2 to 12 s later; `mine` is not trusted
    /// and nothing is asked until this much has passed.
    static let wakeSettleMs: UInt64 = 15_000

    private let channel: GPUControlChannel?
    private let clock: () -> UInt64
    /// True once the app quits: no call is made from then on.
    private let isShutDown: () -> Bool

    /// Called on every change, on the engine's thread.
    var onSnapshot: ((GPUControlSnapshot) -> Void)?
    var onNotice: ((GPUControlNotice) -> Void)?
    /// After a wake, ask again for what was held (D4, phase 2; off by
    /// default like the setting).
    var reaskAfterWake = false

    private(set) var snapshot = GPUControlSnapshot() {
        didSet { if snapshot != oldValue { onSnapshot?(snapshot) } }
    }

    private var opened = false
    /// The latest request not sent yet; a newer one replaces it.
    private var wanted: GPUControlRequest?
    private var wantedOrigin: GPUControlOrigin = .owner
    private var wantedSince: UInt64 = 0
    private var nextTryAt: UInt64 = 0
    private var nextPollAt: UInt64 = 0
    private var statusRequested = false
    /// When this program last made a call that writes (set, setOD8, release).
    private var lastWriteAt: UInt64?
    /// Released the other kind of change: wait for `status` to be quiet.
    private var switching = false
    /// A way back or someone else's change was seen; nothing is asked until
    /// `status` was quiet for 2 s (the way back counts as a write).
    private var sawBusy = false
    private var quietSince: UInt64?
    private var wokeAt: UInt64?
    /// "Close changes" asked for and not answered yet.
    private var closeWanted = false
    private var closeSince: UInt64 = 0

    init(channel: GPUControlChannel?, clock: @escaping () -> UInt64, isShutDown: @escaping () -> Bool = { false }) {
        self.channel = channel
        self.clock = clock
        self.isShutDown = isShutDown
        if channel == nil { snapshot.stopped = .noChannel }
    }

    /// The connection was opened (the app gives it back when it quits).
    private(set) var hasOpened = false

    /// True while something is held or about to be: `alive` must not be late
    /// (App Nap).
    var needsTimelyCalls: Bool {
        snapshot.stopped == nil && (snapshot.held != nil || wanted != nil || closeWanted)
    }

    // MARK: Inputs

    /// The owner chose something, or phase 2 asks for a remembered setting.
    func choose(_ request: GPUControlRequest, origin: GPUControlOrigin = .owner) {
        guard snapshot.stopped == nil else { return }
        if origin == .remembered, wanted != nil, wantedOrigin == .owner { return }
        let request = request.normalized
        let now = clock()
        if wanted == nil, request == snapshot.held, snapshot.activity == .none {
            // Already held: no refusal of an older request stays on screen.
            snapshot.outcome = nil
            return
        }
        // A choice after "close changes" replaces it.
        closeWanted = false
        snapshot.closing = nil
        wanted = request
        wantedOrigin = origin
        wantedSince = now
        nextTryAt = Swift.max(now, wokeAt.map { $0 + Self.wakeSettleMs } ?? 0)
        snapshot.outcome = nil
    }

    /// The whole OD8 state with the GFX maximum changed: the curve and zero
    /// RPM that are held or asked for go with it.
    func chooseGfxMax(_ mhz: Int?) {
        var want = od8Basis
        want.gfxMaxMHz = mhz
        choose(.od8(want))
    }

    /// The whole OD8 state with the fan changed: the GFX maximum that is held
    /// or asked for goes with it.
    func chooseFan(curve: [GPUControlFanPoint]?, zeroRpmOff: Bool) {
        var want = od8Basis
        want.curve = curve
        want.zeroRpmOff = zeroRpmOff
        choose(.od8(want))
    }

    /// The OD8 state a fan or clock change starts from: the one asked for,
    /// else the one held, else stock.
    var od8Basis: GPUControlOD8Want {
        if case .od8(let want)? = wanted { return want }
        if wanted == nil, case .od8(let want)? = snapshot.held { return want }
        return .stock
    }

    /// "Close changes" (kext 0.8.0): give back what this app holds, wait for
    /// the way back, then `disarm` once. No password: anyone may close, and
    /// the kext refuses while anything is applied. A request not sent yet is
    /// dropped: closing is the opposite of asking for something.
    func close() {
        guard snapshot.stopped == nil else { return }
        wanted = nil
        switching = false
        snapshot.activity = .none
        snapshot.outcome = nil
        closeWanted = true
        closeSince = clock()
        nextTryAt = clock()
        snapshot.closing = .waiting
    }

    /// Read `status` at the next step (the page opened).
    func refresh() {
        guard snapshot.stopped == nil else { return }
        statusRequested = true
    }

    /// `NSWorkspace.didWakeNotification`. The kext forgot the owner when the
    /// Mac slept and goes back on its own after the wake.
    func didWake() {
        guard snapshot.stopped == nil else { return }
        backAfterWake(held: snapshot.held)
    }

    /// The kext forgot the owner over a sleep (the wake notice, or `status`
    /// still between sleep and wake while the hold went away).
    private func backAfterWake(held: GPUControlRequest?) {
        let now = clock()
        wokeAt = now
        if let held {
            snapshot.held = nil
            snapshot.outcome = .backAfterWake
            if reaskAfterWake, wanted == nil {
                wanted = held
                wantedOrigin = .remembered
                wantedSince = now
            }
        }
        if wanted != nil {
            nextTryAt = Swift.max(nextTryAt, now + Self.wakeSettleMs)
            if let wanted { snapshot.activity = .afterWake(wanted) }
        }
    }

    /// The app quits: give back what is held and close. `release` answers at
    /// once; the kext goes back on its own when the connection closes anyway.
    func shutdown(callingChannel: Bool = true) {
        if callingChannel, opened, let channel {
            _ = channel.release()
            channel.close()
        }
        opened = false
        wanted = nil
        snapshot.held = nil
        snapshot.activity = .none
        if snapshot.stopped == nil { snapshot.stopped = .shutDown }
    }

    // MARK: The step

    /// Does what is due now. Returns when to step again (the clock's
    /// milliseconds), nil when only an input can start something.
    @discardableResult
    func step() -> UInt64? {
        guard snapshot.stopped == nil else { return nil }
        guard isShutDown() == false else { return stop(.shutDown, close: false) }
        let busy = wanted != nil || snapshot.held != nil || statusRequested || closeWanted
        guard busy else { return nil }
        guard openIfNeeded() else { return nil }
        if statusRequested {
            statusRequested = false
            guard readStatus() != nil else { return nil }
        }
        if snapshot.held != nil, clock() >= nextPollAt {
            guard keepHolding() else { return snapshot.stopped == nil ? nextDue() : nil }
        }
        if closeWanted, clock() >= nextTryAt {
            attemptClose()
        } else if let request = wanted, clock() >= nextTryAt {
            attempt(request)
        }
        return snapshot.stopped == nil ? nextDue() : nil
    }

    private func nextDue() -> UInt64? {
        var due: [UInt64] = []
        if snapshot.held != nil { due.append(nextPollAt) }
        if wanted != nil || closeWanted { due.append(nextTryAt) }
        return due.min()
    }

    private func openIfNeeded() -> Bool {
        if opened { return true }
        guard let channel else {
            stop(.noChannel, close: false)
            return false
        }
        switch channel.open() {
        case .open:
            opened = true
            hasOpened = true
            return true
        case .noService:
            stop(.noService, close: false)
        case .refused(let code):
            stop(.openRefused(code), close: false)
        case .closed:
            stop(.shutDown, close: false)
        }
        return false
    }

    /// Every 5 s while something is held: the owner's word, then `status`.
    /// False when the hold is gone.
    private func keepHolding() -> Bool {
        guard let channel, !isShutDown() else { return false }
        nextPollAt = clock() + Self.pollMs
        guard let alive = channel.alive() else {
            stop(.connectionFailed, close: true)
            return false
        }
        if alive.reply == .notOwner {
            // `status` first: off, or between sleep and wake, says why.
            guard readStatus() != nil else { return false }
            if snapshot.held != nil {
                // The kext still names this connection until its worker
                // takes the hold back: give it back now, the safe side.
                _ = channel.release()
                lastWriteAt = clock()
                lose()
            }
            return false
        }
        guard readStatus() != nil else { return false }
        return snapshot.held != nil
    }

    private func lose() {
        snapshot.held = nil
        snapshot.outcome = .lost
    }

    // MARK: Status

    /// Reads `status` and acts on what it shows: writing off stops the
    /// control, a hold that is not this connection's any more is lost, and a
    /// hold the app did not expect is given back. Nil when the control
    /// stopped.
    @discardableResult
    private func readStatus(confirming: Bool = false) -> GPUControlChannelStatus? {
        guard let channel, !isShutDown() else { return nil }
        guard let status = channel.status() else {
            stop(.connectionFailed, close: true)
            return nil
        }
        guard status.reply == .ok else {
            snapshot.status = status
            stop(status.reply == .badVersion ? .otherVersion(status.version) : .connectionFailed, close: true)
            return nil
        }
        snapshot.status = status
        let now = clock()
        if status.flags.contains(.reverting) || (status.flags.contains(.changed) && !status.flags.contains(.mine)) {
            sawBusy = true
            quietSince = nil
        } else if sawBusy, quietSince == nil {
            quietSince = now
        }
        if status.flags.contains(.off) {
            let held = snapshot.held != nil || confirming
            snapshot.held = nil
            if held { onNotice?(.writingOff(status.writeOff)) }
            stop(.writingOff(status.writeOffCode), close: false)
            return nil
        }
        if confirming { return status }
        if let held = snapshot.held {
            if !status.flags.contains(.mine) {
                if status.flags.contains(.sleeping) { backAfterWake(held: held) } else { lose() }
            } else if !Self.matches(held, status) {
                // Mine, but not what the app holds: give it back.
                _ = channel.release()
                lastWriteAt = now
                lose()
            }
        } else if status.flags.contains(.mine) {
            // A hold the app does not know of (after a wake, the kext may
            // still name this connection for a moment): the safe side.
            _ = channel.release()
            lastWriteAt = now
        }
        return status
    }

    /// The kext's `bootValuePlausible`: a start-up limit it takes as read
    /// (a check of the read, not the floor for requests).
    static func bootBelievable(_ bootW: UInt64) -> Bool {
        bootW >= UInt64(GPUControlWire.minBootW) && bootW <= UInt64(GPUControlWire.maxBootW)
    }

    /// What `status` shows is the request.
    static func matches(_ request: GPUControlRequest, _ status: GPUControlChannelStatus) -> Bool {
        switch request {
        case .power(let watts): return status.heldW == UInt64(watts) && !status.holdsOD8
        case .od8(let want): return status.od8Held == want.heldFlags && !status.holdsPower
        case .startUp: return !status.holdsPower && !status.holdsOD8
        }
    }

    // MARK: Asking

    private func attempt(_ request: GPUControlRequest) {
        guard let channel, let status = readStatus() else { return }
        let now = clock()
        // The kext takes `set` at the start-up limit as the way back
        // (`routeSet`: release, never a change), so `status` would never
        // show it as mine: ask for it as the way back, whoever asked.
        // Only with a start-up limit the kext believes (`checkPower`'s
        // `bootValuePlausible`, the same range). Without one (`bootW` 0: never
        // read; or outside the range) the kext routes no `set` to the way
        // back: it refuses `arm` and every `set` with "no start-up value" and
        // never shows `ready`, so the request ends as `closed` (nothing to
        // compare with, nothing held), never as `notConfirmed`.
        var request = request
        if case .power(let watts) = request, Self.bootBelievable(status.bootW), UInt64(watts) == status.bootW {
            request = .startUp
        }
        if request == .startUp {
            if snapshot.held != nil || status.flags.contains(.mine) {
                _ = channel.release()
                lastWriteAt = now
                snapshot.held = nil
                // Confirmed once `status` no longer names this program; the
                // kext's way back itself may still be running.
                if let after = readStatus(), !after.flags.contains(.mine) {
                    snapshot.outcome = .backToStartUp
                }
            } else if status.flags.contains(.owned) {
                snapshot.outcome = .otherProgram
            } else if wantedOrigin == .owner {
                // Nothing to give back: say so to the owner, who asked.
                snapshot.outcome = .alreadyAtStartUp
            }
            finishRequest()
            return
        }
        if request == snapshot.held, status.flags.contains(.mine) {
            finishRequest()
            return
        }
        if !status.flags.contains(.armed) { return notSent(.closed) }
        if status.flags.contains(.owned), !status.flags.contains(.mine) { return notSent(.otherProgram) }
        if request.isOD8, !status.flags.contains(.od8Ready) { return notSent(.od8NotRead) }
        if let wokeAt, now < wokeAt + Self.wakeSettleMs {
            nextTryAt = wokeAt + Self.wakeSettleMs
            snapshot.activity = .afterWake(request)
            return
        }
        if !status.flags.contains(.ready) { return wait(request, .notReady, every: Self.pollMs) }
        if status.flags.contains(.sleeping) { return wait(request, .sleeping, every: Self.pollMs) }
        // The kext never holds a power and an OD8 change together: the other
        // kind goes back first.
        let otherKind = request.isPower ? status.holdsOD8 : status.holdsPower
        if otherKind, status.flags.contains(.mine) {
            _ = channel.release()
            lastWriteAt = now
            snapshot.held = nil
            switching = true
            sawBusy = true
            quietSince = nil
            snapshot.activity = .switching(request)
            nextTryAt = now + Self.switchPollMs
            return
        }
        if status.flags.contains(.reverting) || otherKind || (status.flags.contains(.changed) && !status.flags.contains(.mine)) {
            if switching {
                snapshot.activity = .switching(request)
                nextTryAt = now + Self.switchPollMs
                return
            }
            return wait(request, .reverting, every: Self.switchPollMs)
        }
        // 2 s after the way back was seen to end, and after this program's
        // own last write.
        if sawBusy {
            let quiet = quietSince ?? now
            if now < quiet + GPUControlWire.minChangeGapMs {
                nextTryAt = quiet + GPUControlWire.minChangeGapMs
                return
            }
        }
        if let lastWriteAt, now < lastWriteAt + GPUControlWire.minChangeGapMs {
            nextTryAt = lastWriteAt + GPUControlWire.minChangeGapMs
            return
        }
        send(request)
    }

    private func send(_ request: GPUControlRequest) {
        guard let channel, !isShutDown() else { return }
        snapshot.activity = .applying(request)
        lastWriteAt = clock()
        sawBusy = false
        quietSince = nil
        let answer: GPUControlAnswer?
        switch request {
        case .power(let watts): answer = channel.setPower(watts: watts)
        case .od8(let want):
            guard want.scalars() != nil else {
                refuse(request, GPUControlAnswer(replyCode: GPUControlReply.badArgs.rawValue))
                return
            }
            answer = channel.setOD8(want)
        case .startUp: return
        }
        guard let answer else {
            stop(.connectionFailed, close: true)
            return
        }
        switching = false
        guard let reply = answer.reply else {
            refuse(request, answer)
            return
        }
        switch reply {
        case .ok:
            guard let status = readStatus(confirming: true) else { return }
            if status.flags.contains(.mine), Self.matches(request, status) {
                snapshot.held = request
                snapshot.outcome = nil
                nextPollAt = clock() + Self.pollMs
            } else {
                if status.flags.contains(.mine) {
                    _ = channel.release()
                    lastWriteAt = clock()
                }
                snapshot.held = nil
                snapshot.outcome = .notConfirmed
            }
            finishRequest()
        case .sleeping, .notReady, .tooSoon:
            wait(request, .reply(reply), every: Self.pollMs)
        case .busy:
            guard let status = readStatus() else { return }
            if status.flags.contains(.owned), !status.flags.contains(.mine) {
                notSent(.otherProgram)
            } else {
                wait(request, .reply(reply), every: Self.pollMs)
            }
        case .timeout:
            // The kext gave back what this program held; say so to it too.
            _ = channel.release()
            lastWriteAt = clock()
            snapshot.held = nil
            snapshot.outcome = .timedOut
            finishRequest()
            _ = readStatus()
        case .failed, .off:
            // "failed": the app's own change was not confirmed; the kext went
            // back and turned writing off. "off" while a set waited: writing
            // went off under it, which the owner hears about if the app held
            // something (the notice comes with the status).
            let wasHeld = snapshot.held != nil
            snapshot.held = nil
            if readStatus(confirming: reply == .failed || wasHeld) != nil {
                // `status` did not say off: stop all the same.
                if reply == .failed || wasHeld { onNotice?(.writingOff(snapshot.status?.writeOff)) }
                stop(.writingOff(snapshot.status?.writeOffCode ?? 0), close: false)
            }
        case .badVersion:
            _ = readStatus()
            if snapshot.stopped == nil { stop(.otherVersion(snapshot.status?.version ?? 0), close: true) }
        case .notArmed:
            notSent(.closed)
        default:
            refuse(request, answer)
        }
    }

    // MARK: Closing (kext 0.8.0)

    /// One step of "close changes": the app's own hold goes back first; the
    /// way back gets up to `retryWindowMs` to finish; then `disarm`, once.
    /// Another program's hold does not go away by waiting: the kext's
    /// `stillApplied` says so at once.
    private func attemptClose() {
        guard let channel, let status = readStatus() else {
            closeWanted = false
            return
        }
        let now = clock()
        if !status.flags.contains(.armed) {
            closeWanted = false
            snapshot.closing = .closed
            return
        }
        if snapshot.held != nil || status.flags.contains(.mine) {
            _ = channel.release()
            lastWriteAt = now
            snapshot.held = nil
            nextTryAt = now + Self.switchPollMs
            return
        }
        let ownWayBack = status.flags.contains(.reverting)
            || (status.flags.contains(.changed) && !status.flags.contains(.owned))
        if ownWayBack, now < closeSince + Self.retryWindowMs {
            nextTryAt = now + Self.switchPollMs
            return
        }
        closeWanted = false
        guard let answer = channel.disarm() else {
            // A 0.7.x kext does not know the selector; the connection is fine.
            snapshot.closing = .notSupported
            return
        }
        switch answer.reply {
        case .ok?:
            snapshot.closing = .closed
            _ = readStatus()
        case .badVersion?:
            snapshot.closing = .refused(answer)
            _ = readStatus()
            if snapshot.stopped == nil { stop(.otherVersion(snapshot.status?.version ?? 0), close: true) }
        default:
            snapshot.closing = .refused(answer)
            _ = readStatus()
        }
    }

    private func wait(_ request: GPUControlRequest, _ why: GPUControlWait, every ms: UInt64) {
        let now = clock()
        if now >= wantedSince + Self.retryWindowMs {
            snapshot.outcome = .gaveUp(request, why)
            finishRequest()
            return
        }
        snapshot.activity = .retrying(request, why)
        nextTryAt = now + ms
    }

    private func refuse(_ request: GPUControlRequest, _ answer: GPUControlAnswer) {
        snapshot.outcome = .refused(request, answer)
        finishRequest()
    }

    private func notSent(_ outcome: GPUControlSnapshot.Outcome) {
        snapshot.outcome = outcome
        finishRequest()
    }

    private func finishRequest() {
        wanted = nil
        switching = false
        wokeAt = nil
        snapshot.activity = .none
    }

    @discardableResult
    private func stop(_ why: GPUControlStop, close: Bool) -> UInt64? {
        if close, opened { channel?.close() }
        if close { opened = false }
        wanted = nil
        closeWanted = false
        snapshot.held = nil
        snapshot.activity = .none
        snapshot.stopped = why
        return nil
    }
}

/// The GPU control's owner in the app: one engine, one connection, one
/// serial queue. Nothing creates one with a real channel yet (phase 2 does,
/// once, at launch); without a channel it cannot open anything.
final class GPUControlController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ryzenstatus.gpu-control", qos: .userInitiated)
    private let channel: GPUControlChannel?
    private let gate = Gate()
    private var engine: GPUControlEngine!
    private var timer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var started = false
    private let snapshotLock = NSLock()
    private var lastSnapshot = GPUControlSnapshot()

    /// Called on the main queue. Read and written under the snapshot lock,
    /// so a handler set at any time is never read half-way.
    var onChange: (@Sendable (GPUControlSnapshot) -> Void)? {
        get { snapshotLock.withLock { changeHandler } }
        set { snapshotLock.withLock { changeHandler = newValue } }
    }
    var onNotice: (@Sendable (GPUControlNotice) -> Void)? {
        get { snapshotLock.withLock { noticeHandler } }
        set { snapshotLock.withLock { noticeHandler = newValue } }
    }
    private var changeHandler: (@Sendable (GPUControlSnapshot) -> Void)?
    private var noticeHandler: (@Sendable (GPUControlNotice) -> Void)?

    /// Thread-safe flag shared with the engine.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var down = false
        private var opened = false
        var isDown: Bool { lock.withLock { down } }
        var wasOpened: Bool { lock.withLock { opened } }
        func shutDown() { lock.withLock { down = true } }
        func markOpened() { lock.withLock { opened = true } }
    }

    init(channel: GPUControlChannel? = nil) {
        self.channel = channel
        let gate = self.gate
        engine = GPUControlEngine(channel: channel, clock: Self.nowMs, isShutDown: { gate.isDown })
        engine.onSnapshot = { [weak self] snapshot in self?.publish(snapshot) }
        engine.onNotice = { [weak self] notice in
            guard let handler = self?.onNotice else { return }
            DispatchQueue.main.async { handler(notice) }
        }
        lastSnapshot = engine.snapshot
    }

    /// Let go without `shutdown`: nothing on the queue holds the controller
    /// any more, so the wake observer, the timer and the activity go here.
    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        timer?.cancel()
        endActivity()
    }

    var snapshot: GPUControlSnapshot { snapshotLock.withLock { lastSnapshot } }

    /// Listens for wakes. Opens nothing by itself.
    func start() {
        queue.async { [self] in
            guard !started, !gate.isDown else { return }
            started = true
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { self.engine.didWake(); self.run() }
                }
        }
    }

    func choose(_ request: GPUControlRequest, origin: GPUControlOrigin = .owner) {
        queue.async { [self] in engine.choose(request, origin: origin); run() }
    }

    func chooseGfxMax(_ mhz: Int?) { queue.async { [self] in engine.chooseGfxMax(mhz); run() } }

    func chooseFan(curve: [GPUControlFanPoint]?, zeroRpmOff: Bool) {
        queue.async { [self] in engine.chooseFan(curve: curve, zeroRpmOff: zeroRpmOff); run() }
    }

    func refresh() { queue.async { [self] in engine.refresh(); run() } }

    /// Ask again for what was held after a wake (remembering, plan 8).
    func setReaskAfterWake(_ on: Bool) { queue.async { [self] in engine.reaskAfterWake = on } }

    /// "Close changes": see `GPUControlEngine.close()`.
    func close() { queue.async { [self] in engine.close(); run() } }

    /// `applicationWillTerminate`: `release` at once on a helper thread,
    /// then close; waits `timeout` seconds at most.
    /// `release` answers right away and wins over a `set` already waiting in
    /// the kext (kext 0.7.2: the waiting `set` sleeps without `gStateLock`,
    /// `release` drops its request and the `set` answers `cancelled`). A
    /// `set` that reaches the kext just after the `release` finds the control
    /// free (the `release` gave it up), so the kext takes it and applies it
    /// if the process lives long enough, not only answers it: `close()` waits
    /// for that answer, up to the kext's 5 s, and closing gives the change
    /// back. Past `timeout` the app goes on; when the process ends the kext
    /// sees the connection die and goes back to the start-up values all the
    /// same.
    func shutdown(timeout: TimeInterval = 1) {
        gate.shutDown()
        let done = DispatchSemaphore(value: 0)
        let channel = self.channel
        let opened = gate
        Thread.detachNewThread {
            // Never opens: `release` only on a connection the engine opened.
            if opened.wasOpened { _ = channel?.release() }
            channel?.close()
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
            wakeObserver = nil
            engine.shutdown(callingChannel: false)
            endActivity()
        }
    }

    /// Waits for the queue (tests).
    func sync() { queue.sync {} }

    // MARK: On the queue

    private func run() {
        let due = engine.step()
        if engine.hasOpened { gate.markOpened() }
        schedule(due)
        if engine.needsTimelyCalls { beginActivity() } else { endActivity() }
    }

    private func schedule(_ due: UInt64?) {
        timer?.cancel()
        timer = nil
        guard let due, !gate.isDown else { return }
        let delay = due > Self.nowMs() ? due - Self.nowMs() : 0
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(Int(delay)), leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.run() }
        timer = source
        source.resume()
    }

    /// App Nap must not make `alive` late while something is held; the Mac
    /// may still sleep (plan section 6, not checked on the Mac).
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Holding a GPU power or fan setting")
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private func publish(_ snapshot: GPUControlSnapshot) {
        let handler: (@Sendable (GPUControlSnapshot) -> Void)? = snapshotLock.withLock {
            lastSnapshot = snapshot
            return changeHandler
        }
        guard let handler else { return }
        DispatchQueue.main.async { handler(snapshot) }
    }

    private static func nowMs() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1_000_000 }
}
