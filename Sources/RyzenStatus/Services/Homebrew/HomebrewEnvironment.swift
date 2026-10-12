// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

enum HomebrewEnvironment {
    // Access only from HomebrewManager's worker queue, never startup/main.
    static let forBrew = ProcessInfo.processInfo.environment.merging(
        exportsFromLoginShell(shellPath: currentShellPath)) { _, shell in shell }
    static var currentShellPath: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) { return shell }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    static let dumpMarker = "__RYZENSTATUS_ENV_DUMP__"
    static let resolvingVariable = "RYZENSTATUS_RESOLVING_ENVIRONMENT"
    static let loginShellTimeout: TimeInterval = 10
    static let passedThroughNames: Set<String> = [
        "http_proxy", "https_proxy", "ftp_proxy", "no_proxy", "all_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY", "NO_PROXY", "ALL_PROXY",
    ]

    static func isPassedThrough(_ name: String) -> Bool {
        passedThroughNames.contains(name) || name.hasPrefix("HOMEBREW_")
    }

    static func passthrough(_ environment: [String: String]) -> [String: String] {
        environment.filter { isPassedThrough($0.key) }
    }

    static func loginShellCommand(shellPath: String, interactive: Bool = true) -> HomebrewCommand {
        HomebrewCommand(executable: shellPath, arguments: (interactive ? ["-l", "-i"] : ["-l"])
            + ["-c", "printf %s \(dumpMarker); /usr/bin/env -0"])
    }

    static func loginShellEnvironment(base: [String: String]) -> [String: String] {
        base.merging([resolvingVariable: "1"]) { _, value in value }
    }

    /// The login shell's exports that brew keeps.
    static func exportsFromLoginShell(shellPath: String, timeout: TimeInterval = loginShellTimeout,
                                     baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        passthrough(loginShellExports(shellPath: shellPath, timeout: timeout, baseEnvironment: baseEnvironment))
    }

    /// Every export a Terminal window's shell has (interactive first, then the
    /// plain login run when a startup file ends the interactive one early).
    /// Unfiltered, for callers that need more than brew's own names, PATH
    /// included.
    static func loginShellExports(shellPath: String, timeout: TimeInterval = loginShellTimeout,
                                  baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        guard !shellPath.isEmpty else { return [:] }
        let environment = loginShellEnvironment(base: baseEnvironment)
        for interactive in [true, false] {
            let command = loginShellCommand(shellPath: shellPath, interactive: interactive)
            let result = BoundedProcessRunner.runInNewSession(command.executable, command.arguments,
                timeout: timeout, maxOutputBytes: 1024 * 1024, environment: environment)
            guard result.status == 0, !result.timedOut, result.output.count < 1024 * 1024,
                  result.output.range(of: Data(dumpMarker.utf8)) != nil else { continue }
            return parse(nullSeparated: result.output)
        }
        return [:]
    }

    static func parse(nullSeparated data: Data) -> [String: String] {
        // No marker = no successful shell dump. Never interpret a startup
        // greeting as exports, even when the greeting contains '='.
        guard let marker = data.range(of: Data(dumpMarker.utf8), options: .backwards) else { return [:] }
        var environment: [String: String] = [:]
        for entry in data[marker.upperBound...].split(separator: 0) {
            guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: entry[entry.startIndex..<separator], as: UTF8.self)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            environment[name] = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
        }
        return environment
    }
}
