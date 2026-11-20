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
            // custom curve is on.
            if draft.customCurve {
                ForEach(0..<GPUControlWire.fanCurvePoints, id: \.self) { k in
                    pointRow(k)
                }
                chart
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
            HStack {
                Spacer()
                // "Entering data": enable the button only with valid data;
                // "Buttons": the editor's one action, prominent.
                Button(fan.apply) { apply(draft) }
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

    /// The kext's refusal of the last fan request, next to the editor.
    private var refusal: GPUControlPageNote? {
        guard case .refused(let request, _)? = input.snapshot?.outcome, request.isOD8 else { return nil }
        return GPUControlPageNote.make(input.snapshot, strings)
    }

    // MARK: Points

    /// "Steppers": a stepper sits next to the field that shows its value;
    /// "Text fields": a number formatter. Nothing is clamped: the live
    /// sentence names a value the kext would refuse.
    private func pointRow(_ k: Int) -> some View {
        let temperature = Binding(get: { draft.points[k].temperatureC }, set: { draft.points[k].temperatureC = $0 })
        let speed = Binding(get: { draft.points[k].speedPercent }, set: { draft.points[k].speedPercent = $0 })
        return HStack(spacing: 6) {
            Text(String(format: fan.pointFormat, k + 1))
            Spacer()
            TextField("", value: temperature, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .accessibilityLabel(String(format: fan.pointTempFormat, k + 1))
            Stepper("", value: temperature, step: 1)
                .labelsHidden()
                .accessibilityLabel(String(format: fan.stepTempFormat, k + 1))
            Text("°C").foregroundStyle(.secondary)
            TextField("", value: speed, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .padding(.leading, 12)
                .accessibilityLabel(String(format: fan.pointSpeedFormat, k + 1))
            Stepper("", value: speed, step: 1)
                .labelsHidden()
                .accessibilityLabel(String(format: fan.stepSpeedFormat, k + 1))
            Text("%").foregroundStyle(.secondary)
        }
        .disabled(!enabled)
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
            Label(text, systemImage: ok ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(ok ? Color.secondary : Color.orange)
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
