import Foundation
import Combine
import os.log

@MainActor
class FanCurveController: ObservableObject {
    static let shared = FanCurveController()
    
    @Published var customCurves: [FanCurve] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customCurves) {
                UserDefaults.standard.set(data, forKey: "customCurves")
            }
        }
    }
    
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
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
                
                guard let self = self else { break }
                
                let telemetry = await ProcessorModel.shared.snapshotTelemetry(forceMetric: false)
                let cpuTemp = Double(telemetry.metric[1]) // Package Temp
                let gpuTemp = await MainActor.run {
                    SystemMonitor.shared.snapshot.gpuTemperature ?? cpuTemp
                }
                
                let mappings = await self.fanMappings
                let curves = await self.customCurves
                
                for (fanId, curveIdx) in mappings {
                    if curveIdx < 0 || curveIdx >= curves.count {
                        // Do not interfere with manual slider overrides set by the user
                        manualFans.remove(fanId)
                        lastSentSMCValue.removeValue(forKey: fanId)
                        continue
                    }
                    
                    let curve = curves[curveIdx]
                    let rawTemp = curve.sourceSensor == .cpu ? cpuTemp : gpuTemp
                    let lastT = lastTemp[curve.sourceSensor] ?? rawTemp
                    let effectiveTemp: Double
                    if abs(rawTemp - lastT) >= curve.hysteresis {
                        effectiveTemp = rawTemp
                        lastTemp[curve.sourceSensor] = rawTemp
                    } else {
                        effectiveTemp = lastT
                    }
                    
                    // LUT Evaluation
                    let lut = curve.generateRPMLUT() // Returns PWM table
                    let safeTemp = min(max(Int(effectiveTemp), 0), 255)
                    let targetPWM = lut[safeTemp]
                    
                    let current = currentPWM[fanId] ?? targetPWM
                    
                    // Ramp rate limit towards targetPWM
                    var newPWM = targetPWM
                    let diff = targetPWM - current
                    if abs(diff) > curve.rampRate {
                        newPWM = current + (diff > 0 ? curve.rampRate : -curve.rampRate)
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
                        _ = ProcessorModel.shared.setFanSpeed(rpm: finalSMCValue, fanIndex: fanId)
                        lastSentSMCValue[fanId] = finalSMCValue
                    }
                }
            }
        }
    }
    
    private func stopControlLoop() {
        controlTask?.cancel()
        controlTask = nil
        
        // Revert all fans mapped to a custom curve back to auto
        Task {
            for (fanId, curveIdx) in fanMappings {
                if curveIdx >= 0 {
                    _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
                }
            }
        }
    }
}
