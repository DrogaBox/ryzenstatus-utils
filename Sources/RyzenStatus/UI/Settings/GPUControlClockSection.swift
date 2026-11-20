// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The GFX maximum clock section of Settings > GPU control (plan 7.1,
/// phase 4): a switch, then a slider from 1500 MHz to the stock maximum with
/// a field and a stepper. Only ever lower than stock.
struct GPUControlClockSection: View {
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
        _draft = State(initialValue: held ?? input.writing?.od8?.stockGfxMaxMHz ?? GPUControlWire.gfxFloorMHz)
    }

    private static func heldMHz(_ input: GPUControlPageInput) -> Int? {
        if case .heldByApp(.od8(let want))? = input.state { return want.gfxMaxMHz }
        return nil
    }

    /// Nil unless OD8 is read cleanly and the kext offers the clock.
    private var top: Int? { input.facts?.od8Ready == true ? input.writing?.od8?.stockGfxMaxMHz : nil }
    private var range: ClosedRange<Int>? { GPUControlClockLogic.range(stockGfxMaxMHz: top) }

    private var enabled: Bool {
        range != nil && input.canChoose && (input.state?.acceptsChoices ?? false) && !input.isPending
    }

    var body: some View {
        Section {
            // "Toggles", macOS: a mini switch in its own row of a grouped
            // form; "Writing": the label says what turning it on does.
            Toggle(clock.toggle, isOn: Binding(get: { on }, set: { switched($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!enabled)
            if range == nil {
                Label(strings.od8NotRead, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else if on, let range, let top {
                clockRow(range: range, top: top)
            }
            if case .heldByApp(.power)? = input.state {
                Label(clock.notePowerHeld, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if lastOD8Source == .clock, case .switching(.od8)? = input.snapshot?.activity {
                // "Feedback": the wait of a switch, said next to the control.
                Label(clock.switching, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            if outOfRange, let range {
                Label(String(format: clock.outOfRangeFormat, range.lowerBound, range.upperBound),
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
            if let note = refusal {
                VStack(alignment: .leading, spacing: 2) {
                    Label(note.sentence, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    if let kext = note.kextText {
                        Text(kext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text(clock.section)
        } footer: {
            Text(clock.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft) { _, value in fieldText = "\(value)" }
        // What is held changed on its own (a wake, the kext going back, a
        // refusal): the switch and the value follow it, unless a request
        // still waits.
        .onChange(of: Self.heldMHz(input)) { _, held in
            guard !input.isPending else { return }
            on = held != nil
            draft = held ?? top ?? draft
        }
        .onAppear { fieldText = "\(draft)" }
    }

    private var refusal: GPUControlPageNote? {
        guard lastOD8Source == .clock, case .refused(let request, _)? = input.snapshot?.outcome,
              request.isOD8 else { return nil }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: The row

    /// "Sliders": a wide range gets a field and a stepper too; minimum on the
    /// leading side; tick marks every 100 MHz with the ends labelled.
    /// "Steppers": next to the field that shows the value.
    private func clockRow(range: ClosedRange<Int>, top: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                GPUControlTickSlider(value: draft, range: range,
                                     ticks: GPUControlClockLogic.tickCount(stockGfxMaxMHz: top),
                                     label: clock.section,
                                     onChange: { draft = GPUControlClockLogic.snapped($0, stockGfxMaxMHz: top) },
                                     onRelease: { send(draft, top: top) })
                TextField(clock.section, text: $fieldText)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .onSubmit { commitField(range: range, top: top) }
                    .accessibilityLabel(clock.section)
                Stepper(clock.section, value: Binding(get: { draft }, set: { value in
                    draft = Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
                    send(draft, top: top)
                }), in: range, step: GPUControlClockLogic.step)
                    .labelsHidden()
                    .accessibilityLabel(clock.section)
                    .accessibilityValue("\(draft) MHz")
                Text("MHz").foregroundStyle(.secondary)
            }
            HStack {
                Text(verbatim: "\(range.lowerBound) MHz")
                Spacer()
                Text(String(format: clock.stockFormat, top))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
    }

    // MARK: Sending

    private func switched(_ value: Bool) {
        on = value
        outOfRange = false
        // Turning it on shows the control and sends nothing: the stock
        // maximum is not a hold. Turning it off puts the stock clock back,
        // keeping a held fan state in the same request.
        // The controller decides whether there is anything to give back
        // (a held or waiting clock); it never gives back a power limit.
        if !value {
            lastOD8Source = .clock
            choose(nil)
            if let top { draft = top }
        }
    }

    private func commitField(range: ClosedRange<Int>, top: Int) {
        // A value outside the range is not sent and not clamped: the field
        // says what it takes ("Writing": the error next to the field).
        guard let value = Int(fieldText.trimmingCharacters(in: .whitespaces)), range.contains(value) else {
            outOfRange = true
            return
        }
        draft = value
        send(value, top: top)
    }

    private func send(_ value: Int, top: Int) {
        outOfRange = false
        // Always to the controller: it compares with what waits and what is
        // held, and drops a request that goes back to the held value.
        lastOD8Source = .clock
        choose(GPUControlClockLogic.request(value, stockGfxMaxMHz: top))
    }
}

/// Which section's OD8 request went out last.
enum GPUControlOD8Source: Equatable {
    case fan
    case clock
}

/// A native slider with tick marks (SwiftUI's has none on macOS) that
/// reports every move and the moment it is let go.
struct GPUControlTickSlider: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let ticks: Int
    let label: String
    let onChange: (Double) -> Void
    let onRelease: () -> Void

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: Double(range.lowerBound),
                              maxValue: Double(range.upperBound), target: context.coordinator,
                              action: #selector(Coordinator.moved(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = ticks
        slider.allowsTickMarkValuesOnly = false
        slider.tickMarkPosition = .below
        slider.setAccessibilityLabel(label)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.numberOfTickMarks = ticks
        slider.isEnabled = context.environment.isEnabled
        if Int(slider.doubleValue.rounded()) != value { slider.doubleValue = Double(value) }
        slider.setAccessibilityValueDescription("\(value) MHz")
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject {
        var parent: GPUControlTickSlider
        init(parent: GPUControlTickSlider) { self.parent = parent }

        @objc func moved(_ sender: NSSlider) {
            parent.onChange(sender.doubleValue)
            // The request goes out when the thumb is let go (plan 7.1), not
            // on every step of the drag.
            let event = NSApp.currentEvent?.type
            if event == .leftMouseUp || event == .keyDown || event == nil {
                parent.onRelease()
            }
        }
    }
}
