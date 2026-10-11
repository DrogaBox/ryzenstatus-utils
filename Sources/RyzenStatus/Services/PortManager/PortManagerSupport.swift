// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

struct PortManagerEntry: Identifiable, Equatable {
    let port: Int
    let protocolName: String
    let address: String
    let pid: Int32
    let processName: String
    let startedAt: UInt64?
    /// Local guard (stricter than upstream): set when the listener belongs to
    /// this app, to a process `KillProcessSupport` protects, or to an Apple
    /// daemon or agent. Rows marked here never offer Kill or Force Kill.
    var isProtected = false
    var id: String { "\(protocolName)-\(port)-\(pid)-\(address)" }
}

enum PortManagerSupport {
    /// Where Apple's own daemons and agents live. They hold sockets macOS
    /// needs (AirPlay receiver, Continuity, sharing), so Port Manager never
    /// offers to terminate them. User tools in `/usr/bin` stay killable.
    static let systemExecutableRoots = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]

    /// Whether a listener's process must never be terminated from Port
    /// Manager: everything `KillProcessSupport` protects (this app, launchd,
    /// WindowServer, loginwindow, the kernel), Apple system executables, and
    /// any process whose executable cannot be resolved, since an unknown
    /// owner cannot be told apart from a system one.
    static func isProtected(pid: Int32, name: String, path: String?) -> Bool {
        guard let path, !path.isEmpty else { return true }
        if KillProcessSupport.isProtected(pid: pid, name: name, path: path) { return true }
        return systemExecutableRoots.contains { path.hasPrefix($0) }
    }

    static func browserURL(for entry: PortManagerEntry) -> URL? {
        guard entry.protocolName == "TCP", (1...65535).contains(entry.port),
              let separator = entry.address.lastIndex(of: ":") else { return nil }
        let host = String(entry.address[..<separator])
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        // Wildcard binds are not destinations. Preserve the address family
        // when it is known, and a specific bind when localhost cannot reach it.
        switch host {
        case "*": components.host = "localhost"
        case "0.0.0.0": components.host = "127.0.0.1"
        case "[::]", "::": components.host = "[::1]"
        default: components.host = host
        }
        components.port = entry.port
        return components.url
    }

    /// Whether an lsof endpoint such as `*:3000` or `127.0.0.1:3000` is bound
    /// to every interface rather than one specific address. A wildcard bind
    /// accepts connections from other machines on the network unless a
    /// firewall stops them, so it is worth pointing out.
    static func listensOnAllInterfaces(_ endpoint: String) -> Bool {
        guard let separator = endpoint.lastIndex(of: ":") else { return false }
        var host = endpoint[..<separator]
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = host.dropFirst().dropLast()
        }
        return host == "*" || host == "0.0.0.0" || host == "::"
    }

    static func parseLsof(_ text: String) -> [PortManagerEntry] {
        var name = "", pid: Int32 = 0, address = "", port = 0, proto = "TCP"
        var rows: [PortManagerEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").map(String.init) {
            guard let type = line.first else { continue }
            let value = String(line.dropFirst())
            switch type {
            case "p":
                pid = Int32(value) ?? 0; port = 0; address = ""
            case "c": name = value
            case "P": proto = value
            case "n":
                address = value
                guard let last = value.split(separator: ":").last, let parsed = Int(last) else {
                    port = 0
                    continue
                }
                port = parsed
                if pid > 0 && port > 0 {
                    let key = "\(proto)|\(port)|\(address)|\(pid)"
                    if seen.insert(key).inserted {
                        rows.append(.init(port: port, protocolName: proto, address: address,
                                          pid: pid, processName: name, startedAt: nil))
                    }
                }
            case "T": continue
            default: continue
            }
        }
        return rows.sorted { $0.port == $1.port ? $0.processName < $1.processName : $0.port < $1.port }
    }
}
