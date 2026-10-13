// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import SwiftUI

// The playback timeline every surface reads: the menu panel and popup read
// `NowPlayingSnapshot` directly, the Dynamic Island reads this richer value
// derived from the same snapshot by `NowPlayingService`. Pure value types,
// so the test harness can exercise the mapping and the song-change rules.

/// The track part of a reading: what is playing and which app plays it.
struct NowPlayingTrack: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?
}

/// A colour taken from the cover art, deepened so it reads as a halo over a
/// black surface. Artwork with no real colour of its own returns nothing,
/// which keeps a grey smudge from appearing behind neutral covers.
struct NowPlayingArtworkTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func from(red: Double, green: Double, blue: Double) -> NowPlayingArtworkTint? {
        let channels = [red, green, blue]
        guard channels.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              let highest = channels.max(), let lowest = channels.min(),
              highest > 0.05 else { return nil }
        let range = highest - lowest
        guard range / highest >= 0.12 else { return nil }
        // Stretch the channels onto a fixed range so every cover glows with the
        // same strength instead of following its own exposure.
        let stretched = channels.map { min(1, max(0, ($0 - lowest) / range * 0.86 + 0.06)) }
        return NowPlayingArtworkTint(red: stretched[0], green: stretched[1], blue: stretched[2])
    }

    /// The cover's average colour, read from a 1×1 downscale.
    static func sample(_ image: NSImage) -> NowPlayingArtworkTint? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return from(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}

/// Identifies one recording on one player. No provider reports it today, so
/// readings carry nil and the same player counts as the same recording.
struct NowPlayingPlaybackContext: Equatable {
    let pid: Int32
    let revision: UUID
}

/// The transport commands a surface can send through `NowPlayingService`.
enum NowPlayingTransportCommand: Equatable {
    case toggle, next, previous
    case seek(Double)

    static func validPosition(_ value: Double) -> Bool {
        value.isFinite && (0...604_800).contains(value)
    }
}

/// One reading on a clock: where the song stood when it was sampled, so a
/// view can move the playhead between polls without asking the player.
struct NowPlayingPlayback: Equatable {
    let track: NowPlayingTrack
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let sampledAt: Date
    let canSeek: Bool
    var hasPosition: Bool = true
    var itemIdentifier: String? = nil
    var commandContext: NowPlayingPlaybackContext? = nil
    /// Every provider takes commands straight from this process.
    var canSendCommandsDirectly = true
    /// Nil when the player's commands could not be read.
    var canSkipNext: Bool? = nil
    var canSkipPrevious: Bool? = nil

    /// The timeline of a snapshot, or nil when nothing is playing.
    static func make(from snapshot: NowPlayingSnapshot, pid: Int32?, sampledAt: Date) -> NowPlayingPlayback? {
        guard snapshot.hasTrack else { return nil }
        let elapsed = snapshot.elapsed ?? 0
        let duration = snapshot.duration ?? 0
        let track = NowPlayingTrack(title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                                    artworkData: snapshot.artworkData, appBundleIdentifier: snapshot.appBundleID,
                                    appPID: pid)
        return NowPlayingPlayback(track: track, isPlaying: snapshot.isPlaying, elapsed: elapsed, duration: duration,
                                  rate: snapshot.isPlaying ? 1 : 0, sampledAt: sampledAt, canSeek: duration > 0,
                                  hasPosition: elapsed >= 0, canSkipNext: true, canSkipPrevious: true)
    }

    /// The same recording from the same player. Readings without a name
    /// share no recording, so only their player tells them apart.
    static func sameRecording(_ first: NowPlayingPlayback?, _ second: NowPlayingPlayback?) -> Bool {
        first?.commandContext == second?.commandContext && first?.track.appPID == second?.track.appPID
    }

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, elapsed + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0)))
    }
}

/// What makes a reading the same song for lyrics and the audio meter.
struct NowPlayingTrackIdentity: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let bundle: String?
    let pid: Int32?
    let itemIdentifier: String?

    init(_ playback: NowPlayingPlayback) {
        title = playback.track.title ?? ""
        artist = playback.track.artist ?? ""
        album = playback.track.album ?? ""
        duration = playback.duration.rounded()
        bundle = playback.track.appBundleIdentifier
        pid = playback.track.appPID
        itemIdentifier = playback.itemIdentifier
    }
}

/// Tells a new song from the updates a playing one keeps sending.
struct NowPlayingTrackChange {
    private struct Song {
        let title: String
        let artist: String?

        func matches(_ other: Song) -> Bool {
            title == other.title && (artist == nil || other.artist == nil || artist == other.artist)
        }
    }

    private var songs: [String: Song] = [:]

    mutating func isNewSong(_ playback: NowPlayingPlayback?, first: Bool) -> Bool {
        guard let playback, let player = Self.player(of: playback), let song = Self.song(of: playback) else { return false }
        guard !first else { songs[player] = song; return false }
        guard playback.isPlaying else { return false }
        guard let previous = songs.updateValue(song, forKey: player) else { return false }
        return !previous.matches(song)
    }

    mutating func reset() { songs = [:] }

    private static func player(of playback: NowPlayingPlayback) -> String? {
        playback.track.appBundleIdentifier ?? playback.track.appPID.map(String.init)
    }

    private static func song(of playback: NowPlayingPlayback) -> Song? {
        cleaned(playback.track.title).map { Song(title: $0, artist: cleaned(playback.track.artist)) }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// One upcoming song in the player's queue.
struct NowPlayingQueueItem: Equatable, Identifiable {
    let id: String
    let offset: Int
    let title: String
    let artist: String
    let duration: Double
}

/// The player's upcoming songs. Only Music shares them, as the rest of the
/// playlist it plays from (its Up Next and Spotify's queue are not
/// scriptable); every other player reports none and the island says so.
struct NowPlayingQueue: Equatable {
    let items: [NowPlayingQueueItem]
    let canPlay: Bool
    /// Shuffle is on, so the playlist order says nothing about what plays next.
    var isShuffled = false
    /// Music plays from outside a library playlist, as an Apple Music
    /// stream does, and keeps that queue to itself.
    var isStreaming = false
}
