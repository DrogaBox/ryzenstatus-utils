// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import ApplicationServices
import Combine

/// Keeps only notifications received during this unlocked, opted-in session.
/// Native banners are preserved; no notification databases or message stores are read.
final class NotchNotificationService: ObservableObject {
    static let shared = NotchNotificationService()
    @Published private var inbox = NotchNotificationInbox()
    var items: [NotchSystemNotification] { inbox.items }
    @Published private(set) var monitoring = false
    @Published private(set) var openingID: UUID?
    let received = PassthroughSubject<NotchSystemNotification, Never>()
    private let queue = DispatchQueue(label: "com.ryzenstatus.notch-notifications", qos: .utility)
    private var appIcons: [String: NSImage] = [:]
    private var sourceApplications: [UUID: String] = [:]
    @Published private(set) var unavailableID: UUID?
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var reader: NotchNotificationReader?
    private var cancellation = DispatchWorkItem {}
    private var pendingScan: DispatchWorkItem?
    private var generation = UUID()
    private var reading = false
    private var rescan = false
    /// Reads in a row that could not finish. A banner that arrives during
    /// one gets no other layout event, so the pass is tried again soon.
    private var failedReads = 0
    private var running = false
    /// Banners the island shows, whose originals stay out of sight.
    private var shownIDs = Set<UUID>()
    private var closingIDs = Set<UUID>()
    private var placing = false
    private var hidesNative = false
    private let notifications = [kAXWindowCreatedNotification, kAXLayoutChangedNotification,
                                 kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification]

    private init() {}

    func syncWithPreferences() {
        guard NotchNotificationSupport.isEnabled(), Permissions.shared.accessibility else { stop(); return }
        running = true
        placeNative()
        if workspaceObservers.isEmpty {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in self?.attach()
                })
            }
        }
        attach()
    }

    private func attach() {
        guard running else { return }
        guard NotchNotificationSupport.isEnabled(), Permissions.shared.accessibility else { stop(); return }
        let nextPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first?.processIdentifier
        guard nextPID != pid || observer == nil else { return }
        detach()
        guard let nextPID else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, name, context in
            guard let context else { return }
            let service = Unmanaged<NotchNotificationService>.fromOpaque(context).takeUnretainedValue()
            // A new window usually brings a banner, laid out a few hundredths
            // of a second later. Reading it then lets a hidden original leave
            // before it slides in. The regular pass still follows.
            if name as String == kAXWindowCreatedNotification {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak service] in service?.scan() }
            }
            service.scheduleScan()
        }
        guard AXObserverCreate(nextPID, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(nextPID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for name in notifications {
            if AXObserverAddNotification(created, app, name as CFString, context) == .success { attached = true }
        }
        guard attached else { return }
        pid = nextPID; application = app; observer = created
        cancellation = DispatchWorkItem {}
        reader = NotchNotificationReader(pid: nextPID, cancellation: cancellation)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        monitoring = true
        scan()
    }

    private func scheduleScan() {
        guard monitoring else { return }
        if reading { rescan = true; return }
        guard pendingScan == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScan = nil
            // An early read may still be running. This pass must follow it.
            if self.reading { self.rescan = true } else { self.scan() }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func scan() {
        guard monitoring, !reading, let reader else { return }
        reading = true
        let requested = generation
        queue.async { [weak self] in
            NotchNotificationSources.refreshIfStale()
            let snapshot = reader.read()
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.reading = false
                if let snapshot { self.failedReads = 0; self.accept(snapshot.items) }
                self.placeNative()
                if self.rescan { self.rescan = false; self.scheduleScan() }
                else if snapshot == nil { self.retryRead() }
            }
        }
    }

    private func retryRead() {
        guard monitoring, failedReads < NotchNotificationSupport.readRetries else { return }
        failedReads += 1
        let requested = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchNotificationSupport.readRetryDelay) { [weak self] in
            guard let self, self.generation == requested else { return }
            self.scheduleScan()
        }
    }

    func icon(for app: String) -> NSImage? { appIcons[app] }

    private func accept(_ live: [NotchSystemNotification]) {
        let sources = Dictionary(uniqueKeysWithValues: Set(live.map { $0.content.app }).map {
            ($0, NotchNotificationSources.source(for: [$0])?.bundleIdentifier)
        })
        for (name, identifier) in sources {
            guard let identifier else { appIcons[name] = nil; continue }
            if appIcons[name] == nil {
                appIcons[name] = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.icon
                    ?? InstalledApps.url(for: identifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
        }
        for item in live {
            if let identifier = sources[item.content.app] ?? nil { sourceApplications[item.id] = identifier }
        }
        let liveIDs = Set(live.map(\.id))
        shownIDs.formIntersection(liveIDs)
        closingIDs.formIntersection(liveIDs)
        let arrivals = inbox.update(live)
        trimIcons()
        for item in arrivals { received.send(item) }
    }

    private func trimIcons() {
        let sources = Set(items.map { $0.content.app })
        appIcons = appIcons.filter { sources.contains($0.key) }
        let ids = Set(items.map(\.id))
        sourceApplications = sourceApplications.filter { ids.contains($0.key) }
    }

    /// Closing a message in the island also closes its original while that
    /// is still on screen, when the island is set to take the place of the
    /// system's banners. Notification Center keeps what already left.
    func dismiss(_ id: UUID) {
        closeNativeNow([id])
        inbox.dismiss(id)
        trimIcons()
    }

    /// An opening in flight still needs its message, so it waits for it.
    func clearAll() {
        guard openingID == nil else { return }
        closeNativeNow(items.map(\.id))
        inbox.clear()
        unavailableID = nil
        trimIcons()
    }

    /// The person asked for it, so there is no grace and alerts go as well.
    private func closeNativeNow(_ ids: [UUID]) {
        guard monitoring, NotchNotificationSupport.dismissesNative(), let reader, !ids.isEmpty else { return }
        // Also when an automatic close is pending or gave up: this one may
        // take an alert too, and closing what is gone does nothing.
        closingIDs.formUnion(ids)
        let requested = generation
        queue.async { [weak self] in
            for id in ids where reader.isLive(id) {
                // A pass that runs out of time on a busy center gets one more go.
                if !reader.closeNative(id, explicit: true), reader.isLive(id) { _ = reader.closeNative(id, explicit: true) }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.scheduleScan()
            }
        }
    }

    /// The island shows this banner, so its original can leave the screen.
    func hideNative(_ id: UUID) {
        guard monitoring, NotchNotificationSupport.dismissesNative(),
              items.contains(where: { $0.id == id }) else { return }
        guard NotchNotificationSupport.movesNativeWindow else {
            if closingIDs.insert(id).inserted { closeNative(id) }
            return
        }
        shownIDs.insert(id)
        placeNative()
    }

    /// Runs once the current pass is over, when the island has already taken
    /// or passed over every banner that just arrived.
    private func placeNative() {
        guard monitoring, !placing, hidesNative || !shownIDs.isEmpty else { return }
        placing = true
        let requested = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == requested else { return }
            self.placing = false
            guard let reader = self.reader else { return }
            let shown = NotchNotificationSupport.dismissesNative() ? self.shownIDs : []
            // Counted as hidden while the move is on its way, so stopping waits for it.
            self.hidesNative = self.hidesNative || !shown.isEmpty
            self.queue.async { [weak self] in
                let failed = reader.hideNative(shown)
                let hidden = reader.hidesWindows
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.hidesNative = hidden
                    // Closed instead, so later passes do not move its window again.
                    self.shownIDs.subtract(failed)
                    for id in failed where self.closingIDs.insert(id).inserted { self.closeNative(id) }
                }
            }
        }
    }

    /// Where a window cannot be moved, the original is closed instead after
    /// a short grace for its sound.
    private func closeNative(_ id: UUID, attempt: Int = 0) {
        guard monitoring, NotchNotificationSupport.dismissesNative(),
              items.contains(where: { $0.id == id }) else { return }
        let requested = generation
        let delay = attempt == 0 ? NotchNotificationSupport.nativeCloseGrace : NotchNotificationSupport.readRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == requested, self.monitoring, let reader = self.reader,
                  NotchNotificationSupport.dismissesNative() else { return }
            self.queue.async { [weak self] in
                // A read that could not finish closes nothing; the banner is
                // still up, so it is tried again a few times.
                guard !reader.closeNative(id), reader.isLive(id) else { return }
                DispatchQueue.main.async {
                    guard let self, self.generation == requested,
                          attempt + 1 < NotchNotificationSupport.readRetries else { return }
                    self.closeNative(id, attempt: attempt + 1)
                }
            }
        }
    }

    func canOpen(_ item: NotchSystemNotification) -> Bool {
        item.canOpen || sourceApplications[item.id] != nil
    }

    func open(_ id: UUID, completion: @escaping (NotchNotificationReader.ActionResult) -> Void) {
        guard openingID == nil, monitoring, NotchNotificationSupport.isEnabled(),
              items.contains(where: { $0.id == id }), let reader else { completion(.unavailable); return }
        openingID = id
        unavailableID = nil
        let requested = generation
        queue.async { [weak self] in
            let result = reader.open(id)
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { completion(.unavailable); return }
                if result == .unavailable, let identifier = self.sourceApplications[id],
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                   Bundle(url: url)?.bundleIdentifier == identifier {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] app, _ in
                        DispatchQueue.main.async {
                            guard let self, self.generation == requested else { completion(.unavailable); return }
                            self.openingID = nil
                            if app == nil { self.unavailableID = id }
                            completion(app == nil ? .unavailable : .openedApplication)
                        }
                    }
                } else {
                    self.openingID = nil
                    if result == .unavailable || result == .uncertain { self.unavailableID = id }
                    completion(result)
                }
                self.scheduleScan()
            }
        }
    }

    private func detach() {
        // Nothing may stay out of sight once mirroring stops, quitting included.
        // Cancelling first ends a read in flight at its next step, and the wait
        // still covers a move on its way, even one a later pass just queued.
        cancellation.cancel()
        if let reader, hidesNative || !shownIDs.isEmpty { queue.sync { reader.showNative() } }
        generation = UUID()
        pendingScan?.cancel(); pendingScan = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let application {
                for name in notifications { AXObserverRemoveNotification(observer, application, name as CFString) }
            }
        }
        observer = nil; application = nil; pid = nil; reader = nil
        monitoring = false; reading = false; rescan = false; failedReads = 0; openingID = nil
        shownIDs.removeAll(); closingIDs.removeAll(); placing = false; hidesNative = false
        appIcons.removeAll()
        sourceApplications.removeAll()
        unavailableID = nil
        inbox = NotchNotificationInbox()
    }

    func stop() {
        running = false
        detach()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
    }
}
