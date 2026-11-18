// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum GPUSensorsTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        rows(suite)
        text(suite)
        translations(suite)
        throttle(suite)
        display(suite)
        sustained(suite)
        history(suite)
    }

    /// The properties GPUSensors 0.1.0 published on an RX 6800 XT (macOS 26.7.3,
    /// 2026-11-18), as `ioreg -r -c DrogaBoxGPUSensors -l` showed them.
    private static func fixture(status: String = "active", age: Int? = 661,
                                sensors: [String: Any]? = nil,
                                units: [String: Any]? = nil) -> [String: Any] {
        var properties: [String: Any] = [
            "Status": status,
            "StatusCode": NSNumber(value: 1),
            "Library": "AMDRadeonX6000HWLibs",
            "Samples": NSNumber(value: 406),
            "Sensors": sensors ?? [
                "Fan speed percent": NSNumber(value: 34), "PCIe lanes": NSNumber(value: 8),
                "Memory clock": NSNumber(value: 1978), "Board power": NSNumber(value: 28),
                "Fan speed": NSNumber(value: 1207), "Edge temperature": NSNumber(value: 37),
                "Hotspot temperature": NSNumber(value: 40), "GFX clock": NSNumber(value: 32),
                "Memory activity": NSNumber(value: 0), "PCIe link speed": NSNumber(value: 2),
                "GFX activity": NSNumber(value: 1), "GFX voltage": NSNumber(value: 1075),
            ],
            "Units": units ?? [
                "Fan speed percent": "%", "PCIe lanes": "", "Memory clock": "MHz", "Board power": "W",
                "Fan speed": "RPM", "Edge temperature": "C", "Hotspot temperature": "C", "GFX clock": "MHz",
                "Memory activity": "%", "PCIe link speed": "", "GFX activity": "%", "GFX voltage": "mV",
            ],
            "PMLog": ["8": NSNumber(value: 37), "27": NSNumber(value: 40)],
        ]
        if let age { properties["SampleAgeMs"] = NSNumber(value: age) }
        return properties
    }

    private static func parsing(_ suite: TestSuite) {
        let reading = GPUSensorsReading.parse(fixture())
        suite.expect(reading?.values.count == 12, "an active kext yields every named sensor it publishes")
        suite.expect(reading?.value("GFX voltage", unit: "mV") == 1075, "a value is read in the unit the kext states")
        suite.expect(reading?.value("GFX voltage", unit: "V") == nil, "a value in another unit than expected is not used")
        suite.expect(GPUSensorsReading.parse(fixture(status: "waiting for AMDRadeonX6000HWLibs")) == nil,
                     "a kext that is still waiting for the driver gives no reading")
        suite.expect(GPUSensorsReading.parse(fixture(status: "off: unknown build")) == nil,
                     "a kext that switched itself off gives no reading")
        suite.expect(GPUSensorsReading.parse(fixture(age: 5_001)) == nil,
                     "a sample older than five seconds counts as no data")
        suite.expect(GPUSensorsReading.parse(fixture(age: 5_000)) != nil, "a sample five seconds old is still used")
        suite.expect(GPUSensorsReading.parse(fixture(age: nil)) == nil, "without a sample age the reading is not trusted")
        suite.expect(GPUSensorsReading.parse(fixture(sensors: [:])) == nil, "an empty sensor table gives no reading")
        suite.expect(GPUSensorsReading.parse([:]) == nil, "no properties at all give no reading")
        let mixed = GPUSensorsReading.parse(fixture(sensors: ["Edge temperature": NSNumber(value: 37), "Bogus": "hot"]))
        suite.expect(mixed?.values.keys.sorted() == ["Edge temperature"], "a value that is not a number is skipped")
    }

    private static func rows(_ suite: TestSuite) {
        let strings = FeatureStrings.sensors(.enUS)
        guard let reading = GPUSensorsReading.parse(fixture()) else {
            suite.expect(false, "the fixture parses")
            return
        }
        let rows = reading.rows(strings)
        suite.expect(rows.map(\.id) == [GPUSensorsRow.hotspotID, "Edge temperature", "GFX voltage",
                                        "Memory activity", "PCIe link"],
                     "only the readings macOS does not publish join the hotspot, in order (got \(rows.map(\.id)))")
        suite.expect(rows.first?.label == strings.gpuHotspot, "the hotspot keeps the hotspot label")
        suite.expect(rows.first { $0.id == "Edge temperature" }?.value == .temperature(37), "edge temperature in °C")
        suite.expect(rows.first { $0.id == "GFX voltage" }?.value == .volts(1.075), "GFX voltage is shown in volts")
        suite.expect(rows.first { $0.id == "PCIe link" }?.value == .pcie(generation: 3, lanes: 8),
                     "AMD's link speed code 2 is PCIe 3.0")
        suite.expect(!rows.contains { $0.id == "Memory temperature" || $0.id.contains("VR") },
                     "sensors the driver does not fill get no row")

        let renamed = GPUSensorsReading.parse(fixture(units: ["Edge temperature": "mC", "Hotspot temperature": "C"]))
        suite.expect(renamed?.rows(strings).map(\.id) == [GPUSensorsRow.hotspotID],
                     "a sensor in an unexpected unit, or with no unit, is left out")
        let cold = GPUSensorsReading.parse(fixture(sensors: ["Edge temperature": NSNumber(value: 0),
                                                             "Memory VR 1 temperature": NSNumber(value: 52)],
                                                   units: ["Edge temperature": "C", "Memory VR 1 temperature": "C"]))
        let coldRows = cold?.rows(strings) ?? []
        suite.expect(coldRows.map(\.id) == ["Memory VR 1 temperature"], "a 0 °C reading is a missing sensor")
        suite.expect(coldRows.first?.label == "GPU memory VRM 1 temperature", "the memory VRMs keep the kext's index")
        // Seen on the RX 6800 XT at idle: the GFX block is off for a sample.
        let gfxOff = GPUSensorsReading.parse(fixture(sensors: ["GFX voltage": NSNumber(value: 0), "GFX clock": NSNumber(value: 0)],
                                                     units: ["GFX voltage": "mV", "GFX clock": "MHz"]))
        suite.expect(gfxOff?.rows(strings).map(\.value) == [.volts(0)],
                     "a GFX block powered off keeps its voltage row at 0 V instead of the row vanishing")
        // GPUSensors 0.2.0 at idle: the fabric clock is a post-deep-sleep average.
        let fabric = GPUSensorsReading.parse(fixture(sensors: ["Fabric clock": NSNumber(value: 95)], units: ["Fabric clock": "MHz"]))
        suite.expect(fabric?.rows(strings).first?.value == .megahertz(95), "a sleeping fabric keeps its row")
        suite.expect(fabric?.rows(strings).first?.label == "GPU fabric clock (average)",
                     "the fabric clock is labelled as the average it is")
        let lanesOnly = GPUSensorsReading.parse(fixture(sensors: ["PCIe lanes": NSNumber(value: 16)], units: ["PCIe lanes": ""]))
        suite.expect(lanesOnly?.rows(strings).first?.value == .pcie(generation: nil, lanes: 16),
                     "the PCIe row shows the lanes even without the speed")
    }

    private static func text(_ suite: TestSuite) {
        let strings = FeatureStrings.sensors(.enUS)
        suite.expect(GPUSensorsRow.text(.pcie(generation: 3, lanes: 8), strings: strings) == "PCIe 3.0 x8", "PCIe text")
        suite.expect(GPUSensorsRow.text(.pcie(generation: nil, lanes: 16), strings: strings) == "x16", "lanes only")
        suite.expect(GPUSensorsRow.text(.throttle(GPUThrottle(rawValue: 0)), strings: strings) == strings.gpuThrottlingNone,
                     "no throttler bit set reads as none")
        suite.expect(GPUSensorsRow.text(.throttle(GPUThrottle(rawValue: 5)), strings: strings)
                         == "\(strings.gpuThrottleCurrent), \(strings.gpuThrottlePower)",
                     "the driver's bits are named, heat and current before the power limit")
        suite.expect(MetricFormat.temperatureDifference(10, unit: .fahrenheit) == "18 °F",
                     "a temperature difference in Fahrenheit takes no 32 °F offset")
        suite.expect(GPUSensorsRow.text(.megahertz(1_600), strings: strings) == "1600 MHz", "clock text")
        suite.expect(GPUSensorsRow.text(.percent(7), strings: strings) == "7%", "activity text")
        suite.expect(GPUSensorsRow.text(.temperature(40), strings: strings) == nil,
                     "temperatures are left to the user's unit setting")
    }

    private static func translations(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.sensors(language)
            let format = strings.gpuMemoryVRMTemperatureFormat
            suite.expect(format.components(separatedBy: "%d").count == 2
                             && !String(format: format, 1).contains("%"),
                         "\(language): the memory VRM label takes exactly one index")
            let fields = [strings.gpuEdgeTemperature, strings.gpuCoreVRMTemperature, strings.gpuSocVRMTemperature,
                          strings.gpuMemoryVRMTemperature, strings.gpuSocVoltage, strings.gpuMemoryVoltage,
                          strings.gpuMemoryActivity, strings.gpuSocClock, strings.gpuFabricClock,
                          strings.gpuThrottling, strings.gpuThrottlingNone, strings.gpuPCIeLink,
                          strings.gpuSensorsSource, strings.gpuThrottlePower, strings.gpuThrottleThermal,
                          strings.gpuThrottleCurrent, strings.gpuHotspotEdgeGap, strings.gpuTemperatureSource,
                          strings.gpuSourceHotspot, strings.gpuSourceEdge, strings.gpuSourceMemory,
                          strings.gpuTemperatureSourceHelp]
            suite.expect(fields.allSatisfy { !$0.isEmpty } && Set(fields).count == fields.count,
                         "\(language): the GPUSensors labels are filled and distinct")
            let alerts = FeatureStrings.monitorAlerts(language)
            let alertFields = [alerts.gpuTemperature, alerts.gpuTemperatureThreshold, alerts.gpuPower,
                               alerts.gpuPowerThreshold, alerts.gpuMemoryTemperature,
                               alerts.gpuMemoryTemperatureThreshold, alerts.gpuMemoryTemperatureHint,
                               alerts.gpuThrottle, alerts.gpuThrottleHint, alerts.gpuMemoryTemperatureTitle,
                               alerts.gpuMemoryTemperatureBodyFormat, alerts.gpuThrottleTitle,
                               alerts.gpuThrottleBodyFormat]
            suite.expect(alertFields.allSatisfy { !$0.isEmpty } && Set(alertFields).count == alertFields.count,
                         "\(language): the GPU alert labels are filled and distinct")
            suite.expect(alerts.gpuMemoryTemperatureBodyFormat.components(separatedBy: "%@").count == 2
                             && alerts.gpuThrottleBodyFormat.components(separatedBy: "%@").count == 2,
                         "\(language): each GPU alert body takes exactly one value")
        }
    }
    /// PMLog id 35 as AMDRadeonX6000HWLibs builds it (IDA, macOS 26.7.3):
    /// 1 power, 2 thermal, 4 current, and nothing above bit 2.
    private static func throttle(_ suite: TestSuite) {
        suite.expect(GPUThrottle(rawValue: 8).isEmpty, "bits above the driver's three are dropped")
        suite.expect(!GPUThrottle.power.holdsClocksBack, "the power limit at full load is not worth an alert")
        suite.expect(GPUThrottle.thermal.holdsClocksBack && GPUThrottle.current.holdsClocksBack,
                     "heat and current are")
        let reading = GPUSensorsReading.parse(fixture(sensors: ["Throttler status": NSNumber(value: 2),
                                                                "Hotspot temperature": NSNumber(value: 95),
                                                                "Edge temperature": NSNumber(value: 70),
                                                                "Memory temperature": NSNumber(value: 0)],
                                                      units: ["Throttler status": "bits", "Hotspot temperature": "C",
                                                              "Edge temperature": "C", "Memory temperature": "C"]))
        let sample = reading?.sample
        suite.expect(sample?.throttle == .thermal, "the throttler status reaches the shared sample")
        suite.expect(sample?.memory == nil, "a 0 °C VRAM reading is a missing sensor")
        suite.expect(sample?.hotspotEdgeGap(load: 0.3) == nil, "the hotspot-edge gap means nothing at light load")
        suite.expect(sample?.hotspotEdgeGap(load: 0.9) == 25, "under load it is hotspot minus edge")
    }
    private static func display(_ suite: TestSuite) {
        let sample = GPUSensorsSample(hotspot: 60, edge: 52, memory: 70, coreVR: nil, throttle: nil)
        suite.expect(GPUDisplayTemperature.resolve(source: .memory, macOS: 60, sample: sample)
                         == GPUDisplayTemperature(celsius: 70, source: .memory), "VRAM shows when chosen")
        suite.expect(GPUDisplayTemperature.resolve(source: .edge, macOS: 60, sample: nil)
                         == GPUDisplayTemperature(celsius: 60, source: .hotspot),
                     "without the kext the macOS reading shows, labelled as such")
        suite.expect(GPUDisplayTemperature.resolve(source: .hotspot, macOS: nil, sample: sample) == nil,
                     "hotspot is always the macOS reading, as before")
        suite.expect(GPUTemperatureSource.from("bogus") == .hotspot && GPUTemperatureSource.from(nil) == .hotspot,
                     "an unknown saved source falls back to hotspot")
        var snapshot = SystemSnapshot()
        snapshot.gpuTemperature = 61
        suite.expect(snapshot.gpuDisplayCelsius == 61 && snapshot.gpuDisplayLabel == "GPU",
                     "a snapshot without a resolved display temperature shows the macOS one")
        snapshot.gpuDisplayTemperature = GPUDisplayTemperature(celsius: 70, source: .memory)
        suite.expect(snapshot.gpuDisplayCelsius == 70 && snapshot.gpuDisplayLabel == "VRAM",
                     "the VRAM figure is never labelled GPU")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.gpuTemperatureSource] as? String == "hotspot"
                         && Defaults.registeredDefaults[DefaultsKey.monitorAlertGPUMemoryTemperatureThreshold] as? Int == 90
                         && Defaults.registeredDefaults[DefaultsKey.monitorAlertGPUThrottle] as? Bool == false,
                     "the new settings are registered, so the settings backup carries them")
    }
    private static func sustained(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 0)
        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
        var condition = SustainedCondition(duration: 12, allowedMisses: 2)
        suite.expect(!condition.update(true, now: at(0)), "the first hot sample starts the wait")
        suite.expect(!condition.update(false, now: at(5)) && !condition.update(false, now: at(6)),
                     "two samples that fall short are tolerated")
        suite.expect(condition.update(true, now: at(12)), "and the wait still ends on time")
        _ = condition.update(false, now: at(13))
        _ = condition.update(false, now: at(14))
        _ = condition.update(false, now: at(15))
        suite.expect(condition.since == nil, "a third miss in a row starts over")
    }
    /// A history file from before the VRAM metric (ten metrics) still loads,
    /// each metric where it was, and the new one starts empty.
    private static func history(_ suite: TestSuite) {
        suite.expect(LongHistoryMetric.gpuMemoryTemperature.rawValue == 10,
                     "the VRAM metric comes after every metric older files store")
        var tiers = (0..<10).map { _ in
            LongHistoryTier(step: LongHistoryStore.coarseStep, capacity: LongHistoryStore.coarseCapacity)
        }
        for minute in 0...30 { tiers[9].record(120, at: TimeInterval(minute * 60)) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-history-gpusensors-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try LongHistoryStore.encode(tiers).write(to: url)
        } catch {
            suite.expect(false, "the ten-metric fixture could be written")
            return
        }
        let store = LongHistoryStore(fileURL: url, now: 1_800)
        suite.expect(store.averages(.systemPower, range: .oneHour, end: 1_800).contains { $0.isFinite },
                     "system power keeps its saved history")
        suite.expect(!store.averages(.gpuMemoryTemperature, range: .oneHour, end: 1_800).contains { $0.isFinite },
                     "the VRAM history starts empty")
        let empty = LongHistoryTier(step: 60, capacity: 43_200)
        suite.expect(empty.means.isEmpty && empty.mean(slot: 0) == nil,
                     "a metric nothing records holds no slots in memory")
    }
}
