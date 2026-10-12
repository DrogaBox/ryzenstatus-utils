// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Shared hints from panel content to the AppKit popover host.
final class PanelInteractionState: ObservableObject {
    static let shared = PanelInteractionState()

    /// A visible utility whose workflow intentionally spans clicks in other
    /// apps. This is one input to the close policy, not the policy itself.
    @Published var viewKeepsPopoverOpen = false

    /// A SwiftUI alert or confirmation dialog is presented from the popover.
    /// Closing its parent window underneath the presentation can leave AppKit's
    /// modal state orphaned and make the next panel unresponsive.
    var isPresentingPopoverModal = false

    /// The one answer every AppKit dismissal path uses. Service state lives here
    /// so the generic popover host does not know about individual tools, and an
    /// operation keeps protecting the panel even after the user switched to
    /// another section of it. The system AirPlay picker is a separate window,
    /// so a click in it must not read as a click outside the panel.
    var preventsPopoverDismissal: Bool {
        PanelInteractionSupport.blocksDismissal(
            viewKeepsPopoverOpen: viewKeepsPopoverOpen,
            isPresentingPopoverModal: isPresentingPopoverModal,
            airPlayPickerShown: AirPlayRouteManager.isPresentingPicker,
            homebrewOperationActive: HomebrewManager.shared.operationStatus?.isActive == true,
            cleanerRunning: JunkCleaner.shared.phase.isRunning,
            uninstallerRunning: AppUninstaller.shared.phase.isRunning)
    }

    /// The screen the menu bar icon is on, so the panel caps its height against
    /// that display instead of whichever one happens to be main. Not published:
    /// the panel reads it while measuring itself.
    var anchorScreen: NSScreen?

    private init() {}
}
