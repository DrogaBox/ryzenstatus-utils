// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// The closed-lid rule's install command (`SudoersSupport.installCommand`):
/// no pipe into `install` (which refuses one), the rule carried as base64,
/// checked before sudo can read it, and the write step run for real.
enum SudoersInstallTests {
    static func run(_ suite: TestSuite) {
        command(suite)
        writeStepRuns(suite)
    }

    private static let rulePath = "/etc/sudoers.d/ryzenstatus-clamshell"
    private static let legacy = ["/etc/sudoers.d/ryzenstatus-utils-clamshell"]

    private static func command(_ suite: TestSuite) {
        let rule = SudoersSupport.clamshellRule(uid: 501)
        let command = SudoersSupport.installCommand(rule: rule, rulePath: rulePath, legacyPaths: legacy)
        let staged = SudoersSupport.stagedPath(for: rulePath)

        suite.expect(!command.contains("/usr/bin/install") && !command.contains("install -m")
                        && !command.contains("/dev/stdin"),
                     "no pipe into install: it refuses a source that is not a regular file")
        suite.expect(staged == "/etc/sudoers.d/.ryzenstatus-clamshell.new",
                     "written first next to the rule, under a name with a dot (sudo skips it)")

        let parts = command.split(separator: "'", omittingEmptySubsequences: false)
        suite.expect(parts.count == 3, "one quoted word")
        if parts.count == 3 {
            let encoded = String(parts[1])
            suite.expect(encoded.allSatisfy { $0.isLetter || $0.isNumber || "+/=".contains($0) },
                         "base64 only inside the quotes")
            let decoded = Data(base64Encoded: encoded).map { String(decoding: $0, as: UTF8.self) }
            suite.expect(decoded == rule + "\n", "it writes exactly the rule, with its last newline")
        }
        suite.expect(command.contains("/usr/bin/base64 -D -o \(staged)"), "base64 writes the file itself")

        // The order: old names gone, staged file written, root's 0440, checked,
        // then moved over the real name; any failure removes both.
        let steps = ["rm -f \(legacy[0])", "rm -f \(staged)", "base64 -D -o \(staged)",
                     "chown root:wheel \(staged)", "chmod 0440 \(staged)",
                     "visudo -c -f \(staged)", "mv -f \(staged) \(rulePath)"]
        let positions = steps.map { command.range(of: $0)?.lowerBound }
        suite.expect(positions.allSatisfy { $0 != nil } && positions.compactMap { $0 } == positions.compactMap { $0 }.sorted(),
                     "remove old names, write, own, mode, check, then move into place")
        suite.expect(command.hasSuffix("|| { rm -f \(staged) \(rulePath); exit 1; }"),
                     "a failed step leaves neither file behind")
        suite.expect(SudoersSupport.installCommand(rule: rule, rulePath: rulePath, legacyPaths: []).hasPrefix(
                        "mkdir -p /etc/sudoers.d && rm -f \(staged) && "),
                     "no earlier names: no empty rm")
    }

    /// The write step, in a folder of this user: the pipe into base64 works
    /// where the old pipe into install did not.
    private static func writeStepRuns(_ suite: TestSuite) {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("sudoers-install-\(getpid())-\(UInt32.random(in: 0...UInt32.max))")
        defer { try? fm.removeItem(at: folder) }
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            suite.expect(false, "temporary folder")
            return
        }
        let target = folder.appendingPathComponent("ryzenstatus-clamshell").path
        let rule = SudoersSupport.clamshellRule(uid: getuid())
        let command = SudoersSupport.installCommand(rule: rule, rulePath: target, legacyPaths: [])
        let staged = SudoersSupport.stagedPath(for: target)

        // The old way, for the record: install refuses the pipe.
        let old = Shell.run("/bin/sh", ["-c", "/bin/echo '\(rule)' | /usr/bin/install -m 0440 /dev/stdin '\(folder.path)/old'"])
        suite.expect(old.status != 0 && !fm.fileExists(atPath: folder.path + "/old"),
                     "install from a pipe fails and writes nothing (status \(old.status))")

        guard let open = command.range(of: "(umask 077"), let close = command.range(of: ")", range: open.upperBound..<command.endIndex) else {
            suite.expect(false, "the write step is in the command")
            return
        }
        let step = String(command[open.lowerBound..<close.upperBound])
        let result = Shell.run("/bin/sh", ["-c", step])
        let written = try? String(contentsOfFile: staged, encoding: .utf8)
        suite.expect(result.status == 0 && written == rule + "\n", "the write step writes the rule (status \(result.status))")
        let mode = (try? fm.attributesOfItem(atPath: staged)[.posixPermissions] as? NSNumber)?.intValue
        suite.expect(mode == 0o600, "umask 077: nobody else can read it before chmod 0440 (mode \(String(mode ?? -1, radix: 8)))")
    }
}
