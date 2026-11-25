// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation
import IOKit

/// AWDL (the link AirDrop, Sidecar and Continuity ride on) as a Wi-Fi driver
/// that reports it publishes it in the I/O Registry: on the `awdl0` interface
/// (class `RTLAwdInterface`), `RTLAwdlPeers` counts the peers that exchanged
/// unicast data in the last 3 s and `RTLAwdlChannel` is the current data
/// channel (0 = none); the driver's own service may add `RTLLed`, the status
/// LED mode. Without those properties (another Wi-Fi card, an older driver)
/// there is no reading and nothing about AWDL shows.
struct AwdlActivity: Equatable {
    static let interfaceClass = "RTLAwdInterface"
    static let peersKey = "RTLAwdlPeers"
    static let channelKey = "RTLAwdlChannel"
    static let ledKey = "RTLLed"

    let peers: Int
    /// 0 while AWDL holds no data channel.
    let channel: Int
    let led: AwdlLedMode?

    var isActive: Bool { peers > 0 }

    /// Nil unless both AWDL numbers are there and plausible, so a driver that
    /// publishes neither (or something else under the names) shows nothing.
    static func parse(peers: Any?, channel: Any?, led: Any? = nil) -> AwdlActivity? {
        guard let peers = integer(peers), (0...255).contains(peers),
              let channel = integer(channel), (0...255).contains(channel) else { return nil }
        return AwdlActivity(peers: peers, channel: channel,
                            led: integer(led).flatMap(AwdlLedMode.init(rawValue:)))
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded() else { return nil }
        return Int(exactly: double)
    }

    /// The panel's value text: the peer count while active, the channel
    /// whenever AWDL holds one.
    func summary(_ strings: AwdlStrings) -> String {
        var parts = [isActive ? String(format: strings.peersFormat, peers) : strings.idle]
        if channel > 0 { parts.append(String(format: strings.channelFormat, channel)) }
        return parts.joined(separator: " · ")
    }

    /// The notification body: peers, and the channel when there is one.
    func notificationBody(_ strings: AwdlStrings) -> String {
        var parts = [String(format: strings.peersFormat, peers)]
        if channel > 0 { parts.append(String(format: strings.channelFormat, channel)) }
        return parts.joined(separator: " · ")
    }
}

/// `RTLLed` as the driver numbers it.
enum AwdlLedMode: Int, Equatable {
    case off = 0
    case status = 1
    case steady = 2

    func label(_ strings: AwdlStrings) -> String {
        switch self {
        case .off: return strings.ledOff
        case .status: return strings.ledStatus
        case .steady: return strings.ledSteady
        }
    }
}

/// When "AWDL became active" is worth a notification: on the step from no
/// peers to some, never for the first reading (the app starting, or the
/// driver arriving, while AWDL is already busy), and at most once per
/// `cooldown`, since an AirDrop session can drop to 0 peers between bursts.
struct AwdlActivationGate {
    static let defaultCooldown: TimeInterval = 60

    var cooldown: TimeInterval = defaultCooldown
    private var lastPeers: Int?
    private var lastNotifiedAt: TimeInterval = -.infinity

    init(cooldown: TimeInterval = defaultCooldown) {
        self.cooldown = cooldown
    }

    /// Feeds one reading (nil = no data) taken at `now` (uptime); true when
    /// it should notify.
    mutating func observe(_ activity: AwdlActivity?, now: TimeInterval) -> Bool {
        let previous = lastPeers
        lastPeers = activity?.peers
        guard let activity, activity.isActive, previous == 0,
              now - lastNotifiedAt >= cooldown else { return false }
        lastNotifiedAt = now
        return true
    }

    /// Forgets the last reading, so the next one is a fresh baseline.
    mutating func reset() {
        lastPeers = nil
    }
}

/// Follows the AWDL interface's arrival and removal through IOKit, and reads
/// its two numbers once a second, only while something wants them: the
/// panel's Network card on screen, or the notification switched on. With the
/// interface missing there is one IOKit registration and nothing after it.
/// `@unchecked Sendable`: every stored property but `activity` is touched
/// only on `queue`, and `activity` only on the main thread.
final class AwdlActivityService: ObservableObject, @unchecked Sendable {
    static let shared = AwdlActivityService()

    static let pollInterval: TimeInterval = 1

    /// Nil while there is no AWDL reading: no such interface, or a driver
    /// that does not publish these numbers.
    @Published private(set) var activity: AwdlActivity?

    // Everything below lives on `queue`.
    private let queue = DispatchQueue(label: "ryzenstatus.awdl", qos: .utility)
    private var service: io_service_t = 0
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var viewers = 0
    private var notifying = false
    private var timer: DispatchSourceTimer?
    private var gate = AwdlActivationGate()
    private var lastPublished: AwdlActivity?

    private init() {}

    /// Starts following the interface. Idempotent; called once at launch.
    @MainActor func watchPresence() {
        let notify = UserDefaults.standard.bool(forKey: DefaultsKey.monitorAlertAwdl)
        queue.async { [self] in
            notifying = notify
            guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
            notifyPort = port
            IONotificationPortSetDispatchQueue(port, queue)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let matched: IOServiceMatchingCallback = { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<AwdlActivityService>.fromOpaque(refcon).takeUnretainedValue().serviceAppeared(iterator)
            }
            let terminated: IOServiceMatchingCallback = { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<AwdlActivityService>.fromOpaque(refcon).takeUnretainedValue().serviceVanished(iterator)
            }
            // Arming a notification means draining its iterator once; that
            // also picks up an interface that is already there.
            if IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
                                                IOServiceMatching(AwdlActivity.interfaceClass),
                                                matched, refcon, &matchedIterator) == KERN_SUCCESS {
                serviceAppeared(matchedIterator)
            }
            if IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                                IOServiceMatching(AwdlActivity.interfaceClass),
                                                terminated, refcon, &terminatedIterator) == KERN_SUCCESS {
                serviceVanished(terminatedIterator)
            }
        }
    }

    /// Balanced with `stop()`: a view showing the reading.
    @MainActor func start() {
        queue.async { [self] in
            viewers += 1
            updateTimer()
        }
    }

    @MainActor func stop() {
        queue.async { [self] in
            guard viewers > 0 else { return }
            viewers -= 1
            updateTimer()
        }
    }

    /// Re-reads the notification switch; its Settings toggle calls this.
    @MainActor func syncNotificationPreference() {
        let notify = UserDefaults.standard.bool(forKey: DefaultsKey.monitorAlertAwdl)
        if notify { Notifier.requestPermission() }
        queue.async { [self] in
            guard notifying != notify else { return }
            notifying = notify
            gate.reset()
            updateTimer()
        }
    }

    /// One read outside the app's run loop, for `--sensors`.
    static func readOnce() -> AwdlActivity? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(AwdlActivity.interfaceClass))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return read(entry)
    }

    // MARK: - Queue

    private func updateTimer() {
        let wanted = service != 0 && (viewers > 0 || notifying)
        if wanted, timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        } else if !wanted, let timer {
            timer.cancel()
            self.timer = nil
            gate.reset()
        }
    }

    private func tick() {
        guard service != 0 else { return }
        let next = Self.read(service)
        if gate.observe(next, now: ProcessInfo.processInfo.systemUptime), notifying, let next {
            DispatchQueue.main.async {
                // The switch lives with the network monitor; with that
                // uninstalled in the hub nothing is announced.
                guard AppFeature.monitorNetwork.isAvailable else { return }
                let strings = FeatureStrings.awdl(L10n.shared.language)
                Notifier.post(title: strings.notificationTitle, body: next.notificationBody(strings))
            }
        }
        publish(next)
    }

    private func publish(_ next: AwdlActivity?) {
        guard next != lastPublished else { return }
        lastPublished = next
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activity != next else { return }
            self.activity = next
        }
    }

    private func serviceAppeared(_ iterator: io_iterator_t) {
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if service == 0 {
                service = entry
            } else {
                IOObjectRelease(entry)
            }
        }
        guard service != 0 else { return }
        // One read now, so Settings knows whether to offer the switch
        // before the panel was ever opened.
        let first = Self.read(service)
        _ = gate.observe(first, now: ProcessInfo.processInfo.systemUptime)
        publish(first)
        updateTimer()
    }

    private func serviceVanished(_ iterator: io_iterator_t) {
        var lost = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if entry == service || IOObjectIsEqualTo(entry, service) != 0 { lost = true }
            IOObjectRelease(entry)
        }
        guard lost else { return }
        IOObjectRelease(service)
        service = 0
        updateTimer()
        gate.reset()
        publish(nil)
        // A second interface may still be registered; pick it up.
        let next = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(AwdlActivity.interfaceClass))
        if next != 0 {
            service = next
            publish(Self.read(next))
            updateTimer()
        }
    }

    /// Two properties of the interface, plus the LED mode searched upward
    /// from it, only once the AWDL numbers are there.
    private static func read(_ entry: io_registry_entry_t) -> AwdlActivity? {
        #if DEBUG
        // `-awdlFakeActivity "3,149,1"` (peers, channel, LED) shows a debug
        // build a driver that reports AWDL.
        if let fake = UserDefaults.standard.string(forKey: "awdlFakeActivity") {
            let parts = fake.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 2 {
                return AwdlActivity.parse(peers: NSNumber(value: parts[0]), channel: NSNumber(value: parts[1]),
                                          led: parts.count > 2 ? NSNumber(value: parts[2]) : nil)
            }
        }
        #endif
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let peers = property(AwdlActivity.peersKey)
        let channel = property(AwdlActivity.channelKey)
        guard peers != nil, channel != nil else { return nil }
        let led = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, AwdlActivity.ledKey as CFString,
                                                  kCFAllocatorDefault,
                                                  IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        return AwdlActivity.parse(peers: peers, channel: channel, led: led)
    }
}
