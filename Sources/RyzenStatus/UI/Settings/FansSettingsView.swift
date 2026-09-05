// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

// MARK: - Fans Settings View

struct FansSettingsView: View {
    @ObservedObject var controller = FanCurveController.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.fanCurvesEditorEnabled) private var autoFanCurveEnabled = false
    @State private var showingMaxSpeedConfirmation = false

    var body: some View {
        Form {
            // MARK: - Privilege / Driver Warning
            if controller.kextMissing {
                Section {
                    SMCNotAvailableView()
                }
            } else {
                if let errorMsg = controller.privilegeError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.fanControl.privilegeRequiredBanner)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(errorMsg)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                controller.privilegeError = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Fan Cards Section
                if controller.fans.isEmpty {
                    Section {
                        Group {
                            if controller.isLoadingFans {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(l10n.fanControl.loadingSensors)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(l10n.fanControl.noFansDetected)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }
                } else {
                    Section {
                        HStack {
                            Text(l10n.fanControl.smcTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .textCase(.uppercase)
                            Spacer()
                            let hiddenCount = controller.fans.filter { $0.isHidden }.count
                            if hiddenCount > 0 {
                                Button(action: {
                                    for f in controller.fans {
                                        controller.setHidden(fanId: f.id, hidden: false)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                        Text(String(format: l10n.fanControl.showAllHiddenFormat, hiddenCount))
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.cyan)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                            Text(l10n.fanControl.bootArgNote)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)

                        ForEach(controller.fans.filter { !$0.isHidden }) { fan in
                            FanControlCard(fan: fan)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }

                        // Bulk Actions Bar
                        HStack(spacing: 10) {
                            Button(action: {
                                controller.setAllAuto()
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(l10n.fanControl.allAutoButton)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.cyan)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(Color.cyan.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.35)))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                showingMaxSpeedConfirmation = true
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "wind")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(l10n.fanControl.maxSpeedButton)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.orange)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35)))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                l10n.fanControl.maxSpeedConfirmationTitle,
                                isPresented: $showingMaxSpeedConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button(l10n.fanControl.confirmButton, role: .destructive) {
                                    controller.setAllMaxSpeed()
                                }
                                Button(l10n.fanControl.cancelButton, role: .cancel) {}
                            } message: {
                                Text(l10n.fanControl.maxSpeedConfirmationMessage)
                            }
                        }
                    } header: {
                        Text(l10n.fanControl.fansHeader)
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(nil)
                    }

                    // MARK: - Dynamic Curves Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l10n.fanControl.dynamicCurvesTitle)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(l10n.fanControl.dynamicCurvesSubtitle)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $autoFanCurveEnabled)
                                    .toggleStyle(.switch)
                                    .tint(.orange)
                                    .labelsHidden()
                            }

                            if autoFanCurveEnabled {
                                Divider()
                                InteractiveFanCurveEditor(
                                    hasDiscreteGPU: !monitor.snapshot.gpuDevices.isEmpty
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(l10n.fanControl.fanCurvesSection)
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(nil)
                    } footer: {
                        Text(l10n.fanControl.dynamicCurvesFooter)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .onChange(of: autoFanCurveEnabled) { _, enabled in
                        if !enabled {
                            controller.resetFansToAutoSync()
                            controller.fanMappings = [:]
                        }
                    }

                    // MARK: - GPU Hardware Guide
                    Section {
                        GPUFanControlGuideView()
                            .padding(.vertical, 4)
                    } header: {
                        Text(l10n.fanControl.gpuHeader)
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .environment(\.defaultMinListRowHeight, 4)
        .onAppear {
            // AUDIT F-19: register as a panel client with the depth-counter API.
            // setMenuPanelNeeds(.none) unconditionally wiped the panel's needs,
            // silently stopping CPU/temp sampling for a detached menu panel until
            // it was reopened — the AMD/Sensors pages already use this API.
            SystemMonitor.shared.panelDidAppear()
            controller.startPolling()
        }
        .onDisappear {
            controller.stopPolling()
            SystemMonitor.shared.panelDidDisappear()
        }
    }
}

// MARK: - Fan Card Selection Helper

private enum FanCardModeSelection: Hashable {
    case auto
    case curve(Int)
    case manual
}

// MARK: - Fan Control Card

struct FanControlCard: View {
    let fan: FanState
    @ObservedObject var controller = FanCurveController.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    @State private var writeTask: Task<Void, Never>?

    private var currentCurveName: String {
        if let idx = fan.mappedCurveIndex, idx >= 0 && idx < controller.customCurves.count {
            return controller.customCurves[idx].name
        }
        return "Unknown"
    }

    private var currentModeSelection: FanCardModeSelection {
        switch fan.controlMode {
        case .auto:
            return .auto
        case .curve:
            return .curve(fan.mappedCurveIndex ?? 0)
        case .manual:
            return .manual
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // --- Top row: Icon, Editable Name, Live RPM · % · Hide Button ---
            HStack {
                Image(systemName: "fan")
                    .foregroundColor(.cyan)
                    .font(.system(size: 14))

                TextField("", text: Binding(
                    get: { fan.effectiveDisplayName },
                    set: { newVal in
                        controller.setCustomName(fanId: fan.id, name: newVal)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 150)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(fan.rpm) RPM")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", fan.pwmPercentage))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(fan.controlMode == .manual ? .orange : .secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Button(action: {
                        controller.setHidden(fanId: fan.id, hidden: true)
                    }) {
                        Image(systemName: "eye.slash")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(l10n.fanControl.hideFanTooltip)
                    .accessibilityLabel(l10n.fanControl.hideFanTooltip)
                }
            }

            // --- Control Mode Status Badge & Mode Picker ---
            HStack {
                switch fan.controlMode {
                case .auto:
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(l10n.fanControl.biosAutoBadge)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal.opacity(0.15))
                    .clipShape(Capsule())

                case .curve:
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: l10n.fanControl.curveBadgeFormat, currentCurveName))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())

                case .manual:
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: l10n.fanControl.manualBadgeFormat, "\(Int(fan.pwmPercentage))%"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()

                // Unified Mode Picker
                Picker("", selection: Binding(
                    get: { currentModeSelection },
                    set: { newSelection in
                        switch newSelection {
                        case .auto:
                            controller.setFanMode(fanId: fan.id, mode: .auto)
                        case .curve(let idx):
                            controller.setFanMode(fanId: fan.id, mode: .curve, curveIndex: idx)
                        case .manual:
                            controller.setFanMode(fanId: fan.id, mode: .manual, manualPWM: fan.throttlePWM)
                        }
                    }
                )) {
                    Text(l10n.fanControl.autoMode).tag(FanCardModeSelection.auto)
                    ForEach(0..<controller.customCurves.count, id: \.self) { idx in
                        Text(String(format: l10n.fanControl.curveBadgeFormat, controller.customCurves[idx].name))
                            .tag(FanCardModeSelection.curve(idx))
                    }
                    Text(l10n.fanControl.manualMode).tag(FanCardModeSelection.manual)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // --- Manual Override Slider & Reset Button (Visible ONLY in Manual Mode) ---
            if fan.controlMode == .manual {
                Divider()

                HStack(spacing: 12) {
                    Text(l10n.fanControl.manualSliderLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Slider(
                        value: Binding(
                            get: { sliderValue },
                            set: { newVal in
                                sliderValue = newVal
                                writeTask?.cancel()
                                writeTask = Task {
                                    try? await Task.sleep(nanoseconds: 60_000_000)
                                    guard !Task.isCancelled else { return }
                                    controller.setManualPWM(fanId: fan.id, pwm: UInt8(newVal))
                                }
                            }
                        ),
                        in: 0...255,
                        step: 1,
                        onEditingChanged: { editing in
                            isDraggingSlider = editing
                            if !editing {
                                writeTask?.cancel()
                                controller.setManualPWM(fanId: fan.id, pwm: UInt8(sliderValue))
                            }
                        }
                    )
                    .tint(.cyan)

                    Text(String(format: "%.0f%%", sliderValue / 255.0 * 100.0))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(width: 38, alignment: .trailing)
                }

                Button(action: {
                    controller.setFanMode(fanId: fan.id, mode: .auto)
                }) {
                    Text(l10n.fanControl.resetToAutoButton)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(fan.controlMode == .manual ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            sliderValue = Double(fan.throttlePWM)
        }
        .onChange(of: fan.throttlePWM) { _, newVal in
            // AUDIT F-22k fix: while a manual override is active, `throttlePWM`
            // IS the live duty we commanded — keep the slider glued to it even
            // when not dragging. The old `!= .manual` guard froze the slider at
            // the value from the moment manual mode was entered, so it stopped
            // tracking reality after any kext-side change (wake, SuperIO
            // re-probe, curve handoff). Only suppress tracking during an active
            // drag, where the user's in-flight value must not be overwritten.
            if !isDraggingSlider {
                sliderValue = Double(newVal)
            }
        }
    }
}

// MARK: - SMC Not Available View

struct SMCNotAvailableView: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(l10n.fanControl.smcUnavailableTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(l10n.fanControl.smcUnavailableBody)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - GPU Fan Control Guide View

struct GPUFanControlGuideView: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 16))
                Text(l10n.fanControl.gpuLimitationTitle)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(l10n.fanControl.gpuLimitationBody)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            Text(l10n.fanControl.gpuSpptTitle)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
            Text(l10n.fanControl.gpuSpptBody)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}

