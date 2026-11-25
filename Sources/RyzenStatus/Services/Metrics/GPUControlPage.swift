// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import Security

/// What the GPU control page knows about the kext's write path, from one
/// place: the channel's `status` while the controller's connection is open
/// (fresher, and the only one that knows which connection holds), else the
/// properties of the whole-table read (plan 7.4).
struct GPUControlFacts: Equatable, Sendable {
    enum Source: Equatable, Sendable { case channel, properties }

    var source: Source
    var armed = false
    var off = false
    var sleeping = false
    var reverting = false
    var changed = false
    /// Some program holds a change.
    var owned = false
    /// This app's connection holds it; false from the properties, which
    /// cannot tell (and the app holds nothing without a connection).
    var mine = false
    var ready = false
    var od8Ready = false
    /// The start-up power limit in watts, nil while the kext has not read it.
    var bootW: Int?
    /// The limit held now; the start-up one while nothing is held.
    var heldW: Int?
    var writeOffCode: UInt64 = 0
    /// The kext's own reason (properties only; from `status` it is the
    /// app's copy of the kext's text for the code).
    var writeOffText: String?
    var od8Held: GPUControlOD8Held = []
    var changes: Int?
    var reverts: Int?
    var od8Changes: Int?
    var od8Reverts: Int?
    /// `OD8State` as the kext wrote it, when OD8 is not read cleanly.
    var od8ReadText: String?
    /// The card's power range: `PowerRange` from kext 0.8.0, or worked out
    /// from the OD8 table for 0.7.x, the same way. Always from the
    /// properties: the channel's `status` does not carry it.
    var powerRange: GPUControlPowerRange?
    /// `PowerRangeState`, the kext's words about the floor (0.8.0).
    var powerRangeState: String?
    /// The kext can close writing again (`disarm`, 0.8.0): it publishes
    /// `PowerRangeState`, which 0.7.x does not.
    var canDisarm = false

    var writeOff: GPUControlWriteOff? { GPUControlWriteOff(rawValue: writeOffCode) }
    /// The read-only card (kext 0.8.0): read, never controlled.
    var isReadOnlyCard: Bool { writeOff == .readOnlyCard }

    /// What only the properties know: the power range and whether the kext
    /// has `disarm`.
    mutating func takeRange(from writing: GPUControlStatus.Writing) {
        powerRangeState = writing.powerRangeState
        canDisarm = writing.powerRangeState != nil
        powerRange = writing.powerRange
            ?? GPUControlPowerRange.fromOD8(bootW: bootW, od8: writing.od8, od8Read: writing.od8Read == .read)
    }

    init(source: Source) { self.source = source }

    /// From the channel. Nil for a status that is not a whole "ok" one.
    init?(status: GPUControlChannelStatus) {
        guard status.reply == .ok else { return nil }
        source = .channel
        let flags = status.flags
        armed = flags.contains(.armed)
        off = flags.contains(.off)
        sleeping = flags.contains(.sleeping)
        reverting = flags.contains(.reverting)
        changed = flags.contains(.changed)
        owned = flags.contains(.owned)
        mine = flags.contains(.mine)
        ready = flags.contains(.ready)
        od8Ready = flags.contains(.od8Ready)
        bootW = status.bootW == 0 ? nil : Int(clamping: status.bootW)
        heldW = status.heldW == 0 ? nil : Int(clamping: status.heldW)
        writeOffCode = status.writeOffCode
        writeOffText = status.writeOff.map(\.kextText).flatMap { $0.isEmpty ? nil : $0 }
        od8Held = status.od8Held
        changes = Int(clamping: status.changes)
        reverts = Int(clamping: status.reverts)
        od8Changes = Int(clamping: status.od8Changes)
        od8Reverts = Int(clamping: status.od8Reverts)
    }

    /// From the properties. Nil for a kext without the write path (before
    /// 0.5.0): then there is no page.
    init?(control: GPUControlStatus) {
        guard let writing = control.writing else { return nil }
        source = .properties
        let state = writing.state
        switch writing.gate {
        case .off: off = true
        case .waiting: break
        case .closed: ready = true
        case .sleeping: ready = true; armed = true; sleeping = true
        case .reverting: ready = true; armed = true; reverting = true
        case .held: ready = true; armed = true; owned = true
        case .idle, .unconfirmed: ready = true; armed = true
        case .other: ready = true; armed = state?.armed ?? false
        }
        if let owned = state?.owned, writing.gate != .off { self.owned = self.owned || owned }
        if writing.od8Gate == .reverting || writing.od8Gate == .unconfirmed { reverting = true }
        if writing.od8Gate == .held { owned = true }
        writeOffCode = UInt64(state?.writeOff ?? 0)
        if writeOffCode != 0 { off = true; armed = false }
        writeOffText = state?.writeOffText.flatMap { $0.isEmpty ? nil : $0 }
        bootW = control.powerWatch?.bootW
        heldW = state?.heldW
        changes = state?.changes
        reverts = state?.reverts
        od8Held = writing.od8State?.held ?? []
        od8Changes = writing.od8State?.changes
        od8Reverts = writing.od8State?.reverts
        od8Ready = writing.od8Read == .read
        if case .notClean(let text)? = writing.od8Read { od8ReadText = text }
        changed = (heldW != nil && bootW != nil && heldW != bootW) || !od8Held.isEmpty
        takeRange(from: writing)
    }
}

/// Where the write path stands, as the page shows it (plan 7.4), in the
/// kext's own order of checks (`writeText()`).
enum GPUControlPageState: Equatable, Sendable {
    /// The kext speaks another version of the channel.
    case otherVersion(UInt64)
    /// Off until restart. `restart`: the card may not be back at stock
    /// (OD8 held 8 with no way back running): restart the Mac.
    case writingOff(GPUControlWriteOff?, text: String?, restart: Bool)
    /// The connection failed: the kext went back on its own.
    case connectionLost
    case waitingForDriver
    /// Not opened since the restart (section 4).
    case closed
    case sleeping
    case reverting
    /// Another program holds the control (`owned` without `mine`).
    case heldByOther
    /// This app holds it, confirmed by `status`.
    case heldByApp(GPUControlRequest)
    /// Open, nothing held.
    case ready
    /// Kext 0.8.0's read-only card (`WriteOff` 15): every reading shows,
    /// nothing can be changed, and that never changes until another card.
    case readOnlyCard

    /// The page's controls take a choice now.
    var acceptsChoices: Bool {
        switch self {
        case .ready, .heldByApp: return true
        default: return false
        }
    }
}

enum GPUControlPageLogic {
    /// The facts for the page: `status` while the controller has a fresh one
    /// and is not stopped, else the properties.
    static func facts(snapshot: GPUControlSnapshot?, control: GPUControlStatus?) -> GPUControlFacts? {
        if let snapshot, snapshot.stopped == nil, let status = snapshot.status,
           var facts = GPUControlFacts(status: status) {
            if let writing = control?.writing { facts.takeRange(from: writing) }
            return facts
        }
        return control.flatMap(GPUControlFacts.init(control:))
    }

    static func state(facts: GPUControlFacts, snapshot: GPUControlSnapshot?) -> GPUControlPageState {
        switch snapshot?.stopped {
        case .otherVersion(let version)?: return .otherVersion(version)
        case .connectionFailed?, .openRefused?: return .connectionLost
        default: break
        }
        if facts.isReadOnlyCard { return .readOnlyCard }
        if facts.off || facts.writeOffCode != 0 {
            let failed: Set<GPUControlWriteOff> = [.sendFailed, .revertFailed, .od8Failed]
            let restart = facts.writeOff.map(failed.contains) == true
                && facts.od8Held.contains(.unknown) && !facts.reverting
            return .writingOff(facts.writeOff, text: facts.writeOffText, restart: restart)
        }
        if !facts.ready { return .waitingForDriver }
        if !facts.armed { return .closed }
        if facts.sleeping { return .sleeping }
        if facts.reverting { return .reverting }
        if facts.owned {
            if facts.mine, let held = snapshot?.held { return .heldByApp(held) }
            if !facts.mine { return .heldByOther }
        }
        return .ready
    }

    /// The values the page and the panel offer: none below the start-up
    /// value on the read-only card, whose `PowerRange` is published for
    /// showing only (kext 0.8.0).
    static func powerChoices(facts: GPUControlFacts?, state: GPUControlPageState?) -> [Int] {
        let all = powerChoices(bootW: facts?.bootW, range: facts?.powerRange)
        if case .readOnlyCard? = state { return Array(all.prefix(1)) }
        return all
    }

    /// What the card takes below its start-up value (kext 0.8.0's
    /// `PowerRange`): nil without a start-up value.
    static func limits(bootW: Int?, range: GPUControlPowerRange?) -> GPUControlPowerLimits? {
        guard let boot = bootW else { return nil }
        // A range for another start-up value is not this one's.
        guard let range, let floor = range.floorW, let top = range.maxW, top == boot else { return .unknown }
        return floor >= boot ? .nothingToLower(boot) : .range(floorW: floor, maxW: top)
    }

    /// The pop-up's values (plan 7.1): the start-up value first, then every
    /// multiple of the step below it down to the card's own floor. Only the
    /// start-up value while the floor is not known or is the start-up value.
    /// Empty for a start-up value the kext would not believe.
    static func powerChoices(bootW: Int?, range: GPUControlPowerRange?) -> [Int] {
        guard let boot = bootW, (GPUControlWire.minBootW...GPUControlWire.maxBootW).contains(boot) else { return [] }
        guard case .range(let floor, _)? = limits(bootW: boot, range: range) else { return [boot] }
        let step = Swift.max(range?.stepW ?? GPUControlWire.powerStepW, 1)
        let firstBelow = (boot - 1) / step * step
        let below = firstBelow >= floor ? Array(stride(from: firstBelow, through: floor, by: -step)) : []
        return [boot] + below
    }

    /// The value the pop-up shows: what is being asked for while a request
    /// runs, else what the kext holds (the start-up value at rest).
    static func shownWatts(facts: GPUControlFacts, snapshot: GPUControlSnapshot?) -> Int? {
        switch snapshot?.activity {
        case .applying(let request)?, .retrying(let request, _)?, .switching(let request)?, .afterWake(let request)?:
            if case .power(let watts) = request { return Int(watts) }
            if request == .startUp { return facts.bootW }
        default: break
        }
        return facts.heldW ?? facts.bootW
    }

    /// The request behind an activity, if any.
    static func pending(_ snapshot: GPUControlSnapshot?) -> GPUControlRequest? {
        switch snapshot?.activity {
        case .applying(let request)?, .retrying(let request, _)?, .switching(let request)?, .afterWake(let request)?:
            return request
        default:
            return nil
        }
    }
}

// MARK: - Opening writing (plan 4, D1 = A2 with B as the fallback)

/// Whether the app may offer "Open writing…": it runs
/// `/usr/local/bin/gpucontrol arm` as root through the administrator dialog,
/// so nothing a program of this user can replace may be on that path. The
/// checks are the ones the RyzenStatus GPU installer makes before it puts the
/// tool there (`GPU/install/sensors.sh`, `tool_file_unsound` and `tool_dir_unsafe`):
/// a plain file, root's, no group or other write, no access control list;
/// every folder above it root's, no group or other write, no access control
/// list; the signature intact with the identifier `com.droga.gpucontrol`.
/// The tool is signed ad hoc, so the identifier only keeps the button from
/// running some other program of that name; the trust comes from only root
/// being able to change the file and its folders.
enum GPUControlArmTool {
    static let installedPath = "/usr/local/bin/gpucontrol"

    /// The whole command the administrator dialog runs: a fixed path, no
    /// input from anyone.
    static let armCommand = installedPath + " arm"
    static let identifier = "com.droga.gpucontrol"

    struct FileInfo: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case regular, directory, symlink, other }
        var kind: Kind
        var uid: UInt32

        /// The permission bits (`st_mode & 07777`).
        var permissions: UInt16

        /// An extended access control list is set (`ls -le` shows "+").
        var hasACL = false
    }

    /// `lstat` plus the ACL, or a test's table.
    typealias Lookup = (String) -> FileInfo?

    /// The identifier of a file whose signature is intact, else nil.
    typealias Signature = (String) -> String?

    /// Why the button is not offered, one translated sentence each.
    enum UnsafeReason: Equatable, Sendable, CaseIterable {
        case notPlain
        case notRoot
        case writable
        /// The file runs as its owner or group (setuid, setgid).
        case setID
        case accessControlList
        case unreadable
        case signature
        case otherProgram
    }

    struct Problem: Equatable, Sendable {
        var reason: UnsafeReason
        var path: String
        /// Detail for a log or a test, in English (another identifier, a mode).
        var detail: String = ""
    }

    enum Availability: Equatable, Sendable {
        /// Installed safely: the button can run it.
        case button

        /// Installed, but something on its path is not root's alone, or the
        /// file is not our signed tool: only the command is shown, for the
        /// owner to run. `path`: the file or folder that failed.
        case unsafe(UnsafeReason, path: String)

        /// Not installed in /usr/local/bin, the only place the app looks:
        /// the RyzenStatus GPU installer puts it there.
        case missing

        /// The command the page shows to copy.
        var command: String {
            switch self {
            case .button, .unsafe, .missing: return "sudo " + GPUControlArmTool.armCommand
            }
        }
    }

    static func availability(lookup: Lookup = lstatInfo, signature: Signature = signingIdentifier) -> Availability {
        guard lookup(installedPath) != nil else { return .missing }
        if let problem = problem(path: installedPath, lookup: lookup, signature: signature) {
            return .unsafe(problem.reason, path: problem.path)
        }
        return .button
    }

    /// Nil when `path` and every folder above it, up to and including `top`,
    /// belong to `owner` alone and the file is our signed tool. The app asks
    /// for root and "/"; a test passes its own user and folder.
    static func problem(path: String, owner: UInt32 = 0, top: String = "/",
                        lookup: Lookup, signature: Signature) -> Problem? {
        guard let file = lookup(path) else { return Problem(reason: .unreadable, path: path) }
        guard file.kind == .regular else { return Problem(reason: .notPlain, path: path) }
        guard file.uid == owner else { return Problem(reason: .notRoot, path: path) }
        // No group or other write (the installer's rule); no setuid or setgid
        // either, which the installer never sets. Each has its own sentence:
        // nobody but root can change a 4755 file.
        guard file.permissions & 0o022 == 0 else {
            return Problem(reason: .writable, path: path, detail: "mode " + String(file.permissions, radix: 8))
        }
        guard file.permissions & 0o6000 == 0 else {
            return Problem(reason: .setID, path: path, detail: "mode " + String(file.permissions, radix: 8))
        }
        guard !file.hasACL else { return Problem(reason: .accessControlList, path: path) }
        var folder = (path as NSString).deletingLastPathComponent
        while true {
            guard let info = lookup(folder) else { return Problem(reason: .unreadable, path: folder) }
            guard info.kind == .directory else { return Problem(reason: .notPlain, path: folder) }
            guard info.uid == owner else { return Problem(reason: .notRoot, path: folder) }
            guard info.permissions & 0o022 == 0 else {
                return Problem(reason: .writable, path: folder, detail: "mode " + String(info.permissions, radix: 8))
            }
            guard !info.hasACL else { return Problem(reason: .accessControlList, path: folder) }
            if folder == top || folder == "/" { break }
            folder = (folder as NSString).deletingLastPathComponent
        }
        guard let id = signature(path) else { return Problem(reason: .signature, path: path) }
        guard id == identifier else { return Problem(reason: .otherProgram, path: path, detail: id) }
        return nil
    }

    /// The real file system, without following a link.
    static func lstatInfo(_ path: String) -> FileInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let type = st.st_mode & S_IFMT
        let kind: FileInfo.Kind = type == S_IFREG ? .regular : type == S_IFDIR ? .directory
            : type == S_IFLNK ? .symlink : .other
        return FileInfo(kind: kind, uid: st.st_uid, permissions: UInt16(st.st_mode & 0o7777),
                        hasACL: hasExtendedACL(path))
    }

    /// Whether the file itself (not a link's target) carries an extended ACL
    /// with at least one entry.
    static func hasExtendedACL(_ path: String) -> Bool {
        guard let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        return acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0
    }

    /// The signing identifier when the signature is intact on every
    /// architecture (`codesign --verify`), else nil.
    static func signingIdentifier(_ path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoIdentifier as String] as? String
    }
}
// MARK: - Remembering the setting (plan 8, D4 = at launch and at wake)

/// What the app remembers: only what it held, confirmed by the kext.
enum GPUControlRemembered: Equatable, Sendable {
    case nothing
    case power(watts: Int)
    /// A fan state (curve and zero RPM; the GFX maximum joins in phase 4).
    case od8(GPUControlOD8Want)

    static func load(_ defaults: UserDefaults) -> Self {
        switch defaults.string(forKey: DefaultsKey.gpuControlRememberedKind) {
        case "power":
            let watts = defaults.integer(forKey: DefaultsKey.gpuControlRememberedWatts)
            return watts > 0 ? .power(watts: watts) : .nothing
        case "od8":
            var want = GPUControlOD8Want(zeroRpmOff: defaults.bool(forKey: DefaultsKey.gpuControlRememberedZeroRpmOff))
            let mhz = defaults.integer(forKey: DefaultsKey.gpuControlRememberedGfxMHz)
            if mhz > 0 { want.gfxMaxMHz = mhz }
            let low = defaults.integer(forKey: DefaultsKey.gpuControlRememberedGfxMinMHz)
            if low > 0 { want.gfxMinMHz = low }
            if let flat = defaults.array(forKey: DefaultsKey.gpuControlRememberedCurve) as? [Int] {
                guard flat.count == 2 * GPUControlWire.fanCurvePoints else { return .nothing }
                want.curve = stride(from: 0, to: flat.count, by: 2).map {
                    GPUControlFanPoint(temperatureC: flat[$0], speedPercent: flat[$0 + 1])
                }
            }
            return want.isStock ? .nothing : .od8(want)
        default:
            return .nothing
        }
    }

    func save(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedWatts)
        defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedCurve)
        defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedZeroRpmOff)
        defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedGfxMHz)
        defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedGfxMinMHz)
        switch self {
        case .nothing:
            defaults.set("none", forKey: DefaultsKey.gpuControlRememberedKind)
        case .power(let watts):
            defaults.set("power", forKey: DefaultsKey.gpuControlRememberedKind)
            defaults.set(watts, forKey: DefaultsKey.gpuControlRememberedWatts)
        case .od8(let want):
            defaults.set("od8", forKey: DefaultsKey.gpuControlRememberedKind)
            if let curve = want.curve {
                defaults.set(curve.flatMap { [$0.temperatureC, $0.speedPercent] },
                             forKey: DefaultsKey.gpuControlRememberedCurve)
            }
            defaults.set(want.zeroRpmOff, forKey: DefaultsKey.gpuControlRememberedZeroRpmOff)
            if let mhz = want.gfxMaxMHz { defaults.set(mhz, forKey: DefaultsKey.gpuControlRememberedGfxMHz) }
            if let low = want.gfxMinMHz { defaults.set(low, forKey: DefaultsKey.gpuControlRememberedGfxMinMHz) }
        }
    }
}

enum GPUControlRememberPolicy {
    /// Remembering works at all: the box is on, and this is not a
    /// development build (which could take the control from the installed
    /// app; plan 8).
    static func isActive(enabled: Bool, isDeveloperBuild: Bool) -> Bool {
        enabled && !isDeveloperBuild
    }

    /// What to save when `status` confirms a hold, nil to keep what is saved.
    /// Only while remembering is active; going back to the start-up values
    /// by choice forgets it.
    static func toSave(held: GPUControlRequest?, ownerChoseStartUp: Bool, active: Bool) -> GPUControlRemembered? {
        guard active else { return nil }
        if case .power(let watts)? = held { return .power(watts: Int(watts)) }
        if case .od8(let want)? = held, !want.isStock { return .od8(want) }
        return ownerChoseStartUp ? .nothing : nil
    }

    /// The request to make for a remembered setting, or nil: only with
    /// remembering active, writing already open (never a password), nobody
    /// else holding, and the control not stopped (a failure or the watchdog
    /// keep it from asking until the app starts again).
    /// `stockGfxMaxMHz`: the GFX maximum the kext allows now (it moves a
    /// little across wakes). A remembered clock above it, or below 1500 MHz,
    /// is left out of the request: only ever lower than stock.
    /// `kextVersion`: the kext's `VersionInfo`. A fan state (curve or zero
    /// RPM) goes out only to a build the curve rules were checked against, as
    /// with "Apply curve" (none given: no fan state). A clock alone does not
    /// depend on them, as on the page.
    /// `gfxMin`: the GFX minimum the kext takes now (`GPUControlClockMinLogic
    /// .limits`), nil when it takes none (a kext before 0.9.0): a remembered
    /// minimum outside it is left out of the request, like the maximum.
    static func request(remembered: GPUControlRemembered, active: Bool,
                        facts: GPUControlFacts?, stopped: GPUControlStop?,
                        stockGfxMaxMHz: Int? = nil, kextVersion: String? = nil,
                        gfxMin: GPUControlClockMinLogic.Limits? = nil) -> GPUControlRequest? {
        guard active, stopped == nil, let facts, facts.armed, !facts.off, facts.writeOffCode == 0,
              !(facts.owned && !facts.mine) else { return nil }
        switch remembered {
        case .nothing:
            return nil
        case .power(let watts):
            guard watts > 0, let boot = facts.bootW, GPUControlPageLogic.powerChoices(bootW: boot, range: facts.powerRange)
                    .contains(watts), watts != boot else { return nil }
            return .power(watts: UInt32(watts))
        case .od8(var want):
            // OD8 not read cleanly: the kext could not take it.
            guard facts.od8Ready else { return nil }
            // A fan state and another kext build: the rules were not checked
            // with it, and Apply is off too. Nothing goes, not even the clock:
            // only what was held is asked for again, never a part of it.
            if want.curve != nil || want.zeroRpmOff, !GPUControlCurveRules.isChecked(kextVersion) { return nil }
            if let mhz = want.gfxMaxMHz, !GPUControlClockLogic.lowers(mhz, stockGfxMaxMHz: stockGfxMaxMHz) {
                want.gfxMaxMHz = nil
            }
            want = GPUControlClockMinLogic.checked(want, limits: gfxMin, stockGfxMaxMHz: stockGfxMaxMHz)
            return want.isStock ? nil : .od8(want)
        }
    }

    /// A remembered limit the card does not take is forgotten, not kept for
    /// later: one saved with 0.7.x below this card's floor (200 W where the
    /// floor is 225 W). Only once the range is known.
    static func forgets(remembered: GPUControlRemembered, facts: GPUControlFacts?) -> Bool {
        guard case .power(let watts) = remembered, let facts, let boot = facts.bootW else { return false }
        switch GPUControlPageLogic.limits(bootW: boot, range: facts.powerRange) {
        case .range?, .nothingToLower?:
            return !GPUControlPageLogic.powerChoices(bootW: boot, range: facts.powerRange).contains(watts)
        case .unknown?, nil:
            return false
        }
    }
}

// MARK: - The GFX maximum clock (plan 7.1, phase 4)

/// The clock control's numbers. The range is 1500 MHz (the kext's floor,
/// `kOd8GfxFloorMHz`) to the stock maximum the kext publishes
/// (`OD8Table.stockGfxMaxMHz`, the lower of the first read and the driver's
/// default now, only with feature 0x1). The control only ever lowers the
/// clock: the stock maximum itself is the way back, never a hold.
enum GPUControlClockLogic {
    static let step = 10
    static let tickStepMHz = 100

    /// Nil when the kext offers no clock (no clean read, feature not 0x1)
    /// or the stock maximum is not above the floor.
    static func range(stockGfxMaxMHz: Int?) -> ClosedRange<Int>? {
        guard let top = stockGfxMaxMHz, top > GPUControlWire.gfxFloorMHz else { return nil }
        return GPUControlWire.gfxFloorMHz...top
    }

    /// A value the control may send as a hold: at or above the floor and
    /// below the stock maximum.
    static func lowers(_ mhz: Int, stockGfxMaxMHz: Int?) -> Bool {
        guard let range = range(stockGfxMaxMHz: stockGfxMaxMHz) else { return false }
        return mhz >= range.lowerBound && mhz < range.upperBound
    }

    /// What choosing `mhz` asks for: nil (the stock clock, the way back) at
    /// the stock maximum, the value when it lowers the clock. Values outside
    /// the range are not sent at all (`lowers` says so first).
    static func request(_ mhz: Int, stockGfxMaxMHz: Int) -> Int? {
        mhz >= stockGfxMaxMHz ? nil : mhz
    }

    /// A slider position as a value: 10 MHz steps, the stock maximum at the
    /// top even when it is not a multiple of 10 (2359 here).
    static func snapped(_ raw: Double, stockGfxMaxMHz top: Int) -> Int {
        let floor = GPUControlWire.gfxFloorMHz
        let value = floor + Int(((raw - Double(floor)) / Double(step)).rounded()) * step
        if value >= top - step / 2 { return top }
        return Swift.max(floor, value)
    }

    /// The slider's tick marks, one every 100 MHz from the floor.
    static func tickCount(stockGfxMaxMHz top: Int) -> Int {
        (top - GPUControlWire.gfxFloorMHz) / tickStepMHz + 1
    }
}

// MARK: - The GFX minimum clock (GPUSensors 0.9.0)

/// The minimum clock control's numbers. The range is the card's stock
/// minimum (OD8 id 1, 500 MHz on the test card; the way back, never a hold)
/// up to the GFX maximum of the same state: the lowered maximum held or
/// asked for, else the stock maximum, and never past the card's own top for
/// id 1. The kext takes the same and nothing else (`GfxMinRange`). Only
/// offered when the kext publishes `Takes` with the GFX minimum.
enum GPUControlClockMinLogic {
    static let step = 10
    static let tickStepMHz = 100

    /// The card's range for the minimum, and its stock value.
    struct Limits: Equatable, Sendable {
        var min: Int
        var max: Int
        var stock: Int
    }

    /// Nil when the kext takes no minimum (before 0.9.0), OD8 is not read
    /// cleanly, or the table has no usable GFX pair.
    static func limits(writing: GPUControlStatus.Writing?, od8Ready: Bool) -> Limits? {
        guard od8Ready, writing?.od8State?.takesGfxMin == true, let m = writing?.od8?.gfxMin else { return nil }
        return Limits(min: m.min, max: m.max, stock: m.stock)
    }

    /// The control's range: stock up to the GFX maximum in force. Nil when
    /// there is nothing above stock to choose.
    static func range(limits: Limits?, gfxMaxMHz: Int?) -> ClosedRange<Int>? {
        guard let limits, let gfxMaxMHz else { return nil }
        let top = Swift.min(gfxMaxMHz, limits.max)
        let bottom = Swift.max(limits.stock, limits.min)
        guard top > bottom else { return nil }
        return bottom...top
    }

    /// A value the control may send as a hold: above stock, inside the range.
    static func raises(_ mhz: Int, range: ClosedRange<Int>?) -> Bool {
        guard let range else { return false }
        return mhz > range.lowerBound && mhz <= range.upperBound
    }

    /// What choosing `mhz` asks for: nil (the stock minimum, the way back) at
    /// or below the stock value, else the value.
    static func request(_ mhz: Int, stockMHz: Int) -> Int? {
        mhz <= stockMHz ? nil : mhz
    }

    /// A slider position as a value: 10 MHz steps from the stock minimum,
    /// the top of the range when it is not on a step.
    static func snapped(_ raw: Double, range: ClosedRange<Int>) -> Int {
        let floor = range.lowerBound
        let value = floor + Int(((raw - Double(floor)) / Double(step)).rounded()) * step
        if value >= range.upperBound - step / 2 { return range.upperBound }
        return Swift.max(floor, value)
    }

    /// The slider's tick marks, one every 100 MHz from the stock minimum.
    static func tickCount(range: ClosedRange<Int>) -> Int {
        (range.upperBound - range.lowerBound) / tickStepMHz + 1
    }

    /// A state with its minimum checked against what the kext takes now:
    /// left out when the kext takes none, or when it is not above stock or
    /// passes the GFX maximum of the state (the lowered one, else the stock
    /// maximum of the moment). The rest of the state is kept.
    static func checked(_ want: GPUControlOD8Want, limits: Limits?, stockGfxMaxMHz: Int?) -> GPUControlOD8Want {
        guard let low = want.gfxMinMHz else { return want }
        var want = want
        let range = range(limits: limits, gfxMaxMHz: want.gfxMaxMHz ?? stockGfxMaxMHz)
        if !raises(low, range: range) { want.gfxMinMHz = nil }
        return want
    }
}

extension GPUControlRememberPolicy {
    /// A remembered request again, right before it goes out: a clock that no
    /// longer lowers the stock maximum of the moment is left out (the rest
    /// of the fan state still goes), and so is a minimum the kext does not
    /// take now (`gfxMin` nil: a kext before 0.9.0, or no clean OD8 read).
    /// Nil when nothing is left to ask.
    static func checkedAgain(_ request: GPUControlRequest, stockGfxMaxMHz: Int?,
                             gfxMin: GPUControlClockMinLogic.Limits? = nil) -> GPUControlRequest? {
        guard case .od8(var want) = request else { return request }
        if let mhz = want.gfxMaxMHz, !GPUControlClockLogic.lowers(mhz, stockGfxMaxMHz: stockGfxMaxMHz) {
            want.gfxMaxMHz = nil
        }
        want = GPUControlClockMinLogic.checked(want, limits: gfxMin, stockGfxMaxMHz: stockGfxMaxMHz)
        return want.isStock ? nil : .od8(want)
    }
}

/// Which channel the app connects at launch (plan 11.1).
enum GPUControlConnectionMode: Equatable, Sendable {
    case none
    case real
    /// The model, for a development build's screenshots.
    case fake

    /// A development build connects nothing unless `-gpuControlReal YES`, so
    /// it never takes the control from the installed app; `-gpuControlFake
    /// YES` shows the model instead.
    /// Making the real channel opens nothing: the controller opens it the
    /// first time the page or a remembered setting needs it.
    static func choose(isDeveloperBuild: Bool, defaults: UserDefaults) -> Self {
        if isDeveloperBuild {
            if defaults.bool(forKey: "gpuControlFake") { return .fake }
            return defaults.bool(forKey: "gpuControlReal") ? .real : .none
        }
        return .real
    }
}

/// The power section's line about the card's own limits.
enum GPUControlPowerLimits: Equatable, Sendable {
    /// The floor is not known (yet): only the start-up value is taken.
    case unknown
    /// The floor is the start-up value: nothing to lower.
    case nothingToLower(Int)
    case range(floorW: Int, maxW: Int)
}

/// Security review S-5 and S-9: what another program did to the GPU control,
/// so the owner hears of it with the page closed too. Fed every few seconds
/// with the properties' facts. A hold appears while the app holds nothing
/// (S-5), or writing closes without the app having asked (S-9). Writing
/// going off is the kext's own notice, not another program's.
struct GPUControlForeignWatch: Equatable, Sendable {
    enum Notice: Equatable, Sendable {
        case changed
        case closed
    }

    private(set) var wasArmed: Bool?
    private(set) var foreignHeld = false

    /// `appHolds`: the app holds or asks for something; `appClosing`: the
    /// app asked to close a short while ago.
    mutating func next(facts: GPUControlFacts, appHolds: Bool, appClosing: Bool) -> Notice? {
        let foreign = facts.owned && !facts.mine && !appHolds
        defer { foreignHeld = foreign }
        if facts.off || facts.isReadOnlyCard {
            wasArmed = nil
            return nil
        }
        let closedNow = wasArmed == true && !facts.armed
        wasArmed = facts.armed
        if foreign, !foreignHeld { return .changed }
        if closedNow, !appClosing { return .closed }
        return nil
    }
}
