// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The kext's checks of an OD8 state (`od8CheckWant`, `od8StockCurveAt`,
/// `od8WantCurveAt`, `od8SameLayout` and `od8StockGfxMax` in
/// GPUSensors.kext's `control_logic.hpp`), copied so the fan curve editor can
/// say while editing whether the kext would take the curve (plan 10, D5).
///
/// Only the kext's constants are copied (22 C gap, 30 C first point,
/// 1500 MHz floor, 25 MHz drift); every range, stock value and feature bit
/// comes from the OD8 table the kext publishes. The copy is checked against
/// the kext's own code by `Tests/Fixtures/GPUSensors/curve-cases.jsonl`,
/// generated from the real `control_logic.hpp`.
///
/// What the preview cannot see: the kext checks against its first read and a
/// fresh read made right before the call, while the app has one published
/// table, so it builds both from it and sees less drift than the kext; and
/// the freshness of the fan watchdog's readings. Those refusals arrive when
/// the curve is applied.
enum GPUControlCurveRules {
    static let entryCount = 38
    static let gfxMax = 0, gfxMin = 1, memMax = 8, targetTemp = 12, zeroRpm = 15, zeroRpmStop = 35
    static let points = GPUControlWire.fanCurvePoints
    static func tempID(_ k: Int) -> Int { 19 + 2 * k }
    static func speedID(_ k: Int) -> Int { 20 + 2 * k }

    // The kext's constants (control_logic.hpp:606-617).
    static let gfxFloorMHz = 1_500
    static let driftMHz = 25
    static let sensorGapC = 22
    static let firstPointMaxC = 30

    /// The kext builds this copy was checked against (`VersionInfo`). With
    /// any other build the preview says so and does not decide.
    static let checkedVersions: Set<String> = ["REL-072-2026-11-19"]

    /// Kext versions checked as a whole: `VersionInfo` is "REL-", the
    /// version's digits, then the build date, and the date comes from
    /// SOURCE_DATE_EPOCH when the GPU package is built (the date of the last
    /// commit under GPU/), so it changes with every rebuild of the same
    /// source. GPUSensors 0.8.0 ("080"): its `od8CheckWant` gives the same
    /// answers as 0.7.2's for every line of `curve-cases.jsonl`, and its
    /// source is GPU/sensors/kext in this repository. GPUSensors 0.8.1
    /// ("081") leaves these checks as they were in 0.8.0. GPUSensors 0.9.0
    /// ("090") adds the GFX minimum (`GfxMinRange`) and gives the same
    /// answers as 0.8.0 for the first 100 lines of `curve-cases.jsonl`; the
    /// lines after them are its GFX minimum cases.
    static let checkedReleases: Set<String> = ["080", "081", "090"]

    /// The kext build is one this copy was checked against. Neither the
    /// editor nor a remembered fan state sends anything to another build.
    static func isChecked(_ version: String?) -> Bool {
        guard let version else { return false }
        return checkedVersions.contains(version) || release(of: version).map(checkedReleases.contains) == true
    }

    /// "080" for "REL-080-2026-11-21": a release build's version digits,
    /// when the rest is a date. Nil for a debug build ("DBG-…") or any
    /// other shape.
    static func release(of version: String) -> String? {
        let parts = version.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "REL",
              parts[1].count == 3, parts[2].count == 4, parts[3].count == 2, parts[4].count == 2,
              parts[1...].allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return String(parts[1])
    }

    /// The 100 % temperature on the card here, for a table without a usable
    /// target (the preview refuses such a table anyway).
    static let cardLimitC = 48

    /// `od8Name`: the published setting names by entry id.
    static let names = [
        "GfxMaxMHz", "GfxMinMHz", "GfxPoint1MHz", "GfxPoint1mV", "GfxPoint2MHz", "GfxPoint2mV", "GfxPoint3MHz",
        "GfxPoint3mV", "MemMaxMHz", "PowerPercent", "FanMinRPM", "FanAcousticRPM", "FanTargetC", "OperatingMaxC",
        "AcTiming", "FanZeroRpm", "AutoUndervolt", "AutoOcGfx", "AutoOcMem", "FanCurve1C", "FanCurve1Pct",
        "FanCurve2C", "FanCurve2Pct", "FanCurve3C", "FanCurve3Pct", "FanCurve4C", "FanCurve4Pct", "FanCurve5C",
        "FanCurve5Pct", "AutoFanAcoustic", "GfxCurveA", "GfxCurveB", "GfxCurveC", "GfxCurveD", "MemMinMHz",
        "FanZeroRpmStopC", "PowerMode", "GfxVoltOffset",
    ]

    /// One OD8 entry (`Od8Entry`).
    struct Entry: Equatable, Sendable {
        var feature: UInt32 = 0
        var min = 0
        var max = 0
        var def = 0
    }

    /// The kext's three reads: the first clean one after boot, the fresh one
    /// right before a call, and the current values.
    struct State: Equatable, Sendable {
        var firstCaps: UInt32 = 0
        var freshCaps: UInt32 = 0
        var first = [Entry](repeating: Entry(), count: GPUControlCurveRules.entryCount)
        var fresh = [Entry](repeating: Entry(), count: GPUControlCurveRules.entryCount)
        var current = [Int](repeating: 0, count: GPUControlCurveRules.entryCount)

        init() {}

        /// From the published table, as `gpucontrol check` maps it: Stock is
        /// the first read, Default the fresh one, Current the current values,
        /// Feature/Min/Max the same for both. A setting the kext leaves out
        /// (nothing there for this card) stays zero, as in the kext. Nil
        /// without the capabilities word.
        init?(table: GPUControlStatus.Writing.OD8Table) {
            guard let caps = table.caps else { return nil }
            firstCaps = caps
            freshCaps = caps
            for (id, name) in GPUControlCurveRules.names.enumerated() {
                guard let setting = table.settings[name] else { continue }
                first[id] = Entry(feature: setting.feature, min: setting.min, max: setting.max, def: setting.stock)
                fresh[id] = Entry(feature: setting.feature, min: setting.min, max: setting.max, def: setting.defaultNow)
                current[id] = setting.current
            }
        }

        /// The stock curve (the first read's defaults).
        var stockCurve: [GPUControlFanPoint] {
            (0..<GPUControlCurveRules.points).map {
                GPUControlFanPoint(temperatureC: first[GPUControlCurveRules.tempID($0)].def,
                                   speedPercent: first[GPUControlCurveRules.speedID($0)].def)
            }
        }

        /// The temperature by which an accepted curve is at 100 %: the
        /// target minus the 22 C gap (48 C on the card here). A target
        /// outside 40 to 100 C (or none published) is one the kext refuses;
        /// the chart and the footer then keep the card's 48 C.
        var limitC: Int {
            let target = first[GPUControlCurveRules.targetTemp].def
            return (40...100).contains(target) ? target - GPUControlCurveRules.sensorGapC
                : GPUControlCurveRules.cardLimitC
        }
    }

    struct Result: Equatable, Sendable {
        var check: GPUControlOD8Check
        /// The curve point (1 to 5) that fails, for the curve checks.
        var point: Int?

        static let ok = Result(check: .ok)
    }

    /// `od8StockCurveAt`: straight lines between the stock points, rounded up.
    static func stockCurveAt(_ state: State, _ t: Int) -> Int {
        let curve = state.stockCurve
        if t <= curve[0].temperatureC { return curve[0].speedPercent }
        for k in 0..<(points - 1) where t <= curve[k + 1].temperatureC {
            let dt = curve[k + 1].temperatureC - curve[k].temperatureC
            if dt <= 0 { return curve[k + 1].speedPercent }
            let num = (curve[k + 1].speedPercent - curve[k].speedPercent) * (t - curve[k].temperatureC)
            return curve[k].speedPercent + (num + dt - 1) / dt
        }
        return curve[points - 1].speedPercent
    }

    /// `od8WantCurveAt`: the same, rounded down (Swift and C++ both truncate).
    static func wantCurveAt(_ curve: [GPUControlFanPoint], _ t: Int) -> Int {
        if t <= curve[0].temperatureC { return curve[0].speedPercent }
        for k in 0..<(points - 1) where t <= curve[k + 1].temperatureC {
            let dt = curve[k + 1].temperatureC - curve[k].temperatureC
            if dt <= 0 { return curve[k + 1].speedPercent }
            return curve[k].speedPercent
                + (curve[k + 1].speedPercent - curve[k].speedPercent) * (t - curve[k].temperatureC) / dt
        }
        return curve[points - 1].speedPercent
    }

    /// `od8CheckWant`, step by step in the kext's order. `notRead` and
    /// `noReadings` never come from here: the kext gives them elsewhere
    /// (first read not clean, kern_control.cpp:995; watchdog without fresh
    /// readings, kern_control.cpp:1115).
    static func check(_ want: GPUControlOD8Want, _ s: State) -> Result {
        // od8SameLayout: caps, feature bits and ranges as at boot.
        if s.firstCaps != s.freshCaps { return Result(check: .drifted) }
        for id in 0..<entryCount {
            let a = s.first[id], b = s.fresh[id]
            if a.feature != b.feature || a.min != b.min || a.max != b.max { return Result(check: .drifted) }
        }
        for id in 0..<entryCount {
            let d = abs(s.first[id].def - s.fresh[id].def)
            let isGfx = id == gfxMax || id == gfxMin
            if isGfx ? d > driftMHz : d != 0 { return Result(check: .drifted) }
        }
        if s.current[memMax] != s.first[memMax].def { return Result(check: .memoryMoved) }
        let z = s.first[zeroRpm], zs = s.first[zeroRpmStop]
        if s.first[gfxMax].feature != 0x1 || s.first[gfxMin].feature != 0x1 || z.feature != 0x200 || z.def != 1
            || zs.feature != 0x200 || zs.min != zs.max || zs.def != zs.min {
            return Result(check: .noFeature)
        }
        for k in 0..<points where s.first[tempID(k)].feature != 0x2000 || s.first[speedID(k)].feature != 0x2000 {
            return Result(check: .noFeature)
        }
        let target = s.first[targetTemp].def
        if target < 40 || target > 100 { return Result(check: .noFeature) }

        if let curve = want.curve {
            guard curve.count == points else { return Result(check: .curveRange) }
            for k in 0..<points {
                let te = s.fresh[tempID(k)], se = s.fresh[speedID(k)]
                let p = curve[k]
                if p.temperatureC <= 0 || p.speedPercent <= 0 || p.temperatureC < te.min || p.temperatureC > te.max
                    || p.speedPercent < se.min || p.speedPercent > se.max {
                    return Result(check: .curveRange, point: k + 1)
                }
                if k > 0, p.temperatureC <= curve[k - 1].temperatureC || p.speedPercent < curve[k - 1].speedPercent {
                    return Result(check: .curveOrder, point: k + 1)
                }
            }
            if curve[0].temperatureC > firstPointMaxC { return Result(check: .curveFirst, point: 1) }
            if curve[points - 1].speedPercent != 100 || curve[points - 1].temperatureC > target - sensorGapC {
                return Result(check: .curveLast, point: points)
            }
            for k in 0..<points {
                let tw = curve[k].temperatureC, ts = s.first[tempID(k)].def
                if wantCurveAt(curve, tw) < stockCurveAt(s, tw) || wantCurveAt(curve, ts) < stockCurveAt(s, ts) {
                    return Result(check: .curveCooling, point: k + 1)
                }
            }
        }
        if let mhz = want.gfxMaxMHz {
            let top = Swift.min(s.first[gfxMax].def, s.fresh[gfxMax].def)
            if mhz < gfxFloorMHz || mhz > top || mhz < s.first[gfxMin].def { return Result(check: .gfxRange) }
        }
        // GPUSensors 0.9.0: the minimum in the card's range for id 1 (the
        // same in both reads, checked above) and never above the maximum of
        // the same state.
        if let low = want.gfxMinMHz {
            let range = s.fresh[gfxMin]
            let top = want.gfxMaxMHz ?? Swift.min(s.first[gfxMax].def, s.fresh[gfxMax].def)
            if low < range.min || low > range.max || low > top { return Result(check: .gfxMinRange) }
        }
        return .ok
    }
}

/// What the editor says about a draft.
enum GPUControlCurvePreview: Equatable, Sendable {
    /// The kext would take it.
    case accepted
    case refused(GPUControlCurveRules.Result)
    /// The kext is a build the copy was not checked against.
    case notChecked
    /// OD8 is not read cleanly, or the table is incomplete.
    case unavailable

    var allowsApply: Bool { self == .accepted }

    static func make(want: GPUControlOD8Want, writing: GPUControlStatus.Writing?) -> GPUControlCurvePreview {
        guard let writing, writing.od8Read == .read, let table = writing.od8,
              let state = GPUControlCurveRules.State(table: table) else { return .unavailable }
        guard GPUControlCurveRules.isChecked(writing.kextVersion) else { return .notChecked }
        let result = GPUControlCurveRules.check(want, state)
        return result.check == .ok ? .accepted : .refused(result)
    }
}

/// The editor's draft: what the page sends with "Apply curve".
struct GPUControlFanDraft: Equatable, Sendable {
    /// The one curve run on the card (plan 7.3).
    static let testedCurve = [(30, 20), (40, 36), (44, 52), (46, 68), (48, 100)]
        .map { GPUControlFanPoint(temperatureC: $0.0, speedPercent: $0.1) }

    // Every change from a control marks the draft as edited. Observers do
    // not run in the initializer, so a draft seeded from what is held starts
    // unedited.
    var customCurve = false { didSet { edited = true } }
    var points = GPUControlFanDraft.testedCurve { didSet { edited = true } }
    var zeroRpmOff = false { didSet { edited = true } }
    /// The owner touched the editor since it was last seeded or applied.
    /// A flag, not a comparison with the seed: an edit set back to the
    /// seeded values is still the owner's, and stays.
    var edited = false

    /// The whole OD8 state for the request (the GFX maximum is added by the
    /// controller from what is held).
    var want: GPUControlOD8Want {
        GPUControlOD8Want(curve: customCurve ? points : nil, zeroRpmOff: zeroRpmOff)
    }

    /// The draft that matches a held state, else the starting one.
    init(held: GPUControlOD8Want? = nil) {
        guard let held else { return }
        customCurve = held.curve != nil
        points = held.curve ?? GPUControlFanDraft.testedCurve
        zeroRpmOff = held.zeroRpmOff
    }

    /// The draft once the held fan state changed to `held`: a draft the
    /// owner has not touched is seeded again from it, an edit stays.
    func following(held: GPUControlOD8Want) -> GPUControlFanDraft {
        edited ? self : GPUControlFanDraft(held: held)
    }

    /// The draft once it was sent: no longer an edit, so the state the kext
    /// reports next seeds it again.
    var applied: GPUControlFanDraft {
        var draft = self
        draft.edited = false
        return draft
    }

    /// Applying this draft gives the whole OD8 hold back (the way back to
    /// the start-up values): it is the stock fan over a held fan state, with
    /// no clock held.
    func givesBack(_ held: GPUControlOD8Want) -> Bool {
        want.isStock && (held.curve != nil || held.zeroRpmOff) && held.gfxMaxMHz == nil && held.gfxMinMHz == nil
    }
}
