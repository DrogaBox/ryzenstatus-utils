// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import PackageDescription

let package = Package(
    name: "RyzenStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RyzenStatus",
            path: "Sources/RyzenStatus",
            swiftSettings: [
                // S10 BLD-01: staging step toward Swift 6 language mode. The
                // target compiled in Swift 5 mode with no concurrency checking,
                // so none of the isolation invariants this audit relies on were
                // enforced. StrictConcurrency surfaces them as WARNINGS first —
                // flip to .swiftLanguageMode(.v6) only once warnings reach zero.
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
