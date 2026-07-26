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
    private var highCPUSince: Date?
    private var thermalThrottleSince: Date?
    private var highGPUTempSince: Date?
    private var highGPUPowerSince: Date?
    private var lastSent: [MonitorAlertKind: Date] = [:]

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

    static func anyEnabled(in defaults: UserDefaults) -> Bool {
        AppFeature.anyMonitorAlertEnabled(
            isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
            boolFor: { defaults.bool(forKey: $0) }
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
        highCPUSince = nil
        thermalThrottleSince = nil
        highGPUTempSince = nil
        highGPUPowerSince = nil
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        let defaults = UserDefaults.standard
        guard Self.anyEnabled(in: defaults) else {
            highCPUSince = nil
            return
        }
        let strings = FeatureStrings.monitorAlerts(L10n.shared.language)

        func alertOn(_ key: String, _ feature: AppFeature) -> Bool {
            defaults.bool(forKey: key) && defaults.bool(forKey: feature.availabilityKey)
        }

        if alertOn(DefaultsKey.monitorAlertCPU, .monitorCPU) {
            evaluateCPU(snapshot.cpuUsage, defaults: defaults, strings: strings)
        } else {
            highCPUSince = nil
        }

        if alertOn(DefaultsKey.monitorAlertCPUTemperature, .monitorCPU),
           let temperature = highCPUTemperature(from: snapshot, defaults: defaults) {
            send(.cpuTemperature,
                 title: strings.cpuTemperatureTitle,
                 body: String(format: strings.cpuTemperatureBodyFormat, temperature))
        }

        if alertOn(DefaultsKey.monitorAlertGPUTemperature, .monitorGPU),
           let gpuTemp = highGPUTemperature(from: snapshot, defaults: defaults) {
            send(.gpuTemperature,
                 title: "GPU Temperature Warning",
                 body: String(format: "GPU temperature reached %d°C", gpuTemp))
        } else {
            highGPUTempSince = nil
        }

        if alertOn(DefaultsKey.monitorAlertGPUPower, .monitorGPU),
           let gpuPower = highGPUPower(from: snapshot, defaults: defaults) {
            send(.gpuPower,
                 title: "GPU Power Warning",
                 body: String(format: "GPU power reached %.0fW", gpuPower))
        } else {
            highGPUPowerSince = nil
        }

        if alertOn(DefaultsKey.monitorAlertMemory, .monitorMemory),
           snapshot.memoryPressure == .critical {
            send(.memory, title: strings.memoryTitle, body: strings.memoryBody)
        }

        if alertOn(DefaultsKey.monitorAlertDisk, .monitorDisk),
           let disk = lowDisk(from: snapshot, defaults: defaults) {
            let body = String(format: strings.diskBodyFormat, disk.name, disk.threshold)
            send(.disk, title: strings.diskTitle, body: body)
        }

        if alertOn(DefaultsKey.monitorAlertBattery, .monitorPower),
           let battery = lowBattery(from: snapshot, defaults: defaults) {
            let body = String(format: strings.batteryBodyFormat, battery)
            send(.battery, title: strings.batteryTitle, body: body)
        }

        if let temp = snapshot.cpuTemperature, temp >= 92.0,
           let usage = snapshot.cpuUsage, usage >= 0.85 {
            let now = Date()
            if thermalThrottleSince == nil {
                thermalThrottleSince = now
            } else if let since = thermalThrottleSince, now.timeIntervalSince(since) >= 30 {
                let ccdInfo = snapshot.ccd0Temperature.map { String(format: " (CCD0: %.0f°C)", $0) } ?? ""
                send(.thermalThrottle,
                     title: "Thermal Throttling Warning",
                     body: String(format: "Sustained CPU temperature at %.0f°C under heavy load for >30s%@", temp, ccdInfo))
            }
        } else {
            thermalThrottleSince = nil
        }
    }

    private func evaluateCPU(_ usage: Double?,
                             defaults: UserDefaults,
                             strings: MonitorAlertFeatureStrings) {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUThreshold),
                                                  fallback: 90,
                                                  range: 50...100)
        guard let usage, usage >= Double(threshold) / 100.0 else {
            highCPUSince = nil
            return
        }

        let now = Date()
        if highCPUSince == nil {
            highCPUSince = now
            return
        }
        guard let since = highCPUSince, now.timeIntervalSince(since) >= 12 else { return }
        send(.cpu,
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
                                    defaults: UserDefaults) -> Int? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUTemperatureThreshold),
                                                  fallback: 90,
                                                  range: 70...105)
        guard let temperature = snapshot.cpuTemperature,
              temperature >= Double(threshold) else { return nil }
        return Int(temperature.rounded())
    }

    private func highGPUTemperature(from snapshot: SystemSnapshot,
                                     defaults: UserDefaults) -> Int? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertGPUTemperatureThreshold),
                                                  fallback: 85,
                                                  range: 50...120)
        guard let temp = snapshot.gpuTemperature, temp >= Double(threshold) else {
            highGPUTempSince = nil
            return nil
        }
        let now = Date()
        if highGPUTempSince == nil {
            highGPUTempSince = now
            return nil
        }
        guard let since = highGPUTempSince, now.timeIntervalSince(since) >= 12 else { return nil }
        return Int(temp.rounded())
    }

    private func highGPUPower(from snapshot: SystemSnapshot,
                               defaults: UserDefaults) -> Double? {
        let threshold = max(1, Double(defaults.integer(forKey: DefaultsKey.monitorAlertGPUPowerThreshold)))
        guard let power = snapshot.gpuPower, power >= threshold else {
            highGPUPowerSince = nil
            return nil
        }
        let now = Date()
        if highGPUPowerSince == nil {
            highGPUPowerSince = now
            return nil
        }
        guard let since = highGPUPowerSince, now.timeIntervalSince(since) >= 12 else { return nil }
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

    private func send(_ kind: MonitorAlertKind, title: String, body: String) {
        let now = Date()
        let minutes = Defaults.sanitizedMonitorAlertCooldown(
            UserDefaults.standard.integer(forKey: DefaultsKey.monitorAlertCooldownMinutes)
        )
        if let previous = lastSent[kind], now.timeIntervalSince(previous) < Double(minutes * 60) {
            return
        }
        lastSent[kind] = now
        Notifier.post(title: title, body: body)
    }
}

private enum MonitorAlertKind: Hashable {
    case cpu, cpuTemperature, gpuTemperature, gpuPower, memory, disk, battery, thermalThrottle
}
