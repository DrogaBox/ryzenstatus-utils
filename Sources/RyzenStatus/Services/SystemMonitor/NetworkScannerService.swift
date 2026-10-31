// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Active network interface adapter info.
struct NetworkAdapterInfo: Identifiable, Sendable, Codable, Equatable {
    var id: String { name }
    var name: String
    var ipAddress: String
    var isUp: Bool
    var rxBytesPerSec: Double
    var txBytesPerSec: Double

    init(name: String, ipAddress: String, isUp: Bool, rxBytesPerSec: Double = 0.0, txBytesPerSec: Double = 0.0) {
        self.name = name
        self.ipAddress = ipAddress
        self.isUp = isUp
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
    }
}

/// Service inspecting network adapters and socket activity.
final class NetworkScannerService: @unchecked Sendable {
    static let shared = NetworkScannerService()

    private struct InterfaceSample {
        var ibytes: UInt64
        var obytes: UInt64
        /// Monotonic seconds (system uptime): a wall-clock change must not
        /// stretch or shrink an interval.
        var time: TimeInterval
    }

    /// Bytes per second between two counter reads; 0 for no time elapsed
    /// or a counter that went backwards (an interface reset).
    static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    private let lock = NSLock()
    private var previousSamples: [String: InterfaceSample] = [:]

    private init() {}

    /// Discovers active network interfaces on macOS with accurate per-interface throughput.
    func activeAdapters() -> [NetworkAdapterInfo] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var ipMap: [String: (ip: String, isUp: Bool)] = [:]
        let now = ProcessInfo.processInfo.systemUptime
        // 64-bit counters; nil when the read failed, which then stores no
        // baseline rather than a zero one that would read as a burst later.
        let counters = NetworkSampler.interfaceByteCounters()

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let name = String(cString: current.pointee.ifa_name)

            if !isLoopback, let addr = current.pointee.ifa_addr {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            ipMap[name] = (ip: ip, isUp: isUp)
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        // Calculate deltas and assemble adapter infos
        var adapters: [NetworkAdapterInfo] = []
        lock.lock()
        for (name, ipInfo) in ipMap {
            var rxRate: Double = 0.0
            var txRate: Double = 0.0

            if let bytes = counters?[name] {
                if let prev = previousSamples[name] {
                    rxRate = Self.rate(previous: prev.ibytes, current: bytes.received, elapsed: now - prev.time)
                    txRate = Self.rate(previous: prev.obytes, current: bytes.sent, elapsed: now - prev.time)
                }
                previousSamples[name] = InterfaceSample(ibytes: bytes.received, obytes: bytes.sent, time: now)
            }

            adapters.append(NetworkAdapterInfo(
                name: name,
                ipAddress: ipInfo.ip,
                isUp: ipInfo.isUp,
                rxBytesPerSec: rxRate,
                txBytesPerSec: txRate
            ))
        }

        // Drop samples for interfaces that vanished (USB tethering,
        // dock adapters, VPN churn) so the dictionary cannot grow without bound
        // and a reused interface name never pairs with a stale baseline.
        if let counters {
            previousSamples = previousSamples.filter { counters[$0.key] != nil }
        }
        lock.unlock()

        return adapters.sorted { $0.name < $1.name }
    }
}
