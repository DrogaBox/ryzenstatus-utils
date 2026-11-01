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
