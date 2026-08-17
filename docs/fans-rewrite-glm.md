# RyzenStatus — Fans rewrite: numeric contract audit (READ-ONLY, fully self-contained)

You are the **hardware-correctness auditor** on a three-agent team rewriting the fan & cooling control system of **RyzenStatus** (macOS menu-bar app, Swift 6, SwiftUI). A second agent implements the rewrite (moving from a 2-second userspace control loop to the kext's native in-kernel fan-curve driver); a third audits architecture/UX. Your job is the **exact numeric contract between the app and the kext**: every scale, conversion, rounding, threshold and packing detail.

**This prompt is fully self-contained** — every relevant source excerpt is pasted below, verbatim from the repo. You have no network/local access, and you must NOT fabricate evidence: every claim you make must cite the pasted code (I will show the file it came from). If something is not present in the excerpts, say "not verifiable from provided excerpts" instead of guessing.

**Why you exist**: a scale mismatch was already caught in review — the app's curve editor exposes ramp rate as "%/s on a 0-100 scale" while the kext interprets it as "PWM units/s on a 0-255 scale" (a ~2.55× error that would silently survive a rewrite). Your deliverable is the reference document the implementer codes against and the reviewer checks against.

## Verified facts — do not relitigate (these come from the code excerpts below)

- Selectors: 90 fanInit, 91 fanCountRead, 92 fanName (string), 93 fanSpeedRead (RPM as UInt64 array), 94 fanCtrlRead (throttle<<8 | autoFlag), 95 fanSpeedWrite [fanIndex, pwm 0-255], 96 fanModeWrite [fanIndex] (restore auto), 101 fanCurveLUTWrite (struct), 102 fanToCurveMap [fanIndex, curveIndex].
- `AMDFanCurveInput` = 272 packed bytes: 4×UInt32 (curveIndex, sourceSensor, hysteresis, rampRate) + 256×UInt8 LUT. Little-endian host order is correct on macOS.
- `MAX_FAN_CURVES = 4`; fan headers `< 16` and `< superIO->getNumberOfFans()`; `curveIdx in [-1, 3]`; `-1` crosses as `UInt64(bitPattern: Int64(-1))` = 0xFFFFFFFFFFFFFFFF.
- Write selectors (95/96/101/102) return `kIOReturnNotPrivileged` (0xe00002c1) without root or `-amdpnopchk`.
- Kext version gate ≥ 1.0.0 (app side).

---

## KEXT SOURCE (from SMCAMDProcessor_Source/)

### 1. `AMDRyzenCPUPowerManagement.hpp` L80-90 — curve config + fan count

```cpp
#define MAX_FAN_CURVES 4
struct FanCurveConfig {
    uint8_t lut[256];
    uint8_t sourceSensor; // 0 = CPU, 1 = GPU
    uint8_t hysteresis;   // In °C
    uint8_t rampRate;     // Max PWM change per second
};
```

### 2. `AMDRyzenCPUPowerManagement.cpp` L21-22 — thermal guard constants

```cpp
static constexpr float  kTHERMAL_GUARD_TEMP_C        = 85.0f;
static constexpr uint8_t kTHERMAL_GUARD_PWM          = 200;   // 80%
```

### 3. `AMDRyzenCPUPowerManagement.cpp` L679-690 — curve init defaults (within the `for i in 0..<MAX_FAN_CURVES` init loop)

```cpp
        fanToCurveMap[i] = -1;
        memset(fanCurves[i].lut, 0, 256);
        fanCurves[i].sourceSensor = 0;
        fanCurves[i].hysteresis = 2;
        fanCurves[i].rampRate = 5;
        curveSmoothedTemp[i] = 40.0f;
```

### 4. `AMDRyzenCPUPowerManagement.cpp` L1559-1666 — the in-kernel curve driver `evaluateFanCurves()` (called from the kext's HF temperature timer, L378; cadence = `HF_TEMP_SAMPLE_PERIOD`)

```cpp
void AMDRyzenCPUPowerManagement::evaluateFanCurves() {
    if (!superIOLock) return;
    IOLockLock(superIOLock);
    if (!superIO) {
        IOLockUnlock(superIOLock);
        return;
    }
    
    // 1. Get raw current temperatures
    float cpuTemp = getPackageTemp();
    float gpuTemp = gpuTempC;
    
    uint64_t now = getCurrentTimeNs();
    
    for (int fanIdx = 0; fanIdx < superIO->getNumberOfFans(); fanIdx++) {
        int8_t curveIdx = fanToCurveMap[fanIdx];
        if (curveIdx < 0 || curveIdx >= MAX_FAN_CURVES) {
            continue; // Default BIOS Auto control
        }
        
        FanCurveConfig &config = fanCurves[curveIdx];
        
        // 2. Select temperature source
        float rawSourceTemp = cpuTemp;
        if (config.sourceSensor == 1) {
            rawSourceTemp = gpuTemp > 0.0f ? gpuTemp : cpuTemp; // Fallback to CPU if GPU not updated
        }
        
        // 3. Apply Exponential Moving Average (EMA) for temperature input
        float alpha = 0.2f;
        float prevSmoothed = curveSmoothedTemp[curveIdx];
        float smoothed = (alpha * rawSourceTemp) + ((1.0f - alpha) * prevSmoothed);
        curveSmoothedTemp[curveIdx] = smoothed;
        
        // 4. Map temperature index (0 - 255) with proper rounding
        int tempIdx = (int)(smoothed + 0.5f);
        if (tempIdx < 0) tempIdx = 0;
        if (tempIdx > 255) tempIdx = 255;
        
        // 5. Look up target PWM from LUT
        uint8_t targetPWM = config.lut[tempIdx];
        
        uint8_t currentPWM = lastAppliedPWM[fanIdx];
        uint64_t lastTime = lastPWMUpdateTime[fanIdx];
        
        // 7. Enforce Hysteresis and Ramp Rate Limiting
        if (currentPWM > 0 && targetPWM != 0) {
            double deltaTime = (double)HF_TEMP_SAMPLE_PERIOD / 1000.0;
            if (lastTime > 0 && now > lastTime) {
                deltaTime = (double)(now - lastTime) / 1e9;
            }
            
            // Check temperature delta for hysteresis
            float tempDelta = rawSourceTemp - prevSmoothed;
            if (tempDelta < 0.0f && -tempDelta < (float)config.hysteresis) {
                targetPWM = currentPWM;
            } else {
                // Limit the speed change to config.rampRate
                float deltaPWM = (float)targetPWM - (float)currentPWM;
                float limit = (float)config.rampRate * (float)deltaTime;
                if (limit < 1.0f) limit = 1.0f; // Ensure at least 1 PWM step can change
                
                if (deltaPWM > limit) {
                    targetPWM = (uint8_t)(currentPWM + limit);
                } else if (deltaPWM < -limit) {
                    targetPWM = (uint8_t)(currentPWM - limit);
                }
            }
        }
        
        // 7.5. Apply Thermal Safety Guard (above kTHERMAL_GUARD_TEMP_C, force at least kTHERMAL_GUARD_PWM)
        if (rawSourceTemp >= kTHERMAL_GUARD_TEMP_C) {
            targetPWM = (targetPWM < kTHERMAL_GUARD_PWM) ? kTHERMAL_GUARD_PWM : targetPWM;
        }
        
        // 8. Apply PWM override to the Super I/O chip
        if (targetPWM == 0) {
            superIO->setDefaultFanControl(fanIdx);
            lastAppliedPWM[fanIdx] = 0;
        } else {
            superIO->overrideFanControl(fanIdx, targetPWM);
            lastAppliedPWM[fanIdx] = targetPWM;
        }
        lastPWMUpdateTime[fanIdx] = now;
    }
    IOLockUnlock(superIOLock);
}
```

### 5. `AMDRyzenCPUPMUserClient.cpp` — fan read/control handlers

Selector 94 (fan throttles + control mode; note it calls `updateFanControl()` every 4th read):
```cpp
        //SMC fan throttles and control mode
        case 94: {
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            if (!arguments->structureOutput)
                return kIOReturnBadArgument;
            uint64_t *dataOut = (uint64_t*) arguments->structureOutput;
            uint32_t maxLen = arguments->structureOutputSize;
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            uint32_t numFans = (uint32_t)provider->superIO->getNumberOfFans();
            uint32_t requiredSize = numFans * sizeof(uint64_t);
            arguments->structureOutputSize = requiredSize;
            UInt32 snap94 = (UInt32)provider->fanUpdateCounter;
            if ((snap94 % 4) == 0) {
                provider->superIO->updateFanControl();
            }
            uint32_t copyCount = (maxLen / sizeof(uint64_t) < numFans) ? (maxLen / sizeof(uint64_t)) : numFans;
            for (uint32_t i = 0; i < copyCount; i++) {
                dataOut[i] = provider->superIO->getFanThrottle(i) << 8 | (provider->superIO->getFanAutoControlMode(i) ? 1 : 0);
            }
            IOLockUnlock(provider->superIOLock);
            break;
        }
```

Selector 95 (override):
```cpp
        case 95: {
            if(!hasPrivilege(95))
                return kIOReturnNotPrivileged;
            if(arguments->scalarInputCount != 2)
                return kIOReturnBadArgument;
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            int fanSel = (int)arguments->scalarInput[0];
            uint8_t pwm = (uint8_t)arguments->scalarInput[1];
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->superIO->overrideFanControl(fanSel, pwm);
            IOLockUnlock(provider->superIOLock);
            break;
        }
```

Selector 96 (restore default/auto):
```cpp
        case 96: {
            if(!hasPrivilege(96))
                return kIOReturnNotPrivileged;
            if(arguments->scalarInputCount != 1)
                return kIOReturnBadArgument;
            if (!provider->superIOLock)
                return kIOReturnNoDevice;
            int fanSel = (int)arguments->scalarInput[0];
            IOLockLock(provider->superIOLock);
            if (!provider->superIO) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnNoDevice;
            }
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->superIO->setDefaultFanControl(fanSel);
            IOLockUnlock(provider->superIOLock);
            break;
        }
```

Selector 101 (curve LUT upload — the struct definition + size check):
```cpp
        case 101: {
            if(!provider)
                return kIOReturnNoDevice;
            if(!provider->superIOLock)
                return kIOReturnNoDevice;
            if(!hasPrivilege(101))
                return kIOReturnNotPrivileged;
                
            #pragma pack(push, 1)
            struct FanCurveInput {
                uint32_t curveIndex;
                uint32_t sourceSensor;
                uint32_t hysteresis;
                uint32_t rampRate;
                uint8_t lut[256];
            };
            #pragma pack(pop)
            
            if (!arguments->structureInput || arguments->structureInputSize != sizeof(FanCurveInput)) {
                return kIOReturnBadArgument;
            }
            const FanCurveInput *input = (const FanCurveInput*) arguments->structureInput;
            uint32_t idx = input->curveIndex;
            if (idx >= MAX_FAN_CURVES) {
                return kIOReturnBadArgument;
            }
            IOLockLock(provider->superIOLock);
            provider->fanCurves[idx].sourceSensor = (uint8_t)input->sourceSensor;
            provider->fanCurves[idx].hysteresis   = (uint8_t)input->hysteresis;
            provider->fanCurves[idx].rampRate     = (uint8_t)input->rampRate;
            memcpy(provider->fanCurves[idx].lut, input->lut, 256);
            IOLockUnlock(provider->superIOLock);
            break;
        }
```

Selector 102 (fan → curve mapping):
```cpp
        // Map physical fan to curve
        case 102: {
            if(!provider)
                return kIOReturnNoDevice;
            if(!hasPrivilege(102))
                return kIOReturnNotPrivileged;
            if (arguments->scalarInputCount != 2) {
                return kIOReturnBadArgument;
            }
            int fanIdx = (int)arguments->scalarInput[0];
            int curveIdx = (int)arguments->scalarInput[1];
            if (fanIdx < 0 || fanIdx >= 16 || curveIdx < -1 || curveIdx >= MAX_FAN_CURVES) {
                return kIOReturnBadArgument;
            }
            if (!provider->superIOLock) {
                return kIOReturnNoDevice;
            }
            IOLockLock(provider->superIOLock);
            if (provider->superIO && fanIdx >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->fanToCurveMap[fanIdx] = (int8_t)curveIdx;
            IOLockUnlock(provider->superIOLock);
            break;
        }
```

---

## APP SOURCE (from Sources/RyzenStatus/)

### 6. `Services/AMD/FanCurveModels.swift` — FULL

```swift
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

    static func stepPWM(current: Double, target: Double, rampPerSec: Double, dt: Double) -> Double {
        guard dt > 0, rampPerSec > 0 else { return target }
        let maxStep = rampPerSec * dt
        let diff = target - current
        if abs(diff) <= maxStep {
            return target
        }
        return current + (diff > 0 ? maxStep : -maxStep)
    }

    static func applyHysteresis(anchor: Double, raw: Double, threshold: Double) -> (effective: Double, newAnchor: Double) {
        if threshold <= 0 || abs(raw - anchor) >= threshold {
            return (effective: raw, newAnchor: raw)
        } else {
            return (effective: anchor, newAnchor: anchor)
        }
    }

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
```

### 7. `Services/AMD/AMDFanCurvePresets.swift` — FULL (kext-native presets + 272-byte packing)

```swift
import Foundation

// MARK: - Kext Fan Curve Presets (selectors 101/102)

enum AMDFanCurvePreset: String, CaseIterable, Identifiable {
    case silent = "Silent"
    case balanced = "Balanced"
    case performance = "Performance"
    case aggressive = "Aggressive"

    var id: String { rawValue }

    /// Anchor points `(temp °C, PWM 0-255)`.
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
        let padded = lut + [UInt8](repeating: 0, count: max(0, 256 - lut.count))
        data.append(contentsOf: padded.prefix(256))
        return data
    }
}
```

### 8. `Services/AMD/ProcessorModel.swift` — the fan I/O surface (the ABI bridge)

```swift
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
            let raw = (i < fanCtrls.count) ? fanCtrls[i] : 0
            let throttle = UInt8((raw >> 8) & 0xFF)
            let isAuto = (raw & 1) == 1
            
            fans.append(FanSnapshot(id: i, name: customName, rpm: rpm, throttle: throttle, isOverridden: !isAuto))
        }
        return fans
    }

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

    @discardableResult
    nonisolated func mapKextFanToCurve(fanIndex: Int, curveIndex: Int) -> kern_return_t {
        // Curve index -1 (Auto) must cross as UInt64 bit pattern, not trap.
        let rawCurve = UInt64(bitPattern: Int64(curveIndex))
        return kernelSetUInt64Status(selector: AMDKextSelector.fanToCurveMap.id, args: [UInt64(fanIndex), rawCurve])
    }
```

### 9. `Services/AMD/CPUSensorPacket.swift` — selector 100 packet (304 bytes)

```swift
/// Swift mirror of the kext's zero-copy telemetry packet
/// (`AMDRyzenCPUPowerManagement::CPUSensorPacket`, selector 100).
///
/// Layout verified against the kext source (`#pragma pack(push, 1)`):
///
///     offset  size  field
///     0       4     packagePowerW          (float)
///     4       4     packageTempC           (float)
///     8       4     numLogicalCores        (uint32_t)
///     12      4     ccdCount               (uint32_t)
///     16      32    ccdTemperatures[8]     (float)
///     48      256   coreFrequenciesMHz[64] (float)
///     ─────
///     304 bytes total
struct CPUSensorPacket: Equatable {
    static let byteSize = 304
    static let maxCCDs = 8
    static let maxCores = 64

    var packagePowerW: Float = 0
    var packageTempC: Float = 0
    var numLogicalCores: UInt32 = 0
    var ccdCount: UInt32 = 0
    var ccdTemperatures = Array(repeating: Float(0), count: maxCCDs)
    var coreFrequenciesMHz = Array(repeating: Float(0), count: maxCores)

    static func parse(_ bytes: [UInt8]) -> CPUSensorPacket? {
        guard bytes.count >= byteSize else { return nil }
        var packet = CPUSensorPacket()
        bytes.withUnsafeBytes { raw -> Void in
            guard let base = raw.baseAddress else { return }
            packet.packagePowerW = base.load(fromByteOffset: 0, as: Float.self)
            packet.packageTempC = base.load(fromByteOffset: 4, as: Float.self)
            packet.numLogicalCores = base.load(fromByteOffset: 8, as: UInt32.self)
            packet.ccdCount = base.load(fromByteOffset: 12, as: UInt32.self)
            for i in 0..<maxCCDs {
                packet.ccdTemperatures[i] = base.load(fromByteOffset: 16 + i * 4, as: Float.self)
            }
            for i in 0..<maxCores {
                packet.coreFrequenciesMHz[i] = base.load(fromByteOffset: 48 + i * 4, as: Float.self)
            }
        }
        return packet
    }
}
```

### 10. `Core/AMDKextSelectors.swift` — fan selectors (excerpt)

```swift
    // MARK: — Fan Control (via SuperIO)
    /// Fan count query — returns the number of SuperIO fan headers.
    case fanCountRead      = 91
    /// Fan speed read — per-fan RPM values.
    case fanSpeedRead      = 93

    // MARK: — Fan Curve LUT & Fan Mapping
    /// Write fan curve LUT (256 points) + hysteresis/ramp parameters to kext storage.
    case fanCurveLUTWrite  = 101
    /// Map a physical fan header to a curve slot; -1 restores automatic control.
    case fanToCurveMap     = 102
```
plus (extended constants): `fanInit = UInt32(90)`, `fanName = UInt32(92)`, `fanCtrlRead = UInt32(94)`, `fanSpeedWrite = UInt32(95)`, `fanModeWrite = UInt32(96)`.

### 11. `UI/Settings/FanCurveEditor.swift` — current UI value ranges (excerpt)

```swift
                        Slider(value: Binding(
                            get: { curve.hysteresis },
                            set: { newVal in ... curve.hysteresis = newVal }
                        ), in: 1...5, step: 1)          // hysteresis: 1...5 °C

                        Slider(value: Binding(
                            get: { curve.rampRate },
                            set: { newVal in ... curve.rampRate = newVal }
                        ), in: 1...20, step: 1)         // rampRate: 1...20 "%/s"
```

---

## Your deliverables

### 1. The numeric contract (the reference document)
For EVERY value that crosses the app↔kext boundary, state the exact semantics citing the pasted code:

- **LUT**: index = °C (0-255), value = PWM 0-255 (kext scales). Compare `AMDFanCurvePreset.interpolate` (already 0-255, `.rounded()`) with the kext lookup `(int)(smoothed + 0.5f)`. Then define the **required conversion** for the rewrite: the editor works in 0-100 % PWM — exact per-point formula (×255/100, rounding rule, clamp) to pack a custom curve into the 272-byte struct, and whether interpolating in 0-100 then converting differs from converting anchors then interpolating in 0-255.
- **rampRate**: kext = PWM units/s on 0-255 (`limit = config.rampRate * deltaTime`, floor `limit < 1.0f → 1.0f`, guard `currentPWM > 0 && targetPWM != 0`). UI = 1-20 "%/s". Give the exact conversion (×255/100, `round`, clamp 1-255). Cross-check against the shipped kext presets (3/5/8/12) and kext default (5) — note the presets are already on the kext scale, proving the custom-curve path must convert.
- **hysteresis**: °C on both sides (UI 1-5, kext `uint8`); no conversion. Confirm how the kext applies it (`tempDelta = rawSourceTemp - prevSmoothed`, `tempDelta < 0.0f && -tempDelta < hysteresis` → hold) — note it only holds on FALLING temperature and compares raw vs the PREVIOUS smoothed value.
- **EMA**: alpha 0.2, init 40.0; interaction with hysteresis; what it means for response time (state the time constant in timer periods).
- **Thermal guard**: `kTHERMAL_GUARD_TEMP_C = 85.0f`, `kTHERMAL_GUARD_PWM = 200`. Note the guard uses RAW temp, not smoothed.
- **Critical behavior**: `targetPWM == 0 → setDefaultFanControl` — a 0-PWM curve point returns the fan to BIOS control instead of forcing it off. Confirm and flag.
- **Read-backs**: selector 94 `throttle<<8 | autoFlag` (exact bit decode), RPM via 93, app cap 9999, `getFanThrottle` is the current duty (0-255). GPU temp SP78 (`Int16(bitPattern:)/256.0` — from repo, not in excerpts; treat as verified fact), CPU package temp from selector 100 (304-byte layout above).
- **Packing**: `packedData()` byte-for-byte vs kext `#pragma pack(1) FanCurveInput` (272 bytes, little-endian); verify the app-side `AMDFanCurveInput` matches the kext struct field-for-field.
- **Bounds**: fanIndex `< 16` AND `< getNumberOfFans()`; curveIndex -1..3; how the app must clamp to avoid `kIOReturnBadArgument`.

Format each row: **Value | App/UI scale | Kext scale | Conversion | Rounding | Clamp | Evidence (excerpt #)**.

### 2. Findings — scale/rounding/threshold bugs in the CURRENT app code
Audit excerpt #6 (`FanCurveModels`) against the kext driver:
- `generateRPMLUT()` produces 0-100 % PWM while `interpolate()` (excerpt #7) produces 0-255 — confirm the two LUT paths disagree on scale.
- `applyHysteresis` (app) vs the kext's rule (excerpt #4) — same behavior? Different?
- `stepPWM` (app, 0-100 scale) vs kext ramp (0-255 scale).
- Rounding/truncation: `Int(effectiveTemp)` vs kext's `(int)(smoothed + 0.5f)`; the old loop's `(clampedPWM / 100.0) * 255.0`.
- Edge cases: empty curve, single-point curve, points with equal temps, temp beyond anchors, PWM 0 (the `setDefaultFanControl` surprise above), the `currentPWM > 0` guard.

Severity per finding (must-fix / should-fix / note) + the exact fix to bake into the rewrite.

### 3. The verification checklist
PASS/FAIL items keyed to the excerpts (e.g. "the 272-byte pack in the new code must produce bytes equal to a hand-built FanCurveInput for a known LUT").

## Report format
1) Numeric contract table · 2) Findings with severity · 3) Verification checklist · 4) Anything in the kext driver that looks like a latent bug (report, don't fix). Every claim cites an excerpt number. No fabrication: anything not in the excerpts is marked "not verifiable from provided excerpts".
