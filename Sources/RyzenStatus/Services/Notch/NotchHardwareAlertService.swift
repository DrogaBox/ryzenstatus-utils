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

    /// What the stall rule remembers about one fan header.
    struct FanTrack: Equatable {
        var turningSince: Date?
        /// Seen turning steadily: only such a fan can stall. An empty header
        /// can pick up a stray reading now and then, never a steady one.
        var proven = false
        var stoppedSince: Date?
    }

    /// Below this a reading is noise, not a turning fan.
    static let turningRPM: UInt64 = 200
    static let provenAfter: TimeInterval = 10
    static let stalledAfter: TimeInterval = 6

    /// The track after one reading. Times, not reading counts: the fan poll
    /// and the monitor run at their own rates, so one stray value can be seen
    /// several times in a row. A fan whose duty is zero was stopped on
    /// purpose (a zero-RPM curve point, a manual 0 %) and never counts.
    static func track(_ track: FanTrack, rpm: UInt64, driven: Bool, now: Date) -> FanTrack {
        var next = track
        if rpm >= turningRPM {
            next.turningSince = next.turningSince ?? now
            next.stoppedSince = nil
            if let since = next.turningSince, now.timeIntervalSince(since) >= provenAfter { next.proven = true }
        } else {
            next.turningSince = nil
            next.stoppedSince = rpm == 0 && driven ? (next.stoppedSince ?? now) : nil
        }
        return next
    }

    /// A fan that turned steadily and has read zero, while driven, for a while.
    static func stalls(_ track: FanTrack, now: Date) -> Bool {
        guard track.proven, let since = track.stoppedSince else { return false }
        return now.timeIntervalSince(since) >= stalledAfter
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
    private var fanTracks: [Int: NotchHardwareAlertSupport.FanTrack] = [:]
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
        fanTracks = [:]
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

    /// A fan that turned steadily and has read zero for a while, while driven
    /// and with the CPU hot. The readings come from the fan controller, and
    /// only while its poll runs (a fan view open, a manual fan): a stale list
    /// is never trusted. Hidden fans are left out.
    private func evaluateFans(snapshot: SystemSnapshot, now: Date, text: NotchIslandExtrasStrings) {
        // The sink delivers on the main queue, where the controller lives.
        let live: (fans: [FanState], packageTemp: Double)? = MainActor.assumeIsolated {
            let controller = FanCurveController.shared
            guard let packageTemp = controller.lastPackageTempC, packageTemp > 0 else { return nil }
            return (controller.fans.filter { !$0.isHidden && $0.rpmValid }, packageTemp)
        }
        guard let live else { return }
        let fans = live.fans
        for fan in fans {
            fanTracks[fan.id] = NotchHardwareAlertSupport.track(fanTracks[fan.id] ?? .init(), rpm: fan.rpm,
                                                                driven: fan.throttlePWM > 0, now: now)
        }
        let temp = snapshot.cpuTemperature ?? live.packageTemp
        guard temp >= 72,
              let fan = fans.first(where: { fanTracks[$0.id].map { NotchHardwareAlertSupport.stalls($0, now: now) } ?? false }),
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
