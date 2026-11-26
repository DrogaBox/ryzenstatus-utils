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
    /// The section that asked last, so a refusal shows next to its control.
    @Binding var lastOD8Source: GPUControlOD8Source
    let apply: (GPUControlFanDraft) -> Void
    /// The zero RPM switch's own answer when the state it would send is not
    /// one the card takes: shown next to the switch, in the page's words for
    /// a refusal.
    @State private var zeroRpmRefusal: GPUControlCurvePreview?

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
            // "Toggles": the label says what turning it on does ("Writing").
            // The regular size, not mini: "Accessibility" asks for at least
            // 20 x 20 pt on macOS (a11y A8).
            Toggle(fan.zeroRpmToggle, isOn: Binding(get: { draft.zeroRpmOff }, set: { zeroRpmSwitched($0) }))
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(!enabled)
            if let refused = zeroRpmRefusal {
                refusalNote(refused)
            }
            Toggle(fan.curveToggle, isOn: $draft.customCurve)
                .toggleStyle(.switch)
                .controlSize(.regular)
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
                // Escape gives the edits back, the way macOS cancels an
                // edit (a11y A10).
                .onExitCommand(perform: discardDraft)
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
                        Text(String(format: strings.kextSaysFormat, kext))
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
                    // a11y A6: what it does and that Return does it too;
                    // A14: why it is dimmed, when the state is the reason
                    // (the live sentence says what is wrong with a draft).
                    .accessibilityHint(fan.applyHint)
                    .accessibilityValue(GPUControlPageContent.disabledReason(input, strings) ?? "")
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

    /// The zero RPM switch. While a curve is held it goes out at once with
    /// that curve, as the clock and voltage controls do; otherwise it is part
    /// of the draft "Apply curve" sends. Point edits not applied yet stay in
    /// the editor and are not sent with it.
    ///
    /// The preview judges the whole state the card will get, not the two
    /// fields the switch builds: the controller adds the held clocks and the
    /// voltage back before the call. When that state is refused, the section
    /// says so next to the switch instead of reading on as if it went out.
    private func zeroRpmSwitched(_ on: Bool) {
        let otherEdits = draft.want.curve != heldOD8.curve
        draft.zeroRpmOff = on
        zeroRpmRefusal = nil
        guard enabled, let send = Self.zeroRpmAtOnce(held: heldOD8, zeroRpmOff: on) else { return }
        let answer = GPUControlCurvePreview.make(want: Self.stateSent(held: heldOD8, zeroRpmOff: on),
                                                 writing: input.writing)
        guard answer.allowsApply else {
            zeroRpmRefusal = answer
            return
        }
        lastOD8Source = .fan
        apply(send)
        if !otherEdits { draft = draft.applied }
    }

    /// The whole OD8 state the card gets when the switch sends `zeroRpmOff`
    /// while `held` is held: the controller takes every setting from the held
    /// state (what the kext has), so the preview must see the same one.
    static func stateSent(held: GPUControlOD8Want, zeroRpmOff: Bool) -> GPUControlOD8Want {
        GPUControlOD8Want(curve: held.curve, zeroRpmOff: zeroRpmOff, gfxMaxMHz: held.gfxMaxMHz,
                          gfxMinMHz: held.gfxMinMHz, voltMV: held.voltMV, overclock: held.overclock)
    }

    /// A refusal in the page's own words (the live row's), with the kext's
    /// sentence under it, as the page shows one.
    private func refusalNote(_ answer: GPUControlCurvePreview) -> some View {
        let (text, detail, _) = sentence(for: answer)
        return VStack(alignment: .leading, spacing: 2) {
            GPUControlProblemLabel(text: text, isProblem: true)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the zero RPM switch sends by itself: the held curve with the new
    /// zero RPM state, only while a curve is held and the state changes. Nil
    /// otherwise (the switch then only edits the draft).
    static func zeroRpmAtOnce(held: GPUControlOD8Want, zeroRpmOff: Bool) -> GPUControlFanDraft? {
        guard let curve = held.curve, held.zeroRpmOff != zeroRpmOff else { return nil }
        return GPUControlFanDraft(held: GPUControlOD8Want(curve: curve, zeroRpmOff: zeroRpmOff))
    }

    private func applyDraft() {
        lastOD8Source = .fan
        apply(draft)
        draft = draft.applied
    }

    /// Escape in the editor: an edited draft goes back to what is held, and
    /// VoiceOver says so; an untouched one stays.
    private func discardDraft() {
        guard draft.edited else { return }
        draft = Self.discarded(held: heldOD8)
        AccessibilityNotification.Announcement(fan.draftDiscarded).post()
    }

    /// The draft Escape leaves: a new one seeded from what is held, unedited.
    /// Not `following(held:)`, which keeps an edited draft as it is.
    static func discarded(held: GPUControlOD8Want) -> GPUControlFanDraft {
        GPUControlFanDraft(held: held)
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
        guard lastOD8Source == .fan, case .refused(let request, _)? = input.snapshot?.outcome,
              request.isOD8 else { return nil }
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
            // At least 44 pt, wider when the number needs it (a11y A4).
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 44)
                .fixedSize(horizontal: true, vertical: false)
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
        .accessibilityValue(Self.chartValue(draft: draft.points, stock: stock, limitC: limitC, fan: fan))
    }

    /// The chart for VoiceOver: the draft's points, the stock curve's (the
    /// dashed line) and the 100 % temperature (the rule), in the language's
    /// own order (a11y A12).
    static func chartValue(draft: [GPUControlFanPoint], stock: [GPUControlFanPoint], limitC: Int,
                           fan: GPUControlFanStrings) -> String {
        func points(_ curve: [GPUControlFanPoint]) -> String {
            curve.map { "\($0.temperatureC) °C \($0.speedPercent) %" }.joined(separator: ", ")
        }
        let limit = String(format: fan.limitFormat, limitC)
        return stock.isEmpty ? String(format: fan.chartValueDraftFormat, points(draft), limit)
            : String(format: fan.chartValueFormat, points(draft), points(stock), limit)
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

    private var previewText: (String, String?, Bool) { sentence(for: preview) }

    /// One preview's sentence: the live row's, and the zero RPM switch's.
    private func sentence(for preview: GPUControlCurvePreview) -> (String, String?, Bool) {
        switch preview {
        case .accepted:
            return (fan.curveOK, nil, true)
        case .notChecked:
            return (fan.notChecked, nil, false)
        case .unavailable:
            return (strings.od8NotRead, nil, false)
        case .refused(let result):
            if let rule = fan.rule(result.check, limitC: limitC), let point = result.point {
                return (String(format: fan.curveFailFormat, point, rule),
                        String(format: strings.kextSaysFormat, result.check.kextText), false)
            }
            let group = GPUControlTextGroup.forOD8Check(result.check.rawValue) ?? .notAllowed
            return (strings.sentence(group), String(format: strings.kextSaysFormat, result.check.kextText), false)
        }
    }
}
