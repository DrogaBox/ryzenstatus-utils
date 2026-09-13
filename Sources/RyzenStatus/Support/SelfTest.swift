// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import IOKit.pwr_mgt

/// Quick subsystem check, run with `RyzenStatus --selftest`.
/// Core capabilities fail the test; hardware-dependent readings only warn.
enum SelfTest {
    static func runAndExit() -> Never {
        var failures: [String] = []
        var warnings: [String] = []

        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "RyzenStatus selftest" as CFString,
                                                 &assertionID)
        if result == kIOReturnSuccess {
            IOPMAssertionRelease(assertionID)
        } else {
            failures.append("power assertion (\(result))")
        }

        if let memory = SystemInfo.memoryUsage() {
            if memory.total == 0 || memory.used > memory.total || memory.appUsed > memory.total
                || memory.compressed > memory.total || memory.cached > memory.total {
                failures.append("memory bounds")
            } else if memory.used == 0 {
                // Virtualized hosts can transiently report every page as
                // speculative or purgeable while idle; treat as a warning.
                warnings.append("zero memory used")
            }
        } else {
            failures.append("memory reading")
        }

        _ = SystemInfo.batterySnapshot() // may be nil on desktops

        if SystemInfo.wallClockUptimeSeconds() == nil {
            failures.append("uptime reading")
        }

        if let smc = SMCClient() {
            let keys = smc.keys { $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("Tg") }
            if keys.isEmpty {
                warnings.append("no SMC temperature keys")
            } else if keys.compactMap({ smc.readValue($0) }).isEmpty {
                warnings.append("SMC keys found but unreadable")
            }
        } else {
            warnings.append("AppleSMC unavailable")
        }

        // Network counters should be readable and never run backwards.
        let net1 = NetworkSampler.readCounters()
        let net2 = NetworkSampler.readCounters()
        if net1 == NetworkCounters(), net2 == NetworkCounters() {
            warnings.append("network counters unavailable")
        } else if net2.received < net1.received || net2.sent < net1.sent {
            failures.append("network counters decreased")
        }

        let diskCounters = DiskSampler.readCounters()
        let disks = DiskSampler().sample(now: ProcessInfo.processInfo.systemUptime)
        if diskCounters.isEmpty {
            warnings.append("disk counters unavailable")
        }
        if disks.isEmpty {
            warnings.append("no mounted disk volumes found")
        }

        // Power: laptops report battery/adapter flow; some desktops report nothing.
        if PowerSampler(smc: SMCClient()).sample().isEmpty {
            warnings.append("no power metrics on this Mac")
        }

        UserDefaults.standard.set("ok", forKey: "selftest")
        if UserDefaults.standard.string(forKey: "selftest") != "ok" {
            failures.append("UserDefaults")
        }
        UserDefaults.standard.removeObject(forKey: "selftest")

        for style in KeepAwakeActiveIcon.allCases {
            guard let image = BlackHoleGlyph.activeImage(style: style, tint: .orange) else {
                failures.append("Keep Awake icon \(style.rawValue)")
                continue
            }
            if image.size != NSSize(width: 20, height: 14) {
                failures.append("Keep Awake icon size \(style.rawValue)")
            }
        }

        for warning in warnings {
            print("SELFTEST WARNING: \(warning)")
        }
        if failures.isEmpty {
            print("SELFTEST OK")
            exit(0)
        } else {
            print("SELFTEST FAILED: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}

/// Prints every temperature sensor the monitor would consider, with its
/// classification. Run with `RyzenStatus --sensors`; handy when porting
/// the sensor mapping to a new chip generation.
enum SensorDump {
    static func runAndExit() -> Never {
        // S10-T2: the AMD kext is the primary sensor source on this platform, so
        // it is dumped first and unconditionally. Previously this command only
        // read AppleSMC Tp/Te/Tg keys, which VirtualSMC does not populate on an
        // AMD system — so `--sensors` printed nothing but its header on exactly
        // the hardware the app targets.
        printAMDTelemetry()

        // AppleSMC section. Non-fatal now: its absence must not suppress the AMD
        // dump above (the old `exit(1)` did precisely that).
        guard let smc = SMCClient() else {
            print("")
            print("AppleSMC unavailable — no SMC temperature keys to dump")
            exit(0)
        }
        let keys = smc.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        let cpuPlatform = TemperatureSensorSelector.currentPlatform()
        let hasCPUCoreSet = TemperatureSensorSelector.hasCPUCoreSet(platform: cpuPlatform)
        print("")
        print("== AppleSMC temperature keys ==")
        print("component    key   type   °C")
        for key in keys.sorted(by: { $0.name < $1.name }) {
            guard let value = smc.readValue(key), value > 1, value < 125 else { continue }
            let component: String
            if key.name.hasPrefix("TB") {
                component = "battery"
            } else if key.name.hasPrefix("Tg") {
                component = "gpu"
            } else if hasCPUCoreSet {
                component = TemperatureSensorSelector.isCPUCoreKey(key.name, platform: cpuPlatform) ? "cpu-core" : "cpu-aux"
            } else {
                component = "cpu"
            }
            print(String(format: "%-11@  %@  %@  %6.2f",
                         component as NSString, key.name, key.dataType, value))
        }
        exit(0)
    }

    /// S10-T2: dumps the AMD kext's own telemetry — the authoritative sensor
    /// source on this platform. Everything here is `nonisolated` on
    /// ProcessorModel, so it is safe to call from this pre-NSApplication path.
    private static func printAMDTelemetry() {
        print("== AMD kext telemetry (AMDRyzenCPUPowerManagement) ==")

        guard ProcessorModel.shared.isConnected else {
            print("kext not loaded — no AMD telemetry available")
            print("  (expected on Intel/Apple Silicon, or if the kext failed to load)")
            return
        }

        guard let packet = ProcessorModel.shared.getTelemetry() else {
            print("kext connected but selector 100 returned no packet")
            print("  (privilege denied, or the kext's sampling timer has not run yet)")
            return
        }

        print(String(format: "package      power   %8.2f W", packet.packagePowerW))
        print(String(format: "package      temp    %8.2f °C", packet.packageTempC))
        print("logical cores        \(packet.numLogicalCores)")
        print("CCD count            \(packet.ccdCount)")

        let ccdCount = Int(packet.ccdCount)
        if ccdCount > 0 {
            for i in 0..<min(ccdCount, packet.ccdTemperatures.count) {
                let t = packet.ccdTemperatures[i]
                guard t > 0 else { continue }
                print(String(format: "ccd%-2d        temp    %8.2f °C", i, t))
            }
        }

        // S10-T2b: the kext fills coreFrequenciesMHz[] indexed by LOGICAL core
        // but sources every entry from effFreq_perCore[phys]
        // (AMDRyzenCPUPMUserClient.cpp:586), so on an SMT part each physical
        // core's clock appears twice. Printing all 32 entries on a 16C/32T part
        // listed 16 phantom duplicates — actively misleading for the porting use
        // case this command exists for.
        let logicalCount = Int(packet.numLogicalCores)
        let physicalCount = Int(ProcessorModel.sysctlInt64(key: "hw.physicalcpu"))
        let smtActive = physicalCount > 0 && logicalCount == physicalCount * 2
        let coreCount = smtActive ? physicalCount : logicalCount
        if smtActive {
            print("SMT                  on (\(logicalCount) threads / \(physicalCount) cores — sibling threads mirror the core clock)")
        }
        if coreCount > 0 {
            var printed = 0
            for i in 0..<min(coreCount, packet.coreFrequenciesMHz.count) {
                let mhz = packet.coreFrequenciesMHz[i]
                guard mhz > 0 else { continue }
                print(String(format: "core%-2d       clock   %8.0f MHz", i, mhz))
                printed += 1
            }
            if printed == 0 {
                print("core clocks          none reported")
            }
        }

        let fans = ProcessorModel.shared.getFans(includeNames: true)
        if fans.isEmpty {
            print("fans                 none detected (SuperIO not initialised?)")
        } else {
            for fan in fans {
                let pct = (Double(fan.throttle) / 255.0) * 100.0
                print(String(format: "fan%-2d  %-12@  %5d RPM  pwm %3d (%5.1f%%)%@",
                             fan.id, fan.name as NSString, Int(fan.rpm),
                             Int(fan.throttle), pct,
                             (fan.rpmValid ? "" : "  [tach unreliable]") as NSString))
            }
        }
    }
}
