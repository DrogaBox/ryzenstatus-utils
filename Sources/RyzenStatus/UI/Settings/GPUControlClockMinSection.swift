// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The GFX minimum clock section of Settings > GPU control (GPUSensors
/// 0.9.0), built like the maximum's (`GPUControlClockSection`): a switch,
/// then a slider from the stock minimum to the GFX maximum in force, with a
/// field and a stepper. Only ever higher than stock and never above the
/// maximum; the page shows it only when the kext takes a minimum.
struct GPUControlClockMinSection: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let clock: GPUControlClockStrings
    /// The section that asked last, so a refusal shows next to its control.
    @Binding var lastOD8Source: GPUControlOD8Source
    let choose: (Int?) -> Void

    @State private var on: Bool
    @State private var draft: Int
    @State private var fieldText = ""
    @State private var outOfRange = false

    init(input: GPUControlPageInput, strings: GPUControlPageStrings, clock: GPUControlClockStrings,
         lastOD8Source: Binding<GPUControlOD8Source>, choose: @escaping (Int?) -> Void) {
        self.input = input
        self.strings = strings
        self.clock = clock
        _lastOD8Source = lastOD8Source
        self.choose = choose
        let held = Self.heldMHz(input)
        _on = State(initialValue: held != nil)
        _draft = State(initialValue: held ?? Self.limits(input)?.stock ?? 0)
    }

    private static func heldMHz(_ input: GPUControlPageInput) -> Int? {
        if case .heldByApp(.od8(let want))? = input.state { return want.gfxMinMHz }
        return nil
    }

    private static func limits(_ input: GPUControlPageInput) -> GPUControlClockMinLogic.Limits? {
        GPUControlClockMinLogic.limits(writing: input.writing, od8Ready: input.facts?.od8Ready == true)
    }

    /// The page shows this section only when the kext takes a minimum.
    static func shows(_ input: GPUControlPageInput) -> Bool { limits(input) != nil }

    /// The GFX maximum in force: the lowered one the app holds, else stock.
    static func topMHz(_ input: GPUControlPageInput) -> Int? {
        if case .heldByApp(.od8(let want))? = input.state, let mhz = want.gfxMaxMHz { return mhz }
        return input.writing?.od8?.stockGfxMaxMHz
    }

    private var range: ClosedRange<Int>? {
        GPUControlClockMinLogic.range(limits: Self.limits(input), gfxMaxMHz: Self.topMHz(input))
    }
    private var stock: Int? { Self.limits(input)?.stock }

    private var enabled: Bool { usable && !input.isPending }

    /// As the maximum's: the slider stays usable while its own request
    /// waits (a11y A3).
    private var usable: Bool {
        range != nil && input.canChoose && (input.state?.acceptsChoices ?? false)
    }

    var body: some View {
        Section {
            Toggle(clock.minToggle, isOn: Binding(get: { on }, set: { switched($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!enabled)
            if range == nil {
                Label(strings.od8NotRead, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else if on, let range, let stock {
                clockRow(range: range, stock: stock)
            }
            if case .heldByApp(.power)? = input.state {
                Label(clock.notePowerHeld, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if lastOD8Source == .clockMin, case .switching(.od8)? = input.snapshot?.activity {
                Label(clock.switching, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            if outOfRange, let range {
                GPUControlProblemLabel(text: String(format: clock.outOfRangeFormat, range.lowerBound, range.upperBound),
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
            Text(clock.minSection)
        } footer: {
            Text(clock.minFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft) { _, value in fieldText = "\(value)" }
        // What is held changed on its own: the switch and the value follow
        // it, unless a request still waits.
        .onChange(of: Self.heldMHz(input)) { _, held in
            guard !input.isPending else { return }
            on = held != nil
            draft = held ?? stock ?? draft
        }
        .onAppear { fieldText = "\(draft)" }
    }

    private var refusal: GPUControlPageNote? {
        guard lastOD8Source == .clockMin, case .refused(let request, _)? = input.snapshot?.outcome,
              request.isOD8 else { return nil }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: The row

    /// VoiceOver's names for the row's three controls, each its own
    /// ("VoiceOver": alternative labels for all key interface elements).
    static func accessibilityNames(_ clock: GPUControlClockStrings) -> (slider: String, field: String, stepper: String) {
        (clock.minSection, clock.minFieldLabel, String(format: clock.minStepperFormat, GPUControlClockMinLogic.step))
    }

    private func clockRow(range: ClosedRange<Int>, stock: Int) -> some View {
        let names = Self.accessibilityNames(clock)
        let reason = GPUControlPageContent.disabledReason(input, strings)
        let slider = GPUControlTickSlider(value: draft, range: range,
                                          ticks: GPUControlClockMinLogic.tickCount(range: range),
                                          label: names.slider,
                                          help: Self.sliderHelp(clock, range: range),
                                          valueDescription: GPUControlPageContent.accessibilityValue(
                                            "\(draft) MHz", reason: usable ? nil : reason, strings),
                                          onChange: { draft = GPUControlClockMinLogic.snapped($0, range: range) },
                                          onRelease: { send(draft, stock: stock) })
        let entry = HStack(spacing: 8) {
            TextField(names.field, text: $fieldText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 56)
                .fixedSize(horizontal: true, vertical: false)
                .onSubmit { commitField(range: range, stock: stock) }
                .accessibilityLabel(names.field)
            Stepper(names.stepper, value: Binding(get: { draft }, set: { value in
                draft = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
                send(draft, stock: stock)
            }), in: range, step: GPUControlClockMinLogic.step)
                .labelsHidden()
                .accessibilityLabel(names.stepper)
                .accessibilityValue(GPUControlPageContent.accessibilityValue(
                    "\(draft) MHz", reason: enabled ? nil : reason, strings))
            Text("MHz").foregroundStyle(.secondary)
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
            // Stock at the leading end, where the slider starts.
            HStack {
                Text(String(format: clock.stockFormat, range.lowerBound))
                Spacer()
                Text(verbatim: "\(range.upperBound) MHz")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The slider's help: its two ends, as written under it, and what
    /// moving it does.
    static func sliderHelp(_ clock: GPUControlClockStrings, range: ClosedRange<Int>) -> String {
        String(format: clock.minSliderHelpFormat, range.lowerBound, range.upperBound)
    }

    // MARK: Sending

    private func switched(_ value: Bool) {
        on = value
        outOfRange = false
        // Turning it on shows the control and sends nothing: the stock
        // minimum is not a hold. Turning it off puts the stock minimum back,
        // keeping the rest of a held OD8 state in the same request.
        if !value {
            lastOD8Source = .clockMin
            choose(nil)
            if let stock { draft = stock }
        }
    }

    private func commitField(range: ClosedRange<Int>, stock: Int) {
        // Outside the range: not sent and not clamped; the field says what
        // it takes.
        guard let value = Int(fieldText.trimmingCharacters(in: .whitespaces)), range.contains(value) else {
            outOfRange = true
            return
        }
        draft = value
        send(value, stock: stock)
    }

    private func send(_ value: Int, stock: Int) {
        outOfRange = false
        lastOD8Source = .clockMin
        choose(GPUControlClockMinLogic.request(value, stockMHz: stock))
    }
}
