// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The evidence surface for the pending on-hardware probes.
///
/// The S-series waves accumulated `[REQUIERE-HW]` rows faster than they could
/// be closed, and the reason was not missing code: it was that judging a probe
/// required reading things no tool here can read. `log show` is sandboxed for
/// our tooling, and `--sensors`/`--selftest` cannot be used during a probe at
/// all — each opens and closes a user client, and `clientClose()` hands *every*
/// fan back to BIOS, silently resetting the state being measured.
///
/// So this page exists to make a probe cycle readable from inside the app:
/// precondition gates that say whether a measurement means anything, a
/// checklist that survives the reboot the cycle spans, and one ASCII report
/// that carries every number a probe is judged on.
struct AmdValidationSettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var fans = FanCurveController.shared

    @State private var snapshot: HardwareValidation.Snapshot?
    @State private var record = HardwareValidation.Record.decode(
        UserDefaults.standard.string(forKey: DefaultsKey.validationRecord)
    )
    @State private var checking = false
    @State private var sampleProbe: HardwareValidation.Probe = .pwmFloor
    @State private var showCopiedToast = false

    private var s: ValidationFeatureStrings { l10n.validation }

    var body: some View {
        Form {
            preconditionsSection
            probesSection
            samplesSection
            reportSection
        }
        .formStyle(.grouped)
        .onAppear { refreshSnapshot() }
        // Fan count is the one precondition a topology change (kext reload, a
        // different board) shows up in without any user action.
        .onChange(of: fans.fans.count) { _, _ in refreshSnapshot() }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text(l10n.amdPower.diagBundleCopied)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Sections

    private var preconditionsSection: some View {
        Section {
            Text(s.checkHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    runPreconditionsCheck()
                } label: {
                    Label(s.checkButton, systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(checking)

                if checking {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if let snapshot {
                    Text(String(format: s.capturedFormat, HardwareValidation.timestamp(snapshot.capturedAt ?? Date())))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            ForEach(currentGates, id: \.gate) { result in
                gateRow(result)
            }
        } header: {
            Text(s.gatesHeader)
        } footer: {
            Text(s.footer)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var probesSection: some View {
        Section {
            ForEach(HardwareValidation.Probe.allCases, id: \.self) { probe in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(probe.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text(probeLabel(probe))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: statusBinding(for: probe)) {
                        Text(s.statusPending).tag(HardwareValidation.ProbeStatus.pending)
                        Text(s.statusPass).tag(HardwareValidation.ProbeStatus.pass)
                        Text(s.statusFail).tag(HardwareValidation.ProbeStatus.fail)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            }
        } header: {
            Text(s.probesHeader)
        } footer: {
            Text(s.probesFooter)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var samplesSection: some View {
        Section {
            HStack(spacing: 10) {
                Picker("", selection: $sampleProbe) {
                    ForEach(HardwareValidation.Probe.allCases, id: \.self) { probe in
                        Text("\(probe.rawValue) — \(probeLabel(probe))").tag(probe)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                Button {
                    recordSample()
                } label: {
                    Label(s.sampleButton, systemImage: "record.circle")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    record.clearSamples()
                    persist()
                } label: {
                    Text(s.clearButton)
                }
                .buttonStyle(.bordered)
                .disabled(record.samples.isEmpty)

                Spacer()

                Text("\(record.samples.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if record.samples.isEmpty {
                Text(s.samplesEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(record.samples.suffix(Self.visibleSamples).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text(s.samplesHeader)
        }
    }

    private var reportSection: some View {
        Section {
            ScrollView {
                Text(currentReport)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)

            Button {
                copyReport()
            } label: {
                Label(s.copyButton, systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text(s.reportHeader)
        }
    }

    // MARK: - Rows

    private func gateRow(_ result: HardwareValidation.GateResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(gateLabel(result.gate))
                    .font(.caption)
                Spacer()
                Text(result.verdict.rawValue)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(verdictColor(result.verdict))
            }
            Text(result.detail)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if result.verdict != .pass {
                Text(gateHint(result.gate))
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 1)
    }

    private func verdictColor(_ verdict: HardwareValidation.Verdict) -> Color {
        switch verdict {
        case .pass: return .green
        case .fail: return .red
        case .unknown: return .secondary
        }
    }

    private func gateLabel(_ gate: HardwareValidation.Gate) -> String {
        switch gate {
        case .kextVersion: return s.gateKextVersion
        case .kextTelemetry: return s.gateKextTelemetry
        case .privilege: return s.gatePrivilege
        case .fanTopology: return s.gateFanTopology
        case .tachValidity: return s.gateTachValidity
        case .superIOFamily: return s.gateSuperIOFamily
        }
    }

    private func gateHint(_ gate: HardwareValidation.Gate) -> String {
        switch gate {
        case .kextVersion: return s.hintKextVersion
        case .kextTelemetry: return s.hintKextTelemetry
        case .privilege: return s.hintPrivilege
        case .fanTopology: return s.hintFanTopology
        case .tachValidity: return s.hintTachValidity
        case .superIOFamily: return s.hintSuperIOFamily
        }
    }

    private func probeLabel(_ probe: HardwareValidation.Probe) -> String {
        switch probe {
        case .identity: return s.probeIdentity
        case .deadMan: return s.probeDeadMan
        case .pwmFloor: return s.probePwmFloor
        case .thermalGuard: return s.probeThermalGuard
        case .smuControls: return s.probeSmuControls
        case .telemetry: return s.probeTelemetry
        case .surfaces: return s.probeSurfaces
        }
    }

    // MARK: - State

    private static let visibleSamples = 12

    /// Gates come from the last snapshot; before the first one the matrix is
    /// still rendered (from an empty snapshot) so the page never shows an
    /// unexplained blank where a precondition should be.
    private var currentGates: [HardwareValidation.GateResult] {
        HardwareValidation.gates(snapshot ?? HardwareValidation.Snapshot())
    }

    private var currentReport: String {
        HardwareValidation.report(snapshot ?? HardwareValidation.Snapshot(),
                                  samples: record.samples,
                                  now: Date())
    }

    private func statusBinding(for probe: HardwareValidation.Probe) -> Binding<HardwareValidation.ProbeStatus> {
        Binding(
            get: { record.status(of: probe) },
            set: { newValue in
                record.setStatus(newValue, for: probe)
                persist()
            }
        )
    }

    private func persist() {
        UserDefaults.standard.set(record.encoded(), forKey: DefaultsKey.validationRecord)
    }

    private func refreshSnapshot() {
        snapshot = HardwareValidation.liveSnapshot(from: controls)
    }

    /// The one precondition the app can resolve by itself. Selector 58 is
    /// privileged and read-only: no fan, no voltage, no limit is written, so
    /// running it on demand costs nothing but mailbox traffic — and its answer
    /// is the difference between "the curve never uploaded" and "the floor
    /// held", which is the probe cycle's worst false positive.
    private func runPreconditionsCheck() {
        checking = true
        Task {
            await controls.runMailboxDiagnostics()
            refreshSnapshot()
            checking = false
        }
    }

    private func recordSample() {
        let current = snapshot ?? HardwareValidation.liveSnapshot(from: controls)
        let line = HardwareValidation.sampleLine(probe: sampleProbe,
                                                at: Date(),
                                                packageTempC: current.packageTempC,
                                                packagePowerW: current.packagePowerW,
                                                fans: current.fans)
        record.appendSample(line)
        persist()
        snapshot = current
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentReport, forType: .string)
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { showCopiedToast = false }
        }
    }
}

// MARK: - Live snapshot

extension HardwareValidation {
    /// Assembles the snapshot from the live app state. Lives here rather than
    /// in the pure file: it is the only part that knows about IOKit-backed
    /// singletons, which is exactly why the gates and the report are testable
    /// without one.
    @MainActor
    static func liveSnapshot(from controls: AmdPowerControlsModel) -> Snapshot {
        var snapshot = Snapshot()

        snapshot.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        snapshot.appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let cachedKextVersion = ProcessorModel.shared.identityCache.kextVersion
        if !cachedKextVersion.isEmpty && cachedKextVersion != "6" {
            snapshot.kextVersion = cachedKextVersion
        } else if let liveKextVersion = ProcessorModel.queryLoadedKextVersion() {
            snapshot.kextVersion = liveKextVersion
        } else {
            snapshot.kextVersion = cachedKextVersion
        }
        snapshot.kextConnected = ProcessorModel.shared.isConnected

        let packet = ProcessorModel.shared.getTelemetry()
        snapshot.hasTelemetryPacket = packet != nil
        snapshot.packageTempC = packet.map { Double($0.packageTempC) } ?? 0
        snapshot.packagePowerW = packet.map { Double($0.packagePowerW) } ?? 0

        snapshot.privilegeChecked = controls.smuDiagnostics != nil || controls.smuDiagnosticsDenied
        snapshot.privilegeReported = controls.smuDiagnostics != nil
        snapshot.privilegeDenied = controls.smuDiagnosticsDenied
        snapshot.privilegeMessage = FanCurveController.shared.privilegeError ?? controls.privilegeWarning

        snapshot.fans = FanCurveController.shared.fans.map { fan in
            FanEvidence(id: fan.id,
                        name: fan.name,
                        isPump: fan.isPumpHeader,
                        rpm: fan.rpm,
                        rpmValid: fan.rpmValid,
                        throttle: fan.throttlePWM,
                        isAuto: fan.isKextAuto)
        }

        let controller = FanCurveController.shared
        let mappings = controller.fanMappings
        snapshot.curves = controller.customCurves.prefix(4).enumerated().map { slot, curve in
            CurveEvidence(name: curve.name,
                          sourceSensor: curve.sourceSensor == .gpu ? "gpu" : "cpu",
                          fanIds: mappings.filter { $0.value == slot }.map(\.key).sorted())
        }

        snapshot.smuLines = controls.smuStateLines()
        snapshot.pmTableLine = controls.pmTableSummaryLine()
        snapshot.capturedAt = Date()
        return snapshot
    }
}
