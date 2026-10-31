// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation
import SystemConfiguration

/// One network reading: instantaneous speed plus session totals.
struct NetworkReading {
    var downBytesPerSec: Double?   // nil until there is a previous sample
    var upBytesPerSec: Double?
    var totalDown: UInt64          // accumulated since the app started watching
    var totalUp: UInt64
}

/// Samples cumulative interface byte counters and derives speed + session totals.
/// State (previous counters, accumulated totals) is only touched from the
/// monitor's serial queue, so no extra synchronization is needed.
final class NetworkSampler {
    private var previous: (counters: NetworkCounters, time: TimeInterval)?
    private var totalDown: UInt64 = 0
    private var totalUp: UInt64 = 0
    private var counterFallback = NetworkCounterFallback()
    private var processDeltaTracker = NetworkProcessDeltaTracker(maxGap: 30)
    private let counterReader: () -> NetworkCounters?
    private let processReader: () -> [NetworkProcessSample]?

    /// After a gap longer than this (sampling was paused), the previous reading
    /// is treated as a fresh baseline instead of producing a misleading spike.
    private static let maxGap: TimeInterval = 10

    init(counterReader: @escaping () -> NetworkCounters? = NetworkSampler.readCounters,
         processReader: @escaping () -> [NetworkProcessSample]? = {
             NetworkProcessSupport.currentExternalActivitySamples()
         }) {
        self.counterReader = counterReader
        self.processReader = processReader
    }

    func sample(now: TimeInterval) -> NetworkReading {
        guard let counters = counterReader() else {
            return NetworkReading(downBytesPerSec: nil, upBytesPerSec: nil,
                                  totalDown: totalDown, totalUp: totalUp)
        }
        defer { previous = (counters, now) }

        guard let prev = previous, now > prev.time, now - prev.time <= Self.maxGap,
              prev.counters.interfaces == counters.interfaces else {
            counterFallback.reset()
            processDeltaTracker.reset()
            return NetworkReading(downBytesPerSec: nil, upBytesPerSec: nil,
                                  totalDown: totalDown, totalUp: totalUp)
        }

        let elapsed = now - prev.time
        let interfaceSpeed = MetricFormat.netSpeed(previous: prev.counters,
                                                   current: counters,
                                                   elapsed: elapsed)
        let fallback = counterFallback.observe(previous: prev.counters, current: counters)
        var processDown: Double?
        if fallback.sampleProcesses,
           let samples = processReader() {
            let hadBaseline = processDeltaTracker.hasBaseline(now: now)
            let rates = processDeltaTracker.rates(from: samples, now: now)
            if fallback.useProcessDownload, hadBaseline {
                processDown = rates.reduce(0) { $0 + $1.bytesIn }
            }
        } else if !fallback.useProcessDownload {
            processDeltaTracker.reset()
        }

        if let processDown {
            accumulate(rate: processDown, elapsed: elapsed, into: &totalDown)
        } else if counters.received >= prev.counters.received {
            totalDown += counters.received - prev.counters.received
        }
        if counters.sent >= prev.counters.sent {
            totalUp += counters.sent - prev.counters.sent
        }
        return NetworkReading(downBytesPerSec: processDown ?? interfaceSpeed.down,
                              upBytesPerSec: interfaceSpeed.up,
                              totalDown: totalDown, totalUp: totalUp)
    }

    private func accumulate(rate: Double, elapsed: TimeInterval, into total: inout UInt64) {
        let bytes = rate * elapsed
        guard bytes.isFinite, bytes > 0 else { return }
        guard bytes < Double(UInt64.max) else {
            total = UInt64.max
            return
        }
        let amount = UInt64(bytes.rounded(.down))
        let addition = total.addingReportingOverflow(amount)
        total = addition.overflow ? UInt64.max : addition.partialValue
    }

    /// Sums received/sent bytes across physical interfaces using the per-interface
    /// MIB, which returns the 64-bit `if_data64` counters on Sequoia.
    /// Falls back to the routing socket (`NET_RT_IFLIST2`), whose `if_data64`
    /// counters are 64-bit too; nil when neither answers, so a failed read
    /// never looks like a sudden drop to zero.
    static func readCounters() -> NetworkCounters? {
        readCountersFromInterfaceMIB() ?? readCountersFromRouteList()
    }

    private static func readCountersFromInterfaceMIB() -> NetworkCounters? {
        var countMib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC,
                                 IFMIB_SYSTEM, IFMIB_IFCOUNT]
        var interfaceCount = 0
        var countLength = MemoryLayout<Int32>.size
        guard sysctl(&countMib, 5, &interfaceCount, &countLength, nil, 0) == 0,
              interfaceCount > 0 else {
            return nil
        }

        var result = NetworkCounters()
        var foundInterface = false
        for index in 1...interfaceCount {
            var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            guard if_indextoname(UInt32(index), &nameBuffer) != nil else { continue }
            let name = String(cString: nameBuffer)
            guard MetricFormat.includeNetworkInterface(name) else { continue }

            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC,
                                IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
            var data = ifmibdata()
            var length = MemoryLayout<ifmibdata>.size
            guard sysctl(&mib, 6, &data, &length, nil, 0) == 0 else { continue }

            result.received += data.ifmd_data.ifi_ibytes
            result.sent += data.ifmd_data.ifi_obytes
            foundInterface = true
        }
        return foundInterface ? result : nil
    }

    private static func readCountersFromRouteList() -> NetworkCounters? {
        guard let perInterface = interfaceByteCounters() else { return nil }
        var result = NetworkCounters()
        result.interfaces = MetricFormat.countedNetworkInterfaces(Array(perInterface.keys),
                                                                  primaries: primaryInterfaces())
        for name in result.interfaces {
            guard let counters = perInterface[name] else { continue }
            result.received += counters.received
            result.sent += counters.sent
        }
        return result
    }

    /// The 64-bit byte counters of every interface from the routing socket
    /// (`NET_RT_IFLIST2`), unfiltered. Nil when `sysctl` fails, so a failed
    /// read is never taken for an empty list or a drop to zero. The adapter
    /// list reads these too: `if_data`'s 32-bit counters wrap every 4 GiB.
    static func interfaceByteCounters() -> [String: (received: UInt64, sent: UInt64)]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var perInterface: [String: (received: UInt64, sent: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                // BUG-04 fix: NET_RT_IFLIST2 buffer has no alignment guarantee.
                // assumingMemoryBound(to:) triggers EXC_BAD_ACCESS in optimized builds.
                // loadUnaligned performs a byte-copy and is unconditionally safe.
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        perInterface[name] = (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return perInterface
    }

    private static let store = SCDynamicStoreCreate(nil, "com.ryzenstatus.utils.network-sampler" as CFString, nil, nil)

    /// The interfaces the system routes IPv4 and IPv6 through.
    private static func primaryInterfaces() -> [String] {
        guard let store else { return [] }
        return ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"].compactMap { key in
            (SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        }
    }
}
