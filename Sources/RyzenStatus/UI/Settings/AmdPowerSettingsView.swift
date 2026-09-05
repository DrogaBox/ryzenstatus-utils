// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdPowerSettingsView: View {
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @State private var cpuProfile = ProcessorModel.CPUProfile()
    @State private var cppcActiveMode: Bool = false
    @State private var cppcCurrentEPP: UInt8 = 0
    @State private var telemetryPacket: CPUSensorPacket?
    @State private var coGeneration = AMDCpuGeneration.unknown
    @State private var coSupported = false
    @State private var coCoreCount = 16
    @State private var curveOffsets: [Int8] = []
    @State private var coStatusMessage: String?
    @State private var coStatusIsError = false
    @State private var isLoading = false
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var c6Service = C6ResidencyService.shared
    
    @State private var showCopiedToast: Bool = false
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var presetCtrl = AmdPresetController.shared
    @ObservedObject private var nvramCState = CStateNvramService.shared
    @ObservedObject private var l10n = L10n.shared

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 25
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50
    @AppStorage("coUnlocked") private var coUnlocked: Bool = false

    private var eppLabel: String {
        switch AMDPowerPreset.snapEPP(controls.selectedEpp) {
        case 0:   return l10n.amdPower.perfMax
        case 85:  return l10n.amdPower.perfBalPlus
        case 170: return l10n.amdPower.perfBalMinus
        default:  return l10n.amdPower.perfEco
        }
    }

    // AUDIT F-17: Move 1 Hz live telemetry out of the root Form into focused
    // subviews so the 1,000-line controls and settings tree does not re-render each second.

    var body: some View {
        Form {
            AmdLiveTelemetrySection()
            
            if isLoading {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading AMD power controls…")
                            .foregroundColor(.secondary)
                    }
                }
            } else if !controls.cppcSupported && !controls.cpbSupported {
                Section {
                    Text(L10n.shared.amdPower.amdPowerControlUnsupported)
                        .foregroundColor(.red)
                }
            } else {
                if controls.cppcSupported {
                    Section {
                        Text(L10n.shared.amdPower.modeDetectedCPPC)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                } else if controls.legacyPstateAllowed {
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

                // AMD Telemetry Packet — zero-copy selector 100 readout (304 bytes).
                if let packet = telemetryPacket {
                    Section {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.cyan)
                                .frame(width: 20)
                            Text("Telemetry Packet (Selector 100)")
                                .font(.subheadline)
                            Spacer()
                            Text("\(CPUSensorPacket.byteSize) B")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Package Power")
                            Spacer()
                            Text(String(format: "%.1f W", packet.packagePowerW))
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Package Temperature")
                            Spacer()
                            let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                            Text(MetricFormat.temperature(Double(packet.packageTempC), unit: unit))
                                .font(.system(.body, design: .monospaced))
                        }
                        if packet.ccdCount > 0 {
                            HStack {
                                Text("CCDs (\(packet.ccdCount))")
                                Spacer()
                                let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                                Text(packet.ccdTemperatures.prefix(Int(packet.ccdCount))
                                    .map { MetricFormat.temperatureCompact(Double($0), unit: unit) }
                                    .joined(separator: "  "))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        let freqs = packet.activeFrequenciesMHz
                        if !freqs.isEmpty {
                            HStack {
                                Text("Core Freq (\(freqs.count) threads)")
                                Spacer()
                                Text(String(format: "%.0f / %.0f / %.0f MHz",
                                           freqs.min() ?? 0,
                                           freqs.reduce(0, +) / Float(freqs.count),
                                           freqs.max() ?? 0))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } header: {
                        Text("Telemetry Packet")
                    } footer: {
                        Text("Zero-copy streaming packet from the kext (selector 100).")
                    }
                }

                // AMD GPU — dedicated GPU telemetry from the kext (selectors 27-30).
                // Hidden entirely when no AMD discrete GPU is detected (iGPU/NVIDIA).
                AmdGpuTelemetrySection()

                // AMD Curve Optimizer — per-core offsets (selectors 110/111).
                // The kext only accepts writes on Zen 3 Vermeer; Zen 4/5 and the
                // baseline profile get an explanatory message instead of a grid.
                Section {
                    if coGeneration.isZen4OrNewer {
                        Label("Curve Optimizer is not supported on Zen 4/5 CPUs. Use PBO in BIOS instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if coSupported {
                        Toggle("Unlock Curve Optimizer Controls", isOn: $coUnlocked)
                            .padding(.bottom, 4)
                        
                        if coUnlocked {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(0..<coCoreCount, id: \.self) { core in
                                    curveOptimizerCell(core)
                                }
                            }
                            HStack(spacing: 10) {
                                Button {
                                    applyAllCurveOffsets()
                                } label: {
                                    Label("Apply All", systemImage: "bolt.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Reset to 0") {
                                    resetCurveOffsets()
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                if let message = coStatusMessage {
                                    Text(message)
                                        .font(.caption2)
                                        .foregroundColor(coStatusIsError ? .red : .green)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } else {
                        Label("Curve Optimizer is disabled because Legacy P-States (PM Dispatch) are not active. The kext blocks SMU writes when running in CPPC or telemetry-only mode.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Curve Optimizer (Selectors 110/111)")
                } footer: {
                    Text("Per-core voltage offset −30..+30 applied via SMU command 0x3D. Writes require root or -amdpnopchk and are blocked above 75 °C package temperature.")
                }

                if controls.cppcSupported {
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
                            .labelsHidden()
                            .disabled(autoEpp.isActive || gaming.isActive)
                        }
                        .padding(.vertical, 8)
                        .opacity(autoEpp.isActive || gaming.isActive ? 0.5 : 1.0)
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

                    // Gaming Mode — one click: Extreme preset + Keep Awake +
                    // hidden menu bar icon. Recoverable by relaunching the app.
                    Section {
                        Toggle(l10n.amdPower.gamingModeTitle, isOn: Binding(
                            get: { gaming.isActive },
                            set: { $0 ? gaming.activate() : gaming.deactivate() }
                        ))

                        Toggle(l10n.amdPower.gamingModeHideIcon, isOn: Binding(
                            get: { gaming.hideMenuBar },
                            set: { newValue in
                                UserDefaults.standard.set(newValue, forKey: DefaultsKey.gamingModeHideMenuBar)
                                if gaming.isActive {
                                    StatusItemController.shared?.setForceHidden(newValue)
                                }
                            }
                        ))
                        .disabled(!gaming.isActive)

                        if gaming.isActive {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(l10n.amdPower.gamingModeActivePreset, systemImage: "flame.fill")
                                Label(l10n.amdPower.gamingModeActiveKeepAwake, systemImage: "moon.zzz.fill")
                                if gaming.hideMenuBar {
                                    Label(l10n.amdPower.gamingModeIconHiddenHint, systemImage: "eye.slash.fill")
                                }
                                if nvramCState.isC6Enabled {
                                    Label(l10n.amdPower.gamingModeC6Hint, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                        }
                        // Rendered even after a failed deactivation: the info
                        // block above disappears with isActive, but the user
                        // must still see that their previous profile could not
                        // be restored.
                        if let message = gaming.statusMessage {
                            Label(message, systemImage: gaming.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(gaming.statusIsError ? .orange : .green)
                                .transition(.opacity)
                        }
                    } header: {
                        Label(l10n.amdPower.gamingModeTitle, systemImage: "gamecontroller.fill")
                    } footer: {
                        Text(l10n.amdPower.gamingModeFooter)
                    }
                } else if controls.legacyPstateAllowed {
                    Section {
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
                            .labelsHidden()
                            .disabled(gaming.isActive)
                        }
                    } header: {
                        Text("CPU Speed Profiles (Legacy P-States)")
                    } footer: {
                        Text(L10n.shared.amdPower.legacyPStatesFooter)
                    }
                }

                Section {
                    if controls.cpbSupported {
                        Toggle("Core Performance Boost (CPB)", isOn: Binding(
                            get: { controls.corePerformanceBoost },
                            set: { controls.setCPB($0) }
                        ))
                        .disabled(gaming.isActive)
                    }

                    Toggle("Processor Power Manager (PPM)", isOn: Binding(
                        get: { controls.ppmEnabled },
                        set: { controls.setPPM($0) }
                    ))
                    .disabled(gaming.isActive)

                    Toggle("Low Power Mode (LPM)", isOn: Binding(
                        get: { controls.lpmEnabled },
                        set: { controls.setLPM($0) }
                    ))
                    .disabled(gaming.isActive)

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
        .task {
            // Full monitor surface: register as a panel client (depth counter)
            // so opening/closing the menu popover cannot wipe these needs.
            SystemMonitor.shared.panelDidAppear()
            await fetchState()
        }
        .onDisappear {
            SystemMonitor.shared.panelDidDisappear()
        }
        // Gaming Mode applies the Extreme preset and restores the previous one
        // on deactivation; re-read the applied preset so the cards highlight
        // what the kext is really running instead of a stale @State value.
        .onChange(of: gaming.isActive) { _, _ in
            Task {
                await controls.syncFromKext()
                await fetchState()
            }
        }
        .alert(
            L10n.shared.amdPower.title,
            isPresented: .init(get: { controls.privilegeWarning != nil }, set: { if !$0 { controls.clearPrivilegeWarning() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controls.privilegeWarning ?? "")
        }
    }

    private var autoEppTargetColor: Color {
        guard autoEpp.isActive else { return .secondary }
        let load = autoEpp.currentCPULoad
        if load < Float(idleThreshold) { return .green }
        if load > Float(loadThreshold) { return .red }
        return .orange
    }

    // MARK: - Curve Optimizer (selectors 110/111)

    private func curveOptimizerCell(_ core: Int) -> some View {
        let offset = core < curveOffsets.count ? curveOffsets[core] : 0
        return VStack(spacing: 3) {
            Text("Core \(core + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button {
                    stepCurveOffset(core, delta: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(offset <= AMDCurveOptimizer.minOffset)

                Text("\(offset)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(curveOffsetColor(offset))
                    .frame(minWidth: 24)

                Button {
                    stepCurveOffset(core, delta: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(offset >= AMDCurveOptimizer.maxOffset)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }

    private func curveOffsetColor(_ offset: Int8) -> Color {
        if offset < 0 { return .green }      // undervolt
        if offset > 0 { return .orange }     // overvolt
        return .secondary                    // stock
    }

    /// Optimistic UI update per tap; the kext write confirms (or reverts via
    /// a reload from selector 110 on failure).
    private func stepCurveOffset(_ core: Int, delta: Int) {
        guard core < curveOffsets.count else { return }
        let candidate = AMDCurveOptimizer.clamp(Int(curveOffsets[core]) + delta)
        guard candidate != curveOffsets[core] else { return }
        curveOffsets[core] = candidate
        writeCurveOffset(core: core, offset: candidate)
    }

    private func writeCurveOffset(core: Int, offset: Int8) {
        // Detached: the SMU 0x3D write can take 5–15 ms on Zen 3 (PLL
        // reconfiguration) — keep it off the main thread, like Apply All.
        // The UI already updated optimistically; on failure we reload from
        // selector 110 so the grid reverts to the kext's real state.
        Task.detached(priority: .userInitiated) {
            let status = ProcessorModel.shared.setCurveOptimizerOffset(core: UInt8(core), offset: offset)
            await MainActor.run {
                if status == KERN_SUCCESS {
                    coStatusMessage = "Core \(core + 1) → \(offset)"
                    coStatusIsError = false
                } else {
                    reloadCurveOffsets()
                    coStatusMessage = curveOptimizerError(status)
                    coStatusIsError = true
                }
            }
        }
    }

    private func applyAllCurveOffsets() {
        let offsets = curveOffsets
        coStatusMessage = nil
        Task.detached(priority: .userInitiated) {
            var firstError: kern_return_t = KERN_SUCCESS
            var applied = 0
            for (core, offset) in offsets.enumerated() {
                let status = ProcessorModel.shared.setCurveOptimizerOffset(core: UInt8(core), offset: offset)
                if status == KERN_SUCCESS {
                    applied += 1
                } else if firstError == KERN_SUCCESS {
                    firstError = status
                }
            }
            // Snapshot before hopping actors so the concurrent closure captures
            // immutable lets (Swift 6 sendable-safe).
            let reportError = firstError
            let reportApplied = applied
            await MainActor.run {
                if reportError == KERN_SUCCESS {
                    coStatusMessage = "Applied \(reportApplied) cores"
                    coStatusIsError = false
                } else {
                    reloadCurveOffsets()
                    coStatusMessage = curveOptimizerError(reportError)
                    coStatusIsError = true
                }
            }
        }
    }

    private func resetCurveOffsets() {
        curveOffsets = [Int8](repeating: 0, count: coCoreCount)
        applyAllCurveOffsets()
    }

    private func reloadCurveOffsets() {
        let raw = ProcessorModel.shared.getCurveOptimizerOffsets()
        if AMDCurveOptimizer.validOffsets(raw, coreCount: coCoreCount) {
            curveOffsets = Array(raw.prefix(coCoreCount))
        } else {
            curveOffsets = [Int8](repeating: 0, count: coCoreCount)
        }
    }

    /// Maps the kext's selector-111 return codes to friendly messages.
    private func curveOptimizerError(_ status: kern_return_t) -> String {
        if status == ProcessorModel.kIOReturnNotPrivilegedCode {
            return "Requires root or -amdpnopchk"
        }
        if status == kIOReturnUnsupported { return "Not supported by the kext on this CPU (Vermeer only)" }
        if status == kIOReturnNotReady { return "Blocked: package temperature above 75 °C" }
        if status == kIOReturnBadArgument { return "Invalid core index" }
        if status == kIOReturnTimeout { return "SMU timeout — try again" }
        if status == kIOReturnBusy { return "SMU busy — try again" }
        return ProcessorModel.privilegeHint(for: status) ?? "Failed (0x\(String(status, radix: 16)))"
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
        let isSelected = presetCtrl.selectedPreset == preset
        return Button {
            applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: preset.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(preset.color)
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
                    .fill(isSelected ? preset.color.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? preset.color.opacity(0.7) : Color.secondary.opacity(0.15),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(gaming.isActive)
    }

    private func applyPreset(_ preset: AMDPowerPreset) {
        presetCtrl.apply(preset)
        Task {
            await controls.syncFromKext()
            await fetchState()
        }
    }

    private func presetSummary(_ preset: AMDPowerPreset) -> String {
        switch preset {
        case .eco: return l10n.amdPower.presetEcoSummary
        case .balance: return l10n.amdPower.presetBalanceSummary
        case .performance: return l10n.amdPower.presetPerformanceSummary
        case .extreme: return l10n.amdPower.presetExtremeSummary
        }
    }

    // presetColor(_:) removed — use preset.color directly from AMDPowerPreset.

    private struct PowerLoadState {
        let kernelAnswered: Bool
        let cpb: [Bool]
        let cppcState: (active: Bool, epp: UInt8)
        let ppm: Bool
        let lpm: Bool
        let profile: ProcessorModel.CPUProfile
        let packet: CPUSensorPacket?
        let generation: AMDCpuGeneration
        let supportsCurveOptimizer: Bool
        let coreCount: Int
        let offsets: [Int8]
        let currentPState: Int?
        let pStateLabels: [String]
    }

    private func fetchState() async {
        isLoading = true
        let worker = Task.detached(priority: .userInitiated) {
            // AUDIT F-27: thread-safe connection check to avoid data races
            let kernelAnswered = ProcessorModel.shared.isConnected
            let cpb = ProcessorModel.shared.getCPB()
            let cppcState: (active: Bool, epp: UInt8) = kernelAnswered
                ? ProcessorModel.shared.getCPPCActiveMode()
                : (active: false, epp: 0)
            let ppm = kernelAnswered ? ProcessorModel.shared.getPPM() : false
            let lpm = kernelAnswered ? ProcessorModel.shared.getLPM() : false
            let profile = await ProcessorModel.shared.cpuProfile
            let packet = ProcessorModel.shared.getTelemetry()
            let family = await ProcessorModel.shared.cpuFamily
            let model = await ProcessorModel.shared.cpuModel
            let physicalCores = await ProcessorModel.shared.physicalCoreCount
            let generation = AMDCpuGeneration.classify(family: family, model: model)
            let supportsCurveOptimizer = AMDCurveOptimizer.supported(family: family, model: model)
            let coreCount = physicalCores > 0 ? min(physicalCores, 32) : 16
            let rawCurveOffsets = supportsCurveOptimizer
                ? ProcessorModel.shared.getCurveOptimizerOffsets()
                : []
            let offsets = AMDCurveOptimizer.validOffsets(rawCurveOffsets, coreCount: coreCount)
                ? Array(rawCurveOffsets.prefix(coreCount))
                : [Int8](repeating: 0, count: coreCount)
            let currentPState: Int?
            let pStateLabels: [String]
            if profile.legacyPstateAllowed {
                currentPState = await ProcessorModel.shared.getPState()
                let clocks = await ProcessorModel.shared.getValidPStateClocks()
                pStateLabels = clocks.enumerated().map { index, clock in
                    String(format: "P%d (%.1f GHz)", index, Double(clock) / 1000.0)
                }
            } else {
                currentPState = nil
                pStateLabels = []
            }

            return PowerLoadState(kernelAnswered: kernelAnswered,
                                   cpb: cpb,
                                   cppcState: cppcState,
                                   ppm: ppm,
                                   lpm: lpm,
                                   profile: profile,
                                   packet: packet,
                                   generation: generation,
                                   supportsCurveOptimizer: supportsCurveOptimizer,
                                   coreCount: coreCount,
                                   offsets: offsets,
                                   currentPState: currentPState,
                                   pStateLabels: pStateLabels)
        }
        let state = await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
        guard !Task.isCancelled else { return }

        await controls.syncFromKext()
        cppcActiveMode = state.cppcState.active
        cppcCurrentEPP = state.cppcState.epp
        cpuProfile = state.profile
        telemetryPacket = state.packet
        coGeneration = state.generation
        coSupported = state.supportsCurveOptimizer
        coCoreCount = state.coreCount
        curveOffsets = state.offsets
        isLoading = false
    }
}

// MARK: - Dedicated Telemetry Subviews (AUDIT F-17)

private struct AmdLiveTelemetrySection: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared

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
                let tempVal = monitor.snapshot.cpuTemperature
                let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                Text(tempVal.map { MetricFormat.temperature($0, unit: unit) } ?? "--")
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
    }
}

private struct AmdGpuTelemetrySection: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
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
                        HStack {
                            Text("Temperature")
                            Spacer()
                            let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                            Text(gpu.temperature > 0 ? MetricFormat.temperature(gpu.temperature, unit: unit) : "--")
                                .font(.system(.body, design: .monospaced))
                        }
                        .foregroundColor(.orange)
                    }
                }
            } header: {
                Text(l10n.amdPower.amdGPUHeader)
            } footer: {
                Text(l10n.amdPower.amdGPUFooter)
            }
        }
    }
}
