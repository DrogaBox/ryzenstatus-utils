// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The panel's close policy as plain booleans, so the rules can be pinned by the
/// unit harness instead of only by running the app. The AppKit popover host
/// gathers the state it can see; the decision lives here.
enum PanelInteractionSupport {
    /// The one answer every dismissal path asks for. A workflow that spans
    /// clicks in other apps, a presented alert, or an operation still running
    /// outrank a click outside, and the service flags keep protecting the panel
    /// even after the user switched to another section of it.
    static func blocksDismissal(viewKeepsPopoverOpen: Bool,
                                isPresentingPopoverModal: Bool,
                                airPlayPickerShown: Bool = false,
                                homebrewOperationActive: Bool,
                                cleanerRunning: Bool,
                                uninstallerRunning: Bool) -> Bool {
        viewKeepsPopoverOpen
            || isPresentingPopoverModal
            || airPlayPickerShown
            || homebrewOperationActive
            || cleanerRunning
            || uninstallerRunning
    }
}
