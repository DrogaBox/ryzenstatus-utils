// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Settings > GPU control > Profiles: the stored shape with its version,
/// the names, the request a profile becomes on a card, the profile that
/// matches what is held, and the words.
enum GPUControlProfileTests {
    static func run(_ suite: TestSuite) {
        encoding(suite)
        names(suite)
        store(suite)
        loading(suite)
        matching(suite)
        strings(suite)
    }

    private typealias Want = GPUControlOD8Want
    private typealias Policy = GPUControlRememberPolicy

    private static let card = GPUControlProfileCard(deviceID: 0x73BF, bootW: 240, floorW: 225, ceilW: 261,
                                                    stockGfxMaxMHz: 2_359, gfxMaxTopMHz: 2_800,
                                                    gfxMinStockMHz: 500, voltStockMV: 1_075, voltMinMV: 881)

    private static let curve = [
        GPUControlFanPoint(temperatureC: 30, speedPercent: 25),
        GPUControlFanPoint(temperatureC: 50, speedPercent: 35),
        GPUControlFanPoint(temperatureC: 65, speedPercent: 50),
        GPUControlFanPoint(temperatureC: 80, speedPercent: 75),
        GPUControlFanPoint(temperatureC: 90, speedPercent: 100),
    ]

    /// The test card's limits as the kext reports them.
    private static func facts(armed: Bool = true, ready: Bool = true, od8Ready: Bool = true,
                              owned: Bool = false, mine: Bool = false) -> GPUControlFacts {
        var f = GPUControlFacts(source: .properties)
        f.ready = ready
        f.armed = armed
        f.od8Ready = od8Ready
        f.takesRaise = true
        f.owned = owned
        f.mine = mine
        f.bootW = 240
        f.powerRange = GPUControlPowerRange(source: .kext, floorW: 225, maxW: 240, ceilW: 261, stepW: 10,
                                            percentMin: -6, percentMax: 9)
        return f
    }

    private static func load(_ profile: GPUControlProfile, facts: GPUControlFacts? = facts(),
                             card: GPUControlProfileCard = card, stockGfxMaxMHz: Int? = 2_359,
                             od8Ready: Bool = true, kextVersion: String? = "REL-090-2026-11-25",
                             gfxMin: GPUControlClockMinLogic.Limits? = nil,
                             volt: GPUControlVoltLogic.Limits? = GPUControlVoltLogic.Limits(min: 881, stock: 1_075),
                             overclock: GPUControlOverclockLogic.GfxLimits? = GPUControlOverclockLogic.GfxLimits(stock: 2_359, max: 2_800),
                             overclockAllowed: Bool = false) -> GPUControlProfileLoad {
        GPUControlProfiles.load(profile, card: card, facts: facts, stockGfxMaxMHz: stockGfxMaxMHz,
                                od8Ready: od8Ready, kextVersion: kextVersion, gfxMin: gfxMin, volt: volt,
                                overclock: overclock, overclockAllowed: overclockAllowed)
    }

    private static func profile(_ name: String, _ request: GPUControlRequest) -> GPUControlProfile {
        GPUControlProfile(name: name, request: request, card: card)
    }

    // MARK: The stored shape

    private static func encoding(_ suite: TestSuite) {
        let power = profile("Quiet", .power(watts: 220))
        let od8 = profile("Game", .od8(Want(curve: curve, zeroRpmOff: true, gfxMaxMHz: 2_500,
                                            gfxMinMHz: 1_600, voltMV: 1_050, overclock: true)))
        for original in [power, od8] {
            let data = GPUControlProfileStore(profiles: [original]).encoded()
            let back = data.flatMap(GPUControlProfileStore.decode)
            suite.expect(back?.profiles == [original], "\(original.name): written and read back unchanged")
            suite.expect(back?.isNewerVersion == false, "\(original.name): the version is this build's")
        }
        let json = """
        {"version":1,"profiles":[{"name":"  Quiet  ","kind":"power","watts":220,"card":{"deviceID":29631,"bootW":240},"future":1}]}
        """
        let read = GPUControlProfileStore.decode(Data(json.utf8))
        suite.expect(read?.profiles.map(\.name) == ["Quiet"], "a stored name is trimmed, an unknown key is ignored")
        suite.expect(read?.profiles.first?.request == .power(watts: 220), "the power limit reads back")
        suite.expect(read?.profiles.first?.card.deviceID == 0x73BF, "the card's device id is kept")

        // A file from a newer build: no profiles, and no save over it.
        let future = Data("""
        {"version":9,"profiles":[{"name":"Future","kind":"power","watts":200}]}
        """.utf8)
        let newer = GPUControlProfileStore.decode(future)
        suite.expect(newer?.profiles.isEmpty == true && newer?.isNewerVersion == true,
                     "a file from a newer build is ignored, not a crash")
        suite.expect(newer?.encoded() == nil, "and nothing is written over it")
        let defaults = UserDefaults(suiteName: "gpucontrol.profile.newer")!
        defaults.removePersistentDomain(forName: "gpucontrol.profile.newer")
        defaults.set(future, forKey: DefaultsKey.gpuControlProfiles)
        var kept = GPUControlProfileStore.load(defaults)
        kept.add(power)
        kept.save(defaults)
        suite.expect(defaults.data(forKey: DefaultsKey.gpuControlProfiles) == future,
                     "saving with a newer file in place leaves that file alone")

        suite.expect(GPUControlProfileStore.decode(Data("not json".utf8)) == nil, "garbage is no store")
        suite.expect(GPUControlProfileStore.decode(Data("{}".utf8)) == nil, "no version, no store")
        suite.expect(GPUControlProfileStore.decode(Data(#"{"version":0,"profiles":[]}"#.utf8)) == nil,
                     "version 0 is no store")

        // One entry this build cannot use does not take the others with it.
        let mixed = Data("""
        {"version":1,"profiles":[
          {"name":"Newer","kind":"curve-thing"},
          {"name":"Game","kind":"od8","curve":[30,25,50,35,65,50,80,75],"zeroRpmOff":true},
          {"name":"Stock","kind":"od8"},
          {"name":"Quiet","kind":"power","watts":220}
        ]}
        """.utf8)
        let read2 = GPUControlProfileStore.decode(mixed)
        suite.expect(read2?.profiles.map(\.name) == ["Quiet"],
                     "an unknown kind, a short curve and a stock state are dropped; the rest stays")
        let empty = Data(#"{"version":1,"profiles":[{"name":"   ","kind":"power","watts":220}]}"#.utf8)
        suite.expect(GPUControlProfileStore.decode(empty)?.profiles.isEmpty == true, "a blank name is no profile")
        let noWatts = Data(#"{"version":1,"profiles":[{"name":"A","kind":"power"}]}"#.utf8)
        suite.expect(GPUControlProfileStore.decode(noWatts)?.profiles.isEmpty == true, "a power limit of 0 is no profile")

        // Only what is worth a name.
        suite.expect(GPUControlProfiles.profile(named: "Stock", held: .startUp, card: card) == nil,
                     "the way back to stock is not a profile")
        suite.expect(GPUControlProfiles.profile(named: "Stock", held: .od8(.stock), card: card) == nil,
                     "nor a stock OD8 state")
        suite.expect(GPUControlProfiles.profile(named: "Quiet", held: .power(watts: 220), card: card)?.request
                        == .power(watts: 220),
                     "a power limit is one")
    }

    // MARK: Names

    private static func names(_ suite: TestSuite) {
        suite.expect(GPUControlProfileStore.clean("  Quiet  ") == "Quiet", "a name is trimmed")
        suite.expect(GPUControlProfileStore.clean("   ") == nil && GPUControlProfileStore.clean("") == nil,
                     "a blank name is not saved")
        var store = GPUControlProfileStore(profiles: [profile("Game", .power(watts: 220))])
        suite.expect(store.isTaken("Game") && store.isTaken("game") && store.isTaken(" GAME "),
                     "names are unique without regard to case, after trimming")
        suite.expect(!store.isTaken("Quiet"), "another name is free")
        suite.expect(!store.isTaken("game", excluding: "Game"), "renaming to its own name is not a clash")
        suite.expect(store.isTaken("Game", excluding: "Other"), "but it clashes with a different entry")
        suite.expect(store.profile(named: "game")?.name == "Game", "a name finds its profile in any case")

        store.add(profile("game", .power(watts: 200)))
        suite.expect(store.profiles.count == 1 && store.profiles.first?.request == .power(watts: 200),
                     "adding a name that exists replaces it, never a second row")
        suite.expect(store.rename("game", to: "Quiet") && store.profiles.first?.name == "Quiet",
                     "renaming finds the profile in any case")
        suite.expect(store.remove(named: "Quiet") && store.profiles.isEmpty, "deleting takes it out")
        suite.expect(!store.remove(named: "Quiet"), "deleting a name that is not there changes nothing")
    }

    private static func store(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "gpucontrol.profile.store")!
        defaults.removePersistentDomain(forName: "gpucontrol.profile.store")
        suite.expect(GPUControlProfileStore.load(defaults).profiles.isEmpty, "no key, no profiles")
        var store = GPUControlProfileStore()
        store.add(profile("Quiet", .power(watts: 220)))
        store.add(profile("Game", .od8(Want(gfxMaxMHz: 2_500, voltMV: 1_050, overclock: true))))
        store.save(defaults)
        let read = GPUControlProfileStore.load(defaults)
        suite.expect(read.profiles == store.profiles, "both profiles come back from the defaults")
        suite.expect(defaults.data(forKey: DefaultsKey.gpuControlProfiles) != nil,
                     "they live under the GPU control's own key")
    }

    // MARK: The request a profile becomes

    private static func loading(_ suite: TestSuite) {
        // The power limit.
        let lower = load(profile("Quiet", .power(watts: 230)))
        suite.expect(lower.request == .power(watts: 230) && lower.leftOut.isEmpty && lower.blocked == nil,
                     "230 W is inside the card's range: it goes out as it is")
        suite.expect(lower.cardChanged == false, "and it was made on this card")
        suite.expect(load(profile("Boot", .power(watts: 240))).request == .startUp,
                     "the start-up limit is the way back, as choosing it is")
        let tooLow = load(profile("Low", .power(watts: 200)))
        suite.expect(tooLow.request == nil && tooLow.blocked == .outOfRange,
                     "below the card's floor: nothing goes, and the page says why")
        let raisedOff = load(profile("Raise", .power(watts: 261)), overclockAllowed: false)
        suite.expect(raisedOff.request == nil && raisedOff.blocked == .raiseNeedsOverclock
                        && raisedOff.raiseNeedsOverclock,
                     "a raised power limit with Allow overclocking off: left out, and the page says why")
        let raisedOn = load(profile("Raise", .power(watts: 261)), overclockAllowed: true)
        suite.expect(raisedOn.request == .power(watts: 261), "the same with the switch on: it goes out")
        suite.expect(load(profile("Odd", .power(watts: 250)), overclockAllowed: true).request == .power(watts: 250),
                     "every value the raised pop-up offers is taken")
        suite.expect(load(profile("Past", .power(watts: 270)), overclockAllowed: true).blocked == .outOfRange,
                     "above the card's ceiling: not taken")
        suite.expect(load(profile("Quiet", .power(watts: 220)), facts: nil).blocked == .waitingForDriver,
                     "no facts yet: nothing is sent")

        // The OD8 state.
        let lowered = load(profile("Clock", .od8(Want(gfxMaxMHz: 2_000))))
        suite.expect(lowered.request == .od8(Want(gfxMaxMHz: 2_000)) && lowered.leftOut.isEmpty,
                     "a lowered GFX maximum goes out, nothing left out")
        suite.expect(load(profile("Below", .od8(Want(gfxMaxMHz: 1_400)))).leftOut == [.gfxMax]
                        && load(profile("Below", .od8(Want(gfxMaxMHz: 1_400)))).request == nil,
                     "below the kext's floor: left out, and nothing is left to send")
        let raiseOn = load(profile("Game", .od8(Want(gfxMaxMHz: 2_500, overclock: true))), overclockAllowed: true)
        suite.expect(raiseOn.request == .od8(Want(gfxMaxMHz: 2_500, overclock: true)) && raiseOn.leftOut.isEmpty,
                     "a raised maximum with Allow overclocking on: it goes out with its flag")
        let raiseOff = load(profile("Game", .od8(Want(gfxMaxMHz: 2_500, overclock: true))), overclockAllowed: false)
        suite.expect(raiseOff.request == nil && raiseOff.blocked == .raiseNeedsOverclock
                        && raiseOff.raiseNeedsOverclock,
                     "a raise alone with the switch off: the page says what to turn on")
        let mixed = Want(curve: curve, zeroRpmOff: true, gfxMaxMHz: 2_500, voltMV: 1_050, overclock: true)
        let mixedOff = load(profile("Mixed", .od8(mixed)), overclockAllowed: false)
        suite.expect(mixedOff.request == .od8(Want(curve: curve, zeroRpmOff: true, voltMV: 1_050)),
                     "with the switch off the raise goes and the rest of the state stays")
        suite.expect(mixedOff.leftOut == [.gfxMax, .raise] && mixedOff.raiseNeedsOverclock,
                     "and the page names what it left out")

        let voltOnly = load(profile("Volt", .od8(Want(voltMV: 950))),
                            volt: GPUControlVoltLogic.Limits(min: 1_000, stock: 1_075))
        suite.expect(voltOnly.request == nil && voltOnly.leftOut == [.volt] && voltOnly.blocked == .outOfRange,
                     "a voltage this card's table does not offer: left out")
        let minOnly = load(profile("Min", .od8(Want(gfxMinMHz: 1_900))), gfxMin: nil)
        suite.expect(minOnly.leftOut == [.gfxMin], "a GFX minimum the kext does not take: left out")

        // The fan state needs a build the curve rules were checked with.
        let fanOnOld = load(profile("Fan", .od8(Want(curve: curve))), kextVersion: "REL-073-2026-12-01")
        suite.expect(fanOnOld.request == nil && fanOnOld.blocked == .fanNotChecked,
                     "a fan curve and an unchecked kext build: nothing goes, as Apply curve would not")
        suite.expect(load(profile("Fan", .od8(Want(curve: curve)))).request == .od8(Want(curve: curve)),
                     "the checked build takes the same curve")

        // Where writing stands.
        suite.expect(load(profile("Quiet", .power(watts: 220)), facts: facts(armed: false)).blocked == .writingClosed,
                     "writing closed: the page says to open it")
        suite.expect(load(profile("Quiet", .power(watts: 220)), facts: facts(owned: true)).blocked == .otherProgram,
                     "another program holds a change: close it first")
        var off = facts()
        off.off = true
        suite.expect(load(profile("Quiet", .power(watts: 220)), facts: off).blocked == .writingClosed,
                     "writing off until restart: no profile goes out")
        suite.expect(load(profile("Quiet", .power(watts: 220)), facts: facts(ready: false)).blocked == .waitingForDriver,
                     "the kext is not ready yet: wait")
        suite.expect(load(profile("Game", .od8(Want(gfxMaxMHz: 2_000))), od8Ready: false).blocked == .od8NotRead,
                     "OD8 not read since the restart: no fan or clock state")

        // Another card: it is still listed, and what it holds is checked again.
        let otherCard = GPUControlProfileCard(deviceID: 0x73E0, bootW: 240)
        let moved = load(profile("Quiet", .power(watts: 230)), card: otherCard)
        suite.expect(moved.cardChanged && moved.request == .power(watts: 230),
                     "a profile from another card still loads, and the page says the card changed")
        let movedRaise = load(profile("Game", .od8(Want(gfxMaxMHz: 2_500, overclock: true))),
                              card: otherCard, overclockAllowed: false)
        suite.expect(movedRaise.cardChanged && movedRaise.blocked == .raiseNeedsOverclock,
                     "and its checks are this card's")
        suite.expect(load(profile("Quiet", .power(watts: 220)),
                          card: GPUControlProfileCard(deviceID: 0x73BF, bootW: 250)).cardChanged,
                     "a card that starts at another limit is a different card too")
        suite.expect(!load(profile("Quiet", .power(watts: 220)),
                           card: GPUControlProfileCard(deviceID: 0x73BF, bootW: 240, stockGfxMaxMHz: 2_400)).cardChanged,
                     "a stock maximum that moved a little is the same card")

        // Which parts are named as left out.
        suite.expect(GPUControlProfiles.leftOut(mixed, keptIn: Want(curve: curve, zeroRpmOff: true, voltMV: 1_050))
                        == [.gfxMax, .raise],
                     "the sentence names the clock and the raise, not what stayed")
        suite.expect(GPUControlProfiles.leftOut(Want(gfxMinMHz: 1_600, voltMV: 1_050),
                                                keptIn: Want(voltMV: 1_050)) == [.gfxMin],
                     "one part at a time")
        suite.expect(GPUControlProfiles.leftOut(.stock, keptIn: .stock).isEmpty, "a stock state leaves nothing out")
    }

    private static func matching(_ suite: TestSuite) {
        let profiles = [profile("Quiet", .power(watts: 220)), profile("Game", .od8(Want(gfxMaxMHz: 2_000)))]
        suite.expect(GPUControlProfiles.match(profiles, held: .power(watts: 220)) == "Quiet",
                     "the profile that is exactly what the card holds")
        suite.expect(GPUControlProfiles.match(profiles, held: .od8(Want(gfxMaxMHz: 2_000))) == "Game",
                     "the OD8 one too")
        suite.expect(GPUControlProfiles.match(profiles, held: .power(watts: 230)) == nil,
                     "another limit matches nothing")
        suite.expect(GPUControlProfiles.match(profiles, held: nil) == nil, "nothing held, no match")
        suite.expect(GPUControlProfiles.match(profiles, held: .startUp) == nil, "the way back is not a profile")
        suite.expect(GPUControlProfiles.match([], held: .power(watts: 220)) == nil, "no profiles, no match")

        // A remembered power raise is checked against the switch too, not
        // only an OD8 raise.
        suite.expect(Policy.checkedAgain(.power(watts: 261), stockGfxMaxMHz: 2_359, overclockAllowed: false,
                                         bootW: 240) == nil, "a raised power limit is dropped with the switch off")
        suite.expect(Policy.checkedAgain(.power(watts: 261), stockGfxMaxMHz: 2_359, overclockAllowed: true,
                                         bootW: 240) == .power(watts: 261), "and kept with it on")
        suite.expect(Policy.checkedAgain(.power(watts: 225), stockGfxMaxMHz: 2_359, overclockAllowed: false,
                                         bootW: 240) == .power(watts: 225), "a lowered limit needs no switch")
        suite.expect(Policy.checkedAgain(.power(watts: 261), stockGfxMaxMHz: 2_359, overclockAllowed: false,
                                         bootW: nil) == .power(watts: 261), "no start-up limit known: left as it is")
    }

    // MARK: The words

    private static func strings(_ suite: TestSuite) {
        let en = GPUControlProfileStrings.enUS
        for language in AppLanguage.allCases {
            let s = FeatureStrings.gpuControlProfile(language)
            suite.expect(s.all.allSatisfy { !$0.isEmpty }, "\(language.rawValue): every profile text is filled")
            suite.expect(Set(s.all).count >= s.all.count - 1, "\(language.rawValue): the texts are not the same word")
            suite.expect(s.leftOutFormat.components(separatedBy: "%1$@").count == 2
                            && s.leftOutFormat.components(separatedBy: "%2$@").count == 2
                            && !s.leftOutFormat.contains("%@"),
                         "\(language.rawValue): the left-out text takes the name and the list")
            let sentence = String(format: s.leftOutFormat, "Quiet", s.fieldFanCurve + s.listLastSeparator + s.fieldVolt)
            suite.expect(!sentence.contains("%") && sentence.contains("Quiet"),
                         "\(language.rawValue): it formats cleanly")
            suite.expect(s.loadedFormat.components(separatedBy: "%@").count == 2, "\(language.rawValue): the loaded text takes the name")
            suite.expect(s.duplicateName.components(separatedBy: "%@").count == 2, "\(language.rawValue): the clash text takes the name")
            suite.expect(s.deleteMessage.components(separatedBy: "%@").count == 2, "\(language.rawValue): the delete text takes the name")
            suite.expect(!s.section.isEmpty && !s.load.isEmpty && !s.delete.isEmpty && !s.blockedWriting.isEmpty,
                         "\(language.rawValue): the section, its buttons and its reasons are filled")
            if language != .enUS {
                suite.expect(s.footer != en.footer && s.otherCard != en.otherCard,
                             "\(language.rawValue): the footer and the card sentence are translated")
            }
        }
        suite.expect(FeatureStrings.gpuControlProfile(.zhHK).section == FeatureStrings.gpuControlProfile(.zhTW).section,
                     "Hong Kong uses the traditional Chinese texts")
        suite.expect(GPUControlProfileField.allCases.map { en.field($0) } == [en.fieldPower, en.fieldFanCurve,
                                                                            en.fieldZeroRpm, en.fieldGfxMax,
                                                                            en.fieldGfxMin, en.fieldVolt,
                                                                            en.fieldRaise],
                     "every part of a profile has its words, in the order they are listed")
    }
}
