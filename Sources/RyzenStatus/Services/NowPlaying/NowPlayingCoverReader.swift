// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import os

/// The cover of the system's Now Playing session on macOS 15.4 and later,
/// where the session reader gets everything but the cover. The cover is only
/// handed to a callback, so a small library in the app bundle
/// (`Contents/Frameworks/NowPlayingCover.dylib`, built from
/// `Sources/NowPlayingCover`) runs inside `/usr/bin/perl`, which the media
/// daemon trusts, and prints it.
///
/// It runs once per song, never per poll. If the library cannot load or
/// answer, one line goes to the log and covers stop for the rest of the run;
/// players then show their app icon, as before.
///
/// Not thread-safe: every call runs on the caller's serial queue.
final class NowPlayingCoverReader {
    struct Cover: Equatable {
        var bundleID: String?
        var title: String?
        var artist: String?
        var album: String?
        var data: Data?
    }

    static let libraryName = "NowPlayingCover.dylib"
    static let timeout: TimeInterval = 4
    static let maximumOutputBytes = 12 * 1_024 * 1_024
    /// Two failed songs in a row stop covers: a helper that cannot answer
    /// would otherwise cost a launch and a wait on every song.
    static let failuresBeforeGivingUp = 2

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ryzenstatus",
                                    category: "NowPlayingCover")

    private let libraryURL: URL?
    private var failures = 0
    private(set) var gaveUp = false

    init(libraryURL: URL? = Bundle.main.privateFrameworksURL?.appendingPathComponent(NowPlayingCoverReader.libraryName)) {
        self.libraryURL = libraryURL
    }

    /// The session's cover now, or nil when there is none or covers stopped.
    func read() -> Cover? {
        guard !gaveUp else { return nil }
        guard let libraryURL, FileManager.default.isReadableFile(atPath: libraryURL.path) else {
            giveUp("Now Playing covers off: \(Self.libraryName) is not in the app bundle")
            return nil
        }
        let result = BoundedProcessRunner.run(
            "/usr/bin/perl", ["-e", Self.loader, libraryURL.path],
            timeout: Self.timeout, maxOutputBytes: Self.maximumOutputBytes,
            // Nothing from the app's environment (PERL5LIB, PERL5OPT) reaches perl.
            environment: ["PATH": "/usr/bin:/bin", "LC_ALL": "C"])
        if result.status == 0, let cover = Self.parse(result.output) {
            failures = 0
            return cover
        }
        failures += 1
        // The loader exits 2 or 3 when the library does not load: no point in
        // asking again.
        if result.status == 2 || result.status == 3 || failures >= Self.failuresBeforeGivingUp {
            let detail = String(decoding: result.output.prefix(300), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            giveUp("Now Playing covers off: perl helper \(result.timedOut ? "timed out" : "exited \(result.status)") \(detail)")
        }
        return nil
    }

    private func giveUp(_ message: String) {
        gaveUp = true
        Self.log.notice("\(message, privacy: .public)")
    }

    /// The helper's JSON line: the last line that is a JSON object. Perl
    /// warnings share the stream and are skipped.
    static func parse(_ output: Data) -> Cover? {
        let lines = output.split(separator: 0x0A)
        guard let line = lines.last(where: { $0.first == UInt8(ascii: "{") }),
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["error"] == nil else { return nil }
        func text(_ key: String) -> String? {
            guard let value = object[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let data = (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return Cover(bundleID: text("bundle"), title: text("title"), artist: text("artist"),
                     album: text("album"), data: data)
    }

    /// The cover belongs to the song on screen: same player and title, so a
    /// cover read at a track change never lands on the next song.
    static func cover(_ cover: Cover, belongsTo snapshot: NowPlayingSnapshot) -> Bool {
        guard let title = cover.title, title == snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if let bundle = cover.bundleID, let owner = snapshot.appBundleID, bundle != owner { return false }
        return true
    }

    /// The song a cover is read for. Play and pause keep it; a new song
    /// changes it.
    static func key(for snapshot: NowPlayingSnapshot) -> String {
        [snapshot.appBundleID, snapshot.title, snapshot.artist, snapshot.album]
            .map { $0 ?? "" }.joined(separator: "\u{1F}")
    }

    /// Loads the library with DynaLoader and runs its one function as a perl
    /// sub. Exit 2: the library did not load. Exit 3: no entry point.
    static let loader = #"""
    use strict; use warnings; use DynaLoader;
    my $library = DynaLoader::dl_load_file($ARGV[0], 0) or do { print "error: ", DynaLoader::dl_error(), "\n"; exit 2 };
    my $entry = DynaLoader::dl_find_symbol($library, "ryzenstatus_now_playing_cover") or do { print "error: no entry point\n"; exit 3 };
    DynaLoader::dl_install_xsub("main::cover", $entry);
    cover();
    """#
}
