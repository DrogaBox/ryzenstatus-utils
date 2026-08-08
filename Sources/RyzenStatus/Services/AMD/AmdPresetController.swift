// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import SwiftUI

/// Single source of truth for applying AMD power presets.
///
/// Both `AmdPowerSettingsView` (Settings) and `AmdControlSection` (menu panel)
/// previously duplicated `applyPreset(_:)` + `presetColor(_:)` + `snapEPP` +
/// `selectedPreset` state. This controller owns all of that so each view just
/// calls `controller.apply(_:)` and observes `controller.selectedPreset`.
///
/// - Note: `@MainActor` because all IOKit writes go through `ProcessorModel`
///   which must be called on the main actor for the `nonisolated` methods and
///   because the published state drives SwiftUI views.
@MainActor
final class AmdPresetController: ObservableObject {

    // MARK: - Shared singleton

    static let shared = AmdPresetController()

    // MARK: - Published state (observed by both views)

    /// The preset currently applied (nil = none applied yet this session).
    @Published private(set) var selectedPreset: AMDPowerPreset? = AMDPowerPreset.saved()

    /// Non-nil when the last `apply` was denied by the kext (no root / no -amdpnopchk).
    @Published private(set) var privilegeMessage: String?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    /// Tail of the preset-transaction queue. Every `withPresetTransaction`
    /// chains behind the previous one so the key write + kext write + rollback
    /// of one preset never interleaves with another — otherwise a restore and
    /// a new activation running in separate Tasks could leave the persisted
    /// key and the kext on different presets (FIFO: last queued wins).
    private var presetQueueTail: Task<AMDPowerPresetApplyResult, Never>?
    /// Monotonic sequence for the tail bookkeeping — `Task` is a struct, so
    /// identity is tracked by sequence number instead of `===`.
    private var presetQueueSequence = 0

    private init() {
        // Keep selectedPreset in sync whenever Gaming Mode toggles the kext
        // preset. The Gaming Mode service writes to DefaultsKey.amdPowerPreset
        // directly, so observing the publisher that GamingModeService updates
        // (isActive) is the correct hook.
        GamingModeService.shared.$isActive
            .sink { [weak self] _ in
                self?.selectedPreset = AMDPowerPreset.saved() ?? self?.selectedPreset
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Applies `preset` to the kext: stops Auto EPP if active, writes EPP/CPB/PPM/LPM,
    /// persists the choice, and surfaces privilege errors.
    ///
    /// Called from both `AmdPowerSettingsView.presetCard` and `AmdControlSection.presetButton`.
    func apply(_ preset: AMDPowerPreset) {
        // A preset owns the EPP profile: stop Auto EPP so its next poll cycle
        // cannot overwrite the preset's value (P2-fix: also resets lastWrittenEPP
        // sentinel, so the first Auto EPP write after re-enabling goes through).
        if AutoEppService.shared.isActive {
            AutoEppService.shared.setCPPCActive(false)
        }

        Task {
            await withPresetTransaction(preset) { preset in
                await ProcessorModel.shared.applyPowerPreset(preset)
            }
        }
    }

    /// Applies a preset transactionally: the persisted `amdPowerPreset` key is
    /// written *before* the kext is touched, so a crash between the kext write
    /// and `UserDefaults.set` can never leave hardware and UI out of sync.
    /// If the kext denies the write (`kIOReturnNotPrivileged`), the key is
    /// rolled back to its previous value so the UI never advertises a preset
    /// the kext rejected.
    ///
    /// Internal so `GamingModeService` can reuse it for its activate/deactivate/
    /// restoreIfNeeded paths (it does NOT touch Auto EPP — callers that need
    /// that behavior use `apply(_:)` instead).
    ///
    /// All transactions are serialized FIFO through `presetQueueTail`, so a
    /// restore and a concurrent activation can never interleave their key
    /// write / kext write / rollback steps. The kext apply itself runs even if
    /// the controller has been released; only the published state needs `self`.
    ///
    /// - Warning: do NOT call this re-entrantly from inside `apply` — the
    ///   chain tasks await each other's values on the MainActor, so a nested
    ///   transaction would deadlock.
    @discardableResult
    func withPresetTransaction(
        _ preset: AMDPowerPreset,
        apply: @escaping (AMDPowerPreset) async -> AMDPowerPresetApplyResult
    ) async -> AMDPowerPresetApplyResult {
        let previous = presetQueueTail
        let sequence = presetQueueSequence
        presetQueueSequence += 1
        let task = Task { [weak self] () -> AMDPowerPresetApplyResult in
            // Wait for the previous transaction to fully settle (key + kext)
            // before starting this one — this is the serialization point.
            _ = await previous?.value

            let previousKey = AmdSettingsStore.shared.amdPowerPreset
            AmdSettingsStore.shared.amdPowerPreset = preset.rawValue
            self?.selectedPreset = preset

            let result = await apply(preset)

            if result.privilegeDenied {
                // Roll back: the kext never accepted the preset, so the
                // persisted key must not claim it did. Keep the error visible.
                AmdSettingsStore.shared.amdPowerPreset = previousKey
                self?.selectedPreset = previousKey.flatMap(AMDPowerPreset.init(rawValue:))
                self?.privilegeMessage = result.firstFailureMessage
                    ?? "Requires admin privileges (-amdpnopchk)."
            } else {
                self?.privilegeMessage = nil
            }
            return result
        }
        presetQueueTail = task
        let result = await task.value
        // Release the completed tail only when no newer transaction was queued
        // while this one ran (a newer transaction replaced `presetQueueTail`,
        // so the chain must keep pointing at it).
        if presetQueueSequence == sequence + 1 { presetQueueTail = nil }
        return result
    }

    /// Clears any stale privilege warning (called after the user dismisses it).
    func clearPrivilegeMessage() {
        privilegeMessage = nil
    }
}
