// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings for Super Key (Caps Lock remapping).
struct SuperKeySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.superKeyEnabled) private var enabled = false
    @State private var accessibilityWarning = false

    private var strings: SuperKeyStrings { FeatureStrings.superKey(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.enableToggle)
                        Text(strings.enableCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: enabled) { _, newValue in
                    if newValue {
                        if !AXIsProcessTrusted() {
                            accessibilityWarning = true
                        } else {
                            accessibilityWarning = false
                            SuperKeyService.shared.syncWithPreferences()
                        }
                    } else {
                        accessibilityWarning = false
                        SuperKeyService.shared.syncWithPreferences()
                    }
                }

                if accessibilityWarning {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Permission Required")
                                .font(.caption.weight(.semibold))
                            Text("Super Key needs Accessibility access to monitor the keyboard and apply the key mapping.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Open Settings") {
                            Permissions.shared.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("After granting permission in System Settings, toggle Super Key off and on again.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(strings.holdHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(strings.pageTitle)
            } footer: {
                Text(strings.panelCaption)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if enabled && !AXIsProcessTrusted() {
                accessibilityWarning = true
            }
        }
    }
}
