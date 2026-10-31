// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import IOKit

/// One row of the per-app breakdown shown when a System stat is expanded.
struct ProcessUsage: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// CPU/GPU: percentage (0–100+). Memory: bytes. Network and disk: total bytes/s.
    let value: Double
    let networkDownBytesPerSec: Double?
    let networkUpBytesPerSec: Double?
    let diskReadBytesPerSec: Double?
    let diskWriteBytesPerSec: Double?

    var id: pid_t { pid }

    init(pid: pid_t,
         name: String,
         value: Double,
         networkDownBytesPerSec: Double? = nil,
         networkUpBytesPerSec: Double? = nil,
         diskReadBytesPerSec: Double? = nil,
         diskWriteBytesPerSec: Double? = nil) {
        self.pid = pid
        self.name = name
        self.value = value
        self.networkDownBytesPerSec = networkDownBytesPerSec
        self.networkUpBytesPerSec = networkUpBytesPerSec
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
    }
}

/// Answers "which apps are eating this resource?" for the panel's System
/// section. CPU and memory come from one `ps` listing shared with the process
/// manager (`ProcessTable`): `ps`'s %cpu and resident memory, the same
/// meaning KillProcessService shows. GPU comes from the accelerator's
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
    private var staleCacheSeconds: TimeInterval { max(60.0, configuredCacheFreshSeconds * 10.0) }
    private let minimumGPUSampleInterval: TimeInterval = 0.8
    private let maximumCachedRows = 60
    private var cpuCache: CachedRows?
    private var memoryCache: CachedRows?
    private var gpuCache: CachedRows?
    private var energyCache: CachedRows?
    private var networkCache: CachedRows?
    private var diskCache: CachedRows?
    private var diskDeltaTracker = DiskProcessDeltaTracker()
    private let diskSampleLock = NSLock()
    /// One `ps` run fills the CPU and the memory caches together.
    private var tableLoading = false
    private var gpuLoading = false
    private var energyLoading = false
    private var networkLoading = false
    private var networkLeaseExpiresAt: TimeInterval = 0
    private var networkDeltaTracker = NetworkProcessDeltaTracker()
    private let networkSamplerLock = NSLock()
    private var networkSamplerRunning = false
    private var networkSamplerGeneration = 0
    /// BUG-08 fix: leakingPIDs is now read-only publicly. All mutations go through
    /// cacheLock to prevent the data race with InsightEngine.evaluate on arbitrary threads.
    private var _leakingPIDs: Set<pid_t> = []
    /// Thread-safe snapshot of PIDs whose memory footprint appears to be leaking.
    func leakingPIDsCopy() -> Set<pid_t> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _leakingPIDs
    }

    private var footprintHistory: [pid_t: [(Date, UInt64)]] = [:]
    private var lastLeakAnalysisTime: TimeInterval = 0

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
        diskCache = nil
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
        networkLeaseExpiresAt = NetworkProcessSamplingPolicy.renewedLease(now: now)
        if let cached = limitedRows(networkCache, limit: limit, now: now, maxAge: staleCacheSeconds) {
            cacheLock.unlock()
            return cached
        }
        networkLoading = true
        cacheLock.unlock()
        startNetworkSampler()
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

    // MARK: - Disk

    /// Readings closer together than this share one sample, so two callers in
    /// the same refresh do not measure a sliver of time between them.
    private let minimumDiskSampleInterval: TimeInterval = 1

    /// The apps reading from and writing to storage the most since the
    /// previous sample, heaviest first. Blocking: call it off the main thread.
    /// Nil while warming up: the first sample only primes the counters.
    func topDisk(limit: Int = 5) -> [ProcessUsage]? {
        diskSampleLock.lock()
        defer { diskSampleLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(diskCache, limit: limit, now: now, maxAge: minimumDiskSampleInterval)
        cacheLock.unlock()
        if let cached { return cached }

        guard let rates = diskDeltaTracker.rates(DiskProcessSampler.totals(), at: now) else { return nil }
        let rows = groupedDiskByApp(rates)
        cacheLock.lock()
        diskCache = cachedRows(from: rows)
        cacheLock.unlock()
        return Array(rows.prefix(limit))
    }

    private func groupedDiskByApp(_ rates: [pid_t: (read: Double, write: Double)]) -> [ProcessUsage] {
        var totals: [pid_t: (read: Double, write: Double)] = [:]
        var fallbackNames: [pid_t: String] = [:]
        for (pid, rate) in rates {
            let responsible = ResponsibleProcess.owner(of: pid)
            let owner = responsible <= 1 ? pid : responsible
            var total = totals[owner] ?? (0, 0)
            total.read += rate.read
            total.write += rate.write
            totals[owner] = total
            if fallbackNames[owner] == nil {
                fallbackNames[owner] = DiskProcessSampler.name(of: pid)
            }
        }
        return totals
            .sorted { ($0.value.read + $0.value.write) > ($1.value.read + $1.value.write) }
            .enumerated()
            .map { index, element in
                let owner = element.key
                let fallback = fallbackNames[owner] ?? "pid \(owner)"
                let name = index < maximumCachedRows
                    ? ResponsibleProcess.displayName(pid: owner, fallback: fallback)
                    : fallback
                return ProcessUsage(pid: owner,
                                    name: name,
                                    value: element.value.read + element.value.write,
                                    diskReadBytesPerSec: element.value.read,
                                    diskWriteBytesPerSec: element.value.write)
            }
    }

    func topCPU(limit: Int = 15) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(cpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
        let isFresh = limitedRows(cpuCache, limit: limit, now: now, maxAge: cacheFreshSeconds) != nil
        if isFresh || tableLoading {
            cacheLock.unlock()
            return cached
        }
        tableLoading = true
        cacheLock.unlock()
        refreshProcessTable()
        return cached
    }

    // MARK: - Memory

    func topMemory(limit: Int = 15) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        let cached = limitedRows(memoryCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
        let isFresh = limitedRows(memoryCache, limit: limit, now: now, maxAge: cacheFreshSeconds) != nil
        if isFresh || tableLoading {
            cacheLock.unlock()
            return cached
        }
        tableLoading = true
        cacheLock.unlock()
        refreshProcessTable()
        return cached
    }

    /// One `ps` listing feeds both rankings, so asking for CPU also keeps the
    /// memory history (and the leak check) growing. Called with
    /// `tableLoading` already set.
    private func refreshProcessTable() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = Shell.run("/bin/ps", ProcessTable.psArguments)
            let table = result.status == 0 ? ProcessTable.parse(result.output) : []
            // An empty listing is a failed run, never "no processes".
            guard !table.isEmpty else {
                self.finishTable(cpu: nil, memory: nil)
                return
            }
            let cpuRows = self.groupedByApp(table.map {
                ProcessUsage(pid: $0.pid, name: $0.shortName, value: $0.cpuPercent)
            })
            let memoryRows = self.groupedByApp(table.filter { $0.rssBytes > 0 }.map {
                ProcessUsage(pid: $0.pid, name: $0.shortName, value: $0.rssBytes)
            })
            self.finishTable(cpu: cpuRows, memory: memoryRows)
        }
    }

    // MARK: - Consolidation

    /// Sums per-process values under each process's responsible app and keeps
    /// the heaviest `limit` rows. The row's pid becomes the responsible pid,
    /// so the app's proper name and icon are shown.
    private func groupedByApp(_ rows: [ProcessUsage]) -> [ProcessUsage] {
        var totals: [pid_t: Double] = [:]
        var fallbackNames: [pid_t: String] = [:]

        for row in rows {
            let respOwner = ResponsibleProcess.owner(of: row.pid)
            let owner = (respOwner <= 1) ? row.pid : respOwner
            totals[owner, default: 0] += row.value
            if fallbackNames[owner] == nil {
                fallbackNames[owner] = row.name
            }
        }

        return totals
            .sorted { a, b in
                if abs(a.value - b.value) > 0.001 {
                    return a.value > b.value
                }
                return a.key < b.key
            }
            .enumerated()
            .map { index, element in
                let owner = element.key
                let value = element.value
                let fallback = fallbackNames[owner] ?? "pid \(owner)"
                let name = index < maximumCachedRows
                    ? ResponsibleProcess.displayName(pid: owner, fallback: fallback)
                    : fallback
                return ProcessUsage(pid: owner, name: name, value: value)
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
            .filter { $0.value.down + $0.value.up > 0 }
            .sorted { ($0.value.down + $0.value.up) > ($1.value.down + $1.value.up) }
            .enumerated()
            .map { index, element in
                let owner = element.key
                let value = element.value
                let fallback = fallbackNames[owner] ?? "pid \(owner)"
                let name = index < maximumCachedRows
                    ? ResponsibleProcess.displayName(pid: owner, fallback: fallback)
                    : fallback
                return ProcessUsage(pid: owner,
                             name: name,
                             value: value.down + value.up,
                             networkDownBytesPerSec: value.down,
                             networkUpBytesPerSec: value.up)
            }
    }

    // MARK: - GPU

    private var previousGPUSample: (time: TimeInterval, perPid: [pid_t: Double])?
    private let gpuSampleLock = NSLock()

    /// True once a GPU sample has completed against an earlier one. Before
    /// that the list is empty only because there is no baseline yet, which
    /// must not read as "this GPU reports nothing".
    private var gpuDeltaSampled = false

    var hasGPUDeltaSample: Bool {
        gpuSampleLock.withLock { gpuDeltaSampled }
    }

    /// Per-process GPU share since the previous call. Work the driver does
    /// not attribute to a process is not billed to anyone: there is no
    /// invented WindowServer row.
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

            var rows: [ProcessUsage] = []
            if let previous, now > previous.time, now - previous.time < 30 {
                let elapsedNs = (now - previous.time) * 1_000_000_000
                for (pid, name, total) in current {
                    guard let before = previous.perPid[pid], total > before else { continue }
                    let percent = (total - before) / elapsedNs * 100
                    guard percent >= 0.05 else { continue }
                    let displayName = ResponsibleProcess.displayName(pid: pid, fallback: name)
                    rows.append(ProcessUsage(pid: pid, name: displayName, value: min(percent, 100)))
                }
                self.gpuSampleLock.withLock { self.gpuDeltaSampled = true }
            }

            _ = self.finishGPU(self.groupedByApp(rows), limit: limit)
        }
        return cached
    }

    /// Stores both rankings from one `ps` run; nil keeps the old caches (a
    /// failed run serves the stale rows until the next one).
    private func finishTable(cpu: [ProcessUsage]?, memory: [ProcessUsage]?) {
        cacheLock.lock()
        tableLoading = false
        guard let cpu, let memory else {
            cacheLock.unlock()
            return
        }
        cpuCache = cachedRows(from: cpu)
        memoryCache = cachedRows(from: memory)
        let historyToAnalyze = updateFootprintHistory(rows: memory)
        cacheLock.unlock()
        if let historyToAnalyze { updateLeakingPIDs(from: historyToAnalyze) }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .processUsageDidUpdate, object: nil)
        }
    }

    /// Called with cacheLock held (from finishTable). Returns a snapshot of the
    /// history when a leak analysis is due; the caller runs it after unlocking.
    private func updateFootprintHistory(rows: [ProcessUsage]) -> [pid_t: [(Date, UInt64)]]? {
        let now = Date()
        let activePIDs = Set(rows.map(\.pid))
        let cutoff = now.addingTimeInterval(-1800)

        for row in rows {
            var series = footprintHistory[row.pid] ?? []
            series.append((now, UInt64(max(0, row.value))))
            series = series.filter { $0.0 >= cutoff }
            footprintHistory[row.pid] = series
        }
        footprintHistory = footprintHistory.filter { activePIDs.contains($0.key) }

        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastLeakAnalysisTime >= 30 else { return nil }
        lastLeakAnalysisTime = uptime
        return footprintHistory
    }

    /// LeakDetector.analyze runs a linear regression over thousands of points, so
    /// it runs outside cacheLock or it would block topCPU/topGPU/topMemory callers.
    private func updateLeakingPIDs(from history: [pid_t: [(Date, UInt64)]]) {
        var newLeaking = Set<pid_t>()
        for (pid, series) in history {
            if LeakDetector.analyze(series: series) != nil {
                newLeaking.insert(pid)
            }
        }
        cacheLock.lock()
        _leakingPIDs = newLeaking
        cacheLock.unlock()
    }

    private func finishGPU(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        gpuLoading = false
        if let rows {
            gpuCache = cachedRows(from: rows)
            cacheLock.unlock()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .processUsageDidUpdate, object: nil)
            }
            return Array(rows.prefix(limit))
        }
        cacheLock.unlock()
        return limitedRows(gpuCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func cachedRows(from rows: [ProcessUsage]) -> CachedRows {
        CachedRows(rows: Array(rows.prefix(maximumCachedRows)),
                   updatedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func limitedRows(_ cache: CachedRows?, limit: Int, now: TimeInterval, maxAge: TimeInterval) -> [ProcessUsage]? {
        guard let cache, now - cache.updatedAt <= maxAge else { return nil }
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
        // IOServiceMatching also matches subclasses, so one accelerator answers to
        // several of these names (a Navi 21 is both IOAccelerator and
        // IOGraphicsAccelerator2). Walk each one once or its time is counted twice.
        var visitedAccelerators = Set<UInt64>()

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

                var entryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(accelerator, &entryID) == kIOReturnSuccess,
                   !visitedAccelerators.insert(entryID).inserted { continue }

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
                    // Targeted property reads instead of materializing
                    // the entire IORegistry properties dictionary for every user client.
                    let keys = ["accumulatedGPUTime", "gpuTime", "accumulatedTime", "CommandQueueGPUTime"]
                    var rawTime: Double = 0
                    for key in keys {
                        if let propRef = IORegistryEntryCreateCFProperty(client, key as CFString, kCFAllocatorDefault, 0) {
                            let val = propRef.takeRetainedValue()
                            if let t = val as? Double, t > 0 {
                                rawTime = t
                                break
                            } else if let t = val as? Int64, t > 0 {
                                rawTime = Double(t)
                                break
                            } else if let t = val as? NSNumber, t.doubleValue > 0 {
                                rawTime = t.doubleValue
                                break
                            }
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

extension Notification.Name {
    static let processUsageDidUpdate = Notification.Name("ProcessUsageDidUpdate")
}
