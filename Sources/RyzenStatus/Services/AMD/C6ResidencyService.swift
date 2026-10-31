// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Per-core idle residency for the menu panel's core grid (kext selector 32).
///
/// It polls only while a view that shows it is on screen (client-counted
/// `startPolling()`/`stopPolling()`, the pattern `FanCurveController` uses).
/// Every kext call restarts the kext's sampling, so a poll that never stops
/// keeps the kext from ever entering its idle mode.
@MainActor
final class C6ResidencyService: ObservableObject {
    static let shared = C6ResidencyService()

    /// Per-core idle residency snapshot (KEXT_WAVE 1.20.0 C-1, selector 32).
    /// Index = logical core; value = % of the last window the CPU spent out of
    /// C0 (kext 3.36.0+: MPERF against the TSC, every Zen; older kexts: the
    /// driver's own idle-loop accounting, Zen 1/2 only). Empty when the kext
    /// predates selector 32, is gone, or nothing has asked for it.
    @Published private(set) var coreResidency: [UInt16] = []

    private var pollTask: Task<Void, Never>?
    /// Views showing the residency while they are on screen.
    private var clients = 0
    private var unloadObserver: Any?
    private static let pollInterval: TimeInterval = 1.5

    private init() {
        unloadObserver = NotificationCenter.default.addObserver(
            forName: ProcessorModel.kextUnloadedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.publish([])
            }
        }
    }

    deinit {
        if let unloadObserver {
            NotificationCenter.default.removeObserver(unloadObserver)
        }
    }

    /// A view showing the residency calls this when it appears, and
    /// `stopPolling()` when it goes away.
    func startPolling() {
        clients += 1
        updateLoop()
    }

    func stopPolling() {
        clients = max(0, clients - 1)
        updateLoop()
    }

    /// Stops the poller. Called on termination.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func updateLoop() {
        guard clients > 0 else {
            stop()
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task.detached(priority: .background) { [weak self] in
            // Exit the loop when the owner is gone, instead of waking every
            // 1.5 s forever with nothing to publish to.
            guard let strong = self else { return }
            await strong.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let strong = self else { break }
                await strong.poll()
            }
        }
    }

    // Move blocking kext IPC off MainActor
    private func poll() async {
        let corePct = await Task.detached(priority: .background) {
            ProcessorModel.shared.getCoreC6Residency()
        }.value
        // A failed read (old kext, kext gone) clears the dots instead of
        // freezing the last ones on the grid.
        publish(corePct)
    }

    private func publish(_ values: [UInt16]) {
        if coreResidency != values { coreResidency = values }
    }
}
