import SwiftUI

struct FansSettingsView: View {
    @State private var fans: [FanSnapshot] = []
    @State private var hasSMCWriteAccess: Bool = true
    @State private var loadTimer: Timer?
    @ObservedObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        Form {
            Section {
                if !hasSMCWriteAccess {
                    Text("No se pudo acceder a los ventiladores de AMD. Ejecuta como root o revisa SMCAMDProcessor.")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if fans.isEmpty {
                    Text("No se detectaron ventiladores.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($fans) { $fan in
                        FanControlRow(fan: $fan)
                            .padding(.vertical, 4)
                        Divider()
                    }
                    
                    HStack {
                        Spacer()
                        Button("Todos en Auto") {
                            Task {
                                for f in fans {
                                    _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: f.id)
                                    FanCurveController.shared.fanMappings[f.id] = -1
                                }
                                fetchState()
                            }
                        }
                        Button("Máxima Velocidad") {
                            Task {
                                for f in fans {
                                    _ = ProcessorModel.shared.setFanSpeed(rpm: 255, fanIndex: f.id)
                                    FanCurveController.shared.fanMappings[f.id] = -1
                                }
                                fetchState()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } header: {
                Text("AMD Power Gadget - Fan Control")
            } footer: {
                Text("Control directo sobre los ventiladores del sistema. Asigna una curva a cada ventilador o usa BIOS / Auto.")
            }
            
            Section {
                InteractiveFanCurveEditor()
                    .padding(.vertical, 4)
            } header: {
                Text("Custom Curves")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GPU Fan Control")
                        .font(.headline)
                    Text("Los ventiladores de la GPU en macOS (como la RX 6800 XT) no pueden ser controlados directamente desde herramientas de CPU a menos que se haya inyectado un Zero RPM override vía PowerPlay Tables. El control nativo recae sobre WhateverGreen o los drivers nativos de Apple.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            setupFans()
            loadTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                fetchState()
            }
        }
        .onDisappear {
            loadTimer?.invalidate()
            loadTimer = nil
        }
    }
    
    private func setupFans() {
        Task {
            let conn = ProcessorModel.shared.connect
            let hasAccess = conn != 0
            let currentFans = ProcessorModel.shared.getFans()
            await MainActor.run {
                self.hasSMCWriteAccess = hasAccess
                self.fans = currentFans
                self.fetchState()
            }
        }
    }
    
    private func fetchState() {
        Task {
            let currentFans = ProcessorModel.shared.getFans()
            await MainActor.run {
                if self.fans.count != currentFans.count {
                    self.fans = currentFans
                } else {
                    for i in 0..<currentFans.count {
                        self.fans[i].rpm = currentFans[i].rpm
                        self.fans[i].throttle = currentFans[i].throttle
                        self.fans[i].isOverrided = currentFans[i].isOverrided
                    }
                }
            }
        }
    }
}

struct FanControlRow: View {
    @Binding var fan: FanSnapshot
    @ObservedObject var controller = FanCurveController.shared
    
    var body: some View {
        let curveIdx = controller.fanMappings[fan.id] ?? -1
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    TextField("", text: Binding(
                        get: { fan.name },
                        set: { newName in
                            fan.name = newName
                            UserDefaults.standard.set(newName, forKey: "FanName_\(fan.id)")
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .bold))
                    
                    Text("\(fan.rpm) RPM")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: Binding(
                    get: { curveIdx },
                    set: { newIdx in
                        controller.fanMappings[fan.id] = newIdx
                        if newIdx == -1 {
                            // Automatically disable manual override and revert to BIOS auto
                            fan.isOverrided = false
                            Task {
                                _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fan.id)
                            }
                        }
                    }
                )) {
                    Text("BIOS / Auto").tag(-1)
                    Divider()
                    ForEach(controller.customCurves.indices, id: \.self) { idx in
                        Text(controller.customCurves[idx].name).tag(idx)
                    }
                }
                .frame(width: 150)
            }
            
            if curveIdx == -1 {
                HStack {
                    Toggle("Manual Override", isOn: Binding(
                        get: { fan.isOverrided },
                        set: { manual in
                            fan.isOverrided = manual
                            Task {
                                if manual {
                                    let currentThrottle = fan.throttle > 0 ? Double(fan.throttle) : 127.0
                                    _ = ProcessorModel.shared.setFanSpeed(rpm: Int(currentThrottle), fanIndex: fan.id)
                                } else {
                                    _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fan.id)
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 12))
                    
                    Spacer()
                }
                
                if fan.isOverrided {
                    HStack {
                        Slider(value: Binding(
                            get: {
                                fan.throttle > 0 ? (Double(fan.throttle) / 255.0 * 100.0) : 50.0
                            },
                            set: { newValue in
                                let rawPWM = Int((newValue / 100.0) * 255.0)
                                fan.throttle = UInt8(rawPWM)
                                Task {
                                    _ = ProcessorModel.shared.setFanSpeed(rpm: rawPWM, fanIndex: fan.id)
                                }
                            }
                        ), in: 0...100, step: 1)
                        .labelsHidden()
                        .tint(.cyan)
                    }
                }
            }
        }
    }
}
