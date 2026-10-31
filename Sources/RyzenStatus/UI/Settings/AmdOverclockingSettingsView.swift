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
    /// The offsets the kext last reported, or nil when that read failed or
    /// was invalid: an unknown offset is never shown or written as 0.
    @State private var curveReadback: [Int8]?
    /// Cores written this session while the readback is unknown; their
    /// value is known again, so the grid shows it.
    @State private var coWrittenCores: Set<Int> = []
    /// Cores with a tap write queued but not started: the queued write sends
    /// the latest value, so quick taps on one core coalesce.
    @State private var coQueuedCores: Set<Int> = []
    @State private var coWriteTail: Task<Void, Never>?
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

    @AppStorage(DefaultsKey.curveOptimizerUnlocked) private var coUnlocked: Bool = false
    @AppStorage(DefaultsKey.pboUnlocked) private var pboUnlocked: Bool = false
    @AppStorage(DefaultsKey.pboLastPPTWatts) private var pboLastPPTWatts: Double = 142
    @AppStorage(DefaultsKey.pboLastTDCAmps) private var pboLastTDCAmps: Double = 95
    @AppStorage(DefaultsKey.pboLastEDCAmps) private var pboLastEDCAmps: Double = 140
    @AppStorage(DefaultsKey.pboLastScalarTenths) private var pboLastScalarTenths: Double = 10

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
                        .disabled(controls.isWriting)

                        Button {
                            Task { await applyOcMode(enable: false) }
                        } label: {
                            Label(l10n.amdPower.ocDisable, systemImage: "lock")
                        }
                        .buttonStyle(.bordered)
                        .disabled(controls.isWriting)

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
                                Task { await applyPBOLimits() }
                            } label: {
                                Label(l10n.amdPower.pboApplyLimits, systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controls.isWriting)

                            Button {
                                Task { await applyPBOScalar() }
                            } label: {
                                Label(l10n.amdPower.pboApplyScalar, systemImage: "gauge.with.needle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(controls.isWriting)

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
                            Task { await applyCHTCLimit() }
                        } label: {
                            Label(l10n.amdPower.chtcApply, systemImage: "thermometer.sun.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controls.isWriting)

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
                            // Writes only the cores that differ from what the
                            // kext reports; nothing to write without a readback.
                            Button {
                                applyAllCurveOffsets()
                            } label: {
                                Label(l10n.amdPower.coApplyAll, systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controls.isWriting
                                      || CurveOptimizerWritePlan.changedCores(draft: curveOffsets, readback: curveReadback).isEmpty)

                            Button(l10n.amdPower.coResetZero) {
                                resetCurveOffsets()
                            }
                            .buttonStyle(.bordered)
                            .disabled(controls.isWriting
                                      || CurveOptimizerWritePlan.coresToReset(readback: curveReadback, coreCount: coCoreCount).isEmpty)

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
                        Task { await applyOcFreqAllCores() }
                    } label: {
                        Label(l10n.amdPower.ocFreqApply, systemImage: "bolt.horizontal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controls.isWriting)

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
                                    Task { await applyOcFreqCcd(ccd) }
                                } label: {
                                    Label(l10n.amdPower.ocFreqApply, systemImage: "bolt.horizontal")
                                }
                                .buttonStyle(.bordered)
                                .disabled(controls.isWriting)
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
                    // The bundle carries the report this click asked for, so
                    // it is built after the run.
                    Task {
                        await controls.runMailboxDiagnostics()
                        let bundle = controls.buildDiagnosticsBundle()
                        GeneralPasteboardAccess.shared.copyString(bundle, ownCopy: false)
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            showCopiedToast = false
                        }
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
        // The shared kext poll runs only while the page is on screen in a
        // visible Settings window.
        .settingsPageActivity(.amdOverclocking)
        .alert(
            l10n.amdPower.ocRiskConfirmTitle,
            isPresented: $showOcRiskConfirm
        ) {
            Button(l10n.amdPower.ocRiskConfirmAccept, role: .destructive) {
                Task { await applyOcMode(enable: true) }
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
            // Capability reads are kext IPC: off the main thread.
            let (coCapability, pboCapability) = await Task.detached(priority: .userInitiated) {
                (ProcessorModel.shared.getCurveOptimizerCapability()?.supported,
                 ProcessorModel.shared.getPBOCapability()?.supported)
            }.value
            coSupported = coCapability ?? AMDCurveOptimizer.supported(family: family, model: model)
            coCoreCount = physicalCores > 0 ? min(physicalCores, 32) : 16
            pboSupported = pboCapability ?? AMDPBOLimits.supported(family: family, model: model)

            // The sliders seed from the readbacks, so they are awaited first.
            await reloadCurveOffsets()
            await refreshPBOReadback()

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
        let known = curveReadback != nil || coWrittenCores.contains(core)
        let coreLabel = String(format: l10n.dashboard.coreLabelFormat, core + 1)
        return VStack(spacing: 3) {
            Text(coreLabel)
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
                .accessibilityLabel(String(format: l10n.dashboard.coLowerFormat, core + 1))

                Text(known ? "\(offset)" : "—")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(known ? curveOffsetColor(offset) : .secondary)
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
                .accessibilityLabel(String(format: l10n.dashboard.coRaiseFormat, core + 1))
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
        enqueueCurveWrite(core: core)
    }

    /// Each tap joins one ordered chain on this page, so two quick taps on a
    /// core can never land out of order. The write sends the core's latest
    /// value when it runs, and the status names the write that finished.
    private func enqueueCurveWrite(core: Int) {
        guard !coQueuedCores.contains(core) else { return }
        coQueuedCores.insert(core)
        let previous = coWriteTail
        coWriteTail = Task {
            await previous?.value
            coQueuedCores.remove(core)
            guard core < curveOffsets.count else { return }
            let offset = curveOffsets[core]
            let status = await controls.perform {
                ProcessorModel.shared.setCurveOptimizerOffset(core: UInt8(core), offset: offset)
            }
            if status == KERN_SUCCESS {
                coWrittenCores.insert(core)
                if var readback = curveReadback, core < readback.count {
                    readback[core] = offset
                    curveReadback = readback
                }
                coStatusMessage = String(format: l10n.dashboard.coreOffsetAppliedFormat, core + 1, Int(offset))
                coStatusIsError = false
            } else {
                coStatusMessage = curveOptimizerError(status)
                coStatusIsError = true
                await reloadCurveOffsets()
            }
        }
    }

    /// Writes the given cores' current values in core order, after any tap
    /// still queued, and stops at the first failure.
    private func writeCurveCores(_ cores: [Int]) {
        guard !cores.isEmpty else { return }
        coStatusMessage = nil
        let offsets = cores.map { (core: $0, offset: curveOffsets[$0]) }
        let previous = coWriteTail
        coWriteTail = Task {
            await previous?.value
            var applied = 0
            var failure: kern_return_t = KERN_SUCCESS
            for item in offsets {
                let status = await controls.perform {
                    ProcessorModel.shared.setCurveOptimizerOffset(core: UInt8(item.core), offset: item.offset)
                }
                guard status == KERN_SUCCESS else {
                    failure = status
                    break
                }
                applied += 1
                coWrittenCores.insert(item.core)
            }
            if failure == KERN_SUCCESS {
                coStatusMessage = String(format: l10n.dashboard.coresAppliedFormat, applied)
                coStatusIsError = false
            } else {
                coStatusMessage = curveOptimizerError(failure)
                coStatusIsError = true
            }
            // The grid shows what the kext holds after the batch.
            await reloadCurveOffsets()
        }
    }

    private func applyAllCurveOffsets() {
        writeCurveCores(CurveOptimizerWritePlan.changedCores(draft: curveOffsets, readback: curveReadback))
    }

    /// Zero is the stock direction, so no confirmation; only cores the kext
    /// reports as non-zero are written, or every core when that is unknown.
    private func resetCurveOffsets() {
        let cores = CurveOptimizerWritePlan.coresToReset(readback: curveReadback, coreCount: coCoreCount)
        if curveOffsets.count != coCoreCount {
            curveOffsets = [Int8](repeating: 0, count: coCoreCount)
        }
        for core in cores where core < curveOffsets.count {
            curveOffsets[core] = 0
        }
        writeCurveCores(cores)
    }

    /// A failed or invalid read leaves the readback unknown instead of
    /// pretending every core holds 0.
    private func reloadCurveOffsets() async {
        let raw = await Task.detached(priority: .userInitiated) {
            ProcessorModel.shared.getCurveOptimizerOffsets()
        }.value
        if AMDCurveOptimizer.validOffsets(raw, coreCount: coCoreCount) {
            let offsets = Array(raw.prefix(coCoreCount))
            curveOffsets = offsets
            curveReadback = offsets
            coWrittenCores = []
        } else {
            curveReadback = nil
            if curveOffsets.count != coCoreCount {
                curveOffsets = [Int8](repeating: 0, count: coCoreCount)
            }
        }
    }

    private func curveOptimizerError(_ status: kern_return_t) -> String {
        AmdWriteStatus.text(status, strings: l10n.dashboard, badArgument: l10n.dashboard.statusInvalidCore)
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

    private func applyPBOLimits() async {
        let ppt = AMDPBOLimits.milliFromBase(Int(pboPPTWatts))
        let tdc = AMDPBOLimits.milliFromBase(Int(pboTDCAmps))
        let edc = AMDPBOLimits.milliFromBase(Int(pboEDCAmps))
        let status = await controls.perform {
            ProcessorModel.shared.setPBOLimits(pptMilliwatts: ppt, tdcMilliamps: tdc, edcMilliamps: edc)
        }
        handlePBOResult(status)
        if status == KERN_SUCCESS {
            pboLastPPTWatts = pboPPTWatts
            pboLastTDCAmps = pboTDCAmps
            pboLastEDCAmps = pboEDCAmps
            await refreshPBOReadback()
        }
    }

    private func applyPBOScalar() async {
        let percentX100 = Int((pboScalarTenths * 10).rounded())
        let status = await controls.perform {
            ProcessorModel.shared.setPBOScalar(percentX100: percentX100)
        }
        handlePBOResult(status)
        if status == KERN_SUCCESS {
            pboLastScalarTenths = pboScalarTenths
            await refreshPBOReadback()
        }
    }

    private func refreshPBOReadback() async {
        let (limits, scalar) = await Task.detached(priority: .userInitiated) {
            (ProcessorModel.shared.getPBOLimits(), ProcessorModel.shared.getPBOScalar())
        }.value
        if let limits {
            pboCacheMilli = (Int(limits.pptMilliwatts), Int(limits.tdcMilliamps), Int(limits.edcMilliamps))
        }
        if let scalar {
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
        pboStatusMessage = AmdWriteStatus.text(status, strings: l10n.dashboard,
                                               badArgument: l10n.dashboard.statusOutOfRange)
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

    private func applyCHTCLimit() async {
        let celsius = Int(chtcDraftCelsius.rounded())
        let status = await controls.perform {
            ProcessorModel.shared.setCHTCLimit(celsius: celsius)
        }
        if status == KERN_SUCCESS {
            chtcStatusIsError = false
            chtcStatusMessage = nil
            chtcAppliedCelsius = celsius
        } else {
            chtcStatusIsError = true
            chtcStatusMessage = AmdWriteStatus.text(status, strings: l10n.dashboard,
                                                    badArgument: l10n.dashboard.statusOutOfRange)
        }
    }

    // MARK: - OC Mode & Frequency Overrides

    private func applyOcMode(enable: Bool) async {
        let resetScalar = !enable && ocResetScalarDraft
        let status = await controls.perform {
            ProcessorModel.shared.setOcMode(enable: enable, resetScalar: resetScalar)
        }
        if status == KERN_SUCCESS {
            ocStatusIsError = false
            ocStatusMessage = nil
        } else {
            ocStatusIsError = true
            ocStatusMessage = AmdWriteStatus.text(status, strings: l10n.dashboard,
                                                  badArgument: l10n.dashboard.statusInvalidOcMode)
        }
    }

    private func applyOcFreqAllCores() async {
        let mhz = Int(ocFreqAllDraft.rounded())
        guard AMDOcFreq.isValidMHz(mhz) else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = l10n.dashboard.statusInvalidFrequency
            return
        }
        let status = await controls.perform {
            ProcessorModel.shared.setOverclockFreq(allCoresMHz: mhz)
        }
        reportOcFreq(status)
    }

    private func applyOcFreqCcd(_ ccd: Int) async {
        guard ccd < ocFreqPerCcdDrafts.count else { return }
        let mhz = Int(ocFreqPerCcdDrafts[ccd].rounded())
        guard AMDOcFreq.isValidMHz(mhz) else {
            ocFreqStatusIsError = true
            ocFreqStatusMessage = l10n.dashboard.statusInvalidFrequency
            return
        }
        let status = await controls.perform {
            ProcessorModel.shared.setOverclockFreq(perCcdMHz: [ccd: mhz])
        }
        reportOcFreq(status)
    }

    private func reportOcFreq(_ status: kern_return_t) {
        if status == KERN_SUCCESS {
            ocFreqStatusIsError = false
            ocFreqStatusMessage = nil
        } else {
            ocFreqStatusIsError = true
            // Here a refusal means this driver has not opened the OC gate.
            ocFreqStatusMessage = AmdWriteStatus.text(status, strings: l10n.dashboard,
                                                      badArgument: l10n.dashboard.statusInvalidFrequency,
                                                      notPermitted: l10n.dashboard.statusEnableOcFirst)
        }
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

/// Which Curve Optimizer cores a bulk action writes. Offsets the user did not
/// change are never written, and a failed readback never turns into zeros.
enum CurveOptimizerWritePlan {
    /// Cores whose value differs from the last valid readback; none without
    /// one, since a difference cannot be known.
    static func changedCores(draft: [Int8], readback: [Int8]?) -> [Int] {
        guard let readback else { return [] }
        return draft.indices.filter { $0 < readback.count && draft[$0] != readback[$0] }
    }

    /// "Reset to 0": cores the readback reports as non-zero, or every core
    /// when the readback is unknown (the user asked for all of them).
    static func coresToReset(readback: [Int8]?, coreCount: Int) -> [Int] {
        guard let readback else { return Array(0..<max(0, coreCount)) }
        return readback.indices.filter { $0 < coreCount && readback[$0] != 0 }
    }
}
