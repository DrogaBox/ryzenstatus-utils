// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

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
}
