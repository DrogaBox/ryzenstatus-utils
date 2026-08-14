// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// A snapshot of whatever is playing right now, gathered from the system's
/// media session. A pure value type so views and tests can hold it freely.
struct NowPlayingSnapshot: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var appName: String?
    var appBundleID: String?
    var artworkData: Data?
    var isPlaying = false
    var elapsed: TimeInterval?
    var duration: TimeInterval?

    /// A title is the minimum requirement for a "now playing" moment; a
    /// paused track still counts, an idle session does not.
    var hasTrack: Bool { !(title ?? "").isEmpty }

    var displayTitle: String { title ?? "" }

    var displayArtist: String {
        let value = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "—" : value
    }

    var artwork: NSImage? {
        guard let artworkData else { return nil }
        return NSImage(data: artworkData)
    }

    /// "3:42" from an elapsed or duration interval; "–" when unknown.
    static func timeLabel(_ interval: TimeInterval?) -> String {
        guard let interval = interval, interval.isFinite, interval >= 0 else { return "–" }
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let empty = NowPlayingSnapshot()

    static func == (lhs: NowPlayingSnapshot, rhs: NowPlayingSnapshot) -> Bool {
        guard lhs.title == rhs.title,
              lhs.artist == rhs.artist,
              lhs.album == rhs.album,
              lhs.appName == rhs.appName,
              lhs.appBundleID == rhs.appBundleID,
              lhs.isPlaying == rhs.isPlaying,
              lhs.elapsed == rhs.elapsed,
              lhs.duration == rhs.duration else { return false }
        
        switch (lhs.artworkData, rhs.artworkData) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (l?, r?):
            return l.count == r.count && l.prefix(64) == r.prefix(64)
        }
    }
}

/// How the menu bar item renders the current track. Mirrors the display
/// modes of a full now-playing app: icon only, artist, song, or both.
enum NowPlayingMenuBarMode: Int, CaseIterable {
    case iconOnly = 0
    case artist = 1
    case song = 2
    case artistSong = 3
}

/// Which app's media session the feature listens to. Auto accepts any app
/// that publishes now-playing info; a pinned provider filters the rest out.
enum NowPlayingProvider: Int, CaseIterable {
    case auto = 0
    case music = 1
    case spotify = 2

    /// Bundle identifiers the pinned providers accept. Auto accepts all.
    func accepts(_ bundleID: String?) -> Bool {
        switch self {
        case .auto: return true
        case .music: return bundleID == "com.apple.Music"
        case .spotify: return bundleID == "com.spotify.client"
        }
    }
}

/// Media transport commands understood by the system media session. Raw
/// values are the stable MRMediaRemoteCommand identifiers (verified against
/// the MediaRemote private framework header):
///   kMRPlay=0, kMRPause=1, kMRTogglePlayPause=2, kMRStop=3,
///   kMRNextTrack=4, kMRPreviousTrack=5, kMRSeekToPlaybackPosition=20.
enum NowPlayingCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    // note: 3 is kMRStop — intentionally omitted to avoid confusion
    case nextTrack = 4
    case previousTrack = 5
    case seekToPlaybackPosition = 20
}

/// The system's media session has no public API. Every symbol resolves once
/// through dlopen/dlsym and the feature degrades gracefully wherever one is
/// missing: no MediaRemote means no now-playing reading, never a crash.
enum MediaRemoteBridge {
    typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    typealias GetNowPlayingClientFn = @convention(c) (DispatchQueue, @escaping (Any?) -> Void) -> Void
    typealias ClientGetBundleIDFn = @convention(c) (Any?) -> Unmanaged<CFString>?
    /// The 2-arg signature for SendCommand is deliberate (header-verified).
    typealias SendCommandFn = @convention(c) (Int, [String: Any]?) -> Void

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

    static let getNowPlayingInfo: GetNowPlayingInfoFn? =
        symbol(handle, "MRMediaRemoteGetNowPlayingInfo")
    static let getNowPlayingClient: GetNowPlayingClientFn? =
        symbol(handle, "MRMediaRemoteGetNowPlayingClient")
    static let clientGetBundleID: ClientGetBundleIDFn? =
        symbol(handle, "MRNowPlayingClientGetBundleIdentifier")
    static let sendCommand: SendCommandFn? =
        symbol(handle, "MRMediaRemoteSendCommand")

    static var isAvailable: Bool { getNowPlayingInfo != nil }

    /// On macOS 15.4+, mediaremoted requires private entitlements
    /// (com.apple.mediaremote.now-playing-read-access) for reading now-playing info,
    /// returning kMRMediaRemoteFrameworkErrorDomain Code=3 ("Operation not permitted").
    /// On these versions, reading must use AppleScript automation instead.
    static var readsBlockedBySystem: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 15 || (v.majorVersion == 15 && v.minorVersion >= 4)
    }

    static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// Keys the system media session stores in its now-playing dictionary.
    private enum InfoKey {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let isPlaying = "kMRMediaRemoteNowPlayingInfoIsPlaying"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    }

    /// Reads the current media session. The completion runs on `queue`, like
    /// every other MediaRemote callback.
    static func fetchNowPlaying(queue: DispatchQueue,
                                completion: @escaping (NowPlayingSnapshot) -> Void) {
        guard let getNowPlayingInfo else {
            completion(.empty)
            return
        }
        getNowPlayingInfo(queue) { info in
            var snapshot = NowPlayingSnapshot()
            if let info = info {
                snapshot.title = info[InfoKey.title] as? String
                snapshot.artist = info[InfoKey.artist] as? String
                snapshot.album = info[InfoKey.album] as? String
                snapshot.artworkData = info[InfoKey.artworkData] as? Data
                snapshot.elapsed = info[InfoKey.elapsedTime] as? TimeInterval
                snapshot.duration = info[InfoKey.duration] as? TimeInterval
                let rate = (info[InfoKey.playbackRate] as? TimeInterval) ?? 0
                snapshot.isPlaying = ((info[InfoKey.isPlaying] as? Bool) ?? false) && rate > 0
            }
            completion(snapshot)
        }
    }

    /// Explicitly triggers the TCC prompt for Apple Events to the target app.
    /// MediaRemote / AppleScript automation requires this permission under the hood.
    static func triggerTCCPrompt(for bundleIdentifier: String) {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
    }

    /// Resolves the bundle identifier of the app that owns the media session,
    /// so the UI can say where the track comes from and filter by provider.
    static func fetchPlayingApp(queue: DispatchQueue,
                                completion: @escaping (String?) -> Void) {
        guard let getNowPlayingClient else {
            completion(nil)
            return
        }
        getNowPlayingClient(queue) { client in
            guard let client, let clientGetBundleID,
                  /// CoreFoundation "Get" rule: we do not own the returned object.
                  let cfID = clientGetBundleID(client)?.takeUnretainedValue() else {
                completion(nil)
                return
            }
            completion(cfID as String)
        }
    }

    /// Sends a transport command (play, pause, next…) to the media session.
    static func send(_ command: NowPlayingCommand) {
        sendCommand?(command.rawValue, nil)
    }

    /// Seeks the current track to the given playback position (seconds).
    static func seek(to seconds: TimeInterval) {
        sendCommand?(NowPlayingCommand.seekToPlaybackPosition.rawValue,
                     ["kMRMediaRemoteOptionSeekToPlaybackPosition": seconds])
    }
}
