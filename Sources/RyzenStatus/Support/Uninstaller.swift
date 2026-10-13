// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import ServiceManagement

/// `RyzenStatus --uninstall`: cleanly detaches the app from the system
/// before its bundle is removed. It unregisters the login item — so no dead
/// entry lingers in System Settings › General › Login Items — restores normal sleep if a closed-lid session left it disabled, and
/// puts back the Space rearranging setting.
///
/// Used by `Tools/uninstall.sh`. Must run from the installed bundle, since
/// `SMAppService.mainApp` is scoped to the running app's bundle identifier.
enum Uninstaller {
    static func runAndExit() -> Never {
        // This runs before `NSApplication.shared` exists, so the password
        // dialog the in-app uninstall falls back to is not available here: it
        // brings the app forward through `NSApp`, which is still nil. Reporting
        // is all this path can do, and `Tools/uninstall.sh` reads the setting
        // back itself rather than trusting the line below.
        if UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) {
            // A probe that did not answer proves nothing. Only a reading
            // that came back, and came back off, clears the restore.
            let probe = Shell.run("/usr/bin/pmset", ["-g"])
            let restored = Sudoers.pmsetDisableSleep(false)
                || (probe.status == 0
                    && !SudoersSupport.sleepDisabled(inPmsetOutput: probe.output))
            print(restored
                  ? "UNINSTALL: normal sleep restored"
                  : "UNINSTALL: sleep is still disabled")
        }
        if SpacesOrderHold.hasPendingRestore {
            print(SpacesOrderHold.restoreForRemoval()
                  ? "UNINSTALL: Space rearranging restored"
                  : "UNINSTALL: Space arrangement restoration could not be confirmed")
        }
        if SpacesOrderHold.hasPendingRestore {
            print(SpacesOrderHold.restoreForRemoval()
                  ? "UNINSTALL: Space rearranging restored"
                  : "UNINSTALL: Space arrangement restoration could not be confirmed")
        }
        do {
            try SMAppService.mainApp.unregister()
            print("UNINSTALL: login item unregistered")
        } catch {
            print("UNINSTALL: login item was not registered")
        }
        // A login item that was never registered is not a failure, and sleep
        // and Space rearranging are settings the caller can read back itself.
        exit(EXIT_SUCCESS)
    }
}
