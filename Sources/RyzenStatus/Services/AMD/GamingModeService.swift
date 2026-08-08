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

    /// In-flight activation transaction. deactivate() must wait for it before
    /// deciding what to restore: activate() publishes isActive synchronously
    /// but the key write + kext write happen in a Task, so a fast toggle-off
    /// could otherwise read the pre-activation key, skip the restore, and let
    /// the late transaction leave the kext on Extreme with the mode off.
    private var activationTask: Task<Void, Never>?
    /// Bumped whenever a new activate()/deactivate() supersedes a pending
    /// activation, so a stale task cannot publish its status afterwards.
    private var activationGeneration = 0

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
        // NOTE: do NOT go through AmdPresetController.apply(_:) here — it calls
        // setCPPCActive(false) when Auto EPP is on, which would permanently
        // write autoEppEnabled=false to UserDefaults.
        AutoEppService.shared.suspend()

        AmdSettingsStore.shared.gamingModeActive = true
        isActive = true

        if hideMenuBar {
            StatusItemController.shared?.setForceHidden(true)
        }

        // Track the in-flight transaction so deactivate() can wait for it
        // before deciding what to restore (see activationTask).
        let generation = activationGeneration + 1
        activationGeneration = generation
        activationTask = Task { [weak self] in
            guard let self else { return }
            // Transactional: the key is written before the kext write and rolled
            // back on privilege denial, so the persisted key always names what
            // the kext actually applied.
            let result = await AmdPresetController.shared.withPresetTransaction(.extreme) { preset in
                await ProcessorModel.shared.applyPowerPreset(preset)
            }
            // A newer activate()/deactivate() superseded this one — do not
            // publish status from a stale activation.
            guard self.activationGeneration == generation else { return }
            self.activationTask = nil
            if result.privilegeDenied {
                self.statusMessage = result.firstFailureMessage
                    ?? "The power preset needs root or -amdpnopchk; Keep Awake and the hidden icon are still active."
                self.statusIsError = true
            } else {
                self.statusMessage = "Extreme preset, Keep Awake and hidden icon active."
                self.statusIsError = false
            }
        }
    }

    func deactivate() {
        // Toggling off while an activation is still in flight must wait for
        // that transaction to settle: activate() publishes isActive
        // synchronously but the key write + kext write happen in a Task, so a
        // fast toggle-off could otherwise read the pre-activation key, skip
        // the restore, and let the late transaction leave the kext on Extreme
        // with the mode off. The pending task is awaited below and its stale
        // status is suppressed via the generation counter.
        guard isActive || activationTask != nil else { return }

        // Flip the user-visible off state synchronously (toggle, persistence,
        // icon, Keep Awake) so the UI reacts instantly even while the kext
        // settles. Keep Awake teardown MUST be synchronous, not deferred into
        // the awaited finishDeactivation: if the user re-activates during the
        // await, the new activation would snapshot keepAwakeWasActive = true
        // (this session still running) and never end it — a leak.
        isActive = false
        AmdSettingsStore.shared.gamingModeActive = false
        StatusItemController.shared?.setForceHidden(false)
        if !keepAwakeWasActive {
            KeepAwakeManager.shared.deactivate(reason: .manual)
        }

        let generation = activationGeneration + 1
        activationGeneration = generation
        let pending = activationTask
        activationTask = nil

        if let pending {
            Task { [weak self] in
                guard let self else { return }
                _ = await pending.value
                self.finishDeactivation(generation: generation)
            }
        } else {
            finishDeactivation(generation: generation)
        }
    }

    /// Shared teardown: restore the pre-gaming preset if Extreme is still
    /// what the kext has applied, end the Keep Awake session, show the icon.
    ///
    /// `generation` guards against a re-activation racing this teardown: if
    /// the user toggled on again while we were restoring, the new activation
    /// owns the preset and this must not restore over it.
    private func finishDeactivation(generation: Int) {
        guard activationGeneration == generation, !isActive else { return }

        // The presets section stays live during the mode: if the user picked a
        // different preset manually, that choice wins over the pre-gaming
        // profile and is left applied (only a preset that is still Extreme is
        // one this mode applied).
        let currentPreset = AmdSettingsStore.shared.amdPowerPreset
            .flatMap(AMDPowerPreset.init(rawValue:)) ?? .balance
        let shouldRestorePreset = currentPreset == .extreme

        if shouldRestorePreset {
            Task {
                // A newer activation may have started while this restore was
                // queued — do not clobber its Extreme with the old profile.
                guard self.activationGeneration == generation, !self.isActive else { return }
                let restore = await AmdPresetController.shared.withPresetTransaction(self.restoredPreset) { preset in
                    await ProcessorModel.shared.applyPowerPreset(preset)
                }
                guard self.activationGeneration == generation, !self.isActive else { return }
                if restore.privilegeDenied {
                    self.statusMessage = restore.firstFailureMessage
                        ?? "Could not restore your previous profile (privilege)."
                    self.statusIsError = true
                } else {
                    self.statusMessage = nil
                }
                // Resume Auto EPP only after the restored preset lands, so its
                // first poll cycle cannot overwrite the restored EPP mid-apply.
                AutoEppService.shared.resume()
            }
        } else {
            statusMessage = nil
            // No preset to restore — Auto EPP is safe to resume right away.
            AutoEppService.shared.resume()
        }
        // Keep Awake teardown, icon and flags are handled synchronously in
        // deactivate(); only the preset restore + Auto EPP resume are deferred.
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
        isActive = true
        if hideMenuBar {
            StatusItemController.shared?.setForceHidden(true)
        }
        
        Task {
            let result = await AmdPresetController.shared.withPresetTransaction(.extreme) { preset in
                await ProcessorModel.shared.applyPowerPreset(preset)
            }
            if result.privilegeDenied {
                // Surfaces in Settings while the mode stays active, so a launch
                // that could not re-apply the profile is not silent.
                self.statusMessage = result.firstFailureMessage
                    ?? "Could not re-apply the Extreme preset on launch; Keep Awake and the hidden icon are still active."
                self.statusIsError = true
            } else {
                self.statusMessage = nil
            }
        }
    }
}
