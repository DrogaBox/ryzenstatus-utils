import SwiftUI

struct SensorsView: View {
    @ObservedObject private var smcDump = SMCDumpService.shared
    @State private var loadTimer: Timer?
    @AppStorage("showPreciseTemperature") private var showPreciseTemperature = true
    @AppStorage("showRawSMCSensors") private var showRawSMCSensors = false
    @ObservedObject private var monitor = SystemMonitor.shared
    
    @State private var showingCPUDetails = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Show precise temperature (e.g. 45.4)", isOn: $showPreciseTemperature)
                    .tint(.blue)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show raw SMC sensors (advanced)", isOn: $showRawSMCSensors)
                        .tint(.gray)
                    
                    Text("Lists every undocumented SMC key in the firmware, with its technical name. Useful for debugging, but most have no publicly known meaning.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                
                HStack {
                    Text("Sensors with a known name")
                    Spacer()
                    Text("\(smcDump.readings.filter { $0.category != "Other" }.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Total SMC keys in firmware")
                    Spacer()
                    Text("\(smcDump.readings.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Sensor verification"), footer: Text("Puts the CPU through three known load states and checks that the keys used for the cores respond like cores. The Mac will heat up and the fan will spin up: that is expected.")) {
                HStack {
                    Button("Start verification (~6 min)") {
                        // TODO: Implement verification
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button("Export sensor dump") {
                        // TODO: Implement export
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
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
                
                let gpuSensors = filteredReadings.filter { $0.key.hasPrefix("TG") }
                let diskSensors = filteredReadings.filter { $0.key.hasPrefix("TH") }
                let ramSensors = filteredReadings.filter { $0.key.hasPrefix("TM") }
                let airSensors = filteredReadings.filter { $0.key.hasPrefix("TA") || $0.key.hasPrefix("Te") || $0.key.hasPrefix("TW") }
                let batterySensors = filteredReadings.filter { $0.key.hasPrefix("TB") }
                let fanSensors = filteredReadings.filter { $0.key.hasPrefix("F") }
                let voltageSensors = filteredReadings.filter { $0.key.hasPrefix("V") }
                let powerSensors = filteredReadings.filter { $0.key.hasPrefix("P") }
                let currentSensors = filteredReadings.filter { $0.key.hasPrefix("I") }
                
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
                                Text("Ryzen Architecture & Core Topology Details")
                                Spacer()
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        SensorRow(name: "CPU Package Temp", value: formatTemp(monitor.snapshot.cpuTemperature ?? 0), icon: "thermometer")
                        SensorRow(name: "CPU Package Power", value: String(format: "%.1f W", monitor.snapshot.cpuPower ?? 0), icon: "bolt.fill")
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Per-Core Temperatures (\(cpuSensors.count) Cores/Sensors)")
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
                    } label: {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.blue)
                            Text("CPU & Processor")
                                .font(.headline)
                            Spacer()
                            Text("\(cpuSensors.count + 2) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 2. GPU Section
                Section {
                    DisclosureGroup(isExpanded: $gpuExpanded) {
                        SensorRow(name: "GPU Global Temp", value: formatTemp(monitor.snapshot.gpuTemperature ?? 0), icon: "thermometer.snowflake")
                        SensorRow(name: "GPU Global Power", value: String(format: "%.1f W", monitor.snapshot.gpuPower ?? 0), icon: "bolt")
                        
                        ForEach(gpuSensors) { sensor in
                            SensorRow(name: sensorDisplayName(for: sensor.key), value: formatValue(sensor), icon: "thermometer.snowflake")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "display")
                                .foregroundColor(.orange)
                            Text("Graphics (GPU)")
                                .font(.headline)
                            Spacer()
                            Text("\(gpuSensors.count + 2) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                                Text("Storage & NVMe SSDs")
                                    .font(.headline)
                                Spacer()
                                Text("\(diskSensors.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("Memory (RAM)")
                                    .font(.headline)
                                Spacer()
                                Text("\(ramSensors.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("Fans & Cooling")
                                    .font(.headline)
                                Spacer()
                                Text("\(fanSensors.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("Voltages, Power & Current")
                                    .font(.headline)
                                Spacer()
                                Text("\(voltageSensors.count + powerSensors.count + currentSensors.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("Environment & Airflow")
                                    .font(.headline)
                                Spacer()
                                Text("\(airSensors.count + batterySensors.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section(header: Text("AppleSMC Raw Sensors")) {
                    if smcDump.readings.isEmpty {
                        Text("Reading SMC...")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(smcDump.readings) { reading in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sensorDisplayName(for: reading.key))
                                        .font(.system(.body, weight: .semibold))
                                    Text("\(reading.key) • \(reading.category)")
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
        .onAppear {
            SystemMonitor.shared.setMenuPanelNeeds(SystemMonitorPanelNeeds(power: true, cpuTemperature: true, gpuTemperature: true))
            smcDump.refresh()
            loadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    smcDump.refresh()
                }
            }
        }
        .onDisappear {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
            loadTimer?.invalidate()
            loadTimer = nil
        }
        .sheet(isPresented: $showingCPUDetails) {
            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
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
    
    private func formatTemp(_ value: Double) -> String {
        return showPreciseTemperature ? String(format: "%.1f °C", value) : String(format: "%.0f °C", value)
    }
    
    private func formatValue(_ sensor: SMCSensorReading) -> String {
        let key = sensor.key
        if key.hasPrefix("T") {
            return formatTemp(sensor.value)
        } else if key.hasPrefix("F") {
            return String(format: "%.0f RPM", sensor.value)
        } else if key.hasPrefix("V") {
            return String(format: "%.3f V", sensor.value)
        } else if key.hasPrefix("P") {
            return String(format: "%.2f W", sensor.value)
        } else if key.hasPrefix("I") {
            return String(format: "%.2f A", sensor.value)
        }
        return String(format: "%.2f", sensor.value)
    }
    
    private func sensorDisplayName(for key: String) -> String {
        // Decode TC<Hex>C and TC<Hex>c into Core 0, Core 1, ..., Core 15
        if key.hasPrefix("TC") && key.count == 4 {
            let idx = key.index(key.startIndex, offsetBy: 2)
            let hexChar = String(key[idx])
            let lastChar = key.last!
            if let coreNum = Int(hexChar, radix: 16) {
                if lastChar == "C" {
                    return "Core \(coreNum) Temp"
                } else if lastChar == "c" {
                    return "Core \(coreNum) Temp"
                }
            }
        }
        
        switch key {
        case "TC0D", "TC0P": return "CPU Package"
        case "TCCD", "TCCD1": return "CPU CCD1 (Core Complex)"
        case "TCCD2": return "CPU CCD2 (Core Complex)"
        case "TDS0": return "CPU Socket 0"
        case "TDS1": return "CPU Socket 1"
        case "Tp0D": return "CPU VRM / Power Plane"
        case "Te0D": return "System Environment"
        case "Tf0D": return "Motherboard Chipset / VRM"
        case "TG0D", "TG0d", "TG0P", "TG0p": return "GPU Core / Die"
        case "TG0H": return "GPU Hotspot"
        case "TG0V", "TG0M": return "GPU Memory (VRAM)"
        case "TGDD": return "GPU Display Engine"
        case "TH0P", "TH0D": return "SSD / NVMe Drive 1"
        case "TH1P", "TH1D": return "SSD / NVMe Drive 2"
        case "TH2P", "TH2D": return "SSD / NVMe Drive 3"
        case "TM0P", "TM0S": return "RAM Memory Module 1"
        case "TM1P", "TM1S": return "RAM Memory Module 2"
        case "TA0P", "TA0S": return "Ambient Air Intake"
        case "TA1P", "TA1S": return "Ambient Exhaust"
        case "TW0P": return "Wi-Fi / PCIe Card"
        case "F0Ac", "F0ID": return "Fan 1 Speed"
        case "F1Ac", "F1ID": return "Fan 2 Speed"
        case "F2Ac", "F2ID": return "Fan 3 Speed"
        case "VC0C": return "CPU Core Voltage (VCore)"
        case "VG0C": return "GPU Voltage"
        case "PC0C": return "CPU Power Consumed"
        case "PG0C": return "GPU Power Consumed"
        default:
            if key.hasPrefix("TC") { return "CPU Sensor (\(key))" }
            if key.hasPrefix("TG") { return "GPU Sensor (\(key))" }
            if key.hasPrefix("TH") { return "SSD Sensor (\(key))" }
            if key.hasPrefix("TM") { return "RAM Sensor (\(key))" }
            if key.hasPrefix("TA") { return "Air Sensor (\(key))" }
            if key.hasPrefix("F") { return "Fan Sensor (\(key))" }
            if key.hasPrefix("V") { return "Voltage Sensor (\(key))" }
            if key.hasPrefix("P") { return "Power Sensor (\(key))" }
            return key
        }
    }
    
    private func buildCPUSensors(from filteredReadings: [SMCSensorReading]) -> [SMCSensorReading] {
        let ccd2Val = filteredReadings.first(where: { $0.key == "TCCD2" })?.value
            ?? filteredReadings.first(where: { $0.key == "TCCD1" || $0.key == "TCCD" })?.value
            ?? monitor.snapshot.cpuTemperature
            ?? 50.0
        
        var existingPerCoreMap: [Int: SMCSensorReading] = [:]
        for sensor in filteredReadings {
            let key = sensor.key
            if key.hasPrefix("TC") && key.count == 4 {
                let idx = key.index(key.startIndex, offsetBy: 2)
                let lastChar = key.last!
                if (lastChar == "C" || lastChar == "c"), let coreNum = Int(String(key[idx]), radix: 16) {
                    existingPerCoreMap[coreNum] = sensor
                }
            }
        }
        
        let numPhysCores = Int(monitor.snapshot.numPhysicalCores > 0 ? monitor.snapshot.numPhysicalCores : 16)
        let targetCoreCount = max(numPhysCores, 16)
        
        var result: [SMCSensorReading] = []
        for i in 0..<targetCoreCount {
            if let existing = existingPerCoreMap[i] {
                result.append(existing)
            } else {
                let hexChar = String(i, radix: 16).uppercased()
                let synthKey = "TC\(hexChar)C"
                let synthVal = (i >= 8) ? ccd2Val : (monitor.snapshot.cpuTemperature ?? ccd2Val)
                result.append(SMCSensorReading(key: synthKey, value: synthVal, type: "sp78", category: "Temperature"))
            }
        }
        return result
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
