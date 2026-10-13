// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import ServiceManagement

/// Clears the app's own footprint on the system, for a clean uninstall.
///
/// Security note: every operation here is scoped to THIS app and nothing else.
/// The bundle id is a constant identifier (never user input), so the `tccutil`
/// call cannot be steered elsewhere; the login item and sudoers rule are the
/// app's own; the preference and saved-state paths are built from the app's own
/// bundle id; and the only thing deleted is the app's own bundle, which is moved
/// to the Trash (reversible). Nothing leaves the machine.
enum SelfUninstall {
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.ryzenstatus.utils" }

    /// Resets every TCC permission the app holds, drops the login item and the
    /// optional closed-lid sudoers rule, and leaves the app in place. Calls back
    /// on the main queue with whether the rule and permissions were removed.
    /// Used by "Clear all permissions".
    static func clearPermissions(completion: @escaping (Bool) -> Void) {
        // Stop every input interceptor FIRST (on the main thread), then revoke.
        // Revoking Accessibility while a tap is live makes the tap callback hang
        // on an AX call and freezes the whole machine's input — see the note on
        // `suspendInputInterceptors`.
        DispatchQueue.main.async {
            suspendInputInterceptors()
            DispatchQueue.global(qos: .userInitiated).async {
                let sleepRestored = restoreSleepBeforeRemoval()
                detachFromSystem()
                removeSudoersRuleIfPresent { ruleRemoved in    // may show one admin prompt
                    let reset = resetTCC()
                    DispatchQueue.main.async {
                        // The published permissions still say granted. Read the
                        // reset state now, or a grant made before the next poll
                        // looks unchanged and the suspended taps never resume.
                        Permissions.shared.refresh()
                        KeepAwakeManager.shared.resumeAfterSystemTeardown()
                        // Whatever survived the reset comes back on its own
                        // preference and permission.
                        FeatureRuntime.shared.sync(AppFeature.allCases)
                        completion(sleepRestored && ruleRemoved && reset)
                    }
                }
            }
        }
    }

    /// Clears permissions, removes preferences and saved state, sends the app
    /// bundle to the Trash and quits. Used by "Uninstall RyzenStatus completely".
    /// Anything that refuses to come off stops it before the preferences and
    /// the bundle go, and `onFailure` gets the message explaining why.
    static func uninstallCompletely(onFailure: @escaping (String) -> Void) {
        // A failed step may have changed some grants. Recheck them before
        // rearming services in the app that remains installed.
        func stop(_ body: String) {
            DispatchQueue.main.async {
                Permissions.shared.refresh()
                KeepAwakeManager.shared.resumeAfterSystemTeardown()
                FeatureRuntime.shared.sync(AppFeature.allCases)
                onFailure(body)
            }
        }
        DispatchQueue.main.async {
            suspendInputInterceptors()
            DispatchQueue.global(qos: .userInitiated).async {
                // Removal is the one exit with no next launch to repair a sleep
                // setting left off, or the Space arrangement setting, so both
                // must be confirmed back before anything else is removed.
                guard SpacesOrderHold.restoreForRemoval(), restoreSleepBeforeRemoval() else {
                    stop(L10n.shared.s.advancedUninstallFailedBody)
                    return
                }
                removeSudoersRuleIfPresent { ruleRemoved in
                    guard ruleRemoved else {
                        stop(L10n.shared.s.advancedClearFailed)
                        return
                    }
                    guard resetTCC() else {
                        stop(L10n.shared.s.advancedClearFailed)
                        return
                    }
                    // Do not clear the launch choice while a failed reset
                    // could still leave this app installed.
                    detachFromSystem()
                    removePreferences()
                    DispatchQueue.main.async { trashOwnBundleAndQuit() }
                }
            }
        }
    }

    // MARK: - Steps (each scoped to this app only)

    /// Tears down every Accessibility-backed input interceptor. MUST run on the
    /// main thread and BEFORE permissions are reset: otherwise revoking
    /// Accessibility while an event tap is still live makes the tap's callback
    /// block on an AX call, which stalls the OS input queue and freezes the
    /// keyboard and clicks (only the mouse cursor keeps moving). Each `stop`/
    /// `suspend`/`deactivate` is idempotent, so calling it when a service is
    /// already off is a no-op.
    @MainActor
    private static func suspendInputInterceptors() {
        ScrollInverter.shared.suspend()
        FocusFollowsMouseService.shared.stop()
        MouseClickDebounceService.shared.suspend()
        MouseAccelerationService.shared.stop()
        SmoothScrollService.shared.suspend()
        MouseNavigationService.shared.suspend()
        WindowMaximizer.shared.stop()
        WindowLayoutService.shared.suspend()
        AppSwitcher.shared.suspend()
        DockPreviewService.shared.stop()
        AutoQuitService.shared.suspend()
        FinderCutPaste.shared.suspend()
        FinderRenameService.shared.suspend()
        KeyboardDebounceService.shared.suspend()
        DockClickService.shared.suspend()
        MiddleClickService.shared.suspend()
        QuitProtectionService.shared.suspend()
        PastePlainService.shared.suspend()
        ScreenCaptureService.shared.suspend()
        RecentCaptureService.shared.suspend()
        QuickLauncherService.shared.suspend()
        ScreenTextService.shared.suspend()
        CameraPreviewService.shared.suspend()
        RadialMenuService.shared.suspend()
        ScratchpadService.shared.suspend()
        // Leaving the mic cut after the app is gone would strand the user
        // with a silent input and no indicator anywhere.
        MicMuteService.shared.unmuteForTeardown()
        MicMuteService.shared.suspend()
        CleaningModeManager.shared.deactivate()
    }

    private static func detachFromSystem() {
        // The Space arrangement marker goes with the preferences, so the
        // system setting is put back first.
        _ = SpacesOrderHold.restoreForRemoval()
        // Unregister the login item (scoped to our bundle id). The stored
        // intent goes with it, or the startup repair would quietly register
        // the item again after the user asked for a clean detach.
        UserDefaults.standard.set(false, forKey: DefaultsKey.launchAtLoginWanted)
        try? SMAppService.mainApp.unregister()
    }

    /// Puts normal sleep back before the app goes. Quitting may leave a failed
    /// revert to the next launch's repair, but removal has no next launch and
    /// the flag that would trigger that repair goes with the preferences, so
    /// this may ask for the password the launch-time recovery would have asked
    /// for. A stale flag must not cost a dialog: only a reading that answered,
    /// and answered "off", skips the rest.
    private static func restoreSleepBeforeRemoval() -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) else { return true }
        let probe = Shell.run("/usr/bin/pmset", ["-g"])
        if probe.status == 0, !SudoersSupport.sleepDisabled(inPmsetOutput: probe.output) {
            return true
        }
        if Sudoers.pmsetDisableSleep(false) { return true }
        guard AdminShell.runSync("pmset disablesleep 0",
                                 prompt: L10n.shared.s.adminPromptRecover) else { return false }
        let verification = Shell.run("/usr/bin/pmset", ["-g"])
        return verification.status == 0
            && !SudoersSupport.sleepDisabled(inPmsetOutput: verification.output)
    }

    private static func removeSudoersRuleIfPresent(then: @escaping (Bool) -> Void) {
        guard Sudoers.ruleFilesPresent || Sudoers.isConfigured() else { then(true); return }
        Sudoers.remove(completion: then)            // shows the admin password prompt
    }

    /// `tccutil reset All <bundle id>` clears Accessibility, Screen Recording,
    /// Full Disk Access, Automation and the rest, for this app only. The bundle
    /// id is a constant, so there is nothing to inject.
    @discardableResult
    private static func resetTCC() -> Bool {
        Shell.run("/usr/bin/tccutil", ["reset", "All", bundleID]).status == 0
    }

    private static func removePreferences() {
        let id = bundleID
        UserDefaults.standard.removePersistentDomain(forName: id)
        let home = NSHomeDirectory()
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Preferences/\(id).plist")
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Saved Application State/\(id).savedState")
        // Clipboard images and any other app-owned data live here.
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Application Support/\(id)")
        try? FileManager.default.removeItem(atPath: "\(home)/Library/Caches/\(id)")
        // URLSession writes these on our behalf whenever the app talks to the
        // network, so they exist without the app ever choosing the path.
        try? FileManager.default.removeItem(atPath: "\(home)/Library/HTTPStorages/\(id)")
        try? FileManager.default.removeItem(
            atPath: "\(home)/Library/HTTPStorages/\(id).binarycookies")
    }

    /// Moves the app's own bundle to the Trash after it quits, then quits. The
    /// path is the running app's own location, checked to be an `.app`, so this
    /// can only ever remove this app. A detached helper does the move so the
    /// bundle is not mutated while it is running.
    private static func trashOwnBundleAndQuit() {
        let app = Bundle.main.bundlePath
        guard app.hasSuffix(".app"), app != "/" else { NSApp.terminate(nil); return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        APP="$1"; PID="$2"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        TRASH="$HOME/.Trash"
        /bin/mkdir -p "$TRASH" 2>/dev/null || true
        BASE="$(basename "$APP")"
        DEST="$TRASH/$BASE"
        n=2
        while [ -e "$DEST" ]; do DEST="$TRASH/${BASE%.app} $n.app"; n=$((n+1)); done
        # Reversible move to the Trash. If a direct move fails, ask Finder to do
        # the same Trash operation so it can present the standard admin prompt.
        if ! /bin/mv "$APP" "$DEST" 2>/dev/null; then
            /usr/bin/osascript - "$APP" <<'APPLESCRIPT'
        on run argv
            tell application "Finder" to delete POSIX file (item 1 of argv)
        end run
        APPLESCRIPT
        fi
        if [ -d "$APP" ]; then /usr/bin/open "$APP" 2>/dev/null; fi
        /bin/rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryzenstatus-uninstall-\(pid)-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptURL.path, app, "\(pid)"]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            // This used to return here, silently.
            //
            // By the time we reach this point the destructive steps have ALREADY
            // run — TCC grants were reset and preferences removed — so a silent
            // return leaves the app half uninstalled, still in /Applications,
            // with nothing on screen to say the uninstall did not finish. The
            // user clicked "uninstall completely" and got no result and no error.
            //
            // The helper script exists to move the bundle AFTER this process
            // exits, which is tidier, but moving a running bundle works and is
            // just as reversible (it goes to the Trash). So fall back to doing it
            // in-process, and if even that fails, reveal the bundle so the user
            // can finish by hand rather than being told nothing at all.
            NSLog("SelfUninstall: uninstall helper could not be launched (\(error.localizedDescription)) — falling back to an in-process Trash move")
            let bundleURL = URL(fileURLWithPath: app)
            NSWorkspace.shared.recycle([bundleURL]) { _, recycleError in
                DispatchQueue.main.async {
                    if let recycleError = recycleError {
                        NSLog("SelfUninstall: in-process Trash move also failed (\(recycleError.localizedDescription)) — revealing the bundle for manual removal")
                        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
