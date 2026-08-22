// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus
//
// Lyrics matching and parsing behavior adapted from the MIT-licensed
// PlayStatus project (https://github.com/nbolar/PlayStatus): lrclib.net
// candidate scoring, LRC parsing and plain-text normalization. Rewritten
// for this codebase; no verbatim code copied.

import Foundation

/// One lyric line; timed lines carry their LRC start time in seconds.
struct NowPlayingLyricsLine: Equatable {
    let text: String
    let startTime: TimeInterval?
}

/// A fetched lyrics document plus where it came from (shown as the pane's
/// source caption).
struct NowPlayingLyricsPayload: Equatable {
    let sourceName: String
    let lines: [NowPlayingLyricsLine]
    let isTimed: Bool
}

/// The credits pane derives its rows from the track metadata the session
/// exposes; labels are enums so the view can localize them.
enum NowPlayingCreditsSection: CaseIterable {
    case contributors
    case release
    case catalog
}

enum NowPlayingCreditsLabel {
    case artist
    case albumArtist
    case composer
    case album
    case genre
    case year
    case trackNumber
}

struct NowPlayingCreditsRow: Equatable {
    let label: NowPlayingCreditsLabel
    let value: String
}

struct NowPlayingCreditsPayload: Equatable {
    let sourceName: String
    let sections: [(NowPlayingCreditsSection, [NowPlayingCreditsRow])]

    var hasContent: Bool { sections.contains { !$0.1.isEmpty } }

    static func == (lhs: NowPlayingCreditsPayload, rhs: NowPlayingCreditsPayload) -> Bool {
        guard lhs.sourceName == rhs.sourceName,
              lhs.sections.count == rhs.sections.count else { return false }
        for (index, entry) in lhs.sections.enumerated() {
            let other = rhs.sections[index]
            if entry.0 != other.0 || entry.1 != other.1 { return false }
        }
        return true
    }
}

/// Builds the credits payload the same way PlayStatus derives it: from the
/// provider's own track metadata (artist/composer, album/genre/year, track
/// number), grouped into Contributors / Release / Catalog. Empty fields drop
/// out; an all-empty track yields nil.
enum NowPlayingCreditsBuilder {
    static func build(title: String,
                      artist: String,
                      albumArtist: String?,
                      album: String,
                      composer: String?,
                      genre: String?,
                      year: Int?,
                      trackNumber: Int?,
                      sourceName: String) -> NowPlayingCreditsPayload? {
        func row(_ label: NowPlayingCreditsLabel, _ value: String?) -> NowPlayingCreditsRow? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return NowPlayingCreditsRow(label: label, value: value)
        }

        // The album artist row only earns its place when it differs from
        // the track artist, same as PlayStatus.
        let distinctAlbumArtist: String? = {
            guard let albumArtist,
                  albumArtist.caseInsensitiveCompare(artist) != .orderedSame else { return nil }
            return albumArtist
        }()
        let contributors = [
            row(.artist, title.isEmpty ? nil : artist),
            row(.albumArtist, distinctAlbumArtist),
            row(.composer, composer),
        ].compactMap { $0 }
        let release = [
            row(.album, album),
            row(.genre, genre),
            row(.year, (year ?? 0) > 0 ? String(year ?? 0) : nil),
        ].compactMap { $0 }
        let catalog = [
            row(.trackNumber, (trackNumber ?? 0) > 0 ? String(trackNumber ?? 0) : nil),
        ].compactMap { $0 }

        let sections: [(NowPlayingCreditsSection, [NowPlayingCreditsRow])] = [
            (.contributors, contributors),
            (.release, release),
            (.catalog, catalog),
        ].filter { !$0.1.isEmpty }

        guard !sections.isEmpty else { return nil }
        return NowPlayingCreditsPayload(sourceName: sourceName, sections: sections)
    }
}

/// Parsing and matching helpers for lyrics documents. Pure functions so the
/// test target can exercise them without networking.
enum NowPlayingLyricsText {
    private static let lrcRegex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#)
    private static let offsetRegex = try? NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#, options: [.caseInsensitive])

    /// Plain lyrics into non-empty trimmed lines.
    static func normalizePlain(_ raw: String) -> [NowPlayingLyricsLine] {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { NowPlayingLyricsLine(text: $0, startTime: nil) }
    }

    /// LRC synced lyrics into timed lines; supports multiple stamps per line
    /// and the [offset:±ms] tag. Returns nil when nothing parses.
    static func parseLRC(_ raw: String) -> [NowPlayingLyricsLine]? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let regex = lrcRegex else {
            return nil
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let offsetSeconds: TimeInterval = {
            guard let offsetRegex = offsetRegex,
                  let match = offsetRegex.matches(in: text, range: fullRange).last,
                  let range = Range(match.range(at: 1), in: text),
                  let milliseconds = Double(text[range]) else {
                return 0
            }
            return milliseconds / 1000.0
        }()

        var parsed: [NowPlayingLyricsLine] = []
        for line in text.components(separatedBy: "\n") {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            let lyricText = regex.stringByReplacingMatches(in: line,
                                                           range: NSRange(location: 0, length: ns.length),
                                                           withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fractional = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let fracString = ns.substring(with: match.range(at: 3))
                    if !fracString.isEmpty, let frac = Double(fracString) {
                        fractional = frac / pow(10, Double(fracString.count))
                    }
                }
                let startTime = (minutes * 60) + seconds + fractional + offsetSeconds
                parsed.append(NowPlayingLyricsLine(text: lyricText, startTime: startTime))
            }
        }

        guard !parsed.isEmpty else { return nil }
        return parsed.sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
    }

    /// Lowercases, strips parentheticals/brackets/punctuation and version
    /// tokens ("remix", "edit"…) so candidate matching ignores packaging.
    static func normalizeForMatch(_ text: String) -> String {
        let lower = text.lowercased()
        let cleaned = lower
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dropTokens: Set<String> = [
            "feat", "featuring", "ft", "remix", "mix", "radio", "edit", "extended",
            "version", "original", "deluxe",
        ]
        return cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !dropTokens.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token-overlap similarity in [0, 1]: exact wins, containment is close,
    /// otherwise Jaccard over the token sets.
    static func similarityScore(lhs: String, rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.92 }
        let leftTokens = Set(lhs.split(separator: " ").map(String.init))
        let rightTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let intersection = Double(leftTokens.intersection(rightTokens).count)
        let union = Double(leftTokens.union(rightTokens).count)
        guard union > 0 else { return 0 }
        return intersection / union
    }
}

/// One candidate returned by the lrclib search endpoint.
struct NowPlayingLyricsCandidate {
    let trackName: String
    let artistName: String
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?

    /// Tolerant decoding: lrclib answers camelCase today but the API has
    /// historically used snake_case, so both key styles are accepted.
    static func from(dictionary: [String: Any]) -> NowPlayingLyricsCandidate? {
        func string(_ keys: [String]) -> String {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
            }
            return ""
        }
        func optionalString(_ keys: [String]) -> String? {
            for key in keys {
                if let value = dictionary[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }
        func optionalDouble(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = dictionary[key] as? Double { return value }
                if let value = dictionary[key] as? Int { return Double(value) }
                if let value = dictionary[key] as? String, let parsed = Double(value) { return parsed }
            }
            return nil
        }

        let trackName = string(["trackName", "track_name", "name"])
        let artistName = string(["artistName", "artist_name"])
        guard !trackName.isEmpty, !artistName.isEmpty else { return nil }
        return NowPlayingLyricsCandidate(
            trackName: trackName,
            artistName: artistName,
            duration: optionalDouble(["duration"]),
            syncedLyrics: optionalString(["syncedLyrics", "synced_lyrics"]),
            plainLyrics: optionalString(["plainLyrics", "plain_lyrics"])
        )
    }

    var hasLyrics: Bool {
        let synced = syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let plain = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return synced || plain
    }

    var hasSyncedLyrics: Bool {
        syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// PlayStatus-weighted match score: the title dominates, the artist
    /// confirms, the duration breaks near-ties and synced lyrics earn a
    /// small bonus.
    func matchScore(queryTitle: String, queryArtist: String, queryDuration: Double) -> Double {
        let titleScore = NowPlayingLyricsText.similarityScore(
            lhs: NowPlayingLyricsText.normalizeForMatch(queryTitle),
            rhs: NowPlayingLyricsText.normalizeForMatch(trackName))
        let artistScore = NowPlayingLyricsText.similarityScore(
            lhs: NowPlayingLyricsText.normalizeForMatch(queryArtist),
            rhs: NowPlayingLyricsText.normalizeForMatch(artistName))
        let durationScore: Double
        if queryDuration > 0, let candidateDuration = duration, candidateDuration > 0 {
            let delta = min(abs(candidateDuration - queryDuration), 10)
            durationScore = max(0, 1 - (delta / 10))
        } else {
            durationScore = 0.5
        }
        let syncedBonus = hasSyncedLyrics ? 0.02 : 0.0
        return (titleScore * 0.62) + (artistScore * 0.28) + (durationScore * 0.08) + syncedBonus
    }

    /// Best payload among the candidates; loose matches (score under the
    /// 0.9 threshold PlayStatus uses) are rejected.
    static func bestPayload(from candidates: [NowPlayingLyricsCandidate],
                            queryTitle: String,
                            queryArtist: String,
                            queryDuration: Double) -> NowPlayingLyricsPayload? {
        var best: (candidate: NowPlayingLyricsCandidate, score: Double)?
        for candidate in candidates where candidate.hasLyrics {
            let score = candidate.matchScore(queryTitle: queryTitle,
                                             queryArtist: queryArtist,
                                             queryDuration: queryDuration)
            guard score > 0.9 else { continue }
            if best == nil || score > best!.score {
                best = (candidate, score)
            }
        }
        guard let best else { return nil }
        return payload(from: best.candidate)
    }

    /// Prefers synced (timed) lyrics over plain text.
    static func payload(from candidate: NowPlayingLyricsCandidate) -> NowPlayingLyricsPayload? {
        if let syncedRaw = candidate.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !syncedRaw.isEmpty,
           let timedLines = NowPlayingLyricsText.parseLRC(syncedRaw),
           !timedLines.isEmpty {
            return NowPlayingLyricsPayload(sourceName: "lrclib.net", lines: timedLines, isTimed: true)
        }
        if let plainRaw = candidate.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plainRaw.isEmpty {
            let lines = NowPlayingLyricsText.normalizePlain(plainRaw)
            if !lines.isEmpty {
                return NowPlayingLyricsPayload(sourceName: "lrclib.net", lines: lines, isTimed: false)
            }
        }
        return nil
    }
}

/// Per-track cache identity, mirroring the artwork fingerprint idea: the
/// same performance of the same track always hits the same entry.
enum NowPlayingLyricsCacheKey {
    static func make(title: String, artist: String, album: String, duration: TimeInterval?) -> String {
        let seconds = Int((duration ?? 0).rounded())
        return "\(artist)|\(album)|\(title)|\(seconds)"
    }
}
