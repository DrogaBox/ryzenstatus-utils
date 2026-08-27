// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// Reads the system media session (any app that publishes now-playing info:
/// the music app, Spotify, browsers, video players) and surfaces it in the
/// menu bar and the menu panel.
///
/// The service is a hub feature: `syncWithPreferences` starts it only while
/// the feature is available AND its enable key is on, and stops it the moment
/// either flips. While stopped there are no timers, no observers and no status
/// item — zero idle cost, exactly like the other features.
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    /// Fired when the menu bar item is clicked, with the status item button
    /// so the panel can anchor its popup to it. AppDelegate wires this to
    /// toggle the detached now-playing popup.
    var onActivate: ((NSStatusBarButton) -> Void)?

    /// Fired when the service stops (feature switched off, app quitting) so
    /// any popup anchored to the item closes with its owner.
    var onDeactivate: (() -> Void)?

    /// Fired by the global hotkeys (PlayStatus parity, MIT): O toggles the
    /// anchored popover, D the detached window. AppDelegate wires both to
    /// the same surfaces the menu bar item toggles.
    var onTogglePopupHotkey: (() -> Void)?
    var onToggleDetachedHotkey: (() -> Void)?

    /// True when macOS refused the registration (combination taken); the
    /// settings row reports it so a dead shortcut is never silent.
    @Published private(set) var popupShortcutRegistrationFailed = false
    @Published private(set) var detachedShortcutRegistrationFailed = false

    /// The menu bar button the popup anchors to; the hotkeys need it too.
    var statusItemButton: NSStatusBarButton? { statusItem?.button }

    @Published private(set) var snapshot = NowPlayingSnapshot.empty
    @Published private(set) var artworkImage: NSImage?
    /// Fingerprint of the current artwork (dimensions + 12×12 pixel hash).
    /// Views key their change animations on it: identical pixels never
    /// re-animate (e.g. when a popover reopens), a genuinely new cover does.
    @Published private(set) var artworkIdentity = ""

    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.now-playing", qos: .utility)
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var lastRenderedKey = ""
    private var marqueeTimer: Timer?
    private var marqueeEngine = NowPlayingMarqueeEngine()
    private var lastPollStartedAt: TimeInterval = 0
    private var pollGeneration = 0
    private var appNameCache: [String: String?] = [:]
    /// Data-keyed fingerprint memoization: the artwork bytes repeat on
    /// every poll of the same track, so comparing them skips the 12×12
    /// re-hash. Keying by data (not NSImage) matters — `snapshot.artwork`
    /// builds a fresh image per access, so an image-keyed cache never hits.
    private var lastFingerprintedData: Data?
    private var lastArtworkIdentity = ""
    private var cancellables = Set<AnyCancellable>()

    /// Free ids in the app's shared Carbon hotkey table: 25 popover,
    /// 26 detached window.
    private let popupHotkey = QuickToolHotkey(id: 25)
    private let detachedHotkey = QuickToolHotkey(id: 26)

    private init() {
        popupHotkey.onPress = { [weak self] in self?.onTogglePopupHotkey?() }
        detachedHotkey.onPress = { [weak self] in self?.onToggleDetachedHotkey?() }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let engaged = AppFeature.nowPlaying.isAvailable
            && defaults.bool(forKey: DefaultsKey.nowPlayingEnabled)
        if engaged {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        pollGeneration += 1
        let provider = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto
        if MediaRemoteBridge.readsBlockedBySystem {
            if provider == .auto || provider == .music {
                MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.musicBundleID)
            }
            if provider == .auto || provider == .spotify {
                MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.spotifyBundleID)
            }
        } else {
            MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.musicBundleID)
        }
        installStatusItem()
        syncShortcuts()
        poll()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrTerminated), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopMarquee()
        pollGeneration += 1
        lastPollStartedAt = 0
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        lastRenderedKey = ""
        snapshot = .empty
        artworkImage = nil
        artworkIdentity = ""
        lastFingerprintedData = nil
        lastArtworkIdentity = ""
        NowPlayingAnimatedArtworkCenter.shared.sync(with: .empty)
        popupHotkey.unregister()
        detachedHotkey.unregister()
        popupShortcutRegistrationFailed = false
        detachedShortcutRegistrationFailed = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onDeactivate?()
    }

    @objc private func appLaunchedOrTerminated() {
        queue.async { [weak self] in
            self?.appNameCache.removeAll()
        }
    }

    // MARK: - Reading

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPollStartedAt >= 2.0 else { return }
        lastPollStartedAt = now
        let gen = pollGeneration
        let provider = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto

        if MediaRemoteBridge.readsBlockedBySystem {
            NowPlayingAutomation.fetchSnapshot(provider: provider, queue: queue) { [weak self] snapshot in
                DispatchQueue.main.async {
                    guard let self, self.timer != nil, gen == self.pollGeneration else { return }
                    var next = snapshot
                    if !provider.accepts(next.appBundleID) {
                        next = .empty
                    }
                    if next != self.snapshot {
                        self.snapshot = next
                        self.artworkImage = next.artwork
                        self.artworkIdentity = self.artworkIdentity(for: next.artworkData)
                        NowPlayingAnimatedArtworkCenter.shared.sync(with: next)
                    }
                    self.renderMenuBar()
                }
            }
            return
        }

        MediaRemoteBridge.fetchNowPlaying(queue: queue) { [weak self] snapshot in
            MediaRemoteBridge.fetchPlayingApp(queue: self?.queue ?? .main) { [weak self] bundleID in
                var resolvedAppName: String? = nil
                if let bundleID = bundleID, let self = self {
                    if let cached = self.appNameCache[bundleID] {
                        resolvedAppName = cached
                    } else {
                        let name = self.appName(for: bundleID)
                        self.appNameCache[bundleID] = name
                        resolvedAppName = name
                    }
                }
                var next = snapshot
                next.appBundleID = bundleID
                next.appName = resolvedAppName
                // MediaRemote never reports shuffle/repeat; the scriptable
                // providers answer for themselves on the same queue.
                if bundleID == NowPlayingAutomation.musicBundleID
                    || bundleID == NowPlayingAutomation.spotifyBundleID,
                   let modes = NowPlayingAutomation.fetchPlaybackModes(bundleID: bundleID) {
                    next.isShuffleEnabled = modes.shuffle
                    next.repeatMode = modes.repeatMode
                }
                DispatchQueue.main.async {
                    guard let self, self.timer != nil, gen == self.pollGeneration else { return }
                    // A pinned provider filters the session out entirely:
                    // nothing shows until that app is the one playing.
                    if !provider.accepts(bundleID) {
                        next = .empty
                    }
                    if next != self.snapshot {
                        self.snapshot = next
                        self.artworkImage = next.artwork
                        self.artworkIdentity = self.artworkIdentity(for: next.artworkData)
                        NowPlayingAnimatedArtworkCenter.shared.sync(with: next)
                    }
                    self.renderMenuBar()
                }
            }
        }
    }

    /// The fingerprint for the current artwork data, memoized on the bytes
    /// themselves (count + first 64B match the last hashed buffer) so the
    /// 12×12 downscale is only computed once per real artwork change.
    private func artworkIdentity(for data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        if let last = lastFingerprintedData,
           last.count == data.count,
           last.prefix(64) == data.prefix(64) {
            return lastArtworkIdentity
        }
        let identity = NowPlayingSnapshot.artworkFingerprint(of: data)
        lastFingerprintedData = data
        lastArtworkIdentity = identity
        return identity
    }

    /// The friendliest known name for the app owning the media session;
    /// bundle identifiers alone are not user-facing.
    private func appName(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.localizedName
        }
        if let name = Bundle(identifier: bundleID)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return name
        }
        return bundleID
    }

    // MARK: - Transport

    func togglePlayPause() {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID {
            NowPlayingAutomation.togglePlayPause(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.togglePlayPause)
        } else {
            Self.postAuxKey(16)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func nextTrack() {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID {
            NowPlayingAutomation.nextTrack(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.nextTrack)
        } else {
            Self.postAuxKey(19)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func previousTrack() {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID {
            NowPlayingAutomation.previousTrack(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.previousTrack)
        } else {
            Self.postAuxKey(20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func seek(to seconds: TimeInterval) {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID {
            NowPlayingAutomation.seek(to: seconds, bundleID: bundleID)
        } else {
            MediaRemoteBridge.seek(to: seconds)
        }
    }

    private static func postAuxKey(_ type: Int32) {
        func post(down: Bool) {
            let stateFlags: NSEvent.ModifierFlags = down
                ? NSEvent.ModifierFlags(rawValue: 0xA00)
                : NSEvent.ModifierFlags(rawValue: 0xB00)
            let data1 = (Int(type) << 16) | ((down ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: stateFlags,
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1)
            else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    /// Only the AppleScript providers expose playback modes; every other
    /// session gets no shuffle/repeat buttons at all.
    var supportsPlaybackModes: Bool {
        snapshot.appBundleID == NowPlayingAutomation.musicBundleID
            || snapshot.appBundleID == NowPlayingAutomation.spotifyBundleID
    }

    /// Toggles shuffle through the provider's AppleScript, flipping the
    /// published state immediately so the button reacts before the next poll
    /// confirms it (PlayStatus-style AppleScript toggles, MIT).
    func toggleShuffle() {
        let bundleID = snapshot.appBundleID
        let target = !snapshot.isShuffleEnabled
        snapshot.isShuffleEnabled = target
        queue.async { [weak self] in
            let confirmed = NowPlayingAutomation.setShuffleEnabled(target, bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self else { return }
                // The provider's own answer wins; a failed command keeps the
                // optimistic flip, the next poll will correct it.
                self.snapshot.isShuffleEnabled = confirmed ?? target
            }
        }
    }

    /// Cycles the repeat mode: off → all → one → off for Music, off → all →
    /// off for Spotify (its dictionary has no single-track step).
    func cycleRepeatMode() {
        let bundleID = snapshot.appBundleID
        let target = snapshot.repeatMode.next(for: bundleID)
        snapshot.repeatMode = target
        queue.async { [weak self] in
            let confirmed = NowPlayingAutomation.setRepeatMode(target, bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot.repeatMode = confirmed ?? target
            }
        }
    }

    func applyPreferenceChanges() {
        guard timer != nil else { return }
        let provider = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto
        if !provider.accepts(snapshot.appBundleID) {
            snapshot = .empty
            artworkImage = nil
            artworkIdentity = ""
        }
        // Display settings changed: restart the marquee from a clean slate.
        stopMarquee()
        lastRenderedKey = ""
        syncShortcuts()
        renderMenuBar()
        poll()
    }

    /// Applies the two hotkey preferences: register, re-register on change,
    /// or release. The enable toggles gate on the feature key too through
    /// the shortcut's required-enable keys.
    private func syncShortcuts() {
        let defaults = UserDefaults.standard
        let popupShortcut = GlobalShortcut.saved(for: DefaultsKey.nowPlayingPopupShortcut,
                                                 fallback: .nowPlayingPopupDefault)
        let detachedShortcut = GlobalShortcut.saved(for: DefaultsKey.nowPlayingDetachedShortcut,
                                                    fallback: .nowPlayingDetachedDefault)
        popupShortcutRegistrationFailed = !popupHotkey.sync(
            enabled: defaults.bool(forKey: DefaultsKey.nowPlayingPopupShortcutEnabled),
            shortcut: popupShortcut)
        detachedShortcutRegistrationFailed = !detachedHotkey.sync(
            enabled: defaults.bool(forKey: DefaultsKey.nowPlayingDetachedShortcutEnabled),
            shortcut: detachedShortcut)
    }

    /// Drops the cached artwork fingerprints so covers are re-hashed from
    /// scratch on the next read. The action behind "Clear media cache".
    func clearMediaCache() {
        lastFingerprintedData = nil
        lastArtworkIdentity = ""
        NowPlayingLyricsCenter.shared.clearCache()
        NowPlayingAnimatedArtworkCenter.shared.clearCache()
        NowPlayingThemeEngine.clearCache()
    }

    /// Brings the app that owns the current session to the front, so the
    /// track title click acts like the original app's "open in source app".
    func openSourceApp() {
        guard let bundleID = snapshot.appBundleID, !bundleID.isEmpty else { return }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: appURL,
                                               configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        }
    }

    // MARK: - Menu bar item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "RyzenStatusNowPlaying"
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // mouseDown on purpose: a .transient popup dismisses on the
            // outside press, so toggling on the same mouseUp would race the
            // dismissal and reopen instantly. Toggling on mouseDown sidesteps
            // the close-reopen race for both left and right clicks.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageLeft
        }
        statusItem = item
        renderMenuBar()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        onActivate?(sender)
    }

    /// Composes the menu bar item into a single image: the note icon, the
    /// track text according to the display mode, and (optionally) a thin
    /// progress strip along the bottom. The item is always visible while the
    /// feature is on — idle shows a dimmed icon, not a hole in the bar.
    private func renderMenuBar() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let mode = NowPlayingMenuBarMode(rawValue: defaults.integer(forKey: DefaultsKey.nowPlayingMenuBarMode)) ?? .artistSong
        let showProgress = defaults.bool(forKey: DefaultsKey.nowPlayingMenuBarProgress)

        var text = ""
        let hasTrack = snapshot.hasTrack
        if !hasTrack {
            text = ""
        } else {
            switch mode {
            case .iconOnly: text = ""
            case .artist: text = snapshot.displayArtist
            case .song: text = snapshot.displayTitle
            case .artistSong:
                text = snapshot.displayArtist == "—"
                    ? snapshot.displayTitle
                    : "\(snapshot.displayTitle) — \(snapshot.displayArtist)"
            }
        }

        let progress: Double? = showProgress && hasTrack
            ? progressFraction : nil

        // The marquee advances its state machine here; the returned offset
        // joins the render key so every scroll step repaints the item.
        let marqueeOffset = updateMarquee(text: text,
                                          enabled: defaults.bool(forKey: DefaultsKey.nowPlayingMarquee))

        let progressStr = progress != nil ? String(Int(progress! * 100)) : "-"
        let appearance = button.effectiveAppearance.name.rawValue
        let offsetKey = marqueeOffset.map { String(Int($0.rounded())) } ?? "-"
        let key = "\(text)|\(hasTrack)|\(snapshot.isPlaying)|\(mode.rawValue)|\(progressStr)|\(offsetKey)|\(appearance)"
        guard key != lastRenderedKey else { return }
        lastRenderedKey = key

        let image = Self.composeMenuBarImage(text: text,
                                             hasTrack: hasTrack,
                                             isPlaying: snapshot.isPlaying,
                                             progress: progress,
                                             marqueeOffset: marqueeOffset)
        button.image = image
        button.toolTip = hasTrack
            ? "\(snapshot.displayTitle) — \(snapshot.displayArtist)"
            : nil
        button.setAccessibilityLabel(hasTrack 
            ? "\(snapshot.displayTitle) — \(snapshot.displayArtist)" 
            : FeatureStrings.nowPlaying(L10n.shared.language).emptyState)
    }

    private var progressFraction: Double? {
        guard let elapsed = snapshot.elapsed, let duration = snapshot.duration,
              duration > 0 else { return nil }
        return max(0, min(1, elapsed / duration))
    }

    // MARK: - Marquee

    /// The menu bar font of the composed item, shared by measurement and draw
    /// so the marquee overflow check and the pixels always agree.
    private static let menuBarTextFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let marqueeTickInterval: TimeInterval = 1.0 / 20.0

    /// Advances the marquee state machine and returns the horizontal offset
    /// to draw the text at (nil = static render). The tick timer only exists
    /// while text genuinely overflows the lane, so an idle bar costs nothing.
    private func updateMarquee(text: String, enabled: Bool) -> CGFloat? {
        let textWidth = Self.menuBarTextWidth(text)
        let slide = UserDefaults.standard.bool(forKey: DefaultsKey.nowPlayingMarqueeSlide)
        let now = CACurrentMediaTime()
        let result = marqueeEngine.update(text: text,
                                          textWidth: textWidth,
                                          enabled: enabled,
                                          slide: slide,
                                          now: now)
        if result.shouldTick {
            startMarqueeTimer()
        } else {
            stopMarqueeTimer()
            if let delay = result.nextHoldDelay {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.renderMenuBar()
                }
            }
        }
        return result.offset
    }

    private func startMarqueeTimer() {
        guard marqueeTimer == nil else { return }
        let timer = Timer(timeInterval: Self.marqueeTickInterval, repeats: true) { [weak self] _ in
            self?.renderMenuBar()
        }
        timer.tolerance = Self.marqueeTickInterval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        marqueeTimer = timer
    }

    private func stopMarqueeTimer() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
    }

    private func stopMarquee() {
        stopMarqueeTimer()
        marqueeEngine.reset()
    }

    private static func menuBarTextWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: menuBarTextFont]).width)
    }

    /// Draws the full status item in one pass so the icon, text and progress
    /// strip stay aligned. Native template rendering lets the menu bar recolor
    /// it for dark/light appearances and custom wallpapers.
    private static func composeMenuBarImage(text: String,
                                            hasTrack: Bool,
                                            isPlaying: Bool,
                                            progress: Double?,
                                            marqueeOffset: CGFloat?) -> NSImage {
        let symbolName = isPlaying ? "waveform" : "music.note"
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11.5, weight: isPlaying ? .semibold : .medium)
        let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        let iconImage = baseSymbol?.withSymbolConfiguration(iconConfig) ?? NSImage()

        // Pure template icon-only when there is no text and no progress bar.
        if text.isEmpty && progress == nil {
            let symbol = iconImage
            symbol.isTemplate = true
            return symbol
        }

        let font = menuBarTextFont
        let alpha: CGFloat = hasTrack ? (isPlaying ? 1.0 : 0.65) : 0.40
        let textColor = NSColor.black.withAlphaComponent(alpha)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        var textSize = (text as NSString).size(withAttributes: textAttrs)
        if textSize.width > 260 {
            textSize.width = 260
        }

        let progressHeight: CGFloat = 1.5
        let progressInset: CGFloat = 1
        let totalHeight: CGFloat = 18 + (progress != nil ? progressHeight + 1 : 0)
        let iconWidth: CGFloat = 14
        let gap: CGFloat = text.isEmpty ? 0 : 5
        let totalWidth = max(18, iconWidth + gap + textSize.width + (text.isEmpty ? 0 : 3))

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
            // Icon vertically centered
            let iconY = (totalHeight - 18) / 2 + (18 - 12) / 2
            iconImage.draw(in: NSRect(x: 0, y: iconY, width: 14, height: 12),
                           from: .zero, operation: .sourceOver, fraction: alpha)

            if !text.isEmpty {
                let textY = (totalHeight - 18) / 2 + 2.5
                let laneX = iconWidth + gap
                if let marqueeOffset {
                    NSGraphicsContext.saveGraphicsState()
                    NSRect(x: laneX, y: 0, width: textSize.width, height: totalHeight).clip()
                    let loopDistance = menuBarTextWidth(text) + NowPlayingMarqueeEngine.loopGap
                    for shift in [marqueeOffset, marqueeOffset - loopDistance] {
                        let x = laneX - shift
                        if x < laneX + textSize.width, x + menuBarTextWidth(text) > laneX {
                            (text as NSString).draw(at: NSPoint(x: x, y: textY),
                                                    withAttributes: textAttrs)
                        }
                    }
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    let textRect = NSRect(x: laneX, y: textY, width: textSize.width, height: textSize.height)
                    (text as NSString).draw(in: textRect, withAttributes: textAttrs)
                }
            }

            // Sleek hairline progress strip along the bottom
            if let progress {
                let barWidth = totalWidth - progressInset * 2
                let bar = NSBezierPath(roundedRect: NSRect(x: progressInset,
                                                           y: 0.5,
                                                           width: barWidth,
                                                           height: progressHeight),
                                       xRadius: progressHeight / 2,
                                       yRadius: progressHeight / 2)
                NSColor.black.withAlphaComponent(0.20).setFill()
                bar.fill()

                let fillWidth = max(progressHeight, barWidth * CGFloat(progress))
                let fill = NSBezierPath(roundedRect: NSRect(x: progressInset,
                                                             y: 0.5,
                                                             width: fillWidth,
                                                             height: progressHeight),
                                        xRadius: progressHeight / 2,
                                        yRadius: progressHeight / 2)
                NSColor.black.withAlphaComponent(0.85).setFill()
                fill.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
