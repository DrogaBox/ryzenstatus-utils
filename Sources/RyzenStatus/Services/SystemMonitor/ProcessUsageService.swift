// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import IOKit

/// One row of the per-app breakdown shown when a System stat is expanded.
struct ProcessUsage: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// CPU/GPU: percentage (0–100+). Memory: bytes. Network: total bytes/s.
    let value: Double
    let networkDownBytesPerSec: Double?
    let networkUpBytesPerSec: Double?

    var id: pid_t { pid }

    init(pid: pid_t,
         name: String,
         value: Double,
         networkDownBytesPerSec: Double? = nil,
         networkUpBytesPerSec: Double? = nil) {
        self.pid = pid
        self.name = name
        self.value = value
        self.networkDownBytesPerSec = networkDownBytesPerSec
        self.networkUpBytesPerSec = networkUpBytesPerSec
    }
}

/// Answers "which apps are eating this resource?" for the panel's System
/// section. CPU and memory come from `ps`; GPU comes from the accelerator's
/// per-process `accumulatedGPUTime` counters, sampled as deltas between calls.
/// Helper processes are consolidated under the app responsible for them, so
/// one app shows up once instead of as a pile of helper rows.
final class ProcessUsageService {
    static let shared = ProcessUsageService()

    private struct CachedRows {
        var rows: [ProcessUsage]
        var updatedAt: TimeInterval
    }

    private let cacheLock = NSLock()
    private var configuredCacheFreshSeconds: TimeInterval {
        let val = UserDefaults.standard.double(forKey: DefaultsKey.processListRefreshInterval)
        return val > 0 ? val : 1.0
    }
    private var cacheFreshSeconds: TimeInterval { configuredCacheFreshSeconds }
    private var memoryCacheFreshSeconds: TimeInterval { configuredCacheFreshSeconds * 1.2 }
    private var staleCacheSeconds: TimeInterval { configuredCacheFreshSeconds * 2.0 }
    private let minimumGPUSampleInterval: TimeInterval = 0.8
    private let maximumCachedRows = 60
    private var cpuCache: CachedRows?
    private var memoryCache: CachedRows?
    private var gpuCache: CachedRows?
    private var energyCache: CachedRows?
    private var networkCache: CachedRows?
    private var cpuLoading = false
    private var memoryLoading = false
    private var gpuLoading = false
    private var energyLoading = false
    private var networkLoading = false
    private var networkLeaseExpiresAt: TimeInterval = 0
    private var networkDeltaTracker = NetworkProcessDeltaTracker()
    private let networkSamplerLock = NSLock()
    private var networkSamplerRunning = false
    private var networkSamplerGeneration = 0

    private init() {}

    func cachedTop(_ kind: BreakdownKind, limit: Int, maxAge: TimeInterval = 18) -> [ProcessUsage]? {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let cache: CachedRows?
        switch kind {
        case .cpu: cache = cpuCache
        case .gpu: cache = gpuCache
        case .memory: cache = memoryCache
        case .energy: cache = energyCache
        case .network: cache = networkCache
        }
        return limitedRows(cache, limit: limit, now: now, maxAge: maxAge)
    }

    func top(_ kind: BreakdownKind, limit: Int) -> [ProcessUsage] {
        switch kind {
        case .cpu: return topCPU(limit: limit)
        case .gpu: return topGPU(limit: limit)
        case .memory: return topMemory(limit: limit)
        case .energy: return topEnergy(limit: limit)
        case .network: return topNetwork(limit: limit)
        }
    }

    func clearCachedRows() {
        cacheLock.lock()
        cpuCache = nil
        memoryCache = nil
        gpuCache = nil
        energyCache = nil
        networkCache = nil
        cacheLock.unlock()
    }

    func startNetworkMonitoring() {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        networkLeaseExpiresAt = NetworkProcessSamplingPolicy.renewedLease(now: now)
        if networkCache?.rows.isEmpty ?? true {
            networkLoading = true
        }
        cacheLock.unlock()
        startNetworkSampler()
    }

    func stopNetworkMonitoring(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if force {
            networkLeaseExpiresAt = 0
            networkLoading = false
            networkDeltaTracker.reset()
        } else {
            networkLeaseExpiresAt = NetworkProcessSamplingPolicy.shortenedLease(
                currentExpiresAt: networkLeaseExpiresAt,
                now: now
            )
        }
        cacheLock.unlock()
        if force {
            stopNetworkSampler()
        }
    }

    var networkMonitoringIsWarmingUp: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let hasCachedRows = networkCache?.rows.isEmpty == false
        return networkMonitoringActive(now: now) && networkLoading && !hasCachedRows
    }

    func canActivate(_ row: ProcessUsage) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: row.pid),
              app.activationPolicy == .regular,
              !app.isTerminated
        else { return false }
        return true
    }

    func activate(_ row: ProcessUsage) {
        guard canActivate(row),
              let app = NSRunningApplication(processIdentifier: row.pid)
        else { return }
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            app.activate(options: [])
        }
    }

    // MARK: - Energy

    /// macOS does not expose Activity Monitor's Energy Impact as a `ps` column.
    /// For the live battery list, combine the current CPU and GPU app shares and
    /// keep only rows that are meaningfully active right now.
    func topEnergy(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if let cached = limitedRows(energyCache, limit: limit, now: now, maxAge: cacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if energyLoading {
            let cached = limitedRows(energyCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        energyLoading = true
        cacheLock.unlock()

        let sampleLimit = max(limit * 3, 12)
        let cpuRows = topCPU(limit: sampleLimit)
        let gpuRows = topGPU(limit: sampleLimit)
        var scores: [pid_t: (name: String, value: Double)] = [:]

        for row in cpuRows + gpuRows {
            var score = scores[row.pid] ?? (row.name, 0)
            score.value += row.value
            if score.name.hasPrefix("pid ") { score.name = row.name }
            scores[row.pid] = score
        }

        let rows = scores
            .filter { _, score in score.value >= 2 }
            .sorted { $0.value.value > $1.value.value }
            .map { pid, score in
                ProcessUsage(pid: pid, name: score.name, value: score.value)
            }
        cacheLock.lock()
        energyCache = cachedRows(from: rows)
        energyLoading = false
        cacheLock.unlock()
        return Array(rows.prefix(limit))
    }

    // MARK: - Network

    func topNetwork(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let monitoring = networkMonitoringActive(now: now)
        if monitoring {
            networkLeaseExpiresAt = NetworkProcessSamplingPolicy.renewedLease(now: now)
        }
        if let cached = limitedRows(networkCache, limit: limit, now: now, maxAge: monitoring ? staleCacheSeconds : cacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if monitoring {
            networkLoading = true
            cacheLock.unlock()
            startNetworkSampler()
            return []
        }
        cacheLock.unlock()
        return []
    }

    private func startNetworkSampler() {
        networkSamplerLock.lock()
        guard !networkSamplerRunning else {
            networkSamplerLock.unlock()
            return
        }
        networkSamplerRunning = true
        networkSamplerGeneration &+= 1
        let generation = networkSamplerGeneration
        networkSamplerLock.unlock()
        scheduleNetworkSample(generation: generation, delay: 0)
    }

    private func stopNetworkSampler() {
        networkSamplerLock.lock()
        networkSamplerRunning = false
        networkSamplerGeneration &+= 1
        networkSamplerLock.unlock()
    }

    private func scheduleNetworkSample(generation: Int, delay: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.networkSamplerIsCurrent(generation) else { return }
            guard self.networkLeaseIsCurrent() else {
                self.stopNetworkSampler()
                return
            }
            let samples = NetworkProcessSupport.currentActivitySamples()
            guard self.networkSamplerIsCurrent(generation) else { return }
            guard self.networkLeaseIsCurrent() else {
                self.stopNetworkSampler()
                return
            }
            self.publishNetworkSamples(samples)
            guard self.networkLeaseIsCurrent() else {
                self.stopNetworkSampler()
                return
            }
            self.scheduleNetworkSample(generation: generation,
                                       delay: NetworkProcessSamplingPolicy.sampleInterval)
        }
    }

    private func networkSamplerIsCurrent(_ generation: Int) -> Bool {
        networkSamplerLock.lock()
        let current = networkSamplerRunning && networkSamplerGeneration == generation
        networkSamplerLock.unlock()
        return current
    }

    private func networkLeaseIsCurrent() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let current = networkMonitoringActive(now: now)
        if !current {
            networkLoading = false
            networkDeltaTracker.reset()
        }
        cacheLock.unlock()
        return current
    }

    private func publishNetworkSamples(_ samples: [NetworkProcessSample]) {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        // A priming sample only records the baseline and yields no rates; keep
        // the warming-up state until a real delta exists, or the UI would show
        // "no activity" for the first ~5 s even during a heavy download.
        let hadBaseline = networkDeltaTracker.hasBaseline(now: now)
        let rateSamples = networkDeltaTracker.rates(from: samples, now: now)
        if hadBaseline {
            networkLoading = false
        }
        cacheLock.unlock()

        let rows = groupedNetworkByApp(rateSamples)

        cacheLock.lock()
        if rows.isEmpty,
           let cache = networkCache,
           !cache.rows.isEmpty,
           now - cache.updatedAt <= cacheFreshSeconds {
            cacheLock.unlock()
            return
        }
        networkCache = cachedRows(from: rows)
        cacheLock.unlock()
    }

    private func networkMonitoringActive(now: TimeInterval) -> Bool {
        NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: networkLeaseExpiresAt,
                                                   now: now)
    }

    // MARK: - CPU

    func topCPU(limit: Int = 15) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(cpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
        let isFresh = limitedRows(cpuCache, limit: limit, now: now, maxAge: cacheFreshSeconds) != nil
        if isFresh || cpuLoading {
            cacheLock.unlock()
            return cached
        }
        cpuLoading = true
        cacheLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"])
            let rows = result.status == 0
                ? self.groupedByApp(self.parsePS(result.output, maxRows: self.rawProcessRowLimit(for: limit)) { Double($0) ?? 0 })
                : nil
            _ = self.finishCPU(rows, limit: limit)
        }
        return cached
    }

    // MARK: - Memory

    func topMemory(limit: Int = 15) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(memoryCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
        let isFresh = limitedRows(memoryCache, limit: limit, now: now, maxAge: memoryCacheFreshSeconds) != nil
        if isFresh || memoryLoading {
            cacheLock.unlock()
            return cached
        }
        memoryLoading = true
        cacheLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = Shell.run("/bin/ps", ["-Aceo", "pid,rss,comm", "-m"])
            let rows = result.status == 0
                ? self.groupedByApp(self.parsePS(result.output, maxRows: self.rawProcessRowLimit(for: limit)) { (Double($0) ?? 0) * 1024 }
                    .map { row in
                        guard let footprint = Self.physicalFootprint(of: row.pid) else { return row }
                        return ProcessUsage(pid: row.pid, name: row.name, value: footprint)
                    })
                : nil
            _ = self.finishMemory(rows, limit: limit)
        }
        return cached
    }

    /// The kernel's physical memory footprint of a process, readable for any
    /// process without special privileges. Returns nil when the process died
    /// between the ps snapshot and this call.
    private static func physicalFootprint(of pid: pid_t) -> Double? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return Double(info.ri_phys_footprint)
    }

    /// Lines look like "  437  12.5 WindowServer" (value column varies).
    private func parsePS(_ output: String, maxRows: Int, transform: (String) -> Double) -> [ProcessUsage] {
        var rows: [ProcessUsage] = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard columns.count == 3, let pid = pid_t(columns[0]) else { continue }
            let value = transform(String(columns[1]))
            guard value > 0 else { continue }
            rows.append(ProcessUsage(pid: pid,
                                     name: String(columns[2]).trimmingCharacters(in: .whitespaces),
                                     value: value))
            if rows.count >= maxRows { break }
        }
        return rows
    }

    private func rawProcessRowLimit(for limit: Int) -> Int {
        max(limit * 10, 120)
    }

    // MARK: - Consolidation

    /// Sums per-process values under each process's responsible app and keeps
    /// the heaviest `limit` rows. The row's pid becomes the responsible pid,
    /// so the app's proper name and icon are shown.
    private func groupedByApp(_ rows: [ProcessUsage]) -> [ProcessUsage] {
        var totals: [pid_t: Double] = [:]
        var fallbackNames: [pid_t: String] = [:]

        for row in rows {
            if kill(row.pid, 0) != 0 && errno == ESRCH { continue }
            let owner = ResponsibleProcess.owner(of: row.pid)
            totals[owner, default: 0] += row.value
            if fallbackNames[owner] == nil {
                fallbackNames[owner] = row.name
            }
        }

        return totals
            .sorted { $0.value > $1.value }
            .map { owner, value in
                ProcessUsage(pid: owner,
                             name: ResponsibleProcess.displayName(pid: owner,
                                                                  fallback: fallbackNames[owner] ?? "pid \(owner)"),
                             value: value)
            }
    }

    private func groupedNetworkByApp(_ samples: [NetworkProcessSample]) -> [ProcessUsage] {
        var totals: [pid_t: (down: Double, up: Double)] = [:]
        var fallbackNames: [pid_t: String] = [:]

        for sample in samples {
            let owner = ResponsibleProcess.owner(of: sample.pid)
            var total = totals[owner] ?? (0, 0)
            total.down += sample.bytesIn
            total.up += sample.bytesOut
            totals[owner] = total
            if fallbackNames[owner] == nil {
                fallbackNames[owner] = sample.name
            }
        }

        return totals
            .map { owner, value in
                ProcessUsage(pid: owner,
                             name: ResponsibleProcess.displayName(pid: owner,
                                                                  fallback: fallbackNames[owner] ?? "pid \(owner)"),
                             value: value.down + value.up,
                             networkDownBytesPerSec: value.down,
                             networkUpBytesPerSec: value.up)
            }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    // MARK: - GPU

    private var previousGPUSample: (time: TimeInterval, perPid: [pid_t: Double])?
    private let gpuSampleLock = NSLock()
    
    /// Global GPU utilization % read from IOAccelerator PerformanceStatistics.
    private var totalGPUUtilPct: Double = 0
    /// WindowServer PID, resolved once and cached.
    private static var _windowServerPID: pid_t?
    private static var windowServerPID: pid_t? {
        if let cached = _windowServerPID { return cached }
        // Find by bundle identifier — WindowServer is always com.apple.windowserver
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.apple.windowserver" {
                _windowServerPID = app.processIdentifier
                return _windowServerPID
            }
        }
        return nil
    }

    /// Per-process GPU share since the previous call. The first call after a
    /// while only primes the baseline and returns [] — callers show a
    /// "measuring" placeholder until the next tick.
    func topGPU(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(gpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
        let isFresh = limitedRows(gpuCache, limit: limit, now: now, maxAge: cacheFreshSeconds) != nil
        if isFresh || gpuLoading {
            cacheLock.unlock()
            return cached
        }
        gpuLoading = true
        cacheLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let current = Self.gpuTimePerPid()
            self.gpuSampleLock.lock()
            let previous = self.previousGPUSample
            self.previousGPUSample = (now, Dictionary(uniqueKeysWithValues: current.map { ($0.pid, $0.time) }))
            self.gpuSampleLock.unlock()

            guard let previous, now > previous.time,
                  now - previous.time < 30
            else {
                _ = self.finishGPU(nil, limit: limit)
                return
            }

            let elapsedNs = (now - previous.time) * 1_000_000_000
            var rows: [ProcessUsage] = []
            var computePercentSum: Double = 0
            for (pid, name, total) in current {
                guard let before = previous.perPid[pid], total > before else { continue }
                let percent = (total - before) / elapsedNs * 100
                guard percent >= 0.05 else { continue }
                let displayName = ResponsibleProcess.displayName(pid: pid, fallback: name)
                rows.append(ProcessUsage(pid: pid, name: displayName, value: min(percent, 100)))
                computePercentSum += percent
            }
            
            let totalGPUUtil = Self.readTotalGPUUtilization()
            self.totalGPUUtilPct = totalGPUUtil
            if let wsPID = Self.windowServerPID,
               totalGPUUtil > computePercentSum + 1,
               totalGPUUtil > 2 {
                let wsShare = max(0, totalGPUUtil - computePercentSum - 1)
                let wsName = ResponsibleProcess.displayName(pid: wsPID, fallback: "WindowServer")
                rows.append(ProcessUsage(pid: wsPID, name: wsName, value: min(wsShare, 100)))
            }
            
            _ = self.finishGPU(self.groupedByApp(rows), limit: limit)
        }
        return cached
    }
    
    /// Reads the global GPU utilization (%) from IOAccelerator PerformanceStatistics.
    /// Reads the global GPU utilization (%) from IOAccelerator PerformanceStatistics.
    private static func readTotalGPUUtilization() -> Double {
        let serviceClasses = ["IOAccelerator", "AMDRadeonX6000_AMDAcceleratedVKDriver", "AMDGPUAccelerator"]
        let keys = ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization", "GPU Busy", "Hardware Activity"]
        
        for cls in serviceClasses {
            var iterator = io_iterator_t()
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iterator) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(iterator) }
            
            while true {
                let entry = IOIteratorNext(iterator)
                if entry == 0 { break }
                defer { IOObjectRelease(entry) }
                
                if let ref = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                   let stats = ref.takeRetainedValue() as? [String: Any] {
                    for key in keys {
                        if let util = stats[key] as? NSNumber {
                            return util.doubleValue
                        } else if let util = stats[key] as? Double {
                            return util
                        } else if let util = stats[key] as? Int {
                            return Double(util)
                        } else if let util = stats[key] as? UInt64 {
                            return Double(util)
                        }
                    }
                }
            }
        }
        return 0
    }

    private func finishCPU(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cpuLoading = false
        if let rows {
            cpuCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(cpuCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func finishMemory(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        memoryLoading = false
        if let rows {
            memoryCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(memoryCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func finishGPU(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        gpuLoading = false
        if let rows {
            gpuCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(gpuCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func cachedRows(from rows: [ProcessUsage]) -> CachedRows {
        CachedRows(rows: Array(rows.prefix(maximumCachedRows)),
                   updatedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func limitedRows(_ cache: CachedRows?, limit: Int, now: TimeInterval, maxAge: TimeInterval) -> [ProcessUsage]? {
        guard let cache, now - cache.updatedAt <= maxAge else { return nil }
        if cache.rows.count < limit {
            // Cache has fewer rows than requested limit — force refresh for larger limit
            return nil
        }
        return Array(cache.rows.prefix(limit))
    }

    /// Walks the accelerator's user clients and sums `accumulatedGPUTime`
    /// (nanoseconds of GPU work since the context was created) per process.
    /// Returns the PID, process name (from IOUserClientCreator), and accumulated time.
    private static func gpuTimePerPid() -> [(pid: pid_t, name: String, time: Double)] {
        var perPid: [pid_t: (name: String, time: Double)] = [:]

        let classes = [
            "IOAccelerator",
            "IOGraphicsAccelerator2",
            "AMDRadeonX6000_AmdRadeonGraphicsAccelerator",
            "AMDRadeonX6000_AmdRadeonGraphicsAccelerator2",
            "AMDRadeonX6000_AMDAcceleratedVKDriver",
            "AMDGPUAccelerator"
        ]
        
        for className in classes {
            var accelIterator = io_iterator_t()
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                               IOServiceMatching(className),
                                               &accelIterator) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(accelIterator) }

            var accelerator = IOIteratorNext(accelIterator)
            while accelerator != 0 {
                defer {
                    IOObjectRelease(accelerator)
                    accelerator = IOIteratorNext(accelIterator)
                }

                var clients = io_iterator_t()
                guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == kIOReturnSuccess
                else { continue }
                defer { IOObjectRelease(clients) }

                var client = IOIteratorNext(clients)
                while client != 0 {
                    defer {
                        IOObjectRelease(client)
                        client = IOIteratorNext(clients)
                    }

                    guard let creatorRef = IORegistryEntryCreateCFProperty(
                              client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0),
                          let creator = creatorRef.takeRetainedValue() as? String,
                          let info = Self.nameAndPid(fromCreator: creator)
                    else { continue }

                // Try Apple Silicon (AppUsage array) first, then fallback to root properties for AMD GPUs
                if let usageRef = IORegistryEntryCreateCFProperty(client, "AppUsage" as CFString, kCFAllocatorDefault, 0),
                   let usage = usageRef.takeRetainedValue() as? [[String: Any]] {
                    for entry in usage {
                        if let time = entry["accumulatedGPUTime"] as? Double {
                            var existing = perPid[info.pid] ?? (info.name, 0)
                            existing.time += time
                            perPid[info.pid] = existing
                        } else if let time = entry["accumulatedGPUTime"] as? Int64 {
                            var existing = perPid[info.pid] ?? (info.name, 0)
                            existing.time += Double(time)
                            perPid[info.pid] = existing
                        }
                    }
                } else {
                    // AMD fallback: properties are on the client itself
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(client, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        let keys = ["accumulatedGPUTime", "gpuTime", "accumulatedTime", "CommandQueueGPUTime"]
                        var rawTime: Double = 0
                        for key in keys {
                            if let t = dict[key] as? Double, t > 0 {
                                rawTime = t
                                break
                            } else if let t = dict[key] as? Int64, t > 0 {
                                rawTime = Double(t)
                                break
                            } else if let t = dict[key] as? NSNumber, t.doubleValue > 0 {
                                rawTime = t.doubleValue
                                break
                            }
                        }
                        if rawTime > 0 {
                            var existing = perPid[info.pid] ?? (info.name, 0)
                            existing.time += rawTime
                            perPid[info.pid] = existing
                        }
                    }
                }
                }
            }
        }
        return perPid.map { (pid: $0.key, name: $0.value.name, time: $0.value.time) }
    }

    /// "pid 437, WindowServer" → (437, "WindowServer")
    private static func nameAndPid(fromCreator creator: String) -> (pid: pid_t, name: String)? {
        guard creator.hasPrefix("pid ") else { return nil }
        let rest = creator.dropFirst(4)
        let digits = rest.prefix { $0.isNumber }
        guard let pid = pid_t(digits) else { return nil }
        let afterPid = rest.dropFirst(digits.count).drop(while: { $0 == " " })
        let name = afterPid.hasPrefix(",")
            ? String(afterPid.dropFirst().drop(while: { $0 == " " }))
            : ""
        return (pid, name.isEmpty ? "pid \(pid)" : name)
    }

}
