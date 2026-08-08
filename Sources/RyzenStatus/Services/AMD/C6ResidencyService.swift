// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// Tracks the percentage of time the CPU package spends in the deepest
/// C-state (C6) using the kext's accumulated residency counter
/// (selector 31 — `ProcessorModel.getPackageC6Residency()`).
///
/// The kext returns a cumulative `uint64` of microseconds; the percentage is
/// derived from the delta between two samples divided by the wall-clock
/// delta:
///
///     Δµs / (Δseconds * 1_000_000) * 100
///
/// A single background poller keeps every observing view (dashboard, AMD
/// settings) in sync, instead of each view running its own timer with its own
/// last-value/last-timestamp bookkeeping.
final class C6ResidencyService: ObservableObject {
    static let shared = C6ResidencyService()

    /// Percentage of time in C6 over the last polling window (0–100).
    @Published private(set) var percentage: Double = 0

    private var lastRaw: UInt64 = 0
    private var lastTimestamp = Date.distantPast
    private var timer: Timer?
    private static let pollInterval: TimeInterval = 1.5

    private init() {}

    /// Starts the background poller. Idempotent — call once at launch.
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Fire immediately so observers have a baseline on first observation.
        poll()
    }

    /// Stops the poller. Called on termination.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let raw = ProcessorModel.shared.getPackageC6Residency()
        let now = Date()

        // No counter (kext absent / not sampling) — report nothing.
        guard raw > 0 else {
            percentage = 0
            lastRaw = 0
            lastTimestamp = .distantPast
            return
        }

        // Counter reset (kext reload / reboot mid-session): skip this sample
        // so the fake huge delta never shows as 100%.
        if lastRaw > 0 && raw < lastRaw {
            lastRaw = raw
            lastTimestamp = now
            return
        }

        if lastRaw > 0 {
            // The reset guard above guarantees raw >= lastRaw here, so plain
            // subtraction is safe (no counter rollover case to wrap around).
            let deltaUs = Double(raw - lastRaw)
            let elapsedUs = now.timeIntervalSince(lastTimestamp) * 1_000_000
            if elapsedUs > 0 {
                percentage = min(100, max(0, (deltaUs / elapsedUs) * 100.0))
            }
        }

        lastRaw = raw
        lastTimestamp = now
    }
}
