// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// GPUSensors 0.9.0's GFX voltage and raises: the wire forms and numbers,
/// the rules one step past every limit, the recommended starting point, the
/// model and the controller, what is never asked for again at launch, the
/// overclock switch, the gating, the words.
enum GPUControlOverclockTests {
    static func run(_ suite: TestSuite) {
        wire(suite)
        rules(suite)
        voltLogic(suite)
        overclockLogic(suite)
        model(suite)
        controller(suite)
        remembering(suite)
        gating(suite)
        strings(suite)
    }

    private typealias Want = GPUControlOD8Want
    private typealias Harness = GPUControlChannelTests.Harness
    private typealias Policy = GPUControlRememberPolicy

    /// The test card's table (`ioreg-0.7.2-2026-11-20.plist`): GfxVoltOffset
    /// 881 to 1075 mV, stock 1075; GfxMaxMHz up to 2800, stock 2359.
    private static func realWriting(takes: GPUControlOD8Held? = [.curve, .zeroRpmOff, .gfxMax, .gfxMin, .volt, .gfxMaxUp])
        -> GPUControlStatus.Writing? {
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var writing = GPUControlStatus.parse(dict)?.writing else { return nil }
        writing.od8State?.takes = takes
        return writing
    }

    // MARK: Wire

    private static func wire(_ suite: TestSuite) {
        suite.expect(Want(voltMV: 1_050).scalars() == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1_050],
                     "a voltage: 15 scalars, the 15th in mV, a stock minimum as 0")
        suite.expect(Want(gfxMinMHz: 1_500, voltMV: 1_050).scalars()?.suffix(2) == [1_500, 1_050],
                     "a minimum and a voltage: both in the 15-scalar form")
        suite.expect(Want(gfxMaxMHz: 2_500, overclock: true).scalars()
                        == [2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2_500],
                     "a raised maximum: the 13-scalar form with the overclock flag 4")
        suite.expect(Want(gfxMaxMHz: 2_500, gfxMinMHz: 1_500, overclock: true).scalars()?.count == 14,
                     "with a minimum and no voltage: 14 scalars, the shortest form")
        suite.expect(Want(voltMV: 0).scalars() == nil, "a voltage of 0 would read as stock: not sent")
        suite.expect(Want(overclock: true).isStock && !Want(voltMV: 1_050).isStock,
                     "the overclock flag alone is the stock state; a voltage is a hold")
        suite.expect(Want(voltMV: 1_050).heldFlags == .volt, "a voltage: held bit 32")
        let raised = Want(gfxMaxMHz: 2_500, overclock: true)
        suite.expect(raised.heldFlags == .gfxMax && raised.heldFlags(stockGfxMaxMHz: 2_359) == [.gfxMax, .gfxMaxUp]
                        && Want(gfxMaxMHz: 2_359, overclock: true).heldFlags(stockGfxMaxMHz: 2_359) == .gfxMax,
                     "a maximum above stock with the flag: bits 4 and 64; at stock, 4 alone (od8RaisesGfxMax)")
        suite.expect(raised.matches(held: [.gfxMax, .gfxMaxUp]) && raised.matches(held: .gfxMax)
                        && !Want(gfxMaxMHz: 2_000).matches(held: [.gfxMax, .gfxMaxUp])
                        && !Want(voltMV: 1_050).matches(held: .gfxMax),
                     "status matches a raised maximum with or without bit 64, a lowered one never with it")
        // The raise form of set, through the model's dispatcher.
        let fake = FakeGPUControlKext()
        fake.takesOverclock = true
        fake.arm()
        let c = fake.connection()
        _ = c.open()
        let answer = c.setPower(watts: 250, raise: true)
        suite.expect(fake.calls.last?.input == [2, 250, 1] && answer?.reply == .ok,
                     "set's raise form: {version, watts, 1}")
        suite.expect(c.call(.set, input: [2, 250, 2], outputCount: 1) == [GPUControlReply.badArgs.rawValue],
                     "a set flag the kext does not know: malformed")
    }

    // MARK: Rules

    private static func rules(_ suite: TestSuite) {
        guard let table = realWriting()?.od8, let base = GPUControlCurveRules.State(table: table) else {
            suite.expect(false, "rules: the 0.7.2 table loads")
            return
        }
        typealias R = GPUControlCurveRules
        suite.expect(base.first[R.gfxVolt] == R.Entry(feature: 0x20000, min: 881, max: 1_075, def: 1_075)
                        && base.notAllowed == 0xfffc_c0f2,
                     "the card's voltage entry and the NotAllowed mask, from the table")
        func check(_ want: Want, _ state: R.State = base) -> GPUControlOD8Check { R.check(want, state).check }
        suite.expect(check(Want(gfxMaxMHz: 2_800, overclock: true)) == .ok
                        && check(Want(gfxMaxMHz: 2_801, overclock: true)) == .gfxRange,
                     "overclock: the card's 2800 MHz is taken, one step above (2801) is refused")
        suite.expect(check(Want(gfxMaxMHz: 2_360)) == .gfxRange, "above stock without the flag: refused")
        suite.expect(check(Want(voltMV: 1_050)) == .ok && check(Want(voltMV: 900)) == .ok,
                     "1050 and 900 mV: whole 25 mV steps inside the card's range")
        suite.expect(check(Want(voltMV: 1_076)) == .voltRange, "stock + 1 mV: refused (lower only)")
        suite.expect(check(Want(voltMV: 880)) == .voltRange, "the card's minimum - 1 mV: refused")
        suite.expect(check(Want(voltMV: 1_060)) == .voltRange, "not a 25 mV step from stock: refused")
        var blocked = base
        blocked.notAllowed |= 0x20000
        suite.expect(check(Want(voltMV: 1_050), blocked) == .noFeature, "the driver does not allow it now: no feature")
        var missing = base
        missing.first[R.gfxVolt].feature = 0
        missing.fresh[R.gfxVolt].feature = 0
        suite.expect(check(Want(voltMV: 1_050), missing) == .noFeature, "not offered: no feature")
    }

    // MARK: The voltage control

    private static func voltLogic(_ suite: TestSuite) {
        typealias V = GPUControlVoltLogic
        let card = V.Limits(min: 881, stock: 1_075)
        suite.expect(V.range(card) == 900...1_075, "900 to 1075 mV: the lowest 25 mV step at or above 881")
        suite.expect(V.lowers(1_050, limits: card) && V.lowers(900, limits: card), "1050 and 900 lower it")
        suite.expect(!V.lowers(1_075, limits: card) && !V.lowers(1_076, limits: card) && !V.lowers(875, limits: card)
                        && !V.lowers(1_060, limits: card) && !V.lowers(1_050, limits: nil),
                     "stock, above, below the minimum, off a step, or no table: never a hold")
        suite.expect(V.request(1_075, stockMV: 1_075) == nil && V.request(1_050, stockMV: 1_075) == 1_050,
                     "choosing stock is the way back")
        suite.expect(V.snapped(1_040, range: 900...1_075) == 1_050 && V.snapped(870, range: 900...1_075) == 900
                        && V.snapped(1_090, range: 900...1_075) == 1_075,
                     "25 mV steps from stock, inside the range")
        suite.expect(V.tickCount(range: 900...1_075) == 8, "a tick every step")
        // The starting point: relative to the card's own stock value.
        suite.expect(V.recommended(card) == 1_050, "one step below stock: 1050 mV on the test card")
        suite.expect(V.recommended(V.Limits(min: 900, stock: 1_100)) == 1_075, "from the table, never a fixed number")
        suite.expect(V.recommended(V.Limits(min: 1_060, stock: 1_075)) == nil, "below the card's minimum: not offered")
        suite.expect(V.recommended(nil) == nil, "no voltage offered: no starting point")
        // From the table.
        if let writing = realWriting() {
            suite.expect(V.limits(writing: writing, od8Ready: true) == card, "the card's voltage: 881, stock 1075")
            suite.expect(V.limits(writing: writing, od8Ready: false) == nil, "no clean read: no voltage")
            var older = writing
            older.od8State?.takes = [.curve, .zeroRpmOff, .gfxMax, .gfxMin]
            suite.expect(V.limits(writing: older, od8Ready: true) == nil, "Takes without 32: no voltage")
            var blocked = writing
            let mask = blocked.od8?.notAllowed ?? 0
            blocked.od8?.notAllowed = mask | 0x20000
            suite.expect(V.limits(writing: blocked, od8Ready: true) == nil, "NotAllowed has the voltage: none")
            var page = GPUControlPageInput(facts: facts(), state: .ready, snapshot: nil)
            page.writing = writing
            suite.expect(GPUControlVoltSection.recommendedMV(page) == 1_050, "the section offers 1050 mV here")
            page.writing = older
            suite.expect(GPUControlVoltSection.recommendedMV(page) == nil && !GPUControlVoltSection.shows(page),
                         "not offered: no section, no starting point")
        } else {
            suite.expect(false, "volt: the 0.7.2 fixture loads")
        }
        suite.expect(V.checked(Want(gfxMaxMHz: 2_000, voltMV: 1_060), limits: card) == Want(gfxMaxMHz: 2_000)
                        && V.checked(Want(voltMV: 1_050), limits: nil) == .stock
                        && V.checked(Want(voltMV: 1_050), limits: card) == Want(voltMV: 1_050),
                     "a voltage the kext would not take is left out, the rest kept")
    }

    // MARK: The overclock control

    private static func overclockLogic(_ suite: TestSuite) {
        typealias O = GPUControlOverclockLogic
        let limits = O.GfxLimits(stock: 2_359, max: 2_800)
        suite.expect(O.raises(2_800, limits: limits) && O.raises(2_360, limits: limits), "up to the card's 2800 MHz")
        suite.expect(!O.raises(2_801, limits: limits) && !O.raises(2_359, limits: limits) && !O.raises(2_500, limits: nil),
                     "one step above the card's maximum, stock, or no table: never a raise")
        suite.expect(O.request(2_359, stockMHz: 2_359) == nil && O.request(2_500, stockMHz: 2_359) == 2_500,
                     "stock is the way back")
        suite.expect(O.snapped(2_363, range: 2_359...2_800) == 2_359 && O.snapped(2_797, range: 2_359...2_800) == 2_800,
                     "10 MHz steps from stock, the card's top on its own")
        if let writing = realWriting() {
            suite.expect(O.gfxLimits(writing: writing, od8Ready: true) == limits, "from the table: 2359 to 2800 MHz")
            var older = writing
            older.od8State?.takes = [.curve, .zeroRpmOff, .gfxMax, .gfxMin, .volt]
            suite.expect(O.gfxLimits(writing: older, od8Ready: true) == nil, "Takes without 64: no raised maximum")
        }
        suite.expect(O.powerChoices(bootW: 240, ceilW: 261) == [240, 250, 260, 261],
                     "start-up, the 10 W steps above it, and the ceiling itself")
        suite.expect(O.powerChoices(bootW: 240, ceilW: 240).isEmpty && O.powerChoices(bootW: 240, ceilW: nil).isEmpty,
                     "nothing above the start-up limit: no raised pop-up")
        var f = facts()
        suite.expect(O.ceilingW(facts: f) == 261, "CeilW 261 above MaxW 240, with the raise flag")
        f.takesRaise = false
        suite.expect(O.ceilingW(facts: f) == nil, "a kext without the raise flag: no ceiling")
        f = facts()
        f.powerRange?.ceilW = 240
        suite.expect(O.ceilingW(facts: f) == nil, "CeilW = MaxW: nothing higher")
    }

    /// The test card's power facts: 240 W at start-up, 225 to 261 W.
    private static func facts() -> GPUControlFacts {
        var f = GPUControlFacts(source: .properties)
        f.ready = true
        f.armed = true
        f.od8Ready = true
        f.takesRaise = true
        f.bootW = 240
        f.powerRange = GPUControlPowerRange(source: .kext, floorW: 225, maxW: 240, ceilW: 261, stepW: 10,
                                            percentMin: -6, percentMax: 9)
        return f
    }

    // MARK: The model

    private static func model(_ suite: TestSuite) {
        let fake = FakeGPUControlKext()
        fake.takesOverclock = true
        fake.powerPercentMax = 9
        fake.arm()
        let c = fake.connection()
        _ = c.open()
        let range = GPUControlService.fakeControl(fake)?.writing?.powerRange
        suite.expect(range?.ceilW == 261 && range?.maxW == 240, "PowerRange CeilW 261 at 240 W (+9 %)")
        suite.expect(c.status()?.flags.isSuperset(of: [.volt, .raise]) == true
                        && GPUControlService.fakeControl(fake)?.writing?.od8State?.takes?.rawValue == 119,
                     "status flags 1024 and 2048, Takes 119")
        // The power ceiling, one past it, a step past it.
        func set(_ watts: UInt32) -> GPUControlReply? {
            let reply = c.setPower(watts: watts, raise: true)?.reply
            fake.advance(by: 3_000)
            return reply
        }
        suite.expect(set(262) == .aboveCeiling && set(271) == .aboveCeiling, "CeilW + 1 and CeilW + 10: above the ceiling")
        suite.expect(set(255) == .notAStep, "off a 10 W step: refused")
        suite.expect(c.setPower(watts: 250)?.reply == .aboveBoot, "above start-up without the raise flag: as before")
        suite.expect(set(261) == .ok && c.status()?.heldW == 261, "the ceiling itself is taken")
        _ = c.release()
        fake.advance(by: 3_000)
        fake.dogSees = false
        suite.expect(set(250) == .noReadings, "no fresh readings: no raised limit")
        fake.dogSees = true
        // A voltage.
        suite.expect(c.setOD8(Want(voltMV: 1_050))?.reply == .ok
                        && GPUControlService.fakeControl(fake)?.writing?.od8State?.voltHeld == 1_050
                        && c.status()?.od8Held == .volt, "a voltage held: VoltHeld 1050, held bit 32")
        fake.advance(by: 3_000)
        let refused = c.setOD8(Want(voltMV: 1_060))
        suite.expect(refused?.reply == .od8Refused && refused?.check == .voltRange, "off a step: VoltRange")
        fake.advance(by: 3_000)
        let up = c.setOD8(Want(gfxMaxMHz: 2_801, overclock: true))
        suite.expect(up?.check == .gfxRange, "2801 MHz with the flag: refused")
        fake.advance(by: 3_000)
        suite.expect(c.setOD8(Want(gfxMaxMHz: 2_800, overclock: true))?.reply == .ok
                        && c.status()?.od8Held == [.gfxMax, .gfxMaxUp], "2800 MHz with the flag: held bits 4 and 64")
    }

    // MARK: The controller

    private static func controller(_ suite: TestSuite) {
        do {
            let h = Harness { $0.takesOverclock = true }
            h.engine.choose(.power(watts: 250))
            h.run(ms: 0)
            suite.expect(h.calls(.set).last?.input == [2, 250, 1] && h.held == .power(watts: 250),
                         "a limit above start-up goes in the raise form, and is held")
            h.run(ms: 3_000)
            h.engine.choose(.power(watts: 230))
            h.run(ms: 0)
            suite.expect(h.calls(.set).last?.input == [2, 230] && h.held == .power(watts: 230),
                         "a lower limit keeps the 2-scalar form")
        }
        do {
            let h = Harness { $0.takesOverclock = true }
            h.engine.choose(.power(watts: 260))
            h.run(ms: 0)
            h.fake.tripFanWatchdog()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.powerWatchdog.rawValue),
                         "the watchdog takes a raised limit back: writing off (PowerWatchdog)")
        }
        do {
            let h = Harness { $0.takesOverclock = true }
            h.engine.chooseGfxMax(2_000)
            h.run(ms: 3_000)
            h.engine.chooseVolt(1_050)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2_000, 0, 1_050]
                            && h.held == .od8(Want(gfxMaxMHz: 2_000, voltMV: 1_050)),
                         "the voltage goes with the held maximum, in the 15-scalar form")
            h.run(ms: 3_000)
            h.engine.chooseGfxMaxRaised(2_600)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input.prefix(2) == [2, 4]
                            && h.held == .od8(Want(gfxMaxMHz: 2_600, voltMV: 1_050, overclock: true)),
                         "a raised maximum replaces the lowered one, with the flag, the voltage kept")
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(nil)
            h.run(ms: 0)
            suite.expect(h.held == .od8(Want(gfxMaxMHz: 2_600, voltMV: 1_050, overclock: true)),
                         "the lowering control's stock leaves a raised maximum alone")
            h.engine.dropRaises()
            h.run(ms: 0)
            suite.expect(h.held == .od8(Want(voltMV: 1_050)), "overclock off: the raise goes, the voltage stays")
        }
        do {
            let h = Harness { $0.takesOverclock = true }
            h.engine.choose(.power(watts: 250))
            h.run(ms: 0)
            h.engine.dropRaises()
            h.run(ms: 3_000)
            suite.expect(h.held == nil && !(h.fake.statusFor(h.connection)?.holdsPower ?? true),
                         "overclock off: a raised power limit goes back to start-up")
        }
    }

    // MARK: Remembering

    private static func remembering(_ suite: TestSuite) {
        let suiteName = "ryzenstatus.tests.gpucontrol.overclock.\(getpid())"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let all = Want(gfxMaxMHz: 2_600, gfxMinMHz: 1_500, voltMV: 1_050, overclock: true)
        GPUControlRemembered.od8(all).save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .od8(all), "a voltage and a raise round-trip")
        GPUControlRemembered.power(watts: 230).save(defaults)
        suite.expect(defaults.object(forKey: DefaultsKey.gpuControlRememberedVoltMV) == nil
                        && defaults.object(forKey: DefaultsKey.gpuControlRememberedOverclock) == nil,
                     "saving power clears them")
        defaults.removePersistentDomain(forName: suiteName)

        let f = facts()
        let minLimits = GPUControlClockMinLogic.Limits(min: 500, max: 2_800, stock: 500)
        func atLaunch(_ remembered: GPUControlRemembered) -> GPUControlRequest? {
            Policy.request(remembered: remembered, active: true, facts: f, stopped: nil, stockGfxMaxMHz: 2_359,
                           gfxMin: minLimits)
        }
        suite.expect(atLaunch(.od8(all)) == .od8(Want(gfxMinMHz: 1_500)),
                     "at launch: no voltage and no raised maximum, the rest still asked for")
        suite.expect(atLaunch(.od8(Want(gfxMaxMHz: 2_000, voltMV: 1_050))) == .od8(Want(gfxMaxMHz: 2_000)),
                     "at launch: a lowered maximum stays, the voltage goes")
        suite.expect(atLaunch(.od8(Want(voltMV: 1_050))) == nil, "a voltage alone: nothing asked for at launch")
        suite.expect(atLaunch(.power(watts: 250)) == nil && atLaunch(.power(watts: 230)) == .power(watts: 230),
                     "a limit above start-up is never asked for at launch; a lower one is")
        // After a wake, in the same run: they follow the remember switch.
        let volt = GPUControlVoltLogic.Limits(min: 881, stock: 1_075)
        let up = GPUControlOverclockLogic.GfxLimits(stock: 2_359, max: 2_800)
        suite.expect(Policy.checkedAgain(.od8(all), stockGfxMaxMHz: 2_359, gfxMin: minLimits, volt: volt, overclock: up)
                        == .od8(all), "after a wake: asked again as it was")
        suite.expect(Policy.checkedAgain(.od8(all), stockGfxMaxMHz: 2_359, gfxMin: minLimits)
                        == .od8(Want(gfxMinMHz: 1_500)), "after a wake with a kext that takes neither: the rest")
        suite.expect(Policy.checkedAgain(.power(watts: 250), stockGfxMaxMHz: 2_359) == .power(watts: 250),
                     "a raised limit after a wake: asked again")
    }

    // MARK: Gating

    private static func gating(_ suite: TestSuite) {
        guard let writing = realWriting() else {
            suite.expect(false, "gating: the 0.7.2 fixture loads")
            return
        }
        var page = GPUControlPageInput(facts: facts(), state: .ready, snapshot: nil)
        page.writing = writing
        suite.expect(GPUControlVoltSection.shows(page) && GPUControlOverclockSection.shows(page),
                     "an RX 6800 XT with 0.9.0: both sections")
        suite.expect(GPUControlOverclockSection.powerChoices(page) == [240, 250, 260, 261],
                     "the raised pop-up: start-up to CeilW")
        page.state = .readOnlyCard
        suite.expect(!GPUControlVoltSection.shows(page) && !GPUControlOverclockSection.shows(page),
                     "the read-only card: neither section")
        page.state = .ready
        page.writing?.od8State?.takes = [.curve, .zeroRpmOff, .gfxMax, .gfxMin]
        page.facts?.takesRaise = false
        suite.expect(!GPUControlVoltSection.shows(page) && !GPUControlOverclockSection.shows(page),
                     "a kext without the voltage or the raises: neither section")
        page.facts?.od8Ready = false
        page.writing = writing
        page.facts?.takesRaise = true
        suite.expect(!GPUControlVoltSection.shows(page) && GPUControlOverclockSection.gfxLimits(page) == nil,
                     "OD8 not read cleanly: no voltage, no raised maximum")
        // The switch is off by default.
        let suiteName = "ryzenstatus.tests.gpucontrol.overclock.switch.\(getpid())"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            MainActor.assumeIsolated {
                let service = GPUControlService(defaults: defaults)
                suite.expect(!service.overclock, "Allow overclocking is off by default")
                service.overclock = true
                suite.expect(defaults.bool(forKey: DefaultsKey.gpuControlOverclock)
                                && GPUControlService(defaults: defaults).overclock, "and kept once turned on")
            }
            defaults.removePersistentDomain(forName: suiteName)
        }
        suite.expect(GPUControlPageInput(facts: nil, state: nil, snapshot: nil).overclock == false,
                     "the page's input starts with the switch off")
    }

    // MARK: Words

    private static func strings(_ suite: TestSuite) {
        func placeholders(_ text: String) -> [String] {
            let pattern = try? NSRegularExpression(pattern: "%(?:[0-9]+\\$)?[@d%]")
            let range = NSRange(text.startIndex..., in: text)
            return pattern?.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { $0 != "%%" } ?? []
        }
        let english = GPUControlOverclockStrings.enUS.all
        suite.expect(english.count == 22, "22 texts")
        for language in AppLanguage.allCases {
            let table = FeatureStrings.gpuControlOverclock(language).all
            suite.expect(table.count == english.count && table.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "\(language.rawValue): every overclock text")
            for (text, reference) in zip(table, english) {
                suite.expect(Set(placeholders(text)) == Set(placeholders(reference)),
                             "\(language.rawValue): the same placeholders as English in \(reference.prefix(30))")
            }
            let page = FeatureStrings.gpuControlPage(language)
            suite.expect(page.voltItemFormat.contains("%d") && !page.offPowerWatchdog.isEmpty,
                         "\(language.rawValue): the held voltage and the power watchdog sentence")
            let names = GPUControlVoltSection.accessibilityNames(FeatureStrings.gpuControlOverclock(language))
            let up = GPUControlOverclockSection.accessibilityNames(FeatureStrings.gpuControlOverclock(language))
            suite.expect(Set([names.slider, names.field, names.stepper, up.slider, up.field, up.stepper]).count == 6,
                         "\(language.rawValue): each control has its own VoiceOver name")
        }
        suite.expect(GPUControlPageStrings.enUS.od8Held(Want(gfxMaxMHz: 2_600, voltMV: 1_050, overclock: true))
                        == "RyzenStatus is holding a GFX maximum of 2600 MHz and a GFX voltage of 1050 mV",
                     "a raised maximum and a voltage, in one sentence")
        suite.expect(GPUControlPageStrings.enUS.sentence(.offPowerWatchdog)
                        == "Off: the watchdog put the start-up power limit back.", "the power watchdog's sentence")
        suite.expect(GPUControlOverclockStrings.enUS.voltRecommendedFormat.contains("not a guarantee"),
                     "the starting point says it is not a guarantee")
    }
}
