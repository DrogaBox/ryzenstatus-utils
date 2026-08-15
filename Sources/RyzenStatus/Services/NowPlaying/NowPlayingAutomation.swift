// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import AppKit
import Carbon

/// AppleScript automation fallback for reading Now Playing information on
/// macOS 15.4+, where private MediaRemote entitlements block third-party
/// read calls with error code 3 ("Operation not permitted").
enum NowPlayingAutomation {
    static let musicBundleID = "com.apple.Music"
    static let spotifyBundleID = "com.spotify.client"

    private static let musicTrackScript: NSAppleScript? = {
        let src = """
        tell application "Music"
            set pState to (player state as string)
            if pState is not "stopped" then
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tPos to player position
                set tDur to duration of current track
                set tId to id of current track
                set tAlbumArtist to ""
                try
                    set tAlbumArtist to album artist of current track
                end try
                set tComposer to ""
                try
                    set tComposer to composer of current track
                end try
                set tGenre to ""
                try
                    set tGenre to genre of current track
                end try
                set tYear to 0
                try
                    set tYear to year of current track
                end try
                set tTrackNumber to 0
                try
                    set tTrackNumber to track number of current track
                end try
                return {tName, tArtist, tAlbum, tPos, tDur, pState, tId as string, tAlbumArtist, tComposer, tGenre, tYear as string, tTrackNumber as string}
            else
                return {"stopped"}
            end if
        end tell
        """
        return NSAppleScript(source: src)
    }()

    private static let musicArtworkScript: NSAppleScript? = {
        let src = """
        tell application "Music"
            if (count of artworks of current track) > 0 then
                return raw data of artwork 1 of current track
            end if
        end tell
        """
        return NSAppleScript(source: src)
    }()

    private static let spotifyTrackScript: NSAppleScript? = {
        let src = """
        tell application "Spotify"
            set pState to (player state as string)
            if pState is not "stopped" then
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tPos to player position
                set tDur to (duration of current track) / 1000.0
                set tId to id of current track
                set artUrl to artwork url of current track
                set tAlbumArtist to ""
                try
                    set tAlbumArtist to album artist of current track
                end try
                set tTrackNumber to 0
                try
                    set tTrackNumber to track number of current track
                end try
                return {tName, tArtist, tAlbum, tPos, tDur, pState, tId as string, artUrl, tAlbumArtist, tTrackNumber as string}
            else
                return {"stopped"}
            end if
        end tell
        """
        return NSAppleScript(source: src)
    }()

    // Artwork cache keyed by track ID to avoid fetching artwork on every poll tick.
    private static var lastTrackID: String?
    private static var cachedArtworkData: Data?

    /// Checks if target application is running without launching it.
    static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Fetches Now Playing snapshot via AppleScript automation for the requested provider.
    static func fetchSnapshot(provider: NowPlayingProvider,
                              queue: DispatchQueue,
                              completion: @escaping (NowPlayingSnapshot) -> Void) {
        queue.async {
            switch provider {
            case .music:
                let snap = fetchMusicSnapshot()
                completion(snap)
            case .spotify:
                let snap = fetchSpotifySnapshot()
                completion(snap)
            case .auto:
                let musicRunning = isRunning(bundleID: musicBundleID)
                let spotifyRunning = isRunning(bundleID: spotifyBundleID)

                if musicRunning {
                    let musicSnap = fetchMusicSnapshot()
                    if musicSnap.hasTrack {
                        completion(musicSnap)
                        return
                    }
                }

                if spotifyRunning {
                    let spotifySnap = fetchSpotifySnapshot()
                    if spotifySnap.hasTrack {
                        completion(spotifySnap)
                        return
                    }
                }

                completion(.empty)
            }
        }
    }

    // MARK: - Music AppleScript

    private static func fetchMusicSnapshot() -> NowPlayingSnapshot {
        guard isRunning(bundleID: musicBundleID),
              let script = musicTrackScript else {
            return .empty
        }

        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil, desc.numberOfItems >= 7 else {
            return .empty
        }

        let firstItem = desc.atIndex(1)?.stringValue ?? ""
        if firstItem == "stopped" || firstItem.isEmpty {
            return .empty
        }

        let title = firstItem
        let artist = desc.atIndex(2)?.stringValue
        let album = desc.atIndex(3)?.stringValue
        let position = desc.atIndex(4)?.doubleValue ?? 0.0
        let duration = desc.atIndex(5)?.doubleValue ?? 0.0
        let stateStr = desc.atIndex(6)?.stringValue ?? ""
        let trackID = desc.atIndex(7)?.stringValue ?? ""
        let albumArtist = desc.numberOfItems >= 8 ? desc.atIndex(8)?.stringValue : nil
        let composer = desc.numberOfItems >= 9 ? desc.atIndex(9)?.stringValue : nil
        let genre = desc.numberOfItems >= 10 ? desc.atIndex(10)?.stringValue : nil
        let year = desc.numberOfItems >= 11 ? Int(desc.atIndex(11)?.stringValue ?? "") : nil
        let trackNumber = desc.numberOfItems >= 12 ? Int(desc.atIndex(12)?.stringValue ?? "") : nil
        let isPlaying = (stateStr == "playing")

        var artworkData: Data? = nil
        if !trackID.isEmpty {
            if trackID == lastTrackID {
                artworkData = cachedArtworkData
            } else {
                lastTrackID = trackID
                cachedArtworkData = fetchMusicArtwork()
                artworkData = cachedArtworkData
            }
        }

        return NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            appName: "Music",
            appBundleID: musicBundleID,
            artworkData: artworkData,
            isPlaying: isPlaying,
            elapsed: position > 0 ? position : nil,
            duration: duration > 0 ? duration : nil,
            albumArtist: emptyToNil(albumArtist),
            composer: emptyToNil(composer),
            genre: emptyToNil(genre),
            year: (year ?? 0) > 0 ? year : nil,
            trackNumber: (trackNumber ?? 0) > 0 ? trackNumber : nil
        )
    }

    private static func fetchMusicArtwork() -> Data? {
        guard let script = musicArtworkScript else { return nil }
        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return desc.data
    }

    // MARK: - Spotify AppleScript

    private static func fetchSpotifySnapshot() -> NowPlayingSnapshot {
        guard isRunning(bundleID: spotifyBundleID),
              let script = spotifyTrackScript else {
            return .empty
        }

        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil, desc.numberOfItems >= 7 else {
            return .empty
        }

        let firstItem = desc.atIndex(1)?.stringValue ?? ""
        if firstItem == "stopped" || firstItem.isEmpty {
            return .empty
        }

        let title = firstItem
        let artist = desc.atIndex(2)?.stringValue
        let album = desc.atIndex(3)?.stringValue
        let position = desc.atIndex(4)?.doubleValue ?? 0.0
        let duration = desc.atIndex(5)?.doubleValue ?? 0.0
        let stateStr = desc.atIndex(6)?.stringValue ?? ""
        let trackID = desc.atIndex(7)?.stringValue ?? ""
        let artUrlStr = desc.numberOfItems >= 8 ? desc.atIndex(8)?.stringValue : nil
        let albumArtist = desc.numberOfItems >= 9 ? desc.atIndex(9)?.stringValue : nil
        let trackNumber = desc.numberOfItems >= 10 ? Int(desc.atIndex(10)?.stringValue ?? "") : nil
        let isPlaying = (stateStr == "playing")

        var artworkData: Data? = nil
        if !trackID.isEmpty {
            if trackID == lastTrackID {
                artworkData = cachedArtworkData
            } else {
                lastTrackID = trackID
                if let artUrlStr = artUrlStr, let url = URL(string: artUrlStr),
                   let data = try? Data(contentsOf: url) {
                    cachedArtworkData = data
                    artworkData = data
                } else {
                    cachedArtworkData = nil
                    artworkData = nil
                }
            }
        }

        return NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            appName: "Spotify",
            appBundleID: spotifyBundleID,
            artworkData: artworkData,
            isPlaying: isPlaying,
            elapsed: position > 0 ? position : nil,
            duration: duration > 0 ? duration : nil,
            albumArtist: emptyToNil(albumArtist),
            composer: nil,
            genre: nil,
            year: nil,
            trackNumber: (trackNumber ?? 0) > 0 ? trackNumber : nil
        )
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Lyrics and search

    /// The Music app keeps lyrics on the track itself; the details pane uses
    /// them as the local fallback when lrclib has nothing (PlayStatus does
    /// the same). Returns nil when there are none or automation fails.
    static func fetchMusicLyrics() -> String? {
        guard isRunning(bundleID: musicBundleID) else { return nil }
        let src = """
        tell application "Music"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    try
                        set lyricsText to lyrics of current track
                        if lyricsText is missing value then
                            return ""
                        end if
                        return lyricsText
                    on error
                        return ""
                    end if
                end if
            end if
            return ""
        end tell
        """
        guard let script = NSAppleScript(source: src) else { return nil }
        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let raw = desc.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// Searches the Music library and plays the results, PlayStatus-style.
    /// Runs off the main thread: AppleScript blocks until the app answers.
    static func searchMusicLibrary(query: String) {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = """
        tell application "Music"
            if it is not running then
                activate
                delay 1
            end if
            set search_results to (search library playlist 1 for "\(escaped)")
            if (count of search_results) > 0 then
                try
                    play search_results
                on error
                    play item 1 of search_results
                end try
            end if
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = NSAppleScript(source: src) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }

    // MARK: - Transport Fallback

    static func sendTransportCommand(_ command: String, bundleID: String?) {
        guard let bundleID = bundleID, isRunning(bundleID: bundleID) else { return }
        let appName = (bundleID == spotifyBundleID) ? "Spotify" : "Music"
        let scriptSource = "tell application \"\(appName)\" to \(command)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }

    static func togglePlayPause(bundleID: String?) {
        sendTransportCommand("playpause", bundleID: bundleID)
    }

    static func nextTrack(bundleID: String?) {
        sendTransportCommand("next track", bundleID: bundleID)
    }

    static func previousTrack(bundleID: String?) {
        sendTransportCommand("previous track", bundleID: bundleID)
    }

    static func seek(to seconds: TimeInterval, bundleID: String?) {
        sendTransportCommand("set player position to \(seconds)", bundleID: bundleID)
    }

    // MARK: - Permission Check

    /// Optional helper to check TCC automation permission state without prompting.
    static func automationPermissionState(for bundleID: String) -> OSStatus {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return OSStatus(procNotFound)
        }
        var targetDesc = AEAddressDesc()
        let appPath = url.path
        let urlDesc = (appPath as NSString).fileSystemRepresentation
        let status = AECreateDesc(
            DescType(typeApplicationURL),
            urlDesc,
            strlen(urlDesc),
            &targetDesc
        )
        guard status == noErr else { return OSStatus(status) }
        defer { AEDisposeDesc(&targetDesc) }

        return AEDeterminePermissionToAutomateTarget(
            &targetDesc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEOpenApplication),
            false
        )
    }
}
