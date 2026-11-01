// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

// MARK: - Capabilities (selector 62)

/// What this CPU accepts, as the kext reports it from its per-family SMU
/// command set, its idle loop and its CPPC probe. The single source the
/// power and overclocking views gate their controls on.
struct AMDPowerCapabilities: OptionSet, Equatable, Sendable {
    let rawValue: UInt64

    static let pptTdcEdcLimits = AMDPowerCapabilities(rawValue: 1 << 0)
    /// APUs: the PPT value is written as the STAPM, fast and slow limits.
    static let apuPowerLimit   = AMDPowerCapabilities(rawValue: 1 << 1)
    static let chtcLimit       = AMDPowerCapabilities(rawValue: 1 << 2)
    static let pboScalar       = AMDPowerCapabilities(rawValue: 1 << 3)
    static let ocMode          = AMDPowerCapabilities(rawValue: 1 << 4)
    static let ocPerCcd        = AMDPowerCapabilities(rawValue: 1 << 5)
    static let ocVid           = AMDPowerCapabilities(rawValue: 1 << 6)
    static let coPerCore       = AMDPowerCapabilities(rawValue: 1 << 7)
    static let coAllCores      = AMDPowerCapabilities(rawValue: 1 << 8)
    static let boostLimit      = AMDPowerCapabilities(rawValue: 1 << 9)
    static let pmTable         = AMDPowerCapabilities(rawValue: 1 << 10)
    static let c6Idle          = AMDPowerCapabilities(rawValue: 1 << 11)
    static let epp             = AMDPowerCapabilities(rawValue: 1 << 12)

    /// Any power limit at all (selector 41).
    var hasPowerLimits: Bool { !isDisjoint(with: [.pptTdcEdcLimits, .apuPowerLimit]) }
}

/// The capability report plus the values this driver wrote this boot (the
/// SMU cannot read them back).
struct AMDPowerControlState: Equatable, Sendable {
    let capabilities: AMDPowerCapabilities
    /// Last OC VID written, nil when none.
    let ocVid: UInt32?
    /// Last all-core Curve Optimizer margin written, nil when none.
    let curveOptimizerAll: Int8?
    /// Last boost ceiling written in MHz, nil when none.
    let boostLimitMHz: UInt32?

    init(raw: [UInt64]) {
        capabilities = AMDPowerCapabilities(rawValue: raw.first ?? 0)
        let vid = raw.count > 1 ? UInt32(truncatingIfNeeded: raw[1]) : 0
        ocVid = vid == 0 ? nil : vid
        let coSet = raw.count > 3 && raw[3] == 1
        curveOptimizerAll = coSet ? Int8(truncatingIfNeeded: raw[2]) : nil
        let boost = raw.count > 4 ? UInt32(truncatingIfNeeded: raw[4]) : 0
        boostLimitMHz = boost == 0 ? nil : boost
    }
}

// MARK: - OC voltage

/// SVI2 VID ↔ volts (1.55 V − VID × 6.25 mV), the encoding of the OC VID
/// command on AM4. The kext accepts VID 16…120 (1.45 V … 0.80 V).
enum AMDOcVoltage {
    static let vidRange: ClosedRange<UInt32> = 16...120
    /// Millivolt range the slider offers, matching `vidRange`.
    static let millivoltRange: ClosedRange<Int> = 800...1450

    static func vid(millivolts: Int) -> UInt32 {
        let clamped = min(millivoltRange.upperBound, max(millivoltRange.lowerBound, millivolts))
        // 1550 mV − VID × 6.25 mV, rounded to the nearest step.
        let steps = (Double(1550 - clamped) / 6.25).rounded()
        return min(vidRange.upperBound, max(vidRange.lowerBound, UInt32(steps)))
    }

    static func millivolts(vid: UInt32) -> Int {
        Int((1550.0 - Double(vid) * 6.25).rounded())
    }
}

// MARK: - Deep C-state policy (selector 34)

/// The kext's CC6 idle state. Kexts before 3.40.0 report only the first two
/// fields; the rest then read as unavailable.
struct AMDCStatePolicy: Equatable, Sendable {
    /// Idle cores stay out of CC6.
    let c6Off: Bool
    /// Raw CSTATE_ADDR (MSR C001_0073).
    let cstateAddress: UInt64
    /// CC6 idle switched on (selector 61).
    let c6On: Bool
    /// Firmware C-state IO base, 0 when none is usable.
    let ioBase: UInt64
    /// CC6 idle can be switched on.
    let c6Available: Bool
    /// CC6 forbidden by the `amdcstate=1` boot argument.
    let forbiddenByBootArg: Bool

    init(raw: [UInt64], count: Int) {
        c6Off = count > 0 && raw[0] == 1
        cstateAddress = count > 1 ? raw[1] : 0
        c6On = count > 2 && raw[2] == 1
        ioBase = count > 3 ? raw[3] : 0
        c6Available = count > 4 && raw[4] == 1
        forbiddenByBootArg = count > 5 && raw[5] == 1
    }
}

// MARK: - ACPI CPPC report (selector 63)

/// What the kext found while looking for CPPC in ACPI (_CPC + PCCT), shown
/// in Hardware Validation so a missing EPP path explains itself.
struct AMDAcpiCppcReport: Equatable, Sendable {
    enum Failure: UInt32, Sendable {
        case none = 0, noAcpiPlane, noCpc, malformedCpc, notPcc, noPcct, malformedPcct,
             mapFailed, processorCountMismatch
    }

    struct Register: Equatable, Sendable {
        let isRegister: Bool
        let space: UInt32
        let bitWidth: UInt32
        let bitOffset: UInt32
        let subspace: UInt32
        let offset: UInt32
        let integer: UInt32
    }

    struct Subspace: Equatable, Sendable {
        let type: UInt32
        let base: UInt64
        let length: UInt32
        let doorbellSpace: UInt32
        let doorbellAddress: UInt32
        let latencyUs: UInt32
    }

    static let registerNames = ["Highest", "Nominal", "Lowest non-linear", "Lowest", "Desired",
                                "Minimum", "Maximum", "CPPC enable", "Autonomous", "EPP"]
    static let wordCount = 7 + registerNames.count * 6 + 8 * 8

    let supported: Bool
    let failure: Failure?
    let cpuCount: UInt32
    let revision: UInt32
    let lastResult: Int32
    let lastStatus: UInt32
    let msrCppc: Bool
    let registers: [Register]
    let subspaces: [Int: Subspace]

    init?(words: [UInt32]) {
        guard words.count >= Self.wordCount else { return nil }
        supported = words[0] == 1
        failure = Failure(rawValue: words[1])
        cpuCount = words[2]
        revision = words[3]
        lastResult = Int32(bitPattern: words[4])
        lastStatus = words[5]
        msrCppc = words[6] == 1
        var w = 7
        var regs: [Register] = []
        for _ in Self.registerNames {
            regs.append(Register(isRegister: words[w] == 1, space: words[w + 1],
                                 bitWidth: words[w + 2] & 0xFF, bitOffset: (words[w + 2] >> 8) & 0xFF,
                                 subspace: words[w + 3], offset: words[w + 4], integer: words[w + 5]))
            w += 6
        }
        registers = regs
        var spaces: [Int: Subspace] = [:]
        for id in 0..<8 {
            if words[w] == 1 {
                spaces[id] = Subspace(type: words[w + 1],
                                      base: UInt64(words[w + 2]) | (UInt64(words[w + 3]) << 32),
                                      length: words[w + 4], doorbellSpace: words[w + 5],
                                      doorbellAddress: words[w + 6], latencyUs: words[w + 7])
            }
            w += 8
        }
        subspaces = spaces
    }
}

// MARK: - Kext calls (selectors 34, 61–67)

extension ProcessorModel {
    nonisolated func getPowerControlState() -> AMDPowerControlState? {
        var output = [UInt64](repeating: 0, count: 5)
        var outputCount: UInt32 = 5
        let res = safeIOConnectCallMethod(AMDKextSelector.powerCapabilities.id, nil, 0, nil, 0,
                                          &output, &outputCount, nil, nil)
        guard res == KERN_SUCCESS, outputCount >= 1 else { return nil }
        return AMDPowerControlState(raw: Array(output.prefix(Int(outputCount))))
    }

    /// nil when the kernel connection is down or the kext predates selector 34.
    nonisolated func getCStatePolicy() -> AMDCStatePolicy? {
        var output = [UInt64](repeating: 0, count: 6)
        var outputCount: UInt32 = 6
        let res = safeIOConnectCallMethod(AMDKextSelector.cStatePolicy.id, nil, 0, nil, 0,
                                          &output, &outputCount, nil, nil)
        guard res == KERN_SUCCESS, outputCount >= 1 else { return nil }
        return AMDCStatePolicy(raw: output, count: Int(outputCount))
    }

    @discardableResult
    nonisolated func setC6Idle(_ on: Bool) -> kern_return_t {
        var input: [UInt64] = [on ? 1 : 0]
        return safeIOConnectCallMethod(AMDKextSelector.c6IdleWrite.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    @discardableResult
    nonisolated func setOcVid(_ vid: UInt32) -> kern_return_t {
        var input: [UInt64] = [UInt64(vid)]
        return safeIOConnectCallMethod(AMDKextSelector.ocVidWrite.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    @discardableResult
    nonisolated func setCurveOptimizerAll(_ offset: Int8) -> kern_return_t {
        var input: [UInt64] = [UInt64(bitPattern: Int64(offset))]
        return safeIOConnectCallMethod(AMDKextSelector.curveOptimizerAllWrite.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    @discardableResult
    nonisolated func setBoostLimit(mhz: UInt32) -> kern_return_t {
        var input: [UInt64] = [UInt64(mhz)]
        return safeIOConnectCallMethod(AMDKextSelector.boostLimitWrite.id, &input, 1, nil, 0, nil, nil, nil, nil)
    }

    nonisolated func getAcpiCppcReport() -> AMDAcpiCppcReport? {
        var words = [UInt32](repeating: 0, count: AMDAcpiCppcReport.wordCount)
        var size = words.count * MemoryLayout<UInt32>.size
        let res = words.withUnsafeMutableBytes { buffer in
            safeIOConnectCallMethod(AMDKextSelector.acpiCppcReport.id, nil, 0, nil, 0,
                                    nil, nil, buffer.baseAddress, &size)
        }
        guard res == KERN_SUCCESS else { return nil }
        return AMDAcpiCppcReport(words: words)
    }

    /// One PCC read: (highest, nominal, lowest non-linear, lowest, EPP,
    /// channel status), or nil when the kext refused or timed out.
    nonisolated func probeAcpiCppc() -> [UInt64]? {
        var output = [UInt64](repeating: 0, count: 6)
        var outputCount: UInt32 = 6
        let res = safeIOConnectCallMethod(AMDKextSelector.acpiCppcProbe.id, nil, 0, nil, 0,
                                          &output, &outputCount, nil, nil)
        guard res == KERN_SUCCESS, outputCount == 6 else { return nil }
        return output
    }
}
