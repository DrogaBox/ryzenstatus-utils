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
                let cpuSensors = smcDump.readings.filter { $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tp") || $0.key.hasPrefix("Te") || $0.key.hasPrefix("Tf") }
                let gpuSensors = smcDump.readings.filter { $0.key.hasPrefix("TG") }
                let diskSensors = smcDump.readings.filter { $0.key.hasPrefix("TH") }
                let ramSensors = smcDump.readings.filter { $0.key.hasPrefix("TM") }
                let airSensors = smcDump.readings.filter { $0.key.hasPrefix("TA") }
                let batterySensors = smcDump.readings.filter { $0.key.hasPrefix("TB") }
                
                Section(header: Text("Ryzen Package")) {
                    Button {
                        showingCPUDetails = true
                    } label: {
                        HStack {
                            Image(systemName: "cpu")
                                .frame(width: 24)
                                .foregroundColor(.blue)
                            Text("CPU Details")
                            Spacer()
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    SensorRow(name: "Package Temp", value: formatTemp(monitor.snapshot.cpuTemperature ?? 0), icon: "thermometer")
                    SensorRow(name: "Package Power", value: String(format: "%.2f W", monitor.snapshot.cpuPower ?? 0), icon: "bolt.fill")
                }
                
                if !diskSensors.isEmpty {
                    Section(header: Text("Discos / SSD")) {
                        ForEach(diskSensors) { sensor in
                            SensorRow(name: "Drive \\(sensor.key)", value: formatTemp(sensor.value), icon: "internaldrive")
                        }
                    }
                }
                
                if !ramSensors.isEmpty {
                    Section(header: Text("Memoria RAM")) {
                        ForEach(ramSensors) { sensor in
                            SensorRow(name: "RAM \\(sensor.key)", value: formatTemp(sensor.value), icon: "memorychip")
                        }
                    }
                }
                
                if !batterySensors.isEmpty {
                    Section(header: Text("Batería")) {
                        ForEach(batterySensors) { sensor in
                            SensorRow(name: "Battery \\(sensor.key)", value: formatTemp(sensor.value), icon: "battery.100")
                        }
                    }
                }
                
                if !airSensors.isEmpty {
                    Section(header: Text("Airflow / Motherboard")) {
                        ForEach(airSensors) { sensor in
                            SensorRow(name: "Sensor \\(sensor.key)", value: formatTemp(sensor.value), icon: "wind")
                        }
                    }
                }
                
                Section(header: Text("GPU")) {
                    SensorRow(name: "GPU Temp", value: formatTemp(monitor.snapshot.gpuTemperature ?? 0), icon: "thermometer.snowflake")
                    SensorRow(name: "GPU Power", value: String(format: "%.2f W", monitor.snapshot.gpuPower ?? 0), icon: "bolt")
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
                                    Text(reading.key).font(.system(.body, design: .monospaced, weight: .bold))
                                    Text(reading.category).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: showPreciseTemperature ? "%.2f" : "%.0f", reading.value))
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
            loadTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                if showRawSMCSensors {
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
    
    private func formatTemp(_ value: Double) -> String {
        return showPreciseTemperature ? String(format: "%.1f °C", value) : String(format: "%.0f °C", value)
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
