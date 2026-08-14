// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdControlSection: View {
    let collapsible: Bool

    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var presetCtrl = AmdPresetController.shared
    @State private var loadTimer: Timer?
    @State private var showThresholds: Bool = false
    
    // Fan state
    @State private var availableFans: [(id: Int, name: String)] = []
    @State private var selectedFanId: Int = 0
    @State private var selectedFanRpm: Int = 0

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 25
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50
    @AppStorage(DefaultsKey.showFansInAmdPower) private var showFansInAmdPower = false

    private var eppLabel: String {
        if autoEpp.isActive {
            return autoEpp.currentTarget.isEmpty ? "Monitor…" : autoEpp.currentTarget
        }
        switch AMDPowerPreset.snapEPP(controls.selectedEpp) {
        case 0:   return L10n.shared.amdPower.perfMax
        case 85:  return L10n.shared.amdPower.perfBalPlus
        case 170: return L10n.shared.amdPower.perfBalMinus
        default:  return L10n.shared.amdPower.perfEco
        }
    }

    private var eppColor: Color {
        if autoEpp.isActive { return .secondary }
        switch AMDPowerPreset.snapEPP(controls.selectedEpp) {
        case 0:   return .red
        case 85:  return .orange
        case 170: return .yellow
        default:  return .green
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
                    DisclosureGroup(isExpanded: $showFansInAmdPower) {
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
                    } label: {
                        Text("SMC Fan Control (Advanced)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Divider().padding(.top, -6).padding(.bottom, -6)
                }
                
                if !controls.cppcSupported && !controls.legacyPstateAllowed && !controls.cpbSupported {
                    Text(L10n.shared.amdPower.amdPowerControlUnsupported)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    if controls.cppcSupported {
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
                                        return AMDPowerPreset.snapEPP(autoEpp.currentEPP)
                                    } else {
                                        return AMDPowerPreset.snapEPP(controls.selectedEpp)
                                    }
                                },
                                set: { controls.setEPP($0) }
                            )) {
                                Text("Max").tag(UInt8(0))
                                Text("Bal+").tag(UInt8(85))
                                Text("Bal-").tag(UInt8(170))
                                Text("Eco").tag(UInt8(255))
                            }
                            .pickerStyle(.segmented)
                            .disabled(autoEpp.isActive || gaming.isActive)
                        }
                        .opacity(autoEpp.isActive || gaming.isActive ? 0.4 : 1.0)

                        if gaming.isActive {
                            Text("Managed by Gaming Mode")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }

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
                            if let warning = controls.privilegeWarning, !warning.isEmpty {
                                Text(warning)
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
                    } else if controls.legacyPstateAllowed {
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
                            
                            if !controls.validPStateLabels.isEmpty {
                                Picker("", selection: Binding(
                                    get: { controls.selectedPState },
                                    set: { controls.setPState($0) }
                                )) {
                                    ForEach(0..<controls.validPStateLabels.count, id: \.self) { idx in
                                        Text(controls.validPStateLabels[idx]).tag(idx)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.shared.amdPower.advancedControls)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        if controls.cppcSupported {
                            HStack {
                                Image(systemName: "cpu").foregroundColor(.cyan).frame(width: 20)
                                Toggle("Auto EPP (Zen 3)", isOn: Binding(
                                    get: { autoEpp.isActive },
                                    set: { autoEpp.setCPPCActive($0) }
                                ))
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                    .disabled(gaming.isActive)
                            }
                        }

                        if controls.cpbSupported {
                            HStack {
                                Image(systemName: "flame.fill").foregroundColor(.orange).frame(width: 20)
                                Toggle("Core Performance Boost", isOn: Binding(
                                    get: { controls.corePerformanceBoost },
                                    set: { controls.setCPB($0) }
                                ))
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                                    .disabled(gaming.isActive)
                            }
                        }

                        HStack {
                            Image(systemName: "speedometer").foregroundColor(.teal).frame(width: 20)
                            Toggle("PPM Limit", isOn: Binding(
                                get: { controls.ppmEnabled },
                                set: { controls.setPPM($0) }
                            ))
                                .font(.system(size: 12))
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                .disabled(gaming.isActive)
                        }

                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundColor(.purple).frame(width: 20)
                            Toggle("LPM Limit", isOn: Binding(
                                get: { controls.lpmEnabled },
                                set: { controls.setLPM($0) }
                            ))
                                .font(.system(size: 12))
                                .toggleStyle(SwitchToggleStyle(tint: .purple))
                                .disabled(gaming.isActive)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onAppear {
                loadFanPicker()
                Task { await controls.syncFromKext() }
                loadTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    Task { await controls.syncFromKext() }
                    updateFanRpm()
                }
                updateFanRpm()
            }
            .onDisappear {
                loadTimer?.invalidate()
                loadTimer = nil
            }
        }
    }
    
    private func loadFanPicker() {
        Task.detached(priority: .userInitiated) {
            let fansRes = ProcessorModel.shared.kernelGetUInt64(count: 1, selector: AMDKextSelector.fanCountRead.id)
            var fans: [(id: Int, name: String)] = []
            if fansRes.count > 0 {
                let numFans = Int(fansRes[0])
                for i in 0..<numFans {
                    fans.append((id: i, name: "Fan \(i + 1)"))
                }
            }
            let initFans = fans          // immutable capture before await
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.availableFans = initFans
            }
        }
    }

    private func updateFanRpm() {
        guard !availableFans.isEmpty else { return }
        let fanCount = availableFans.count
        Task.detached(priority: .utility) {
            let rpms = ProcessorModel.shared.kernelGetUInt64(count: fanCount, selector: AMDKextSelector.fanSpeedRead.id)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if self.selectedFanId < rpms.count {
                    self.selectedFanRpm = Int(min(rpms[self.selectedFanId], 9999))
                }
            }
        }
    }

    // MARK: - Power Presets (menu panel)

    private func presetButton(_ preset: AMDPowerPreset) -> some View {
        let isSelected = presetCtrl.selectedPreset == preset
        return Button {
            presetCtrl.apply(preset)
            Task { await controls.syncFromKext() }
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
                    .fill(isSelected ? preset.color.opacity(0.15) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? preset.color : Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(gaming.isActive)
    }
}
