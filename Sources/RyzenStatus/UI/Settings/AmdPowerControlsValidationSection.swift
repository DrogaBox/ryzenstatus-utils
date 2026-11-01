// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Hardware Validation › Power controls: the capability report (selector 62),
/// the CC6 state (selector 34) and the ACPI CPPC discovery report (selectors
/// 63/64), so a missing control explains itself.
struct AmdPowerControlsValidationSection: View {
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var report: AMDAcpiCppcReport?
    @State private var probe: [UInt64]?
    @State private var probeFailed = false

    private static let capabilityNames: [(AMDPowerCapabilities, String)] = [
        (.pptTdcEdcLimits, "PPT / TDC / EDC"), (.apuPowerLimit, "STAPM / fast / slow"),
        (.chtcLimit, "cHTC"), (.pboScalar, "PBO scalar"), (.ocMode, "OC"),
        (.ocPerCcd, "OC per CCD"), (.ocVid, "OC VID"), (.coPerCore, "Curve Optimizer per core"),
        (.coAllCores, "Curve Optimizer all cores"), (.boostLimit, "Boost ceiling"),
        (.pmTable, "PM table"), (.c6Idle, "CC6 idle"), (.epp, "EPP"),
    ]

    var body: some View {
        Section {
            let caps = controls.powerCapabilities
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(Self.capabilityNames, id: \.1) { cap, name in
                    Label(name, systemImage: caps.contains(cap) ? "checkmark.circle.fill" : "minus.circle")
                        .font(.caption)
                        .foregroundColor(caps.contains(cap) ? .primary : .secondary)
                }
            }
            if let policy = controls.c6Policy {
                monoLine(String(format: "CC6 %@ · CSTATE_ADDR 0x%llX · IO base 0x%llX%@",
                                policy.c6On ? "on" : "off", policy.cstateAddress, policy.ioBase,
                                policy.forbiddenByBootArg ? " · amdcstate=1" : ""))
            }
            if let report {
                cppcLines(report)
            }
            Button(l10n.amdPower.validationCppcProbe) {
                Task {
                    let values = await Task.detached { ProcessorModel.shared.probeAcpiCppc() }.value
                    probe = values
                    probeFailed = values == nil
                    report = await Task.detached { ProcessorModel.shared.getAcpiCppcReport() }.value
                }
            }
            .buttonStyle(.bordered)
            .disabled(report?.supported != true)
            if let probe {
                monoLine(String(format: "highest %llu · nominal %llu · lowest non-linear %llu · lowest %llu · EPP %llu · status 0x%llX",
                                probe[0], probe[1], probe[2], probe[3], probe[4], probe[5]))
            } else if probeFailed {
                Text(l10n.amdPower.validationCppcProbeFailed)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        } header: {
            Text(l10n.amdPower.validationPowerHeader)
        } footer: {
            Text(l10n.amdPower.validationPowerFooter)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await controls.syncFromKext()
            report = await Task.detached { ProcessorModel.shared.getAcpiCppcReport() }.value
        }
    }

    @ViewBuilder
    private func cppcLines(_ r: AMDAcpiCppcReport) -> some View {
        let path = r.msrCppc ? "MSR" : (r.supported ? "ACPI CPPC" : "none")
        monoLine("EPP path: \(path) · _CPC CPUs \(r.cpuCount) · revision \(r.revision)"
                 + (r.failure.map { $0 == .none ? "" : " · \(Self.failureText($0))" } ?? ""))
        if let epp = r.registers.last, epp.isRegister {
            monoLine(String(format: "EPP register: space 0x%02X · %u bits @ %u · subspace %u · offset 0x%X",
                            epp.space, epp.bitWidth, epp.bitOffset, epp.subspace, epp.offset))
        }
        ForEach(r.subspaces.keys.sorted(), id: \.self) { id in
            if let ss = r.subspaces[id] {
                monoLine(String(format: "PCC %d: type %u · base 0x%llX · %u bytes · doorbell %@ 0x%X · %u us",
                                id, ss.type, ss.base, ss.length, ss.doorbellSpace == 0 ? "mem" : "io",
                                ss.doorbellAddress, ss.latencyUs))
            }
        }
    }

    private static func failureText(_ failure: AMDAcpiCppcReport.Failure) -> String {
        switch failure {
        case .none: return ""
        case .noAcpiPlane: return "no ACPI plane"
        case .noCpc: return "no _CPC"
        case .malformedCpc: return "malformed _CPC"
        case .notPcc: return "_CPC registers are not PCC"
        case .noPcct: return "no PCCT"
        case .malformedPcct: return "malformed PCCT"
        case .mapFailed: return "PCC map failed"
        case .processorCountMismatch: return "_CPC missing on some CPUs"
        }
    }

    private func monoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
