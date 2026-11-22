// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// The lowest and highest value seen of one reading.
struct SessionRange: Equatable, Sendable {
    var min: Double
    var max: Double

    /// The range widened to take `value` in, or a new one from it.
    static func widened(_ range: SessionRange?, with value: Double) -> SessionRange {
        guard let range else { return SessionRange(min: value, max: value) }
        return SessionRange(min: Swift.min(range.min, value), max: Swift.max(range.max, value))
    }
}

/// The lowest and highest CPU temperature, package power, average clock and
/// fastest fan seen since `startedAt`. Kept in memory only: it belongs to
/// this run of the app, and Reset starts it again. Readings that are
/// missing, not finite or zero say nothing about the CPU and are skipped;
/// only the fan may read zero, and only when a fan actually reported it
/// (a fan that stops at idle).
struct SessionPeaks: Equatable, Sendable {
    private(set) var startedAt: Date
    private(set) var temperature: SessionRange?
    private(set) var power: SessionRange?
    /// Average clock of the physical cores, in GHz.
    private(set) var clock: SessionRange?
    /// The fastest fan, in RPM.
    private(set) var fan: SessionRange?

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    var isEmpty: Bool { temperature == nil && power == nil && clock == nil && fan == nil }

    /// Takes in one sample of the CPU readings; nil means not sampled.
    mutating func record(temperatureC: Double?, powerW: Double?, clockGHz: Double?) {
        if let value = Self.usable(temperatureC) { temperature = SessionRange.widened(temperature, with: value) }
        if let value = Self.usable(powerW) { power = SessionRange.widened(power, with: value) }
        if let value = Self.usable(clockGHz) { clock = SessionRange.widened(clock, with: value) }
    }

    /// Takes in the fastest of the fans that reported a speed this time.
    /// Nil (no fan reported) leaves the range as it is; zero is kept.
    mutating func record(fanRPM: Double?) {
        guard let fanRPM, fanRPM.isFinite, fanRPM >= 0 else { return }
        fan = SessionRange.widened(fan, with: fanRPM)
    }

    /// Forgets every reading and starts again at `date`.
    mutating func reset(at date: Date) {
        self = SessionPeaks(startedAt: date)
    }

    /// A positive, finite reading, or nil.
    static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// The fastest fan among those with a trusted reading that the user has
    /// not hidden, or nil when none of them reported.
    static func fastestFanRPM(_ fans: [FanState]) -> Double? {
        fans.filter { $0.rpmValid && !$0.isHidden }.map { Double($0.rpm) }.max()
    }

    /// "min – max", each end formatted the way the reading is shown elsewhere.
    static func rangeText(_ range: SessionRange?, format: (Double) -> String) -> String {
        guard let range else { return "—" }
        return "\(format(range.min)) – \(format(range.max))"
    }
}

/// The app's one session tracker. It takes every snapshot the system
/// monitor publishes (the same samples the panel shows) and every fan poll
/// the fan controller makes; it never starts a read of its own.
@MainActor
final class SessionPeaksTracker: ObservableObject {
    static let shared = SessionPeaksTracker()

    @Published private(set) var peaks = SessionPeaks(startedAt: Date())
    private var snapshotSubscription: AnyCancellable?

    private init() {}

    /// Subscribes to the system monitor. Called once at launch.
    func start() {
        guard snapshotSubscription == nil else { return }
        snapshotSubscription = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                // Delivered on the main queue, where the tracker lives.
                MainActor.assumeIsolated { self?.record(snapshot) }
            }
    }

    func record(_ snapshot: SystemSnapshot) {
        var next = peaks
        next.record(temperatureC: snapshot.cpuTemperature,
                    powerW: snapshot.cpuPower,
                    clockGHz: SystemSection.averageFrequencyGHz(snapshot.cores))
        if next != peaks { peaks = next }
    }

    func record(fans: [FanState]) {
        var next = peaks
        next.record(fanRPM: SessionPeaks.fastestFanRPM(fans))
        if next != peaks { peaks = next }
    }

    func reset() {
        peaks.reset(at: Date())
    }
}
