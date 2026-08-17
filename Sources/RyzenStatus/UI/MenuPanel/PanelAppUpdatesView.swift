// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

struct PanelAppUpdatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = AppUpdatesService.shared

    var onClose: () -> Void

    private var text: AppUpdateStrings { FeatureStrings.appUpdates(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            AppUpdatesListView(compact: true)
                .panelCard()
        }
        .onAppear {
            PanelInteractionState.shared.keepsPopoverOpen = true
            updates.checkIfNeeded()
        }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.pageTitle, systemImage: "arrow.down.app")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .appUpdates
                appDelegate()?.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
            .accessibilityLabel(l10n.s.uninstallerCancel)
        }
    }
}
