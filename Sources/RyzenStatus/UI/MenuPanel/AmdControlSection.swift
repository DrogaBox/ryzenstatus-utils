// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdControlSection: View {
    let collapsible: Bool

    @State private var isCPPCActive: Bool = false
    @State private var selectedEpp: UInt8 = 127
    @State private var cppcSupported: Bool = false
    @State private var cpbSupported: Bool = false
    @State private var corePerformanceBoost: Bool = false
    @State private var legacyPstateAllowed: Bool = false
    @State private var selectedPState: Int = 0
    @State private var validPStateLabels: [String] = []
    @ObservedObject private var autoEpp = AutoEppService.shared
    @State private var loadTimer: Timer?
    @State private var showThresholds: Bool = false
    
    // Fan state
    @State private var availableFans: [(id: Int, name: String)] = []
    @State private var selectedFanId: Int = 0
    @State private var selectedFanRpm: Int = 0

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 10
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50

    // Mapping for EPP values: 0 (Rendimiento), 85 (Balanced Perf), 170 (Balanced Power), 255 (Power Save)
    private func snapEPP(_ e: UInt8) -> UInt8 {
        if e < 42 { return 0 }
        if e < 127 { return 85 }
        if e < 212 { return 170 }
        return 255
    }

    private var eppLabel: String {
        if isCPPCActive {
            return autoEpp.currentTarget.isEmpty ? "Monitor…" : autoEpp.currentTarget
        }
        switch snapEPP(selectedEpp) {
        case 0:   return "Rendimiento"
        case 85:  return "Balanced Perf"
        case 170: return "Balanced Power"
        default:  return "Power Save"
        }
    }

    private var eppColor: Color {
        if isCPPCActive { return .secondary }
        switch snapEPP(selectedEpp) {
        case 0:   return .red      // Rendimiento = high power
        case 85:  return .orange
        case 170: return .yellow
        default:  return .green    // Power Save = efficient
        }
    }

    private var autoEppTargetColor: Color {
        guard isCPPCActive else { return .cyan }
        let load = autoEpp.currentCPULoad
        if load < Float(idleThreshold) { return .green }
        if load > Float(loadThreshold) { return .red }
        return .orange
    }

    var body: some View {
        PanelSection(.amdPower, title: "AMD Ryzen Power Control", collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 18) {
                if !availableFans.isEmpty {
                    HStack {
                        Picker("", selection: $selectedFanId) {
                            ForEach(availableFans, id: \.id) { fan in
                                Text(fan.name).tag(fan.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 80)
                        .onChange(of: selectedFanId) { _, _ in
                            updateFanRpm()
                        }
                        
                        Spacer()
                        
                        Text("\(selectedFanRpm) RPM")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Divider().padding(.top, -6).padding(.bottom, -6)
                }
                
                if !cppcSupported && !legacyPstateAllowed && !cpbSupported {
                    Text("AMD Power Control no es compatible con tu procesador o versión de kext.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    if cppcSupported {
                        Text("Modo Detectado: CPPC (Auto-EPP)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.bottom, 2)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isCPPCActive ? "Auto EPP Activo" : "Energy Profile (Manual)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.cyan)
                                Text(eppLabel)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(eppColor)
                            }
                            Spacer()
                            if isCPPCActive {
                                ZStack {
                                    Circle()
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(min(autoEpp.currentCPULoad, 100) / 100))
                                        .stroke(autoEppTargetColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 36, height: 36)
                                        .animation(.easeInOut(duration: 0.3), value: autoEpp.currentCPULoad)
                                    Text("\(Int(autoEpp.currentCPULoad))%")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(autoEppTargetColor)
                                }
                            }
                        }

                        VStack(spacing: 8) {
                            Picker("", selection: $selectedEpp) {
                                Text("Max").tag(UInt8(0))
                                Text("Bal+").tag(UInt8(85))
                                Text("Bal-").tag(UInt8(170))
                                Text("Eco").tag(UInt8(255))
                            }
                            .pickerStyle(.segmented)
                            .disabled(isCPPCActive)
                            .onChange(of: selectedEpp) { _, newValue in
                                _ = ProcessorModel.shared.setCPPCEPPValue(epp: newValue)
                            }
                        }
                        .opacity(isCPPCActive ? 0.4 : 1.0)

                        if isCPPCActive {
                            VStack(spacing: 10) {
                                Button(action: { withAnimation { showThresholds.toggle() } }) {
                                    HStack {
                                        Image(systemName: showThresholds ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                        Text("Umbrales Auto EPP")
                                            .font(.system(size: 10, weight: .medium))
                                        Spacer()
                                        Text("Inactivo <\(idleThreshold)% | Carga >\(loadThreshold)%")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                if showThresholds {
                                    VStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Umbral Inactividad").font(.system(size: 10))
                                                Spacer()
                                                Text("\(idleThreshold)%").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.green)
                                            }
                                            Slider(value: Binding(get: { Double(idleThreshold) }, set: { idleThreshold = Int($0) }), in: 1...99)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Umbral Carga").font(.system(size: 10))
                                                Spacer()
                                                Text("\(loadThreshold)%").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.red)
                                            }
                                            Slider(value: Binding(get: { Double(loadThreshold) }, set: { loadThreshold = Int($0) }), in: 1...99)
                                        }
                                    }
                                    .padding(.leading, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                    } else if legacyPstateAllowed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Modo Detectado: Legacy P-States")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(.bottom, -2)

                            Text("CPU Speed Profiles (Legacy)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.cyan)
                            
                            Text("P-State overrides (Frequencies locked).")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            if !validPStateLabels.isEmpty {
                                Picker("", selection: $selectedPState) {
                                    ForEach(0..<validPStateLabels.count, id: \.self) { idx in
                                        Text(validPStateLabels[idx]).tag(idx)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: selectedPState) { _, newValue in
                                    Task {
                                        _ = await ProcessorModel.shared.setPState(state: newValue)
                                    }
                                }
                            }
                        }
                    }

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Controles Avanzados")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        if cppcSupported {
                            HStack {
                                Image(systemName: "cpu").foregroundColor(.cyan).frame(width: 20)
                                Toggle("Auto EPP (Zen 3)", isOn: $isCPPCActive)
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            }
                            .onChange(of: isCPPCActive) { _, newValue in
                                _ = ProcessorModel.shared.setCPPCActiveMode(active: newValue)
                            }
                        }

                        if cpbSupported {
                            HStack {
                                Image(systemName: "flame.fill").foregroundColor(.orange).frame(width: 20)
                                Toggle("Core Performance Boost", isOn: $corePerformanceBoost)
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                            }
                            .onChange(of: corePerformanceBoost) { _, newValue in
                                _ = ProcessorModel.shared.setCPB(enabled: newValue)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onAppear {
                let fansRes = ProcessorModel.shared.kernelGetUInt64(count: 1, selector: 91)
                if fansRes.count > 0 {
                    let numFans = Int(fansRes[0])
                    var initFans: [(id: Int, name: String)] = []
                    for i in 0..<numFans {
                        initFans.append((id: i, name: "Fan \(i + 1)"))
                    }
                    availableFans = initFans
                }
                
                checkCapabilities()
                
                if cppcSupported {
                    loadTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                        checkCapabilities()
                        updateFanRpm()
                    }
                } else {
                    loadTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                        checkCapabilities()
                        if !availableFans.isEmpty {
                            updateFanRpm()
                        }
                    }
                }
                // Trigger initial read
                updateFanRpm()
            }
            .onDisappear {
                loadTimer?.invalidate()
                loadTimer = nil
            }
        }
    }
    
    private func updateFanRpm() {
        if !availableFans.isEmpty {
            let rpms = ProcessorModel.shared.kernelGetUInt64(count: availableFans.count, selector: 93)
            if selectedFanId < rpms.count {
                selectedFanRpm = Int(min(rpms[selectedFanId], 9999))
            }
        }
    }

    private func checkCapabilities() {
        Task { @MainActor in
            let kernelAnswered = ProcessorModel.shared.connect != 0
            if kernelAnswered {
                let profile = await ProcessorModel.shared.cpuProfile
                cppcSupported = profile.supportsCPPC
                legacyPstateAllowed = profile.legacyPstateAllowed
                
                if cppcSupported {
                    let state = ProcessorModel.shared.getCPPCActiveMode()
                    if isCPPCActive != state.active {
                        isCPPCActive = state.active
                    }
                    // Snap to segmented value
                    let target = snapEPP(state.epp)
                    if selectedEpp != target {
                        selectedEpp = target
                    }
                } else if legacyPstateAllowed {
                    let curState = await ProcessorModel.shared.getPState()
                    if selectedPState != curState {
                        selectedPState = curState
                    }
                    
                    if validPStateLabels.isEmpty {
                        let clocks = await ProcessorModel.shared.getValidPStateClocks()
                        if !clocks.isEmpty {
                            var labels: [String] = []
                            for i in 0..<clocks.count {
                                if i == 0 {
                                    labels.append(String(format: "P%d (Max)", i))
                                } else if i == clocks.count - 1 {
                                    labels.append(String(format: "P%d (Low)", i))
                                } else {
                                    labels.append(String(format: "P%d", i))
                                }
                            }
                            validPStateLabels = labels
                        }
                    }
                }
            } else {
                cppcSupported = false
                legacyPstateAllowed = false
            }

            let cpb = ProcessorModel.shared.getCPB()
            if cpb.count > 1 {
                cpbSupported = cpb[0]
                if corePerformanceBoost != cpb[1] {
                    corePerformanceBoost = cpb[1]
                }
            }
        }
    }
}
