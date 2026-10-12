// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

// The child Super Key leaves behind takes its key mapping back out if the app
// dies without quitting, then exits.
SuperKeyMappingGuard.runIfRequestedAndExit()
Defaults.register()
// The island's keyboard-light control appears only on a Mac whose built-in
// keyboard backlight the system client can actually drive.
NotchControlItem.keyboardLightIsSupported = { BrightnessService.keyboardLightIsSupported }

// The child the mouse acceleration feature leaves behind puts the pointer
// settings back if the app dies without quitting, then exits.
MouseAccelerationGuard.runIfRequestedAndExit()
MouseAccelerationService.recoverPendingAtLaunch()

// A developer's check of the island's windows, only in debug builds.
#if DEBUG
if CommandLine.arguments.contains("--notch-presentation-test") {
    NotchPresentationProbe.runAndExit()
}
#endif

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
