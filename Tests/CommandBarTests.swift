// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Standalone harness for the command bar's pure logic, in the same shape as
/// `MetricsTests`: no XCTest, equality and boolean assertions only, every case
/// in a file of its own.
///
/// `./build.sh --test` compiles a pinned list of sources and its list is
/// frozen, so it cannot reach the command bar's modules. This harness is built
/// and run by `Tools/commandbar-tests.sh`, which pins the bar's pure modules
/// next to the local files they depend on.
typealias CommandBarExpect = (Bool, String) -> Void

@main
struct CommandBarTests {
    static func main() {
        var failures: [String] = []
        var checks = 0
        let expect: CommandBarExpect = { condition, message in
            checks += 1
            if !condition { failures.append(message) }
        }

        CommandBarMathCases.run(expect)
        CommandBarUnitsCases.run(expect)
        CommandBarDatesCases.run(expect)
        CommandBarEmojiCases.run(expect)
        CommandBarLearningCases.run(expect)
        CommandBarRowShortcutCases.run(expect)
        CommandBarPreferencesCases.run(expect)
        CommandBarStringsCases.run(expect)

        if failures.isEmpty {
            print("COMMAND BAR TESTS OK (\(checks) checks)")
            exit(0)
        }
        for failure in failures { print("✗ \(failure)") }
        print("COMMAND BAR TESTS FAILED (\(failures.count) of \(checks) checks)")
        exit(1)
    }
}
