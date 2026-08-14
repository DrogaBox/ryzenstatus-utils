import SwiftUI

struct InteractiveFanCurveEditor: View {
    @ObservedObject var controller = FanCurveController.shared
    /// False when no discrete AMD GPU is present. The GPU fan is always
    /// managed by the GPU itself (vBIOS), so a GPU-temp-sourced curve can only
    /// drive a case/CPU fan header — and the control loop falls back to CPU
    /// temp when no GPU temperature is available. Hiding the option on
    /// GPU-less machines is purely cosmetic: the user's stored curves are
    /// never rewritten, only the visible picker choices shrink.
    var hasDiscreteGPU: Bool = true
    @State private var selectedCurveIndex: Int = 0
    @State private var hoveredPointIndex: Int? = nil
    @State private var draggingPoint: (index: Int, temp: Double, pwm: Double)? = nil
    @ObservedObject private var l10n = L10n.shared

    private var visibleSensors: [FanSensor] {
        hasDiscreteGPU ? [.cpu, .gpu] : [.cpu]
    }
    
    @ViewBuilder
    var body: some View {
        if selectedCurveIndex < controller.customCurves.count {
            let curve = controller.customCurves[selectedCurveIndex]
            
            VStack(alignment: .leading, spacing: 12) {
                // Curve Selector and Controls
                HStack(spacing: 8) {
                    Text(l10n.fanControl.curveNameLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    Picker("", selection: $selectedCurveIndex) {
                        ForEach(0..<controller.customCurves.count, id: \.self) { idx in
                            Text(controller.customCurves[idx].name).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    
                    TextField("Name", text: Binding(
                        get: { curve.name },
                        set: { newVal in
                            var updated = controller.customCurves
                            updated[selectedCurveIndex].name = newVal
                            controller.customCurves = updated
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    
                    Button("+") {
                        var updated = controller.customCurves
                        let newCurve = FanCurve(
                            name: "Curve \(updated.count + 1)",
                            points: [
                                FanCurvePoint(temp: 40, pwm: 30),
                                FanCurvePoint(temp: 70, pwm: 60),
                                FanCurvePoint(temp: 85, pwm: 100)
                            ],
                            sourceSensor: .cpu,
                            hysteresis: 2.0,
                            rampRate: 5.0
                        )
                        updated.append(newCurve)
                        controller.customCurves = updated
                        selectedCurveIndex = updated.count - 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Add new curve")
                    
                    if controller.customCurves.count > 1 {
                        Button("−") {
                            let deletedIdx = selectedCurveIndex
                            var updated = controller.customCurves
                            guard deletedIdx < updated.count else { return }
                            updated.remove(at: deletedIdx)
                            controller.customCurves = updated
                            controller.fanMappings = FanCurve.compactMappingsOnDeletion(
                                mappings: controller.fanMappings,
                                deletedIndex: deletedIdx
                            )
                            if selectedCurveIndex >= updated.count {
                                selectedCurveIndex = max(0, updated.count - 1)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .help("Delete this curve")
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.fanControl.sourceSensorLabel).font(.system(size: 10)).foregroundColor(.secondary)
                        Picker("", selection: Binding(
                            get: {
                                visibleSensors.contains(curve.sourceSensor) ? curve.sourceSensor : .cpu
                            },
                            set: { newVal in
                                guard visibleSensors.contains(newVal) else { return }
                                var updated = controller.customCurves
                                updated[selectedCurveIndex].sourceSensor = newVal
                                controller.customCurves = updated
                            }
                        )) {
                            ForEach(visibleSensors, id: \.self) { sensor in
                                Text(sensor == .cpu ? "CPU Temp" : "GPU Temp").tag(sensor)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: hasDiscreteGPU ? 150 : 100)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.fanControl.hysteresisLabel).font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: l10n.fanControl.hysteresisFormat, curve.hysteresis)).font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { curve.hysteresis },
                            set: { newVal in
                                var updated = controller.customCurves
                                updated[selectedCurveIndex].hysteresis = newVal
                                controller.customCurves = updated
                            }
                        ), in: 1...5, step: 1)
                        .accentColor(.blue)
                        .frame(width: 120)
                    }
                    .frame(width: 120)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.fanControl.rampRateLabel).font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: l10n.fanControl.rampRateFormat, curve.rampRate)).font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { curve.rampRate },
                            set: { newVal in
                                var updated = controller.customCurves
                                updated[selectedCurveIndex].rampRate = newVal
                                controller.customCurves = updated
                            }
                        ), in: 1...20, step: 1)
                        .accentColor(.blue)
                        .frame(width: 120)
                    }
                    .frame(width: 120)
                }
                
                // 2D Graph Area
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    ZStack {
                        // Background Grid
                        Canvas { context, size in
                            let gridColor = Color.primary.opacity(0.1)
                            
                            // Horizontal lines (PWM)
                            for i in 0...5 {
                                let y = CGFloat(i) * size.height / 5
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                
                                // PWM Labels
                                let pwmPct = 100 - i * 20
                                if pwmPct > 0 {
                                    context.draw(Text("\(pwmPct)%").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: 12, y: y - 6), anchor: .leading)
                                }
                            }
                            
                            // Vertical lines (Temp)
                            for i in 0...5 {
                                let x = CGFloat(i) * size.width / 5
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                
                                // Temp Labels
                                let tempC = i * 20
                                if tempC > 0 {
                                    context.draw(Text("\(tempC)°C").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: x + 2, y: size.height - 10), anchor: .leading)
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
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.20), Color.orange.opacity(0.30)]),
                                             startPoint: .leading, endPoint: .trailing))
                        
                        // Points to render (incorporating draft drag state)
                        let activePoints: [FanCurvePoint] = {
                            var pts = curve.points
                            if let drag = draggingPoint, drag.index < pts.count {
                                pts[drag.index] = FanCurvePoint(temp: drag.temp, pwm: drag.pwm)
                            }
                            return pts
                        }()

                        // Line Path connecting points
                        Path { path in
                            let sorted = activePoints.sorted { $0.temp < $1.temp }
                            guard let firstPt = sorted.first else { return }
                            
                            path.move(to: CGPoint(x: CGFloat(firstPt.temp / 100.0) * w, y: h - CGFloat(firstPt.pwm / 100.0) * h))
                            
                            for pt in sorted.dropFirst() {
                                path.addLine(to: CGPoint(x: CGFloat(pt.temp / 100.0) * w, y: h - CGFloat(pt.pwm / 100.0) * h))
                            }
                        }
                        .stroke(LinearGradient(gradient: Gradient(colors: [.cyan, .orange]), startPoint: .leading, endPoint: .trailing), lineWidth: 2.5)
                        
                        // Interactive points
                        ForEach(curve.points.indices, id: \.self) { ptIdx in
                            let displayPt = (draggingPoint?.index == ptIdx)
                                ? FanCurvePoint(temp: draggingPoint!.temp, pwm: draggingPoint!.pwm)
                                : curve.points[ptIdx]
                            let ptX = CGFloat(displayPt.temp / 100.0) * w
                            let ptY = h - CGFloat(displayPt.pwm / 100.0) * h
                            
                            ZStack {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .fill(hoveredPointIndex == ptIdx || draggingPoint?.index == ptIdx ? Color.cyan : Color.blue)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            .position(x: ptX, y: ptY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let newX = max(0, min(w, val.location.x))
                                        let newY = max(0, min(h, val.location.y))
                                        let snappedTemp = round(Double(newX / w) * 100.0)
                                        let snappedPWM = round(Double((h - newY) / h) * 100.0)
                                        draggingPoint = (index: ptIdx, temp: snappedTemp, pwm: snappedPWM)
                                    }
                                    .onEnded { val in
                                        if let drag = draggingPoint {
                                            var updated = controller.customCurves
                                            updated[selectedCurveIndex].points[drag.index].temp = drag.temp
                                            updated[selectedCurveIndex].points[drag.index].pwm = drag.pwm
                                            updated[selectedCurveIndex].points.sort { $0.temp < $1.temp }
                                            controller.customCurves = updated
                                            draggingPoint = nil
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                if curve.points.count > 2 {
                                    var updated = controller.customCurves
                                    updated[selectedCurveIndex].points.remove(at: ptIdx)
                                    controller.customCurves = updated
                                }
                            }
                            .onHover { hovering in
                                hoveredPointIndex = hovering ? ptIdx : nil
                            }
                            .contextMenu {
                                Button("Delete Point") {
                                    if curve.points.count > 2 {
                                        var updated = controller.customCurves
                                        updated[selectedCurveIndex].points.remove(at: ptIdx)
                                        controller.customCurves = updated
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
                                    return dist < 12
                                }
                                
                                if !tooClose && curve.points.count < 8 {
                                    let newTemp = Double(tapX / w) * 100.0
                                    let newPWM = Double((h - tapY) / h) * 100.0
                                    var updated = controller.customCurves
                                    updated[selectedCurveIndex].points.append(FanCurvePoint(temp: newTemp, pwm: newPWM))
                                    updated[selectedCurveIndex].points.sort { $0.temp < $1.temp }
                                    controller.customCurves = updated
                                }
                            }
                    )
                }
                .frame(height: 180)
                Text(l10n.fanControl.instructionsHint)
                    .font(.system(size: 9.5)).foregroundColor(.secondary)
            }
        } else {
            Text(l10n.fanControl.noCurvesConfigured).foregroundColor(.secondary)
        }
    }
}
