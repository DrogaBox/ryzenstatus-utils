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
            fan: FeatureStrings.gpuControlFan(l10n.language),
            clock: FeatureStrings.gpuControlClock(l10n.language),
            title: FeatureStrings.gpuControl(l10n.language).title,
            actions: GPUControlPageActions(
                choosePower: { service.choosePower($0) },
                backToStartUp: { service.backToStartUp() },
                openWriting: { service.openWriting(prompt: FeatureStrings.gpuControlPage(l10n.language).armPrompt) },
                setRemember: { service.remember = $0 },
                applyFan: { service.applyFan($0) },
                chooseGfxMax: { service.chooseGfxMax($0) },
                closeChanges: { service.closeChanges() }))
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
    var armTool: GPUControlArmTool.Availability = .missing
    var isArming = false
    var armFailed = false
    var remember = false
    /// `VersionInfo`, the kext's build name.
    var kextVersion: String?
    /// The controller exists (a channel was connected at launch).
    var canChoose = true
    /// The write keys of the last read: the OD8 table and the kext's build
    /// name, for the curve editor's preview.
    var writing: GPUControlStatus.Writing?
    /// The editor's starting draft; nil starts from what is held, or from
    /// the tested curve.
    var fanDraft: GPUControlFanDraft?

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
        writing = service.control?.writing
    }
}

struct GPUControlPageActions {
    var choosePower: (Int) -> Void = { _ in }
    var backToStartUp: () -> Void = {}
    var openWriting: () -> Void = {}
    var setRemember: (Bool) -> Void = { _ in }
    var applyFan: (GPUControlFanDraft) -> Void = { _ in }
    var chooseGfxMax: (Int?) -> Void = { _ in }
    var closeChanges: () -> Void = {}
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
        case .readOnlyCard?: return s.readOnlyTitle
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

extension GPUControlPageNote {
    /// What the last "close changes" came to. "Closed" only while the page
    /// shows the closed state: after writing opens again it is old news.
    static func closing(_ closing: GPUControlClosing?, state: GPUControlPageState?,
                        _ s: GPUControlPageStrings) -> GPUControlPageNote? {
        switch closing {
        case .closed?:
            guard case .closed? = state else { return nil }
            return GPUControlPageNote(sentence: s.closedAgain, kextText: nil, isProblem: false)
        case .refused(let answer)?:
            let group = GPUControlTextGroup.forReply(answer.replyCode)
            return GPUControlPageNote(sentence: group.map(s.sentence) ?? answer.kextText,
                                      kextText: group == nil ? nil : answer.kextText, isProblem: true)
        case .notSupported?:
            return GPUControlPageNote(sentence: s.closeNotSupported, kextText: nil, isProblem: false)
        case .waiting?, nil:
            return nil
        }
    }
}

/// The page itself.
struct GPUControlPageContent: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let fan: GPUControlFanStrings
    let clock: GPUControlClockStrings
    let title: String
    let actions: GPUControlPageActions
    @State private var copied = false
    /// The editor's draft; its `edited` flag says whether the owner touched
    /// it since it was last seeded or applied.
    @State private var draft: GPUControlFanDraft
    @State private var lastOD8Source: GPUControlOD8Source = .fan

    init(input: GPUControlPageInput, strings: GPUControlPageStrings, fan: GPUControlFanStrings,
         clock: GPUControlClockStrings, title: String, actions: GPUControlPageActions) {
        self.input = input
        self.strings = strings
        self.fan = fan
        self.clock = clock
        self.title = title
        self.actions = actions
        var held: GPUControlOD8Want?
        if case .heldByApp(.od8(let want))? = input.state { held = want }
        _draft = State(initialValue: input.fanDraft ?? GPUControlFanDraft(held: held))
    }

    /// The fan part of the OD8 state the app holds (stock when none).
    private static func heldFan(_ input: GPUControlPageInput) -> GPUControlOD8Want {
        guard case .heldByApp(.od8(let want))? = input.state else { return .stock }
        return GPUControlOD8Want(curve: want.curve, zeroRpmOff: want.zeroRpmOff)
    }

    private var s: GPUControlPageStrings { strings }

    var body: some View {
        Form {
            stateSection
            if showsPower { powerSection }
            if showsPower, input.facts?.od8Ready == true {
                GPUControlFanSection(input: input, strings: strings, fan: fan, draft: $draft,
                                     lastOD8Source: $lastOD8Source, apply: actions.applyFan)
            }
            if showsPower {
                GPUControlClockSection(input: input, strings: strings, clock: clock,
                                       lastOD8Source: $lastOD8Source, choose: actions.chooseGfxMax)
            }
            if case .closed? = input.state { armSection }
            rememberSection
            detailsSection
        }
        .formStyle(.grouped)
        // "VoiceOver": "Inform VoiceOver when visible content or layout
        // changes occur": the state line changes on its own (a11y A2).
        .onChange(of: stateTitle) { _, title in
            AccessibilityNotification.Announcement(title).post()
        }
        // What is held changed (the first status after the page appeared, a
        // remembered state, a wake, the kext going back): an editor the owner
        // has not touched follows it, so Apply never gives back a hold the
        // page did not show; an edit stays, even one set back to the
        // seeded values.
        .onChange(of: Self.heldFan(input)) { _, held in
            draft = draft.following(held: held)
        }
    }

    // MARK: Status

    /// "Feedback": the state next to what it describes; never color alone
    /// ("Color", "Accessibility"): a symbol and a text.
    private var stateSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                // The text next to it says the state (a11y A5).
                Image(systemName: stateSymbol.name)
                    .foregroundStyle(stateSymbol.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
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
            if let note = GPUControlPageNote.closing(input.snapshot?.closing, state: input.state, s) {
                noteView(note)
            }
            if showsClose { closeRow }
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
        case .readOnlyCard?: return ("eye", .secondary)
        case .heldByOther?: return ("person.crop.circle.badge.exclamationmark", .orange)
        case .reverting?, .sleeping?, .waitingForDriver?: return ("clock", .secondary)
        case .writingOff?, .connectionLost?, .otherVersion?: return ("exclamationmark.triangle", .orange)
        case nil: return ("questionmark.circle", .secondary)
        }
    }

    private var stateTitle: String { input.stateTitle(s, short: false) }

    /// The reason under the state: the kext's own words while writing is
    /// off; "restart the Mac" only when the card may not be at stock; why a
    /// read-only card shows nothing to change; that another program changed
    /// the GPU (security review S-5).
    private var stateDetail: String? {
        if case .readOnlyCard? = input.state { return s.readOnlyDetail }
        if case .heldByOther? = input.state { return s.otherProgramChanged }
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

    /// Also on the read-only card: its values show, disabled, with the
    /// reason in the state above (plan A6).
    private var showsPower: Bool {
        switch input.state {
        case .ready?, .heldByApp?, .heldByOther?, .reverting?, .sleeping?, .readOnlyCard?: return true
        default: return false
        }
    }

    // MARK: Closing changes (kext 0.8.0)

    /// "Close changes": shown only while writing is open, with a kext that
    /// can close it; pressable unless something is on its way (a request, a
    /// close, a way back, a sleep).
    static func closeButton(_ input: GPUControlPageInput) -> (shown: Bool, enabled: Bool) {
        guard let facts = input.facts, facts.canDisarm, facts.armed, !facts.off else { return (false, false) }
        let waiting = input.snapshot?.closing == .waiting
        var busy = false
        switch input.state {
        case .reverting?, .sleeping?: busy = true
        default: break
        }
        return (true, input.canChoose && !input.isPending && !waiting && !busy)
    }

    private var showsClose: Bool { Self.closeButton(input).shown }

    /// "Buttons": a plain push button, not the primary role (that stays with
    /// what the page is for) and not destructive (closing deletes nothing and
    /// only makes the card safer); no Return key. Its help says what it does.
    private var closeRow: some View {
        HStack {
            if input.snapshot?.closing == .waiting { ProgressView().controlSize(.small) }
            Spacer()
            Button(s.closeChanges) { actions.closeChanges() }
                .help(s.closeChangesHelp)
                .disabled(!Self.closeButton(input).enabled)
        }
    }

    private func noteView(_ note: GPUControlPageNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GPUControlProblemLabel(text: note.sentence, isProblem: note.isProblem)
            if let kext = note.kextText {
                Text(kext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The card's own limits under the pop-up (kext 0.8.0's `PowerRange`).
    @ViewBuilder
    private func limitsRow(_ limits: GPUControlPowerLimits) -> some View {
        switch limits {
        case .range(let floor, let top):
            Text(String(format: s.cardRangeFormat, floor, top))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .nothingToLower:
            Text(s.nothingToLower)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .unknown:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.floorUnknown)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = input.facts?.powerRangeState {
                    Text(why).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    /// "Pop-up buttons": a short list of exclusive choices. "Entering data":
    /// offer choices instead of typing. Applies when chosen, like AMD Power
    /// and System Settings ("Sliders", macOS: show the result as it changes).
    private var powerSection: some View {
        let choices = GPUControlPageLogic.powerChoices(facts: input.facts, state: input.state)
        let limits = GPUControlPageLogic.limits(bootW: input.facts?.bootW, range: input.facts?.powerRange)
        let shown = input.facts.flatMap { GPUControlPageLogic.shownWatts(facts: $0, snapshot: input.snapshot) }
        // While a request is out or waits, the kext has not taken it: no
        // second choice until it answers.
        let enabled = input.canChoose && (input.state?.acceptsChoices ?? false) && !input.isPending
        let holding: Bool = {
            if case .heldByApp? = input.state { return true }
            return false
        }()
        // A refusal of a fan request shows in the fan section instead.
        var note = GPUControlPageNote.make(input.snapshot, s)
        if case .refused(let request, _)? = input.snapshot?.outcome, request.isOD8 { note = nil }
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
            if let limits { limitsRow(limits) }
            if let note {
                // "Writing": the error next to the problem, with what to do.
                noteView(note)
            }
            if case .heldByApp(.od8(let held))? = input.state {
                // "Writing": what choosing a limit does, before it is chosen.
                Label(held.curve == nil && !held.zeroRpmOff ? clock.noteClockHeld : fan.noteCurveHeld,
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
    /// "Toggles", macOS: within a grouped form, a mini switch per row (as in
    /// the fan section); its label says what turning it on does.
    private var rememberSection: some View {
        Section {
            Toggle(s.rememberToggle, isOn: Binding(get: { input.remember }, set: { actions.setRemember($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
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
            case .missing:
                Text(s.notInstalled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                commandRow(input.armTool.command)
            }
            if input.armFailed {
                GPUControlProblemLabel(text: s.armFailed, isProblem: true)
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

/// A note's line: the symbol carries the colour, the text stays legible
/// (a11y A1: orange text on the grouped background is below 4.5:1).
/// "Accessibility": never colour alone; the symbol and the words say it.
struct GPUControlProblemLabel: View {
    let text: String
    let isProblem: Bool

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(isProblem ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isProblem ? "exclamationmark.circle" : "info.circle")
                .foregroundStyle(isProblem ? Color.orange : Color.secondary)
        }
    }
}
