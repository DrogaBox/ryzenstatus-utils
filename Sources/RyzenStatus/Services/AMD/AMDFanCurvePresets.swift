import Foundation

// MARK: - Kext Fan Curve Presets (selectors 101/102)

/// Predefined 256-point fan curves that match the kext's `FanCurveInput`
/// layout (selector 101). LUT index = temperature °C, value = PWM on the
/// 0–255 SMC scale — the same scale the kext's SuperIO control applies.
enum AMDFanCurvePreset: String, CaseIterable, Identifiable {
    case silent = "Silent"
    case balanced = "Balanced"
    case performance = "Performance"
    case aggressive = "Aggressive"

    var id: String { rawValue }

    /// Anchor points `(temp °C, PWM 0-255)`. Silent mirrors the reference
    /// curve: 0–40°C → PWM 0, ramping to 80 at 60°C, 150 at 80°C and 255 at
    /// 100°C.
    var anchors: [(temp: Int, pwm: Int)] {
        switch self {
        case .silent:      return [(0, 0), (40, 0), (60, 80), (80, 150), (100, 255)]
        case .balanced:    return [(0, 30), (40, 30), (60, 110), (80, 180), (100, 255)]
        case .performance: return [(0, 50), (40, 50), (60, 160), (80, 230), (100, 255)]
        case .aggressive:  return [(0, 80), (40, 80), (60, 200), (80, 250), (100, 255)]
        }
    }

    /// Temperature hysteresis (°C) uploaded with the curve (kext default 2).
    var hysteresis: UInt32 {
        switch self {
        case .silent:      return 3
        case .balanced:    return 2
        case .performance: return 1
        case .aggressive:  return 1
        }
    }

    /// PWM ramp-rate limit (units/sec) uploaded with the curve (kext default 5).
    var rampRate: UInt32 {
        switch self {
        case .silent:      return 3
        case .balanced:    return 5
        case .performance: return 8
        case .aggressive:  return 12
        }
    }

    /// Linear-interpolated 256-entry LUT (index = °C, value = PWM 0–255).
    func makeLUT() -> [UInt8] {
        AMDFanCurvePreset.interpolate(anchors: anchors)
    }

    /// Pure LUT builder shared with tests. Linearly interpolates between
    /// anchor points; temperatures before the first / after the last anchor
    /// clamp to the endpoints. Every value is clamped to 0...255.
    static func interpolate(anchors: [(temp: Int, pwm: Int)]) -> [UInt8] {
        let sorted = anchors.sorted { $0.temp < $1.temp }
        guard let first = sorted.first, let last = sorted.last else {
            return [UInt8](repeating: 0, count: 256)
        }
        var lut = [UInt8](repeating: 0, count: 256)
        for temp in 0...255 {
            var pwm: Int
            if temp <= first.temp {
                pwm = first.pwm
            } else if temp >= last.temp {
                pwm = last.pwm
            } else if let pair = segmentIndex(for: temp, in: sorted) {
                let p1 = sorted[pair]
                let p2 = sorted[pair + 1]
                let span = p2.temp - p1.temp
                let pct = span > 0 ? Double(temp - p1.temp) / Double(span) : 0
                pwm = Int((Double(p1.pwm) + pct * Double(p2.pwm - p1.pwm)).rounded())
            } else {
                pwm = 0
            }
            lut[temp] = UInt8(min(255, max(0, pwm)))
        }
        return lut
    }

    private static func segmentIndex(for temp: Int, in sorted: [(temp: Int, pwm: Int)]) -> Int? {
        for i in 0..<(sorted.count - 1) where temp >= sorted[i].temp && temp <= sorted[i + 1].temp {
            return i
        }
        return nil
    }
}

// MARK: - Kext FanCurveInput (272 packed bytes)

/// Packed input for kext selector 101. Layout matches the kext's
/// `#pragma pack(push, 1) struct FanCurveInput` exactly:
/// 4 × `UInt32` + 256 × `UInt8` = 272 bytes. macOS is little-endian, so plain
/// host-order bytes are correct for the IOKit struct-copy call.
struct AMDFanCurveInput {
    var curveIndex: UInt32   // 0..<MAX_FAN_CURVES (4)
    var sourceSensor: UInt32 // 0 = CPU, 1 = GPU
    var hysteresis: UInt32   // °C
    var rampRate: UInt32     // PWM/sec
    var lut: [UInt8]         // 256 entries: idx = °C, value = PWM 0–255

    static let byteSize = 272

    func packedData() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: curveIndex.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sourceSensor.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: hysteresis.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: rampRate.littleEndian) { Array($0) })
        // Pad/trim defensively so the payload is always exactly 256 LUT bytes.
        let padded = lut + [UInt8](repeating: 0, count: max(0, 256 - lut.count))
        data.append(contentsOf: padded.prefix(256))
        return data
    }
}
