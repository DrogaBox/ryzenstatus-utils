// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum PackageManagerProvider: String, CaseIterable, Identifiable {
    case automatic, macPorts, homebrew
    var id: String { rawValue }

    func resolved(isIntel: Bool) -> PackageManagerProvider {
        self == .automatic ? (isIntel ? .macPorts : .homebrew) : self
    }

    static var current: PackageManagerProvider {
        let saved = PackageManagerProvider(rawValue: UserDefaults.standard.string(
            forKey: DefaultsKey.packageManagerProvider) ?? "automatic") ?? .automatic
#if arch(x86_64)
        return saved.resolved(isIntel: true)
#else
        return saved.resolved(isIntel: false)
#endif
    }
}

struct MacPortsPackage: Identifiable, Equatable {
    let name: String
    var installedVersion: String?
    var latestVersion: String?
    var active = false
    var description = ""
    var homepage: String?
    var id: String { name }
    var isOutdated: Bool { latestVersion != nil && installedVersion != nil }
}

enum MacPortsSupport {
    static let executable = "/opt/local/bin/port"
    static let outputLimit = 2 * 1024 * 1024
    static let timeout: TimeInterval = 30

    // Pseudo-ports are expressions, not individual packages. Never let an
    // untrusted name turn uninstall/upgrade into a catalog-wide operation.
    private static let selectors: Set<String> = [
        "all", "installed", "active", "inactive", "outdated", "requested",
        "unrequested", "leaves", "obsolete", "current", "dependentof", "rdependentof",
    ]

    static func isPackageName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 128,
              let first = name.utf8.first,
              (48...57).contains(first) || (65...90).contains(first) || (97...122).contains(first),
              !selectors.contains(name.lowercased()) else { return false }
        return name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95 || $0 == 43
        }
    }

    static func searchArguments(_ query: String) -> [String]? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPackageName(query) else { return nil }
        // -q suppresses version/description even with --line. Deliberately
        // omit it: verified with MacPorts 2.12.6 on the user's machine.
        return ["search", "--name", "--line", "--glob", "*\(query)*"]
    }

    static func installed(_ output: String) -> [MacPortsPackage] {
        var rows: [String: MacPortsPackage] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, isPackageName(String(fields[0])), fields[1].hasPrefix("@") else { continue }
            let version = String(fields[1].dropFirst())
            guard !version.isEmpty else { continue }
            let name = String(fields[0])
            let active = fields.dropFirst(2).contains("(active)")
            // Keep active version when several old inactive images coexist.
            if rows[name] == nil || active {
                rows[name] = MacPortsPackage(name: name, installedVersion: version, active: active)
            }
        }
        return rows.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func outdated(_ output: String) -> [String: String] {
        var versions: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 4, isPackageName(String(fields[0])), fields[2] == "<" else { continue }
            versions[String(fields[0])] = String(fields[3])
        }
        return versions
    }

    static func searchResults(_ output: String) -> [MacPortsPackage] {
        var rows: [String: MacPortsPackage] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, isPackageName(String(fields[0])) else { continue }
            let name = String(fields[0])
            rows[name] = MacPortsPackage(name: name, latestVersion: String(fields[1]),
                                         description: String(fields[3]))
        }
        return rows.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    enum Action: String, Identifiable {
        case install, upgrade, uninstall, upgradeAll, selfupdate
        var id: String { rawValue }

        func arguments(package: String? = nil) -> [String]? {
            switch self {
            case .upgradeAll: return ["upgrade", "outdated"]
            case .selfupdate: return ["selfupdate"]
            case .install, .upgrade, .uninstall:
                guard let package, MacPortsSupport.isPackageName(package) else { return nil }
                return [rawValue, package]
            }
        }
    }

    static func shellCommand(action: Action, package: String? = nil) -> String? {
        guard let arguments = action.arguments(package: package) else { return nil }
        // Shell tokens are escaped even though package names are validated.
        let quoted = ([executable] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return "sudo " + quoted.joined(separator: " ")
    }
}
