// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct CutPasteSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = FinderCutPaste.shared
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.cutPasteEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        FinderCutPaste.shared.syncWithPreferences()
                    }
                Text(l10n.s.cutPasteEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(l10n.s.cutPasteActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(l10n.s.cutPasteHowTitle) {
                howRow(keys: ["⌘", "X"], text: l10n.s.cutPasteStep1)
                howRow(keys: ["⌘", "V"], text: l10n.s.cutPasteStep2)
                Text(l10n.s.cutPasteTextNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                    Text(l10n.s.cutPasteAutomationNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func howRow(keys: [String], text: String) -> some View {
        HStack(spacing: 10) {
            ShortcutCaps(keys: keys)
                .frame(width: 56, alignment: .leading)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
