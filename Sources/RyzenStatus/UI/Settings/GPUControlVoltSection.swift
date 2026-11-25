// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The GFX voltage section of Settings > GPU control (GPUSensors 0.9.0),
/// built like the clock sections (`GPUControlClockMinSection`): a switch,
/// then a slider from the card's lowest 25 mV step up to stock with a field
/// and a stepper. Only ever lower than stock. Under it, the recommended
/// starting point (one step below stock, from the card's own table) with a
/// button that puts it into the control and never sends it, and the button
/// that sends what the control shows. The page shows it only when the kext
/// takes a voltage and the card offers one, and never on a card that can
/// only be read.
struct GPUControlVoltSection: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let clock: GPUControlClockStrings
    let overclock: GPUControlOverclockStrings
    /// The section that asked last, so a refusal shows next to its control.
    @Binding var lastOD8Source: GPUControlOD8Source
    let choose: (Int?) -> Void

    @State private var on: Bool
    @State private var draft: Int
    @State private var fieldText = ""
    @State private var outOfRange = false

    init(input: GPUControlPageInput, strings: GPUControlPageStrings, clock: GPUControlClockStrings,
         overclock: GPUControlOverclockStrings, lastOD8Source: Binding<GPUControlOD8Source>,
         choose: @escaping (Int?) -> Void) {
        self.input = input
        self.strings = strings
        self.clock = clock
        self.overclock = overclock
        _lastOD8Source = lastOD8Source
        self.choose = choose
        let held = Self.heldMV(input)
        _on = State(initialValue: held != nil)
        _draft = State(initialValue: held ?? Self.limits(input)?.stock ?? 0)
    }

    private static func heldMV(_ input: GPUControlPageInput) -> Int? {
        if case .heldByApp(.od8(let want))? = input.state { return want.voltMV }
        return nil
    }

    private static func limits(_ input: GPUControlPageInput) -> GPUControlVoltLogic.Limits? {
        GPUControlVoltLogic.limits(writing: input.writing, od8Ready: input.facts?.od8Ready == true)
    }

    /// The page shows this section only when the kext takes a voltage, the
    /// card offers one below stock, and writing can open on the card.
    static func shows(_ input: GPUControlPageInput) -> Bool {
        if case .readOnlyCard? = input.state { return false }
        return limits(input) != nil
    }

    /// The starting point the section offers, nil when there is none.
    static func recommendedMV(_ input: GPUControlPageInput) -> Int? {
        GPUControlVoltLogic.recommended(limits(input))
    }

    private var range: ClosedRange<Int>? { GPUControlVoltLogic.range(Self.limits(input)) }
    private var stock: Int? { Self.limits(input)?.stock }

    private var enabled: Bool { usable && !input.isPending }

    /// As the clock sections: the slider stays usable while its own request
    /// waits (a11y A3).
    private var usable: Bool {
        range != nil && input.canChoose && (input.state?.acceptsChoices ?? false)
    }

    /// The value in force: the one held, else stock.
    private var inForce: Int? { Self.heldMV(input) ?? stock }

    var body: some View {
        Section {
            Toggle(overclock.voltToggle, isOn: Binding(get: { on }, set: { switched($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!enabled)
            if on, let range, let stock {
                voltRow(range: range, stock: stock)
            }
            if let recommended = Self.recommendedMV(input) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: overclock.voltRecommendedFormat, recommended))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    // Puts the starting point into the control; nothing is
                    // sent until Apply.
                    Button(overclock.voltUseRecommended) { useRecommended(recommended) }
                        .disabled(!enabled)
                }
            }
            if on, let stock {
                HStack {
                    Spacer()
                    Button(overclock.voltApply) { send(draft, stock: stock) }
                        .disabled(!enabled || draft == inForce)
                }
            }
            if case .heldByApp(.power)? = input.state {
                Label(clock.notePowerHeld, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if lastOD8Source == .volt, case .switching(.od8)? = input.snapshot?.activity {
                Label(clock.switching, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            if outOfRange, let range {
                GPUControlProblemLabel(text: String(format: overclock.voltOutOfRangeFormat, range.lowerBound,
                                                    range.upperBound, GPUControlVoltLogic.step),
                                       isProblem: true)
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
            Text(overclock.voltSection)
        } footer: {
            Text(overclock.voltFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft) { _, value in fieldText = "\(value)" }
        // What is held changed on its own: the switch and the value follow
        // it, unless a request still waits.
        .onChange(of: Self.heldMV(input)) { _, held in
            guard !input.isPending else { return }
            on = held != nil
            draft = held ?? stock ?? draft
        }
        .onAppear { fieldText = "\(draft)" }
    }

    private var refusal: GPUControlPageNote? {
        guard lastOD8Source == .volt, case .refused(let request, _)? = input.snapshot?.outcome,
              request.isOD8 else { return nil }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: The row

    /// VoiceOver's names for the row's three controls, each its own.
    static func accessibilityNames(_ overclock: GPUControlOverclockStrings)
        -> (slider: String, field: String, stepper: String) {
        (overclock.voltSection, overclock.voltFieldLabel,
         String(format: overclock.voltStepperFormat, GPUControlVoltLogic.step))
    }

    private func voltRow(range: ClosedRange<Int>, stock: Int) -> some View {
        let names = Self.accessibilityNames(overclock)
        let reason = GPUControlPageContent.disabledReason(input, strings)
        let slider = GPUControlTickSlider(value: draft, range: range,
                                          ticks: GPUControlVoltLogic.tickCount(range: range),
                                          label: names.slider,
                                          help: Self.sliderHelp(overclock, range: range),
                                          valueDescription: GPUControlPageContent.accessibilityValue(
                                            "\(draft) mV", reason: usable ? nil : reason, strings),
                                          onChange: { draft = GPUControlVoltLogic.snapped($0, range: range) },
                                          onRelease: { send(draft, stock: stock) })
        let entry = HStack(spacing: 8) {
            TextField(names.field, text: $fieldText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 56)
                .fixedSize(horizontal: true, vertical: false)
                .onSubmit { commitField(stock: stock) }
                .accessibilityLabel(names.field)
            Stepper(names.stepper, value: Binding(get: { draft }, set: { value in
                draft = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
                send(draft, stock: stock)
            }), in: range, step: GPUControlVoltLogic.step)
                .labelsHidden()
                .accessibilityLabel(names.stepper)
                .accessibilityValue(GPUControlPageContent.accessibilityValue(
                    "\(draft) mV", reason: enabled ? nil : reason, strings))
            Text("mV").foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    slider.frame(minWidth: GPUControlClockSection.sliderMinWidth).disabled(!usable)
                    entry
                }
                VStack(alignment: .trailing, spacing: 4) {
                    slider.disabled(!usable)
                    entry
                }
            }
            // Stock at the trailing end, where the slider starts from, as
            // the maximum clock's.
            HStack {
                Text(verbatim: "\(range.lowerBound) mV")
                Spacer()
                Text(String(format: overclock.voltStockFormat, stock))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The slider's help: its two ends, as written under it, and what
    /// moving it does.
    static func sliderHelp(_ overclock: GPUControlOverclockStrings, range: ClosedRange<Int>) -> String {
        String(format: overclock.voltSliderHelpFormat, range.lowerBound, range.upperBound)
    }

    // MARK: Sending

    private func switched(_ value: Bool) {
        on = value
        outOfRange = false
        // Turning it on shows the control and sends nothing: the stock
        // voltage is not a hold. Turning it off puts the stock voltage back,
        // keeping the rest of a held OD8 state in the same request.
        if !value {
            lastOD8Source = .volt
            choose(nil)
            if let stock { draft = stock }
        }
    }

    /// The starting point goes into the control only: the owner sends it
    /// with Apply, the slider or the field.
    private func useRecommended(_ mv: Int) {
        outOfRange = false
        on = true
        draft = mv
        fieldText = "\(mv)"
    }

    private func commitField(stock: Int) {
        // Outside the range or off a step: not sent and not clamped; the
        // field says what it takes.
        guard let value = Int(fieldText.trimmingCharacters(in: .whitespaces)),
              value == stock || GPUControlVoltLogic.lowers(value, limits: Self.limits(input)) else {
            outOfRange = true
            return
        }
        draft = value
        send(value, stock: stock)
    }

    private func send(_ value: Int, stock: Int) {
        outOfRange = false
        lastOD8Source = .volt
        choose(GPUControlVoltLogic.request(value, stockMV: stock))
    }
}
