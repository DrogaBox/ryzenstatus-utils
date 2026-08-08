// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

enum CPUTemperaturePlatform: Equatable {
    case appleM1Family
    case appleM2Family
    case appleM3Family
    case appleM4Family
    case appleM5Family
    case generic
}

struct CachedSensorReading {
    var value: Double
    var updatedAt: TimeInterval
    var missedSamples: Int
}

protocol PlatformDetector {
    func currentPlatform() -> CPUTemperaturePlatform
}

struct SysctlPlatformDetector: PlatformDetector {
    func currentPlatform() -> CPUTemperaturePlatform {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return .generic
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return .generic
        }
        return TemperatureSensorSelector.platform(brandString: String(cString: buffer))
    }
}

enum TemperatureSensorSelector {
    static let minimumChipTemperature = 10.0

#if arch(arm64)
    private static let appleM1CPUCoreKeys: Set<String> = [
        "Tp09", "Tp0T",
        "Tp01", "Tp05", "Tp0D", "Tp0H",
        "Tp0L", "Tp0P", "Tp0X", "Tp0b",
    ]

    private static let appleM2CPUCoreKeys: Set<String> = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]

    private static let appleM3CPUCoreKeys: Set<String> = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49",
        "Tf4A", "Tf4B", "Tf4D", "Tf4E",
    ]

    private static let appleM4CPUCoreKeys: Set<String> = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ]

    private static let appleM5CPUCoreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C",
        "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X",
        "Tp0a", "Tp0d", "Tp0g", "Tp0j",
        "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]
#endif

    static func platform(brandString: String?) -> CPUTemperaturePlatform {
        let brand = brandString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#if arch(arm64)
        switch appleSiliconGeneration(in: brand) {
        case 1: return .appleM1Family
        case 2: return .appleM2Family
        case 3: return .appleM3Family
        case 4: return .appleM4Family
        case 5: return .appleM5Family
        default: return .generic
        }
#else
        return .generic
#endif
    }

    static func currentPlatform(detector: PlatformDetector = SysctlPlatformDetector()) -> CPUTemperaturePlatform {
        detector.currentPlatform()
    }

    static func displayedCPUTemperature(readings: [(key: String, value: Double)],
                                        platform: CPUTemperaturePlatform) -> Double? {
        let valid = readings.filter { isPlausibleTemperature($0.value) }
        guard !valid.isEmpty else { return nil }

        let core = valid.filter { isCPUCoreKey($0.key, platform: platform) }
        if let value = core.map({ $0.value }).max() {
            return value
        }
        return valid.map { $0.value }.max()
    }

    static func hasCPUCoreSet(platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
        case .appleM1Family, .appleM2Family, .appleM3Family, .appleM4Family, .appleM5Family, .generic:
            return true
        }
    }

    static func isCPUCoreKey(_ key: String, platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
#if arch(arm64)
        case .appleM1Family:
            return appleM1CPUCoreKeys.contains(key)
        case .appleM2Family:
            return appleM2CPUCoreKeys.contains(key)
        case .appleM3Family:
            return appleM3CPUCoreKeys.contains(key)
        case .appleM4Family:
            return appleM4CPUCoreKeys.contains(key)
        case .appleM5Family:
            return appleM5CPUCoreKeys.contains(key)
#else
        case .appleM1Family, .appleM2Family, .appleM3Family, .appleM4Family, .appleM5Family:
            return false
#endif
        case .generic:
            return [
                // Intel legacy
                "TC0D", "TC0P", "TC0C", "TCXC", "TC0E", "TC0F",
                // AMD Ryzen (SMCAMDProcessor.kext)
                "Tdie", "Tctl", "Tccd1", "Tccd2", "Tccd3", "Tccd4",
                "TSI0", "TSI1", "TC0R"
            ].contains(key)
        }
    }

#if arch(arm64)
    private static func appleSiliconGeneration(in brand: String) -> Int? {
        guard brand.hasPrefix("Apple M") else { return nil }
        let remainder = brand.dropFirst("Apple M".count)
        guard let first = remainder.first, let generation = Int(String(first)) else { return nil }
        guard generation >= 1, generation <= 5 else { return nil }
        let afterGeneration = remainder.dropFirst()
        guard afterGeneration.isEmpty || afterGeneration.first == " " else { return nil }
        return generation
    }
#endif

    static func stabilizedTemperature(_ reading: Double?,
                                      cache: inout CachedSensorReading?,
                                      now: TimeInterval,
                                      maxAge: TimeInterval,
                                      minimum: Double = 1) -> Double? {
        if let reading, reading > 1, reading >= minimum, reading < 125 {
            cache = CachedSensorReading(value: reading, updatedAt: now, missedSamples: 0)
            return reading
        }
        guard var cached = cache else { return nil }
        cached.missedSamples += 1
        if cached.missedSamples <= 4, now - cached.updatedAt <= maxAge {
            cache = cached
            return cached.value
        }
        cache = nil
        return nil
    }

    private static func isPlausibleTemperature(_ value: Double) -> Bool {
        value >= minimumChipTemperature && value < 125
    }
}
