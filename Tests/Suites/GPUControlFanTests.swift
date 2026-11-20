// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The fan curve editor and zero RPM (plan phase 3): the app's copy of the
/// kext's rules against the case file made from the real `control_logic.hpp`,
/// the preview and its sentences, the draft, the scalars, the controller
/// switching between power and the curve against the model, remembering a
/// fan state, and the strings.
enum GPUControlFanTests {
    static func run(_ suite: TestSuite) {
        rulesAgainstTheKext(suite)
        preview(suite)
        draftAndScalars(suite)
        controller(suite)
        remember(suite)
        strings(suite)
    }

    private typealias Rules = GPUControlCurveRules
    private typealias Harness = GPUControlChannelTests.Harness

    private static func fixture(_ name: String) -> Data? {
        FileManager.default.contents(atPath: FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/" + name)
    }

    private static func realWriting() -> GPUControlStatus.Writing? {
        guard let data = fixture("ioreg-0.7.2-2026-11-20.plist"),
              let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        return GPUControlStatus.parse(table)?.writing
    }

    // MARK: The rules against the kext's own answers

    private static func rulesAgainstTheKext(_ suite: TestSuite) {
        guard let writing = realWriting(), let table = writing.od8, let base = Rules.State(table: table) else {
            suite.expect(false, "the 0.7.2 OD8 table loads")
            return
        }
        suite.expect(base.stockCurve == [(30, 20), (50, 36), (56, 52), (63, 68), (70, 100)]
                        .map { GPUControlFanPoint(temperatureC: $0.0, speedPercent: $0.1) },
                     "the stock curve from the table")
        suite.expect(base.limitC == 48, "100 % by 70 - 22 = 48 C on this card")
        var noTarget = base
        noTarget.first[Rules.targetTemp] = Rules.Entry()
        suite.expect(noTarget.limitC == 48, "no target published: the card's 48 C, never -22 C")
        noTarget.first[Rules.targetTemp].def = 110
        suite.expect(noTarget.limitC == 48, "a target the kext refuses: the card's 48 C")
        noTarget.first[Rules.targetTemp].def = 80
        suite.expect(noTarget.limitC == 58, "another target in range: 80 - 22")
        suite.expect(base.first[Rules.gfxMax] == Rules.Entry(feature: 1, min: 500, max: 2_800, def: 2_359),
                     "GFX max by its id, from its name")
        suite.expect(base.first[2] == Rules.Entry() && base.current[13] == 0,
                     "an entry the kext leaves out stays zero, as in the kext")

        guard let data = fixture("curve-cases.jsonl"), let text = String(data: data, encoding: .utf8) else {
            suite.expect(false, "the case file loads")
            return
        }
        let lines = text.split(separator: "\n")
        suite.expect(lines.count == 100, "100 cases")
        var seen: [UInt64: Int] = [:]
        for (index, line) in lines.enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let wantDict = object["want"] as? [String: Any],
                  let expected = (object["check"] as? NSNumber)?.uint64Value else {
                suite.expect(false, "case \(index + 1) parses")
                continue
            }
            var state = base
            for mutation in (object["muts"] as? [[String: Any]]) ?? [] {
                apply(mutation, to: &state)
            }
            let want = Self.want(wantDict)
            let result = Rules.check(want, state)
            suite.expect(result.check.rawValue == expected,
                         "case \(index + 1): the kext says \(expected), the copy \(result.check.rawValue)")
            suite.expect(result.check != .notRead && result.check != .noReadings,
                         "case \(index + 1): never a code od8CheckWant does not give")
            seen[expected, default: 0] += 1
        }
        suite.expect(seen == [0: 33, 2: 14, 3: 5, 4: 12, 5: 9, 6: 4, 7: 3, 8: 6, 9: 6, 10: 8],
                     "every code od8CheckWant gives is in the file: \(seen)")
        // The GFX drift boundary, by hand: +25 MHz is taken, +26 is not.
        var drift = base
        drift.fresh[Rules.gfxMax].def += 25
        suite.expect(Rules.check(.stock, drift).check == .ok, "GFX default 25 MHz away: still ok")
        drift.fresh[Rules.gfxMax].def += 1
        suite.expect(Rules.check(.stock, drift).check == .drifted, "26 MHz away: drifted")
    }

    private static func want(_ dict: [String: Any]) -> GPUControlOD8Want {
        let temps = (dict["temp"] as? [Int]) ?? []
        let speeds = (dict["speed"] as? [Int]) ?? []
        let curve = (dict["curve"] as? Bool) == true
            ? zip(temps, speeds).map { GPUControlFanPoint(temperatureC: $0, speedPercent: $1) } : nil
        let gfx = (dict["gfx"] as? Int) ?? 0
        return GPUControlOD8Want(curve: curve, zeroRpmOff: (dict["zeroRpmOff"] as? Bool) == true,
                                 gfxMaxMHz: gfx == 0 ? nil : gfx)
    }

    private static func apply(_ mutation: [String: Any], to state: inout Rules.State) {
        let kind = mutation["kind"] as? String ?? ""
        let value = (mutation["value"] as? NSNumber)?.int64Value ?? 0
        let id = mutation["id"] as? Int ?? 0
        let field = mutation["field"] as? String ?? ""
        func change(_ entry: inout Rules.Entry) {
            switch field {
            case "feature": entry.feature = UInt32(truncatingIfNeeded: value)
            case "min": entry.min = Int(value)
            case "max": entry.max = Int(value)
            case "def": entry.def = Int(value)
            default: break
            }
        }
        switch kind {
        case "freshCaps": state.freshCaps = UInt32(truncatingIfNeeded: value)
        case "firstCaps": state.firstCaps = UInt32(truncatingIfNeeded: value)
        case "freshEntry": change(&state.fresh[id])
        case "firstEntry": change(&state.first[id])
        case "bothEntry": change(&state.fresh[id]); change(&state.first[id])
        case "cur": state.current[id] = Int(value)
        default: break
        }
    }

    // MARK: Preview

    private static func preview(_ suite: TestSuite) {
        guard let writing = realWriting() else { return }
        let tested = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve)
        suite.expect(GPUControlCurvePreview.make(want: tested, writing: writing) == .accepted,
                     "the tested curve: the kext would accept it")
        var last50 = GPUControlFanDraft.testedCurve
        last50[4].temperatureC = 50
        suite.expect(GPUControlCurvePreview.make(want: GPUControlOD8Want(curve: last50), writing: writing)
                        == .refused(Rules.Result(check: .curveLast, point: 5)),
                     "last point at 50 C: refused, point 5 (plan 11.4 step 14)")
        var order = GPUControlFanDraft.testedCurve
        order[2].speedPercent = 30
        suite.expect(GPUControlCurvePreview.make(want: GPUControlOD8Want(curve: order), writing: writing)
                        == .refused(Rules.Result(check: .curveOrder, point: 3)), "a falling speed at point 3")
        var low = GPUControlFanDraft.testedCurve
        low[0].speedPercent = 10
        suite.expect(GPUControlCurvePreview.make(want: GPUControlOD8Want(curve: low), writing: writing)
                        == .refused(Rules.Result(check: .curveRange, point: 1)),
                     "10 % is below the driver's 20 % minimum: out of range, point 1")
        // 22 % at 40 C where the stock curve gives 28 %.
        var less = GPUControlFanDraft.testedCurve
        less[1].speedPercent = 22
        suite.expect(GPUControlCurvePreview.make(want: GPUControlOD8Want(curve: less), writing: writing)
                        == .refused(Rules.Result(check: .curveCooling, point: 2)), "less air than stock at point 2")
        suite.expect(GPUControlCurvePreview.make(want: GPUControlOD8Want(zeroRpmOff: true), writing: writing) == .accepted,
                     "zero RPM off alone: no curve rules")

        var other = writing
        other.kextVersion = "REL-073-2026-12-01"
        suite.expect(GPUControlCurvePreview.make(want: tested, writing: other) == .notChecked,
                     "another kext build: not checked, Apply off")
        other.kextVersion = nil
        suite.expect(GPUControlCurvePreview.make(want: tested, writing: other) == .notChecked, "no build name: not checked")
        var odd = writing
        odd.od8Read = .notClean("read, but an entry is not as expected")
        suite.expect(GPUControlCurvePreview.make(want: tested, writing: odd) == .unavailable, "OD8 not clean: unavailable")
        suite.expect(GPUControlCurvePreview.make(want: tested, writing: nil) == .unavailable, "no table: unavailable")
        suite.expect(!GPUControlCurvePreview.notChecked.allowsApply && !GPUControlCurvePreview.unavailable.allowsApply
                        && GPUControlCurvePreview.accepted.allowsApply, "Apply only for an accepted draft")

        // The sentences: the rule names the point; state checks use the group.
        let fan = GPUControlFanStrings.es
        suite.expect(String(format: fan.curveFailFormat, 5, fan.rule(.curveLast, limitC: 48) ?? "")
                        == "Punto 5: el último punto tiene que ser 100% a 48 °C o menos.", "the failing point in Spanish")
        for check in [GPUControlOD8Check.curveRange, .curveOrder, .curveFirst, .curveLast, .curveCooling] {
            suite.expect(fan.rule(check, limitC: 48) != nil, "\(check): a rule sentence")
        }
        for check in [GPUControlOD8Check.drifted, .memoryMoved, .noFeature, .gfxRange] {
            suite.expect(fan.rule(check, limitC: 48) == nil && GPUControlTextGroup.forOD8Check(check.rawValue) != nil,
                         "\(check): the grouped sentence and the kext's words")
        }
    }

    // MARK: Draft and scalars

    private static func draftAndScalars(_ suite: TestSuite) {
        let start = GPUControlFanDraft()
        suite.expect(!start.customCurve && !start.zeroRpmOff && start.points == GPUControlFanDraft.testedCurve,
                     "the draft starts at the tested curve, off")
        suite.expect(start.want.isStock, "both off: the stock state, sent as the way back")
        let held = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, zeroRpmOff: true)
        suite.expect(GPUControlFanDraft(held: held).want == held, "the draft starts from what is held")
        var draft = GPUControlFanDraft()
        draft.customCurve = true
        draft.zeroRpmOff = true
        suite.expect(draft.want.scalars() == [2, 3, 30, 40, 44, 46, 48, 20, 36, 52, 68, 100, 0],
                     "curve and zero RPM off: flags 3, the points, stock clock")
        draft.customCurve = false
        suite.expect(draft.want.scalars() == [2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                     "zero RPM off only: flags 2, ten zeros")
        draft.zeroRpmOff = false
        draft.customCurve = true
        suite.expect(draft.want.scalars()?[1] == 1, "curve only: flags 1")

        // The page drawn before the first status, then a held curve: the
        // untouched editor follows it, so Apply does not give it back.
        suite.expect(!GPUControlFanDraft().edited && !GPUControlFanDraft(held: held).edited,
                     "a seeded draft starts unedited")
        let followed = GPUControlFanDraft().following(held: held)
        suite.expect(followed.want == held, "an untouched draft follows what is held")
        suite.expect(followed.following(held: .stock).want.isStock,
                     "the hold went away on its own: the untouched draft follows back")
        var edited = GPUControlFanDraft()
        edited.zeroRpmOff = true
        suite.expect(edited.edited && edited.following(held: held) == edited, "an edit stays")
        // An edit set back to the seeded values is still the owner's: the
        // next state from the kext does not overwrite it.
        var undone = GPUControlFanDraft()
        undone.zeroRpmOff = true
        undone.zeroRpmOff = false
        suite.expect(undone.want.isStock && undone.following(held: held) == undone,
                     "an edit back to the seed stays")
        var pointBack = GPUControlFanDraft(held: held)
        pointBack.points[2].speedPercent += 4
        pointBack.points[2].speedPercent -= 4
        suite.expect(pointBack.edited && pointBack.following(held: .stock).want == held,
                     "a point moved and back is still an edit")
        // Applied: the next state seeds it again.
        let sent = edited.applied
        suite.expect(!sent.edited && sent.want == edited.want, "applying keeps the values, not the edit mark")
        suite.expect(sent.following(held: held).want == held, "after Apply the draft follows what the kext holds")

        // The button's title: a stock draft over a held fan state is the way back.
        suite.expect(GPUControlFanDraft().givesBack(held), "both off over a held curve: back to stock")
        suite.expect(!GPUControlFanDraft().givesBack(.stock), "nothing held: still Apply")
        suite.expect(!GPUControlFanDraft(held: held).givesBack(held), "a curve over a curve: Apply")
        suite.expect(!GPUControlFanDraft().givesBack(GPUControlOD8Want(curve: held.curve, gfxMaxMHz: 2_000)),
                     "a clock held too: not the whole way back, so Apply")
    }

    // MARK: The controller against the model

    private static func controller(_ suite: TestSuite) {
        let curve = GPUControlFanDraft.testedCurve
        // Power held, then a curve: the power limit goes back first.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.chooseFan(curve: curve, zeroRpmOff: false)
            h.run(ms: 10_000)
            suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: curve)), "power to curve: the curve held")
            suite.expect(h.fake.writes.map(\.kind) == [.power(220), .wayBack, .od8(GPUControlOD8Want(curve: curve))]
                            && h.gapsKept, "power to curve: change, way back, curve, gaps kept")
            suite.expect(h.calls(.setOD8).count == 1, "the curve is sent once")
            // And back to a power limit.
            h.engine.choose(.power(watts: 210))
            h.run(ms: 10_000)
            suite.expect(h.engine.snapshot.held == .power(watts: 210) && h.gapsKept, "curve to power: 210 W held")
        }
        // A curve the kext refuses: the refusal, nothing held.
        do {
            let h = Harness()
            h.fake.refuseNextOD8 = .curveCooling
            h.engine.chooseFan(curve: curve, zeroRpmOff: true)
            h.run(ms: 0)
            guard case .refused(let request, let answer)? = h.engine.snapshot.outcome else {
                suite.expect(false, "a refused curve: refused")
                return
            }
            suite.expect(request.isOD8 && answer.check == .curveCooling && h.engine.snapshot.held == nil,
                         "a refused curve: the reason, nothing held")
        }
        // Zero RPM with the curve, then the curve alone: every call is whole.
        do {
            let h = Harness()
            h.engine.chooseFan(curve: curve, zeroRpmOff: true)
            h.run(ms: 3_000)
            h.engine.chooseFan(curve: curve, zeroRpmOff: false)
            h.run(ms: 3_000)
            let flags = h.calls(.setOD8).map { $0.input[1] }
            suite.expect(flags == [3, 1], "curve + zero RPM off, then the curve alone: flags 3 then 1")
            suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: curve)), "the curve alone held")
        }
        // A curve held over a sleep, remembering on: asked again after the wake.
        do {
            let h = Harness(reask: true)
            h.engine.chooseFan(curve: curve, zeroRpmOff: false)
            h.run(ms: 0)
            h.fake.sleep()
            h.fake.wake()
            h.engine.didWake()
            h.run(ms: 40_000)
            suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: curve)) && h.gapsKept,
                         "the curve back after the wake (plan 11.4 step 18)")
        }
        // The watchdog while the curve is held: writing off, told, stopped.
        do {
            let h = Harness()
            h.engine.chooseFan(curve: curve, zeroRpmOff: false)
            h.run(ms: 0)
            h.fake.tripFanWatchdog()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.od8Watchdog.rawValue)
                            && h.notices == [.writingOff(.od8Watchdog)], "watchdog: stopped and told")
        }
    }

    // MARK: Remembering a fan state

    private static func remember(_ suite: TestSuite) {
        let suiteName = "ryzenstatus.tests.gpucontrol.fan.\(getpid())"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let want = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve, zeroRpmOff: true)
        GPUControlRemembered.od8(want).save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .od8(want), "a fan state round-trips")
        GPUControlRemembered.od8(GPUControlOD8Want(zeroRpmOff: true)).save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .od8(GPUControlOD8Want(zeroRpmOff: true)),
                     "zero RPM off alone round-trips, no curve")
        GPUControlRemembered.power(watts: 220).save(defaults)
        suite.expect(GPUControlRemembered.load(defaults) == .power(watts: 220)
                        && defaults.object(forKey: DefaultsKey.gpuControlRememberedCurve) == nil,
                     "saving power clears the fan keys")
        defaults.set("od8", forKey: DefaultsKey.gpuControlRememberedKind)
        defaults.set([1, 2, 3], forKey: DefaultsKey.gpuControlRememberedCurve)
        suite.expect(GPUControlRemembered.load(defaults) == .nothing, "a broken saved curve is nothing")
        defaults.removePersistentDomain(forName: suiteName)

        suite.expect(GPUControlRememberPolicy.toSave(held: .od8(want), ownerChoseStartUp: false, active: true) == .od8(want),
                     "a confirmed fan hold is saved")
        var facts = GPUControlFacts(source: .properties)
        facts.ready = true
        facts.armed = true
        facts.bootW = 240
        facts.od8Ready = true
        let checked = "REL-072-2026-11-19"
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts, stopped: nil,
                                                      kextVersion: checked)
                        == .od8(want), "writing open, OD8 read: ask for the fan state")
        // Another kext build: Apply is off, and the remembered state is not
        // asked for either.
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts, stopped: nil,
                                                      kextVersion: "REL-073-2026-12-01") == nil,
                     "another kext build: no remembered fan state")
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts, stopped: nil)
                        == nil, "no build name: no remembered fan state")
        suite.expect(GPUControlRememberPolicy.request(remembered: .power(watts: 220), active: true, facts: facts,
                                                      stopped: nil, kextVersion: "REL-073-2026-12-01")
                        == .power(watts: 220), "the power limit does not depend on the curve rules")
        facts.od8Ready = false
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts, stopped: nil,
                                                      kextVersion: checked) == nil,
                     "OD8 not read: nothing")
    }

    // MARK: Strings

    private static func strings(_ suite: TestSuite) {
        func specifiers(_ text: String) -> [String] {
            let pattern = try? NSRegularExpression(pattern: "%%|%(\\d\\$)?[@d]")
            let range = NSRange(text.startIndex..., in: text)
            return pattern?.matches(in: text, range: range)
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                .filter { $0 != "%%" } ?? []
        }
        let english = GPUControlFanStrings.enUS.all
        suite.expect(english.count == 24, "24 texts")
        for language in AppLanguage.allCases {
            let fan = FeatureStrings.gpuControlFan(language)
            // Two buttons on one page never share a name.
            suite.expect(fan.backToStock != FeatureStrings.gpuControlPage(language).backToBoot,
                         "\(language.rawValue): the fan's way back is not the power section's button")
            let table = fan.all
            suite.expect(table.count == english.count && table.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "\(language.rawValue): every fan text is there")
            for (index, text) in table.enumerated() {
                suite.expect(specifiers(text) == specifiers(english[index]),
                             "\(language.rawValue): fan text \(index) keeps the English placeholders")
                // Every literal percent in a format is written %%.
                let formatted = String(format: text, 1, "x")
                suite.expect(!formatted.contains("%%") && !formatted.isEmpty, "\(language.rawValue): fan text \(index) formats")
            }
        }
        suite.expect(String(format: GPUControlFanStrings.enUS.limitFormat, 48) == "100% by 48 °C", "the rule's label")
        suite.expect(String(format: GPUControlFanStrings.tr.limitFormat, 48) == "48 °C'de %100", "Turkish puts % first")
    }
}
