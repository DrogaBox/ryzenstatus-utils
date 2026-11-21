// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation
import IOKit

/// The extra GPU readings an optional third-party kext, GPUSensors.kext, publishes
/// on an IOService of class `DrogaBoxGPUSensors`: a copy of the PMLog table that
/// Apple's AMD driver already reads for `PerformanceStatistics`, so reading it
/// adds no work for the card. Without the kext there is no reading and every
/// caller behaves as before.
struct GPUSensorsReading: Equatable {
    static let serviceClass = "DrogaBoxGPUSensors"
    /// The driver refreshes the table about once a second. An older copy means
    /// the driver stopped sampling, so its values are no longer current.
    static let maxSampleAgeMs: Double = 5_000

    /// Sensor name, exactly as the kext spells it, to its value in `units`.
    let values: [String: Double]
    let units: [String: String]
    /// When the driver took this sample, in system uptime: the read time
    /// minus the kext's `SampleAgeMs`, so a copy read late is not dated as new.
    var takenAt: TimeInterval = 0

    static var maxSampleAge: TimeInterval { maxSampleAgeMs / 1_000 }

    /// Whether the sample is still current at `now` (uptime).
    func isCurrent(at now: TimeInterval) -> Bool {
        now - takenAt <= Self.maxSampleAge
    }

    /// Nil unless the kext reports itself active with a fresh sample. `now`
    /// is the system uptime of the read, used to date the sample.
    static func parse(_ properties: [String: Any],
                      now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GPUSensorsReading? {
        guard properties["Status"] as? String == "active",
              let age = (properties["SampleAgeMs"] as? NSNumber)?.doubleValue,
              age >= 0, age <= maxSampleAgeMs,
              let sensors = properties["Sensors"] as? [String: Any] else { return nil }
        var values: [String: Double] = [:]
        for (name, raw) in sensors {
            guard let number = raw as? NSNumber, number.doubleValue.isFinite else { continue }
            values[name] = number.doubleValue
        }
        guard !values.isEmpty else { return nil }
        let units = (properties["Units"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        return GPUSensorsReading(values: values, units: units, takenAt: now - age / 1_000)
    }

    /// A value only when the kext states the unit this app expects for it, so
    /// a renamed or rescaled sensor drops out instead of showing a wrong figure.
    func value(_ name: String, unit: String) -> Double? {
        guard units[name] == unit else { return nil }
        return values[name]
    }

    /// The few readings the rest of the app uses, small enough to ride along
    /// in every `SystemSnapshot` without making each one differ.
    var sample: GPUSensorsSample {
        GPUSensorsSample(
            hotspot: GPUSensorsRow.plausibleTemperature(value(GPUSensorsRow.hotspotID, unit: "C")),
            edge: GPUSensorsRow.plausibleTemperature(value("Edge temperature", unit: "C")),
            memory: GPUSensorsRow.plausibleTemperature(value("Memory temperature", unit: "C")),
            coreVR: GPUSensorsRow.plausibleTemperature(value("GFX VR temperature", unit: "C")),
            throttle: throttle)
    }

    var throttle: GPUThrottle? {
        guard let bits = value("Throttler status", unit: "bits"), bits >= 0, bits <= Double(UInt32.max) else { return nil }
        return GPUThrottle(rawValue: UInt32(bits))
    }

    /// The rows for the GPU section, in display order. Readings that macOS
    /// already publishes (clocks, fan, activity, board power) are left out.
    func rows(_ strings: SensorStrings) -> [GPUSensorsRow] {
        var rows: [GPUSensorsRow] = []
        func temperature(_ name: String, _ label: String) {
            if let celsius = GPUSensorsRow.plausibleTemperature(value(name, unit: "C")) {
                rows.append(GPUSensorsRow(id: name, label: label, value: .temperature(celsius)))
            }
        }
        // 0 mV is a real reading: the driver powers the GFX block off at idle
        // (GFX clock, activity and voltage all read 0 for that sample), and
        // dropping the row then made it blink in and out.
        func millivolts(_ name: String, _ label: String) {
            if let mV = value(name, unit: "mV"), mV >= 0, mV < 5_000 {
                rows.append(GPUSensorsRow(id: name, label: label, value: .volts(mV / 1_000)))
            }
        }
        func megahertz(_ name: String, _ label: String) {
            if let mhz = value(name, unit: "MHz"), mhz > 0, mhz < 10_000 {
                rows.append(GPUSensorsRow(id: name, label: label, value: .megahertz(mhz)))
            }
        }

        temperature(GPUSensorsRow.hotspotID, strings.gpuHotspot)
        temperature("Edge temperature", strings.gpuEdgeTemperature)
        temperature("Memory temperature", strings.gpuMemory)
        temperature("GFX VR temperature", strings.gpuCoreVRMTemperature)
        temperature("SOC VR temperature", strings.gpuSocVRMTemperature)
        temperature("Memory VR temperature", strings.gpuMemoryVRMTemperature)
        temperature("Memory VR 0 temperature", String(format: strings.gpuMemoryVRMTemperatureFormat, 0))
        temperature("Memory VR 1 temperature", String(format: strings.gpuMemoryVRMTemperatureFormat, 1))
        millivolts("GFX voltage", strings.gpuVoltage)
        millivolts("SOC voltage", strings.gpuSocVoltage)
        millivolts("Memory voltage", strings.gpuMemoryVoltage)
        if let percent = value("Memory activity", unit: "%"), percent >= 0, percent <= 100 {
            rows.append(GPUSensorsRow(id: "Memory activity", label: strings.gpuMemoryActivity,
                                      value: .percent(percent)))
        }
        megahertz("SOC clock", strings.gpuSocClock)
        // The driver fills this from the firmware's fabric clock averaged after
        // deep sleep, so it falls to about 95 MHz whenever the fabric sleeps:
        // a real figure, labelled as an average rather than the current clock.
        megahertz("Fabric clock", strings.gpuFabricClock)
        if let throttle {
            rows.append(GPUSensorsRow(id: "Throttler status", label: strings.gpuThrottling,
                                      value: .throttle(throttle)))
        }
        // AMD counts the link generation from 0: a speed code of 2 is PCIe 3.0.
        let speed = value("PCIe link speed", unit: "").flatMap { $0 >= 0 && $0 <= 7 ? Int($0) + 1 : nil }
        let lanes = value("PCIe lanes", unit: "").flatMap { $0 >= 1 && $0 <= 32 ? Int($0) : nil }
        if speed != nil || lanes != nil {
            rows.append(GPUSensorsRow(id: "PCIe link", label: strings.gpuPCIeLink,
                                      value: .pcie(generation: speed, lanes: lanes)))
        }
        return rows
    }
}

/// Why the card is holding its clocks back, as Apple's AMD driver reports it
/// in PMLog id 35. It is not the firmware's own throttler bitmask: the driver
/// (`smu_11_0_7_map_smu_throttler_status`, AMDRadeonX6000HWLibs) folds the
/// firmware's per-throttler percentages into three bits, each set once its
/// group reaches the driver's threshold (power 80 %, thermal 90 %, current
/// 80 % by default), and keeps only those three (`& 7`).
struct GPUThrottle: OptionSet, Equatable, Hashable {
    let rawValue: UInt32

    init(rawValue: UInt32) { self.rawValue = rawValue & 7 }

    /// PPT0-3: the board power limit. Reached at full load by design.
    static let power = GPUThrottle(rawValue: 1)
    /// Edge, hotspot, memory, GFX VR, liquid or PLX temperature.
    static let thermal = GPUThrottle(rawValue: 2)
    /// GFX current (TDC).
    static let current = GPUThrottle(rawValue: 4)

    /// Heat or current, not the power limit a card under full load always
    /// runs into: the reasons worth telling the user about.
    var holdsClocksBack: Bool { contains(.thermal) || contains(.current) }

    func text(_ strings: SensorStrings) -> String {
        var reasons: [String] = []
        if contains(.thermal) { reasons.append(strings.gpuThrottleThermal) }
        if contains(.current) { reasons.append(strings.gpuThrottleCurrent) }
        if contains(.power) { reasons.append(strings.gpuThrottlePower) }
        return reasons.isEmpty ? strings.gpuThrottlingNone : reasons.joined(separator: ", ")
    }
}

/// The kext readings the menu bar, the panel, the alerts and the history use.
/// Every field is nil when the kext or the card does not report it.
struct GPUSensorsSample: Equatable {
    var hotspot: Double?
    var edge: Double?
    var memory: Double?
    var coreVR: Double?
    var throttle: GPUThrottle?

    /// GFX load from which the hotspot–edge gap says something about the
    /// cooler. At idle the two sit a few degrees apart on any card.
    static let gapMinimumLoad = 0.5

    /// Hotspot minus edge, only under load (`load` 0...1) and only when both
    /// come from this same reading.
    func hotspotEdgeGap(load: Double?) -> Double? {
        guard let hotspot, let edge, let load, load >= Self.gapMinimumLoad else { return nil }
        return max(0, hotspot - edge)
    }
}

/// Which GPU temperature the menu bar and the island show.
enum GPUTemperatureSource: String, CaseIterable, Identifiable {
    /// What macOS reports (on Navi 21 the hotspot); the default, as before.
    case hotspot
    case edge
    case memory

    var id: String { rawValue }

    static func from(_ raw: String?) -> GPUTemperatureSource {
        raw.flatMap(GPUTemperatureSource.init(rawValue:)) ?? .hotspot
    }
}

/// The GPU temperature to display and where it came from. A source the kext
/// does not report right now falls back to the macOS reading, and the saved
/// choice stays as it is for when the kext is back.
struct GPUDisplayTemperature: Equatable {
    let celsius: Double
    let source: GPUTemperatureSource

    static func resolve(source: GPUTemperatureSource, macOS: Double?, sample: GPUSensorsSample?) -> GPUDisplayTemperature? {
        switch source {
        case .edge:
            if let edge = sample?.edge { return GPUDisplayTemperature(celsius: edge, source: .edge) }
        case .memory:
            if let memory = sample?.memory { return GPUDisplayTemperature(celsius: memory, source: .memory) }
        case .hotspot:
            break
        }
        return macOS.map { GPUDisplayTemperature(celsius: $0, source: .hotspot) }
    }
}

struct GPUSensorsRow: Equatable, Identifiable {
    enum Value: Equatable {
        case temperature(Double)   // °C
        case volts(Double)
        case percent(Double)       // 0...100
        case megahertz(Double)
        case throttle(GPUThrottle)
        case pcie(generation: Int?, lanes: Int?)
    }

    /// The kext's name for the hotspot, the value `PerformanceStatistics`
    /// publishes as `Temperature(C)` on Navi 21.
    static let hotspotID = "Hotspot temperature"

    let id: String
    let label: String
    let value: Value

    /// A sensor the card does not have reads 0, never a real chip temperature.
    static func plausibleTemperature(_ celsius: Double?) -> Double? {
        guard let celsius, celsius > 0, celsius < 150 else { return nil }
        return celsius
    }

    /// Everything but the temperature, which follows the user's unit setting.
    static func text(_ value: Value, strings: SensorStrings) -> String? {
        switch value {
        case .temperature:
            return nil
        case .volts(let volts):
            return MetricFormat.fixed(volts, decimals: 3, unit: "V")
        case .percent(let percent):
            return String(format: "%.0f%%", percent)
        case .megahertz(let mhz):
            return String(format: "%.0f MHz", mhz)
        case .throttle(let throttle):
            return throttle.text(strings)
        case .pcie(let generation, let lanes):
            let parts = [generation.map { "PCIe \($0).0" }, lanes.map { "x\($0)" }].compactMap { $0 }
            return parts.joined(separator: " ")
        }
    }
}

/// Owns the one handle to `DrogaBoxGPUSensors`. The service is found through
/// an IOKit matching notification, so a Mac without the kext pays one
/// registration at launch and nothing after it, and readers never search the
/// registry themselves. Reads are shared: callers within `cacheLifetime` of
/// each other (the system monitor and the Sensors page) get the same copy.
///
/// `@unchecked Sendable`: `service`, `present`, `cached`, `cachedControl`,
/// `cachedAt` and `readInFlight` are guarded by `lock` (the registry read
/// itself runs outside it); `reading`, `control`, `isPresent`,
/// `clients`, `timer` and the notification state are main thread only.
final class GPUSensorsService: ObservableObject, @unchecked Sendable {
    static let shared = GPUSensorsService()

    /// The Sensors page's full table, refreshed while that page is open.
    @Published private(set) var reading: GPUSensorsReading?
    /// What the kext's GPU control (0.3.0+) says about itself, from the same
    /// read as `reading`. Kept apart so it still shows while the sensors have
    /// no fresh sample. Nil without the kext or with one older than 0.3.0.
    @Published private(set) var control: GPUControlStatus?
    /// Whether the kext's service exists. Gates settings that only mean
    /// something with the kext, so they never show on other Macs.
    @Published private(set) var isPresent = false
    /// Whether the kext has the write path (`Write`, 0.5.0 and later): the
    /// GPU control page and its panel row exist only then.
    @Published private(set) var hasWritePath = false

    static let pollInterval: TimeInterval = 1
    static let cacheLifetime: TimeInterval = 0.5

    private let lock = NSLock()
    private var service: io_service_t = 0
    private var present = false
    private var cached: GPUSensorsReading?
    private var cachedControl: GPUControlStatus?
    private var writePath = false
    private var cachedAt: TimeInterval = -.infinity
    /// A registry read is out (`refreshIfStale`); no second one starts.
    private var readInFlight = false

    private let queue = DispatchQueue(label: "ryzenstatus.gpusensors", qos: .utility)
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var clients = 0
    private var timer: DispatchSourceTimer?

    private init() {}

    /// Starts following the service's arrival and removal. Idempotent; call
    /// once at launch. The kext loads at boot, so the first match normally
    /// fires right away.
    @MainActor func watchPresence() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, queue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let matched: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<GPUSensorsService>.fromOpaque(refcon).takeUnretainedValue().serviceAppeared(iterator)
        }
        let terminated: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<GPUSensorsService>.fromOpaque(refcon).takeUnretainedValue().serviceVanished(iterator)
        }
        if IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
                                            IOServiceMatching(GPUSensorsReading.serviceClass),
                                            matched, refcon, &matchedIterator) == KERN_SUCCESS {
            // Arming the notification means draining it once; this also picks
            // up a service that is already there.
            let iterator = matchedIterator
            queue.async { [self] in serviceAppeared(iterator) }
        }
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                            IOServiceMatching(GPUSensorsReading.serviceClass),
                                            terminated, refcon, &terminatedIterator) == KERN_SUCCESS {
            let iterator = terminatedIterator
            queue.async { [self] in serviceVanished(iterator) }
        }
    }

    /// Thread-safe. Nil without the kext, while it is not active, or with a
    /// stale sample. At most one registry read per `cacheLifetime`.
    func currentReading(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GPUSensorsReading? {
        #if DEBUG
        // `-gpuSensorsOff YES` shows a debug build as a Mac without the kext.
        if UserDefaults.standard.bool(forKey: "gpuSensorsOff") { return nil }
        #endif
        refreshIfStale(now: now)
        lock.lock()
        defer { lock.unlock() }
        guard service != 0 else { return nil }
        // A cached copy ages too: past the driver's 5 s it is no reading.
        guard let cached, cached.isCurrent(at: now) else { return nil }
        return cached
    }
    /// Thread-safe. The GPU control's state, from the same shared read as
    /// `currentReading`; nil without the kext or with one older than 0.3.0.
    func currentControl(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GPUControlStatus? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "gpuSensorsOff") { return nil }
        #endif
        refreshIfStale(now: now)
        lock.lock()
        defer { lock.unlock() }
        guard service != 0 else { return nil }
        return cachedControl
    }
    /// One registry read per `cacheLifetime` feeds both values. The read
    /// runs outside `lock`, so a caller on the main thread never waits
    /// behind the timer's read: the one caller that finds the copy stale
    /// reads, and everyone else meanwhile gets the copy there is.
    private func refreshIfStale(now: TimeInterval) {
        lock.lock()
        guard service != 0, !readInFlight, now - cachedAt >= Self.cacheLifetime else {
            lock.unlock()
            return
        }
        readInFlight = true
        let entry = service
        // The service may vanish during the read: keep the handle alive.
        IOObjectRetain(entry)
        lock.unlock()
        let properties = Self.properties(of: entry)
        let nextReading = properties.flatMap { GPUSensorsReading.parse($0, now: now) }
        let nextControl = properties.flatMap(GPUControlStatus.parse)
        lock.lock()
        readInFlight = false
        // Gone or replaced while reading: that read is not this service's.
        if service == entry {
            cached = nextReading
            cachedControl = nextControl
            cachedAt = now
            let hasWrite = nextControl?.writing != nil
            if hasWrite != writePath {
                writePath = hasWrite
                publishWritePath(hasWrite)
            }
        }
        lock.unlock()
        IOObjectRelease(entry)
    }
    /// Thread-safe, no registry access: the last read had `Write`.
    var hasWritePathNow: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "gpuSensorsOff") { return false }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return writePath
    }
    private func publishWritePath(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hasWritePath != value else { return }
            self.hasWritePath = value
        }
    }

    /// Thread-safe, no registry access.
    var isPresentNow: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "gpuSensorsOff") { return false }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return present
    }

    /// Balanced with `stop()`; the first client starts the Sensors page poll.
    @MainActor func start() {
        watchPresence()
        clients += 1
        guard clients == 1 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let next = self.currentReading(now: now)
            let nextControl = self.currentControl(now: now)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.reading != next { self.reading = next }
                if self.control != nextControl { self.control = nextControl }
            }
        }
        self.timer = timer
        timer.resume()
    }

    @MainActor func stop() {
        guard clients > 0 else { return }
        clients -= 1
        guard clients == 0 else { return }
        timer?.cancel()
        timer = nil
    }

    /// One read outside the app's run loop, for `--sensors`.
    static func readOnce() -> GPUSensorsReading? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(GPUSensorsReading.serviceClass))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return properties(of: entry).flatMap { GPUSensorsReading.parse($0) }
    }

    // `queue` only (IOKit delivers the notifications there).
    private func serviceAppeared(_ iterator: io_iterator_t) {
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            lock.lock()
            if service == 0 {
                service = entry
                present = true
                cachedAt = -.infinity
                found = true
            } else {
                IOObjectRelease(entry)
            }
            lock.unlock()
        }
        guard found else { return }
        // One read now, so the write path is known before a page asks.
        refreshIfStale(now: ProcessInfo.processInfo.systemUptime)
        publishPresence(true)
    }

    private func serviceVanished(_ iterator: io_iterator_t) {
        var lost = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            IOObjectRelease(entry)
            lock.lock()
            if service != 0 {
                IOObjectRelease(service)
                service = 0
                present = false
                cached = nil
                cachedControl = nil
                if writePath {
                    writePath = false
                    publishWritePath(false)
                }
                lost = true
            }
            lock.unlock()
        }
        if lost { publishPresence(false) }
    }

    private func publishPresence(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresent != value else { return }
            self.isPresent = value
            if !value {
                self.reading = nil
                self.control = nil
            }
            // The kext alerts count, and add their sampling need, only while
            // it is here: re-sync both when it comes or goes.
            SystemMonitor.shared.planDidChange()
            MainActor.assumeIsolated { MonitorAlertService.shared.syncWithPreferences() }
        }
    }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var dict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = dict?.takeRetainedValue() as? [String: Any] else { return nil }
        return properties
    }
}
