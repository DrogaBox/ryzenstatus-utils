// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI


struct FansSettingsView: View {
    @State private var fans: [FanSnapshot] = []
    @State private var hasSMCWriteAccess: Bool = true
    @State private var loadTimer: Timer?
    
    var body: some View {
        Form {
            Section {
                if !hasSMCWriteAccess {
                    Text("No se pudo acceder a los ventiladores de AMD. Ejecuta como root o revisa SMCAMDProcessor / SuperIO kext.")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if fans.isEmpty {
                    Text("No se detectaron ventiladores.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(fans) { fan in
                        FanControlRow(fan: fan)
                            .padding(.vertical, 4)
                    }
                    
                    HStack {
                        Spacer()
                        Button("Todos Automáticos") {
                            for f in fans {
                                _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: f.id)
                            }
                            fetchState()
                        }
                        Button("Máxima Velocidad") {
                            for f in fans {
                                _ = ProcessorModel.shared.setFanSpeed(rpm: 255, fanIndex: f.id)
                            }
                            fetchState()
                        }
                    }
                    .padding(.top, 8)
                }
            } header: {
                Text("Control de Ventiladores AMD")
            } footer: {
                Text("El control de ventiladores funciona interceptando los registros SuperIO soportados por tu placa base. Algunos ventiladores (GPU, etc.) son controlados independientemente por su firmware.")
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
        hasSMCWriteAccess = ProcessorModel.shared.connect != 0
        
        let fansRes = ProcessorModel.shared.kernelGetUInt64(count: 1, selector: 91)
        guard fansRes.count > 0 else { return }
        let numFans = Int(fansRes[0])
        
        var initFans: [FanSnapshot] = []
        for i in 0..<numFans {
            let name = ProcessorModel.shared.kernelGetString(selector: 92, args: [UInt64(i)])
            let finalName = name.isEmpty ? "Fan \(i + 1)" : name
            initFans.append(FanSnapshot(id: i, name: finalName, rpm: 0, throttle: 0, isOverrided: false))
        }
        self.fans = initFans
        fetchState()
    }
    
    private func fetchState() {
        let numFans = fans.count
        guard numFans > 0 else { return }
        
        let fanRpms = ProcessorModel.shared.kernelGetUInt64(count: numFans, selector: 93)
        let fanCtrls = ProcessorModel.shared.kernelGetUInt64(count: numFans, selector: 94)
        
        for i in 0..<numFans {
            if i < fanRpms.count {
                // Clamp to a sane RPM range to avoid display issues
                fans[i].rpm = min(fanRpms[i], 9999)
            }
            if i < fanCtrls.count {
                // Mask to 8 bits — kernel can return garbage high bytes;
                // force-casting UInt64 > 255 to UInt8 is an overflow trap (SIGILL release)
                fans[i].throttle = UInt8(fanCtrls[i] & 0xFF)
            }
        }
    }
}

struct FanControlRow: View {
    let fan: FanSnapshot
    
    @State private var sliderValue: Double = 0
    @State private var isManual: Bool = false
    
    private var displayedPct: Int {
        if isManual {
            return Int(sliderValue)
        } else {
            // En Auto, ignoramos fan.throttle (puede reportar valores engañosos como 1 o 2)
            // y usamos RPM puro para estimar el porcentaje (asumiendo 2500RPM como 100%).
            return Int(min(100.0, max(0.0, (Double(fan.rpm) / 2500.0) * 100.0)))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {

                
                VStack(alignment: .leading) {
                    Text(fan.name)
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("\(fan.rpm) RPM · \(displayedPct)%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $isManual) {
                    Text("Auto").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: isManual) { _, manual in
                    if manual {
                        var targetPct = sliderValue
                        if fan.throttle == 0 && fan.rpm > 0 {
                            // Estimar % inicial para que al pasar a manual no se caiga a 0
                            let estimatedPct = (Double(fan.rpm) / 2500.0) * 100.0
                            targetPct = min(100.0, max(25.0, estimatedPct)) // Mínimo seguro de 25%
                            sliderValue = targetPct
                        } else if fan.throttle > 0 {
                            targetPct = Double(fan.throttle) / 255.0 * 100.0
                            sliderValue = targetPct
                        }
                        
                        let rawPWM = Int((targetPct / 100.0) * 255.0)
                        _ = ProcessorModel.shared.setFanSpeed(rpm: rawPWM, fanIndex: fan.id)
                    } else {
                        _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fan.id)
                    }
                }
            }
            
            if isManual {
                HStack {
                    Text("Min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $sliderValue, in: 0...100, step: 1) { editing in
                        if !editing {
                            let rawPWM = Int((sliderValue / 100.0) * 255.0)
                            _ = ProcessorModel.shared.setFanSpeed(rpm: rawPWM, fanIndex: fan.id)
                        }
                    }
                    .tint(.orange)
                    Image(systemName: "wind")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            isManual = fan.isOverrided
            if fan.isOverrided {
                sliderValue = fan.throttle > 0 ? Double(fan.throttle) / 255.0 * 100.0 : 50.0
            } else {
                sliderValue = min(100.0, max(25.0, (Double(fan.rpm) / 2500.0) * 100.0))
            }
        }
        .onChange(of: fan.throttle) { _, newVal in
            if !isManual && newVal > 0 {
                // If it's manual, we don't let external throttle override the slider unless we just opened the view
            }
        }
        .onChange(of: fan.isOverrided) { _, overridden in
            if isManual != overridden {
                isManual = overridden
            }
        }
    }
}

