// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import QuartzCore

struct NotchMascotCheatsTests {
    static func run(_ suite: TestSuite) {
        konamiSequence(suite)
        doomIdkfaSequence(suite)
        doomIddqdSequence(suite)
        doomIdclipSequence(suite)
        starFoxRollSequence(suite)
        simsMotherlodeSequence(suite)
        noisePrefixMatching(suite)
        modifierRejection(suite)
        timeoutReset(suite)
        badgesAndSoundEffects(suite)
        newCheatSequences(suite)
        newBadgesAndSounds(suite)
        fanfares(suite)
        showLengths(suite)
        bigHeadLook(suite)
    }

    private static func konamiSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let konamiKeycodes: [UInt16] = [126, 126, 125, 125, 123, 124, 123, 124, 11, 0]
        var result: NotchMascotCheat?
        for code in konamiKeycodes {
            result = engine.receive(keyCode: code, timestamp: 100.0)
        }
        suite.expect(result == .konami, "Konami keycode sequence matches .konami")
        suite.expect(engine.bufferCount == 0, "Buffer clears upon cheat completion")
    }

    private static func doomIdkfaSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let result = engine.receive(text: "idkfa", timestamp: 100.0)
        suite.expect(result == .idkfa, "idkfa characters match .idkfa")
    }

    private static func doomIddqdSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let result = engine.receive(text: "iddqd", timestamp: 100.0)
        suite.expect(result == .iddqd, "iddqd characters match .iddqd")
    }

    private static func doomIdclipSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let result = engine.receive(text: "idclip", timestamp: 100.0)
        suite.expect(result == .idclip, "idclip characters match .idclip")
    }

    private static func starFoxRollSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let result = engine.receive(text: "roll", timestamp: 100.0)
        suite.expect(result == .roll, "roll characters match .roll")
    }

    private static func simsMotherlodeSequence(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        let result = engine.receive(text: "motherlode", timestamp: 100.0)
        suite.expect(result == .motherlode, "motherlode characters match .motherlode")
    }

    private static func noisePrefixMatching(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        _ = engine.receive(text: "randomstuffbefore", timestamp: 100.0)
        let result = engine.receive(text: "idkfa", timestamp: 100.0)
        suite.expect(result == .idkfa, "Cheat matches suffix even with prefix noise")
    }

    private static func modifierRejection(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        // Reject key with Command modifier
        let cmdR = engine.receive(character: "r", modifiers: [.command], timestamp: 100.0)
        suite.expect(cmdR == nil, "Command modifier rejects keypress")
        _ = engine.receive(text: "oll", timestamp: 100.1)
        suite.expect(engine.bufferCount == 3, "Prefix was not registered due to Command modifier")

        // Reject key with Control modifier
        let ctrlI = engine.receive(character: "i", modifiers: [.control], timestamp: 100.2)
        suite.expect(ctrlI == nil, "Control modifier rejects keypress")

        // Reject key with Option modifier
        let optI = engine.receive(character: "i", modifiers: [.option], timestamp: 100.3)
        suite.expect(optI == nil, "Option modifier rejects keypress")

        // A cheat sequence with a modifier on the final key does not trigger
        engine.reset()
        _ = engine.receive(text: "idkf", timestamp: 100.4)
        let finalCmd = engine.receive(character: "a", modifiers: [.command], timestamp: 100.5)
        suite.expect(finalCmd == nil, "Cheat does not trigger when final key has Command modifier")
        suite.expect(engine.bufferCount == 4, "Buffer retains uncompleted keys without final modified key")
    }

    private static func timeoutReset(_ suite: TestSuite) {
        let engine = NotchMascotCheatEngine()
        _ = engine.receive(character: "r", timestamp: 10.0)
        _ = engine.receive(character: "o", timestamp: 10.5)

        // Typing silence of 2.6 seconds (> 2.5s)
        _ = engine.receive(character: "l", timestamp: 13.1)
        let result = engine.receive(character: "l", timestamp: 13.2)
        suite.expect(result == nil, "Typing silence > 2.5s resets buffer, roll does not trigger")

        // Retyping within 2.5s triggers properly
        let completed = engine.receive(text: "roll", timestamp: 14.0)
        suite.expect(completed == .roll, "Typing roll anew completes within timeout")
    }

    private static func badgesAndSoundEffects(_ suite: TestSuite) {
        suite.expect(NotchMascotCheat.konami.badge == "👾 30 LIVES", "Konami badge matches")
        suite.expect(NotchMascotCheat.konami.soundEffect == .magic, "Konami sound matches .magic")

        suite.expect(NotchMascotCheat.idkfa.badge == "🔫 FULL ARSENAL", "idkfa badge matches")
        suite.expect(NotchMascotCheat.idkfa.soundEffect == .clash, "idkfa sound matches .clash")

        suite.expect(NotchMascotCheat.iddqd.badge == "👁️ GOD MODE", "iddqd badge matches")
        suite.expect(NotchMascotCheat.iddqd.soundEffect == .magic, "iddqd sound matches .magic")

        suite.expect(NotchMascotCheat.idclip.badge == "👻 NO CLIP", "idclip badge matches")
        suite.expect(NotchMascotCheat.idclip.soundEffect == .poof, "idclip sound matches .poof")

        suite.expect(NotchMascotCheat.roll.badge == "🔄 BARREL ROLL", "roll badge matches")
        suite.expect(NotchMascotCheat.roll.soundEffect == .whoosh, "roll sound matches .whoosh")

        suite.expect(NotchMascotCheat.motherlode.badge == "💸 +10,000 GOLD", "motherlode badge matches")
        suite.expect(NotchMascotCheat.motherlode.soundEffect == .coin, "motherlode sound matches .coin")

        let initialGold = UserDefaults.standard.integer(forKey: DefaultsKey.notchMascotGold)
        UserDefaults.standard.set(initialGold + 10_000, forKey: DefaultsKey.notchMascotGold)
        suite.expect(UserDefaults.standard.integer(forKey: DefaultsKey.notchMascotGold) == initialGold + 10_000,
                     "motherlode awards 10,000 gold")
        UserDefaults.standard.set(initialGold, forKey: DefaultsKey.notchMascotGold)
    }

    private static func newCheatSequences(_ suite: TestSuite) {
        let words: [(String, NotchMascotCheat)] = [("partyhard", .party), ("bighead", .bighead),
                                                   ("thereisnospoon", .thereisnospoon), ("moonwalk", .moonwalk)]
        for (word, cheat) in words {
            let engine = NotchMascotCheatEngine()
            suite.expect(engine.receive(text: word, timestamp: 100.0) == cheat, "\(word) characters match .\(cheat)")
            suite.expect(engine.bufferCount == 0, "\(word) clears the buffer")
        }
        // By key codes alone, as a layout that types other letters sends them.
        let engine = NotchMascotCheatEngine()
        var result: NotchMascotCheat?
        for code: UInt16 in [46, 31, 31, 45, 13, 0, 37, 40] {
            result = engine.receive(keyCode: code, timestamp: 100.0)
        }
        suite.expect(result == .moonwalk, "moonwalk key codes match .moonwalk")
        let partial = NotchMascotCheatEngine()
        suite.expect(partial.receive(text: "thereisnospo", timestamp: 100.0) == nil, "half a cheat is no cheat")
        suite.expect(NotchMascotCheatEngine().receive(text: "lets partyhard", timestamp: 100.0) == .party,
                     "a cheat at the end of other typing still counts")
    }
    private static func newBadgesAndSounds(_ suite: TestSuite) {
        suite.expect(NotchMascotCheat.party.badge == "🎉 PARTY TIME", "party badge matches")
        suite.expect(NotchMascotCheat.party.soundEffect == .toot, "party sound matches .toot")
        suite.expect(NotchMascotCheat.bighead.badge == "🎈 BIG HEAD MODE", "bighead badge matches")
        suite.expect(NotchMascotCheat.bighead.soundEffect == .boing, "bighead sound matches .boing")
        suite.expect(NotchMascotCheat.thereisnospoon.badge == "🥄 THERE IS NO SPOON", "thereisnospoon badge matches")
        suite.expect(NotchMascotCheat.thereisnospoon.soundEffect == .bleep, "thereisnospoon sound matches .bleep")
        suite.expect(NotchMascotCheat.moonwalk.badge == "🌙 MOONWALK", "moonwalk badge matches")
        suite.expect(NotchMascotCheat.moonwalk.soundEffect == .warble, "moonwalk sound matches .warble")
        let badges = NotchMascotCheat.allCases.map(\.badge)
        suite.expect(Set(badges).count == badges.count, "every cheat has a badge of its own")
    }
    private static func fanfares(_ suite: TestSuite) {
        for cheat in NotchMascotCheat.allCases {
            let fanfare = cheat.fanfare
            suite.expect(fanfare.count >= 4, "\(cheat) plays several sounds")
            suite.expect(fanfare.first?.effect == cheat.soundEffect && fanfare.first?.at == 0,
                         "\(cheat) opens with its own sound")
            suite.expect(zip(fanfare, fanfare.dropFirst()).allSatisfy { $0.at < $1.at }, "\(cheat) plays them in turn")
            suite.expect((fanfare.last?.at ?? 0) < NotchMascotCheatBanner.length, "\(cheat) is over before its banner")
        }
        suite.expect(AppLanguage.allCases.allSatisfy { !FeatureStrings.notchMascotCheats($0).activated.isEmpty },
                     "the banner's line is there in every language")
    }
    private static func showLengths(_ suite: TestSuite) {
        suite.expect(NotchMascotCheatShows.godLength == 30, "god mode lasts 30 s")
        suite.expect(NotchMascotCheatShows.bigHeadLength == 45, "big-head mode lasts 45 s")
        suite.expect(NotchMascotCheatShows.slowLength == 15 && NotchMascotCheatShows.slowPace == 0.3,
                     "slow motion: 15 s at 0.3 times the pace")
        suite.expect(NotchMascotCheatShows.moonLength == 60 && NotchMascotCheatShows.moonGravity < 0.5,
                     "low gravity for 60 s")
        suite.expect(NotchMascotCheatShows.trainLength == 30, "thirty tiny copies run in the train")
        suite.expect(NotchMascotCheatShows.coinLife >= 6 && NotchMascotCheatShows.coinLife <= 10, "the gold fades after a while")
        let desktop = NotchMascotDesktop()
        suite.expect(desktop.cheatPace == 1 && desktop.cheatGravity == 1 && !desktop.cheatInvulnerable
                         && !desktop.cheatPassesThrough && desktop.cheatStride(1) == 1,
                     "with no cheat it moves as ever")
        desktop.cheat.slowUntil = CACurrentMediaTime() + 10
        desktop.cheat.moonUntil = CACurrentMediaTime() + 10
        desktop.cheat.invulnerableUntil = CACurrentMediaTime() + 10
        suite.expect(abs(desktop.cheatPace - 0.3) < 0.001 && desktop.cheatGravity < 1 && desktop.cheatInvulnerable
                         && desktop.cheatStride(1) == -1,
                     "slow, floaty, untouchable and walking backwards while they last")
        var body = NotchMascotRoam.Body(position: CGPoint(x: 100, y: 50), velocity: CGVector(dx: 0, dy: -500))
        let area = CGRect(x: 0, y: 50, width: 800, height: 600)
        desktop.cheat.ghostUntil = CACurrentMediaTime() + 10
        desktop.cheat.fallsThrough = true
        suite.expect(desktop.cheatArea(area, body: &body).minY < area.minY, "falling through, the floor is gone")
        desktop.cheat.ghostUntil = -.infinity
        suite.expect(desktop.cheatArea(area, body: &body) == area && !desktop.cheat.fallsThrough,
                     "no longer see-through, the floor is back")
    }
    private static func bigHeadLook(_ suite: TestSuite) {
        let size: CGFloat = 50
        let feet: CGFloat = 30
        let look = NotchMascotCheatShows.bigHead
        let transform = NotchMascotCheatShows.bigHeadTransform(squeeze: look.squeeze, swell: look.swell, size: size, feet: feet)
        // A point (0, y) as the layer draws it, counted down from its middle.
        func drawn(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let w = x * transform.m14 + y * transform.m24 + transform.m44
            return CGPoint(x: (x * transform.m11 + y * transform.m21 + transform.m41) / w,
                           y: (x * transform.m12 + y * transform.m22 + transform.m42) / w)
        }
        let foot = drawn(0, feet)
        suite.expect(abs(foot.y - feet) < 0.001 && abs(foot.x) < 0.001, "its feet stay where they are")
        let top = drawn(10, feet - size)
        let low = drawn(10, feet - size * 0.1)
        suite.expect(feet - top.y > size * 1.3, "the top of its head is drawn far higher")
        suite.expect(top.x > 10 * 1.4 && low.x < 10, "its head is drawn bigger and its feet smaller")
        suite.expect(feet - top.y < size * 1.63, "its head still fits in its window")
        let still = NotchMascotCheatShows.bigHeadTransform(squeeze: 1, swell: 0, size: size, feet: feet)
        suite.expect(CATransform3DIsIdentity(still), "with nothing swollen it is drawn as ever")
    }
}
