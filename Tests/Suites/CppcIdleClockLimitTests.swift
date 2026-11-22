// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Idle clock limit (issue 108): the CPPC perf range the kext reports
/// (selector 68), its MHz conversion, when Auto EPP writes a max perf
/// (selector 69), and the kext's clamping of the limits.
enum CppcIdleClockLimitTests {
    static func run(_ suite: TestSuite) {
        rangeDecoding(suite)
        conversion(suite)
        policy(suite)
        writes(suite)
        kextSource(suite)
        appSource(suite)
    }

    /// A Cezanne-like range: lowest 13, lowest non-linear 38, nominal 100,
    /// highest 139, base clock 3200 MHz (lowest = 416 MHz).
    private static func cezanne(min: UInt64 = 0, max: UInt64 = 0, base: Double? = 3200) -> AMDCppcRange {
        AMDCppcRange(raw: [1, 13, 38, 100, 139, min, max, 1], count: 8, baseMHz: base)
    }

    private static func rangeDecoding(_ suite: TestSuite) {
        let r = cezanne(min: 0, max: 25)
        suite.expect(r.mechanism == .msr && r.lowest == 13 && r.lowestNonlinear == 38
                     && r.nominal == 100 && r.highest == 139, "selector 68 words decode in order")
        suite.expect(r.minLimit == 0 && r.maxLimit == 25 && r.limitsInForce, "limits and in-force flag decode")
        suite.expect(r.isKnown, "a complete range with a base clock is known")
        suite.expect(!cezanne(base: nil).isKnown, "no base clock: no MHz slider")
        suite.expect(!cezanne(base: 0).isKnown, "a zero P0 clock counts as no base clock")
        let acpiBeforeEngage = AMDCppcRange(raw: [2, 0, 0, 0, 0, 0, 0, 0], count: 8, baseMHz: 3800)
        suite.expect(acpiBeforeEngage.mechanism == .acpi && !acpiBeforeEngage.isKnown,
                     "ACPI CPPC before the first PCC read is not known yet")
        let short = AMDCppcRange(raw: [1, 13, 0, 0, 0, 0, 0, 0], count: 2, baseMHz: 3200)
        suite.expect(short.nominal == 0 && !short.isKnown, "a short reply leaves the missing words at 0")
        let none = AMDCppcRange(raw: [9], count: 1, baseMHz: 3200)
        suite.expect(none.mechanism == .none, "an unknown mechanism reads as none")
    }

    private static func conversion(_ suite: TestSuite) {
        let r = cezanne()
        suite.expect(r.mhz(perf: 100) == 3200, "nominal perf is the base clock")
        suite.expect(r.mhz(perf: 13) == 425, "lowest perf 13 → 416 MHz, rounded to 25 MHz (got \(r.mhz(perf: 13) ?? -1))")
        suite.expect(r.mhz(perf: 38) == 1225, "lowest non-linear 38 → 1216 MHz → 1225 (got \(r.mhz(perf: 38) ?? -1))")
        suite.expect(r.perf(atMost: 800) == 25, "800 MHz → perf 25 (800 MHz exactly)")
        suite.expect(r.perf(atMost: 799) == 24, "the perf never passes the asked clock")
        suite.expect(r.perf(atMost: 100) == 13, "below the lowest clock it clamps to lowest perf")
        suite.expect(r.perf(atMost: 9000) == 139, "above the boost clock it clamps to highest perf")
        suite.expect(r.idleLimitRangeMHz == 425...3200, "the slider spans lowest…base clock")
        suite.expect(cezanne(base: nil).idleLimitRangeMHz == nil, "no slider without a base clock")
        suite.expect(IdleClockLimitRow.clock(800) == "800 MHz", "clocks below 1 GHz read in MHz")
    }

    private static func policy(_ suite: TestSuite) {
        let r = cezanne()
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 800, range: r) == 25,
                     "Eco (idle) with an 800 MHz limit writes max perf 25")
        for preset in [AMDPowerPreset.balance, .performance, .extreme] {
            suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: preset, limitMHz: 800, range: r) == 0,
                         "\(preset) lifts the limit")
        }
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 0, range: r) == 0,
                     "limit off: no max perf")
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 800, range: nil) == 0,
                     "no range: nothing written")
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 800, range: cezanne(base: nil)) == 0,
                     "unknown base clock: nothing written")
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 9000, range: r) == 0,
                     "a limit at or above the boost clock is no limit")
        suite.expect(AMDIdleClockLimitPolicy.maxPerf(preset: .eco, limitMHz: 100, range: r) == 13,
                     "a limit under the lowest clock holds at lowest perf")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.autoEppIdleClockLimitMHz] == nil,
                     "the idle clock limit is off unless the user sets it")
    }

    /// Write bookkeeping: a refused lift stays owed, a refused value is
    /// sent at most `maxFailures` times and then once every `retryAfter`,
    /// counted per value so an alternating preset cannot reset it.
    private static func writes(_ suite: TestSuite) {
        let t0: TimeInterval = 1_000
        var w = AMDIdleClockLimitWrites()
        suite.expect(!w.mayBeCapped && !w.hasGivenUp(on: 0, now: t0), "nothing written: no cap, nothing given up")

        w.willWrite(25)
        w.record(25, succeeded: false, now: t0)
        suite.expect(w.mayBeCapped, "a refused cap may still have reached some cores")

        w.willWrite(0)
        w.record(0, succeeded: false, now: t0)
        suite.expect(w.mayBeCapped, "a refused lift leaves the cap owed, so it is tried again")
        w.willWrite(0)
        w.record(0, succeeded: true, now: t0)
        suite.expect(!w.mayBeCapped && w.failures.isEmpty, "a lift the kext took clears the cap and the refusals")

        w.willWrite(25)
        w.record(25, succeeded: true, now: t0)
        w.willWrite(30)
        w.record(30, succeeded: true, now: t0)
        suite.expect(w.mayBeCapped, "a cap the kext took is in force until a lift succeeds")

        var gaveUpAt: [Int] = []
        for attempt in 1...(AMDIdleClockLimitWrites.maxFailures + 2) {
            w.willWrite(25)
            if w.record(25, succeeded: false, now: t0) { gaveUpAt.append(attempt) }
        }
        suite.expect(gaveUpAt == [AMDIdleClockLimitWrites.maxFailures],
                     "gives up once, on refusal \(AMDIdleClockLimitWrites.maxFailures) (got \(gaveUpAt))")
        suite.expect(w.hasGivenUp(on: 25, now: t0) && !w.hasGivenUp(on: 0, now: t0),
                     "only the refused value is given up on")
        suite.expect(w.anyGivenUp(now: t0), "the row shows the limit as unavailable")

        // A preset going idle -> load -> idle alternates 25 and 0. A refused
        // lift must not re-arm 25 (the old per-value-in-a-row count did, so
        // every load change sent 25 three more times).
        for _ in 1...AMDIdleClockLimitWrites.maxFailures { w.record(0, succeeded: false, now: t0) }
        suite.expect(w.hasGivenUp(on: 25, now: t0) && w.hasGivenUp(on: 0, now: t0),
                     "each value keeps its own count: alternating re-arms nothing")

        // A passing refusal does not lock the limit out for the session.
        let later = t0 + AMDIdleClockLimitWrites.retryAfter
        suite.expect(w.hasGivenUp(on: 25, now: later - 1), "still given up just before the retry")
        suite.expect(!w.hasGivenUp(on: 25, now: later) && !w.anyGivenUp(now: later),
                     "tried again after retryAfter")
        suite.expect(!w.record(25, succeeded: false, now: later) && w.hasGivenUp(on: 25, now: later),
                     "a refused retry gives up again quietly, for another retryAfter")
        w.willWrite(25)
        w.record(25, succeeded: true, now: later)
        suite.expect(w.failures.isEmpty && !w.anyGivenUp(now: later),
                     "a write the kext took clears every value's refusals")

        w.record(0, succeeded: false, now: later)
        w.clearFailures()
        suite.expect(!w.hasGivenUp(on: 0, now: later) && w.failures.isEmpty && w.mayBeCapped,
                     "a wake or switching Auto EPP forgets the refusals but not the cap")
    }

    private static func appSource(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Sources/RyzenStatus/Services/AMD/AutoEppService.swift")
        guard let svc = try? String(contentsOf: file, encoding: .utf8) else {
            suite.expect(false, "AutoEppService.swift readable")
            return
        }
        suite.expect(!svc.contains("appliedIdleMaxPerf = 0")
                     && svc.contains("appliedIdleMaxPerf = ok ? maxPerf : nil"),
                     "the written max perf is recorded only after the kext took it")
        suite.expect(svc.contains("guard idleLimitWrites.mayBeCapped, canRun else { return }")
                     && svc.contains("if !writeIdleClockLimit(0) { scheduleLiftRetry() }"),
                     "a lift follows the cap, not the last value, and a refused one is retried")
    }

    private static func kextSource(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement")
        guard let pm = try? String(contentsOf: dir.appendingPathComponent("AMDRyzenCPUPowerManagement.cpp"), encoding: .utf8),
              let uc = try? String(contentsOf: dir.appendingPathComponent("AMDRyzenCPUPMUserClient.cpp"), encoding: .utf8)
        else {
            suite.expect(false, "kext sources readable")
            return
        }
        suite.expect(pm.contains("if (maxLimit != 0 && maxLimit < highest) maxPerf = maxLimit < lowest ? lowest : maxLimit;")
                     && pm.contains("if (minLimit > lowest) minPerf = minLimit > maxPerf ? maxPerf : minLimit;"),
                     "the kext clamps max into lowest…highest and min into lowest…max")
        suite.expect(pm.contains("cppcPerfRange(a->minLimit, a->maxLimit, lowest, highest, minPerf, maxPerf);")
                     && pm.contains("cppcPerfRange(minLimit, maxLimit, lowest, highest, minPerf, maxPerf);"),
                     "both the MSR and the ACPI path apply the limits per core")
        suite.expect(pm.contains("minLimit = cppcMinPerfLimit;") && pm.contains("uint8_t minLimit = 0, maxLimit = 0;"),
                     "limits hold only in autonomous mode; CPPC off goes back to the full range")
        suite.expect(uc.contains("if (!hasPrivilege(69)) return kIOReturnNotPrivileged;"),
                     "selector 69 needs privilege")
        suite.expect(uc.contains("if (minPerf != 0 && maxPerf != 0 && minPerf > maxPerf) return kIOReturnBadArgument;"),
                     "selector 69 refuses an inverted range")
        suite.expect(!uc.contains("hasPrivilege(68)"), "selector 68 is a read for everyone")
        suite.expect(uc.contains("provider->cppcLimitsOwner = (minPerf != 0 || maxPerf != 0) ? (const void *)this : nullptr;"),
                     "selector 69 records which client set the limits")
        suite.expect(uc.contains("if (provider->cppcLimitsOwner == (const void *)this) {")
                     && uc.contains("const bool lifted = provider->setCppcPerfLimits(0, 0);"),
                     "clientClose of the client that set them lifts the limits")
        suite.expect(!uc.contains("provider->cppcMinPerfLimit = ") && !uc.contains("provider->cppcMaxPerfLimit = "),
                     "the user client never stores the limits outside setCppcPerfLimits")
        suite.expect(pm.contains("IOLockLock(rendezvousLock);\n    cppcMinPerfLimit = minLimit;\n    cppcMaxPerfLimit = maxLimit;"),
                     "the limits change under rendezvousLock, the lock the timer's apply holds")
    }
}
