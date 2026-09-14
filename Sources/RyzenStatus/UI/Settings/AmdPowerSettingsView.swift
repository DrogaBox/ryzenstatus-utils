// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdPowerSettingsView: View {
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @State private var cpuProfile = ProcessorModel.CPUProfile()
    @State private var cppcActiveMode: Bool = false
    @State private var cppcCurrentEPP: UInt8 = 0
    @State private var telemetryPacket: CPUSensorPacket?
    // PM-table export status
    @State private var pmStatusMessage: String?
    @State private var pmStatusIsError = false
    @State private var isLoading = false
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var c6Service = C6ResidencyService.shared

    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var presetCtrl = AmdPresetController.shared
    @ObservedObject private var nvramCState = CStateNvramService.shared
    @ObservedObject private var l10n = L10n.shared
    // AMD Polish S2-T4: kext-resolved C-state runtime policy (selector 34,
    // selector-22 fallback). nil = kext unreachable.
    @State private var c6RuntimeDisabled: Bool?
    @State private var c6RuntimeAddr: UInt64 = 0
    @State private var showCopiedToast = false

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 25
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50

    private var eppLabel: String {
        switch AMDPowerPreset.snapEPP(controls.selectedEpp) {
        case 0:   return l10n.amdPower.perfMax
        case 85:  return l10n.amdPower.perfBalPlus
        case 170: return l10n.amdPower.perfBalMinus
        default:  return l10n.amdPower.perfEco
        }
    }

    // Move 1 Hz live telemetry out of the root Form into focused
    // subviews so the 1,000-line controls and settings tree does not re-render each second.

    var body: some View {
        Form {
            AmdLiveTelemetrySection()

            if isLoading {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(l10n.amdPower.loadingControls)
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
                            Text(l10n.amdPower.telemetryPacketSelectorTitle)
                                .font(.subheadline)
                            Spacer()
                            Text("\(CPUSensorPacket.byteSize) B")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text(l10n.amdPower.packagePowerLabel)
                            Spacer()
                            Text(String(format: "%.1f W", packet.packagePowerW))
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text(l10n.amdPower.packageTempLabel)
                            Spacer()
                            let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                            Text(MetricFormat.temperature(Double(packet.packageTempC), unit: unit))
                                .font(.system(.body, design: .monospaced))
                        }
                        // S2-T5: two telemetry sources can momentarily disagree;
                        // label each section's source so readers know which is which.
                        Text(l10n.amdPower.telemetrySourcePacket)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if packet.ccdCount > 0 {
                            HStack {
                                Text(String(format: l10n.amdPower.ccdCountFormat, Int(packet.ccdCount)))
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
                                Text(String(format: l10n.amdPower.telemetryCoreFreqFormat, freqs.count))
                                Spacer()
                                Text(String(format: "%.0f / %.0f / %.0f MHz",
                                           freqs.min() ?? 0,
                                           freqs.reduce(0, +) / Float(freqs.count),
                                           freqs.max() ?? 0))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } header: {
                        Text(l10n.amdPower.telemetryPacketHeader)
                    } footer: {
                        Text(l10n.amdPower.telemetryPacketFooter)
                    }
                }

                // AMD GPU — dedicated GPU telemetry from the kext (selectors 27-30).
                // Hidden entirely when no AMD discrete GPU is detected (iGPU/NVIDIA).
                AmdGpuTelemetrySection()

                // S4-T1: Dedicated navigation banner to AMD Overclocking & PBO Tuning
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AMD Overclocking & PBO Tuning")
                                .font(.headline)
                            Text("Precision Boost Overdrive, Curve Optimizer per-core undervolting, cHTC limit, and frequency overrides.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            SettingsRouter.shared.page = .amdOverclocking
                        } label: {
                            Label("Open Overclocking", systemImage: "arrow.forward.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.vertical, 4)
                }

                // SMU PM-table plumbing diagnostics (0x05/0x06/0x08).
                // Read-only: the kext's timer captures the SMU's metrics
                // table into a snapshot buffer; this section surfaces the
                // version/size/base info and a bug-report export.
                Section {
                    if !controls.pmTableVersionPolled {
                        Label(l10n.amdPower.pmTableUnavailable, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack {
                            Text(l10n.amdPower.pmTableVersionLabel)
                            Spacer()
                            Text(AMDSmuPMTable.formatVersion(controls.pmTableVersionRaw))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text(l10n.amdPower.pmTableSizeLabel)
                            Spacer()
                            Text(controls.pmTableSizeBytes > 0
                                 ? "\(controls.pmTableSizeBytes) B"
                                 : l10n.amdPower.pmTableUnknownVersion)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(controls.pmTableSizeBytes > 0 ? .primary : .orange)
                        }
                        if controls.pmTableValid {
                            HStack {
                                Text(l10n.amdPower.pmTableCaptureLabel)
                                Spacer()
                                Text("\(controls.pmTableAgeMs / 1000)s")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            Button {
                                exportPMTable()
                            } label: {
                                Label(l10n.amdPower.pmTableExport, systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            // Run the mailbox health probes and copy a
                            // paste-able diagnostics bundle. Privileged — the
                            // kext refuses without root/-amdpnopchk.
                            Button {
                                Task { await controls.runMailboxDiagnostics() }
                                let bundle = controls.buildDiagnosticsBundle()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bundle, forType: .string)
                                pmStatusMessage = l10n.amdPower.diagBundleCopied
                                pmStatusIsError = false
                            } label: {
                                Label(l10n.amdPower.diagBundleButton, systemImage: "stethoscope")
                            }
                            .buttonStyle(.bordered)
                            if controls.smuDiagnosticsDenied {
                                Label(l10n.amdPower.diagBundleDenied, systemImage: "lock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else if let diag = controls.smuDiagnostics {
                                Text(AMDSmuDiagnostics.line(for: diag))
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundColor(AMDSmuDiagnostics.decodeHealthy(diag) ? .green : .orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let message = pmStatusMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundColor(pmStatusIsError ? .red : .green)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // Decoded live rows. Only for known table
                            // layouts — unknown versions keep the raw-export-only
                            // behavior, fail closed.
                            if let decoded = controls.pmTableDecoded {
                                Divider()
                                pmTablePackageRows(decoded.summary)
                                Divider()
                                pmTableCoreRows(decoded.cores)
                                if !decoded.l3.isEmpty {
                                    Divider()
                                    pmTableL3Rows(decoded.l3)
                                }
                            } else {
                                Text(l10n.amdPower.pmTableUnknownVersion)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text(l10n.amdPower.pmTableHeader)
                } footer: {
                    Text(l10n.amdPower.pmTableFooter)
                }



                if controls.cppcSupported {
                    Section {
                        Toggle(l10n.amdPower.autoEppToggle, isOn: Binding(
                            get: { autoEpp.isActive },
                            set: { autoEpp.setCPPCActive($0) }
                        ))

                        if autoEpp.isActive {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(l10n.amdPower.cpuLoadLabel)
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
                                    Text(autoEpp.isActive ? l10n.amdPower.autoBadge : eppLabel)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(autoEpp.isActive ? .secondary : .cyan)
                                    Spacer()
                                    if !autoEpp.isActive {
                                        Text(l10n.amdPower.manualBadge)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                            // CPPC info (selector 23): active mode + raw EPP value.
                            HStack {
                                Image(systemName: cppcActiveMode ? "bolt.fill" : "bolt.slash")
                                    .font(.caption)
                                    .foregroundColor(cppcActiveMode ? .green : .secondary)
                                Text(cppcActiveMode ? l10n.amdPower.cppcActiveOn : l10n.amdPower.cppcActiveOff)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: l10n.amdPower.eppValueFormat, cppcCurrentEPP))
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
                                Text(l10n.amdPower.perfMax).tag(UInt8(0))
                                Text(l10n.amdPower.perfBalPlus).tag(UInt8(85))
                                Text(l10n.amdPower.perfBalMinus).tag(UInt8(170))
                                Text(l10n.amdPower.perfEco).tag(UInt8(255))
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .disabled(autoEpp.isActive || gaming.isActive)
                        }
                        .padding(.vertical, 8)
                        .opacity(autoEpp.isActive || gaming.isActive ? 0.5 : 1.0)
                    } header: {
                        Text(l10n.amdPower.cppcSectionHeader)
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
                        Text(l10n.amdPower.legacyPstatesHeader)
                    } footer: {
                        Text(L10n.shared.amdPower.legacyPStatesFooter)
                    }
                }
                Section {
                    if controls.cpbSupported {
                        Toggle(l10n.amdPower.cpbToggle, isOn: Binding(
                            get: { controls.corePerformanceBoost },
                            set: { controls.setCPB($0) }
                        ))
                        .disabled(gaming.isActive)
                    }

                    Toggle(l10n.amdPower.ppmToggle, isOn: Binding(
                        get: { controls.ppmEnabled },
                        set: { controls.setPPM($0) }
                    ))
                    .disabled(gaming.isActive)

                    Toggle(l10n.amdPower.lpmToggle, isOn: Binding(
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

                        // S2-T4: kext-resolved runtime policy + NVRAM drift warning.
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(.indigo)
                                .font(.caption)
                            Text(l10n.amdPower.c6RuntimeRowTitle)
                                .font(.subheadline)
                            Spacer()
                            switch c6RuntimeDisabled {
                            case .some(true):
                                Text(l10n.amdPower.runtimeC6DisabledBadge)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                            case .some(false):
                                Text(l10n.amdPower.runtimeC6EnabledBadge)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.12)))
                            case .none:
                                Text("--")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let runtime = c6RuntimeDisabled, runtime != nvramCState.isC6Enabled {
                            // amdcstate in boot-args says one thing, the running
                            // kext does another: stale boot-args vs pre-feature
                            // kext (older than 1.21.0). Drift must be visible.
                            Label(l10n.amdPower.c6DriftWarning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

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
            if let policy = ProcessorModel.shared.getCStatePolicy() {
                c6RuntimeDisabled = policy.disabled
                c6RuntimeAddr = policy.addr
            } else {
                c6RuntimeDisabled = nil
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await controls.syncFromKext()
            }
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
        .onReceive(nvramCState.$isC6Enabled) { _ in
            // Re-resolve runtime policy when the NVRAM badge refreshes so the
            // drift warning flips without leaving the settings page.
            Task {
                if let policy = ProcessorModel.shared.getCStatePolicy() {
                    c6RuntimeDisabled = policy.disabled
                    c6RuntimeAddr = policy.addr
                }
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

    /// Package-level rows decoded from the PM-table snapshot. Monospace
    /// Technical labels, no localization — same convention as the info
    /// rows above (version/size render without locale strings).
    private func pmTablePackageRows(_ s: AMDSmuPMTable.Summary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            pmTablePair("PPT", String(format: "%6.1f / %.0f W", s.pptValueW, s.pptLimitW))
            pmTablePair("TDC", String(format: "%6.1f / %.0f A", s.tdcValueA, s.tdcLimitA))
            pmTablePair("EDC", String(format: "%6.1f / %.0f A", s.edcValueA, s.edcLimitA))
            pmTablePair("THM", String(format: "%.0f C limit", s.thmLimitC))
            pmTablePair("Core V", String(format: "%.3f V", s.coreVoltageV))
            pmTablePair("Socket", String(format: "%6.1f W", s.socketPowerW))
            pmTablePair("FCLK/UCLK/MEM", String(format: "%.0f / %.0f / %.0f MHz", s.fclkMHz, s.uclkMHz, s.memclkMHz))
            pmTablePair("Peak temp", String(format: "%.1f C", s.peakTempC))
            if s.pc6Percent > 0 {
                pmTablePair("PC6", String(format: "%.1f %%", s.pc6Percent))
            }
        }
    }

    /// Per-core grid — two cores per row to keep the section compact.
    private func pmTableCoreRows(_ cores: [AMDSmuPMTable.CoreRow]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Cores (Effective Clock / CC6)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Effective Clock = active rate × C0%")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)
            ForEach(0..<(cores.count + 1) / 2, id: \.self) { pair in
                HStack(spacing: 12) {
                    pmTableCell(cores[pair * 2])
                    if pair * 2 + 1 < cores.count {
                        pmTableCell(cores[pair * 2 + 1])
                    }
                }
            }
        }
    }

    private func pmTableCell(_ c: AMDSmuPMTable.CoreRow) -> some View {
        let sleeping = c.isSleeping && c.isPresent
        return HStack(spacing: 5) {
            Text(String(format: "C%02d", c.slot))
                .foregroundColor(c.isPresent ? .primary : .secondary)
            Text(sleeping
                 ? String(format: "   park  %5.1f W", c.powerW)
                 : String(format: "%5.0f MHz %5.1f W %4.1f C", c.freqMHz, c.powerW, c.tempC))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(c.isPresent ? (sleeping ? .secondary : .primary) : .secondary)
            if !c.isPresent { Text("off").font(.caption2).foregroundColor(.secondary) }
        }
    }

    /// L3 (GameCache) rows decoded from the PM-table snapshot — one
    /// compact line per cache. Monospace technical labels, same convention
    /// as the package/core rows (raw telemetry renders without locale
    /// strings).
    private func pmTableL3Rows(_ l3: [AMDSmuPMTable.L3Row]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(l3, id: \.id) { row in
                HStack(spacing: 5) {
                    Text("L3[\(row.id)]")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%4.0f MHz  %4.1f C  %4.2f + %.2f W  EDC %.0f A",
                                row.freqEffMHz, row.tempC, row.logicPowerW, row.vddmPowerW, row.edcLimitA))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private func pmTablePair(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    /// Export the PM-table snapshot via a save panel (bug-report
    /// capture). Runs the privileged force-capture first so the exported
    /// bytes are as fresh as the kext can make them.
    private func exportPMTable() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        let v = controls.pmTableVersionRaw
        let versionPart = AMDSmuPMTable.formatVersion(v).replacingOccurrences(of: ".", with: "")
        panel.nameFieldStringValue = "pmtable_\(versionPart)_size\(controls.pmTableSizeBytes).bin"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let captured = ProcessorModel.shared.forcePMTableCapture()
            guard captured == KERN_SUCCESS, let data = ProcessorModel.shared.getPMTableSnapshot() else {
                pmStatusIsError = true
                pmStatusMessage = "PM table capture failed"
                return
            }
            do {
                try data.write(to: url)
                pmStatusIsError = false
                pmStatusMessage = nil
            } catch {
                pmStatusIsError = true
                pmStatusMessage = "Export failed"
            }
        }
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
        // S2-T1: presets rewrite EPP; don't fight Auto EPP (same gate as the
        // segmented EPP picker in this view).
        guard !autoEpp.isActive else { return }
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
        let currentPState: Int?
        let pStateLabels: [String]
    }

    private func fetchState() async {
        isLoading = true
        let worker = Task.detached(priority: .userInitiated) {
            let kernelAnswered = ProcessorModel.shared.isConnected
            let cpb = ProcessorModel.shared.getCPB()
            let cppcState: (active: Bool, epp: UInt8) = kernelAnswered
                ? ProcessorModel.shared.getCPPCActiveMode()
                : (active: false, epp: 0)
            let ppm = kernelAnswered ? ProcessorModel.shared.getPPM() : false
            let lpm = kernelAnswered ? ProcessorModel.shared.getLPM() : false
            let profile = await ProcessorModel.shared.cpuProfile
            let packet = ProcessorModel.shared.getTelemetry()

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
        isLoading = false
    }
}

// MARK: - Dedicated Telemetry Subviews

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
        Section {
            HStack {
                Text(l10n.amdPower.packagePowerLabel)
                Spacer()
                Text(String(format: "%.1f W", monitor.snapshot.cpuPower ?? 0))
                    .font(.system(.body, design: .monospaced))
            }
            HStack {
                Text(l10n.amdPower.packageTempLabel)
                Spacer()
                let tempVal = monitor.snapshot.cpuTemperature
                let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                Text(tempVal.map { MetricFormat.temperature($0, unit: unit) } ?? "--")
                    .font(.system(.body, design: .monospaced))
            }
            // S2-T5: source caption — this section reads SystemMonitor's poll.
            Text(l10n.amdPower.telemetrySourceMonitor)
                .font(.caption2)
                .foregroundColor(.secondary)

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
        } header: {
            Text(l10n.s.amdRyzenProcessorInfo)
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
                    VStack(alignment: .leading, spacing: 4) {
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
                        }
                        HStack {
                            Text(l10n.amdPower.gpuTempRowLabel)
                            Spacer()
                            let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
                            Text(gpu.temperature > 0 ? MetricFormat.temperature(gpu.temperature, unit: unit) : "--")
                                .font(.system(.body, design: .monospaced))
                        }
                        .foregroundColor(.orange)
                        .padding(.leading, 20)
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
