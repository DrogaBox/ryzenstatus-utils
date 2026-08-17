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
    @State private var hoveredPointIndex: Int? = nil
    @State private var draggingPoint: (index: Int, temp: Double, pwm: Double)? = nil

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

    private var currentSensorTemperature: Double {
        guard let curve = currentCurve else { return 45.0 }
        if curve.sourceSensor == .gpu {
            let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
            let fallback = monitor.snapshot.gpuTemperature ?? 0.0
            let gpuTemp = kextGPUTemp > 0 ? kextGPUTemp : fallback
            if gpuTemp > 0 { return gpuTemp }
        }
        if let packet = ProcessorModel.shared.getTelemetry(), packet.packageTempC > 0 {
            return Double(packet.packageTempC)
        }
        return monitor.snapshot.cpuTemperature ?? 45.0
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

                    Picker("", selection: Binding(
                        get: { selectedCurveIndex },
                        set: { newIdx in
                            selectedCurveIndex = newIdx
                            if newIdx < controller.customCurves.count {
                                draftCurve = controller.customCurves[newIdx]
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

                    TextField("", text: Binding(
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
                            let deletedIdx = selectedCurveIndex
                            guard deletedIdx < controller.customCurves.count else { return }
                            controller.deleteCurve(id: curve.id)
                            let newIdx = max(0, min(selectedCurveIndex, controller.customCurves.count - 1))
                            selectedCurveIndex = newIdx
                            if newIdx < controller.customCurves.count {
                                draftCurve = controller.customCurves[newIdx]
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
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(String(format: l10n.fanControl.currentTempIndicatorFormat, currentSensorTemperature))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }

                // MARK: - Sensor & Parameter Sliders + Apply Controls
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.fanControl.sourceSensorLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker("", selection: Binding(
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
                                        showAppliedConfirmation = true
                                        Task {
                                            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                                    if selectedCurveIndex < controller.customCurves.count {
                                        draftCurve = controller.customCurves[selectedCurveIndex]
                                    }
                                }) {
                                    Text(l10n.fanControl.revertChangesButton)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
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
                        if liveTemp >= 0 && liveTemp <= 100 {
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
                                        let snappedPWM = max(1.0, round(Double((h - newY) / h) * 100.0))
                                        draggingPoint = (index: ptIdx, temp: snappedTemp, pwm: snappedPWM)
                                    }
                                    .onEnded { _ in
                                        if let drag = draggingPoint {
                                            mutateDraft { draft in
                                                guard drag.index < draft.points.count else { return }
                                                draft.points[drag.index].temp = drag.temp
                                                draft.points[drag.index].pwm = drag.pwm
                                                draft.points.sort { $0.temp < $1.temp }
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
                                    let newPWM = max(1.0, min(100.0, Double((h - tapY) / h) * 100.0))
                                    mutateDraft { draft in
                                        draft.points.append(FanCurvePoint(temp: newTemp, pwm: newPWM))
                                        draft.points.sort { $0.temp < $1.temp }
                                    }
                                }
                            }
                    )
                }
                .frame(height: 180)

                Text(l10n.fanControl.instructionsHint)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            .onAppear {
                if selectedCurveIndex < controller.customCurves.count {
                    draftCurve = controller.customCurves[selectedCurveIndex]
                }
            }
        } else {
            Text(l10n.fanControl.noCurvesConfigured)
                .foregroundColor(.secondary)
        }
    }

    private func mutateDraft(_ transform: (inout FanCurveDefinition) -> Void) {
        let base = draftCurve ?? (selectedCurveIndex < controller.customCurves.count ? controller.customCurves[selectedCurveIndex] : nil)
        guard var draft = base else { return }
        transform(&draft)
        draftCurve = draft
    }
}


