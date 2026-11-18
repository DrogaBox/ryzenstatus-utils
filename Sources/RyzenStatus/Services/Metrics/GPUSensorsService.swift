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

    /// Nil unless the kext reports itself active with a fresh sample.
    static func parse(_ properties: [String: Any]) -> GPUSensorsReading? {
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
        return GPUSensorsReading(values: values, units: units)
    }

    /// A value only when the kext states the unit this app expects for it, so
    /// a renamed or rescaled sensor drops out instead of showing a wrong figure.
    func value(_ name: String, unit: String) -> Double? {
        guard units[name] == unit else { return nil }
        return values[name]
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
        func millivolts(_ name: String, _ label: String) {
            if let mV = value(name, unit: "mV"), mV > 0, mV < 5_000 {
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
        megahertz("Fabric clock", strings.gpuFabricClock)
        if let bits = value("Throttler status", unit: "bits"), bits >= 0, bits <= Double(UInt32.max) {
            rows.append(GPUSensorsRow(id: "Throttler status", label: strings.gpuThrottling,
                                      value: .throttler(UInt32(bits))))
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

struct GPUSensorsRow: Equatable, Identifiable {
    enum Value: Equatable {
        case temperature(Double)   // °C
        case volts(Double)
        case percent(Double)       // 0...100
        case megahertz(Double)
        case throttler(UInt32)     // the driver's throttler bitmask, 0 when nothing holds the clocks back
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
        case .throttler(let bits):
            return bits == 0 ? strings.gpuThrottlingNone : String(format: "0x%08X", bits)
        case .pcie(let generation, let lanes):
            let parts = [generation.map { "PCIe \($0).0" }, lanes.map { "x\($0)" }].compactMap { $0 }
            return parts.joined(separator: " ")
        }
    }
}

/// Polls `DrogaBoxGPUSensors` once a second while a page that shows it is on
/// screen. Each poll is one property read of a service found once, never a
/// user client. When the service is missing it is looked for again only every
/// `lookupInterval`, so a Mac without the kext pays next to nothing.
///
/// `@unchecked Sendable`: every mutable property is confined, as marked below,
/// either to the main thread or to `queue`.
final class GPUSensorsService: ObservableObject, @unchecked Sendable {
    static let shared = GPUSensorsService()

    // Main thread only.
    @Published private(set) var reading: GPUSensorsReading?

    static let pollInterval: TimeInterval = 1
    static let lookupInterval: TimeInterval = 15

    private let queue = DispatchQueue(label: "ryzenstatus.gpusensors", qos: .utility)
    // Main thread only.
    private var clients = 0
    private var timer: DispatchSourceTimer?
    // `queue` only.
    private var service: io_service_t = 0
    private var nextLookup: TimeInterval = 0

    private init() {}

    /// Balanced with `stop()`; the first client starts the poll.
    @MainActor func start() {
        clients += 1
        guard clients == 1 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.poll() }
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
        return properties(of: entry).flatMap(GPUSensorsReading.parse)
    }

    private func poll() {
        let next = read(now: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reading != next else { return }
            self.reading = next
        }
    }

    private func read(now: TimeInterval) -> GPUSensorsReading? {
        #if DEBUG
        // `-gpuSensorsOff YES` shows a debug build as a Mac without the kext.
        if UserDefaults.standard.bool(forKey: "gpuSensorsOff") { return nil }
        #endif
        if service == 0 {
            guard now >= nextLookup else { return nil }
            nextLookup = now + Self.lookupInterval
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(GPUSensorsReading.serviceClass))
            guard service != 0 else { return nil }
        }
        guard let properties = Self.properties(of: service) else {
            // The service went away; look for it again on the lookup schedule.
            IOObjectRelease(service)
            service = 0
            return nil
        }
        return GPUSensorsReading.parse(properties)
    }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var dict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = dict?.takeRetainedValue() as? [String: Any] else { return nil }
        return properties
    }
}
