import Foundation
import AppKit
import Combine
import os.log
import os

@MainActor
class FanCurveController: ObservableObject {
    static let shared = FanCurveController()
    
    struct FanCurveState {
        var mappings: [Int: Int] = [:]
        var curves: [FanCurve] = []
        var manualOverrideFanIds: Set<Int> = []
    }
    
    private let stateLock = OSAllocatedUnfairLock(initialState: FanCurveState())
    private var persistTask: Task<Void, Never>?
    
    @Published var customCurves: [FanCurve] = [] {
        didSet {
            let curvesToSave = customCurves
            stateLock.withLock { $0.curves = curvesToSave }
            persistTask?.cancel()
            persistTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                if let data = try? JSONEncoder().encode(curvesToSave) {
                    UserDefaults.standard.set(data, forKey: "customCurves")
                }
            }
        }
    }
    
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
            let mappingsToSave = fanMappings
            stateLock.withLock { $0.mappings = mappingsToSave }
            if let data = try? JSONEncoder().encode(fanMappings) {
                UserDefaults.standard.set(data, forKey: "fanMappings")
            }
            updateControlLoopState()
        }
    }
    
    // PID state
    private var controlTask: Task<Void, Never>?
    private let logger = OSLog(subsystem: "com.ryzenstatus.fancurve", category: "Controller")
    private var wakeObserver: Any?
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: "customCurves"),
           let decoded = try? JSONDecoder().decode([FanCurve].self, from: data) {
            self.customCurves = decoded
        } else {
            self.customCurves = [
                FanCurve(
                    name: "Silent",
                    points: [
                        FanCurvePoint(temp: 40, pwm: 20),
                        FanCurvePoint(temp: 60, pwm: 35),
                        FanCurvePoint(temp: 75, pwm: 50),
                        FanCurvePoint(temp: 85, pwm: 80)
                    ],
                    sourceSensor: .cpu,
                    hysteresis: 2.0,
                    rampRate: 5.0
                ),
                FanCurve(
                    name: "Performance",
                    points: [
                        FanCurvePoint(temp: 40, pwm: 40),
                        FanCurvePoint(temp: 60, pwm: 65),
                        FanCurvePoint(temp: 75, pwm: 85),
                        FanCurvePoint(temp: 85, pwm: 100)
                    ],
                    sourceSensor: .cpu,
                    hysteresis: 1.0,
                    rampRate: 10.0
                )
            ]
        }
        
        if let data = UserDefaults.standard.data(forKey: "fanMappings"),
           let decoded = try? JSONDecoder().decode([Int: Int].self, from: data) {
            self.fanMappings = decoded
        } else {
            self.fanMappings = [:]
        }
        
        let curvesToSave = self.customCurves
        let mappingsToSave = self.fanMappings
        stateLock.withLock {
            $0.curves = curvesToSave
            $0.mappings = mappingsToSave
        }
        
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWakeNotification()
            }
        }
        
        updateControlLoopState()
    }
    
    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
    
    func registerManualOverride(fanId: Int) {
        _ = stateLock.withLock { $0.manualOverrideFanIds.insert(fanId) }
    }
    
    func unregisterManualOverride(fanId: Int) {
        _ = stateLock.withLock { $0.manualOverrideFanIds.remove(fanId) }
    }
    
    private func handleWakeNotification() {
        // Restart loop to clear stale temperature anchors and timers
        if fanMappings.values.contains(where: { $0 >= 0 }) {
            stopControlLoop()
            startControlLoop()
        }
    }
    
    private func updateControlLoopState() {
        let hasActiveCurves = fanMappings.values.contains(where: { $0 >= 0 })
        if hasActiveCurves {
            startControlLoop()
        } else {
            stopControlLoop()
        }
    }

    // MARK: - Control Loop
    
    private func startControlLoop() {
        guard controlTask == nil else { return }
        
        controlTask = Task.detached(priority: .utility) { [weak self] in
            var lastSentSMCValue: [Int: Int] = [:]
            var currentPWM: [Int: Double] = [:]
            var lastTemp: [FanSensor: Double] = [:]
            var hysteresisAnchor: [FanSensor: Double] = [:]
            var lastTickTime = ProcessInfo.processInfo.systemUptime
            
            // Track which fans are already in manual mode to avoid redundant IOKit calls
            var manualFans: Set<Int> = []
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard let self else { break }
                
                let now = ProcessInfo.processInfo.systemUptime
                let dt = max(0.1, min(10.0, now - lastTickTime))
                lastTickTime = now
                
                // Optimized telemetry: try selector 100 directly first (F13)
                var rawCPUTemp: Double = 0.0
                if let packet = ProcessorModel.shared.getTelemetry(), packet.packageTempC > 0 {
                    rawCPUTemp = Double(packet.packageTempC)
                } else {
                    let telemetry = await ProcessorModel.shared.snapshotTelemetry(forceMetric: false)
                    rawCPUTemp = telemetry.metric.count > 1 ? Double(telemetry.metric[1]) : 0.0
                }
                
                // Thermal safety guardrails: rawCPUTemp <= 0 or > 125.0 are considered sensor failures.
                if rawCPUTemp > 0 && rawCPUTemp <= 125.0 {
                    lastTemp[.cpu] = rawCPUTemp
                }
                let cpuTemp = lastTemp[.cpu] ?? rawCPUTemp
                
                // Kext GPU temp (thread-safe, no actor hop)
                let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
                // Fallback: SystemMonitor snapshot GPU temp
                let fallbackGPUTemp = await MainActor.run {
                    SystemMonitor.shared.snapshot.gpuTemperature ?? cpuTemp
                }
                var rawGPUTemp = kextGPUTemp > 0 ? kextGPUTemp : (fallbackGPUTemp > 0 ? fallbackGPUTemp : cpuTemp)
                if rawGPUTemp > 0 && rawGPUTemp <= 125.0 {
                    lastTemp[.gpu] = rawGPUTemp
                } else {
                    rawGPUTemp = lastTemp[.gpu] ?? rawGPUTemp
                }
                let gpuTemp = rawGPUTemp
                
                let (mappings, curves) = self.stateLock.withLock { ($0.mappings, $0.curves) }
                
                for (fanId, curveIdx) in mappings {
                    // F1 fix: If mapping is out of range or deactivated, return the fan to Auto mode
                    if curveIdx < 0 || curveIdx >= curves.count {
                        if manualFans.contains(fanId) {
                            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
                            manualFans.remove(fanId)
                        }
                        lastSentSMCValue.removeValue(forKey: fanId)
                        currentPWM.removeValue(forKey: fanId)
                        continue
                    }
                    
                    var curve = curves[curveIdx]
                    let rawTemp = curve.sourceSensor == .cpu ? cpuTemp : gpuTemp
                    
                    // F2 fix: Independent hysteresis anchor
                    let currentAnchor = hysteresisAnchor[curve.sourceSensor] ?? rawTemp
                    let (effectiveTemp, newAnchor) = FanCurve.applyHysteresis(
                        anchor: currentAnchor,
                        raw: rawTemp,
                        threshold: curve.hysteresis
                    )
                    hysteresisAnchor[curve.sourceSensor] = newAnchor
                    
                    // LUT Evaluation (cached LUT)
                    let lut = curve.getLUT()
                    let safeTemp = min(max(Int(effectiveTemp), 0), 255)
                    let targetPWM = lut[safeTemp]
                    
                    let current = currentPWM[fanId] ?? targetPWM
                    
                    // F3 fix: Ramp rate per second with dt
                    var newPWM = FanCurve.stepPWM(
                        current: current,
                        target: targetPWM,
                        rampPerSec: curve.rampRate,
                        dt: dt
                    )
                    
                    // Thermal safety guard — mirrors the kext's own fan-curve guard (85°C / 80% PWM)
                    if effectiveTemp >= 85.0 {
                        newPWM = max(newPWM, 80.0)
                    }
                    
                    currentPWM[fanId] = newPWM
                    
                    // Only call setFanMode once per fan when transitioning to manual
                    if !manualFans.contains(fanId) {
                        _ = ProcessorModel.shared.setFanMode(auto: false, fanIndex: fanId)
                        manualFans.insert(fanId)
                    }
                    
                    // Convert PWM percentage (0-100) to SMC scale (0-255) with clamp
                    let clampedPWM = min(max(newPWM, 0), 100)
                    let finalSMCValue = min(max(Int((clampedPWM / 100.0) * 255.0), 0), 255)
                    
                    // Deduplicate hardware writes: only send IOKit call when target value changes
                    if lastSentSMCValue[fanId] != finalSMCValue {
                        _ = ProcessorModel.shared.setFanSpeed(pwm: finalSMCValue, fanIndex: fanId)
                        lastSentSMCValue[fanId] = finalSMCValue
                    }
                }
            }
        }
    }
    
    private func stopControlLoop() {
        controlTask?.cancel()
        controlTask = nil
        
        resetFansToAutoSync()
    }

    /// Resets all custom-mapped fans and manual overrides back to automatic mode.
    nonisolated func resetFansToAutoSync() {
        let (mappings, overrides) = stateLock.withLock { ($0.mappings, $0.manualOverrideFanIds) }
        var fansToReset = Set<Int>()
        for (fanId, curveIdx) in mappings where curveIdx >= 0 {
            fansToReset.insert(fanId)
        }
        for fanId in overrides {
            fansToReset.insert(fanId)
        }
        for fanId in fansToReset {
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
        }
    }
}
