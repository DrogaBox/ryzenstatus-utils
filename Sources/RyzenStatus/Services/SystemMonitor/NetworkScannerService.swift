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
        var time: Date
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
        var byteMap: [String: (ibytes: UInt64, obytes: UInt64, isUp: Bool)] = [:]
        let now = Date()

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
                } else if family == UInt8(AF_LINK), let data = current.pointee.ifa_data {
                    let ifd = data.assumingMemoryBound(to: if_data.self)
                    let ibytes = UInt64(ifd.pointee.ifi_ibytes)
                    let obytes = UInt64(ifd.pointee.ifi_obytes)
                    byteMap[name] = (ibytes: ibytes, obytes: obytes, isUp: isUp)
                }
            }
            ptr = current.pointee.ifa_next
        }

        // Calculate deltas and assemble adapter infos
        var adapters: [NetworkAdapterInfo] = []
        lock.lock()
        for (name, ipInfo) in ipMap {
            let (ibytes, obytes, isUp) = byteMap[name] ?? (0, 0, ipInfo.isUp)
            var rxRate: Double = 0.0
            var txRate: Double = 0.0

            if let prev = previousSamples[name] {
                let dt = max(now.timeIntervalSince(prev.time), 0.001)
                if ibytes >= prev.ibytes {
                    rxRate = Double(ibytes - prev.ibytes) / dt
                }
                if obytes >= prev.obytes {
                    txRate = Double(obytes - prev.obytes) / dt
                }
            }
            previousSamples[name] = InterfaceSample(ibytes: ibytes, obytes: obytes, time: now)

            adapters.append(NetworkAdapterInfo(
                name: name,
                ipAddress: ipInfo.ip,
                isUp: isUp,
                rxBytesPerSec: rxRate,
                txBytesPerSec: txRate
            ))
        }
        lock.unlock()

        return adapters.sorted { $0.name < $1.name }
    }
}
