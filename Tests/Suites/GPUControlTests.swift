// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The "GPU control" readout: what GPUSensors.kext 0.3.0 and 0.4.0 publish
/// about their GPU control, read from the same property table as the sensors.
enum GPUControlTests {
    static func run(_ suite: TestSuite) {
        versions(suite)
        states(suite)
        powerWatch(suite)
        robustness(suite)
        translations(suite)
        powerRange(suite)
    }

    private static let en = GPUControlStrings.enUS

    /// GPUSensors 0.2.0: sensors only, no control keys.
    private static var v020: [String: Any] {
        [
            "Status": "active",
            "StatusCode": NSNumber(value: 1),
            "Library": "AMDRadeonX6000HWLibs",
            "SampleAgeMs": NSNumber(value: 640),
            "Sensors": ["Hotspot temperature": NSNumber(value: 40)],
            "Units": ["Hotspot temperature": "C"],
        ]
    }

    /// GPUSensors 0.3.0 on the test RX 6800 XT (macOS 26.7.3, 2026-11-19),
    /// as `ioreg -r -c DrogaBoxGPUSensors -l` showed it, no `gpuprofile`.
    private static var v030: [String: Any] {
        var p = v020
        p["Control"] = "watching the profile requests"
        p["Profile"] = "not asked: macOS keeps its 16 (compute)"
        p["ProfileRequests"] = ["Seen": NSNumber(value: 0), "Calls": NSNumber(value: 13), "Last": NSNumber(value: 0)]
        return p
    }

    /// GPUSensors 0.4.0, made up from kern_service.cpp's `publish()` (not yet
    /// booted): every function watched, the boot limit read, nothing sent.
    private static func v040(watch: [String: Any]? = nil,
                             power: String = "watching the power limit, sleep and wake") -> [String: Any] {
        var p = v030
        p["Power"] = power
        p["PowerWatch"] = watch ?? [
            "BootW": NSNumber(value: 240), "LastReadW": NSNumber(value: 240), "Reads": NSNumber(value: 2),
            "Sent": NSNumber(value: 0), "Sleeps": NSNumber(value: 1), "Wakes": NSNumber(value: 1),
        ]
        return p
    }

    private static func row(_ rows: [GPUControlRow], _ id: String) -> GPUControlRow? {
        rows.first { $0.id == id }
    }

    private static func versions(_ suite: TestSuite) {
        suite.expect(GPUControlStatus.parse(v020) == nil, "0.2.0 has no GPU control, so no group")
        suite.expect(GPUControlStatus.parse([:]) == nil, "no properties, no group")
        suite.expect(GPUSensorsReading.parse(v030) != nil, "the control keys do not disturb the sensor reading")

        let s030 = GPUControlStatus.parse(v030)
        suite.expect(s030?.control == .watching, "0.3.0: the control watches the profile requests")
        suite.expect(s030?.profile == .macOSDefault, "0.3.0: nobody asked for a profile")
        suite.expect(s030?.power == nil && s030?.powerWatch == nil, "0.3.0 has no power watch")
        let rows030 = s030?.rows(en) ?? []
        suite.expect(rows030.map(\.id) == ["Control", "Profile"], "0.3.0 shows the control and the boot profile only")
        suite.expect(row(rows030, "Control")?.value == "Watching profile requests", "the control row in words")
        suite.expect(row(rows030, "Profile")?.value == "macOS default (compute)", "the boot profile row in words")
        suite.expect(rows030.allSatisfy { $0.detail == nil }, "nothing to explain while it watches")
        suite.expect(s030?.summary(en) == "Watching", "the header sums it up")

        let s040 = GPUControlStatus.parse(v040())
        suite.expect(s040?.power == .watching, "0.4.0: the power watch has all four functions")
        let rows040 = s040?.rows(en) ?? []
        suite.expect(rows040.map(\.id) == ["Control", "Profile", "Power", "BootW", "SleepWake"],
                     "0.4.0 with nothing sent: no last-limit row")
        suite.expect(row(rows040, "BootW")?.value == "240 W", "the boot power limit in watts")
        suite.expect(row(rows040, "SleepWake")?.value == "1 / 1", "one sleep, one wake")
        suite.expect(row(rows040, "Power")?.value == "Watching limit, sleep and wake", "the power watch in words")
    }

    private static func states(_ suite: TestSuite) {
        func control(_ text: String) -> GPUControlStatus.Watch { .parse(text) }
        suite.expect(control("waiting for the driver's library") == .waiting, "waiting for the library")
        suite.expect(control("off: -gpuctloff") == .off(reason: "-gpuctloff"), "off by boot argument keeps the reason")
        suite.expect(control("off: no RX 6800 XT (73BF rev C1) found") == .off(reason: "no RX 6800 XT (73BF rev C1) found"),
                     "off on another card keeps the reason")
        suite.expect(control("off") == .off(reason: nil), "a bare off has no reason")
        suite.expect(control("watching in part: see PowerWatch") == .watchingInPart, "a partial power watch")
        suite.expect(control("something new") == .other("something new"), "an unknown state is kept as written")

        func profile(_ text: String) -> GPUControlStatus.Profile { .parse(text) }
        suite.expect(profile("set before the power management started") == .set, "a profile set at boot")
        suite.expect(profile("asked: waiting for the power management to start") == .waiting, "asked, not yet set")
        suite.expect(profile("refused: gpuprofile must be 0, 2 or 16") == .refused(reason: "gpuprofile must be 0, 2 or 16"),
                     "a refused profile keeps the reason")
        suite.expect(profile("not set: no RX 6800 XT found") == .notSet(reason: "no RX 6800 XT found"),
                     "not set keeps the reason")
        suite.expect(profile("off") == .off, "profile off")

        var p = v030
        p["Profile"] = "set before the power management started"
        p["ProfileSet"] = NSNumber(value: 2)
        suite.expect(row(GPUControlStatus.parse(p)?.rows(en) ?? [], "Profile")?.value == "Set at boot: power saving",
                     "a set profile is named")
        p["ProfileSet"] = NSNumber(value: 0)
        suite.expect(row(GPUControlStatus.parse(p)?.rows(en) ?? [], "Profile")?.value == "Set at boot: chosen by the driver",
                     "profile 0 lets the driver choose")
        p["ProfileSet"] = nil
        suite.expect(row(GPUControlStatus.parse(p)?.rows(en) ?? [], "Profile")?.value == "Set at boot",
                     "set without a published value")

        var off = v030
        off["Control"] = "off: -gpuctloff"
        off["Profile"] = "off"
        let offStatus = GPUControlStatus.parse(off)
        let offRows = offStatus?.rows(en) ?? []
        suite.expect(row(offRows, "Control")?.value == "Off" && row(offRows, "Control")?.detail == "-gpuctloff",
                     "an off control says why under the row")
        suite.expect(offStatus?.summary(en) == "Off", "the header says off")

        var refused = v030
        refused["Profile"] = "refused: gpuprofile must be 0, 2 or 16"
        let refusedRow = row(GPUControlStatus.parse(refused)?.rows(en) ?? [], "Profile")
        suite.expect(refusedRow?.value == "Refused" && refusedRow?.detail == "gpuprofile must be 0, 2 or 16",
                     "a refused profile says why")
    }

    private static func powerWatch(_ suite: TestSuite) {
        let sent = GPUControlStatus.parse(v040(watch: [
            "BootW": NSNumber(value: 240), "Reads": NSNumber(value: 1), "LastReadW": NSNumber(value: 240),
            "Sent": NSNumber(value: 3), "LastSentW": NSNumber(value: 220), "LastSentSource": NSNumber(value: 0),
            "LastSentResult": NSNumber(value: 0), "Sleeps": NSNumber(value: 2), "Wakes": NSNumber(value: 2),
        ]))
        let rows = sent?.rows(en) ?? []
        suite.expect(row(rows, "LastSentW")?.value == "220 W", "a limit the firmware took")
        suite.expect(rows.map(\.id) == ["Control", "Profile", "Power", "BootW", "LastSentW", "SleepWake"],
                     "the full 0.4.0 group, in order")
        suite.expect(sent?.powerWatch?.lastSentSource == 0 && sent?.powerWatch?.reads == 1, "every key is read")

        let failed = GPUControlStatus.parse(v040(watch: [
            "Sent": NSNumber(value: 1), "LastSentW": NSNumber(value: 300), "LastSentResult": NSNumber(value: 5),
        ]))
        suite.expect(row(failed?.rows(en) ?? [], "LastSentW")?.value == "300 W, not taken (code 5)",
                     "a limit the firmware refused shows its code")

        // uint32_t results with bit 31 set: a negative error (-1) and an IOReturn.
        func sentRow(_ result: Any?) -> String? {
            var watch: [String: Any] = ["Sent": NSNumber(value: 1), "LastSentW": NSNumber(value: 300)]
            if let result { watch["LastSentResult"] = result }
            return row(GPUControlStatus.parse(v040(watch: watch))?.rows(en) ?? [], "LastSentW")?.value
        }
        suite.expect(sentRow(NSNumber(value: UInt64(0xFFFF_FFFF))) == "300 W, not taken (code 0xFFFFFFFF)",
                     "a -1 result (0xFFFFFFFF) is a refusal, shown in hex")
        suite.expect(sentRow(NSNumber(value: UInt64(0xE000_02BC))) == "300 W, not taken (code 0xE00002BC)",
                     "an IOReturn result is a refusal, shown in hex")
        suite.expect(sentRow(NSNumber(value: Int32.max)) == "300 W, not taken (code 2147483647)",
                     "the largest small code stays decimal")
        suite.expect(sentRow(nil) == "300 W, not confirmed", "a send without a result is not shown as taken")
        suite.expect(sentRow("0") == "300 W, not confirmed", "a result of the wrong type is not shown as taken")
        suite.expect(sentRow(NSNumber(value: UInt64(0x1_0000_0000))) == "300 W, not confirmed",
                     "a result past 32 bits is unreadable, so not taken")
        suite.expect(sentRow(NSNumber(value: 0)) == "300 W", "only a read result of 0 counts as taken")
        suite.expect(GPUControlStatus.resultCode(5) == "5" && GPUControlStatus.resultCode(0xE000_02BC) == "0xE00002BC",
                     "result codes read right")

        let partial = GPUControlStatus.parse(v040(watch: ["BootW": NSNumber(value: 240), "Reads": NSNumber(value: 1),
                                                          "Sleeps": NSNumber(value: 0), "Wakes": NSNumber(value: 0)],
                                                  power: "watching in part: see PowerWatch"))
        let partialRows = partial?.rows(en) ?? []
        suite.expect(row(partialRows, "Power")?.value == "Watching in part", "a partial watch says so")
        suite.expect(row(partialRows, "LastSentW") == nil, "no send function, no last-limit row")
        suite.expect(row(partialRows, "SleepWake")?.value == "0 / 0", "no sleep yet")

        let notSent = GPUControlStatus.parse(v040(watch: ["Sent": NSNumber(value: 0), "LastSentW": NSNumber(value: 200)]))
        suite.expect(row(notSent?.rows(en) ?? [], "LastSentW") == nil, "Sent 0 hides the last limit")

        let onlyWakes = GPUControlStatus.parse(v040(watch: ["Wakes": NSNumber(value: 4)]))
        suite.expect(row(onlyWakes?.rows(en) ?? [], "SleepWake")?.value == "— / 4", "a missing count reads as a dash")
        suite.expect(row(onlyWakes?.rows(en) ?? [], "BootW") == nil, "no boot limit until it was read")

        let empty = GPUControlStatus.parse(v040(watch: [:], power: "waiting for the driver's library"))
        let emptyRows = empty?.rows(en) ?? []
        suite.expect(emptyRows.map(\.id) == ["Control", "Profile", "Power"], "an empty power watch adds no rows")
        suite.expect(row(emptyRows, "Power")?.value == "Waiting for the driver", "a waiting power watch")

        var noWatch = v040()
        noWatch["Power"] = "off: none of its functions could be routed"
        noWatch["PowerWatch"] = nil
        let noWatchRow = row(GPUControlStatus.parse(noWatch)?.rows(en) ?? [], "Power")
        suite.expect(noWatchRow?.value == "Off" && noWatchRow?.detail == "none of its functions could be routed",
                     "a power watch that is off says why")
    }

    private static func robustness(_ suite: TestSuite) {
        suite.expect(GPUControlStatus.integer(NSNumber(value: -1)) == nil, "a negative count is no value")
        suite.expect(GPUControlStatus.integer(NSNumber(value: 2.5)) == nil, "a fraction is no count")
        suite.expect(GPUControlStatus.integer(kCFBooleanTrue) == nil, "a boolean is no number")
        suite.expect(GPUControlStatus.integer("240") == nil, "a string is no number")
        suite.expect(GPUControlStatus.integer(NSNumber(value: UInt64.max)) == nil, "an absurd value is dropped")
        suite.expect(GPUControlStatus.integer(NSNumber(value: UInt32.max)) == Int(UInt32.max),
                     "a full uint32_t value is read")
        suite.expect(GPUControlStatus.integer(NSNumber(value: UInt64(UInt32.max) + 1)) == nil,
                     "past uint32_t is no value")
        // The uint64_t counters (Reads, Sent, Sleeps, Wakes) keep their row past uint32_t.
        let big = UInt64(UInt32.max) + 1
        suite.expect(GPUControlStatus.count(NSNumber(value: big)) == Int(big), "a uint64_t count past uint32_t is read")
        suite.expect(GPUControlStatus.count(NSNumber(value: -1)) == nil, "a negative count is no value")
        suite.expect(GPUControlStatus.count(NSNumber(value: 2.5)) == nil, "a fraction is no count")
        suite.expect(GPUControlStatus.count(kCFBooleanTrue) == nil, "a boolean is no count")
        suite.expect(GPUControlStatus.count(NSNumber(value: UInt64.max)) == nil, "a count past Int.max is no value")
        let bigWatch = GPUControlStatus.PowerWatch.parse([
            "Reads": NSNumber(value: big), "Sent": NSNumber(value: big), "Sleeps": NSNumber(value: big),
            "Wakes": NSNumber(value: big), "LastSentResult": NSNumber(value: big),
        ])
        suite.expect(bigWatch?.reads == Int(big) && bigWatch?.sent == Int(big) && bigWatch?.sleeps == Int(big)
                         && bigWatch?.wakes == Int(big) && bigWatch?.lastSentResult == nil,
                     "PowerWatch: the counters read as uint64_t, the result as uint32_t")

        for blank in ["", "   ", "\n"] {
            var noControl = v030
            noControl["Control"] = blank
            suite.expect(GPUControlStatus.parse(noControl) == nil, "a blank control means no group")
            var blanks = v040()
            blanks["Profile"] = blank
            blanks["Power"] = blank
            let ids = GPUControlStatus.parse(blanks)?.rows(en).map(\.id)
            suite.expect(ids == ["Control", "BootW", "SleepWake"], "blank profile and power texts give no rows")
        }
        suite.expect(GPUControlStatus.parse(["Control": "  watching the profile requests "])?.control == .watching,
                     "the kext's text is trimmed")
        suite.expect(GPUControlStatus.Profile.parse("setting up") == .other("setting up"),
                     "a word that only starts like \"set\" is not a set profile")
        suite.expect(GPUControlStatus.Profile.parse("asking") == .other("asking"), "nor \"asking\" a request")
        suite.expect(GPUControlStatus.Profile.parse("set") == .set, "a bare \"set\" is")
        suite.expect(GPUControlStatus.Watch.parse("waitingroom") == .other("waitingroom"),
                     "a word that only starts like \"waiting\" is kept as written")
        suite.expect(GPUControlStatus.Watch.parse("offline") == .other("offline"), "\"offline\" is not off")
        suite.expect(GPUControlStatus.Watch.parse("watching") == .watching, "a bare \"watching\" is")
        var wrong = v040(watch: ["BootW": "240", "Sleeps": NSNumber(value: 3)])
        wrong["Profile"] = NSNumber(value: 1)
        let status = GPUControlStatus.parse(wrong)
        suite.expect(status?.profile == nil, "a profile that is not text is left out")
        suite.expect(status?.rows(en).map(\.id) == ["Control", "Power", "SleepWake"],
                     "keys of the wrong type drop their row only")
        var wrongControl = v030
        wrongControl["Control"] = NSNumber(value: 1)
        suite.expect(GPUControlStatus.parse(wrongControl) == nil, "a control that is not text means no group")
        suite.expect(GPUControlStatus.parse(v040()) == GPUControlStatus.parse(v040()), "equal reads compare equal")
    }

    /// The power range row after the start-up limit: the kext's `PowerRange`
    /// (0.8.0), the OD8 table's for 0.7.x, and "not known" with the kext's
    /// reason under it.
    private static func powerRange(_ suite: TestSuite) {
        func v080(_ range: [String: Any], state: String? = "from the card: start-up limit less its OD8 power percent",
                  writeOff: Int = 0) -> [String: Any] {
            var p = v040()
            p["Write"] = "closed: an administrator opens it until restart"
            p["WriteState"] = ["WriteOff": NSNumber(value: writeOff)]
            p["PowerRange"] = range
            if let state { p["PowerRangeState"] = state }
            return p
        }
        let known: [String: Any] = ["Known": NSNumber(value: 1), "FloorW": NSNumber(value: 225),
                                    "MaxW": NSNumber(value: 240), "StepW": NSNumber(value: 10)]
        let rows = GPUControlStatus.parse(v080(known))?.rows(en) ?? []
        suite.expect(rows.map(\.id) == ["Control", "Profile", "Power", "BootW", "PowerRange", "SleepWake"],
                     "0.8.0: the power range right after the start-up limit")
        let kext = row(rows, "PowerRange")
        suite.expect(kext?.label == "Power range" && kext?.value == "225–240 W in 10 W steps"
                        && kext?.detail == nil && kext?.isNumber == true,
                     "0.8.0, known: floor to maximum and the step (\(kext?.value ?? "none"))")
        suite.expect(row(GPUControlStatus.parse(v080(known))?.rows(GPUControlStrings.es) ?? [], "PowerRange")?.value
                        == "225–240 W en pasos de 10 W", "the same in Spanish")
        var step5 = known
        step5["StepW"] = NSNumber(value: 5)
        suite.expect(row(GPUControlStatus.parse(v080(step5))?.rows(en) ?? [], "PowerRange")?.value
                        == "225–240 W in 5 W steps", "the step is the kext's")
        // The read-only card publishes its range for showing.
        suite.expect(row(GPUControlStatus.parse(v080(known, writeOff: 15))?.rows(en) ?? [], "PowerRange")?.value
                        == "225–240 W in 10 W steps", "the read-only card: its own range")
        var flat = known
        flat["FloorW"] = NSNumber(value: 240)
        suite.expect(row(GPUControlStatus.parse(v080(flat, state: "the card offers no lower power limit: only the start-up limit"))?
                            .rows(en) ?? [], "PowerRange")?.value == "240 W only",
                     "a floor at the start-up limit: that value only")
        let notYet = "not known yet: waiting for a clean OD8 read"
        let unknown = row(GPUControlStatus.parse(v080(["Known": NSNumber(value: 0), "StepW": NSNumber(value: 10)],
                                                      state: notYet))?.rows(en) ?? [], "PowerRange")
        suite.expect(unknown?.value == "Not known yet" && unknown?.detail == notYet && unknown?.isNumber == false,
                     "0.8.0, not known: says so, with the kext's reason under it")
        var odd = known
        odd["FloorW"] = NSNumber(value: 250)
        suite.expect(row(GPUControlStatus.parse(v080(odd))?.rows(en) ?? [], "PowerRange")?.value == "Not known yet",
                     "a floor above the maximum: not known")
        suite.expect(row(GPUControlStatus.parse(v040())?.rows(en) ?? [], "PowerRange") == nil,
                     "no write path (0.4.0): no power range row")

        // 0.7.2, the card's real properties: no PowerRange, so the range comes
        // from the OD8 table (240 W less 6 %), marked as the app's.
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        let table = FileManager.default.contents(atPath: path)
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
        let legacy = table.flatMap(GPUControlStatus.parse)
        suite.expect(legacy?.writing?.powerRange == nil, "0.7.2 publishes no PowerRange")
        suite.expect(row(legacy?.rows(en) ?? [], "PowerRange")?.value == "225–240 W in 10 W steps, from the card’s table",
                     "0.7.2: worked out from the OD8 table, and says so (\(row(legacy?.rows(en) ?? [], "PowerRange")?.value ?? "none"))")
        var unread = table ?? [:]
        unread["OD8State"] = "not read: waiting for the driver"
        suite.expect(row(GPUControlStatus.parse(unread)?.rows(en) ?? [], "PowerRange")?.value == "Not known yet",
                     "0.7.2 without a clean OD8 read: not known")

        for language in AppLanguage.allCases {
            let s = FeatureStrings.gpuControl(language)
            let range = String(format: s.powerRangeFormat, 225, 240, 10)
            suite.expect(range.contains("225") && range.contains("240") && range.contains("10") && !range.contains("%"),
                         "\(language): the range takes the floor, the maximum and the step")
            let only = String(format: s.powerRangeOnlyFormat, 240)
            suite.expect(only.contains("240") && !only.contains("%"), "\(language): one value")
            let derived = String(format: s.powerRangeDerivedFormat, range)
            suite.expect(derived.contains(range) && derived != range && !derived.contains("%@"),
                         "\(language): the derived range keeps the range and marks it")
            suite.expect(!s.powerRange.isEmpty && !s.powerRangeUnknown.isEmpty && s.powerRange != s.bootPowerLimit,
                         "\(language): the power range row has its own label and a not-known text")
            if language != .enUS {
                suite.expect(s.powerRange != en.powerRange && s.powerRangeUnknown != en.powerRangeUnknown,
                             "\(language): the power range row is translated")
            }
        }
    }

    private static func translations(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let s = FeatureStrings.gpuControl(language)
            let labels = [s.title, s.control, s.bootProfile, s.powerWatch, s.bootPowerLimit,
                          s.lastLimitSent, s.sleepsWakes]
            let values = [s.watching, s.waiting, s.off, s.watchingProfileRequests, s.watchingPowerLimit,
                          s.watchingInPart, s.waitingForDriver, s.profileMacOSDefault, s.profileSetAtBoot,
                          s.profileWaiting, s.refused, s.notSet, s.profileDriverChooses, s.profilePowerSaving,
                          s.profileCompute, s.footer]
            suite.expect(Set(labels).count == labels.count && labels.allSatisfy { !$0.isEmpty },
                         "\(language): the GPU control labels are filled and distinct")
            suite.expect(Set(values).count == values.count && values.allSatisfy { !$0.isEmpty },
                         "\(language): the GPU control states are filled and distinct")
            suite.expect(s.profileSetFormat.components(separatedBy: "%@").count == 2
                             && !s.profileSetFormat.contains("%d"),
                         "\(language): the set-profile text takes one name")
            suite.expect(s.notTakenFormat.components(separatedBy: "%@").count == 3
                             && !s.notTakenFormat.contains("%d"),
                         "\(language): the not-taken text takes the watts and the code")
            let notTaken = String(format: s.notTakenFormat, "220 W", "0xE00002BC")
            suite.expect(!notTaken.contains("%") && notTaken.contains("220 W") && notTaken.contains("0xE00002BC"),
                         "\(language): the not-taken text formats cleanly")
            suite.expect(s.unconfirmedFormat.components(separatedBy: "%@").count == 2
                             && !String(format: s.unconfirmedFormat, "220 W").contains("%")
                             && s.unconfirmedFormat != s.notTakenFormat,
                         "\(language): the unconfirmed text takes the watts")
            if language != .enUS {
                suite.expect(s.title != GPUControlStrings.enUS.title && s.footer != GPUControlStrings.enUS.footer,
                             "\(language): the group is translated")
            }
        }
        suite.expect(FeatureStrings.gpuControl(.zhHK).title == FeatureStrings.gpuControl(.zhTW).title,
                     "Hong Kong uses the traditional Chinese texts")
    }
}
