// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Dedicated AMD Overclocking & PBO Tuning Settings Page.
/// Separated from AmdPowerSettingsView to isolate high-risk hardware modifications
/// (PBO limits, Curve Optimizer, SMU OC mode, frequency targets, cHTC thermal limit)
/// from everyday energy and monitoring profiles.
struct AmdOverclockingSettingsView: View {
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var l10n = L10n.shared

    @State private var coGeneration = AMDCpuGeneration.unknown
    @State private var coSupported = false
    @State private var coCoreCount = 16
    @State private var curveOffsets: [Int8] = []
    @State private var coStatusMessage: String?
    @State private var coStatusIsError = false

    @State private var pboSupported = false
    @State private var pboCacheMilli: (ppt: Int, tdc: Int, edc: Int)?
    @State private var pboScalarCacheX100: Int?
    @State private var pboPPTWatts: Double = 142
    @State private var pboTDCAmps: Double = 95
    @State private var pboEDCAmps: Double = 140
    @State private var pboScalarTenths: Double = 10  // 1.0x
    @State private var pboStatusMessage: String?
    @State private var pboStatusIsError = false

    // S6: cHTC limit (0x56) — draft slider + applied badge + status message.
    @State private var chtcDraftCelsius: Double = Double(AMDSmuParameters.defaultCHTCCelsius)
    @State private var chtcAppliedCelsius: Int?
    @State private var chtcStatusMessage: String?
    @State private var chtcStatusIsError = false
    @State private var chtcSeeded = false

    // S8: OC mode — status message + reset-scalar draft.
    @State private var ocStatusMessage: String?
    @State private var ocStatusIsError = false
    @State private var ocResetScalarDraft = true
    @State private var showOcRiskConfirm = false

    // S8.2: frequency-override drafts — local state seeded once from kext cache.
    @State private var ocFreqAllDraft: Double = 4000
    @State private var ocFreqPerCcdDrafts: [Double] = []
    @State private var ocFreqSeeded = false
    @State private var ocFreqStatusMessage: String?
    @State private var ocFreqStatusIsError = false

    @State private var showCopiedToast = false

    @AppStorage("coUnlocked") private var coUnlocked: Bool = false
    @AppStorage("pboUnlocked") private var pboUnlocked: Bool = false
    @AppStorage("pboLastPPTWatts") private var pboLastPPTWatts: Double = 142
    @AppStorage("pboLastTDCAmps") private var pboLastTDCAmps: Double = 95
    @AppStorage("pboLastEDCAmps") private var pboLastEDCAmps: Double = 140
    @AppStorage("pboLastScalarTenths") private var pboLastScalarTenths: Double = 10

    var body: some View {
        Form {
            // Hardware-risk disclaimer: prominent warning ahead of SMU write controls.
            Section {
                Label(l10n.amdPower.hardwareRiskBanner, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // S8: OC Mode Master Switch (RSMU 0x5A/0x5B, selectors 49/50)
            Section {
                if coGeneration.isZen4OrNewer {
                    Label(l10n.amdPower.ocUnsupportedZen4, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if controls.ocSupported {
                    HStack {
                        Text(l10n.amdPower.ocModeLabel)
                        Spacer()
                        switch AMDOcMode.from(code: controls.ocModeCode) {
                        case .enabled:
                            Label(l10n.amdPower.ocStateEnabled, systemImage: "lock.open.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        case .disabled:
                            Label(l10n.amdPower.ocStateDisabled, systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .unknown:
                            Label(l10n.amdPower.ocStateUnknown, systemImage: "questionmark.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(l10n.amdPower.ocResetScalarLabel, isOn: $ocResetScalarDraft)
                        .font(.caption)

                    HStack(spacing: 10) {
                        Button {
                            showOcRiskConfirm = true
                        } label: {
                            Label(l10n.amdPower.ocEnable, systemImage: "lock.open")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            applyOcMode(enable: false)
                        } label: {
                            Label(l10n.amdPower.ocDisable, systemImage: "lock")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if let message = ocStatusMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundColor(ocStatusIsError ? .red : .green)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Label(l10n.amdPower.ocUnsupportedVermeer, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.amdPower.ocHeader)
            } footer: {
                Text(l10n.amdPower.ocFooter)
            }

            // S4: Precision Boost Overdrive Limits + Scalar (selectors 36-42)
            Section {
                if coGeneration.isZen4OrNewer {
                    Label(l10n.amdPower.pboUnsupportedZen4, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if pboSupported {
                    Toggle(l10n.amdPower.pboUnlockToggle, isOn: $pboUnlocked)
                        .padding(.bottom, 4)

                    if pboUnlocked {
                        Group {
                            pboLimitRow(title: l10n.amdPower.pboPPTLabel,
                                        value: $pboPPTWatts,
                                        range: 20...500,
                                        step: 1,
                                        unit: l10n.amdPower.pboUnitWatts,
                                        format: "%0.0f")
                            pboLimitRow(title: l10n.amdPower.pboTDCLabel,
                                        value: $pboTDCAmps,
                                        range: 5...500,
                                        step: 1,
                                        unit: l10n.amdPower.pboUnitAmps,
                                        format: "%0.0f")
                            pboLimitRow(title: l10n.amdPower.pboEDCLabel,
                                        value: $pboEDCAmps,
                                        range: 5...500,
                                        step: 1,
                                        unit: l10n.amdPower.pboUnitAmps,
                                        format: "%0.0f")
                            pboLimitRow(title: l10n.amdPower.pboScalarLabel,
                                        value: $pboScalarTenths,
                                        range: 10...100,
                                        step: 1,
                                        unit: l10n.amdPower.pboUnitScalar,
                                        format: "%0.1f")
                        }
                        .padding(.vertical, 2)

                        HStack(spacing: 10) {
                            Button {
                                applyPBOLimits()
                            } label: {
                                Label(l10n.amdPower.pboApplyLimits, systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                applyPBOScalar()
                            } label: {
                                Label(l10n.amdPower.pboApplyScalar, systemImage: "gauge.with.needle")
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            if let message = pboStatusMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundColor(pboStatusIsError ? .red : .green)
                                    .lineLimit(2)
                            }
                        }

                        if let cache = pboCacheMilli {
                            Text(String(format: l10n.amdPower.pboActiveLimitsFormat,
                                        AMDPBOLimits.formatLimit(cache.ppt,
                                                                 unitMilli: l10n.amdPower.pboUnitMilliwatts,
                                                                 unitBase: l10n.amdPower.pboUnitWatts),
                                        AMDPBOLimits.formatLimit(cache.tdc,
                                                                 unitMilli: l10n.amdPower.pboUnitMilliamps,
                                                                 unitBase: l10n.amdPower.pboUnitAmps),
                                        AMDPBOLimits.formatLimit(cache.edc,
                                                                 unitMilli: l10n.amdPower.pboUnitMilliamps,
                                                                 unitBase: l10n.amdPower.pboUnitAmps)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let scalar = pboScalarCacheX100 {
                            Text(String(format: l10n.amdPower.pboActiveScalarFormat,
                                        AMDPBOLimits.formatScalar(scalar)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Label(l10n.amdPower.pboDisabledLegacy, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.amdPower.pboHeader)
            } footer: {
                Text(l10n.amdPower.pboFooter)
            }

            // S5: SMU Boost Telemetry (selector 43) + S7 Readbacks
            Section {
                if controls.maxBoostFreqMHz == 0 && controls.fastestCoreRaw == 0 {
                    Text(l10n.amdPower.boostTelemetryUnavailable)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if controls.maxBoostFreqMHz > 0 {
                        HStack {
                            Text(String(format: l10n.amdPower.boostMaxFreqFormat, controls.maxBoostFreqMHz))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundColor(.cyan)
                                .font(.caption)
                        }
                    }
                    if let coreIndex = controls.fastestCoreIndex {
                        HStack {
                            Text(String(format: l10n.amdPower.boostFastestCoreFormat, UInt32(coreIndex)))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    } else if controls.fastestCoreRaw != 0 {
                        Text(String(format: "0x%08X", controls.fastestCoreRaw))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let scalar = AMDSmuReadback.formatActiveScalar(controls.activeScalarRaw) {
                    HStack {
                        Text(String(format: l10n.amdPower.smuActiveScalarFormat, scalar))
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Image(systemName: "gauge.with.needle")
                            .foregroundColor(.mint)
                            .font(.caption)
                    }
                }
                if let version = AMDSmuReadback.formatSmuVersion(controls.smuVersionRaw) {
                    Text(String(format: l10n.amdPower.smuVersionFormat, version))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(l10n.amdPower.boostTelemetryHeader)
            } footer: {
                Text(l10n.amdPower.boostTelemetryFooter)
            }

            // S6: cHTC Thermal Limit (SMU 0x56) + Fused Capability Bits (0x6F)
            Section {
                if coGeneration.isZen4OrNewer {
                    Label(l10n.amdPower.chtcUnsupportedZen4, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if pboSupported {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.amdPower.chtcSliderLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(chtcDraftCelsius)) °C")
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(value: $chtcDraftCelsius,
                               in: Double(AMDSmuParameters.minCHTCCelsius)...Double(AMDSmuParameters.maxCHTCCelsius),
                               step: 1)
                    }
                    .padding(.vertical, 2)

                    HStack(spacing: 10) {
                        Button {
                            applyCHTCLimit()
                        } label: {
                            Label(l10n.amdPower.chtcApply, systemImage: "thermometer.sun.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        if let message = chtcStatusMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundColor(chtcStatusIsError ? .red : .green)
                                .lineLimit(2)
                        }
                    }

                    if let applied = chtcAppliedCelsius {
                        Text(String(format: l10n.amdPower.chtcActiveFormat, applied))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if controls.procParamsPolled {
                        HStack(spacing: 12) {
                            capabilityBadge(l10n.amdPower.chtcOverclockable,
                                            enabled: AMDSmuParameters.isOverclockable(controls.procParamsRaw))
                            capabilityBadge(l10n.amdPower.chtcPBOSupport,
                                            enabled: AMDSmuParameters.pboSupportFused(controls.procParamsRaw))
                            if AMDSmuParameters.hasReservedBits(controls.procParamsRaw) {
                                Text(String(format: "0x%08X", controls.procParamsRaw))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Label(l10n.amdPower.chtcUnsupportedVermeer, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.amdPower.chtcHeader)
            } footer: {
                Text(l10n.amdPower.chtcFooter)
            }

            // AMD Curve Optimizer — per-core offsets (selectors 110/111)
            Section {
                if coGeneration.isZen4OrNewer {
                    Label(l10n.amdPower.coUnsupportedZen4, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if coSupported {
                    Toggle(l10n.amdPower.coUnlockToggle, isOn: $coUnlocked)
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
                                Label(l10n.amdPower.coApplyAll, systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(l10n.amdPower.coResetZero) {
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
                    Label(l10n.amdPower.coDisabledLegacy, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.amdPower.coHeader)
            } footer: {
                Text(l10n.amdPower.coFooter)
            }

            // S8.2: Frequency Overrides (0x5C/0x5D)
            Section {
                if coGeneration.isZen4OrNewer {
                    Label(l10n.amdPower.ocUnsupportedZen4, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if controls.ocFreqSupported,
                          AMDOcMode.from(code: controls.ocModeCode) == .enabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.amdPower.ocFreqAllCoreLabel)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(ocFreqAllDraft)) MHz")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        Slider(value: $ocFreqAllDraft,
                               in: Double(AMDOcFreq.minMHz)...Double(AMDOcFreq.maxMHz),
                               step: 25)
                            .labelsHidden()
                    }
                    .padding(.bottom, 4)

                    Button {
                        applyOcFreqAllCores()
                    } label: {
                        Label(l10n.amdPower.ocFreqApply, systemImage: "bolt.horizontal")
                    }
                    .buttonStyle(.borderedProminent)

                    ForEach(0..<controls.kextCcdCount, id: \.self) { ccd in
                        if ccd < ocFreqPerCcdDrafts.count {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(String(format: l10n.amdPower.ocFreqPerCcdFormat, ccd))
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(ocFreqPerCcdDrafts[ccd])) MHz")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                                Slider(value: $ocFreqPerCcdDrafts[ccd],
                                       in: Double(AMDOcFreq.minMHz)...Double(AMDOcFreq.maxMHz),
                                       step: 25)
                                    .labelsHidden()
                                Button {
                                    applyOcFreqCcd(ccd)
                                } label: {
                                    Label(l10n.amdPower.ocFreqApply, systemImage: "bolt.horizontal")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 2)
                        }
                    }

                    if let message = ocFreqStatusMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(ocFreqStatusIsError ? .red : .green)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !ocFreqCacheSummary.isEmpty {
                        Text(ocFreqCacheSummary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if controls.ocFreqSupported {
                    Label(l10n.amdPower.ocFreqBlockedNoOcMode, systemImage: "lock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(l10n.amdPower.ocUnsupportedVermeer, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.amdPower.ocFreqHeader)
            } footer: {
                Text(l10n.amdPower.ocFreqFooter)
            }

            // Diagnostics: Copy SMU Mailbox Diagnostics bundle for troubleshooting
            Section {
                Button {
                    Task { await controls.runMailboxDiagnostics() }
                    let bundle = controls.buildDiagnosticsBundle()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bundle, forType: .string)
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        showCopiedToast = false
                    }
                } label: {
                    Label(l10n.amdPower.diagBundleButton, systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)

                if showCopiedToast {
                    Text(l10n.amdPower.diagBundleCopied)
                        .font(.caption2)
                        .foregroundColor(.green)
                }
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
            }
        }
        .formStyle(.grouped)
        .onAppear {
            seedState()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await controls.syncFromKext()
            }
        }
        .alert(
            l10n.amdPower.ocRiskConfirmTitle,
            isPresented: $showOcRiskConfirm
        ) {
            Button(l10n.amdPower.ocRiskConfirmAccept, role: .destructive) {
                applyOcMode(enable: true)
            }
            Button(l10n.amdPower.ocRiskConfirmCancel, role: .cancel) {}
        } message: {
            Text(l10n.amdPower.ocRiskConfirmBody)
        }
    }

    // MARK: - State Seeding & Helpers

    private func seedState() {
        Task {
            let family = await ProcessorModel.shared.cpuFamily
            let model = await ProcessorModel.shared.cpuModel
            let physicalCores = await ProcessorModel.shared.physicalCoreCount

            coGeneration = AMDCpuGeneration.classify(family: family, model: model)
            let supportsCO = ProcessorModel.shared.getCurveOptimizerCapability()?.supported
                ?? AMDCurveOptimizer.supported(family: family, model: model)
            coSupported = supportsCO
            coCoreCount = physicalCores > 0 ? min(physicalCores, 32) : 16

            let supportsPBO = ProcessorModel.shared.getPBOCapability()?.supported
                ?? AMDPBOLimits.supported(family: family, model: model)
            pboSupported = supportsPBO

            reloadCurveOffsets()
            refreshPBOReadback()

            pboPPTWatts = pboCacheMilli.map { Double($0.ppt / 1000) } ?? pboLastPPTWatts
            pboTDCAmps = pboCacheMilli.map { Double($0.tdc / 1000) } ?? pboLastTDCAmps
            pboEDCAmps = pboCacheMilli.map { Double($0.edc / 1000) } ?? pboLastEDCAmps
            pboScalarTenths = pboScalarCacheX100.map { Double($0) / 10.0 } ?? pboLastScalarTenths

            if !chtcSeeded {
                if let cached = controls.chtcLimitCelsius, cached > 0 {
                    chtcDraftCelsius = Double(cached)
                    chtcAppliedCelsius = cached
                } else {
                    chtcDraftCelsius = Double(AMDSmuParameters.defaultCHTCCelsius)
                    chtcAppliedCelsius = nil
                }
                chtcSeeded = true
            }

            if !ocFreqSeeded {
                let allCached = controls.ocFreqAllCoresMHz
                ocFreqAllDraft = allCached > 0 ? Double(allCached) : 4000
                ocFreqPerCcdDrafts = (0..<controls.kextCcdCount).map { ccd in
                    let mhz = controls.ocFreqPerCcdMHz.indices.contains(ccd) ? controls.ocFreqPerCcdMHz[ccd] : 0
                    return mhz > 0 ? Double(mhz) : (allCached > 0 ? Double(allCached) : 4000)
                }
                ocFreqSeeded = true
            }
        }
    }

    // MARK: - Curve Optimizer

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
        if offset < 0 { return .green }
        if offset > 0 { return .orange }
        return .secondary
    }

    private func stepCurveOffset(_ core: Int, delta: Int) {
        guard core < curveOffsets.count else { return }
        let candidate = AMDCurveOptimizer.clamp(Int(curveOffsets[core]) + delta)
        guard candidate != curveOffsets[core] else { return }
        curveOffsets[core] = candidate
        writeCurveOffset(core: core, offset: candidate)
    }

    private func writeCurveOffset(core: Int, offset: Int8) {
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

    // MARK: - PBO Controls

    private func pboLimitRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                             step: Double, unit: String, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue) + " \(unit)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func applyPBOLimits() {
        let status = ProcessorModel.shared.setPBOLimits(
            pptMilliwatts: AMDPBOLimits.milliFromBase(Int(pboPPTWatts)),
            tdcMilliamps: AMDPBOLimits.milliFromBase(Int(pboTDCAmps)),
            edcMilliamps: AMDPBOLimits.milliFromBase(Int(pboEDCAmps)))
        handlePBOResult(status)
        if status == KERN_SUCCESS {
            pboLastPPTWatts = pboPPTWatts
            pboLastTDCAmps = pboTDCAmps
            pboLastEDCAmps = pboEDCAmps
            refreshPBOReadback()
        }
    }

    private func applyPBOScalar() {
        let percentX100 = Int((pboScalarTenths * 10).rounded())
        let status = ProcessorModel.shared.setPBOScalar(percentX100: percentX100)
        handlePBOResult(status)
        if status == KERN_SUCCESS {
            pboLastScalarTenths = pboScalarTenths
            refreshPBOReadback()
        }
    }

    private func refreshPBOReadback() {
        if let limits = ProcessorModel.shared.getPBOLimits() {
            pboCacheMilli = (Int(limits.pptMilliwatts), Int(limits.tdcMilliamps), Int(limits.edcMilliamps))
        }
        if let scalar = ProcessorModel.shared.getPBOScalar() {
            pboScalarCacheX100 = Int(scalar)
        }
    }

    private func handlePBOResult(_ status: kern_return_t) {
        if status == KERN_SUCCESS {
            pboStatusIsError = false
            pboStatusMessage = nil
            return
        }
        pboStatusIsError = true
        if status == ProcessorModel.kIOReturnNotPrivilegedCode {
            pboStatusMessage = "Requires root or -amdpnopchk"
        } else if status == kIOReturnUnsupported {
            pboStatusMessage = "Not supported by the kext on this CPU (Vermeer only)"
        } else if status == kIOReturnNotReady {
            pboStatusMessage = "Blocked: package temperature above 75 °C"
        } else if status == kIOReturnBadArgument {
            pboStatusMessage = "Value outside the safe range"
        } else if status == kIOReturnTimeout {
            pboStatusMessage = "SMU timeout — try again"
        } else if status == kIOReturnBusy {
            pboStatusMessage = "SMU busy — try again"
        } else {
            pboStatusMessage = "SMU command failed"
        }
    }

    private func capabilityBadge(_ title: String, enabled: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? .green : .secondary)
                .font(.caption2)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - cHTC Limit

    private func applyCHTCLimit() {
        let status = ProcessorModel.shared.setCHTCLimit(celsius: Int(chtcDraftCelsius.rounded()))
        if status == KERN_SUCCESS {
            chtcStatusIsError = false
            chtcStatusMessage = nil
            chtcAppliedCelsius = Int(chtcDraftCelsius.rounded())
        } else {
            chtcStatusIsError = true
            if status == ProcessorModel.kIOReturnNotPrivilegedCode {
                chtcStatusMessage = "Requires root or -amdpnopchk"
            } else if status == kIOReturnUnsupported {
                chtcStatusMessage = "Not supported by the kext on this CPU (Vermeer only)"
            } else if status == kIOReturnNotReady {
                chtcStatusMessage = "Blocked: package temperature above 75 °C"
            } else if status == kIOReturnBadArgument {
                chtcStatusMessage = "Value outside the safe range"
            } else if status == kIOReturnTimeout {
                chtcStatusMessage = "SMU timeout — try again"
            } else if status == kIOReturnBusy {
                chtcStatusMessage = "SMU busy — try again"
            } else {
                chtcStatusMessage = "SMU command failed"
            }
        }
    }

    // MARK: - OC Mode & Frequency Overrides

    private func applyOcMode(enable: Bool) {
        let status = ProcessorModel.shared.setOcMode(enable: enable,
                                                     resetScalar: !enable && ocResetScalarDraft)
        if status == KERN_SUCCESS {
            ocStatusIsError = false
            ocStatusMessage = nil
        } else {
            ocStatusIsError = true
            if status == ProcessorModel.kIOReturnNotPrivilegedCode {
                ocStatusMessage = "Requires root or -amdpnopchk"
            } else if status == kIOReturnUnsupported {
                ocStatusMessage = "Not supported by the kext on this CPU (Vermeer only)"
            } else if status == kIOReturnNotReady {
                ocStatusMessage = "Blocked: package temperature above 75 °C"
            } else if status == kIOReturnBadArgument {
                ocStatusMessage = "Invalid OC mode request"
            } else if status == kIOReturnTimeout {
                ocStatusMessage = "SMU timeout — try again"
            } else if status == kIOReturnBusy {
                ocStatusMessage = "SMU busy — try again"
            } else {
                ocStatusMessage = "SMU command failed"
            }
        }
    }

    private func applyOcFreqAllCores() {
        let mhz = Int(ocFreqAllDraft.rounded())
        guard AMDOcFreq.isValidMHz(mhz) else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = "Invalid frequency request"
            return
        }
        let status = ProcessorModel.shared.setOverclockFreq(allCoresMHz: mhz)
        if status == KERN_SUCCESS {
            ocFreqStatusIsError = false
            ocFreqStatusMessage = nil
        } else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = ocFreqError(status)
        }
    }

    private func applyOcFreqCcd(_ ccd: Int) {
        guard ccd < ocFreqPerCcdDrafts.count else { return }
        let mhz = Int(ocFreqPerCcdDrafts[ccd].rounded())
        guard AMDOcFreq.isValidMHz(mhz) else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = "Invalid frequency request"
            return
        }
        let status = ProcessorModel.shared.setOverclockFreq(perCcdMHz: [ccd: mhz])
        if status == KERN_SUCCESS {
            ocFreqStatusIsError = false
            ocFreqStatusMessage = nil
        } else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = ocFreqError(status)
        }
    }

    private func ocFreqError(_ status: kern_return_t) -> String {
        if status == ProcessorModel.kIOReturnNotPrivilegedCode { return "Requires root or -amdpnopchk" }
        if status == kIOReturnNotPermitted { return "Enable OC mode first (this driver must open the gate itself)" }
        if status == kIOReturnUnsupported { return "Not supported by the kext on this CPU (Vermeer only)" }
        if status == kIOReturnNotReady { return "Blocked: package temperature above 75 °C" }
        if status == kIOReturnBadArgument { return "Invalid frequency request" }
        if status == kIOReturnTimeout { return "SMU timeout — try again" }
        if status == kIOReturnBusy { return "SMU busy — try again" }
        return "SMU command failed"
    }

    private var ocFreqCacheSummary: String {
        var parts: [String] = []
        if controls.ocFreqAllCoresMHz > 0 {
            parts.append(String(format: l10n.amdPower.ocFreqCacheFormat, controls.ocFreqAllCoresMHz))
        }
        for (ccd, mhz) in controls.ocFreqPerCcdMHz.enumerated()
        where mhz > 0 && ccd < controls.kextCcdCount {
            parts.append(String(format: l10n.amdPower.ocFreqPerCcdFormat, ccd) + " \(mhz) MHz")
        }
        return parts.joined(separator: " · ")
    }
}
