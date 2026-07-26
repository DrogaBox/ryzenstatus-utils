// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings for programmable mouse button shortcuts.
struct MouseButtonSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MouseButtonShortcutService.shared
    @AppStorage(DefaultsKey.mouseButtonShortcutsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.mouseButtonShortcuts) private var mappingsData: String = ""

    @State private var accessibilityWarning = false
    @State private var isCapturing = false
    @State private var capturedButton: Int64? = nil
    @State private var captureShortcut = GlobalShortcut.keepAwakeDefault

    private var strings: MouseButtonFeatureStrings { FeatureStrings.mouseButtons(l10n.language) }

    private var mappings: [Int64: GlobalShortcut] {
        guard let data = mappingsData.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return MouseButtonShortcutSupport.decode(dict)
    }

    private var sortedMappings: [(button: Int64, shortcut: GlobalShortcut)] {
        mappings.sorted { $0.key < $1.key }.map { (button: $0.key, shortcut: $0.value) }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.enableLabel)
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
                            startCaptureFlow()
                        }
                    } else {
                        accessibilityWarning = false
                        stopCapture()
                        MouseButtonShortcutService.shared.syncWithPreferences()
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
                            Text("Mouse Button Shortcuts needs Accessibility access to detect button presses and type shortcuts.")
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

                    Text("After granting permission, toggle the feature off and on again.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if enabled && AXIsProcessTrusted() {
                if isCapturing {
                    captureSection
                }

                if !isCapturing {
                    mappingsSection
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if enabled && !AXIsProcessTrusted() {
                accessibilityWarning = true
            } else if enabled && AXIsProcessTrusted() && mappings.isEmpty {
                startCaptureFlow()
            }
        }
        .onDisappear {
            stopCapture()
        }
        .onChange(of: service.lastButtonSeen) { _, button in
            guard let button, isCapturing else { return }
            capturedButton = button
            service.setCapturing(false)
        }
    }

    // MARK: - Capture Flow

    private var captureSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "computermouse")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)

                if capturedButton == nil {
                    VStack(spacing: 4) {
                        Text(strings.captureWaiting)
                            .font(.headline)
                        Text(strings.captureHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(String(format: strings.otherButtonFormat, capturedButton!))
                                .font(.headline)
                        }

                        Divider()

                        VStack(spacing: 10) {
                            Text(strings.setShortcutButton)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ShortcutRecorderButton(
                                shortcut: captureShortcut,
                                isEnabled: true,
                                recordingTitle: "Type shortcut\u{2026}",
                                invalidAction: { NSSound.beep() },
                                captureAction: { captured in
                                    captureShortcut = captured
                                }
                            )
                            .frame(width: 120, height: 32)

                            HStack(spacing: 12) {
                                Button("Skip") {
                                    resetCapture()
                                }
                                .controlSize(.small)

                                Button(strings.setShortcutButton) {
                                    saveCapturedMapping()
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .disabled(!captureShortcut.hasUsableKeyCode)
                            }

                            Text("Tap Done when finished, or press another button")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    if capturedButton == nil {
                        Button(strings.captureCancel) {
                            stopCapture()
                            enabled = false
                        }
                        .controlSize(.small)
                    } else {
                        Button("Done") {
                            stopCapture()
                        }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        } header: {
            Text(strings.addButton)
        }
    }

    // MARK: - Mappings List

    private var mappingsSection: some View {
        Section {
            if sortedMappings.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "button.programmable")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text(strings.emptyCaption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(strings.addButton) {
                            startCaptureFlow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(sortedMappings, id: \.button) { item in
                    HStack {
                        Image(systemName: "computermouse")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: strings.otherButtonFormat, item.button))
                                .font(.body)
                            Text(item.shortcut.displayString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteMapping(item.button)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !sortedMappings.isEmpty {
                Button {
                    startCaptureFlow()
                } label: {
                    Label(strings.addButton, systemImage: "plus")
                }
            }
        } header: {
            Text(strings.pageTitle)
        } footer: {
            Text(strings.enableCaption)
        }
    }

    // MARK: - Actions

    private func startCaptureFlow() {
        guard AXIsProcessTrusted() else { return }
        capturedButton = nil
        captureShortcut = GlobalShortcut.keepAwakeDefault
        isCapturing = true
        service.setCapturing(true)
    }

    private func stopCapture() {
        isCapturing = false
        capturedButton = nil
        service.setCapturing(false)
    }

    private func resetCapture() {
        capturedButton = nil
        captureShortcut = GlobalShortcut.keepAwakeDefault
        service.setCapturing(true)
    }

    private func saveCapturedMapping() {
        guard let button = capturedButton,
              MouseButtonShortcutSupport.canMap(button),
              captureShortcut.hasUsableKeyCode else { return }
        var current = mappings
        current[button] = captureShortcut
        saveMappings(current)
        resetCapture()
    }

    private func deleteMapping(_ button: Int64) {
        var current = mappings
        current.removeValue(forKey: button)
        saveMappings(current)
    }

    private func saveMappings(_ mappings: [Int64: GlobalShortcut]) {
        let encoded = MouseButtonShortcutSupport.encode(mappings)
        if let data = try? JSONSerialization.data(withJSONObject: encoded),
           let json = String(data: data, encoding: .utf8) {
            mappingsData = json
        }
        MouseButtonShortcutService.shared.syncWithPreferences()
    }
}
