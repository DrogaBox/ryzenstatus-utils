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
                set tShuffle to false
                try
                    set tShuffle to (shuffle enabled as boolean)
                end try
                set tRepeat to "off"
                try
                    set tRepeat to (song repeat as string)
                end try
                return {tName, tArtist, tAlbum, tPos, tDur, pState, tId as string, tAlbumArtist, tComposer, tGenre, tYear as string, tTrackNumber as string, tShuffle as string, tRepeat}
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
                set tShuffle to false
                try
                    set tShuffle to (shuffling as boolean)
                end try
                set tRepeat to false
                try
                    set tRepeat to (repeating as boolean)
                end try
                return {tName, tArtist, tAlbum, tPos, tDur, pState, tId as string, artUrl, tAlbumArtist, tTrackNumber as string, tShuffle as string, tRepeat as string}
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
        let isShuffleEnabled = parseAppleScriptBoolean(desc.numberOfItems >= 13 ? desc.atIndex(13)?.stringValue : nil) ?? false
        let repeatMode = NowPlayingRepeatMode.musicAppleScriptMode(from: desc.numberOfItems >= 14 ? desc.atIndex(14)?.stringValue ?? "" : "")
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
            trackNumber: (trackNumber ?? 0) > 0 ? trackNumber : nil,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode
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
        let isShuffleEnabled = parseAppleScriptBoolean(desc.numberOfItems >= 11 ? desc.atIndex(11)?.stringValue : nil) ?? false
        // Spotify's dictionary only knows repeat on/off; on maps to "all".
        let repeatMode: NowPlayingRepeatMode = (parseAppleScriptBoolean(desc.numberOfItems >= 12 ? desc.atIndex(12)?.stringValue : nil) ?? false) ? .all : .off
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
            trackNumber: (trackNumber ?? 0) > 0 ? trackNumber : nil,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode
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
        var targetID = bundleID
        if targetID == nil || !isRunning(bundleID: targetID ?? "") {
            if isRunning(bundleID: spotifyBundleID) {
                targetID = spotifyBundleID
            } else if isRunning(bundleID: musicBundleID) {
                targetID = musicBundleID
            }
        }
        guard let finalID = targetID, isRunning(bundleID: finalID) else { return }
        let appName = (finalID == spotifyBundleID) ? "Spotify" : "Music"
        let scriptSource = "tell application \"\(appName)\" to \(command)"
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
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

    // MARK: - Shuffle / repeat
    //
    // Both providers go through AppleScript, the way PlayStatus (MIT) does
    // it: MediaRemote exposes no dependable shuffle/repeat state or toggle,
    // while Music's `shuffle enabled`/`song repeat` and Spotify's
    // `shuffling`/`repeating` are scriptable and report the resulting state.

    /// "true"/"false"/"yes"/"no"/"1"/"0" from an AppleScript result.
    private static func parseAppleScriptBoolean(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    /// Reads the live shuffle/repeat state of a provider session; nil when
    /// the app is not running or automation fails.
    static func fetchPlaybackModes(bundleID: String?) -> (shuffle: Bool, repeatMode: NowPlayingRepeatMode)? {
        guard let bundleID, isRunning(bundleID: bundleID) else { return nil }
        let src: String
        if bundleID == spotifyBundleID {
            src = """
            tell application "Spotify"
                try
                    return {(shuffling as string), (repeating as string)}
                on error
                    return {"__error__"}
                end try
            end tell
            """
        } else {
            src = """
            tell application "Music"
                try
                    return {(shuffle enabled as string), (song repeat as string)}
                on error
                    return {"__error__"}
                end try
            end tell
            """
        }
        guard let script = NSAppleScript(source: src) else { return nil }
        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil, desc.numberOfItems >= 2 else { return nil }
        let shuffle = parseAppleScriptBoolean(desc.atIndex(1)?.stringValue) ?? false
        let repeatMode: NowPlayingRepeatMode
        if bundleID == spotifyBundleID {
            repeatMode = (parseAppleScriptBoolean(desc.atIndex(2)?.stringValue) ?? false) ? .all : .off
        } else {
            repeatMode = NowPlayingRepeatMode.musicAppleScriptMode(from: desc.atIndex(2)?.stringValue ?? "")
        }
        return (shuffle, repeatMode)
    }

    /// Sets shuffle on/off and returns the state the provider reports back;
    /// nil when the app is not running or the command failed.
    @discardableResult
    static func setShuffleEnabled(_ isEnabled: Bool, bundleID: String?) -> Bool? {
        guard let bundleID, isRunning(bundleID: bundleID) else { return nil }
        let targetValue = isEnabled ? "true" : "false"
        let appName = (bundleID == spotifyBundleID) ? "Spotify" : "Music"
        let property = (bundleID == spotifyBundleID) ? "shuffling" : "shuffle enabled"
        let src = """
        tell application "\(appName)"
            if it is running then
                try
                    set \(property) to \(targetValue)
                    return (\(property) as string)
                on error
                    return "__error__"
                end try
            else
                return "__error__"
            end if
        end tell
        """
        guard let script = NSAppleScript(source: src) else { return nil }
        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return parseAppleScriptBoolean(desc.stringValue)
    }

    /// Sets the repeat mode and returns what the provider reports back.
    /// Spotify only understands on/off, so any enabled mode lands on `.all`.
    @discardableResult
    static func setRepeatMode(_ mode: NowPlayingRepeatMode, bundleID: String?) -> NowPlayingRepeatMode? {
        guard let bundleID, isRunning(bundleID: bundleID) else { return nil }
        let appName = (bundleID == spotifyBundleID) ? "Spotify" : "Music"
        let src: String
        if bundleID == spotifyBundleID {
            let targetValue = mode == .off ? "false" : "true"
            src = """
            tell application "\(appName)"
                if it is running then
                    try
                        set repeating to \(targetValue)
                        return (repeating as string)
                    on error
                        return "__error__"
                    end try
                else
                    return "__error__"
                end if
            end tell
            """
        } else {
            src = """
            tell application "\(appName)"
                if it is running then
                    try
                        set song repeat to \(mode.musicAppleScriptLiteral)
                        return (song repeat as string)
                    on error
                        return "__error__"
                    end try
                else
                    return "__error__"
                end if
            end tell
            """
        }
        guard let script = NSAppleScript(source: src) else { return nil }
        var error: NSDictionary?
        let desc = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        if bundleID == spotifyBundleID {
            guard let enabled = parseAppleScriptBoolean(desc.stringValue) else { return nil }
            return enabled ? .all : .off
        }
        return NowPlayingRepeatMode.musicAppleScriptMode(from: desc.stringValue ?? "")
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
