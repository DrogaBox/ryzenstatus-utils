// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import ApplicationServices
import Foundation

enum AutoQuitWindowEvent: Equatable {
    case windowDestroyed
    case appHidden
    case appDeactivated
    case mainWindowChanged
    case focusedWindowChanged
    case windowCreated
    case windowDeminiaturized
    case appShown
    case other
}

enum AutoQuitSupport {
    /// QWERTY position of the W key — only a fallback for when the event carries
    /// no typed character; the service matches the layout-resolved character
    /// first (key codes are positional: 13 types "z" on AZERTY).
    static let commandWKeyCode: Int64 = 13

    /// Bundle metadata key some standalone apps use to declare which host
    /// process they depend on (Chromium's "CrBundleIdentifier").
    private static let hostBundleIdentifierKey = "CrBundleIdentifier"

    static func shouldScheduleWindowCheck(for event: AutoQuitWindowEvent,
                                          hasRecentCloseRequest: Bool) -> Bool {
        switch event {
        case .windowDestroyed:
            return true
        case .appHidden:
            return hasRecentCloseRequest
        case .appDeactivated,
             .mainWindowChanged,
             .focusedWindowChanged,
             .windowCreated,
             .windowDeminiaturized,
             .appShown,
             .other:
            return false
        }
    }

    /// Every found user window requires a registered destroy notification.
    /// Accessibility-listed windows set that count directly; window-server
    /// evidence when Accessibility lists none still requires one watch.
    static func needsWindowWatchRetry(registeredWindows: Int,
                                      listedWindows: Int,
                                      foundUserWindow: Bool) -> Bool {
        foundUserWindow && registeredWindows < max(listedWindows, 1)
    }

    /// Whether adding a window notification left the observer watching for it.
    /// Already registered is the ordinary answer, not a failure: every refresh
    /// registers the windows it is already watching again, and counting those
    /// as unwatched would zero the count above on every refresh and leave the
    /// retry firing for as long as the app runs.
    static func isWindowNotificationRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    static func shouldQuitAfterWindowCheck(hadWindows: Bool,
                                           appIsTerminated: Bool,
                                           appIsExcepted: Bool,
                                           appIsHidden: Bool,
                                           hiddenByCloseRequest: Bool,
                                           hasKnownMinimizedWindow: Bool,
                                           hasUserFacingWindow: Bool) -> Bool {
        guard hadWindows, !appIsTerminated, !appIsExcepted else { return false }
        if appIsHidden && !hiddenByCloseRequest { return false }
        if hasKnownMinimizedWindow { return false }
        return !hasUserFacingWindow
    }

    static func isCommandW(keyCode: Int64, command: Bool, control: Bool) -> Bool {
        keyCode == commandWKeyCode && command && !control
    }

    /// Some standalone apps depend on a separate host process and declare that
    /// relationship in their bundle metadata. Quitting the host while one of
    /// those apps is running would close both from a single window close.
    static func hasDependentApplication(hostBundleIdentifier: String?,
                                        applicationBundleURLs: [URL]) -> Bool {
        guard let hostBundleIdentifier, !hostBundleIdentifier.isEmpty else { return false }
        return applicationBundleURLs.contains { bundleURL in
            Bundle(url: bundleURL)?.object(forInfoDictionaryKey: hostBundleIdentifierKey) as? String
                == hostBundleIdentifier
        }
    }
}
