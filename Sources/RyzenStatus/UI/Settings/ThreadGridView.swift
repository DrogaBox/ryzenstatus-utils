import SwiftUI

class ThreadGridViewModel: ObservableObject {
    struct ThreadData: Identifiable {
        let id: Int
        let isLogical: Bool
        let usage: Double
        let freqMHz: Double
        /// True when this thread sits on one of the CPU's best (max-score) cores.
        let isFavoriteCore: Bool
    }
    
    @Published var threads: [ThreadData] = []
    /// Whether the kext reports CPPC core ranking (selector 21).
    @Published private(set) var cppcSupported: Bool = false
    /// Per-logical-thread HighestPerf scores (selector 21), indexed by thread id.
    private var cppcScores: [UInt8] = []
    
    /// Number of logical threads marked as favorite (max HighestPerf) cores.
    var favoriteCount: Int { threads.filter(\.isFavoriteCore).count }
    
    let physicalCpuCount: Int
    let logicalCpuCount: Int
    
    private var timer: Timer?
    private var previousCpuInfo: processor_info_array_t?
    private var previousNumCpuInfo: mach_msg_type_number_t = 0
    
    init() {
        var size = MemoryLayout<Int32>.size
        var phys: Int32 = 0
        sysctlbyname("hw.physicalcpu", &phys, &size, nil, 0)
        self.physicalCpuCount = Int(phys > 0 ? phys : 16)
        
        var logical: Int32 = 0
        sysctlbyname("hw.logicalcpu", &logical, &size, nil, 0)
        self.logicalCpuCount = Int(logical > 0 ? logical : 32)
        
        for i in 0..<self.logicalCpuCount {
            self.threads.append(ThreadData(id: i, isLogical: i >= self.physicalCpuCount, usage: 0, freqMHz: 0,
                                           isFavoriteCore: false))
        }
        
        DispatchQueue.main.async {
            self.startMonitoring()
        }
    }
    
    func startMonitoring() {
        updateUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUsage()
        }
    }
    
    /// Reads the CPPC core ranking (selector 21: supported flag + one UInt8
    /// HighestPerf score per logical thread). Scores are static per boot but
    /// re-read on each tick so a kext reload is picked up.
    private func refreshCPPC() {
        let ranking = ProcessorModel.shared.getCPPCScore()
        cppcSupported = ranking.supported
        cppcScores = ranking.scores
    }
    
    func updateUsage() {
        refreshCPPC()
        var numCpuInfo: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpus: natural_t = 0
        
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        if err == KERN_SUCCESS, let cpuInfo = cpuInfo {
            var newThreads = self.threads
            let freq = SystemMonitor.shared.snapshot.avgCPUFreq ?? 0
            
            // Favorite cores = threads whose HighestPerf equals the max score
            // (selector 21), trimmed to the real thread count so the kext's
            // trailing zero padding can't fake a spread.
            let favorites = AMDCoreRanking.favoriteThreads(supported: self.cppcSupported,
                                                           scores: self.cppcScores,
                                                           logicalThreadCount: self.logicalCpuCount)
            
            for i in 0..<Int(numCpus) {
                let inUse: Int32
                let total: Int32
                if let prev = previousCpuInfo {
                    let index = Int32(i) * CPU_STATE_MAX
                    let user = cpuInfo[Int(index + CPU_STATE_USER)] - prev[Int(index + CPU_STATE_USER)]
                    let system = cpuInfo[Int(index + CPU_STATE_SYSTEM)] - prev[Int(index + CPU_STATE_SYSTEM)]
                    let nice = cpuInfo[Int(index + CPU_STATE_NICE)] - prev[Int(index + CPU_STATE_NICE)]
                    let idle = cpuInfo[Int(index + CPU_STATE_IDLE)] - prev[Int(index + CPU_STATE_IDLE)]
                    
                    inUse = user + system + nice
                    total = inUse + idle
                } else {
                    inUse = 0
                    total = 0
                }
                
                let usage = total > 0 ? Double(inUse) / Double(total) * 100.0 : 0.0
                
                if i < self.logicalCpuCount {
                    newThreads[i] = ThreadData(id: i,
                                               isLogical: i >= self.physicalCpuCount,
                                               usage: usage,
                                               freqMHz: Double(freq),
                                               isFavoriteCore: favorites.contains(i))
                }
            }
            
            if let prev = previousCpuInfo {
                let prevSize = vm_size_t(previousNumCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: prev)), prevSize)
            }
            
            self.previousCpuInfo = cpuInfo
            self.previousNumCpuInfo = numCpuInfo
            self.threads = newThreads
        }
    }
    
    deinit {
        timer?.invalidate()
        if let prev = previousCpuInfo {
            let prevSize = vm_size_t(previousNumCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: prev)), prevSize)
        }
    }
}

struct ThreadGridView: View {
    @StateObject private var viewModel = ThreadGridViewModel()
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.cppcSupported && viewModel.favoriteCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                    Text("\(viewModel.favoriteCount) hilo\(viewModel.favoriteCount == 1 ? "" : "s") con mayor HighestPerf (selector 21)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(viewModel.threads) { thread in
                    ThreadCell(thread: thread)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

private struct ThreadCell: View {
    let thread: ThreadGridViewModel.ThreadData
    
    private var loadColor: Color {
        if thread.usage > 80 { return Color.red }
        if thread.usage > 50 { return Color.yellow } // user said: green (0-50%), yellow (50-80%), red (80-100%)
        return Color.green
    }
    
    private var backgroundColor: Color {
        // Threads 0..<physicalcpu: fondo #1E3A5F (azul oscuro, core físico)
        // Threads physicalcpu..<logicalcpu: fondo #4A90D9 (celeste, SMT)
        thread.isLogical ? Color(hex: "#4A90D9") : Color(hex: "#1E3A5F")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(thread.id)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                if thread.isFavoriteCore {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
                Spacer(minLength: 2)
                Text(String(format: "%.0f%%", thread.usage))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(loadColor)
                        .frame(width: geo.size.width * CGFloat(thread.usage / 100.0), height: 4)
                        .shadow(color: loadColor.opacity(0.5), radius: 2)
                }
            }
            .frame(height: 4)
            
            // Frecuencia por thread
            Text(thread.freqMHz > 0 ? String(format: "%.0f MHz", thread.freqMHz) : "--- MHz")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .frame(height: 56)
        .background(backgroundColor)
        .cornerRadius(6)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
