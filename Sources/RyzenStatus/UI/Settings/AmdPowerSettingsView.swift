// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdPowerSettingsView: View {
    @State private var selectedEpp: UInt8 = 127
    @State private var cppcSupported: Bool = false
    @State private var cpbSupported: Bool = false
    @AppStorage(DefaultsKey.amdCpbEnabled) private var corePerformanceBoost = true
    @AppStorage(DefaultsKey.amdPpmEnabled) private var ppmEnabled = false
    @AppStorage(DefaultsKey.amdLpmEnabled) private var lpmEnabled = false
    @State private var legacyPstateAllowed: Bool = false
    @State private var selectedPState: Int = 0
    @State private var validPStateLabels: [String] = []
    @State private var cpuProfile = ProcessorModel.CPUProfile()
    @State private var cppcActiveMode: Bool = false
    @State private var cppcCurrentEPP: UInt8 = 0
    @ObservedObject private var c6Service = C6ResidencyService.shared
    
    @State private var showCopiedToast: Bool = false
    @State private var selectedPreset: AMDPowerPreset? = {
        guard let raw = UserDefaults.standard.object(forKey: DefaultsKey.amdPowerPreset) as? String,
              let preset = AMDPowerPreset(rawValue: raw) else { return nil }
        return preset
    }()
    @State private var privilegeMessage: String?
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var nvramCState = CStateNvramService.shared
    @ObservedObject private var l10n = L10n.shared

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
            Section(header: Text(l10n.s.amdRyzenProcessorInfo)) {
                HStack {
                    Text("Package Power")
                    Spacer()
                    Text(String(format: "%.1f W", monitor.snapshot.cpuPower ?? 0))
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
                        Text(l10n.s.amdMinFrequency)
                        Spacer()
                        Text(String(format: "%.0f MHz", minFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text(l10n.s.amdMaxFrequency)
                        Spacer()
                        Text(String(format: "%.0f MHz", maxFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text(l10n.s.amdAvgFrequency)
                        Spacer()
                        Text(String(format: "%.0f MHz", averageFrequency))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            if !cppcSupported && !cpbSupported {
                Section {
                    Text(L10n.shared.amdPower.amdPowerControlUnsupported)
                        .foregroundColor(.red)
                }
            } else {
                if cppcSupported {
                    Section {
                        Text(L10n.shared.amdPower.modeDetectedCPPC)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                } else if legacyPstateAllowed {
                    Section {
                        Text(L10n.shared.amdPower.modeDetectedPStates)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                // CPU Profile — architecture codename + capabilities (kext selector 26).
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "cpu.fill")
                                .foregroundColor(.cyan)
                            Text(cpuProfile.archName.isEmpty ? "AMD Ryzen" : cpuProfile.archName)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(cpuProfile.modeDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            capabilityBadge(title: "PM Dispatch",
                                            active: cpuProfile.pmDispatchAllowed,
                                            color: .blue,
                                            help: "Full power-management dispatch (Zen 1/2).")
                            capabilityBadge(title: "Legacy P-States",
                                            active: cpuProfile.legacyPstateAllowed,
                                            color: .teal,
                                            help: "Legacy P-State frequency overrides available.")
                            capabilityBadge(title: "CPPC",
                                            active: cpuProfile.supportsCPPC,
                                            color: .green,
                                            help: "Collaborative Power & Performance Control (EPP).")
                            Spacer()
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(l10n.amdPower.cpuProfileHeader)
                } footer: {
                    Text(l10n.amdPower.cpuProfileFooter)
                }

                // AMD GPU — dedicated GPU telemetry from the kext (selectors 27-30).
                // Hidden entirely when no AMD discrete GPU is detected (iGPU/NVIDIA).
                if !monitor.snapshot.gpuDevices.isEmpty {
                    Section {
                        ForEach(monitor.snapshot.gpuDevices) { gpu in
                            let label = monitor.snapshot.gpuDevices.count > 1 ? "AMD GPU \(gpu.id)" : "AMD GPU"
                            HStack {
                                Image(systemName: "display")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                Text(label)
                                    .font(.subheadline)
                                Spacer()
                                if gpu.supportsPower {
                                    Text(gpu.power > 0 ? String(format: "%.1f W", gpu.power) : "— W")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.green)
                                } else {
                                    Text("— W")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text(gpu.temperature > 0 ? String(format: "%.1f °C", gpu.temperature) : "— °C")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    } header: {
                        Text(l10n.amdPower.amdGPUHeader)
                    } footer: {
                        Text(l10n.amdPower.amdGPUFooter)
                    }
                }

                if cppcSupported {
                    Section {
                        Toggle("Auto EPP (Zen 3)", isOn: Binding(
                            get: { autoEpp.isActive },
                            set: { autoEpp.setCPPCActive($0) }
                        ))

                        if autoEpp.isActive {
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
                                Text(L10n.shared.amdPower.autoEPPActive)
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
                                        Text(L10n.shared.amdPower.idleThresholdLabel)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(idleThreshold)%")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    Text(L10n.shared.amdPower.idleThresholdHelp)
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
                                        Text(L10n.shared.amdPower.loadThresholdLabel)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(loadThreshold)%")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.red)
                                    }
                                    Text(L10n.shared.amdPower.loadThresholdHelp)
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
                            Text(L10n.shared.amdPower.energyProfileHeader)
                                .font(.headline)

                            HStack {
                                Text(autoEpp.isActive ? "Auto" : eppLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(autoEpp.isActive ? .secondary : .cyan)
                                Spacer()
                                if !autoEpp.isActive {
                                    Text("Manual")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // CPPC info (selector 23): active mode + raw EPP value.
                            HStack {
                                Image(systemName: cppcActiveMode ? "bolt.fill" : "bolt.slash")
                                    .font(.caption)
                                    .foregroundColor(cppcActiveMode ? .green : .secondary)
                                Text(cppcActiveMode ? "CPPC Active Mode: On" : "CPPC Active Mode: Off")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("EPP \(cppcCurrentEPP)/255")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.cyan)
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
                            .disabled(autoEpp.isActive)
                        }
                        .padding(.vertical, 8)
                        .opacity(autoEpp.isActive ? 0.5 : 1.0)
                    } header: {
                        Text("Collaborative Processor Performance Control")
                    } footer: {
                        Text(L10n.shared.amdPower.autoEPPFooter)
                    }

                    Section {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(AMDPowerPreset.allCases) { preset in
                                presetCard(preset)
                            }
                        }
                        if autoEpp.isActive {
                            Label(l10n.amdPower.presetsDisableAutoEppHint, systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text(l10n.amdPower.powerPresetsHeader)
                    } footer: {
                        Text(l10n.amdPower.powerPresetsFooter)
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
                        Text(L10n.shared.amdPower.legacyPStatesFooter)
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
                            if newValue { lpmEnabled = false } // PPM and LPM are mutually exclusive
                            _ = ProcessorModel.shared.setPPM(enabled: newValue)
                        }

                    Toggle("Low Power Mode (LPM)", isOn: $lpmEnabled)
                        .onChange(of: lpmEnabled) { _, newValue in
                            if newValue { ppmEnabled = false } // PPM and LPM are mutually exclusive
                            _ = ProcessorModel.shared.setLPM(enabled: newValue)
                        }

                    // Deep C-States (C6) — read-only NVRAM status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(.purple)
                                .font(.caption)
                            Text(l10n.amdPower.deepCStatesTitle)
                                .font(.subheadline)
                            Spacer()
                            if nvramCState.isC6Enabled {
                                Text(l10n.amdPower.c6ActiveBadge)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))
                            } else {
                                Text(l10n.amdPower.c6DisabledBadge)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            }
                        }

                        // Visual bar for C6 residency
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 6)
                                if c6Service.percentage > 0 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(c6Service.percentage > 10 ? Color.green : Color.orange)
                                        .frame(width: max(2, geo.size.width * CGFloat(min(c6Service.percentage / 100.0, 1.0))), height: 6)
                                }
                            }
                        }
                        .frame(height: 6)

                        Text(l10n.amdPower.c6Guidance)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    // CPPC Active Mode — read-only NVRAM status
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "bolt.badge.clock.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(l10n.amdPower.cppcTitle)
                                .font(.subheadline)
                            Spacer()
                            Text(nvramCState.isCppcActiveEnabled ? l10n.amdPower.cppcActiveBadge : l10n.amdPower.cppcInactiveBadge)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(nvramCState.isCppcActiveEnabled ? .green : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill((nvramCState.isCppcActiveEnabled ? Color.green : Color.secondary).opacity(0.12)))
                        }
                        Text(l10n.amdPower.cppcGuidance)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    // Root Privilege Bypass — read-only NVRAM status
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(l10n.amdPower.pnopchkTitle)
                                .font(.subheadline)
                            Spacer()
                            Text(nvramCState.isPnopchkEnabled ? l10n.amdPower.pnopchkActiveBadge : l10n.amdPower.pnopchkInactiveBadge)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(nvramCState.isPnopchkEnabled ? .green : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill((nvramCState.isPnopchkEnabled ? Color.green : Color.secondary).opacity(0.12)))
                        }
                        Text(l10n.amdPower.pnopchkGuidance)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    // Copy AMD Boot-Args — one-click clipboard copy for config.plist
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                            Text(l10n.amdPower.copyAmdArgsButton)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if showCopiedToast {
                                Text(l10n.amdPower.copiedToastText + " " + nvramCState.amdBootArgsString)
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .transition(.opacity)
                            }
                        }

                        HStack {
                            Text(l10n.amdPower.copyAmdArgsGuidance)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button {
                                nvramCState.copyAmdArgsToClipboard()
                                withAnimation { showCopiedToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation { showCopiedToast = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                    Text(l10n.amdPower.copyAmdArgsButton)
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text(L10n.shared.amdPower.advancedEnergyHeader)
                } footer: {
                    Text(L10n.shared.amdPower.advancedEnergyFooter)
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
        .alert(
            L10n.shared.amdPower.title,
            isPresented: .init(get: { privilegeMessage != nil }, set: { if !$0 { privilegeMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(privilegeMessage ?? "")
        }
    }

    private var autoEppTargetColor: Color {
        guard autoEpp.isActive else { return .secondary }
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

    /// Capsule badge for a CPU capability flag, with an explanatory tooltip.
    private func capabilityBadge(title: String, active: Bool, color: Color, help: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(active ? color : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((active ? color : Color.secondary).opacity(active ? 0.15 : 0.1)))
            .help(help)
    }

    // MARK: - Power Presets

    private func presetCard(_ preset: AMDPowerPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: preset.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(presetColor(preset))
                    Text(preset.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                }
                Text(presetSummary(preset))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? presetColor(preset).opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? presetColor(preset).opacity(0.7) : Color.secondary.opacity(0.15),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func applyPreset(_ preset: AMDPowerPreset) {
        // A preset owns the EPP profile: stop Auto EPP so its next poll cycle
        // cannot overwrite the preset's values.
        if autoEpp.isActive {
            autoEpp.setCPPCActive(false)
        }
        let result = ProcessorModel.shared.applyPowerPreset(preset)
        UserDefaults.standard.set(preset.rawValue, forKey: DefaultsKey.amdPowerPreset)
        selectedPreset = preset
        if result.privilegeDenied {
            privilegeMessage = result.firstFailureMessage
        }
        fetchState() // re-sync toggle states with the kext echo
    }

    private func presetSummary(_ preset: AMDPowerPreset) -> String {
        switch preset {
        case .eco: return l10n.amdPower.presetEcoSummary
        case .balance: return l10n.amdPower.presetBalanceSummary
        case .performance: return l10n.amdPower.presetPerformanceSummary
        case .extreme: return l10n.amdPower.presetExtremeSummary
        }
    }

    private func presetColor(_ preset: AMDPowerPreset) -> Color {
        switch preset {
        case .eco: return .green
        case .balance: return .blue
        case .performance: return .orange
        case .extreme: return .red
        }
    }

    private func fetchState() {
        Task { @MainActor in
            let kernelAnswered = ProcessorModel.shared.connect != 0
            cppcSupported = kernelAnswered
            if kernelAnswered {
                let state = ProcessorModel.shared.getCPPCActiveMode()
                cppcActiveMode = state.active
                cppcCurrentEPP = state.epp
                // Snap to segmented value
                let target = snapEPP(state.epp)
                if selectedEpp != target {
                    selectedEpp = target
                }

                let ppm = ProcessorModel.shared.getPPM()
                if ppmEnabled != ppm { ppmEnabled = ppm }
                let lpm = ProcessorModel.shared.getLPM()
                if lpmEnabled != lpm { lpmEnabled = lpm }
            }

            let cpb = ProcessorModel.shared.getCPB()
            if cpb.count > 1 {
                cpbSupported = cpb[0]
                if corePerformanceBoost != cpb[1] {
                    corePerformanceBoost = cpb[1]
                }
            }
            
            // P-States (Legacy Zen)
            let profile = await ProcessorModel.shared.cpuProfile
            legacyPstateAllowed = profile.legacyPstateAllowed
            cpuProfile = profile
            
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
