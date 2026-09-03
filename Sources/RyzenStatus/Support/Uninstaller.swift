// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import ServiceManagement

/// `RyzenStatus --uninstall`: cleanly detaches the app from the system
/// before its bundle is removed. It unregisters the login item — so no dead
/// entry lingers in System Settings › General › Login Items — and restores
/// normal sleep if a closed-lid session left it disabled.
///
/// Used by `Tools/uninstall.sh`. Must run from the installed bundle, since
/// `SMAppService.mainApp` is scoped to the running app's bundle identifier.
enum Uninstaller {
    static func runAndExit() -> Never {
        if UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) {
            _ = Sudoers.pmsetDisableSleep(false)
        }
        do {
            try SMAppService.mainApp.unregister()
            print("UNINSTALL: login item unregistered")
        } catch {
            print("UNINSTALL: login item was not registered")
        }
        exit(0)
    }
}
