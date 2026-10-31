// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// The companions' engine: what runs while the island cannot show, how often
/// it looks at the windows, which screen a point belongs to, the hearts after
/// a long pause, and the bond and gold kept in the preferences.
enum NotchMascotRuntimeTests {
    static func run(_ suite: TestSuite) {
        heartsAfterLongPause(suite)
        windowWatchInterval(suite)
        nearestScreen(suite)
        frameRates(suite)
        tolerantBond(suite)
        bondMap(suite)
        bondStoreKeepsWhatItCannotRead(suite)
        readingBondDoesNotWrite(suite)
        unchangedBondIsNotSaved(suite)
        spentGoldIsSavedAtOnce(suite)
        backgroundLifeStopsWithTheIsland(suite)
        desktopSoundsBelongToTheOuting(suite)
        reduceMotionAndLowPower(suite)
        displayLinkGoesWithTheOuting(suite)
        spriteSheetsAreShared(suite)
    }

    // MARK: Pure rules

    private static func heartsAfterLongPause(_ suite: TestSuite) {
        let drain = NotchMascotRPG.drainPerSecond
        // Two hours from vitality 15: fed for a while, then starving.
        var stepped = 8.0
        var vitality = 15.0
        for _ in 0..<1200 {
            stepped = NotchMascotRPG.hearts(stepped, containers: 10, vitality: vitality, elapsed: 6)
            vitality = NotchMascotRPG.clampVitality(vitality - 6 * drain)
        }
        let once = NotchMascotRPG.hearts(8, containers: 10, vitality: 15, elapsed: 7200)
        suite.expect(abs(once - stepped) <= 6 * NotchMascotRPG.heartLossPerSecond + 0.0001,
                     "one two-hour step matches 1200 six-second steps (\(once) vs \(stepped))")
        suite.expect(once > 8 - 7200 * NotchMascotRPG.heartLossPerSecond,
                     "the fed part of a long pause does not starve")
        let fed = NotchMascotRPG.hearts(3, containers: 10, vitality: 100, elapsed: 3600)
        suite.expect(abs(fed - (3 + 3600 * NotchMascotRPG.heartGainPerSecond)) < 0.0001, "fed all along, hearts come back")
        let starving = NotchMascotRPG.hearts(5, containers: 10, vitality: 2, elapsed: 900)
        suite.expect(abs(starving - 4) < 0.0001, "starving all along, a heart fades every quarter hour")
        suite.expect(NotchMascotRPG.hearts(1.2, containers: 10, vitality: 0, elapsed: 36_000) == 1, "never below one heart")
        suite.expect(NotchMascotRPG.hearts(9.9, containers: 10, vitality: 100, elapsed: 36_000) == 10, "never above the containers")
    }

    private static func windowWatchInterval(_ suite: TestSuite) {
        func interval(climbs: Bool = true, perched: Bool, riding: Bool = false, pressed: Bool = false,
                      lowPower: Bool = false) -> Int {
            NotchMascotLedges.watchInterval(climbs: climbs, perched: perched, riding: riding, pressed: pressed,
                                            lowPower: lowPower)
        }
        suite.expect(interval(climbs: false, perched: true, riding: true) == 0, "without climbing it never looks")
        suite.expect(interval(perched: true) == 250, "on a window at rest it looks slowly")
        suite.expect(interval(perched: true, riding: true) == 33, "on a moving window it looks every frame or two")
        suite.expect(interval(perched: true, pressed: true) == 33, "on a window while the button is held, often")
        suite.expect(interval(perched: true, lowPower: true) == 250, "on a window, Low Power Mode keeps the slow look")
        suite.expect(interval(perched: false) == 0, "on the floor with nothing held it does not look")
        suite.expect(interval(perched: false, pressed: true) == 300, "on the floor while the button is held, it looks")
        suite.expect(interval(perched: false, pressed: true, lowPower: true) == 0, "on the floor in Low Power Mode, never")
    }

    private static func nearestScreen(_ suite: TestSuite) {
        let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1560, height: 1600)]
        suite.expect(NotchMascotRoam.screenIndex(for: CGPoint(x: 2000, y: 400), in: frames) == 1, "a point inside the second screen")
        suite.expect(NotchMascotRoam.screenIndex(for: CGPoint(x: 100, y: 100), in: frames) == 0, "a point inside the first screen")
        suite.expect(NotchMascotRoam.screenIndex(for: CGPoint(x: 1400, y: 1200), in: frames) == 1,
                     "a point in the gap of an L belongs to the nearer screen, not the first")
        suite.expect(NotchMascotRoam.screenIndex(for: CGPoint(x: -50, y: 450), in: frames) == 0, "left of everything, the first")
        suite.expect(NotchMascotRoam.screenIndex(for: .zero, in: []) == nil, "no screens, no index")
        suite.expect(NotchMascotRoam.distance(from: CGPoint(x: 10, y: 10), to: frames[0]) == 0, "inside is no distance")
        suite.expect(NotchMascotRoam.distance(from: CGPoint(x: 1443, y: 904), to: frames[0]) == 5, "corner distance is diagonal")
    }

    private static func frameRates(_ suite: TestSuite) {
        let range = NotchMascotDesktop.frameRates
        suite.expect(range.minimum == 30 && range.maximum == 72 && range.preferred == 60,
                     "the desktop companion asks for 60 frames, up to 72 and down to 30")
    }

    // MARK: The bond

    private static func json(_ text: String) -> Data { Data(text.utf8) }

    private static func tolerantBond(_ suite: TestSuite) {
        let decoder = JSONDecoder()
        let bare = try? decoder.decode(NotchMascotBond.self, from: json(#"{"adopted":0}"#))
        suite.expect(bare.map { $0.experience == 0 && $0.pets == 0 && $0.celebratedAges.isEmpty && $0.lastDay == nil } == true,
                     "a record with only its adoption day loads with zeros")
        let odd = try? decoder.decode(NotchMascotBond.self, from: json(#"{"adopted":0,"experience":-5,"pets":"x","moments":3}"#))
        suite.expect(odd.map { $0.experience == 0 && $0.pets == 0 && $0.moments == 3 } == true,
                     "a negative or unreadable field keeps its default, the rest loads")
        suite.expect((try? decoder.decode(NotchMascotBond.self, from: json("{}"))) == nil, "a record without an adoption day is unreadable")
        var full = NotchMascotBond(adopted: Date(timeIntervalSinceReferenceDate: 1000))
        full.experience = 420
        full.pets = 12
        full.moments = 3
        full.daysTogether = 9
        full.lastDay = "2026-10-30"
        full.petExperienceToday = 4
        full.momentExperienceToday = 2
        full.greetedDay = "2026-10-30"
        full.celebratedAges = [7]
        let again = (try? JSONEncoder().encode(full)).flatMap { try? decoder.decode(NotchMascotBond.self, from: $0) }
        suite.expect(again == full, "a full record survives a round trip")
    }

    private static let damagedMap = #"{"minimal":{"adopted":0,"experience":120},"dog":{"adopted":"x"},"cat":5,"fox":null}"#

    private static func bondMap(_ suite: TestSuite) {
        let decoded = NotchMascotBondStore.decodeBonds(json(damagedMap))
        suite.expect(decoded?.bonds.count == 1 && decoded?.bonds["minimal"]?.experience == 120,
                     "a damaged map keeps the entries it can read")
        suite.expect(decoded?.complete == false, "and says it could not read them all")
        let whole = NotchMascotBondStore.decodeBonds(json(#"{"minimal":{"adopted":0},"someday":{"adopted":5}}"#))
        suite.expect(whole?.complete == true && whole?.bonds.count == 2, "a sound map is read whole, unknown styles kept")
        suite.expect(NotchMascotBondStore.decodeBonds(json("garbage")) == nil, "garbage is no map")
        suite.expect(NotchMascotBondStore.decodeBonds(json("[1,2]")) == nil, "a list is no map")
    }

    /// A clean preferences domain for one test, removed again afterwards.
    private static func withDefaults(_ name: String, _ suite: TestSuite, _ body: (UserDefaults) -> Void) {
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "the preferences domain \(name) opens")
            return
        }
        defaults.removePersistentDomain(forName: name)
        body(defaults)
        defaults.removePersistentDomain(forName: name)
    }

    private static func bondStoreKeepsWhatItCannotRead(_ suite: TestSuite) {
        withDefaults("ryzenstatus.tests.mascot.bonds", suite) { defaults in
            let seed = json(damagedMap)
            defaults.set(seed, forKey: DefaultsKey.notchMascotBonds)
            let store = NotchMascotBondStore(defaults: defaults)
            suite.expect(store.bonds["minimal"]?.experience == 120, "the store keeps the entry it could read")
            suite.expect(defaults.data(forKey: DefaultsKey.notchMascotBondsBackup) == seed,
                         "what it could not read is copied aside as it was")
        }
    }

    private static func readingBondDoesNotWrite(_ suite: TestSuite) {
        withDefaults("ryzenstatus.tests.mascot.read", suite) { defaults in
            let store = NotchMascotBondStore(defaults: defaults)
            let before = defaults.data(forKey: DefaultsKey.notchMascotBonds)
            let first = store.bond(for: .dog)
            let second = store.bond(for: .dog)
            suite.expect(first.experience == 0 && second.experience == 0 && store.bonds["dog"] == nil,
                         "a style with no bond reads as new, and is not stored")
            suite.expect(defaults.data(forKey: DefaultsKey.notchMascotBonds) == before, "reading a bond writes nothing")
        }
    }

    private static func unchangedBondIsNotSaved(_ suite: TestSuite) {
        withDefaults("ryzenstatus.tests.mascot.record", suite) { defaults in
            let store = NotchMascotBondStore(defaults: defaults)
            let day = Date(timeIntervalSinceReferenceDate: 815_000_000)
            MainActor.assumeIsolated {
                store.record(.dayTogether, for: .minimal, now: day)
                let sentinel = Data([1])
                defaults.set(sentinel, forKey: DefaultsKey.notchMascotBonds)
                let gained = store.record(.dayTogether, for: .minimal, now: day)
                suite.expect(gained == 0, "the same day counted twice brings nothing")
                suite.expect(defaults.data(forKey: DefaultsKey.notchMascotBonds) == sentinel,
                             "a day already counted writes nothing")
            }
        }
    }

    private static func spentGoldIsSavedAtOnce(_ suite: TestSuite) {
        withDefaults("ryzenstatus.tests.mascot.rpg", suite) { defaults in
            MainActor.assumeIsolated {
                let state = NotchMascotRPGState(defaults: defaults)
                state.goldCoins = 100
                suite.expect(state.rerollShop(), "a reroll with enough gold goes through")
                suite.expect(defaults.integer(forKey: DefaultsKey.notchMascotGold) == 100 - NotchMascotShop.rerollPrice,
                             "the gold a reroll costs is saved at once")
            }
        }
    }

    // MARK: Wiring, read from the source

    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: "Sources/RyzenStatus/" + path, encoding: .utf8)) ?? ""
    }

    /// The body of the first declaration that starts with `signature`, from
    /// its opening brace to the matching closing one; empty when not found.
    private static func body(of signature: String, in text: String) -> String {
        guard let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return "" }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[open...index]) }
            default: break
            }
            index = text.index(after: index)
        }
        return ""
    }

    private static func backgroundLifeStopsWithTheIsland(_ suite: TestSuite) {
        let service = source("Services/Notch/NotchService.swift")
        let teardown = body(of: "private func tearDownPresentation()", in: service)
        suite.expect(teardown.contains("suspendMascotLife()"), "tearing the island down stops the companion's background life")
        let suspend = body(of: "private func suspendMascotLife()", in: service)
        suite.expect(suspend.contains("mascotIslandPlayTick?.cancel()")
                     && suspend.contains("NotchMascotAutomation.shared.sync(islandRunning: false)")
                     && suspend.contains("NotchMascotCheats.shared.stop()")
                     && suspend.contains("endMascotIslandPlay()")
                     && suspend.contains("NotchMascotRPG.flush()"),
                     "suspending stops the tick, automation, the cheat listener and a play, and saves the RPG state")
        suite.expect(body(of: "private func withdrawFromMissingScreen()", in: service).contains("tearDownPresentation()"),
                     "a missing screen goes through the same teardown")
        let sync = body(of: "func syncWithPreferences()", in: service)
        let beforeGuard = sync.components(separatedBy: "guard screenIndex(in: NSScreen.screens)").first ?? sync
        suite.expect(!beforeGuard.contains("NotchMascotCheats.shared.start()") && !beforeGuard.contains("scheduleMascotIslandPlayTick()"),
                     "the tick and the cheat listener start only after the screen guard")
        suite.expect(sync.contains("if NotchMascotSupport.isEnabled() { NotchMascotCheats.shared.start() }"),
                     "the cheat listener runs only with the companion on")
        let automation = source("Services/Notch/NotchMascotAutomation.swift")
        suite.expect(body(of: "private func readHardware()", in: automation).contains("!Task.isCancelled"),
                     "a cancelled hardware read leaves the newer one alone")
    }

    private static func desktopSoundsBelongToTheOuting(_ suite: TestSuite) {
        let desktop = source("Services/Notch/NotchMascotDesktop.swift")
        let helper = body(of: "private func sound(", in: desktop)
        let direct = desktop.components(separatedBy: "NotchMascotSound.play(").count - 1
        let inHelper = helper.components(separatedBy: "NotchMascotSound.play(").count - 1
        suite.expect(!helper.isEmpty && direct == inHelper, "every desktop sound goes through the outing's own helper")
        suite.expect(body(of: "private func later(", in: desktop).contains("lasts()"), "delayed work ends with the outing")
        let dismiss = body(of: "func dismiss()", in: desktop)
        suite.expect(dismiss.contains("encounterStage?.close()") && dismiss.contains("occasionStage?.close()"),
                     "dismissed, the companion puts its stages away at once")
        suite.expect(body(of: "private func finishHome(", in: desktop).contains("self.outing == outing"),
                     "a fade-out cut short by a dismissal does not report a homecoming")
    }

    private static func reduceMotionAndLowPower(_ suite: TestSuite) {
        let desktop = source("Services/Notch/NotchMascotDesktop.swift")
        suite.expect(body(of: "func hop(dx: CGFloat, dy: CGFloat)", in: desktop).contains("!holdsStill")
                     && body(of: "func stroll(to x: CGFloat", in: desktop).contains("!holdsStill"),
                     "with Reduce Motion it neither hops nor strolls on its own")
        suite.expect(body(of: "private func leap(to ledge:", in: desktop).contains("self.planNext(after: 2)"),
                     "a leap refused by Reduce Motion plans again rather than waiting forever")
        let activity = body(of: "private func startActivity()", in: desktop)
        suite.expect(activity.contains("if !lowPower {") && activity.contains("if !reduceMotion, maybeDanceSolo()"),
                     "Low Power Mode and Reduce Motion gate what it starts on its own")
        let service = source("Services/Notch/NotchService.swift")
        suite.expect(body(of: "private func tryMascotOccasion(", in: service).contains("isLowPowerModeEnabled"),
                     "occasions wait on the desktop in Low Power Mode")
    }

    private static func displayLinkGoesWithTheOuting(_ suite: TestSuite) {
        let desktop = source("Services/Notch/NotchMascotDesktop.swift")
        suite.expect(body(of: "func dismiss()", in: desktop).contains("invalidateTicking()")
                     && body(of: "private func finishHome(", in: desktop).contains("invalidateTicking()"),
                     "going in invalidates the display link")
    }

    private static func spriteSheetsAreShared(_ suite: TestSuite) {
        let layer = source("UI/Notch/NotchMascotSpriteLayer.swift")
        suite.expect(layer.contains("private static var sheets: [String: CGImage]"), "decoded sheets are kept per resource")
        suite.expect(body(of: "private static func sheet(", in: layer).contains("CGImageSourceCreateImageAtIndex")
                     && !body(of: "private init?(sheet:", in: layer).contains("CGImageSourceCreateImageAtIndex"),
                     "a sheet is decoded once, not per framing")
    }
}
