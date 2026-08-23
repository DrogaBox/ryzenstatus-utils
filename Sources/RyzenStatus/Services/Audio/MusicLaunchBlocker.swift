// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreGraphics

/// Keeps the system music app from opening on its own, which macOS does
/// whenever a media key is pressed with no other player around to take it.
///
/// While the option is on, the blocker intercepts media-key events and
/// timestamps the last press. A music-app launch is terminated only if it
/// falls within the arm window after one of those key presses. Launching
/// from the Dock, Spotlight or a double-click has no such press and passes
/// through unaffected.
///
/// Nothing runs while the feature is off: no observers, no timers, no cost.
final class MusicLaunchBlocker: ObservableObject {
    static let shared = MusicLaunchBlocker()

    /// The current and the legacy identifier of the system music app.
    static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]

    private var observers: [NSObjectProtocol] = []
    private var mediaKeyTap: CFMachPort?
    private var mediaKeyTapSource: CFRunLoopSource?
    /// Uptime of the last media-key press that could trigger a music launch.
    private var lastMediaKeyAt: TimeInterval?
    /// One media key press produces both a will-launch and a did-launch
    /// notification; the replacement should open once, not twice.
    private var lastReplacementLaunch: TimeInterval = 0

    private init() {}

    func syncWithPreferences() {
        if AppFeature.musicBlock.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.musicBlockEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // Will-launch usually wins the race before any window shows;
        // did-launch catches the rare launch that slips past it.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleLaunch(note)
            }
        }
        installMediaKeyTap()
    }

    func stop() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
        removeMediaKeyTap()
    }

    // MARK: - Media key tap

    private func installMediaKeyTap() {
        guard mediaKeyTap == nil else { return }
        let mask: CGEventMask = 1 << MusicLaunchSupport.systemDefinedEventTypeRawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<MusicLaunchBlocker>.fromOpaque(refcon).takeUnretainedValue()
                blocker.handleMediaKeyEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        mediaKeyTap = tap
        mediaKeyTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeMediaKeyTap() {
        guard let tap = mediaKeyTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let mediaKeyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mediaKeyTapSource, .commonModes)
        }
        mediaKeyTapSource = nil
        mediaKeyTap = nil
    }

    private func handleMediaKeyEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let mediaKeyTap { CGEvent.tapEnable(tap: mediaKeyTap, enable: true) }
            return
        }
        guard type.rawValue == MusicLaunchSupport.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              MusicLaunchSupport.isMusicLaunchTrigger(subtype: Int(nsEvent.subtype.rawValue),
                                                       data1: nsEvent.data1)
        else { return }
        lastMediaKeyAt = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Launch handling

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              Self.blockedBundleIDs.contains(bundleID) else { return }
        // Only block launches triggered by a media key press within the arm window.
        // User-initiated opens (Dock, Spotlight, double-click) pass through.
        let now = ProcessInfo.processInfo.systemUptime
        guard MusicLaunchSupport.shouldBlockLaunch(now: now, lastTriggerAt: lastMediaKeyAt) else { return }
        if !app.forceTerminate() {
            app.terminate()
        }
        openReplacementIfConfigured()
    }

    private func openReplacementIfConfigured() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReplacementLaunch > 1.0 else { return }
        lastReplacementLaunch = now

        let path = UserDefaults.standard.string(forKey: DefaultsKey.musicBlockReplacementPath) ?? ""
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        // The replacement must never be the app being blocked, or the two
        // settings would chase each other in a launch-and-kill loop.
        guard let replacementID = Bundle(url: url)?.bundleIdentifier,
              !Self.blockedBundleIDs.contains(replacementID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
