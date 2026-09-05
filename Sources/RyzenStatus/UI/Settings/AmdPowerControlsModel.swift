// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation
import SwiftUI

/// Shared observable model for AMD Ryzen Power Controls.
/// Bridges and deduplicates state between the menu bar panel (`AmdControlSection`)
/// and the Settings window (`AmdPowerSettingsView`).
@MainActor
final class AmdPowerControlsModel: ObservableObject {
    static let shared = AmdPowerControlsModel()

    @Published var selectedEpp: UInt8 = 127
    @Published var cppcSupported: Bool = false
    @Published var cpbSupported: Bool = false
    @Published var legacyPstateAllowed: Bool = false
    @Published var selectedPState: Int = 0
    @Published var validPStateLabels: [String] = []

    @Published var corePerformanceBoost: Bool = true
    @Published var ppmEnabled: Bool = false
    @Published var lpmEnabled: Bool = false

    @Published var privilegeWarning: String?
    @Published var isLoading: Bool = false

    /// Guard flag: true when updating published properties from kext reads
    /// to avoid trigger loops from `.onChange` handlers.
    /// Writes arriving while a sync is in flight are intentionally dropped;
    /// the 3 s panel timer re-syncs and reconciles published state.
    private(set) var isSyncingFromKext: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Mirror UserDefaults on init
        self.corePerformanceBoost = UserDefaults.standard.object(forKey: DefaultsKey.amdCpbEnabled) as? Bool ?? true
        self.ppmEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.amdPpmEnabled)
        self.lpmEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.amdLpmEnabled)

        // Observe preset controller privilege messages reactively
        AmdPresetController.shared.$privilegeMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                if let msg = msg {
                    self?.privilegeWarning = msg
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func setEPP(_ value: UInt8) {
        guard !isSyncingFromKext else { return }
        selectedEpp = value
        Task {
            let res = await ProcessorModel.shared.setCPPCEPPValue(epp: value)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeWarning = "Root privileges required (-amdpnopchk) to set EPP."
            }
        }
    }

    func setCPB(_ enabled: Bool) {
        guard !isSyncingFromKext else { return }
        corePerformanceBoost = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.amdCpbEnabled)
        Task {
            let res = await ProcessorModel.shared.setCPB(enabled: enabled)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeWarning = "Root privileges required (-amdpnopchk) to change CPB."
            }
        }
    }

    func setPPM(_ enabled: Bool) {
        guard !isSyncingFromKext else { return }
        ppmEnabled = enabled
        if enabled { lpmEnabled = false }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.amdPpmEnabled)
        UserDefaults.standard.set(lpmEnabled, forKey: DefaultsKey.amdLpmEnabled)
        Task {
            let res = await ProcessorModel.shared.setPPM(enabled: enabled)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeWarning = "Root privileges required (-amdpnopchk) to change PPM."
            }
        }
    }

    func setLPM(_ enabled: Bool) {
        guard !isSyncingFromKext else { return }
        lpmEnabled = enabled
        if enabled { ppmEnabled = false }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.amdLpmEnabled)
        UserDefaults.standard.set(ppmEnabled, forKey: DefaultsKey.amdPpmEnabled)
        Task {
            let res = await ProcessorModel.shared.setLPM(enabled: enabled)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeWarning = "Root privileges required (-amdpnopchk) to change LPM."
            }
        }
    }

    func setPState(_ pstate: Int) {
        guard !isSyncingFromKext else { return }
        selectedPState = pstate
        Task {
            let res = await ProcessorModel.shared.setPState(state: pstate)
            if res == ProcessorModel.kIOReturnNotPrivilegedCode {
                self.privilegeWarning = "Root privileges required (-amdpnopchk) to lock P-State."
            }
        }
    }

    func clearPrivilegeWarning() {
        privilegeWarning = nil
    }

    // MARK: - State Sync

    // AUDIT F-28: move blocking kext IPC off MainActor
    func syncFromKext() async {
        guard !isSyncingFromKext else { return }
        isSyncingFromKext = true
        defer { isSyncingFromKext = false }

        let (kernelAnswered, cpb, cppcState, ppm, lpm) = await Task.detached(priority: .userInitiated) {
            // AUDIT F-27: thread-safe connection check to avoid data races
            let kernelAnswered = ProcessorModel.shared.isConnected
            let cpb = ProcessorModel.shared.getCPB()
            let cppcState: (active: Bool, epp: UInt8) = kernelAnswered
                ? ProcessorModel.shared.getCPPCActiveMode()
                : (active: false, epp: 0)
            let ppm = kernelAnswered ? ProcessorModel.shared.getPPM() : false
            let lpm = kernelAnswered ? ProcessorModel.shared.getLPM() : false
            return (kernelAnswered, cpb, cppcState, ppm, lpm)
        }.value
        let profile = await ProcessorModel.shared.cpuProfile

        cppcSupported = kernelAnswered
        legacyPstateAllowed = profile.legacyPstateAllowed

        let target = AMDPowerPreset.snapEPP(cppcState.epp)
        if selectedEpp != target { selectedEpp = target }

        if kernelAnswered {
            if ppmEnabled != ppm { ppmEnabled = ppm }
            if lpmEnabled != lpm { lpmEnabled = lpm }
        }

        if cpb.count > 1 {
            cpbSupported = cpb[0]
            if corePerformanceBoost != cpb[1] { corePerformanceBoost = cpb[1] }
        }

        if profile.legacyPstateAllowed {
            let currentPState = await ProcessorModel.shared.getPState()
            if selectedPState != currentPState { selectedPState = currentPState }
            if validPStateLabels.isEmpty {
                let clocks = await ProcessorModel.shared.getValidPStateClocks()
                validPStateLabels = clocks.enumerated().map { index, clock in
                    String(format: "P%d (%.1f GHz)", index, Double(clock) / 1000.0)
                }
            }
        }
    }
}
