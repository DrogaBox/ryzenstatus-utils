// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The numbers of GPUSensors.kext's control channel, version 2 (kext 0.7.x
/// and 0.8.0): an IOUserClient of type 0 on `DrogaBoxGPUSensors` that takes
/// and returns scalars only. Copied from the kext's `control_logic.hpp`
/// (selectors, replies, the status layout, its flags) and `kern_service.cpp`
/// (the counts each call takes). 0.8.0 keeps version 2 and only adds: the
/// `disarm` selector, two replies, one `WriteOff` reason and the card's own
/// power range (`PowerRange`, read from the properties). Nothing here talks
/// to the kext.
enum GPUControlWire {
    /// The first scalar of every call. A kext that speaks another version
    /// answers `badVersion` and nothing else.
    static let channelVersion: UInt64 = 2

    enum Selector: UInt32, CaseIterable, Sendable {
        case status = 0
        /// Opens writing until restart. Root only: the app never calls it.
        case arm = 1
        case set = 2
        case alive = 3
        case release = 4
        case setOD8 = 5
        /// Closes writing again (0.8.0). Anyone may: closing only makes it
        /// safer, it is refused while anything is applied, and opening again
        /// still needs `arm`. A 0.7.x kext does not know it: the call fails.
        case disarm = 6

        /// Scalars in, the version included.
        var inputCount: Int {
            switch self {
            case .set: return 2
            case .setOD8: return GPUControlWire.setOD8InputCount
            default: return 1
            }
        }

        /// Scalars out, the reply first.
        var outputCount: Int {
            switch self {
            case .status: return GPUControlWire.statusCount
            case .setOD8: return 2
            default: return 1
            }
        }
    }

    static let statusCount = 13
    /// `{version, flags, t1..t5, s1..s5, gfxMaxMHz}`.
    static let setOD8InputCount = 13
    static let fanCurvePoints = 5

    /// `set` and `setOD8` wait this long for the kext's worker.
    static let setWaitMs: UInt64 = 5_000
    /// Without a word from the owner for this long the kext goes back.
    static let aliveTimeoutMs: UInt64 = 30_000
    /// Two GPU writes are at least this far apart; a way back counts.
    static let minChangeGapMs: UInt64 = 2_000

    /// The power limit the kext takes goes down from the start-up value in
    /// these steps, to the card's own floor (`GPUControlPowerRange`, never a
    /// number written here). The start-up value itself is the way back.
    static let powerStepW = 10
    /// `kMinBootW` and `kMaxBootW`: a start-up value outside these is not
    /// believed as read. A check of the read only, never a floor for requests.
    static let minBootW = 200
    static let maxBootW = 300
    /// The GFX maximum clock is never taken below this (`kOd8GfxFloorMHz`).
    static let gfxFloorMHz = 1_500
    /// The fan watchdog takes the curve back after this long hot
    /// (`kOd8DogHoldMs`).
    static let od8DogHoldMs: UInt64 = 5_000
    /// After a wake the kext waits this long after the driver's read before
    /// it calls the card ready (`kWakeReadyMarginMs`).
    static let wakeReadyMarginMs: UInt64 = 2_000

    /// `setOD8`'s flags scalar.
    static let wantCurve: UInt64 = 1
    static let wantZeroRpmOff: UInt64 = 2
}

/// A call's first scalar out (`gpuctl::Reply`).
enum GPUControlReply: UInt64, CaseIterable, Sendable {
    case ok = 0
    case badVersion = 1
    case badArgs = 2
    case notPrivileged = 3
    case off = 4
    case notArmed = 5
    case noBootValue = 6
    case notReady = 7
    case sleeping = 8
    case busy = 9
    case tooSoon = 10
    case belowFloor = 11
    case aboveBoot = 12
    case notAStep = 13
    case timeout = 14
    case failed = 15
    case notOwner = 16
    case cancelled = 17
    case od8Refused = 18
    /// `disarm` (0.8.0): something is still applied; go back first.
    case stillApplied = 19
    /// `set` (0.8.0): the card's minimum power limit is not known
    /// (`PowerRangeState` says why): only the start-up value is taken.
    case noFloor = 20

    /// The kext's own words (`replyText`), shown under the app's sentence.
    var kextText: String {
        switch self {
        case .ok: return "ok"
        case .badVersion: return "refused: the kext speaks another version of the channel"
        case .badArgs: return "refused: malformed request"
        case .notPrivileged: return "refused: arm needs an administrator (sudo)"
        case .off: return "refused: writing is off until restart"
        case .notArmed: return "refused: not armed since restart (sudo gpucontrol arm)"
        case .noBootValue: return "refused: the start-up limit is not read yet or not believable"
        case .notReady: return "refused: GPU asleep or not ready, nothing sent"
        case .sleeping: return "refused: the Mac is between sleep and wake"
        case .busy:
            return "busy: another program holds the control, a way back is running, or the GPU is busy; try later"
        case .tooSoon: return "refused: less than 2 s since the last write"
        case .belowFloor: return "refused: below the card's minimum power limit (PowerRange)"
        case .aboveBoot: return "refused: above the start-up limit"
        case .notAStep: return "refused: not a 10 W step"
        case .timeout: return "busy: no answer in 5 s; anything held by this program goes back"
        case .failed:
            return "failed: the change was not confirmed; the start-up limit was sent and writing is off until restart"
        case .notOwner: return "this program holds nothing"
        case .cancelled: return "cancelled: the connection closed"
        case .od8Refused: return "refused: the fan or clock setting is not allowed"
        case .stillApplied:
            return "refused: a change is still applied or being handled; go back to the start-up values first"
        case .noFloor: return "refused: the card's minimum power limit is not known (PowerRangeState)"
        }
    }
}

/// Why the kext refused an OD8 state (`gpuctl::Od8Check`): `setOD8`'s second
/// scalar out, and `status`'s last field.
enum GPUControlOD8Check: UInt64, CaseIterable, Sendable {
    case ok = 0
    case notRead = 1
    case drifted = 2
    case memoryMoved = 3
    case noFeature = 4
    case curveRange = 5
    case curveOrder = 6
    case curveFirst = 7
    case curveLast = 8
    case curveCooling = 9
    case gfxRange = 10
    case noReadings = 11

    /// `od8CheckText`.
    var kextText: String {
        switch self {
        case .ok: return "ok"
        case .notRead: return "OD8 was not read cleanly since boot"
        case .drifted: return "OD8 now differs from the first read after boot"
        case .memoryMoved: return "the memory clock is not at stock"
        case .noFeature: return "a setting is not offered as expected on this card"
        case .curveRange: return "a fan point is outside the driver's range (25-100 C, 20-100 %)"
        case .curveOrder: return "fan temperatures must rise and speeds must not fall"
        case .curveFirst: return "the first fan point must be at 30 C or below"
        case .curveLast: return "the last fan point must be 100 % at or below the safe top temperature"
        case .curveCooling: return "the curve gives less air than stock somewhere"
        case .gfxRange: return "GFX max must be between 1500 MHz and the stock maximum"
        case .noReadings: return "the fan watchdog has no fresh hotspot and fan readings"
        }
    }
}

/// Why writing is off until restart (`gpuctl::WriteOff`).
enum GPUControlWriteOff: UInt64, CaseIterable, Sendable {
    case none = 0
    case ctlOff = 1
    case notOneCard = 2
    case otherAmdGpu = 3
    case library = 4
    case routes = 5
    case cwdde = 6
    case secondObject = 7
    case bootImplausible = 8
    case start = 9
    case sendFailed = 10
    case revertFailed = 11
    case teardown = 12
    case od8Failed = 13
    case od8Watchdog = 14
    /// 0.8.0: a card the kext reads but never writes (the RX 6900 XT, 73BF
    /// rev C0). Off from boot; the reads still run.
    case readOnlyCard = 15

    /// `writeOffText`.
    var kextText: String {
        switch self {
        case .none: return ""
        case .ctlOff: return "-gpuctloff"
        case .notOneCard: return "not exactly one RX 6800 XT or RX 6900 XT"
        case .otherAmdGpu: return "another AMD GPU is present"
        case .library: return "the driver library is not AMDRadeonX6000HWLibs"
        case .routes: return "a watched driver function is not routed"
        case .cwdde: return "ppCWDDE is not as expected"
        case .secondObject: return "a second PowerPlay object showed up"
        case .bootImplausible: return "the start-up limit read is not believable"
        case .start: return "the control could not start its thread"
        case .sendFailed: return "a change could not be confirmed"
        case .revertFailed: return "a way back did not take"
        case .teardown: return "the GPU went away or the Mac is stopping"
        case .od8Failed: return "an OD8 change did not read back as sent"
        case .od8Watchdog: return "the fan watchdog put the stock fan back"
        case .readOnlyCard: return "this card can only be read (RX 6900 XT, 73BF rev C0): writing never opens on it"
        }
    }
}

/// `status`'s flags (`kFlag*`).
struct GPUControlFlags: OptionSet, Hashable, Sendable {
    let rawValue: UInt64

    /// An administrator opened writing since the restart, and (0.8.0)
    /// nobody closed it again.
    static let armed = GPUControlFlags(rawValue: 1)
    /// Writing is off until restart, or (0.8.0) the card is read only.
    static let off = GPUControlFlags(rawValue: 2)
    static let sleeping = GPUControlFlags(rawValue: 4)
    /// A way back to the start-up values is running.
    static let reverting = GPUControlFlags(rawValue: 8)
    /// Something may differ from the start-up values.
    static let changed = GPUControlFlags(rawValue: 16)
    /// Some program holds a change.
    static let owned = GPUControlFlags(rawValue: 32)
    /// The connection that asked does.
    static let mine = GPUControlFlags(rawValue: 64)
    /// The driver's power management and the start-up limit are known.
    static let ready = GPUControlFlags(rawValue: 128)
    /// OD8 was read cleanly since boot: `setOD8` can work.
    static let od8Ready = GPUControlFlags(rawValue: 256)
}

/// What the confirmed OD8 state changes (`kOd8Held*`).
struct GPUControlOD8Held: OptionSet, Hashable, Sendable {
    let rawValue: UInt64

    static let curve = GPUControlOD8Held(rawValue: 1)
    static let zeroRpmOff = GPUControlOD8Held(rawValue: 2)
    static let gfxMax = GPUControlOD8Held(rawValue: 4)
    /// Not confirmed at stock: a failed call, or one the GPU did not take.
    static let unknown = GPUControlOD8Held(rawValue: 8)
}

/// The 13 scalars `status` returns, in the kext's order (`StatusField`).
/// Anyone may ask, whether or not it holds the control.
struct GPUControlChannelStatus: Equatable, Sendable {
    /// `ok`, or `badVersion` from a kext that speaks another version; then
    /// only `version` is certain to be filled.
    var replyCode: UInt64
    /// The channel version of the kext.
    var version: UInt64
    var flags: GPUControlFlags
    /// The start-up limit in watts, 0 until the kext read it.
    var bootW: UInt64
    /// The limit held now; the start-up one while nothing is held.
    var heldW: UInt64
    /// `GPUControlWriteOff`, 0 while writing can be opened.
    var writeOffCode: UInt64
    var changes: UInt64
    var reverts: UInt64
    /// The last `set`'s reply.
    var lastReplyCode: UInt64
    var od8Held: GPUControlOD8Held
    var od8Changes: UInt64
    var od8Reverts: UInt64
    /// The last OD8 refusal (`GPUControlOD8Check`).
    var od8CheckCode: UInt64

    var reply: GPUControlReply? { GPUControlReply(rawValue: replyCode) }
    var writeOff: GPUControlWriteOff? { GPUControlWriteOff(rawValue: writeOffCode) }
    /// A lower power limit is on the card.
    var holdsPower: Bool { bootW != 0 && heldW != bootW }
    /// An OD8 change is, or may be, on the card.
    var holdsOD8: Bool { !od8Held.isEmpty }

    /// Nil unless the scalars are a whole answer: all 13 for `ok`; a kext
    /// with another channel version may return fewer (version 1 has 9), and
    /// then the reply and its version are enough.
    init?(scalars: [UInt64]) {
        guard scalars.count >= 2 else { return nil }
        let isBadVersion = scalars[0] == GPUControlReply.badVersion.rawValue
        guard isBadVersion || scalars.count >= GPUControlWire.statusCount else { return nil }
        func field(_ index: Int) -> UInt64 { index < scalars.count ? scalars[index] : 0 }
        replyCode = field(0)
        version = field(1)
        flags = GPUControlFlags(rawValue: field(2))
        bootW = field(3)
        heldW = field(4)
        writeOffCode = field(5)
        changes = field(6)
        reverts = field(7)
        lastReplyCode = field(8)
        od8Held = GPUControlOD8Held(rawValue: field(9))
        od8Changes = field(10)
        od8Reverts = field(11)
        od8CheckCode = field(12)
    }

    /// The scalars again, as the kext would write them.
    var scalars: [UInt64] {
        [replyCode, version, flags.rawValue, bootW, heldW, writeOffCode, changes, reverts,
         lastReplyCode, od8Held.rawValue, od8Changes, od8Reverts, od8CheckCode]
    }
}

/// What a call other than `status` answered: the reply as the kext wrote it,
/// and for `setOD8` why the state was refused.
struct GPUControlAnswer: Equatable, Sendable {
    var replyCode: UInt64
    /// `GPUControlOD8Check`; only with `od8Refused`, else 0.
    var checkCode: UInt64 = 0

    var reply: GPUControlReply? { GPUControlReply(rawValue: replyCode) }
    var check: GPUControlOD8Check? { GPUControlOD8Check(rawValue: checkCode) }

    /// The kext's words for this answer; a number this app does not know is
    /// shown as the number.
    var kextText: String {
        if reply == .od8Refused, checkCode != 0 {
            return check?.kextText ?? "OD8 check \(checkCode)"
        }
        return reply?.kextText ?? "reply \(replyCode)"
    }
}

/// One point of a fan curve.
struct GPUControlFanPoint: Equatable, Hashable, Sendable {
    var temperatureC: Int
    var speedPercent: Int
}

/// The whole OD8 state a program wants, never one setting: the kext takes
/// the fan curve, zero RPM and the GFX maximum clock together in every call,
/// so a request that left one out would put that one back to stock.
struct GPUControlOD8Want: Equatable, Hashable, Sendable {
    /// Five points, or nil for the stock fan.
    var curve: [GPUControlFanPoint]?
    /// True keeps the fan turning; false is the stock behaviour.
    var zeroRpmOff = false
    /// A lower GFX maximum clock in MHz, or nil for stock.
    var gfxMaxMHz: Int?

    static let stock = GPUControlOD8Want()

    /// The stock state is the way back, never a change (`od8IsStock`).
    var isStock: Bool { curve == nil && !zeroRpmOff && gfxMaxMHz == nil }

    /// What `status` reports while this state is held (`od8HeldFlags`).
    var heldFlags: GPUControlOD8Held {
        var held: GPUControlOD8Held = []
        if curve != nil { held.insert(.curve) }
        if zeroRpmOff { held.insert(.zeroRpmOff) }
        if gfxMaxMHz != nil { held.insert(.gfxMax) }
        return held
    }

    /// The 13 scalars of `setOD8` for this state, as `gpucontrol` builds
    /// them: without a curve its ten entries are 0, and a stock clock is 0.
    /// Nil when the state cannot be written as scalars at all (a curve that
    /// is not five points, a negative number, a clock of 0 that would read as
    /// "stock"). Every other value goes out unchanged: the kext decides, and
    /// the app never clamps.
    func scalars() -> [UInt64]? {
        var input = [UInt64](repeating: 0, count: GPUControlWire.setOD8InputCount)
        input[0] = GPUControlWire.channelVersion
        input[1] = (curve != nil ? GPUControlWire.wantCurve : 0) | (zeroRpmOff ? GPUControlWire.wantZeroRpmOff : 0)
        if let curve {
            guard curve.count == GPUControlWire.fanCurvePoints else { return nil }
            for (index, point) in curve.enumerated() {
                guard point.temperatureC >= 0, point.speedPercent >= 0 else { return nil }
                input[2 + index] = UInt64(point.temperatureC)
                input[7 + index] = UInt64(point.speedPercent)
            }
        }
        if let gfxMaxMHz {
            guard gfxMaxMHz > 0 else { return nil }
            input[12] = UInt64(gfxMaxMHz)
        }
        return input
    }
}

/// The sentences the app shows for the kext's numbers. The kext answers with
/// 20 replies besides "ok", 11 OD8 refusals and 15 reasons that keep writing
/// off; the app translates one sentence per group and puts the kext's own
/// English text under it. A number this app does not know has no group and is
/// shown as the kext wrote it.
enum GPUControlTextGroup: CaseIterable, Sendable {
    /// The value is outside what the kext takes.
    case notAllowed
    /// The kext is busy; trying again shortly can work.
    case busy
    /// Not ready yet: the Mac is waking, the driver has not started, or the
    /// card's values moved since boot.
    case notReady
    /// Writing is off until restart.
    case writingOff
    /// Writing is still closed: an administrator has to open it.
    case closed
    case needsAdministrator
    /// The kext speaks another version of the channel.
    case otherVersion
    /// Not confirmed; the kext went back to the start-up values.
    case unconfirmed
    /// This program holds nothing.
    case notOwner
    /// A setting the request needs is not available now.
    case settingMissing
    /// Off: the driver, the card or the start is not as expected.
    case offNotAsExpected
    /// Off: a change could not be confirmed. Restart the Mac.
    case offChangeUnconfirmed
    /// Off: the GPU driver stopped or the Mac is shutting down.
    case offDriverStopped
    /// Off: the fan watchdog put the stock fan back.
    case offWatchdog

    /// Nil for "ok" and for a reply this app does not know. `od8Refused`
    /// takes the group of its reason.
    static func forReply(_ code: UInt64, check: UInt64 = 0) -> GPUControlTextGroup? {
        guard let reply = GPUControlReply(rawValue: code) else { return nil }
        switch reply {
        case .ok: return nil
        case .badVersion: return .otherVersion
        case .badArgs, .belowFloor, .aboveBoot, .notAStep: return .notAllowed
        // Until the page has its own sentences for them.
        case .noFloor: return .notReady
        case .stillApplied: return .busy
        case .notPrivileged: return .needsAdministrator
        case .off: return .writingOff
        case .notArmed: return .closed
        case .noBootValue, .notReady, .sleeping, .cancelled: return .notReady
        case .busy, .tooSoon: return .busy
        case .timeout, .failed: return .unconfirmed
        case .notOwner: return .notOwner
        case .od8Refused: return forOD8Check(check) ?? .notAllowed
        }
    }

    /// Nil for "ok" and for a reason this app does not know.
    static func forOD8Check(_ code: UInt64) -> GPUControlTextGroup? {
        guard let check = GPUControlOD8Check(rawValue: code) else { return nil }
        switch check {
        case .ok: return nil
        case .notRead, .drifted, .memoryMoved: return .notReady
        case .noFeature, .noReadings: return .settingMissing
        case .curveRange, .curveOrder, .curveFirst, .curveLast, .curveCooling, .gfxRange: return .notAllowed
        }
    }

    /// Nil while writing is not off and for a reason this app does not know.
    static func forWriteOff(_ code: UInt64) -> GPUControlTextGroup? {
        guard let reason = GPUControlWriteOff(rawValue: code) else { return nil }
        switch reason {
        case .none: return nil
        case .ctlOff, .notOneCard, .otherAmdGpu, .library, .routes, .cwdde, .secondObject, .bootImplausible, .start:
            return .offNotAsExpected
        case .sendFailed, .revertFailed, .od8Failed: return .offChangeUnconfirmed
        case .teardown: return .offDriverStopped
        case .od8Watchdog: return .offWatchdog
        case .readOnlyCard: return .offNotAsExpected
        }
    }
}
