// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// The AMD hardware layer's rules: which fan writes reach the kext, which
/// kext answers make the connection suspect, and where EPP and P-state
/// writes go. Pure functions are tested directly; a source check stands in
/// only where the rule lives in wiring with no pure seam.
enum HardwareLayerTests {
    static func run(_ suite: TestSuite) {
        manualFansKeepTheirDuty(suite)
        curveMappingsChangeOnlyWhenNeeded(suite)
        planInvariantOverEveryState(suite)
        suspectReturnCodes(suite)
        eppWrites(suite)
        pStateRoutes(suite)
        presetFailureMessage(suite)
        pmTableAgeAtReadTime(suite)
        cachesClear(suite)
        wiring(suite)
    }

    // MARK: - Fan write plan

    private static func manualFansKeepTheirDuty(_ suite: TestSuite) {
        let idle = FanKextWritePlan.writes(mappings: [0: -1], manualPWMs: [0: 120],
                                           kextMappings: [:], curveCount: 2)
        suite.expect(idle.isEmpty,
                     "a manual fan the kext holds no curve for gets no write, above all no 102(-1)")

        let asserted = FanKextWritePlan.writes(mappings: [0: -1], manualPWMs: [0: 120],
                                               kextMappings: [:], curveCount: 2, assertDutyFor: [0])
        suite.expect(asserted == [.manualDuty(fan: 0, pwm: 120)],
                     "a duty the user just set is written without unmapping the fan again")

        let leavingCurve = FanKextWritePlan.writes(mappings: [0: -1], manualPWMs: [0: 120],
                                                   kextMappings: [0: 1], curveCount: 2)
        suite.expect(leavingCurve == [.mapToCurve(fan: 0, curve: -1), .manualDuty(fan: 0, pwm: 120)],
                     "a manual fan still on a kext curve is unmapped and gets its duty in the same pass")

        let allMax = FanKextWritePlan.writes(mappings: [0: -1, 1: -1, 2: -1],
                                             manualPWMs: [0: 255, 1: 255, 2: 255],
                                             kextMappings: [1: 0], curveCount: 2,
                                             assertDutyFor: [0, 1, 2])
        suite.expect(allMax == [.manualDuty(fan: 0, pwm: 255),
                                .mapToCurve(fan: 1, curve: -1), .manualDuty(fan: 1, pwm: 255),
                                .manualDuty(fan: 2, pwm: 255)],
                     "all max unmaps only the fan the kext ran a curve on, and every fan gets 255")

        let afterReconnect = FanKextWritePlan.writes(mappings: [0: -1, 1: 0],
                                                     manualPWMs: [0: 90],
                                                     kextMappings: [:], curveCount: 1,
                                                     assertDutyFor: [0])
        suite.expect(afterReconnect == [.manualDuty(fan: 0, pwm: 90), .mapToCurve(fan: 1, curve: 0)],
                     "after a reconnect the manual duty is re-applied and the curve fan mapped again")
    }

    private static func curveMappingsChangeOnlyWhenNeeded(_ suite: TestSuite) {
        suite.expect(FanKextWritePlan.writes(mappings: [3: 1], manualPWMs: [:],
                                             kextMappings: [:], curveCount: 2)
                     == [.mapToCurve(fan: 3, curve: 1)],
                     "a fan newly on a curve is mapped")
        suite.expect(FanKextWritePlan.writes(mappings: [3: 1], manualPWMs: [:],
                                             kextMappings: [3: 1], curveCount: 2).isEmpty,
                     "an unchanged mapping is not uploaded again")
        suite.expect(FanKextWritePlan.writes(mappings: [3: 0], manualPWMs: [:],
                                             kextMappings: [3: 1], curveCount: 2)
                     == [.mapToCurve(fan: 3, curve: 0)],
                     "a fan moved to another curve is mapped once, to the new slot")
        suite.expect(FanKextWritePlan.writes(mappings: [3: -1], manualPWMs: [:],
                                             kextMappings: [3: 1], curveCount: 2)
                     == [.mapToCurve(fan: 3, curve: -1)],
                     "an auto fan the kext still runs a curve on goes back to the BIOS")
        suite.expect(FanKextWritePlan.writes(mappings: [3: -1], manualPWMs: [:],
                                             kextMappings: [:], curveCount: 2).isEmpty,
                     "an auto fan the kext holds nothing for gets no write")
        suite.expect(FanKextWritePlan.writes(mappings: [3: 2], manualPWMs: [:],
                                             kextMappings: [:], curveCount: 2).isEmpty,
                     "a mapping to a slot without a curve is not on a curve")
        suite.expect(FanKextWritePlan.heldCurve(after: .mapToCurve(fan: 2, curve: 1))! == (2, 1)
                     && FanKextWritePlan.heldCurve(after: .mapToCurve(fan: 2, curve: -1))! == (2, nil),
                     "a successful selector 102 write records what the kext holds")
        suite.expect(FanKextWritePlan.heldCurve(after: .biosControl(fan: 2)) == nil
                     && FanKextWritePlan.heldCurve(after: .manualDuty(fan: 2, pwm: 50)) == nil,
                     "selectors 95 and 96 leave the recorded mapping alone")
    }

    /// Every combination of one fan's state: a manual fan never gets 102(-1)
    /// unless its duty follows at once, and a settled state writes nothing.
    private static func planInvariantOverEveryState(_ suite: TestSuite) {
        var violations: [String] = []
        for mapping in [nil, -1, 0, 1, 5] as [Int?] {
            for held in [nil, 0, 1] as [Int?] {
                for manual in [nil, 77] as [UInt8?] {
                    for assert in [false, true] {
                        var mappings: [Int: Int] = [:]
                        if let mapping { mappings[4] = mapping }
                        var kext: [Int: Int] = [:]
                        if let held { kext[4] = held }
                        var manuals: [Int: UInt8] = [:]
                        if let manual { manuals[4] = manual }
                        let writes = FanKextWritePlan.writes(mappings: mappings, manualPWMs: manuals,
                                                             kextMappings: kext, curveCount: 2,
                                                             assertDutyFor: assert ? [4] : [])
                        let label = "mapping=\(String(describing: mapping)) held=\(String(describing: held)) manual=\(String(describing: manual)) assert=\(assert)"
                        let onCurve = mapping.map { (0..<2).contains($0) } ?? false
                        for (i, write) in writes.enumerated() where write == .mapToCurve(fan: 4, curve: -1) {
                            if manual != nil && !onCurve
                                && (i + 1 >= writes.count || writes[i + 1] != .manualDuty(fan: 4, pwm: 77)) {
                                violations.append("unmap without duty: \(label)")
                            }
                        }
                        if !assert {
                            let settled = onCurve ? held == mapping : held == nil
                            if settled && !writes.isEmpty { violations.append("write in a settled state: \(label)") }
                        }
                    }
                }
            }
        }
        suite.expect(violations.isEmpty, "fan write plan invariants: \(violations)")
    }

    // MARK: - Connection health

    private static func suspectReturnCodes(_ suite: TestSuite) {
        let suspect: [(kern_return_t, String)] = [
            (kIOReturnNotReady, "NotReady"),
            (kIOReturnNotResponding, "NotResponding"),
            (kIOReturnNotAttached, "NotAttached"),
            (kern_return_t(MIG_SERVER_DIED), "MIG_SERVER_DIED"),
            (kern_return_t(MACH_SEND_INVALID_DEST), "MACH_SEND_INVALID_DEST"),
            (kern_return_t(MACH_SEND_TIMED_OUT), "MACH_SEND_TIMED_OUT"),
            (kern_return_t(MACH_SEND_INVALID_RIGHT), "MACH_SEND_INVALID_RIGHT"),
        ]
        for (kr, name) in suspect {
            suite.expect(KextTransportHealth.isSuspectFailure(kr, serviceMatches: true),
                         "\(name) makes the connection suspect")
        }
        suite.expect(KextTransportHealth.isSuspectFailure(kIOReturnNoDevice, serviceMatches: true),
                     "NoDevice counts while the service still matches")
        suite.expect(!KextTransportHealth.isSuspectFailure(kIOReturnNoDevice, serviceMatches: false),
                     "NoDevice with the service gone is the unload path's, not a stale handle")
        let normal: [(kern_return_t, String)] = [
            (KERN_SUCCESS, "success"),
            (kIOReturnNotPrivileged, "NotPrivileged"),
            (kIOReturnBadArgument, "BadArgument"),
            (kIOReturnUnsupported, "Unsupported"),
            (kern_return_t(MACH_SEND_IN_PROGRESS), "MACH_SEND_IN_PROGRESS"),
        ]
        for (kr, name) in normal {
            suite.expect(!KextTransportHealth.isSuspectFailure(kr, serviceMatches: true),
                         "\(name) is a normal kext answer")
        }
    }

    // MARK: - EPP and P-states

    private static func eppWrites(_ suite: TestSuite) {
        suite.expect(!ProcessorModel.eppWritesTakeEffect,
                     "EPP writes stay off while the kext's applyEPPControl() is a stub")
        suite.expect(ProcessorModel.eppWriteRefusal(writesTakeEffect: false) == kIOReturnUnsupported,
                     "an EPP write the kext would ignore answers unsupported without IPC")
        suite.expect(ProcessorModel.eppWriteRefusal(writesTakeEffect: true) == nil,
                     "an EPP write that takes effect goes to the kext")
        suite.expect(!AutoEppPolicy.shouldRun(enabled: true, suspended: false, writesTakeEffect: false),
                     "the Auto EPP loop never starts while EPP writes have no effect")
        suite.expect(AutoEppPolicy.shouldRun(enabled: true, suspended: false, writesTakeEffect: true),
                     "Auto EPP runs once it is on and the writes take effect")
        suite.expect(!AutoEppPolicy.shouldRun(enabled: false, suspended: false, writesTakeEffect: true)
                     && !AutoEppPolicy.shouldRun(enabled: true, suspended: true, writesTakeEffect: true),
                     "Auto EPP stays off while disabled or suspended by Gaming Mode")
    }

    private static func pStateRoutes(_ suite: TestSuite) {
        suite.expect(ProcessorModel.pStateRoute(isEmulating: true, profileKnown: true, legacyAllowed: false) == .emulated,
                     "the emulated table maps to CPB/LPM/PPM whatever the profile says")
        suite.expect(ProcessorModel.pStateRoute(isEmulating: false, profileKnown: true, legacyAllowed: false) == .unsupported,
                     "a profile without legacy P-states reports unsupported instead of a silent success")
        suite.expect(ProcessorModel.pStateRoute(isEmulating: false, profileKnown: true, legacyAllowed: true) == .legacyMSR,
                     "legacy P-states go to selector 10")
        suite.expect(ProcessorModel.pStateRoute(isEmulating: false, profileKnown: false, legacyAllowed: false) == .legacyMSR,
                     "an older kext without a profile keeps selector 10")
    }

    private static func presetFailureMessage(_ suite: TestSuite) {
        let privilegeHint = ProcessorModel.privilegeHint(for: ProcessorModel.kIOReturnNotPrivilegedCode)
        let denied = AMDPowerPresetApplyResult(epp: kIOReturnUnsupported,
                                               cpb: ProcessorModel.kIOReturnNotPrivilegedCode,
                                               ppm: KERN_SUCCESS, lpm: KERN_SUCCESS)
        suite.expect(denied.privilegeDenied && denied.firstFailureMessage == privilegeHint,
                     "a preset denied privilege shows the privilege hint, not EPP's unsupported")
        let eppOnly = AMDPowerPresetApplyResult(epp: kIOReturnUnsupported, cpb: KERN_SUCCESS,
                                                ppm: KERN_SUCCESS, lpm: KERN_SUCCESS)
        suite.expect(!eppOnly.privilegeDenied, "an ignored EPP write is not a privilege denial")
    }

    // MARK: - Caches

    private static func pmTableAgeAtReadTime(_ suite: TestSuite) {
        let box = ProcessorModel.PMTableBox()
        box.update(nil, capturedAtUptime: 0)
        suite.expect(box.ageMs(now: 100) == nil, "no capture, no age")
        box.update(nil, capturedAtUptime: 90)
        suite.expect(box.ageMs(now: 100) == 10_000, "the age grows with the clock after the read")
        suite.expect(box.ageMs(now: 89) == 0, "clock skew clamps the age to 0")
        suite.expect(box.freshSocketPowerW == 0 && box.freshCoreClocksMHz.isEmpty,
                     "nothing decoded, nothing promoted")
    }

    private static func cachesClear(_ suite: TestSuite) {
        let power = ProcessorModel.PowerCache()
        power.setCPU(5)
        power.setGPU(3)
        power.setCPUTemp(40)
        power.reset()
        suite.expect(power.cpuWatts == 0 && power.gpuWatts == 0 && power.cpuTemp == 0,
                     "an unload clears the power cache")
    }

    // MARK: - Wiring (no pure seam)

    private static func source(_ path: String, _ suite: TestSuite) -> String {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        suite.expect(!text.isEmpty, "\(path) is readable")
        return text
    }

    /// The text of `name`'s body: from its declaration to the next `func`.
    private static func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: "func \(name)") ?? text.range(of: "var \(name)") else { return "" }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private static func wiring(_ suite: TestSuite) {
        let controller = source("Sources/RyzenStatus/Services/AMD/FanCurveController.swift", suite)
        suite.expect(!body(of: "setManualPWM", in: controller).contains("mapKextFanToCurve"),
                     "a manual duty step does not unmap the fan first")
        suite.expect(body(of: "disableCurves", in: controller).contains("enqueueKextWrite"),
                     "disabling the curves joins the ordered write chain")
        for name in ["setFanMode", "setManualPWM", "setAllAuto", "setAllMaxSpeed",
                     "enforceManualThermalGuard", "currentCPUOrPackageTemp"] {
            let text = body(of: name, in: controller)
            suite.expect(!text.isEmpty && !text.contains("ProcessorModel.shared.set")
                         && !text.contains("ProcessorModel.shared.map")
                         && !text.contains("getTelemetry()"),
                         "\(name) makes no kext call on the main actor")
        }
        suite.expect(body(of: "pushGPUTempIfNeeded", in: controller).contains("enqueueKextWrite"),
                     "the GPU temperature bridge writes through the chain")
        suite.expect(!controller.contains("curveUploadTask") && !controller.contains("mappingUploadTask"),
                     "the curve and mapping uploads go through the write chain, not their own tasks")
        suite.expect(controller.contains("kextWriteTail") && !controller.contains("kextWriteTail?.cancel()"),
                     "nothing cancels the write chain")

        let editor = source("Sources/RyzenStatus/UI/Settings/FanCurveEditor.swift", suite)
        suite.expect(!editor.contains("getTelemetry()"), "the curve editor's body makes no kext call")

        let model = source("Sources/RyzenStatus/Services/AMD/ProcessorModel.swift", suite)
        suite.expect(model.contains("await self.forgetUnloadedKext()"),
                     "the watchdog clears the kext's caches when it unloads")
        suite.expect(model.contains("isLikelyStale, !self.probeConnection()"),
                     "a suspect handle is reopened only when the probe fails too")
        suite.expect(!model.contains("func setPState(def"), "the unused P-state definition write is gone")
        suite.expect(!model.contains("(PStateDef[1] & 0x8000000000000000) == 0"),
                     "P-state reads and writes share one routing rule")
        suite.expect(body(of: "refreshPMTableBox", in: model).contains("getPMTableSnapshot(info: info)"),
                     "a PM-table refresh makes one selector 56 call")
        suite.expect(!model.contains("getPackageC6Residency") && !model.contains("getCoreInstRetired"),
                     "selectors 31 and 33 are no longer read")

        let c6 = source("Sources/RyzenStatus/Services/AMD/C6ResidencyService.swift", suite)
        suite.expect(c6.contains("func startPolling()") && c6.contains("func stopPolling()")
                     && !c6.contains("willSleepNotification"),
                     "the residency poll is client-counted, with no sleep observers")
        let grid = source("Sources/RyzenStatus/UI/MenuPanel/CPUCoreGridView.swift", suite)
        suite.expect(grid.contains("C6ResidencyService.shared.startPolling()")
                     && grid.contains("C6ResidencyService.shared.stopPolling()"),
                     "the core grid is the residency poll's client")
        let delegate = source("Sources/RyzenStatus/App/AppDelegate.swift", suite)
        suite.expect(!delegate.contains("C6ResidencyService.shared.start()"),
                     "the residency poll no longer starts at launch")

        let settings = source("Sources/RyzenStatus/UI/Settings/AmdPowerSettingsView.swift", suite)
        suite.expect(body(of: "exportPMTable", in: settings).contains("Task.detached"),
                     "the PM-table save captures off the main actor")

        let smc = source("Sources/RyzenStatus/Services/SystemMonitor/SMCClient.swift", suite)
        suite.expect(!smc.contains("cmdWriteKey") && !smc.contains("func write"),
                     "the SMC client has no write path")
        let dump = source("Sources/RyzenStatus/Services/SystemMonitor/SMCDumpService.swift", suite)
        suite.expect(!dump.contains("lastKeyDiscovery"), "SMC keys are not re-listed on a timer")
        let sensors = source("Sources/RyzenStatus/UI/Settings/SensorsView.swift", suite)
        suite.expect(sensors.contains("smcDump.rediscoverKeys()"),
                     "SMC keys are listed when the Sensors page opens")
    }
}
