// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// Optional Monitor notifications. Everything is off by default, throttled, and
/// driven by the existing SystemMonitor sampler.
@MainActor
final class MonitorAlertService {
    static let shared = MonitorAlertService()

    private var cancellables = Set<AnyCancellable>()
    private var highCPU = OverLimitTimer()
    private var highCPUTemp = OverLimitTimer()
    private var highCPUPower = OverLimitTimer()
    private var thermalThrottle = OverLimitTimer()
    private var highGPUTemp = OverLimitTimer()
    private var highGPUPower = OverLimitTimer()
    private var criticalMemory = OverLimitTimer()
    private var lowDiskSpace = OverLimitTimer()
    private var lowBatteryLevel = OverLimitTimer()
    private var gpuMemoryHot = SustainedCondition(duration: 12, allowedMisses: 2)
    private var gpuHeldBack = SustainedCondition(duration: 12, allowedMisses: 2)
    /// The GPUSensors sample the two kext alerts last counted; a sample
    /// carried over between strides is counted once, not once per tick.
    private var gpuSensorsGate = FreshSampleGate()
    private var cooldown = AlertCooldownGate<MonitorAlertKind>()

    private init() {}

    /// Owns the whole lifecycle: the snapshot sink only exists while some
    /// alert is on for an available metric, so the service costs nothing
    /// otherwise. The alert toggles in Settings call this on every change.
    func syncWithPreferences() {
        let enabled = Self.anyEnabled(in: .standard)
        if enabled {
            startSinkIfNeeded()
        } else {
            stopSink()
        }
        SystemMonitor.shared.setAlertsActive(enabled)
        if enabled {
            Notifier.requestPermission()
        }
    }

    /// The GPUSensors.kext alerts count only while the kext is there, so a
    /// switch left on after it went away keeps nothing running.
    nonisolated static func anyEnabled(in defaults: UserDefaults,
                           gpuSensorsPresent: Bool = GPUSensorsService.shared.isPresentNow) -> Bool {
        AppFeature.anyMonitorAlertEnabled(
            isAvailable: {
                defaults.bool(forKey: $0.availabilityKey)
                    && ($0 != .monitorPower || PowerSampler.hasInternalBattery)
            },
            boolFor: { key in
                guard defaults.bool(forKey: key) else { return false }
                return gpuSensorsPresent || !DefaultsKey.gpuSensorsAlertKeys.contains(key)
            }
        )
    }

    private func startSinkIfNeeded() {
        guard cancellables.isEmpty else { return }
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
            .store(in: &cancellables)
    }

    private func stopSink() {
        cancellables.removeAll()
        stopTimers()
    }

    private func stopTimers() {
        highCPU.reset()
        highCPUTemp.reset()
        highCPUPower.reset()
        thermalThrottle.reset()
        highGPUTemp.reset()
        highGPUPower.reset()
        criticalMemory.reset()
        lowDiskSpace.reset()
        lowBatteryLevel.reset()
        gpuMemoryHot.reset()
        gpuHeldBack.reset()
        gpuSensorsGate = FreshSampleGate()
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        let defaults = UserDefaults.standard
        guard Self.anyEnabled(in: defaults) else {
            stopTimers()
            return
        }
        let strings = FeatureStrings.monitorAlerts(L10n.shared.language)
        let now = Date()
        let sustain = defaults.integer(forKey: DefaultsKey.monitorAlertSustainSeconds)
        /// Each alert's own wait, made longer by the "for at least" choice.
        func wait(_ builtIn: TimeInterval) -> TimeInterval {
            MonitorAlertSustain.wait(builtIn: builtIn, chosenSeconds: sustain)
        }

        func alertOn(_ key: String, _ feature: AppFeature) -> Bool {
            defaults.bool(forKey: key)
                && defaults.bool(forKey: feature.availabilityKey)
                && (feature != .monitorPower || PowerSampler.hasInternalBattery)
        }

        if alertOn(DefaultsKey.monitorAlertCPU, .monitorCPU) {
            evaluateCPU(snapshot.cpuUsage, defaults: defaults, strings: strings, now: now, wait: wait(12))
        } else {
            highCPU.reset()
        }

        if alertOn(DefaultsKey.monitorAlertCPUTemperature, .monitorCPU) {
            if let temperature = highCPUTemperature(from: snapshot, defaults: defaults, now: now, wait: wait(5)) {
                send(at: now, .cpuTemperature,
                     title: strings.cpuTemperatureTitle,
                     body: String(format: strings.cpuTemperatureBodyFormat,
                                  Self.formattedTemperature(temperature, defaults: defaults)))
            }
        } else {
            highCPUTemp.reset()
        }

        // Same 12 s wait as the GPU power alert, so a short boost spike of
        // the package power does not notify.
        if alertOn(DefaultsKey.monitorAlertCPUPower, .monitorCPU) {
            let threshold = Defaults.sanitizedMonitorAlertCPUPowerThreshold(
                defaults.integer(forKey: DefaultsKey.monitorAlertCPUPowerThreshold))
            let power = snapshot.cpuPower
            if highCPUPower.update(isOver: Self.cpuPowerIsOver(power, thresholdWatts: threshold),
                                   now: now, wait: wait(12)),
               let power {
                send(at: now, .cpuPower,
                     title: strings.cpuPowerTitle,
                     body: String(format: strings.cpuPowerBodyFormat, power))
            }
        } else {
            highCPUPower.reset()
        }

        // The helpers own their timers: they start one on the first hot
        // reading and return nil while it runs. Clearing it here on that nil
        // restarted the wait on every sample, so these alerts never fired.
        if alertOn(DefaultsKey.monitorAlertGPUTemperature, .monitorGPU) {
            if let gpuTemp = highGPUTemperature(from: snapshot, defaults: defaults, now: now, wait: wait(12)) {
                send(at: now, .gpuTemperature,
                     title: strings.gpuTemperatureTitle,
                     body: String(format: strings.gpuTemperatureBodyFormat,
                                  Self.formattedTemperature(gpuTemp, defaults: defaults)))
            }
        } else {
            highGPUTemp.reset()
        }

        if alertOn(DefaultsKey.monitorAlertGPUPower, .monitorGPU) {
            if let gpuPower = highGPUPower(from: snapshot, defaults: defaults, now: now, wait: wait(12)) {
                send(at: now, .gpuPower,
                     title: strings.gpuPowerTitle,
                     body: String(format: strings.gpuPowerBodyFormat, gpuPower))
            }
        } else {
            highGPUPower.reset()
        }

        // GPUSensors.kext alerts. Without the kext `gpuSensors` is nil and
        // the waits are dropped. With alerts alone the kext is read every
        // few seconds while snapshots arrive every second, so each sample
        // counts once.
        let memoryAlertOn = alertOn(DefaultsKey.monitorAlertGPUMemoryTemperature, .monitorGPU)
        let throttleAlertOn = alertOn(DefaultsKey.monitorAlertGPUThrottle, .monitorGPU)
        if !memoryAlertOn { gpuMemoryHot.reset() }
        if !throttleAlertOn { gpuHeldBack.reset() }
        if let sensors = snapshot.gpuSensors {
            if gpuSensorsGate.isFresh(snapshot.gpuSensorsTakenAt) {
                if memoryAlertOn {
                    let threshold = Defaults.sanitizedPercent(
                        defaults.integer(forKey: DefaultsKey.monitorAlertGPUMemoryTemperatureThreshold),
                        fallback: 90,
                        range: 60...110)
                    let memory = sensors.memory
                    if gpuMemoryHot.update(memory.map { $0 >= Double(threshold) } ?? false, now: now,
                                           atLeast: wait(0)), let memory {
                        send(at: now, .gpuMemoryTemperature,
                             title: strings.gpuMemoryTemperatureTitle,
                             body: String(format: strings.gpuMemoryTemperatureBodyFormat,
                                          Self.formattedTemperature(memory, defaults: defaults)))
                    }
                }
                if throttleAlertOn {
                    let throttle = sensors.throttle
                    if gpuHeldBack.update(throttle?.holdsClocksBack ?? false, now: now, atLeast: wait(0)), let throttle {
                        // The power limit is left out of the reasons: it is normal.
                        let reasons = throttle.subtracting(.power).text(FeatureStrings.sensors(L10n.shared.language))
                        send(at: now, .gpuThrottle,
                             title: strings.gpuThrottleTitle,
                             body: String(format: strings.gpuThrottleBodyFormat, reasons))
                    }
                }
            }
        } else {
            gpuMemoryHot.reset()
            gpuHeldBack.reset()
        }
        // These three had no wait of their own: with "Immediately" the first
        // sample over the limit still notifies.
        if alertOn(DefaultsKey.monitorAlertMemory, .monitorMemory) {
            if criticalMemory.update(isOver: snapshot.memoryPressure == .critical, now: now, wait: wait(0)) {
                send(at: now, .memory, title: strings.memoryTitle, body: strings.memoryBody)
            }
        } else {
            criticalMemory.reset()
        }

        if alertOn(DefaultsKey.monitorAlertDisk, .monitorDisk) {
            let disk = lowDisk(from: snapshot, defaults: defaults)
            if lowDiskSpace.update(isOver: disk != nil, now: now, wait: wait(0)), let disk {
                let body = String(format: strings.diskBodyFormat, disk.name, disk.threshold)
                send(at: now, .disk, title: strings.diskTitle, body: body)
            }
        } else {
            lowDiskSpace.reset()
        }

        if alertOn(DefaultsKey.monitorAlertBattery, .monitorPower) {
            let battery = lowBattery(from: snapshot, defaults: defaults)
            if lowBatteryLevel.update(isOver: battery != nil, now: now, wait: wait(0)), let battery {
                let body = String(format: strings.batteryBodyFormat, battery)
                send(at: now, .battery, title: strings.batteryTitle, body: body)
            }
        } else {
            lowBatteryLevel.reset()
        }

        let tempThreshold = Defaults.sanitizedPercent(
            defaults.integer(forKey: DefaultsKey.monitorAlertCPUTemperatureThreshold),
            fallback: 90,
            range: 70...105
        )
        let thermalLimit = max(85.0, Double(tempThreshold))

        let throttling = (snapshot.cpuTemperature ?? 0) >= thermalLimit && (snapshot.cpuUsage ?? 0) >= 0.85
        // Not one of the switches in Settings: its text says 30 s, so the
        // "for at least" choice leaves it alone. The wait starts over after
        // each notice, as it always has.
        if thermalThrottle.update(isOver: throttling, now: now, wait: 30),
           let temp = snapshot.cpuTemperature {
            let ccdInfo = snapshot.ccd0Temperature.map {
                " (CCD0: \(Self.formattedTemperature(Double($0), defaults: defaults)))"
            } ?? ""
            send(at: now, .thermalThrottle,
                 title: strings.thermalThrottleTitle,
                 body: String(format: strings.thermalThrottleBodyFormat,
                              Self.formattedTemperature(temp, defaults: defaults)) + ccdInfo)
            thermalThrottle.reset()
        }
    }

    private func evaluateCPU(_ usage: Double?,
                             defaults: UserDefaults,
                             strings: MonitorAlertFeatureStrings,
                             now: Date,
                             wait: TimeInterval) {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUThreshold),
                                                  fallback: 90,
                                                  range: 50...100)
        let over = usage.map { $0 >= Double(threshold) / 100.0 } ?? false
        guard highCPU.update(isOver: over, now: now, wait: wait) else { return }
        send(at: now, .cpu,
             title: strings.cpuTitle,
             body: String(format: strings.cpuBodyFormat, threshold))
    }

    private func lowDisk(from snapshot: SystemSnapshot,
                         defaults: UserDefaults) -> (name: String, threshold: Int)? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertDiskFreePercent),
                                                  fallback: 10,
                                                  range: 5...30)
        guard let device = snapshot.disk?.devices.first(where: { device in
            guard device.totalBytes >= 10_000_000_000 else { return false }
            let freePercent = Double(device.freeBytes) / Double(device.totalBytes) * 100.0
            return freePercent < Double(threshold)
        }) else { return nil }
        return (device.name, threshold)
    }

    private func highCPUTemperature(from snapshot: SystemSnapshot,
                                    defaults: UserDefaults,
                                    now: Date,
                                    wait: TimeInterval) -> Double? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUTemperatureThreshold),
                                                  fallback: 90,
                                                  range: 70...105)
        let temperature = snapshot.cpuTemperature
        let over = temperature.map { $0 >= Double(threshold) } ?? false
        guard highCPUTemp.update(isOver: over, now: now, wait: wait) else { return nil }
        return temperature
    }

    private func highGPUTemperature(from snapshot: SystemSnapshot,
                                     defaults: UserDefaults,
                                     now: Date,
                                     wait: TimeInterval) -> Double? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertGPUTemperatureThreshold),
                                                  fallback: 85,
                                                  range: 50...120)
        let temp = snapshot.gpuTemperature
        let over = temp.map { $0 >= Double(threshold) } ?? false
        guard highGPUTemp.update(isOver: over, now: now, wait: wait) else { return nil }
        return temp
    }

    private func highGPUPower(from snapshot: SystemSnapshot,
                               defaults: UserDefaults,
                               now: Date,
                               wait: TimeInterval) -> Double? {
        let threshold = max(1, Double(defaults.integer(forKey: DefaultsKey.monitorAlertGPUPowerThreshold)))
        let power = snapshot.gpuPower
        let over = power.map { $0 >= threshold } ?? false
        guard highGPUPower.update(isOver: over, now: now, wait: wait) else { return nil }
        return power
    }

    private func lowBattery(from snapshot: SystemSnapshot,
                            defaults: UserDefaults) -> Int? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertBatteryPercent),
                                                  fallback: 15,
                                                  range: 5...50)
        guard let power = snapshot.power,
              power.hasBattery,
              !power.isCharging,
              let charge = power.chargePercent,
              charge <= threshold else { return nil }
        return charge
    }

    /// Alerts speak the unit the rest of the app shows, not always Celsius.
    private static func formattedTemperature(_ celsius: Double, defaults: UserDefaults) -> String {
        let unit = TemperatureUnit(rawValue: defaults.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
        return MetricFormat.temperature(celsius, unit: unit)
    }

    /// A CPU package power reading over the limit. The kext reports 0 W
    /// while it has no reading; the snapshot leaves that out as nil.
    nonisolated static func cpuPowerIsOver(_ watts: Double?, thresholdWatts: Int) -> Bool {
        guard let watts, watts > 0 else { return false }
        return watts >= Double(thresholdWatts)
    }

    /// `now` is the time the sample was judged at, so the repeat interval
    /// starts from the same clock as the waits.
    private func send(at now: Date, _ kind: MonitorAlertKind, title: String, body: String) {
        let minutes = Defaults.sanitizedMonitorAlertCooldown(
            UserDefaults.standard.integer(forKey: DefaultsKey.monitorAlertCooldownMinutes)
        )
        guard cooldown.allows(kind, now: now, interval: Double(minutes * 60)) else { return }
        Notifier.post(title: title, body: body)
    }
}

private enum MonitorAlertKind: Hashable {
    case cpu, cpuTemperature, cpuPower, gpuTemperature, gpuPower, memory, disk, battery, thermalThrottle
    // Each has its own wait between notices: an 85 °C hotspot alert, normal
    // under load on Navi 21, must not hold back a VRAM or held-back warning.
    case gpuMemoryTemperature, gpuThrottle
}

/// Lets a sample through once: a snapshot that carries the same reading as
/// the last one (same `takenAt`) is not a new observation.
struct FreshSampleGate {
    private(set) var last: TimeInterval?

    mutating func isFresh(_ takenAt: TimeInterval?) -> Bool {
        guard let takenAt, takenAt != last else { return false }
        last = takenAt
        return true
    }
}

/// A condition that has to hold for `duration` before it counts. Up to
/// `allowedMisses` samples in a row may fall short without starting over, so
/// one idle or missing sample from the GPU does not reset a long wait.
struct SustainedCondition {
    let duration: TimeInterval
    let allowedMisses: Int
    private(set) var since: Date?
    private var misses = 0
    private var lastSample: Date?

    init(duration: TimeInterval, allowedMisses: Int) {
        self.duration = duration
        self.allowedMisses = allowedMisses
    }

    /// True once the condition has held, give or take the allowed misses,
    /// for `duration`, and on every holding sample after that.
    /// `atLeast` makes the wait longer than `duration`, never shorter.
    mutating func update(_ holds: Bool, now: Date, atLeast minimum: TimeInterval = 0) -> Bool {
        // Nothing samples while the Mac sleeps: a wait never spans the gap.
        if MonitorAlertSustain.isBreak(since: lastSample, now: now) { reset() }
        lastSample = now
        guard holds else {
            if since != nil {
                misses += 1
                if misses > allowedMisses { reset() }
            }
            return false
        }
        misses = 0
        guard let since else {
            self.since = now
            return false
        }
        return now.timeIntervalSince(since) >= max(duration, minimum)
    }

    mutating func reset() {
        since = nil
        misses = 0
        lastSample = nil
    }
}

/// Since when a reading has been over its limit. A sample back under the
/// limit starts the wait over. With no wait, the first sample over the limit
/// counts; with one, the sample that starts it never does.
struct OverLimitTimer {
    private(set) var since: Date?
    private var lastSample: Date?

    /// True once the reading has been over the limit for `wait`, and on
    /// every sample over it after that; the repeat interval in
    /// `AlertCooldownGate` keeps those from notifying again.
    mutating func update(isOver: Bool, now: Date, wait: TimeInterval) -> Bool {
        // A long gap between samples (sleep, or a clock change) means the
        // reading was not watched in between: the wait starts over.
        if MonitorAlertSustain.isBreak(since: lastSample, now: now) { since = nil }
        lastSample = now
        guard isOver else {
            since = nil
            return false
        }
        guard let since else {
            self.since = now
            return wait <= 0
        }
        return now.timeIntervalSince(since) >= wait
    }

    mutating func reset() {
        since = nil
        lastSample = nil
    }
}

/// The "for at least" choice applied to an alert's own wait. The longer one
/// wins, so Immediately (0) leaves every alert as it was.
enum MonitorAlertSustain {
    /// The longest gap between two samples that still counts as watching.
    /// Samples come every 1 to 5 s, and the slowest temperature stride is
    /// about 15 s, so 45 s is three of those; sleep is far longer.
    static let maxSampleGap: TimeInterval = 45

    /// True when the time from the previous sample is too long, or runs
    /// backwards, for the reading to have been watched in between.
    static func isBreak(since previous: Date?, now: Date) -> Bool {
        guard let previous else { return false }
        let gap = now.timeIntervalSince(previous)
        return gap < 0 || gap > maxSampleGap
    }

    static func wait(builtIn: TimeInterval, chosenSeconds: Int) -> TimeInterval {
        max(builtIn, TimeInterval(Defaults.sanitizedMonitorAlertSustain(chosenSeconds)))
    }
}

/// One notice per kind per repeat interval ("Repeat the same alert after").
struct AlertCooldownGate<Kind: Hashable> {
    private(set) var lastSent: [Kind: Date] = [:]

    mutating func allows(_ kind: Kind, now: Date, interval: TimeInterval) -> Bool {
        if let previous = lastSent[kind], now.timeIntervalSince(previous) < interval {
            return false
        }
        lastSent[kind] = now
        return true
    }
}
