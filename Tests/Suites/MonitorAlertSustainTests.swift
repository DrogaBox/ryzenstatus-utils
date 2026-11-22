// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The "for at least" wait shared by the Monitor alerts, and the CPU package
/// power alert: when it fires, when it starts over, and when it may repeat.
enum MonitorAlertSustainTests {
    static func run(_ suite: TestSuite) {
        timer(suite)
        sustainChoice(suite)
        sustainedCondition(suite)
        sleepGap(suite)
        cpuPowerTrigger(suite)
        cooldown(suite)
        settings(suite)
        strings(suite)
    }

    private static let start = Date(timeIntervalSince1970: 1_000)
    private static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private static func timer(_ suite: TestSuite) {
        var immediate = OverLimitTimer()
        suite.expect(immediate.update(isOver: true, now: at(0), wait: 0),
                     "with no wait the first sample over the limit counts")
        suite.expect(!immediate.update(isOver: false, now: at(1), wait: 0) && immediate.since == nil,
                     "a sample under the limit clears the timer")

        var timer = OverLimitTimer()
        suite.expect(!timer.update(isOver: true, now: at(0), wait: 30), "the first sample starts a 30 s wait")
        suite.expect(timer.since == at(0), "and records when it started")
        suite.expect(!timer.update(isOver: true, now: at(29), wait: 30), "29 s is not enough")
        suite.expect(timer.update(isOver: true, now: at(30), wait: 30), "30 s over the limit counts")
        suite.expect(timer.update(isOver: true, now: at(31), wait: 30),
                     "every sample after that still counts; the repeat interval holds the notices back")
        suite.expect(!timer.update(isOver: false, now: at(32), wait: 30), "a drop under the limit")
        suite.expect(!timer.update(isOver: true, now: at(33), wait: 30)
                         && !timer.update(isOver: true, now: at(62), wait: 30),
                     "starts the whole wait over")
        suite.expect(timer.update(isOver: true, now: at(63), wait: 30), "which ends 30 s after the new start")
        timer.reset()
        suite.expect(timer.since == nil, "reset forgets the start")
    }

    private static func sustainChoice(_ suite: TestSuite) {
        suite.expect(Defaults.allowedMonitorAlertSustainSeconds == [0, 10, 30, 60],
                     "the choices are Immediately, 10, 30 and 60 seconds")
        suite.expect(MonitorAlertSustain.wait(builtIn: 12, chosenSeconds: 0) == 12
                         && MonitorAlertSustain.wait(builtIn: 5, chosenSeconds: 0) == 5
                         && MonitorAlertSustain.wait(builtIn: 0, chosenSeconds: 0) == 0,
                     "Immediately keeps every alert's own wait")
        suite.expect(MonitorAlertSustain.wait(builtIn: 12, chosenSeconds: 10) == 12,
                     "a choice shorter than the built-in wait never shortens it")
        suite.expect(MonitorAlertSustain.wait(builtIn: 12, chosenSeconds: 30) == 30
                         && MonitorAlertSustain.wait(builtIn: 0, chosenSeconds: 60) == 60,
                     "a longer choice makes the wait longer")
        suite.expect(MonitorAlertSustain.wait(builtIn: 5, chosenSeconds: 45) == 5
                         && Defaults.sanitizedMonitorAlertSustain(-3) == 0,
                     "a stored value outside the menu counts as Immediately")
    }

    private static func sustainedCondition(_ suite: TestSuite) {
        var condition = SustainedCondition(duration: 12, allowedMisses: 2)
        _ = condition.update(true, now: at(0), atLeast: 30)
        suite.expect(!condition.update(true, now: at(12), atLeast: 30),
                     "a GPUSensors alert waits for the longer choice, not its own 12 s")
        suite.expect(condition.update(true, now: at(30), atLeast: 30), "and fires once it has passed")
        var plain = SustainedCondition(duration: 12, allowedMisses: 2)
        _ = plain.update(true, now: at(0))
        suite.expect(plain.update(true, now: at(12), atLeast: 0), "with Immediately it keeps its 12 s")
    }

    /// Nothing samples while the Mac sleeps, so a wait must not count the
    /// time asleep: waking 10 minutes later is no "over the limit for 10 minutes".
    private static func sleepGap(_ suite: TestSuite) {
        var timer = OverLimitTimer()
        _ = timer.update(isOver: true, now: at(0), wait: 600)
        _ = timer.update(isOver: true, now: at(30), wait: 600)
        suite.expect(!timer.update(isOver: true, now: at(630), wait: 600),
                     "the first sample after a 10 min sleep does not fire a 10 min wait")
        suite.expect(timer.since == at(630), "it starts the wait again at the wake")
        suite.expect(!timer.update(isOver: true, now: at(631), wait: 600)
                         && timer.update(isOver: true, now: at(1230), wait: 600) == false,
                     "and a sample every second is still needed to get there")
        var watched = OverLimitTimer()
        var fired = false
        for second in stride(from: 0.0, through: 600, by: 5) {
            fired = watched.update(isOver: true, now: at(second), wait: 600)
        }
        suite.expect(fired, "samples 5 s apart for 10 minutes do fire")
        var slow = OverLimitTimer()
        _ = slow.update(isOver: true, now: at(0), wait: 30)
        suite.expect(slow.update(isOver: true, now: at(15), wait: 30) == false
                         && slow.update(isOver: true, now: at(30), wait: 30),
                     "the slowest 15 s temperature stride is not a break")
        var backwards = OverLimitTimer()
        _ = backwards.update(isOver: true, now: at(100), wait: 10)
        suite.expect(!backwards.update(isOver: true, now: at(50), wait: 10) && backwards.since == at(50),
                     "a clock set back starts the wait over")
        suite.expect(!MonitorAlertSustain.isBreak(since: at(0), now: at(45))
                         && MonitorAlertSustain.isBreak(since: at(0), now: at(46))
                         && !MonitorAlertSustain.isBreak(since: nil, now: at(0)),
                     "a break is a gap over 45 s")

        var condition = SustainedCondition(duration: 12, allowedMisses: 2)
        _ = condition.update(true, now: at(0), atLeast: 60)
        _ = condition.update(true, now: at(5), atLeast: 60)
        suite.expect(!condition.update(true, now: at(605), atLeast: 60) && condition.since == at(605),
                     "a GPUSensors alert does not count the time asleep either")
    }

    private static func cpuPowerTrigger(_ suite: TestSuite) {
        suite.expect(!MonitorAlertService.cpuPowerIsOver(nil, thresholdWatts: 120),
                     "no CPU power reading never fires")
        suite.expect(!MonitorAlertService.cpuPowerIsOver(0, thresholdWatts: 10),
                     "0 W is the kext saying it has no reading")
        suite.expect(!MonitorAlertService.cpuPowerIsOver(119.9, thresholdWatts: 120), "under the limit")
        suite.expect(MonitorAlertService.cpuPowerIsOver(120, thresholdWatts: 120)
                         && MonitorAlertService.cpuPowerIsOver(142, thresholdWatts: 120),
                     "at or over the limit")

        // A load that crosses 120 W, dips once, and stays up again.
        let samples: [(TimeInterval, Double?)] = [(0, 130), (5, 131), (8, 90), (9, 135), (20, 136), (21, 137), (40, nil), (41, 140)]
        var timer = OverLimitTimer()
        var fired: [TimeInterval] = []
        for (time, watts) in samples {
            let wait = MonitorAlertSustain.wait(builtIn: 12, chosenSeconds: 0)
            if timer.update(isOver: MonitorAlertService.cpuPowerIsOver(watts, thresholdWatts: 120),
                            now: at(time), wait: wait) {
                fired.append(time)
            }
        }
        suite.expect(fired == [21], "the dip at 8 s starts the 12 s over and a lost reading re-arms it, got \(fired)")
    }

    private static func cooldown(_ suite: TestSuite) {
        enum Kind: Hashable { case cpuPower, gpuPower }
        var gate = AlertCooldownGate<Kind>()
        let interval: TimeInterval = 15 * 60
        suite.expect(gate.allows(.cpuPower, now: at(0), interval: interval), "the first notice goes out")
        suite.expect(!gate.allows(.cpuPower, now: at(60), interval: interval), "the same alert waits for the repeat interval")
        suite.expect(gate.allows(.gpuPower, now: at(60), interval: interval), "another kind has its own interval")
        suite.expect(gate.allows(.cpuPower, now: at(interval), interval: interval), "after the interval it may repeat")
    }

    private static func settings(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.monitorAlertCPUPower] as? Bool == false,
                     "the CPU power alert is off out of the box")
        suite.expect(registered[DefaultsKey.monitorAlertCPUPowerThreshold] as? Int == 120
                         && Defaults.monitorAlertCPUPowerRange == 10...300,
                     "it starts at 120 W, chosen from 10 to 300 W")
        suite.expect(registered[DefaultsKey.monitorAlertSustainSeconds] as? Int == 0,
                     "the wait starts at Immediately, so the other alerts behave as before")
        suite.expect(Defaults.sanitizedMonitorAlertCPUPowerThreshold(5) == 120
                         && Defaults.sanitizedMonitorAlertCPUPowerThreshold(200) == 200,
                     "an out-of-range threshold goes back to the default")
        let cpuOnly: (AppFeature) -> Bool = { $0 == .monitorCPU }
        let powerOnly: (String) -> Bool = { $0 == DefaultsKey.monitorAlertCPUPower }
        suite.expect(AppFeature.anyMonitorAlertEnabled(isAvailable: cpuOnly, boolFor: powerOnly),
                     "the CPU power switch alone keeps the alert service running")
        suite.expect(SystemMonitorPanelNeeds.alerts(boolFor: powerOnly, isAvailable: cpuOnly,
                                                    hasInternalBattery: false, gpuSensorsPresent: false).cpu,
                     "and samples the CPU, which carries the kext package power")
    }

    private static func strings(_ suite: TestSuite) {
        let english = FeatureStrings.monitorAlerts(.enUS)
        for language in AppLanguage.allCases {
            let text = FeatureStrings.monitorAlerts(language)
            let all = [text.cpuPower, text.cpuPowerThreshold, text.cpuPowerTitle, text.cpuPowerBodyFormat,
                       text.sustain, text.sustainImmediately, text.sustain10, text.sustain30, text.sustain60]
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(language): every new alert string is filled in")
            suite.expect(text.cpuPowerBodyFormat.contains("%.0f"), "\(language): the body shows the watts")
            if language != .enUS {
                suite.expect(text.sustain != english.sustain && text.sustainImmediately != english.sustainImmediately,
                             "\(language): the wait menu is translated")
            }
        }
    }
}
