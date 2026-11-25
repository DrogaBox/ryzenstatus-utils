// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum AwdlActivityTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        text(suite)
        gate(suite)
        translations(suite)
        defaults(suite)
    }

    private static func number(_ value: Int) -> NSNumber { NSNumber(value: value) }

    private static func parsing(_ suite: TestSuite) {
        let active = AwdlActivity.parse(peers: number(2), channel: number(149), led: number(1))
        suite.expect(active == AwdlActivity(peers: 2, channel: 149, led: .status),
                     "the driver's three numbers make one AWDL reading")
        suite.expect(active?.isActive == true, "peers above zero count as active")
        suite.expect(AwdlActivity.parse(peers: number(0), channel: number(0))?.isActive == false,
                     "no peers and no channel is a reading, idle")
        suite.expect(AwdlActivity.parse(peers: nil, channel: nil) == nil,
                     "a driver without the AWDL numbers gives no reading, so nothing shows")
        suite.expect(AwdlActivity.parse(peers: number(1), channel: nil) == nil
                         && AwdlActivity.parse(peers: nil, channel: number(6)) == nil,
                     "one number alone is no reading")
        suite.expect(AwdlActivity.parse(peers: "2", channel: number(6)) == nil,
                     "a property of another type under the name is not read")
        suite.expect(AwdlActivity.parse(peers: kCFBooleanTrue, channel: number(6)) == nil,
                     "a boolean is not a peer count")
        suite.expect(AwdlActivity.parse(peers: number(-1), channel: number(6)) == nil
                         && AwdlActivity.parse(peers: number(2), channel: number(999)) == nil,
                     "implausible numbers give no reading")
        suite.expect(AwdlActivity.parse(peers: NSNumber(value: 1.5), channel: number(6)) == nil,
                     "a fractional count gives no reading")
        suite.expect(AwdlActivity.parse(peers: number(1), channel: number(6), led: number(7))?.led == nil,
                     "an unknown LED mode is left out, the AWDL numbers stay")
        suite.expect(AwdlActivity.parse(peers: number(1), channel: number(6), led: number(0))?.led == .off
                         && AwdlActivity.parse(peers: number(1), channel: number(6), led: number(2))?.led == .steady,
                     "LED modes 0 and 2 are off and steady")
    }

    private static func text(_ suite: TestSuite) {
        let strings = AwdlStrings.enUS
        suite.expect(AwdlActivity(peers: 3, channel: 149, led: nil).summary(strings) == "Peers: 3 · Channel 149",
                     "an active line shows peers and channel")
        suite.expect(AwdlActivity(peers: 0, channel: 6, led: nil).summary(strings) == "Idle · Channel 6",
                     "an idle line still shows the channel AWDL holds")
        suite.expect(AwdlActivity(peers: 0, channel: 0, led: nil).summary(strings) == "Idle",
                     "channel 0 means none and is left out")
        suite.expect(AwdlActivity(peers: 1, channel: 0, led: nil).notificationBody(strings) == "Peers: 1",
                     "the notification leaves out a missing channel")
        suite.expect(AwdlLedMode.steady.label(strings) == strings.ledSteady, "each LED mode has its label")
    }

    private static func gate(_ suite: TestSuite) {
        let idle = AwdlActivity(peers: 0, channel: 0, led: nil)
        func active(_ peers: Int) -> AwdlActivity { AwdlActivity(peers: peers, channel: 149, led: nil) }

        var gate = AwdlActivationGate(cooldown: 60)
        suite.expect(!gate.observe(active(2), now: 0), "the first reading is a baseline, even when active")
        suite.expect(!gate.observe(idle, now: 1), "going idle never notifies")
        suite.expect(gate.observe(active(1), now: 100), "from no peers to some notifies")
        suite.expect(!gate.observe(active(3), now: 101), "more peers while active do not notify again")
        suite.expect(!gate.observe(idle, now: 102) && !gate.observe(active(1), now: 110),
                     "a new burst inside the cooldown stays quiet")
        _ = gate.observe(idle, now: 170)
        suite.expect(gate.observe(active(1), now: 171), "a new burst after the cooldown notifies")

        var vanish = AwdlActivationGate(cooldown: 0)
        _ = vanish.observe(idle, now: 0)
        _ = vanish.observe(nil, now: 1)
        suite.expect(!vanish.observe(active(1), now: 2),
                     "a reading right after the numbers were missing is a new baseline")

        var reset = AwdlActivationGate(cooldown: 0)
        _ = reset.observe(idle, now: 0)
        reset.reset()
        suite.expect(!reset.observe(active(1), now: 1), "after a reset the next reading is a baseline")
    }

    private static func translations(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.awdl(language)
            let fields = [strings.rowTitle, strings.idle, strings.peersFormat, strings.channelFormat, strings.led,
                          strings.ledOff, strings.ledStatus, strings.ledSteady, strings.notifyToggle,
                          strings.notifyHint, strings.notificationTitle]
            suite.expect(fields.allSatisfy { !$0.isEmpty } && Set(fields).count == fields.count,
                         "\(language): the AWDL labels are filled and distinct")
            for format in [strings.peersFormat, strings.channelFormat] {
                suite.expect(format.components(separatedBy: "%d").count == 2
                                 && !String(format: format, 7).contains("%"),
                             "\(language): \(format) takes exactly one number")
            }
        }
    }

    private static func defaults(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.monitorAlertAwdl] as? Bool == false,
                     "the AWDL notification starts off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.monitorNetAwdl] as? Bool == true,
                     "the AWDL line shows by default where the driver reports AWDL")
    }
}
