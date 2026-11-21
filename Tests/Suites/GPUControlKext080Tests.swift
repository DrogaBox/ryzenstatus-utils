// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// GPUSensors.kext 0.8.0 on the app's side: `disarm`,
/// the card's own power floor (`PowerRange`), the read-only card and the new
/// refusal order, on the model and through the engine, with 0.7.2 next to it.
enum GPUControlKext080Tests {
    static func run(_ suite: TestSuite) {
        modelDisarm(suite)
        modelFloor(suite)
        modelOrderAndReadOnly(suite)
        engineClose(suite)
        engineReadOnly(suite)
        powerRange(suite)
    }

    private typealias Harness = GPUControlChannelTests.Harness

    private static func opened(_ setup: (FakeGPUControlKext) -> Void = { _ in },
                               armed: Bool = true) -> (FakeGPUControlKext, FakeGPUControlKext.Connection) {
        let fake = FakeGPUControlKext()
        setup(fake)
        if armed { fake.arm() }
        let connection = fake.connection()
        _ = connection.open()
        return (fake, connection)
    }

    // MARK: The model

    private static func modelDisarm(_ suite: TestSuite) {
        do {
            let (fake, c) = opened()
            suite.expect(c.disarm()?.reply == .ok && c.status()?.flags.contains(.armed) == false,
                         "disarm with nothing applied: closed, no password")
            suite.expect(c.disarm()?.reply == .ok, "disarm again: ok (already closed)")
            suite.expect(c.setPower(watts: 230)?.reply == .notArmed, "after disarm a change is refused as before arm")
            suite.expect(fake.arm() == .ok && c.status()?.flags.contains(.armed) == true, "arm opens it again, no restart")
        }
        do {
            let (fake, c) = opened()
            _ = c.setPower(watts: 230)
            suite.expect(c.disarm()?.reply == .stillApplied, "disarm while this program holds: still applied")
            _ = c.release()
            suite.expect(c.disarm()?.reply == .stillApplied, "disarm while the way back runs: still applied")
            fake.advance(by: 1_000)
            suite.expect(c.disarm()?.reply == .ok, "disarm after the way back: closed")
        }
        do {
            let (fake, c) = opened()
            let other = fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            suite.expect(c.disarm()?.reply == .stillApplied, "another program holds: still applied, for anyone")
        }
        do {
            let (_, c) = opened { $0.generation = .v07 }
            suite.expect(c.disarm() == nil && c.status()?.reply == .ok,
                         "0.7.2: disarm fails as a call (no selector 6), the connection still works")
        }
    }

    private static func modelFloor(_ suite: TestSuite) {
        do {
            // The test RX 6800 XT: 240 W, PowerPercent -6: 225 W.
            let (fake, c) = opened { $0.powerPercentMin = -6 }
            suite.expect(fake.floorW == 225, "240 W less 6 %: 225 W, integer division as Linux")
            suite.expect(c.setPower(watts: 220)?.reply == .belowFloor, "220 W under the card's floor: below floor")
            fake.advance(by: 3_000)
            suite.expect(c.setPower(watts: 230)?.reply == .ok, "230 W: taken")
            let range = GPUControlPowerRange.parse(fake.properties()["PowerRange"])
            suite.expect(range?.floorW == 225 && range?.maxW == 240 && range?.stepW == 10
                            && range?.percentMin == -6 && range?.percentMax == 9 && range?.source == .kext,
                         "PowerRange as the kext publishes it")
        }
        do {
            let (fake, c) = opened { $0.od8Ready = false }
            suite.expect(fake.floorW == 0 && c.setPower(watts: 230)?.reply == .noFloor,
                         "OD8 not read: the floor is not known, every lower limit answers no floor")
            let props = fake.properties()
            suite.expect(GPUControlPowerRange.parse(props["PowerRange"])?.isKnown == false
                            && (props["PowerRangeState"] as? String) == "not known yet: waiting for a clean OD8 read",
                         "PowerRange Known 0 and its state")
        }
        do {
            let (fake, c) = opened { $0.powerPercentFeature = 0 }
            suite.expect(fake.floorW == 240 && c.setPower(watts: 230)?.reply == .belowFloor,
                         "no power percent on the card: the floor is the start-up value")
        }
        do {
            let (fake, c) = opened { $0.generation = .v07; $0.powerPercentMin = -6 }
            suite.expect(fake.floorW == FakeGPUControlKext.legacyFloorW && c.setPower(watts: 210)?.reply == .ok
                            && fake.properties()["PowerRange"] == nil,
                         "0.7.2: its own fixed floor, no PowerRange")
        }
    }

    private static func modelOrderAndReadOnly(_ suite: TestSuite) {
        do {
            let (_, c) = opened(armed: false)
            suite.expect(c.setPower(watts: 240)?.reply == .notArmed, "0.8.0: set(start-up) before arm: not armed")
            suite.expect(c.setPower(watts: 5)?.reply == .notArmed, "0.8.0: an absurd value still gets the real reason")
            let absurd = c.call(.setOD8, input: [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9_000], outputCount: 2)
            suite.expect(absurd?.first == GPUControlReply.notArmed.rawValue, "0.8.0: setOD8 checks arm before its values")
            suite.expect(c.release()?.reply == .ok, "release is never gated")
        }
        do {
            let (_, c) = opened({ $0.generation = .v07 }, armed: false)
            suite.expect(c.setPower(watts: 240)?.reply == .ok, "0.7.2: set(start-up) before arm is the way back, ok")
        }
        do {
            let (fake, c) = opened({ $0.makeReadOnlyCard() }, armed: false)
            suite.expect(fake.arm() == .off, "read-only card: arm answers off, even for an administrator")
            let status = c.status()
            suite.expect(status?.flags.contains(.off) == true && status?.flags.contains(.armed) == false
                            && status?.writeOff == .readOnlyCard && status?.flags.contains(.od8Ready) == true,
                         "read-only card: off from boot, never armed, the reads still run")
            suite.expect(c.setPower(watts: 230)?.reply == .off && c.disarm()?.reply == .off,
                         "read-only card: set and disarm answer off")
            let writing = GPUControlStatus.Writing.parse(fake.properties())
            suite.expect(writing?.gate == .off && writing?.state?.writeOff == 15,
                         "read-only card: Write reads 'read only', WriteState.WriteOff 15")
        }
    }

    // MARK: The engine

    private static func engineClose(_ suite: TestSuite) {
        do {
            let h = Harness()
            h.engine.refresh()
            h.run(ms: 100)
            h.engine.close()
            h.run(ms: 100)
            suite.expect(h.engine.snapshot.closing == .closed && h.engine.snapshot.status?.flags.contains(.armed) == false,
                         "close with nothing held: closed at once")
            suite.expect(h.replies(.disarm) == 1, "one disarm")
        }
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 1_000)
            suite.expect(h.held == .power(watts: 220), "held before the close")
            h.engine.close()
            h.run(ms: 5_000)
            suite.expect(h.held == nil && h.engine.snapshot.closing == .closed, "close while held: back first, then closed")
            let releases = h.calls(.release).map(\.atMs), disarms = h.calls(.disarm).map(\.atMs)
            suite.expect(releases.count == 1 && disarms.count == 1 && releases[0] < disarms[0],
                         "the release comes before the one disarm")
            suite.expect(h.fake.writes.last?.kind == .wayBack, "the card went back")
        }
        do {
            let h = Harness()
            let other = h.fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            h.engine.close()
            h.run(ms: 3_000)
            suite.expect(h.engine.snapshot.closing == .refused(GPUControlAnswer(replyCode: GPUControlReply.stillApplied.rawValue)),
                         "another program holds: refused with still applied, no waiting for it")
            suite.expect(h.replies(.disarm) == 1, "asked once, no loop")
            h.run(ms: 60_000)
            suite.expect(h.replies(.disarm) == 1, "and not again later")
        }
        do {
            let h = Harness { $0.generation = .v07 }
            h.engine.close()
            h.run(ms: 1_000)
            suite.expect(h.engine.snapshot.closing == .notSupported && h.engine.snapshot.stopped == nil,
                         "0.7.2: close is not supported, the control goes on")
            h.engine.choose(.power(watts: 220))
            h.run(ms: 1_000)
            suite.expect(h.held == .power(watts: 220) && h.engine.snapshot.closing == nil,
                         "a choice after it works and clears the close")
        }
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.engine.close()
            h.run(ms: 2_000)
            suite.expect(h.replies(.set) == 0 && h.engine.snapshot.closing == .closed,
                         "close drops a request not sent yet")
        }
    }

    private static func engineReadOnly(_ suite: TestSuite) {
        let h = Harness(armed: false) { $0.makeReadOnlyCard() }
        h.engine.choose(.power(watts: 220))
        h.run(ms: 70_000)
        suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.readOnlyCard.rawValue),
                     "read-only card: the control stops on the first status")
        suite.expect(h.replies(.set) == 0 && h.replies(.status) == 1, "no set, no retry")
        suite.expect(h.notices.isEmpty, "nothing was held: no notice")
    }

    // MARK: PowerRange

    private static func powerRange(_ suite: TestSuite) {
        // ioreg prints -6 as 18446744073709551610; CFNumber gives the 64-bit pattern.
        let raw: [String: Any] = ["Known": NSNumber(value: 1), "FloorW": NSNumber(value: 225), "MaxW": NSNumber(value: 240),
                                  "StepW": NSNumber(value: 10), "PercentMin": NSNumber(value: UInt32(4_294_967_290)),
                                  "PercentMax": NSNumber(value: 9)]
        let range = GPUControlPowerRange.parse(raw)
        suite.expect(range?.floorW == 225 && range?.percentMin == -6, "PercentMin read as signed 32-bit")
        let wide = GPUControlPowerRange.parse(["Known": NSNumber(value: 0), "PercentMin": NSNumber(value: UInt64(18_446_744_073_709_551_610))])
        suite.expect(wide?.percentMin == -6, "PercentMin also as the 64-bit pattern ioreg prints")
        let unknown = GPUControlPowerRange.parse(["Known": NSNumber(value: 0), "StepW": NSNumber(value: 10)])
        suite.expect(unknown?.isKnown == false && unknown?.floorW == nil, "Known 0: no floor")
        suite.expect(GPUControlPowerRange.parse(["Known": NSNumber(value: 1), "FloorW": NSNumber(value: 250),
                                                 "MaxW": NSNumber(value: 240)])?.isKnown == false,
                     "a floor above the maximum is not taken")
        // 0.7.2 publishes no range: the app works it out from the OD8 table.
        guard let table = GPUControlChannelTests.real072(), let writing = GPUControlStatus.parse(table)?.writing else {
            suite.expect(false, "the 0.7.2 fixture loads")
            return
        }
        suite.expect(writing.powerRange == nil && writing.powerRangeState == nil, "0.7.2: no PowerRange keys")
        let derived = GPUControlPowerRange.fromOD8(bootW: 240, od8: writing.od8, od8Read: writing.od8Read == .read)
        suite.expect(derived?.floorW == 225 && derived?.maxW == 240 && derived?.source == .od8Table,
                     "0.7.2 card: 240 W and PowerPercent -6 give the kext 0.8.0's 225 W")
        suite.expect(GPUControlPowerRange.fromOD8(bootW: 240, od8: writing.od8, od8Read: false) == nil,
                     "no clean OD8 read: no floor")
        var odd = writing.od8
        odd?.settings["PowerPercent"]?.min = -60
        suite.expect(GPUControlPowerRange.fromOD8(bootW: 240, od8: odd, od8Read: true)?.isKnown == false,
                     "more than 50 % down: not taken as a floor")
        var none = writing.od8
        none?.settings["PowerPercent"]?.feature = 0
        suite.expect(GPUControlPowerRange.fromOD8(bootW: 240, od8: none, od8Read: true)?.floorW == 240,
                     "no power percent feature: the floor is the start-up value")
    }
}
