// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The GPU control base (plan phase 1): the reader of the write keys, the
/// `setOD8` scalars, the kext model and the controller's rules (plan
/// section 6) against it, and the text groups (section 13). Nothing here
/// opens the kext: every channel is `FakeGPUControlKext`.
enum GPUControlChannelTests {
    static func run(_ suite: TestSuite) {
        reader(suite)
        olderKexts(suite)
        gateTexts(suite)
        od8Scalars(suite)
        fakeScenarios(suite)
        fakeEveryReply(suite)
        controllerRows(suite)
        controllerWake(suite)
        controllerRetries(suite)
        controllerStops(suite)
        controllerQueue(suite)
        reviewFixes(suite)
        noChannel(suite)
        textGroups(suite)
        wireNumbers(suite)
    }

    // MARK: Fixtures

    /// The curve run on the card with 0.7.1 (plan 7.3).
    static let testedCurve = [(30, 20), (40, 36), (44, 52), (46, 68), (48, 100)]
        .map { GPUControlFanPoint(temperatureC: $0.0, speedPercent: $0.1) }

    /// The real 0.7.2 table (Tests/Fixtures/GPUSensors/README.md).
    static func real072() -> [String: Any]? {
        let path = FileManager.default.currentDirectoryPath + "/Tests/Fixtures/GPUSensors/ioreg-0.7.2-2026-11-20.plist"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    // MARK: Reader

    private static func reader(_ suite: TestSuite) {
        guard let table = real072() else {
            suite.expect(false, "the 0.7.2 fixture loads from Tests/Fixtures/GPUSensors (run from the repo root)")
            return
        }
        let status = GPUControlStatus.parse(table)
        let w = status?.writing
        suite.expect(w != nil, "0.7.2 has the write path")
        suite.expect(w?.text == "closed: sudo gpucontrol arm opens it until restart" && w?.gate == .closed,
                     "Write: closed until an administrator arms it")
        suite.expect(w?.od8Gate == .closed, "OD8Write: closed too")
        let state = w?.state
        suite.expect(state?.writeOff == 0 && state?.writeOffText == "", "WriteState: not off, empty reason kept")
        suite.expect(state?.armed == false && state?.owned == false, "WriteState: not armed, nobody holds")
        suite.expect(state?.heldW == 240 && state?.changes == 0 && state?.reverts == 0 && state?.lastReply == 0,
                     "WriteState: the start-up 240 W, nothing changed")
        let od8State = w?.od8State
        suite.expect(od8State?.held == [] && od8State?.lastCheck == 0 && od8State?.lastCheckText == "ok",
                     "OD8WriteState: nothing held, last check ok")
        suite.expect(od8State?.fanCurveHeld == nil && od8State?.gfxMaxHeld == nil, "no held curve or clock at stock")
        // The uint64_t counters keep their value past UInt32.max.
        let big = NSNumber(value: UInt64(UInt32.max) + 1)
        let bigState = GPUControlStatus.Writing.State.parse(["Changes": big, "Reverts": big])
        let bigOD8 = GPUControlStatus.Writing.OD8State.parse(["Changes": big, "Reverts": big, "SentPower": big])
        suite.expect(bigState?.changes == big.intValue && bigState?.reverts == big.intValue
                         && bigOD8?.changes == big.intValue && bigOD8?.reverts == big.intValue
                         && bigOD8?.sentPower == big.intValue,
                     "WriteState and OD8WriteState: uint64_t counters past UInt32.max")
        suite.expect(w?.od8Read == .read, "OD8State: read cleanly")
        let od8 = w?.od8
        suite.expect(od8?.caps == 212_749 && od8?.reads == 1 && od8?.tries == 1, "OD8: caps and read counts")
        suite.expect(od8?.notAllowed == UInt32(bitPattern: -212_750), "NotAllowed arrives signed and keeps its 32 bits")
        suite.expect(od8?.settings["PowerPercent"]?.min == -6 && od8?.settings["PowerPercent"]?.max == 9,
                     "a negative 32-bit minimum reads as -6")
        let published = ((table["OD8"] as? [String: Any])?["Settings"] as? [String: Any])?.count
        suite.expect(published == 25 && od8?.settings.count == 25, "every OD8 setting the card offers is read (25)")
        let gfx = od8?.settings["GfxMaxMHz"]
        suite.expect(gfx?.feature == 1 && gfx?.stock == 2_359 && gfx?.min == 500 && gfx?.max == 2_800,
                     "GFX max: stock 2359 MHz, driver range 500-2800")
        suite.expect(od8?.stockGfxMaxMHz == 2_359, "the clock a request may not pass is the stock 2359 MHz")
        if var odd = od8, let entry = odd.settings["GfxMaxMHz"] {
            odd.settings["GfxMaxMHz"] = GPUControlStatus.Writing.OD8Setting(
                feature: 0x2, min: entry.min, max: entry.max, stock: entry.stock,
                defaultNow: entry.defaultNow, current: entry.current)
            suite.expect(odd.stockGfxMaxMHz == nil, "a GFX max feature other than 0x1 offers no clock (the kext says NoFeature)")
        }
        suite.expect(od8?.settings["FanTargetC"]?.stock == 70 && od8?.settings["FanTargetC"]?.feature == 0,
                     "fan target 70 C, not offered as a feature")
        let stockCurve = [(30, 20), (50, 36), (56, 52), (63, 68), (70, 100)]
            .map { GPUControlFanPoint(temperatureC: $0.0, speedPercent: $0.1) }
        suite.expect(od8?.fanCurveStock == stockCurve && od8?.fanCurve == stockCurve, "the stock fan curve, five points")
        suite.expect(od8?.stockOdd == false && od8?.defaultsMoved == false && od8?.currentMoved == false,
                     "nothing odd or moved since boot")

        // LastReadAgeS moves every second and must not change the value.
        var older = table
        if var od8Dict = older["OD8"] as? [String: Any] {
            od8Dict["LastReadAgeS"] = NSNumber(value: 99_999)
            older["OD8"] = od8Dict
        }
        suite.expect(GPUControlStatus.parse(older) == status, "the read age alone does not change the status")

        // While a curve and a clock are held (0.7.2's packing, C x 1000 + %).
        var held = table
        held["OD8Write"] = "armed: a program holds a fan or clock change"
        held["OD8WriteState"] = [
            "Held": NSNumber(value: 5), "Changes": NSNumber(value: 1), "Reverts": NSNumber(value: 0),
            "LastCheck": NSNumber(value: 0), "LastCheckText": "ok", "SentPower": NSNumber(value: 0),
            "FanCurveHeld": [30_020, 40_036, 44_052, 46_068, 48_100].map { NSNumber(value: $0) },
            "GfxMaxHeld": NSNumber(value: 2_300),
        ] as [String: Any]
        let heldState = GPUControlStatus.parse(held)?.writing
        suite.expect(heldState?.od8Gate == .held, "OD8Write: a program holds a fan or clock change")
        suite.expect(heldState?.od8State?.held == [.curve, .gfxMax], "Held 5 = curve + GFX max")
        suite.expect(heldState?.od8State?.fanCurveHeld == testedCurve, "FanCurveHeld unpacks to the five points")
        suite.expect(heldState?.od8State?.gfxMaxHeld == 2_300, "GfxMaxHeld in MHz")

        // A broken curve is no curve, never four points.
        suite.expect(GPUControlStatus.fanCurvePairs([[30, 20], [50, 36]]) == nil, "two points are not a curve")
        suite.expect(GPUControlStatus.fanCurvePacked([30_020, "x", 1, 2, 3]) == nil, "a curve with a non-number is none")
        suite.expect(GPUControlStatus.signed32(NSNumber(value: 4_294_967_290 as UInt64)) == -6,
                     "the unsigned 32-bit form of -6 also reads as -6")
        suite.expect(GPUControlStatus.signed32(NSNumber(value: 1.5)) == nil, "a fraction is no OD8 number")
        suite.expect(GPUControlStatus.signed32(NSNumber(value: true)) == nil, "a boolean is no OD8 number")
    }

    /// Kexts before the write path, and each step of it. Built from the real
    /// 0.7.2 table without the keys those versions did not publish
    /// (kern_service.cpp's history: Write/WriteState 0.5.0, OD8State/OD8
    /// 0.6.0, OD8Write/OD8WriteState 0.7.0).
    private static func olderKexts(_ suite: TestSuite) {
        guard let table = real072() else { return }
        func without(_ keys: [String]) -> [String: Any] {
            var t = table
            keys.forEach { t[$0] = nil }
            return t
        }
        let v040 = without(["Write", "WriteState", "OD8State", "OD8", "OD8Write", "OD8WriteState"])
        suite.expect(GPUControlStatus.parse(v040) != nil && GPUControlStatus.parse(v040)?.writing == nil,
                     "0.4.0: the control readout, no write path")
        let v050 = without(["OD8State", "OD8", "OD8Write", "OD8WriteState"])
        let w050 = GPUControlStatus.parse(v050)?.writing
        suite.expect(w050?.gate == .closed && w050?.state?.heldW == 240, "0.5.0: Write and WriteState")
        suite.expect(w050?.od8Text == nil && w050?.od8Gate == nil && w050?.od8Read == nil && w050?.od8 == nil,
                     "0.5.0: no OD8 at all")
        let v060 = without(["OD8Write", "OD8WriteState"])
        let w060 = GPUControlStatus.parse(v060)?.writing
        suite.expect(w060?.od8Read == .read && w060?.od8?.caps == 212_749, "0.6.0: the OD8 readout")
        suite.expect(w060?.od8Gate == nil && w060?.od8State == nil, "0.6.0: no OD8 writes")
        var blank = table
        blank["Write"] = "  "
        suite.expect(GPUControlStatus.parse(blank)?.writing == nil, "a blank Write is no write path")
        var odd = table
        odd["OD8State"] = "read, but an entry is not as expected"
        suite.expect(GPUControlStatus.parse(odd)?.writing?.od8Read == .notClean("read, but an entry is not as expected"),
                     "only a bare \"read\" is a clean OD8 read")
        // A version 1 kext answers status with 9 scalars, and only "bad version".
        suite.expect(GPUControlChannelStatus(scalars: [1, 1, 0, 240, 240, 0, 0, 0, 0])?.version == 1,
                     "nine scalars with bad version still give the kext's version")
        suite.expect(GPUControlChannelStatus(scalars: [0, 2, 0, 240, 240, 0, 0, 0, 0]) == nil,
                     "nine scalars with ok are not a whole status")
        let all: [UInt64] = [0, 2, 497, 240, 230, 0, 1, 0, 0, 0, 0, 0, 0]
        suite.expect(GPUControlChannelStatus(scalars: all)?.scalars == all, "a whole status reads back as sent")
    }

    /// Every text of writeText() and od8WriteText() (kern_control.cpp).
    private static func gateTexts(_ suite: TestSuite) {
        typealias Gate = GPUControlStatus.Writing.Gate
        let cases: [(String, Gate)] = [
            ("off", .off),
            ("off until restart: see WriteState", .off),
            ("waiting for the power management and its start-up limit", .waiting),
            ("waiting for the driver's library", .waiting),
            ("waiting for a clean OD8 read (OD8State)", .waiting),
            ("closed: sudo gpucontrol arm opens it until restart", .closed),
            ("armed: the Mac is between sleep and wake", .sleeping),
            ("armed: going back to the start-up limit", .reverting),
            ("armed: going back to stock", .reverting),
            ("armed: the last OD8 call was not taken; going back to stock", .unconfirmed),
            ("armed: a program holds a lower limit", .held),
            ("armed: a program holds a fan or clock change", .held),
            ("armed: nothing held", .idle),
            ("armed: OD8 at stock", .idle),
            ("armed: something new", .other("armed: something new")),
            ("offline", .other("offline")),
        ]
        for (text, gate) in cases {
            suite.expect(Gate.parse(text) == gate, "\"\(text)\" reads as \(gate)")
        }
        // The model publishes the same texts the reader knows.
        let fake = FakeGPUControlKext()
        func gates() -> (Gate?, Gate?) {
            let w = GPUControlStatus.Writing.parse(fake.properties())
            return (w?.gate, w?.od8Gate)
        }
        suite.expect(gates() == (.closed, .closed), "the model starts closed")
        fake.arm()
        suite.expect(gates() == (.idle, .idle), "armed, nothing held")
        let c = fake.connection()
        _ = c.open()
        _ = c.setPower(watts: 220)
        suite.expect(gates() == (.held, .idle), "a power limit held")
        _ = c.release()
        suite.expect(gates() == (.reverting, .idle), "going back")
        fake.advance(by: 3_000)
        _ = c.setOD8(GPUControlOD8Want(gfxMaxMHz: 2_300))
        // writeText() says "a lower limit" for any held change, OD8 too.
        suite.expect(gates() == (.held, .held), "an OD8 change held")
        let props = GPUControlStatus.Writing.parse(fake.properties())
        suite.expect(props?.od8State?.gfxMaxHeld == 2_300 && props?.state?.heldW == 240,
                     "the model's OD8WriteState and WriteState read back")
        fake.turnOff(.teardown)
        suite.expect(gates() == (.off, .off), "off until restart")
        suite.expect(GPUControlStatus.Writing.parse(fake.properties())?.state?.writeOffText == "the GPU went away or the Mac is stopping",
                     "the write-off reason in the kext's words")
    }

    // MARK: setOD8 scalars

    private static func od8Scalars(_ suite: TestSuite) {
        suite.expect(GPUControlOD8Want.stock.scalars() == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                     "stock: the version, then twelve zeros")
        // Every combination the page can make: curve or not, zero RPM or not,
        // a lower clock or not.
        for curve in [nil, testedCurve] {
            for zero in [false, true] {
                for gfx in [nil, 2_300] as [Int?] {
                    let want = GPUControlOD8Want(curve: curve, zeroRpmOff: zero, gfxMaxMHz: gfx)
                    let name = "curve \(curve != nil), zero RPM off \(zero), GFX \(gfx.map(String.init) ?? "stock")"
                    guard let s = want.scalars() else {
                        suite.expect(false, "\(name): has scalars")
                        continue
                    }
                    suite.expect(s.count == 13 && s[0] == 2, "\(name): 13 scalars, version 2 first")
                    suite.expect(s[1] == (curve != nil ? 1 : 0) | (zero ? 2 : 0), "\(name): the flags")
                    let temps = Array(s[2...6]), speeds = Array(s[7...11])
                    if curve != nil {
                        suite.expect(temps == [30, 40, 44, 46, 48] && speeds == [20, 36, 52, 68, 100],
                                     "\(name): five temperatures, then five speeds")
                    } else {
                        suite.expect(temps.allSatisfy { $0 == 0 } && speeds.allSatisfy { $0 == 0 },
                                     "\(name): no curve, ten zeros")
                    }
                    suite.expect(s[12] == UInt64(gfx ?? 0), "\(name): the clock last, 0 for stock")
                    suite.expect(want.heldFlags.rawValue == (curve != nil ? 1 : 0) | (zero ? 2 : 0) | (gfx != nil ? 4 : 0),
                                 "\(name): what status reports while it is held")
                    // The model's dispatcher reads them back as the same state.
                    if !want.isStock {
                        let fake = FakeGPUControlKext()
                        fake.arm()
                        let c = fake.connection()
                        _ = c.open()
                        let answer = c.setOD8(want)
                        suite.expect(answer?.reply == .ok && fake.writes.last?.kind == .od8(want),
                                     "\(name): the kext model takes the same state back")
                    }
                }
            }
        }
        suite.expect(GPUControlOD8Want(curve: Array(testedCurve.prefix(4))).scalars() == nil, "four points cannot be sent")
        suite.expect(GPUControlOD8Want(curve: [GPUControlFanPoint(temperatureC: -1, speedPercent: 20)] + testedCurve.dropFirst())
                         .scalars() == nil, "a negative number cannot be sent")
        suite.expect(GPUControlOD8Want(gfxMaxMHz: 0).scalars() == nil, "a clock of 0 would read as stock: not sent")
        suite.expect(GPUControlOD8Want(gfxMaxMHz: 9_000).scalars()?[12] == 9_000,
                     "an out-of-range clock goes out unchanged: the kext decides, the app never clamps")

        // Changing one setting sends the others that are held.
        let h = Harness()
        h.engine.chooseFan(curve: testedCurve, zeroRpmOff: false)
        h.run(ms: 0)
        suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(curve: testedCurve)), "a curve held")
        h.run(ms: 3_000)
        h.engine.chooseGfxMax(2_300)
        h.run(ms: 0)
        let last = h.calls(.setOD8).last?.input
        suite.expect(last == [2, 1, 30, 40, 44, 46, 48, 20, 36, 52, 68, 100, 2_300],
                     "a clock change carries the held curve")
        h.run(ms: 3_000)
        h.engine.chooseFan(curve: nil, zeroRpmOff: true)
        h.run(ms: 0)
        suite.expect(h.calls(.setOD8).last?.input == [2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2_300],
                     "a fan change carries the held clock")
        suite.expect(h.engine.snapshot.held == .od8(GPUControlOD8Want(zeroRpmOff: true, gfxMaxMHz: 2_300)),
                     "zero RPM off and the clock held together")
    }

    // MARK: The model against the kext's scenarios (spec-fake-kext.md)

    private static func fakeScenarios(_ suite: TestSuite) {
        func pair(armed: Bool = true) -> (FakeGPUControlKext, FakeGPUControlKext.Connection, FakeGPUControlKext.Connection) {
            let fake = FakeGPUControlKext()
            if armed { fake.arm() }
            let c1 = fake.connection(), c2 = fake.connection()
            _ = c1.open()
            _ = c2.open()
            return (fake, c1, c2)
        }
        let gfx = GPUControlOD8Want(gfxMaxMHz: 2_300)

        // S1: not armed.
        do {
            let (_, c1, _) = pair(armed: false)
            suite.expect(c1.status()?.flags.rawValue == 384, "S1: ready + OD8 ready, nothing else (384)")
            suite.expect(c1.setPower(watts: 230)?.reply == .notArmed, "S1: set before arm: not armed")
            suite.expect(c1.setOD8(gfx)?.reply == .notArmed, "S1: setOD8 before arm: not armed")
        }
        // S2: arm needs an administrator; the app never is one.
        do {
            let (fake, c1, _) = pair(armed: false)
            suite.expect(c1.call(.arm, input: [2], outputCount: 1) == [GPUControlReply.notPrivileged.rawValue],
                         "S2: arm from the app: not privileged")
            suite.expect(fake.arm() == .ok && c1.status()?.flags.rawValue == 385, "S2: armed by root (385)")
        }
        // S3: 2 s between writes, exactly.
        do {
            let (fake, c1, _) = pair()
            let t0 = fake.nowMs
            suite.expect(c1.setPower(watts: 230)?.reply == .ok, "S3: first change ok")
            suite.expect(c1.status()?.flags.rawValue == 497, "S3: changed + owned + mine (497)")
            fake.advance(to: t0 + 1_000)
            suite.expect(c1.setPower(watts: 220)?.reply == .tooSoon, "S3: 1 s later: too soon")
            fake.advance(to: t0 + 2_000)
            suite.expect(c1.setPower(watts: 220)?.reply == .ok, "S3: exactly 2 s later: ok")
            fake.advance(to: t0 + 2_001)
            suite.expect(c1.setPower(watts: 210)?.reply == .tooSoon, "S3: 1 ms after that change: too soon")
        }
        // S4: one owner; mine is per connection.
        do {
            let (_, c1, c2) = pair()
            _ = c1.setPower(watts: 230)
            suite.expect(c2.setPower(watts: 220)?.reply == .busy, "S4: another connection: busy")
            suite.expect(c2.status()?.flags.rawValue == 433, "S4: the other sees owned without mine (433)")
            suite.expect(c1.status()?.flags.rawValue == 497, "S4: the owner still sees mine (497)")
        }
        // S5: the start-up value is the way back. While it runs, changed
        // stays set (Owner keeps dirty_ until reverted), so 409, not the
        // spec's 393.
        do {
            let (fake, c1, c2) = pair()
            _ = c1.setPower(watts: 230)
            suite.expect(c1.setPower(watts: 240)?.reply == .ok, "S5: set(boot) answers ok")
            suite.expect(c1.status()?.flags.rawValue == 409, "S5: reverting while the way back runs (409)")
            fake.advance(by: 1_000)
            suite.expect(c1.status()?.flags.rawValue == 385 && c1.status()?.heldW == 240, "S5: back at 240 W (385)")
            suite.expect(c2.setPower(watts: 240)?.reply == .ok && fake.writes.count == 2,
                         "S5: set(boot) from a non-owner is ok and sends nothing")
        }
        // S6: 30 s without alive.
        do {
            let (fake, c1, _) = pair()
            let t0 = fake.nowMs
            _ = c1.setPower(watts: 230)
            fake.advance(to: t0 + 29_999)
            suite.expect(c1.alive()?.reply == .ok, "S6: alive at 29.999 s: ok")
            let (fake2, d1, _) = pair()
            let u0 = fake2.nowMs
            _ = d1.setPower(watts: 230)
            fake2.advance(to: u0 + 30_000)
            suite.expect(d1.alive()?.reply == .notOwner, "S6: alive at 30 s: not owner")
            suite.expect(d1.status()?.flags.rawValue == 409, "S6: the kext is going back (409)")
            fake2.advance(by: 1_000)
            suite.expect(d1.status()?.flags.rawValue == 385, "S6: back (385)")
        }
        // S7: the worker does not answer.
        do {
            let (fake, c1, _) = pair()
            fake.workerStalled = true
            let t0 = fake.nowMs
            suite.expect(c1.setPower(watts: 230)?.reply == .timeout, "S7: no answer in 5 s: timeout")
            suite.expect(fake.nowMs == t0 + 5_000 && fake.writes.isEmpty, "S7: the call took 5 s, nothing was sent")
        }
        // S8: the connection closes.
        do {
            let (fake, c1, c2) = pair()
            _ = c1.setPower(watts: 230)
            c1.close()
            suite.expect(c2.status()?.flags.rawValue == 409, "S8: closing goes back at once (409)")
            fake.advance(by: 1_000)
            suite.expect(c2.status()?.flags.rawValue == 385 && c2.status()?.heldW == 240, "S8: back at 240 W")
            suite.expect(c1.status() == nil, "S8: a closed connection answers nothing")
        }
        // S9: sleep and wake.
        do {
            let (fake, c1, _) = pair()
            _ = c1.setPower(watts: 230)
            let before = fake.writes.count
            fake.sleep()
            suite.expect(fake.writes.count == before, "S9: nothing is sent at sleep")
            fake.advance(by: 1_000)
            suite.expect(c1.setPower(watts: 220)?.reply == .sleeping, "S9: set while asleep: sleeping")
            suite.expect(c1.status()?.flags.rawValue == 405, "S9: sleeping, changed, owner forgotten (405)")
            fake.wake(driverReadAfterMs: 3_000)
            fake.advance(by: 4_000)
            suite.expect(c1.status()?.flags.contains(.sleeping) == true, "S9: still waking 4 s later")
            fake.advance(by: 1_100)
            suite.expect(c1.status()?.flags.contains(.reverting) == true, "S9: read + 2 s: going back")
            fake.advance(by: 1_000)
            suite.expect(c1.status()?.flags.rawValue == 385 && fake.writes.last?.kind == .wayBack,
                         "S9: back at the start-up limit after the wake")
        }
        // S10: an OD8 change held, a power change asked.
        do {
            let (fake, c1, _) = pair()
            _ = c1.setOD8(gfx)
            suite.expect(c1.setPower(watts: 220)?.reply == .tooSoon, "S10: at once: too soon comes first")
            fake.advance(by: 2_000)
            suite.expect(c1.setPower(watts: 220)?.reply == .busy, "S10: power while OD8 is held: busy")
            suite.expect(c1.setOD8(.stock)?.reply == .ok, "S10: the stock OD8 state goes back")
            suite.expect(c1.status()?.flags.rawValue == 409, "S10: going back (409)")
            fake.advance(by: 1_000)
            suite.expect(c1.status()?.flags.rawValue == 385 && c1.status()?.od8Held == [], "S10: OD8 at stock")
        }
        // S11: power held, OD8 asked.
        do {
            let (fake, c1, c2) = pair()
            _ = c1.setPower(watts: 230)
            fake.advance(by: 2_000)
            suite.expect(c1.setOD8(gfx)?.reply == .busy, "S11: OD8 while power is held: busy")
            suite.expect(c2.setOD8(.stock)?.reply == .busy, "S11: the stock state from another program: busy")
        }
        // S12: the fan watchdog.
        do {
            let (fake, c1, _) = pair()
            _ = c1.setOD8(GPUControlOD8Want(curve: testedCurve))
            fake.tripFanWatchdog()
            let s = c1.status()
            suite.expect(s?.flags.contains(.off) == true && s?.flags.contains(.armed) == false, "S12: off, not armed")
            suite.expect(s?.writeOff == .od8Watchdog && s?.od8Held == [] && s?.od8Reverts == 1,
                         "S12: stock fan confirmed, writing off for the watchdog")
            suite.expect(fake.arm() == .off && c1.setPower(watts: 220)?.reply == .off, "S12: arm and set: off")
        }
        // S13: a change that is not confirmed.
        do {
            let (fake, c1, _) = pair()
            fake.failNextChange = true
            suite.expect(c1.setPower(watts: 230)?.reply == .failed, "S13: failed")
            suite.expect(fake.arm() == .off && c1.setPower(watts: 220)?.reply == .off, "S13: off until restart")
            suite.expect(c1.status()?.flags.rawValue == 386 && c1.status()?.writeOff == .sendFailed,
                         "S13: off + ready + OD8 ready (386), send failed")
            let (fake2, d1, _) = pair()
            fake2.failNextChange = true
            fake2.failRecovery = true
            _ = d1.setPower(watts: 230)
            suite.expect(d1.status()?.flags.rawValue == 402, "S13: the way back failed too: the limit is unknown (402)")
        }
        // A way back that does not take.
        do {
            let (fake, c1, _) = pair()
            _ = c1.setPower(watts: 230)
            fake.failNextWayBack = true
            _ = c1.release()
            fake.advance(by: 1_000)
            suite.expect(c1.status()?.writeOff == .revertFailed && c1.status()?.flags.contains(.off) == true,
                         "a failed way back turns writing off")
        }
        // An OD8 change the GPU does not take.
        do {
            let (fake, c1, _) = pair()
            fake.notAppliedNextOD8 = true
            suite.expect(c1.setOD8(gfx)?.reply == .notReady, "not applied: not ready")
            suite.expect(c1.status()?.od8Held == .unknown && c1.status()?.flags.contains(.reverting) == true,
                         "not applied: unknown, stock on its way")
            fake.advance(by: 1_000)
            suite.expect(c1.status()?.od8Held == [], "not applied: stock again")
        }
    }

    /// Every reply the kext has, from the model.
    private static func fakeEveryReply(_ suite: TestSuite) {
        func fresh(_ setup: (FakeGPUControlKext) -> Void = { _ in }) -> (FakeGPUControlKext, FakeGPUControlKext.Connection) {
            let fake = FakeGPUControlKext()
            setup(fake)
            fake.arm()
            let c = fake.connection()
            _ = c.open()
            return (fake, c)
        }
        var seen = Set<UInt64>()
        func got(_ answer: GPUControlAnswer?, _ reply: GPUControlReply, _ why: String) {
            suite.expect(answer?.reply == reply, "\(why): \(reply)")
            if let code = answer?.replyCode { seen.insert(code) }
        }
        let gfx = GPUControlOD8Want(gfxMaxMHz: 2_300)
        do { let (_, c) = fresh(); got(c.setPower(watts: 230), .ok, "a change") }
        do {
            let (_, c) = fresh { $0.version = 1 }
            let out = c.call(.status, input: [2], outputCount: 13)
            suite.expect(out?.count == 9 && out?.first == 1 && out?[1] == 1, "a version 1 kext: 9 scalars, bad version")
            got(c.setPower(watts: 230), .badVersion, "another channel version")
        }
        do {
            let (_, c) = fresh()
            let bad = c.call(.setOD8, input: [2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], outputCount: 2)
            got(bad.map { GPUControlAnswer(replyCode: $0[0]) }, .badArgs, "an unknown setOD8 flag")
            suite.expect(c.call(.set, input: [2], outputCount: 1) == nil, "a wrong count fails the call itself")
            suite.expect(c.call(.status, input: [2], outputCount: 5) == nil, "too few outputs fail the call")
        }
        do {
            let (_, c) = fresh()
            got(c.call(.arm, input: [2], outputCount: 1).map { GPUControlAnswer(replyCode: $0[0]) },
                .notPrivileged, "arm from the app")
        }
        do { let (fake, c) = fresh(); fake.turnOff(.secondObject); got(c.setPower(watts: 230), .off, "writing off") }
        do {
            let fake = FakeGPUControlKext()
            let c = fake.connection()
            _ = c.open()
            got(c.setPower(watts: 230), .notArmed, "not armed")
        }
        do { let (fake, c) = fresh(); fake.bootW = 100; got(c.setPower(watts: 230), .noBootValue, "a start-up value of 100 W") }
        do { let (fake, c) = fresh(); fake.driverReady = false; got(c.setPower(watts: 230), .notReady, "the driver not ready") }
        do { let (fake, c) = fresh(); fake.sleep(); got(c.setPower(watts: 230), .sleeping, "asleep") }
        do {
            let (fake, c) = fresh()
            let other = fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            got(c.setPower(watts: 220), .busy, "another program holds")
        }
        do { let (_, c) = fresh(); _ = c.setPower(watts: 230); got(c.setPower(watts: 220), .tooSoon, "1 ms later") }
        do { let (_, c) = fresh(); got(c.setPower(watts: 190), .belowFloor, "190 W") }
        do { let (_, c) = fresh(); got(c.setPower(watts: 250), .aboveBoot, "250 W") }
        do { let (_, c) = fresh(); got(c.setPower(watts: 225), .notAStep, "225 W") }
        do { let (fake, c) = fresh(); fake.workerStalled = true; got(c.setPower(watts: 230), .timeout, "a stuck worker") }
        do { let (fake, c) = fresh(); fake.failNextChange = true; got(c.setPower(watts: 230), .failed, "not confirmed") }
        do { let (_, c) = fresh(); got(c.alive(), .notOwner, "alive holding nothing") }
        do {
            // The kext answers "cancelled" when its connection closes while a
            // set waits; the synchronous model can only be told to.
            let (fake, c) = fresh()
            fake.forcedReplies[.set] = [GPUControlReply.cancelled.rawValue]
            got(c.setPower(watts: 230), .cancelled, "a forced cancel")
            suite.expect(fake.writes.isEmpty, "a forced reply changes nothing")
        }
        do {
            let (_, c) = fresh()
            let answer = c.setOD8(GPUControlOD8Want(gfxMaxMHz: 1_400))
            got(answer, .od8Refused, "1400 MHz")
            suite.expect(answer?.check == .gfxRange, "the reason: GFX range")
        }
        // 0.8.0's two replies.
        do { let (_, c) = fresh { $0.od8Ready = false }; got(c.setPower(watts: 230), .noFloor, "the card's floor not known") }
        do { let (_, c) = fresh(); _ = c.setPower(watts: 230); got(c.disarm(), .stillApplied, "close while a change is held") }
        suite.expect(seen == Set(GPUControlReply.allCases.map(\.rawValue)), "the model gives every reply of the kext")

        // Every reason writing goes off, with the off-back for OD8.
        for reason in GPUControlWriteOff.allCases where reason != .none {
            let (fake, c) = fresh()
            _ = c.setOD8(gfx)
            fake.turnOff(reason)
            let s = c.status()
            suite.expect(s?.writeOff == reason && s?.flags.contains(.off) == true, "off for \(reason)")
            fake.advance(by: 1_000)
            if reason == .teardown {
                suite.expect(c.status()?.od8Held == .gfxMax, "torn down: nothing more is sent")
            } else {
                suite.expect(c.status()?.od8Held == [], "off for \(reason): OD8 back at stock")
            }
        }
        // The first reason is kept.
        do {
            let (fake, c) = fresh()
            fake.turnOff(.secondObject)
            fake.turnOff(.teardown)
            suite.expect(c.status()?.writeOff == .secondObject, "the first write-off reason is kept")
        }
        // The fan watchdog with readings missing refuses a curve at once.
        do {
            let (fake, c) = fresh { $0.dogSees = false }
            let answer = c.setOD8(GPUControlOD8Want(curve: testedCurve))
            suite.expect(answer?.reply == .od8Refused && answer?.check == .noReadings && fake.writes.isEmpty,
                         "no fan readings: no curve")
        }
    }

    // MARK: The controller

    /// The engine on the model, with the model's clock.
    final class Harness {
        let fake = FakeGPUControlKext()
        let connection: FakeGPUControlKext.Connection
        let engine: GPUControlEngine
        var notices: [GPUControlNotice] = []
        var snapshots: [GPUControlSnapshot] = []

        init(armed: Bool = true, reask: Bool = false, setup: (FakeGPUControlKext) -> Void = { _ in }) {
            setup(fake)
            if armed { fake.arm() }
            connection = fake.connection()
            let fake = self.fake
            engine = GPUControlEngine(channel: connection, clock: { fake.nowMs })
            engine.reaskAfterWake = reask
            engine.onNotice = { [unowned self] in notices.append($0) }
            engine.onSnapshot = { [unowned self] in snapshots.append($0) }
        }

        /// Steps the engine whenever it asks to, moving the model's clock,
        /// for `ms`.
        func run(ms: UInt64) {
            let end = fake.nowMs + ms
            var steps = 0
            while steps < 1_000 {
                steps += 1
                guard let due = engine.step(), due <= end else { break }
                if due > fake.nowMs { fake.advance(to: due) }
            }
            fake.advance(to: end)
        }

        func calls(_ selector: GPUControlWire.Selector? = nil) -> [FakeGPUControlKext.Call] {
            fake.calls.filter { $0.client == connection.clientID && (selector == nil || $0.selector == selector) }
        }

        func replies(_ selector: GPUControlWire.Selector) -> Int { calls(selector).count }

        var held: GPUControlRequest? { engine.snapshot.held }

        /// No change went to the GPU less than 2 s after the write before it.
        var gapsKept: Bool {
            zip(fake.writes, fake.writes.dropFirst()).allSatisfy { previous, write in
                write.kind == .wayBack || write.atMs >= previous.atMs + GPUControlWire.minChangeGapMs
            }
        }
    }

    private static let gfx2300 = GPUControlRequest.od8(GPUControlOD8Want(gfxMaxMHz: 2_300))

    /// Plan section 6, row by row.
    private static func controllerRows(_ suite: TestSuite) {
        // Choosing a value: applying until the answer, held from status.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.snapshots.contains { $0.activity == .applying(.power(watts: 220)) }, "choose: applying first")
            suite.expect(h.held == .power(watts: 220) && h.engine.snapshot.status?.heldW == 220
                             && h.engine.snapshot.status?.flags.contains(.mine) == true,
                         "choose: held once status shows it as mine")
            h.run(ms: 60_000)
            let alive = h.calls(.alive).map(\.atMs)
            suite.expect(alive.count == 12 && zip(alive, alive.dropFirst()).allSatisfy { $1 - $0 == 5_000 },
                         "holding: alive every 5 s")
            suite.expect(h.held == .power(watts: 220) && h.fake.owningClient == h.connection.clientID,
                         "holding: the kext never takes it back")
            suite.expect(h.replies(.status) >= 12, "holding: status every 5 s too")
        }
        // Power to OD8 and back: release, wait for quiet + 2 s, ask.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 10_000)
            suite.expect(h.held == gfx2300, "power to clock: the clock is held")
            suite.expect(h.snapshots.contains { $0.activity == .switching(gfx2300) }, "power to clock: switching first")
            let kinds = h.fake.writes.map(\.kind)
            suite.expect(kinds == [.power(220), .wayBack, .od8(GPUControlOD8Want(gfxMaxMHz: 2_300))],
                         "power to clock: change, way back, change")
            suite.expect(h.gapsKept, "power to clock: 2 s after the way back")
            suite.expect(h.fake.calls.allSatisfy { $0.selector != .setOD8 || $0.atMs > h.fake.writes[1].atMs },
                         "power to clock: no setOD8 before the way back ended")
            h.engine.choose(.power(watts: 210))
            h.run(ms: 10_000)
            suite.expect(h.held == .power(watts: 210) && h.gapsKept, "clock to power: 210 W held, gaps kept")
            suite.expect(h.engine.snapshot.outcome == nil, "no refusal on the way")
        }
        // A new value of the same kind: no release, 2 s after the last write.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 230))
            h.run(ms: 0)
            h.fake.advance(by: 1)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 5_000)
            let sets = h.calls(.set)
            suite.expect(sets.count == 2 && sets[1].atMs - sets[0].atMs == 2_000, "the next value goes 2 s later")
            suite.expect(h.replies(.release) == 0 && h.held == .power(watts: 220), "no way back between two limits")
        }
        // Quitting: release, close.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.shutdown()
            suite.expect(h.calls().last?.selector == .release, "quit: release is the last call")
            suite.expect(h.fake.owningClient == 0 && h.engine.snapshot.stopped == .shutDown, "quit: nothing held, stopped")
            h.fake.advance(by: 1_000)
            suite.expect(h.fake.writes.last?.kind == .wayBack, "quit: the kext went back")
            suite.expect(h.connection.status() == nil, "quit: the connection is closed")
        }
        // The app hangs: 30 s without alive, then the loss is seen.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.advance(by: 31_000)
            h.run(ms: 0)
            suite.expect(h.held == nil && h.engine.snapshot.outcome == .lost, "hang: the kext went back, shown as lost")
            h.run(ms: 60_000)
            suite.expect(h.replies(.set) == 1, "hang: not asked again")
        }
        // Lost without "not owner": status without mine.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.forcedReplies[.alive] = [0, 0, 0]
            h.fake.advance(by: 31_000)
            h.run(ms: 0)
            suite.expect(h.held == nil && h.engine.snapshot.outcome == .lost, "no mine flag: lost")
        }
        // Timeout: taken as not held, released.
        do {
            let h = Harness()
            h.fake.workerStalled = true
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            let calls = h.calls().map(\.selector)
            suite.expect(h.engine.snapshot.outcome == .timedOut && h.held == nil, "timeout: shown, nothing held")
            if let set = calls.firstIndex(of: .set) {
                suite.expect(calls[(set + 1)...].contains(.release), "timeout: release after it, as gpucontrol")
            }
            h.fake.workerStalled = false
            h.run(ms: 60_000)
            suite.expect(h.replies(.set) == 1, "timeout: not asked again")
        }
        // The Mac sleeps: nothing is sent.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.sleep()
            h.run(ms: 20_000)
            suite.expect(h.replies(.release) == 0 && h.replies(.set) == 1, "sleep: no release, no set")
            suite.expect(h.engine.snapshot.outcome == .backAfterWake && h.held == nil,
                         "sleep: a hold lost between sleep and wake counts as the wake's")
        }
        // Another program holds the control.
        do {
            let h = Harness()
            let other = h.fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.outcome == .otherProgram && h.replies(.set) == 0,
                         "another program: not sent")
            let count = h.calls().count
            h.run(ms: 60_000)
            suite.expect(h.calls().count == count, "another program: no retries")
        }
        // The app holds; gpucontrol hold hears busy.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            let other = h.fake.connection()
            _ = other.open()
            suite.expect(other.setPower(watts: 230)?.reply == .busy, "the app holds: another program hears busy")
            h.run(ms: 10_000)
            suite.expect(h.held == .power(watts: 220), "the app keeps it")
        }
        // Refusals: the kext's reason, no retry.
        let refusals: [(GPUControlRequest, GPUControlReply, GPUControlOD8Check)] = [
            (.power(watts: 190), .belowFloor, .ok),
            (.power(watts: 250), .aboveBoot, .ok),
            (.power(watts: 225), .notAStep, .ok),
            (.od8(GPUControlOD8Want(gfxMaxMHz: 1_400)), .od8Refused, .gfxRange),
            (.od8(GPUControlOD8Want(curve: Array(testedCurve.dropLast()) + [GPUControlFanPoint(temperatureC: 50, speedPercent: 100)])),
             .od8Refused, .curveLast),
        ]
        for (request, reply, check) in refusals {
            let h = Harness()
            h.engine.choose(request)
            h.run(ms: 30_000)
            guard case .refused(let asked, let answer)? = h.engine.snapshot.outcome else {
                suite.expect(false, "\(request): refused")
                continue
            }
            suite.expect(asked == request && answer.reply == reply && (check == .ok || answer.check == check),
                         "\(request): refused with \(reply) \(check)")
            suite.expect(GPUControlTextGroup.forReply(answer.replyCode, check: answer.checkCode) == .notAllowed,
                         "\(request): grouped as not allowed")
            suite.expect(h.replies(.set) + h.replies(.setOD8) == 1 && h.held == nil, "\(request): sent once, nothing held")
        }
        // Not sent at all.
        do {
            let h = Harness(armed: false)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.outcome == .closed && h.replies(.set) == 0, "not armed: not sent, closed")
        }
        do {
            let h = Harness { $0.od8Ready = false }
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.outcome == .od8NotRead && h.replies(.setOD8) == 0, "OD8 not read: not sent")
        }
        // Back to the start-up values.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.choose(.startUp)
            h.run(ms: 0)
            suite.expect(h.replies(.release) == 1 && h.held == nil && h.engine.snapshot.outcome == .backToStartUp,
                         "start-up values: release, confirmed")
            h.run(ms: 3_000)
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 3_000)
            h.engine.choose(.od8(.stock))
            h.run(ms: 0)
            suite.expect(h.replies(.release) == 2 && h.replies(.setOD8) == 1 && h.engine.snapshot.outcome == .backToStartUp,
                         "the stock OD8 state is a release too")
            h.engine.choose(.startUp)
            h.run(ms: 0)
            suite.expect(h.replies(.release) == 2 && h.engine.snapshot.outcome == .alreadyAtStartUp,
                         "nothing held: nothing to give back, and the owner is told")
        }
        // The start-up limit asked as a power value: the kext takes that `set`
        // as the way back, so the app asks for the way back.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.run(ms: 3_000)
            h.engine.choose(.power(watts: h.fake.bootW))
            h.run(ms: 0)
            suite.expect(h.replies(.set) == 1 && h.replies(.release) == 1,
                         "power at the start-up limit: release, no set")
            suite.expect(h.held == nil && h.engine.snapshot.outcome == .backToStartUp,
                         "power at the start-up limit: nothing held, confirmed as the way back")
            h.fake.advance(by: 1_000)
            suite.expect(h.fake.writes.map(\.kind) == [.power(220), .wayBack], "power at the start-up limit: the kext went back")
            h.run(ms: 3_000)
            h.engine.choose(.power(watts: h.fake.bootW), origin: .remembered)
            h.run(ms: 0)
            suite.expect(h.replies(.set) == 1 && h.replies(.release) == 1 && h.engine.snapshot.outcome == nil,
                         "power at the start-up limit with nothing held: no call that writes, no outcome")
            h.engine.choose(.power(watts: h.fake.bootW))
            h.run(ms: 0)
            suite.expect(h.replies(.set) == 1 && h.replies(.release) == 1 && h.engine.snapshot.outcome == .alreadyAtStartUp,
                         "power at the start-up limit asked by the owner with nothing held: no call, the owner is told")
        }
        // The way back while another program holds the control: nothing of
        // the other program's is touched, and the owner is told who holds it.
        for request in [GPUControlRequest.startUp, .power(watts: 240)] {
            let h = Harness()
            let other = h.fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            h.engine.choose(request)
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.outcome == .otherProgram, "\(request) while another program holds: other program")
            suite.expect(h.replies(.release) == 0 && h.replies(.set) == 0 && h.held == nil,
                         "\(request) while another program holds: no call that writes")
            suite.expect(h.fake.statusFor(other)?.flags.contains(.mine) == true && h.fake.statusFor(other)?.heldW == 230,
                         "\(request) while another program holds: its change stays")
        }
        // No start-up limit the kext believes: the kext opens nothing, so a
        // power value equal to what `status` shows as `bootW` is not taken as
        // the way back; it ends as "closed", never "not confirmed".
        for boot: UInt32 in [0, 350] {
            let h = Harness { $0.bootW = boot }
            h.engine.choose(.power(watts: boot == 0 ? 240 : boot))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.outcome == .closed && h.held == nil,
                         "start-up limit \(boot) W not believable: closed")
            suite.expect(h.replies(.set) == 0 && h.replies(.release) == 0,
                         "start-up limit \(boot) W not believable: no call that writes")
        }
        // One request at a time; the latest choice wins.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 230))
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.calls(.set).map { $0.input[1] } == [220], "two choices before a step: only the last is sent")
            h.engine.choose(.power(watts: 210), origin: .owner)
            h.engine.choose(.power(watts: 200), origin: .remembered)
            h.run(ms: 5_000)
            suite.expect(h.calls(.set).map { $0.input[1] } == [220, 210],
                         "a remembered setting never replaces the owner's choice")
        }
        // One connection for everything.
        do {
            let h = Harness(reask: true)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 10_000)
            h.fake.sleep()
            h.fake.wake()
            h.engine.didWake()
            h.run(ms: 40_000)
            suite.expect(h.held == gfx2300, "after a wake the clock is held again")
            suite.expect(h.fake.connectionsOpened == 1 && Set(h.fake.calls.map(\.client)).count == 1,
                         "one connection for every call")
        }
    }

    private static func controllerWake(_ suite: TestSuite) {
        // Without asking again: shown, nothing sent.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.sleep()
            h.fake.advance(by: 60_000)
            h.fake.wake(driverReadAfterMs: 3_000)
            let calls = h.calls().count
            h.engine.didWake()
            h.run(ms: 30_000)
            suite.expect(h.held == nil && h.engine.snapshot.outcome == .backAfterWake, "wake: back to the start-up values")
            suite.expect(h.calls().count == calls, "wake, remembering off: no call")
            suite.expect(h.fake.writes.map(\.kind) == [.power(220), .wayBack], "wake: the kext went back on its own")
        }
        // Asking again: after the kext's own way back, 2 s later at least.
        do {
            let h = Harness(reask: true)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.sleep()
            h.fake.advance(by: 60_000)
            h.fake.wake(driverReadAfterMs: 3_000)
            let wokeAt = h.fake.nowMs
            h.engine.didWake()
            h.run(ms: 1_000)
            suite.expect(h.engine.snapshot.activity == .afterWake(.power(watts: 220)) && h.held == nil,
                         "wake: waiting, the remembered value is not shown as held")
            h.run(ms: 40_000)
            suite.expect(h.held == .power(watts: 220), "wake: held again")
            let writes = h.fake.writes
            suite.expect(writes.map(\.kind) == [.power(220), .wayBack, .power(220)] && h.gapsKept,
                         "wake: the kext's way back, then the change 2 s later at least")
            suite.expect(h.calls(.set).last.map { $0.atMs >= wokeAt + GPUControlEngine.wakeSettleMs } == true,
                         "wake: nothing asked in the first 15 s")
        }
        // A slow way back: the kext's own 2 s rule answers, the app retries.
        do {
            let h = Harness(reask: true) { $0.revertMs = 2_500 }
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.sleep()
            h.fake.wake(driverReadAfterMs: 10_000)
            h.engine.didWake()
            h.run(ms: 60_000)
            suite.expect(h.held == .power(watts: 220) && h.gapsKept, "slow wake: held again, gaps kept")
        }
        // The kext's worker sees the sleep late: status still says mine
        // right after the wake. The app gives it back and asks after 15 s.
        do {
            let h = Harness(reask: true)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            // The kext's clock does not run while the Mac sleeps.
            h.fake.sleep(workerLateByMs: 3_000)
            h.fake.wake()
            suite.expect(h.connection.status()?.flags.contains(.mine) == true, "late worker: still mine right after the wake")
            h.engine.didWake()
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(h.replies(.release) == 1, "late worker: the unexpected hold is given back")
            h.run(ms: 40_000)
            suite.expect(h.held == .power(watts: 220) && h.gapsKept, "late worker: held again after the kext's way back")
        }
        // Waking with another program holding: no retry.
        do {
            let h = Harness(reask: true)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.fake.sleep()
            h.fake.wake()
            h.engine.didWake()
            h.fake.advance(by: 6_000)
            let other = h.fake.connection()
            _ = other.open()
            _ = other.setPower(watts: 230)
            h.run(ms: 60_000)
            suite.expect(h.engine.snapshot.outcome == .otherProgram && h.replies(.set) == 1,
                         "wake: another program took it, not asked")
        }
    }

    private static func controllerRetries(_ suite: TestSuite) {
        // Sleeping, not ready, too soon, busy without an owner: every 5 s.
        do {
            let h = Harness()
            h.fake.forcedReplies[.set] = [GPUControlReply.sleeping, .notReady, .tooSoon, .busy].map(\.rawValue)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 30_000)
            let sets = h.calls(.set).map(\.atMs)
            suite.expect(sets.count == 5 && zip(sets, sets.dropFirst()).allSatisfy { $1 - $0 == 5_000 },
                         "transient answers: tried again every 5 s")
            suite.expect(h.held == .power(watts: 220), "transient answers: held at the fifth try")
        }
        // Not ready for a minute: given up, never sent.
        do {
            let h = Harness()
            h.fake.driverReady = false
            h.engine.choose(.power(watts: 220))
            h.run(ms: 70_000)
            suite.expect(h.engine.snapshot.outcome == .gaveUp(.power(watts: 220), .notReady), "not ready: given up after 60 s")
            suite.expect(h.replies(.set) == 0 && h.replies(.status) == 13, "not ready: only status, every 5 s")
            let count = h.calls().count
            h.run(ms: 60_000)
            suite.expect(h.calls().count == count, "given up: nothing more")
        }
        // A different answer: shown, not retried.
        do {
            let h = Harness { $0.bootW = 264 }
            h.fake.forcedReplies[.set] = [GPUControlReply.noBootValue.rawValue]
            h.engine.choose(.power(watts: 260))
            h.run(ms: 30_000)
            suite.expect(h.replies(.set) == 1 && h.engine.snapshot.outcome
                             == .refused(.power(watts: 260), GPUControlAnswer(replyCode: GPUControlReply.noBootValue.rawValue)),
                         "no start-up value: shown, not retried")
        }
        // A newer choice replaces one that waits.
        do {
            let h = Harness()
            h.fake.forcedReplies[.set] = [GPUControlReply.busy.rawValue]
            h.engine.choose(.power(watts: 230))
            h.run(ms: 1_000)
            h.engine.choose(.power(watts: 210))
            h.run(ms: 10_000)
            suite.expect(h.calls(.set).map { $0.input[1] } == [230, 210] && h.held == .power(watts: 210),
                         "a waiting request is replaced by the newer one")
        }
    }

    private static func controllerStops(_ suite: TestSuite) {
        // A change not confirmed: writing off, notice, nothing more.
        do {
            let h = Harness()
            h.fake.failNextChange = true
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.sendFailed.rawValue),
                         "failed: stopped, writing off (send failed)")
            suite.expect(h.notices == [.writingOff(.sendFailed)], "failed: one notice")
            let count = h.calls().count
            h.engine.choose(.power(watts: 210))
            h.engine.refresh()
            h.run(ms: 60_000)
            suite.expect(h.calls().count == count, "failed: no call until the app starts again")
        }
        do {
            let h = Harness()
            h.fake.failNextChange = true
            h.engine.chooseGfxMax(2_300)
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.od8Failed.rawValue),
                         "OD8 failed: stopped (OD8 failed)")
        }
        // The fan watchdog while the app holds a curve.
        do {
            let h = Harness()
            h.engine.chooseFan(curve: testedCurve, zeroRpmOff: false)
            h.run(ms: 0)
            h.fake.tripFanWatchdog()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.od8Watchdog.rawValue)
                             && h.notices == [.writingOff(.od8Watchdog)],
                         "watchdog: stopped and told")
            suite.expect(h.engine.snapshot.status?.od8Held == [], "watchdog: the stock fan is back")
            let count = h.calls().count
            h.engine.chooseFan(curve: testedCurve, zeroRpmOff: false)
            h.run(ms: 60_000)
            suite.expect(h.calls().count == count, "watchdog: nothing more until restart")
        }
        // Writing off while nothing is held: stopped, no notice.
        do {
            let h = Harness()
            h.fake.turnOff(.teardown)
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.stopped == .writingOff(GPUControlWriteOff.teardown.rawValue) && h.notices.isEmpty,
                         "off before asking: stopped, nothing to tell")
        }
        // Another version of the channel.
        do {
            let h = Harness { $0.version = 1 }
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.stopped == .otherVersion(1) && h.engine.snapshot.status?.version == 1,
                         "version 1 kext: stopped, its version shown")
            suite.expect(h.replies(.set) == 0 && h.connection.status() == nil, "version 1 kext: nothing sent, closed")
        }
        // The connection breaks.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.connection.close()
            h.run(ms: 5_000)
            suite.expect(h.engine.snapshot.stopped == .connectionFailed && h.held == nil, "a dead connection: stopped")
            suite.expect(h.fake.connectionsOpened == 1, "a dead connection is not opened again")
        }
        // No service.
        do {
            let h = Harness { $0.openResult = .noService }
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.engine.snapshot.stopped == .noService && h.fake.connectionsOpened == 0, "no kext: stopped")
        }
        // Nothing to do: nothing is opened.
        do {
            let h = Harness()
            h.run(ms: 60_000)
            suite.expect(h.fake.connectionsOpened == 0 && h.fake.calls.isEmpty, "nothing asked: no connection")
            h.engine.refresh()
            h.run(ms: 0)
            suite.expect(h.fake.connectionsOpened == 1 && h.replies(.status) == 1, "the page asks: one status read")
        }
    }

    /// Fixes from the review of phase 1.
    private static func reviewFixes(_ suite: TestSuite) {
        // The GPU does not take a power change: the kext releases the owner,
        // goes back and answers busy (kern_control.cpp:805-810).
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.run(ms: 3_000)
            h.fake.gpuAnswers = false
            h.engine.choose(.power(watts: 210))
            h.run(ms: 0)
            let s = h.engine.snapshot
            suite.expect(h.fake.owningClient == 0 && s.status?.flags.contains(.reverting) == true,
                         "send not taken: the kext gave the hold back and goes back")
            suite.expect(s.held == nil && s.activity == .retrying(.power(watts: 210), .reply(.busy)),
                         "send not taken: nothing held, the request waits (busy without an owner)")
            h.fake.gpuAnswers = true
            h.run(ms: 10_000)
            suite.expect(h.engine.snapshot.held == .power(watts: 210) && h.gapsKept,
                         "the GPU answers again: held at the next try, gaps kept")
        }
        // Writing goes off while a set waits and the app held a change.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.run(ms: 3_000)
            h.fake.forcedReplies[.set] = [GPUControlReply.off.rawValue]
            h.engine.choose(.power(watts: 210))
            h.run(ms: 0)
            suite.expect(h.notices.count == 1 && h.engine.snapshot.stopped != nil,
                         "off under a set while holding: told once, stopped")
        }
        do {
            let h = Harness()
            h.fake.forcedReplies[.set] = [GPUControlReply.off.rawValue]
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            suite.expect(h.notices.isEmpty && h.engine.snapshot.stopped != nil,
                         "off under a first set: stopped, nothing to tell")
        }
        // An older refusal does not stay next to a value that is held.
        do {
            let h = Harness()
            h.engine.choose(.power(watts: 220))
            h.run(ms: 0)
            h.engine.choose(.power(watts: 190))
            h.run(ms: 3_000)
            suite.expect(h.engine.snapshot.outcome != nil, "190 W: refused")
            h.engine.choose(.power(watts: 220))
            suite.expect(h.engine.snapshot.outcome == nil && h.engine.snapshot.held == .power(watts: 220),
                         "choosing the held value again clears the old refusal")
        }
        // The handlers are read under the lock.
        do {
            let fake = FakeGPUControlKext()
            fake.arm()
            let controller = GPUControlController(channel: fake.connection())
            controller.onChange = { _ in }
            suite.expect(controller.onChange != nil && controller.onNotice == nil, "handlers set and read back")
            controller.shutdown(timeout: 1)
        }
        // set(boot) leaves LastReply alone, as the kext does.
        do {
            let fake = FakeGPUControlKext()
            fake.arm()
            let c = fake.connection()
            _ = c.open()
            _ = c.setPower(watts: 190)
            _ = c.setPower(watts: 240)
            suite.expect(c.status()?.lastReplyCode == GPUControlReply.belowFloor.rawValue,
                         "the start-up value does not overwrite the last reply")
        }
    }

    /// The controller's queue around the engine.
    private static func controllerQueue(_ suite: TestSuite) {
        let fake = FakeGPUControlKext()
        fake.arm()
        let connection = fake.connection()
        let controller = GPUControlController(channel: connection)
        suite.expect(controller.snapshot.stopped == nil && fake.connectionsOpened == 0, "a new controller opens nothing")
        controller.choose(.power(watts: 220))
        controller.sync()
        suite.expect(controller.snapshot.held == .power(watts: 220), "the queue: held")
        controller.shutdown(timeout: 1)
        controller.sync()
        suite.expect(fake.calls.last?.selector == .release && fake.owningClient == 0, "shutdown: released at once")
        suite.expect(controller.snapshot.stopped == .shutDown && connection.status() == nil, "shutdown: closed, stopped")

        // Quitting before anything opened: nothing opens.
        let quiet = FakeGPUControlKext()
        let quietController = GPUControlController(channel: quiet.connection())
        quietController.shutdown(timeout: 1)
        quietController.choose(.power(watts: 220))
        quietController.sync()
        suite.expect(quiet.connectionsOpened == 0 && quiet.calls.isEmpty, "shutdown before use: nothing opened, ever")
    }

    /// Plan 11.1: without a channel the controller cannot open anything, and
    /// phase 1 gives it none anywhere.
    private static func noChannel(_ suite: TestSuite) {
        let engine = GPUControlEngine(channel: nil, clock: { 0 })
        suite.expect(engine.snapshot.stopped == .noChannel, "no channel: stopped from the start")
        engine.choose(.power(watts: 220))
        engine.refresh()
        engine.didWake()
        suite.expect(engine.step() == nil && engine.snapshot.stopped == .noChannel && !engine.hasOpened,
                     "no channel: nothing to step, nothing opened")
        let controller = GPUControlController()
        controller.choose(.power(watts: 220))
        controller.refresh()
        controller.sync()
        suite.expect(controller.snapshot.stopped == .noChannel && controller.snapshot.held == nil,
                     "a controller made without a channel: no channel")
        controller.shutdown(timeout: 1)

        // The source: the real channel is made in one place only, inside
        // applicationDidFinishLaunching, and only the service gives the
        // controller a channel (plan 11.1).
        let root = FileManager.default.currentDirectoryPath + "/Sources/RyzenStatus"
        let files = (FileManager.default.enumerator(atPath: root)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") }
        suite.expect(files.count > 100, "the sources are found from the repo root")
        var makers: [String: Int] = [:]
        var controllers: [String] = []
        for file in files {
            guard let text = try? String(contentsOfFile: root + "/" + file, encoding: .utf8) else { continue }
            let made = text.components(separatedBy: "KextGPUControlChannel(").count - 1
            if made > 0 { makers[file] = made }
            if text.contains("GPUControlController(channel") { controllers.append(file) }
        }
        suite.expect(makers == ["App/AppDelegate.swift": 1],
                     "only AppDelegate makes a KextGPUControlChannel, once: \(makers)")
        suite.expect(controllers == ["Services/Metrics/GPUControlService.swift"],
                     "only the service gives the controller a channel: \(controllers)")
        if let app = try? String(contentsOfFile: root + "/App/AppDelegate.swift", encoding: .utf8),
           let launch = app.range(of: "func applicationDidFinishLaunching("),
           let made = app.range(of: "KextGPUControlChannel(") {
            let nextFunction = app.range(of: "\n    func ", range: launch.upperBound..<app.endIndex)?.lowerBound ?? app.endIndex
            suite.expect(made.lowerBound > launch.upperBound && made.lowerBound < nextFunction,
                         "the real channel is made inside applicationDidFinishLaunching")
        } else {
            suite.expect(false, "AppDelegate makes the real channel at launch")
        }
    }

    // MARK: Text groups (plan section 13)

    private static func textGroups(_ suite: TestSuite) {
        typealias G = GPUControlTextGroup
        let replies: [GPUControlReply: G] = [
            .badVersion: .otherVersion, .badArgs: .notAllowed, .notPrivileged: .needsAdministrator, .off: .writingOff,
            .notArmed: .closed, .noBootValue: .notReady, .notReady: .notReady, .sleeping: .notReady, .busy: .busy,
            .tooSoon: .busy, .belowFloor: .notAllowed, .aboveBoot: .notAllowed, .notAStep: .notAllowed,
            .timeout: .unconfirmed, .failed: .unconfirmed, .notOwner: .notOwner, .cancelled: .notReady,
            .od8Refused: .notAllowed, .noFloor: .noFloor, .stillApplied: .stillApplied,
        ]
        suite.expect(replies.count == 20, "20 replies besides ok")
        for reply in GPUControlReply.allCases {
            suite.expect(G.forReply(reply.rawValue) == replies[reply], "reply \(reply.rawValue) \(reply): its group")
            suite.expect(!reply.kextText.isEmpty, "reply \(reply): the kext's words")
        }
        suite.expect(G.forReply(99) == nil, "an unknown reply has no group: shown as the kext wrote it")
        let checks: [GPUControlOD8Check: G] = [
            .notRead: .notReady, .drifted: .notReady, .memoryMoved: .notReady, .noFeature: .settingMissing,
            .curveRange: .notAllowed, .curveOrder: .notAllowed, .curveFirst: .notAllowed, .curveLast: .notAllowed,
            .curveCooling: .notAllowed, .gfxRange: .notAllowed, .noReadings: .settingMissing,
        ]
        suite.expect(checks.count == 11, "11 OD8 reasons besides ok")
        for check in GPUControlOD8Check.allCases {
            suite.expect(G.forOD8Check(check.rawValue) == checks[check], "OD8 check \(check.rawValue) \(check): its group")
            if check != .ok {
                suite.expect(G.forReply(GPUControlReply.od8Refused.rawValue, check: check.rawValue) == checks[check],
                             "OD8 refused for \(check): the reason's group")
            }
        }
        suite.expect(G.forOD8Check(12) == nil, "an unknown OD8 reason has no group")
        suite.expect(G.forReply(GPUControlReply.od8Refused.rawValue, check: 12) == .notAllowed,
                     "refused for an unknown reason: not allowed")
        let offs: [GPUControlWriteOff: G] = [
            .ctlOff: .offNotAsExpected, .notOneCard: .offNotAsExpected, .otherAmdGpu: .offNotAsExpected,
            .library: .offNotAsExpected, .routes: .offNotAsExpected, .cwdde: .offNotAsExpected,
            .secondObject: .offNotAsExpected, .bootImplausible: .offNotAsExpected, .start: .offNotAsExpected,
            .sendFailed: .offChangeUnconfirmed, .revertFailed: .offChangeUnconfirmed, .teardown: .offDriverStopped,
            .od8Failed: .offChangeUnconfirmed, .od8Watchdog: .offWatchdog, .readOnlyCard: .readOnlyCard,
        ]
        suite.expect(offs.count == 15, "15 write-off reasons")
        for reason in GPUControlWriteOff.allCases {
            suite.expect(G.forWriteOff(reason.rawValue) == offs[reason], "write off \(reason.rawValue) \(reason): its group")
            suite.expect(reason == .none || !reason.kextText.isEmpty, "write off \(reason): the kext's words")
        }
        suite.expect(G.forWriteOff(16) == nil, "an unknown write-off reason has no group")
        let answer = GPUControlAnswer(replyCode: GPUControlReply.od8Refused.rawValue, checkCode: 10)
        suite.expect(answer.kextText == "GFX max must be between 1500 MHz and the stock maximum",
                     "a refused OD8 state shows the reason in the kext's words")
        suite.expect(GPUControlAnswer(replyCode: 77).kextText == "reply 77", "an unknown reply shows its number")
    }

    // MARK: Wire numbers (control_logic.hpp, kext 0.8.0)

    /// The numbers written out, in the kext's order: a case added in the
    /// middle of an enum would renumber the channel without any other test
    /// noticing, since the rest compare the app with itself.
    private static func wireNumbers(_ suite: TestSuite) {
        let selectors: [(GPUControlWire.Selector, UInt32)] = [
            (.status, 0), (.arm, 1), (.set, 2), (.alive, 3), (.release, 4), (.setOD8, 5), (.disarm, 6),
        ]
        suite.expect(selectors.allSatisfy { $0.0.rawValue == $0.1 } && GPUControlWire.Selector.allCases.count == 7,
                     "selectors: status 0 ... disarm 6, as kSelStatus ... kSelDisarm")
        suite.expect(GPUControlWire.Selector.disarm.inputCount == 1 && GPUControlWire.Selector.disarm.outputCount == 1,
                     "disarm: the version in, the reply out")
        let replies: [(GPUControlReply, UInt64)] = [
            (.ok, 0), (.badVersion, 1), (.badArgs, 2), (.notPrivileged, 3), (.off, 4), (.notArmed, 5),
            (.noBootValue, 6), (.notReady, 7), (.sleeping, 8), (.busy, 9), (.tooSoon, 10), (.belowFloor, 11),
            (.aboveBoot, 12), (.notAStep, 13), (.timeout, 14), (.failed, 15), (.notOwner, 16), (.cancelled, 17),
            (.od8Refused, 18), (.stillApplied, 19), (.noFloor, 20),
        ]
        suite.expect(replies.allSatisfy { $0.0.rawValue == $0.1 } && GPUControlReply.allCases.count == 21,
                     "replies: ok 0 ... noFloor 20, as gpuctl::Reply")
        let checks: [(GPUControlOD8Check, UInt64)] = [
            (.ok, 0), (.notRead, 1), (.drifted, 2), (.memoryMoved, 3), (.noFeature, 4), (.curveRange, 5),
            (.curveOrder, 6), (.curveFirst, 7), (.curveLast, 8), (.curveCooling, 9), (.gfxRange, 10),
            (.noReadings, 11),
        ]
        suite.expect(checks.allSatisfy { $0.0.rawValue == $0.1 } && GPUControlOD8Check.allCases.count == 12,
                     "OD8 checks: ok 0 ... noReadings 11, as gpuctl::Od8Check")
        let offs: [(GPUControlWriteOff, UInt64)] = [
            (.none, 0), (.ctlOff, 1), (.notOneCard, 2), (.otherAmdGpu, 3), (.library, 4), (.routes, 5),
            (.cwdde, 6), (.secondObject, 7), (.bootImplausible, 8), (.start, 9), (.sendFailed, 10),
            (.revertFailed, 11), (.teardown, 12), (.od8Failed, 13), (.od8Watchdog, 14), (.readOnlyCard, 15),
        ]
        suite.expect(offs.allSatisfy { $0.0.rawValue == $0.1 } && GPUControlWriteOff.allCases.count == 16,
                     "write-off reasons: none 0 ... readOnlyCard 15, as gpuctl::WriteOff")
        kextConstants(suite)
    }

    /// Security review S-6: the kext's constants the app mirrors, read from
    /// the kext's own source in this repository
    /// (`GPU/sensors/kext/control_logic.hpp`, GPUSensors 0.8.0) and compared
    /// with the app's, so a change on either side fails here.
    /// Not the power floor: since 0.8.0 the floor is the card's own
    /// (`PowerRange`), and `kMinBootW` only checks the start-up read.
    private static func kextConstants(_ suite: TestSuite) {
        let path = FileManager.default.currentDirectoryPath + "/GPU/sensors/kext/control_logic.hpp"
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        suite.expect(!source.isEmpty, "S-6: GPU/sensors/kext/control_logic.hpp is read from the repo root")
        let mirrored: [(String, UInt64)] = [
            ("kChannelVersion", GPUControlWire.channelVersion),
            ("kMaxBootW", UInt64(GPUControlWire.maxBootW)),
            ("kMinBootW", UInt64(GPUControlWire.minBootW)),
            ("kStepW", UInt64(GPUControlWire.powerStepW)),
            ("kOd8GfxFloorMHz", UInt64(GPUControlWire.gfxFloorMHz)),
            ("kOd8DogHoldMs", GPUControlWire.od8DogHoldMs),
            ("kWakeReadyMarginMs", GPUControlWire.wakeReadyMarginMs),
            ("kSetWaitMs", GPUControlWire.setWaitMs),
            ("kMaxPowerPercentDown", UInt64(GPUControlPowerRange.maxPercentDown)),
        ]
        let kext = constants(in: source)
        for (name, app) in mirrored {
            suite.expect(kext[name] == [app],
                         "S-6: \(name) is \(kext[name] ?? []) in control_logic.hpp, the app has \(app)")
        }
    }

    /// `constexpr <integer type> <name> = <decimal>;` lines of a C++ header,
    /// by name; a name defined twice keeps both values (and fails above).
    static func constants(in source: String) -> [String: [UInt64]] {
        let pattern = #"(?m)^\s*(?:static\s+)?constexpr\s+u?int(?:8|16|32|64)_t\s+(k\w+)\s*=\s*([0-9][0-9']*)u?l{0,2}\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [:] }
        let text = source as NSString
        var found: [String: [UInt64]] = [:]
        for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: match.range(at: 1))
            let digits = text.substring(with: match.range(at: 2)).replacingOccurrences(of: "'", with: "")
            if let value = UInt64(digits) { found[name, default: []].append(value) }
        }
        return found
    }
}
