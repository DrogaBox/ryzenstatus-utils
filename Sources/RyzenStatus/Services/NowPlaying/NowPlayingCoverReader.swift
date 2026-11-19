// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import os
import Security

/// When the cover helper may run. A library that does not load (missing,
/// refused, wrong file) stops covers for the run; anything else, such as a
/// timeout right after wake, rests covers for a while and then tries again.
struct NowPlayingCoverBackoff: Equatable {
    static let failuresBeforeRest = 2
    static let restInterval: TimeInterval = 300

    enum Outcome: Equatable { case success, unavailable, transientFailure }
    enum Change: Equatable { case none, stopped, resting }

    private(set) var stopped = false
    private(set) var failures = 0
    private(set) var restingUntil: TimeInterval = 0

    func allows(at uptime: TimeInterval) -> Bool { !stopped && uptime >= restingUntil }

    /// Records one attempt. The change says when to write the one log line.
    mutating func record(_ outcome: Outcome, at uptime: TimeInterval) -> Change {
        switch outcome {
        case .success:
            failures = 0
            return .none
        case .unavailable:
            guard !stopped else { return .none }
            stopped = true
            return .stopped
        case .transientFailure:
            failures += 1
            guard failures >= Self.failuresBeforeRest else { return .none }
            failures = 0
            restingUntil = uptime + Self.restInterval
            return .resting
        }
    }

    /// "Clear media cache" gives covers another chance after a rest, not
    /// after a library that cannot load.
    mutating func clearRest() {
        failures = 0
        restingUntil = 0
    }
}

/// The cover of the system's Now Playing session on macOS 15.4 and later,
/// where the session reader gets everything but the cover. The cover is only
/// handed to a callback, so a small library in the app bundle
/// (`Contents/Frameworks/NowPlayingCover.dylib`, built from
/// `Sources/NowPlayingCover`) runs inside `/usr/bin/perl`, which the media
/// daemon trusts, and prints it.
///
/// It runs for a new song, never per poll. Failures write one log line and
/// back off (`NowPlayingCoverBackoff`); players then show their app icon.
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

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ryzenstatus",
                                    category: "NowPlayingCover")

    private let libraryURL: URL?
    private let frameworksURL: URL?
    private var backoff = NowPlayingCoverBackoff()
    /// The library's signature is checked once per run.
    private var verifiedLibrary = false

    var gaveUp: Bool { backoff.stopped }

    init(libraryURL: URL? = Bundle.main.privateFrameworksURL?.appendingPathComponent(NowPlayingCoverReader.libraryName),
         frameworksURL: URL? = Bundle.main.privateFrameworksURL) {
        self.libraryURL = libraryURL
        self.frameworksURL = frameworksURL
    }

    /// Whether a read would run now.
    func isReady(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        backoff.allows(at: uptime)
    }

    func clearRest() { backoff.clearRest() }

    /// The session's cover now, or nil when there is none or covers rest.
    func read() -> Cover? {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard backoff.allows(at: uptime) else { return nil }
        guard let libraryURL, FileManager.default.isReadableFile(atPath: libraryURL.path) else {
            note(.unavailable, "\(Self.libraryName) is not in the app bundle", at: uptime)
            return nil
        }
        if !verifiedLibrary {
            guard Self.isInside(libraryURL, frameworks: frameworksURL) else {
                note(.unavailable, "\(Self.libraryName) is not inside the app's Frameworks folder", at: uptime)
                return nil
            }
            guard Self.isSignedLikeThisApp(libraryURL) else {
                note(.unavailable, "\(Self.libraryName) fails its code signature check", at: uptime)
                return nil
            }
            verifiedLibrary = true
        }
        let result = BoundedProcessRunner.run(
            "/usr/bin/perl", ["-e", Self.loader, libraryURL.resolvingSymlinksInPath().path],
            timeout: Self.timeout, maxOutputBytes: Self.maximumOutputBytes,
            // Nothing from the app's environment (PERL5LIB, PERL5OPT) reaches perl.
            environment: NowPlayingSessionReader.childEnvironment)
        if result.status == 0, let cover = Self.parse(result.output) {
            _ = backoff.record(.success, at: uptime)
            return cover
        }
        let detail = String(decoding: result.output.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The loader exits 2 or 3 when the library does not load.
        let outcome: NowPlayingCoverBackoff.Outcome = (result.status == 2 || result.status == 3) ? .unavailable : .transientFailure
        note(outcome, "perl helper \(result.timedOut ? "timed out" : "exited \(result.status)") \(detail)", at: uptime)
        return nil
    }

    private func note(_ outcome: NowPlayingCoverBackoff.Outcome, _ reason: String, at uptime: TimeInterval) {
        switch backoff.record(outcome, at: uptime) {
        case .stopped:
            Self.log.notice("Now Playing covers off for this run: \(reason, privacy: .public)")
        case .resting:
            Self.log.notice("Now Playing covers rest for \(Int(NowPlayingCoverBackoff.restInterval)) s: \(reason, privacy: .public)")
        case .none:
            break
        }
    }

    /// The library is a file directly inside the app's Frameworks folder once
    /// symbolic links are resolved, so perl never loads something else.
    static func isInside(_ library: URL, frameworks: URL?) -> Bool {
        guard let frameworks else { return false }
        let folder = frameworks.resolvingSymlinksInPath().standardizedFileURL.path
        let file = library.resolvingSymlinksInPath().standardizedFileURL.path
        guard file.hasPrefix(folder + "/") else { return false }
        return !file.dropFirst(folder.count + 1).contains("/")
    }

    /// The library's own signature is intact, and when this app is signed by
    /// a team the library is signed by the same team. Ad-hoc builds have no
    /// team to compare, so they get the integrity check only.
    static func isSignedLikeThisApp(_ library: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(library as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
        else { return false }
        guard let appTeam = runningAppTeamIdentifier() else { return true }
        return teamIdentifier(of: staticCode) == appTeam
    }

    private static func runningAppTeamIdentifier() -> String? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return nil }
        var staticMe: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe else { return nil }
        return teamIdentifier(of: staticMe)
    }

    private static func teamIdentifier(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
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

/// One song's cover in the service: what came back, and whether to ask again.
/// A song whose cover is not ready yet (TIDAL can still be downloading it) is
/// asked once more a few seconds later; never more.
struct NowPlayingSessionCover: Equatable {
    static let attempts = 2
    static let retryDelay: TimeInterval = 3

    let key: String
    var data: Data?
    var tries: Int
    var askedAt: TimeInterval

    func shouldAskAgain(at uptime: TimeInterval) -> Bool {
        data == nil && tries < Self.attempts && uptime - askedAt >= Self.retryDelay
    }
}
