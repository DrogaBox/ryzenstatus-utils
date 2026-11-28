// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The kext version gate (batch 84, job 259): a kext outside
/// `GPUControlCurveRules.checkedReleases`, or one that publishes no
/// `VersionInfo`, is sent no value — the six controls that send one, "Load
/// profile", the remembered setting after launch and the wake re-ask. The way
/// back to the start-up values (`backToStartUp`, `closeChanges`) is not a
/// change and stays open.
enum GPUControlKextGateTests {
    static func run(_ suite: TestSuite) {
        verdicts(suite)
        remembered(suite)
        policy(suite)
        wiring(suite)
    }

    // MARK: The verdict

    private static func verdicts(_ suite: TestSuite) {
        suite.expect(GPUControlKextGate.verdict(nil) == .unknown, "no version read: unknown, not fine")
        suite.expect(GPUControlKextGate.verdict("   ") == .unknown, "a blank version: unknown too")
        suite.expect(GPUControlKextGate.verdict("REL-091-2026-11-27") == .outdated,
                     "0.9.1, one of the two that panicked this Mac: outdated")
        suite.expect(GPUControlKextGate.verdict("REL-092-2026-11-27") == .outdated,
                     "0.9.2, the other one: outdated")
        suite.expect(GPUControlKextGate.verdict("REL-093-2026-11-27") == .allowed,
                     "0.9.3, the release this app carries: allowed")
        suite.expect(GPUControlKextGate.verdict("REL-080-2026-11-21") == .allowed, "0.8.0: allowed")
        suite.expect(GPUControlKextGate.verdict("REL-072-2026-11-19") == .allowed,
                     "the exact build the curve rules were checked against: allowed")
        suite.expect(GPUControlKextGate.verdict("DBG-abc") == .outdated,
                     "a debug build (no release digits): not a build this copy was checked against")
        suite.expect(GPUControlKextGate.verdict("  REL-093-2026-11-27\n ") == .allowed,
                     "the version is trimmed before it is judged")
    }

    // MARK: What the remembered setting does

    private static func remembered(_ suite: TestSuite) {
        suite.expect(GPUControlKextGate.remembered(.allowed) == .send,
                     "a checked build: the remembered setting goes out")
        suite.expect(GPUControlKextGate.remembered(.outdated) == .drop,
                     "an outdated build: given up, nothing sent")
        suite.expect(GPUControlKextGate.remembered(.unknown) == .wait,
                     "no version read yet: it waits, the pending flag is kept")
        suite.expect(GPUControlKextGate.remembered(GPUControlKextGate.verdict(nil)) == .wait,
                     "a kext that says nothing keeps the setting waiting, never sends it")
        suite.expect(GPUControlKextGate.remembered(GPUControlKextGate.verdict("REL-092-2026-11-27")) == .drop,
                     "0.9.2 drops it before the request is even built")
        suite.expect(GPUControlKextGate.remembered(GPUControlKextGate.verdict("REL-093-2026-11-27")) == .send,
                     "0.9.3 sends it")
    }

    // MARK: The remembered request

    /// The second gate, inside the policy: a remembered fan state only ever
    /// goes to a build the curve rules were checked against. The service's
    /// gate drops a remembered setting before this runs; this one keeps the
    /// fan state from leaving on its own.
    private static func policy(_ suite: TestSuite) {
        let fake = FakeGPUControlKext()
        fake.arm()
        // The channel's facts, as GPUControlKext080Tests reads them: the model's
        // properties carry no `OD8State`, so only the status flags say the OD8
        // read is clean.
        let channel = fake.connection()
        _ = channel.open()
        var snapshot = GPUControlSnapshot()
        snapshot.status = channel.status()
        guard let facts = GPUControlPageLogic.facts(snapshot: snapshot,
                                                    control: GPUControlService.fakeControl(fake)) else {
            suite.expect(false, "the kext model's facts load")
            return
        }
        suite.expect(facts.armed && facts.od8Ready, "the model is armed and its OD8 read")
        let want = GPUControlOD8Want(curve: GPUControlFanDraft.testedCurve)
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts,
                                                      stopped: nil, kextVersion: nil) == nil,
                     "a remembered curve with no version read: nothing goes out")
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts,
                                                      stopped: nil, kextVersion: "REL-092-2026-11-27") == nil,
                     "a remembered curve with 0.9.2: nothing goes out")
        suite.expect(GPUControlRememberPolicy.request(remembered: .od8(want), active: true, facts: facts,
                                                      stopped: nil, kextVersion: "REL-093-2026-11-27") != nil,
                     "a remembered curve with the build this copy was checked against: it goes")
    }

    // MARK: The service's wiring

    /// Where the gate sits in `GPUControlService`. The service itself needs a
    /// channel and a kext, which a unit test cannot install (a release build
    /// always takes the real connection mode), so the paths are checked here:
    /// every control that sends a value is behind the gate, the remembered
    /// setting and the wake re-ask ask it, and the two way-back paths do not.
    private static func wiring(_ suite: TestSuite) {
        let path = FileManager.default.currentDirectoryPath
            + "/Sources/RyzenStatus/Services/Metrics/GPUControlService.swift"
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        suite.expect(!source.isEmpty, "the service's source is readable")
        func count(_ needle: String) -> Int { source.components(separatedBy: needle).count - 1 }
        suite.expect(count("guard !kextRefusesWrites else { return }") == 7,
                     "the six controls that send a value and load profile sit behind the gate")
        suite.expect(count("GPUControlKextGate.remembered(kextVerdict)") == 1,
                     "the remembered setting asks the gate")
        suite.expect(source.contains("GPUControlKextGate.verdict(control?.writing?.kextVersion"),
                     "the wake re-ask asks the gate")
        suite.expect(!source.contains("guard let version = control?.writing?.kextVersion"),
                     "the old nil-is-fine check is gone")

        func body(of function: String) -> String {
            guard let start = source.range(of: "func \(function)(") else { return "" }
            let rest = source[start.upperBound...]
            guard let end = rest.range(of: "\n    }") else { return "" }
            return String(rest[..<end.lowerBound])
        }
        for name in ["backToStartUp", "closeChanges"] {
            let text = body(of: name)
            suite.expect(!text.isEmpty, "\(name): found in the source")
            suite.expect(!text.contains("kextRefusesWrites") && !text.contains("kextOutdated")
                            && !text.contains("kextVersionUnknown") && !text.contains("kextVerdict")
                            && !text.contains("GPUControlKextGate"),
                         "\(name): the way back keeps no version gate, on purpose")
        }
        let openWriting = body(of: "openWriting")
        suite.expect(openWriting.contains("guard !kextOutdated else { return }")
                        && !openWriting.contains("kextRefusesWrites"),
                     "opening writing asks the outdated build only: arming sends no value")
    }
}
