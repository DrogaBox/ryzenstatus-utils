// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// The card a profile was made on: its PCI device id and the limits the kext
/// reported when it was saved. A profile from another card is never refused
/// for that alone: the numbers are here so the page can say that what was
/// left out was left out because this card is a different one.
struct GPUControlProfileCard: Codable, Equatable, Sendable {
    var deviceID: UInt32?
    /// The start-up power limit, in watts.
    var bootW: Int?
    var floorW: Int?
    var ceilW: Int?
    var stockGfxMaxMHz: Int?
    var gfxMaxTopMHz: Int?
    var gfxMinStockMHz: Int?
    var voltStockMV: Int?
    var voltMinMV: Int?

    static let unknown = GPUControlProfileCard()

    init(deviceID: UInt32? = nil, bootW: Int? = nil, floorW: Int? = nil, ceilW: Int? = nil,
         stockGfxMaxMHz: Int? = nil, gfxMaxTopMHz: Int? = nil, gfxMinStockMHz: Int? = nil,
         voltStockMV: Int? = nil, voltMinMV: Int? = nil) {
        self.deviceID = deviceID
        self.bootW = bootW
        self.floorW = floorW
        self.ceilW = ceilW
        self.stockGfxMaxMHz = stockGfxMaxMHz
        self.gfxMaxTopMHz = gfxMaxTopMHz
        self.gfxMinStockMHz = gfxMinStockMHz
        self.voltStockMV = voltStockMV
        self.voltMinMV = voltMinMV
    }

    /// The card as the kext and the registry describe it now.
    static func current(facts: GPUControlFacts?, writing: GPUControlStatus.Writing?,
                        deviceID: UInt32?) -> Self {
        let od8 = writing?.od8
        return Self(deviceID: deviceID,
                    bootW: facts?.bootW,
                    floorW: facts?.powerRange?.floorW,
                    ceilW: facts?.powerRange?.ceilW,
                    stockGfxMaxMHz: od8?.stockGfxMaxMHz,
                    gfxMaxTopMHz: od8?.gfxMaxTopMHz,
                    gfxMinStockMHz: od8?.gfxMin?.stock,
                    voltStockMV: od8?.gfxVolt?.stock,
                    voltMinMV: od8?.gfxVolt?.min)
    }

    /// Two cards are the same when every value both of them know agrees: the
    /// device id when both have it, and the limits the kext reports (the GFX
    /// maximum moves a little across wakes, so a card saved before a wake is
    /// still the same card; the start-up limit and the stock maximum are the
    /// ones that do not move on their own).
    func isSameCard(as other: Self) -> Bool {
        if let mine = deviceID, let theirs = other.deviceID, mine != theirs { return false }
        if let mine = bootW, let theirs = other.bootW, mine != theirs { return false }
        if let mine = floorW, let theirs = other.floorW, mine != theirs { return false }
        return true
    }
}

/// One of the saved GPU profiles: a name, what the page held when it was
/// saved, and the card it was saved on. Its values are the page's own types,
/// never a second set of fields: a power limit, or the whole OD8 state.
struct GPUControlProfile: Equatable, Identifiable, Sendable {
    var name: String
    var request: GPUControlRequest
    var card: GPUControlProfileCard

    var id: String { name }

    /// Only a power limit and a fan/clock/voltage state are worth a name;
    /// the way back to stock is not a profile.
    var isSaveable: Bool {
        switch request {
        case .power(let watts): return watts > 0
        case .od8(let want): return !want.isStock
        case .startUp: return false
        }
    }
}

extension GPUControlProfile: Codable {
    /// The stored shape: flat, every part optional, so a file from an older
    /// or a newer build still reads (an entry this build cannot use is
    /// dropped, never a reason to lose the others).
    private struct Stored: Codable {
        var name: String?
        var kind: String?
        var watts: Int?
        /// `[C, %]` × 5, flat, as the remembered curve is kept.
        var curve: [Int]?
        var zeroRpmOff: Bool?
        var gfxMaxMHz: Int?
        var gfxMinMHz: Int?
        var voltMV: Int?
        var overclock: Bool?
        var card: GPUControlProfileCard?
    }

    private enum Keys: String, CodingKey {
        case name, kind, watts, curve, zeroRpmOff, gfxMaxMHz, gfxMinMHz, voltMV, overclock, card
    }

    init(from decoder: Decoder) throws {
        let stored = try Stored(from: decoder)
        let card = stored.card ?? .unknown
        let name = (stored.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch stored.kind {
        case "power":
            let watts = stored.watts ?? 0
            guard !name.isEmpty, watts > 0 else { throw GPUControlProfileDecodeError.unusable }
            self.init(name: name, request: .power(watts: UInt32(clamping: watts)), card: card)
        case "od8":
            var want = GPUControlOD8Want(zeroRpmOff: stored.zeroRpmOff ?? false)
            if let flat = stored.curve {
                guard flat.count == 2 * GPUControlWire.fanCurvePoints else {
                    throw GPUControlProfileDecodeError.unusable
                }
                want.curve = stride(from: 0, to: flat.count, by: 2).map {
                    GPUControlFanPoint(temperatureC: flat[$0], speedPercent: flat[$0 + 1])
                }
            }
            if let mhz = stored.gfxMaxMHz, mhz > 0 { want.gfxMaxMHz = mhz }
            if let mhz = stored.gfxMinMHz, mhz > 0 { want.gfxMinMHz = mhz }
            if let mv = stored.voltMV, mv > 0 { want.voltMV = mv }
            want.overclock = stored.overclock ?? false
            guard !name.isEmpty, !want.isStock else { throw GPUControlProfileDecodeError.unusable }
            self.init(name: name, request: .od8(want), card: card)
        default:
            // A kind this build does not know: the entry is left out.
            throw GPUControlProfileDecodeError.unusable
        }
    }

    func encode(to encoder: Encoder) throws {
        var stored = Stored()
        stored.name = name
        stored.card = card
        switch request {
        case .power(let watts):
            stored.kind = "power"
            stored.watts = Int(watts)
        case .od8(let want):
            stored.kind = "od8"
            if let curve = want.curve {
                stored.curve = curve.flatMap { [$0.temperatureC, $0.speedPercent] }
            }
            stored.zeroRpmOff = want.zeroRpmOff
            stored.gfxMaxMHz = want.gfxMaxMHz
            stored.gfxMinMHz = want.gfxMinMHz
            stored.voltMV = want.voltMV
            if want.overclock { stored.overclock = true }
        case .startUp:
            stored.kind = "power"
            stored.watts = 0
        }
        try stored.encode(to: encoder)
    }
}

enum GPUControlProfileDecodeError: Error {
    /// An entry this build cannot use: dropped, the others are kept.
    case unusable
}

/// The saved profiles, in the app's defaults under one key, with a version
/// number. A file written by a newer build is left alone: this build shows
/// no profiles and saves none over it.
struct GPUControlProfileStore: Equatable, Sendable {
    static let currentVersion = 1

    private(set) var profiles: [GPUControlProfile] = []
    /// The stored file came from a newer build and was not read: nothing is
    /// written over it.
    private(set) var isNewerVersion = false

    init() {}

    init(profiles: [GPUControlProfile], isNewerVersion: Bool = false) {
        self.profiles = profiles
        self.isNewerVersion = isNewerVersion
    }

    /// One entry of the written file.
    private struct File: Encodable {
        var version: Int
        var profiles: [GPUControlProfile]
    }

    /// One entry of a file being read: an entry this build cannot use is
    /// dropped on its own, never together with the others.
    private struct Entry: Decodable {
        var profile: GPUControlProfile?

        init(from decoder: Decoder) throws {
            profile = try? GPUControlProfile(from: decoder)
        }
    }

    private struct ReadFile: Decodable {
        var version: Int
        var profiles: [Entry]
    }

    /// The raw text of a file this build could not read because of its
    /// version, so a save does not throw it away.
    private struct VersionProbe: Decodable {
        var version: Int
    }

    static func decode(_ data: Data) -> GPUControlProfileStore? {
        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.version > currentVersion {
            return GPUControlProfileStore(profiles: [], isNewerVersion: true)
        }
        guard let file = try? decoder.decode(ReadFile.self, from: data) else { return nil }
        guard file.version >= 1 else { return nil }
        return GPUControlProfileStore(profiles: file.profiles.compactMap(\.profile))
    }

    static func load(_ defaults: UserDefaults) -> GPUControlProfileStore {
        guard let data = defaults.data(forKey: DefaultsKey.gpuControlProfiles) else { return GPUControlProfileStore() }
        return decode(data) ?? GPUControlProfileStore()
    }

    /// Written as one JSON blob, with the version this build writes.
    func save(_ defaults: UserDefaults) {
        guard !isNewerVersion else { return }
        guard let data = encoded() else { return }
        defaults.set(data, forKey: DefaultsKey.gpuControlProfiles)
    }

    func encoded() -> Data? {
        guard !isNewerVersion else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(File(version: Self.currentVersion, profiles: profiles))
    }

    // MARK: Names

    /// A name with its ends trimmed; nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Names are unique without regard to case, so "Game" and "game" cannot
    /// sit next to each other.
    func isTaken(_ name: String, excluding: String? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return profiles.contains { profile in
            if let excluding, profile.name.caseInsensitiveCompare(excluding) == .orderedSame { return false }
            return profile.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// The first entry with that name (exact, then without regard to case).
    func profile(named name: String) -> GPUControlProfile? {
        profiles.first { $0.name == name } ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Changing them

    mutating func add(_ profile: GPUControlProfile) {
        if let index = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    @discardableResult
    mutating func rename(_ name: String, to newName: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.name == name }) else { return false }
        profiles[index].name = newName
        return true
    }

    @discardableResult
    mutating func remove(named name: String) -> Bool {
        let count = profiles.count
        profiles.removeAll { $0.name == name }
        return profiles.count != count
    }
}

/// One part of a profile's state, for the sentence about what was left out.
enum GPUControlProfileField: String, CaseIterable, Equatable, Sendable {
    case power
    case fanCurve
    case zeroRpm
    case gfxMax
    case gfxMin
    case volt
    case raise
}

/// Why a profile went out as nothing at all.
enum GPUControlProfileBlock: Equatable, Sendable {
    /// Writing is closed, off, or was never opened since the restart.
    case writingClosed
    case waitingForDriver
    case otherProgram
    /// OD8 was not read cleanly after the restart.
    case od8NotRead
    /// A fan state, and this kext build was not checked with fan curves.
    case fanNotChecked
    /// Every value in it is outside this card's limits now.
    case outOfRange
    /// All it held was a raise, and "Allow overclocking" is off.
    case raiseNeedsOverclock
}

/// What loading one profile came to.
struct GPUControlProfileLoad: Equatable, Sendable {
    var name: String
    /// What goes out, nil when nothing does.
    var request: GPUControlRequest?
    /// The parts this card does not take now; the rest of the state still
    /// goes, as with a value set by hand.
    var leftOut: [GPUControlProfileField] = []
    /// The profile was made on another card (or the limits moved).
    var cardChanged = false
    /// A raise (a GFX maximum above stock, a power limit above the start-up
    /// one) was left out because "Allow overclocking" is off.
    var raiseNeedsOverclock = false
    var blocked: GPUControlProfileBlock?

    var wentOut: Bool { request != nil }
}

/// What saving one profile came to.
enum GPUControlProfileSave: Equatable, Sendable {
    case saved(name: String)
    case emptyName
    case duplicateName(String)
    case nothingToSave
    /// The stored file comes from a newer build: nothing is written over it.
    case newerVersion
}

/// The profiles' rules, without threads or defaults: what a name may be, and
/// what of a profile this card takes now.
enum GPUControlProfiles {
    /// A profile for what is held: the card is recorded with it.
    static func profile(named name: String, held: GPUControlRequest, card: GPUControlProfileCard) -> GPUControlProfile? {
        let profile = GPUControlProfile(name: name, request: held.normalized, card: card)
        return profile.isSaveable ? profile : nil
    }

    /// The request a profile becomes on this card now, through the same
    /// checks the page applies to a value set by hand: the power limit from
    /// the pop-up's values (or, above the start-up limit, the overclock
    /// section's, only while "Allow overclocking" is on), and an OD8 state
    /// through `checkedAgain`, which leaves out a clock, a minimum, a voltage
    /// or a raise the card does not take now. A fan state needs a kext build
    /// the curve rules were checked with, as "Apply curve" does.
    static func load(_ profile: GPUControlProfile, card: GPUControlProfileCard,
                     facts: GPUControlFacts?, stockGfxMaxMHz: Int?,
                     od8Ready: Bool, kextVersion: String?,
                     gfxMin: GPUControlClockMinLogic.Limits?,
                     volt: GPUControlVoltLogic.Limits?,
                     overclock: GPUControlOverclockLogic.GfxLimits?,
                     overclockAllowed: Bool) -> GPUControlProfileLoad {
        var load = GPUControlProfileLoad(name: profile.name, request: nil)
        load.cardChanged = !profile.card.isSameCard(as: card)
        guard let facts else {
            load.blocked = .waitingForDriver
            return load
        }
        if facts.isReadOnlyCard || facts.off || facts.writeOffCode != 0 || !facts.armed {
            load.blocked = .writingClosed
            return load
        }
        if facts.owned && !facts.mine {
            load.blocked = .otherProgram
            return load
        }
        if !facts.ready {
            load.blocked = .waitingForDriver
            return load
        }
        switch profile.request {
        case .startUp:
            load.blocked = .outOfRange
            return load
        case .power(let watts):
            loadPower(&load, watts: Int(watts), facts: facts, overclockAllowed: overclockAllowed)
            return load
        case .od8(let want):
            return loadOD8(load, want: want, facts: facts, od8Ready: od8Ready, kextVersion: kextVersion,
                           stockGfxMaxMHz: stockGfxMaxMHz, gfxMin: gfxMin, volt: volt,
                           overclock: overclock, overclockAllowed: overclockAllowed)
        }
    }

    private static func loadPower(_ load: inout GPUControlProfileLoad, watts: Int,
                                  facts: GPUControlFacts, overclockAllowed: Bool) {
        guard let boot = facts.bootW else {
            load.blocked = .waitingForDriver
            return
        }
        let choices = GPUControlPageLogic.powerChoices(bootW: boot, range: facts.powerRange)
        // The start-up limit is the way back, as choosing it on the page is.
        if watts == boot, choices.contains(watts) {
            load.request = .startUp
            return
        }
        if choices.contains(watts) {
            load.request = .power(watts: UInt32(clamping: watts))
            return
        }
        // Above the start-up limit: the overclock section's own values, and
        // only while "Allow overclocking" is on.
        if watts > boot, let ceiling = GPUControlOverclockLogic.ceilingW(facts: facts),
           GPUControlOverclockLogic.powerChoices(bootW: boot, ceilW: ceiling,
                                                 stepW: facts.powerRange?.stepW ?? GPUControlWire.powerStepW)
            .contains(watts) {
            if overclockAllowed {
                load.request = .power(watts: UInt32(clamping: watts))
            } else {
                load.blocked = .raiseNeedsOverclock
                load.raiseNeedsOverclock = true
            }
            return
        }
        load.blocked = .outOfRange
    }

    private static func loadOD8(_ load: GPUControlProfileLoad, want: GPUControlOD8Want,
                                facts: GPUControlFacts, od8Ready: Bool, kextVersion: String?,
                                stockGfxMaxMHz: Int?, gfxMin: GPUControlClockMinLogic.Limits?,
                                volt: GPUControlVoltLogic.Limits?,
                                overclock: GPUControlOverclockLogic.GfxLimits?,
                                overclockAllowed: Bool) -> GPUControlProfileLoad {
        var load = load
        // OD8 not read cleanly: the kext could not take it.
        guard od8Ready else {
            load.blocked = .od8NotRead
            return load
        }
        // A fan state and another kext build: the rules were not checked with
        // it, and "Apply curve" is off too. The fan part is left out and the
        // clocks and voltage still go; a profile that is only a fan state
        // goes out as nothing.
        var sendable = want
        if want.curve != nil || want.zeroRpmOff, !GPUControlCurveRules.isChecked(kextVersion) {
            sendable.curve = nil
            sendable.zeroRpmOff = false
            if sendable.isStock {
                load.blocked = .fanNotChecked
                return load
            }
        }
        guard let checked = GPUControlRememberPolicy.checkedAgain(
                .od8(sendable), stockGfxMaxMHz: stockGfxMaxMHz, gfxMin: gfxMin, volt: volt,
                overclock: overclock, overclockAllowed: overclockAllowed),
              case .od8(let kept) = checked else {
            let fields = leftOut(want, keptIn: .stock)
            // A raise alone, with the switch off: that is the reason, not
            // the card's limits.
            if !overclockAllowed, want.overclock, fields.allSatisfy({ $0 == .gfxMax || $0 == .raise }) {
                load.blocked = .raiseNeedsOverclock
                load.raiseNeedsOverclock = true
                return load
            }
            load.leftOut = fields
            load.blocked = .outOfRange
            return load
        }
        load.leftOut = leftOut(want, keptIn: kept)
        load.request = .od8(kept)
        // A raise left out only because the switch is off says why.
        if want.overclock || (want.gfxMaxMHz.map { $0 > (stockGfxMaxMHz ?? $0) } ?? false) {
            if !overclockAllowed, kept.overclock == false,
               kept.gfxMaxMHz != want.gfxMaxMHz {
                load.raiseNeedsOverclock = true
            }
        }
        return load
    }

    /// Which parts of `want` the state `kept` no longer carries.
    static func leftOut(_ want: GPUControlOD8Want, keptIn kept: GPUControlOD8Want) -> [GPUControlProfileField] {
        var fields: [GPUControlProfileField] = []
        if want.curve != nil, kept.curve == nil { fields.append(.fanCurve) }
        if want.zeroRpmOff, !kept.zeroRpmOff { fields.append(.zeroRpm) }
        if want.gfxMaxMHz != nil, kept.gfxMaxMHz == nil {
            fields.append(.gfxMax)
            if want.overclock { fields.append(.raise) }
        }
        if want.gfxMinMHz != nil, kept.gfxMinMHz == nil { fields.append(.gfxMin) }
        if want.voltMV != nil, kept.voltMV == nil { fields.append(.volt) }
        return fields
    }

    /// The saved profile that is exactly what the card holds now, if any: a
    /// name, not a second copy of the values.
    static func match(_ profiles: [GPUControlProfile], held: GPUControlRequest?) -> String? {
        guard let held, held != .startUp else { return nil }
        return profiles.first { $0.request == held }?.name
    }
}

/// The display card's PCI device id, read from the I/O Registry: the
/// accelerator's own node or the one above it (the PCI device). Read only;
/// nil when it cannot be read, and then a profile is only compared by the
/// limits the kext reports.
enum GPUControlCardDevice {
    static func displayDeviceID() -> UInt32? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let id = deviceID(from: entry, depth: 4) { return id }
        }
        return nil
    }

    /// AMD's PCI vendor id: an Intel iGPU or another card is never the one read.
    private static let amdVendor: UInt32 = 0x1002

    private static func number(_ key: String, of entry: io_registry_entry_t) -> UInt32? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        // The registry keeps it as four bytes, little endian (bf 73 00 00).
        if let data = value as? Data, data.count >= 4 {
            return UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
        }
        return (value as? NSNumber)?.uint32Value
    }

    private static func deviceID(from entry: io_registry_entry_t, depth: Int) -> UInt32? {
        if let id = number("device-id", of: entry) {
            // The node with the PCI ids: only an AMD card counts.
            return number("vendor-id", of: entry) == amdVendor ? id : nil
        }
        guard depth > 0 else { return nil }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else {
            return nil
        }
        defer { IOObjectRelease(parent) }
        return deviceID(from: parent, depth: depth - 1)
    }
}
