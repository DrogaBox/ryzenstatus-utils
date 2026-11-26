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
            boot: FeatureStrings.gpuControlBoot(l10n.language),
            overclock: FeatureStrings.gpuControlOverclock(l10n.language),
            profile: FeatureStrings.gpuControlProfile(l10n.language),
            title: FeatureStrings.gpuControl(l10n.language).title,
            actions: GPUControlPageActions(
                choosePower: { service.choosePower($0) },
                backToStartUp: { service.backToStartUp() },
                openWriting: { service.openWriting(prompt: FeatureStrings.gpuControlPage(l10n.language).armPrompt) },
                setRemember: { service.remember = $0 },
                setBootArm: { on in
                    let boot = FeatureStrings.gpuControlBoot(l10n.language)
                    service.setBootArm(on, prompt: on ? boot.promptOn : boot.promptOff)
                },
                applyFan: { service.applyFan($0) },
                chooseGfxMax: { service.chooseGfxMax($0) },
                chooseGfxMin: { service.chooseGfxMin($0) },
                chooseVolt: { service.chooseVolt($0) },
                chooseGfxMaxRaised: { service.chooseGfxMaxRaised($0) },
                setOverclock: { service.overclock = $0 },
                closeChanges: { service.closeChanges() }),
            profileActions: GPUControlProfileActions(
                save: { service.saveProfile(named: $0) },
                load: { service.loadProfile($0) },
                rename: { service.renameProfile(named: $0, to: $1) },
                delete: { service.deleteProfile(named: $0) }))
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
    /// "Allow changes after restart too": the start-up daemon is installed.
    var bootArm = false
    var isChangingBootArm = false
    var bootArmFailed = false
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
    /// "Allow overclocking" (GPUSensors 0.9.0), off by default.
    var overclock = false
    /// The owner's saved GPU profiles, and the name of the one that is
    /// exactly what the card holds now (nil when none is).
    var profiles: [GPUControlProfile] = []
    var matchingProfile: String?
    /// The last profile loaded: what went out and what was left out.
    var profileLoad: GPUControlProfileLoad?

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
        bootArm = service.bootArm
        isChangingBootArm = service.isChangingBootArm
        bootArmFailed = service.bootArmFailed
        kextVersion = service.control?.writing?.kextVersion
        canChoose = service.mode != .none
        writing = service.control?.writing
        overclock = service.overclock
        profiles = service.profiles
        matchingProfile = service.matchingProfile
        profileLoad = service.profileLoad
    }
}

struct GPUControlPageActions {
    var choosePower: (Int) -> Void = { _ in }
    var backToStartUp: () -> Void = {}
    var openWriting: () -> Void = {}
    var setRemember: (Bool) -> Void = { _ in }
    var setBootArm: (Bool) -> Void = { _ in }
    var applyFan: (GPUControlFanDraft) -> Void = { _ in }
    var chooseGfxMax: (Int?) -> Void = { _ in }
    var chooseGfxMin: (Int?) -> Void = { _ in }
    var chooseVolt: (Int?) -> Void = { _ in }
    var chooseGfxMaxRaised: (Int?) -> Void = { _ in }
    var setOverclock: (Bool) -> Void = { _ in }
    var closeChanges: () -> Void = {}
}

extension GPUControlPageInput {
    /// A request is out, or waits to be tried again: the kext has not taken it.
    var isPending: Bool { GPUControlPageLogic.pending(snapshot) != nil }

    /// The hold is the gpucontrol this app installs, not another program
    /// (GPUControlHolder): the page says so, and it is no problem to report.
    var holderIsOwnTool: Bool { facts?.holder.isOwnTool ?? false }

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
        case .heldByOther?: return holderIsOwnTool ? s.heldByTool : s.heldByOther
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
    let boot: GPUControlBootStrings
    let overclock: GPUControlOverclockStrings
    let profile: GPUControlProfileStrings
    let title: String
    let actions: GPUControlPageActions
    let profileActions: GPUControlProfileActions
    @State private var copied = false
    /// The editor's draft; its `edited` flag says whether the owner touched
    /// it since it was last seeded or applied.
    @State private var draft: GPUControlFanDraft
    @State private var lastOD8Source: GPUControlOD8Source = .fan

    init(input: GPUControlPageInput, strings: GPUControlPageStrings, fan: GPUControlFanStrings,
         clock: GPUControlClockStrings, boot: GPUControlBootStrings = .enUS,
         overclock: GPUControlOverclockStrings = .enUS, profile: GPUControlProfileStrings = .enUS,
         title: String, actions: GPUControlPageActions,
         profileActions: GPUControlProfileActions = GPUControlProfileActions()) {
        self.input = input
        self.strings = strings
        self.fan = fan
        self.clock = clock
        self.boot = boot
        self.overclock = overclock
        self.profile = profile
        self.title = title
        self.actions = actions
        self.profileActions = profileActions
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
            // Right under the maximum: the two ends of the same clock range.
            if showsPower, GPUControlClockMinSection.shows(input) {
                GPUControlClockMinSection(input: input, strings: strings, clock: clock,
                                          lastOD8Source: $lastOD8Source, choose: actions.chooseGfxMin)
            }
            // GPUSensors 0.9.0: the voltage next to the clocks, then the
            // raises on their own, off by default. Neither on a card that can
            // only be read.
            if showsPower, GPUControlVoltSection.shows(input) {
                GPUControlVoltSection(input: input, strings: strings, clock: clock, overclock: overclock,
                                      lastOD8Source: $lastOD8Source, choose: actions.chooseVolt)
            }
            if showsPower, GPUControlOverclockSection.shows(input) {
                GPUControlOverclockSection(input: input, strings: strings, clock: clock, overclock: overclock,
                                           lastOD8Source: $lastOD8Source, setOn: actions.setOverclock,
                                           chooseGfx: actions.chooseGfxMaxRaised, choosePower: actions.choosePower)
            }
            if case .closed? = input.state { armSection }
            if Self.showsBootArm(input) { bootArmSection }
            rememberSection
            // Its own section, like "remember": the list is worth seeing even
            // on a card the control only reads.
            if showsPower || !input.profiles.isEmpty {
                GPUControlProfilesSection(input: input, strings: profile, page: s, actions: profileActions)
            }
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
                Text(input.bootArm ? boot.readyWarning : s.readyWarning)
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
        case .heldByOther?: return input.holderIsOwnTool
            ? ("gauge.with.dots.needle.33percent", .secondary)
            : ("person.crop.circle.badge.exclamationmark", .orange)
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
        // Our own gpucontrol holding a curve is not news, and not a problem.
        if case .heldByOther? = input.state { return input.holderIsOwnTool ? nil : s.otherProgramChanged }
        guard case .writingOff(let reason, let text, let restart)? = input.state else { return nil }
        let group = reason.flatMap { GPUControlTextGroup.forWriteOff($0.rawValue) }
        var lines: [String] = []
        if restart {
            lines.append(s.restartMac)
        } else if let group {
            lines.append(s.sentence(group))
        }
        // The kext's words under the translation, unless the sentence above
        // already says them (English: "Off: <the kext's text>"), said as the
        // kext's (a11y A13).
        if let text, !text.isEmpty, !lines.contains(where: { $0.lowercased().contains(text.lowercased()) }) {
            lines.append(String(format: s.kextSaysFormat, text))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private var liveText: String? { Self.liveText(input.live, s) }

    /// The live row; nil with no reading at all. A missing reading is a
    /// word, not a dash some screen readers say as "dash" (a11y A15).
    static func liveText(_ live: GPUControlLive, _ s: GPUControlPageStrings) -> String? {
        guard live != GPUControlLive() else { return nil }
        let watts = live.boardW.map { String(format: s.wattsFormat, Int($0.rounded())) } ?? s.noReading
        let fan = live.fanRPM.map { "\(Int($0.rounded())) RPM" } ?? s.noReading
        let hot = live.hotspotC.map { "\(Int($0.rounded())) °C" } ?? s.noReading
        return String(format: s.liveFormat, watts, fan, hot)
    }

    /// Why a control the page turned off is off, in the state's own words
    /// (closed, waiting for the driver, applying…): VoiceOver says "dimmed"
    /// and nothing else (a11y A14). Nil while the state takes choices.
    static func disabledReason(_ input: GPUControlPageInput, _ s: GPUControlPageStrings) -> String? {
        guard input.isPending || input.state?.acceptsChoices != true else { return nil }
        return input.stateTitle(s, short: true)
    }

    /// A control's own value, then why it is off, as one list.
    static func accessibilityValue(_ value: String, reason: String?, _ s: GPUControlPageStrings) -> String {
        guard let reason else { return value }
        return value.isEmpty ? reason : value + s.listSeparator + reason
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
                Text(String(format: s.kextSaysFormat, kext))
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
                    Text(String(format: s.kextSaysFormat, why)).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    /// "Pop-up buttons": a short list of exclusive choices. "Entering data":
    /// offer choices instead of typing. Applies when chosen, like AMD Power
    /// and System Settings ("Sliders", macOS: show the result as it changes).
    private var powerSection: some View {
        let lowerChoices = GPUControlPageLogic.powerChoices(facts: input.facts, state: input.state)
        let limits = GPUControlPageLogic.limits(bootW: input.facts?.bootW, range: input.facts?.powerRange)
        let shown = input.facts.flatMap { GPUControlPageLogic.shownWatts(facts: $0, snapshot: input.snapshot) }
        // A raised limit (held from the Overclock section) is not one of the
        // lower choices: listed so the menu shows what is in force.
        let choices = shown.map { lowerChoices.isEmpty || lowerChoices.contains($0) ? lowerChoices : lowerChoices + [$0] }
            ?? lowerChoices
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
        // A refused raise shows in the overclock section instead.
        if case .refused(.power(let watts), _)? = input.snapshot?.outcome,
           GPUControlOverclockSection.shows(input),
           GPUControlOverclockLogic.raisesPower(Int(watts), bootW: input.facts?.bootW) { note = nil }
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
            // a11y A6: what choosing does, before the range below is heard;
            // A14: why it is dimmed.
            .accessibilityHint(s.powerHint)
            .accessibilityValue(Self.accessibilityValue(
                (shown ?? choices.first).map { $0 == choices.first ? String(format: s.bootFormat, $0) : String(format: s.wattsFormat, $0) } ?? "",
                reason: enabled ? nil : Self.disabledReason(input, s), s))
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
    /// "Toggles": its label says what turning it on does. The regular size,
    /// not mini: "Accessibility" asks for controls of at least 20 x 20 pt
    /// on macOS (a11y A8, chosen over the mini switch "Toggles" suggests for
    /// grouped forms).
    private var rememberSection: some View {
        Section {
            Toggle(s.rememberToggle, isOn: Binding(get: { input.remember }, set: { actions.setRemember($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
        } footer: {
            Text(s.rememberFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: After a restart (GPUControlBootArm)

    /// Shown where opening writing is possible at all: the tool installed
    /// safely (the button), or the daemon already there, so it can always be
    /// turned off. Not on the read-only card, where writing never opens.
    static func showsBootArm(_ input: GPUControlPageInput) -> Bool {
        if input.bootArm { return true }
        if case .readOnlyCard? = input.state { return false }
        return input.armTool == .button
    }

    /// Turning it on needs the tool installed safely; off is always allowed.
    static func bootArmEnabled(_ input: GPUControlPageInput) -> Bool {
        guard !input.isChangingBootArm, input.canChoose else { return false }
        return input.bootArm || input.armTool == .button
    }

    /// "Toggles": the label says what turning it on does; the footer says
    /// the password is asked once and what turning it off leaves open. Its
    /// own section, like "remember": it can be set while writing is closed.
    /// The regular size, as "remember" (a11y A8).
    private var bootArmSection: some View {
        Section {
            // Dimmed while the administrator dialog is up: the dialog is the
            // feedback, and the switch shows the disk's state after it.
            Toggle(boot.toggle, isOn: Binding(get: { input.bootArm }, set: { actions.setBootArm($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!Self.bootArmEnabled(input))
                .accessibilityHint(boot.hint)
            if input.bootArmFailed {
                GPUControlProblemLabel(text: boot.failed, isProblem: true)
            }
        } footer: {
            Text(boot.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Opening writing (plan 4)

    private var armSection: some View {
        Section {
            Text(input.bootArm ? boot.armClosed : s.armClosed)
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
                        .accessibilityHint(s.openWritingHint)
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
                    // The label changes, but VoiceOver does not say so on
                    // its own (a11y A11).
                    AccessibilityNotification.Announcement(s.copied).post()
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
