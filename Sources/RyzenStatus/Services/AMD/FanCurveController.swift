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
        }
    }
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
            persistMappings()
            syncMappingsToKext()
        }
    }
    @Published var privilegeError: String? = nil
    @Published var kextMissing: Bool = false
    @Published var isLoadingFans: Bool = false

    // MARK: - Internal Synchronization & Storage

    private let stateLock = OSAllocatedUnfairLock(initialState: [Int: Int]())
    private var pollTimer: Timer?
    private var readTask: Task<Void, Never>?
    private var persistCurvesTask: Task<Void, Never>?
    private var persistMappingsTask: Task<Void, Never>?
    private var wakeObserver: Any?
    private let logger = OSLog(subsystem: "com.ryzenstatus.fancurve", category: "Controller")

    // MARK: - Initialization

    private init() {
        loadPersistedState()
        setupWakeObserver()
        refreshFansInitial()
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        pollTimer?.invalidate()
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

        let initialMappings = self.fanMappings
        stateLock.withLock { $0 = initialMappings }
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
    }

    private func handleWakeNotification() {
        os_log("System did wake; re-syncing fan curves and mappings to kernel", log: logger, type: .info)
        // AUDIT B-30: force on wake — the kext may have lost its slots across
        // sleep even though our persisted state is unchanged.
        syncCurvesToKext(force: true)
        syncMappingsToKext(force: true)
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
        stateLock.withLock { $0 = mappingsToSave }
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

    /// AUDIT B-30: fingerprints of the last curve/mapping set successfully
    /// uploaded to the kext. `didSet` on the published properties fires on every
    /// UI refresh cycle, and each call re-issued 4 LUT writes + N mapping
    /// writes; under a non-root session every one of those logs a privilege
    /// denial. Uploads now happen only when content actually changes (or after
    /// a wake, where the kext may have lost state — `force` bypasses the
    /// fingerprint).
    private var lastUploadedCurvesFingerprint: Int?
    private var lastUploadedMappingsFingerprint: Int?

    /// Uploads custom curves into kernel curve slots 0..<min(4, curves.count) (selector 101).
    func syncCurvesToKext(force: Bool = false) {
        // AUDIT F-27: thread-safe connection check to avoid data races
        guard ProcessorModel.shared.isConnected else {
            self.kextMissing = true
            return
        }
        self.kextMissing = false

        // AUDIT B-30: skip the write burst when nothing changed.
        let fingerprint = customCurves.prefix(4).hashValue
        if !force, fingerprint == lastUploadedCurvesFingerprint { return }

        var sawPrivilegeError = false
        for (slot, curve) in customCurves.prefix(4).enumerated() {
            let input = curve.makeKextInput(slot: slot)
            let status = ProcessorModel.shared.setKextFanCurve(
                index: UInt32(slot),
                sourceSensor: input.sourceSensor,
                hysteresis: input.hysteresis,
                rampRate: input.rampRate,
                lut: input.lut
            )
            if status == kIOReturnNotPrivileged {
                self.privilegeError = ProcessorModel.privilegeHint(for: status)
                sawPrivilegeError = true
            }
        }
        // AUDIT B-30: remember success only — a failed upload retries on the
        // next content change (never on unchanged refreshes, which is what
        // caused the privilege-error spam).
        if !sawPrivilegeError {
            lastUploadedCurvesFingerprint = fingerprint
        }
    }

    /// Maps each physical fan header to its designated curve slot or restores Auto (selector 102).
    func syncMappingsToKext(force: Bool = false) {
        // AUDIT F-27: thread-safe connection check to avoid data races
        guard ProcessorModel.shared.isConnected else {
            self.kextMissing = true
            return
        }
        self.kextMissing = false

        // AUDIT B-30: skip the write burst when nothing changed. (Deterministic
        // order — tuples aren't Hashable, so fold key/value pairs into a Hasher
        // over sorted keys.)
        var mappingHasher = Hasher()
        for key in fanMappings.keys.sorted() {
            mappingHasher.combine(key)
            mappingHasher.combine(fanMappings[key] ?? -1)
        }
        let fingerprint = mappingHasher.finalize()
        if !force, fingerprint == lastUploadedMappingsFingerprint { return }

        var sawPrivilegeError = false
        for (fanId, curveIdx) in fanMappings {
            if curveIdx >= 0 && curveIdx < customCurves.count {
                let status = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: curveIdx)
                if status == kIOReturnNotPrivileged {
                    self.privilegeError = ProcessorModel.privilegeHint(for: status)
                    sawPrivilegeError = true
                }
            } else {
                _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            }
        }
        // AUDIT B-30: see syncCurvesToKext — success-only fingerprint.
        if !sawPrivilegeError {
            lastUploadedMappingsFingerprint = fingerprint
        }
    }

    /// Injects GPU temperature (selector 103) if any active curve uses GPU temp as its source.
    func pushGPUTempIfNeeded() {
        let hasActiveGPUCurve = fanMappings.values.contains { idx in
            idx >= 0 && idx < customCurves.count && customCurves[idx].sourceSensor == .gpu
        }
        guard hasActiveGPUCurve else { return }

        let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
        let monitorGPUTemp = SystemMonitor.shared.snapshot.gpuTemperature ?? 0.0
        let tempToSend = kextGPUTemp > 0 ? kextGPUTemp : monitorGPUTemp
        if tempToSend > 0 && tempToSend <= 120.0 {
            _ = ProcessorModel.shared.setKextGPUTemp(Float(tempToSend))
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
            let res = ProcessorModel.shared.setFanSpeed(pwm: Int(pwm), fanIndex: fanId)
            if !res {
                self.privilegeError = "Write permission denied for manual fan control."
            }
            updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: pwm)
        }
    }

    func setManualPWM(fanId: Int, pwm: UInt8) {
        _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
        _ = ProcessorModel.shared.setFanSpeed(pwm: Int(pwm), fanIndex: fanId)
        updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: pwm)
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
    }

    /// Resets all fans to BIOS/Auto control synchronously and thread-safely.
    /// Preserves safety guarantee on quit, toggle disable, and window dismiss.
    nonisolated func resetFansToAutoSync() {
        let mappings = stateLock.withLock { $0 }
        for fanId in 0..<16 {
            _ = ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            _ = ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
        }
        _ = mappings
    }

    // MARK: - Telemetry & Hardware Polling

    func refreshFansInitial() {
        isLoadingFans = true
        readTask?.cancel()
        readTask = Task.detached(priority: .userInitiated) {
            // AUDIT F-27: thread-safe connection check to avoid data races
            let kernelConnected = ProcessorModel.shared.isConnected
            guard kernelConnected else {
                await MainActor.run {
                    self.kextMissing = true
                    self.isLoadingFans = false
                }
                return
            }

            let initialSnapshots = ProcessorModel.shared.getFans(includeNames: true)
            let savedHidden = Set((UserDefaults.standard.array(forKey: "HiddenFanIDs") as? [Int]) ?? [])

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.kextMissing = false
                self.isLoadingFans = false

                var newFans: [FanState] = []
                for snap in initialSnapshots {
                    let customName = UserDefaults.standard.string(forKey: "FanName_\(snap.id)")
                    let mappedIdx = self.fanMappings[snap.id]
                    let mode: FanControlMode
                    if let mappedIdx, mappedIdx >= 0 && mappedIdx < self.customCurves.count {
                        mode = .curve
                    } else if snap.isOverridden {
                        mode = .manual
                    } else {
                        mode = .auto
                    }

                    newFans.append(FanState(
                        id: snap.id,
                        name: snap.name,
                        rpm: snap.rpm,
                        throttlePWM: snap.throttle,
                        isKextAuto: !snap.isOverridden,
                        controlMode: mode,
                        mappedCurveIndex: (mode == .curve) ? mappedIdx : nil,
                        manualPWM: (mode == .manual) ? snap.throttle : nil,
                        isHidden: savedHidden.contains(snap.id),
                        customName: customName
                    ))
                }
                self.fans = newFans
                // AUDIT B-30: force — after a fan-count change / kext reload the
                // kext-side slots may be stale even when our state is identical.
                self.syncCurvesToKext(force: true)
                self.syncMappingsToKext(force: true)
            }
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareState()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        readTask?.cancel()
        readTask = nil
    }

    private func pollHardwareState() {
        readTask?.cancel()
        readTask = Task.detached(priority: .utility) {
            let currentSnapshots = ProcessorModel.shared.getFans(includeNames: false)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                if self.fans.count != currentSnapshots.count {
                    self.refreshFansInitial()
                    return
                }

                for i in 0..<currentSnapshots.count {
                    let snap = currentSnapshots[i]
                    self.fans[i].rpm = snap.rpm
                    self.fans[i].throttlePWM = snap.throttle
                    self.fans[i].isKextAuto = !snap.isOverridden
                }
                self.pushGPUTempIfNeeded()
            }
        }
    }
}

typealias FanController = FanCurveController
