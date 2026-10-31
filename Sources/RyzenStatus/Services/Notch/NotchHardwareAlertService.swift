// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// The rules behind the hardware alerts, kept pure for the tests.
enum NotchHardwareAlertSupport {
    /// Readings in a row at or past `trigger`; one below `release` resets.
    static func nextStreak(_ streak: Int, value: Double, trigger: Double, release: Double) -> Int {
        if value >= trigger { return streak + 1 }
        return value < release ? 0 : streak
    }

    static func cooledDown(_ last: Date?, now: Date, cooldown: TimeInterval) -> Bool {
        last.map { now.timeIntervalSince($0) >= cooldown } ?? true
    }

    /// Fans seen turning at some point: only these can stall. A header with
    /// nothing plugged in reads zero from the start and never counts.
    static func spinning(_ readings: [Int: UInt64], adding known: Set<Int>) -> Set<Int> {
        known.union(readings.filter { $0.value > 0 }.map(\.key))
    }

    /// Fans that turned before and read zero now.
    static func stalled(_ readings: [Int: UInt64], spun: Set<Int>) -> Set<Int> {
        Set(readings.filter { $0.value == 0 && spun.contains($0.key) }.map(\.key))
    }
}

/// Thermal, PPT power and fan stall alerts through the Dynamic Island.
/// Runs only while the island can show: the island stops it on suspend.
final class NotchHardwareAlertService {
    static let shared = NotchHardwareAlertService()

    private var subscription: AnyCancellable?
    private var thermalStreak = 0
    private var powerStreak = 0
    private var lastThermalAlert: Date?
    private var lastPowerAlert: Date?
    private var lastFanAlert: Date?
    private var spunFans = Set<Int>()
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
        thermalStreak = 0
        powerStreak = 0
    }

    /// Each alert stamps its cooldown and plays its sound only once the
    /// island has taken it: a refused alert stays silent and can fire again.
    private func evaluate(_ snapshot: SystemSnapshot) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchHardwareAlertsEnabled) else { return }
        let now = Date()
        let text = FeatureStrings.notchIslandExtras(L10n.shared.language)

        if let temp = snapshot.cpuTemperature {
            thermalStreak = NotchHardwareAlertSupport.nextStreak(thermalStreak, value: temp, trigger: 85, release: 78)
            let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "")
                ?? .celsius
            if thermalStreak >= 3,
               NotchHardwareAlertSupport.cooledDown(lastThermalAlert, now: now, cooldown: cooldown),
               NotchService.shared.show(NotchNotice(event: .hardwareAlert, title: text.thermalAlert,
                                                    detail: MetricFormat.temperature(temp, unit: unit),
                                                    symbol: "flame.fill", mascot: .surprised)) {
                lastThermalAlert = now
                NotchSoundCueService.shared.play(.error)
            }
        }

        if let power = snapshot.cpuPower {
            powerStreak = NotchHardwareAlertSupport.nextStreak(powerStreak, value: power, trigger: 140, release: 130)
            if powerStreak >= 3,
               NotchHardwareAlertSupport.cooledDown(lastPowerAlert, now: now, cooldown: cooldown),
               NotchService.shared.show(NotchNotice(event: .hardwareAlert, title: text.powerAlert,
                                                    detail: String(format: "%.0f W", power),
                                                    symbol: "bolt.fill", mascot: .surprised)) {
                lastPowerAlert = now
                NotchSoundCueService.shared.play(.context)
            }
        }

        evaluateFans(snapshot: snapshot, now: now, text: text)
    }

    /// A fan that turned earlier and reads zero while the CPU is hot. The
    /// readings come from the fan controller, and only while its poll runs
    /// (a fan view open, a manual fan): a stale list is never trusted.
    private func evaluateFans(snapshot: SystemSnapshot, now: Date, text: NotchIslandExtrasStrings) {
        // The sink delivers on the main queue, where the controller lives.
        let live: (fans: [FanState], packageTemp: Double)? = MainActor.assumeIsolated {
            let controller = FanCurveController.shared
            guard let packageTemp = controller.lastPackageTempC, packageTemp > 0 else { return nil }
            return (controller.fans.filter { !$0.isHidden && $0.rpmValid }, packageTemp)
        }
        guard let live else { return }
        let fans = live.fans
        let readings = Dictionary(fans.map { ($0.id, $0.rpm) }, uniquingKeysWith: { first, _ in first })
        spunFans = NotchHardwareAlertSupport.spinning(readings, adding: spunFans)
        let temp = snapshot.cpuTemperature ?? live.packageTemp
        let stalled = NotchHardwareAlertSupport.stalled(readings, spun: spunFans)
        guard temp >= 72, let fan = fans.first(where: { stalled.contains($0.id) }),
              NotchHardwareAlertSupport.cooledDown(lastFanAlert, now: now, cooldown: cooldown * 1.5) else { return }
        let name = fan.customName.flatMap { $0.isEmpty ? nil : $0 } ?? fan.name
        if NotchService.shared.show(NotchNotice(event: .hardwareAlert, title: text.fanAlert,
                                                detail: name + " · 0 RPM",
                                                symbol: "fanblades.slash", mascot: .confused)) {
            lastFanAlert = now
            NotchSoundCueService.shared.play(.error)
        }
    }
}
