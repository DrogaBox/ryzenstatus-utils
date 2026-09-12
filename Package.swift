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
            path: "Sources/RyzenStatus"
        )
    ]
)
