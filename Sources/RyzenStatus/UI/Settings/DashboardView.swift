import SwiftUI
import Charts

enum DashboardPreset: String, Codable, CaseIterable, Identifiable {
    case amdGadget = "AMD Power Gadget"
    case iStats = "iStats Style"
    case bTop = "BTop Cyberpunk"
    var id: String { rawValue }
}

enum DashboardModule: String, Codable, CaseIterable, Identifiable {
    case topCards = "Tarjetas de Resumen"
    case mainCharts = "Gráficos Principales"
    case coreGrid = "Uso de Núcleos (Grilla)"
    var id: String { rawValue }
}

struct DashboardView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var cpuProfile = ProcessorModel.CPUProfile()
    @AppStorage("dashboardPresetStyle") private var selectedPreset: DashboardPreset = .amdGadget
    
    // Default order
    @AppStorage("dashboardOrder2") private var orderData: Data = try! JSONEncoder().encode([DashboardModule.topCards, .mainCharts, .coreGrid])
    @AppStorage("dashboardHidden2") private var hiddenData: Data = try! JSONEncoder().encode([DashboardModule]())
    
    @State private var isEditing = false
    
    private var activeModules: [DashboardModule] {
        guard let order = try? JSONDecoder().decode([DashboardModule].self, from: orderData) else { return [] }
        return order
    }
    
    private var hiddenModules: Set<DashboardModule> {
        guard let hidden = try? JSONDecoder().decode([DashboardModule].self, from: hiddenData) else { return [] }
        return Set(hidden)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !monitor.snapshot.isKextAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Kext AMD no detectado. Telemetría AMD en modo lectura reducida.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Header with Title, Style Selector & Edit button
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dashboard")
                        .font(.headline)
                        .foregroundColor(.white)
                    // Architecture codename from the kext (selector 26), e.g. "Zen 3 Vermeer".
                    if !cpuProfile.archName.isEmpty {
                        Text(cpuProfile.archName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.9))
                    }
                }
                
                Spacer()
                
                Picker("", selection: $selectedPreset) {
                    ForEach(DashboardPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                
                if selectedPreset == .amdGadget || selectedPreset == .iStats {
                    Button(action: {
                        withAnimation { isEditing.toggle() }
                    }) {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundColor(isEditing ? .accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Customize Modules")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 12)
            
            if selectedPreset == .bTop {
                ScrollView {
                    BTopDashboardView(monitor: monitor)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                }
            } else if selectedPreset == .iStats {
                ScrollView {
                    IStatsPopoverWidgetsView(monitor: monitor, editing: isEditing, isDashboard: true)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                }
            } else if isEditing {
                EditDashboardView(orderData: $orderData, hiddenData: $hiddenData)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        let active = activeModules.filter { !hiddenModules.contains($0) }
                        
                        ForEach(active) { module in
                            renderModule(module)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12).edgesIgnoringSafeArea(.all)) // Dark theme similar to AMD PG
        .onAppear {
            SystemMonitor.shared.setMenuPanelNeeds(SystemMonitorPanelNeeds(network: true, power: true, cpu: true, gpu: true, memory: true, cpuTemperature: true, gpuTemperature: true))
        }
        .task {
            cpuProfile = await ProcessorModel.shared.cpuProfile
        }
        .onDisappear {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
    }
    
    @ViewBuilder
    private func renderModule(_ module: DashboardModule) -> some View {
        switch module {
        case .topCards:
            TopCardsView(monitor: monitor)
        case .mainCharts:
            MainChartsView(monitor: monitor)
        case .coreGrid:
            ThreadGridView()
        }
    }
}

// MARK: - Modules

struct TopCardsView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject private var c6 = C6ResidencyService.shared
    
    /// Preferred GPU temperature: kext > IOAccelerator > SMC
    private var preferredGPUTemp: Double? {
        if let kextGpu = monitor.snapshot.gpuDevices.first, kextGpu.temperature > 0 {
            return kextGpu.temperature
        }
        return monitor.snapshot.gpuTemperature
    }
    
    /// Preferred GPU power: kext > IOAccelerator
    private var preferredGPUPower: Double? {
        if let kextGpu = monitor.snapshot.gpuDevices.first, kextGpu.power > 0 {
            return kextGpu.power
        }
        return monitor.snapshot.gpuPower
    }

    /// Thermal color for a CCD card: green < 70 °C, orange < 85 °C, red above.
    private func ccdTempColor(for temp: Float) -> Color {
        if temp > 85 { return .red }
        if temp > 70 { return .orange }
        return .green
    }

    /// Color for the C6 residency bar: green when C6 is meaningfully engaged.
    private var c6Color: Color {
        if c6.percentage > 10 { return .green }
        if c6.percentage > 0 { return .orange }
        return .secondary
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Main row of cards
            HStack(spacing: 12) {
                let cpuLoadPct = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
                let cpuLoadStr = String(format: "%.0f%%", cpuLoadPct)
                
                let usedMem = Double(monitor.snapshot.memoryUsed ?? 0)
                let totalMem = Double(max(1, monitor.snapshot.memoryTotal ?? 1))
                let ramPct = (usedMem / totalMem) * 100.0
                let ramStr = String(format: "%.0f%%", ramPct)
                
                let gpuTempVal = preferredGPUTemp ?? 0
                let gpuUsagePct = (monitor.snapshot.gpuUsage ?? 0.0) * 100.0
                let gpuStr = gpuUsagePct > 0 ? String(format: "%.0f%%", gpuUsagePct) : (gpuTempVal > 0 ? String(format: "%.1f°C", gpuTempVal) : "---")
                let gpuPwrVal = preferredGPUPower ?? 0
                let gpuPwrStr = gpuPwrVal > 0 ? String(format: "%.1f W", gpuPwrVal) : "--- W"
                
                GadgetCard(title: "CPU Load", value: cpuLoadStr, icon: "cpu", history: monitor.snapshot.cpuHistory, color: .cyan)
                GadgetCard(title: "RAM Usage", value: ramStr, icon: "memorychip", history: monitor.snapshot.memoryHistory, color: .purple)
                GadgetCard(title: "GPU Usage", value: gpuStr, icon: "display", history: monitor.snapshot.gpuHistory.isEmpty ? monitor.snapshot.gpuTempHistory : monitor.snapshot.gpuHistory, color: .orange)
                GadgetCard(title: "GPU Power", value: gpuPwrStr, icon: "bolt.fill", history: monitor.snapshot.gpuPowerHistory, color: .green)
            }
            
            // AMD GPU devices from the kext (selectors 27-30). Only populated when
            // the kext finds a dedicated AMD GPU — iGPU-only or NVIDIA leaves the
            // array empty and this row hidden.
            if !monitor.snapshot.gpuDevices.isEmpty {
                HStack(spacing: 12) {
                    ForEach(monitor.snapshot.gpuDevices) { gpu in
                        let label = monitor.snapshot.gpuDevices.count > 1 ? "AMD GPU \(gpu.id)" : "AMD GPU"
                        let gpuTempStr = gpu.temperature > 0 ? String(format: "%.1f°C", gpu.temperature) : "---"
                        let gpuPwrStr = gpu.supportsPower && gpu.power > 0 ? String(format: "%.1f W", gpu.power) : "--- W"
                        
                        GadgetCard(title: "\(label) Temp", value: gpuTempStr, icon: "display", history: monitor.snapshot.gpuTempHistory, color: .orange.opacity(0.7))
                        GadgetCard(title: "\(label) Power", value: gpuPwrStr, icon: "bolt.fill", history: monitor.snapshot.gpuPowerHistory, color: .green.opacity(0.7))
                    }
                }
            }

            // CCD temperature row — one card per Core Complex Die (kext selector 20).
            if !monitor.snapshot.ccdTemperatures.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(monitor.snapshot.ccdTemperatures.enumerated()), id: \.offset) { index, temp in
                        if temp > 0 {
                            GadgetCard(title: "CCD\(index)",
                                       value: String(format: "%.0f°C", temp),
                                       icon: "cpu",
                                       history: [],
                                       color: ccdTempColor(for: temp))
                        }
                    }
                }
            }

            // C6 residency — % of time in the deepest C-state (kext selector 31).
            if c6.percentage > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 11))
                        Text("C6 RESIDENCY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", c6.percentage))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(c6Color)
                    }
                    ProgressView(value: c6.percentage, total: 100)
                        .progressViewStyle(.linear)
                        .tint(c6Color)
                }
                .padding(10)
                .background(Color(red: 0.15, green: 0.15, blue: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(.horizontal)
    }
}

struct MainChartsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(spacing: 16) {
            // Real Frequency + IPS Combined Chart
            VStack(alignment: .leading, spacing: 4) {
                Text("FREQUENCY & IPS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                CombinedFreqIPSGraph(
                    freqHistory: monitor.snapshot.cpuFreqHistory,
                    ipsHistory: monitor.snapshot.ipsHistory
                )
            }
            // CPU Temperature Chart
            ChartBox(title: "CPU TEMP", unit: "°C", data: monitor.snapshot.cpuTempHistory, color: .red)
            // CPU Power Chart
            ChartBox(title: "CPU POWER", unit: "W", data: monitor.snapshot.cpuPowerHistory, color: .blue)
            // GPU Temperature Chart
            if !monitor.snapshot.gpuTempHistory.isEmpty {
                ChartBox(title: "GPU TEMP", unit: "°C", data: monitor.snapshot.gpuTempHistory, color: .orange)
            }
            // GPU Power Chart
            if !monitor.snapshot.gpuPowerHistory.isEmpty {
                ChartBox(title: "GPU POWER", unit: "W", data: monitor.snapshot.gpuPowerHistory, color: .green)
            }
        }
        .padding(.horizontal)
    }
}

struct CoreGridDashboardWrapper: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT UTILIZATION")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            CoreGridDashboard(
                cores: monitor.snapshot.cores,
                ccdTemperatures: monitor.snapshot.ccdTemperatures,
                physicalCoresCount: monitor.snapshot.numPhysicalCores
            )
        }
        .padding(.horizontal)
    }
}


// MARK: - Components

struct GadgetCard: View {
    let title: String
    let value: String
    let icon: String
    let history: [Double]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            // Sparkline using TrendChart Canvas engine
            if history.isEmpty {
                Rectangle().fill(Color.clear).frame(height: 20)
            } else {
                let now = Date()
                let count = history.count
                let points = history.enumerated().map { TrendPoint(date: now.addingTimeInterval(Double($0.offset - count)), value: $0.element) }
                let series = TrendSeries(points: points, color: color, filled: true, lineWidth: 1.5)
                TrendChart(series: [series])
                    .frame(height: 20)
            }
        }
        .padding(10)
        .background(Color(red: 0.15, green: 0.15, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct ChartBox: View {
    let title: String
    let unit: String
    let data: [Double]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                if let last = data.last {
                    Text(String(format: "%.1f", last))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
                Spacer()
                Text(unit)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                
                if data.isEmpty {
                    Text("No data")
                        .foregroundColor(.secondary)
                } else {
                    let now = Date()
                    let count = data.count
                    let points = data.enumerated().map { TrendPoint(date: now.addingTimeInterval(Double($0.offset - count)), value: $0.element) }
                    let series = TrendSeries(points: points, color: color, filled: true, lineWidth: 2)
                    TrendChart(series: [series], yFormat: { String(format: "%.0f", $0) }, showsTimeAxis: false)
                        .padding(8)
                }
            }
            .frame(height: 120)
        }
    }
}

// MARK: - Edit Dashboard
struct EditDashboardView: View {
    @Binding var orderData: Data
    @Binding var hiddenData: Data
    
    @State private var order: [DashboardModule] = []
    @State private var hidden: Set<DashboardModule> = []
    
    var body: some View {
        List {
            ForEach(order) { module in
                HStack {
                    Button(action: {
                        if hidden.contains(module) {
                            hidden.remove(module)
                        } else {
                            hidden.insert(module)
                        }
                        save()
                    }) {
                        Image(systemName: hidden.contains(module) ? "eye.slash" : "eye")
                            .foregroundColor(hidden.contains(module) ? .secondary : .accentColor)
                            .frame(width: 30)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(module.rawValue)
                        .foregroundColor(hidden.contains(module) ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onMove { source, destination in
                order.move(fromOffsets: source, toOffset: destination)
                save()
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if let o = try? JSONDecoder().decode([DashboardModule].self, from: orderData) {
                order = o
            }
            if let h = try? JSONDecoder().decode([DashboardModule].self, from: hiddenData) {
                hidden = Set(h)
            }
        }
    }
    
    private func save() {
        if let o = try? JSONEncoder().encode(order) { orderData = o }
        if let h = try? JSONEncoder().encode(Array(hidden)) { hiddenData = h }
    }
}
