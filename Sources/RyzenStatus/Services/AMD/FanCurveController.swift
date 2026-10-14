// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import AppKit
import Combine
import os.log
import os

@MainActor
final class FanCurveController: ObservableObject {
    static let shared = FanCurveController()

    // MARK: - Published State

    @Published var fans: [FanState] = []
    @Published var customCurves: [FanCurveDefinition] = [] {
        didSet {
            persistCurves()
            syncCurvesToKext()
            updatePollTimer()
        }
    }
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
            persistMappings()
            syncMappingsToKext()
            updatePollTimer()
        }
    }
    @Published var privilegeError: String? = nil
    @Published var kextMissing: Bool = false
    @Published var isLoadingFans: Bool = false

    // MARK: - Internal Synchronization & Storage

    private var pollTimer: Timer?
    /// The full fan read (names included). Polls wait for it instead of
    /// cancelling it, so a slow first read always lands.
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var pollGeneration = 0
    /// Views showing live fan state (Settings › Fans, the AMD Power panel's
    /// fan row) while they are on screen.
    private var viewPollingClients = 0
    private var isSuspendedForSleep = false
    private var persistCurvesTask: Task<Void, Never>?
    private var persistMappingsTask: Task<Void, Never>?
    /// Coalescing upload tasks that keep kext IPC off the main actor.
    private var curveUploadTask: Task<Void, Never>?
    private var mappingUploadTask: Task<Void, Never>?
    /// Sleep-side observer, previously absent entirely.
    private var sleepObserver: Any?
    /// One-shot latch so the GPU-bridge diagnostic is logged once
    /// per failure episode instead of on every poll tick.
    private var gpuBridgeWarned = false
    private var wakeObserver: Any?
    private var reconnectObserver: Any?
    /// Rolling RPM window per fan, feeding the frozen-tachometer detector
    /// (S11-b). Reset whenever the fan list is rebuilt, since a rebuild means
    /// the channel set changed and the old windows describe other headers.
    private var rpmWindows: [Int: [UInt64]] = [:]
    /// 12 polls (18 s at the 1.5 s view cadence, 36 s at the 3 s safety
    /// cadence): eight identical non-zero readings is the detector's
    /// threshold, and the extra four keep the judgement from being made on a
    /// window that is all there is.
    private static let rpmWindowLength = 12
    private let logger = OSLog(subsystem: "com.ryzenstatus.fancurve", category: "Controller")

    // MARK: - Initialization

    private init() {
        loadPersistedState()
        setupWakeObserver()
        refreshFansInitial()
    }

    /// Brings the controller up at launch when the user has fans on curves.
    /// The app hands every fan back to the BIOS when it quits, so without
    /// this the curves only came back once Settings › Fans was opened.
    static func startIfConfigured(defaults: UserDefaults = .standard) {
        let mappings = defaults.data(forKey: DefaultsKey.fanMappingsV2)
            .flatMap { try? JSONDecoder().decode([Int: Int].self, from: $0) } ?? [:]
        guard FanPollingPolicy.needsStartAtLaunch(
            curvesEnabled: defaults.bool(forKey: DefaultsKey.fanCurvesEditorEnabled),
            mappings: mappings) else { return }
        _ = shared
    }

    deinit {
        // NOTE: this class is a `static let shared` singleton, so deinit never
        // actually runs. It is kept correct as defensive code and because Swift 6
        // language mode will type-check it. Real teardown happens in
        // AppDelegate.applicationWillTerminate via resetFansToAutoSync(), and in
        // The kernel via clientClose().
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let reconnectObserver {
            NotificationCenter.default.removeObserver(reconnectObserver)
        }
        pollTimer?.invalidate()
        // These were previously leaked on teardown.
        refreshTask?.cancel()
        pollTask?.cancel()
        persistCurvesTask?.cancel()
        persistMappingsTask?.cancel()
        curveUploadTask?.cancel()
        mappingUploadTask?.cancel()
    }

    // MARK: - State Loading & Defaults

    private func loadPersistedState() {
        // Load custom curves (v2 key first, then fallback to defaults)
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.customCurvesV2),
           let decoded = try? JSONDecoder().decode([FanCurveDefinition].self, from: data),
           !decoded.isEmpty {
            self.customCurves = Array(decoded.prefix(4))
        } else {
            self.customCurves = [
                FanCurveDefinition(
                    name: "Silent",
                    kextSlot: 0,
                    points: [
                        FanCurvePoint(temp: 40, pwm: 20),
                        FanCurvePoint(temp: 60, pwm: 35),
                        FanCurvePoint(temp: 75, pwm: 50),
                        FanCurvePoint(temp: 85, pwm: 80)
                    ],
                    sourceSensor: .cpu,
                    hysteresis: 2,
                    rampRate: 5
                ),
                FanCurveDefinition(
                    name: "Performance",
                    kextSlot: 1,
                    points: [
                        FanCurvePoint(temp: 40, pwm: 40),
                        FanCurvePoint(temp: 60, pwm: 65),
                        FanCurvePoint(temp: 75, pwm: 85),
                        FanCurvePoint(temp: 85, pwm: 100)
                    ],
                    sourceSensor: .cpu,
                    hysteresis: 1,
                    rampRate: 10
                )
            ]
        }

        // Load fan mappings
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.fanMappingsV2),
           let decoded = try? JSONDecoder().decode([Int: Int].self, from: data) {
            self.fanMappings = decoded
        } else {
            self.fanMappings = [:]
        }
    }

    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWakeNotification()
            }
        }

        // Nothing in this app observed willSleepNotification, so the
        // 1.5 s fan poll (plus AutoEppService, C6ResidencyService and the 5 s
        // kext watchdog) stayed armed across suspend. Timers coalesce but fire
        // immediately on wake, and the Task.sleep loops genuinely resume during
        // dark wake and hit IOKit.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSleepNotification()
            }
        }

        // The watchdog reopens the kext connection after a kext reload or a
        // dead handle. Closing the old connection hands every fan back to the
        // BIOS, so the fans are read again and the curves and mappings are
        // uploaded anew (the full read forces both uploads).
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: ProcessorModel.kextReconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFansInitial()
            }
        }
    }

    private func handleSleepNotification() {
        os_log("System will sleep; suspending fan telemetry", log: logger, type: .info)
        isSuspendedForSleep = true
        updatePollTimer()
    }

    private func handleWakeNotification() {
        os_log("System did wake; re-syncing fan curves and mappings to kernel", log: logger, type: .info)
        // Force on wake — the kext may have lost its slots across
        // sleep even though our persisted state is unchanged.
        // These are now debounced and run off the main actor, so the
        // wake path no longer performs 4+N blocking kernel writes on main.
        syncCurvesToKext(force: true)
        syncMappingsToKext(force: true)
        isSuspendedForSleep = false
        updatePollTimer()
    }

    // MARK: - Persistence

    private func persistCurves() {
        let curvesToSave = customCurves
        persistCurvesTask?.cancel()
        persistCurvesTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(curvesToSave) {
                UserDefaults.standard.set(data, forKey: DefaultsKey.customCurvesV2)
            }
        }
    }

    private func persistMappings() {
        let mappingsToSave = fanMappings
        persistMappingsTask?.cancel()
        persistMappingsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(mappingsToSave) {
                UserDefaults.standard.set(data, forKey: DefaultsKey.fanMappingsV2)
            }
        }
    }

    // MARK: - Kext Native Synchronization (Selectors 101 / 102 / 103)

    /// Fingerprints of the last curve/mapping set successfully
    /// uploaded to the kext. `didSet` on the published properties fires on every
    /// UI refresh cycle, and each call re-issued 4 LUT writes + N mapping
    /// writes; under a non-root session every one of those logs a privilege
    /// denial. Uploads now happen only when content actually changes (or after
    /// a wake, where the kext may have lost state — `force` bypasses the
    /// fingerprint).
    private var lastUploadedCurvesFingerprint: Int?
    private var lastUploadedMappingsFingerprint: Int?

    // MARK: - coalesced, off-main-actor kext upload
    //
    // These two entry points keep their original names and signatures, so every
    // existing call site (the two didSet observers, handleWakeNotification,
    // setFanMode and refreshFansInitial) is unchanged. What changed is that the
    // kernel IPC no longer runs synchronously on the main actor.
    //
    // Two defects were stacked in the old implementation. First, the uploads
    // issue synchronous IOConnectCallMethod calls and this class is @MainActor,
    // so every assignment blocked the main thread on kernel IPC (up to 4 LUT
    // writes of 272 B, plus one call per fan). Second, they were invoked from a
    // `didSet` and write @Published state back (kextMissing, privilegeError),
    // mutating observable state *during* a SwiftUI publish cycle.
    //
    // A 120 ms debounce also coalesces bursts (a slider drag, a preset switch)
    // into a single upload instead of one per assignment.

    /// Sendable payload so nothing non-Sendable crosses into the detached task.
    /// Note this is deliberately NOT `AMDFanCurveInput`-by-reference: the LUT is
    /// a heap array, so it is snapshotted on the main actor first.
    private struct CurveUploadPayload: Sendable {
        let slot: UInt32
        let sourceSensor: UInt32
        let hysteresis: UInt32
        let rampRate: UInt32
        let lut: [UInt8]
    }

    private struct UploadOutcome: Sendable {
        var privilegeMessage: String?
    }

    /// Uploads custom curves into kernel curve slots 0..<min(4, curves.count) (selector 101).
    func syncCurvesToKext(force: Bool = false) {
        curveUploadTask?.cancel()
        curveUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }

            // --- main actor: gating and payload snapshot ---
            guard ProcessorModel.shared.isConnected else {
                self.kextMissing = true
                return
            }
            self.kextMissing = false

            // Skip the write burst when nothing changed.
            let fingerprint = self.customCurves.prefix(4).hashValue
            if !force, fingerprint == self.lastUploadedCurvesFingerprint { return }

            var payloads: [CurveUploadPayload] = []
            for (slot, curve) in self.customCurves.prefix(4).enumerated() {
                let input = curve.makeKextInput(slot: slot)
                payloads.append(CurveUploadPayload(slot: UInt32(slot),
                                                   sourceSensor: input.sourceSensor,
                                                   hysteresis: input.hysteresis,
                                                   rampRate: input.rampRate,
                                                   lut: input.lut))
            }

            // --- off the main actor: the actual kernel IPC ---
            let outcome = await Task.detached(priority: .userInitiated) {
                FanCurveController.performCurveUpload(payloads)
            }.value

            guard !Task.isCancelled else { return }
            if let message = outcome.privilegeMessage {
                self.privilegeError = message
            } else {
                // Remember success only — a failed upload retries on
                // the next content change, never on unchanged refreshes.
                self.lastUploadedCurvesFingerprint = fingerprint
            }
        }
    }

    nonisolated private static func performCurveUpload(_ payloads: [CurveUploadPayload]) -> UploadOutcome {
        var outcome = UploadOutcome()
        for payload in payloads {
            let status = ProcessorModel.shared.setKextFanCurve(
                index: payload.slot,
                sourceSensor: payload.sourceSensor,
                hysteresis: payload.hysteresis,
                rampRate: payload.rampRate,
                lut: payload.lut
            )
            if status == kIOReturnNotPrivileged {
                outcome.privilegeMessage = ProcessorModel.privilegeHint(for: status)
            }
        }
        return outcome
    }

    /// Maps each physical fan header to its designated curve slot or restores Auto (selector 102).
    func syncMappingsToKext(force: Bool = false) {
        mappingUploadTask?.cancel()
        mappingUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }

            guard ProcessorModel.shared.isConnected else {
                self.kextMissing = true
                return
            }
            self.kextMissing = false

            // Deterministic fingerprint over sorted keys.
            var mappingHasher = Hasher()
            for key in self.fanMappings.keys.sorted() {
                mappingHasher.combine(key)
                mappingHasher.combine(self.fanMappings[key] ?? -1)
            }
            let fingerprint = mappingHasher.finalize()
            if !force, fingerprint == self.lastUploadedMappingsFingerprint { return }

            // [Int: Int] is Sendable, so the snapshot crosses safely.
            let mappings = self.fanMappings
            let curveCount = self.customCurves.count

            let outcome = await Task.detached(priority: .userInitiated) {
                FanCurveController.performMappingUpload(mappings, curveCount: curveCount)
            }.value

            guard !Task.isCancelled else { return }
            if let message = outcome.privilegeMessage {
                self.privilegeError = message
            } else {
                self.lastUploadedMappingsFingerprint = fingerprint
            }
        }
    }

    nonisolated private static func performMappingUpload(_ mappings: [Int: Int], curveCount: Int) -> UploadOutcome {
        var outcome = UploadOutcome()
        for (fanId, curveIdx) in mappings {
            if curveIdx >= 0 && curveIdx < curveCount {
                let status = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: curveIdx)
                if status == kIOReturnNotPrivileged {
                    outcome.privilegeMessage = ProcessorModel.privilegeHint(for: status)
                }
            } else {
                _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            }
        }
        return outcome
    }

    /// True while some fan follows a curve that reads the GPU temperature,
    /// which only the app can feed to the kext.
    private var hasActiveGPUCurve: Bool {
        fanMappings.values.contains { idx in
            idx >= 0 && idx < customCurves.count && customCurves[idx].sourceSensor == .gpu
        }
    }

    /// Injects GPU temperature (selector 103) if any active curve uses GPU temp as its source.
    /// `freshKextTemp` is the kext's own reading taken by this poll; the
    /// cached one is only refreshed while the system monitor samples.
    func pushGPUTempIfNeeded(freshKextTemp: Double? = nil) {
        guard hasActiveGPUCurve else { return }

        let kextGPUTemp = freshKextTemp ?? ProcessorModel.shared.lastKextGPUTemperature
        let monitorGPUTemp = SystemMonitor.shared.snapshot.gpuTemperature ?? 0.0
        // SMU7 GPUs report 255 for an invalid sample; fall back to the monitor
        // then instead of dropping the update.
        let kextUsable = kextGPUTemp > 0 && kextGPUTemp <= 120.0
        let tempToSend = kextUsable ? kextGPUTemp : monitorGPUTemp

        guard tempToSend > 0, tempToSend <= 120.0, tempToSend.isFinite else {
            // No trustworthy GPU reading. Say so once instead of
            // failing silently — the kext keeps its previous gpuTempC, and a
            // GPU-sourced curve would otherwise evaluate against a frozen value
            // with no user-visible explanation.
            if !gpuBridgeWarned {
                gpuBridgeWarned = true
                os_log("GPU-sourced fan curve active but no valid GPU temperature available (kext=%{public}.1f monitor=%{public}.1f)",
                       log: logger, type: .error, kextGPUTemp, monitorGPUTemp)
            }
            return
        }

        // Selector 103 is privilege-gated (root or -amdpnopchk).
        // It used to be called with `_ =`, so a kIOReturnNotPrivileged silently
        // froze every GPU-sourced curve. Selectors 101/102 already surface
        // privilegeError; 103 was the inconsistent one.
        let status = ProcessorModel.shared.setKextGPUTemp(Float(tempToSend))
        if status == KERN_SUCCESS {
            gpuBridgeWarned = false
        } else if !gpuBridgeWarned {
            gpuBridgeWarned = true
            if status == kIOReturnNotPrivileged {
                privilegeError = ProcessorModel.privilegeHint(for: status)
            }
            os_log("selector 103 (GPU temp bridge) failed kr=0x%08x; GPU-sourced curves fall back to CPU temperature",
                   log: logger, type: .error, status)
        }
    }

    // MARK: - Curve Management

    func saveCurve(_ curve: FanCurveDefinition) {
        guard FanCurveDefinition.isValid(points: curve.points) else { return }
        if let idx = customCurves.firstIndex(where: { $0.id == curve.id }) {
            customCurves[idx] = curve
        } else if customCurves.count < 4 {
            var updated = customCurves
            var newCurve = curve
            newCurve.kextSlot = updated.count
            updated.append(newCurve)
            customCurves = updated
        }
    }

    func resetToDefaults() {
        self.customCurves = [
            FanCurveDefinition(
                name: "Silent",
                kextSlot: 0,
                points: [
                    FanCurvePoint(temp: 40, pwm: 20),
                    FanCurvePoint(temp: 60, pwm: 35),
                    FanCurvePoint(temp: 75, pwm: 50),
                    FanCurvePoint(temp: 85, pwm: 80)
                ],
                sourceSensor: .cpu,
                hysteresis: 2,
                rampRate: 5
            ),
            FanCurveDefinition(
                name: "Performance",
                kextSlot: 1,
                points: [
                    FanCurvePoint(temp: 40, pwm: 40),
                    FanCurvePoint(temp: 60, pwm: 65),
                    FanCurvePoint(temp: 75, pwm: 85),
                    FanCurvePoint(temp: 85, pwm: 100)
                ],
                sourceSensor: .cpu,
                hysteresis: 1,
                rampRate: 10
            )
        ]
        setAllAuto()
    }

    func deleteCurve(id: UUID) {
        guard let idx = customCurves.firstIndex(where: { $0.id == id }) else { return }
        var updated = customCurves
        updated.remove(at: idx)
        for i in 0..<updated.count {
            updated[i].kextSlot = i
        }
        customCurves = updated
        fanMappings = FanCurveDefinition.compactMappingsOnDeletion(mappings: fanMappings, deletedIndex: idx)
    }

    // MARK: - Fan Mode & Speed Control

    func setFanMode(fanId: Int, mode: FanControlMode, curveIndex: Int? = nil, manualPWM: UInt8? = nil) {
        switch mode {
        case .auto:
            var updated = fanMappings
            updated[fanId] = -1
            fanMappings = updated
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
            updateFanLocalState(fanId: fanId, mode: .auto, curveIdx: nil, manualPWM: nil)

        case .curve:
            let targetIdx = curveIndex ?? 0
            guard targetIdx >= 0 && targetIdx < customCurves.count else { return }
            var updated = fanMappings
            updated[fanId] = targetIdx
            fanMappings = updated
            syncCurvesToKext()
            let status = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: targetIdx)
            if status == kIOReturnNotPrivileged {
                self.privilegeError = ProcessorModel.privilegeHint(for: status)
            }
            updateFanLocalState(fanId: fanId, mode: .curve, curveIdx: targetIdx, manualPWM: nil)

        case .manual:
            var updated = fanMappings
            updated[fanId] = -1
            fanMappings = updated
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            let pwm = manualPWM ?? 128
            let safePWM = AMDFanSafety.clampManualPWM(pwm)
            let effectivePWM = AMDFanSafety.effectiveManualPWM(userPWM: safePWM, currentTemp: currentCPUOrPackageTemp)
            let res = ProcessorModel.shared.setFanSpeed(pwm: Int(effectivePWM), fanIndex: fanId)
            if !res {
                self.privilegeError = ProcessorModel.privilegeHint(for: ProcessorModel.kIOReturnNotPrivilegedCode)
            }
            updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: safePWM)
        }
    }

    var currentCPUOrPackageTemp: Double {
        if let packet = ProcessorModel.shared.getTelemetry(), packet.packageTempC > 0 {
            return Double(packet.packageTempC)
        }
        return SystemMonitor.shared.snapshot.cpuTemperature ?? 0.0
    }

    /// S2-T2: true while the emergency thermal guard is clamping manual fans
    /// (temp at/above 85 °C) — drives the UI hint in FanControlCard.
    var isThermalGuardActive: Bool {
        currentCPUOrPackageTemp >= AMDFanSafety.thermalGuardTempC
    }

    func setManualPWM(fanId: Int, pwm: UInt8) {
        let safePWM = AMDFanSafety.clampManualPWM(pwm)
        _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
        let effectivePWM = AMDFanSafety.effectiveManualPWM(userPWM: safePWM, currentTemp: currentCPUOrPackageTemp)
        _ = ProcessorModel.shared.setFanSpeed(pwm: Int(effectivePWM), fanIndex: fanId)
        updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: safePWM)
    }

    func setAllAuto() {
        var updated = fanMappings
        for f in fans {
            updated[f.id] = -1
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: f.id, curveIndex: -1)
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: f.id)
            updateFanLocalState(fanId: f.id, mode: .auto, curveIdx: nil, manualPWM: nil)
        }
        fanMappings = updated
    }

    func setAllMaxSpeed() {
        var updated = fanMappings
        for f in fans {
            updated[f.id] = -1
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: f.id, curveIndex: -1)
            _ = ProcessorModel.shared.setFanSpeed(pwm: 255, fanIndex: f.id)
            updateFanLocalState(fanId: f.id, mode: .manual, curveIdx: nil, manualPWM: 255)
        }
        fanMappings = updated
    }

    func setCustomName(fanId: Int, name: String) {
        if let idx = fans.firstIndex(where: { $0.id == fanId }) {
            fans[idx].customName = name.isEmpty ? nil : name
        }
        if name.isEmpty {
            UserDefaults.standard.removeObject(forKey: "FanName_\(fanId)")
        } else {
            UserDefaults.standard.set(name, forKey: "FanName_\(fanId)")
        }
    }

    func setHidden(fanId: Int, hidden: Bool) {
        if let idx = fans.firstIndex(where: { $0.id == fanId }) {
            fans[idx].isHidden = hidden
        }
        var hiddenSet = Set((UserDefaults.standard.array(forKey: "HiddenFanIDs") as? [Int]) ?? [])
        if hidden {
            hiddenSet.insert(fanId)
        } else {
            hiddenSet.remove(fanId)
        }
        UserDefaults.standard.set(Array(hiddenSet), forKey: "HiddenFanIDs")
    }

    private func updateFanLocalState(fanId: Int, mode: FanControlMode, curveIdx: Int?, manualPWM: UInt8?) {
        guard let idx = fans.firstIndex(where: { $0.id == fanId }) else { return }
        fans[idx].controlMode = mode
        fans[idx].mappedCurveIndex = curveIdx
        fans[idx].manualPWM = manualPWM
        updatePollTimer()
    }

    /// Resets all fans to BIOS/Auto control synchronously and thread-safely.
    /// Preserves safety guarantee on quit, toggle disable, and window dismiss.
    /// Every header slot is reset, including fans the list does not show.
    nonisolated func resetFansToAutoSync() {
        for fanId in 0..<16 {
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
        }
    }

    /// Turning the curves off: every header back to the BIOS, the mappings
    /// cleared and the fan list showing Auto right away.
    func disableCurves() {
        resetFansToAutoSync()
        for fan in fans {
            updateFanLocalState(fanId: fan.id, mode: .auto, curveIdx: nil, manualPWM: nil)
        }
        fanMappings = [:]
    }

    // MARK: - Telemetry & Hardware Polling

    /// Reads every fan with its name and rebuilds the list, then uploads the
    /// curves and mappings again: after a fan-count change or a kext reload
    /// the kext's slots may be stale even when our state is identical.
    func refreshFansInitial() {
        isLoadingFans = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let snapshots: [FanSnapshot]? = await Task.detached(priority: .userInitiated) {
                guard ProcessorModel.shared.isConnected else { return nil }
                return ProcessorModel.shared.getFans(includeNames: true)
            }.value
            // A newer refresh replaced this one and owns the loading state.
            guard let self, !Task.isCancelled else { return }
            self.refreshTask = nil
            self.isLoadingFans = false
            guard let snapshots else {
                // No kext, no fans: an empty list also keeps the poll from
                // asking for a new full read on every tick.
                self.kextMissing = true
                self.rebuildFans(from: [])
                return
            }
            self.kextMissing = false
            self.rebuildFans(from: snapshots)
            self.syncCurvesToKext(force: true)
            self.syncMappingsToKext(force: true)
        }
    }

    private func rebuildFans(from snapshots: [FanSnapshot]) {
        let defaults = UserDefaults.standard
        let savedHidden = Set((defaults.array(forKey: "HiddenFanIDs") as? [Int]) ?? [])
        fans = snapshots.map { snap in
            let mappedIdx = fanMappings[snap.id]
            let mode: FanControlMode
            if let mappedIdx, mappedIdx >= 0 && mappedIdx < customCurves.count {
                mode = .curve
            } else if snap.isOverridden {
                mode = .manual
            } else {
                mode = .auto
            }
            return FanState(
                id: snap.id,
                name: snap.name,
                rpm: snap.rpm,
                throttlePWM: snap.throttle,
                isKextAuto: !snap.isOverridden,
                controlMode: mode,
                mappedCurveIndex: (mode == .curve) ? mappedIdx : nil,
                manualPWM: (mode == .manual) ? snap.throttle : nil,
                isHidden: savedHidden.contains(snap.id),
                customName: defaults.string(forKey: "FanName_\(snap.id)"),
                rpmValid: snap.rpmValid
            )
        }
        self.rpmWindows.removeAll()
        updatePollTimer()
    }

    /// A view showing live fan state calls this when it appears, and
    /// `stopPolling()` when it goes away.
    func startPolling() {
        viewPollingClients += 1
        updatePollTimer()
    }

    func stopPolling() {
        viewPollingClients = max(0, viewPollingClients - 1)
        updatePollTimer()
    }

    /// Runs the poll at the pace its clients need: quickly while a view
    /// shows live fan state; slower, but with every window closed, while a
    /// fan is in manual mode (the thermal guard) or follows a GPU-sourced
    /// curve (the GPU temperature only the app can feed to the kext); not at
    /// all otherwise, or during sleep.
    private func updatePollTimer() {
        let interval = isSuspendedForSleep ? nil : FanPollingPolicy.interval(
            viewClients: viewPollingClients,
            hasManualFan: fans.contains { $0.controlMode == .manual },
            hasGPUCurve: hasActiveGPUCurve)
        guard let interval else {
            pollTimer?.invalidate()
            pollTimer = nil
            pollTask?.cancel()
            pollTask = nil
            return
        }
        if let pollTimer, pollTimer.isValid, pollTimer.timeInterval == interval { return }
        pollTimer?.invalidate()
        // `.common` mode, not `.default`: a timer in the default mode does not
        // fire while a tracking run loop is up (an open menu, a slider drag),
        // and this one drives the manual-mode thermal guard.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollHardwareState() {
        // A full read in flight answers the same question; a poll still in
        // flight is not doubled up.
        guard refreshTask == nil, pollTask == nil else { return }
        pollGeneration &+= 1
        let generation = pollGeneration
        let wantsGPUTemp = hasActiveGPUCurve
        let wantsCPUTemp = fans.contains { $0.controlMode == .manual }
        pollTask = Task { [weak self] in
            // Every kext read of the tick happens here, off the main actor.
            let (snapshots, kextGPUTemp, packageTemp) = await Task.detached(priority: .utility) {
                () -> ([FanSnapshot], Double?, Double?) in
                let fans = ProcessorModel.shared.getFans(includeNames: false)
                let packageTemp = wantsCPUTemp
                    ? ProcessorModel.shared.getTelemetry().map { Double($0.packageTempC) }
                    : nil
                guard wantsGPUTemp, ProcessorModel.shared.getKextGPUCount() > 0 else {
                    return (fans, nil, packageTemp)
                }
                return (fans, ProcessorModel.shared.getKextGPUTemperatures().first.map(Double.init), packageTemp)
            }.value
            guard let self else { return }
            if self.pollGeneration == generation { self.pollTask = nil }
            guard !Task.isCancelled else { return }
            if self.fans.map(\.id) != snapshots.map(\.id) {
                self.refreshFansInitial()
                return
            }

            for (i, snap) in snapshots.enumerated() {
                let frozen = self.recordRPM(snap.rpm, for: snap.id)
                self.fans[i].rpm = snap.rpm
                // The detector only ever REMOVES trust, never grants it: an
                // unconnected header (or a channel reading electrical
                // residue) reports the same plausible non-zero count
                // forever, and every RPM-based heuristic reads that as a
                // healthy rotor — including the kernel's rotor-start
                // floor, which then declines to help a genuinely stalled
                // fan. Untrusted readings render as "— RPM" rather than a
                // number that cannot be true.
                self.fans[i].rpmValid = snap.rpmValid && !frozen
                self.fans[i].throttlePWM = snap.throttle
                self.fans[i].isKextAuto = !snap.isOverridden
            }
            self.pushGPUTempIfNeeded(freshKextTemp: kextGPUTemp)
            self.enforceManualThermalGuard(packageTemp: packageTemp)
        }
    }

    /// Folds one RPM reading into a fan's window and answers whether the
    /// channel now looks frozen (`AMDFanSafety.isTachometerStale`, already
    /// unit-tested; this is where it finally gets wired in).
    private func recordRPM(_ rpm: UInt64, for fanId: Int) -> Bool {
        var window = rpmWindows[fanId] ?? []
        window.append(rpm)
        if window.count > Self.rpmWindowLength {
            window.removeFirst(window.count - Self.rpmWindowLength)
        }
        rpmWindows[fanId] = window
        return AMDFanSafety.isTachometerStale(samples: window)
    }

    /// `packageTemp` is the kext's reading taken by this poll; without one
    /// the system monitor's CPU temperature stands in.
    private func enforceManualThermalGuard(packageTemp: Double?) {
        let temp = packageTemp.flatMap { $0 > 0 ? $0 : nil }
            ?? SystemMonitor.shared.snapshot.cpuTemperature ?? 0
        for fan in fans {
            guard fan.controlMode == .manual, let userPWM = fan.manualPWM else { continue }
            // guardOnlyPWM, not effectiveManualPWM. `manualPWM` seeds
            // from the hardware's current duty (often a fixed BIOS setpoint),
            // so applying the user-commanded floor here would silently ramp
            // BIOS-fixed fans up on the first poll after an update. The floor
            // is enforced where the USER sets duty (setManualPWM and the
            // slider); the enforcement loop only arms the emergency guard.
            // Intentional divergence from effectiveManualPWM — do not "fix".
            let effectivePWM = AMDFanSafety.guardOnlyPWM(userPWM: userPWM, currentTemp: temp)
            if fan.throttlePWM != effectivePWM {
                _ = ProcessorModel.shared.setFanSpeed(pwm: Int(effectivePWM), fanIndex: fan.id)
            }
        }
    }
}

typealias FanController = FanCurveController
