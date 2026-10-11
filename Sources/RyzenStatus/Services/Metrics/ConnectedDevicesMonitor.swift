// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit
import IOKit.usb

/// Owns the list of connected external USB devices for the Connected Devices
/// feature.
///
/// Upstream samples this list inside `SystemMonitor`. This fork's monitor is
/// AMD-specific and its telemetry paths stay untouched, so the list lives in
/// this standalone owner instead. It is event driven rather than polled: one
/// IOKit read when a surface starts watching, then a fresh read only after a
/// USB device arrives or leaves. With no surface watching, or with the feature
/// uninstalled in the hub, the IOKit notifications are torn down.
final class ConnectedDevicesMonitor: ObservableObject {
    static let shared = ConnectedDevicesMonitor()

    @Published private(set) var devices: [ConnectedUSBDevice] = []
    @Published private(set) var hasLoadedOnce = false

    private let sampler = USBDeviceSampler()
    private let sampleQueue = DispatchQueue(label: "com.ryzenstatus.connected-devices", qos: .utility)
    /// Surfaces currently showing the list. Main thread only.
    private var watchers = 0
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pendingSample: DispatchWorkItem?
    /// Bumped on every teardown so a read already in flight cannot publish
    /// into a monitor that stopped watching.
    private var generation = 0

    /// A device that just arrived may still be publishing its product and
    /// vendor strings; a short settle also folds a hub's burst of arrivals
    /// into one read.
    private static let settleDelay: TimeInterval = 0.4

    private init() {}

    var count: Int { devices.count }

    /// Called on the main thread by every surface that shows the list, paired
    /// with `endWatching()`.
    func beginWatching() {
        dispatchPrecondition(condition: .onQueue(.main))
        watchers += 1
        guard watchers == 1 else { return }
        start()
    }

    func endWatching() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard watchers > 0 else { return }
        watchers -= 1
        guard watchers == 0 else { return }
        stop(clearing: false)
    }

    /// Hub binding: uninstalling the feature drops the notifications and the
    /// cached list at once; installing it again resumes for any surface that
    /// is still watching.
    func syncWithPreferences() {
        dispatchPrecondition(condition: .onQueue(.main))
        if AppFeature.connectedDevices.isAvailable {
            if watchers > 0, notifyPort == nil { start() }
        } else {
            stop(clearing: true)
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard AppFeature.connectedDevices.isAvailable else { return }
        armNotifications()
        scheduleSample(after: 0)
    }

    private func stop(clearing: Bool) {
        generation += 1
        pendingSample?.cancel()
        pendingSample = nil
        teardownNotifications()
        if clearing {
            devices = []
            hasLoadedOnce = false
        }
    }

    private func armNotifications() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            // Draining the iterator is what re-arms the notification.
            ConnectedDevicesMonitor.drain(iterator)
            guard let refcon else { return }
            Unmanaged<ConnectedDevicesMonitor>.fromOpaque(refcon)
                .takeUnretainedValue()
                .deviceSetChanged()
        }
        // The same classes `USBDeviceSampler` reads, arrivals and departures.
        for className in ["IOUSBHostDevice", kIOUSBDeviceClassName] {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                guard let matching = IOServiceMatching(className) else { continue }
                var iterator: io_iterator_t = 0
                guard IOServiceAddMatchingNotification(port, type, matching, callback,
                                                       refcon, &iterator) == KERN_SUCCESS else { continue }
                // The devices already present arrive through the first read,
                // so they are only drained here.
                Self.drain(iterator)
                iterators.append(iterator)
            }
        }
    }

    private func teardownNotifications() {
        for iterator in iterators {
            IOObjectRelease(iterator)
        }
        iterators.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }

    // MARK: - Sampling

    private func deviceSetChanged() {
        guard watchers > 0 else { return }
        scheduleSample(after: Self.settleDelay)
    }

    private func scheduleSample(after delay: TimeInterval) {
        pendingSample?.cancel()
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sampleQueue.async {
                let list = self.sampler.sample()
                DispatchQueue.main.async {
                    guard expected == self.generation,
                          AppFeature.connectedDevices.isAvailable else { return }
                    if self.devices != list { self.devices = list }
                    if !self.hasLoadedOnce { self.hasLoadedOnce = true }
                }
            }
        }
        pendingSample = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
