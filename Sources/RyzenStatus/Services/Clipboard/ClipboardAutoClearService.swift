// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

final class ClipboardAutoClearService {
    static let shared = ClipboardAutoClearService()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var generation = 0
    private var readInFlight = false
    private var lastChangeCount = -1
    private var lastClearedChangeCount = -1
    private var lastChangeDate = Date()
    private let lock = NSLock()
    private var configurationGeneration = 0
    private var configuredKeys = Set<String>()
    private var configurationAvailable = false
    private var configuredDelay = 0
    // Read/clear work is owned by the serial pasteboard lane only.
    private var laneLastClearedCount = -1
    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let available = AppFeature.clipboardHistory.isAvailable
        let triggers = [DefaultsKey.clipboardAutoClearOnDelay, DefaultsKey.clipboardAutoClearOnSleep,
                        DefaultsKey.clipboardAutoClearOnDisplaySleep, DefaultsKey.clipboardAutoClearOnScreenLock]
        let keys = Set(triggers.filter { available && defaults.bool(forKey: $0) })
        let delay = Defaults.sanitizedClipboardAutoClearDelay(defaults.integer(forKey: DefaultsKey.clipboardAutoClearDelay))
        lock.lock()
        let changed = keys != configuredKeys || available != configurationAvailable || delay != configuredDelay
        if changed { configurationGeneration &+= 1 }
        configuredKeys = keys
        configurationAvailable = available
        configuredDelay = delay
        lock.unlock()
        guard changed else { return }
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        timer?.invalidate(); timer = nil
        generation &+= 1
        // Keep an in-flight lane read marked until it actually returns. A
        // wedged pasteboard must not accumulate a new work item every tick.
        lastChangeCount = -1
        lastChangeDate = Date()
        if keys.contains(DefaultsKey.clipboardAutoClearOnDelay) {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            tick()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        addObserver(workspace, NSWorkspace.willSleepNotification, key: DefaultsKey.clipboardAutoClearOnSleep, keys: keys)
        addObserver(workspace, NSWorkspace.screensDidSleepNotification,
                    key: DefaultsKey.clipboardAutoClearOnDisplaySleep, keys: keys)
        addObserver(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"),
                    key: DefaultsKey.clipboardAutoClearOnScreenLock, keys: keys)
    }

    private func addObserver(_ center: NotificationCenter, _ name: Notification.Name,
                             key: String, keys: Set<String>) {
        guard keys.contains(key) else { return }
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.clear(trigger: key)
        }
        observers.append((center, token))
    }

    private func tick() {
        guard timer != nil, !readInFlight else { return }
        readInFlight = true
        let generation = self.generation
        GeneralPasteboardAccess.shared.async { NSPasteboard.general.changeCount } then: { [weak self] count in
            guard let self else { return }
            self.readInFlight = false
            guard generation == self.generation, self.timer != nil else { return }
            let delay = Defaults.sanitizedClipboardAutoClearDelay(
                UserDefaults.standard.integer(forKey: DefaultsKey.clipboardAutoClearDelay))
            switch ClipboardAutoClearSupport.decide(changeCount: count, lastChangeCount: self.lastChangeCount,
                lastClearedChangeCount: self.lastClearedChangeCount, lastChangeDate: self.lastChangeDate,
                now: Date(), delay: TimeInterval(delay)) {
            case .noteChange:
                self.lastChangeCount = count
                self.lastChangeDate = Date()
            case .clear:
                self.clear(trigger: DefaultsKey.clipboardAutoClearOnDelay, expected: count)
            case .wait: break
            }
        }
    }

    private func clear(trigger: String, expected: Int? = nil) {
        lock.lock()
        let configuration = configurationGeneration
        lock.unlock()
        GeneralPasteboardAccess.shared.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let authorized = ClipboardAutoClearSupport.clearIsAuthorized(
                enqueuedGeneration: configuration, currentGeneration: self.configurationGeneration,
                featureIsAvailable: self.configurationAvailable,
                triggerIsEnabled: self.configuredKeys.contains(trigger))
            self.lock.unlock()
            guard authorized, AppFeature.clipboardHistory.isAvailable,
                  UserDefaults.standard.bool(forKey: trigger) else { return }
            let pasteboard = NSPasteboard.general
            let count = pasteboard.changeCount
            guard count != self.laneLastClearedCount, expected == nil || expected == count else { return }
            let cleared = pasteboard.clearContents()
            self.laneLastClearedCount = cleared
            DispatchQueue.main.async {
                self.lastChangeCount = cleared
                self.lastClearedChangeCount = cleared
                self.lastChangeDate = Date()
                ClipboardHistoryService.shared.ignoreNextChange(upTo: cleared)
                // The menu bar preview must stop showing what is gone.
                ClipboardHistoryService.shared.pasteboardWasCleared()
            }
        }
    }
}
