import SwiftUI

// MARK: - Fans Settings View (AMD Power Gadget exact replica)
struct FansSettingsView: View {
    @State private var fans: [FanSnapshot] = []
    @State private var hasSMCWriteAccess: Bool = true
    @State private var loadTimer: Timer?
    @State private var hiddenFanIDs: Set<Int> = []
    @State private var autoFanCurveEnabled: Bool = false
    @State private var customFanNames: [Int: String] = [:]
    @ObservedObject var controller = FanCurveController.shared
    
    var body: some View {
        Form {
            if !hasSMCWriteAccess {
                Section {
                    SMCNotAvailableView()
                }
            } else if fans.isEmpty {
                Section {
                    Text("No fans detected.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(32)
                }
            } else {
                Section {
                    HStack {
                        Text("SMC Fan Control")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .textCase(.uppercase)
                        Spacer()
                        if !hiddenFanIDs.isEmpty {
                            Button(action: { hiddenFanIDs.removeAll() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                    Text(String(format: "Show All (%d hidden)", hiddenFanIDs.count))
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    ForEach(fans.filter { !hiddenFanIDs.contains($0.id) }) { fan in
                        FanControlCard(fan: fan, customFanNames: $customFanNames, onHide: {
                            hiddenFanIDs.insert(fan.id)
                        })
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            Task {
                                for f in fans {
                                    _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: f.id)
                                    controller.fanMappings[f.id] = -1
                                }
                            }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("All Auto")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(Color.cyan.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.35)))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            Task {
                                for f in fans {
                                    _ = ProcessorModel.shared.setFanSpeed(rpm: 255, fanIndex: f.id)
                                    controller.fanMappings[f.id] = -1
                                }
                            }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "wind")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Max Speed")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.orange)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35)))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Fans")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(nil)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dynamic Next-Gen Fan Curves")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Evaluated in the kernel with 256-step LUT interpolation, hysteresis, and smooth ramping.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $autoFanCurveEnabled)
                                .toggleStyle(.switch)
                                .tint(.orange)
                                .labelsHidden()
                        }
                        
                        if autoFanCurveEnabled {
                            Divider()
                            InteractiveFanCurveEditor()
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Curves")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(nil)
                }
                
                Section {
                    GPUFanControlGuideView()
                        .padding(.vertical, 4)
                } header: {
                    Text("GPU")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(nil)
                }
            }
        }
        .formStyle(.grouped)
        .environment(\.defaultMinListRowHeight, 4)
        .onAppear {
            setupFans()
            loadTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                fetchState()
            }
        }
        .onDisappear {
            loadTimer?.invalidate()
            loadTimer = nil
        }
    }
    
    private func setupFans() {
        Task {
            let conn = ProcessorModel.shared.connect
            let hasAccess = conn != 0
            let currentFans = ProcessorModel.shared.getFans()
            await MainActor.run {
                self.hasSMCWriteAccess = hasAccess
                self.fans = currentFans
                // Load custom names
                for fan in currentFans {
                    if let saved = UserDefaults.standard.string(forKey: "FanName_\(fan.id)") {
                        self.customFanNames[fan.id] = saved
                    }
                }
                self.fetchState()
            }
        }
    }
    
    private func fetchState() {
        Task {
            let currentFans = ProcessorModel.shared.getFans()
            await MainActor.run {
                if self.fans.count != currentFans.count {
                    self.fans = currentFans
                } else {
                    for i in 0..<currentFans.count {
                        self.fans[i].rpm = currentFans[i].rpm
                        self.fans[i].throttle = currentFans[i].throttle
                        self.fans[i].isOverrided = currentFans[i].isOverrided
                    }
                }
            }
        }
    }
}

// MARK: - Fan Control Card (exact replica of AMD Power Gadget's FanControlCard)
struct FanControlCard: View {
    let fan: FanSnapshot
    @Binding var customFanNames: [Int: String]
    let onHide: () -> Void
    @State private var sliderValue: Double = 0
    /// Se setea true cuando el usuario empieza a arrastrar el slider.
    /// Mantiene visible el botón "Reset to Auto" hasta que el kext confirma.
    @State private var didDrag = false
    @ObservedObject var controller = FanCurveController.shared
    
    private var isMappedToCurve: Bool {
        (controller.fanMappings[fan.id] ?? -1) != -1
    }
    
    private var mappedCurveIdx: Int {
        controller.fanMappings[fan.id] ?? -1
    }
    
    private var curveName: String {
        let idx = mappedCurveIdx
        if idx >= 0, idx < controller.customCurves.count {
            return controller.customCurves[idx].name
        }
        return "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // --- Top row: icon, name, RPM · % · hide ---
            HStack {
                Image(systemName: "fan")
                    .foregroundColor(.cyan)
                    .font(.system(size: 14))
                
                TextField("", text: Binding(
                    get: { customFanNames[fan.id] ?? (fan.name.isEmpty ? "Fan \(fan.id + 1)" : fan.name) },
                    set: { newVal in
                        customFanNames[fan.id] = newVal
                        UserDefaults.standard.set(newVal, forKey: "FanName_\(fan.id)")
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 150)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("\(fan.rpm) RPM")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", sliderValue / 255.0 * 100.0))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(fan.isOverrided ? .orange : .secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Button(action: onHide) {
                        Image(systemName: "eye.slash")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Hide this fan")
                }
            }
            
            // --- Control Mode & Status Badge ---
            HStack {
                if isMappedToCurve {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                        Text("Curve: \(curveName)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                } else if fan.isOverrided {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                        Text("Manual: \(String(format: "%.0f%%", sliderValue / 255.0 * 100.0))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("BIOS / Auto")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                Picker("", selection: Binding(
                    get: { controller.fanMappings[fan.id] ?? -1 },
                    set: { newVal in
                        var updated = controller.fanMappings
                        updated[fan.id] = newVal
                        controller.fanMappings = updated
                    }
                )) {
                    Text("BIOS / Auto").tag(-1)
                    ForEach(0..<controller.customCurves.count, id: \.self) { idx in
                        Text(controller.customCurves[idx].name).tag(idx)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            // --- Slider (igual que AMD Power Gadget) ---
            HStack(spacing: 12) {
                Text("Override")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Slider(value: $sliderValue, in: 0...255, step: 1) { editing in
                    if editing {
                        didDrag = true
                    } else {
                        Task {
                            _ = ProcessorModel.shared.setFanSpeed(rpm: Int(sliderValue), fanIndex: fan.id)
                        }
                    }
                }
                .tint(.cyan)
                Text(String(format: "%.0f%%", sliderValue / 255.0 * 100.0))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(width: 36, alignment: .trailing)
            }
            
            // --- Reset to Auto ---
            if fan.isOverrided || didDrag {
                Button("↩ Reset to Auto") {
                    didDrag = false
                    Task {
                        _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fan.id)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(fan.isOverrided ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            // El kext ahora reporta PWM estimado desde RPM incluso en Auto mode
            sliderValue = Double(fan.throttle)
        }
        .onChange(of: fan.throttle) { _, newVal in
            // Sincronizar slider con el throttle reportado por el kext
            // (PWM real en Manual, PWM estimado desde RPM en Auto)
            sliderValue = Double(newVal)
        }
        .onChange(of: fan.isOverrided) { _, newVal in
            if newVal {
                didDrag = false
            }
        }
    }
}

// MARK: - SMC Not Available View
struct SMCNotAvailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("SMC driver not available")
                .font(.system(size: 14, weight: .semibold))
            Text("Your SMC chip may not be supported.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - GPU Fan Control Guide View
struct GPUFanControlGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 16))
                Text("macOS Hardware Limitation")
                    .font(.system(size: 13, weight: .bold))
            }
            Text("Direct software-based GPU fan speed overrides (such as zero-rpm toggle or drawing fan curves in macOS) are not supported by the macOS kernel/IOKit driver for AMD GPUs. The GPU's onboard firmware (vBIOS) manages the fans.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)
            
            Text("Standard Hackintosh Solution:")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
            Text("The only way to modify this behavior (like forcing fans to spin at lower temperatures or disabling Zero RPM) is by exporting the vBIOS, creating a Soft PowerPlay Table (SPPT), and injecting it via OpenCore's config.plist under DeviceProperties.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}
