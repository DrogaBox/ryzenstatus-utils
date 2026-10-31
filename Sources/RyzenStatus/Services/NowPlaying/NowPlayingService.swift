// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// Reads the system media session (any app that publishes now-playing info:
/// the music app, Spotify, browsers, video players) and surfaces it in the
/// menu bar and the menu panel.
///
/// It is the single now-playing engine of the app: the Dynamic Island reads
/// the same session through `playback`/`artworkImage`/`artworkTint` and the
/// track change subjects, and commands it through `send(_:)`, shuffle and
/// the scripting consent below. The island registers as the `.notch`
/// consumer; its feed is only computed while that consumer is active.
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
    /// One once a poll has finished, whatever it found, so a one-off reader
    /// (the radial menu) can tell "nothing is playing" from "not read yet".
    /// Set on the first reading only: bumping it on every poll would redraw
    /// every observer every two seconds.
    @Published private(set) var completedReadings = 0
    /// Polling is running and has answered at least once.
    var hasCurrentReading: Bool { timer != nil && completedReadings > 0 }
    @Published private(set) var artworkImage: NSImage?
    /// Fingerprint of the current artwork (dimensions + 12×12 pixel hash).
    /// Views key their change animations on it: identical pixels never
    /// re-animate (e.g. when a popover reopens), a genuinely new cover does.
    @Published private(set) var artworkIdentity = ""

    // MARK: Island feed (computed only while the `.notch` consumer is active)

    /// The current reading on a playback clock, nil when nothing plays.
    @Published private(set) var playback: NowPlayingPlayback?
    /// The cover's colour for halos and accents; nil for neutral covers.
    @Published private(set) var artworkTint: NowPlayingArtworkTint?
    /// The player's upcoming songs: the rest of Music's current playlist
    /// while the island's queue is on. Nil for every other player, and the
    /// island reports the queue as unavailable.
    @Published private(set) var upcoming: NowPlayingQueue?
    /// Consent state for the player's scripting dictionary, when it has one.
    @Published private(set) var automationAvailability: NowPlayingScripting.Availability?
    @Published private(set) var requestingAutomation = false
    /// Shuffle read through a scripting dictionary, for players outside the
    /// AppleScript providers. Nil until the player answers.
    @Published private(set) var scriptedShuffleEnabled: Bool?
    @Published private(set) var scriptedShuffleAllowed = true
    @Published private(set) var scriptedShufflePending = false
    @Published private(set) var requestingShuffleAccess = false
    /// Sent before a reading that starts a new song is published.
    let trackChanges = PassthroughSubject<Void, Never>()
    /// Sent before the reading that ends playback is published.
    let trackEnds = PassthroughSubject<Void, Never>()
    /// Skips asked for by a swipe on the island; true is forward.
    let gestureSkips = PassthroughSubject<Bool, Never>()
    private var trackChangeDetector = NowPlayingTrackChange()
    private var tintIdentity = ""
    private var scriptingCapabilities: [URL: NowPlayingScriptingCapabilities?] = [:]
    private var shuffleGeneration = UUID()
    private var shuffleSwitchID = UUID()
    private var shuffleReading = false
    /// The song and shuffle state `upcoming` was read for, so the playlist is
    /// asked again only when either changes, not on every poll.
    private var upcomingKey = ""
    private var upcomingGeneration = UUID()
    private static let upcomingLimit = 25

    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.now-playing", qos: .utility)
    /// Apple Events to scriptable players wait up to a second for a reply;
    /// they get their own queue so they never hold up a poll.
    private let scriptingQueue = DispatchQueue(label: "com.ryzenstatus.utils.now-playing-scripting", qos: .utility)
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
    /// Lock, sleep and console state, seeded when observing starts. Polls
    /// and the marquee wait while nobody can see the item or the island.
    private var session = NotchSessionState()
    private var sessionObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var statusItemOcclusionObserver: NSObjectProtocol?
    /// The marquee's next redraw after a hold; one at a time.
    private var marqueeHoldWork: DispatchWorkItem?
    private var automationCheckGeneration = UUID()

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

    enum Consumer: Hashable {
        case menuBar
        case notch
        /// The radial menu's Now Playing slice, held only until one reading lands.
        case radialMenu
    }
    private var activeConsumers = Set<Consumer>()

    func registerConsumer(_ consumer: Consumer) {
        let wasEmpty = activeConsumers.isEmpty
        activeConsumers.insert(consumer)
        if wasEmpty {
            startPolling()
        }
        if consumer == .menuBar {
            installStatusItem()
            syncShortcuts()
        }
        if consumer == .notch {
            syncIslandFeed()
        }
    }

    func unregisterConsumer(_ consumer: Consumer) {
        activeConsumers.remove(consumer)
        if consumer == .menuBar {
            removeStatusItemOcclusionObserver()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            self.statusItem = nil
            lastRenderedKey = ""
            stopMarquee()
            popupHotkey.unregister()
            detachedHotkey.unregister()
            popupShortcutRegistrationFailed = false
            detachedShortcutRegistrationFailed = false
        }
        if consumer == .notch {
            clearIslandFeed()
        }
        if activeConsumers.isEmpty {
            stopPolling()
        }
    }

    /// The island's music surfaces start and stop the shared reading here.
    func startIslandFeed() { registerConsumer(.notch) }
    func stopIslandFeed() { unregisterConsumer(.notch) }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let engaged = AppFeature.nowPlaying.isAvailable
            && defaults.bool(forKey: DefaultsKey.nowPlayingEnabled)
        if engaged {
            registerConsumer(.menuBar)
        } else {
            unregisterConsumer(.menuBar)
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        pollGeneration += 1
        let provider = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto
        if MediaRemoteBridge.readsBlockedBySystem {
            if (provider == .auto || provider == .music),
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingAutomation.musicBundleID) != nil {
                MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.musicBundleID)
            }
            if (provider == .auto || provider == .spotify),
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingAutomation.spotifyBundleID) != nil {
                MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.spotifyBundleID)
            }
            if provider == .auto || provider == .kaset {
                let kasetID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingAutomation.kasetBundleID) != nil
                    ? NowPlayingAutomation.kasetBundleID
                    : (NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingAutomation.kasetBundleIDLower) != nil ? NowPlayingAutomation.kasetBundleIDLower : nil)
                if let kasetID {
                    MediaRemoteBridge.triggerTCCPrompt(for: kasetID)
                }
            }
        } else {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingAutomation.musicBundleID) != nil {
                MediaRemoteBridge.triggerTCCPrompt(for: NowPlayingAutomation.musicBundleID)
            }
        }
        installSessionObservers()
        poll()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        if !session.canPresent { t.fireDate = .distantFuture }
        timer = t
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrTerminated), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func stop() {
        activeConsumers.removeAll()
        removeStatusItemOcclusionObserver()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        lastRenderedKey = ""
        popupHotkey.unregister()
        detachedHotkey.unregister()
        popupShortcutRegistrationFailed = false
        detachedShortcutRegistrationFailed = false
        stopPolling()
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        stopMarquee()
        pollGeneration += 1
        lastPollStartedAt = 0
        snapshot = .empty
        completedReadings = 0
        artworkImage = nil
        artworkIdentity = ""
        lastFingerprintedData = nil
        lastArtworkIdentity = ""
        NowPlayingAnimatedArtworkCenter.shared.sync(with: .empty)
        clearIslandFeed()
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
        guard session.canPresent else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPollStartedAt >= 2.0 else { return }
        lastPollStartedAt = now
        let gen = pollGeneration
        let provider = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto

        if MediaRemoteBridge.readsBlockedBySystem {
            NowPlayingAutomation.fetchSnapshot(provider: provider, queue: queue) { [weak self] snapshot in
                var next = snapshot
                next.sampledAt = Date()
                DispatchQueue.main.async {
                    guard let self, self.timer != nil, gen == self.pollGeneration else { return }
                    if !provider.accepts(next.appBundleID) {
                        next = .empty
                    }
                    self.apply(next)
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
                    || bundleID == NowPlayingAutomation.spotifyBundleID
                    || NowPlayingAutomation.isKaset(bundleID),
                   let modes = NowPlayingAutomation.fetchPlaybackModes(bundleID: bundleID) {
                    next.isShuffleEnabled = modes.shuffle
                    next.repeatMode = modes.repeatMode
                }
                next.sampledAt = Date()
                DispatchQueue.main.async {
                    guard let self, self.timer != nil, gen == self.pollGeneration else { return }
                    // A pinned provider filters the session out entirely:
                    // nothing shows until that app is the one playing.
                    if !provider.accepts(bundleID) {
                        next = .empty
                    }
                    self.apply(next)
                }
            }
        }
    }

    /// One finished reading. A reading the published one already predicts
    /// (the same song, the playhead where its clock puts it) publishes
    /// nothing; the cover is decoded again only when its bytes change.
    private func apply(_ next: NowPlayingSnapshot) {
        if !NowPlayingSnapshot.continues(snapshot, with: next) {
            let identity = artworkIdentity(for: next.artworkData)
            snapshot = next
            if identity != artworkIdentity {
                artworkImage = next.artwork
                artworkIdentity = identity
            }
            NowPlayingAnimatedArtworkCenter.shared.sync(with: next)
            syncIslandFeed()
        }
        if completedReadings == 0 { completedReadings = 1 }
        renderMenuBar()
    }

    /// The fingerprint for the current artwork data, memoized on the bytes
    /// themselves (the whole buffer matches the last hashed one) so the
    /// 12×12 downscale is only computed once per real artwork change.
    private func artworkIdentity(for data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        if let last = lastFingerprintedData, last == data {
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
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID || NowPlayingAutomation.isKaset(bundleID) {
            NowPlayingAutomation.togglePlayPause(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.togglePlayPause)
        } else if !sendScripted(.toggle) {
            Self.postAuxKey(16)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func nextTrack() {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID || NowPlayingAutomation.isKaset(bundleID) {
            NowPlayingAutomation.nextTrack(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.nextTrack)
        } else if !sendScripted(.next) {
            Self.postAuxKey(19)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func previousTrack() {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID || NowPlayingAutomation.isKaset(bundleID) {
            NowPlayingAutomation.previousTrack(bundleID: bundleID)
        } else if MediaRemoteBridge.sendCommand != nil {
            MediaRemoteBridge.send(.previousTrack)
        } else if !sendScripted(.previous) {
            Self.postAuxKey(20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.poll()
        }
    }

    func seek(to seconds: TimeInterval) {
        let bundleID = snapshot.appBundleID
        if bundleID == NowPlayingAutomation.spotifyBundleID || bundleID == NowPlayingAutomation.musicBundleID || NowPlayingAutomation.isKaset(bundleID) {
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
            || NowPlayingAutomation.isKaset(snapshot.appBundleID)
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
            syncIslandFeed()
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
            shortcut: popupShortcut,
            storageKey: DefaultsKey.nowPlayingPopupShortcut)
        detachedShortcutRegistrationFailed = !detachedHotkey.sync(
            enabled: defaults.bool(forKey: DefaultsKey.nowPlayingDetachedShortcutEnabled),
            shortcut: detachedShortcut,
            storageKey: DefaultsKey.nowPlayingDetachedShortcut)
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

    // MARK: - Island feed

    /// Derives the island's reading from the current snapshot. Runs after
    /// every published snapshot change, and only while the island listens.
    private func syncIslandFeed() {
        guard activeConsumers.contains(.notch) else { return }
        let pid = snapshot.appBundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier
        }
        // The reading's own clock, so a feed derived later still places the
        // playhead where the song is now.
        guard let next = NowPlayingPlayback.make(from: snapshot, pid: pid, sampledAt: snapshot.sampledAt ?? Date()) else {
            if playback != nil {
                // Sent first, so the island lets the ending song go as itself.
                trackEnds.send()
                playback = nil
                artworkTint = nil
                tintIdentity = ""
                automationAvailability = nil
                automationCheckGeneration = UUID()
            }
            return
        }
        let isNewSong = trackChangeDetector.isNewSong(next, first: playback == nil)
        // The tint only changes with the cover: one 1×1 draw per new cover.
        if artworkIdentity != tintIdentity {
            tintIdentity = artworkIdentity
            artworkTint = artworkImage.flatMap(NowPlayingArtworkTint.sample)
        }
        playback = next
        NowPlayingPreferredPlayer.remember(next)
        refreshAutomation()
        refreshUpcomingIfNeeded()
        if isNewSong {
            trackChanges.send()
        }
    }

    private func clearIslandFeed() {
        playback = nil
        artworkTint = nil
        tintIdentity = ""
        automationAvailability = nil
        automationCheckGeneration = UUID()
        upcoming = nil
        upcomingKey = ""
        upcomingGeneration = UUID()
        trackChangeDetector.reset()
        stopShuffleReading()
    }

    var canSeek: Bool { playback?.canSeek == true }

    func lacksTrackSkipping(_ command: NowPlayingTransportCommand) -> Bool {
        switch command {
        case .next: return playback?.canSkipNext != true
        case .previous: return playback?.canSkipPrevious != true
        default: return false
        }
    }

    func canPerform(_ command: NowPlayingTransportCommand) -> Bool {
        playback != nil
    }

    /// The island's transport. Every command goes through the same provider
    /// routing as the menu panel's buttons.
    @discardableResult
    func send(_ command: NowPlayingTransportCommand, context: NowPlayingPlaybackContext? = nil) -> Bool {
        switch command {
        case .toggle: togglePlayPause()
        case .next: nextTrack()
        case .previous: previousTrack()
        case .seek(let seconds):
            guard NowPlayingTransportCommand.validPosition(seconds) else { return false }
            seek(to: seconds)
        }
        return true
    }

    func skipFromGesture(forward: Bool) {
        if forward { nextTrack() } else { previousTrack() }
        gestureSkips.send(forward)
    }

    /// Opens the app that owns the island's current reading.
    func openPlayingApp() {
        guard let track = playback?.track else { openSourceApp(); return }
        NowPlayingApplication.open(track)
    }

    // MARK: - Scripting dictionaries

    /// Reads which scripting commands the playing app declares and whether
    /// this app may send them. The dictionary is parsed once per app; both
    /// it and the permission check (which can block for a second) run on the
    /// scripting queue. `force` drops the recent permission answer first, for
    /// a person who asks to look again after changing it in System Settings.
    func refreshAutomation(force: Bool = false) {
        let generation = UUID()
        automationCheckGeneration = generation
        guard let playback, let target = NowPlayingScripting.Target(playback) else {
            if automationAvailability != nil { automationAvailability = nil }
            return
        }
        if force { NowPlayingScripting.forgetAccess(for: target.pid) }
        let cached = scriptingCapabilities[target.bundleURL]
        scriptingQueue.async { [weak self] in
            let capabilities = cached ?? NowPlayingScriptingCapabilities.load(bundleURL: target.bundleURL)
            let access: NowPlayingScripting.Access = capabilities == nil ? .unavailable : NowPlayingScripting.access(to: target)
            DispatchQueue.main.async {
                guard let self, self.automationCheckGeneration == generation else { return }
                if cached == nil {
                    if self.scriptingCapabilities.count > 16 { self.scriptingCapabilities.removeAll() }
                    self.scriptingCapabilities[target.bundleURL] = .some(capabilities)
                }
                guard let capabilities else {
                    if self.automationAvailability != nil { self.automationAvailability = nil }
                    return
                }
                let next = NowPlayingScripting.Availability(target: target, capabilities: capabilities, access: access)
                let current = self.automationAvailability
                guard next.target != current?.target || next.access != current?.access
                        || next.capabilities != current?.capabilities else { return }
                self.automationAvailability = next
                // Shuffle is read through the same consent, so it looks again.
                if self.shuffleReading { self.refreshShuffle() }
            }
        }
    }

    /// Asks for consent off the main thread: the call waits for the person
    /// to answer the system dialog, and the island and menu bar keep working.
    func requestAutomationAccess() {
        guard !requestingAutomation, let playback, let target = NowPlayingScripting.Target(playback) else { return }
        requestingAutomation = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let address = NSAppleEventDescriptor(processIdentifier: target.pid)
            withExtendedLifetime(address) {
                _ = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, true)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAutomation = false
                NowPlayingScripting.forgetAccess(for: target.pid)
                self.refreshAutomation()
            }
        }
    }

    /// Players outside the providers that MediaRemote cannot reach still
    /// take the commands their dictionary declares, once allowed.
    private func sendScripted(_ command: NowPlayingTransportCommand) -> Bool {
        guard let playback, let availability = automationAvailability, availability.access == .granted,
              availability.capabilities.event(for: command, isPlaying: playback.isPlaying) != nil else { return false }
        let validatedAt = ProcessInfo.processInfo.systemUptime
        scriptingQueue.async {
            _ = NowPlayingScripting.send(command, playback: playback, availability: availability,
                                         cancellation: DispatchWorkItem {}, validatedAt: validatedAt)
        }
        return true
    }

    // MARK: - Island queue

    /// Reads Music's upcoming songs when the song or shuffle changed. Every
    /// other player keeps the queue unavailable.
    private func refreshUpcomingIfNeeded() {
        guard NotchQueueSupport.isEnabled(), snapshot.appBundleID == NowPlayingAutomation.musicBundleID else {
            upcomingKey = ""
            upcomingGeneration = UUID()
            if upcoming != nil { upcoming = nil }
            return
        }
        let key = [snapshot.title, snapshot.artist, snapshot.album].map { $0 ?? "" }.joined(separator: "\u{1F}")
            + (snapshot.isShuffleEnabled ? "|shuffled" : "")
        guard key != upcomingKey else { return }
        upcomingKey = key
        reloadUpcoming()
    }

    private func reloadUpcoming() {
        let generation = UUID()
        upcomingGeneration = generation
        scriptingQueue.async { [weak self] in
            let queue = NowPlayingAutomation.fetchMusicUpcoming(limit: Self.upcomingLimit)
            DispatchQueue.main.async {
                guard let self, self.upcomingGeneration == generation else { return }
                self.upcoming = queue
            }
        }
    }

    /// Plays one of the listed songs in Music. The next poll sees the new
    /// song and reads the queue again from there.
    func playUpcoming(_ item: NowPlayingQueueItem) {
        guard upcoming?.canPlay == true, let databaseID = Int(item.id) else { return }
        scriptingQueue.async {
            NowPlayingAutomation.playMusicUpcoming(databaseID: databaseID)
        }
    }

    // MARK: - Island shuffle

    /// Shuffle the island offers: the provider's own (Music, Spotify, Kaset)
    /// or the switch another player's scripting dictionary declares.
    var shuffleIsOffered: Bool {
        if supportsPlaybackModes { return true }
        guard let availability = automationAvailability, availability.capabilities.shuffle != nil else { return false }
        return availability.access == .consent || (availability.access == .granted && scriptedShuffleEnabled != nil)
    }

    var shuffleIsOn: Bool {
        supportsPlaybackModes ? snapshot.isShuffleEnabled : scriptedShuffleEnabled == true
    }

    /// The first press on a scriptable player not yet allowed asks for consent.
    var shuffleNeedsConsent: Bool {
        !supportsPlaybackModes && automationAvailability?.access == .consent
    }

    var shuffleIsBlocked: Bool {
        !supportsPlaybackModes && (requestingShuffleAccess || !scriptedShuffleAllowed)
    }

    /// Reads a scriptable player's shuffle switch. Runs when the island's
    /// music page opens and whenever its song or player changes, since
    /// shuffle can also be switched in the player itself. The providers'
    /// shuffle is already read by every poll.
    func refreshShuffle() {
        shuffleReading = true
        let requested = UUID()
        shuffleGeneration = requested
        guard !supportsPlaybackModes, let available = automationAvailability,
              available.capabilities.shuffle != nil else {
            scriptedShuffleEnabled = nil
            scriptedShuffleAllowed = true
            return
        }
        scriptingQueue.async { [weak self] in
            let state = NowPlayingScripting.shuffle(of: available)
            let allowed = NowPlayingScripting.shuffleAllowed(by: available)
            DispatchQueue.main.async {
                guard let self, self.shuffleGeneration == requested else { return }
                self.scriptedShuffleEnabled = state
                self.scriptedShuffleAllowed = allowed
            }
        }
    }

    func toggleIslandShuffle() {
        if supportsPlaybackModes {
            toggleShuffle()
            return
        }
        guard !scriptedShufflePending, !requestingShuffleAccess, let available = automationAvailability,
              available.capabilities.shuffle != nil, available.target.isCurrent else { return }
        if available.access == .consent {
            requestShuffleAccess(available)
            return
        }
        guard available.access == .granted, scriptedShuffleAllowed, let current = scriptedShuffleEnabled else { return }
        scriptedShufflePending = true
        let id = UUID()
        shuffleSwitchID = id
        scriptingQueue.async { [weak self] in
            let sent = NowPlayingScripting.setShuffle(!current, availability: available)
            DispatchQueue.main.async {
                guard let self, self.shuffleSwitchID == id else { return }
                self.scriptedShufflePending = false
                guard self.automationAvailability?.target == available.target else { return }
                self.scriptedShuffleEnabled = sent ? !current : current
                // A switch that did not go through may mean consent was taken
                // back or the player went away, so look again.
                if !sent {
                    self.refreshAutomation()
                    self.refreshShuffle()
                }
            }
            // Some players answer with the old state for about a second after
            // the switch, so their own answer is asked for a moment later.
            self?.scriptingQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                let state = NowPlayingScripting.shuffle(of: available)
                DispatchQueue.main.async {
                    guard let self, self.shuffleSwitchID == id,
                          self.automationAvailability?.target == available.target, let state else { return }
                    self.scriptedShuffleEnabled = state
                }
            }
        }
    }

    /// The island's music page closed: stop reading the scripted switch.
    func stopShuffleReading() {
        shuffleReading = false
        shuffleGeneration = UUID()
        shuffleSwitchID = UUID()
        scriptedShuffleEnabled = nil
        scriptedShuffleAllowed = true
        scriptedShufflePending = false
    }

    private func requestShuffleAccess(_ available: NowPlayingScripting.Availability) {
        requestingShuffleAccess = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if available.target.isCurrent {
                _ = AppleScriptRunner.consentToAutomate(bundleID: available.target.bundleIdentifier)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingShuffleAccess = false
                guard self.shuffleReading else { return }
                // The playback buttons share this consent, so they look again
                // too, past the answer remembered from before the question.
                NowPlayingScripting.forgetAccess(for: available.target.pid)
                self.refreshAutomation()
                self.refreshShuffle()
            }
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
        // Behind the camera housing, in a full-screen Space without a menu
        // bar, or switched off in the system's menu bar settings, the item is
        // occluded and its text stops scrolling.
        removeStatusItemOcclusionObserver()
        if let window = item.button?.window {
            statusItemOcclusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.renderMenuBar() }
        }
        renderMenuBar()
    }

    private func removeStatusItemOcclusionObserver() {
        if let statusItemOcclusionObserver { NotificationCenter.default.removeObserver(statusItemOcclusionObserver) }
        statusItemOcclusionObserver = nil
    }

    // MARK: - Session

    /// Observed for the life of the app once polling first starts, so the
    /// state is always current; seeded from the system before the first
    /// notification, as the island does.
    private func installSessionObservers() {
        guard sessionObservers.isEmpty else { return }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        func observe(_ center: NotificationCenter, _ name: Notification.Name,
                     _ change: @escaping (inout NotchSessionState) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let couldPresent = self.session.canPresent
                change(&self.session)
                if couldPresent != self.session.canPresent { self.sessionChanged() }
            }
            sessionObservers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.sleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.sleeping = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysSleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysSleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.onConsole = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.onConsole = true }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        // Reduce Motion switched on stops the scroll at once.
        let options = workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.renderMenuBar() }
        sessionObservers.append((workspace, options))
    }

    /// Nobody can see the item or the island: no polls and no marquee until
    /// someone can, then one reading at once.
    private func sessionChanged() {
        guard let timer else { return }
        if session.canPresent {
            timer.fireDate = Date().addingTimeInterval(2)
            lastPollStartedAt = 0
            poll()
        } else {
            timer.fireDate = .distantFuture
        }
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
        let scrolls = NowPlayingMarqueeEngine.scrolls(
            setting: defaults.bool(forKey: DefaultsKey.nowPlayingMarquee),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            itemVisible: button.window.map { $0.occlusionState.contains(.visible) } ?? true,
            sessionActive: session.canPresent)
        let marqueeOffset = updateMarquee(text: text, enabled: scrolls)

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
        guard let elapsed = snapshot.position(at: Date()), let duration = snapshot.duration,
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
            // One pending redraw at a time: polls during a hold would
            // otherwise stack a chain of them.
            marqueeHoldWork?.cancel()
            marqueeHoldWork = nil
            if let delay = result.nextHoldDelay {
                let work = DispatchWorkItem { [weak self] in
                    self?.marqueeHoldWork = nil
                    self?.renderMenuBar()
                }
                marqueeHoldWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        marqueeHoldWork?.cancel()
        marqueeHoldWork = nil
        marqueeEngine.reset()
    }

    // Memoized text measurement.
    //
    // menuBarTextWidth is called up to 3x per composed frame and the marquee
    // drives that at 20 Hz for as long as the title overflows — indefinitely
    // for long track titles. Each call runs a full NSString layout pass. The
    // measured width depends only on the string and the font; neither changes
    // while the marquee scrolls, only the draw offset does. Memoizing removes
    // ~60 layout passes per second at zero behavioural cost. Drop-in: same
    // name, signature and return type, so no call site changes.
    private struct MenuBarTextWidthKey: Hashable {
        let text: String
        let fontName: String
        let fontSize: Double
    }
    private static var menuBarTextWidthCache: [MenuBarTextWidthKey: CGFloat] = [:]

    private static func menuBarTextWidth(_ text: String) -> CGFloat {
        let font = menuBarTextFont
        let key = MenuBarTextWidthKey(text: text,
                                      fontName: font.fontName,
                                      fontSize: Double(font.pointSize))
        if let hit = menuBarTextWidthCache[key] { return hit }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        // Bound the cache: track titles churn over a long listening session and
        // an unbounded dictionary here would be a slow leak.
        if menuBarTextWidthCache.count > 64 {
            menuBarTextWidthCache.removeAll(keepingCapacity: true)
        }
        menuBarTextWidthCache[key] = width
        return width
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
