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

    // S2-T2: rolling history for the AMD panel sparklines — 60 samples ≈ 3 min
    // at the 3 s panel poll. Sampled inside syncFromKext, so no new timers.
    @Published private(set) var packagePowerHistory: [Double] = []
    @Published private(set) var packageTempHistory: [Double] = []
    private static let historyCapacity = 60

    // S5: SMU boost telemetry (selector 43) — refreshed inside syncFromKext's
    // detached kext batch. `fastestCoreIndex` is nil while the kext cache is
    // cold or the raw 0x59 word does not decode; `fastestCoreRaw` then carries
    // the undecoded word for display.
    @Published private(set) var maxBoostFreqMHz: UInt32 = 0
    @Published private(set) var fastestCoreIndex: Int?
    @Published private(set) var fastestCoreRaw: UInt32 = 0

    // S6: ProcessorParameters (0x6F) + cHTC limit cache — refreshed inside
    // syncFromKext's detached kext batch alongside the S5 telemetry.
    // `procParamsPolled` is false until the kext timer's one-shot 0x6F read
    // has succeeded this boot; `chtcLimitCelsius` stays nil until a write
    // succeeds (or the kext reports a cache from an earlier write).
    @Published private(set) var procParamsRaw: UInt32 = 0
    @Published private(set) var procParamsPolled = false
    @Published private(set) var chtcLimitCelsius: Int?

    // S7: SMU firmware version (0x02, one-shot) + active PBO scalar (0x6C,
    // rides the boost throttle) — refreshed inside syncFromKext's detached
    // kext batch. `smuVersionPolled` distinguishes "not read yet" from a
    // cached answer; `activeScalarRaw` stays 0 until the timer succeeds.
    @Published private(set) var smuVersionRaw: UInt32 = 0
    @Published private(set) var smuVersionPolled = false
    @Published private(set) var activeScalarRaw: UInt32 = 0

    // S8: OC capability + mode cache (selectors 49/50). `ocModeCode` mirrors
    // the kext's cache: 0 = this driver never touched OC mode this boot
    // (honestly unknown), 1 = enabled via 0x5A, 2 = disabled via 0x5B.
    @Published private(set) var ocSupported = false
    @Published private(set) var ocModeCode: UInt64 = 0

    // S8.2: frequency-override support flag (selector 49 [3], promoted from
    // reserved-0 in 1.28.0) + selector-52 cache. 0 MHz slots mean "never
    // written by this driver this boot" — never fabricated state.
    @Published private(set) var ocFreqSupported = false
    @Published private(set) var ocFreqAllCoresMHz: UInt32 = 0
    @Published private(set) var ocFreqPerCcdMHz: [UInt32] = []
    @Published private(set) var kextCcdCount: Int = 0

    // S9a: PM-table plumbing snapshot info (selector 56). All diagnostic —
    // `pmTableValid` is false until the timer's first successful capture.
    @Published private(set) var pmTableVersionRaw: UInt32 = 0
    @Published private(set) var pmTableVersionPolled = false
    @Published private(set) var pmTableSizeBytes: UInt32 = 0
    @Published private(set) var pmTableBase: UInt64 = 0
    @Published private(set) var pmTableValid = false
    @Published private(set) var pmTableAgeMs: UInt64 = 0

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

        recordTelemetrySample()

        let (kernelAnswered, cpb, cppcState, ppm, lpm, boost, procParams, chtcLimit,
             smuVersion, activeScalar, ocCap, ocFreq, pmInfo) = await Task.detached(priority: .userInitiated) {
            // AUDIT F-27: thread-safe connection check to avoid data races
            let kernelAnswered = ProcessorModel.shared.isConnected
            let cpb = ProcessorModel.shared.getCPB()
            let cppcState: (active: Bool, epp: UInt8) = kernelAnswered
                ? ProcessorModel.shared.getCPPCActiveMode()
                : (active: false, epp: 0)
            let ppm = kernelAnswered ? ProcessorModel.shared.getPPM() : false
            let lpm = kernelAnswered ? ProcessorModel.shared.getLPM() : false
            // S5: cached boost telemetry — the kext call never touches the SMU,
            // it only reads the timer-populated cache.
            let boost = kernelAnswered ? ProcessorModel.shared.getBoostTelemetry() : nil
            // S6: one-shot 0x6F bitfield + cHTC cache, same off-the-SMU policy.
            let procParams = kernelAnswered ? ProcessorModel.shared.getProcessorParameters() : nil
            let chtcLimit = kernelAnswered ? ProcessorModel.shared.getCHTCLimit() : nil
            // S7: one-shot 0x02 version + 0x6C active scalar readbacks.
            let smuVersion = kernelAnswered ? ProcessorModel.shared.getSmuVersion() : nil
            let activeScalar = kernelAnswered ? ProcessorModel.shared.getActivePBOScalar() : nil
            // S8: OC capability + mode cache (no SMU traffic — cache only).
            let ocCap = kernelAnswered ? ProcessorModel.shared.getOcCapability() : nil
            // S8.2: frequency-override cache (cache only, no SMU traffic).
            let ocFreq = kernelAnswered ? ProcessorModel.shared.getOcFreqCache() : nil
            // S9a: PM-table info (cache only, no SMU traffic).
            let pmInfo = kernelAnswered ? ProcessorModel.shared.getPMTableInfo() : nil
            return (kernelAnswered, cpb, cppcState, ppm, lpm, boost, procParams, chtcLimit,
                    smuVersion, activeScalar, ocCap, ocFreq, pmInfo)
        }.value
        let profile = await ProcessorModel.shared.cpuProfile
        // S8.2 fallback for the per-CCD row count when the kext's register
        // probe has not run (0): Vermeer packs 8 cores per CCD.
        let physicalCores = await ProcessorModel.shared.physicalCoreCount

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

        // S5: publish the boost telemetry snapshot (or clear it when the kext
        // is pre-1.25 / the cache has not been populated yet).
        if let boost {
            maxBoostFreqMHz = boost.maxBoostFreqMHz
            fastestCoreRaw = boost.fastestCoreRaw
            fastestCoreIndex = AMDSmuBoost.decodeFastestCore(boost.fastestCoreRaw)
        } else {
            maxBoostFreqMHz = 0
            fastestCoreRaw = 0
            fastestCoreIndex = nil
        }

        // S6: publish the ProcessorParameters bitfield + cHTC limit cache.
        if let procParams {
            procParamsRaw = procParams.raw
            procParamsPolled = procParams.polled
        } else {
            procParamsRaw = 0
            procParamsPolled = false
        }
        if chtcLimitCelsius != chtcLimit.map({ Int($0) }) {
            chtcLimitCelsius = chtcLimit.map({ Int($0) })
        }

        // S7: publish the SMU version + active scalar readbacks.
        if let smuVersion {
            smuVersionRaw = smuVersion.raw
            smuVersionPolled = smuVersion.polled
        } else {
            smuVersionRaw = 0
            smuVersionPolled = false
        }
        if let activeScalar {
            activeScalarRaw = activeScalar.raw
        } else {
            activeScalarRaw = 0
        }

        // S8: publish the OC capability + mode cache.
        if let ocCap {
            ocSupported = ocCap.supported
            ocModeCode = ocCap.modeCode
        } else {
            ocSupported = false
            ocModeCode = 0
        }

        // S8.2: publish the frequency-override cache. `ocFreqSupported` reads
        // selector 49 [3] (0 on pre-1.30 kexts — controls stay hidden); the
        // kext's CCD count falls back to the app's own estimate when the
        // kext reports 0.
        ocFreqSupported = ocCap?.freqSupported ?? false
        if let ocFreq {
            ocFreqAllCoresMHz = ocFreq.allCoresMHz
            ocFreqPerCcdMHz = ocFreq.perCcdMHz
            kextCcdCount = ocFreq.kextCcdCount > 0
                ? Int(ocFreq.kextCcdCount)
                : max(1, physicalCores / 8)
        } else {
            ocFreqAllCoresMHz = 0
            ocFreqPerCcdMHz = []
            kextCcdCount = 0
        }

        // S9a: publish the PM-table plumbing info.
        if let pmInfo {
            pmTableVersionRaw = pmInfo.versionRaw
            pmTableVersionPolled = pmInfo.versionPolled
            pmTableSizeBytes = pmInfo.sizeBytes
            pmTableBase = pmInfo.dramBase
            pmTableValid = pmInfo.snapshotValid
            pmTableAgeMs = pmInfo.snapshotAgeMs
        } else {
            pmTableVersionRaw = 0
            pmTableVersionPolled = false
            pmTableSizeBytes = 0
            pmTableBase = 0
            pmTableValid = false
            pmTableAgeMs = 0
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

    private func recordTelemetrySample() {
        guard let packet = ProcessorModel.shared.getTelemetry() else { return }
        packagePowerHistory.append(Double(packet.packagePowerW))
        if packagePowerHistory.count > Self.historyCapacity {
            packagePowerHistory.removeFirst(packagePowerHistory.count - Self.historyCapacity)
        }
        packageTempHistory.append(Double(packet.packageTempC))
        if packageTempHistory.count > Self.historyCapacity {
            packageTempHistory.removeFirst(packageTempHistory.count - Self.historyCapacity)
        }
    }
}
