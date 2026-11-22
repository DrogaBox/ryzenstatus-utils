// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// On battery (laptops): the stored mode, the power source, what Auto EPP
/// becomes on battery, how the idle clock limit follows it, that plugging
/// in gives the normal behaviour back, and that a manual EPP is left alone
/// (Linux amd-pstate's dynamic EPP acts on the balanced profile only). No
/// battery is needed: every rule is a pure function of (source, mode, target).
enum BatteryPowerPolicyTests {
    static func run(_ suite: TestSuite) {
        storedMode(suite)
        powerSource(suite)
        autoTargets(suite)
        idleClockLimit(suite)
        backToExternal(suite)
        strings(suite)
        source(suite)
    }

    private static let targets: [AutoEppTarget] = [.gpuPerformance, .performance, .gpuActive, .balanced, .powerSave]
    private static let modes = AMDBatteryPowerMode.allCases

    private static func rank(_ preset: AMDPowerPreset) -> Int {
        AMDPowerPreset.allCases.firstIndex(of: preset) ?? -1
    }

    private static func storedMode(_ suite: TestSuite) {
        suite.expect(AMDBatteryPowerMode(stored: nil) == .sameAsPluggedIn, "no stored mode: same as plugged in")
        suite.expect(AMDBatteryPowerMode(stored: "bogus") == .sameAsPluggedIn, "an unknown stored mode: same as plugged in")
        for mode in modes {
            suite.expect(AMDBatteryPowerMode(stored: mode.rawValue) == mode, "\(mode) round-trips through its stored value")
        }
        suite.expect(Set(modes.map(\.rawValue)).count == 3, "three distinct stored values")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.amdBatteryPowerMode] == nil,
                     "On battery changes nothing unless the user picks a mode")
    }

    private static func powerSource(_ suite: TestSuite) {
        suite.expect(AMDPowerSource(hasBattery: true, onBattery: true) == .battery, "battery Mac on battery")
        suite.expect(AMDPowerSource(hasBattery: true, onBattery: false) == .external, "battery Mac plugged in")
        suite.expect(AMDPowerSource(hasBattery: true, onBattery: nil) == .external, "unknown source counts as plugged in")
        suite.expect(AMDPowerSource(hasBattery: false, onBattery: true) == .external, "a Mac without a battery is never on battery")
        suite.expect(AMDPowerSource(hasBattery: false, onBattery: nil) == .external, "a desktop reads as plugged in")
        for mode in modes {
            suite.expect(!AMDBatteryPowerPolicy.adjusts(source: .external, mode: mode), "\(mode) changes nothing plugged in")
        }
        suite.expect(!AMDBatteryPowerPolicy.adjusts(source: .battery, mode: .sameAsPluggedIn),
                     "same as plugged in changes nothing on battery")
        suite.expect(AMDBatteryPowerPolicy.adjusts(source: .battery, mode: .saveMore)
                     && AMDBatteryPowerPolicy.adjusts(source: .battery, mode: .maximumSaving),
                     "Save more and Maximum saving act on battery")
    }

    private static func autoTargets(_ suite: TestSuite) {
        func auto(_ t: AutoEppTarget, _ source: AMDPowerSource, _ mode: AMDBatteryPowerMode) -> AutoEppTarget {
            AMDBatteryPowerPolicy.autoTarget(t, source: source, mode: mode)
        }
        for t in targets {
            for mode in modes {
                suite.expect(auto(t, .external, mode) == t, "plugged in, \(mode) keeps \(t)")
                let onBattery = auto(t, .battery, mode)
                suite.expect(rank(onBattery.preset) <= rank(t.preset),
                             "on battery \(mode) never raises \(t) (got \(onBattery))")
            }
            suite.expect(auto(t, .battery, .sameAsPluggedIn) == t, "same as plugged in keeps \(t) on battery")
            suite.expect(auto(t, .battery, .maximumSaving) == .powerSave, "Maximum saving holds Eco for \(t)")
            suite.expect(auto(t, .battery, .saveMore).preset != .performance, "Save more never applies Performance for \(t)")
        }
        suite.expect(auto(.performance, .battery, .saveMore) == .balanced, "Save more: CPU load Performance → Balance")
        suite.expect(auto(.gpuPerformance, .battery, .saveMore) == .gpuActive, "Save more: GPU Performance → GPU · Balance")
        suite.expect(auto(.balanced, .battery, .saveMore) == .balanced
                     && auto(.gpuActive, .battery, .saveMore) == .gpuActive
                     && auto(.powerSave, .battery, .saveMore) == .powerSave,
                     "Save more keeps Balance and Eco as they are")
    }

    private static func idleClockLimit(_ suite: TestSuite) {
        // The Cezanne-like range of CppcIdleClockLimitTests (base 3200 MHz).
        let range = AMDCppcRange(raw: [1, 13, 38, 100, 139, 0, 0, 1], count: 8, baseMHz: 3200)
        func maxPerf(load: AutoEppTarget, mode: AMDBatteryPowerMode, source: AMDPowerSource = .battery) -> UInt8 {
            let applied = AMDBatteryPowerPolicy.autoTarget(load, source: source, mode: mode)
            let preset = AMDBatteryPowerPolicy.idleLimitPreset(loadTarget: load, appliedTarget: applied)
            return AMDIdleClockLimitPolicy.maxPerf(preset: preset, limitMHz: 800, range: range)
        }
        for mode in modes {
            suite.expect(maxPerf(load: .powerSave, mode: mode) == 25, "\(mode): Eco at idle on battery keeps the idle clock limit")
            suite.expect(maxPerf(load: .powerSave, mode: mode, source: .external) == 25, "\(mode): plugged in, the limit works as before")
            for load in targets where load != .powerSave {
                suite.expect(maxPerf(load: load, mode: mode) == 0, "\(mode): \(load) under load lifts the limit on battery")
                suite.expect(maxPerf(load: load, mode: mode, source: .external) == 0, "\(mode): \(load) plugged in lifts the limit")
            }
        }
        suite.expect(AMDBatteryPowerPolicy.idleLimitPreset(loadTarget: .performance, appliedTarget: .powerSave) == .performance,
                     "an Eco forced by Maximum saving under load is not idle")
        suite.expect(AMDBatteryPowerPolicy.idleLimitPreset(loadTarget: .performance, appliedTarget: .balanced) == .balance,
                     "a capped Balance decides on Balance")
        suite.expect(AMDBatteryPowerPolicy.idleLimitPreset(loadTarget: .powerSave, appliedTarget: .powerSave) == .eco,
                     "Eco at idle decides on Eco")
    }

    private static func backToExternal(_ suite: TestSuite) {
        // A laptop unplugged and plugged back in: each step is decided from
        // the source alone, so nothing from the battery phase lingers.
        let steps: [AMDPowerSource] = [.external, .battery, .external, .battery, .external]
        for mode in modes {
            var seen: [AutoEppTarget] = []
            for source in steps {
                seen.append(AMDBatteryPowerPolicy.autoTarget(.performance, source: source, mode: mode))
            }
            suite.expect(seen[0] == .performance && seen[2] == .performance && seen[4] == .performance,
                         "\(mode): plugged in again, Auto EPP is back to its normal choice (got \(seen))")
            let expected: AutoEppTarget = mode == .sameAsPluggedIn ? .performance
                : mode == .saveMore ? .balanced : .powerSave
            suite.expect(seen[1] == expected && seen[3] == expected,
                         "\(mode): every unplug applies the battery target again (got \(seen))")
        }
    }

    private static func strings(_ suite: TestSuite) {
        let locales: [(String, AMDPowerFeatureStrings)] = [
            ("enUS", .enUS), ("es", .es), ("ptBR", .ptBR), ("de", .de), ("fr", .fr), ("it", .it),
            ("ru", .ru), ("tr", .tr), ("ja", .ja), ("ko", .ko), ("zhHans", .zhHans), ("zhTW", .zhTW),
            ("sk", .sk), ("uk", .uk),
        ]
        for (name, s) in locales {
            let all = [s.batteryModeTitle, s.batteryModeSame, s.batteryModeSaveMore, s.batteryModeMaximum,
                       s.batteryModeSameCaption, s.batteryModeSaveMoreCaption, s.batteryModeMaximumCaption,
                       s.batteryModeNeedsAutoEpp, s.batteryModeUnavailable]
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(name): every On battery string is filled in")
            let labels = modes.map { BatteryPowerRow.label($0, s) }
            suite.expect(Set(labels).count == 3, "\(name): the three modes read differently")
            if name != "enUS" {
                suite.expect(s.batteryModeTitle != AMDPowerFeatureStrings.enUS.batteryModeTitle
                             && s.batteryModeSaveMoreCaption != AMDPowerFeatureStrings.enUS.batteryModeSaveMoreCaption,
                             "\(name): translated, not an English copy")
            }
        }
    }

    /// The service watches IOPS (no poll) and writes nothing; the manual EPP
    /// path does not consult it.
    private static func source(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/RyzenStatus")
        guard let text = try? String(contentsOf: sources.appendingPathComponent("Services/AMD/BatteryPowerService.swift"), encoding: .utf8),
              let manual = try? String(contentsOf: sources.appendingPathComponent("UI/Settings/AmdPowerControlsModel.swift"), encoding: .utf8),
              let presets = try? String(contentsOf: sources.appendingPathComponent("Services/AMD/AmdPresetController.swift"), encoding: .utf8)
        else {
            suite.expect(false, "BatteryPowerService, AmdPowerControlsModel and AmdPresetController readable")
            return
        }
        suite.expect(text.contains("IOPSNotificationCreateRunLoopSource("), "the power source comes from the IOPS notification")
        suite.expect(!text.contains("setCPPCEPPValue") && !text.contains("restoreManualEPP") && !text.contains("Task.sleep"),
                     "no EPP write of its own and no poll loop")
        suite.expect(!manual.contains("BatteryPowerService") && !presets.contains("BatteryPowerService"),
                     "the manual EPP, presets and custom profiles ignore the battery mode")
    }
}
