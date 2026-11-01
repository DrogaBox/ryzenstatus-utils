// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct AmdControlSection: View {
    let collapsible: Bool

    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var presetCtrl = AmdPresetController.shared
    @ObservedObject private var fanController = FanCurveController.shared
    @State private var showThresholds: Bool = false

    // Fan state: the fan controller reads the headers; this row registers
    // for its live poll while it is expanded and on screen.
    @State private var selectedFanId: Int = 0
    @State private var isPollingFans = false

    @AppStorage(DefaultsKey.autoEppIdleThreshold) private var idleThreshold: Int = 25
    @AppStorage(DefaultsKey.autoEppLoadThreshold) private var loadThreshold: Int = 50
    @AppStorage(DefaultsKey.showFansInAmdPower) private var showFansInAmdPower = false
    // Per-core PM-table telemetry disclosure in the panel (persisted).
    @AppStorage(DefaultsKey.showPmTableCoresInPanel) private var showPmTableCores = false
    // Optional per-core columns, each persisted independently.
    @AppStorage(DefaultsKey.showPmCoreVoltage) private var showsPmCoreVoltage = false
    @AppStorage(DefaultsKey.showPmCoreC0) private var showsPmCoreC0 = false
    @AppStorage(DefaultsKey.showPmCoreCC6) private var showsPmCoreCC6 = false

    /// The picker value shown, nil (unselected) while nothing true can be.
    private var shownEpp: UInt8? {
        AutoEppPolicy.shownEPP(writesTakeEffect: autoEpp.writesTakeEffect,
                               autoActive: autoEpp.isActive,
                               autoEPP: autoEpp.currentEPP,
                               manualEPP: controls.selectedEpp)
    }
    private var eppLabel: String {
        if autoEpp.isActive {
            return autoEpp.currentTarget.isEmpty ? "…" : autoEpp.currentTarget
        }
        switch shownEpp {
        case nil: return "…"
        case 0:   return L10n.shared.amdPower.perfMax
        case 85:  return L10n.shared.amdPower.perfBalPlus
        case 170: return L10n.shared.amdPower.perfBalMinus
        default:  return L10n.shared.amdPower.perfEco
        }
    }

    private var eppColor: Color {
        if autoEpp.isActive { return .secondary }
        switch shownEpp {
        case nil: return .secondary
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

    /// Package power is drawn against the PPT limit when the PM table
    /// reports it (the same scale as the dashboard), so a full column means
    /// the CPU is at its limit. Without the table the busiest sample,
    /// rounded up to 25 W, sets the scale.
    private var packagePowerCeiling: Double {
        if let ppt = controls.pmTableDecoded?.summary.pptLimitW, ppt.isFinite, ppt > 0 {
            return max(60, Double(ppt) * 1.05)
        }
        let peak = controls.packagePowerHistory.filter(\.isFinite).max() ?? 0
        return ColumnGraphGeometry.roundedCeiling(peak: peak, step: 25, minimum: 50)
    }

    var body: some View {
        PanelSection(.amdPower, title: L10n.shared.amdPower.sidebarTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 18) {
                if !visibleFans.isEmpty {
                    DisclosureGroup(isExpanded: $showFansInAmdPower) {
                        HStack {
                            Picker(L10n.shared.amdPower.panelSmcFanControl, selection: $selectedFanId) {
                                ForEach(visibleFans) { fan in
                                    Text(fan.effectiveDisplayName).tag(fan.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            // S2-T1: 80 pt truncated hardware names like "CPU Fan 0".
                            .frame(width: 130)

                            Spacer()

                            Text(selectedFanRpmText)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                        }
                    } label: {
                        Text(L10n.shared.amdPower.panelSmcFanControl)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .disclosureHeader(isExpanded: $showFansInAmdPower)
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

                        // S2-T2: package power / temp history from the 3 s
                        // sync (no new timers, no extra kext traffic), drawn
                        // as columns on steady scales so a flat reading sits
                        // where it belongs instead of hugging the top.
                        if controls.packagePowerHistory.count >= 2 {
                            HStack(spacing: 10) {
                                AmdHistoryGraph(label: L10n.shared.amdPower.packagePowerLabel,
                                                values: controls.packagePowerHistory,
                                                ceiling: packagePowerCeiling,
                                                ink: .primary,
                                                format: { String(format: "%.0f W", $0) })
                                AmdHistoryGraph(label: L10n.shared.amdPower.packageTempLabel,
                                                values: controls.packageTempHistory,
                                                ceiling: ColumnGraphGeometry.roundedCeiling(
                                                    peak: controls.packageTempHistory.filter(\.isFinite).max() ?? 0,
                                                    step: 10, minimum: 100),
                                                ink: .secondary,
                                                format: { String(format: "%.0f °C", $0) })
                            }
                        }

                        // Live per-core SMU PM-table telemetry (clocks,
                        // temps, power) decoded from the kext's 1 Hz snapshot
                        // and refreshed by the same 3 s sync as everything else
                        // in this section — no extra timers, no extra kext
                        // traffic. Hidden on old kexts / undecoded table versions.
                        if let decoded = controls.pmTableDecoded {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { showPmTableCores.toggle() }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: showPmTableCores ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Text(L10n.shared.amdPower.panelPmTableCores)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        // At-a-glance package state while collapsed.
                                        Text(String(format: "%.0f W · %.0f °C", decoded.summary.socketPowerW, decoded.summary.thmValueC))
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if showPmTableCores {
                                    // Per-field column toggles — icon-only and
                                    // language-neutral (tooltips carry the meaning),
                                    // matching the section's technical-label convention.
                                    HStack(spacing: 12) {
                                        pmColumnToggle("bolt.fill", color: .yellow,
                                                       isOn: $showsPmCoreVoltage,
                                                       help: L10n.shared.amdPower.pmVoltageHelp)
                                        pmColumnToggle("cpu", color: .green,
                                                       isOn: $showsPmCoreC0,
                                                       help: L10n.shared.amdPower.pmC0Help)
                                        pmColumnToggle("moon.zzz.fill", color: .purple,
                                                       isOn: $showsPmCoreCC6,
                                                       help: L10n.shared.amdPower.pmCC6Help)
                                        Spacer()
                                    }
                                    .padding(.leading, 2)
                                    // UX fix: bounded core list. Unbounded, 16 rows
                                    // grew the panel past the screen below the status
                                    // item, and macOS re-anchored the whole popover to
                                    // the side of the icon. Taller than the cap ⇒ the
                                    // list scrolls internally; the frame height is
                                    // computed from the row count, so the expand
                                    // animation stays deterministic (no measurement
                                    // pass, no second reflow).
                                    let presentCores = decoded.cores.filter { $0.isPresent }
                                    let listCap = min(320.0, max(160.0, ((PanelInteractionState.shared.anchorScreen ?? NSScreen.main)?.visibleFrame.height ?? 760) * 0.3))
                                    ScrollView(.vertical, showsIndicators: true) {
                                        VStack(spacing: 2) {
                                            ForEach(presentCores, id: \.slot) { core in
                                                AmdPmTableCoreRowView(core: core,
                                                                      clockHistory: controls.pmCoreClockHistory[core.slot],
                                                                      tempHistory: controls.pmCoreTempHistory[core.slot],
                                                                      showsVoltage: showsPmCoreVoltage,
                                                                      showsC0: showsPmCoreC0,
                                                                      showsCC6: showsPmCoreCC6)
                                            }
                                        }
                                    }
                                    .frame(height: min(listCap, CGFloat(presentCores.count) * 17 + 2))
                                    .transition(.opacity.combined(with: .move(edge: .top)))

                                    // One compact row per L3 cache (temp +
                                    // effective clock only — the 308 pt row budget is
                                    // nearly full; full fields live in Settings and
                                    // the tooltip).
                                    ForEach(decoded.l3, id: \.id) { l3 in
                                        HStack(spacing: 6) {
                                            Text(l3.id == 0 ? "L3" : String(format: "L3%d", l3.id))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(.secondary.opacity(0.6))
                                                .frame(width: 18, alignment: .leading)
                                            Text(String(format: "%.0f MHz", l3.freqEffMHz))
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .frame(width: 46, alignment: .leading)
                                            Text(String(format: "%.1f °C", l3.tempC))
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .trailing)
                                            Spacer(minLength: 0)
                                            Text(String(format: "%.1f W", l3.logicPowerW + l3.vddmPowerW))
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 38, alignment: .trailing)
                                        }
                                        .help(String(format: L10n.shared.amdPower.l3HelpFormat,
                                                     l3.id, l3.freqEffMHz, l3.tempC, l3.logicPowerW, l3.vddmPowerW, l3.edcLimitA))
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        VStack(spacing: 8) {
                            // Unselected (nil) while the kext ignores EPP or
                            // Auto EPP has not applied a value yet.
                            Picker(L10n.shared.amdPower.energyProfileManual, selection: Binding<UInt8?>(
                                get: { shownEpp },
                                set: { if let value = $0 { controls.setEPP(value) } }
                            )) {
                                Text(L10n.shared.amdPower.perfMaxShort).tag(UInt8?.some(0))
                                Text(L10n.shared.amdPower.perfBalPlusShort).tag(UInt8?.some(85))
                                Text(L10n.shared.amdPower.perfBalMinusShort).tag(UInt8?.some(170))
                                Text(L10n.shared.amdPower.perfEcoShort).tag(UInt8?.some(255))
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .disabled(autoEpp.isActive || gaming.isActive)
                        }
                        .opacity(autoEpp.isActive || gaming.isActive ? 0.4 : 1.0)

                        // The picker, Auto EPP and the presets' EPP do not
                        // reach the CPU while the kext ignores EPP writes.
                        if !autoEpp.writesTakeEffect {
                            Text(L10n.shared.amdPower.eppNotApplied)
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if gaming.isActive {
                            Text(L10n.shared.amdPower.panelManagedByGamingMode)
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
                                        Text(String(format: L10n.shared.amdPower.panelThresholdsSummaryFormat, idleThreshold, loadThreshold))
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

                            Text(L10n.shared.amdPower.panelLegacyProfiles)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.cyan)

                            Text(L10n.shared.amdPower.panelPstateOverrides)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            if !controls.validPStateLabels.isEmpty {
                                Picker(L10n.shared.amdPower.panelLegacyProfiles, selection: Binding(
                                    get: { controls.selectedPState },
                                    set: { controls.setPState($0) }
                                )) {
                                    ForEach(0..<controls.validPStateLabels.count, id: \.self) { idx in
                                        Text(controls.validPStateLabels[idx]).tag(idx)
                                    }
                                }
                                .labelsHidden()
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
                                Toggle(L10n.shared.amdPower.autoEppToggle, isOn: Binding(
                                    get: { autoEpp.isActive },
                                    set: { autoEpp.setEnabled($0) }
                                ))
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                    // Not switched on with neither EPP nor
                                    // boost to drive.
                                    .disabled(gaming.isActive
                                              || (!autoEpp.canRun && !autoEpp.isActive))
                            }
                        }

                        if controls.cpbSupported {
                            HStack {
                                Image(systemName: "flame.fill").foregroundColor(.orange).frame(width: 20)
                                Toggle(L10n.shared.amdPower.panelCpbToggle, isOn: Binding(
                                    get: { controls.corePerformanceBoost },
                                    set: { controls.setCPB($0) }
                                ))
                                    .font(.system(size: 12))
                                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                                    // Auto EPP switches boost while it is on.
                                    .disabled(gaming.isActive)
                            }
                        }

                        HStack {
                            Image(systemName: "speedometer").foregroundColor(.teal).frame(width: 20)
                            Toggle(L10n.shared.amdPower.panelPpmToggle, isOn: Binding(
                                get: { controls.ppmEnabled },
                                set: { controls.setPPM($0) }
                            ))
                                .font(.system(size: 12))
                                .toggleStyle(SwitchToggleStyle(tint: .teal))
                                .disabled(gaming.isActive)
                        }

                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundColor(.purple).frame(width: 20)
                            Toggle(L10n.shared.amdPower.panelLpmLimit, isOn: Binding(
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
            // The same rounded card every other panel section sits in.
            .panelCard()
            .onAppear {
                // The model runs one 3 s loop for every view that shows it.
                controls.beginLiveSync()
                setFanPolling(showFansInAmdPower)
                keepFanSelectionVisible()
            }
            .onDisappear {
                controls.endLiveSync()
                setFanPolling(false)
            }
            .onChange(of: showFansInAmdPower) { _, expanded in
                setFanPolling(expanded)
            }
            .onChange(of: visibleFans.map(\.id)) { _, _ in
                keepFanSelectionVisible()
            }
        }
    }

    private var visibleFans: [FanState] {
        fanController.fans.filter { !$0.isHidden }
    }

    /// The picked fan's speed, or a dash while the reading cannot be trusted
    /// (an implausible or frozen tachometer).
    private var selectedFanRpmText: String {
        guard let fan = visibleFans.first(where: { $0.id == selectedFanId }),
              fan.rpmValid else { return "— RPM" }
        return "\(fan.rpm) RPM"
    }

    /// The picker needs a selection among the fans it lists; a hidden or
    /// vanished fan falls back to the first one shown.
    private func keepFanSelectionVisible() {
        guard !visibleFans.contains(where: { $0.id == selectedFanId }),
              let first = visibleFans.first else { return }
        selectedFanId = first.id
    }

    /// S2-T1: the RPM poll only matters while the fan disclosure is expanded
    /// and on screen — skip it otherwise to avoid needless LPC traffic.
    private func setFanPolling(_ on: Bool) {
        guard on != isPollingFans else { return }
        isPollingFans = on
        if on { fanController.startPolling() } else { fanController.stopPolling() }
    }

    // MARK: - Per-core column toggles (icon-only, language-neutral)

    /// One icon toggle for an optional per-core column. On = colored chip,
    /// off = dim; the meaning lives in the tooltip, the glyph in the row.
    private func pmColumnToggle(_ icon: String, color: Color,
                                isOn: Binding<Bool>, help: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isOn.wrappedValue ? color : .secondary.opacity(0.45))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn.wrappedValue ? color.opacity(0.14) : Color.secondary.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        // The glyph alone says nothing to VoiceOver; the tooltip's words do.
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    // MARK: - Power Presets (menu panel)

    private func presetButton(_ preset: AMDPowerPreset) -> some View {
        let isSelected = presetCtrl.shownPreset == preset
        return Button {
            presetCtrl.apply(preset)
            Task { await controls.syncFromKext() }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 11))
                Text(L10n.shared.amdPower.presetTitle(preset))
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
        // S2-T1: presets also drive EPP, so gate on Auto EPP like the EPP
        // picker above — otherwise the two systems fight over the same MSR.
        .disabled(gaming.isActive || autoEpp.isActive)
    }
}

// MARK: - Package history graph (menu panel)

/// One package reading over the last few minutes: its name and latest value
/// above, the columns below with the scale's top in the corner, the way the
/// sensor graphs elsewhere read.
struct AmdHistoryGraph: View {
    let label: String
    let values: [Double]
    let ceiling: Double
    let ink: GraphInk
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let latest = values.last, latest.isFinite, latest > 0 {
                    Text(format(latest))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(values, ceiling: ceiling)],
                               inks: [ink])
                .frame(height: 26)
                .overlay(alignment: .topLeading) {
                    Text(format(ceiling))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(values.last.map(format) ?? "")
    }
}

// MARK: - Per-core PM-table row (menu panel)

/// One per-core telemetry row for the AMD Power panel section: SMU PM-table
/// effective clock, temperature and power for a single core slot, plus
/// two tiny column graphs fed by rolling windows in `AmdPowerControlsModel`
/// (sampled on the model's 3 s sync tick — no timers here). Monospaced
/// technical fields by design — same convention as the Settings PM Table
/// diagnostics section (raw telemetry renders without localization).
///
/// Width budget: the panel content column is 308 pt and the row must fit
/// with EVERY optional column enabled (~295 pt worst case), so all frames
/// are sized for the longest realistic string at 9 pt monospaced and the
/// C0/CC6 fields share one residency column.
struct AmdPmTableCoreRowView: View {
    let core: AMDSmuPMTable.CoreRow
    /// Rolling windows from the model; nil/short windows render nothing.
    let clockHistory: [Double]?
    let tempHistory: [Double]?
    /// Optional per-core columns, each toggled independently in the section.
    /// Fixed frame widths keep the trailing columns row-aligned while a
    /// column is on; the leading slot/clock/graph group never shifts.
    let showsVoltage: Bool
    let showsC0: Bool
    let showsCC6: Bool

    /// Fixed scales keep rows comparable across slots and over time:
    /// clocks against a ceiling above Vermeer's ~5.15 GHz max boost,
    /// temps against a sane 0–100 °C envelope.
    private static let clockScaleMHz = 5400.0
    private static let tempScaleC = 100.0

    private var tempColor: Color {
        if core.tempC >= 70 { return .red }
        if core.tempC >= 50 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(String(format: "%02d", core.slot))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 14, alignment: .leading)
            // Sleeping cores show a language-neutral dash instead of a clock.
            Text(core.isSleeping ? "—" : String(format: "%.0f MHz", core.freqMHz))
                .font(.system(size: 9, weight: core.isSleeping ? .medium : .semibold, design: .monospaced))
                .foregroundColor(core.isSleeping ? Color.secondary.opacity(0.55) : .cyan)
                .frame(width: 46, alignment: .leading)
            // One-point columns, newest on the right: 28 samples fit, and a
            // sleeping core reads as an empty column rather than a dive.
            VStack(spacing: 1) {
                ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(clockHistory ?? [],
                                                                          ceiling: Self.clockScaleMHz)],
                                   inks: [.primary], columnWidth: 1, spacing: 0, showsBaseline: false)
                    .frame(width: 28, height: 8)
                ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(tempHistory ?? [],
                                                                          ceiling: Self.tempScaleC)],
                                   inks: [.secondary], columnWidth: 1, spacing: 0, showsBaseline: false)
                    .frame(width: 28, height: 8)
            }
            .background(Color.primary.opacity(0.05))
            if showsVoltage {
                Text(String(format: "%.2f V", core.voltageRaw))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.85))
                    .frame(width: 36, alignment: .trailing)
            }
            if showsC0 || showsCC6 {
                HStack(spacing: 3) {
                    if showsC0 {
                        Text(String(format: "C0 %.0f", core.c0Percent))
                            .foregroundColor(.secondary)
                    }
                    if showsCC6 {
                        Text(String(format: "CC6 %.0f", core.cc6Percent))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(width: 78, alignment: .trailing)
            }
            Text(String(format: "%.0f °C", core.tempC))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(tempColor)
                .frame(width: 40, alignment: .trailing)
            Text(String(format: "%.1f W", core.powerW))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .help(String(format: L10n.shared.amdPower.gridCoreFormat, core.slot) + " · "
              + String(format: L10n.shared.amdPower.gridClockValueFormat, core.freqMHz)
              + String(format: " · %.1f °C · %.2f W · C0 %.1f%% · CC6 %.1f%%",
                       core.tempC, core.powerW, core.c0Percent, core.cc6Percent))
    }
}
