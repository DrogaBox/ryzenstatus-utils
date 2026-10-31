// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The Settings pages that show live data, and which shared sources each one
/// holds while it is on screen. One row per page, so "every page" has a
/// single definition. A page's own work (an SMC sweep, the fan poll) stays in
/// the page and runs through the same activation.
enum SettingsLivePage: CaseIterable {
    case performanceSuite
    case sensors
    case fans
    case amdPower
    case amdOverclocking
    case amdValidation
    case monitorSettings

    /// Registers a full SystemMonitor client, which samples every family.
    var holdsMonitorClient: Bool {
        switch self {
        case .performanceSuite, .sensors, .fans, .amdPower, .monitorSettings: return true
        // Overclocking reads only the kext caches; Validation takes one
        // snapshot when it opens and on request.
        case .amdOverclocking, .amdValidation: return false
        }
    }

    /// Holds the shared 3 s kext poll of `AmdPowerControlsModel`.
    var holdsLiveSync: Bool {
        switch self {
        case .performanceSuite, .amdPower, .amdOverclocking: return true
        case .sensors, .fans, .amdValidation, .monitorSettings: return false
        }
    }
}

/// Runs a Settings page's live work exactly while the page is on screen in a
/// visible Settings window. Closing the window keeps the page alive without
/// `onDisappear`, so window visibility is part of the rule. Activation and
/// deactivation fire only on a change, so the reference counts underneath
/// (monitor clients, kext poll) always stay balanced.
struct SettingsPageActivity: ViewModifier {
    @ObservedObject private var visibility = SettingsWindowVisibility.shared
    @State private var appeared = false
    @State private var active = false
    let page: SettingsLivePage
    let activate: () -> Void
    let deactivate: () -> Void

    nonisolated static func isActive(appeared: Bool, windowVisible: Bool) -> Bool { appeared && windowVisible }

    func body(content: Content) -> some View {
        content
            .onAppear { appeared = true; sync() }
            .onDisappear { appeared = false; sync() }
            .onChange(of: visibility.isVisible) { _, _ in sync() }
    }

    private func sync() {
        let next = Self.isActive(appeared: appeared, windowVisible: visibility.isVisible)
        guard next != active else { return }
        active = next
        if next {
            if page.holdsMonitorClient { SystemMonitor.shared.panelDidAppear() }
            if page.holdsLiveSync { AmdPowerControlsModel.shared.beginLiveSync() }
            activate()
        } else {
            deactivate()
            if page.holdsLiveSync { AmdPowerControlsModel.shared.endLiveSync() }
            if page.holdsMonitorClient { SystemMonitor.shared.panelDidDisappear() }
        }
    }
}

extension View {
    func settingsPageActivity(_ page: SettingsLivePage,
                              activate: @escaping () -> Void = {},
                              deactivate: @escaping () -> Void = {}) -> some View {
        modifier(SettingsPageActivity(page: page, activate: activate, deactivate: deactivate))
    }
}
