// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

// MARK: - Fan Sensor

enum FanSensor: Int, Codable, CaseIterable, Sendable {
    case cpu = 0
    case gpu = 1
}

// MARK: - Fan Control Mode

enum FanControlMode: Int, Codable, Sendable, CaseIterable {
    case auto = 0
    case curve = 1
    case manual = 2
}

// MARK: - Fan State (Source of Truth Model)

struct FanState: Identifiable, Sendable, Hashable {
    let id: Int                       // SuperIO fan index (0..<16)
    var name: String
    var rpm: UInt64                   // selector 93 (RPM)
    var throttlePWM: UInt8            // selector 94 bits [15:8] (0-255 SMC scale)
    var isKextAuto: Bool              // selector 94 bit 0 (1 = Auto / SmartGuardian)
    var controlMode: FanControlMode   // derived from hardware state + intent
    var mappedCurveIndex: Int?        // 0..<4, nil if unmapped/Auto
    var manualPWM: UInt8?             // non-nil in .manual (0-255)
    var isHidden: Bool
    var customName: String?

    init(id: Int,
         name: String,
         rpm: UInt64,
         throttlePWM: UInt8,
         isKextAuto: Bool,
         controlMode: FanControlMode,
         mappedCurveIndex: Int? = nil,
         manualPWM: UInt8? = nil,
         isHidden: Bool = false,
         customName: String? = nil) {
        self.id = id
        self.name = name
        self.rpm = rpm
        self.throttlePWM = throttlePWM
        self.isKextAuto = isKextAuto
        self.controlMode = controlMode
        self.mappedCurveIndex = mappedCurveIndex
        self.manualPWM = manualPWM
        self.isHidden = isHidden
        self.customName = customName
    }

    var pwmPercentage: Double {
        (Double(throttlePWM) / 255.0) * 100.0
    }

    var effectiveDisplayName: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return name.isEmpty ? "Fan \(id + 1)" : name
    }
}

// MARK: - Legacy / Telemetry Fan Snapshot

struct FanSnapshot: Identifiable, Sendable, Hashable {
    let id: Int
    var name: String
    var rpm: UInt64
    var throttle: UInt8
    var isOverridden: Bool

    @available(*, deprecated, renamed: "isOverridden")
    var isOverrided: Bool {
        get { isOverridden }
        set { isOverridden = newValue }
    }

    var pwmPercentage: Double {
        (Double(throttle) / 255.0) * 100.0
    }
}

// MARK: - Fan Curve Point

struct FanCurvePoint: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var temp: Double // 0-100 °C
    var pwm: Double  // 0-100 % (UI scale)

    init(id: UUID = UUID(), temp: Double, pwm: Double) {
        self.id = id
        self.temp = temp
        self.pwm = pwm
    }
}

// MARK: - Fan Curve Definition

struct FanCurveDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kextSlot: Int                 // 0..<4, assigned on upload
    var points: [FanCurvePoint]       // edit-time (0-100 % PWM)
    var sourceSensor: FanSensor       // 0=cpu, 1=gpu
    var hysteresis: UInt8             // °C (1..5)
    var rampRate: UInt8               // UI scale %/s (1..20) — converted on pack

    init(id: UUID = UUID(),
         name: String,
         kextSlot: Int = 0,
         points: [FanCurvePoint],
         sourceSensor: FanSensor = .cpu,
         hysteresis: UInt8 = 2,
         rampRate: UInt8 = 5) {
        self.id = id
        self.name = name
        self.kextSlot = kextSlot
        self.points = points
        self.sourceSensor = sourceSensor
        self.hysteresis = hysteresis
        self.rampRate = rampRate
    }

    /// Converts edit points (0-100% PWM) to the kext 256-point UInt8 LUT (0-255 PWM).
    /// Numeric contract: convert anchor points to 0-255 first (`round(pwm * 2.55)`),
    /// then interpolate in Double 0-255, and `.rounded()` per entry.
    func makeSMC_LUT() -> [UInt8] {
        FanCurveDefinition.interpolateAnchorsToSMC_LUT(points: points)
    }

    /// Converts edit points (0-100% PWM) to a 256-point Double array (0-100%) for UI graph rendering.
    func generateRPMLUT() -> [Double] {
        FanCurveDefinition.interpolatePointsToPercentLUT(points: points)
    }

    /// Pure LUT generator converting anchors to 0-255 scale first, then interpolating.
    static func interpolateAnchorsToSMC_LUT(points: [FanCurvePoint]) -> [UInt8] {
        guard !points.isEmpty else {
            return [UInt8](repeating: 0, count: 256)
        }
        let sorted = points.sorted { $0.temp < $1.temp }

        let convertedAnchors: [(temp: Int, pwm: Int)] = sorted.map { pt in
            let t = min(255, max(0, Int(pt.temp.rounded())))
            let p = min(255, max(0, Int((pt.pwm * 2.55).rounded())))
            return (temp: t, pwm: p)
        }

        return AMDFanCurvePreset.interpolate(anchors: convertedAnchors)
    }

    /// Interpolates points directly in percentage scale (0-100%).
    static func interpolatePointsToPercentLUT(points: [FanCurvePoint]) -> [Double] {
        var lut = [Double](repeating: 0.0, count: 256)
        let sorted = points.sorted { $0.temp < $1.temp }
        guard let firstPt = sorted.first, let lastPt = sorted.last else { return lut }

        for temp in 0...255 {
            let tempD = Double(temp)
            if tempD <= firstPt.temp {
                lut[temp] = firstPt.pwm
                continue
            }
            if tempD >= lastPt.temp {
                lut[temp] = lastPt.pwm
                continue
            }
            for i in 0..<(sorted.count - 1) {
                let p1 = sorted[i]
                let p2 = sorted[i + 1]
                if tempD >= p1.temp && tempD <= p2.temp {
                    let span = p2.temp - p1.temp
                    let pct = span > 0 ? (tempD - p1.temp) / span : 0.0
                    let interpPWM = p1.pwm + pct * (p2.pwm - p1.pwm)
                    lut[temp] = interpPWM
                    break
                }
            }
        }
        return lut
    }

    /// Packs this curve into the 272-byte `AMDFanCurveInput` struct for selector 101.
    func makeKextInput(slot: Int) -> AMDFanCurveInput {
        let convertedRampRate = UInt32(min(255, max(1, Int((Double(rampRate) * 2.55).rounded()))))
        let convertedHysteresis = UInt32(min(255, max(1, hysteresis)))
        return AMDFanCurveInput(
            curveIndex: UInt32(slot),
            sourceSensor: UInt32(sourceSensor.rawValue),
            hysteresis: convertedHysteresis,
            rampRate: convertedRampRate,
            lut: makeSMC_LUT()
        )
    }

    // MARK: - Pure Math & Mapping Helpers

    /// Computes the next PWM level stepped smoothly according to ramp rate (%/s) and elapsed time (seconds).
    static func stepPWM(current: Double, target: Double, rampPerSec: Double, dt: Double) -> Double {
        guard dt > 0, rampPerSec > 0 else { return target }
        let maxStep = rampPerSec * dt
        let diff = target - current
        if abs(diff) <= maxStep {
            return target
        }
        return current + (diff > 0 ? maxStep : -maxStep)
    }

    /// Evaluates temperature with hysteresis against a reference anchor.
    /// Updates anchor only when temperature delta reaches or exceeds threshold.
    static func applyHysteresis(anchor: Double, raw: Double, threshold: Double) -> (effective: Double, newAnchor: Double) {
        if threshold <= 0 || abs(raw - anchor) >= threshold {
            return (effective: raw, newAnchor: raw)
        } else {
            return (effective: anchor, newAnchor: anchor)
        }
    }

    /// Compacts fan mapping indices when a curve at `deletedIndex` is removed:
    /// - Fans mapped to `deletedIndex` are set to `-1` (Auto mode)
    /// - Fans mapped to higher indices are shifted down by 1
    /// - Other mappings remain intact
    static func compactMappingsOnDeletion(mappings: [Int: Int], deletedIndex: Int) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (fanId, curveIdx) in mappings {
            if curveIdx == deletedIndex {
                result[fanId] = -1
            } else if curveIdx > deletedIndex {
                result[fanId] = curveIdx - 1
            } else {
                result[fanId] = curveIdx
            }
        }
        return result
    }
}

typealias FanCurve = FanCurveDefinition
