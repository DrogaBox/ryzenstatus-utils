// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The mouse features ported from upstream, as grouped-form sections that sit
/// inside the Mouse page next to the local ones: sideways scrolling with a
/// held key, focus follows mouse, linear scrolling, mouse acceleration and
/// the click filter. Each section only shows while its feature is installed
/// in the hub, and every switch starts off.
struct MouseExtrasSections: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.scrollHorizontalEnabled) private var horizontalScrollEnabled = false
    @AppStorage(DefaultsKey.scrollHorizontalModifier) private var horizontalScrollModifier =
        ScrollHorizontalModifier.shift.rawValue
    @AppStorage(DefaultsKey.focusFollowsMouseEnabled) private var focusFollowsMouseEnabled = false
    @AppStorage(DefaultsKey.focusFollowsMouseRaise) private var focusFollowsMouseRaise = true
    @AppStorage(DefaultsKey.focusFollowsMouseWaitForStop) private var focusFollowsMouseWaitForStop = true
    @AppStorage(DefaultsKey.focusFollowsMouseDelay) private var focusFollowsMouseDelay =
        FocusFollowsMouseSupport.defaultDelayMilliseconds
    @AppStorage(DefaultsKey.linearScrollEnabled) private var linearScrollEnabled = false
    @AppStorage(DefaultsKey.linearScrollLines) private var linearScrollLines =
        ScrollWheelSupport.defaultLinesPerNotch
    @AppStorage(DefaultsKey.mouseAccelerationDisabled) private var mouseAccelerationDisabled = false
    @AppStorage(DefaultsKey.mouseClickDebounceEnabled) private var mouseClickDebounceEnabled = false
    @AppStorage(DefaultsKey.mouseClickDebounceWindowMs) private var mouseClickDebounceWindow =
        Defaults.defaultMouseClickDebounceWindowMs

    private var extras: MouseExtrasStrings { FeatureStrings.mouseExtras(l10n.language) }
    private var clickDebounce: MouseClickDebounceStrings { FeatureStrings.mouseClickDebounce(l10n.language) }

    var body: some View {
        if AppFeature.scrollHorizontal.isAvailable {
            Section(l10n.s.scrollHorizontalName) {
                Toggle(l10n.s.scrollHorizontalName, isOn: $horizontalScrollEnabled)
                    .onChange(of: horizontalScrollEnabled) { _, enabled in
                        syncWheelTaps()
                        if enabled { permissions.requestAccessibility() }
                    }
                Text(l10n.s.scrollHorizontalCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if horizontalScrollEnabled {
                    Picker(l10n.s.scrollHorizontalModifierLabel, selection: $horizontalScrollModifier) {
                        Text("⇧ \(extras.shiftKey)").tag(ScrollHorizontalModifier.shift.rawValue)
                        Text("⌥ \(extras.optionKey)").tag(ScrollHorizontalModifier.option.rawValue)
                        Text("⌃ \(extras.controlKey)").tag(ScrollHorizontalModifier.control.rawValue)
                        Text("⌘ \(extras.commandKey)").tag(ScrollHorizontalModifier.command.rawValue)
                    }
                    .onChange(of: horizontalScrollModifier) { _, _ in syncWheelTaps() }
                    MouseExceptionsList(scope: .scrollDirection)
                }
            }
        }
        if AppFeature.focusFollowsMouse.isAvailable {
            Section(l10n.s.focusFollowsMouseName) {
                Toggle(l10n.s.focusFollowsMouseName, isOn: $focusFollowsMouseEnabled)
                    .onChange(of: focusFollowsMouseEnabled) { _, enabled in
                        FocusFollowsMouseService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
                Text(l10n.s.focusFollowsMouseCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if focusFollowsMouseEnabled {
                    sliderRow(l10n.s.focusFollowsMouseDelay,
                              value: focusFollowsMouseDelayBinding,
                              range: Double(FocusFollowsMouseSupport.delayRange.lowerBound)
                                  ... Double(FocusFollowsMouseSupport.delayRange.upperBound),
                              step: 50,
                              readout: "\(FocusFollowsMouseSupport.sanitizedDelay(focusFollowsMouseDelay)) ms")
                    Toggle(l10n.s.focusFollowsMouseRaise, isOn: $focusFollowsMouseRaise)
                        .onChange(of: focusFollowsMouseRaise) { _, _ in
                            FocusFollowsMouseService.shared.preferencesDidChange()
                        }
                    if !focusFollowsMouseRaise {
                        Toggle(l10n.s.focusFollowsMouseWaitForStop, isOn: $focusFollowsMouseWaitForStop)
                            .onChange(of: focusFollowsMouseWaitForStop) { _, _ in
                                FocusFollowsMouseService.shared.preferencesDidChange()
                            }
                    }
                    MouseExceptionsList(scope: .focusFollowsMouse)
                }
            }
        }
        if AppFeature.linearScroll.isAvailable {
            Section(l10n.s.linearScrollName) {
                Toggle(l10n.s.linearScrollName, isOn: $linearScrollEnabled)
                    .onChange(of: linearScrollEnabled) { _, enabled in
                        syncWheelTaps()
                        if enabled { permissions.requestAccessibility() }
                    }
                Text(l10n.s.linearScrollCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if linearScrollEnabled {
                    sliderRow(l10n.s.linearScrollLinesLabel,
                              value: linearScrollLinesBinding,
                              range: Double(ScrollWheelSupport.linesPerNotchRange.lowerBound)
                                  ... Double(ScrollWheelSupport.linesPerNotchRange.upperBound),
                              step: 1,
                              readout: "\(ScrollWheelSupport.sanitizedLinesPerNotch(linearScrollLines))")
                    MouseExceptionsList(scope: .linearScroll)
                }
            }
        }
        if AppFeature.mouseAcceleration.isAvailable {
            Section(l10n.s.mouseAccelerationName) {
                Toggle(l10n.s.mouseAccelerationName, isOn: $mouseAccelerationDisabled)
                    .onChange(of: mouseAccelerationDisabled) { _, _ in
                        MouseAccelerationService.shared.syncWithPreferences()
                    }
                Text(l10n.s.mouseAccelerationCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if AppFeature.mouseClickDebounce.isAvailable {
            Section(clickDebounce.title) {
                Toggle(clickDebounce.title, isOn: $mouseClickDebounceEnabled)
                    .onChange(of: mouseClickDebounceEnabled) { _, enabled in
                        MouseClickDebounceService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
                Text(clickDebounce.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if mouseClickDebounceEnabled {
                    Stepper(value: mouseClickDebounceWindowBinding,
                            in: Defaults.allowedMouseClickDebounceWindowRange,
                            step: 1) {
                        HStack {
                            Text(clickDebounce.windowLabel)
                            Spacer()
                            Text("\(Defaults.sanitizedMouseClickDebounceWindow(mouseClickDebounceWindow)) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(clickDebounce.windowCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Whether one of these features is on and installed, so the page's
    /// shared Accessibility note covers them too.
    static func needsAccessibility(defaults: UserDefaults = .standard) -> Bool {
        let engaged: [(AppFeature, String)] = [
            (.scrollHorizontal, DefaultsKey.scrollHorizontalEnabled),
            (.focusFollowsMouse, DefaultsKey.focusFollowsMouseEnabled),
            (.linearScroll, DefaultsKey.linearScrollEnabled),
            (.mouseClickDebounce, DefaultsKey.mouseClickDebounceEnabled),
        ]
        return engaged.contains { feature, key in
            feature.isAvailable(in: defaults) && defaults.bool(forKey: key)
        }
    }

    /// Sideways and linear scrolling ride the inverter's wheel tap, and the
    /// glide applies them while smooth scrolling swallows the wheel.
    private func syncWheelTaps() {
        ScrollInverter.shared.syncWithPreferences()
        if AppFeature.smoothScroll.isAvailable {
            SmoothScrollService.shared.syncWithPreferences()
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, readout: String) -> some View {
        HStack {
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var linearScrollLinesBinding: Binding<Double> {
        Binding(
            get: { Double(ScrollWheelSupport.sanitizedLinesPerNotch(linearScrollLines)) },
            set: { linearScrollLines = Int($0) }
        )
    }

    private var focusFollowsMouseDelayBinding: Binding<Double> {
        Binding(
            get: { Double(FocusFollowsMouseSupport.sanitizedDelay(focusFollowsMouseDelay)) },
            set: {
                focusFollowsMouseDelay = Int($0)
                FocusFollowsMouseService.shared.preferencesDidChange()
            }
        )
    }

    private var mouseClickDebounceWindowBinding: Binding<Int> {
        Binding(
            get: { Defaults.sanitizedMouseClickDebounceWindow(mouseClickDebounceWindow) },
            set: {
                mouseClickDebounceWindow = Defaults.sanitizedMouseClickDebounceWindow($0)
                MouseClickDebounceService.shared.syncWithPreferences()
            }
        )
    }
}

/// Keeping Spaces in a fixed order, as a section on the Switcher & Dock page.
struct SpacesOrderSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.spacesOrderEnabled) private var spacesOrderEnabled = false

    var body: some View {
        if AppFeature.spacesOrder.isAvailable {
            Section(l10n.s.spacesOrderName) {
                Toggle(l10n.s.spacesOrderName, isOn: $spacesOrderEnabled)
                    .onChange(of: spacesOrderEnabled) { _, _ in
                        SpacesOrderHold.shared.syncWithPreferences()
                    }
                Text(l10n.s.spacesOrderCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
