// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI
import UserNotifications

struct MonitorAlertsControls: View {
    @ObservedObject private var l10n = L10n.shared
    let compact: Bool
    @State private var notificationsDenied = false
    @AppStorage(DefaultsKey.monitorAlertCPU) private var alertCPU = false
    @AppStorage(DefaultsKey.monitorAlertCPUTemperature) private var alertCPUTemperature = false
    @AppStorage(DefaultsKey.monitorAlertGPUTemperature) private var alertGPUTemperature = false
    @AppStorage(DefaultsKey.monitorAlertGPUPower) private var alertGPUPower = false
    @AppStorage(DefaultsKey.monitorAlertGPUMemoryTemperature) private var alertGPUMemoryTemperature = false
    @AppStorage(DefaultsKey.monitorAlertGPUThrottle) private var alertGPUThrottle = false
    @AppStorage(DefaultsKey.monitorAlertGPUMemoryTemperatureThreshold) private var alertGPUMemoryTemperatureThreshold = 90
    @ObservedObject private var gpuSensors = GPUSensorsService.shared
    @AppStorage(DefaultsKey.monitorAlertMemory) private var alertMemory = false
    @AppStorage(DefaultsKey.monitorAlertDisk) private var alertDisk = false
    @AppStorage(DefaultsKey.monitorAlertBattery) private var alertBattery = false
    @AppStorage(DefaultsKey.monitorAlertCPUThreshold) private var alertCPUThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertCPUTemperatureThreshold) private var alertCPUTemperatureThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertGPUTemperatureThreshold) private var alertGPUTemperatureThreshold = 85
    @AppStorage(DefaultsKey.monitorAlertGPUPowerThreshold) private var alertGPUPowerThreshold = 250
    @AppStorage(DefaultsKey.monitorAlertDiskFreePercent) private var alertDiskFreePercent = 10
    @AppStorage(DefaultsKey.monitorAlertBatteryPercent) private var alertBatteryPercent = 15
    @AppStorage(DefaultsKey.monitorAlertCooldownMinutes) private var alertCooldown = 15

    private var text: MonitorAlertFeatureStrings {
        FeatureStrings.monitorAlerts(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
            Text(text.caption)
                .font(compact ? .system(size: 9.5) : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if AppFeature.monitorCPU.isAvailable {
                Toggle(text.cpu, isOn: $alertCPU)
                if alertCPU {
                    Stepper("\(text.cpuThreshold) \(alertCPUThreshold)%",
                            value: $alertCPUThreshold,
                            in: 50...100,
                            step: 5)
                }
                Toggle(text.cpuTemperature, isOn: $alertCPUTemperature)
                if alertCPUTemperature {
                    Stepper("\(text.cpuTemperatureThreshold) \(alertCPUTemperatureThreshold) °C",
                            value: $alertCPUTemperatureThreshold,
                            in: 70...105,
                            step: 5)
                }
            }
            if AppFeature.monitorGPU.isAvailable {
                Toggle(text.gpuTemperature, isOn: $alertGPUTemperature)
                if alertGPUTemperature {
                    Stepper("\(text.gpuTemperatureThreshold) \(alertGPUTemperatureThreshold) °C",
                            value: $alertGPUTemperatureThreshold,
                            in: 50...120,
                            step: 5)
                }
                Toggle(text.gpuPower, isOn: $alertGPUPower)
                if alertGPUPower {
                    Stepper("\(text.gpuPowerThreshold) \(alertGPUPowerThreshold) W",
                            value: $alertGPUPowerThreshold,
                            in: 50...500,
                            step: 25)
                }
                // Only with GPUSensors.kext, or while one is still switched
                // on after the kext went away, so it can be switched off.
                if gpuSensors.isPresent || alertGPUMemoryTemperature {
                    Toggle(text.gpuMemoryTemperature, isOn: $alertGPUMemoryTemperature)
                    if alertGPUMemoryTemperature {
                        Stepper("\(text.gpuMemoryTemperatureThreshold) \(alertGPUMemoryTemperatureThreshold) °C",
                                value: $alertGPUMemoryTemperatureThreshold,
                                in: 60...110,
                                step: 5)
                        hint(text.gpuMemoryTemperatureHint)
                    }
                }
                if gpuSensors.isPresent || alertGPUThrottle {
                    Toggle(text.gpuThrottle, isOn: $alertGPUThrottle)
                    if alertGPUThrottle {
                        hint(text.gpuThrottleHint)
                    }
                }
            }
            if AppFeature.monitorMemory.isAvailable {
                Toggle(text.memory, isOn: $alertMemory)
            }
            if AppFeature.monitorDisk.isAvailable {
                Toggle(text.disk, isOn: $alertDisk)
                if alertDisk {
                    Stepper("\(text.diskThreshold) \(alertDiskFreePercent)%",
                            value: $alertDiskFreePercent,
                            in: 5...30,
                            step: 5)
                }
            }
            if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
                Toggle(text.battery, isOn: $alertBattery)
                if alertBattery {
                    Stepper("\(text.batteryThreshold) \(alertBatteryPercent)%",
                            value: $alertBatteryPercent,
                            in: 5...50,
                            step: 5)
                }
            }
            if anyAlertEnabled {
                Picker(text.cooldown, selection: $alertCooldown) {
                    Text(text.cooldown2).tag(2)
                    Text(text.cooldown5).tag(5)
                    Text(text.cooldown15).tag(15)
                    Text(text.cooldown30).tag(30)
                    Text(text.cooldown60).tag(60)
                }
                .pickerStyle(.menu)
            }
            // Alerts silently cannot fire when macOS notifications are denied
            // for the app; without this line that state is invisible (the
            // user just never hears anything).
            if notificationsDenied, anyAlertEnabled {
                Text(text.notificationsDenied)
                    .font(compact ? .system(size: 9.5) : .caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(compact ? .small : .regular)
        .font(compact ? .system(size: 10.5) : .body)
        .onAppear {
            sanitizeAlertValues()
            refreshNotificationStatus()
        }
        // One handler per kind keeps this body cheap to type-check.
        .onChange(of: alertSwitches) { _, _ in
            MonitorAlertService.shared.syncWithPreferences()
            refreshNotificationStatus()
        }
        .onChange(of: alertValues) { _, _ in sanitizeAlertValues() }
    }

    private func hint(_ string: String) -> some View {
        Text(string)
            .font(compact ? .system(size: 9.5) : .caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var alertSwitches: [Bool] {
        [alertCPU, alertCPUTemperature, alertGPUTemperature, alertGPUPower, alertGPUMemoryTemperature,
         alertGPUThrottle, alertMemory, alertDisk, alertBattery]
    }
    private var alertValues: [Int] {
        [alertCPUThreshold, alertCPUTemperatureThreshold, alertGPUTemperatureThreshold, alertGPUPowerThreshold,
         alertGPUMemoryTemperatureThreshold, alertDiskFreePercent, alertBatteryPercent, alertCooldown]
    }
    private var anyAlertEnabled: Bool {
        alertCPU || alertCPUTemperature || alertGPUTemperature || alertGPUPower || alertMemory || alertDisk
            || alertGPUMemoryTemperature || alertGPUThrottle
            || (PowerSampler.hasInternalBattery && alertBattery)
    }

    /// Checked slightly delayed so a just-fired authorization prompt has a
    /// chance to be answered before the warning appears.
    private func refreshNotificationStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsDenied = settings.authorizationStatus == .denied
                }
            }
        }
    }

    private func sanitizeAlertValues() {
        alertCPUThreshold = Defaults.sanitizedPercent(alertCPUThreshold, fallback: 90, range: 50...100)
        alertCPUTemperatureThreshold = Defaults.sanitizedPercent(alertCPUTemperatureThreshold, fallback: 90, range: 70...105)
        alertGPUTemperatureThreshold = Defaults.sanitizedPercent(alertGPUTemperatureThreshold, fallback: 90, range: 50...120)
        alertGPUPowerThreshold = max(50, min(500, alertGPUPowerThreshold))
        alertGPUMemoryTemperatureThreshold = Defaults.sanitizedPercent(alertGPUMemoryTemperatureThreshold, fallback: 90, range: 60...110)
        alertDiskFreePercent = Defaults.sanitizedPercent(alertDiskFreePercent, fallback: 10, range: 5...30)
        alertBatteryPercent = Defaults.sanitizedPercent(alertBatteryPercent, fallback: 15, range: 5...50)
        alertCooldown = Defaults.sanitizedMonitorAlertCooldown(alertCooldown)
    }
}
