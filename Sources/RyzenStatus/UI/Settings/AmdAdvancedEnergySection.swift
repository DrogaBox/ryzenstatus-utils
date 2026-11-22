// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings › AMD Ryzen Power › Advanced energy: boost, PPM/LPM, CC6 idle
/// and the AMD boot arguments the app reads from NVRAM.
struct AmdAdvancedEnergySection: View {
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var bootArgs = AmdBootArgsService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var showCopiedToast = false

    var body: some View {
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

            c6IdleRow
            bootArgRow(title: l10n.amdPower.cppcTitle, icon: "bolt.badge.clock.fill", tint: .blue,
                       active: bootArgs.isCppcActiveEnabled,
                       activeBadge: l10n.amdPower.cppcActiveBadge, inactiveBadge: l10n.amdPower.cppcInactiveBadge,
                       guidance: l10n.amdPower.cppcGuidance)
            bootArgRow(title: l10n.amdPower.pnopchkTitle, icon: "lock.shield.fill", tint: .orange,
                       active: bootArgs.isPnopchkEnabled,
                       activeBadge: l10n.amdPower.pnopchkActiveBadge, inactiveBadge: l10n.amdPower.pnopchkInactiveBadge,
                       guidance: l10n.amdPower.pnopchkGuidance)
            copyBootArgsRow
        } header: {
            Text(l10n.amdPower.advancedEnergyHeader)
        } footer: {
            Text(l10n.amdPower.advancedEnergyFooter)
        }
    }

    /// CC6 idle, switched live through the kext (selector 61).
    private var c6IdleRow: some View {
        let policy = controls.c6Policy
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { policy?.c6On ?? false },
                set: { controls.setC6Idle($0) }
            )) {
                Label(l10n.amdPower.deepCStatesTitle, systemImage: "moon.zzz.fill")
            }
            .disabled(policy?.c6Available != true || gaming.isActive)

            Text(c6Caption(policy))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func c6Caption(_ policy: AMDCStatePolicy?) -> String {
        guard let policy else { return l10n.amdPower.c6IdleUnavailable }
        if policy.forbiddenByBootArg { return l10n.amdPower.c6IdleForbidden }
        if !policy.c6Available { return l10n.amdPower.c6IdleUnavailable }
        return l10n.amdPower.c6IdleCaption
    }

    private func bootArgRow(title: String, icon: String, tint: Color, active: Bool,
                            activeBadge: String, inactiveBadge: String, guidance: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(active ? activeBadge : inactiveBadge)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(active ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill((active ? Color.green : Color.secondary).opacity(0.12)))
            }
            Text(guidance)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// One-click copy of the AMD boot arguments for config.plist.
    private var copyBootArgsRow: some View {
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
                    Text(l10n.amdPower.copiedToastText + " " + bootArgs.amdBootArgsString)
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
                    bootArgs.copyAmdArgsToClipboard()
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
    }
}

/// Adaptive power limit switch and target (Settings › AMD Ryzen Power,
/// below Auto EPP). Desktop parts with PPT/TDC/EDC only.
struct AdaptivePowerRow: View {
    @ObservedObject private var adaptive = AdaptivePowerService.shared
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var enabled = AdaptivePowerService.shared.isEnabled
    @State private var target = Double(AdaptivePowerService.shared.targetCelsius)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(l10n.amdPower.adaptiveToggle, isOn: Binding(
                get: { enabled },
                set: { enabled = $0; adaptive.setEnabled($0) }
            ))
            .disabled(!controls.powerCapabilities.contains(.pptTdcEdcLimits))
            if enabled {
                HStack {
                    Text(l10n.amdPower.adaptiveTargetLabel)
                        .font(.caption)
                    Slider(value: $target,
                           in: Double(AdaptivePowerPolicy.targetRange.lowerBound)...Double(AdaptivePowerPolicy.targetRange.upperBound),
                           step: 1) { editing in
                        if !editing { adaptive.setTarget(celsius: Int(target)) }
                    }
                    Text("\(Int(target)) °C")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                if let limit = adaptive.currentLimitW {
                    Text(String(format: l10n.amdPower.adaptiveCurrentFormat, limit))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text(l10n.amdPower.adaptiveCaption)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Idle clock limit (Settings › AMD Ryzen Power, below Auto EPP): the CPPC
/// max clock while Auto EPP holds Eco, Linux amd-pstate's scaling_max_freq
/// applied only at idle. CPUs whose kext reports a CPPC range only.
struct IdleClockLimitRow: View {
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var range: AMDCppcRange?
    @State private var limitMHz = Double(AmdSettingsStore.shared.autoEppIdleClockLimitMHz)

    var body: some View {
        let bounds = range?.idleLimitRangeMHz
        VStack(alignment: .leading, spacing: 4) {
            Toggle(l10n.amdPower.idleClockToggle, isOn: Binding(
                get: { limitMHz > 0 && bounds != nil },
                set: { on in
                    guard let bounds, let range else { return }
                    // Starts at the efficient minimum, where amd-pstate puts
                    // its default floor.
                    let start = range.mhz(perf: range.lowestNonlinear) ?? bounds.lowerBound
                    store(on ? Double(min(max(start, bounds.lowerBound), bounds.upperBound)) : 0)
                }
            ))
            .disabled(bounds == nil || !autoEpp.isActive)

            if let bounds, limitMHz > 0 {
                HStack {
                    Slider(value: $limitMHz,
                           in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                           step: 25) {
                        Text(l10n.amdPower.idleClockToggle)
                    } minimumValueLabel: {
                        Text(Self.clock(bounds.lowerBound)).font(.caption2)
                    } maximumValueLabel: {
                        Text(Self.clock(bounds.upperBound)).font(.caption2)
                    } onEditingChanged: { editing in
                        if !editing { store(limitMHz) }
                    }
                    .labelsHidden()
                    .disabled(!autoEpp.isActive)
                    Text(Self.clock(Int(limitMHz)))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }

            Text(caption(bounds: bounds))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refresh)
        .onChange(of: autoEpp.currentTarget) { _, _ in refresh() }
    }

    private func refresh() {
        range = autoEpp.currentCppcRange()
    }

    private func store(_ mhz: Double) {
        limitMHz = mhz
        AmdSettingsStore.shared.autoEppIdleClockLimitMHz = Int(mhz)
    }

    private func caption(bounds: ClosedRange<Int>?) -> String {
        guard bounds != nil, let range,
              let low = range.mhz(perf: range.lowest),
              let efficient = range.mhz(perf: range.lowestNonlinear),
              let base = range.mhz(perf: range.nominal)
        else { return l10n.amdPower.idleClockUnavailable }
        let lead = autoEpp.isActive ? l10n.amdPower.idleClockCaption : l10n.amdPower.idleClockNeedsAutoEpp
        let cpu = String(format: l10n.amdPower.idleClockRangeFormat,
                         Self.clock(low), Self.clock(efficient), Self.clock(base))
        return lead + " " + cpu
    }

    /// 400 MHz, 1.2 GHz, 3.2 GHz.
    static func clock(_ mhz: Int) -> String {
        if mhz < 1000 { return "\(mhz) MHz" }
        let ghz = Double(mhz) / 1000
        return ghz.formatted(.number.precision(.fractionLength(1...2))) + " GHz"
    }
}

/// On battery (Settings › AMD Ryzen Power, below the idle clock limit): what
/// Auto EPP does while a laptop runs on its battery. Shown only on a Mac
/// with an internal battery; it needs Auto EPP (a manual energy profile is
/// the user's own choice and is left alone) and a kext that applies EPP.
struct BatteryPowerRow: View {
    @ObservedObject private var battery = BatteryPowerService.shared
    @ObservedObject private var autoEpp = AutoEppService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let s = l10n.amdPower
        VStack(alignment: .leading, spacing: 4) {
            Picker(s.batteryModeTitle, selection: Binding(
                get: { battery.mode },
                set: { battery.setMode($0) }
            )) {
                ForEach(AMDBatteryPowerMode.allCases) { mode in
                    Text(Self.label(mode, s)).tag(mode)
                }
            }
            .disabled(!autoEpp.writesTakeEffect || !autoEpp.isActive)

            Text(caption(s))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ s: AMDPowerFeatureStrings) -> String {
        guard autoEpp.writesTakeEffect else { return s.batteryModeUnavailable }
        guard autoEpp.isActive else { return s.batteryModeNeedsAutoEpp }
        switch battery.mode {
        case .sameAsPluggedIn: return s.batteryModeSameCaption
        case .saveMore: return s.batteryModeSaveMoreCaption
        case .maximumSaving: return s.batteryModeMaximumCaption
        }
    }

    static func label(_ mode: AMDBatteryPowerMode, _ s: AMDPowerFeatureStrings) -> String {
        switch mode {
        case .sameAsPluggedIn: return s.batteryModeSame
        case .saveMore: return s.batteryModeSaveMore
        case .maximumSaving: return s.batteryModeMaximum
        }
    }
}
