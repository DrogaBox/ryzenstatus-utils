// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI
import UniformTypeIdentifiers

struct SensorsView: View {
    @ObservedObject private var smcDump = SMCDumpService.shared
    @State private var loadTimer: Timer?
    @AppStorage(DefaultsKey.showPreciseTemperature) private var showPreciseTemperature = true
    @AppStorage(DefaultsKey.showRawSMCSensors) private var showRawSMCSensors = false
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: SensorStrings { FeatureStrings.sensors(l10n.language) }
    
    @State private var showingCPUDetails = false
    
    var body: some View {
        Form {
            Section {
                Toggle(strings.preciseTemperature, isOn: $showPreciseTemperature)
                    .tint(.blue)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(strings.rawSensorsToggle, isOn: $showRawSMCSensors)
                        .tint(.gray)
                    
                    Text(strings.rawSensorsCaption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                
                HStack {
                    Text(strings.namedSensors)
                    Spacer()
                    Text("\(smcDump.readings.filter { $0.category != "Other" }.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(strings.totalKeys)
                    Spacer()
                    Text("\(smcDump.readings.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text(strings.exportHeader), footer: Text(strings.exportFooter)) {
                HStack {
                    Button {
                        exportSensorDumpCSV()
                    } label: {
                        Label(strings.exportButton, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            if !showRawSMCSensors {
                // Deduplicate lowercase sensor keys if uppercase counterpart exists
                let allReadings = smcDump.readings
                let filteredReadings = allReadings.filter { sensor in
                    let key = sensor.key
                    if key.hasPrefix("TC") && key.hasSuffix("c") {
                        let upperKey = key.dropLast() + "C"
                        if allReadings.contains(where: { $0.key == upperKey }) {
                            return false
                        }
                    }
                    if key.hasPrefix("TG") && key.hasSuffix("d") {
                        if allReadings.contains(where: { $0.key == "TG0D" || $0.key == "TG0P" }) {
                            return false
                        }
                    }
                    if key.hasPrefix("TG") && key.hasSuffix("p") {
                        if allReadings.contains(where: { $0.key == "TG0D" || $0.key == "TG0P" }) {
                            return false
                        }
                    }
                    return true
                }
                
                let cpuSensors = buildCPUSensors(from: filteredReadings)
                
                let hasKextGpu = !monitor.snapshot.gpuDevices.isEmpty
                let rawGpuSensors = filteredReadings.filter { $0.key.hasPrefix("TG") && $0.value > 0 }
                // When kext GPU devices exist, filter out duplicate primary die temperature keys (TG0D/TG0P),
                // but preserve supplemental sensors such as Hotspot (TG0H) and VRAM (TG0M/TG0V).
                let gpuSensors = rawGpuSensors.filter { sensor in
                    if hasKextGpu {
                        let k = sensor.key
                        if k == "TG0D" || k == "TG0d" || k == "TG0P" || k == "TG0p" {
                            return false
                        }
                    }
                    return true
                }
                let diskSensors = filteredReadings.filter { $0.key.hasPrefix("TH") && $0.value > 0 }
                let ramSensors = filteredReadings.filter { $0.key.hasPrefix("TM") && $0.value > 0 }
                let airSensors = filteredReadings.filter { ($0.key.hasPrefix("TA") || $0.key.hasPrefix("Te") || $0.key.hasPrefix("TW")) && $0.value > 0 }
                let batterySensors = filteredReadings.filter { $0.key.hasPrefix("TB") && $0.value > 0 }
                // Only the FxAc tachometers: FNum is the fan count and FAC0 a
                // flag, neither of them a speed.
                let fanSensors = filteredReadings.filter {
                    $0.key.count == 4 && $0.key.hasPrefix("F") && $0.key.hasSuffix("Ac") && $0.value > 0
                }
                // VC0C comes from the kext's SVI2 reading when the CPU
                // section already shows it; listing it again here would
                // show the same voltage twice.
                let voltageSensors = filteredReadings.filter {
                    $0.key.hasPrefix("V") && $0.value > 0
                        && !($0.key == "VC0C" && monitor.snapshot.cpuCoreVoltage != nil)
                }
                let powerSensors = filteredReadings.filter { $0.key.hasPrefix("P") && $0.value > 0 }
                let currentSensors = filteredReadings.filter { $0.key.hasPrefix("I") && $0.value > 0 }
                
                // 1. CPU Section
                Section {
                    DisclosureGroup(isExpanded: $cpuExpanded) {
                        Button {
                            showingCPUDetails = true
                        } label: {
                            HStack {
                                Image(systemName: "cpu")
                                    .frame(width: 24)
                                    .foregroundColor(.blue)
                                Text(strings.cpuDetailsButton)
                                Spacer()
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // A missing reading shows a dash, never 0 °C or 0 W.
                        SensorRow(name: strings.cpuPackageTemp, value: monitor.snapshot.cpuTemperature.map(formatTemp) ?? "—", icon: "thermometer")
                        SensorRow(name: strings.cpuPackagePower, value: monitor.snapshot.cpuPower.map { MetricFormat.fixed($0, decimals: 1, unit: "W") } ?? "—", icon: "bolt.fill")
                        // SVI2 planes read by the kext (selector 59); Zen 4/5 report none.
                        if let coreVolts = monitor.snapshot.cpuCoreVoltage {
                            SensorRow(name: strings.cpuCoreVoltageSVI2, value: MetricFormat.fixed(coreVolts, decimals: 3, unit: "V"), icon: "bolt.horizontal")
                        }
                        if let socVolts = monitor.snapshot.cpuSocVoltage {
                            SensorRow(name: strings.socVoltageSVI2, value: MetricFormat.fixed(socVolts, decimals: 3, unit: "V"), icon: "bolt.horizontal.circle")
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text(String(format: strings.ccdTemperaturesFormat, cpuSensors.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        
                        // 2-column Grid for CPU Cores to save vertical space
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(cpuSensors) { sensor in
                                HStack {
                                    Image(systemName: "cpu")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    Text(sensorDisplayName(for: sensor.key))
                                        .font(.subheadline)
                                    Spacer(minLength: 4)
                                    Text(formatValue(sensor))
                                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 4)

                        // Per-core power from the kext's CORE_ENERGY_STAT
                        // counters (selector 60); absent on older kexts.
                        let corePowers = monitor.snapshot.cpuCorePowers
                        if !corePowers.isEmpty {
                            Text(String(format: strings.corePowerFormat, corePowers.count,
                                        MetricFormat.fixed(corePowers.reduce(0, +), decimals: 1, unit: "W")))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                                .padding(.bottom, 2)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(Array(corePowers.enumerated()), id: \.offset) { index, watts in
                                    HStack {
                                        Text(String(format: strings.coreFormat, index))
                                            .font(.subheadline)
                                        Spacer(minLength: 4)
                                        Text(MetricFormat.fixed(watts, decimals: 2, unit: "W"))
                                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.blue)
                            Text(strings.cpuSection)
                                .font(.headline)
                            Spacer()
                            Text(strings.sensorCount(cpuSensors.count + 2))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .disclosureHeader(isExpanded: $cpuExpanded)
                    }
                }
                
                // 2. GPU Section
                Section {
                    DisclosureGroup(isExpanded: $gpuExpanded) {
                        if !monitor.snapshot.gpuDevices.isEmpty {
                            // Kext GPU devices (selectors 27-30)
                            ForEach(monitor.snapshot.gpuDevices) { gpu in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Image(systemName: "display")
                                            .foregroundColor(.orange)
                                            .frame(width: 24)
                                        Text(String(format: strings.gpuDeviceFormat, gpu.id))
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                    HStack {
                                        Image(systemName: "thermometer.snowflake")
                                            .frame(width: 24)
                                            .foregroundColor(.secondary)
                                        Text(strings.temperature)
                                        Spacer()
                                        // The kext reports 0 for a reading it does not have.
                                        Text(gpu.temperature > 0 ? formatTemp(gpu.temperature) : "—")
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    if gpu.supportsPower {
                                        HStack {
                                            Image(systemName: "bolt")
                                                .frame(width: 24)
                                                .foregroundColor(.secondary)
                                            Text(strings.power)
                                            Spacer()
                                            Text(gpu.power > 0 ? MetricFormat.fixed(gpu.power, decimals: 1, unit: "W") : "—")
                                                .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            // Fallback: show monitor snapshot GPU data ONLY when no discrete kext devices detected
                            if let temp = monitor.snapshot.gpuTemperature, temp > 0 {
                                SensorRow(name: strings.gpuTemperature, value: formatTemp(temp), icon: "thermometer.snowflake")
                            }
                            if let power = monitor.snapshot.gpuPower, power > 0 {
                                SensorRow(name: strings.gpuPower, value: MetricFormat.fixed(power, decimals: 1, unit: "W"), icon: "bolt")
                            }
                        }
                        // The card's own fan, as its driver reports it; it cannot be set from macOS.
                        if let fan = monitor.snapshot.gpuFan, fan > 0 {
                            SensorRow(name: FeatureStrings.notchCapsuleCenter(L10n.shared.language).fanSpeed,
                                      value: String(format: "%.0f RPM", fan), icon: "fanblades")
                        }

                        // Supplemental SMC TGxx sensors (Hotspot, VRAM, or fallback die)
                        ForEach(gpuSensors) { sensor in
                            SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "thermometer.snowflake")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "display")
                                .foregroundColor(.orange)
                            Text(strings.gpuSection)
                                .font(.headline)
                            Spacer()
                            let kextCount = monitor.snapshot.gpuDevices.count
                            let fanCount = (monitor.snapshot.gpuFan ?? 0) > 0 ? 1 : 0
                            let totalGpuCount = fanCount + (kextCount > 0 ? (kextCount + gpuSensors.count) : (gpuSensors.count + (monitor.snapshot.gpuTemperature != nil ? 1 : 0)))
                            Text(strings.sensorCount(totalGpuCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .disclosureHeader(isExpanded: $gpuExpanded)
                    }
                }
                
                // 3. Storage / Disks Section
                if !diskSensors.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $disksExpanded) {
                            ForEach(diskSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "internaldrive")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "internaldrive")
                                    .foregroundColor(.purple)
                                Text(strings.storageSection)
                                    .font(.headline)
                                Spacer()
                                Text(strings.sensorCount(diskSensors.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disclosureHeader(isExpanded: $disksExpanded)
                        }
                    }
                }
                
                // 4. Memory (RAM) Section
                if !ramSensors.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $ramExpanded) {
                            ForEach(ramSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "memorychip")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "memorychip")
                                    .foregroundColor(.green)
                                Text(strings.memorySection)
                                    .font(.headline)
                                Spacer()
                                Text(strings.sensorCount(ramSensors.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disclosureHeader(isExpanded: $ramExpanded)
                        }
                    }
                }
                
                // 5. Fans & Cooling Section
                if !fanSensors.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $fansExpanded) {
                            ForEach(fanSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "fanblades")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "fanblades")
                                    .foregroundColor(.cyan)
                                Text(strings.fansSection)
                                    .font(.headline)
                                Spacer()
                                Text(strings.sensorCount(fanSensors.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disclosureHeader(isExpanded: $fansExpanded)
                        }
                    }
                }
                
                // 6. Voltages, Power & Current Section
                if !voltageSensors.isEmpty || !powerSensors.isEmpty || !currentSensors.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $powerExpanded) {
                            ForEach(powerSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "bolt.circle")
                            }
                            ForEach(voltageSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "gauge.with.dots.needle.bottom.100percent")
                            }
                            ForEach(currentSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "waveform.path.ecg")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                Text(strings.powerSection)
                                    .font(.headline)
                                Spacer()
                                Text(strings.sensorCount(voltageSensors.count + powerSensors.count + currentSensors.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disclosureHeader(isExpanded: $powerExpanded)
                        }
                    }
                }
                
                // 7. System & Airflow Section
                if !airSensors.isEmpty || !batterySensors.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $systemExpanded) {
                            ForEach(airSensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "wind")
                            }
                            ForEach(batterySensors) { sensor in
                                SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "battery.100")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wind")
                                    .foregroundColor(.teal)
                                Text(strings.environmentSection)
                                    .font(.headline)
                                Spacer()
                                Text(strings.sensorCount(airSensors.count + batterySensors.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disclosureHeader(isExpanded: $systemExpanded)
                        }
                    }
                }
            } else {
                Section(header: Text(strings.rawSection)) {
                    if smcDump.readings.isEmpty {
                        Text(strings.readingSMC)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(smcDump.readings) { reading in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sensorDisplayName(for: reading.key))
                                        .font(.system(.body, weight: .semibold))
                                    Text("\(reading.key) • \(strings.category(reading.category))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatValue(reading))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // The monitor client (a depth-counted panel client, so the popover
        // cannot wipe these needs) and the 1 s SMC sweep run only while the
        // page is on screen in a visible Settings window.
        .settingsPageActivity(.sensors, activate: {
            smcDump.rediscoverKeys()
            smcDump.refresh()
            loadTimer?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    smcDump.refresh()
                }
            }
            timer.tolerance = 0.2
            loadTimer = timer
        }, deactivate: {
            loadTimer?.invalidate()
            loadTimer = nil
        })
        .sheet(isPresented: $showingCPUDetails) {
            VStack {
                HStack {
                    Spacer()
                    Button(strings.done) {
                        showingCPUDetails = false
                    }
                    .padding()
                }
                CPUDetailsView()
                    .frame(width: 500, height: 600)
            }
        }
    }
    
    @State private var cpuExpanded = true
    @State private var gpuExpanded = true
    @State private var disksExpanded = false
    @State private var ramExpanded = false
    @State private var fansExpanded = false
    @State private var powerExpanded = false
    @State private var systemExpanded = false
    
    /// Follows the app's temperature unit; the precise option adds one decimal.
    private func formatTemp(_ value: Double) -> String {
        let unit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
        return showPreciseTemperature
            ? MetricFormat.temperaturePrecise(value, unit: unit)
            : MetricFormat.temperature(value, unit: unit)
    }
    
    private func formatValue(_ sensor: SMCSensorReading) -> String {
        let key = sensor.key
        if key.hasPrefix("T") {
            return formatTemp(sensor.value)
        } else if key.hasPrefix("F") {
            return String(format: "%.0f RPM", sensor.value)
        } else if key.hasPrefix("V") {
            return MetricFormat.fixed(sensor.value, decimals: 3, unit: "V")
        } else if key.hasPrefix("P") {
            return MetricFormat.fixed(sensor.value, decimals: 2, unit: "W")
        } else if key.hasPrefix("I") {
            return MetricFormat.fixed(sensor.value, decimals: 2, unit: "A")
        }
        return String(format: "%.2f", locale: MetricFormat.locale, sensor.value)
    }
    
    private func sensorDisplayName(for key: String) -> String {
        let s = strings
        // TC<Hex>C and TC<Hex>c are one CCD each (TC0C = CCD 1), not one core.
        if key.hasPrefix("TC") && key.count == 4 {
            let idx = key.index(key.startIndex, offsetBy: 2)
            let lastChar = key.last!
            if lastChar == "C" || lastChar == "c", let ccd = Int(String(key[idx]), radix: 16) {
                return String(format: s.ccdTempFormat, ccd + 1)
            }
        }

        switch key {
        case "TC0D", "TC0P": return s.cpuPackage
        case "TCCD", "TCCD1": return String(format: s.cpuCCDFormat, 1)
        case "TCCD2": return String(format: s.cpuCCDFormat, 2)
        case "TDS0": return String(format: s.cpuSocketFormat, 0)
        case "TDS1": return String(format: s.cpuSocketFormat, 1)
        case "Tp0D": return s.cpuVRM
        case "Te0D": return s.systemEnvironment
        case "Tf0D": return s.chipsetVRM
        case "TG0D", "TG0d": return s.gpuDie
        case "TG0P", "TG0p": return s.gpuProximity
        case "TG0H": return s.gpuHotspot
        case "TG0V", "TG0M": return s.gpuMemory
        case "TGDD": return s.gpuDisplayEngine
        case "TH0P", "TH0D": return String(format: s.ssdDriveFormat, 1)
        case "TH1P", "TH1D": return String(format: s.ssdDriveFormat, 2)
        case "TH2P", "TH2D": return String(format: s.ssdDriveFormat, 3)
        case "TM0P", "TM0S": return String(format: s.ramModuleFormat, 1)
        case "TM1P", "TM1S": return String(format: s.ramModuleFormat, 2)
        case "TA0P", "TA0S": return s.ambientIntake
        case "TA1P", "TA1S": return s.ambientExhaust
        case "TW0P": return s.pcieCard
        case "VC0C": return s.cpuCoreVoltageVCore
        case "VG0C": return s.gpuVoltage
        case "PC0C": return s.cpuPowerConsumed
        case "PG0C": return s.gpuPowerConsumed
        default:
            // FxAc / FxID: one Super I/O header each, x = 0-9, A-Z (the kext
            // publishes FNum + FxAc from 3.36.0; SMCSuperIO uses the same keys).
            if key.count == 4, key.hasPrefix("F"), key.hasSuffix("Ac") || key.hasSuffix("ID"),
               let fan = Int(String(key[key.index(key.startIndex, offsetBy: 1)]), radix: 36) {
                return String(format: s.fanSpeedFormat, fan + 1)
            }
            if key.hasPrefix("TC") { return String(format: s.cpuSensorFormat, key) }
            if key.hasPrefix("TG") { return String(format: s.gpuSensorFormat, key) }
            if key.hasPrefix("TH") { return String(format: s.ssdSensorFormat, key) }
            if key.hasPrefix("TM") { return String(format: s.ramSensorFormat, key) }
            if key.hasPrefix("TA") { return String(format: s.airSensorFormat, key) }
            if key.hasPrefix("F") { return String(format: s.fanSensorFormat, key) }
            if key.hasPrefix("V") { return String(format: s.voltageSensorFormat, key) }
            if key.hasPrefix("P") { return String(format: s.powerSensorFormat, key) }
            return key
        }
    }

    /// S2-T5: export the current SMC dump as CSV via a save panel (replaces
    /// the dead stub; the verification flow was never implemented and is gone).
    private func exportSensorDumpCSV() {
        let readings = smcDump.readings
        guard !readings.isEmpty else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "RyzenStatus-Sensors"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "Key,Value,Type,Category\n"
        for r in readings {
            let value = (r.value.isFinite)
                ? String(format: "%.4f", r.value)
                : ""
            csv += "\(r.key),\(value),\(r.type),\(r.category)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// The kext publishes TCxC/TCxc once per CCD (Zen has no per-core
    /// temperature sensor), so this lists the CCDs it actually reports and
    /// never fills in rows for keys that do not exist.
    private func buildCPUSensors(from filteredReadings: [SMCSensorReading]) -> [SMCSensorReading] {
        var perCCD: [Int: SMCSensorReading] = [:]
        for sensor in filteredReadings {
            let key = sensor.key
            if key.hasPrefix("TC") && key.count == 4 {
                let idx = key.index(key.startIndex, offsetBy: 2)
                let lastChar = key.last!
                if (lastChar == "C" || lastChar == "c"), let ccd = Int(String(key[idx]), radix: 16),
                   perCCD[ccd] == nil || lastChar == "C" {
                    perCCD[ccd] = sensor
                }
            }
        }
        return perCCD.keys.sorted().compactMap { perCCD[$0] }
    }
}

struct SensorRow: View {
    let name: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            Text(name)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
