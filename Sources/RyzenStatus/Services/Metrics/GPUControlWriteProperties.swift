// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

extension GPUControlStatus {
    /// What GPUSensors.kext 0.5.0 and later publish about writing: the power
    /// limit's write path (`Write`, `WriteState`, 0.5.0), the OD8 readout
    /// (`OD8State`, `OD8`, 0.6.0) and the OD8 writes (`OD8Write`,
    /// `OD8WriteState`, 0.7.0). Read from the same whole-table read as the
    /// sensors, without opening the control channel, so the app can tell the
    /// state before it ever connects. Nothing here says whether this app
    /// holds a change: only the channel's `status` knows which connection
    /// asks.
    struct Writing: Equatable {
        /// `Write` and `OD8Write`: where the write path stands, in the
        /// kext's own order of checks.
        enum Gate: Equatable {
            /// Off until restart, or the control never started.
            case off
            /// The driver, its start-up limit or a clean OD8 read is missing.
            case waiting
            /// An administrator has not opened writing since the restart.
            case closed
            case sleeping
            /// Going back to the start-up values.
            case reverting
            /// Some program holds a change.
            case held
            /// `OD8Write` only: the last call was not taken; stock is on its way.
            case unconfirmed
            /// Open, nothing held.
            case idle
            /// A text this app does not know, as the kext wrote it.
            case other(String)
        }

        /// `WriteState`.
        struct State: Equatable {
            /// `GPUControlWriteOff`, 0 while writing can be opened.
            var writeOff: Int?
            /// The kext's reason, empty while writing is not off.
            var writeOffText: String?
            var armed: Bool?
            var owned: Bool?
            /// The limit held now; the start-up one while nothing is held.
            var heldW: Int?
            var changes: Int?
            var reverts: Int?
            /// The last `set`'s reply (`GPUControlReply`).
            var lastReply: Int?
        }

        /// `OD8WriteState`.
        struct OD8State: Equatable {
            var held: GPUControlOD8Held?
            var changes: Int?
            var reverts: Int?
            /// Why the last OD8 request was refused (`GPUControlOD8Check`).
            var lastCheck: Int?
            var lastCheckText: String?
            /// Power limit sends the kext saw during OD8 calls.
            var sentPower: Int?
            /// The curve held now, nil at stock.
            var fanCurveHeld: [GPUControlFanPoint]?
            /// The GFX maximum held now in MHz, nil at stock.
            var gfxMaxHeld: Int?
        }

        /// `OD8State`: whether the kext read OD8 since boot.
        enum OD8Read: Equatable {
            /// Read, every entry as expected: OD8 writes can be checked.
            case read
            /// Anything else, as the kext wrote it: waiting, off, no data,
            /// read with an entry that is not as expected.
            case notClean(String)
        }

        /// One OD8 setting of `OD8.Settings`. Signed: the kext publishes its
        /// 32-bit values as their two's complement.
        struct OD8Setting: Equatable {
            /// The setting's feature bit, 0 when the card does not offer it.
            var feature: UInt32
            var min: Int
            var max: Int
            /// The first read after boot.
            var stock: Int
            /// The driver's default at the last read; equal to `stock` when
            /// the kext does not publish it.
            var defaultNow: Int
            var current: Int
        }

        /// `OD8`. `LastReadAgeS` is left out on purpose: it moves every
        /// second and nothing in the app decides on it.
        struct OD8Table: Equatable {
            var reads: Int?
            var tries: Int?
            var lastResult: UInt32?
            var oddEntry: Int?
            var oddEscape: UInt32?
            var caps: UInt32?
            /// Features NOT allowed now (the inverse of a mask).
            var notAllowed: UInt32?
            var stockOdd: Bool?
            var defaultsMoved: Bool?
            var currentMoved: Bool?
            var fanCurveStock: [GPUControlFanPoint]?
            var fanCurve: [GPUControlFanPoint]?
            /// By the kext's setting name (`GfxMaxMHz`, `FanCurve1C`, ...).
            var settings: [String: OD8Setting]

            /// The stock GFX maximum a request may not pass: the lower of
            /// the first read and the driver's default now (`od8StockGfxMax`).
            var stockGfxMaxMHz: Int? {
                guard let setting = settings["GfxMaxMHz"], setting.feature != 0 else { return nil }
                return Swift.min(setting.stock, setting.defaultNow)
            }
        }

        /// `Write`, as the kext wrote it.
        var text: String
        var gate: Gate
        var state: State?
        /// `OD8Write`, nil before 0.7.0.
        var od8Text: String?
        var od8Gate: Gate?
        var od8State: OD8State?
        /// `OD8State`, nil before 0.6.0.
        var od8Read: OD8Read?
        var od8: OD8Table?

        /// Nil for a kext without the write path (before 0.5.0): there is no
        /// `Write` text, so there is nothing to control.
        static func parse(_ properties: [String: Any]) -> Writing? {
            guard let text = GPUControlStatus.text(properties["Write"]) else { return nil }
            let od8Text = GPUControlStatus.text(properties["OD8Write"])
            return Writing(
                text: text,
                gate: Gate.parse(text),
                state: State.parse(properties["WriteState"]),
                od8Text: od8Text,
                od8Gate: od8Text.map(Gate.parse),
                od8State: OD8State.parse(properties["OD8WriteState"]),
                od8Read: GPUControlStatus.text(properties["OD8State"]).map(OD8Read.parse),
                od8: OD8Table.parse(properties["OD8"]))
        }
    }

    /// A signed 32-bit value: the kext's OD8 numbers are `int32_t` published
    /// as 32-bit numbers, so -6 can arrive as -6 or as 4294967290. Nil for
    /// anything that is not a whole number of 32 bits.
    static func signed32(_ raw: Any?) -> Int? {
        bits32(raw).map { Int(Int32(bitPattern: $0)) }
    }

    /// The same 32 bits as an unsigned word (feature bits, masks, results).
    static func bits32(_ raw: Any?) -> UInt32? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value == value.rounded(),
              value >= Double(Int32.min), value <= Double(UInt32.max) else { return nil }
        return UInt32(truncatingIfNeeded: number.int64Value)
    }

    /// The kext publishes its booleans as the numbers 0 and 1.
    static func flag(_ raw: Any?) -> Bool? {
        integer(raw).map { $0 != 0 }
    }

    /// Five `[C, %]` pairs (`OD8.FanCurve`, `OD8.FanCurveStock`); nil for
    /// anything else, so a curve is never shown with a point missing.
    static func fanCurvePairs(_ raw: Any?) -> [GPUControlFanPoint]? {
        guard let pairs = raw as? [Any], pairs.count == GPUControlWire.fanCurvePoints else { return nil }
        var points: [GPUControlFanPoint] = []
        for pair in pairs {
            guard let values = pair as? [Any], values.count == 2,
                  let temperature = signed32(values[0]), let speed = signed32(values[1]) else { return nil }
            points.append(GPUControlFanPoint(temperatureC: temperature, speedPercent: speed))
        }
        return points
    }

    /// Five numbers of `C x 1000 + %` (`OD8WriteState.FanCurveHeld`).
    static func fanCurvePacked(_ raw: Any?) -> [GPUControlFanPoint]? {
        guard let values = raw as? [Any], values.count == GPUControlWire.fanCurvePoints else { return nil }
        var points: [GPUControlFanPoint] = []
        for value in values {
            guard let packed = integer(value) else { return nil }
            points.append(GPUControlFanPoint(temperatureC: packed / 1_000, speedPercent: packed % 1_000))
        }
        return points
    }
}

extension GPUControlStatus.Writing.Gate {
    /// The texts of `GPUControl::writeText()` and `od8WriteText()`
    /// (kern_control.cpp).
    static func parse(_ text: String) -> Self {
        func starts(_ word: String) -> Bool { GPUControlStatus.starts(text, with: word) }
        if starts("off") { return .off }
        if starts("waiting") { return .waiting }
        if starts("closed") { return .closed }
        guard starts("armed"), let rest = GPUControlStatus.reason(text, after: "armed") else { return .other(text) }
        if rest.hasPrefix("the Mac is between sleep and wake") { return .sleeping }
        if rest.hasPrefix("the last OD8 call was not taken") { return .unconfirmed }
        if rest.hasPrefix("going back") { return .reverting }
        if rest.hasPrefix("a program holds") { return .held }
        if rest == "nothing held" || rest == "OD8 at stock" { return .idle }
        return .other(text)
    }
}

extension GPUControlStatus.Writing.State {
    static func parse(_ raw: Any?) -> Self? {
        guard let dict = raw as? [String: Any] else { return nil }
        func n(_ key: String) -> Int? { GPUControlStatus.integer(dict[key]) }
        return Self(writeOff: n("WriteOff"),
                    // Kept even when empty: an empty text is the kext saying "not off".
                    writeOffText: (dict["WriteOffText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    armed: GPUControlStatus.flag(dict["Armed"]), owned: GPUControlStatus.flag(dict["Owned"]),
                    heldW: n("HeldW"), changes: n("Changes"), reverts: n("Reverts"), lastReply: n("LastReply"))
    }
}

extension GPUControlStatus.Writing.OD8State {
    static func parse(_ raw: Any?) -> Self? {
        guard let dict = raw as? [String: Any] else { return nil }
        func n(_ key: String) -> Int? { GPUControlStatus.integer(dict[key]) }
        return Self(held: n("Held").map { GPUControlOD8Held(rawValue: UInt64($0)) },
                    changes: n("Changes"), reverts: n("Reverts"), lastCheck: n("LastCheck"),
                    lastCheckText: GPUControlStatus.text(dict["LastCheckText"]), sentPower: n("SentPower"),
                    fanCurveHeld: GPUControlStatus.fanCurvePacked(dict["FanCurveHeld"]),
                    gfxMaxHeld: n("GfxMaxHeld").flatMap { $0 > 0 ? $0 : nil })
    }
}

extension GPUControlStatus.Writing.OD8Read {
    /// The texts of `GPUControl::od8Text()`: only a bare "read" is a clean
    /// read ("read, but an entry is not as expected" is not).
    static func parse(_ text: String) -> Self {
        text == "read" ? .read : .notClean(text)
    }
}

extension GPUControlStatus.Writing.OD8Setting {
    /// Nil unless the entry has every number `gpucontrol check` reads.
    static func parse(_ raw: Any?) -> Self? {
        guard let dict = raw as? [String: Any],
              let feature = GPUControlStatus.bits32(dict["Feature"]),
              let min = GPUControlStatus.signed32(dict["Min"]),
              let max = GPUControlStatus.signed32(dict["Max"]),
              let stock = GPUControlStatus.signed32(dict["Stock"]),
              let current = GPUControlStatus.signed32(dict["Current"]) else { return nil }
        return Self(feature: feature, min: min, max: max, stock: stock,
                    defaultNow: GPUControlStatus.signed32(dict["Default"]) ?? stock, current: current)
    }
}

extension GPUControlStatus.Writing.OD8Table {
    static func parse(_ raw: Any?) -> Self? {
        guard let dict = raw as? [String: Any] else { return nil }
        func n(_ key: String) -> Int? { GPUControlStatus.integer(dict[key]) }
        func bits(_ key: String) -> UInt32? { GPUControlStatus.bits32(dict[key]) }
        func flag(_ key: String) -> Bool? { GPUControlStatus.flag(dict[key]) }
        var settings: [String: GPUControlStatus.Writing.OD8Setting] = [:]
        for (name, entry) in (dict["Settings"] as? [String: Any]) ?? [:] {
            if let setting = GPUControlStatus.Writing.OD8Setting.parse(entry) { settings[name] = setting }
        }
        return Self(reads: n("Reads"), tries: n("Tries"), lastResult: bits("LastResult"),
                    oddEntry: n("OddEntry"), oddEscape: bits("OddEscape"), caps: bits("Caps"),
                    notAllowed: bits("NotAllowed"), stockOdd: flag("StockOdd"),
                    defaultsMoved: flag("DefaultsMoved"), currentMoved: flag("CurrentMoved"),
                    fanCurveStock: GPUControlStatus.fanCurvePairs(dict["FanCurveStock"]),
                    fanCurve: GPUControlStatus.fanCurvePairs(dict["FanCurve"]), settings: settings)
    }
}
