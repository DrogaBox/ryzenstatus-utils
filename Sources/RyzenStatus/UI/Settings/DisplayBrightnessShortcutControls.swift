// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct DisplayBrightnessShortcutControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.displayBrightnessShortcutsEnabled) private var enabled = false
    var showsShortcutRows = true
    var showsSettingsRow = false

    var body: some View {
        let strings = FeatureStrings.brightness(l10n.language)
        Group {
            if showsSettingsRow {
                SettingsRow(symbol: "keyboard", title: strings.displayBrightnessShortcuts,
                            caption: strings.displayBrightnessShortcutCaption) {
                    Toggle(strings.displayBrightnessShortcuts, isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            } else {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strings.displayBrightnessShortcuts)
                        Text(strings.displayBrightnessShortcutCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: enabled) { _, _ in brightness.syncWithPreferences() }
        if showsShortcutRows, enabled {
            ForEach([GlobalShortcutRole.displayBrightnessDecrease, .displayBrightnessIncrease]) { role in
                // Inactive roles already count as conflicts here (see
                // GlobalShortcut.conflictTitle), so no extra flag is passed.
                ShortcutPreferenceRow(role: role, isEnabled: enabled, label: role.title(l10n.s),
                                      additionalConflict: { shortcut in
                    guard AppFeature.windowLayout.isAvailable else { return nil }
                    return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
                }) {
                    brightness.syncWithPreferences()
                }
                .padding(.leading, showsSettingsRow ? settingsRowTextInset : 0)
            }
        }
        if enabled, brightness.displayBrightnessShortcutRegistrationFailed {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, showsSettingsRow ? settingsRowTextInset : 0)
        }
    }
}
