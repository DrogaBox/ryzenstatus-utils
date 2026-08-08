// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// One-click gaming profile: the Extreme power preset (EPP 0 via selectors
/// 25/12/14/19), an indefinite Keep Awake session and a hidden menu bar icon.
/// Turning the mode off restores the previous preset, ends the Keep Awake
/// session it started and shows the icon again.
///
/// The mode persists across launches (`DefaultsKey.gamingModeActive`) and is
/// re-applied on startup; the Settings window stays reachable by relaunching
/// the app, which falls back to `openSettingsWindow()` when the icon is hidden.
@MainActor
final class GamingModeService: ObservableObject {
    static let shared = GamingModeService()

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false

    /// Whether the mode hides the menu bar icon (default on).
    var hideMenuBar: Bool {
        AmdSettingsStore.shared.gamingModeHideMenuBar
    }

    private var keepAwakeWasActive = false
    private var restoredPreset: AMDPowerPreset = .balance

    private let activeKey = DefaultsKey.gamingModeActive
    private let presetKey = DefaultsKey.amdPowerPreset
    // restoreAutoEppKey removed: AutoEppService.suspend()/resume() make the
    // snapshot-in-UserDefaults pattern unnecessary and race-free.

    private init() {}

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !isActive else { return }

        // Remember the current profile so deactivate() can put it back.
        if let raw = AmdSettingsStore.shared.amdPowerPreset,
           let preset = AMDPowerPreset(rawValue: raw) {
            restoredPreset = preset
        } else {
            restoredPreset = .balance
        }

        keepAwakeWasActive = KeepAwakeManager.shared.isActive
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.activate(minutes: 0)
        }

        // Suspend Auto EPP poll loop so it cannot overwrite the Extreme preset
        // value during Gaming Mode. suspend() is idempotent and does not touch
        // UserDefaults, so the user's Auto EPP preference is preserved.
        AutoEppService.shared.suspend()

        let result = ProcessorModel.shared.applyPowerPreset(.extreme)
        // Mirror the presets UI: the key always names what is actually applied,
        // so deactivate() can tell a mid-mode manual preset change apart from
        // the untouched Extreme this mode applied.
        AmdPresetController.shared.apply(.extreme)
        AmdSettingsStore.shared.gamingModeActive = true
        isActive = true

        if hideMenuBar {
            StatusItemController.shared?.setForceHidden(true)
        }

        if result.privilegeDenied {
            statusMessage = result.firstFailureMessage
                ?? "The power preset needs root or -amdpnopchk; Keep Awake and the hidden icon are still active."
            statusIsError = true
        } else {
            statusMessage = "Extreme preset, Keep Awake and hidden icon active."
            statusIsError = false
        }
    }

    func deactivate() {
        guard isActive else { return }

        // The presets section stays live during the mode: if the user picked a
        // different preset manually, that choice wins over the pre-gaming
        // profile and is left applied (only a preset that is still Extreme is
        // one this mode applied).
        let currentPreset = AmdSettingsStore.shared.amdPowerPreset
            .flatMap(AMDPowerPreset.init(rawValue:)) ?? .balance
        let shouldRestorePreset = currentPreset == .extreme

        if shouldRestorePreset {
            let restore = ProcessorModel.shared.applyPowerPreset(restoredPreset)
            if restore.privilegeDenied {
                statusMessage = restore.firstFailureMessage
                    ?? "Could not restore your previous profile (privilege)."
                statusIsError = true
            } else {
                statusMessage = nil
            }
            AmdSettingsStore.shared.amdPowerPreset = restoredPreset.rawValue
        } else {
            statusMessage = nil
        }
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.deactivate(reason: .manual)
        }
        // Resume Auto EPP poll loop if the user had it enabled.
        // resume() checks UserDefaults.autoEppEnabled internally and is a no-op
        // if the user explicitly disabled it during Gaming Mode.
        AutoEppService.shared.resume()
        StatusItemController.shared?.setForceHidden(false)
        AmdSettingsStore.shared.gamingModeActive = false
        isActive = false
    }

    /// Re-applies a persisted Gaming Mode on launch (same pattern as Keep
    /// Awake's auto-start): Extreme preset, indefinite Keep Awake and the
    /// hidden icon. Safe to call early in `applicationDidFinishLaunching`.
    func restoreIfNeeded() {
        guard AmdSettingsStore.shared.gamingModeActive, !isActive else { return }
        keepAwakeWasActive = KeepAwakeManager.shared.isActive
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.activate(minutes: 0)
        }
        // Suspend Auto EPP on relaunch just like on initial activation.
        AutoEppService.shared.suspend()
        let result = ProcessorModel.shared.applyPowerPreset(.extreme)
        if result.privilegeDenied {
            // Surfaces in Settings while the mode stays active, so a launch
            // that could not re-apply the profile is not silent.
            statusMessage = result.firstFailureMessage
                ?? "Could not re-apply the Extreme preset on launch; Keep Awake and the hidden icon are still active."
            statusIsError = true
        } else {
            statusMessage = nil
        }
        if hideMenuBar {
            StatusItemController.shared?.setForceHidden(true)
        }
        isActive = true
    }
}
