// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

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

    var writeOff: GPUControlWriteOff? { GPUControlWriteOff(rawValue: writeOffCode) }

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
           let facts = GPUControlFacts(status: status) {
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

    /// The pop-up's values (plan 7.1): the start-up value first, then every
    /// multiple of 10 below it down to 200 W. Empty for a start-up value the
    /// kext would not believe.
    static func powerChoices(bootW: Int?) -> [Int] {
        guard let boot = bootW, (GPUControlWire.powerFloorW...GPUControlWire.maxBootW).contains(boot) else { return [] }
        let step = GPUControlWire.powerStepW
        let firstBelow = (boot - 1) / step * step
        let below = firstBelow >= GPUControlWire.powerFloorW
            ? Array(stride(from: firstBelow, through: GPUControlWire.powerFloorW, by: -step)) : []
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
/// so nothing a program of this user can replace may be on that path.
enum GPUControlArmTool {
    static let installedPath = "/usr/local/bin/gpucontrol"
    /// The whole command the administrator dialog runs: a fixed path, no
    /// input from anyone.
    static let armCommand = installedPath + " arm"
    /// Where DrogaBoxGPU's build leaves the tool, under the home folder.
    static let buildRelativePath = "Desktop/DrogaBoxGPU/sensors/build/gpucontrol"

    struct FileInfo: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case regular, directory, symlink, other }
        var kind: Kind
        var uid: UInt32
        /// The permission bits (`st_mode & 07777`).
        var permissions: UInt16
    }

    /// `lstat`, or a test's table.
    typealias Lookup = (String) -> FileInfo?

    enum Availability: Equatable, Sendable {
        /// Installed safely: the button can run it.
        case button
        /// Installed, but something on its path is not root's alone: only
        /// the command is shown, for the owner to run.
        case unsafe(String)
        /// Not installed. `buildPath`: the tool where DrogaBoxGPU builds it,
        /// when it is there.
        case missing(buildPath: String?)

        /// The command the page shows to copy.
        var command: String {
            switch self {
            case .button, .unsafe: return "sudo " + GPUControlArmTool.armCommand
            case .missing(let buildPath?): return "sudo " + buildPath + " arm"
            case .missing(nil): return "sudo " + GPUControlArmTool.armCommand
            }
        }
    }

    static func availability(lookup: Lookup, home: String) -> Availability {
        guard let file = lookup(installedPath) else {
            let build = (home as NSString).appendingPathComponent(buildRelativePath)
            return .missing(buildPath: lookup(build)?.kind == .regular ? build : nil)
        }
        if let problem = problem(file: file, lookup: lookup) { return .unsafe(problem) }
        return .button
    }

    /// Nil when the file and every folder above it belong to root alone.
    static func problem(file: FileInfo, lookup: Lookup) -> String? {
        guard file.kind == .regular else { return "\(installedPath) is not a plain file" }
        guard file.uid == 0 else { return "\(installedPath) does not belong to root" }
        guard file.permissions == 0o755 else {
            return "\(installedPath) has mode \(String(file.permissions, radix: 8)), not 755"
        }
        var folder = (installedPath as NSString).deletingLastPathComponent
        while true {
            guard let info = lookup(folder) else { return "\(folder) cannot be read" }
            guard info.kind == .directory else { return "\(folder) is not a plain folder" }
            guard info.uid == 0 else { return "\(folder) does not belong to root" }
            guard info.permissions & 0o022 == 0 else { return "\(folder) can be written by others than root" }
            if folder == "/" { return nil }
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    /// The real file system, without following a link.
    static func lstatInfo(_ path: String) -> FileInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let type = st.st_mode & S_IFMT
        let kind: FileInfo.Kind = type == S_IFREG ? .regular : type == S_IFDIR ? .directory
            : type == S_IFLNK ? .symlink : .other
        return FileInfo(kind: kind, uid: st.st_uid, permissions: UInt16(st.st_mode & 0o7777))
    }
}

// MARK: - Remembering the setting (plan 8, D4 = at launch and at wake)

/// What the app remembers: only what it held, confirmed by the kext.
enum GPUControlRemembered: Equatable, Sendable {
    case nothing
    case power(watts: Int)

    static func load(_ defaults: UserDefaults) -> Self {
        guard defaults.string(forKey: DefaultsKey.gpuControlRememberedKind) == "power" else { return .nothing }
        let watts = defaults.integer(forKey: DefaultsKey.gpuControlRememberedWatts)
        return watts > 0 ? .power(watts: watts) : .nothing
    }

    func save(_ defaults: UserDefaults) {
        switch self {
        case .nothing:
            defaults.set("none", forKey: DefaultsKey.gpuControlRememberedKind)
            defaults.removeObject(forKey: DefaultsKey.gpuControlRememberedWatts)
        case .power(let watts):
            defaults.set("power", forKey: DefaultsKey.gpuControlRememberedKind)
            defaults.set(watts, forKey: DefaultsKey.gpuControlRememberedWatts)
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
        return ownerChoseStartUp ? .nothing : nil
    }

    /// The request to make for a remembered setting, or nil: only with
    /// remembering active, writing already open (never a password), nobody
    /// else holding, and the control not stopped (a failure or the watchdog
    /// keep it from asking until the app starts again).
    static func request(remembered: GPUControlRemembered, active: Bool,
                        facts: GPUControlFacts?, stopped: GPUControlStop?) -> GPUControlRequest? {
        guard active, stopped == nil, let facts, facts.armed, !facts.off, facts.writeOffCode == 0,
              !(facts.owned && !facts.mine) else { return nil }
        guard case .power(let watts) = remembered, watts > 0, let boot = facts.bootW,
              GPUControlPageLogic.powerChoices(bootW: boot).contains(watts), watts != boot else { return nil }
        return .power(watts: UInt32(watts))
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
