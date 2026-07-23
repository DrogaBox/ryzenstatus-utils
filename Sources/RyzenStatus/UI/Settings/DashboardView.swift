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
            // Header with Title, Style Selector & Edit button
            HStack(alignment: .center, spacing: 12) {
                Text("Dashboard")
                    .font(.headline)
                    .foregroundColor(.white)
                
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
            SystemMonitor.shared.setMenuPanelNeeds(SystemMonitorPanelNeeds(power: true, cpu: true, gpu: true, memory: true, cpuTemperature: true, gpuTemperature: true))
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
            CoreGridDashboardWrapper(monitor: monitor)
        }
    }
}

// MARK: - Modules

struct TopCardsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        HStack(spacing: 12) {
            let cpuLoadPct = (monitor.snapshot.cpuUsage ?? 0.0) * 100.0
            let cpuLoadStr = String(format: "%.0f%%", cpuLoadPct)
            
            let usedMem = Double(monitor.snapshot.memoryUsed ?? 0)
            let totalMem = Double(max(1, monitor.snapshot.memoryTotal ?? 1))
            let ramPct = (usedMem / totalMem) * 100.0
            let ramStr = String(format: "%.0f%%", ramPct)
            
            let gpuUsagePct = (monitor.snapshot.gpuUsage ?? 0.0) * 100.0
            let gpuStr = gpuUsagePct > 0 ? String(format: "%.0f%%", gpuUsagePct) : (monitor.snapshot.gpuTemperature != nil ? String(format: "%.1f°C", monitor.snapshot.gpuTemperature!) : "---")
            let gpuPwrStr = monitor.snapshot.gpuPower != nil ? String(format: "%.1f W", monitor.snapshot.gpuPower!) : "--- W"
            
            GadgetCard(title: "CPU Load", value: cpuLoadStr, icon: "cpu", history: monitor.snapshot.cpuHistory, color: .cyan)
            GadgetCard(title: "RAM Usage", value: ramStr, icon: "memorychip", history: monitor.snapshot.memoryHistory, color: .purple)
            GadgetCard(title: "GPU Usage", value: gpuStr, icon: "display", history: monitor.snapshot.gpuHistory.isEmpty ? monitor.snapshot.gpuTempHistory : monitor.snapshot.gpuHistory, color: .orange)
            GadgetCard(title: "GPU Power", value: gpuPwrStr, icon: "bolt.fill", history: monitor.snapshot.gpuPowerHistory, color: .green)
        }
        .padding(.horizontal)
    }
}

struct MainChartsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(spacing: 16) {
            // Real Frequency Chart
            ChartBox(title: "FREQUENCY", unit: "GHz", data: monitor.snapshot.cpuFreqHistory, color: .purple)
            // Real Temperature Chart
            ChartBox(title: "TEMPERATURE", unit: "°C", data: monitor.snapshot.cpuTempHistory, color: .red)
            // Real Power Chart
            ChartBox(title: "POWER", unit: "W", data: monitor.snapshot.cpuPowerHistory, color: .blue)
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
            
            // Sparkline
            if history.isEmpty {
                Rectangle().fill(Color.clear).frame(height: 20)
            } else {
                Chart {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, val in
                        LineMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [color.opacity(0.3), .clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
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
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, val in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Value", val)
                            )
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            
                            AreaMark(
                                x: .value("Time", index),
                                y: .value("Value", val)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [color.opacity(0.4), .clear]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartXAxis(.hidden)
                    .padding(10)
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
