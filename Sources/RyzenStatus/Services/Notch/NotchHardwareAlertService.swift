// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Proactive Dynamic Island hardware alerts for AMD Ryzen systems.
/// Monitors thermal, PPT power and fan health metrics and alerts through the Dynamic Island.
final class NotchHardwareAlertService: @unchecked Sendable {
    static let shared = NotchHardwareAlertService()

    private var subscription: AnyCancellable?
    private var thermalStreak = 0
    private var lastThermalAlert: Date?
    private var lastPowerAlert: Date?
    private var lastFanAlert: Date?
    private let cooldown: TimeInterval = 35

    private init() {}

    func start() {
        guard subscription == nil else { return }
        subscription = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchHardwareAlertsEnabled) else { return }
        let now = Date()

        // 1. Thermal Spike Check
        if let temp = snapshot.cpuTemperature {
            if temp >= 85.0 {
                thermalStreak += 1
                if thermalStreak >= 3,
                   lastThermalAlert == nil || now.timeIntervalSince(lastThermalAlert!) >= cooldown {
                    lastThermalAlert = now
                    NotchSoundCueService.shared.play(.error)
                    let notice = NotchNotice(
                        event: .hardwareAlert,
                        title: "CPU Thermal Alert",
                        detail: String(format: "%.0f°C", temp),
                        symbol: "flame.fill",
                        mascot: .surprised
                    )
                    NotchService.shared.show(notice)
                }
            } else if temp < 78.0 {
                thermalStreak = 0
            }
        }

        // 2. PPT Power Limit Check
        if let power = snapshot.cpuPower, power >= 140.0 {
            if lastPowerAlert == nil || now.timeIntervalSince(lastPowerAlert!) >= cooldown {
                lastPowerAlert = now
                NotchSoundCueService.shared.play(.context)
                let notice = NotchNotice(
                    event: .hardwareAlert,
                    title: "PPT Saturation",
                    detail: String(format: "%.0fW", power),
                    symbol: "bolt.fill",
                    mascot: .surprised
                )
                NotchService.shared.show(notice)
            }
        }

        // 3. Fan Stall Check under load
        if let temp = snapshot.cpuTemperature, temp >= 72.0,
           let fan = snapshot.gpuFan, fan == 0 {
            if lastFanAlert == nil || now.timeIntervalSince(lastFanAlert!) >= (cooldown * 1.5) {
                lastFanAlert = now
                NotchSoundCueService.shared.play(.error)
                let notice = NotchNotice(
                    event: .hardwareAlert,
                    title: "Fan Check",
                    detail: "0 RPM",
                    symbol: "fanblades.slash",
                    mascot: .confused
                )
                NotchService.shared.show(notice)
            }
        }
    }
}
