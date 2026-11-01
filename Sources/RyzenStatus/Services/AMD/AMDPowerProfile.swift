// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

// MARK: - Profile

/// One set of power settings. A nil field is left as the CPU has it, and a
/// field the CPU does not accept (selector 62) is skipped and reported.
struct AMDPowerProfile: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var c6Idle: Bool?
    var cpb: Bool?
    /// Zen 1/2 only: limits the legacy P-states the idle loop steps through.
    var lpm: Bool?
    /// Package power in W; on APUs the STAPM, fast and slow limits.
    var pptW: Int?
    var tdcA: Int?
    var edcA: Int?
    var chtcC: Int?
    /// PBO scalar in %×100 (100 = 1x … 1000 = 10x).
    var pboScalarX100: Int?
    /// All-core Curve Optimizer margin, −30…+30.
    var coAll: Int?
    var boostLimitMHz: Int?
    /// Energy performance preference, 0 (performance) … 255 (power saving).
    var epp: UInt8?

    var id: String { name }

    /// The levers this profile sets, in the order they are written.
    var levers: [AMDPowerLever] {
        var out: [AMDPowerLever] = []
        if c6Idle != nil { out.append(.c6Idle) }
        if cpb != nil { out.append(.cpb) }
        if pptW != nil { out.append(.powerLimits) }
        if chtcC != nil { out.append(.chtc) }
        if pboScalarX100 != nil { out.append(.pboScalar) }
        if coAll != nil { out.append(.curveOptimizer) }
        if boostLimitMHz != nil { out.append(.boostLimit) }
        if epp != nil { out.append(.epp) }
        if lpm != nil { out.append(.lpm) }
        return out
    }
}

extension AMDPowerProfile {
    /// One line for a preset card: the levers this CPU accepts, with their
    /// values ("PPT 95 W · TDC 130 A · EDC 130 A · CC6 · Boost on · EPP …").
    func summary(caps: AMDPowerCapabilities, cpbSupported: Bool,
                 strings s: AMDPowerFeatureStrings) -> String {
        var parts: [String] = []
        if let ppt = pptW, caps.hasPowerLimits {
            parts.append("PPT \(ppt) \(s.pboUnitWatts)")
            if caps.contains(.pptTdcEdcLimits), let tdc = tdcA, let edc = edcA {
                parts.append("TDC \(tdc) \(s.pboUnitAmps)")
                parts.append("EDC \(edc) \(s.pboUnitAmps)")
            }
        }
        if c6Idle == true, caps.contains(.c6Idle) { parts.append("CC6") }
        if let on = cpb, cpbSupported { parts.append(on ? s.presetBoostOn : s.presetBoostOff) }
        if let epp, caps.contains(.epp) {
            switch AMDPowerPreset.snapEPP(epp) {
            case 0: parts.append("EPP \(s.perfMax)")
            case 85: parts.append("EPP \(s.perfBalPlus)")
            case 170: parts.append("EPP \(s.perfBalMinus)")
            default: parts.append("EPP \(s.perfEco)")
            }
        }
        return parts.joined(separator: " · ")
    }
}

enum AMDPowerLever: String, CaseIterable, Sendable {
    case c6Idle, cpb, powerLimits, chtc, pboScalar, curveOptimizer, boostLimit, epp, lpm
}

/// Per-lever outcome of applying a profile.
struct AMDPowerProfileApplyResult: Sendable {
    /// kext status per lever written; levers the CPU lacks are absent.
    var statuses: [(lever: AMDPowerLever, status: kern_return_t)] = []
    /// Levers the profile set but this CPU or kext does not accept.
    var skipped: [AMDPowerLever] = []

    var succeeded: Bool { statuses.allSatisfy { $0.status == KERN_SUCCESS } }

    /// True when the kext rejected any write with `kIOReturnNotPrivileged`
    /// (writes need root or the `-amdpnopchk` boot-arg).
    var privilegeDenied: Bool {
        statuses.contains { $0.status == ProcessorModel.kIOReturnNotPrivilegedCode }
    }

    /// Reason for the first failed lever; a privilege denial wins, being the
    /// one the user can act on.
    var firstFailureMessage: String? {
        if privilegeDenied {
            return ProcessorModel.privilegeHint(for: ProcessorModel.kIOReturnNotPrivilegedCode)
        }
        return statuses.first { $0.status != KERN_SUCCESS }.flatMap { ProcessorModel.privilegeHint(for: $0.status) }
    }
}

// MARK: - Built-in presets per CPU class

/// The ZenTune preset class of a CPU (ZenTune engine/presets.py), from its
/// brand string: desktop parts by suffix and series, APUs by suffix.
enum AMDPresetClass: Equatable, Sendable {
    case desktopX3D, desktopE, desktopX9(preRaphael: Bool), desktopX, desktopStandard
    case apuDesktopG, apuDesktopGE
    case apuMobileU, apuMobileH, apuMobileHS, apuMobileHX
    /// No published limits: the presets set boost, CC6 and EPP only.
    case other

    /// - Parameters:
    ///   - brand: `machdep.cpu.brand_string`, e.g. "AMD Ryzen 9 5900XT 16-Core Processor".
    ///   - isApu: the kext's command set takes APU (STAPM/fast/slow) limits.
    static func classify(brand: String, family: Int, model: Int, isApu: Bool) -> AMDPresetClass {
        // ZenTune splits the name after "AMD Ryzen": series, then model.
        var name = brand.replacingOccurrences(of: "AMD", with: "")
        name = name.replacingOccurrences(of: "Ryzen", with: "")
        let parts = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let series = parts.count >= 2 ? parts[0] : ""
        let part = parts.count >= 2 ? parts[1] : (parts.first ?? "")

        if isApu {
            // Raven Ridge, Picasso and Dali predate Matisse in ZenTune's list.
            let preMatisse = family == 0x17 && model < 0x30
            if part.contains("U") || part.contains("e") || part.contains("Ce")
                || (!preMatisse && part.contains("AI") && !part.contains("HX")) {
                return .apuMobileU
            }
            if !preMatisse && part.contains("HX") { return .apuMobileHX }
            if !preMatisse && part.contains("HS") { return .apuMobileHS }
            if part.contains("H") { return .apuMobileH }
            if part.contains("GE") { return .apuDesktopGE }
            if part.contains("G") { return .apuDesktopG }
            return .other
        }
        if part.contains("X3D") { return .desktopX3D }
        if part.contains("E") { return .desktopE }
        // Raphael and everything after it (AM5) use the larger AM5 limits.
        let preRaphael = family < 0x19 || (family == 0x19 && model < 0x60)
        if part.contains("X") && series.contains("9") { return .desktopX9(preRaphael: preRaphael) }
        if part.contains("X") { return .desktopX }
        return family >= 0x17 ? .desktopStandard : .other
    }

    /// (PPT W, TDC A, EDC A) per preset, ZenTune's values. APUs give the
    /// STAPM limit, the one the kext writes as STAPM, fast and slow.
    func limits(_ preset: AMDPowerPreset) -> (ppt: Int, tdc: Int?, edc: Int?)? {
        let table: [(Int, Int?, Int?)]
        switch self {
        case .desktopX3D: table = [(65, 90, 90), (85, 120, 120), (105, 142, 142), (140, 190, 190)]
        case .desktopE: table = [(45, 90, 90), (65, 90, 90), (95, 122, 122), (105, 142, 142)]
        case .desktopX9(let preRaphael):
            table = preRaphael
                ? [(65, 90, 90), (95, 130, 130), (125, 142, 142), (170, 230, 230)]
                : [(65, 90, 90), (105, 145, 145), (145, 210, 210), (230, 310, 310)]
        case .desktopX: table = [(65, 90, 90), (88, 125, 125), (105, 142, 142), (140, 190, 190)]
        case .desktopStandard: table = [(45, 90, 90), (65, 90, 90), (88, 125, 125), (105, 142, 142)]
        case .apuDesktopG: table = [(15, nil, nil), (65, nil, nil), (80, nil, nil), (85, nil, nil)]
        case .apuDesktopGE: table = [(15, nil, nil), (45, nil, nil), (55, nil, nil), (65, nil, nil)]
        case .apuMobileU: table = [(6, nil, nil), (22, nil, nil), (28, nil, nil), (30, nil, nil)]
        case .apuMobileH: table = [(6, nil, nil), (45, nil, nil), (55, nil, nil), (65, nil, nil)]
        case .apuMobileHS: table = [(6, nil, nil), (35, nil, nil), (45, nil, nil), (55, nil, nil)]
        case .apuMobileHX: table = [(6, nil, nil), (55, nil, nil), (78, nil, nil), (85, nil, nil)]
        case .other: return nil
        }
        let index = AMDPowerPreset.allCases.firstIndex(of: preset) ?? 1
        return table[index]
    }

    /// Tctl/cHTC limit of every preset: 85 °C on X3D parts, 95 °C elsewhere.
    var tctlCelsius: Int? {
        switch self {
        case .other: return nil
        case .desktopX3D: return 85
        default: return 95
        }
    }
}

extension AMDPowerPreset {
    /// The full profile this preset applies on a CPU of `cpuClass`: ZenTune's
    /// limits plus the boost, CC6, EPP and (Zen 1/2) LPM choices.
    func profile(for cpuClass: AMDPresetClass) -> AMDPowerProfile {
        let limits = cpuClass.limits(self)
        return AMDPowerProfile(
            name: rawValue,
            c6Idle: c6Desired,
            cpb: cpbEnabled,
            lpm: lpmEnabled,
            pptW: limits?.ppt,
            tdcA: limits?.tdc,
            edcA: limits?.edc,
            chtcC: cpuClass.tctlCelsius,
            epp: eppValue
        )
    }
}

// MARK: - Profile files

/// The app's own export format for custom profiles.
enum AMDPowerProfileFile {
    static let format = "RyzenStatus Power Profiles"

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let profiles: [AMDPowerProfile]
    }

    static func encode(_ profiles: [AMDPowerProfile]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Envelope(format: format, version: 1, profiles: profiles))
    }

    /// Profiles from the app's own file or from a ZenTune backup, with the
    /// ZenTune keys that had no equivalent; nil when the file is neither.
    static func decode(_ data: Data) -> ZenTuneBackupImport.Outcome? {
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.format == format {
            return ZenTuneBackupImport.Outcome(profiles: envelope.profiles)
        }
        return ZenTuneBackupImport.parse(data)
    }
}

// MARK: - ZenTune backup import

/// Reads the custom presets of a ZenTune backup ("ZenTune Preset Backup",
/// `~/zentune_backup.json`): each record maps field keys to
/// `{"enabled": Bool, "value": Number}`. Only enabled fields this app can
/// apply become profile fields; the rest are listed as skipped.
enum ZenTuneBackupImport {
    struct Outcome: Sendable {
        var profiles: [AMDPowerProfile] = []
        /// ZenTune keys that were enabled but have no equivalent here.
        var skippedKeys: Set<String> = []
    }

    static func parse(_ data: Data) -> Outcome? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "ZenTune Preset Backup",
              let records = root["custom_presets"] as? [[String: Any]] else { return nil }
        var outcome = Outcome()
        for record in records {
            guard let name = record["name"] as? String, !name.isEmpty else { continue }
            var profile = AMDPowerProfile(name: name)
            for (key, raw) in record where key != "name" {
                guard let field = raw as? [String: Any], field["enabled"] as? Bool == true,
                      let value = (field["value"] as? NSNumber)?.doubleValue else { continue }
                switch key {
                case "tctl_temp": profile.chtcC = Int(value)
                case "ppt_limit": profile.pptW = Int(value)
                case "stapm_limit": if profile.pptW == nil { profile.pptW = Int(value) }
                case "tdc_limit": profile.tdcA = Int(value)
                case "edc_limit": profile.edcA = Int(value)
                case "pbo_scalar": profile.pboScalarX100 = Int((value * 100).rounded())
                case "coall": profile.coAll = max(-30, min(30, Int(value)))
                default: outcome.skippedKeys.insert(key)
                }
            }
            outcome.profiles.append(profile)
        }
        return outcome
    }
}

// MARK: - Applying

extension ProcessorModel {
    /// The ZenTune preset class of this CPU; APUs are told apart by the
    /// kext's command set (selector 62).
    func presetClass() -> AMDPresetClass {
        let isApu = getPowerControlState()?.capabilities.contains(.apuPowerLimit) ?? false
        return AMDPresetClass.classify(brand: Self.sysctlString(key: "machdep.cpu.brand_string"),
                                       family: cpuFamily, model: cpuModel, isApu: isApu)
    }
    /// Applies a built-in preset with this CPU's limits.
    func applyPreset(_ preset: AMDPowerPreset) -> AMDPowerProfileApplyResult {
        applyPowerProfile(preset.profile(for: presetClass()))
    }
    /// Writes `profile` lever by lever in a fixed order (CC6, boost, power
    /// limits, cHTC, scalar, Curve Optimizer, boost ceiling, EPP, LPM). A
    /// lever this CPU does not accept is skipped, never sent.
    func applyPowerProfile(_ profile: AMDPowerProfile) -> AMDPowerProfileApplyResult {
        var result = AMDPowerProfileApplyResult()
        let caps = getPowerControlState()?.capabilities ?? []
        let legacyPstate = cpuProfile.legacyPstateAllowed
        let cpbSupported = getCPB().first ?? false

        func record(_ lever: AMDPowerLever, supported: Bool, _ write: () -> kern_return_t) {
            if supported { result.statuses.append((lever, write())) } else { result.skipped.append(lever) }
        }

        if let on = profile.c6Idle {
            record(.c6Idle, supported: caps.contains(.c6Idle)) { setC6Idle(on) }
        }
        if let on = profile.cpb {
            record(.cpb, supported: cpbSupported) { setCPB(enabled: on) }
        }
        if let ppt = profile.pptW {
            let tdc = profile.tdcA ?? 0, edc = profile.edcA ?? 0
            let desktop = caps.contains(.pptTdcEdcLimits) && tdc > 0 && edc > 0
            record(.powerLimits, supported: desktop || caps.contains(.apuPowerLimit)) {
                // APUs ignore TDC/EDC; the kext still validates them.
                setPBOLimits(pptMilliwatts: ppt * 1000,
                             tdcMilliamps: (desktop ? tdc : 100) * 1000,
                             edcMilliamps: (desktop ? edc : 100) * 1000)
            }
        }
        if let celsius = profile.chtcC {
            record(.chtc, supported: caps.contains(.chtcLimit)) { setCHTCLimit(celsius: celsius) }
        }
        if let scalar = profile.pboScalarX100 {
            record(.pboScalar, supported: caps.contains(.pboScalar)) { setPBOScalar(percentX100: scalar) }
        }
        if let margin = profile.coAll {
            record(.curveOptimizer, supported: caps.contains(.coAllCores)) {
                setCurveOptimizerAll(Int8(max(-30, min(30, margin))))
            }
        }
        if let mhz = profile.boostLimitMHz {
            record(.boostLimit, supported: caps.contains(.boostLimit)) { setBoostLimit(mhz: UInt32(mhz)) }
        }
        if let epp = profile.epp {
            record(.epp, supported: caps.contains(.epp)) { setCPPCEPPValue(epp: epp) }
        }
        if let on = profile.lpm {
            record(.lpm, supported: legacyPstate) {
                // PPM and LPM share one kext limit: switch the other off first.
                let off = setPPM(enabled: false)
                let res = setLPM(enabled: on)
                return off == KERN_SUCCESS ? res : off
            }
        }
        return result
    }
}
