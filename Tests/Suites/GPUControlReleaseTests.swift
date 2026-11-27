// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// GPU control refuses the GPUSensors releases that panic (0.9.1 and 0.9.2)
/// and anything it was not checked against, and says so where GPU control
/// lives (batch 256, part 3).
enum GPUControlReleaseTests {
    static func run(_ suite: TestSuite) {
        releases(suite)
        refused(suite)
        warning(suite)
    }

    /// A release build's `VersionInfo`: "REL-", the digits, then the date.
    private static func build(_ release: String) -> String { "REL-\(release)-2026-11-27" }

    private static func releases(_ suite: TestSuite) {
        suite.expect(GPUControlCurveRules.checkedReleases == ["080", "081", "090", "093"],
                     "the checked releases are 080, 081, 090 and 093")
        suite.expect(!GPUControlCurveRules.checkedReleases.contains("091"),
                     "0.9.1 is not a checked release")
        suite.expect(!GPUControlCurveRules.checkedReleases.contains("092"),
                     "0.9.2 is not a checked release")
        suite.expect(GPUControlCurveRules.shippedRelease == "093",
                     "the app says it ships GPUSensors 0.9.3")

        for release in ["090", "093"] {
            suite.expect(GPUControlCurveRules.isChecked(build(release)),
                         "GPUSensors \(release) is a checked release")
            suite.expect(!GPUControlCurveRules.isOutdated(build(release)),
                         "GPUSensors \(release) is not out of date")
        }
    }

    private static func refused(_ suite: TestSuite) {
        for release in ["091", "092", "094"] {
            suite.expect(!GPUControlCurveRules.isChecked(build(release)),
                         "GPUSensors \(release) is refused")
            suite.expect(GPUControlCurveRules.isOutdated(build(release)),
                         "GPUSensors \(release) is reported as out of date")
        }
        // An older release outside the set, and builds that are not a release.
        suite.expect(GPUControlCurveRules.isOutdated(build("072")),
                     "a release outside the set is out of date")
        suite.expect(GPUControlCurveRules.isOutdated("DBG-2026-11-27"),
                     "a debug build is not a checked release")
        suite.expect(GPUControlCurveRules.isOutdated(nil),
                     "an empty build name is not a checked release")
        // The one build checked by name stays accepted.
        suite.expect(GPUControlCurveRules.isChecked("REL-072-2026-11-19"),
                     "the build checked by name is accepted")
    }

    private static func warning(_ suite: TestSuite) {
        let en = FeatureStrings.gpuControlPage(.enUS)
        suite.expect(
            en.kextOutdated == "The GPU package is out of date. Open the RyzenStatus GPU installer from the DMG and install the update, then restart.",
            "the warning is the sentence the job asks for")
        suite.expect(en.all.contains(en.kextOutdated),
                     "the warning is part of the page's texts")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.gpuControlPage(language)
            suite.expect(!strings.kextOutdated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         "\(language.rawValue) has the warning")
            suite.expect(!strings.all.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }),
                         "\(language.rawValue) has no empty page text")
        }

        // The page's own rule: only a kext that says which build it is.
        var input = GPUControlPageInput(facts: nil, state: nil, snapshot: nil)
        input.kextVersion = build("091")
        suite.expect(input.kextOutdated, "the page warns about 0.9.1")
        input.kextVersion = build("092")
        suite.expect(input.kextOutdated, "the page warns about 0.9.2")
        input.kextVersion = build("093")
        suite.expect(!input.kextOutdated, "the page says nothing about 0.9.3")
        input.kextVersion = build("090")
        suite.expect(!input.kextOutdated, "the page says nothing about 0.9.0")
        input.kextVersion = nil
        suite.expect(!input.kextOutdated, "a kext with no build name is not judged")
    }
}
