// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › AMD Ryzen Power › Custom profiles: the user's own
/// `AMDPowerProfile`s, applied, edited, imported (own format or a ZenTune
/// backup) and exported.
struct AmdCustomProfilesSection: View {
    @ObservedObject private var presets = AmdPresetController.shared
    @ObservedObject private var controls = AmdPowerControlsModel.shared
    @ObservedObject private var gaming = GamingModeService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var editing: AMDPowerProfile?
    @State private var editingOriginalName: String?
    @State private var status: String?
    @State private var statusIsError = false

    var body: some View {
        Section {
            ForEach(presets.customProfiles) { profile in
                profileRow(profile)
            }
            HStack(spacing: 10) {
                Button(l10n.amdPower.customProfileNew) {
                    var draft = presets.profile(for: .balance)
                    draft.name = uniqueName(l10n.amdPower.customProfileNew)
                    editingOriginalName = nil
                    editing = draft
                }
                Button(l10n.amdPower.customProfileImport) { importProfiles() }
                Button(l10n.amdPower.customProfileExport) { exportProfiles() }
                    .disabled(presets.customProfiles.isEmpty)
                Spacer()
            }
            .buttonStyle(.bordered)
            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(statusIsError ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(l10n.amdPower.customProfilesHeader)
        } footer: {
            Text(l10n.amdPower.customProfilesFooter)
        }
        .sheet(item: $editing) { draft in
            AmdProfileEditor(profile: draft, onSave: { saved in
                if let original = editingOriginalName, original != saved.name {
                    presets.deleteCustom(named: original)
                }
                presets.save(custom: saved)
                editing = nil
            }, onCancel: { editing = nil })
        }
    }

    private func profileRow(_ profile: AMDPowerProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .fontWeight(presets.selectedCustomName == profile.name ? .semibold : .regular)
                if presets.selectedCustomName == profile.name {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                Spacer()
                Button(l10n.amdPower.customProfileApply) {
                    Task {
                        let result = await presets.apply(custom: profile)
                        await controls.syncFromKext()
                        report(result)
                    }
                }
                .disabled(gaming.isActive || controls.isWriting)
                Button(l10n.amdPower.customProfileEdit) {
                    editingOriginalName = profile.name
                    editing = profile
                }
                Button(role: .destructive) {
                    presets.deleteCustom(named: profile.name)
                } label: {
                    Image(systemName: "trash")
                }
                .help(l10n.amdPower.customProfileDelete)
            }
            .buttonStyle(.borderless)
            Text(profile.summary(caps: controls.powerCapabilities, cpbSupported: controls.cpbSupported,
                                 strings: l10n.amdPower))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func report(_ result: AMDPowerProfileApplyResult) {
        if let message = result.firstFailureMessage {
            status = message
            statusIsError = true
        } else {
            status = result.skipped.isEmpty ? nil : l10n.amdPower.customProfilePartial
            statusIsError = false
        }
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(presets.customProfiles.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        guard let outcome = AMDPowerProfileFile.decode(data) else {
            status = l10n.amdPower.customProfileImportFailed
            statusIsError = true
            return
        }
        presets.importCustom(outcome.profiles)
        var lines = [String(format: l10n.amdPower.customProfileImported, outcome.profiles.count)]
        if !outcome.skippedKeys.isEmpty {
            lines.append(String(format: l10n.amdPower.customProfileSkipped,
                                outcome.skippedKeys.sorted().joined(separator: ", ")))
        }
        status = lines.joined(separator: " ")
        statusIsError = false
    }

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ryzenstatus_power_profiles.json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = AMDPowerProfileFile.encode(presets.customProfiles) else { return }
        do {
            try data.write(to: url, options: .atomic)
            status = nil
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }
}

/// Edits one profile: every lever is optional, a switch turns it on.
private struct AmdProfileEditor: View {
    @State var profile: AMDPowerProfile
    let onSave: (AMDPowerProfile) -> Void
    let onCancel: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let s = l10n.amdPower
        VStack(alignment: .leading, spacing: 12) {
            TextField(s.customProfileName, text: $profile.name)
                .textFieldStyle(.roundedBorder)
            Form {
                optionalToggle(s.deepCStatesTitle, value: $profile.c6Idle, defaultValue: true)
                optionalToggle(s.cpbToggle, value: $profile.cpb, defaultValue: true)
                optionalNumber(s.pboPPTLabel, value: $profile.pptW, range: 5...500, step: 1, unit: s.pboUnitWatts, defaultValue: 95)
                optionalNumber(s.pboTDCLabel, value: $profile.tdcA, range: 5...500, step: 1, unit: s.pboUnitAmps, defaultValue: 130)
                optionalNumber(s.pboEDCLabel, value: $profile.edcA, range: 5...500, step: 1, unit: s.pboUnitAmps, defaultValue: 130)
                optionalNumber(s.chtcSliderLabel, value: $profile.chtcC,
                               range: AMDSmuParameters.minCHTCCelsius...AMDSmuParameters.maxCHTCCelsius,
                               step: 1, unit: "°C", defaultValue: 90)
                optionalNumber(s.pboScalarLabel, value: $profile.pboScalarX100, range: 100...1000, step: 100,
                               unit: "", defaultValue: 100, format: { String(format: "%.0fx", Double($0) / 100) })
                optionalNumber(s.customProfileCoAll, value: $profile.coAll, range: -30...30, step: 1, unit: "",
                               defaultValue: 0, format: { String(format: "%+d", $0) })
                optionalNumber(s.boostLimitLabel, value: $profile.boostLimitMHz, range: 400...8000, step: 25,
                               unit: "MHz", defaultValue: 4500)
                optionalEPP(value: $profile.epp)
                optionalToggle(s.lpmToggle, value: $profile.lpm, defaultValue: false)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(s.customProfileCancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(s.customProfileSave) { onSave(profile) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 560)
    }

    private func optionalToggle(_ title: String, value: Binding<Bool?>, defaultValue: Bool) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value.wrappedValue != nil },
                                        set: { value.wrappedValue = $0 ? defaultValue : nil }))
            Spacer()
            if value.wrappedValue != nil {
                Toggle("", isOn: Binding(get: { value.wrappedValue ?? defaultValue },
                                         set: { value.wrappedValue = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func optionalNumber(_ title: String, value: Binding<Int?>, range: ClosedRange<Int>, step: Int,
                                unit: String, defaultValue: Int,
                                format: ((Int) -> String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(get: { value.wrappedValue != nil },
                                        set: { value.wrappedValue = $0 ? defaultValue : nil }))
            if let current = value.wrappedValue {
                HStack {
                    Slider(value: Binding(get: { Double(current) },
                                          set: { value.wrappedValue = Int(($0 / Double(step)).rounded()) * step }),
                           in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                    Text(format?(current) ?? "\(current) \(unit)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(minWidth: 70, alignment: .trailing)
                }
            }
        }
    }

    private func optionalEPP(value: Binding<UInt8?>) -> some View {
        let s = l10n.amdPower
        return VStack(alignment: .leading, spacing: 4) {
            Toggle("EPP", isOn: Binding(get: { value.wrappedValue != nil },
                                        set: { value.wrappedValue = $0 ? 128 : nil }))
            if value.wrappedValue != nil {
                Picker("EPP", selection: Binding(get: { AMDPowerPreset.snapEPP(value.wrappedValue ?? 128) },
                                                 set: { value.wrappedValue = $0 })) {
                    Text(s.perfMax).tag(UInt8(0))
                    Text(s.perfBalPlus).tag(UInt8(85))
                    Text(s.perfBalMinus).tag(UInt8(170))
                    Text(s.perfEco).tag(UInt8(255))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}
