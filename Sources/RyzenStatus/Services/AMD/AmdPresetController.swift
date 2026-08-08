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

        let result = ProcessorModel.shared.applyPowerPreset(preset)
        AmdSettingsStore.shared.amdPowerPreset = preset.rawValue
        selectedPreset = preset

        if result.privilegeDenied {
            privilegeMessage = result.firstFailureMessage
                ?? "Requires admin privileges (-amdpnopchk)."
        } else {
            privilegeMessage = nil
        }
    }

    /// Clears any stale privilege warning (called after the user dismisses it).
    func clearPrivilegeMessage() {
        privilegeMessage = nil
    }
}
