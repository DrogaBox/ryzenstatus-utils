import SwiftUI
import Charts

enum DashboardModule: String, Codable, CaseIterable, Identifiable {
    case topCards = "Tarjetas de Resumen"
    case mainCharts = "Gráficos Principales"
    case coreGrid = "Uso de Núcleos (Grilla)"
    var id: String { rawValue }
}

struct DashboardView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    
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
            // Header with Edit button
            HStack {
                Text("AMD Power Gadget")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    withAnimation { isEditing.toggle() }
                }) {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "slider.horizontal.3")
                        .foregroundColor(isEditing ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 10)
            
            if isEditing {
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
            SystemMonitor.shared.setMenuPanelNeeds(SystemMonitorPanelNeeds(power: true, cpu: true, gpu: true, cpuTemperature: true, gpuTemperature: true))
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
            let cpuTempStr = monitor.snapshot.cpuTemperature != nil ? String(format: "%.1f°C", monitor.snapshot.cpuTemperature!) : "---°C"
            let gpuTempStr = monitor.snapshot.gpuTemperature != nil ? String(format: "%.1f°C", monitor.snapshot.gpuTemperature!) : "---°C"
            let cpuPwrStr = monitor.snapshot.cpuPower != nil ? String(format: "%.2f W", monitor.snapshot.cpuPower!) : "--- W"
            let gpuPwrStr = monitor.snapshot.gpuPower != nil ? String(format: "%.2f W", monitor.snapshot.gpuPower!) : "--- W"
            
            GadgetCard(title: "CPU Temp", value: cpuTempStr, icon: "cpu", history: monitor.snapshot.cpuHistory.map { Double($0) }, color: .red)
            GadgetCard(title: "GPU Temp", value: gpuTempStr, icon: "display", history: monitor.snapshot.gpuHistory.map { Double($0) }, color: .orange)
            GadgetCard(title: "CPU Power", value: cpuPwrStr, icon: "bolt.fill", history: monitor.snapshot.cpuHistory.map { Double($0) }, color: .blue)
            GadgetCard(title: "GPU Power", value: gpuPwrStr, icon: "bolt.fill", history: monitor.snapshot.gpuHistory.map { Double($0) }, color: .green)
        }
        .padding(.horizontal)
    }
}

struct MainChartsView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(spacing: 16) {
            // Frequency Chart
            ChartBox(title: "FREQUENCY", unit: "GHz", data: monitor.snapshot.cpuHistory.map { Double($0) * 0.04 }, color: .purple) // Fake freq history for now using load
            // Temperature Chart
            ChartBox(title: "TEMPERATURE", unit: "°C", data: monitor.snapshot.cpuHistory.map { Double($0) }, color: .red) // Fake temp history using load
            // Power Chart
            ChartBox(title: "POWER", unit: "W", data: monitor.snapshot.cpuHistory.map { Double($0) }, color: .blue) // Fake power history using load
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
