// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdPowerSettingsView: View {
    @State private var isCPPCActive: Bool = false
    @State private var selectedEpp: UInt8 = 127
    @State private var cppcSupported: Bool = false
    @State private var cpbSupported: Bool = false
    @State private var corePerformanceBoost: Bool = false
    @State private var ppmEnabled: Bool = false
    @State private var lpmEnabled: Bool = false
    @State private var legacyPstateAllowed: Bool = false
    @State private var selectedPState: Int = 0
    @State private var validPStateLabels: [String] = []
    
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var monitor = SystemMonitor.shared

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 10
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50

    // Mapping for EPP values
    private func snapEPP(_ e: UInt8) -> UInt8 {
        if e < 42 { return 0 }
        if e < 127 { return 85 }
        if e < 212 { return 170 }
        return 255
    }

    private var eppLabel: String {
        switch snapEPP(selectedEpp) {
        case 0:   return "Rendimiento"
        case 85:  return "Balanced Perf"
        case 170: return "Balanced Power"
        default:  return "Power Save"
        }
    }

    private var minFrequency: Double {
        let freqs = monitor.snapshot.cores.map { Double($0.freqMHz) }.filter { $0 > 0 }
        return freqs.min() ?? 0
    }

    private var maxFrequency: Double {
        let freqs = monitor.snapshot.cores.map { Double($0.freqMHz) }.filter { $0 > 0 }
        return freqs.max() ?? 0
    }

    private var averageFrequency: Double {
        let freqs = monitor.snapshot.cores.map { Double($0.freqMHz) }.filter { $0 > 0 }
        guard !freqs.isEmpty else { return 0 }
        return freqs.reduce(0, +) / Double(freqs.count)
    }

    var body: some View {
        Form {
            Section(header: Text("Información del Procesador AMD Ryzen")) {
                HStack {
                    Text("Package Power")
                    Spacer()
                    Text(String(format: "%.2f W", monitor.snapshot.cpuPower ?? 0))
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("Package Temp")
                    Spacer()
                    Text(String(format: "%.1f °C", monitor.snapshot.cpuTemperature ?? 0))
                        .font(.system(.body, design: .monospaced))
                }
                
                if !monitor.snapshot.cores.isEmpty {
                    HStack {
                        Text("Frecuencia Mínima")
                        Spacer()
                        Text(String(format: "%.0f MHz", minFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Frecuencia Máxima (Peak)")
                        Spacer()
                        Text(String(format: "%.0f MHz", maxFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Frecuencia Promedio")
                        Spacer()
                        Text(String(format: "%.0f MHz", averageFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            if !cppcSupported && !cpbSupported {
                Section {
                    Text("AMD Power Control no es compatible con tu procesador o versión de kext.")
                        .foregroundColor(.red)
                }
            } else {
                if cppcSupported {
                    Section {
                        Text("Modo Detectado: CPPC (Auto-EPP - Zen 3+)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                } else if legacyPstateAllowed {
                    Section {
                        Text("Modo Detectado: Legacy P-States (Zen/Zen+)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                if cppcSupported {
                    Section {
                        Toggle("Auto EPP (Zen 3)", isOn: $isCPPCActive)
                            .onChange(of: isCPPCActive) { _, newValue in
                                _ = ProcessorModel.shared.setCPPCActiveMode(active: newValue)
                            }

                        if isCPPCActive {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("CPU Load")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(autoEpp.currentCPULoad))%")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(loadColor(for: autoEpp.currentCPULoad))
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(height: 8)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(loadColor(for: autoEpp.currentCPULoad))
                                            .frame(width: max(2, geo.size.width * CGFloat(min(autoEpp.currentCPULoad, 100) / 100)), height: 8)
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding(.vertical, 4)

                            HStack {
                                Image(systemName: "cpu")
                                    .foregroundColor(.cyan)
                                Text("Auto EPP Activo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(autoEpp.currentTarget)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(autoEppTargetColor)
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Umbral de Inactividad")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(idleThreshold)%")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    Text("Por debajo de este % de carga -> Power Save (máxima eficiencia)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(
                                        get: { Double(idleThreshold) },
                                        set: { idleThreshold = Int($0) }
                                    ), in: 1...99)
                                    .labelsHidden()
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Umbral de Carga")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(loadThreshold)%")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.red)
                                    }
                                    Text("Por encima de este % de carga -> Rendimiento (máxima velocidad)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(
                                        get: { Double(loadThreshold) },
                                        set: { loadThreshold = Int($0) }
                                    ), in: 1...99)
                                    .labelsHidden()
                                }
                            }
                            .padding(.vertical, 4)
                            .transition(.opacity)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Perfil de Energia (Energy Profile)")
                                .font(.headline)

                            HStack {
                                Text(isCPPCActive ? "Auto" : eppLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isCPPCActive ? .secondary : .cyan)
                                Spacer()
                                if !isCPPCActive {
                                    Text("Manual")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Picker("", selection: $selectedEpp) {
                                Text("Max").tag(UInt8(0))
                                Text("Bal+").tag(UInt8(85))
                                Text("Bal-").tag(UInt8(170))
                                Text("Eco").tag(UInt8(255))
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: selectedEpp) { _, newValue in
                                _ = ProcessorModel.shared.setCPPCEPPValue(epp: newValue)
                            }
                            .disabled(isCPPCActive)
                        }
                        .padding(.vertical, 8)
                        .opacity(isCPPCActive ? 0.5 : 1.0)
                    } header: {
                        Text("Collaborative Processor Performance Control")
                    } footer: {
                        Text("Auto EPP monitorea la carga de la CPU y alterna entre Power Save (inactividad) y Rendimiento (carga alta) según los umbrales configurados.")
                    }
                } else if legacyPstateAllowed {
                    Section {
                        if !validPStateLabels.isEmpty {
                            Picker("", selection: $selectedPState) {
                                ForEach(0..<validPStateLabels.count, id: \.self) { idx in
                                    Text(validPStateLabels[idx]).tag(idx)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: selectedPState) { _, newValue in
                                Task {
                                    _ = await ProcessorModel.shared.setPState(state: newValue)
                                }
                            }
                        }
                    } header: {
                        Text("CPU Speed Profiles (Legacy P-States)")
                    } footer: {
                        Text("Modifica el multiplicador y voltaje global bloqueando el P-State.")
                    }
                }

                Section {
                    if cpbSupported {
                        Toggle("Core Performance Boost (CPB)", isOn: $corePerformanceBoost)
                            .onChange(of: corePerformanceBoost) { _, newValue in
                                _ = ProcessorModel.shared.setCPB(enabled: newValue)
                            }
                    }

                    Toggle("Processor Power Manager (PPM)", isOn: $ppmEnabled)
                        .onChange(of: ppmEnabled) { _, newValue in
                            _ = ProcessorModel.shared.setPPM(enabled: newValue)
                        }

                    Toggle("Low Power Mode (LPM)", isOn: $lpmEnabled)
                        .onChange(of: lpmEnabled) { _, newValue in
                            _ = ProcessorModel.shared.setLPM(enabled: newValue)
                        }
                } header: {
                    Text("Controles Avanzados de Energía")
                } footer: {
                    Text("Desactivar CPB o activar LPM reducirá las temperaturas y el consumo a costa del rendimiento máximo.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            SystemMonitor.shared.setMenuPanelNeeds(SystemMonitorPanelNeeds(cpu: true))
            fetchState()
        }
        .onDisappear {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
    }

    private var autoEppTargetColor: Color {
        guard isCPPCActive else { return .secondary }
        let load = autoEpp.currentCPULoad
        if load < Float(idleThreshold) { return .green }
        if load > Float(loadThreshold) { return .red }
        return .orange
    }

    private func loadColor(for load: Float) -> Color {
        if load < Float(idleThreshold) { return .green }
        if load > Float(loadThreshold) { return .red }
        return .orange
    }

    private func fetchState() {
        Task { @MainActor in
            let kernelAnswered = ProcessorModel.shared.connect != 0
            cppcSupported = kernelAnswered
            if kernelAnswered {
                let state = ProcessorModel.shared.getCPPCActiveMode()
                if isCPPCActive != state.active {
                    isCPPCActive = state.active
                }
                // Snap to segmented value
                let target = snapEPP(state.epp)
                if selectedEpp != target {
                    selectedEpp = target
                }
            }

            let cpb = ProcessorModel.shared.getCPB()
            if cpb.count > 1 {
                cpbSupported = cpb[0]
                if corePerformanceBoost != cpb[1] {
                    corePerformanceBoost = cpb[1]
                }
            }

            ppmEnabled = ProcessorModel.shared.getPPM()
            lpmEnabled = ProcessorModel.shared.getLPM()
            
            // P-States (Legacy Zen)
            let profile = await ProcessorModel.shared.cpuProfile
            legacyPstateAllowed = profile.legacyPstateAllowed
            
            if legacyPstateAllowed {
                let curState = await ProcessorModel.shared.getPState()
                if selectedPState != curState {
                    selectedPState = curState
                }
                
                if validPStateLabels.isEmpty {
                    let clocks = await ProcessorModel.shared.getValidPStateClocks()
                    if !clocks.isEmpty {
                        var labels: [String] = []
                        for (i, c) in clocks.enumerated() {
                            labels.append(String(format: "P%d (%.1f GHz)", i, Double(c)/1000.0))
                        }
                        validPStateLabels = labels
                    }
                }
            }
        }
    }
}
