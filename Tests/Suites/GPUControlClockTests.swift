// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GFX maximum clock (plan phase 4): the range from the kext's table,
/// only lower than stock, the slider's steps and ticks, remembering the
/// clock with the fan state, the controller against the model, the strings.
enum GPUControlClockTests {
    static func run(_ suite: TestSuite) {
        logic(suite)
        table(suite)
        remember(suite)
        controller(suite)
        strings(suite)
        reviewFixes(suite)
        gfxMin(suite)
    }

    private typealias Logic = GPUControlClockLogic
    private typealias Harness = GPUControlChannelTests.Harness

    private static func logic(_ suite: TestSuite) {
        suite.expect(Logic.range(stockGfxMaxMHz: 2_359) == 1_500...2_359, "1500 MHz to the stock 2359 MHz")
        suite.expect(Logic.range(stockGfxMaxMHz: nil) == nil && Logic.range(stockGfxMaxMHz: 1_500) == nil,
                     "no stock maximum, or none above the floor: no clock")
        suite.expect(Logic.lowers(2_300, stockGfxMaxMHz: 2_359) && Logic.lowers(1_500, stockGfxMaxMHz: 2_359),
                     "2300 and the 1500 floor lower the clock")
        suite.expect(!Logic.lowers(2_359, stockGfxMaxMHz: 2_359) && !Logic.lowers(2_400, stockGfxMaxMHz: 2_359)
                        && !Logic.lowers(1_490, stockGfxMaxMHz: 2_359) && !Logic.lowers(2_300, stockGfxMaxMHz: nil),
                     "the stock maximum, above it, below the floor, or no table: never a hold")
        suite.expect(Logic.request(2_359, stockGfxMaxMHz: 2_359) == nil, "choosing the stock maximum is the way back")
        suite.expect(Logic.request(2_300, stockGfxMaxMHz: 2_359) == 2_300, "a lower value is asked for")
        suite.expect(Logic.snapped(2_352, stockGfxMaxMHz: 2_359) == 2_350, "10 MHz steps")
        suite.expect(Logic.snapped(2_356, stockGfxMaxMHz: 2_359) == 2_359, "the top is the stock maximum, 2359")
        suite.expect(Logic.snapped(1_400, stockGfxMaxMHz: 2_359) == 1_500, "never below the floor")
        suite.expect(Logic.snapped(1_904, stockGfxMaxMHz: 2_359) == 1_900, "rounds to the nearest 10")
        suite.expect(Logic.tickCount(stockGfxMaxMHz: 2_359) == 9, "a tick every 100 MHz: 1500 to 2300")
    }

    /// The stock maximum comes from the kext's table, only with feature 0x1.
    private static func table(_ suite: TestSuite) {
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let od8 = GPUControlStatus.parse(dict)?.writing?.od8 else {
            suite.expect(false, "the 0.7.2 fixture loads")
            return
        }
        suite.expect(od8.stockGfxMaxMHz == 2_359 && Logic.range(stockGfxMaxMHz: od8.stockGfxMaxMHz) == 1_500...2_359,
                     "0.7.2 here: the slider goes from 1500 to 2359 MHz, not the driver's 2800")
        var moved = od8
        if let entry = moved.settings["GfxMaxMHz"] {
            moved.settings["GfxMaxMHz"] = GPUControlStatus.Writing.OD8Setting(
                feature: entry.feature, min: entry.min, max: entry.max, stock: 2_359, defaultNow: 2_354, current: 2_354)
            suite.expect(moved.stockGfxMaxMHz == 2_354, "the default moved to 2354 after a wake: the lower one")
            moved.settings["GfxMaxMHz"] = GPUControlStatus.Writing.OD8Setting(
                feature: 0x2, min: entry.min, max: entry.max, stock: entry.stock, defaultNow: entry.defaultNow,
                current: entry.current)
            suite.expect(Logic.range(stockGfxMaxMHz: moved.stockGfxMaxMHz) == nil,
                         "feature not 0x1: no clock (the kext refuses every OD8 call then)")
        }
        // A held clock from the properties (published only while held).
        let fake = FakeGPUControlKext()
        fake.arm()
        let c = fake.connection()
        _ = c.open()
        _ = c.setOD8(GPUControlOD8Want(gfxMaxMHz: 2_300))
        let writing = GPUControlService.fakeControl(fake)?.writing
        suite.expect(writing?.od8State?.gfxMaxHeld == 2_300 && writing?.od8State?.held == .gfxMax,
                     "GfxMaxHeld 2300 while held")
    }

    private static func remember(_ suite: TestSuite) {
        let suiteName = "ryzenstatus.tests.gpucontrol.clock.\(getpid())"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let clockOnly = GPUControlOD8Want(gfxMaxMHz: 2_300)
        GPUControlRemembered.od8(clockOnly).save(defaults)
        suite.expect(defaults.integer(forKey: DefaultsKey.gpuControlRememberedGfxMHz) == 2_300
                        && GPUControlRemembered.load(defaults) == .od8(clockOnly), "a clock round-trips")
        let both = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, gfxMaxMHz: 2_300)
        GPUControlRemembered.od8(both).save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .od8(both), "a curve and a clock round-trip together")
        GPUControlRemembered.power(watts: 220).save(defaults)
        suite.expect(defaults.object(forKey: DefaultsKey.gpuControlRememberedGfxMHz) == nil, "saving power clears the clock")
        defaults.removePersistentDomain(forName: suiteName)

        suite.expect(GPUControlRememberPolicy.toSave(held: .od8(clockOnly), ownerChoseStartUp: false, active: true)
                        == .od8(clockOnly), "a confirmed clock is saved")
        var facts = GPUControlFacts(source: .properties)
        facts.ready = true
        facts.armed = true
        facts.bootW = 240
        facts.od8Ready = true
        typealias Policy = GPUControlRememberPolicy
        suite.expect(Policy.request(remembered: .od8(clockOnly), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_359) == .od8(clockOnly), "a remembered 2300 MHz is asked for")
        let atTop = GPUControlOD8Want(gfxMaxMHz: 2_359)
        suite.expect(Policy.request(remembered: .od8(atTop), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_354) == nil,
                     "a remembered 2359 MHz with today's 2354 stock: never above stock, nothing asked")
        let curveAndTop = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, gfxMaxMHz: 2_359)
        suite.expect(Policy.request(remembered: .od8(curveAndTop), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_354, kextVersion: "REL-072-2026-11-19")
                        == .od8(GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve)),
                     "with a curve, only the clock is left out")
        let curveAndClock = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, gfxMaxMHz: 2_300)
        suite.expect(Policy.request(remembered: .od8(curveAndClock), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_359, kextVersion: "REL-073-2026-12-01") == nil,
                     "a curve and another kext build: nothing, not even the clock")
        suite.expect(Policy.request(remembered: .od8(clockOnly), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_359, kextVersion: "REL-073-2026-12-01") == .od8(clockOnly),
                     "a clock alone does not depend on the curve rules, as on the page")
        suite.expect(Policy.request(remembered: .od8(clockOnly), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: nil) == nil, "no stock maximum known: no clock asked")
        var other = facts
        other.owned = true
        suite.expect(Policy.request(remembered: .od8(clockOnly), active: true, facts: other, stopped: nil,
                                    stockGfxMaxMHz: 2_359) == nil, "another program holds it: nothing")
    }

    private static func controller(_ suite: TestSuite) {
        // The clock with a held curve: one whole OD8 request.
        do {
            let h = Harness()
            h.engine.chooseFan(curve: GPUControlFanDraft.testedCurve, zeroRpmOff: false)
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input == [2, 1, 30, 40, 44, 46, 48, 20, 36, 52, 68, 100, 2_300],
                         "the clock goes with the held curve")
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(nil)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input == [2, 1, 30, 40, 44, 46, 48, 20, 36, 52, 68, 100, 0]
                            && h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve)),
                         "turning the clock off keeps the curve")
        }
        // Above stock and below the floor: refused by the kext, never clamped.
        for (mhz, why) in [(2_400, "above the stock maximum"), (1_400, "below 1500 MHz")] {
            let h = Harness()
            h.engine.chooseGfxMax(mhz)
            h.run(ms: 0)
            guard case .refused(_, let answer)? = h.engine.snapshot.outcome else {
                suite.expect(false, "\(why): refused")
                continue
            }
            suite.expect(answer.check == .gfxRange && h.calls(.setOD8).last?.input[12] == UInt64(mhz)
                            && h.engine.snapshot.held == nil, "\(why): sent unchanged, refused (GFX range), nothing held")
        }
        // The default moved since boot: the kext refuses, the page groups it.
        do {
            let h = Harness()
            h.fake.refuseNextOD8 = .drifted
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            if case .refused(_, let answer)? = h.engine.snapshot.outcome {
                suite.expect(GPUControlTextGroup.forReply(answer.replyCode, check: answer.checkCode) == .notReady,
                             "drifted: the 'not ready yet' sentence")
            } else {
                suite.expect(false, "drifted: refused")
            }
        }
        // A clock and a power limit: the other goes back first, both ways.
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            h.engine.choose(.power(watts: 230))
            h.run(ms: 10_000)
            suite.expect(h.engine.snapshot.held == .power(watts: 230)
                            && h.fake.writes.map(\.kind) == [.od8(GPUControlOD8Want(gfxMaxMHz: 2_300)), .wayBack, .power(230)]
                            && h.gapsKept, "clock to power: the clock goes back first")
            suite.expect(h.engine.snapshot.status?.od8Reverts == 1, "one OD8 way back counted")
        }
        // A clock alone cannot trip the fan watchdog (it watches a held curve).
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            h.fake.tripFanWatchdog()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == nil && h.engine.snapshot.held == .od8(GPUControlOD8Want(gfxMaxMHz: 2_300)),
                         "a clock-only hold: no watchdog, still held")
        }
    }

    private static func strings(_ suite: TestSuite) {
        func specifiers(_ text: String) -> [String] {
            let pattern = try? NSRegularExpression(pattern: "%%|%(\\d\\$)?[@d]")
            let range = NSRange(text.startIndex..., in: text)
            return pattern?.matches(in: text, range: range)
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { $0 != "%%" } ?? []
        }
        let english = GPUControlClockStrings.enUS.all
        suite.expect(english.count == 17, "17 texts (6 for the GFX minimum)")
        for language in AppLanguage.allCases {
            let clock = FeatureStrings.gpuControlClock(language)
            let table = clock.all
            suite.expect(table.count == english.count && table.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "\(language.rawValue): every clock text is there")
            // VoiceOver: the names the row gives its three controls differ,
            // and the stepper's says its step.
            let names = GPUControlClockSection.accessibilityNames(clock)
            suite.expect(Set([names.slider, names.field, names.stepper]).count == 3
                            && names.stepper.contains("\(GPUControlClockLogic.step)"),
                         "\(language.rawValue): the clock row's three controls have their own names")
            let low = GPUControlClockMinSection.accessibilityNames(clock)
            suite.expect(Set([low.slider, low.field, low.stepper, names.slider, names.field, names.stepper]).count == 6
                            && low.stepper.contains("\(GPUControlClockMinLogic.step)"),
                         "\(language.rawValue): the minimum's three controls have their own names, not the maximum's")
            // No watts written into a text (S-2): the clock footer's 200 W is gone.
            suite.expect(!table.contains { $0.contains("200 W") || $0.contains("200 Вт") || $0.contains("200 W'") },
                         "\(language.rawValue): no fixed watts in the clock texts")
            for (index, text) in table.enumerated() {
                suite.expect(specifiers(text) == specifiers(english[index]),
                             "\(language.rawValue): clock text \(index) keeps the English placeholders")
            }
            if language != .enUS {
                let same = zip(table, english).filter { $0.0 == $0.1 }.map(\.0)
                suite.expect(same.isEmpty, "\(language.rawValue): translated (\(same))")
            }
        }
        suite.expect(String(format: GPUControlClockStrings.es.outOfRangeFormat, 1_500, 2_359)
                        == "Elige un valor entre 1500 y 2359 MHz.", "the field's range in Spanish")
        suite.expect(GPUControlPageStrings.enUS.od8Held(GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, gfxMaxMHz: 2_300))
                        == "RyzenStatus is holding a fan curve and a GFX maximum of 2300 MHz", "a curve and a clock held, in one sentence")
        suite.expect(GPUControlClockSection.sliderMinWidth > 0, "the row keeps the slider at least this wide on one line")
    }

    /// The GFX minimum clock (GPUSensors 0.9.0): its range from the card's
    /// table up to the maximum in force, the 14 scalars, `Takes`, the
    /// controller against the model, remembering it, its words.
    private static func gfxMin(_ suite: TestSuite) {
        typealias Min = GPUControlClockMinLogic
        let limits = Min.Limits(min: 500, max: 2_800, stock: 500)
        suite.expect(Min.range(limits: limits, gfxMaxMHz: 2_359) == 500...2_359,
                     "the minimum: from the stock 500 MHz to the stock maximum")
        suite.expect(Min.range(limits: limits, gfxMaxMHz: 2_000) == 500...2_000, "up to a lowered maximum")
        suite.expect(Min.range(limits: nil, gfxMaxMHz: 2_359) == nil && Min.range(limits: limits, gfxMaxMHz: nil) == nil
                        && Min.range(limits: limits, gfxMaxMHz: 500) == nil,
                     "no minimum taken, no maximum known, or nothing above stock: no control")
        suite.expect(Min.range(limits: Min.Limits(min: 500, max: 2_000, stock: 500), gfxMaxMHz: 2_359) == 500...2_000,
                     "never past the card's own top for the minimum")
        let r = 500...2_359
        suite.expect(Min.raises(1_500, range: r) && Min.raises(2_359, range: r),
                     "1500 MHz and the maximum itself raise the minimum")
        suite.expect(!Min.raises(500, range: r) && !Min.raises(2_360, range: r) && !Min.raises(1_500, range: nil),
                     "stock, above the maximum, or no range: never a hold")
        suite.expect(Min.request(500, stockMHz: 500) == nil && Min.request(1_500, stockMHz: 500) == 1_500,
                     "choosing the stock minimum is the way back; a higher value is asked for")
        suite.expect(Min.snapped(1_504, range: r) == 1_500 && Min.snapped(2_356, range: r) == 2_359
                        && Min.snapped(400, range: r) == 500, "10 MHz steps, the top on its own, never below stock")
        suite.expect(Min.tickCount(range: r) == 19, "a tick every 100 MHz: 500 to 2300")
        let low = GPUControlOD8Want(gfxMinMHz: 2_100)
        suite.expect(Min.checked(low, limits: limits, stockGfxMaxMHz: 2_359) == low, "2100 MHz is kept")
        suite.expect(Min.checked(low, limits: nil, stockGfxMaxMHz: 2_359).gfxMinMHz == nil,
                     "a kext that takes no minimum: left out")
        suite.expect(Min.checked(GPUControlOD8Want(gfxMaxMHz: 2_000, gfxMinMHz: 2_100), limits: limits, stockGfxMaxMHz: 2_359)
                        == GPUControlOD8Want(gfxMaxMHz: 2_000), "above the lowered maximum: left out, the maximum stays")

        // The scalars.
        suite.expect(GPUControlOD8Want(gfxMinMHz: 1_500).scalars() == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1_500],
                     "a minimum: 14 scalars, the 14th in MHz")
        suite.expect(GPUControlOD8Want(gfxMaxMHz: 2_300).scalars()?.count == 13,
                     "no minimum: the 13 every kext since 0.7.0 takes")
        suite.expect(GPUControlOD8Want(gfxMinMHz: 0).scalars() == nil, "a minimum of 0 would read as stock: not sent")
        suite.expect(!GPUControlOD8Want(gfxMinMHz: 1_500).isStock && GPUControlOD8Want(gfxMinMHz: 1_500).heldFlags == .gfxMin,
                     "a raised minimum is a hold, held bit 16")

        // The table, and whether the kext takes it.
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        if let data = FileManager.default.contents(atPath: path),
           let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
           var writing = GPUControlStatus.parse(dict)?.writing {
            suite.expect(writing.od8?.gfxMin.map { [$0.min, $0.max, $0.stock] } == [500, 2_800, 500],
                         "the card's minimum: 500 to 2800 MHz, stock 500")
            suite.expect(Min.limits(writing: writing, od8Ready: true) == nil,
                         "0.7.2 publishes no Takes: no minimum control")
            writing.od8State?.takes = [.curve, .zeroRpmOff, .gfxMax, .gfxMin]
            suite.expect(Min.limits(writing: writing, od8Ready: true) == limits
                            && Min.limits(writing: writing, od8Ready: false) == nil,
                         "with Takes 23 and a clean read: the card's limits")
        } else {
            suite.expect(false, "the 0.7.2 fixture loads")
        }
        do {
            let fake = FakeGPUControlKext()
            fake.takesGfxMin = true
            fake.arm()
            let c = fake.connection()
            _ = c.open()
            let answer = c.setOD8(GPUControlOD8Want(gfxMinMHz: 1_500))
            let writing = GPUControlService.fakeControl(fake)?.writing
            suite.expect(answer?.reply == .ok && writing?.od8State?.gfxMinHeld == 1_500
                            && writing?.od8State?.held == .gfxMin && writing?.od8State?.takesGfxMin == true
                            && c.status()?.flags.contains(.gfxMin) == true,
                         "0.9.0 model: GfxMinHeld 1500, Takes, the status flag")
        }

        // The controller against the 0.9.0 model.
        do {
            let h = Harness { $0.takesGfxMin = true }
            h.engine.chooseGfxMax(2_000)
            h.run(ms: 3_000)
            h.engine.chooseGfxMin(1_500)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2_000, 1_500]
                            && h.engine.snapshot.held == .od8(GPUControlOD8Want(gfxMaxMHz: 2_000, gfxMinMHz: 1_500)),
                         "the minimum goes with the held maximum, and is held")
            h.run(ms: 3_000)
            h.engine.chooseGfxMin(nil)
            h.run(ms: 0)
            suite.expect(h.calls(.setOD8).last?.input == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2_000]
                            && h.engine.snapshot.held == .od8(GPUControlOD8Want(gfxMaxMHz: 2_000)),
                         "turning the minimum off keeps the maximum, in the 13-scalar form")
        }
        do {
            let h = Harness { $0.takesGfxMin = true }
            h.engine.chooseGfxMin(2_400)
            h.run(ms: 0)
            if case .refused(_, let answer)? = h.engine.snapshot.outcome {
                suite.expect(answer.check == .gfxMinRange && h.calls(.setOD8).last?.input[13] == 2_400
                                && h.engine.snapshot.held == nil
                                && GPUControlTextGroup.forReply(answer.replyCode, check: answer.checkCode) == .notAllowed,
                             "above the stock maximum: sent unchanged, refused (GFX min range), nothing held")
            } else {
                suite.expect(false, "a minimum above the maximum: refused")
            }
        }
        do {
            let h = Harness { $0.takesGfxMin = true }
            h.engine.chooseGfxMin(1_500)
            h.run(ms: 0)
            h.fake.tripFanWatchdog()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.od8Watchdog.rawValue),
                         "a raised minimum is watched: the watchdog stops it")
        }

        // Remembering it.
        let suiteName = "ryzenstatus.tests.gpucontrol.clockmin.\(getpid())"
        if let defaults = UserDefaults(suiteName: suiteName) {
            let both = GPUControlOD8Want(gfxMaxMHz: 2_000, gfxMinMHz: 1_500)
            GPUControlRemembered.od8(both).save(defaults)
            suite.expect(defaults.integer(forKey: DefaultsKey.gpuControlRememberedGfxMinMHz) == 1_500
                            && GPUControlRemembered.load(defaults) == .od8(both), "a minimum round-trips with the maximum")
            GPUControlRemembered.power(watts: 220).save(defaults)
            suite.expect(defaults.object(forKey: DefaultsKey.gpuControlRememberedGfxMinMHz) == nil,
                         "saving power clears the minimum")
            defaults.removePersistentDomain(forName: suiteName)
        }
        var facts = GPUControlFacts(source: .properties)
        facts.ready = true
        facts.armed = true
        facts.bootW = 240
        facts.od8Ready = true
        typealias Policy = GPUControlRememberPolicy
        let both = GPUControlOD8Want(gfxMaxMHz: 2_000, gfxMinMHz: 1_500)
        suite.expect(Policy.request(remembered: .od8(both), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_359, gfxMin: limits) == .od8(both),
                     "a remembered minimum is asked for again with a kext that takes it")
        suite.expect(Policy.request(remembered: .od8(both), active: true, facts: facts, stopped: nil,
                                    stockGfxMaxMHz: 2_359) == .od8(GPUControlOD8Want(gfxMaxMHz: 2_000)),
                     "a kext that takes no minimum: only the maximum is asked for")
        suite.expect(Policy.checkedAgain(.od8(GPUControlOD8Want(gfxMinMHz: 1_500)), stockGfxMaxMHz: 2_359) == nil,
                     "after a wake, no minimum taken: nothing left to ask")
        suite.expect(Policy.checkedAgain(.od8(GPUControlOD8Want(gfxMinMHz: 1_500)), stockGfxMaxMHz: 2_359, gfxMin: limits)
                        == .od8(GPUControlOD8Want(gfxMinMHz: 1_500)), "and with it: asked again")
        suite.expect(GPUControlPageStrings.enUS.od8Held(both)
                        == "RyzenStatus is holding a GFX maximum of 2000 MHz and a GFX minimum of 1500 MHz",
                     "both clocks held, in one sentence")
    }

    /// The review of phases 3 and 4 (F1 to F6).
    private static func reviewFixes(_ suite: TestSuite) {
        let curve = GPUControlFanDraft.testedCurve
        // F1: a stock fan draft keeps a held clock, and never gives back power.
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 3_000)
            h.engine.chooseFan(curve: nil, zeroRpmOff: false)
            h.run(ms: 3_000)
            suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(gfxMaxMHz: 2_300)) && h.replies(.release) == 0,
                         "F1: a stock fan with a held clock: the clock stays")
        }
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 3_000)
            h.engine.chooseFan(curve: nil, zeroRpmOff: false)
            h.engine.chooseGfxMax(nil)
            h.run(ms: 3_000)
            suite.expect(h.engine.snapshot.held == .power(watts: 220) && h.replies(.release) == 0,
                         "F1/F3: a stock fan or clock with a power limit held: nothing is given back")
        }
        let service = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath
                                    + "/Sources/RyzenStatus/Services/Metrics/GPUControlService.swift", encoding: .utf8)) ?? ""
        suite.expect(!service.contains("draft.want.isStock"), "F1: applyFan always goes through the controller")
        // F2: the owner's way back is in the snapshot, so the remembered one is forgotten.
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 3_000)
            suite.expect(!h.engine.snapshot.ownerReleased, "F2: a hold is not a way back")
            h.engine.chooseGfxMax(nil)
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.ownerReleased && h.engine.snapshot.held == nil && h.replies(.release) == 1,
                         "F2: turning the clock off is the owner's way back")
            suite.expect(GPUControlRememberPolicy.toSave(held: nil, ownerChoseStartUp: h.engine.snapshot.ownerReleased,
                                                         active: true) == .nothing, "F2: so the remembered clock is forgotten")
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(2_200)
            suite.expect(!h.engine.snapshot.ownerReleased, "F2: the next choice clears it")
            suite.expect(service.contains("next.ownerReleased"), "F2: the service saves on the snapshot's flag")
        }
        // F3: the controller compares with what waits, not only with what is held.
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_200)
            h.run(ms: 0)
            h.engine.chooseGfxMax(2_100)
            h.engine.chooseGfxMax(2_200)
            h.run(ms: 5_000)
            suite.expect(h.calls(.setOD8).map { $0.input[12] } == [2_200]
                            && h.engine.snapshot.held == .od8(GPUControlOD8Want(gfxMaxMHz: 2_200)),
                         "F3: 2200 held, 2100 waiting, back to 2200: 2100 never goes out")
        }
        do {
            let h = Harness()
            h.engine.chooseGfxMax(2_300)
            h.engine.chooseGfxMax(nil)
            h.run(ms: 5_000)
            suite.expect(h.calls(.setOD8).isEmpty && h.replies(.release) == 0 && h.engine.snapshot.activity == .none,
                         "F3: a clock asked for and switched off before it went out: nothing goes out")
        }
        let view = (try? String(contentsOfFile: FileManager.default.currentDirectoryPath
                                + "/Sources/RyzenStatus/UI/Settings/GPUControlClockSection.swift", encoding: .utf8)) ?? ""
        suite.expect(!view.contains("request != Self.heldMHz") && !view.contains("if !value, Self.heldMHz"),
                     "F3: the clock section no longer filters against the held value")
        // F4: the switch follows what is held when nothing waits.
        suite.expect(view.contains(".onChange(of: Self.heldMHz(input))"), "F4: the switch and value follow the held clock")
        // F5: a remembered fan state waits for OD8 to be read.
        typealias Read = GPUControlStatus.Writing.OD8Read
        suite.expect(Read.notClean("waiting for the driver").isWaiting
                        && Read.notClean("no data: the GPU was asleep or blocked").isWaiting
                        && Read.notClean("not read: going to sleep, or the driver went away").isWaiting,
                     "F5: the kext's waiting texts")
        suite.expect(!Read.read.isWaiting && !Read.notClean("read, but an entry is not as expected").isWaiting
                        && !Read.notClean("not available: OD8 not initialized").isWaiting,
                     "F5: a clean read, an odd one or one that will not come is not waiting")
        suite.expect(service.contains("od8Read?.isWaiting"), "F5: the service keeps the remembered fan state pending")
        // F6: after a wake the clock is checked against the table of the moment.
        suite.expect(GPUControlRememberPolicy.checkedAgain(.od8(GPUControlOD8Want(curve: curve, gfxMaxMHz: 2_350)),
                                                           stockGfxMaxMHz: 2_340) == .od8(GPUControlOD8Want(curve: curve)),
                     "F6: a clock above today's stock is left out, the curve stays")
        suite.expect(GPUControlRememberPolicy.checkedAgain(.od8(GPUControlOD8Want(gfxMaxMHz: 2_350)), stockGfxMaxMHz: 2_340) == nil,
                     "F6: a clock alone above today's stock: nothing to ask")
        suite.expect(GPUControlRememberPolicy.checkedAgain(.power(watts: 220), stockGfxMaxMHz: nil) == .power(watts: 220),
                     "F6: a power limit is not touched")
        do {
            let h = Harness(reask: true)
            h.engine.reaskFilter = { GPUControlRememberPolicy.checkedAgain($0, stockGfxMaxMHz: 2_340) }
            h.engine.chooseFan(curve: curve, zeroRpmOff: false)
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(2_350)
            h.run(ms: 3_000)
            h.fake.sleep()
            h.fake.wake()
            h.engine.didWake()
            h.run(ms: 40_000)
            suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: curve)) && h.calls(.setOD8).last?.input[12] == 0,
                         "F6: after the wake the curve comes back without the clock above stock")
        }
    }
}
