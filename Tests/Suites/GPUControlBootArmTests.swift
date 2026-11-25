// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// "Allow changes after restart too" (`GPUControlBootArm`): the daemon's
/// property list and commands, the start-up script run for real against a
/// signed stand-in tool (it runs it only when every check passes), the page's
/// rules for the switch, and the strings.
enum GPUControlBootArmTests {
    static func run(_ suite: TestSuite) {
        plistAndCommands(suite)
        installedCheck(suite)
        scriptRuns(suite)
        pageRules(suite)
        strings(suite)
    }

    private static func plistAndCommands(_ suite: TestSuite) {
        let data = GPUControlBootArm.plistData()
        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        suite.expect(plist?["Label"] as? String == "com.ryzenstatus.utils.gpu-arm", "the daemon's label")
        let args = plist?["ProgramArguments"] as? [String]
        suite.expect(args?.count == 3 && args?[0] == "/bin/sh" && args?[1] == "-c"
                        && args?[2] == GPUControlBootArm.script(), "it runs the script with the system shell")
        suite.expect(plist?["RunAtLoad"] as? Bool == true && plist?["KeepAlive"] == nil,
                     "once per load: at start-up and right after installing, never kept alive")
        suite.expect(GPUControlBootArm.plistPath == "/Library/LaunchDaemons/com.ryzenstatus.utils.gpu-arm.plist",
                     "a system daemon, root's folder")

        let script = GPUControlBootArm.script()
        suite.expect(script.contains("tool='/usr/local/bin/gpucontrol'") && script.contains("\"$tool\" arm"),
                     "the same fixed command as the button")
        suite.expect(script.contains("identifier \"com.droga.gpucontrol\"") && script.contains("-perm +022")
                        && script.contains("-perm +6000") && script.contains("-user 0"),
                     "the button's checks: signature, no group or other write, no setuid, root's")
        suite.expect(script.contains("'/usr/local/bin' '/usr/local' '/usr' '/'"), "every folder up to /")
        suite.expect(script.contains("-lt 120") && script.contains("/bin/sleep 5"), "10 min of tries, 5 s apart")

        // The install command carries the list as base64 and nothing else to quote.
        let install = GPUControlBootArm.installCommand
        let quoted = install.split(separator: "'", omittingEmptySubsequences: false)
        suite.expect(quoted.count == 3, "one quoted word in the install command")
        if quoted.count == 3 {
            let encoded = String(quoted[1])
            suite.expect(encoded.allSatisfy { $0.isLetter || $0.isNumber || "+/=".contains($0) },
                         "base64 only inside the quotes")
            suite.expect(Data(base64Encoded: encoded) == data, "it writes exactly the property list")
        }
        suite.expect(install.contains("/usr/bin/base64 -D -o " + GPUControlBootArm.plistPath)
                        && !install.contains("/dev/stdin"),
                     "base64 writes the file (install cannot read a pipe)")
        suite.expect(install.contains("chown root:wheel") && install.contains("chmod 0644")
                        && install.contains("plutil -lint") && install.contains("launchctl bootstrap system"),
                     "root's, 0644, checked, loaded")
        suite.expect(install.hasSuffix("|| { /bin/rm -f \(GPUControlBootArm.plistPath); exit 1; }"),
                     "a list that fails a step is removed again")
        suite.expect(GPUControlBootArm.removeCommand
                        == "/bin/launchctl bootout system/com.ryzenstatus.utils.gpu-arm 2>/dev/null; /bin/rm -f /Library/LaunchDaemons/com.ryzenstatus.utils.gpu-arm.plist",
                     "off: unload and remove, nothing else")
    }

    private static func installedCheck(_ suite: TestSuite) {
        typealias Info = GPUControlArmTool.FileInfo
        func lookup(_ info: Info?) -> GPUControlArmTool.Lookup { { path in
            path == GPUControlBootArm.plistPath ? info : nil
        } }
        suite.expect(!GPUControlBootArm.isInstalled(lookup: lookup(nil)), "no file: off")
        suite.expect(GPUControlBootArm.isInstalled(lookup: lookup(Info(kind: .regular, uid: 0, permissions: 0o644))),
                     "root's file: on")
        suite.expect(!GPUControlBootArm.isInstalled(lookup: lookup(Info(kind: .regular, uid: 501, permissions: 0o644))),
                     "someone else's file: off")
        suite.expect(!GPUControlBootArm.isInstalled(lookup: lookup(Info(kind: .symlink, uid: 0, permissions: 0o755))),
                     "a link: off")
    }

    /// The real script with its paths moved to a folder of this user, and a
    /// copy of `touch` signed ad hoc as the tool: running "tool arm" leaves
    /// a file named "arm" in the working folder.
    private static func scriptRuns(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gpu-boot-arm-\(getpid())-\(UInt32.random(in: 0...UInt32.max))")
        let folder = root.appendingPathComponent("bin")
        let work = root.appendingPathComponent("work")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o755])
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        } catch {
            suite.expect(false, "temporary folders: \(error)")
            return
        }
        let tool = folder.appendingPathComponent("tool").path
        let identifier = "com.ryzenstatus.tests.bootarm"
        guard (try? fm.copyItem(atPath: "/usr/bin/touch", toPath: tool)) != nil,
              Shell.run("/usr/bin/codesign", ["-s", "-", "-f", "-i", identifier, tool]).status == 0 else {
            suite.expect(false, "the stand-in tool could not be made")
            return
        }
        let armed = work.appendingPathComponent("arm").path

        func ran(owner: UInt32 = getuid(), id: String = identifier, folders: [String]? = nil) -> Bool {
            try? fm.removeItem(atPath: armed)
            let script = GPUControlBootArm.script(tool: tool, folders: folders ?? [folder.path, root.path],
                                                  ownerUID: owner, identifier: id, tries: 1, pause: 0)
            let status = Shell.run("/bin/sh", ["-c", "cd \(GPUControlBootArm.shellQuoted(work.path)) || exit 9\n" + script]).status
            suite.expect(status == 0, "the script always ends quietly (status \(status))")
            return fm.fileExists(atPath: armed)
        }

        suite.expect(ran(), "every check passes: the tool runs with arm")
        suite.expect(!ran(owner: 0), "a tool that is not the owner's: not run")
        suite.expect(!ran(id: "com.droga.gpucontrol"), "another identifier: not run")
        suite.expect(!ran(folders: [folder.path, root.appendingPathComponent("missing").path]),
                     "a folder that is not there: not run")

        _ = chmod(folder.path, 0o775)
        suite.expect(!ran(), "a folder writable by its group: not run")
        _ = chmod(folder.path, 0o755)
        _ = chmod(tool, 0o757)
        suite.expect(!ran(), "a tool writable by others: not run")
        _ = chmod(tool, 0o4755)
        suite.expect(!ran(), "a setuid tool: not run")
        _ = chmod(tool, 0o755)
        suite.expect(Shell.run("/bin/chmod", ["+a", "everyone allow write", folder.path]).status == 0
                        && !ran(), "a folder with an access control list: not run")
        _ = Shell.run("/bin/chmod", ["-N", folder.path])
        suite.expect(ran(), "back to sound: it runs again")

        let link = folder.appendingPathComponent("link").path
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: tool)
        let viaLink = GPUControlBootArm.script(tool: link, folders: [folder.path, root.path],
                                               ownerUID: getuid(), identifier: identifier, tries: 1, pause: 0)
        try? fm.removeItem(atPath: armed)
        _ = Shell.run("/bin/sh", ["-c", "cd \(GPUControlBootArm.shellQuoted(work.path)) || exit 9\n" + viaLink])
        suite.expect(!fm.fileExists(atPath: armed), "the tool through a link: not run")

        try? fm.removeItem(atPath: tool)
        suite.expect(!ran(), "no tool (the GPU commands removed): nothing runs, no error")
    }

    private static func pageRules(_ suite: TestSuite) {
        var input = GPUControlPageInput(facts: nil, state: .closed, snapshot: nil)
        input.armTool = .missing
        suite.expect(!GPUControlPageContent.showsBootArm(input), "no safe tool, nothing installed: hidden")
        input.armTool = .button
        suite.expect(GPUControlPageContent.showsBootArm(input) && GPUControlPageContent.bootArmEnabled(input),
                     "the button's tool: shown, can be turned on")
        input.isChangingBootArm = true
        suite.expect(!GPUControlPageContent.bootArmEnabled(input), "dimmed while the dialog is up")
        input.isChangingBootArm = false
        input.armTool = .unsafe(.writable, path: "/usr/local/bin")
        input.bootArm = true
        suite.expect(GPUControlPageContent.showsBootArm(input) && GPUControlPageContent.bootArmEnabled(input),
                     "installed: can always be turned off, even when the tool is no longer sound")
        input.bootArm = false
        suite.expect(!GPUControlPageContent.showsBootArm(input), "not installed, tool not sound: hidden")
        input.armTool = .button
        input.state = .readOnlyCard
        suite.expect(!GPUControlPageContent.showsBootArm(input), "the read-only card: never offered")
        input.state = .closed
        input.canChoose = false
        suite.expect(!GPUControlPageContent.bootArmEnabled(input), "no controller: dimmed")
    }

    private static func strings(_ suite: TestSuite) {
        let english = GPUControlBootStrings.enUS.all
        suite.expect(english.count == 8, "8 texts")
        for language in AppLanguage.allCases {
            let table = FeatureStrings.gpuControlBoot(language).all
            suite.expect(table.count == english.count && table.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "\(language.rawValue): every text is there")
            suite.expect(table.allSatisfy { !$0.contains("%") }, "\(language.rawValue): no placeholders")
            if language != .enUS {
                let same = zip(table, english).filter { $0.0 == $0.1 && $0.0.count > 8 }.map(\.0)
                suite.expect(same.isEmpty, "\(language.rawValue): translated (\(same))")
            }
        }
        let es = GPUControlBootStrings.es
        suite.expect(es.toggle == "Permitir cambios también después de reiniciar", "the switch in Spanish")
        suite.expect(es.readyWarning.contains("cualquier programa de este Mac")
                        && GPUControlBootStrings.enUS.readyWarning.contains("any program on this Mac"),
                     "the warning still says any program can change it")
        suite.expect(es.footer.contains("una sola vez") && es.footer.contains("no cierra"),
                     "the footer says it asks once and what turning it off leaves open")
    }
}
