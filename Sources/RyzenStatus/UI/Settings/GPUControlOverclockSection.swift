// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The Overclock section of Settings > GPU control (GPUSensors 0.9.0): a
/// switch, off by default, with a plain warning under it. When it is on, and
/// each only when the kext and the card offer it: a GFX maximum above stock
/// up to the card's own maximum (built like the clock sections: a slider, a
/// field and a stepper; sent with the overclock flag), and a power limit
/// above the start-up one up to the card's ceiling (a pop-up like the power
/// section's; sent with `set`'s raise form). Turning the switch off gives
/// back whatever it raised. No preset raises anything. Never on a card that
/// can only be read.
struct GPUControlOverclockSection: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let clock: GPUControlClockStrings
    let overclock: GPUControlOverclockStrings
    /// The section that asked last, so a refusal shows next to its control.
    @Binding var lastOD8Source: GPUControlOD8Source
    let setOn: (Bool) -> Void
    let chooseGfx: (Int?) -> Void
    let choosePower: (Int) -> Void

    @State private var draft: Int
    @State private var fieldText = ""
    @State private var outOfRange = false

    init(input: GPUControlPageInput, strings: GPUControlPageStrings, clock: GPUControlClockStrings,
         overclock: GPUControlOverclockStrings, lastOD8Source: Binding<GPUControlOD8Source>,
         setOn: @escaping (Bool) -> Void, chooseGfx: @escaping (Int?) -> Void, choosePower: @escaping (Int) -> Void) {
        self.input = input
        self.strings = strings
        self.clock = clock
        self.overclock = overclock
        _lastOD8Source = lastOD8Source
        self.setOn = setOn
        self.chooseGfx = chooseGfx
        self.choosePower = choosePower
        _draft = State(initialValue: Self.heldMHz(input) ?? Self.gfxLimits(input)?.stock ?? 0)
    }

    /// A raised GFX maximum the app holds (the overclock flag with it).
    static func heldMHz(_ input: GPUControlPageInput) -> Int? {
        if case .heldByApp(.od8(let want))? = input.state, want.overclock { return want.gfxMaxMHz }
        return nil
    }

    static func gfxLimits(_ input: GPUControlPageInput) -> GPUControlOverclockLogic.GfxLimits? {
        GPUControlOverclockLogic.gfxLimits(writing: input.writing, od8Ready: input.facts?.od8Ready == true)
    }

    /// The raised pop-up's values; empty when the card offers nothing above
    /// the start-up limit or the kext takes no raise.
    static func powerChoices(_ input: GPUControlPageInput) -> [Int] {
        GPUControlOverclockLogic.powerChoices(bootW: input.facts?.bootW,
                                              ceilW: GPUControlOverclockLogic.ceilingW(facts: input.facts),
                                              stepW: input.facts?.powerRange?.stepW ?? GPUControlWire.powerStepW)
    }

    /// The page shows this section when the kext and the card offer at
    /// least one raise, and writing can open on the card.
    static func shows(_ input: GPUControlPageInput) -> Bool {
        if case .readOnlyCard? = input.state { return false }
        return gfxLimits(input) != nil || !powerChoices(input).isEmpty
    }

    private var takesChoices: Bool { input.canChoose && (input.state?.acceptsChoices ?? false) }
    private var enabled: Bool { takesChoices && !input.isPending }

    var body: some View {
        Section {
            // "Toggles": the label says what turning it on does. Off by
            // default; it can be turned off at any time.
            Toggle(overclock.ocToggle, isOn: Binding(get: { input.overclock }, set: { setOn($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!input.canChoose || (!input.overclock && !enabled))
            Text(overclock.ocWarning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if input.overclock {
                if let limits = Self.gfxLimits(input) {
                    gfxRow(limits)
                }
                let choices = Self.powerChoices(input)
                if !choices.isEmpty { powerRow(choices) }
            }
            if lastOD8Source == .overclock, case .switching(.od8)? = input.snapshot?.activity {
                Label(clock.switching, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            if let note = refusal {
                VStack(alignment: .leading, spacing: 2) {
                    GPUControlProblemLabel(text: note.sentence, isProblem: true)
                    if let kext = note.kextText {
                        Text(String(format: strings.kextSaysFormat, kext))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text(overclock.ocSection)
        } footer: {
            Text(overclock.ocFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft) { _, value in fieldText = "\(value)" }
        .onChange(of: Self.heldMHz(input)) { _, held in
            guard !input.isPending else { return }
            draft = held ?? Self.gfxLimits(input)?.stock ?? draft
        }
        .onAppear { fieldText = "\(draft)" }
    }

    /// A refusal of the raised GFX maximum (an OD8 request this section
    /// sent), or of a raised power limit.
    private var refusal: GPUControlPageNote? {
        guard case .refused(let request, _)? = input.snapshot?.outcome else { return nil }
        if request.isOD8 {
            guard lastOD8Source == .overclock else { return nil }
        } else if case .power(let watts) = request {
            guard GPUControlOverclockLogic.raisesPower(Int(watts), bootW: input.facts?.bootW) else { return nil }
        } else {
            return nil
        }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: The GFX maximum above stock

    /// VoiceOver's names for the row's three controls, each its own.
    static func accessibilityNames(_ overclock: GPUControlOverclockStrings)
        -> (slider: String, field: String, stepper: String) {
        (overclock.ocGfxLabel, overclock.ocGfxFieldLabel,
         String(format: overclock.ocGfxStepperFormat, GPUControlOverclockLogic.step))
    }

    private func gfxRow(_ limits: GPUControlOverclockLogic.GfxLimits) -> some View {
        let range = GPUControlOverclockLogic.gfxRange(limits)
        let names = Self.accessibilityNames(overclock)
        let reason = GPUControlPageContent.disabledReason(input, strings)
        let slider = GPUControlTickSlider(value: draft, range: range,
                                          ticks: GPUControlOverclockLogic.tickCount(range: range),
                                          label: names.slider,
                                          help: Self.sliderHelp(overclock, limits: limits),
                                          valueDescription: GPUControlPageContent.accessibilityValue(
                                            "\(draft) MHz", reason: takesChoices ? nil : reason, strings),
                                          onChange: { draft = GPUControlOverclockLogic.snapped($0, range: range) },
                                          onRelease: { send(draft, limits: limits) })
        let entry = HStack(spacing: 8) {
            TextField(names.field, text: $fieldText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 56)
                .fixedSize(horizontal: true, vertical: false)
                .onSubmit { commitField(limits: limits) }
                .accessibilityLabel(names.field)
            Stepper(names.stepper, value: Binding(get: { draft }, set: { value in
                draft = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
                send(draft, limits: limits)
            }), in: range, step: GPUControlOverclockLogic.step)
                .labelsHidden()
                .accessibilityLabel(names.stepper)
                .accessibilityValue(GPUControlPageContent.accessibilityValue(
                    "\(draft) MHz", reason: enabled ? nil : reason, strings))
            Text("MHz").foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        return VStack(alignment: .leading, spacing: 4) {
            Text(overclock.ocGfxLabel)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    slider.frame(minWidth: GPUControlClockSection.sliderMinWidth).disabled(!takesChoices)
                    entry
                }
                VStack(alignment: .trailing, spacing: 4) {
                    slider.disabled(!takesChoices)
                    entry
                }
            }
            // Stock at the leading end, where the slider starts.
            HStack {
                Text(String(format: clock.stockFormat, limits.stock))
                Spacer()
                Text(String(format: overclock.ocGfxTopFormat, limits.max))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if outOfRange {
                GPUControlProblemLabel(text: String(format: clock.outOfRangeFormat, range.lowerBound, range.upperBound),
                                       isProblem: true)
            }
        }
    }

    /// The slider's help: its two ends, as written under it, and what
    /// moving it does.
    static func sliderHelp(_ overclock: GPUControlOverclockStrings,
                           limits: GPUControlOverclockLogic.GfxLimits) -> String {
        String(format: overclock.ocGfxSliderHelpFormat, limits.stock, limits.max)
    }

    private func commitField(limits: GPUControlOverclockLogic.GfxLimits) {
        // Outside the range: not sent and not clamped; the row says what it
        // takes.
        guard let value = Int(fieldText.trimmingCharacters(in: .whitespaces)),
              GPUControlOverclockLogic.gfxRange(limits).contains(value) else {
            outOfRange = true
            return
        }
        draft = value
        send(value, limits: limits)
    }

    private func send(_ value: Int, limits: GPUControlOverclockLogic.GfxLimits) {
        outOfRange = false
        lastOD8Source = .overclock
        chooseGfx(GPUControlOverclockLogic.request(value, stockMHz: limits.stock))
    }

    // MARK: The power limit above the start-up one

    /// "Pop-up buttons", as the power section: applies when chosen. The
    /// start-up value is the way back.
    private func powerRow(_ choices: [Int]) -> some View {
        let shown = Self.shownWatts(input, choices: choices)
        return Picker(overclock.ocPowerLabel, selection: Binding(get: { shown }, set: { choosePower($0) })) {
            ForEach(choices, id: \.self) { watts in
                Text(watts == choices.first ? String(format: strings.bootFormat, watts)
                                            : String(format: strings.wattsFormat, watts))
                    .tag(watts)
            }
        }
        .pickerStyle(.menu)
        .disabled(!enabled)
        .accessibilityHint(overclock.ocPowerHint)
        .accessibilityValue(GPUControlPageContent.accessibilityValue(
            shown == choices.first ? String(format: strings.bootFormat, shown) : String(format: strings.wattsFormat, shown),
            reason: enabled ? nil : GPUControlPageContent.disabledReason(input, strings), strings))
    }

    /// The pop-up's value: a raised limit asked for or held, else the
    /// start-up value (a lower limit belongs to the power section).
    static func shownWatts(_ input: GPUControlPageInput, choices: [Int]) -> Int {
        let boot = choices.first ?? 0
        guard let facts = input.facts,
              let watts = GPUControlPageLogic.shownWatts(facts: facts, snapshot: input.snapshot),
              choices.contains(watts) else { return boot }
        return watts
    }
}
