import Foundation
import Combine
import os.log
import os

@MainActor
class FanCurveController: ObservableObject {
    static let shared = FanCurveController()
    
    struct FanCurveState {
        var mappings: [Int: Int] = [:]
        var curves: [FanCurve] = []
    }
    
    private let stateLock = OSAllocatedUnfairLock(initialState: FanCurveState())
    
    @Published var customCurves: [FanCurve] = [] {
        didSet {
            let curvesToSave = customCurves
            stateLock.withLock { $0.curves = curvesToSave }
            if let data = try? JSONEncoder().encode(customCurves) {
                UserDefaults.standard.set(data, forKey: "customCurves")
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
        
        updateControlLoopState()
    }
    
    private func updateControlLoopState() {
        let hasActiveCurves = fanMappings.values.contains(where: { $0 >= 0 })
        if hasActiveCurves {
            startControlLoop()
        } else {
            stopControlLoop()
        }
    }
    
    private func startControlLoop() {
        if controlTask != nil { return }
        
        controlTask = Task.detached(priority: .background) { [weak self] in
            var lastTemp: [FanSensor: Double] = [:]
            var currentPWM: [Int: Double] = [:] // Fan ID -> PWM
            var lastSentSMCValue: [Int: Int] = [:] // Fan ID -> last sent SMC PWM (0-255)
            
            // Track which fans are already in manual mode to avoid redundant IOKit calls
            var manualFans: Set<Int> = []
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard let self else { break }
                
                let telemetry = await ProcessorModel.shared.snapshotTelemetry(forceMetric: false)
                // P1/P2-fix: If the kext times out, metric[1] comes back as 0.0.
                // Thermal safety guardrails: rawCPUTemp <= 0 or > 125.0 are considered sensor failures.
                // Retain the last valid reading instead.
                let rawCPUTemp = telemetry.metric.count > 1 ? Double(telemetry.metric[1]) : 0.0
                if rawCPUTemp > 0 && rawCPUTemp <= 125.0 { lastTemp[.cpu] = rawCPUTemp }
                let cpuTemp = lastTemp[.cpu] ?? rawCPUTemp  // falls back to bad value only on first read

                // Kext GPU temp (thread-safe, no actor hop)
                let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
                // Fallback: SystemMonitor snapshot GPU temp
                let fallbackGPUTemp = await MainActor.run {
                    SystemMonitor.shared.snapshot.gpuTemperature ?? cpuTemp
                }
                var rawGPUTemp = kextGPUTemp > 0 ? kextGPUTemp : fallbackGPUTemp > 0 ? fallbackGPUTemp : cpuTemp
                if rawGPUTemp > 0 && rawGPUTemp <= 125.0 {
                    lastTemp[.gpu] = rawGPUTemp
                } else {
                    rawGPUTemp = lastTemp[.gpu] ?? rawGPUTemp
                }
                let gpuTemp = rawGPUTemp
                
                let (mappings, curves) = self.stateLock.withLock { ($0.mappings, $0.curves) }
                
                for (fanId, curveIdx) in mappings {
                    if curveIdx < 0 || curveIdx >= curves.count {
                        // Do not interfere with manual slider overrides set by the user
                        manualFans.remove(fanId)
                        lastSentSMCValue.removeValue(forKey: fanId)
                        continue
                    }
                    
                    var curve = curves[curveIdx]
                    let rawTemp = curve.sourceSensor == .cpu ? cpuTemp : gpuTemp
                    let lastT = lastTemp[curve.sourceSensor] ?? rawTemp
                    let effectiveTemp: Double
                    if abs(rawTemp - lastT) >= curve.hysteresis {
                        effectiveTemp = rawTemp
                        lastTemp[curve.sourceSensor] = rawTemp
                    } else {
                        effectiveTemp = lastT
                    }
                    
                    // LUT Evaluation (cached LUT)
                    let lut = curve.getLUT() // Returns cached PWM table
                    let safeTemp = min(max(Int(effectiveTemp), 0), 255)
                    let targetPWM = lut[safeTemp]
                    
                    let current = currentPWM[fanId] ?? targetPWM
                    
                    // Ramp rate limit towards targetPWM
                    var newPWM = targetPWM
                    let diff = targetPWM - current
                    if abs(diff) > curve.rampRate {
                        newPWM = current + (diff > 0 ? curve.rampRate : -curve.rampRate)
                    }
                    
                    // Thermal safety guard — mirrors the kext's own fan-curve
                    // guard (kTHERMAL_GUARD_TEMP_C 85°C / kTHERMAL_GUARD_PWM
                    // 80%) so a user-drawn curve can never leave the CPU
                    // without airflow near TjMax. Applies to every supported
                    // family (Zen 1-5 all share the 90-95°C TjMax range).
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

    /// Resets all custom-mapped fans back to automatic mode asynchronously.
    /// Safe to call on app termination or teardown.
    ///
    /// Reads the fan mapping from the thread-safe `stateLock` snapshot instead
    /// of crossing to the MainActor to capture `FanCurveController.shared` —
    /// on teardown the shared instance may already be deallocated, and the
    /// lock snapshot needs no actor hop.
    nonisolated func resetFansToAutoSync() {
        let mappings = stateLock.withLock { $0.mappings }
        for (fanId, curveIdx) in mappings where curveIdx >= 0 {
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
        }
    }
}
