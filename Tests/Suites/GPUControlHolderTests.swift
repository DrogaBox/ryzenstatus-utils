// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Who holds the GPU control when it is not the app (security review S-5,
/// corrected): `gpucontrol`, the tool RyzenStatus installs, is not "another
/// program" when it keeps the OD8 table (and the fan curve in it) from a
/// terminal. Nothing here opens the kext or the registry: the decision is
/// `GPUControlHolderLogic`, and the wiring is the sources'.
enum GPUControlHolderTests {
    static func run(_ suite: TestSuite) {
        classification(suite)
        creators(suite)
        notices(suite)
        wires(suite)
    }

    // MARK: The decision

    private static func classification(_ suite: TestSuite) {
        let ours: (Int32) -> Bool = { $0 == 4_242 }
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: false, attachedPids: [4_242], ownPid: 9,
                                                    isOwnTool: ours) == .none,
                     "nothing held: nobody, whatever is attached")
        suite.expect(GPUControlHolderLogic.classify(mine: true, owned: true, attachedPids: [9], ownPid: 9,
                                                    isOwnTool: ours) == .app,
                     "the app's own connection holds it: the app")
        // The case in the report: `gpucontrol hold` keeps a curve, the app
        // holds nothing but its own connection is attached.
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [9, 4_242], ownPid: 9,
                                                    isOwnTool: ours) == .tool,
                     "only our gpucontrol attached besides the app: our own tool")
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [777], ownPid: 9,
                                                    isOwnTool: ours) == .other,
                     "a program of its own: another program")
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [9, 4_242, 777], ownPid: 9,
                                                    isOwnTool: ours) == .other,
                     "our tool and another program attached: another program")
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [9], ownPid: 9,
                                                    isOwnTool: ours) == .other,
                     "a hold with no other client listed: nothing the app can vouch for")
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [4_242, 4_243], ownPid: 9,
                                                    isOwnTool: ours) == .other,
                     "two programs attached, one of them not ours: another program")
        suite.expect(GPUControlHolderLogic.classify(mine: false, owned: true, attachedPids: [4_242], ownPid: 9,
                                                    isOwnTool: { _ in false }) == .other,
                     "a gpucontrol the app does not install: another program")
        suite.expect(!GPUControlHolder.none.isOwnTool && !GPUControlHolder.app.isOwnTool
                        && !GPUControlHolder.other.isOwnTool && GPUControlHolder.tool.isOwnTool,
                     "only .tool is ours")
    }

    // MARK: The kernel's own word about a client

    private static func creators(_ suite: TestSuite) {
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "pid 4242, gpucontrol") == 4_242,
                     "IOUserClientCreator: the pid")
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "pid 1, RyzenStatus") == 1, "a pid of one digit")
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "gpucontrol") == nil, "no pid in the value: nothing")
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "pid 0, kernel_task") == nil, "pid 0 is never a client")
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "pid abc, x") == nil, "not a number: nothing")
        suite.expect(GPUControlHolderLogic.pid(fromCreator: "") == nil, "an empty value: nothing")
    }

    // MARK: The notice (S-5)

    private static func notices(_ suite: TestSuite) {
        func held(_ holder: GPUControlHolder) -> GPUControlFacts {
            var facts = GPUControlFacts(source: .properties)
            facts.armed = true
            facts.ready = true
            facts.owned = true
            facts.holder = holder
            return facts
        }
        var watch = GPUControlForeignWatch()
        suite.expect(watch.next(facts: held(.tool), appHolds: false, appClosing: false) == nil,
                     "our own gpucontrol took the fan curve: no another-program notice")
        watch = GPUControlForeignWatch()
        suite.expect(watch.next(facts: held(.other), appHolds: false, appClosing: false) == .changed,
                     "a program the app cannot vouch for: the notice, as before")
        // Ours, then a real stranger: the stranger is still told.
        watch = GPUControlForeignWatch()
        _ = watch.next(facts: held(.tool), appHolds: false, appClosing: false)
        suite.expect(watch.next(facts: held(.other), appHolds: false, appClosing: false) == .changed,
                     "our tool first, another program after: the other program is told")
        // The app's own hold is not a foreign one either.
        watch = GPUControlForeignWatch()
        suite.expect(watch.next(facts: held(.app), appHolds: true, appClosing: false) == nil,
                     "the app's own hold: nothing")
    }

    // MARK: The wiring

    private static func wires(_ suite: TestSuite) {
        let service = source("Sources/RyzenStatus/Services/Metrics/GPUControlService.swift")
        suite.expect(service.contains("GPUControlHolderProbe.current("), "the service asks who holds it")
        suite.expect(service.contains(".map(withHolder)"), "every page read carries the answer")
        let page = source("Sources/RyzenStatus/Services/Metrics/GPUControlPage.swift")
        suite.expect(page.contains("facts.holder.isOwnTool"),
                     "a hold by our own tool is not another program's notice")
        let view = source("Sources/RyzenStatus/UI/Settings/GPUControlSettingsView.swift")
        suite.expect(view.contains("s.heldByTool"), "the page says gpucontrol, not another program")
        let strings = source("Sources/RyzenStatus/Core/GPUControlPageStrings.swift")
        suite.expect(strings.contains("heldByTool: \"gpucontrol"), "the sentence is written")
        suite.expect(!strings.contains("heldByTool: \"\""), "and written in every language")
        // No new kext field: the identity comes from IOKit.
        let kext = source("GPU/sensors/kext/control_logic.hpp")
        suite.expect(!kext.isEmpty && !kext.contains("kFlagOwnerIsTool"), "the kext is not touched")
    }

    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: FileManager.default.currentDirectoryPath + "/" + path,
                     encoding: .utf8)) ?? ""
    }
}
