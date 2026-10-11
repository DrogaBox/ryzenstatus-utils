// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

/// Pure-Swift native music adapter for the Notch, observing NowPlayingService.shared.
/// Zero Perl scripts, zero external dylibs, zero IPC pipes.
final class NotchMusicService: ObservableObject {
    static let shared = NotchMusicService()

    typealias Command = NotchPlaybackCommand

    @Published private(set) var playback: NotchPlayback?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkTint: NotchArtworkTint?
    @Published private(set) var sources: [NotchPlaybackSource] = []
    @Published private(set) var sourceIsAutomatic = true
    @Published private(set) var selectedSourcePID: Int32?
    @Published private(set) var awaitingPlayback = false
    @Published private(set) var commandFailed = false
    @Published private(set) var commandPending = false

    @Published private(set) var automationAvailability: NotchMusicAutomation.Availability?
    @Published private(set) var requestingAutomation = false

    @Published private(set) var upcoming: NotchQueueSnapshot?
    @Published private(set) var upcomingArtwork: [String: NSImage] = [:]
    var upcomingRows: [NotchQueueItem] { upcoming?.items ?? [] }
    @Published private(set) var upcomingIsHeld = false
    @Published private(set) var queueLoading = false
    @Published private(set) var queueActionPending = false
    @Published private(set) var queueActionFailed = false

    let trackChanges = PassthroughSubject<Void, Never>()
    let trackEnds = PassthroughSubject<Void, Never>()
    let gestureSkips = PassthroughSubject<Bool, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var trackChangeDetector = NotchTrackChange()
    private var isStarted = false

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.notch.isAvailable && defaults.bool(forKey: DefaultsKey.notchEnabled)
        if wanted {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        NowPlayingService.shared.registerConsumer(.notch)

        Publishers.CombineLatest(NowPlayingService.shared.$snapshot, NowPlayingService.shared.$artworkImage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, image in
                self?.handleSnapshotUpdate(snapshot: snapshot, image: image)
            }
            .store(in: &cancellables)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        NowPlayingService.shared.unregisterConsumer(.notch)
        playback = nil
        artwork = nil
        artworkTint = nil
        sources = []
        trackChangeDetector.reset()
    }

    var canSeek: Bool {
        playback?.canSeek == true
    }

    func lacksTrackSkipping(_ command: Command) -> Bool {
        switch command {
        case .next:
            return playback?.canSkipNext != true
        case .previous:
            return playback?.canSkipPrevious != true
        default:
            return false
        }
    }

    func canPerform(_ command: Command) -> Bool {
        switch command {
        case .toggle, .next, .previous, .seek:
            return playback != nil
        default:
            return false
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        send(command, context: nil)
    }

    @discardableResult
    func send(_ command: Command, context: NotchPlaybackContext?) -> Bool {
        switch command {
        case .toggle:
            NowPlayingService.shared.togglePlayPause()
            return true
        case .next:
            NowPlayingService.shared.nextTrack()
            return true
        case .previous:
            NowPlayingService.shared.previousTrack()
            return true
        case .seek(let seconds):
            NowPlayingService.shared.seek(to: seconds)
            return true
        default:
            return false
        }
    }

    func seek(to position: Double, in track: RadialNowPlayingSnapshot, context: NotchPlaybackContext?) {
        NowPlayingService.shared.seek(to: position)
    }

    func skipFromGesture(forward: Bool) {
        if forward {
            NowPlayingService.shared.nextTrack()
        } else {
            NowPlayingService.shared.previousTrack()
        }
        gestureSkips.send(forward)
    }

    func selectSource(_ selection: NotchPlaybackSource.Selection?) {
        if let selection {
            sourceIsAutomatic = false
            selectedSourcePID = selection.pid
        } else {
            sourceIsAutomatic = true
            selectedSourcePID = nil
        }
    }

    func setQueueVisible(_ visible: Bool) {
        // Queue visibility hook
    }

    func refreshQueue() {
        // Native pure-Swift queue refresh
    }

    func playQueued(_ item: NotchQueueItem) {
        // Native pure-Swift queue play
    }

    func refreshAutomation() {
        guard let playback else {
            automationAvailability = nil
            return
        }
        if let target = NotchMusicAutomation.Target(playback) {
            automationAvailability = NotchMusicAutomation.inspect(target)
        } else {
            automationAvailability = nil
        }
    }

    func requestAutomationAccess() {
        guard let playback, let target = NotchMusicAutomation.Target(playback) else { return }
        requestingAutomation = true
        let address = NSAppleEventDescriptor(processIdentifier: target.pid)
        _ = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestingAutomation = false
            self?.refreshAutomation()
        }
    }

    private func handleSnapshotUpdate(snapshot: NowPlayingSnapshot, image: NSImage?) {
        guard snapshot.hasTrack else {
            if playback != nil {
                playback = nil
                artwork = nil
                artworkTint = nil
                automationAvailability = nil
                trackEnds.send()
            }
            return
        }

        var appPID: Int32?
        if let bundleID = snapshot.appBundleID {
            appPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        }

        let radial = RadialNowPlayingSnapshot(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            artworkData: snapshot.artworkData,
            appBundleIdentifier: snapshot.appBundleID,
            appPID: appPID
        )

        let isPlaying = snapshot.isPlaying
        let elapsed = snapshot.elapsed ?? 0
        let duration = snapshot.duration ?? 0

        let newPlayback = NotchPlayback(
            track: radial,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            rate: isPlaying ? 1.0 : 0.0,
            sampledAt: Date(),
            canSeek: duration > 0,
            hasPosition: (snapshot.elapsed ?? 0) >= 0,
            itemIdentifier: nil,
            commandContext: nil,
            canSendCommandsDirectly: true,
            canSkipNext: true,
            canSkipPrevious: true
        )

        let isNewSong = trackChangeDetector.isNewSong(newPlayback, first: playback == nil)
        playback = newPlayback
        artwork = image

        if let image {
            artworkTint = extractArtworkTint(from: image)
        } else {
            artworkTint = nil
        }

        refreshAutomation()

        if isNewSong {
            trackChanges.send()
        }
    }

    private func extractArtworkTint(from image: NSImage) -> NotchArtworkTint? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0

        return NotchArtworkTint.from(red: r, green: g, blue: b)
    }
}
