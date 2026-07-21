import SwiftUI

struct InteractiveFanCurveEditor: View {
    @ObservedObject var controller = FanCurveController.shared
    @State private var selectedCurveIndex: Int = 0
    @State private var hoveredPointIndex: Int? = nil
    
    var body: some View {
        guard selectedCurveIndex < controller.customCurves.count else {
            return AnyView(Text("No curves configured.").foregroundColor(.secondary))
        }
        
        let curve = controller.customCurves[selectedCurveIndex]
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Curve Selector and Controls
                HStack(spacing: 8) {
                    Text("Curve").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
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
                            var updated = controller.customCurves
                            guard selectedCurveIndex < updated.count else { return }
                            updated.remove(at: selectedCurveIndex)
                            controller.customCurves = updated
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
                        Text("Temp Source").font(.system(size: 10)).foregroundColor(.secondary)
                        Picker("", selection: Binding(
                            get: { curve.sourceSensor },
                            set: { newVal in
                                var updated = controller.customCurves
                                updated[selectedCurveIndex].sourceSensor = newVal
                                controller.customCurves = updated
                            }
                        )) {
                            Text("CPU Temp").tag(FanSensor.cpu)
                            Text("GPU Temp").tag(FanSensor.gpu)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hysteresis").font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(curve.hysteresis))°C").font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
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
                            Text("Ramp Rate").font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(curve.rampRate))%/s").font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
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
                        
                        // Line Path connecting points
                        Path { path in
                            let sorted = curve.points.sorted { $0.temp < $1.temp }
                            guard let firstPt = sorted.first else { return }
                            
                            path.move(to: CGPoint(x: CGFloat(firstPt.temp / 100.0) * w, y: h - CGFloat(firstPt.pwm / 100.0) * h))
                            
                            for pt in sorted.dropFirst() {
                                path.addLine(to: CGPoint(x: CGFloat(pt.temp / 100.0) * w, y: h - CGFloat(pt.pwm / 100.0) * h))
                            }
                        }
                        .stroke(Color.blue, lineWidth: 2)
                        
                        // Interactive points
                        ForEach(curve.points.indices, id: \.self) { ptIdx in
                            let pt = curve.points[ptIdx]
                            let ptX = CGFloat(pt.temp / 100.0) * w
                            let ptY = h - CGFloat(pt.pwm / 100.0) * h
                            
                            Circle()
                                .fill(hoveredPointIndex == ptIdx ? Color.cyan : Color.blue)
                                .frame(width: 10, height: 10)
                                .position(x: ptX, y: ptY)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { val in
                                            let newX = max(0, min(w, val.location.x))
                                            let newY = max(0, min(h, val.location.y))
                                            
                                            var updated = controller.customCurves
                                            updated[selectedCurveIndex].points[ptIdx].temp = Double(newX / w) * 100.0
                                            updated[selectedCurveIndex].points[ptIdx].pwm = Double((h - newY) / h) * 100.0
                                            controller.customCurves = updated
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
                
                Text("Drag control points to edit curve. Double-click empty space to add (max 8). Double-click a point or right-click to delete.")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
        )
    }
}
