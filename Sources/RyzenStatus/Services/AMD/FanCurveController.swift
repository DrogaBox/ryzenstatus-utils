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
    /// Debounce for the curve and mapping uploads; cancelling it only drops
    /// a pending schedule, never a queued write (see `scheduleKextSync`).
    private var syncDebounceTask: Task<Void, Never>?
    private var pendingCurveForce = false
    private var pendingKextReset = false
    private var pendingDutyReapply: Set<Int> = []
    /// Tail of the ordered kext write chain (see `enqueueKextWrite`).
    private var kextWriteTail: Task<Void, Never>?
    private var kextWriteSequence = 0
    /// The curve slot the kext holds for each fan, as far as our own writes
    /// say; a fan absent here is not on a kext curve. Emptied whenever the
    /// connection is reopened: closing the old one unmapped every fan.
    private var kextMappings: [Int: Int] = [:]
    /// Package temperature from the last poll, for the thermal-guard hints
    /// the views show. Nil while the poll is not running, so it never shows
    /// a reading from before a sleep or an unload.
    private(set) var lastPackageTempC: Double?
    /// Sleep-side observer, previously absent entirely.
    private var sleepObserver: Any?
    /// One-shot latch so the GPU-bridge diagnostic is logged once
    /// per failure episode instead of on every poll tick.
    private var gpuBridgeWarned = false
    private var wakeObserver: Any?
    private var reconnectObserver: Any?
    private var unloadObserver: Any?
    /// Each fan's run of identical RPM readings, feeding the frozen-tachometer
    /// detector. Reset whenever the fan list is rebuilt, since a rebuild means
    /// the channel set changed and the old runs describe other headers.
    private var rpmRuns: [Int: AMDFanSafety.TachometerRun] = [:]
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
        if let unloadObserver {
            NotificationCenter.default.removeObserver(unloadObserver)
        }
        pollTimer?.invalidate()
        // These were previously leaked on teardown.
        refreshTask?.cancel()
        pollTask?.cancel()
        persistCurvesTask?.cancel()
        persistMappingsTask?.cancel()
        syncDebounceTask?.cancel()
        // The write chain is never cancelled: a queued safety write lands.
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

        // An unloaded kext holds nothing of ours, and its readings are gone.
        unloadObserver = NotificationCenter.default.addObserver(
            forName: ProcessorModel.kextUnloadedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleKextUnloaded()
            }
        }
    }

    private func handleSleepNotification() {
        os_log("System will sleep; suspending fan telemetry", log: logger, type: .info)
        isSuspendedForSleep = true
        updatePollTimer()
    }

    private func handleWakeNotification() {
        os_log("System did wake; re-syncing fan curves to kernel", log: logger, type: .info)
        // Force the curves on wake — the kext may have lost its slots across
        // sleep even though our persisted state is unchanged. The mappings
        // live in kext memory, which sleep keeps, so they are only checked.
        // Both run debounced and off the main actor.
        syncCurvesToKext(force: true)
        syncMappingsToKext()
        isSuspendedForSleep = false
        updatePollTimer()
    }

    private func handleKextUnloaded() {
        kextMissing = true
        kextMappings = [:]
        lastPackageTempC = nil
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

    /// Fingerprint of the last curve set successfully uploaded to the kext.
    /// `didSet` on the published properties fires on every UI refresh cycle,
    /// and each call re-issued 4 LUT writes; under a non-root session every
    /// one of those logs a privilege denial. Curves are uploaded only when
    /// their content changes (or after a wake or a reconnect, where the kext
    /// may have lost them — `force` bypasses the fingerprint). Mappings need
    /// no fingerprint: `kextMappings` says per fan what the kext holds.
    private var lastUploadedCurvesFingerprint: Int?

    // MARK: - Ordered, off-main-actor kext writes
    //
    // Every fan write the controller makes (a mode switch, a manual duty, the
    // thermal guard, disabling the curves, the curve and mapping uploads, the
    // GPU temperature bridge) goes through one chain. Each job waits for the
    // one before it, snapshots what it needs on the main actor when it
    // starts, and does its kernel IPC in a detached task. The writes
    // therefore land in the order they were made, and the main thread never
    // waits on the kext.
    //
    // A 120 ms debounce in front of the uploads coalesces bursts (a slider
    // drag, a preset switch) into a single upload instead of one per
    // assignment, and keeps `didSet` from writing @Published state back
    // during a SwiftUI publish cycle.

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

    /// Queues `job` behind every kext write queued before it, in the
    /// task-chain shape `AmdPresetController` uses for presets. Nothing
    /// cancels the chain, so a queued safety write always lands.
    private func enqueueKextWrite(_ job: @escaping @MainActor @Sendable (FanCurveController) async -> Void) {
        let previous = kextWriteTail
        kextWriteSequence &+= 1
        let sequence = kextWriteSequence
        kextWriteTail = Task { @MainActor in
            await previous?.value
            await job(self)
            // Release the tail only when no newer job chained behind this one.
            if self.kextWriteSequence == sequence { self.kextWriteTail = nil }
        }
    }

    /// Uploads custom curves into kernel curve slots 0..<min(4, curves.count) (selector 101).
    func syncCurvesToKext(force: Bool = false) {
        scheduleKextSync(forceCurves: force)
    }

    /// Brings each fan header's kext mapping in line with `fanMappings`
    /// (selector 102). `force` means the connection was just (re)opened:
    /// closing the previous one unmapped every fan and dropped every manual
    /// duty, so the curve fans are mapped again and the manual fans that
    /// survived the reconnect get their duty back.
    func syncMappingsToKext(force: Bool = false, reapplyingDutyFor manualFans: Set<Int> = []) {
        scheduleKextSync(kextWasReset: force, reapplyDutyFor: manualFans)
    }

    /// One debounce for both uploads. When it fires, the curve upload is
    /// queued before the mapping pass, so a fan is never mapped to a slot
    /// whose curve has not landed, whichever schedule came last.
    private func scheduleKextSync(forceCurves: Bool = false, kextWasReset: Bool = false,
                                  reapplyDutyFor manualFans: Set<Int> = []) {
        pendingCurveForce = pendingCurveForce || forceCurves
        pendingKextReset = pendingKextReset || kextWasReset
        pendingDutyReapply.formUnion(manualFans)
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            let forceCurves = self.pendingCurveForce
            let kextWasReset = self.pendingKextReset
            let manualFans = self.pendingDutyReapply
            self.pendingCurveForce = false
            self.pendingKextReset = false
            self.pendingDutyReapply = []
            self.enqueueCurveUpload(force: forceCurves || kextWasReset)
            self.enqueueFanStateSync(assertDutyFor: manualFans, kextWasReset: kextWasReset)
        }
    }

    private func enqueueCurveUpload(force: Bool) {
        enqueueKextWrite { controller in
            guard ProcessorModel.shared.isConnected else {
                controller.kextMissing = true
                return
            }
            controller.kextMissing = false

            // Skip the write burst when nothing changed.
            let curves = Array(controller.customCurves.prefix(4))
            let fingerprint = curves.hashValue
            if !force, fingerprint == controller.lastUploadedCurvesFingerprint { return }

            let payloads = curves.enumerated().map { slot, curve in
                let input = curve.makeKextInput(slot: slot)
                return CurveUploadPayload(slot: UInt32(slot),
                                          sourceSensor: input.sourceSensor,
                                          hysteresis: input.hysteresis,
                                          rampRate: input.rampRate,
                                          lut: input.lut)
            }
            let status = await Task.detached(priority: .userInitiated) {
                FanCurveController.performCurveUpload(payloads)
            }.value
            if status == KERN_SUCCESS {
                // Remember success only — a failed upload retries on the
                // next change or forced sync, never on unchanged refreshes.
                controller.lastUploadedCurvesFingerprint = fingerprint
            } else {
                controller.privilegeError = ProcessorModel.privilegeHint(for: status)
            }
        }
    }

    /// The first failure the kext answered, or `KERN_SUCCESS`.
    nonisolated private static func performCurveUpload(_ payloads: [CurveUploadPayload]) -> kern_return_t {
        var firstFailure = KERN_SUCCESS
        for payload in payloads {
            let status = ProcessorModel.shared.setKextFanCurve(
                index: payload.slot,
                sourceSensor: payload.sourceSensor,
                hysteresis: payload.hysteresis,
                rampRate: payload.rampRate,
                lut: payload.lut
            )
            if status != KERN_SUCCESS && firstFailure == KERN_SUCCESS { firstFailure = status }
        }
        return firstFailure
    }

    /// Queues one pass that brings the kext's fan mappings and manual duties
    /// in line with the controller (`FanKextWritePlan`), worked out when the
    /// job starts so it sees every write queued before it.
    /// - Parameters:
    ///   - fanIds: only these fans (a user action on one fan); nil = every fan.
    ///   - assertDutyFor: manual fans whose duty is written even when their
    ///     mapping needs no change.
    ///   - kextWasReset: the connection was reopened and the kext holds
    ///     nothing of ours any more.
    private func enqueueFanStateSync(only fanIds: Set<Int>? = nil,
                                     assertDutyFor: Set<Int> = [],
                                     kextWasReset: Bool = false) {
        enqueueKextWrite { controller in
            guard ProcessorModel.shared.isConnected else {
                controller.kextMissing = true
                return
            }
            controller.kextMissing = false
            if kextWasReset { controller.kextMappings = [:] }
            let writes = controller.plannedFanWrites(only: fanIds, assertDutyFor: assertDutyFor)
            await controller.perform(writes)
        }
    }

    /// Queues writes fixed at the moment they are made (an explicit move
    /// back to the BIOS).
    private func enqueueFanWrites(_ writes: [FanKextWrite]) {
        guard !writes.isEmpty else { return }
        enqueueKextWrite { controller in
            await controller.perform(writes)
        }
    }

    private func plannedFanWrites(only fanIds: Set<Int>?, assertDutyFor: Set<Int>) -> [FanKextWrite] {
        // Only headers the kext reported: a persisted mapping for a fan that
        // is not there would only earn a bad-argument answer.
        let present = fanIds ?? Set(fans.map(\.id))
        var manualPWMs: [Int: UInt8] = [:]
        for fan in fans where fan.controlMode == .manual && present.contains(fan.id) {
            if let pwm = fan.manualPWM { manualPWMs[fan.id] = pwm }
        }
        return FanKextWritePlan.writes(
            mappings: fanMappings.filter { present.contains($0.key) },
            manualPWMs: manualPWMs,
            kextMappings: kextMappings.filter { present.contains($0.key) },
            curveCount: customCurves.count,
            assertDutyFor: assertDutyFor)
    }

    /// Runs `writes` off the main actor, then records what the kext now
    /// holds and reports the first failure with the kext's own status.
    /// `packageTemp` is a reading the caller already took; without one the
    /// job reads it at write time for the thermal guard.
    private func perform(_ writes: [FanKextWrite], packageTemp: Double? = nil) async {
        guard !writes.isEmpty else { return }
        let fallbackTemp = SystemMonitor.shared.snapshot.cpuTemperature ?? 0
        let statuses = await Task.detached(priority: .userInitiated) {
            FanCurveController.send(writes, packageTemp: packageTemp, fallbackTemp: fallbackTemp)
        }.value
        var firstFailure = KERN_SUCCESS
        for (write, status) in zip(writes, statuses) {
            guard status == KERN_SUCCESS else {
                if firstFailure == KERN_SUCCESS { firstFailure = status }
                continue
            }
            if let held = FanKextWritePlan.heldCurve(after: write) {
                kextMappings[held.fan] = held.curve
            }
        }
        if firstFailure != KERN_SUCCESS {
            privilegeError = ProcessorModel.privilegeHint(for: firstFailure)
        }
    }

    /// The kernel IPC of `perform`: one status per write, in order.
    nonisolated private static func send(_ writes: [FanKextWrite],
                                         packageTemp: Double?,
                                         fallbackTemp: Double) -> [kern_return_t] {
        var temp = packageTemp
        if temp == nil, writes.contains(where: \.isManualDuty),
           let packet = ProcessorModel.shared.getTelemetry(), packet.packageTempC > 0 {
            temp = Double(packet.packageTempC)
        }
        let guardTemp = temp ?? fallbackTemp
        return writes.map { write in
            switch write {
            case .mapToCurve(let fan, let curve):
                return ProcessorModel.shared.mapKextFanToCurve(fanIndex: fan, curveIndex: curve)
            case .manualDuty(let fan, let pwm):
                // The duty is the user's, already clamped where it was set;
                // only the emergency guard is added here.
                let effective = AMDFanSafety.guardOnlyPWM(userPWM: pwm, currentTemp: guardTemp)
                return ProcessorModel.shared.setFanSpeed(pwm: Int(effective), fanIndex: fan)
            case .biosControl(let fan):
                return ProcessorModel.shared.setFanMode(auto: true, fanIndex: fan)
            }
        }
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
        let temp = Float(tempToSend)
        enqueueKextWrite { controller in
            let status = await Task.detached(priority: .utility) {
                ProcessorModel.shared.setKextGPUTemp(temp)
            }.value
            controller.noteGPUBridgeResult(status)
        }
    }

    private func noteGPUBridgeResult(_ status: kern_return_t) {
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
    //
    // The local state changes at once, so the UI answers the click; the
    // kext writes follow through the ordered chain.

    func setFanMode(fanId: Int, mode: FanControlMode, curveIndex: Int? = nil, manualPWM: UInt8? = nil) {
        switch mode {
        case .auto:
            var updated = fanMappings
            updated[fanId] = -1
            fanMappings = updated
            updateFanLocalState(fanId: fanId, mode: .auto, curveIdx: nil, manualPWM: nil)
            enqueueFanWrites([.mapToCurve(fan: fanId, curve: -1), .biosControl(fan: fanId)])

        case .curve:
            let targetIdx = curveIndex ?? 0
            guard targetIdx >= 0 && targetIdx < customCurves.count else { return }
            // The mapping's didSet queues the curve upload and then the
            // mapping write, so the fan only follows a slot already uploaded.
            var updated = fanMappings
            updated[fanId] = targetIdx
            fanMappings = updated
            updateFanLocalState(fanId: fanId, mode: .curve, curveIdx: targetIdx, manualPWM: nil)

        case .manual:
            var updated = fanMappings
            updated[fanId] = -1
            fanMappings = updated
            let safePWM = AMDFanSafety.clampManualPWM(manualPWM ?? 128)
            updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: safePWM)
            // Unmaps the fan only if the kext still runs a curve on it, then
            // writes the duty in the same job, with the thermal guard read
            // at write time.
            enqueueFanStateSync(only: [fanId], assertDutyFor: [fanId])
        }
    }

    /// Package temperature for the views' thermal-guard hint: the poll's
    /// last reading, which it takes while a fan view is on screen. No kext
    /// call here: SwiftUI bodies read it.
    var currentCPUOrPackageTemp: Double {
        lastPackageTempC ?? SystemMonitor.shared.snapshot.cpuTemperature ?? 0.0
    }

    /// S2-T2: true while the emergency thermal guard is clamping manual fans
    /// (temp at/above 85 °C) — drives the UI hint in FanControlCard.
    var isThermalGuardActive: Bool {
        currentCPUOrPackageTemp >= AMDFanSafety.thermalGuardTempC
    }

    func setManualPWM(fanId: Int, pwm: UInt8) {
        let safePWM = AMDFanSafety.clampManualPWM(pwm)
        updateFanLocalState(fanId: fanId, mode: .manual, curveIdx: nil, manualPWM: safePWM)
        // A fan already off its curve is not unmapped again: that would hand
        // it to the BIOS before every slider step.
        enqueueFanStateSync(only: [fanId], assertDutyFor: [fanId])
    }

    func setAllAuto() {
        var updated = fanMappings
        var writes: [FanKextWrite] = []
        for f in fans {
            updated[f.id] = -1
            writes += [.mapToCurve(fan: f.id, curve: -1), .biosControl(fan: f.id)]
            updateFanLocalState(fanId: f.id, mode: .auto, curveIdx: nil, manualPWM: nil)
        }
        fanMappings = updated
        enqueueFanWrites(writes)
    }

    func setAllMaxSpeed() {
        var updated = fanMappings
        for f in fans {
            updated[f.id] = -1
            updateFanLocalState(fanId: f.id, mode: .manual, curveIdx: nil, manualPWM: 255)
        }
        fanMappings = updated
        let ids = Set(fans.map(\.id))
        enqueueFanStateSync(only: ids, assertDutyFor: ids)
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
    /// Quit calls it directly: a write still queued behind it is undone by
    /// the kext's dead-man switch when the connection closes right after.
    nonisolated func resetFansToAutoSync() {
        Self.resetAllHeadersToAuto()
    }

    nonisolated private static func resetAllHeadersToAuto() {
        for fanId in 0..<16 {
            ProcessorModel.shared.mapKextFanToCurve(fanIndex: fanId, curveIndex: -1)
            ProcessorModel.shared.setFanMode(auto: true, fanIndex: fanId)
        }
    }

    /// Turning the curves off: every header back to the BIOS, the mappings
    /// cleared and the fan list showing Auto right away. The reset joins the
    /// write chain, so a manual write queued before it cannot land after it.
    func disableCurves() {
        for fan in fans {
            updateFanLocalState(fanId: fan.id, mode: .auto, curveIdx: nil, manualPWM: nil)
        }
        fanMappings = [:]
        enqueueKextWrite { controller in
            await Task.detached(priority: .userInitiated) {
                FanCurveController.resetAllHeadersToAuto()
            }.value
            controller.kextMappings = [:]
        }
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
            // A reconnect hands every fan to the BIOS, so the kext reports
            // the user's manual fans as auto; they stay manual here and get
            // their duty back with the forced sync.
            var manualBefore: [Int: UInt8] = [:]
            for fan in self.fans where fan.controlMode == .manual {
                if let pwm = fan.manualPWM { manualBefore[fan.id] = pwm }
            }
            self.rebuildFans(from: snapshots, keepingManual: manualBefore)
            let keptManual = Set(self.fans.filter { manualBefore[$0.id] != nil && $0.controlMode == .manual }.map(\.id))
            self.syncCurvesToKext(force: true)
            self.syncMappingsToKext(force: true, reapplyingDutyFor: keptManual)
        }
    }

    private func rebuildFans(from snapshots: [FanSnapshot], keepingManual manualBefore: [Int: UInt8] = [:]) {
        let defaults = UserDefaults.standard
        let savedHidden = Set((defaults.array(forKey: "HiddenFanIDs") as? [Int]) ?? [])
        fans = snapshots.map { snap in
            let mappedIdx = fanMappings[snap.id]
            let mode: FanControlMode
            if let mappedIdx, mappedIdx >= 0 && mappedIdx < customCurves.count {
                mode = .curve
            } else if snap.isOverridden || manualBefore[snap.id] != nil {
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
                manualPWM: (mode == .manual) ? (manualBefore[snap.id] ?? snap.throttle) : nil,
                isHidden: savedHidden.contains(snap.id),
                customName: defaults.string(forKey: "FanName_\(snap.id)"),
                rpmValid: snap.rpmValid
            )
        }
        self.rpmRuns.removeAll()
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
            // Nothing refreshes it any more; a later hint must not show it.
            lastPackageTempC = nil
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
        // The thermal guard needs it, and so does the hint an open fan view
        // shows (`isThermalGuardActive`, the curve editor's marker).
        let wantsCPUTemp = fans.contains { $0.controlMode == .manual } || viewPollingClients > 0
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
            self.lastPackageTempC = packageTemp.flatMap { $0 > 0 ? $0 : nil }
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

    /// Folds one RPM reading into a fan's run and answers whether the
    /// channel now looks frozen (`AMDFanSafety.isTachometerFrozen`).
    private func recordRPM(_ rpm: UInt64, for fanId: Int) -> Bool {
        let run = AMDFanSafety.advanceTachometerRun(rpmRuns[fanId], rpm: rpm,
                                                    at: ProcessInfo.processInfo.systemUptime)
        rpmRuns[fanId] = run
        return AMDFanSafety.isTachometerFrozen(run)
    }

    /// `packageTemp` is the kext's reading taken by this poll; without one
    /// the system monitor's CPU temperature stands in.
    private func enforceManualThermalGuard(packageTemp: Double?) {
        let temp = packageTemp.flatMap { $0 > 0 ? $0 : nil }
            ?? SystemMonitor.shared.snapshot.cpuTemperature ?? 0
        var writes: [FanKextWrite] = []
        for fan in fans {
            guard fan.controlMode == .manual, let userPWM = fan.manualPWM else { continue }
            // guardOnlyPWM, not effectiveManualPWM. `manualPWM` seeds
            // from the hardware's current duty (often a fixed BIOS setpoint),
            // so applying the user-commanded floor here would silently ramp
            // BIOS-fixed fans up on the first poll after an update. The floor
            // is enforced where the USER sets duty (setManualPWM and the
            // slider); the enforcement loop only arms the emergency guard.
            // Intentional divergence from effectiveManualPWM — do not "fix".
            // `send` applies the same guardOnlyPWM at write time.
            let effectivePWM = AMDFanSafety.guardOnlyPWM(userPWM: userPWM, currentTemp: temp)
            if fan.throttlePWM != effectivePWM {
                writes.append(.manualDuty(fan: fan.id, pwm: userPWM))
            }
        }
        guard !writes.isEmpty else { return }
        enqueueKextWrite { controller in
            await controller.perform(writes, packageTemp: temp)
        }
    }
}

typealias FanController = FanCurveController
