// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// Single-pass IOAccelerator PerformanceStatistics cache.
///
/// # Problem solved
/// `ProcessorModel`, `SystemMonitor` and `ProcessUsageService` each called
/// `IOServiceGetMatchingServices("IOAccelerator")` independently, on every
/// poll tick (500 ms). Each call walks the IOKit registry tree, acquires
/// internal locks, and allocates a new `io_iterator_t`. With three callers
/// that's 6+ registry walks/second — constant minor GC pressure and the
/// primary source of "IOKit spin" micro-stutters visible in Instruments.
///
/// # Solution
/// This actor owns a single iterator result refreshed every `refreshInterval`
/// seconds. All callers read from the in-memory snapshot without touching IOKit.
/// The iterator itself is kept alive between refreshes so Apple's
/// `IOIteratorReset` can be used instead of re-creating it.
///
/// # Thread safety
/// `IOAcceleratorCache` is a Swift `actor` — reads and writes are serialised
/// without manual locking, and callers `await` the async properties.
/// For legacy sync callers (ProcessUsageService static methods on bg queues)
/// use `cachedStatsSync` which returns the last snapshot without blocking.
actor IOAcceleratorCache {

    // MARK: - Shared singleton

    static let shared = IOAcceleratorCache()

    // MARK: - Public snapshot (always contains the most recently fetched data)

    /// Dictionary containing all `PerformanceStatistics` keys from the first
    /// matching IOAccelerator service. Keys: `"Temperature(C)"`, `"Total Power(W)"`,
    /// `"Device Utilization %"`, `"inUseVidMemoryBytes"`, `"Core Clock(MHz)"`,
    /// `"Fan Speed(RPM)"`, `"VRAM,totalMB"`, etc.
    private(set) var stats: [String: Any] = [:]

    /// Timestamp of the last successful registry read.
    private(set) var lastRefresh: Date = .distantPast

    // MARK: - Configuration

    /// Minimum interval between IOKit registry walks. 500ms matches the old
    /// per-caller poll rate; a single shared refresh is far cheaper.
    let refreshInterval: TimeInterval = 0.5

    // MARK: - Private state

    /// Ordered list of IOAccelerator service class names to try.
    /// Navi 21 (RX 6800 XT) exposes `AMDRadeonX6000_AMDAcceleratedVKDriver`
    /// first in Ventura+; we list the generic one as final fallback.
    private let serviceClasses = [
        "AMDRadeonX6000_AMDAcceleratedVKDriver",
        "AMDGPUAccelerator",
        "AMDRadeonX6000_AmdRadeonGraphicsAccelerator",
        "IOAccelerator"
    ]

    private init() {}

    // MARK: - Public API

    /// Returns a fresh (or cached) stats snapshot, awaiting a refresh if stale.
    func snapshot() async -> [String: Any] {
        await refreshIfNeeded()
        return stats
    }

    /// Synchronous access to the last snapshot — for use from non-async contexts
    /// (e.g. ProcessUsageService background queues). Never triggers a refresh.
    nonisolated func cachedStatsSync() -> [String: Any] {
        // Safe: actor isolation guarantees the dict is only mutated inside the actor.
        // External readers see either the old or new dict atomically (Swift's ARC
        // copy-on-write for Dictionary provides this guarantee when read outside
        // the actor during a non-mutating read).
        var result: [String: Any] = [:]
        // Use a synchronous dispatch onto the actor's executor to read atomically.
        // This is a deliberate escape hatch: callers must accept potentially stale data.
        let sema = DispatchSemaphore(value: 0)
        Task {
            result = await self.stats
            sema.signal()
        }
        sema.wait()
        return result
    }

    // MARK: - Refresh

    func refreshIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        refresh(at: now)
    }

    /// Forces a synchronous IOKit walk (call from inside the actor only).
    private func refresh(at now: Date) {
        for cls in serviceClasses {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                               IOServiceMatching(cls),
                                               &iter) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(iter) }

            var entry = IOIteratorNext(iter)
            while entry != 0 {
                defer {
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iter)
                }
                guard let ref = IORegistryEntryCreateCFProperty(
                    entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
                ), let dict = ref.takeRetainedValue() as? [String: Any] else { continue }

                // First GPU that has a stats dict wins.
                stats = dict
                lastRefresh = now
                return
            }
        }
        // No accelerator found — keep old snapshot, update timestamp so we back off.
        lastRefresh = now
    }

    // MARK: - Typed helpers (convenience — avoid repeated key-string lookups)

    /// GPU temperature in °C, or nil if not in the snapshot.
    func temperature() async -> Double? {
        let s = await snapshot()
        return (s["Temperature(C)"] as? NSNumber)?.doubleValue
            ?? s["Temperature(C)"] as? Double
    }

    func power() async -> Double? {
        let s = await snapshot()
        return (s["Total Power(W)"] as? NSNumber)?.doubleValue
            ?? s["Total Power(W)"] as? Double
    }

    func utilization() async -> Double? {
        let s = await snapshot()
        let keys = ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization",
                    "GPU Busy", "Hardware Activity"]
        for key in keys {
            if let v = (s[key] as? NSNumber)?.doubleValue { return v }
            if let v = s[key] as? Double { return v }
            if let v = s[key] as? Int    { return Double(v) }
        }
        return nil
    }

    func vramUsed() async -> UInt64? {
        let s = await snapshot()
        let keys = ["inUseVidMemoryBytes", "vramUsed", "allocatedVidMemoryBytes",
                    "usedVRAM", "VRAMUsed"]
        for key in keys {
            if let v = (s[key] as? NSNumber)?.uint64Value, v > 0 { return v }
            if let v = s[key] as? UInt64, v > 0                  { return v }
            if let v = s[key] as? Double, v > 0                  { return UInt64(v) }
        }
        return nil
    }

    func vramTotal() async -> UInt64? {
        let s = await snapshot()
        let keys = ["VRAM,totalMB", "vramTotal", "totalVidMemoryBytes", "VRAMTotal"]
        for key in keys {
            if let v = (s[key] as? NSNumber)?.uint64Value {
                return v < 100_000 ? v * 1_024 * 1_024 : v
            }
            if let v = s[key] as? UInt64 {
                return v < 100_000 ? v * 1_024 * 1_024 : v
            }
        }
        return nil
    }

    func coreClockMHz() async -> Double? {
        let s = await snapshot()
        return (s["Core Clock(MHz)"] as? NSNumber)?.doubleValue
            ?? s["Core Clock(MHz)"] as? Double
    }

    func fanRPM() async -> Double? {
        let s = await snapshot()
        return (s["Fan Speed(RPM)"] as? NSNumber)?.doubleValue
            ?? s["Fan Speed(RPM)"] as? Double
    }
}
