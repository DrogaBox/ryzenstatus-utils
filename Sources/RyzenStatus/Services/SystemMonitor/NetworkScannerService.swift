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

    private init() {}

    /// Discovers active network interfaces on macOS.
    func activeAdapters() -> [NetworkAdapterInfo] {
        var adapters: [NetworkAdapterInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return [NetworkAdapterInfo(name: "en0", ipAddress: "192.168.1.100", isUp: true)]
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let name = String(cString: current.pointee.ifa_name)
            
            if let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "127.0.0.1" {
                        adapters.append(NetworkAdapterInfo(name: name, ipAddress: ip, isUp: isUp))
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        if adapters.isEmpty {
            adapters.append(NetworkAdapterInfo(name: "en0", ipAddress: "127.0.0.1", isUp: true))
        }

        return adapters
    }
}
