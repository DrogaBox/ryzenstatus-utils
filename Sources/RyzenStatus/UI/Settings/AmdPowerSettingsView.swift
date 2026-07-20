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
        case 255: return "Rendimiento"
        case 170: return "Balanced Perf"
        case 85: return "Balanced Power"
        default: return "Power Save"
        }
    }

    var body: some View {
        Form {
            if !cppcSupported && !cpbSupported {
                Section {
                    Text("AMD Power Control no es compatible con tu procesador o versión de kext.")
                        .foregroundColor(.red)
                }
            } else {
                Section {
                    CoreGridDashboard(
                        cores: monitor.snapshot.cores,
                        ccdTemperatures: monitor.snapshot.ccdTemperatures,
                        physicalCoresCount: ProcessorModel.shared.snapshotTelemetry(forceMetric: false).numPhysicalCores
                    )
                } footer: {
                    Text("⚠️ Atención: Mantener esta ventana abierta mantendrá activa la lectura del hardware en segundo plano (SystemMonitor), lo cual puede impactar el consumo de batería y la CPU a lo largo del tiempo. Cierra las preferencias cuando no necesites monitorear.")
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
                                    Text("Por debajo de este % de carga -> Power Save (maxima eficiencia)")
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
                                    Text("Por encima de este % de carga -> Rendimiento (maxima velocidad)")
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
                                Text("Max").tag(UInt8(255))
                                Text("Bal+").tag(UInt8(170))
                                Text("Bal-").tag(UInt8(85))
                                Text("Eco").tag(UInt8(0))
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
                        Text("Auto EPP monitorea la carga de la CPU y alterna entre Power Save (inactividad) y Rendimiento (carga alta) segun los umbrales configurados.")
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
                    Text("Controles Avanzados de Energia")
                } footer: {
                    Text("Desactivar CPB o activar LPM reducira las temperaturas y el consumo a costa del rendimiento maximo.")
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
        }
    }
}
