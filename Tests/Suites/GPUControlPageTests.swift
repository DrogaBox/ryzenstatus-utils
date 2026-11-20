// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GPU control page (plan phase 2): its states from the kext model and
/// from the real 0.7.2 properties, the power pop-up, the notes, opening
/// writing (the file checks, never the dialog), remembering, the connection
/// rules, the page's visibility, and the strings.
enum GPUControlPageTests {
    static func run(_ suite: TestSuite) {
        statesFromStatus(suite)
        statesFromProperties(suite)
        powerChoices(suite)
        notes(suite)
        armTool(suite)
        remember(suite)
        connection(suite)
        visibility(suite)
        strings(suite)
        reviewFixes(suite)
    }

    /// Fixes from the review of phase 2.
    private static func reviewFixes(_ suite: TestSuite) {
        let s = GPUControlPageStrings.es
        var facts = GPUControlFacts(source: .channel)
        facts.ready = true
        facts.armed = true
        facts.bootW = 240
        facts.heldW = 240
        // Any pending request reads "Applying…", never "Ready" next to watts
        // the kext has not taken.
        for activity: GPUControlSnapshot.Activity in [.applying(.power(watts: 220)),
                                                      .retrying(.power(watts: 220), .reply(.busy)),
                                                      .switching(.power(watts: 220)),
                                                      .afterWake(.power(watts: 220))] {
            var snapshot = GPUControlSnapshot()
            snapshot.activity = activity
            let input = GPUControlPageInput(facts: facts, state: .ready, snapshot: snapshot)
            suite.expect(input.isPending && input.stateTitle(s, short: false) == s.applying
                            && input.stateTitle(s, short: true) == s.applying,
                         "\(activity): applying on the page and in the panel")
        }
        let idle = GPUControlPageInput(facts: facts, state: .ready, snapshot: GPUControlSnapshot())
        suite.expect(!idle.isPending && idle.stateTitle(s, short: false) == s.ready, "nothing pending: ready")
        // OD8 holds in words, not "Ready".
        let curve = GPUControlOD8Want(curve: GPUControlChannelTests.testedCurve, zeroRpmOff: true)
        let held = GPUControlPageInput(facts: facts, state: .heldByApp(.od8(curve)), snapshot: GPUControlSnapshot())
        suite.expect(held.stateTitle(s, short: false)
                        == "RyzenStatus mantiene una curva de ventilador y el ventilador siempre girando",
                     "a held curve and zero RPM off, in one sentence")
        let all = GPUControlOD8Want(curve: GPUControlChannelTests.testedCurve, zeroRpmOff: true, gfxMaxMHz: 2_300)
        suite.expect(GPUControlPageStrings.enUS.od8Held(all)
                        == "RyzenStatus is holding a fan curve, the fan always running and a GFX maximum of 2300 MHz",
                     "three held settings: commas, then the language's \"and\"")
        suite.expect(GPUControlPageStrings.ja.od8Held(curve) == "RyzenStatus が保持中: ファンカーブと常に回るファン",
                     "Japanese joins with と, not an English comma")
        suite.expect(GPUControlPageStrings.zhHans.od8Held(all) == "RyzenStatus 正在维持：风扇曲线、始终转动的风扇和GFX 最大时钟 2300 MHz",
                     "Chinese: 、 between the items, 和 before the last")
        suite.expect(GPUControlPageStrings.enUS.od8Held(GPUControlOD8Want(gfxMaxMHz: 2_300))
                        == "RyzenStatus is holding a GFX maximum of 2300 MHz", "a held clock, in words")
        // The panel row has two caption lines: a short title, not the list.
        let heldAll = GPUControlPageInput(facts: facts, state: .heldByApp(.od8(all)), snapshot: GPUControlSnapshot())
        for language in AppLanguage.allCases {
            let t = FeatureStrings.gpuControlPage(language)
            let short = heldAll.stateTitle(t, short: true)
            suite.expect(short == t.heldOD8Short && short.count <= 40 && short.count < heldAll.stateTitle(t, short: false).count,
                         "\(language.rawValue): an OD8 hold in the panel row is short (\(short.count))")
        }
        // The channel version is an argument, not a "2" in the text.
        let other = GPUControlPageInput(facts: facts, state: .otherVersion(1), snapshot: nil)
        suite.expect(other.stateTitle(GPUControlPageStrings.enUS, short: false)
                        == "The kext speaks channel version 1 and the app version 2. Update one of them.",
                     "both versions come from numbers")
        // The changelog keeps its own structure.
        let changelog = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath + "/CHANGELOG.md",
                                     encoding: .utf8)) ?? ""
        suite.expect(!changelog.contains("## [Unreleased]"), "no invented changelog heading")
        let firstRelease = changelog.range(of: "\n## [")?.lowerBound ?? changelog.startIndex
        suite.expect(changelog[..<firstRelease].contains("GPU power limit"),
                     "the GPU control page has its paragraph above the first release")
        // The page source: the status header, the remember section apart.
        let view = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath
                                + "/Sources/RyzenStatus/UI/Settings/GPUControlSettingsView.swift", encoding: .utf8)) ?? ""
        suite.expect(view.contains("Text(s.stateSection)"), "the status section has its header")
        suite.expect(view.contains("            rememberSection\n"), "remembering has its own section, shown while closed")
    }

    private typealias Harness = GPUControlChannelTests.Harness

    private static func state(_ h: Harness) -> GPUControlPageState? {
        let facts = GPUControlPageLogic.facts(snapshot: h.engine.snapshot, control: nil)
        return facts.map { GPUControlPageLogic.state(facts: $0, snapshot: h.engine.snapshot) }
    }

    /// Every state of plan 7.4 that `status` shows, made by the model.
    private static func statesFromStatus(_ suite: TestSuite) {
        do {
            let h = Harness(armed: false)
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(state(h) == .closed, "not armed: closed")
        }
        do {
            let h = Harness()
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(state(h) == .ready, "armed, nothing held: ready")
            let facts = GPUControlPageLogic.facts(snapshot: h.engine.snapshot, control: nil)
            suite.expect(facts?.source == .channel && facts?.bootW == 240 && facts?.heldW == 240,
                         "from status: the start-up 240 W")
        }
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(state(h) == .heldByApp(.power(watts: 220)), "mine: held by the app")
            let facts = GPUControlPageLogic.facts(snapshot: h.engine.snapshot, control: nil)!
            suite.expect(GPUControlPageLogic.shownWatts(facts: facts, snapshot: h.engine.snapshot) == 220,
                         "the pop-up shows the held 220 W")
            h.engine.choose(.startUp)
            h.run(ms: 0)
            suite.expect(state(h) == .reverting, "going back: reverting")
        }
        do {
            let h = Harness()
            let other = h.fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(state(h) == .heldByOther, "owned without mine: another program")
            let facts = GPUControlPageLogic.facts(snapshot: h.engine.snapshot, control: nil)!
            suite.expect(GPUControlPageLogic.shownWatts(facts: facts, snapshot: h.engine.snapshot) == 230,
                         "the pop-up shows what the kext holds, 230 W")
            suite.expect(!GPUControlPageState.heldByOther.acceptsChoices, "another program: the controls are off")
        }
        do {
            let h = Harness()
            h.fake.sleep()
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(state(h) == .sleeping, "between sleep and wake: sleeping")
        }
        do {
            let h = Harness()
            h.fake.driverReady = false
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(state(h) == .waitingForDriver, "no ready flag: waiting for the driver")
        }
        // Writing off: stopped controller, facts from the properties.
        for reason in GPUControlWriteOff.allCases where reason != .none {
            let fake = FakeGPUControlKext()
            fake.arm()
            fake.turnOff(reason)
            let control = GPUControlService.fakeControl(fake)
            let facts = GPUControlPageLogic.facts(snapshot: nil, control: control)
            let shown = facts.map { GPUControlPageLogic.state(facts: $0, snapshot: nil) }
            suite.expect(shown == .writingOff(reason, text: reason.kextText, restart: false),
                         "off for \(reason): writing off with the kext's reason")
        }
        // Restart the Mac only when OD8 may not be at stock and nothing runs.
        do {
            var facts = GPUControlFacts(source: .channel)
            facts.ready = true
            facts.off = true
            facts.writeOffCode = GPUControlWriteOff.od8Failed.rawValue
            facts.od8Held = .unknown
            suite.expect(GPUControlPageLogic.state(facts: facts, snapshot: nil)
                            == .writingOff(.od8Failed, text: nil, restart: true), "OD8 held 8 after a failure: restart")
            facts.reverting = true
            if case .writingOff(_, _, let restart) = GPUControlPageLogic.state(facts: facts, snapshot: nil) {
                suite.expect(!restart, "a way back still running: no restart sentence yet")
            }
            facts.reverting = false
            facts.writeOffCode = GPUControlWriteOff.od8Watchdog.rawValue
            if case .writingOff(_, _, let restart) = GPUControlPageLogic.state(facts: facts, snapshot: nil) {
                suite.expect(!restart, "the watchdog's own way back: its own sentence, not restart")
            }
        }
        // Another version, and a dead connection, come from the controller.
        do {
            let h = Harness { $0.version = 1 }
            h.engine.refresh()
            h.run(ms: 0)
            let facts = GPUControlFacts(source: .properties)
            suite.expect(GPUControlPageLogic.state(facts: facts, snapshot: h.engine.snapshot) == .otherVersion(1),
                         "a version 1 kext: other version")
        }
        do {
            let h = Harness()
            h.engine.refresh()
            h.run(ms: 0)
            h.connection.close()
            h.engine.refresh()
            h.run(ms: 0)
            let facts = GPUControlFacts(source: .properties)
            suite.expect(GPUControlPageLogic.state(facts: facts, snapshot: h.engine.snapshot) == .connectionLost,
                         "a dead connection: lost")
        }
    }

    /// Without a connection: the properties (the real 0.7.2 table).
    private static func statesFromProperties(_ suite: TestSuite) {
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let control = GPUControlStatus.parse(table) else {
            suite.expect(false, "the 0.7.2 fixture loads")
            return
        }
        let facts = GPUControlPageLogic.facts(snapshot: nil, control: control)
        suite.expect(facts?.source == .properties && facts?.bootW == 240 && facts?.heldW == 240,
                     "0.7.2 properties: the start-up 240 W from PowerWatch and WriteState")
        suite.expect(facts.map { GPUControlPageLogic.state(facts: $0, snapshot: nil) } == .closed,
                     "0.7.2 here: closed")
        suite.expect(control.writing?.kextVersion == "REL-072-2026-11-19", "the kext's build name")
        // The model's properties read the same way as the kext's.
        let fake = FakeGPUControlKext()
        fake.arm()
        let c = fake.connection()
        _ = c.open()
        _ = c.setPower(watts: 220)
        let other = GPUControlService.fakeControl(fake).flatMap { GPUControlPageLogic.facts(snapshot: nil, control: $0) }
        suite.expect(other.map { GPUControlPageLogic.state(facts: $0, snapshot: nil) } == .heldByOther,
                     "from the properties a hold is someone's: the app holds nothing without its connection")
        // A stopped controller (no channel) falls back to the properties.
        let noChannel = GPUControlEngine(channel: nil, clock: { 0 }).snapshot
        suite.expect(GPUControlPageLogic.facts(snapshot: noChannel, control: control)?.source == .properties,
                     "no channel: the properties")
        // Without the write path there is no page.
        var old = table
        old["Write"] = nil
        suite.expect(GPUControlStatus.parse(old).flatMap { GPUControlFacts(control: $0) } == nil,
                     "a kext before 0.5.0: no facts, no page")
    }

    private static func powerChoices(_ suite: TestSuite) {
        suite.expect(GPUControlPageLogic.powerChoices(bootW: 240) == [240, 230, 220, 210, 200], "240 W: five values")
        suite.expect(GPUControlPageLogic.powerChoices(bootW: 264) == [264, 260, 250, 240, 230, 220, 210, 200],
                     "264 W: the start-up value, then every 10 W down to 200")
        suite.expect(GPUControlPageLogic.powerChoices(bootW: 200) == [200], "200 W: nothing lower")
        suite.expect(GPUControlPageLogic.powerChoices(bootW: 205) == [205, 200], "205 W: 200 below it")
        suite.expect(GPUControlPageLogic.powerChoices(bootW: nil).isEmpty
                         && GPUControlPageLogic.powerChoices(bootW: 150).isEmpty
                         && GPUControlPageLogic.powerChoices(bootW: 301).isEmpty,
                     "no believable start-up value: no choices")
        // Every value offered is one the kext takes.
        for boot in [200, 205, 240, 264, 300] {
            let fake = FakeGPUControlKext()
            fake.bootW = UInt32(boot)
            fake.arm()
            for watts in GPUControlPageLogic.powerChoices(bootW: boot) {
                let c = fake.connection()
                _ = c.open()
                let reply = c.setPower(watts: UInt32(watts))?.reply
                suite.expect(reply == .ok, "boot \(boot) W: \(watts) W is taken")
                c.close()
                fake.advance(by: 3_000)
            }
        }
        // While asking, the pop-up shows the request.
        var snapshot = GPUControlSnapshot()
        snapshot.activity = .applying(.power(watts: 210))
        var facts = GPUControlFacts(source: .channel)
        facts.bootW = 240
        facts.heldW = 240
        suite.expect(GPUControlPageLogic.shownWatts(facts: facts, snapshot: snapshot) == 210, "applying: the asked value")
        snapshot.activity = .applying(.startUp)
        suite.expect(GPUControlPageLogic.shownWatts(facts: facts, snapshot: snapshot) == 240, "going back: the start-up value")
    }

    private static func notes(_ suite: TestSuite) {
        let s = GPUControlPageStrings.enUS
        func note(_ outcome: GPUControlSnapshot.Outcome?, activity: GPUControlSnapshot.Activity = .none) -> GPUControlPageNote? {
            var snapshot = GPUControlSnapshot()
            snapshot.outcome = outcome
            snapshot.activity = activity
            return GPUControlPageNote.make(snapshot, s)
        }
        let below = GPUControlAnswer(replyCode: GPUControlReply.belowFloor.rawValue)
        suite.expect(note(.refused(.power(watts: 190), below))
                        == GPUControlPageNote(sentence: s.notAllowed, kextText: "refused: below 200 W", isProblem: true),
                     "a refusal: the group's sentence, the kext's words under it")
        let unknown = GPUControlAnswer(replyCode: 77)
        suite.expect(note(.refused(.power(watts: 220), unknown))?.sentence == "reply 77",
                     "an unknown reply: its number, no group")
        suite.expect(note(.gaveUp(.power(watts: 220), .notReady))?.sentence == String(format: s.gaveUpFormat, s.notReady),
                     "given up: after a minute, why")
        suite.expect(note(.otherProgram)?.sentence == s.heldByOther, "another program")
        suite.expect(note(.closed)?.sentence == s.closedGroup, "closed")
        suite.expect(note(.timedOut)?.kextText == GPUControlReply.timeout.kextText, "timeout with the kext's words")
        suite.expect(note(.lost)?.isProblem == false && note(.backAfterWake)?.sentence == s.backAfterWake,
                     "lost and back after the wake: information, not errors")
        suite.expect(note(nil, activity: .afterWake(.power(watts: 220)))?.sentence == String(format: s.reaskingFormat, 220),
                     "after a wake with remembering: asking again, never shown as held")
        suite.expect(note(nil) == nil, "nothing happened: no note")
    }

    private static func armTool(_ suite: TestSuite) {
        typealias Tool = GPUControlArmTool
        let rootDir = Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o755)
        let rootTool = Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o755)
        let safe: [String: Tool.FileInfo] = [
            "/usr/local/bin/gpucontrol": rootTool, "/usr/local/bin": rootDir, "/usr/local": rootDir,
            "/usr": rootDir, "/": Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o1755),
        ]
        let ours: Tool.Signature = { _ in Tool.identifier }
        func availability(_ table: [String: Tool.FileInfo], signature: @escaping Tool.Signature = ours,
                          home: String = "/Users/someone") -> Tool.Availability {
            Tool.availability(lookup: { table[$0] }, signature: signature, home: home)
        }
        suite.expect(availability(safe) == .button, "our signed tool, root's, in root's folders: the button")
        suite.expect(Tool.armCommand == "/usr/local/bin/gpucontrol arm", "the dialog runs a fixed command")
        suite.expect(AdminShell.appleScriptSource(command: Tool.armCommand, prompt: "p")
                        == "do shell script \"/usr/local/bin/gpucontrol arm\" with administrator privileges with prompt \"p\"",
                     "the administrator script carries the fixed command and nothing else")
        // The installer's rule is "no group or other write", not one mode.
        for mode: UInt16 in [0o755, 0o555, 0o700, 0o750] {
            var table = safe
            table["/usr/local/bin/gpucontrol"] = Tool.FileInfo(kind: .regular, uid: 0, permissions: mode)
            suite.expect(availability(table) == .button, "mode \(String(mode, radix: 8)): no group or other write, the button")
        }
        let cases: [(String, Tool.FileInfo, String)] = [
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .regular, uid: 501, permissions: 0o755), "the user's file"),
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o775), "group can write the file"),
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o757), "others can write the file"),
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o4755), "setuid file"),
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .symlink, uid: 0, permissions: 0o755), "a link"),
            ("/usr/local/bin/gpucontrol", Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o755, hasACL: true),
             "an access control list on the file"),
            ("/usr/local/bin", Tool.FileInfo(kind: .directory, uid: 501, permissions: 0o755), "the user's bin folder (Homebrew)"),
            ("/usr/local/bin", Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o775), "group can write bin"),
            ("/usr/local/bin", Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o755, hasACL: true),
             "an access control list on bin"),
            ("/usr/local", Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o757), "others can write /usr/local"),
            ("/usr/local", Tool.FileInfo(kind: .symlink, uid: 0, permissions: 0o755), "/usr/local is a link"),
            ("/usr", Tool.FileInfo(kind: .directory, uid: 0, permissions: 0o755, hasACL: true), "an access control list on /usr"),
            ("/", Tool.FileInfo(kind: .directory, uid: 501, permissions: 0o755), "the root folder is not root's"),
        ]
        for (path, info, why) in cases {
            var table = safe
            table[path] = info
            guard case .unsafe(let reason, let failed) = availability(table) else {
                suite.expect(false, "\(why): no button")
                continue
            }
            suite.expect(failed == path, "\(why): the failing path is \(path)")
            suite.expect(!GPUControlPageStrings.es.sentence(reason).isEmpty, "\(why): a translated reason")
            suite.expect(availability(table).command == "sudo /usr/local/bin/gpucontrol arm", "\(why): the command to copy")
        }
        suite.expect(availability(safe, signature: { _ in nil }) == .unsafe(.signature, path: Tool.installedPath),
                     "a broken signature: no button")
        suite.expect(availability(safe, signature: { _ in "com.example.gpucontrol" })
                        == .unsafe(.otherProgram, path: Tool.installedPath), "another identifier: no button")
        // Setuid or setgid is its own reason: nobody but root can change a
        // 4755 file, so "anyone other than root can change it" would be wrong.
        let setIDModes: [(UInt16, String)] = [(0o4755, "setuid"), (0o2755, "setgid"), (0o6755, "both")]
        for (mode, why) in setIDModes {
            var table = safe
            table[Tool.installedPath] = Tool.FileInfo(kind: .regular, uid: 0, permissions: mode)
            suite.expect(availability(table) == .unsafe(.setID, path: Tool.installedPath), "\(why): the setuid/setgid reason")
        }
        var groupWrite = safe
        groupWrite[Tool.installedPath] = Tool.FileInfo(kind: .regular, uid: 0, permissions: 0o4775)
        suite.expect(availability(groupWrite) == .unsafe(.writable, path: Tool.installedPath),
                     "setuid and group write: the write comes first")
        suite.expect(GPUControlPageStrings.enUS.sentence(.setID) == "It has the setuid or setgid bit set."
                        && GPUControlPageStrings.enUS.sentence(.writable) == "Anyone other than root can change it.",
                     "the two English sentences")
        // The rule and the reason read as two sentences, in every language.
        suite.expect(String(format: GPUControlPageStrings.enUS.unsafeToolFormat, GPUControlPageStrings.enUS.sentence(.notRoot))
                        == "The button needs gpucontrol and every folder above it to belong to root alone. It does not belong to root.",
                     "the rule, a full stop, then the reason")
        for language in AppLanguage.allCases {
            let t = FeatureStrings.gpuControlPage(language)
            let text = String(format: t.unsafeToolFormat, t.sentence(.notRoot))
            suite.expect(!text.contains(":") && !text.contains("：") && text.hasSuffix(t.sentence(.notRoot)),
                         "\(language.rawValue): no colon before the reason")
        }
        var userBin = safe
        userBin["/usr/local/bin"] = Tool.FileInfo(kind: .directory, uid: 501, permissions: 0o755)
        suite.expect(availability(userBin) == .unsafe(.notRoot, path: "/usr/local/bin"),
                     "a bin folder that is not root's: that reason and that folder")
        for reason in Tool.UnsafeReason.allCases {
            for language in AppLanguage.allCases {
                suite.expect(!FeatureStrings.gpuControlPage(language).sentence(reason).isEmpty,
                             "\(language.rawValue): a sentence for \(reason)")
            }
        }
        var unreadable = safe
        unreadable["/usr"] = nil
        if case .unsafe = availability(unreadable) {} else { suite.expect(false, "a folder that cannot be read: no button") }
        var missing = safe
        missing["/usr/local/bin/gpucontrol"] = nil
        suite.expect(availability(missing) == .missing(buildPath: nil), "not installed, no build: missing")
        suite.expect(availability(missing).command == "sudo /usr/local/bin/gpucontrol arm", "missing: the installed command")
        missing["/Users/someone/Desktop/DrogaBoxGPU/sensors/build/gpucontrol"] =
            Tool.FileInfo(kind: .regular, uid: 501, permissions: 0o755)
        let build = availability(missing)
        suite.expect(build == .missing(buildPath: "/Users/someone/Desktop/DrogaBoxGPU/sensors/build/gpucontrol"),
                     "not installed, built: the build path")
        suite.expect(build.command == "sudo /Users/someone/Desktop/DrogaBoxGPU/sensors/build/gpucontrol arm",
                     "the build path's command to copy (never run by the app)")

        realFiles(suite)

        // The service runs only that command, only from the button.
        let source = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath
                                    + "/Sources/RyzenStatus/Services/Metrics/GPUControlService.swift", encoding: .utf8)) ?? ""
        suite.expect(source.components(separatedBy: "AdminShell.").count == 2
                        && source.contains("AdminShell.run(GPUControlArmTool.armCommand, prompt: prompt)"),
                     "one administrator call, with the fixed command")
        suite.expect(source.contains("guard armTool == .button else { return }"),
                     "the button checks the file again right before the dialog")
    }

    /// The same checks on real files in a folder this test owns: its user
    /// stands in for root and the folder for "/". Never the real tool.
    private static func realFiles(_ suite: TestSuite) {
        typealias Tool = GPUControlArmTool
        @discardableResult
        func run(_ tool: String, _ arguments: [String]) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }
        let top = NSTemporaryDirectory() + "gpucontrol-armtool-\(getpid())"
        let bin = top + "/bin"
        let tool = bin + "/gpucontrol"
        try? FileManager.default.removeItem(atPath: top)
        try? FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        run("/bin/chmod", ["755", top])
        try? FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: tool)
        run("/bin/chmod", ["755", tool])
        // An ad hoc signature with our identifier, as DrogaBoxGPU signs it.
        let signed = run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", Tool.identifier, tool])
        suite.expect(signed == 0, "the test's copy is signed ad hoc as com.droga.gpucontrol")
        let me = getuid()
        func check(_ path: String = tool) -> Tool.Problem? {
            Tool.problem(path: path, owner: me, top: top, lookup: Tool.lstatInfo, signature: Tool.signingIdentifier)
        }
        suite.expect(Tool.signingIdentifier(tool) == Tool.identifier, "the signature reads back as com.droga.gpucontrol")
        suite.expect(Tool.signingIdentifier("/usr/bin/true") == "com.apple.true", "a system tool reads as its own identifier")
        suite.expect(check() == nil, "own folder, own signed tool, mode 755, no ACL: safe")
        suite.expect(Tool.lstatInfo(tool) == Tool.FileInfo(kind: .regular, uid: me, permissions: 0o755, hasACL: false),
                     "lstat: a plain file, the user's, mode 755, no ACL")

        run("/bin/chmod", ["775", tool])
        suite.expect(check() == Tool.Problem(reason: .writable, path: tool, detail: "mode 775"),
                     "group write on the file: unsafe")
        run("/bin/chmod", ["700", tool])
        suite.expect(check() == nil, "mode 700, no group or other write: safe")
        run("/bin/chmod", ["757", bin])
        run("/bin/chmod", ["755", tool])
        suite.expect(check()?.reason == .writable && check()?.path == bin, "others can write the folder: unsafe")
        run("/bin/chmod", ["755", bin])

        run("/bin/chmod", ["+a", "everyone allow write", tool])
        suite.expect(Tool.hasExtendedACL(tool), "an ACL on the file is seen")
        suite.expect(check() == Tool.Problem(reason: .accessControlList, path: tool), "an ACL on the file: unsafe")
        run("/bin/chmod", ["-N", tool])
        suite.expect(!Tool.hasExtendedACL(tool) && check() == nil, "the ACL removed: safe again")

        run("/bin/chmod", ["+a", "everyone allow add_file", bin])
        suite.expect(check() == Tool.Problem(reason: .accessControlList, path: bin), "an ACL on the folder: unsafe")
        run("/bin/chmod", ["-N", bin])

        try? FileManager.default.createSymbolicLink(atPath: bin + "/link", withDestinationPath: tool)
        suite.expect(Tool.lstatInfo(bin + "/link")?.kind == .symlink, "lstat does not follow a link")
        suite.expect(check(bin + "/link")?.reason == .notPlain, "a link to the tool: unsafe")

        if let handle = FileHandle(forWritingAtPath: tool) {
            handle.seekToEndOfFile()
            handle.write(Data([0]))
            try? handle.close()
        }
        suite.expect(Tool.signingIdentifier(tool) == nil, "a byte added after signing: the signature is broken")
        suite.expect(check() == Tool.Problem(reason: .signature, path: tool), "a changed tool: unsafe")
        suite.expect(Tool.problem(path: tool, lookup: Tool.lstatInfo, signature: Tool.signingIdentifier) != nil,
                     "with the app's own rule (root, \"/\") a user's file is never safe")
        suite.expect(Tool.lstatInfo(top + "/none") == nil, "lstat: nothing there")
        try? FileManager.default.removeItem(atPath: top)
    }

    private static func remember(_ suite: TestSuite) {
        typealias Policy = GPUControlRememberPolicy
        suite.expect(Policy.isActive(enabled: true, isDeveloperBuild: false), "on in the installed app")
        suite.expect(!Policy.isActive(enabled: true, isDeveloperBuild: true), "never in a development build")
        suite.expect(!Policy.isActive(enabled: false, isDeveloperBuild: false), "off by default")

        suite.expect(Policy.toSave(held: .power(watts: 220), ownerChoseStartUp: false, active: true) == .power(watts: 220),
                     "a confirmed hold is saved")
        suite.expect(Policy.toSave(held: .power(watts: 220), ownerChoseStartUp: false, active: false) == nil,
                     "nothing saved while remembering is off")
        suite.expect(Policy.toSave(held: nil, ownerChoseStartUp: true, active: true) == .nothing,
                     "going back by choice forgets it")
        suite.expect(Policy.toSave(held: nil, ownerChoseStartUp: false, active: true) == nil,
                     "a hold lost to a wake or the kext keeps what was saved")

        var facts = GPUControlFacts(source: .properties)
        facts.ready = true
        facts.armed = true
        facts.bootW = 240
        facts.heldW = 240
        let remembered = GPUControlRemembered.power(watts: 220)
        suite.expect(Policy.request(remembered: remembered, active: true, facts: facts, stopped: nil) == .power(watts: 220),
                     "writing open, nobody holding: ask for it")
        suite.expect(Policy.request(remembered: remembered, active: false, facts: facts, stopped: nil) == nil,
                     "remembering off: nothing")
        suite.expect(Policy.request(remembered: .nothing, active: true, facts: facts, stopped: nil) == nil,
                     "nothing remembered: nothing")
        suite.expect(Policy.request(remembered: remembered, active: true, facts: facts, stopped: .writingOff(14)) == nil,
                     "after a failure or the watchdog: nothing until the app starts again")
        suite.expect(Policy.request(remembered: .power(watts: 225), active: true, facts: facts, stopped: nil) == nil,
                     "a value the pop-up would not offer: nothing")
        suite.expect(Policy.request(remembered: .power(watts: 240), active: true, facts: facts, stopped: nil) == nil,
                     "the start-up value: nothing to ask")
        var closed = facts
        closed.armed = false
        suite.expect(Policy.request(remembered: remembered, active: true, facts: closed, stopped: nil) == nil,
                     "writing closed: nothing, never a password")
        var other = facts
        other.owned = true
        suite.expect(Policy.request(remembered: remembered, active: true, facts: other, stopped: nil) == nil,
                     "another program holds it: nothing")
        var off = facts
        off.off = true
        off.writeOffCode = GPUControlWriteOff.od8Watchdog.rawValue
        suite.expect(Policy.request(remembered: remembered, active: true, facts: off, stopped: nil) == nil,
                     "writing off: nothing")
        var smaller = facts
        smaller.bootW = 230
        suite.expect(Policy.request(remembered: .power(watts: 230), active: true, facts: smaller, stopped: nil) == nil,
                     "a remembered value that is now the start-up one: nothing")

        // The keys round-trip.
        let suiteName = "ryzenstatus.tests.gpucontrol.\(getpid())"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        suite.expect(GPUControlRemembered.load(defaults) == .nothing, "nothing saved: nothing")
        GPUControlRemembered.power(watts: 210).save(defaults)
        suite.expect(defaults.string(forKey: DefaultsKey.gpuControlRememberedKind) == "power"
                        && defaults.integer(forKey: DefaultsKey.gpuControlRememberedWatts) == 210,
                     "saved as kind power, 210 W")
        suite.expect(GPUControlRemembered.load(defaults) == .power(watts: 210), "loads back")
        GPUControlRemembered.nothing.save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .nothing
                        && defaults.object(forKey: DefaultsKey.gpuControlRememberedWatts) == nil, "forgotten")
        suite.expect(defaults.object(forKey: DefaultsKey.gpuControlRemember) == nil, "the box is off unless set")
        defaults.removePersistentDomain(forName: suiteName)

        // The controller asks again after a wake only when told to.
        let h = Harness(reask: true)
        h.engine.choose(.power(watts: 220), origin: .remembered)
        h.run(ms: 0)
        suite.expect(h.engine.snapshot.held == .power(watts: 220), "a remembered request is held like any other")
    }

    private static func connection(_ suite: TestSuite) {
        let suiteName = "ryzenstatus.tests.gpucontrol.mode.\(getpid())"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        typealias Mode = GPUControlConnectionMode
        suite.expect(Mode.choose(isDeveloperBuild: false, defaults: defaults) == .real, "the installed app: the real channel")
        suite.expect(Mode.choose(isDeveloperBuild: true, defaults: defaults) == .none,
                     "a development build: nothing, it never takes the control from the installed app")
        defaults.set(true, forKey: "gpuControlReal")
        suite.expect(Mode.choose(isDeveloperBuild: true, defaults: defaults) == .real, "-gpuControlReal YES: real")
        defaults.set(true, forKey: "gpuControlFake")
        suite.expect(Mode.choose(isDeveloperBuild: true, defaults: defaults) == .fake, "-gpuControlFake YES: the model")
        suite.expect(Mode.choose(isDeveloperBuild: false, defaults: defaults) == .real,
                     "the installed app ignores the development switches")
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The page and its search rows exist only with the write path.
    private static func visibility(_ suite: TestSuite) {
        let language = AppLanguage.enUS
        let strings = Strings.enUS
        func state(_ on: Bool) -> SettingsSearchState {
            SettingsSearchState(defaults: .standard, hardware: .init(
                battery: false, notchedDisplay: false, plainDisplay: true, keyboardLight: false,
                bluetoothSleep: false, brightnessOSD: false, gpuControl: on))
        }
        let without = SettingsDirectory.searchItems(strings, language: language, superKeySource: .capsLock, state: state(false))
        let with = SettingsDirectory.searchItems(strings, language: language, superKeySource: .capsLock, state: state(true))
        suite.expect(!without.contains { $0.destination.page == .gpuControl }, "no write path: no GPU control in search")
        suite.expect(with.contains { $0.destination.page == .gpuControl }, "write path: GPU control in search")
        let all = SettingsDirectory.allItems(strings, language: language, superKeySource: .capsLock)
        suite.expect(all.contains { $0.page == .gpuControl }, "the directory itself always lists the page")
        suite.expect(FeatureVisibilitySupport.features(for: .gpuControl).isEmpty, "no feature switch gates the page")
    }

    private static func strings(_ suite: TestSuite) {
        func specifiers(_ text: String) -> [String] {
            let pattern = try? NSRegularExpression(pattern: "%(\\d\\$)?[@d]")
            let range = NSRange(text.startIndex..., in: text)
            return pattern?.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
        }
        let english = GPUControlPageStrings.enUS.all
        suite.expect(english.count == 76, "76 texts")
        for language in AppLanguage.allCases {
            let table = FeatureStrings.gpuControlPage(language).all
            suite.expect(table.count == english.count && table.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "\(language.rawValue): every text is there")
            for (index, text) in table.enumerated() {
                suite.expect(specifiers(text) == specifiers(english[index]),
                             "\(language.rawValue): text \(index) keeps the English placeholders")
            }
            if language != .enUS {
                let same = zip(table, english).filter { $0.0 == $0.1 && $0.0.count > 8 }.map(\.0)
                suite.expect(same.isEmpty, "\(language.rawValue): translated (\(same))")
            }
        }
        // Every group has its sentence in every language.
        for group in GPUControlTextGroup.allCases {
            suite.expect(!GPUControlPageStrings.es.sentence(group).isEmpty, "a sentence for \(group)")
        }
        suite.expect(String(format: GPUControlPageStrings.es.heldPowerFormat, 220) == "RyzenStatus mantiene 220 W",
                     "the held limit in Spanish")
        suite.expect(String(format: GPUControlPageStrings.enUS.liveFormat, "201 W", "1203 RPM", "45 °C")
                        == "Board 201 W · Fan 1203 RPM · Hotspot 45 °C", "the live row's order")
    }
}
