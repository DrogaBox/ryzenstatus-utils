// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// A model of the control channel of GPUSensors.kext 0.8.0 (and, with
/// `generation = .v07`, of 0.7.2), driven by a clock the caller moves. It
/// never touches IOKit or the GPU: the tests and the screenshots talk to it
/// instead of the kext.
///
/// 0.8.0 against 0.7.2: `disarm` (0.7.2 fails the call), the card's own
/// power floor from its OD8 power percent (0.7.2: a fixed 200 W) and
/// `PowerRange`, `NoFloor` and `StillApplied`, the read-only card
/// (`WriteOff` 15), and `set`/`setOD8` answering off and not armed before
/// they look at a value.
///
/// What it copies, from `control_logic.hpp` and `kern_control.cpp`:
/// - `Owner`: one owner at a time, 2 s between GPU writes (a way back counts),
///   30 s without `alive` and the kext goes back, sleep forgets the owner and
///   the way back runs after the wake;
/// - the channel's dispatcher (`kern_service.cpp`): another channel version
///   answers "bad version" (a version 1 kext returns 9 status scalars), wrong
///   counts fail the call, `setOD8` scalars that cannot be a fan point or a
///   clock are malformed;
/// - `set`, `setOd8`, `alive`, `release`, `closed` and `status` with their
///   replies, a power change and an OD8 change never held together, the
///   stock OD8 state and the start-up limit as ways back;
/// - the worker: ways back, failed changes that turn writing off, the fan
///   watchdog, timeouts.
///
/// What it does not copy: the OD8 checks beyond the GFX range, the curve's
/// ranges, order, first and last point (no "less air than stock"), and the
/// real driver calls. Times are the kext's: `revertMs` stands for the driver
/// calls of a way back.
///
/// Simplified on purpose:
/// - A way back is one step that ends `revertMs` later, confirmed or failed
///   (`failNextWayBack`). The kext makes up to 3 tries 500 ms apart
///   (`kRevertTries`, `afterRevertTry`), so a slow way back that confirms on
///   its second try keeps the reverting flag longer than here.
/// - The fan watchdog trips only when a test calls `tripFanWatchdog()`; the
///   kext's conditions (95 C, or 75 C with the fan under 90 % for 5 s, or
///   10 s without readings) are not modelled.
/// - There is no `SetSlot`: calls answer at once, so a second set while one
///   waits (Busy) and a connection closing during a set (Cancelled) only
///   happen through `forcedReplies`.
final class FakeGPUControlKext: @unchecked Sendable {
    // MARK: Settings the test changes

    /// Which kext this is.
    enum Generation: Equatable, Sendable {
        /// 0.7.2: no `disarm`, the floor fixed at `legacyFloorW`, no
        /// `PowerRange`, values checked before "not armed".
        case v07
        /// 0.8.0.
        case v08
    }

    var generation: Generation = .v08
    /// The channel version this kext speaks; 1 is 0.5.0 and 0.6.0.
    var version: UInt64 = GPUControlWire.channelVersion
    var bootW: UInt32 = 240
    /// The card's `OD8.Settings.PowerPercent`: feature 0x8, its lower bound
    /// (negative) and upper bound. The test RX 6800 XT has -6 and 9 (floor 225 W
    /// at 240 W); the model's default -20 leaves the tests room (192 W).
    /// Feature 0: the card offers no lower limit, the floor is the start-up
    /// value.
    var powerPercentFeature: UInt32 = 0x8
    var powerPercentMin = -20
    var powerPercentMax = 9
    /// 0.7.2's `kFloorW`: the old kext's fixed floor, modelled as it was.
    static let legacyFloorW: UInt32 = 200
    /// The driver's power management is up (`readyLocked` without the
    /// start-up limit, which `bootW` decides).
    var driverReady = true
    /// OD8 was read cleanly since boot.
    var od8Ready = true
    var stockGfxMaxMHz = 2_359
    var gfxMinMHz = 500
    /// The stock fan target; the last curve point must be at 100 % at or
    /// below this minus 22 C.
    var fanTargetC = 70
    /// The fan watchdog has fresh hotspot and fan readings.
    var dogSees = true
    /// The GPU answers the driver calls. False: a power change answers "not
    /// ready" and an OD8 change is not applied.
    var gpuAnswers = true
    /// The next change is not confirmed: writing goes off until restart.
    var failNextChange = false
    /// Every way back after that fails too.
    var failRecovery = false
    /// The next ordinary way back gives up after its tries.
    var failNextWayBack = false
    /// The next OD8 change is not taken by the GPU.
    var notAppliedNextOD8 = false
    /// The OD8 checks refuse the next state with this reason.
    var refuseNextOD8: GPUControlOD8Check?
    /// The worker does not answer: `set` and `setOD8` give up after 5 s.
    var workerStalled = false
    /// How long a way back takes on the worker.
    var revertMs: UInt64 = 300
    /// What `IOServiceOpen` answers.
    var openResult: GPUControlChannelOpen = .open
    /// Replies to give instead of the model's, once each, per call.
    var forcedReplies: [GPUControlWire.Selector: [UInt64]] = [:]

    // MARK: What the test reads

    struct Call: Equatable {
        var client: UInt64
        var selector: GPUControlWire.Selector
        var input: [UInt64]
        var atMs: UInt64
    }

    /// A GPU write: a change or a way back, as the worker sent it.
    struct Write: Equatable {
        enum Kind: Equatable { case power(UInt32), od8(GPUControlOD8Want), wayBack }
        var kind: Kind
        var atMs: UInt64
    }

    private(set) var nowMs: UInt64 = 100_000
    private(set) var calls: [Call] = []
    private(set) var writes: [Write] = []
    private(set) var connectionsOpened = 0

    // MARK: The kext's state (`gOwner`, `g*` in kern_control.cpp)

    private let lock = NSLock()
    private var owner = Owner()
    private var nextClient: UInt64 = 0
    private var heldW: UInt32 = 0
    private var limitUnknown = false
    private var od8Dirty = false
    private var od8Held: UInt64 = 0
    private var od8HeldWant = GPUControlOD8Want.stock
    private var changes: UInt64 = 0
    private var reverts: UInt64 = 0
    private var od8Changes: UInt64 = 0
    private var od8Reverts: UInt64 = 0
    private var od8LastCheck: UInt64 = 0
    private var lastReply: UInt64 = 0
    private var writeOff: GPUControlWriteOff = .none
    private var pendingRevert: UInt64 = 0
    private var revertDoneAt: UInt64?
    private var offBackAt: UInt64?
    private var offBackLeft = 0
    private var od8OffAfterWayBack = false
    private var tornDown = false
    // Sleep and wake, as the worker sees them.
    private var inSleep = false
    private var willSleepAt: UInt64?
    private var workerAsleep = false
    private var wakeDoneAt: UInt64?
    private var pendingWakeReadMs: UInt64 = 0

    // MARK: Connections

    /// A new connection, as `IOServiceOpen` would make one. Nothing is open
    /// until `open()`.
    func connection() -> Connection { Connection(kext: self) }

    final class Connection: GPUControlChannel, @unchecked Sendable {
        fileprivate let kext: FakeGPUControlKext
        fileprivate var client: UInt64 = 0
        fileprivate var isClosed = false

        fileprivate init(kext: FakeGPUControlKext) { self.kext = kext }

        /// The kext's number for this connection, 0 before it opened.
        var clientID: UInt64 { kext.locked { client } }

        func open() -> GPUControlChannelOpen { kext.open(self) }

        func call(_ selector: GPUControlWire.Selector, input: [UInt64], outputCount: Int) -> [UInt64]? {
            kext.call(self, selector, input: input, outputCount: outputCount)
        }

        func close() { kext.close(self) }
    }

    // MARK: The test's hands

    /// The card is the read-only one (0.8.0, RX 6900 XT rev C0): set once at
    /// start, before anything can arm. The reads go on; writing never opens.
    func makeReadOnlyCard() {
        locked {
            owner.markReadOnly()
            writeOff = .readOnlyCard
        }
    }

    /// The lowest limit `set` takes now, 0 while it is not known (0.8.0:
    /// OD8 not read, or an entry the kext does not take as a floor).
    var floorW: UInt32 { locked { floorLocked } }

    /// `sudo gpucontrol arm`: what an administrator gets.
    @discardableResult
    func arm(administrator: Bool = true) -> GPUControlReply {
        locked { armLocked(administrator: administrator) }
    }

    /// Moves the clock, running everything the worker has to do on the way.
    func advance(by ms: UInt64) { locked { runWorker(until: nowMs + ms) } }

    func advance(to ms: UInt64) { locked { runWorker(until: Swift.max(ms, nowMs)) } }

    /// The Mac goes to sleep. The worker sees it `workerLateByMs` later; until
    /// then a connection can still read itself as the owner.
    func sleep(workerLateByMs: UInt64 = 0) {
        locked {
            inSleep = true
            willSleepAt = nowMs + workerLateByMs
            runWorker(until: nowMs)
        }
    }

    /// The Mac wakes. The driver reads the power limit `driverReadAfterMs`
    /// later (10 s at most), then the kext waits 2 s and goes back if
    /// something was changed before the sleep.
    func wake(driverReadAfterMs: UInt64 = 0) {
        locked {
            inSleep = false
            pendingWakeReadMs = Swift.min(driverReadAfterMs, 10_000)
            if workerAsleep { wakeDoneAt = nowMs + pendingWakeReadMs + GPUControlWire.wakeReadyMarginMs }
            runWorker(until: nowMs)
        }
    }

    /// The fan watchdog trips (95 C, or 75 C with the fan under 90 % for 5 s,
    /// or 10 s without readings): stock fan once, writing off until restart.
    func tripFanWatchdog() {
        locked {
            let curve = (od8Held & (GPUControlOD8Held.curve.rawValue | GPUControlOD8Held.unknown.rawValue)) != 0
            guard curve, od8Dirty, !tornDown, !owner.isOff else { return }
            if inSleep {
                // After the wake Owner goes back, and writing goes off then.
                od8OffAfterWayBack = true
                startRevert(owner.release(owner.owner))
                return
            }
            if !failRecovery { od8BackConfirmed() }
            _ = owner.release(owner.owner)
            pendingRevert = 0
            revertDoneAt = nil
            turnOffLocked(.od8Watchdog)
        }
    }

    /// Writing goes off for this reason (a second power object, the driver
    /// going away, ...), as the kext does for its runtime checks.
    func turnOff(_ why: GPUControlWriteOff) {
        locked {
            if why == .teardown { tornDown = true }
            turnOffLocked(why)
        }
    }

    /// What `status` shows this connection, without a call.
    func statusFor(_ connection: Connection) -> GPUControlChannelStatus? {
        locked { GPUControlChannelStatus(scalars: statusScalars(client: connection.client)) }
    }

    var owningClient: UInt64 { locked { owner.owner } }

    /// The properties the kext would publish for the write path: `Write`,
    /// `WriteState`, `OD8Write`, `OD8WriteState`.
    func properties() -> [String: Any] {
        locked {
            var od8State: [String: Any] = [
                "Held": NSNumber(value: od8Dirty ? od8Held : 0),
                "Changes": NSNumber(value: od8Changes), "Reverts": NSNumber(value: od8Reverts),
                "LastCheck": NSNumber(value: od8LastCheck),
                "LastCheckText": GPUControlOD8Check(rawValue: od8LastCheck)?.kextText ?? "unknown",
                "SentPower": NSNumber(value: 0),
            ]
            if od8Dirty, let curve = od8HeldWant.curve {
                od8State["FanCurveHeld"] = curve.map { NSNumber(value: $0.temperatureC * 1_000 + $0.speedPercent) }
            }
            if od8Dirty, let gfx = od8HeldWant.gfxMaxMHz { od8State["GfxMaxHeld"] = NSNumber(value: gfx) }
            var all: [String: Any] = [
                "Write": writeText(),
                "WriteState": [
                    "WriteOff": NSNumber(value: writeOff.rawValue), "WriteOffText": writeOff.kextText,
                    "Armed": NSNumber(value: owner.isArmed ? 1 : 0), "Owned": NSNumber(value: owner.owner != 0 ? 1 : 0),
                    "HeldW": NSNumber(value: heldW != 0 ? heldW : bootW),
                    "Changes": NSNumber(value: changes), "Reverts": NSNumber(value: reverts),
                    "LastReply": NSNumber(value: lastReply),
                ] as [String: Any],
                "OD8Write": od8WriteText(),
                "OD8WriteState": od8State,
            ]
            if generation == .v08 {
                let floor = floorLocked
                all["PowerRangeState"] = powerRangeText(floor: floor)
                var range: [String: Any] = ["Known": NSNumber(value: floor != 0 ? 1 : 0),
                                            "StepW": NSNumber(value: GPUControlWire.powerStepW)]
                if floor != 0 {
                    range["FloorW"] = NSNumber(value: floor)
                    range["MaxW"] = NSNumber(value: bootW)
                }
                if od8Ready, Self.bootPlausible(bootW) {
                    // Signed 32-bit, as the kext publishes them.
                    range["PercentMin"] = NSNumber(value: Int32(powerPercentMin))
                    range["PercentMax"] = NSNumber(value: Int32(powerPercentMax))
                }
                all["PowerRange"] = range
            }
            return all
        }
    }

    // `floorStateText`.
    private func powerRangeText(floor: UInt32) -> String {
        if !Self.bootPlausible(bootW) { return "not known: the start-up limit is not read yet or not believable" }
        if !od8Ready { return "not known yet: waiting for a clean OD8 read" }
        if powerPercentFeature == 0 { return "the card offers no lower power limit: only the start-up limit" }
        if floor == 0 { return "not known: the card's OD8 power entry is not as expected" }
        return "from the card: start-up limit less its OD8 power percent"
    }

    // MARK: Connections, inside

    private func open(_ connection: Connection) -> GPUControlChannelOpen {
        locked {
            if connection.isClosed { return .closed }
            if connection.client != 0 { return .open }
            guard openResult == .open else { return openResult }
            nextClient += 1
            connection.client = nextClient
            connectionsOpened += 1
            return .open
        }
    }

    private func close(_ connection: Connection) {
        locked {
            defer { connection.isClosed = true }
            guard !connection.isClosed, connection.client != 0 else { return }
            // `GPUControl::closed`: whatever it held goes back at once.
            startRevert(owner.closed(connection.client))
        }
    }

    // `DrogaBoxGPUControlClient::externalMethod`.
    private func call(_ connection: Connection, _ selector: GPUControlWire.Selector,
                      input: [UInt64], outputCount: Int) -> [UInt64]? {
        locked {
            let client = connection.client
            guard client != 0, !connection.isClosed else { return nil }
            calls.append(Call(client: client, selector: selector, input: input, atMs: nowMs))
            let kextStatusCount = version == 1 ? 9 : GPUControlWire.statusCount
            if !input.isEmpty, input[0] != version, outputCount >= 1 {
                var all = selector == .status ? statusScalars(client: client) : []
                all += [UInt64](repeating: 0, count: Swift.max(0, kextStatusCount - all.count))
                var out = Array(all.prefix(Swift.min(outputCount, kextStatusCount)))
                out[0] = GPUControlReply.badVersion.rawValue
                return out
            }
            guard input.count == selector.inputCount, outputCount >= selector.outputCount else { return nil }
            if var forced = forcedReplies[selector], !forced.isEmpty {
                let reply = forced.removeFirst()
                forcedReplies[selector] = forced
                var out = selector == .status ? statusScalars(client: client)
                                              : [UInt64](repeating: 0, count: selector.outputCount)
                out[0] = reply
                return out
            }
            switch selector {
            case .status:
                return statusScalars(client: client)
            case .arm:
                // The app is never root.
                return [armLocked(administrator: false).rawValue]
            case .disarm:
                // 0.7.2 has no selector 6: `IOConnectCallScalarMethod` fails.
                guard generation == .v08 else { return nil }
                return [disarmLocked().rawValue]
            case .set:
                // 0.8.0: off and not armed come before any value (`valueGate`).
                if generation == .v08, let gate = valueGate() { return [record(gate).rawValue] }
                let reply: GPUControlReply = input[1] > 0xFFFF_FFFF
                    ? .aboveBoot : set(client: client, watts: UInt32(input[1]))
                return [reply.rawValue]
            case .alive:
                return [(owner.alive(client, nowMs) ? GPUControlReply.ok : .notOwner).rawValue]
            case .release:
                startRevert(owner.release(client))
                return [GPUControlReply.ok.rawValue]
            case .setOD8:
                if generation == .v08, let gate = valueGate() { return [record(gate).rawValue, 0] }
                guard let want = Self.want(from: input, maxGfxMHz: generation == .v08 ? 0x7FFF_FFFF : 5_000) else {
                    return [GPUControlReply.badArgs.rawValue, 0]
                }
                let (reply, check) = setOD8(client: client, want: want)
                return [reply.rawValue, reply == .od8Refused ? check.rawValue : 0]
            }
        }
    }

    /// The dispatcher's reading of `setOD8`'s 13 scalars; nil is malformed.
    /// The clock's wire bound: 5000 MHz in 0.7.2, the 32-bit field in 0.8.0.
    private static func want(from input: [UInt64], maxGfxMHz: UInt64) -> GPUControlOD8Want? {
        let flags = input[1]
        guard flags & ~(GPUControlWire.wantCurve | GPUControlWire.wantZeroRpmOff) == 0, input[12] <= maxGfxMHz else {
            return nil
        }
        let curve = flags & GPUControlWire.wantCurve != 0
        var points: [GPUControlFanPoint] = []
        for k in 0..<GPUControlWire.fanCurvePoints {
            let t = input[2 + k], v = input[7 + k]
            guard t <= 200, v <= 200, curve || (t == 0 && v == 0) else { return nil }
            points.append(GPUControlFanPoint(temperatureC: Int(t), speedPercent: Int(v)))
        }
        return GPUControlOD8Want(curve: curve ? points : nil,
                                 zeroRpmOff: flags & GPUControlWire.wantZeroRpmOff != 0,
                                 gfxMaxMHz: input[12] == 0 ? nil : Int(input[12]))
    }

    // MARK: The kext's calls

    private func armLocked(administrator: Bool) -> GPUControlReply {
        guard administrator else { return .notPrivileged }
        if owner.isOff || owner.isReadOnly { return .off }
        if !Self.bootPlausible(bootW) { return .noBootValue }
        if !readyLocked { return .notReady }
        return owner.arm() ? .ok : .off
    }

    // `disarmCheck` (0.8.0): anyone may close; refused while anything is
    // applied (a hold, something not confirmed back, a way back).
    private func disarmLocked() -> GPUControlReply {
        startRevert(owner.expired(nowMs))
        if owner.isOff || owner.isReadOnly { return .off }
        let holds = changedLocked || heldW != 0 || limitUnknown || od8Dirty || pendingRevert != 0
        if holds || !owner.canDisarm { return .stillApplied }
        owner.disarm()
        return .ok
    }

    // `valueGate` (0.8.0): nil when set and setOD8 go on to their values.
    private func valueGate() -> GPUControlReply? {
        if owner.isOff || owner.isReadOnly { return .off }
        if !owner.isArmed { return .notArmed }
        return nil
    }

    // `powerRange`: 0.8.0's floor from the card's power percent, once OD8
    // was read; 0.7.2's fixed one.
    private var floorLocked: UInt32 {
        guard generation == .v08 else { return Self.legacyFloorW }
        guard Self.bootPlausible(bootW), od8Ready else { return 0 }
        if powerPercentFeature == 0 { return bootW }
        guard powerPercentFeature == 0x8, powerPercentMin <= 0,
              powerPercentMin >= -GPUControlPowerRange.maxPercentDown, powerPercentMin <= powerPercentMax else { return 0 }
        return bootW * UInt32(100 + powerPercentMin) / 100
    }

    // `GPUControl::set` and the worker's `runSet`.
    private func set(client: UInt64, watts: UInt32) -> GPUControlReply {
        startRevert(owner.expired(nowMs))
        if owner.isOff || owner.isReadOnly { return record(.off) }
        let reply: GPUControlReply
        switch Self.routeSet(boot: bootW, floor: floorLocked, watts: watts) {
        case .refuse(let refusal):
            reply = refusal
        case .release:
            // The kext writes `LastReply` only for a posted set or a refusal.
            startRevert(owner.release(client))
            return .ok
        case .change:
            var pre = Self.reply(owner.wouldChange(client, nowMs))
            if pre == .ok, !readyLocked { pre = .notReady }
            if pre == .ok, od8Dirty { pre = .busy }
            guard pre == .ok else { return record(pre) }
            if workerStalled { return record(timeout(client: client)) }
            reply = runSet(client: client, watts: watts)
        }
        return record(reply)
    }

    private func runSet(client: UInt64, watts: UInt32) -> GPUControlReply {
        if sleepingLocked { return .sleeping }
        if od8Dirty { return .busy }
        let change = Self.reply(owner.change(client, nowMs))
        guard change == .ok else { return change }
        guard gpuAnswers else {
            // `runSet`, sendLimit Busy or NotSent (kern_control.cpp:805-810):
            // nothing reached the firmware; the change Owner counted goes
            // back and the program hears "busy".
            startRevert(owner.release(client))
            return .busy
        }
        if failNextChange {
            failNextChange = false
            _ = owner.release(client)
            pendingRevert = 0
            revertDoneAt = nil
            if !failRecovery && !sleepingLocked {
                heldW = 0
                reverts += 1
                writes.append(Write(kind: .wayBack, atMs: nowMs))
            } else {
                limitUnknown = true
            }
            turnOffLocked(.sendFailed)
            return .failed
        }
        heldW = watts
        changes += 1
        writes.append(Write(kind: .power(watts), atMs: nowMs))
        return .ok
    }

    // `GPUControl::setOd8` and the worker's `runSetOd8`.
    private func setOD8(client: UInt64, want: GPUControlOD8Want) -> (GPUControlReply, GPUControlOD8Check) {
        startRevert(owner.expired(nowMs))
        if owner.isOff || owner.isReadOnly { return (record(.off), .ok) }
        if want.isStock {
            // The stock state is the way back, never a change.
            if owner.owner != 0, owner.owner != client { return (record(.busy), .ok) }
            if od8Dirty || owner.owner == client { startRevert(owner.release(client)) }
            return (.ok, .ok)
        }
        var pre = Self.reply(owner.wouldChange(client, nowMs))
        if pre == .ok, !readyLocked || !od8Ready { pre = .notReady }
        if pre == .ok, heldW != 0 || limitUnknown { pre = .busy }
        guard pre == .ok else { return (record(pre), .ok) }
        if workerStalled { return (record(timeout(client: client)), .ok) }
        let (reply, check) = runSetOD8(client: client, want: want)
        return (record(reply), check)
    }

    private func runSetOD8(client: UInt64, want: GPUControlOD8Want) -> (GPUControlReply, GPUControlOD8Check) {
        if sleepingLocked { return (.sleeping, .ok) }
        if heldW != 0 || limitUnknown { return (.busy, .ok) }
        var check = GPUControlOD8Check.ok
        if want.curve != nil, !dogSees { check = .noReadings }
        if check == .ok, !gpuAnswers { return (.notReady, .ok) }
        if check == .ok { check = checkOD8(want) }
        if check != .ok {
            od8LastCheck = check.rawValue
            return (.od8Refused, check)
        }
        let change = Self.reply(owner.change(client, nowMs))
        guard change == .ok else { return (change, .ok) }
        od8Dirty = true
        if notAppliedNextOD8 {
            notAppliedNextOD8 = false
            od8Held = GPUControlOD8Held.unknown.rawValue
            startRevert(owner.release(client))
            return (.notReady, .ok)
        }
        if failNextChange {
            failNextChange = false
            _ = owner.release(client)
            pendingRevert = 0
            revertDoneAt = nil
            writes.append(Write(kind: .od8(want), atMs: nowMs))
            if failRecovery {
                od8Held = GPUControlOD8Held.unknown.rawValue
            } else {
                od8BackConfirmed()
            }
            turnOffLocked(.od8Failed)
            return (.failed, .ok)
        }
        od8Held = want.heldFlags.rawValue
        od8HeldWant = want
        od8Changes += 1
        od8LastCheck = 0
        writes.append(Write(kind: .od8(want), atMs: nowMs))
        return (.ok, .ok)
    }

    /// The checks the fake makes; the kext makes more (see the type's note).
    private func checkOD8(_ want: GPUControlOD8Want) -> GPUControlOD8Check {
        if let refusal = refuseNextOD8 {
            refuseNextOD8 = nil
            return refusal
        }
        if !od8Ready { return .notRead }
        if let curve = want.curve {
            guard curve.count == GPUControlWire.fanCurvePoints else { return .curveRange }
            for (k, point) in curve.enumerated() {
                guard (25...100).contains(point.temperatureC), (20...100).contains(point.speedPercent) else {
                    return .curveRange
                }
                if k > 0, point.temperatureC <= curve[k - 1].temperatureC || point.speedPercent < curve[k - 1].speedPercent {
                    return .curveOrder
                }
            }
            if curve[0].temperatureC > 30 { return .curveFirst }
            if let last = curve.last, last.speedPercent != 100 || last.temperatureC > fanTargetC - 22 { return .curveLast }
        }
        if let gfx = want.gfxMaxMHz, gfx < GPUControlWire.gfxFloorMHz || gfx > stockGfxMaxMHz || gfx < gfxMinMHz {
            return .gfxRange
        }
        return .ok
    }

    /// The caller gave up after 5 s: its request is dropped, whatever it held
    /// goes back.
    private func timeout(client: UInt64) -> GPUControlReply {
        nowMs += GPUControlWire.setWaitMs
        if owner.owner == client { startRevert(owner.release(client)) }
        return .timeout
    }

    private func record(_ reply: GPUControlReply) -> GPUControlReply {
        lastReply = reply.rawValue
        return reply
    }

    // MARK: Status and texts

    private func statusScalars(client: UInt64) -> [UInt64] {
        var flags: GPUControlFlags = []
        if od8Ready { flags.insert(.od8Ready) }
        if owner.isArmed { flags.insert(.armed) }
        if owner.isOff || owner.isReadOnly { flags.insert(.off) }
        if sleepingLocked { flags.insert(.sleeping) }
        if owner.isReverting || pendingRevert != 0 { flags.insert(.reverting) }
        if changedLocked { flags.insert(.changed) }
        if owner.owner != 0 { flags.insert(.owned) }
        if client != 0, owner.owner == client { flags.insert(.mine) }
        if readyLocked { flags.insert(.ready) }
        let held: UInt64 = od8Dirty ? (od8Held != 0 ? od8Held : GPUControlOD8Held.unknown.rawValue) : 0
        let all: [UInt64] = [
            GPUControlReply.ok.rawValue, version, flags.rawValue, UInt64(bootW),
            UInt64(heldW != 0 ? heldW : bootW), writeOff.rawValue, changes, reverts, lastReply,
            held, od8Changes, od8Reverts, od8LastCheck,
        ]
        return version == 1 ? Array(all.prefix(9)) : all
    }

    private func writeText() -> String {
        if owner.isReadOnly { return "read only: this card can only be read (see WriteState)" }
        if owner.isOff { return "off until restart: see WriteState" }
        if !readyLocked { return "waiting for the power management and its start-up limit" }
        if !owner.isArmed { return "closed: sudo gpucontrol arm opens it until restart" }
        if sleepingLocked { return "armed: the Mac is between sleep and wake" }
        if owner.isReverting || pendingRevert != 0 { return "armed: going back to the start-up limit" }
        if owner.owner != 0, owner.isChanged { return "armed: a program holds a lower limit" }
        return "armed: nothing held"
    }

    private func od8WriteText() -> String {
        if owner.isReadOnly { return "read only: this card can only be read (see WriteState)" }
        if owner.isOff { return "off until restart: see WriteState" }
        if !od8Ready { return "waiting for a clean OD8 read (OD8State)" }
        if !owner.isArmed { return "closed: sudo gpucontrol arm opens it until restart" }
        if od8Held & GPUControlOD8Held.unknown.rawValue != 0 {
            return "armed: the last OD8 call was not taken; going back to stock"
        }
        if od8Dirty, od8Held != 0 { return "armed: a program holds a fan or clock change" }
        if od8Dirty { return "armed: going back to stock" }
        return "armed: OD8 at stock"
    }

    private var sleepingLocked: Bool { owner.isSleeping || inSleep }

    private var readyLocked: Bool { driverReady && !tornDown && Self.bootPlausible(bootW) }

    private var changedLocked: Bool {
        owner.isOff ? (heldW != 0 || limitUnknown || od8Dirty) : owner.isChanged
    }

    // MARK: The worker

    private func startRevert(_ id: UInt64) {
        guard id != 0 else { return }
        pendingRevert = id
        revertDoneAt = nowMs + revertMs
    }

    private func turnOffLocked(_ why: GPUControlWriteOff) {
        if writeOff == .none { writeOff = why }
        owner.turnOff()
        pendingRevert = 0
        revertDoneAt = nil
        if od8Dirty, !tornDown, offBackAt == nil {
            offBackLeft = 3
            offBackAt = nowMs + revertMs
        }
    }

    private func od8BackConfirmed() {
        od8Dirty = false
        od8Held = 0
        od8Reverts += 1
        writes.append(Write(kind: .wayBack, atMs: nowMs))
    }

    /// Everything due up to `target`, in time order, then the clock at `target`.
    private func runWorker(until target: UInt64) {
        while true {
            var due: [(UInt64, Int)] = []
            if let at = willSleepAt { due.append((at, 0)) }
            if workerAsleep, !inSleep, let at = wakeDoneAt { due.append((at, 1)) }
            if !workerAsleep, owner.owner != 0 { due.append((owner.deadline, 2)) }
            if !workerAsleep, !inSleep, pendingRevert != 0, let at = revertDoneAt { due.append((at, 3)) }
            if !inSleep, let at = offBackAt { due.append((at, 4)) }
            guard let next = due.filter({ $0.0 <= target }).min(by: { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) })
            else { break }
            nowMs = Swift.max(nowMs, next.0)
            switch next.1 {
            case 0:
                // The worker sees the sleep: forget the owner, send nothing.
                willSleepAt = nil
                workerAsleep = true
                owner.willSleep()
                pendingRevert = 0
                revertDoneAt = nil
                if !inSleep { wakeDoneAt = nowMs + pendingWakeReadMs + GPUControlWire.wakeReadyMarginMs }
            case 1:
                workerAsleep = false
                wakeDoneAt = nil
                startRevert(owner.didWake())
            case 2:
                // 30 s without a word.
                startRevert(owner.expired(nowMs))
            case 3:
                finishRevert()
            default:
                offBackPass()
            }
        }
        nowMs = Swift.max(nowMs, target)
    }

    private func finishRevert() {
        let id = pendingRevert
        revertDoneAt = nil
        let od8 = od8Dirty
        if failNextWayBack || (od8 && failRecovery) {
            failNextWayBack = false
            owner.revertFailed(id)
            pendingRevert = 0
            if owner.isOff { turnOffLocked(.revertFailed) }
            return
        }
        owner.reverted(id, nowMs)
        pendingRevert = 0
        writes.append(Write(kind: .wayBack, atMs: nowMs))
        if od8 {
            od8Dirty = false
            od8Held = 0
            od8Reverts += 1
            if od8OffAfterWayBack { turnOffLocked(.od8Watchdog) }
        } else {
            if !owner.isChanged { heldW = 0 }
            reverts += 1
        }
    }

    private func offBackPass() {
        guard od8Dirty, !tornDown, offBackLeft > 0 else {
            offBackAt = nil
            return
        }
        if failRecovery {
            offBackLeft -= 1
            od8Held |= GPUControlOD8Held.unknown.rawValue
            offBackAt = offBackLeft > 0 ? nowMs + 500 : nil
            return
        }
        od8BackConfirmed()
        offBackAt = nil
        offBackLeft = 0
    }

    // MARK: Helpers

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func bootPlausible(_ watts: UInt32) -> Bool {
        watts >= UInt32(GPUControlWire.minBootW) && watts <= UInt32(GPUControlWire.maxBootW)
    }

    private enum Route { case refuse(GPUControlReply), release, change }

    // `checkPower` and `routeSet`. `floor` 0: not known (0.8.0), only the
    // start-up value is taken.
    private static func routeSet(boot: UInt32, floor: UInt32, watts: UInt32) -> Route {
        if !bootPlausible(boot) { return .refuse(.noBootValue) }
        if watts == boot { return .release }
        if watts > boot { return .refuse(.aboveBoot) }
        if floor == 0 || floor > boot { return .refuse(.noFloor) }
        if watts < floor { return .refuse(.belowFloor) }
        if watts % UInt32(GPUControlWire.powerStepW) != 0 { return .refuse(.notAStep) }
        return .change
    }

    private static func reply(_ ask: Owner.Ask) -> GPUControlReply {
        switch ask {
        case .ok: return .ok
        case .busy: return .busy
        case .tooSoon: return .tooSoon
        case .off: return .off
        case .notArmed: return .notArmed
        case .sleeping: return .sleeping
        case .badClient: return .badArgs
        }
    }

    /// `gpuctl::Owner`, line for line.
    private struct Owner {
        enum Ask { case ok, busy, tooSoon, off, notArmed, sleeping, badClient }

        private(set) var owner: UInt64 = 0
        private var lastAliveMs: UInt64 = 0
        private var lastWriteMs: UInt64 = 0
        private var revertId: UInt64 = 0
        private var wroteOnce = false
        private(set) var isArmed = false
        private(set) var isChanged = false
        private(set) var isReverting = false
        private(set) var isSleeping = false
        private(set) var isOff = false
        private(set) var isReadOnly = false

        mutating func arm() -> Bool {
            if isOff || isReadOnly { return false }
            isArmed = true
            return true
        }

        // 0.8.0.
        var canDisarm: Bool { !isOff && owner == 0 && !isChanged && !isReverting }

        mutating func disarm() {
            if canDisarm { isArmed = false }
        }

        mutating func markReadOnly() {
            isReadOnly = true
            isArmed = false
        }

        mutating func change(_ client: UInt64, _ now: UInt64) -> Ask {
            let ask = wouldChange(client, now)
            guard ask == .ok else { return ask }
            owner = client
            lastAliveMs = now
            lastWriteMs = now
            wroteOnce = true
            isChanged = true
            return .ok
        }

        func wouldChange(_ client: UInt64, _ now: UInt64) -> Ask {
            if client == 0 { return .badClient }
            if isOff || isReadOnly { return .off }
            if !isArmed { return .notArmed }
            if isSleeping { return .sleeping }
            if isReverting { return .busy }
            if owner != 0, owner != client { return .busy }
            if owner == client, now < lastAliveMs || now - lastAliveMs >= GPUControlWire.aliveTimeoutMs { return .busy }
            if wroteOnce, now < lastWriteMs || now - lastWriteMs < GPUControlWire.minChangeGapMs { return .tooSoon }
            return .ok
        }

        var deadline: UInt64 { owner == 0 ? 0 : lastAliveMs + GPUControlWire.aliveTimeoutMs }

        mutating func alive(_ client: UInt64, _ now: UInt64) -> Bool {
            if owner == 0 || owner != client { return false }
            if now < lastAliveMs || now - lastAliveMs >= GPUControlWire.aliveTimeoutMs { return false }
            lastAliveMs = now
            return true
        }

        mutating func release(_ client: UInt64) -> UInt64 { drop(client) }
        mutating func closed(_ client: UInt64) -> UInt64 { drop(client) }

        mutating func expired(_ now: UInt64) -> UInt64 {
            if owner == 0 || now < lastAliveMs || now - lastAliveMs < GPUControlWire.aliveTimeoutMs { return 0 }
            return drop(owner)
        }

        mutating func reverted(_ id: UInt64, _ now: UInt64) {
            guard isReverting, id == revertId else { return }
            isReverting = false
            isChanged = false
            if !wroteOnce || now > lastWriteMs { lastWriteMs = now }
            wroteOnce = true
        }

        mutating func revertFailed(_ id: UInt64) {
            guard isReverting, id == revertId else { return }
            turnOff()
        }

        mutating func willSleep() {
            isSleeping = true
            owner = 0
            isReverting = false
        }

        mutating func didWake() -> UInt64 {
            let wasSleeping = isSleeping
            isSleeping = false
            if !wasSleeping || isOff || !isChanged { return 0 }
            return startRevert()
        }

        mutating func turnOff() {
            isOff = true
            isArmed = false
            owner = 0
            isReverting = false
        }

        private mutating func drop(_ client: UInt64) -> UInt64 {
            if owner == 0 || owner != client { return 0 }
            owner = 0
            if !isChanged { return 0 }
            return startRevert()
        }

        private mutating func startRevert() -> UInt64 {
            isReverting = true
            revertId += 1
            return revertId
        }
    }
}
