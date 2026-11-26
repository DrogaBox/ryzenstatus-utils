// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// What the profiles section asks of the app: saving what the card holds now
/// under a name, and loading, renaming or deleting one of them. Saving and
/// renaming answer with what came of the name, so the sheet can say why it
/// stayed open.
struct GPUControlProfileActions {
    var save: (String) -> GPUControlProfileSave = { _ in .nothingToSave }
    var load: (GPUControlProfile) -> Void = { _ in }
    var rename: (String, String) -> GPUControlProfileSave = { _, _ in .nothingToSave }
    var delete: (String) -> Void = { _ in }
}

/// Settings > GPU control > Profiles: the owner's GPU setups, one row each,
/// in the plain style of Settings > AMD Ryzen Power > Custom profiles (a
/// name, its buttons, and what it holds under it). Saving asks for a name in
/// a sheet; deleting asks first.
struct GPUControlProfilesSection: View {
    let input: GPUControlPageInput
    let strings: GPUControlProfileStrings
    let page: GPUControlPageStrings
    let actions: GPUControlProfileActions

    @State private var sheet: NameSheet?
    @State private var pendingDelete: GPUControlProfile?
    @State private var sheetProblem: String?

    /// The name sheet: a new profile (`original` nil) or a rename.
    private struct NameSheet: Identifiable {
        var id: String
        var original: String?
        var name: String
        var title: String
    }

    var body: some View {
        Section {
            ForEach(input.profiles) { profile in
                row(profile)
            }
            if input.profiles.isEmpty {
                Text(strings.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(strings.saveCurrent) {
                    sheetProblem = nil
                    sheet = NameSheet(id: "new", original: nil, name: "", title: strings.saveTitle)
                }
                .disabled(held == nil)
                Spacer()
            }
            .buttonStyle(.bordered)
            if let message {
                GPUControlProblemLabel(text: message.text, isProblem: message.isProblem)
            }
        } header: {
            Text(strings.section)
        } footer: {
            Text(strings.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $sheet) { draft in
            sheetView(draft)
        }
        .alert(strings.deleteTitle, isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { profile in
            Button(strings.delete, role: .destructive) {
                actions.delete(profile.name)
                pendingDelete = nil
            }
            Button(strings.cancel, role: .cancel) { pendingDelete = nil }
        } message: { profile in
            Text(String(format: strings.deleteMessage, profile.name))
        }
    }

    // MARK: Rows

    private func row(_ profile: GPUControlProfile) -> some View {
        let matches = input.matchingProfile.map { $0 == profile.name } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .fontWeight(matches ? .semibold : .regular)
                if matches {
                    // Never colour alone: the row's weight and the help say it.
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help(strings.matches)
                        .accessibilityLabel(strings.matches)
                }
                Spacer()
                Button(strings.load) { actions.load(profile) }
                    .disabled(!canLoad)
                Button(strings.rename) {
                    sheetProblem = nil
                    sheet = NameSheet(id: profile.name, original: profile.name, name: profile.name,
                                      title: strings.renameTitle)
                }
                Button(role: .destructive) {
                    pendingDelete = profile
                } label: {
                    Image(systemName: "trash")
                }
                .help(strings.delete)
            }
            .buttonStyle(.borderless)
            Text(summary(profile.request))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// What a profile holds, in the page's own words.
    private func summary(_ request: GPUControlRequest) -> String {
        switch request {
        case .power(let watts): return String(format: page.wattsFormat, Int(watts))
        case .od8(let want): return page.od8Held(want)
        case .startUp: return ""
        }
    }

    /// What the card holds now, when that is something a profile could keep.
    private var held: GPUControlRequest? {
        guard case .heldByApp(let request)? = input.state, request != .startUp else { return nil }
        return request
    }

    /// Loading goes through the page's own path, so it waits where the
    /// controls wait: writing open, nothing else on its way.
    private var canLoad: Bool {
        input.canChoose && (input.state?.acceptsChoices ?? false) && !input.isPending
    }

    // MARK: The last load

    /// One line about the last profile loaded, or why Save is dimmed.
    private var message: (text: String, isProblem: Bool)? {
        if let load = input.profileLoad {
            if let blocked = load.blocked {
                return (blockedText(blocked), true)
            }
            var lines: [String] = []
            if load.leftOut.isEmpty {
                lines.append(String(format: strings.loadedFormat, load.name))
            } else {
                lines.append(String(format: strings.leftOutFormat, load.name, fieldList(load.leftOut)))
            }
            if load.raiseNeedsOverclock { lines.append(strings.raiseNeedsOverclock) }
            if load.cardChanged { lines.append(strings.otherCard) }
            return (lines.joined(separator: " "), !load.leftOut.isEmpty || load.raiseNeedsOverclock)
        }
        return held == nil ? (strings.nothingToSave, false) : nil
    }

    private func blockedText(_ block: GPUControlProfileBlock) -> String {
        switch block {
        case .writingClosed: return strings.blockedWriting
        case .waitingForDriver: return strings.blockedDriver
        case .otherProgram: return strings.blockedOther
        case .od8NotRead: return strings.blockedOD8
        case .fanNotChecked: return strings.blockedFan
        case .outOfRange: return strings.blockedOutOfRange
        case .raiseNeedsOverclock: return strings.raiseNeedsOverclock
        }
    }

    private func fieldList(_ fields: [GPUControlProfileField]) -> String {
        let names = fields.map(fieldName)
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: strings.listSeparator) + strings.listLastSeparator + last
    }

    private func fieldName(_ field: GPUControlProfileField) -> String {
        switch field {
        case .power: return strings.fieldPower
        case .fanCurve: return strings.fieldFanCurve
        case .zeroRpm: return strings.fieldZeroRpm
        case .gfxMax: return strings.fieldGfxMax
        case .gfxMin: return strings.fieldGfxMin
        case .volt: return strings.fieldVolt
        case .raise: return strings.fieldRaise
        }
    }

    // MARK: The name sheet

    private func sheetView(_ draft: NameSheet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.title)
                .font(.headline)
            TextField(strings.nameLabel, text: Binding(
                get: { sheet?.name ?? "" },
                set: { sheet?.name = $0; sheetProblem = nil }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 340)
            if let sheetProblem {
                Text(sheetProblem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(strings.cancel) { sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button(strings.saveAction) { commit(sheet ?? draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled((sheet ?? draft).name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func commit(_ draft: NameSheet) {
        let outcome = draft.original.map { actions.rename($0, draft.name) } ?? actions.save(draft.name)
        switch outcome {
        case .saved:
            sheet = nil
            sheetProblem = nil
        case .duplicateName(let name):
            sheetProblem = String(format: strings.duplicateName, name)
        case .emptyName, .nothingToSave, .newerVersion:
            // Nothing the sheet can fix: it closes, and the section's line
            // says why Save is dimmed.
            sheet = nil
        }
    }
}
