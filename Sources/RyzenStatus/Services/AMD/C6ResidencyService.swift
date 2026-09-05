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

    /// Per-core C6 residency snapshot (KEXT_WAVE 1.20.0 C-1, selector 32).
    /// Index = logical core; value = % of the decayed accounting window spent
    /// idling (C6-ish). Empty when the kext predates selector 32.
    @Published private(set) var coreResidency: [UInt16] = []

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

    // AUDIT F-28: move blocking kext IPC off MainActor
    private func poll() async {
        let (raw, now, corePct) = await Task.detached(priority: .background) {
            (ProcessorModel.shared.getPackageC6Residency(),
             ProcessInfo.processInfo.systemUptime,
             ProcessorModel.shared.getCoreC6Residency())
        }.value

        let (newPct, nextRaw, nextTimestamp) = C6Sampling.sample(
            raw: raw, now: now,
            lastRaw: lastRaw, lastTimestamp: lastTimestamp
        )

        // No counter (kext absent / not sampling) — report nothing.
        if raw == 0 {
            if percentage != 0 { percentage = 0 }
        }

        // KEXT_WAVE C-1: publish the per-core snapshot on the same cadence.
        // Empty result (old kext) keeps the previous value untouched so the UI
        // never flashes to "all zero" on a version mismatch.
        if !corePct.isEmpty {
            coreResidency = corePct
        }

        lastRaw = nextRaw
        lastTimestamp = nextTimestamp

        if let pct = newPct {
            if abs(percentage - pct) >= 0.1 {
                percentage = pct
            }
        }
    }
}
