// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdControlSection: View {
    let collapsible: Bool

    @State private var selectedEpp: UInt8 = 127
    @State private var cppcSupported: Bool = false
    @State private var cpbSupported: Bool = false
    @AppStorage(DefaultsKey.amdCpbEnabled) private var corePerformanceBoost = true
    @AppStorage(DefaultsKey.amdPpmEnabled) private var ppmEnabled = false
    @AppStorage(DefaultsKey.amdLpmEnabled) private var lpmEnabled = false
    @State private var legacyPstateAllowed: Bool = false
    @State private var selectedPState: Int = 0
    @State private var validPStateLabels: [String] = []
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var gaming = GamingModeService.shared
    @State private var loadTimer: Timer?
    @State private var showThresholds: Bool = false
    @State private var selectedPreset: AMDPowerPreset? = AMDPowerPreset.saved()
    @State private var panelWarning: String = ""
    
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
        if autoEpp.isActive {
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
        if autoEpp.isActive { return .secondary }
        switch snapEPP(selectedEpp) {
        case 0:   return .red      // Rendimiento = high power
        case 85:  return .orange
        case 170: return .yellow
        default:  return .green    // Power Save = efficient
        }
    }

    private var autoEppTargetColor: Color {
        guard autoEpp.isActive else { return .cyan }
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
                    Text(L10n.shared.amdPower.amdPowerControlUnsupported)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    if cppcSupported {
                        Text(L10n.shared.amdPower.modeDetectedCPPC)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.bottom, 2)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(autoEpp.isActive ? L10n.shared.amdPower.autoEPPActive : L10n.shared.amdPower.energyProfileManual)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.cyan)
                                Text(eppLabel)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(eppColor)
                            }
                            Spacer()
                            if autoEpp.isActive {
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
                            Picker("", selection: Binding(
                                get: { 
                                    if autoEpp.isActive {
                                        let e = autoEpp.currentEPP
                                        return e < 42 ? UInt8(0) : (e < 127 ? UInt8(85) : (e < 212 ? UInt8(170) : UInt8(255)))
                                    } else {
                                        return selectedEpp
                                    }
                                },
                                set: { selectedEpp = $0 }
                            )) {
                                Text("Max").tag(UInt8(0))
                                Text("Bal+").tag(UInt8(85))
                                Text("Bal-").tag(UInt8(170))
                                Text("Eco").tag(UInt8(255))
                            }
                            .pickerStyle(.segmented)
                            .disabled(autoEpp.isActive)
                            .onChange(of: selectedEpp) { _, newValue in
                                _ = ProcessorModel.shared.setCPPCEPPValue(epp: newValue)
                            }
                        }
                        .opacity(autoEpp.isActive ? 0.4 : 1.0)

                        // One-tap power presets (EPP + CPB + PPM/LPM)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.shared.amdPower.powerPresetsHeader)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                ForEach(AMDPowerPreset.allCases) { preset in
                                    presetButton(preset)
                                }
                            }
                            if !panelWarning.isEmpty {
                                Text(panelWarning)
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                            }
                            if autoEpp.isActive {
                                Text(L10n.shared.amdPower.presetsDisableAutoEppHint)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)

                        if autoEpp.isActive {
                            VStack(spacing: 10) {
                                Button(action: { withAnimation { showThresholds.toggle() } }) {
                                    HStack {
                                        Image(systemName: showThresholds ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10))
                                        Text(L10n.shared.amdPower.autoEPPThresholds)
                                            .font(.system(size: 10, weight: .medium))
                                        Spacer()
                                        Text("Idle <\(idleThreshold)% | Load >\(loadThreshold)%")
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
                                                Text(L10n.shared.amdPower.idleThresholdLabel).font(.system(size: 10))
                                                Spacer()
                                                Text("\(idleThreshold)%").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.green)
                                            }
                                            Slider(value: Binding(get: { Double(idleThreshold) }, set: { idleThreshold = Int($0) }), in: 1...99)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(L10n.shared.amdPower.loadThresholdLabel).font(.system(size: 10))
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
                            Text(L10n.shared.amdPower.modeDetectedPStates)
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
                        Text(L10n.shared.amdPower.advancedControls)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        if cppcSupported {
                            HStack {
                                Image(systemName: "cpu").foregroundColor(.cyan).frame(width: 20)
                                Toggle("Auto EPP (Zen 3)", isOn: Binding(
                                    get: { autoEpp.isActive },
                                    set: { autoEpp.setCPPCActive($0) }
                                ))
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
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

                        HStack {
                            Image(systemName: "speedometer").foregroundColor(.teal).frame(width: 20)
                            Toggle("PPM Limit", isOn: $ppmEnabled)
                                .font(.system(size: 12))
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                        }
                        .onChange(of: ppmEnabled) { _, newValue in
                            if newValue { lpmEnabled = false } // PPM and LPM are mutually exclusive
                            _ = ProcessorModel.shared.setPPM(enabled: newValue)
                        }

                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundColor(.purple).frame(width: 20)
                            Toggle("LPM Limit", isOn: $lpmEnabled)
                                .font(.system(size: 12))
                                .toggleStyle(SwitchToggleStyle(tint: .purple))
                        }
                        .onChange(of: lpmEnabled) { _, newValue in
                            if newValue { ppmEnabled = false } // PPM and LPM are mutually exclusive
                            _ = ProcessorModel.shared.setLPM(enabled: newValue)
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
            // Gaming Mode applies the Extreme preset and restores the previous
            // one on deactivation; re-read the applied preset so the buttons
            // highlight what the kext is really running (the panel can stay
            // open beside Settings while the mode toggles).
            .onChange(of: gaming.isActive) { _, _ in
                selectedPreset = AMDPowerPreset.saved() ?? selectedPreset
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

            if kernelAnswered {
                let ppm = ProcessorModel.shared.getPPM()
                if ppmEnabled != ppm { ppmEnabled = ppm }
                let lpm = ProcessorModel.shared.getLPM()
                if lpmEnabled != lpm { lpmEnabled = lpm }
            }
        }
    }

    // MARK: - Power Presets (menu panel)

    private func presetButton(_ preset: AMDPowerPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            applyPreset(preset)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 11))
                Text(preset.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? presetColor(preset).opacity(0.15) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? presetColor(preset) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func applyPreset(_ preset: AMDPowerPreset) {
        if autoEpp.isActive {
            autoEpp.setCPPCActive(false)
        }
        let result = ProcessorModel.shared.applyPowerPreset(preset)
        UserDefaults.standard.set(preset.rawValue, forKey: DefaultsKey.amdPowerPreset)
        selectedPreset = preset
        panelWarning = result.privilegeDenied ? "Requires admin privileges (-amdpnopchk)." : ""
        checkCapabilities() // re-sync toggles + EPP picker with the kext echo right away
    }

    private func presetColor(_ preset: AMDPowerPreset) -> Color {
        switch preset {
        case .eco: return .green
        case .balance: return .blue
        case .performance: return .orange
        case .extreme: return .red
        }
    }
}
