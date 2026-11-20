// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Settings > GPU control: the power limit held through GPUSensors.kext.
/// Built like the read-only group on the Sensors page (#109): a grouped
/// `Form`, system `Section`s, system text styles, captions for the
/// explanations, nothing under 10 pt, no capsules or cards ("Settings",
/// "Typography": 10 pt is the minimum on macOS).
struct GPUControlSettingsView: View {
    @ObservedObject private var service = GPUControlService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        GPUControlPageContent(
            input: GPUControlPageInput(service: service),
            strings: FeatureStrings.gpuControlPage(l10n.language),
            title: FeatureStrings.gpuControl(l10n.language).title,
            actions: GPUControlPageActions(
                choosePower: { service.choosePower($0) },
                backToStartUp: { service.backToStartUp() },
                openWriting: { service.openWriting(prompt: FeatureStrings.gpuControlPage(l10n.language).armPrompt) },
                setRemember: { service.remember = $0 }))
            // Reads once a second only while the page is on screen.
            .settingsPageActivity(.gpuControl,
                                  activate: { service.viewerAppeared() },
                                  deactivate: { service.viewerDisappeared() })
    }
}

/// Everything the page shows, as plain values (the screenshot harness and
/// the tests build these without the service).
struct GPUControlPageInput: Equatable {
    var facts: GPUControlFacts?
    var state: GPUControlPageState?
    var snapshot: GPUControlSnapshot?
    var live = GPUControlLive()
    var armTool: GPUControlArmTool.Availability = .missing(buildPath: nil)
    var isArming = false
    var armFailed = false
    var remember = false
    /// `VersionInfo`, the kext's build name.
    var kextVersion: String?
    /// The controller exists (a channel was connected at launch).
    var canChoose = true

    init(facts: GPUControlFacts?, state: GPUControlPageState?, snapshot: GPUControlSnapshot?) {
        self.facts = facts
        self.state = state
        self.snapshot = snapshot
    }

    @MainActor init(service: GPUControlService) {
        facts = service.facts
        state = service.state
        snapshot = service.snapshot
        live = service.live
        armTool = service.armTool
        isArming = service.isArming
        armFailed = service.armFailed
        remember = service.remember
        kextVersion = service.control?.writing?.kextVersion
        canChoose = service.mode != .none
    }
}

struct GPUControlPageActions {
    var choosePower: (Int) -> Void = { _ in }
    var backToStartUp: () -> Void = {}
    var openWriting: () -> Void = {}
    var setRemember: (Bool) -> Void = { _ in }
}

extension GPUControlPageInput {
    /// A request is out, or waits to be tried again: the kext has not taken it.
    var isPending: Bool { GPUControlPageLogic.pending(snapshot) != nil }

    /// The state in words, for the page and (`short`) the panel row.
    func stateTitle(_ s: GPUControlPageStrings, short: Bool) -> String {
        if isPending { return s.applying }
        switch state {
        case .ready?: return s.ready
        case .closed?: return s.closed
        case .writingOff?: return s.writingOff
        case .waitingForDriver?, nil: return s.waitingForDriver
        case .reverting?: return s.reverting
        case .sleeping?: return s.sleeping
        case .heldByOther?: return s.heldByOther
        case .heldByApp(.power(let watts))?: return String(format: s.heldPowerFormat, Int(watts))
        // The whole list does not fit the panel row's two lines.
        case .heldByApp(.od8(let want))?: return short ? s.heldOD8Short : s.od8Held(want)
        case .heldByApp(.startUp)?: return s.ready
        case .connectionLost?: return short ? s.lost : s.connectionLost
        case .otherVersion(let version)?:
            return short ? s.otherVersion
                : String(format: s.otherVersionFormat, Int(clamping: version), Int(GPUControlWire.channelVersion))
        }
    }
}

/// One sentence for the page about the last thing that happened, with the
/// kext's own English text under it when there is one (plan 13).
struct GPUControlPageNote: Equatable {
    var sentence: String
    var kextText: String?
    var isProblem: Bool

    static func make(_ snapshot: GPUControlSnapshot?, _ s: GPUControlPageStrings) -> GPUControlPageNote? {
        guard let snapshot else { return nil }
        if case .afterWake(.power(let watts)) = snapshot.activity {
            return GPUControlPageNote(sentence: String(format: s.reaskingFormat, Int(watts)), kextText: nil, isProblem: false)
        }
        switch snapshot.outcome {
        case .refused(_, let answer)?:
            let group = GPUControlTextGroup.forReply(answer.replyCode, check: answer.checkCode)
            return GPUControlPageNote(sentence: group.map(s.sentence) ?? answer.kextText,
                                      kextText: group == nil ? nil : answer.kextText, isProblem: true)
        case .gaveUp(_, let wait)?:
            let reply: GPUControlReply
            switch wait {
            case .reply(let r): reply = r
            case .notReady: reply = .notReady
            case .sleeping: reply = .sleeping
            case .reverting: reply = .busy
            }
            let group = GPUControlTextGroup.forReply(reply.rawValue) ?? .notReady
            return GPUControlPageNote(sentence: String(format: s.gaveUpFormat, s.sentence(group)),
                                      kextText: reply.kextText, isProblem: true)
        case .closed?: return GPUControlPageNote(sentence: s.closedGroup, kextText: nil, isProblem: true)
        case .otherProgram?: return GPUControlPageNote(sentence: s.heldByOther, kextText: nil, isProblem: true)
        case .od8NotRead?: return GPUControlPageNote(sentence: s.od8NotRead, kextText: nil, isProblem: true)
        case .timedOut?:
            return GPUControlPageNote(sentence: s.timedOut, kextText: GPUControlReply.timeout.kextText, isProblem: true)
        case .notConfirmed?: return GPUControlPageNote(sentence: s.notConfirmed, kextText: nil, isProblem: true)
        case .lost?: return GPUControlPageNote(sentence: s.lost, kextText: nil, isProblem: false)
        case .backAfterWake?: return GPUControlPageNote(sentence: s.backAfterWake, kextText: nil, isProblem: false)
        case .backToStartUp?: return GPUControlPageNote(sentence: s.backToStartUp, kextText: nil, isProblem: false)
        case .alreadyAtStartUp?: return GPUControlPageNote(sentence: s.alreadyAtStartUp, kextText: nil, isProblem: false)
        case nil: return nil
        }
    }
}

/// The page itself.
struct GPUControlPageContent: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let title: String
    let actions: GPUControlPageActions
    @State private var copied = false

    private var s: GPUControlPageStrings { strings }

    var body: some View {
        Form {
            stateSection
            if showsPower { powerSection }
            if case .closed? = input.state { armSection }
            rememberSection
            detailsSection
        }
        .formStyle(.grouped)
    }

    // MARK: Status

    /// "Feedback": the state next to what it describes; never color alone
    /// ("Color", "Accessibility"): a symbol and a text.
    private var stateSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: stateSymbol.name)
                    .foregroundStyle(stateSymbol.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateTitle)
                    if let detail = stateDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let live = liveText {
                LabeledContent(s.liveLabel) {
                    Text(live).monospacedDigit()
                }
            }
        } header: {
            Text(s.stateSection)
        } footer: {
            if case .ready? = input.state {
                Text(s.readyWarning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateSymbol: (name: String, color: Color) {
        if input.isPending { return ("clock", .secondary) }
        switch input.state {
        case .ready?: return ("checkmark.circle", .green)
        case .heldByApp?: return ("gauge.with.dots.needle.33percent", .accentColor)
        case .closed?: return ("lock", .secondary)
        case .heldByOther?: return ("person.crop.circle.badge.exclamationmark", .orange)
        case .reverting?, .sleeping?, .waitingForDriver?: return ("clock", .secondary)
        case .writingOff?, .connectionLost?, .otherVersion?: return ("exclamationmark.triangle", .orange)
        case nil: return ("questionmark.circle", .secondary)
        }
    }

    private var stateTitle: String { input.stateTitle(s, short: false) }

    /// The reason under the state: the kext's own words while writing is
    /// off; "restart the Mac" only when the card may not be at stock.
    private var stateDetail: String? {
        guard case .writingOff(let reason, let text, let restart)? = input.state else { return nil }
        let group = reason.flatMap { GPUControlTextGroup.forWriteOff($0.rawValue) }
        var lines: [String] = []
        if restart {
            lines.append(s.restartMac)
        } else if let group {
            lines.append(s.sentence(group))
        }
        // The kext's words under the translation, unless the sentence above
        // already says them (English: "Off: <the kext's text>").
        if let text, !text.isEmpty,
           !lines.contains(where: { $0.lowercased().contains(text.lowercased()) }) { lines.append(text) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private var liveText: String? {
        func watts(_ value: Double?) -> String {
            value.map { String(format: s.wattsFormat, Int($0.rounded())) } ?? "–"
        }
        let fan = input.live.fanRPM.map { "\(Int($0.rounded())) RPM" } ?? "–"
        let hot = input.live.hotspotC.map { "\(Int($0.rounded())) °C" } ?? "–"
        guard input.live != GPUControlLive() else { return nil }
        return String(format: s.liveFormat, watts(input.live.boardW), fan, hot)
    }

    // MARK: Power limit

    private var showsPower: Bool {
        switch input.state {
        case .ready?, .heldByApp?, .heldByOther?, .reverting?, .sleeping?: return true
        default: return false
        }
    }

    /// "Pop-up buttons": a short list of exclusive choices. "Entering data":
    /// offer choices instead of typing. Applies when chosen, like AMD Power
    /// and System Settings ("Sliders", macOS: show the result as it changes).
    private var powerSection: some View {
        let choices = GPUControlPageLogic.powerChoices(bootW: input.facts?.bootW)
        let shown = input.facts.flatMap { GPUControlPageLogic.shownWatts(facts: $0, snapshot: input.snapshot) }
        // While a request is out or waits, the kext has not taken it: no
        // second choice until it answers.
        let enabled = input.canChoose && (input.state?.acceptsChoices ?? false) && !input.isPending
        let holding: Bool = {
            if case .heldByApp? = input.state { return true }
            return false
        }()
        let note = GPUControlPageNote.make(input.snapshot, s)
        return Section {
            Picker(s.powerLabel, selection: Binding(
                get: { shown ?? choices.first ?? 0 },
                set: { actions.choosePower($0) })) {
                ForEach(choices, id: \.self) { watts in
                    Text(watts == choices.first ? String(format: s.bootFormat, watts) : String(format: s.wattsFormat, watts))
                        .tag(watts)
                }
            }
            .pickerStyle(.menu)
            .disabled(!enabled || choices.isEmpty)
            if let note {
                // "Writing": the error next to the problem, with what to do.
                VStack(alignment: .leading, spacing: 2) {
                    Label(note.sentence, systemImage: note.isProblem ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(note.isProblem ? Color.orange : Color.secondary)
                    if let kext = note.kextText {
                        Text(kext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // "Alerts": no alert for a common, repeatable action; the safe
            // action is a plain button.
            HStack {
                Spacer()
                Button(s.backToBoot) { actions.backToStartUp() }
                    .disabled(!input.canChoose || !holding)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.powerFooter)
                Text(s.exclusiveNote)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Remembering (plan 8)

    /// Its own section: it can be set while writing is still closed.
    /// "Toggles", macOS: a small switch per row, its label says what turning
    /// it on does.
    private var rememberSection: some View {
        Section {
            Toggle(s.rememberToggle, isOn: Binding(get: { input.remember }, set: { actions.setRemember($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
        } footer: {
            Text(s.rememberFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Opening writing (plan 4)

    private var armSection: some View {
        Section {
            Text(s.armClosed)
                .fixedSize(horizontal: false, vertical: true)
            switch input.armTool {
            case .button:
                HStack {
                    if input.isArming { ProgressView().controlSize(.small) }
                    Spacer()
                    // "Buttons": the primary role goes to the button people
                    // are most likely to choose. While the control is closed
                    // this is the only action on the page. No Return key: it
                    // raises the administrator password dialog.
                    Button(s.openWriting) { actions.openWriting() }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.isArming || !input.canChoose)
                }
            case .unsafe(let reason, let path):
                VStack(alignment: .leading, spacing: 2) {
                    // One sentence for the rule, then the reason: each
                    // language joins them its own way (no space after 。).
                    Text(String(format: s.unsafeToolFormat, s.sentence(reason)))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                commandRow(input.armTool.command)
            case .missing(let buildPath):
                if buildPath == nil {
                    Text(s.notInstalled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                commandRow(input.armTool.command)
            }
            if input.armFailed {
                Label(s.armFailed, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func commandRow(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.runInTerminal)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(copied ? s.copied : s.copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
            }
        }
        // "Copied" goes back to "Copy" after 2 s, and when the command changes.
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
        .onChange(of: command) { _, _ in copied = false }
    }

    // MARK: Details

    /// "Disclosure controls": the counts and versions stay out of the way
    /// until needed; the header row toggles the whole group.
    private var detailsSection: some View {
        Section {
            DisclosureGroup(s.detailsSection) {
                if let changes = input.facts?.changes {
                    LabeledContent(s.changes) { Text("\(changes)").monospacedDigit() }
                }
                if let reverts = input.facts?.reverts {
                    LabeledContent(s.reverts) { Text("\(reverts)").monospacedDigit() }
                }
                if let version = input.kextVersion {
                    LabeledContent(s.kextVersion) { Text(version).font(.system(.body, design: .monospaced)) }
                }
                if let status = input.snapshot?.status {
                    LabeledContent(s.channel) { Text("\(status.version)").monospacedDigit() }
                }
                if input.facts?.od8Ready == false {
                    LabeledContent("OD8") {
                        Text(input.facts?.od8ReadText ?? s.od8NotRead)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
