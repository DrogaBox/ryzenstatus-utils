// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct InteractiveFanCurveEditor: View {
    @ObservedObject var controller = FanCurveController.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared

    var hasDiscreteGPU: Bool = true
    @State private var selectedCurveIndex: Int = 0
    @State private var draftCurve: FanCurveDefinition? = nil
    @State private var showAppliedConfirmation: Bool = false
    // Hold the hide task so a second apply cancels the first one;
    // previously two quick applies made the first (uncancelled) sleep hide the
    // second confirmation immediately.
    @State private var appliedConfirmationTask: Task<Void, Never>?
    @State private var hoveredPointIndex: Int? = nil
    @State private var draggingPoint: (index: Int, temp: Double, pwm: Double)? = nil
    /// The curve the picker asked for while the draft has unsaved edits.
    @State private var pendingCurveIndex: Int? = nil
    @State private var confirmDeleteInUse = false
    /// The last Apply was refused by the controller (invalid points).
    @State private var curveRejected = false

    private var visibleSensors: [FanSensor] {
        hasDiscreteGPU ? [.cpu, .gpu] : [.cpu]
    }

    private var currentCurve: FanCurveDefinition? {
        if let draft = draftCurve {
            return draft
        }
        if selectedCurveIndex < controller.customCurves.count {
            return controller.customCurves[selectedCurveIndex]
        }
        return nil
    }

    private var hasUnsavedChanges: Bool {
        guard let draft = draftCurve, selectedCurveIndex < controller.customCurves.count else { return false }
        return draft != controller.customCurves[selectedCurveIndex]
    }

    /// Nil when no sensor answers: the badge and the graph marker then stay
    /// hidden instead of showing an invented temperature.
    private var currentSensorTemperature: Double? {
        guard let curve = currentCurve else { return nil }
        if curve.sourceSensor == .gpu {
            let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
            let fallback = monitor.snapshot.gpuTemperature ?? 0.0
            let gpuTemp = kextGPUTemp > 0 ? kextGPUTemp : fallback
            if gpuTemp > 0 { return gpuTemp }
        }
        // The fan poll's last reading: a SwiftUI body must not call the kext.
        if let temp = controller.lastPackageTempC { return temp }
        return monitor.snapshot.cpuTemperature
    }

    /// Fans following the selected curve go back to BIOS control when it is
    /// deleted, so that delete asks first.
    private var selectedCurveInUse: Bool {
        controller.fanMappings.values.contains(selectedCurveIndex)
    }

    /// Loads a saved curve as the draft, sorted by temperature: the drag
    /// clamp works on neighbours, and an older saved curve may be unsorted.
    private func loadDraft(_ index: Int) {
        guard index < controller.customCurves.count else { return }
        var draft = controller.customCurves[index]
        draft.points.sort { $0.temp < $1.temp }
        draftCurve = draft
        curveRejected = false
    }

    private func selectCurve(_ index: Int) {
        selectedCurveIndex = index
        loadDraft(index)
    }

    @ViewBuilder
    var body: some View {
        if let curve = currentCurve {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Curve Header & Actions
                HStack(spacing: 8) {
                    Text(l10n.fanControl.curveNameLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker(l10n.fanControl.curveNameLabel, selection: Binding(
                        get: { selectedCurveIndex },
                        set: { newIdx in
                            guard newIdx != selectedCurveIndex else { return }
                            // Switching would drop the unsaved edits.
                            if hasUnsavedChanges {
                                pendingCurveIndex = newIdx
                            } else {
                                selectCurve(newIdx)
                            }
                        }
                    )) {
                        ForEach(0..<controller.customCurves.count, id: \.self) { idx in
                            Text(controller.customCurves[idx].name).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)

                    TextField(l10n.fanControl.curveNameLabel, text: Binding(
                        get: { curve.name },
                        set: { newVal in
                            mutateDraft { $0.name = newVal }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                    Button("+") {
                        guard controller.customCurves.count < 4 else { return }
                        var updated = controller.customCurves
                        let newCurve = FanCurveDefinition(
                            name: String(format: l10n.fanControl.fanHeaderFormat, updated.count + 1),
                            kextSlot: updated.count,
                            points: [
                                FanCurvePoint(temp: 40, pwm: 30),
                                FanCurvePoint(temp: 70, pwm: 65),
                                FanCurvePoint(temp: 85, pwm: 100)
                            ],
                            sourceSensor: .cpu,
                            hysteresis: 2,
                            rampRate: 5
                        )
                        updated.append(newCurve)
                        controller.customCurves = updated
                        selectedCurveIndex = updated.count - 1
                        draftCurve = newCurve
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(controller.customCurves.count >= 4)
                    .help(controller.customCurves.count >= 4 ? l10n.fanControl.maxCurvesReached : l10n.fanControl.addCurveButton)
                    .accessibilityLabel(l10n.fanControl.addCurveButton)

                    if controller.customCurves.count > 1 {
                        Button("−") {
                            if selectedCurveInUse {
                                confirmDeleteInUse = true
                            } else {
                                deleteSelectedCurve(id: curve.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .help(l10n.fanControl.deleteCurveButton)
                        .accessibilityLabel(l10n.fanControl.deleteCurveButton)
                    }

                    Spacer()

                    // Live Sensor Readout Badge
                    if let liveTemp = currentSensorTemperature {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(String(format: l10n.fanControl.currentTempIndicatorFormat, liveTemp))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                    }
                }

                // MARK: - Sensor & Parameter Sliders + Apply Controls
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.fanControl.sourceSensorLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker(l10n.fanControl.sourceSensorLabel, selection: Binding(
                            get: {
                                visibleSensors.contains(curve.sourceSensor) ? curve.sourceSensor : .cpu
                            },
                            set: { newVal in
                                guard visibleSensors.contains(newVal) else { return }
                                mutateDraft { $0.sourceSensor = newVal }
                            }
                        )) {
                            ForEach(visibleSensors, id: \.self) { sensor in
                                Text(sensor == .cpu ? l10n.fanControl.cpuTempSource : l10n.fanControl.gpuTempSource).tag(sensor)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: hasDiscreteGPU ? 160 : 100)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.fanControl.hysteresisLabel)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: l10n.fanControl.hysteresisFormat, Double(curve.hysteresis)))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                        Slider(value: Binding(
                            get: { Double(curve.hysteresis) },
                            set: { newVal in
                                mutateDraft { $0.hysteresis = UInt8(min(5, max(1, Int(newVal.rounded())))) }
                            }
                        ), in: 1...5, step: 1)
                        .tint(.cyan)
                        .frame(width: 110)
                    }
                    .frame(width: 110)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.fanControl.rampRateLabel)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: l10n.fanControl.rampRateFormat, Double(curve.rampRate)))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                        Slider(value: Binding(
                            get: { Double(curve.rampRate) },
                            set: { newVal in
                                mutateDraft { $0.rampRate = UInt8(min(20, max(1, Int(newVal.rounded())))) }
                            }
                        ), in: 1...20, step: 1)
                        .tint(.cyan)
                        .frame(width: 110)
                    }
                    .frame(width: 110)

                    Spacer()

                    // Apply / Revert Actions
                    VStack(alignment: .trailing, spacing: 4) {
                        if hasUnsavedChanges {
                            HStack(spacing: 8) {
                                Button(action: {
                                    if let draft = draftCurve {
                                        controller.saveCurve(draft)
                                        // The controller refuses invalid points
                                        // without saying so; "Applied" only
                                        // when the saved curve is the draft.
                                        let saved = controller.customCurves.first(where: { $0.id == draft.id }) == draft
                                        curveRejected = !saved
                                        showAppliedConfirmation = saved
                                        appliedConfirmationTask?.cancel()
                                        guard saved else { return }
                                        appliedConfirmationTask = Task {
                                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                                            guard !Task.isCancelled else { return }
                                            showAppliedConfirmation = false
                                        }
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text(l10n.fanControl.applyCurveButton)
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.cyan)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    loadDraft(selectedCurveIndex)
                                }) {
                                    Text(l10n.fanControl.revertChangesButton)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            if curveRejected {
                                Text(l10n.dashboard.curveRejectedHint)
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                        } else if showAppliedConfirmation {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 10, weight: .bold))
                                Text(l10n.fanControl.appliedCurveBadge)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: - 2D Graph Area
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let liveTemp = currentSensorTemperature
                    let lut = curve.generateRPMLUT()

                    ZStack {
                        // Background Grid
                        Canvas { context, size in
                            let gridColor = Color.primary.opacity(0.08)

                            // Horizontal PWM lines
                            for i in 0...5 {
                                let y = CGFloat(i) * size.height / 5
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                                let pwmPct = 100 - i * 20
                                if pwmPct > 0 {
                                    context.draw(
                                        Text("\(pwmPct)%").font(.system(size: 8)).foregroundColor(.secondary),
                                        at: CGPoint(x: 14, y: y - 6),
                                        anchor: .leading
                                    )
                                }
                            }

                            // Vertical Temp lines
                            for i in 0...5 {
                                let x = CGFloat(i) * size.width / 5
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                                let tempC = i * 20
                                if tempC > 0 {
                                    context.draw(
                                        Text("\(tempC)°C").font(.system(size: 8)).foregroundColor(.secondary),
                                        at: CGPoint(x: x + 2, y: size.height - 10),
                                        anchor: .leading
                                    )
                                }
                            }
                        }

                        // Minimum Hardware Safety Floor Line (15.7% / PWM 40)
                        let floorY = h - CGFloat(AMDFanSafety.minimumCurvePWMPercent / 100.0) * h
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: floorY))
                            path.addLine(to: CGPoint(x: w, y: floorY))
                        }
                        .stroke(Color.red.opacity(0.35), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))

                        Text(String(format: l10n.dashboard.pwmFloorFormat,
                                    Int(AMDFanSafety.minimumCurvePWMPercent.rounded())))
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.red.opacity(0.6))
                            .position(x: w - 30, y: max(8, floorY - 7))

                        // Gradient Area Fill under the curve
                        Path { path in
                            let sorted = curve.points.sorted { $0.temp < $1.temp }
                            guard let firstPt = sorted.first, let lastPt = sorted.last else { return }

                            let startX = CGFloat(firstPt.temp / 100.0) * w
                            path.move(to: CGPoint(x: startX, y: h))
                            path.addLine(to: CGPoint(x: startX, y: h - CGFloat(firstPt.pwm / 100.0) * h))

                            for pt in sorted.dropFirst() {
                                path.addLine(to: CGPoint(x: CGFloat(pt.temp / 100.0) * w, y: h - CGFloat(pt.pwm / 100.0) * h))
                            }

                            let endX = CGFloat(lastPt.temp / 100.0) * w
                            path.addLine(to: CGPoint(x: endX, y: h))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color.cyan.opacity(0.20), Color.orange.opacity(0.30)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))

                        // Thin Preview of 256-point LUT
                        Path { path in
                            guard lut.count >= 100 else { return }
                            let firstY = h - CGFloat(lut[0] / 100.0) * h
                            path.move(to: CGPoint(x: 0, y: firstY))
                            for t in 1...100 {
                                let x = CGFloat(Double(t) / 100.0) * w
                                let y = h - CGFloat(lut[t] / 100.0) * h
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))

                        // Connecting Curve Line
                        let activePoints: [FanCurvePoint] = {
                            var pts = curve.points
                            if let drag = draggingPoint, drag.index < pts.count {
                                pts[drag.index] = FanCurvePoint(temp: drag.temp, pwm: drag.pwm)
                            }
                            return pts
                        }()

                        Path { path in
                            let sorted = activePoints.sorted { $0.temp < $1.temp }
                            guard let firstPt = sorted.first else { return }

                            path.move(to: CGPoint(x: CGFloat(firstPt.temp / 100.0) * w, y: h - CGFloat(firstPt.pwm / 100.0) * h))
                            for pt in sorted.dropFirst() {
                                path.addLine(to: CGPoint(x: CGFloat(pt.temp / 100.0) * w, y: h - CGFloat(pt.pwm / 100.0) * h))
                            }
                        }
                        .stroke(
                            LinearGradient(gradient: Gradient(colors: [.cyan, .orange]), startPoint: .leading, endPoint: .trailing),
                            lineWidth: 2.5
                        )

                        // Live Temperature Marker Line & Target Dot
                        if let liveTemp, liveTemp >= 0 && liveTemp <= 100 {
                            let liveX = CGFloat(liveTemp / 100.0) * w
                            let targetPWM = lut[min(255, max(0, Int(liveTemp.rounded())))]
                            let liveY = h - CGFloat(targetPWM / 100.0) * h

                            // Vertical marker line
                            Path { path in
                                path.move(to: CGPoint(x: liveX, y: 0))
                                path.addLine(to: CGPoint(x: liveX, y: h))
                            }
                            .stroke(Color.green.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                            // Live operating point dot
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.green.opacity(0.8), radius: 4)
                                .position(x: liveX, y: liveY)
                        }

                        // Interactive Control Points
                        ForEach(curve.points.indices, id: \.self) { ptIdx in
                            let displayPt = (draggingPoint?.index == ptIdx)
                                ? FanCurvePoint(temp: draggingPoint!.temp, pwm: draggingPoint!.pwm)
                                : curve.points[ptIdx]
                            let ptX = CGFloat(displayPt.temp / 100.0) * w
                            let ptY = h - CGFloat(displayPt.pwm / 100.0) * h

                            ZStack {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 26, height: 26)
                                Circle()
                                    .fill(hoveredPointIndex == ptIdx || draggingPoint?.index == ptIdx ? Color.cyan : Color.orange)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                            }
                            .position(x: ptX, y: ptY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let newX = max(0, min(w, val.location.x))
                                        let newY = max(0, min(h, val.location.y))
                                        let snappedTemp = round(Double(newX / w) * 100.0)
                                        let rawPWM = round(Double((h - newY) / h) * 100.0)
                                        // Between its neighbours, so the curve
                                        // keeps its order and never falls.
                                        let point = FanCurveGeometry.clampedPoint(
                                            index: ptIdx, temp: snappedTemp, pwm: rawPWM,
                                            sorted: curve.points,
                                            floor: AMDFanSafety.minimumCurvePWMPercent.rounded())
                                        draggingPoint = (index: ptIdx, temp: point.temp, pwm: point.pwm)
                                    }
                                    .onEnded { _ in
                                        if let drag = draggingPoint {
                                             mutateDraft { draft in
                                                 guard drag.index < draft.points.count else { return }
                                                 draft.points[drag.index].temp = drag.temp
                                                 draft.points[drag.index].pwm = drag.pwm
                                             }
                                             draggingPoint = nil
                                         }
                                     }
                             )
                             .onTapGesture(count: 2) {
                                 if curve.points.count > 2 {
                                     mutateDraft { draft in
                                         guard ptIdx < draft.points.count else { return }
                                         draft.points.remove(at: ptIdx)
                                     }
                                 }
                             }
                             .onHover { hovering in
                                 hoveredPointIndex = hovering ? ptIdx : nil
                             }
                             .accessibilityElement()
                             .accessibilityLabel(String(format: l10n.dashboard.curvePointLabelFormat, ptIdx + 1))
                             .accessibilityValue(String(format: l10n.dashboard.curvePointValueFormat,
                                                        Int(displayPt.temp.rounded()), Int(displayPt.pwm.rounded())))
                             .contextMenu {
                                 Button(l10n.fanControl.deletePointTooltip) {
                                     if curve.points.count > 2 {
                                         mutateDraft { draft in
                                             guard ptIdx < draft.points.count else { return }
                                             draft.points.remove(at: ptIdx)
                                         }
                                     }
                                 }
                             }
                         }
                     }
                     .background(Color.primary.opacity(0.02))
                     .cornerRadius(8)
                     .overlay(
                         RoundedRectangle(cornerRadius: 8)
                             .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                     )
                     .gesture(
                         SpatialTapGesture()
                             .onEnded { val in
                                 let tapX = val.location.x
                                 let tapY = val.location.y

                                 let tooClose = curve.points.contains { pt in
                                     let ptX = CGFloat(pt.temp / 100.0) * w
                                     let ptY = h - CGFloat(pt.pwm / 100.0) * h
                                     let dist = sqrt(pow(tapX - ptX, 2) + pow(tapY - ptY, 2))
                                     return dist < 14
                                 }

                                 if !tooClose && curve.points.count < 8 {
                                     let newTemp = max(0.0, min(100.0, Double(tapX / w) * 100.0))
                                     let rawPWM = round(Double((h - tapY) / h) * 100.0)
                                     // No point on top of another temperature,
                                     // and a duty between its neighbours'.
                                     if let point = FanCurveGeometry.insertedPoint(
                                         temp: newTemp, pwm: rawPWM, sorted: curve.points,
                                         floor: AMDFanSafety.minimumCurvePWMPercent.rounded()) {
                                         mutateDraft { draft in
                                             draft.points.append(FanCurvePoint(temp: point.temp, pwm: point.pwm))
                                             draft.points.sort { $0.temp < $1.temp }
                                         }
                                     }
                                 }
                             }
                     )
                 }
                 .frame(height: 180)

                 HStack(spacing: 8) {
                     Text(l10n.fanControl.instructionsHint)
                     Spacer()
                     Text(l10n.fanControl.pwmFloorHint)
                 }
                 .font(.system(size: 9.5))
                 .foregroundColor(.secondary)
            }
            .onAppear {
                loadDraft(selectedCurveIndex)
            }
            .confirmationDialog(l10n.dashboard.discardChangesTitle,
                                isPresented: Binding(get: { pendingCurveIndex != nil },
                                                     set: { if !$0 { pendingCurveIndex = nil } })) {
                Button(l10n.dashboard.discardChangesButton, role: .destructive) {
                    if let index = pendingCurveIndex { selectCurve(index) }
                    pendingCurveIndex = nil
                }
                Button(l10n.fanControl.cancelButton, role: .cancel) { pendingCurveIndex = nil }
            }
            .confirmationDialog(l10n.dashboard.deleteCurveInUseTitle, isPresented: $confirmDeleteInUse) {
                Button(l10n.fanControl.deleteCurveButton, role: .destructive) {
                    deleteSelectedCurve(id: curve.id)
                }
                Button(l10n.fanControl.cancelButton, role: .cancel) {}
            } message: {
                Text(l10n.dashboard.deleteCurveInUseMessage)
            }
        } else {
            Text(l10n.fanControl.noCurvesConfigured)
                .foregroundColor(.secondary)
        }
    }

    private func deleteSelectedCurve(id: UUID) {
        guard selectedCurveIndex < controller.customCurves.count else { return }
        controller.deleteCurve(id: id)
        selectCurve(max(0, min(selectedCurveIndex, controller.customCurves.count - 1)))
    }

    private func mutateDraft(_ transform: (inout FanCurveDefinition) -> Void) {
        let base = draftCurve ?? (selectedCurveIndex < controller.customCurves.count ? controller.customCurves[selectedCurveIndex] : nil)
        guard var draft = base else { return }
        transform(&draft)
        draftCurve = draft
    }
}

/// Where the editor lets a curve point go, so a drag or a tap can never make
/// the duty fall as the temperature rises or put two points on one
/// temperature. Plain functions over points sorted by temperature, kept off
/// the view so they can be tested.
enum FanCurveGeometry {
    /// Keeps a dragged point at least 1 °C from its neighbours and its duty
    /// between theirs, never below `floor`. When the bounds cross (neighbours
    /// 1 °C apart, or an older curve whose duty already falls) the point pins
    /// to the lower bound.
    static func clampedPoint(index: Int, temp: Double, pwm: Double,
                             sorted points: [FanCurvePoint], floor: Double) -> (temp: Double, pwm: Double) {
        let previous = index > 0 && index - 1 < points.count ? points[index - 1] : nil
        let next = index >= 0 && index + 1 < points.count ? points[index + 1] : nil
        let lowTemp = previous.map { $0.temp + 1 } ?? 0
        let highTemp = next.map { $0.temp - 1 } ?? 100
        let lowPWM = max(floor, previous?.pwm ?? floor)
        let highPWM = next?.pwm ?? 100
        return (clamp(temp, lowTemp, highTemp), clamp(pwm, lowPWM, highPWM))
    }

    /// A new point at `temp`, or nil when another point is closer than 1 °C
    /// (exactly 1 °C apart is allowed); its duty sits between the
    /// neighbours' duties and never below `floor`.
    static func insertedPoint(temp: Double, pwm: Double,
                              sorted points: [FanCurvePoint], floor: Double) -> (temp: Double, pwm: Double)? {
        guard !points.contains(where: { abs($0.temp - temp) < 1 }) else { return nil }
        let previous = points.last(where: { $0.temp < temp })
        let next = points.first(where: { $0.temp > temp })
        let lowPWM = max(floor, previous?.pwm ?? floor)
        let highPWM = next?.pwm ?? 100
        return (temp, clamp(pwm, lowPWM, highPWM))
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        high < low ? low : min(max(value, low), high)
    }
}
