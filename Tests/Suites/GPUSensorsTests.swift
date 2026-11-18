// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum GPUSensorsTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        rows(suite)
        text(suite)
        translations(suite)
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
        let lanesOnly = GPUSensorsReading.parse(fixture(sensors: ["PCIe lanes": NSNumber(value: 16)], units: ["PCIe lanes": ""]))
        suite.expect(lanesOnly?.rows(strings).first?.value == .pcie(generation: nil, lanes: 16),
                     "the PCIe row shows the lanes even without the speed")
    }

    private static func text(_ suite: TestSuite) {
        let strings = FeatureStrings.sensors(.enUS)
        suite.expect(GPUSensorsRow.text(.pcie(generation: 3, lanes: 8), strings: strings) == "PCIe 3.0 x8", "PCIe text")
        suite.expect(GPUSensorsRow.text(.pcie(generation: nil, lanes: 16), strings: strings) == "x16", "lanes only")
        suite.expect(GPUSensorsRow.text(.throttler(0), strings: strings) == strings.gpuThrottlingNone,
                     "no throttler bit set reads as none")
        suite.expect(GPUSensorsRow.text(.throttler(5), strings: strings) == "0x00000005", "throttler bits in hex")
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
                          strings.gpuSensorsSource]
            suite.expect(fields.allSatisfy { !$0.isEmpty } && Set(fields).count == fields.count,
                         "\(language): the GPUSensors labels are filled and distinct")
        }
    }
}
