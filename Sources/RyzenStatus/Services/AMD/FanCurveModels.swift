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
    var isOverrided: Bool
}

// MARK: - Fan Curve Point

struct FanCurvePoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var temp: Double
    var pwm: Double
}

// MARK: - Fan Curve

struct FanCurve: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var points: [FanCurvePoint]
    var sourceSensor: FanSensor
    var hysteresis: Double // In °C
    var rampRate: Double   // In % PWM / sec
    
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
}
