// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

Defaults.register()

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

// Top-level code in main.swift is nonisolated in the Swift 5 language mode, and
// AppDelegate is now @MainActor. This is the program entry point, so the main
// thread is where we are by definition — asserting that isolation is a statement
// of fact here, not a workaround for a diagnostic.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
