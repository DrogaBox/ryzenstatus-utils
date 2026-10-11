// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Snapshot of media playback information.
struct RadialNowPlayingSnapshot: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?

    var radialLabel: String? {
        let parts = [title, artist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// A colour taken from the cover art, deepened so it reads as a halo over the
/// notch's black base. Artwork with no real colour of its own returns nothing,
/// which keeps a grey smudge from appearing behind neutral covers.
struct NotchArtworkTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func from(red: Double, green: Double, blue: Double) -> NotchArtworkTint? {
        let channels = [red, green, blue]
        guard channels.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              let highest = channels.max(), let lowest = channels.min(),
              highest > 0.05 else { return nil }
        let range = highest - lowest
        guard range / highest >= 0.12 else { return nil }
        // Stretch the channels onto a fixed range so every cover glows with the
        // same strength instead of following its own exposure.
        let stretched = channels.map { min(1, max(0, ($0 - lowest) / range * 0.86 + 0.06)) }
        return NotchArtworkTint(red: stretched[0], green: stretched[1], blue: stretched[2])
    }
}

struct NotchPlayback: Equatable {
    /// How long a song stays shown after a reading finds nothing playing,
    /// which a player moving on to its next song can report for a moment.
    static let gapGracePeriod: TimeInterval = 1.5

    let track: RadialNowPlayingSnapshot
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let sampledAt: Date
    let canSeek: Bool
    var hasPosition: Bool = true
    var itemIdentifier: String? = nil
    var commandContext: NotchPlaybackContext? = nil
    var canSendCommandsDirectly = false
    /// Nil when the player's commands could not be read.
    var canSkipNext: Bool? = nil
    var canSkipPrevious: Bool? = nil

    /// The same recording from the same player. Readings without a name
    /// share no recording, so only their player tells them apart.
    static func sameRecording(_ first: NotchPlayback?, _ second: NotchPlayback?) -> Bool {
        first?.commandContext == second?.commandContext && first?.track.appPID == second?.track.appPID
    }

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, elapsed + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0)))
    }

    func seekPosition(_ proposed: Double, allowed: Bool? = nil) -> Double? {
        guard allowed ?? canSeek, duration > 0, proposed.isFinite else { return nil }
        return min(duration, max(0, proposed))
    }
}

/// Keeps one decoded cover in memory. Metadata-only updates of the same song
/// retain it; a new song gets a short grace period while its artwork arrives.
struct NotchArtworkCache<Artwork> {
    static var transitionDuration: TimeInterval { 1.5 }
    private struct Identity: Equatable {
        let pid: Int32?
        let bundle: String?
        let item: String?
        let title: String?
        let artist: String?
        let album: String?

        init(_ playback: NotchPlayback) {
            pid = playback.track.appPID
            bundle = playback.track.appBundleIdentifier
            item = playback.itemIdentifier
            title = playback.track.title
            artist = playback.track.artist
            album = playback.track.album
        }
    }

    private var identity: Identity?
    private var artworkData: Data?
    private var inheritedUntil: Date?
    private(set) var artwork: Artwork?
    private(set) var expiresAt: Date?

    mutating func update(_ incoming: Artwork?, for playback: NotchPlayback?, now: Date = Date()) {
        guard let playback else { self = Self(); return }
        let next = Identity(playback)
        if identity?.pid != next.pid || identity?.bundle != next.bundle { self = Self() }
        if identity != next || inheritedUntil.map({ now >= $0 }) == true { inheritedUntil = nil }
        if let incoming {
            if artworkData == nil || playback.track.artworkData != artworkData {
                inheritedUntil = nil
            } else if identity != next {
                inheritedUntil = now.addingTimeInterval(Self.transitionDuration)
            }
            artwork = incoming
            identity = next
            artworkData = playback.track.artworkData
            expiresAt = nil
        } else if identity == next, inheritedUntil == nil {
            expiresAt = nil
        } else if artwork != nil {
            if expiresAt == nil { expiresAt = inheritedUntil ?? now.addingTimeInterval(Self.transitionDuration) }
            expire(at: now)
        }
    }

    mutating func expire(at now: Date = Date()) {
        guard let expiresAt, now >= expiresAt else { return }
        self = Self()
    }
}

/// Tells a new song from the updates a playing one keeps sending.
struct NotchTrackChange {
    private struct Song {
        let title: String
        let artist: String?

        func matches(_ other: Song) -> Bool {
            title == other.title && (artist == nil || other.artist == nil || artist == other.artist)
        }
    }

    private var songs: [String: Song] = [:]

    mutating func isNewSong(_ playback: NotchPlayback?, first: Bool) -> Bool {
        guard let playback, let player = Self.player(of: playback), let song = Self.song(of: playback) else { return false }
        guard !first else { songs[player] = song; return false }
        guard playback.isPlaying else { return false }
        guard let previous = songs.updateValue(song, forKey: player) else { return false }
        return !previous.matches(song)
    }

    static func isBetweenSongs(_ next: NotchPlayback?, after current: NotchPlayback,
                               sources: [NotchPlaybackSource] = []) -> Bool {
        guard let next else { return true }
        guard current.isPlaying, !next.isPlaying else { return false }
        guard let player = Self.player(of: next), player == Self.player(of: current) else {
            return !sources.contains { $0.pid == current.track.appPID && $0.hasTrack }
        }
        guard let song = Self.song(of: next), let played = Self.song(of: current) else { return true }
        return !song.matches(played)
    }

    mutating func reset() { songs = [:] }

    private static func player(of playback: NotchPlayback) -> String? {
        playback.track.appBundleIdentifier ?? playback.track.appPID.map(String.init)
    }

    private static func song(of playback: NotchPlayback) -> Song? {
        cleaned(playback.track.title).map { Song(title: $0, artist: cleaned(playback.track.artist)) }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

enum RadialNowPlayingApplication {
    static func runningApplication(for snapshot: RadialNowPlayingSnapshot) -> NSRunningApplication? {
        if let bundleIdentifier = snapshot.appBundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return application
        }
        if let pid = snapshot.appPID {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
    }

    static func name(for snapshot: RadialNowPlayingSnapshot) -> String? {
        if let name = runningApplication(for: snapshot)?.localizedName, !name.isEmpty { return name }
        guard let identifier = snapshot.appBundleIdentifier else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    static func open(_ snapshot: RadialNowPlayingSnapshot) {
        if let application = runningApplication(for: snapshot) {
            guard application.activationPolicy == .regular else { return }
            if application.isHidden { application.unhide() }
            application.activate(options: [.activateAllWindows])
            if let url = application.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
