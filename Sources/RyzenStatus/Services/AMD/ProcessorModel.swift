//
//  ProcessorModel.swift
//  AMD Power Gadget
//
//  Created by trulyspinach, modified by Droga (2026) on 3/3/20.
//

import Cocoa
import Darwin
import Metal


actor ProcessorModel {
    static let shared = ProcessorModel()


    nonisolated let iokitLock = NSLock()
    nonisolated(unsafe) var connect: io_connect_t
    private var kextWatchdogTask: Task<Void, Never>?

    nonisolated func safeIOConnectCallMethod(
        _ selector: UInt32,
        _ scalarInput: UnsafePointer<UInt64>!,
        _ scalarInputCount: UInt32,
        _ structureInput: UnsafeRawPointer!,
        _ structureInputSize: Int,
        _ scalarOutput: UnsafeMutablePointer<UInt64>!,
        _ scalarOutputCount: UnsafeMutablePointer<UInt32>!,
        _ structureOutput: UnsafeMutableRawPointer!,
        _ structureOutputSize: UnsafeMutablePointer<Int>!
    ) -> kern_return_t {
        iokitLock.lock()
        defer { iokitLock.unlock() }
        if connect == 0 { return kIOReturnNoDevice }
        return IOConnectCallMethod(connect, selector, scalarInput, scalarInputCount, structureInput, structureInputSize, scalarOutput, scalarOutputCount, structureOutput, structureOutputSize)
    }


    class TerminationState {
        private let lock = NSLock()
        private var _isTerminating = false
        var isTerminating: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _isTerminating
            }
            set {
                lock.lock()
                _isTerminating = newValue
                lock.unlock()
            }
        }
    }
    nonisolated let terminationState = TerminationState()
    nonisolated var isTerminating: Bool { terminationState.isTerminating }

    private var cachedMetric : [Float] = []
    private var numberOfCores : Int = 0
    private var lastMLoad : Double = 0

    private var PStateDef : [UInt64] = []
    private var PStateCur : Int = 0
    private var instructionDelta : [UInt64] = []
    private var loadIndex : [Float] = []
    private var previousCpuLoadInfo : [processor_cpu_load_info] = []
    private var PStateDefClock : [Float] = []
    private var validPStateLength : Int = 0
    private var emulatedPState : Int = 0
    private var isEmulatingPStates : Bool = false
    private var emulatedPStateDefClock : [Float] = []
    
    // Performance optimization: cache for expensive kernel calls
    private var cachedGPUStats: (temp: Float, power: Float, util: Float, vram: Float, fan: Float, freq: Float, lastUpdate: Date) = (0, 0, 0, 0, 0, 0, .distantPast)
    // gpuStatsCacheInterval removed — IOAcceleratorCache owns the 500ms refresh cadence.

    // Thread-safe power cache: readable nonisolated from any queue (SystemMonitor, MenuBarRenderer)
    // Uses same class-wrapper pattern as TerminationState to avoid actor isolation issues.
    final class PowerCache {
        private let lock = NSLock()
        private var _cpuWatts: Double = 0
        private var _gpuWatts: Double = 0

        var cpuWatts: Double {
            lock.lock(); defer { lock.unlock() }; return _cpuWatts
        }
        var gpuWatts: Double {
            lock.lock(); defer { lock.unlock() }; return _gpuWatts
        }
        func setCPU(_ w: Double) {
            lock.lock()
            _cpuWatts = max(0, w)
            lock.unlock()
        }
        func setGPU(_ w: Double) {
            lock.lock()
            _gpuWatts = max(0, w)
            lock.unlock()
        }
    }
    nonisolated let powerCache = PowerCache()

    /// Latest CPU package power in Watts. Thread-safe, no await needed.
    nonisolated var lastCPUPowerWatts: Double { powerCache.cpuWatts }
    /// Latest GPU total power in Watts. Thread-safe, no await needed.
    nonisolated var lastGPUPowerWatts: Double { powerCache.gpuWatts }

    // Thread-safe GPU cache for kext readings (selectors 27-30)
    // Provides nonisolated access to GPU temperature and power from the kext.
    final class GPUCache {
        private let lock = NSLock()
        private var _count: Int = 0
        private var _temperatures: [Double] = []
        private var _powers: [Double] = []
        private var _capabilities: [UInt8] = []

        var count: Int {
            lock.lock(); defer { lock.unlock() }; return _count
        }
        var temperatures: [Double] {
            lock.lock(); defer { lock.unlock() }; return _temperatures
        }
        var powers: [Double] {
            lock.lock(); defer { lock.unlock() }; return _powers
        }
        var capabilities: [UInt8] {
            lock.lock(); defer { lock.unlock() }; return _capabilities
        }
        func update(count: Int, temperatures: [Double], powers: [Double], capabilities: [UInt8] = []) {
            lock.lock()
            _count = count
            _temperatures = temperatures
            _powers = powers
            _capabilities = capabilities
            lock.unlock()
        }
    }
    nonisolated let gpuCache = GPUCache()

    /// Latest GPU temperature from kext (selectors 27-28). 0 if unavailable.
    nonisolated var lastKextGPUTemperature: Double {
        let temps = gpuCache.temperatures
        return temps.first ?? 0
    }
    /// Latest GPU power from kext (selectors 27-29). 0 if unavailable.
    nonisolated var lastKextGPUPower: Double {
        let powers = gpuCache.powers
        return powers.first ?? 0
    }
    /// Number of GPUs detected by kext (selector 27).
    nonisolated var lastKextGPUCount: Int { gpuCache.count }

    private var cpuListedAsSupported : Bool = false

    var systemConfig : [String : String] = [:]
    var kextVersion : String = ""
    var cpuidBasic : [UInt64] = []
    var boardValid = false
    var boardName : String = "Unknown"
    var boardVendor : String = "Unknown"
    var fetchRetry : Int = 10
    var fetchRetry2 : Int = 10
    var retryTimer : Timer?

    var cpuFamily: Int {
        return cpuidBasic.count > 0 ? Int(cpuidBasic[0]) : 0
    }

    /// CPU model from the kext's CPUID report (selector 7, dataOut[1]).
    /// Combined with `cpuFamily` this classifies the Zen generation.
    var cpuModel: Int {
        return cpuidBasic.count > 1 ? Int(cpuidBasic[1]) : 0
    }

    /// Physical core count from the kext's CPUID report (selector 7,
    /// dataOut[2]) — the bound used by the kext's Curve Optimizer (selector 111).
    var physicalCoreCount: Int {
        return cpuidBasic.count > 2 ? Int(cpuidBasic[2]) : 0
    }
    
    // CPU profile: architecture name and capability flags from the kext.
    // Populated by loadCPUProfile().
    struct CPUProfile {
        var archName: String = ""           // e.g. "Zen 3 Vermeer"
        var pmDispatchAllowed: Bool = false // Full PM dispatch (Zen 1/2)
        var legacyPstateAllowed: Bool = false
        var supportsCPPC: Bool = false
        
        var modeDescription: String {
            pmDispatchAllowed ? "Full PM Dispatch" : "Telemetry-only"
        }
        
        var availableFeatures: [String] {
            var features: [String] = []
            if pmDispatchAllowed { features.append("PM Dispatch") }
            if legacyPstateAllowed { features.append("Legacy P-States") }
            if supportsCPPC { features.append("CPPC") }
            if features.isEmpty { features.append("Telemetry only") }
            return features
        }
    }
    
    private(set) var cpuProfile = CPUProfile()
    
    private func loadCPUProfile() {
        guard connect != 0 else { return }
        let nameSize = 16
        let flagsSize = MemoryLayout<UInt64>.size
        let totalSize = nameSize + flagsSize
        
        var output = [UInt8](repeating: 0, count: totalSize)
        var outputSize = totalSize
        
        let res: kern_return_t = safeIOConnectCallMethod( AMDKextSelector.cpuPowerProfile.id, nil, 0, nil, 0,
                                                      nil, nil,
                                                      &output, &outputSize)
        guard res == KERN_SUCCESS, outputSize >= nameSize else {
            return
        }
        
        // Read architecture name (null-terminated within first 16 bytes)
        let nameBytes = output[0..<nameSize]
        let name = nameBytes.withUnsafeBufferPointer { buf -> String in
            if let nullIdx = buf.firstIndex(of: 0) {
                return String(decoding: buf[..<nullIdx], as: UTF8.self)
            }
            return String(decoding: buf, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
        
        // Read flags
        var flags: UInt64 = 0
        if outputSize >= totalSize {
            withUnsafeMutableBytes(of: &flags) { flagsBuf in
                let src = output[nameSize..<nameSize + MemoryLayout<UInt64>.size]
                src.withUnsafeBytes { srcBuf in
                    flagsBuf.copyMemory(from: srcBuf)
                }
            }
        }
        
        cpuProfile = CPUProfile(
            archName: name,
            pmDispatchAllowed: (flags & (1 << 0)) != 0,
            legacyPstateAllowed: (flags & (1 << 1)) != 0,
            supportsCPPC: (flags & (1 << 2)) != 0
        )
    }
    
    var isLegacyPStateSupported: Bool {
        // Use kext profile when available, fallback to family heuristic
        if !cpuProfile.archName.isEmpty {
            return cpuProfile.legacyPstateAllowed
        }
        return cpuFamily > 0 && cpuFamily <= 0x17
    }

    init() {
        let serviceObject = IOServiceGetMatchingService(kIOMainPortDefault,
                                                        IOServiceMatching("AMDRyzenCPUPowerManagement"))
        let conn: io_connect_t
        if serviceObject == 0 {
            conn = 0
        } else {
            var c: io_connect_t = 0
            let status = IOServiceOpen(serviceObject, mach_task_self_, 0, &c)
            IOObjectRelease(serviceObject)
            if status != KERN_SUCCESS {
                conn = 0
                NSLog("ProcessorModel: IOServiceOpen failed status=0x%08x (service was present)", status)
            } else {
                conn = c
            }
        }
        self.connect = conn

        // Deferred actor-isolated initialization: the IOKit connection is established
        // synchronously, but all further setup (version check, CPUID, board info,
        // metrics, P-state defs) happens asynchronously via finishInit().
        // This avoids Swift 6 warnings about calling actor-isolated methods from
        // a nonisolated init() context.
        Task { await self._finishInit() }
        
        self.kextWatchdogTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self else { break }
                let serviceObject = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AMDRyzenCPUPowerManagement"))
                if serviceObject == 0 {
                    self.iokitLock.lock()
                    let wasConnected = (self.connect != 0)
                    if wasConnected {
                        IOServiceClose(self.connect)
                        self.connect = 0
                    }
                    self.iokitLock.unlock()
                    
                    if wasConnected {
                        self.terminationState.isTerminating = true
                        NSLog("ProcessorModel: AMDRyzenCPUPowerManagement was unloaded!")
                        NotificationCenter.default.post(name: NSNotification.Name("KextUnloaded"), object: nil)
                    }
                } else {
                    IOObjectRelease(serviceObject)
                }
            }
        }
    }

    private(set) var isKextAvailable: Bool = false

    private func _finishInit() async {
        if connect == 0 {
            NSLog("ProcessorModel: AMDRyzenCPUPowerManagement.kext is not loaded. Running in degraded mode.")
            isKextAvailable = false
            return
        }
        isKextAvailable = true

        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 0

        let maxStrLength = 16
        var outputStr: [CChar] = [CChar](repeating: 0, count: maxStrLength)
        var outputStrCount: Int = maxStrLength
        let versionResult = safeIOConnectCallMethod( AMDKextSelector.kextVersion.id, nil, 0, nil, 0,
                                                 &scalerOut, &outputCount,
                                                 &outputStr, &outputStrCount)
        guard versionResult == KERN_SUCCESS, outputStrCount > 0 else {
            NSLog("ProcessorModel: failed to read kext version, kr=0x%08x", versionResult)
            kextVersion = ""
            return
        }
        kextVersion = String(cString: Array(outputStr[0...min(outputStrCount - 1, outputStr.count - 1)]))

        let compatVers = ["1.0.0"]

        var isCompatible = compatVers.contains(kextVersion)
        if !isCompatible {
            if kextVersion.compare("1.0.0", options: .numeric) != .orderedAscending {
                isCompatible = true
            }
        }

        if !isCompatible {
            let fmt = NSLocalizedString("Your AMD Power Management kext version (%@) is outdated and no longer API compatible. Please use version 1.0.0 or newer and start this application again.", comment: "")
            alertAndQuit(message: String(format: fmt, kextVersion))
            return
        }

        loadCPUID()
        loadCPUProfile()
        loadBaseBoardInfo()
        loadMetric()
        loadSystemConfig()
        loadPStateDef()
        loadPStateDefClock()

        // Initialize SuperIO for fan reading (selector 90)
        _ = kernelGetUInt64(count: 2, selector: AMDKextSelector.fanInit)

        if numberOfCores < 1 {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Error reading CPU data.", comment: "")
                alert.informativeText = NSLocalizedString("This application can not be launched due to AMD Power Management kext reporting incorrect data.", comment: "")
                alert.alertStyle = .critical
                alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    nonisolated func closeDriver() {
        terminationState.isTerminating = true
        IOServiceClose(connect)
    }

    func alertAndQuit(message : String){
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("No AMD Power Management Kext Found!", comment: "")
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Quit and Download", comment: ""))
            NSApp.activate(ignoringOtherApps: true)
            let res = alert.runModal()

            if res == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/DrogaBox/SMCAMDProcessor-personal") {
                    NSWorkspace.shared.open(url)
                }
            }

            NSApplication.shared.terminate(nil)
        }
    }

    func alertDontQuit(message : String){
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Kext Update Available", comment: "")
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Download", comment: ""))
            NSApp.activate(ignoringOtherApps: true)
            let res = alert.runModal()

            if res == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/DrogaBox/SMCAMDProcessor-personal") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Kernel IOKit Calls

    nonisolated private func logKernelError(_ status: kern_return_t) {
        if status != KERN_SUCCESS {
            NSLog("ProcessorModel: selector failed with %@", String(cString: mach_error_string(status)))
        }
    }

    nonisolated func kernelGetFloats(count: Int, selector: UInt32) -> [Float] {
        if isTerminating || Task.isCancelled { return [] }
        var scalarOut: UInt64 = 0
        var scalarOutCount: UInt32 = 1
        var output = [Float](repeating: 0, count: count)
        var outputSize = MemoryLayout<Float>.size * count

        let status = safeIOConnectCallMethod( selector, nil, 0, nil, 0,
                                         &scalarOut, &scalarOutCount,
                                         &output, &outputSize)
        guard status == KERN_SUCCESS else {
            logKernelError(status)
            return []
        }

        let valid = min(count, outputSize / MemoryLayout<Float>.size)
        return Array(output.prefix(valid))
    }

    nonisolated func kernelGetUInt64(count: Int, selector: UInt32) -> [UInt64] {
        if isTerminating || Task.isCancelled { return [] }
        var scalarOut: UInt64 = 0
        var scalarOutCount: UInt32 = 1
        var output = [UInt64](repeating: 0, count: count)
        var outputSize = MemoryLayout<UInt64>.size * count

        let status = safeIOConnectCallMethod( selector, nil, 0, nil, 0,
                                         &scalarOut, &scalarOutCount,
                                         &output, &outputSize)
        guard status == KERN_SUCCESS else {
            logKernelError(status)
            return []
        }

        let valid = min(count, outputSize / MemoryLayout<UInt64>.size)
        return Array(output.prefix(valid))
    }

    nonisolated func kernelGetUInt16s(count: Int, selector: UInt32) -> [UInt16] {
        if isTerminating || Task.isCancelled { return [] }
        var scalarOut: UInt64 = 0
        var scalarOutCount: UInt32 = 1
        var output = [UInt16](repeating: 0, count: count)
        var outputSize = MemoryLayout<UInt16>.size * count

        let status = safeIOConnectCallMethod( selector, nil, 0, nil, 0,
                                         &scalarOut, &scalarOutCount,
                                         &output, &outputSize)
        guard status == KERN_SUCCESS else {
            logKernelError(status)
            return []
        }

        let valid = min(count, outputSize / MemoryLayout<UInt16>.size)
        return Array(output.prefix(valid))
    }

    /// IOKit `kIOReturnNotPrivileged` (0xe00002c1) — write selectors require root or `-amdpnopchk`.
    static let kIOReturnNotPrivilegedCode: kern_return_t = kern_return_t(bitPattern: 0xe00002c1)

    nonisolated func kernelSetStruct(selector: UInt32, data: Data) -> kern_return_t {
        if isTerminating || Task.isCancelled { return kIOReturnNotReady }
        return data.withUnsafeBytes { rawBuffer -> kern_return_t in
            guard let baseAddress = rawBuffer.baseAddress else { return kIOReturnBadArgument }
            return safeIOConnectCallMethod( selector, nil, 0, baseAddress, data.count, nil, nil, nil, nil)
        }
    }

    @discardableResult
    nonisolated func kernelSetStructSuccess(selector: UInt32, data: Data) -> Bool {
        kernelSetStruct(selector: selector, data: data) == KERN_SUCCESS
    }

    nonisolated func kernelGetString(selector : UInt32, args : [UInt64]) -> String {
        if isTerminating || Task.isCancelled { return "" }
        var argcpy = args
        var outbuffersize = 16
        var outputStr: [CChar] = [CChar](repeating: 0, count: outbuffersize)

        var res = safeIOConnectCallMethod( selector, &argcpy, UInt32(args.count), nil, 0,
                                      nil, nil,
                                      &outputStr, &outbuffersize)

        if res == MIG_ARRAY_TOO_LARGE{
            outputStr = [CChar](repeating: 0, count: outbuffersize)
            res = safeIOConnectCallMethod( selector, &argcpy, UInt32(args.count), nil, 0,
                                      nil, nil,
                                      &outputStr, &outbuffersize)
        }
        if res != KERN_SUCCESS || outbuffersize <= 0 {
            if res != KERN_SUCCESS { logKernelError(res) }
            return ""
        }

        var validBytes = Array(outputStr.prefix(outbuffersize))
        if validBytes.isEmpty || validBytes.last != 0 {
            validBytes.append(0)
        }
        return String(cString: validBytes)
    }

    /// Returns the raw IOKit status (KERN_SUCCESS / kIOReturnNotPrivileged / …).
    @discardableResult
    nonisolated func kernelSetUInt64Status(selector: UInt32, args: [UInt64]) -> kern_return_t {
        if isTerminating || Task.isCancelled { return kIOReturnNotReady }
        var argcpy = args
        return safeIOConnectCallMethod( selector, &argcpy, UInt32(args.count), nil, 0,
                                   nil, nil, nil, nil)
    }

    nonisolated func kernelSetUInt64(selector: UInt32, args: [UInt64]) -> Bool {
        kernelSetUInt64Status(selector: selector, args: args) == KERN_SUCCESS
    }

    /// Human-readable message for failed kernel write calls (localized).
    nonisolated static func privilegeHint(for status: kern_return_t) -> String? {
        if status == kIOReturnNotPrivilegedCode {
            return NSLocalizedString(
                "This action requires administrator privileges. Run AMD Power Gadget as root, or add the boot argument -amdpnopchk for debugging. Note: GPU temperature injection for fan curves also requires privilege.",
                comment: "Shown when a privileged kext write is denied"
            )
        }
        if status != KERN_SUCCESS {
            return String(cString: mach_error_string(status))
        }
        return nil
    }

    private func loadMetric(){
        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 1

        let maxStrLength = 67 //MaxCpu + 3
        var outputStr: [Float] = [Float](repeating: 0, count: maxStrLength)
        var outputStrCount: Int = 4/*sizeof(float)*/ * maxStrLength
        let res = safeIOConnectCallMethod( AMDKextSelector.coreMetric.id, nil, 0, nil, 0,
                                      &scalerOut, &outputCount,
                                      &outputStr, &outputStrCount)

        if res != KERN_SUCCESS {
            logKernelError(res)
            return
        }

        numberOfCores = Int(scalerOut)
        let endIdx = min(numberOfCores + 2, outputStr.count - 1)
        cachedMetric = outputStr.count > 0 && endIdx >= 0 ? Array(outputStr[0...endIdx]) : []
        if outputStr.count > 2 { PStateCur = Int(outputStr[2]) }

        // metric[0] = CPU Package Power (W) — update the thread-safe cache
        if outputStr.count > 0 {
            powerCache.setCPU(Double(outputStr[0]))
        }

        lastMLoad = ProcessInfo.processInfo.systemUptime
    }

    private func loadLoadIndex(){
        var numCPUs: mach_msg_type_number_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        
        // mach_host_self() returns a send right the caller owns; release it or
        // each call leaks a mach port (this runs on every sampling tick).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &infoArray, &infoCount)
        guard kr == KERN_SUCCESS, let info = infoArray else {
            return
        }
        
        let count = Int(numCPUs)
        var newLoads = [Float](repeating: 0.0, count: count)
        
        let cpuLoadData = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: count) { $0 }
        
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        
        if previousCpuLoadInfo.count == count {
            for i in 0..<count {
                let prev = previousCpuLoadInfo[i]
                let curr = cpuLoadData[i]
                
                let userDiff   = max(0.0, Double(curr.cpu_ticks.0 &- prev.cpu_ticks.0))
                let systemDiff = max(0.0, Double(curr.cpu_ticks.1 &- prev.cpu_ticks.1))
                let idleDiff   = max(0.0, Double(curr.cpu_ticks.2 &- prev.cpu_ticks.2))
                let niceDiff   = max(0.0, Double(curr.cpu_ticks.3 &- prev.cpu_ticks.3))
                
                let total = userDiff + systemDiff + idleDiff + niceDiff
                if total > 0 {
                    newLoads[i] = Float(userDiff + systemDiff + niceDiff) / Float(total)
                } else {
                    newLoads[i] = 0.0
                }
            }
        }
        
        previousCpuLoadInfo = (0..<count).map { cpuLoadData[$0] }
        
        loadIndex = newLoads
    }

    private func loadPStateDef(){

        PStateDef = kernelGetUInt64(count: 8, selector: AMDKextSelector.pStateDef)
        var i = 0
        while i < PStateDef.count {
            if (PStateDef[i] & 0x8000000000000000) == 0 { //LOL Swift
                break
            }
            i += 1
        }
        validPStateLength = i

    }

    private func loadCPUID(){
        cpuidBasic = kernelGetUInt64(count: 8, selector: AMDKextSelector.cpuidInfo.id)
    }

    private func loadBaseBoardInfo(){
        var scalerOut: [UInt64] = [UInt64](repeating: 0, count: 1)
        var outputCount: UInt32 = 1

        let maxStrLength = 128
        var outputStr: [CChar] = [CChar](repeating: 0, count: maxStrLength)
        var outputStrCount: Int = maxStrLength
        let _ = safeIOConnectCallMethod( AMDKextSelector.baseboardInfo.id, nil, 0, nil, 0,
                                      &scalerOut, &outputCount,
                                      &outputStr, &outputStrCount)

        if scalerOut[0] == 1 {
            boardValid = true
            boardVendor = String(cString: Array(outputStr[0...64-1]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .controlCharacters)
            boardName = String(cString: Array(outputStr[64...128-1]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .controlCharacters)
        }

    }

    private func loadPStateDefClock(){
        // If already in emulation mode, do not read from the kernel again.
        // Emulated values are static and correct for the whole session.
        if isEmulatingPStates {
            PStateDefClock = emulatedPStateDefClock
            return
        }

        PStateDefClock = kernelGetFloats(count: 10, selector: AMDKextSelector.pStateDefClock)

        // Sanitizar valores NaN/Inf del kernel (CpuDfsId=0 produce NaN en la división)
        for i in 0..<PStateDefClock.count {
            if PStateDefClock[i].isNaN || PStateDefClock[i].isInfinite {
                PStateDefClock[i] = 0.0
            }
        }

        // If we detect only one (or zero) legacy P-states due to UEFI/BIOS behavior on Zen 3,
        // activate permanent emulation mode for this session.
        if validPStateLength <= 1 {
            var baseClock: Float = 0.0
            if PStateDefClock.count > 0 && PStateDefClock[0] > 1000.0 {
                baseClock = PStateDefClock[0]
            }

            // If baseClock is invalid, derive it from the CPU brand string
            if baseClock < 1000.0 {
                let cpuBrand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string").lowercased()
                if let range = cpuBrand.range(of: #"(\d+\.\d+)\s*ghz"#, options: .regularExpression) {
                    let ghzStr = cpuBrand[range].replacingOccurrences(of: "ghz", with: "").trimmingCharacters(in: .whitespaces)
                    if let ghz = Float(ghzStr) {
                        baseClock = ghz * 1000.0
                    }
                }
                if baseClock < 1000.0 {
                    if cpuBrand.contains("5900xt") { baseClock = 3300.0 }
                    else if cpuBrand.contains("5950x") { baseClock = 3400.0 }
                    else if cpuBrand.contains("5900x") { baseClock = 3700.0 }
                    else if cpuBrand.contains("5800x") { baseClock = 3800.0 }
                    else if cpuBrand.contains("5600x") { baseClock = 3700.0 }
                    else { baseClock = 3300.0 }
                }
            }

            var maxBoost: Float = baseClock + 1000.0
            let cpuBrand = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string").lowercased()
            if cpuBrand.contains("5900xt") || cpuBrand.contains("5950x") {
                maxBoost = 4900.0
            } else if cpuBrand.contains("5900x") || cpuBrand.contains("5800x") || cpuBrand.contains("5700x") {
                maxBoost = 4800.0
            } else if cpuBrand.contains("5600x") || cpuBrand.contains("5600g") {
                maxBoost = 4600.0
            } else if cpuBrand.contains("3900x") || cpuBrand.contains("3950x") {
                maxBoost = 4600.0
            } else if cpuBrand.contains("3800x") || cpuBrand.contains("3700x") {
                maxBoost = 4500.0
            } else if cpuBrand.contains("3600") {
                maxBoost = 4200.0
            }

            if maxBoost <= baseClock {
                maxBoost = baseClock + 1000.0
            }

            let step5 = maxBoost
            let step4 = baseClock + (maxBoost - baseClock) * 0.5
            let step3 = baseClock
            let step2 = Float(2800.0)
            let step1 = Float(2200.0)

            PStateDefClock = [step5, step4, step3, step2, step1, 0.0, 0.0, 0.0, 0.0, 0.0]
            emulatedPStateDefClock = PStateDefClock
            validPStateLength = 5
            isEmulatingPStates = true
        }
    }

    func refreshPStateDef() {
        loadPStateDefClock()
    }

    nonisolated func getHPCpus() -> Int{
        let o = kernelGetUInt64(count: 1, selector: AMDKextSelector.hpCpusRead)
        return o.count > 0 ? Int(o[0]) : 0
    }

    @discardableResult
    func setPState(state : Int) -> kern_return_t {
        // If we are in emulation mode (hardware reports only 1 P-state but we expose 5 in the GUI)
        if PStateDef.count > 1 && (PStateDef[1] & 0x8000000000000000) == 0 {
            // Smart mapping to real hardware controls in Zen 3 — surface first privilege failure
            var status: kern_return_t = KERN_SUCCESS
            switch state {
            case 0, 1: // Boost / High Performance
                status = setCPB(enabled: true)
                if status == KERN_SUCCESS { status = setLPM(enabled: false) }
                if status == KERN_SUCCESS { status = setPPM(enabled: true) }
            case 2: // Base Clock
                status = setCPB(enabled: false)
                if status == KERN_SUCCESS { status = setLPM(enabled: false) }
                if status == KERN_SUCCESS { status = setPPM(enabled: true) }
            case 3: // Balanced / Low-Medium
                status = setCPB(enabled: false)
                if status == KERN_SUCCESS { status = setLPM(enabled: false) }
                if status == KERN_SUCCESS { status = setPPM(enabled: true) }
            case 4: // LPM / Idle
                status = setCPB(enabled: false)
                if status == KERN_SUCCESS { status = setLPM(enabled: true) }
            default:
                break
            }
            if status == KERN_SUCCESS {
                emulatedPState = state
            } else {
                logKernelError(status)
            }
            return status
        }

        var input: [UInt64] = [UInt64(state)]
        let res = safeIOConnectCallMethod( AMDKextSelector.pStateWrite.id, &input, 1, nil, 0,
                                      nil, nil,
                                      nil, nil)

        if res != KERN_SUCCESS {
            logKernelError(res)
        }
        return res
    }

    func getPState() -> Int {
        if PStateDef.count > 1 && (PStateDef[1] & 0x8000000000000000) == 0 {
            let lpm = getLPM()
            let cpb = getCPB() // devuelve [cpbSupported, cpbEnabled]

            if lpm {
                return 4 // LPM / Idle
            } else if cpb.count > 1 && !cpb[1] {
                return 2 // Base Clock (CPB desactivado)
            } else {
                // If CPB is active, return the last emulated selection (0, 1, or 3)
                // otherwise default to 0 (Boost)
                return emulatedPState == 4 || emulatedPState == 2 ? 0 : emulatedPState
            }
        }
        return PStateCur
    }

    nonisolated func getCPPCActiveMode() -> (active: Bool, epp: UInt8) {
        var output: [UInt64] = [0, 0]
        var outputCount: UInt32 = 2
        let res = safeIOConnectCallMethod( AMDKextSelector.cppcActive.id, nil, 0, nil, 0, &output, &outputCount, nil, nil)
        if res != KERN_SUCCESS {
            logKernelError(res)
            return (false, 0x3F)
        }
        return (output[0] == 1, UInt8(output[1]))
    }

    nonisolated func setCPPCActiveMode(active: Bool) -> kern_return_t {
        var input: [UInt64] = [active ? 1 : 0]
        return safeIOConnectCallMethod( AMDKextSelector.cppcActiveMode.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    func setCPPCEPPValue(epp: UInt8) -> kern_return_t {
        var input: [UInt64] = [UInt64(epp)]
        return safeIOConnectCallMethod( AMDKextSelector.eppValue.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    func getPStateDef() -> [UInt64]{
        return PStateDef
    }

    func getValidPStateClocks() -> [Float] {
        if validPStateLength <= 0 || PStateDefClock.isEmpty {
            return [3300.0] // Safe fallback: return at least one valid value
        }
        let len = min(validPStateLength, PStateDefClock.count)
        return Array(PStateDefClock[0...len-1])
    }

    func getMetric(forced : Bool) -> [Float] {
        if forced || (ProcessInfo.processInfo.systemUptime - lastMLoad >= 1.0) {
            loadMetric()
        }
        return cachedMetric
    }

    func getNumOfCore() -> Int {
        numberOfCores
    }

    func getLoadIndex() -> [Float] {
        loadLoadIndex()
        return loadIndex
    }

    nonisolated func getCPB() -> [Bool] {
        let o = kernelGetUInt64(count: 2, selector: AMDKextSelector.cpbRead)
        return o.map{ $0 == 0 ? false : true }
    }

    @discardableResult
    func setCPB(enabled: Bool) -> kern_return_t {
        var input: [UInt64] = [UInt64(enabled ? 1 : 0)]
        return safeIOConnectCallMethod( AMDKextSelector.cpb.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    nonisolated func getPPM() -> Bool {
        let o = kernelGetUInt64(count: 2, selector: AMDKextSelector.ppmRead)
        return o.count > 0 && o[0] != 0
    }

    @discardableResult
    func setPPM(enabled: Bool) -> kern_return_t {
        var input: [UInt64] = [UInt64(enabled ? 1 : 0)]
        return safeIOConnectCallMethod( AMDKextSelector.ppm.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    nonisolated func getLPM() -> Bool {
        let o = kernelGetUInt64(count: 1, selector: AMDKextSelector.lpmRead)
        return o.count > 0 && o[0] != 0
    }

    @discardableResult
    func setLPM(enabled: Bool) -> kern_return_t {
        var input: [UInt64] = [UInt64(enabled ? 1 : 0)]
        return safeIOConnectCallMethod( AMDKextSelector.lpm.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    // MARK: - Power Presets (EPP + CPB + PPM/LPM)

    /// Applies a full power preset through the existing write selectors:
    /// EPP (25), CPB (12) and PPM/LPM (14/19). PPM and LPM are mutually
    /// exclusive — the preset's choice wins and the other is forced off.
    /// Returns per-component IOKit statuses so the UI can surface privilege
    /// errors (`kIOReturnNotPrivilegedCode`) per feature.
    func applyPowerPreset(_ preset: AMDPowerPreset) -> AMDPowerPresetApplyResult {
        let epp = setCPPCEPPValue(epp: preset.eppValue)
        let cpb = setCPB(enabled: preset.cpbEnabled)

        // PPM (selector 14) and LPM (selector 19) share the kext's
        // `setPMPStateLimit`; exactly one may be on at a time.
        var ppm: kern_return_t = KERN_SUCCESS
        var lpm: kern_return_t = KERN_SUCCESS
        if preset.lpmEnabled {
            ppm = setPPM(enabled: false)   // enforce exclusivity
            lpm = setLPM(enabled: true)
        } else {
            lpm = setLPM(enabled: false)   // enforce exclusivity
            ppm = setPPM(enabled: preset.ppmEnabled)
        }

        return AMDPowerPresetApplyResult(epp: epp, cpb: cpb, ppm: ppm, lpm: lpm)
    }

    nonisolated func getInstructionDelta() -> [UInt64]{
        let o = kernelGetUInt64(count: 1, selector: AMDKextSelector.deltaInstructions.id)
        return o.count > 0 ? [o[0]] : [0]
    }

    func setPState(def : [UInt64]) -> Int{
        if def.count != 8 {
            return -1
        }

        var input: [UInt64] = def
        let res = safeIOConnectCallMethod( AMDKextSelector.pStateManual.id, &input, 8, nil, 0,
                                      nil, nil,
                                      nil, nil)


        if res != KERN_SUCCESS {
            logKernelError(res)
            return Int(res)
        }

        loadPStateDef()
        loadPStateDefClock()
        return 0
    }

    static func sysctlString(key : String) -> String {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        // P1-fix: size == 0 means the key is absent or the call failed.
        // Do NOT allocate an empty [CChar] — String(cString:) would read
        // past the buffer boundary looking for a NUL terminator.
        guard size > 0 else { return "" }
        var machine = [CChar](repeating: 0, count: size + 1) // +1 guarantees NUL terminator
        sysctlbyname(key, &machine, &size, nil, 0)
        return String(cString: machine)
    }

    static func sysctlInt64(key : String) -> Int64 {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        sysctlbyname(key, &v, &size, nil, 0)
        return v
    }

    func loadSystemConfig() {
        systemConfig["ver"] = kextVersion
        systemConfig["cpu"] = ProcessorModel.sysctlString(key: "machdep.cpu.brand_string")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        systemConfig["os"] = ProcessorModel.sysctlString(key: "kern.osproductversion")
        systemConfig["mem"] = "\(Int(ProcessorModel.sysctlInt64(key: "hw.memsize") / 1024 / 1024))"

        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        if let path = paths.last, let dictionary = try? FileManager.default.attributesOfFileSystem(forPath: path) {
            if let size = dictionary[FileAttributeKey.systemSize] as? NSNumber {
                systemConfig["rs"] = "\(Int(Int(truncating: size) / 1024 / 1024))"
            }
        }

        if boardValid {
            systemConfig["mb"] = "\(boardName) \(boardVendor)"
        }

        // GPU info detection optimized and offloaded to avoid blocking the actor
        Task.detached(priority: .background) {
            var gpuString = "Unknown"
            var iter: io_iterator_t = 0
            let err = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                   IOServiceMatching("IOPCIDevice"), &iter)
            if err == kIOReturnSuccess {
                defer { IOObjectRelease(iter) }
                var foundGPU = false
                while !foundGPU {
                    let reg = IOIteratorNext(iter)
                    guard reg != 0 else { break }
                    defer { IOObjectRelease(reg) }
                    
                    var serviceDictionary: Unmanaged<CFMutableDictionary>?
                    let e = IORegistryEntryCreateCFProperties(reg, &serviceDictionary, kCFAllocatorDefault, .zero)
                    guard e == kIOReturnSuccess, let dic = serviceDictionary?.takeRetainedValue() as? NSDictionary else { continue }
                    
                    if let type = dic.object(forKey: "IOName") as? String, type == "display" {
                        if let model = dic.object(forKey: "model") as? Data {
                            let rawStr = String(data: model, encoding: .ascii) ?? String(data: model, encoding: .utf8) ?? "Unknown GPU"
                            gpuString = rawStr
                                .trimmingCharacters(in: .controlCharacters)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        foundGPU = true
                    }
                }
            }
            await self.updateGPUConfig(gpuString)
        }
    }

    private func updateGPUConfig(_ gpu: String) {
        self.systemConfig["gpu"] = gpu
    }

    // MARK: - Kext GPU Data (Selectors 27-30)

    /// Number of AMD GPUs detected by the kext (selector 27).
    /// Returns 0 if selectors are not implemented in the loaded kext.
    nonisolated func getKextGPUCount() -> Int {
        let result = kernelGetUInt64(count: 1, selector: AMDKextSelector.gpuLoad)
        return result.isEmpty ? 0 : Int(result[0])
    }

    /// GPU temperatures from kext in SP78 format (selector 28).
    /// Convert to °C: `Double(Int16(bitPattern: raw)) / 256.0`
    nonisolated func getKextGPUTemperatures() -> [UInt16] {
        return kernelGetUInt16s(count: 16, selector: AMDKextSelector.gpuStats1.id)
    }

    /// GPU powers from kext in watts (selector 29).
    nonisolated func getKextGPUPowers() -> [Float] {
        return kernelGetFloats(count: 16, selector: AMDKextSelector.gpuStats2.id)
    }

    /// GPU capabilities from kext (selector 30).
    /// Bit 0: supportsPower. The kext packs each GPU's capability bitmap as a
    /// little-endian uint64 (one slot per GPU); reduce each slot to its low byte
    /// so the result is a per-GPU `UInt8` array as documented (bit 0 = supportsPower).
    nonisolated func getKextGPUCapabilities() -> [UInt8] {
        let raw = kernelGetUInt64(count: 16, selector: AMDKextSelector.gpuStats3.id)
        return raw.map { UInt8(truncatingIfNeeded: $0) }
    }

    /// Refresh cached kext GPU data. Call from actor context.
    func refreshKextGPUStats() {
        let count = getKextGPUCount()
        guard count > 0 else {
            gpuCache.update(count: 0, temperatures: [], powers: [])
            return
        }

        let rawTemps = getKextGPUTemperatures()
        let temps = rawTemps.map { Double(Int16(bitPattern: $0)) / 256.0 }
        let powers = getKextGPUPowers().map(Double.init)
        let capabilities = getKextGPUCapabilities()

        gpuCache.update(count: count, temperatures: temps, powers: powers, capabilities: capabilities)
    }

    // MARK: - GPU Statistics (via IOAcceleratorCache — single shared IOKit iterator)

    /// Refreshes the GPU stats tuple from the shared IOAcceleratorCache.
    /// The cache throttles IOKit walks to once per 500ms; this call is cheap
    /// when called more frequently (returns cached snapshot).
    private func updateGPUStatsCache() async {
        let s   = await IOAcceleratorCache.shared.snapshot()
        let temp  = (s["Temperature(C)"] as? NSNumber)?.floatValue ?? (s["Temperature(C)"] as? Float) ?? 0
        let power = (s["Total Power(W)"] as? NSNumber)?.floatValue ?? (s["Total Power(W)"] as? Float) ?? 0
        let util  = (s["Device Utilization %"] as? NSNumber)?.floatValue ?? 0
        let vram  = (s["inUseVidMemoryBytes"] as? NSNumber)?.floatValue ?? 0
        let freq  = (s["Core Clock(MHz)"] as? NSNumber)?.floatValue ?? 0
        let rawFan = (s["Fan Speed(RPM)"] as? NSNumber)?.floatValue ?? 0
        let fan   = (temp > 0 && temp < 50.0) ? 0 : rawFan

        cachedGPUStats = (temp, power, util, vram, fan, freq, Date())
        powerCache.setGPU(Double(power))
    }
    
    func getGPUTemp() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.temp
    }

    func getGPUPower() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.power
    }

    func getGPUUtilization() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.util
    }

    func getGPUVramUsed() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.vram
    }

    func getGPUFanRPM() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.fan
    }

    func getGPUFreq() async -> Float {
        await updateGPUStatsCache()
        return cachedGPUStats.freq
    }

    nonisolated func getCCDTemperatures() -> [Float] {
        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 1
        let maxCCDs = 16
        var outputStr: [Float] = [Float](repeating: 0.0, count: maxCCDs)
        var outputStrCount: Int = MemoryLayout<Float>.size * maxCCDs
        
        let res = safeIOConnectCallMethod( AMDKextSelector.ccdTopology.id, nil, 0, nil, 0,
                                      &scalerOut, &outputCount,
                                      &outputStr, &outputStrCount)
                                      
        if res != KERN_SUCCESS {
            return []
        }
        
        let actualCCDCount = Int(scalerOut)
        if actualCCDCount <= 0 {
            return []
        }
        
        return Array(outputStr[0..<min(actualCCDCount, maxCCDs)])
    }

    nonisolated func getCPPCScore() -> (supported: Bool, scores: [UInt8]) {
        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 1
        let maxLogicalCores = 64
        var outputStr: [UInt8] = [UInt8](repeating: 0, count: maxLogicalCores)
        var outputStrCount: Int = MemoryLayout<UInt8>.size * maxLogicalCores
        
        let res = safeIOConnectCallMethod( AMDKextSelector.coreRanking.id, nil, 0, nil, 0,
                                      &scalerOut, &outputCount,
                                      &outputStr, &outputStrCount)
                                      
        if res != KERN_SUCCESS {
            return (false, [])
        }
        
        let supported = scalerOut == 1
        return (supported, Array(outputStr[0..<maxLogicalCores]))
    }

    nonisolated func getPackageC6Residency() -> UInt64 {
        let o = kernelGetUInt64(count: 1, selector: AMDKextSelector.c6ResidencyPkg)
        return o.first ?? 0
    }

    /// Reads the zero-copy telemetry packet (selector 100) — a packed
    /// `CPUSensorPacket` of exactly 304 bytes. Returns nil when the kext does
    /// not answer or the buffer comes back short.
    nonisolated func getTelemetry() -> CPUSensorPacket? {
        if isTerminating || Task.isCancelled { return nil }
        var output = [UInt8](repeating: 0, count: CPUSensorPacket.byteSize)
        var outputSize = CPUSensorPacket.byteSize
        let status = safeIOConnectCallMethod( AMDKextSelector.telemetryFull.id, nil, 0, nil, 0,
                                         nil, nil,
                                         &output, &outputSize)
        guard status == KERN_SUCCESS, outputSize >= CPUSensorPacket.byteSize else {
            if status != KERN_SUCCESS { logKernelError(status) }
            return nil
        }
        return CPUSensorPacket.parse(output)
    }

    nonisolated func getCStateAddress() -> UInt64 {
        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 1
        
        let res = safeIOConnectCallMethod( AMDKextSelector.cStateAddress.id, nil, 0, nil, 0,
                                      &scalerOut, &outputCount,
                                      nil, nil)
                                      
        if res != KERN_SUCCESS {
            return 0
        }
        return scalerOut
    }

    // MARK: - Snapshot Transaction (IPC Optimization)

    /// Consolidated telemetry snapshot returned by `snapshotTelemetry()`.
    /// Reduces actor hops from ~8 individual `await` calls to 1.
    struct TelemetrySnapshot {
        let metric: [Float]
        let loadIndex: [Float]
        let numPhysicalCores: Int
        let gpuTemp: Float
        let gpuPower: Float
        let gpuUtil: Float
        let gpuVram: Float
        let gpuFan: Float
        let gpuFreq: Float
        let ccdTemperatures: [Float]
    }

    /// Fetches all kext/mach telemetry in a single actor-isolated call,
    /// collapsing ~8 `await` crossings into one. Internally caches GPU stats
    /// via `updateGPUStatsCache()` (500 ms TTL).
    func snapshotTelemetry(forceMetric: Bool) async -> TelemetrySnapshot {
        let metric = getMetric(forced: forceMetric)
        let loadIdx = getLoadIndex()
        let cores = numberOfCores
        await updateGPUStatsCache()
        return TelemetrySnapshot(
            metric: metric,
            loadIndex: loadIdx,
            numPhysicalCores: cores,
            gpuTemp: cachedGPUStats.temp,
            gpuPower: cachedGPUStats.power,
            gpuUtil: cachedGPUStats.util,
            gpuVram: cachedGPUStats.vram,
            gpuFan: cachedGPUStats.fan,
            gpuFreq: cachedGPUStats.freq,
            ccdTemperatures: getCCDTemperatures()
        )
    }

    /// Lightweight refresh called by SystemMonitor when CPU/GPU power metrics
    /// are pinned to the menu bar. Updates the nonisolated PowerCache so the
    /// monitor queue can read fresh values without any actor crossing.
    /// Also refreshes kext GPU data (selectors 27-30).
    func refreshPowerCache() async {
        loadMetric()              // updates powerCache.cpu via setCPU
        await updateGPUStatsCache()  // updates powerCache.gpu via setGPU
        refreshKextGPUStats()    // updates gpuCache via kext selectors 27-30
    }
    
    // MARK: - CPU Details (sysctl)
    
    struct CPUDetails {
        let name: String
        let vendor: String
        let physicalCores: Int64
        let logicalCores: Int64
        let family: Int64
        let model: Int64
        let extModel: Int64
        let extFamily: Int64
        let stepping: Int64
        let signature: Int64
        let brand: Int64
        let features: String
        let extFeatures: String
        let microcodeVersion: Int64
    }
    
    nonisolated func getCPUDetails() -> CPUDetails {
        return CPUDetails(
            name: ProcessorModel.sysctlString(key: "machdep.cpu.brand_string"),
            vendor: ProcessorModel.sysctlString(key: "machdep.cpu.vendor"),
            physicalCores: ProcessorModel.sysctlInt64(key: "hw.physicalcpu"),
            logicalCores: ProcessorModel.sysctlInt64(key: "hw.logicalcpu"),
            family: ProcessorModel.sysctlInt64(key: "machdep.cpu.family"),
            model: ProcessorModel.sysctlInt64(key: "machdep.cpu.model"),
            extModel: ProcessorModel.sysctlInt64(key: "machdep.cpu.extmodel"),
            extFamily: ProcessorModel.sysctlInt64(key: "machdep.cpu.extfamily"),
            stepping: ProcessorModel.sysctlInt64(key: "machdep.cpu.stepping"),
            signature: ProcessorModel.sysctlInt64(key: "machdep.cpu.signature"),
            brand: ProcessorModel.sysctlInt64(key: "machdep.cpu.brand"),
            features: ProcessorModel.sysctlString(key: "machdep.cpu.features"),
            extFeatures: ProcessorModel.sysctlString(key: "machdep.cpu.extfeatures"),
            microcodeVersion: ProcessorModel.sysctlInt64(key: "machdep.cpu.microcode_version")
        )
    }

    nonisolated func getCurveOptimizerOffsets() -> [Int8] {
        var output = [Int8](repeating: 0, count: 64) // MaxCpus is typically 64
        var outputSize = output.count
        
        let res = safeIOConnectCallMethod( AMDKextSelector.curveOptimizerRead.id, nil, 0, nil, 0,
                                      nil, nil,
                                      &output, &outputSize)
        
        if res == KERN_SUCCESS {
            return Array(output.prefix(Int(outputSize)))
        } else {
            NSLog("getCurveOptimizerOffsets failed: %@", String(cString: mach_error_string(res)))
            return []
        }
    }
    
    nonisolated func getFans(includeNames: Bool = true) -> [FanSnapshot] {
        let fansRes = kernelGetUInt64(count: 1, selector: AMDKextSelector.fanCountRead.id)
        guard fansRes.count > 0 else { return [] }
        let numFans = min(Int(fansRes[0]), 16) // Cap at 16 to prevent unbounded allocation
        guard numFans > 0 else { return [] }
        
        let fanRpms = kernelGetUInt64(count: numFans, selector: AMDKextSelector.fanSpeedRead.id)
        let fanCtrls = kernelGetUInt64(count: numFans, selector: AMDKextSelector.fanCtrlRead)
        
        var fans: [FanSnapshot] = []
        for i in 0..<numFans {
            let name = includeNames
                ? kernelGetString(selector: AMDKextSelector.fanName, args: [UInt64(i)])
                : ""
            let finalName = name.isEmpty ? "Fan \(i + 1)" : name
            let customName = includeNames
                ? (UserDefaults.standard.string(forKey: "FanName_\(i)") ?? finalName)
                : finalName
            
            let rpm = (i < fanRpms.count) ? min(fanRpms[i], 9999) : 0
            
            // Selector 94 packs: (throttle << 8) | autoFlag
            // - Bits 15:8 = throttle/PWM value (0-255)
            // - Bit 0    = autoFlag (1 = Auto/SmartGuardian, 0 = Manual/Override)
            let raw = (i < fanCtrls.count) ? fanCtrls[i] : 0
            let throttle = UInt8((raw >> 8) & 0xFF)  // Extract actual throttle from bits 15:8
            let isAuto = (raw & 1) == 1               // Extract auto flag from bit 0
            
            fans.append(FanSnapshot(id: i, name: customName, rpm: rpm, throttle: throttle, isOverridden: !isAuto))
        }
        return fans
    }
    
    // MARK: - SMC Fan Control
    
    nonisolated func setFanMode(auto: Bool, fanIndex: Int = 0) -> Bool {
        if auto {
            // Selector 96 = setDefaultFanControl(fanSel)
            let res = kernelSetUInt64Status(selector: AMDKextSelector.fanModeWrite, args: [UInt64(fanIndex)])
            return res == KERN_SUCCESS
        }
        return true
    }
    
    nonisolated func setFanSpeed(pwm: Int, fanIndex: Int = 0) -> Bool {
        // Selector 95 = overrideFanControl(fanSel, pwm)
        let res = kernelSetUInt64Status(selector: AMDKextSelector.fanSpeedWrite, args: [UInt64(fanIndex), UInt64(pwm)])
        return res == KERN_SUCCESS
    }
    
    // MARK: - Kext Fan Curves (selectors 101/102)

    /// Uploads a 256-point fan curve LUT plus its parameters to the kext
    /// (selector 101, packed `FanCurveInput`, 272 bytes). `index` must be in
    /// `0..<MAX_FAN_CURVES` (4). Returns `kIOReturnNotPrivileged` when the
    /// process lacks root or the `-amdpnopchk` boot-arg.
    @discardableResult
    nonisolated func setKextFanCurve(index: UInt32,
                                     sourceSensor: UInt32,
                                     hysteresis: UInt32,
                                     rampRate: UInt32,
                                     lut: [UInt8]) -> kern_return_t {
        guard index < 4 else { return kIOReturnBadArgument }
        let input = AMDFanCurveInput(curveIndex: index,
                                     sourceSensor: sourceSensor,
                                     hysteresis: hysteresis,
                                     rampRate: rampRate,
                                     lut: lut)
        return kernelSetStruct(selector: AMDKextSelector.fanCurveLUTWrite.id, data: input.packedData())
    }

    /// Maps a physical fan header to a curve slot (selector 102).
    /// `curveIndex == -1` unmaps the fan and restores automatic control
    /// (the kext calls `setDefaultFanControl`). `fanIndex` must be a real
    /// SuperIO fan header (`0..<getNumberOfFans()`); the kext rejects others
    /// with `kIOReturnBadArgument`.
    @discardableResult
    nonisolated func mapKextFanToCurve(fanIndex: Int, curveIndex: Int) -> kern_return_t {
        // Curve index -1 (Auto) must cross as UInt64 bit pattern, not trap.
        let rawCurve = UInt64(bitPattern: Int64(curveIndex))
        return kernelSetUInt64Status(selector: AMDKextSelector.fanToCurveMap.id, args: [UInt64(fanIndex), rawCurve])
    }

    @discardableResult
    nonisolated func setCurveOptimizerOffset(core: UInt8, offset: Int8) -> kern_return_t {
        // cast offset to raw bit representation for transfer over 64-bit parameter
        let rawOffset = UInt64(bitPattern: Int64(offset))
        var input: [UInt64] = [UInt64(core), rawOffset]
        return safeIOConnectCallMethod( AMDKextSelector.curveOptimizerWrite.id, &input, 2, nil, 0, nil, nil, nil, nil)
    }
}

/// Per-component IOKit statuses of a `ProcessorModel.applyPowerPreset(_:)` call.
struct AMDPowerPresetApplyResult {
    let epp: kern_return_t
    let cpb: kern_return_t
    let ppm: kern_return_t
    let lpm: kern_return_t

    /// True when the kext rejected any write with `kIOReturnNotPrivileged`
    /// (writes need root or the `-amdpnopchk` boot-arg).
    var privilegeDenied: Bool {
        [epp, cpb, ppm, lpm].contains(ProcessorModel.kIOReturnNotPrivilegedCode)
    }

    /// Localized, human-readable reason for the first failed component.
    var firstFailureMessage: String? {
        for status in [epp, cpb, ppm, lpm] where status != KERN_SUCCESS {
            return ProcessorModel.privilegeHint(for: status)
        }
        return nil
    }
}
