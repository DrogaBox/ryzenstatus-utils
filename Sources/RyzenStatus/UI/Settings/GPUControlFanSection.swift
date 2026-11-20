// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Charts
import SwiftUI

/// The fan section of Settings > GPU control (plan 7.3): zero RPM, the
/// custom curve with its five points, a chart that only shows, the live
/// sentence from the kext's own rules, and "Apply curve".
struct GPUControlFanSection: View {
    let input: GPUControlPageInput
    let strings: GPUControlPageStrings
    let fan: GPUControlFanStrings
    @Binding var draft: GPUControlFanDraft
    let apply: (GPUControlFanDraft) -> Void

    private var curveState: GPUControlCurveRules.State? {
        input.writing?.od8.flatMap(GPUControlCurveRules.State.init(table:))
    }

    private var limitC: Int { curveState?.limitC ?? 48 }

    private var preview: GPUControlCurvePreview {
        GPUControlCurvePreview.make(want: draft.want, writing: input.writing)
    }

    /// The OD8 state the kext holds for this app now (stock when none).
    private var heldOD8: GPUControlOD8Want {
        if case .heldByApp(.od8(let want))? = input.state { return want }
        return .stock
    }

    private var enabled: Bool {
        input.canChoose && (input.state?.acceptsChoices ?? false) && !input.isPending
    }

    /// Apply only for a draft the rules accept that changes what is held.
    private var canApply: Bool {
        guard enabled, preview.allowsApply else { return false }
        return draft.want.curve != heldOD8.curve || draft.want.zeroRpmOff != heldOD8.zeroRpmOff
    }

    /// "Buttons": the title says what the button does. A stock draft over a
    /// held fan state gives that state back, so it says so, in the stock
    /// words of this section (the power section's button keeps start-up).
    private var applyTitle: String {
        draft.givesBack(heldOD8) ? fan.backToStock : fan.apply
    }

    var body: some View {
        Section {
            // "Toggles", macOS: within a grouped form, a mini switch per row;
            // the label says what turning it on does ("Writing").
            Toggle(fan.zeroRpmToggle, isOn: $draft.zeroRpmOff)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!enabled)
            Toggle(fan.curveToggle, isOn: $draft.customCurve)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!enabled)
            // "Layout": progressive disclosure, the editor only while the
            // custom curve is on, indented under its switch: "people
            // perceive indented items as subordinate to the item they
            // follow".
            if draft.customCurve {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<GPUControlWire.fanCurvePoints, id: \.self) { k in
                        pointRow(k)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        chart
                        // "Charts": name the lines on screen too, not only for
                        // VoiceOver (the chart's label says the same).
                        Text(fan.chartKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, Self.editorIndent)
                // "Buttons": Return confirms, as with a primary button, but
                // only from the editor's own fields: a default button
                // would take Return from every field on the page.
                .onSubmit(applyOnReturn)
            }
            previewRow
            if case .heldByApp(.power)? = input.state {
                // "Writing": what happens, next to the control, before Apply.
                Label(fan.notePowerHeld, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = refusal {
                VStack(alignment: .leading, spacing: 2) {
                    GPUControlProblemLabel(text: note.sentence, isProblem: true)
                    if let kext = note.kextText {
                        Text(kext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                // "Entering data": enable the button only with valid data;
                // "Buttons": the editor's one action, prominent.
                Button(applyTitle, action: applyDraft)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
            }
        } header: {
            Text(fan.section)
        } footer: {
            Text(String(format: fan.footerFormat, limitC))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How far the curve editor sits in from its switch.
    static let editorIndent: CGFloat = 20

    private func applyDraft() {
        apply(draft)
        draft = draft.applied
    }

    /// Return in a point field. The field commits its number on Return as
    /// well, so the check waits for the next turn of the main queue, when
    /// the draft holds the typed value; nothing is sent unless Apply
    /// itself could be used.
    private func applyOnReturn() {
        DispatchQueue.main.async {
            if canApply { applyDraft() }
        }
    }

    /// The kext's refusal of the last fan request, next to the editor.
    private var refusal: GPUControlPageNote? {
        guard case .refused(let request, _)? = input.snapshot?.outcome, request.isOD8 else { return nil }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: Points

    /// "Steppers": a stepper sits next to the field that shows its value;
    /// "Text fields": a number formatter. Nothing is clamped: the live
    /// sentence names a value the kext would refuse.
    /// "Layout": "horizontally adjacent views may need to stack vertically
    /// to provide more space for text": one line while it fits, then the
    /// label above the two fields, then each field on its own line.
    private func pointRow(_ k: Int) -> some View {
        let temperature = Binding(get: { draft.points[k].temperatureC }, set: { draft.points[k].temperatureC = $0 })
        let speed = Binding(get: { draft.points[k].speedPercent }, set: { draft.points[k].speedPercent = $0 })
        let label = Text(String(format: fan.pointFormat, k + 1))
        let temperatureField = valueField(temperature, unit: "°C",
                                          name: String(format: fan.pointTempFormat, k + 1),
                                          stepName: String(format: fan.stepTempFormat, k + 1))
        let speedField = valueField(speed, unit: "%",
                                    name: String(format: fan.pointSpeedFormat, k + 1),
                                    stepName: String(format: fan.stepSpeedFormat, k + 1))
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                label
                Spacer()
                temperatureField
                speedField.padding(.leading, 12)
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                HStack(spacing: 6) {
                    Spacer()
                    temperatureField
                    speedField.padding(.leading, 12)
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                temperatureField
                speedField
            }
        }
        .disabled(!enabled)
    }

    /// One number of a point: its field, its stepper and its unit, each
    /// control with its own VoiceOver name.
    private func valueField(_ value: Binding<Int>, unit: String, name: String, stepName: String) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .accessibilityLabel(name)
            Stepper("", value: value, step: 1)
                .labelsHidden()
                .accessibilityLabel(stepName)
            // The field's name already says the unit (a11y A7).
            Text(unit).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }

    // MARK: Chart

    /// "Charts": a line for each curve and points on the edited one; three
    /// elements only ("Charting data": keep it simple). It never edits.
    private var chart: some View {
        let stock = curveState?.stockCurve ?? input.writing?.od8?.fanCurveStock ?? []
        return Chart {
            ForEach(Array(stock.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("°C", point.temperatureC), y: .value("%", point.speedPercent),
                         series: .value("curve", "stock"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
            }
            ForEach(Array(draft.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("°C", point.temperatureC), y: .value("%", point.speedPercent),
                         series: .value("curve", "draft"))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("°C", point.temperatureC), y: .value("%", point.speedPercent))
                    .foregroundStyle(Color.accentColor)
            }
            RuleMark(x: .value("°C", limitC))
                .foregroundStyle(Color.orange)
                .annotation(position: .top, alignment: .trailing) {
                    Text(String(format: fan.limitFormat, limitC))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 20...100)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("°C")
        .chartYAxisLabel("%")
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: fan.chartLabelFormat, limitC))
        .accessibilityValue(draft.points.map { "\($0.temperatureC) °C \($0.speedPercent) %" }.joined(separator: ", "))
    }

    // MARK: Live sentence

    /// "Feedback": the result next to the editor, as text (never color
    /// alone). It follows every edit.
    private var previewRow: some View {
        let (text, detail, ok) = previewText
        return VStack(alignment: .leading, spacing: 2) {
            // a11y A1: the symbol carries the orange, the words stay legible.
            Label {
                Text(text).foregroundStyle(ok ? Color.secondary : Color.primary)
            } icon: {
                Image(systemName: ok ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(ok ? Color.secondary : Color.orange)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var previewText: (String, String?, Bool) {
        switch preview {
        case .accepted:
            return (fan.curveOK, nil, true)
        case .notChecked:
            return (fan.notChecked, nil, false)
        case .unavailable:
            return (strings.od8NotRead, nil, false)
        case .refused(let result):
            if let rule = fan.rule(result.check, limitC: limitC), let point = result.point {
                return (String(format: fan.curveFailFormat, point, rule), result.check.kextText, false)
            }
            let group = GPUControlTextGroup.forOD8Check(result.check.rawValue) ?? .notAllowed
            return (strings.sentence(group), result.check.kextText, false)
        }
    }
}
