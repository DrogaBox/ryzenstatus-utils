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
        UserDefaults.standard.bool(forKey: DefaultsKey.gamingModeHideMenuBar)
    }

    private var keepAwakeWasActive = false
    private var autoEppWasActive = false
    private var restoredPreset: AMDPowerPreset = .balance

    private let activeKey = DefaultsKey.gamingModeActive
    private let presetKey = DefaultsKey.amdPowerPreset
    /// Persisted snapshot of the Auto EPP preference taken at activation, so a
    /// relaunch while the mode is active can still restore it on deactivation
    /// (setCPPCActive flips the live `autoEppEnabled` key).
    private let restoreAutoEppKey = DefaultsKey.gamingModeRestoreAutoEpp

    private init() {}

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !isActive else { return }

        // Remember the current profile so deactivate() can put it back.
        if let raw = UserDefaults.standard.string(forKey: presetKey),
           let preset = AMDPowerPreset(rawValue: raw) {
            restoredPreset = preset
        } else {
            restoredPreset = .balance
        }

        keepAwakeWasActive = KeepAwakeManager.shared.isActive
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.activate(minutes: 0)
        }

        // The preset owns the EPP profile: stop Auto EPP so its next poll
        // cycle cannot overwrite the Extreme value (same guard as the presets UI).
        // Snapshot the original preference BEFORE the flip, and persist it:
        // setCPPCActive(false) writes `autoEppEnabled` to UserDefaults, so the
        // in-memory flag alone would read wrong after a relaunch.
        autoEppWasActive = UserDefaults.standard.bool(forKey: DefaultsKey.autoEppEnabled)
        UserDefaults.standard.set(autoEppWasActive, forKey: restoreAutoEppKey)
        if autoEppWasActive {
            AutoEppService.shared.setCPPCActive(false)
        }

        let result = ProcessorModel.shared.applyPowerPreset(.extreme)
        UserDefaults.standard.set(true, forKey: activeKey)
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

        let restore = ProcessorModel.shared.applyPowerPreset(restoredPreset)
        if restore.privilegeDenied {
            statusMessage = restore.firstFailureMessage
                ?? "Could not restore your previous profile (privilege)."
            statusIsError = true
        } else {
            statusMessage = nil
        }
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.deactivate(reason: .manual)
        }
        if autoEppWasActive {
            AutoEppService.shared.setCPPCActive(true)
        }
        // The snapshot has served its purpose (restore decided above); drop it
        // so the next activation snapshots fresh state.
        UserDefaults.standard.removeObject(forKey: restoreAutoEppKey)
        StatusItemController.shared?.setForceHidden(false)
        UserDefaults.standard.set(false, forKey: activeKey)
        isActive = false
    }

    /// Re-applies a persisted Gaming Mode on launch (same pattern as Keep
    /// Awake's auto-start): Extreme preset, indefinite Keep Awake and the
    /// hidden icon. Safe to call early in `applicationDidFinishLaunching`.
    func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: activeKey), !isActive else { return }
        keepAwakeWasActive = KeepAwakeManager.shared.isActive
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.activate(minutes: 0)
        }
        // The snapshot taken at activation survives the relaunch even though
        // setCPPCActive(false) flipped the live preference key; reading it
        // restores the user's original Auto EPP choice on deactivation.
        autoEppWasActive = UserDefaults.standard.bool(forKey: restoreAutoEppKey)
        if autoEppWasActive {
            AutoEppService.shared.setCPPCActive(false)
        }
        _ = ProcessorModel.shared.applyPowerPreset(.extreme)
        if hideMenuBar {
            StatusItemController.shared?.setForceHidden(true)
        }
        isActive = true
    }
}
