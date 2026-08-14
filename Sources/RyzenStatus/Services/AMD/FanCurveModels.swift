import Foundation

// MARK: - Fan Sensor

enum FanSensor: Int, Codable, CaseIterable {
    case cpu = 0
    case gpu = 1
}

// MARK: - Fan Snapshot

struct FanSnapshot: Identifiable {
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
}

// MARK: - Fan Curve Point

struct FanCurvePoint: Codable, Identifiable, Hashable {
    let id: UUID
    var temp: Double
    var pwm: Double
    
    init(id: UUID = UUID(), temp: Double, pwm: Double) {
        self.id = id
        self.temp = temp
        self.pwm = pwm
    }
}

// MARK: - Fan Curve

struct FanCurve: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var points: [FanCurvePoint] {
        didSet { _cachedLUT = nil }
    }
    var sourceSensor: FanSensor
    var hysteresis: Double // In °C
    var rampRate: Double   // In % PWM / sec
    
    private var _cachedLUT: [Double]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, points, sourceSensor, hysteresis, rampRate
    }
    
    init(id: UUID = UUID(),
         name: String,
         points: [FanCurvePoint],
         sourceSensor: FanSensor,
         hysteresis: Double,
         rampRate: Double) {
        self.id = id
        self.name = name
        self.points = points
        self.sourceSensor = sourceSensor
        self.hysteresis = hysteresis
        self.rampRate = rampRate
    }
    
    mutating func invalidateLUT() {
        _cachedLUT = nil
    }
    
    mutating func getLUT() -> [Double] {
        if let cached = _cachedLUT { return cached }
        let lut = generateRPMLUT()
        _cachedLUT = lut
        return lut
    }

    func generateRPMLUT() -> [Double] {
        var lut = [Double](repeating: 0.0, count: 256)
        let sortedPoints = points.sorted { $0.temp < $1.temp }
        guard let firstPt = sortedPoints.first, let lastPt = sortedPoints.last else { return lut }
        
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
            for i in 0..<(sortedPoints.count - 1) {
                let p1 = sortedPoints[i]
                let p2 = sortedPoints[i + 1]
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
