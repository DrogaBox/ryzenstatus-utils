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
    private var marqueePhase = MarqueePhase.idle
    private var lastMarqueeText = ""
    private var lastPollStartedAt: TimeInterval = 0
    private var pollGeneration = 0
    private var appNameCache: [String: String?] = [:]
    private var artworkFingerprintCache = NSCache<NSImage, NSString>()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

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
                        self.artworkIdentity = self.artworkIdentity(for: next.artwork)
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
                DispatchQueue.main.async {
                    guard let self, self.timer != nil, gen == self.pollGeneration else { return }
                    var next = snapshot
                    next.appBundleID = bundleID
                    next.appName = resolvedAppName
                    // A pinned provider filters the session out entirely:
                    // nothing shows until that app is the one playing.
                    if !provider.accepts(bundleID) {
                        next = .empty
                    }
                    if next != self.snapshot {
                        self.snapshot = next
                        self.artworkImage = next.artwork
                        self.artworkIdentity = self.artworkIdentity(for: next.artwork)
                    }
                    self.renderMenuBar()
                }
            }
        }
    }

    /// The fingerprint for an artwork image, cached per image instance so
    /// the 12×12 downscale is only computed once per real artwork change.
    private func artworkIdentity(for image: NSImage?) -> String {
        guard let image else { return "" }
        if let cached = artworkFingerprintCache.object(forKey: image) {
            return cached as String
        }
        let identity = NowPlayingSnapshot.artworkFingerprint(of: snapshot.artworkData)
        artworkFingerprintCache.setObject(identity as NSString, forKey: image)
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
        if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.togglePlayPause)
        } else {
            NowPlayingAutomation.togglePlayPause(bundleID: snapshot.appBundleID)
        }
    }

    func nextTrack() {
        if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.nextTrack)
        } else {
            NowPlayingAutomation.nextTrack(bundleID: snapshot.appBundleID)
        }
    }

    func previousTrack() {
        if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.previousTrack)
        } else {
            NowPlayingAutomation.previousTrack(bundleID: snapshot.appBundleID)
        }
    }

    func seek(to seconds: TimeInterval) {
        if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.seek(to: seconds)
        } else {
            NowPlayingAutomation.seek(to: seconds, bundleID: snapshot.appBundleID)
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
        renderMenuBar()
        poll()
    }

    /// Drops the cached artwork fingerprints so covers are re-hashed from
    /// scratch on the next read. The action behind "Clear media cache".
    func clearMediaCache() {
        artworkFingerprintCache.removeAllObjects()
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
    /// The text lane never grows past this; longer text scrolls instead.
    private static let marqueeMaxTextWidth: CGFloat = 260
    /// Pause before the first scroll and between loops.
    private static let marqueeHoldDuration: TimeInterval = 1.6
    private static let marqueeSpeed: CGFloat = 26 // pt per second
    /// Breathing room between the tail of one pass and the head of the next.
    private static let marqueeLoopGap: CGFloat = 48
    private static let marqueeSlideDuration: TimeInterval = 0.45
    private static let marqueeTickInterval: TimeInterval = 1.0 / 30.0

    /// The marquee lifecycle: a new track slides in (optionally), holds, scrolls
    /// left, and loops with a hold between passes.
    private enum MarqueePhase {
        case idle
        case slideIn(startedAt: TimeInterval)
        case hold(startedAt: TimeInterval)
        case scroll(startedAt: TimeInterval)
    }

    /// Advances the marquee state machine and returns the horizontal offset
    /// to draw the text at (nil = static render). The tick timer only exists
    /// while text genuinely overflows the lane, so an idle bar costs nothing.
    private func updateMarquee(text: String, enabled: Bool) -> CGFloat? {
        let needsMarquee = enabled && !text.isEmpty
            && Self.menuBarTextWidth(text) > Self.marqueeMaxTextWidth
        guard needsMarquee else {
            stopMarquee()
            return nil
        }
        let now = CACurrentMediaTime()
        if text != lastMarqueeText {
            lastMarqueeText = text
            let slide = UserDefaults.standard.bool(forKey: DefaultsKey.nowPlayingMarqueeSlide)
            marqueePhase = slide ? .slideIn(startedAt: now) : .hold(startedAt: now)
        }
        startMarqueeTimer()
        switch marqueePhase {
        case .idle:
            return 0
        case .slideIn(let startedAt):
            let progress = min(1, (now - startedAt) / Self.marqueeSlideDuration)
            if progress >= 1 {
                marqueePhase = .hold(startedAt: now)
                return 0
            }
            // Ease-out cubic: the text arrives fast and settles into place.
            let eased = CGFloat(1 - pow(1 - progress, 3))
            return -Self.marqueeMaxTextWidth * (1 - eased)
        case .hold(let startedAt):
            if now - startedAt >= Self.marqueeHoldDuration {
                marqueePhase = .scroll(startedAt: now)
            }
            return 0
        case .scroll(let startedAt):
            let distance = Self.menuBarTextWidth(text) + Self.marqueeLoopGap
            let offset = CGFloat(now - startedAt) * Self.marqueeSpeed
            if offset >= distance {
                marqueePhase = .hold(startedAt: now)
                return 0
            }
            return offset
        }
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

    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        marqueePhase = .idle
        lastMarqueeText = ""
    }

    private static func menuBarTextWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: menuBarTextFont]).width)
    }

    /// Draws the full status item in one pass so the icon, text and progress
    /// strip stay aligned regardless of the menu bar's dark/light appearance.
    private static func composeMenuBarImage(text: String,
                                            hasTrack: Bool,
                                            isPlaying: Bool,
                                            progress: Double?,
                                            marqueeOffset: CGFloat?) -> NSImage {
        let icon = NSImage(systemSymbolName: "music.note",
                           accessibilityDescription: nil)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let iconImage = icon?.withSymbolConfiguration(iconConfig) ?? NSImage()

        let font = menuBarTextFont
        let dim = hasTrack && !isPlaying
        let textColor: NSColor = hasTrack
            ? (dim ? NSColor.secondaryLabelColor : NSColor.labelColor)
            : NSColor.tertiaryLabelColor

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

        let progressHeight: CGFloat = 2.5
        let progressInset: CGFloat = 2
        let totalHeight: CGFloat = 18 + (progress != nil ? progressHeight + 1 : 0)
        let iconWidth: CGFloat = 14
        let gap: CGFloat = text.isEmpty ? 0 : 4
        let totalWidth = max(20, iconWidth + gap + textSize.width + 4)

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
            // Icon, vertically centered on the text line.
            let iconY = (totalHeight - 18) / 2 + (18 - 11) / 2
            iconImage.draw(in: NSRect(x: 1, y: iconY, width: 14, height: 11),
                           from: .zero, operation: .sourceOver, fraction: 1)

            if !text.isEmpty {
                let textY = (totalHeight - 18) / 2 + 3
                let laneX = 1 + iconWidth + gap
                if let marqueeOffset {
                    // Scrolling lane: clip to the fixed-width window and draw
                    // the text twice — the live copy and the loop copy one
                    // full pass ahead — so the wrap is seamless.
                    NSGraphicsContext.saveGraphicsState()
                    NSRect(x: laneX, y: 0, width: textSize.width, height: totalHeight).clip()
                    let loopDistance = menuBarTextWidth(text) + marqueeLoopGap
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

            // Thin progress strip along the bottom, matching the menu bar accent.
            if let progress {
                let barWidth = totalWidth - progressInset * 2
                let bar = NSBezierPath(roundedRect: NSRect(x: progressInset,
                                                           y: 1,
                                                           width: barWidth,
                                                           height: progressHeight),
                                       xRadius: progressHeight / 2,
                                       yRadius: progressHeight / 2)
                NSColor.quaternaryLabelColor.setFill()
                bar.fill()

                let fill = NSBezierPath(roundedRect: NSRect(x: progressInset,
                                                            y: 1,
                                                            width: max(progressHeight, barWidth * CGFloat(progress)),
                                                            height: progressHeight),
                                        xRadius: progressHeight / 2,
                                        yRadius: progressHeight / 2)
                NSColor.controlAccentColor.setFill()
                fill.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
