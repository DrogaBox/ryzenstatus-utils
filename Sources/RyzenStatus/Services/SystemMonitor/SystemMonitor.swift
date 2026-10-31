// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Memory pressure as reported by the kernel, mapped to the traffic-light
/// indicator shown in the panel.
enum MemoryPressure {
    case normal, warning, critical, unknown

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

/// One refresh tick of the system monitor. Optionals stay nil when a reading
/// is unavailable on the current hardware, and the UI hides those rows.
struct SystemSnapshot {
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    var cpuPower: Double?
    /// SVI2 core and SoC voltages from the kext (selector 59, kext 3.36.0+);
    /// nil on Zen 4/5 (SVI3), on older kexts, or while a plane is untrusted.
    var cpuCoreVoltage: Double?
    var cpuSocVoltage: Double?
    /// Per-core power in watts from the kext (selector 60, kext 3.37.0+),
    /// one per physical core; empty on older kexts.
    var cpuCorePowers: [Double] = []
    var gpuPower: Double?
    var gpuFreq: Double?
    var gpuFan: Double?
    var batteryTemperature: Double?
    var cpuUsage: Double?          // 0...1
    var cpuSystemUsage: Double?    // 0...1, the kernel's share of cpuUsage
    var gpuUsage: Double?          // 0...1
    var memoryUsed: UInt64?
    var memoryAppUsed: UInt64?
    var memoryTotal: UInt64?
    var memoryCompressed: UInt64?
    var memoryCached: UInt64?
    var memorySwapUsed: UInt64?
    /// Bytes paged in from and out to backing store since boot.
    var memoryPageIns: UInt64?
    var memoryPageOuts: UInt64?
    var memoryPressure: MemoryPressure = .unknown

    // GPU VRAM
    var gpuMemoryUsed: UInt64?
    var gpuMemoryTotal: UInt64?

    // Network
    var netDownBytesPerSec: Double?
    var netUpBytesPerSec: Double?
    var netTotalDown: UInt64?      // since the app started watching
    var netTotalUp: UInt64?

    // Power
    var power: PowerReading?
    var peripheralBatteries: [PeripheralBatteryDevice] = []
    var peripheralBatterySample: PeripheralBatterySample {
        PeripheralBatterySample(devices: peripheralBatteries)
    }

    // Disk
    var disk: DiskReading?

    // History (oldest → newest) for the graphs
    var cpuHistory: [Double] = []          // 0...1
    var cpuSystemHistory: [Double] = []    // 0...1, aligned with cpuHistory
    var gpuHistory: [Double] = []          // 0...1
    var memoryHistory: [Double] = []       // 0...1
    var memoryAppHistory: [Double] = []    // 0...1
    var netDownHistory: [Double] = []      // bytes/sec
    var netUpHistory: [Double] = []        // bytes/sec
    var diskReadHistory: [Double] = []     // bytes/sec
    var diskWriteHistory: [Double] = []    // bytes/sec
    var systemPowerHistory: [Double] = []  // watts
    var batteryHistory: [Double] = []      // 0...1 charge level
    var cpuFreqHistory: [Double] = []      // GHz

    // Detailed AMD Telemetry
    var isKextAvailable: Bool = true
    var cores: [CoreSnapshot] = []
    var ccdTemperatures: [Float] = []
    var numPhysicalCores: Int = 0
    var peakCPUFreq: Double?
    var avgCPUFreq: Double?
    /// GPU devices reported by the kext (selectors 27-30).
    var gpuDevices: [GPUDeviceSnapshot] = []

    /// Temperature for CCD0 (°C) if reported by kext, nil otherwise
    var ccd0Temperature: Float? {
        ccdTemperatures.indices.contains(0) ? ccdTemperatures[0] : nil
    }

    /// Temperature for CCD1 (°C) if reported by kext, nil otherwise
    var ccd1Temperature: Float? {
        ccdTemperatures.indices.contains(1) ? ccdTemperatures[1] : nil
    }
}

/// What parts of the menu panel are actually visible right now. The popover can
/// be open on Keep Awake, Utilities or Controls; in those states the monitor
/// should not wake the heavier samplers just because the user clicked the icon.
struct SystemMonitorPanelNeeds: Equatable {
    var system = false
    var network = false
    var disk = false
    var power = false
    var cpu = false
    var gpu = false
    var memory = false
    var battery = false
    var peripheralBattery = false
    var cpuTemperature = false
    var gpuTemperature = false
    var batteryTemperature = false

    func merging(_ other: Self) -> Self {
        Self(system: system || other.system,
             network: network || other.network,
             disk: disk || other.disk,
             power: power || other.power,
             cpu: cpu || other.cpu,
             gpu: gpu || other.gpu,
             memory: memory || other.memory,
             battery: battery || other.battery,
             peripheralBattery: peripheralBattery || other.peripheralBattery,
             cpuTemperature: cpuTemperature || other.cpuTemperature,
             gpuTemperature: gpuTemperature || other.gpuTemperature,
             batteryTemperature: batteryTemperature || other.batteryTemperature)
    }

    static let none = SystemMonitorPanelNeeds()

    var any: Bool {
        system || network || disk || power || cpu || gpu || memory || battery ||
            peripheralBattery || cpuTemperature || gpuTemperature || batteryTemperature
    }

    /// The families the enabled monitor alerts read, with the availability
    /// rule MonitorAlertService applies. Any active alert also keeps CPU load
    /// and temperature: the thermal-throttle notice runs whenever an alert is
    /// on and reads both, so an alerts-only plan must not starve it.
    static func alerts(boolFor: (String) -> Bool,
                       isAvailable: (AppFeature) -> Bool,
                       hasInternalBattery: Bool) -> SystemMonitorPanelNeeds {
        var needs = SystemMonitorPanelNeeds()
        for pair in AppFeature.monitorAlertPairs where boolFor(pair.key) && isAvailable(pair.feature) {
            if pair.feature == .monitorPower && !hasInternalBattery { continue }
            switch pair.key {
            case DefaultsKey.monitorAlertCPU: needs.cpu = true
            case DefaultsKey.monitorAlertCPUTemperature: needs.cpuTemperature = true
            case DefaultsKey.monitorAlertMemory: needs.memory = true
            case DefaultsKey.monitorAlertDisk: needs.disk = true
            case DefaultsKey.monitorAlertBattery: needs.battery = true
            case DefaultsKey.monitorAlertGPUTemperature: needs.gpuTemperature = true
            // The GPU power reading comes with the kext power read, which
            // GPU usage switches on.
            case DefaultsKey.monitorAlertGPUPower: needs.gpu = true
            default: break
            }
        }
        if needs.any {
            needs.cpu = true
            needs.cpuTemperature = true
        }
        return needs
    }
}

/// Reads temperatures (SMC), CPU/GPU usage, memory, network and power on a
/// background queue. Runs while the panel is visible (full readings) and/or
/// while a menu bar metric is enabled (only the readings that metric needs).
/// When nothing needs it, the timer stops — zero idle cost.
final class SystemMonitor: ObservableObject, @unchecked Sendable {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.system-monitor", qos: .utility)
    private var timer: Timer?
    private var intervalSeconds: Double = 1.0
    private var panelClients = 0
    private var menuPanelNeeds: SystemMonitorPanelNeeds = .none
    private var notchVisible = false
    private var notchDetailNeeds: SystemMonitorPanelNeeds = .none
    private var notchAccessoryMonitoring = false
    private var menuBarActive = false
    private var alertsActive = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pendingRefreshSuppressesGPU = false
    private var pendingRefreshForcing: Set<MonitorSamplingKind> = []
    private var suppressGPUReadsUntil: TimeInterval = 0

    // SMC sensors
    private var smc: SMCClient?
    private var smcTried = false
    private var cpuKeys: [SMCClient.Key] = []
    /// The platform's known CPU core sensors (what the displayed value is
    /// actually computed from) and everything else, split once at discovery:
    /// each SMC read is a kernel call, so the per-tick read sticks to the
    /// core set and only sweeps the rest when the core set goes silent.
    private var preferredCPUKeys: [SMCClient.Key] = []
    private var fallbackCPUKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false
    private var cpuTemperaturePlatform: CPUTemperaturePlatform = .generic

    // Samplers
    private let networkSampler = NetworkSampler()
    private let diskSampler = DiskSampler()
    private let peripheralBatterySampler = PeripheralBatterySampler()
    private var powerSampler: PowerSampler?

    // Running state
    private var previousCPUTicks: CPUTickSample?
    private var previousCPUTicksAt: TimeInterval?
    private var previousCoreTicks: [CPUTickSample] = []
    private var previousCoreTicksAt: TimeInterval?
    /// Main-thread flag: at most one kext refresh task runs at a time, so a
    /// slow kext cannot pile tasks up that land out of order.
    private var amdRefreshInFlight = false
    /// Queue-owned: when the empty-cache temperature seed last read the SMC.
    /// On a machine where no key answers, the cache stays nil and the seed
    /// would otherwise sweep the SMC on every tick.
    private var lastCPUTemperatureSeed: TimeInterval = -.infinity
    private var lastGPUTemperatureSeed: TimeInterval = -.infinity
    /// Wake observer token — see invalidateTickBaseline().
    private var wakeObserver: Any?
    private var tickCount = 0
    /// Timer cadence in base ticks (GCD of the needed strides); 1 = every tick.
    private var scheduledWakeTicks = 1
    /// The plan the cadence was last derived from. Activation setters early
    /// return while their flag is unchanged, but a metric or alert toggle can
    /// still change the plan underneath a slow cadence — the comparison is
    /// what triggers the immediate resample instead of a wait of up to 60 s.
    private var lastSyncedPlan: SamplingPlan?
    private var lastCPUUsage: Double?
    private var lastCPUSystemUsage: Double?
    private var lastMemoryReading: (used: UInt64, appUsed: UInt64, total: UInt64, pressure: MemoryPressure)?
    private var cores: [CoreSnapshot] = []
    private var ccdTemperatures: [Double] = []
    private var cpuVoltages: (core: Double?, soc: Double?) = (nil, nil)
    private var cpuCorePowers: [Double] = []
    private var lastAmdSnapshot: ProcessorModel.TelemetrySnapshot?
    private var isKextAvailable: Bool = true
    private var missedCPUUsageSamples = 0
    private var lastGPUUsage: Double?
    private var missedGPUUsageSamples = 0
    private var lastGPUVRAMUsed: UInt64?
    private var lastGPUVRAMTotal: UInt64?
    private var memoryCache: CachedMemoryReading?
    private var cpuTemperatureCache: CachedSensorReading?
    private var gpuTemperatureCache: CachedSensorReading?
    private var batteryTemperatureCache: CachedSensorReading?
    private var lastDiskReading: DiskReading?
    private var lastNetworkReading: NetworkReading?
    private var lastPowerReading: PowerReading?
    private var lastPeripheralBatteries: [PeripheralBatteryDevice] = []
    private var lastPublishedPlan: SamplingPlan?
    private var lastPublishedForeground: Bool?

    // History
    private let historyCapacity = 120
    private var cpuHistory: MetricHistory
    private var cpuSystemHistory: MetricHistory
    private var gpuHistory: MetricHistory
    private var memoryHistory: MetricHistory
    private var memoryAppHistory: MetricHistory
    private var netDownHistory: MetricHistory
    private var netUpHistory: MetricHistory
    private var diskReadHistory: MetricHistory
    private var diskWriteHistory: MetricHistory
    private var systemPowerHistory: MetricHistory
    private var batteryHistory: MetricHistory
    private var cpuFreqHistory: MetricHistory
    private var lastPeakCPUFreq: Double = 0
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        cpuHistory = MetricHistory(capacity: historyCapacity)
        cpuSystemHistory = MetricHistory(capacity: historyCapacity)
        gpuHistory = MetricHistory(capacity: historyCapacity)
        memoryHistory = MetricHistory(capacity: historyCapacity)
        memoryAppHistory = MetricHistory(capacity: historyCapacity)
        netDownHistory = MetricHistory(capacity: historyCapacity)
        netUpHistory = MetricHistory(capacity: historyCapacity)
        diskReadHistory = MetricHistory(capacity: historyCapacity)
        diskWriteHistory = MetricHistory(capacity: historyCapacity)
        systemPowerHistory = MetricHistory(capacity: historyCapacity)
        batteryHistory = MetricHistory(capacity: historyCapacity)
        cpuFreqHistory = MetricHistory(capacity: historyCapacity)
        // A desktop has no battery to watch: the power-source notification
        // would only wake the monitor for nothing.
        if PowerSampler.hasInternalBattery {
            installPowerSourceObserver()
        }
        // CPU utilisation is a delta between consecutive tick samples.
        // Across a suspend those bases are stale, so the first post-wake sample
        // is computed over the entire sleep interval and is meaningless.
        // Dropping the bases makes that sample return nil instead, and the next
        // tick re-seeds cleanly.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateTickBaseline()
        }
    }

    /// Drops the CPU/core tick baselines so the first post-wake sample
    /// is skipped rather than computed across the sleep discontinuity.
    /// The baselines are queue state, so the wake observer (main) hops there.
    private func invalidateTickBaseline() {
        queue.async { [weak self] in
            guard let self else { return }
            self.previousCPUTicks = nil
            self.previousCPUTicksAt = nil
            self.previousCoreTicks = []
            self.previousCoreTicksAt = nil
        }
    }

    /// Longest pause over which two tick samples still give a current load.
    /// Shared by the total and the per-core readings so both treat a gap the
    /// same way: past it, the old ticks only serve as a baseline.
    static let maximumTickGap: TimeInterval = 12.5

    /// Per-core busy/system shares, or nil when there is no usable baseline:
    /// none yet, a different CPU count, or a gap over `maximumTickGap`. A
    /// single core whose counters went backwards gets a nil entry.
    static func coreLoads(current: [CPUTickSample], previous: [CPUTickSample],
                          elapsed: TimeInterval?) -> [(busy: Double, system: Double)?]? {
        guard let elapsed, elapsed <= maximumTickGap,
              !current.isEmpty, previous.count == current.count else { return nil }
        return zip(current, previous).map { $0.load(since: $1) }
    }

    /// Physical cores the kernel reports: the topology before the first kext
    /// snapshot arrives and on machines without the kext.
    static let hostPhysicalCoreCount = max(1, Int(ProcessorModel.sysctlInt64(key: "hw.physicalcpu")))

    /// Maps each logical CPU to its physical core. With SMT the kernel
    /// numbers the two threads of a core next to each other; without it every
    /// logical CPU is a core.
    static func coreTopology(logicalCount: Int, physicalCount: Int) -> [(physicalIndex: Int, isLogical: Bool)] {
        guard logicalCount > 0 else { return [] }
        let physical = max(1, physicalCount)
        let hasSMT = logicalCount == 2 * physical
        return (0..<logicalCount).map { logicalIdx in
            (physicalIndex: hasSMT ? logicalIdx / 2 : logicalIdx % physical,
             isLogical: hasSMT ? logicalIdx % 2 != 0 : logicalIdx >= physical)
        }
    }

    /// The anti-glitch bridge for temperatures spans a couple of temperature
    /// sampling gaps, never less than 12 s, so one bad SMC read on the slow
    /// background stride does not blank the reading.
    static func temperatureBridge(stride: Int, intervalSeconds: Double) -> TimeInterval {
        max(12, TimeInterval(stride) * intervalSeconds * 2.2)
    }

    deinit {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        // Release the wake observer.
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Lifecycle

    /// The same system notification used by the reference battery monitor.
    /// It removes the normal background sampling delay after unplugging,
    /// charging changes or a newly calculated time-to-empty value.
    private func installPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                guard monitor.shouldRun,
                      monitor.currentPlan(defaults: .standard).needPower else { return }
                monitor.refresh(forcing: [.power, .powerDraw])
            }
        }, context)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
    }

    /// A full monitor surface became visible (Settings preview or onboarding).
    func panelDidAppear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients += 1
            ensureTimer()
            refresh(suppressImmediateGPU: true)
            scheduleDeferredGPURefreshIfNeeded()
        }
    }

    /// A full monitor surface closed: keep going only if the menu panel or menu
    /// bar metrics still need readings.
    func panelDidDisappear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients = max(0, panelClients - 1)
            stopTimerIfIdle()
        }
    }

    /// Independent from the menu panel, so either surface can close without
    /// taking the other surface’s readings away.
    func setNotchDetailNeeds(_ needs: SystemMonitorPanelNeeds) {
        runOnMain { [weak self] in
            guard let self, self.notchDetailNeeds != needs else { return }
            self.notchDetailNeeds = needs
            self.stopTimerIfIdle()
            self.ensureTimer()
            if needs.any { self.refresh(suppressImmediateGPU: true); self.scheduleDeferredGPURefreshIfNeeded() }
        }
    }

    /// This background consumer only requests accessory batteries. It does
    /// not make CPU, graphics, temperature or disk sampling foreground work.
    func setNotchAccessoryMonitoring(_ enabled: Bool) {
        runOnMain { [weak self] in
            guard let self, self.notchAccessoryMonitoring != enabled else { return }
            self.notchAccessoryMonitoring = enabled
            self.stopTimerIfIdle()
            self.ensureTimer()
            if enabled { self.refresh(suppressImmediateGPU: true) }
        }
    }

    func setNotchVisible(_ visible: Bool) {
        runOnMain { [weak self] in
            guard let self, self.notchVisible != visible else { return }
            self.notchVisible = visible
            if visible {
                self.ensureTimer()
                self.refresh(suppressImmediateGPU: true)
                self.scheduleDeferredGPURefreshIfNeeded()
            } else {
                self.stopTimerIfIdle()
                self.ensureTimer()
            }
        }
    }

    /// The menu popover reports exactly which monitor sections are on screen.
    /// This avoids paying for GPU, network or power reads while the panel is open
    /// on another section.
    func setMenuPanelNeeds(_ needs: SystemMonitorPanelNeeds) {
        runOnMain { [weak self] in
            guard let self else { return }
            if needs == menuPanelNeeds {
                if shouldRun {
                    ensureTimer()
                } else {
                    stopTimerIfIdle()
                }
                return
            }
            let defaults = UserDefaults.standard
            let previousNeeds = menuPanelNeeds
            let neededGPUBefore = currentPlan(defaults: defaults).needGPUUsage
            menuPanelNeeds = needs
            let needsGPUAfter = currentPlan(defaults: defaults).needGPUUsage
            if shouldRun {
                ensureTimer()
                let panelGPUBecameVisible = needs.system
                    && !previousNeeds.system
                    && defaults.bool(forKey: DefaultsKey.monitorSysGPU)
                let suppressImmediateGPU = needsGPUAfter && (!neededGPUBefore || panelGPUBecameVisible)
                refresh(suppressImmediateGPU: suppressImmediateGPU)
                if suppressImmediateGPU {
                    scheduleDeferredGPURefreshIfNeeded()
                }
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// The menu popover animation can briefly raise compositor GPU usage. When
    /// GPU is pinned to the menu bar, keep the previous value through that short
    /// window instead of sampling the animation itself.
    func suppressGPUReadsForTransientUI(duration: TimeInterval = 0.9) {
        runOnMain { [weak self] in
            guard let self else { return }
            let until = ProcessInfo.processInfo.systemUptime + max(0.1, duration)
            suppressGPUReadsUntil = max(suppressGPUReadsUntil, until)
            if shouldSample(), currentPlan(defaults: .standard).needGPUUsage {
                scheduleDeferredGPURefreshIfNeeded()
            }
        }
    }

    /// Toggles continuous light sampling for the menu bar metrics.
    func setMenuBarActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard active != menuBarActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            menuBarActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// Optional alert rules can keep only the necessary samplers alive even when
    /// no monitor UI is visible and no metric is pinned to the menu bar.
    func setAlertsActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard active != alertsActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            alertsActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// A settings change can swap which metrics are needed without flipping
    /// any activation flag. On a slow wake cadence the newly pinned metric
    /// would sit on its placeholder until the next wake (up to 60 s), so a
    /// changed plan resamples right away.
    private func resyncIfPlanChanged() {
        guard shouldSample() else { return }
        let plan = currentPlan(defaults: .standard)
        guard plan != lastSyncedPlan else { return }
        if let oldPlan = lastSyncedPlan {
            queue.async { [weak self] in
                guard let self else { return }
                if !oldPlan.needCPU && plan.needCPU {
                    self.cpuHistory = MetricHistory(capacity: self.historyCapacity)
                    self.cpuSystemHistory = MetricHistory(capacity: self.historyCapacity)
                }
                if !oldPlan.needGPUUsage && plan.needGPUUsage { self.gpuHistory = MetricHistory(capacity: self.historyCapacity) }
                if !oldPlan.needMemory && plan.needMemory {
                    self.memoryHistory = MetricHistory(capacity: self.historyCapacity)
                    self.memoryAppHistory = MetricHistory(capacity: self.historyCapacity)
                }
                if !oldPlan.needNetwork && plan.needNetwork {
                    self.netDownHistory = MetricHistory(capacity: self.historyCapacity)
                    self.netUpHistory = MetricHistory(capacity: self.historyCapacity)
                }
                if !oldPlan.needDisk && plan.needDisk {
                    self.diskReadHistory = MetricHistory(capacity: self.historyCapacity)
                    self.diskWriteHistory = MetricHistory(capacity: self.historyCapacity)
                }
                if !oldPlan.needPower && plan.needPower {
                    self.systemPowerHistory = MetricHistory(capacity: self.historyCapacity)
                    self.batteryHistory = MetricHistory(capacity: self.historyCapacity)
                }
            }
        }
        syncTimerCadence(plan: plan)
        refresh()
    }

    /// The hub switching a metric on or off changes the plan without touching
    /// any activation flag; resample right away like any settings change.
    func planDidChange() {
        runOnMain { [weak self] in self?.resyncIfPlanChanged() }
    }

    /// Changes the sampling cadence (seconds). Restarts a running timer.
    func setInterval(seconds: Double) {
        runOnMain { [weak self] in
            guard let self else { return }
            let clamped = max(0.1, seconds)
            guard clamped != intervalSeconds else { return }
            intervalSeconds = clamped
            // Strides are derived from the interval, so the wake cadence must
            // resync before the timer is rebuilt on the new base interval.
            syncTimerCadence(plan: currentPlan(defaults: .standard))
            if timer != nil { restartTimer() }
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }

    private func scheduleDeferredGPURefreshIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self,
                  self.shouldRun,
                  self.currentPlan(defaults: .standard).needGPUUsage else { return }
            self.refresh()
        }
    }

    /// True while at least one full monitor surface (Settings or onboarding) is
    /// on screen. A depth count, not a bool, so overlapping appear/disappear from
    /// independent surfaces cannot desync.
    private var fullMonitorVisible: Bool { panelClients > 0 }

    private var shouldRun: Bool { fullMonitorVisible || menuPanelNeeds.any || notchDetailNeeds.any || notchVisible || notchAccessoryMonitoring || menuBarActive || alertsActive }

    private func shouldSample(defaults: UserDefaults = .standard) -> Bool {
        shouldRun && currentPlan(defaults: defaults).any
    }

    private struct SamplingPlan: Equatable {
        var needCPU = false
        var needMemory = false
        var needNetwork = false
        var needDisk = false
        var needPower = false
        var needPeripheralBattery = false
        var needGPUUsage = false
        var needCPUTemperature = false
        var needGPUTemperature = false
        var needBatteryTemperature = false
        var needAMDPower = false  // CPU/GPU power from AMD PM kext
        /// The system draw pinned to the menu bar keeps the chosen interval;
        /// battery charge and time alone stay on the slow power stride.
        var needPowerDraw = false

        var powerKind: MonitorSamplingKind { needPowerDraw ? .powerDraw : .power }

        var needSMC: Bool { needPower || needTemperature }

        var needTemperature: Bool {
            needCPUTemperature || needGPUTemperature || needBatteryTemperature
        }

        var any: Bool {
            needCPU || needMemory || needNetwork || needDisk || needPower ||
                needPeripheralBattery || needGPUUsage || needTemperature || needAMDPower
        }
    }



    private struct CachedMemoryReading {
        var used: UInt64
        var appUsed: UInt64
        var total: UInt64
        var compressed: UInt64
        var cached: UInt64
        var swapUsed: UInt64?
        var pageIns: UInt64
        var pageOuts: UInt64
        var pressure: MemoryPressure
        var updatedAt: TimeInterval
        var missedSamples: Int
    }


    private func currentPlan(defaults: UserDefaults) -> SamplingPlan {
        var plan = SamplingPlan()
        var effectiveNeeds = menuPanelNeeds.merging(notchDetailNeeds)
        if fullMonitorVisible || effectiveNeeds.system {
            enableAll(&plan)
        } else {
            // Alerts sample only the families they watch, not every sampler.
            if alertsActive {
                effectiveNeeds = effectiveNeeds.merging(.alerts(
                    boolFor: { defaults.bool(forKey: $0) },
                    isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                    hasInternalBattery: PowerSampler.hasInternalBattery))
            }
            apply(effectiveNeeds, to: &plan)
            if notchVisible {
                plan.needCPU = true
                plan.needMemory = true
                plan.needNetwork = true
                plan.needGPUUsage = true
                plan.needPower = true
            }
            if notchAccessoryMonitoring {
                plan.needPeripheralBattery = true
            }
            if menuBarActive {
                for metric in MenuBarMetric.enabled(in: defaults) {
                    apply(metric, to: &plan)
                }
            }
        }

        // The hub gates whole metric families: an unavailable metric never
        // samples, no matter what is pinned, shown or alerting.
        func available(_ feature: AppFeature) -> Bool {
            defaults.bool(forKey: feature.availabilityKey)
        }
        if !available(.monitorCPU) {
            plan.needCPU = false
            plan.needCPUTemperature = false
        }
        if !available(.monitorGPU) {
            plan.needGPUUsage = false
            plan.needGPUTemperature = false
        }
        if !available(.monitorMemory) { plan.needMemory = false }
        if !available(.monitorNetwork) { plan.needNetwork = false }
        if !available(.monitorDisk) { plan.needDisk = false }
        if !available(.monitorPower) {
            plan.needPower = false
            plan.needPeripheralBattery = false
            plan.needBatteryTemperature = false
        }
        plan.needAMDPower = plan.needCPU || plan.needGPUUsage ||
            plan.needCPUTemperature || plan.needGPUTemperature
        return plan
    }

    private func enableAll(_ plan: inout SamplingPlan) {
        plan.needCPU = true
        plan.needMemory = true
        plan.needNetwork = true
        plan.needDisk = true
        plan.needPower = true
        plan.needPeripheralBattery = true
        plan.needGPUUsage = true
        plan.needCPUTemperature = true
        plan.needGPUTemperature = true
        plan.needBatteryTemperature = true
    }

    private func apply(_ needs: SystemMonitorPanelNeeds, to plan: inout SamplingPlan) {
        if needs.system {
            enableAll(&plan)
            return
        }
        plan.needCPU = plan.needCPU || needs.cpu
        plan.needMemory = plan.needMemory || needs.memory
        plan.needNetwork = plan.needNetwork || needs.network
        plan.needDisk = plan.needDisk || needs.disk
        plan.needPower = plan.needPower || needs.power || needs.battery
        plan.needPeripheralBattery = plan.needPeripheralBattery || needs.peripheralBattery
        plan.needGPUUsage = plan.needGPUUsage || needs.gpu
        plan.needCPUTemperature = plan.needCPUTemperature || needs.cpuTemperature
        plan.needGPUTemperature = plan.needGPUTemperature || needs.gpuTemperature
        plan.needBatteryTemperature = plan.needBatteryTemperature || needs.batteryTemperature
    }

    private func apply(_ metric: MenuBarMetric, to plan: inout SamplingPlan) {
        let combineTemps = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarCombineTemperatures)
        switch metric {
        case .cpu:
            plan.needCPU = true
            if combineTemps { plan.needCPUTemperature = true }
        case .cpuPower, .cpuFrequency:
            plan.needCPU = true
        case .cpuTempPower, .cpuTemperature:
            plan.needCPU = true
            plan.needCPUTemperature = true
        case .gpu:
            plan.needGPUUsage = true
            if combineTemps { plan.needGPUTemperature = true }
        case .gpuTemperature:
            plan.needGPUTemperature = true
        case .gpuPower:
            plan.needGPUUsage = true
        case .gpuTempPower:
            plan.needGPUUsage = true
            plan.needGPUTemperature = true
        case .memory:
            plan.needMemory = true
        case .network:
            plan.needNetwork = true
        case .diskUsage, .diskActivity:
            plan.needDisk = true
        case .battery, .batteryTime, .batteryTemperature, .power:
            plan.needPower = true
            plan.needPowerDraw = plan.needPowerDraw || metric == .power
            plan.needBatteryTemperature = plan.needBatteryTemperature || metric == .batteryTemperature
        case .peripheralBattery:
            plan.needPower = true
            plan.needPeripheralBattery = true
        case .connectedDevices:
            // ConnectedDevicesMonitor owns this list; nothing to sample here.
            break
        }
    }

    private func ensureTimer() {
        guard shouldSample() else { return }
        syncTimerCadence(plan: currentPlan(defaults: .standard))
        guard timer == nil else { return }
        startTimer()
    }

    private func stopTimerIfIdle() {
        guard !shouldSample() else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Keeps the timer waking only when the next needed sample can be due.
    /// The cadence is the GCD of the needed strides, so every sample still
    /// lands exactly on its original schedule; the tick counter is realigned
    /// onto the new grid or `tick % stride` could become unreachable.
    private func syncTimerCadence(plan: SamplingPlan) {
        lastSyncedPlan = plan
        let foreground = fullMonitorVisible || menuPanelNeeds.any
        let desired = MonitorSamplingPolicy.wakeTicks(for: Self.neededKinds(of: plan),
                                                      intervalSeconds: intervalSeconds,
                                                      foreground: foreground)
        guard desired != scheduledWakeTicks else { return }
        scheduledWakeTicks = desired
        tickCount = MonitorSamplingPolicy.alignedTick(tickCount, wakeTicks: desired)
        if timer != nil {
            restartTimer()
        }
    }

    private static func neededKinds(of plan: SamplingPlan) -> [MonitorSamplingKind] {
        var kinds: [MonitorSamplingKind] = []
        if plan.needCPU { kinds.append(.cpu) }
        if plan.needMemory { kinds.append(.memory) }
        if plan.needNetwork { kinds.append(.network) }
        if plan.needDisk { kinds.append(.disk) }
        if plan.needPower { kinds.append(plan.powerKind) }
        if plan.needPeripheralBattery { kinds.append(.peripheralBattery) }
        if plan.needGPUUsage { kinds.append(.gpuUsage) }
        if plan.needTemperature { kinds.append(.temperature) }
        return kinds
    }

    private func startTimer() {
        let cadenceSeconds = intervalSeconds * TimeInterval(scheduledWakeTicks)
        let t = Timer(timeInterval: cadenceSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = cadenceSeconds * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        startTimer()
    }

    // MARK: - Refresh

    private func refresh(suppressImmediateGPU: Bool = false, forcing: Set<MonitorSamplingKind> = []) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh(suppressImmediateGPU: suppressImmediateGPU, forcing: forcing) }
            return
        }
        let defaults = UserDefaults.standard
        let plan = currentPlan(defaults: defaults)
        guard plan.any else {
            stopTimerIfIdle()
            return
        }
        if refreshInFlight {
            pendingRefresh = true
            pendingRefreshSuppressesGPU = pendingRefreshSuppressesGPU || suppressImmediateGPU
            pendingRefreshForcing.formUnion(forcing)
            return
        }
        syncTimerCadence(plan: plan)
        refreshInFlight = true
        let suppressGPUReadsUntil = self.suppressGPUReadsUntil
        let foregroundSampling = fullMonitorVisible || menuPanelNeeds.any
        let intervalSeconds = self.intervalSeconds
        // Ticks advance by the timer's cadence so `tick % stride` keeps
        // measuring base intervals; mutated on main only, read by the queue
        // through the captured value.
        let tick = tickCount
        tickCount &+= scheduledWakeTicks
        // If AMD power metrics are needed, trigger a fresh kext read on the actor
        // so the nonisolated PowerCache is populated before the queue reads it.
        // The read is kext IPC, so it follows the CPU and temperature strides
        // instead of every tick, and a slow kext never has two reads queued.
        let amdRefreshDue = [MonitorSamplingKind.cpu, .temperature].contains {
            MonitorSamplingPolicy.shouldSample($0, tick: tick, intervalSeconds: intervalSeconds,
                                               foreground: foregroundSampling, forced: forcing)
        }
        if (plan.needAMDPower || plan.needCPU || plan.needCPUTemperature), amdRefreshDue, !amdRefreshInFlight {
            amdRefreshInFlight = true
            // BUG-07 fix: the queue.async that reads lastAmdSnapshot / isKextAvailable
            // was dispatched at the same time as the Task, so the queue would race with
            // the Task and read stale values from the previous tick.
            // Fix: the Task now explicitly triggers the queue dispatch itself, guaranteeing
            // the snapshot properties are written before the queue reads them.
            Task { [weak self] in
                await ProcessorModel.shared.refreshPowerCache()
                let snap = await ProcessorModel.shared.snapshotTelemetry(forceMetric: false)
                let avail = await ProcessorModel.shared.isKextAvailable
                self?.queue.async {
                    self?.lastAmdSnapshot = snap
                    self?.isKextAvailable = avail
                }
                DispatchQueue.main.async { self?.amdRefreshInFlight = false }
            }
            // NOTE: The main queue.async below still fires concurrently with the AMD Task.
            // It uses the *previous tick's* AMD values which is acceptable — AMD reads are
            // expensive and intentionally staggered by one tick. The critical fix above
            // ensures lastAmdSnapshot is coherently written by the Task before the *next*
            // queue.async reads it, preventing torn reads across rapid successive ticks.
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareIfNeeded(needSMC: plan.needSMC,
                                 needTemperature: plan.needTemperature)
            let now = ProcessInfo.processInfo.systemUptime

            var next = SystemSnapshot()
            next.isKextAvailable = self.isKextAvailable

            // Publishing a snapshot redraws the menu bar (attributed-string
            // rebuild + width measurement); on ticks where every needed metric
            // was stride-skipped the values are pure carry-over, so the publish
            // is skipped below to save that work.
            var sampledAnything = false
            func take(_ kind: MonitorSamplingKind) -> Bool {
                let sample = MonitorSamplingPolicy.shouldSample(kind,
                                                                tick: tick,
                                                                intervalSeconds: intervalSeconds,
                                                                foreground: foregroundSampling,
                                                                forced: forcing)
                if sample { sampledAnything = true }
                return sample
            }

            if plan.needCPU {
                if take(.cpu) {
                    // Fetch per-core metrics only when CPU is actually being sampled (F3.2)
                    let (cores, ccdTemps) = self.readCoreUsageAndTelemetry(now: now)
                    self.cores = cores
                    self.ccdTemperatures = ccdTemps.map { Double($0) }
                    let volts = ProcessorModel.shared.getSviVoltages()
                    self.cpuVoltages = (volts?.coreVolts, volts?.socVolts)
                    self.cpuCorePowers = ProcessorModel.shared.getCorePowers() ?? []

                    // No baseline (launch, wake, a long gap) is a missed sample,
                    // never a 0 % or a gap-long average in the history.
                    if let load = self.readCPUUsage(now: now) {
                        let cpu = load.busy
                        self.lastCPUUsage = cpu
                        self.lastCPUSystemUsage = load.system
                        self.missedCPUUsageSamples = 0
                        self.cpuHistory.push(cpu)
                        LongHistoryStore.shared.record(.cpu, cpu)
                        self.cpuSystemHistory.push(load.system)
                    } else if self.missedCPUUsageSamples < 3 {
                        self.missedCPUUsageSamples += 1
                    } else {
                        self.lastCPUUsage = nil
                        self.lastCPUSystemUsage = nil
                    }
                }
                next.cpuUsage = self.lastCPUUsage
                next.cpuSystemUsage = self.lastCPUSystemUsage
                next.cores = self.cores
                next.ccdTemperatures = self.ccdTemperatures.map { Float($0) }
                next.cpuCoreVoltage = self.cpuVoltages.core
                next.cpuSocVoltage = self.cpuVoltages.soc
                next.cpuCorePowers = self.cpuCorePowers
            }

            if plan.needMemory {
                if take(.memory) {
                    if let (memory, isFresh) = self.stabilizedMemoryReading(now: now) {
                        next.memoryUsed = memory.used
                        next.memoryAppUsed = memory.appUsed
                        next.memoryTotal = memory.total
                        next.memoryCompressed = memory.compressed
                        next.memoryCached = memory.cached
                        next.memorySwapUsed = memory.swapUsed
                        next.memoryPageIns = memory.pageIns
                        next.memoryPageOuts = memory.pageOuts
                        next.memoryPressure = memory.pressure
                        if isFresh, memory.total > 0 {
                            let fraction = Double(memory.used) / Double(memory.total)
                            let appFraction = Double(memory.appUsed) / Double(memory.total)
                            self.memoryHistory.push(fraction)
                            LongHistoryStore.shared.record(.memory, fraction)
                            self.memoryAppHistory.push(appFraction)
                        }
                    }
                } else if let cached = self.memoryCache {
                    next.memoryUsed = cached.used
                    next.memoryAppUsed = cached.appUsed
                    next.memoryTotal = cached.total
                    next.memoryCompressed = cached.compressed
                    next.memoryCached = cached.cached
                    next.memorySwapUsed = cached.swapUsed
                    next.memoryPageIns = cached.pageIns
                    next.memoryPageOuts = cached.pageOuts
                    next.memoryPressure = cached.pressure
                }
            }


            if plan.needMemory || plan.needGPUUsage {
                if take(.memory) {
                    // The kext fallback is read here, on the queue that writes it.
                    let kextVramMB = self.lastAmdSnapshot?.gpuVram
                    Task { [weak self] in
                        guard let self else { return }
                        let vramUsed = await self.readGPUVRAM(kextVramMB: kextVramMB)
                        let totalVram = await self.readGPUVRAMTotal()
                        self.queue.async {
                            if let vramUsed {
                                self.lastGPUVRAMUsed = vramUsed
                            }
                            // Nil clears a total the accelerator stopped reporting.
                            self.lastGPUVRAMTotal = totalVram
                        }
                    }
                }
                next.gpuMemoryUsed = self.lastGPUVRAMUsed
                next.gpuMemoryTotal = self.lastGPUVRAMTotal
            }

            if plan.needNetwork {
                if take(.network) {
                    let network = self.networkSampler.sample(now: now)
                    self.lastNetworkReading = network
                    next.netDownBytesPerSec = network.downBytesPerSec
                    next.netUpBytesPerSec = network.upBytesPerSec
                    next.netTotalDown = network.totalDown
                    next.netTotalUp = network.totalUp
                    if let down = network.downBytesPerSec {
                        self.netDownHistory.push(down)
                        LongHistoryStore.shared.record(.networkDown, down)
                    }
                    if let up = network.upBytesPerSec {
                        self.netUpHistory.push(up)
                        LongHistoryStore.shared.record(.networkUp, up)
                    }
                } else if let network = self.lastNetworkReading {
                    next.netDownBytesPerSec = network.downBytesPerSec
                    next.netUpBytesPerSec = network.upBytesPerSec
                    next.netTotalDown = network.totalDown
                    next.netTotalUp = network.totalUp
                }
            }

            if plan.needDisk {
                if take(.disk) {
                    let disk = self.diskSampler.sample(now: now, refreshMetadata: foregroundSampling)
                    self.lastDiskReading = disk
                    next.disk = disk
                    let ioDevices = disk.uniqueIODevices
                    let readValues = ioDevices.compactMap(\.readBytesPerSec)
                    let writeValues = ioDevices.compactMap(\.writeBytesPerSec)
                    if !readValues.isEmpty {
                        self.diskReadHistory.push(readValues.reduce(0, +))
                        LongHistoryStore.shared.record(.diskRead, readValues.reduce(0, +))
                    }
                    if !writeValues.isEmpty {
                        self.diskWriteHistory.push(writeValues.reduce(0, +))
                        LongHistoryStore.shared.record(.diskWrite, writeValues.reduce(0, +))
                    }
                } else {
                    next.disk = self.lastDiskReading
                }
            }

            if plan.needPower, let powerSampler = self.powerSampler {
                if take(plan.powerKind) {
                    let power = powerSampler.sample()
                    self.lastPowerReading = power
                    next.power = power
                    if let watts = power.systemWatts {
                        self.systemPowerHistory.push(watts)
                        LongHistoryStore.shared.record(.systemPower, watts)
                    }
                    if let charge = power.chargePercent { self.batteryHistory.push(Double(charge) / 100.0) }
                } else {
                    next.power = self.lastPowerReading
                }
            }

            if plan.needPeripheralBattery {
                if take(.peripheralBattery) {
                    self.lastPeripheralBatteries = self.peripheralBatterySampler.sample(now: now)
                }
                next.peripheralBatteries = self.lastPeripheralBatteries
            }

            // GPU usage is the priciest normal monitor read. When the panel first
            // opens, skip the immediate read so the popover animation does not
            // become a visible one-sample GPU spike. A deferred refresh follows.
            if plan.needGPUUsage {
                let suppressGPUForUI = suppressImmediateGPU || now < suppressGPUReadsUntil
                let shouldSampleGPU = !suppressGPUForUI && take(.gpuUsage)
                if shouldSampleGPU {
                    let kextUtil = self.lastAmdSnapshot?.gpuUtil
                    Task { [weak self] in
                        guard let self else { return }
                        let rawGPU = await self.readGPUUsage(kextUtil: kextUtil)
                        self.queue.async {
                            if let rawGPU {
                                self.lastGPUUsage = MetricFormat.stabilizedGPUUsage(previous: self.lastGPUUsage,
                                                                                    current: rawGPU)
                                self.missedGPUUsageSamples = 0
                                if let gpu = self.lastGPUUsage {
                                    self.gpuHistory.push(gpu)
                                    LongHistoryStore.shared.record(.gpu, gpu)
                                }
                            } else if self.missedGPUUsageSamples < 3 {
                                self.missedGPUUsageSamples += 1
                            } else {
                                self.lastGPUUsage = nil
                            }
                        }
                    }
                }
                next.gpuUsage = self.lastGPUUsage
            }
            // The anti-glitch bridge spans a couple of temperature sampling
            // gaps, never less than 12 s.
            let temperatureBridge = Self.temperatureBridge(
                stride: MonitorSamplingPolicy.sampleStride(for: .temperature,
                                                           intervalSeconds: intervalSeconds,
                                                           foreground: foregroundSampling),
                intervalSeconds: intervalSeconds)
            let temperatureDue = plan.needTemperature && take(.temperature)
            // A temperature reaches the long history only on a tick where a
            // sensor was actually read, never as a bridged or carried value.
            var cpuTemperatureRead = false
            var gpuTemperatureRead = false
            if plan.needCPUTemperature {
                // An empty cache seeds between strides, at most every 5 s so
                // a machine where no key answers is not swept every tick.
                if temperatureDue || (self.cpuTemperatureCache == nil && now - self.lastCPUTemperatureSeed >= 5) {
                    self.lastCPUTemperatureSeed = now
                    var temp = self.cpuTemperature()
                    if temp == nil || temp == 0 {
                        let amdTemp = ProcessorModel.shared.lastCPUTemperature
                        if amdTemp > 0 && amdTemp <= 125.0 {
                            temp = amdTemp
                        }
                    }
                    next.cpuTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        temp,
                        cache: &self.cpuTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge,
                        minimum: TemperatureSensorSelector.minimumChipTemperature)
                    cpuTemperatureRead = self.cpuTemperatureCache?.updatedAt == now
                    if next.cpuTemperature != nil {
                        sampledAnything = true
                    }
                } else {
                    next.cpuTemperature = self.cpuTemperatureCache?.value
                }
            }
            if plan.needGPUTemperature {
                if temperatureDue || (self.gpuTemperatureCache == nil && now - self.lastGPUTemperatureSeed >= 5) {
                    self.lastGPUTemperatureSeed = now
                    next.gpuTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        self.maxTemperature(of: self.gpuKeys),
                        cache: &self.gpuTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge,
                        minimum: TemperatureSensorSelector.minimumChipTemperature)
                    gpuTemperatureRead = self.gpuTemperatureCache?.updatedAt == now
                    if next.gpuTemperature != nil {
                        sampledAnything = true
                    }
                } else {
                    next.gpuTemperature = self.gpuTemperatureCache?.value
                }
            }
            if plan.needBatteryTemperature {
                if temperatureDue {
                    next.batteryTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        self.maxTemperature(of: self.batteryKeys),
                        cache: &self.batteryTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge)
                    if next.batteryTemperature != nil {
                        sampledAnything = true
                    }
                } else {
                    next.batteryTemperature = self.batteryTemperatureCache?.value
                }
            }
            // AMD kext power — read from the nonisolated PowerCache (zero async
            // overhead). These are cached kext values, not a sample taken on
            // this tick, so they never make a carry-over tick publish.
            if plan.needAMDPower {
                let cpuW = ProcessorModel.shared.lastCPUPowerWatts
                let gpuW = ProcessorModel.shared.lastGPUPowerWatts
                if cpuW > 0 { next.cpuPower = cpuW }
                if gpuW > 0 { next.gpuPower = gpuW }

                // Build GPU device snapshots from kext (selectors 27-30)
                let gpuCount = ProcessorModel.shared.lastKextGPUCount
                if gpuCount > 0 {
                    let temps = ProcessorModel.shared.gpuCache.temperatures
                    let powers = ProcessorModel.shared.gpuCache.powers
                    let capabilities = ProcessorModel.shared.gpuCache.capabilities
                    var devices: [GPUDeviceSnapshot] = []
                    for i in 0..<gpuCount {
                        let temp = i < temps.count ? temps[i] : 0
                        let power = i < powers.count ? powers[i] : 0
                        // Capabilities bitmap (selector 30), bit 0 = supportsPower.
                        // Falls back to the power > 0 heuristic when the loaded
                        // kext does not report capabilities (older kext without
                        // selector 30 returns an empty array).
                        let supportsPower = i < capabilities.count
                            ? (capabilities[i] & 0x01) != 0
                            : power > 0
                        devices.append(GPUDeviceSnapshot(id: i, temperature: temp, power: power, supportsPower: supportsPower))
                    }
                    next.gpuDevices = devices

                    // Use kext GPU temp/power as primary source (overrides IOAccelerator)
                    if let d0 = devices.first {
                        if d0.temperature > 0 {
                            next.gpuTemperature = d0.temperature
                            gpuTemperatureRead = temperatureDue
                        }
                        if d0.power > 0 { next.gpuPower = d0.power }
                    }
                }
            }
            // The last kext snapshot fills a missing temperature for display,
            // but it is not a reading taken on this tick: it neither publishes
            // nor reaches the long history.
            if plan.needCPUTemperature || plan.needGPUTemperature, let amd = self.lastAmdSnapshot {
                if plan.needCPUTemperature && amd.metric.count > 1 && (next.cpuTemperature == nil || next.cpuTemperature == 0) {
                    let rawTemp = Double(amd.metric[1])
                    if rawTemp > 0 && rawTemp <= 125.0 {
                        next.cpuTemperature = TemperatureSensorSelector.stabilizedTemperature(
                            rawTemp,
                            cache: &self.cpuTemperatureCache,
                            now: now,
                            maxAge: temperatureBridge,
                            minimum: TemperatureSensorSelector.minimumChipTemperature)
                    }
                }
                // Only set GPU temp from lastAmdSnapshot if it reports a real GPU temperature
                if plan.needGPUTemperature && (next.gpuTemperature == nil || next.gpuTemperature == 0) {
                    if amd.gpuTemp > 0 {
                        next.gpuTemperature = Double(amd.gpuTemp)
                    }
                }
                if amd.gpuFreq > 0 { next.gpuFreq = Double(amd.gpuFreq) }
                if amd.gpuFan > 0 { next.gpuFan = Double(amd.gpuFan) }
            }
            if cpuTemperatureRead, let temp = next.cpuTemperature {
                LongHistoryStore.shared.record(.cpuTemperature, temp)
            }
            if gpuTemperatureRead, let temp = next.gpuTemperature {
                LongHistoryStore.shared.record(.gpuTemperature, temp)
            }
            let freqs = next.cores.map { Double($0.freqMHz) }.filter { $0 > 0 }
            if !freqs.isEmpty {
                let rawMax = freqs.max() ?? 0
                let rawAvg = freqs.reduce(0, +) / Double(freqs.count)
                if rawMax >= self.lastPeakCPUFreq {
                    self.lastPeakCPUFreq = rawMax
                } else {
                    self.lastPeakCPUFreq = max(rawMax, self.lastPeakCPUFreq * 0.90)
                }
                let peak = max(self.lastPeakCPUFreq, rawAvg)
                next.peakCPUFreq = peak
                next.avgCPUFreq = rawAvg
                self.cpuFreqHistory.push(rawAvg / 1000.0)
            }
            if let kextCores = self.lastAmdSnapshot?.numPhysicalCores, kextCores > 0 {
                next.numPhysicalCores = kextCores
            } else {
                next.numPhysicalCores = Self.hostPhysicalCoreCount
            }
            next.cpuHistory = plan.needCPU ? self.cpuHistory.values : []
            next.cpuSystemHistory = plan.needCPU ? self.cpuSystemHistory.values : []
            next.gpuHistory = plan.needGPUUsage ? self.gpuHistory.values : []
            next.memoryHistory = plan.needMemory ? self.memoryHistory.values : []
            next.memoryAppHistory = plan.needMemory ? self.memoryAppHistory.values : []
            next.netDownHistory = plan.needNetwork ? self.netDownHistory.values : []
            next.netUpHistory = plan.needNetwork ? self.netUpHistory.values : []
            next.diskReadHistory = plan.needDisk ? self.diskReadHistory.values : []
            next.diskWriteHistory = plan.needDisk ? self.diskWriteHistory.values : []
            next.systemPowerHistory = plan.needPower ? self.systemPowerHistory.values : []
            next.batteryHistory = plan.needPower ? self.batteryHistory.values : []
            next.cpuFreqHistory = self.cpuFreqHistory.values

            DispatchQueue.main.async {
                // Skip pure carry-over publishes (nothing sampled, same plan,
                // same mode): the values are identical to the ones on screen.
                let planChanged = plan != self.lastPublishedPlan
                    || foregroundSampling != self.lastPublishedForeground
                if sampledAnything || planChanged {
                    self.snapshot = next
                    self.lastPublishedPlan = plan
                    self.lastPublishedForeground = foregroundSampling
                }
                self.refreshInFlight = false
                let shouldRunPendingRefresh = self.pendingRefresh
                let suppressGPU = self.pendingRefreshSuppressesGPU
                let pendingForcing = self.pendingRefreshForcing
                self.pendingRefresh = false
                self.pendingRefreshSuppressesGPU = false
                self.pendingRefreshForcing = []
                if shouldRunPendingRefresh, self.shouldRun {
                    self.refresh(suppressImmediateGPU: suppressGPU, forcing: pendingForcing)
                }
            }
        }
    }

    private func stabilizedMemoryReading(now: TimeInterval) -> (CachedMemoryReading, isFresh: Bool)? {
        let pressure = Self.readMemoryPressure()
        if let memory = SystemInfo.memoryUsage(), memory.total > 0 {
            let swapUsed = memory.swapUsed ?? memoryCache?.swapUsed
            let stablePressure: MemoryPressure
            switch pressure {
            case .unknown:
                stablePressure = memoryCache?.pressure ?? .unknown
            case .normal, .warning, .critical:
                stablePressure = pressure
            }
            let reading = CachedMemoryReading(used: memory.used,
                                              appUsed: memory.appUsed,
                                              total: memory.total,
                                              compressed: memory.compressed,
                                              cached: memory.cached,
                                              swapUsed: swapUsed,
                                              pageIns: memory.pageIns,
                                              pageOuts: memory.pageOuts,
                                              pressure: stablePressure,
                                              updatedAt: now,
                                              missedSamples: 0)
            memoryCache = reading
            return (reading, true)
        }

        guard var held = memoryCache else { return nil }
        held.missedSamples += 1
        guard held.missedSamples <= 4, now - held.updatedAt <= 12 else {
            memoryCache = nil
            return nil
        }

        switch pressure {
        case .normal, .warning, .critical:
            held.pressure = pressure
        case .unknown:
            break
        }
        memoryCache = held
        return (held, false)
    }


    // MARK: - Sensor preparation

    /// Opens the SMC lazily. Temperature key discovery is heavier (it enumerates
    /// every SMC key) so it waits until the panel or a pinned temperature metric
    /// actually needs it.
    private func prepareIfNeeded(needSMC: Bool,
                                 needTemperature: Bool) {
        if needSMC, !smcTried {
            smcTried = true
            smc = SMCClient()
            cpuTemperaturePlatform = TemperatureSensorSelector.currentPlatform()
            powerSampler = PowerSampler(smc: smc)
        }
        guard let client = smc else { return }

        guard needTemperature, !tempKeysPrepared else { return }
        tempKeysPrepared = true

        let all = client.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg") || name.hasPrefix("TG")
                || name.hasPrefix("TC") || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        cpuKeys = all.filter { $0.name.hasPrefix("Tp") || $0.name.hasPrefix("Te") || $0.name.hasPrefix("TC") }
        preferredCPUKeys = cpuKeys.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.name, platform: cpuTemperaturePlatform)
        }
        let preferredNames = Set(preferredCPUKeys.map(\.name))
        fallbackCPUKeys = cpuKeys.filter { !preferredNames.contains($0.name) }
        gpuKeys = all.filter { $0.name.hasPrefix("Tg") || $0.name.hasPrefix("TG") }
        batteryKeys = all.filter { $0.name.hasPrefix("TB") }
    }

    private func cpuTemperature() -> Double? {
        guard smc != nil else { return nil }
        // The core set decides the displayed value whenever it answers, so a
        // normal tick reads only those keys; the remaining Tp/Te keys are
        // swept exactly when they would have mattered before the split —
        // unknown platforms (empty core set) or a tick with no plausible
        // core reading.
        var readings = temperatureReadings(of: preferredCPUKeys)
        if let value = TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                         platform: cpuTemperaturePlatform) {
            return value
        }
        readings += temperatureReadings(of: fallbackCPUKeys)
        return TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                 platform: cpuTemperaturePlatform)
    }

    private func temperatureReadings(of keys: [SMCClient.Key]) -> [(key: String, value: Double)] {
        guard let smc else { return [] }
        return keys.compactMap { key -> (key: String, value: Double)? in
            guard let value = smc.readValue(key) else { return nil }
            return (key.name, value)
        }
    }

    private func maxTemperature(of keys: [SMCClient.Key]) -> Double? {
        guard let smc else { return nil }
        let values = keys.compactMap { key -> Double? in
            guard let v = smc.readValue(key), v > 1, v < 125 else { return nil }
            return v
        }
        return values.max()
    }

    // MARK: - CPU usage

    /// Aggregated load from HOST_CPU_LOAD_INFO: the busy and system tick
    /// shares since the previous refresh. After a gap (CPU was not needed for
    /// a while) the old ticks only serve as a baseline: their average over the
    /// whole gap is not a current reading and must not reach the history.
    private func readCPUUsage(now: TimeInterval) -> (busy: Double, system: Double)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        // mach_host_self() returns a send right the caller owns; release it or each
        // call leaks a mach port (this runs on every sampling tick).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let sample = CPUTickSample(user: UInt64(info.cpu_ticks.0),
                                   system: UInt64(info.cpu_ticks.1),
                                   idle: UInt64(info.cpu_ticks.2),
                                   nice: UInt64(info.cpu_ticks.3))
        let previousAt = previousCPUTicksAt
        defer {
            previousCPUTicks = sample
            previousCPUTicksAt = now
        }
        guard let previous = previousCPUTicks else { return nil }
        if let previousAt, now - previousAt > Self.maximumTickGap { return nil }
        return sample.load(since: previous)
    }

    /// Fetches per-core load using host_processor_info and combines it with
    /// AMD telemetry (frequencies, temperatures) from ProcessorModel.
    /// Publishes no cores until a per-core baseline exists: a load computed
    /// without one (launch, wake, a long gap) would read 0 % or the average
    /// over the whole gap.
    private func readCoreUsageAndTelemetry(now: TimeInterval) -> (cores: [CoreSnapshot], ccdTemps: [Float]) {
        let amdSnap = self.lastAmdSnapshot ?? ProcessorModel.TelemetrySnapshot(metric: [], loadIndex: [], numPhysicalCores: Self.hostPhysicalCoreCount, gpuTemp: 0, gpuPower: 0, gpuUtil: 0, gpuVram: 0, gpuFan: 0, gpuFreq: 0, ccdTemperatures: [])
        let numPhysical = amdSnap.numPhysicalCores > 0 ? amdSnap.numPhysicalCores : Self.hostPhysicalCoreCount

        // Get Host Processor Info for per-core load
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var coreLoads: [Float] = []
        var coreSystemLoads: [Float] = []
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &numCpuInfo)

        if kr == KERN_SUCCESS, let cpuInfo = cpuInfo {
            let cpuLoadInfo = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { ptr in
                UnsafeBufferPointer(start: ptr, count: Int(numCpuInfo))
            }

            var newTicks: [CPUTickSample] = []
            for i in 0..<Int(cpuCount) {
                let offset = i * Int(CPU_STATE_MAX)
                newTicks.append(CPUTickSample(machUser: cpuLoadInfo[offset + Int(CPU_STATE_USER)],
                                              system: cpuLoadInfo[offset + Int(CPU_STATE_SYSTEM)],
                                              idle: cpuLoadInfo[offset + Int(CPU_STATE_IDLE)],
                                              nice: cpuLoadInfo[offset + Int(CPU_STATE_NICE)]))
            }
            let loads = Self.coreLoads(current: newTicks, previous: previousCoreTicks,
                                       elapsed: previousCoreTicksAt.map { now - $0 })
            previousCoreTicks = newTicks
            previousCoreTicksAt = now
            let deallocSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), deallocSize)

            guard let loads else { return ([], amdSnap.ccdTemperatures) }
            // A single core whose counters wrapped reads 0 % for this tick.
            coreLoads = loads.map { Float($0?.busy ?? 0) * 100.0 }
            coreSystemLoads = loads.map { Float($0?.system ?? 0) * 100.0 }
        }

        // Build CoreSnapshots in natural hardware processor order (interleaved)
        var cores: [CoreSnapshot] = []
        // FREQ SOURCE: the kext's computed metric array (current-clocks
        // semantics — what each core runs at right now). The SMU PM-table's
        // CORE_FREQEFF is deliberately NOT promoted here: it is an *average
        // over the kext's sample window*, so a core parked in CC6 decodes to
        // single-digit MHz and would poison every aggregate consumer of
        // snapshot.cores[] — the Settings min/max/avg rows, the popover CPU
        // card, the menu bar avg/peak and the IPS estimate (all verified
        // Consumers). True per-physical-core SMU clocks live in the per-core
        // disclosure (AmdPowerControlsModel) which renders them per-core with
        // Sleeping-core semantics; the SMU socket POWER promotion is
        // unaffected and stays in ProcessorModel.lastCPUPowerWatts.
        let topology = Self.coreTopology(logicalCount: Int(cpuCount), physicalCount: numPhysical)
        for (logicalIdx, place) in topology.enumerated() {
            let freqIdx = place.physicalIndex + 3
            let freq = amdSnap.metric.count > freqIdx ? amdSnap.metric[freqIdx] : 0.0
            let load = coreLoads.count > logicalIdx ? coreLoads[logicalIdx] : 0.0
            let systemLoad = coreSystemLoads.count > logicalIdx ? coreSystemLoads[logicalIdx] : 0.0

            cores.append(CoreSnapshot(
                id: logicalIdx,
                freqMHz: freq,
                loadPct: load,
                isLogical: place.isLogical,
                cppcScore: nil,
                cppcScoreEstimated: false,
                coreRank: nil,
                systemPct: systemLoad
            ))
        }

        let ccdTemps = amdSnap.ccdTemperatures

        return (cores, ccdTemps)
    }

    // MARK: - GPU usage

    /// "Device Utilization %" published by the graphics accelerator
    /// (AGXAccelerator on Apple Silicon).
    private static func extractUtilization(from stats: [String: Any]) -> Double? {
        let keys = [
            "Device Utilization %",
            "GPU Activity",
            "GPU Core Utilization",
            "GPU Busy",
            "Hardware Activity",
            "Utilization",
            "gpu-usage"
        ]
        for key in keys {
            if let val = stats[key] {
                if let num = val as? NSNumber {
                    let d = num.doubleValue
                    return MetricFormat.normalizedGPUUtilization(rawValue: d, key: key)
                } else if let str = val as? String, let d = Double(str) {
                    return MetricFormat.normalizedGPUUtilization(rawValue: d, key: key)
                }
            }
        }
        return nil
    }

    /// `kextUtil` is the last kext snapshot's GPU utilisation, captured on the
    /// monitor queue by the caller: the snapshot is queue state and this runs
    /// on the global executor.
    private func readGPUUsage(kextUtil: Float?) async -> Double? {
        // Delegate to the shared IOAcceleratorCache — avoids a second IOKit registry walk.
        if let util = await IOAcceleratorCache.shared.utilization() {
            return util
        }
        // Fallback: last AMD kext snapshot if the accelerator dict has no utilisation key.
        if let amdUtil = kextUtil, amdUtil > 0 {
            return Double(amdUtil) / 100.0
        }
        return nil
    }

    /// `kextVramMB` is captured on the monitor queue, like `kextUtil` above.
    private func readGPUVRAM(kextVramMB: Float?) async -> UInt64? {
        if let v = await IOAcceleratorCache.shared.vramUsed() { return v }
        if let vramMB = kextVramMB, vramMB > 0 {
            return UInt64(vramMB * 1024 * 1024)
        }
        return nil
    }

    /// Nil when the accelerator does not report its size: an unknown total
    /// stays unknown rather than borrowing one card's 16 GB.
    private func readGPUVRAMTotal() async -> UInt64? {
        await IOAcceleratorCache.shared.vramTotal()
    }

    // MARK: - Memory pressure

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(kernelLevel: level)
    }
}
