// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Tracks the percentage of time the CPU package spends in the deepest
/// C-state (C6) using the kext's accumulated residency counter
/// (selector 31 — `ProcessorModel.getPackageC6Residency()`).
///
/// The kext returns a cumulative `uint64` of microseconds; the percentage is
/// derived from the delta between two samples divided by the elapsed uptime:
///
///     Δµs / (Δseconds * 1_000_000) * 100
@MainActor
final class C6ResidencyService: ObservableObject {
    static let shared = C6ResidencyService()

    /// Percentage of time in C6 over the last polling window (0–100).
    @Published private(set) var percentage: Double = 0

    private var lastRaw: UInt64 = 0
    private var lastTimestamp: TimeInterval = 0
    private var pollTask: Task<Void, Never>?
    private var wakeObserver: Any?
    private static let pollInterval: TimeInterval = 1.5

    private init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetBaseline()
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Starts the background poller. Idempotent — call once at launch.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached(priority: .background) { [weak self] in
            await self?.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                await self?.poll()
            }
        }
    }

    /// Stops the poller. Called on termination.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func resetBaseline() {
        lastRaw = 0
        lastTimestamp = 0
    }

    private func poll() async {
        let raw = ProcessorModel.shared.getPackageC6Residency()
        let now = ProcessInfo.processInfo.systemUptime

        // No counter (kext absent / not sampling) — report nothing.
        guard raw > 0 else {
            if percentage != 0 { percentage = 0 }
            lastRaw = 0
            lastTimestamp = 0
            return
        }

        // Counter reset (kext reload / reboot / sleep mid-session): skip this sample
        if lastRaw > 0 && raw < lastRaw {
            lastRaw = raw
            lastTimestamp = now
            return
        }

        var newPercentage: Double? = nil
        if lastRaw > 0 && lastTimestamp > 0 {
            let deltaUs = Double(raw - lastRaw)
            let elapsedUs = (now - lastTimestamp) * 1_000_000
            if elapsedUs > 0 {
                newPercentage = min(100, max(0, (deltaUs / elapsedUs) * 100.0))
            }
        }

        lastRaw = raw
        lastTimestamp = now

        if let newPct = newPercentage {
            if abs(percentage - newPct) >= 0.1 {
                percentage = newPct
            }
        }
    }
}
