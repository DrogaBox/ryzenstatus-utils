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
    /// CPPC min/max perf limits, selectors 68/69 (kext 3.41.0+).
    static let cppcLimits      = AMDPowerCapabilities(rawValue: 1 << 13)

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

// MARK: - CPPC performance range (selectors 68/69)

/// The CPU's CPPC performance scale and the min/max limits the kext holds,
/// the macOS side of Linux amd-pstate's cpuinfo_min_freq /
/// amd_pstate_lowest_nonlinear_freq / scaling_min_freq / scaling_max_freq.
/// Perf units are abstract; like amd-pstate, MHz = perf × base clock ÷
/// nominal perf, with the base clock taken from P-state 0.
struct AMDCppcRange: Equatable, Sendable {
    enum Mechanism: UInt64, Sendable { case none = 0, msr = 1, acpi = 2 }

    let mechanism: Mechanism
    let lowest: UInt8
    let lowestNonlinear: UInt8
    let nominal: UInt8
    let highest: UInt8
    /// 0 = the CPU's own bound.
    let minLimit: UInt8
    let maxLimit: UInt8
    /// CPPC autonomous mode is engaged, so the limits reach the cores.
    let limitsInForce: Bool
    /// P-state 0 (base clock) in MHz, nil when the kext has none.
    let baseMHz: Double?

    init(raw: [UInt64], count: Int, baseMHz: Double?) {
        func byte(_ i: Int) -> UInt8 { i < count ? UInt8(truncatingIfNeeded: raw[i]) : 0 }
        mechanism = Mechanism(rawValue: count > 0 ? raw[0] : 0) ?? .none
        lowest = byte(1)
        lowestNonlinear = byte(2)
        nominal = byte(3)
        highest = byte(4)
        minLimit = byte(5)
        maxLimit = byte(6)
        limitsInForce = count > 7 && raw[7] == 1
        if let baseMHz, baseMHz.isFinite, baseMHz >= 400 { self.baseMHz = baseMHz } else { self.baseMHz = nil }
    }

    /// The perf scale is known and usable for a MHz slider.
    var isKnown: Bool {
        mechanism != .none && lowest > 0 && nominal >= lowest && highest >= nominal && baseMHz != nil
    }

    /// The clock a perf level stands for, rounded to 25 MHz.
    func mhz(perf: UInt8) -> Int? {
        guard let baseMHz, nominal > 0 else { return nil }
        let value = Double(perf) * baseMHz / Double(nominal)
        return Int((value / 25).rounded()) * 25
    }

    /// The highest perf level whose clock does not pass `mhz`, kept inside
    /// lowest…highest.
    func perf(atMost mhz: Int) -> UInt8 {
        guard let baseMHz, nominal > 0 else { return highest }
        let raw = (Double(mhz) * Double(nominal) / baseMHz).rounded(.down)
        return UInt8(min(max(raw, Double(lowest)), Double(highest)))
    }

    /// The idle limit slider: from the lowest clock up to the base clock.
    var idleLimitRangeMHz: ClosedRange<Int>? {
        guard isKnown, let low = mhz(perf: lowest), let base = mhz(perf: nominal), base > low else { return nil }
        return low...base
    }
}

/// When the idle clock limit is written. Kept apart from the service so it
/// can be tested.
enum AMDIdleClockLimitPolicy {
    /// The CPPC max perf for one Auto EPP decision: the limit while Auto EPP
    /// holds Eco (the CPU is idle), 0 (no limit) otherwise or when the limit
    /// is off, the range is unknown or the limit would not lower anything.
    static func maxPerf(preset: AMDPowerPreset, limitMHz: Int, range: AMDCppcRange?) -> UInt8 {
        guard preset == .eco, limitMHz > 0, let range, range.isKnown else { return 0 }
        let perf = range.perf(atMost: limitMHz)
        return perf >= range.highest ? 0 : perf
    }
}

/// The idle clock limit's write bookkeeping (selector 69): whether a cap may
/// be in the CPU, and when to stop sending a value the kext keeps refusing.
/// Kept apart from the service so it can be tested. Times are seconds of
/// system uptime.
struct AMDIdleClockLimitWrites: Equatable, Sendable {
    /// Refusals of one value before it is no longer sent.
    static let maxFailures = 3
    /// A value given up on is tried once more after this long, so a refusal
    /// that was only passing (a busy firmware channel) does not lock the
    /// limit out for the rest of the session.
    static let retryAfter: TimeInterval = 300

    /// A non-zero max perf was sent and no lift has succeeded since. Set
    /// before the write: a refused write may still have reached some cores.
    private(set) var mayBeCapped = false
    /// Refusals per value since the kext last took a write. Kept per value,
    /// so a preset that alternates between a cap and a lift does not reset
    /// the other value's count and send it three more times.
    private(set) var failures: [UInt8: Int] = [:]
    /// When each value was last given up on.
    private(set) var givenUpAt: [UInt8: TimeInterval] = [:]

    /// `value` has been refused `maxFailures` times and its retry is not due.
    func hasGivenUp(on value: UInt8, now: TimeInterval) -> Bool {
        guard let since = givenUpAt[value] else { return false }
        return now - since < Self.retryAfter
    }

    /// Whether any value is given up on and not due for a retry: the row
    /// shows the limit as unavailable.
    func anyGivenUp(now: TimeInterval) -> Bool {
        givenUpAt.keys.contains { hasGivenUp(on: $0, now: now) }
    }

    /// Call before sending `value`.
    mutating func willWrite(_ value: UInt8) {
        if value != 0 { mayBeCapped = true }
    }

    /// Records the kext's answer. True only on the refusal that first makes
    /// it give up on `value`, so the caller logs once; a refused retry after
    /// `retryAfter` gives up again quietly.
    @discardableResult
    mutating func record(_ value: UInt8, succeeded: Bool, now: TimeInterval) -> Bool {
        if succeeded {
            if value == 0 { mayBeCapped = false }
            // The kext takes writes again: every value is worth sending.
            clearFailures()
            return false
        }
        let count = (failures[value] ?? 0) + 1
        failures[value] = count
        guard count >= Self.maxFailures else { return false }
        let first = givenUpAt[value] == nil
        givenUpAt[value] = now
        return first
    }

    /// Forgets the refusals, so every value is sent again (Auto EPP switched
    /// on or off, a wake, or a write the kext took).
    mutating func clearFailures() {
        failures = [:]
        givenUpAt = [:]
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

// MARK: - Kext calls (selectors 34, 61–69)

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

    /// The CPPC range and limits (selector 68) with the base clock from
    /// P-state 0 (selector 1); nil when the kext predates selector 68.
    nonisolated func getCppcRange() -> AMDCppcRange? {
        var output = [UInt64](repeating: 0, count: 8)
        var outputCount: UInt32 = 8
        let res = safeIOConnectCallMethod(AMDKextSelector.cppcRangeRead.id, nil, 0, nil, 0,
                                          &output, &outputCount, nil, nil)
        guard res == KERN_SUCCESS, outputCount >= 1 else { return nil }
        var clocks = [Float](repeating: 0, count: 8)
        var size = clocks.count * MemoryLayout<Float>.size
        let clockRes = clocks.withUnsafeMutableBytes { buffer in
            safeIOConnectCallMethod(AMDKextSelector.pStateDefClock, nil, 0, nil, 0,
                                    nil, nil, buffer.baseAddress, &size)
        }
        let base = clockRes == KERN_SUCCESS ? Double(clocks[0]) : 0
        return AMDCppcRange(raw: output, count: Int(outputCount), baseMHz: base)
    }

    /// CPPC min/max perf limits, 0 = the CPU's own bound (selector 69).
    @discardableResult
    nonisolated func setCppcLimits(minPerf: UInt8, maxPerf: UInt8) -> kern_return_t {
        var input: [UInt64] = [UInt64(minPerf), UInt64(maxPerf)]
        return safeIOConnectCallMethod(AMDKextSelector.cppcRangeWrite.id, &input, 2, nil, 0, nil, nil, nil, nil)
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
