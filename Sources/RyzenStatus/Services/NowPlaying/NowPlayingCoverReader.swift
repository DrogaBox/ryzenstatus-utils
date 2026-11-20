// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import os
import Security

/// When the cover helper may run. A library that does not load (missing,
/// refused, wrong file) stops covers for the run; so does a perl that will
/// not start, until "Clear media cache". Anything else, such as a timeout
/// right after wake, rests covers for a while and then tries again.
struct NowPlayingCoverBackoff: Equatable {
    static let failuresBeforeRest = 2
    static let restInterval: TimeInterval = 300

    /// `notStarting`: perl failed to start twice in a row.
    enum Outcome: Equatable { case success, unavailable, notStarting, transientFailure }
    enum Change: Equatable { case none, stopped, resting }

    private(set) var stopped = false
    /// Covers stopped because perl would not start, which "Clear media cache"
    /// may try again; a library that cannot load stays off.
    private(set) var stoppedByLaunch = false
    private(set) var failures = 0
    private(set) var restingUntil: TimeInterval = 0

    func allows(at uptime: TimeInterval) -> Bool { !stopped && uptime >= restingUntil }

    /// Records one attempt. The change says when to write the one log line.
    mutating func record(_ outcome: Outcome, at uptime: TimeInterval) -> Change {
        switch outcome {
        case .success:
            failures = 0
            return .none
        case .unavailable, .notStarting:
            guard !stopped else { return .none }
            stopped = true
            stoppedByLaunch = outcome == .notStarting
            return .stopped
        case .transientFailure:
            failures += 1
            guard failures >= Self.failuresBeforeRest else { return .none }
            failures = 0
            restingUntil = uptime + Self.restInterval
            return .resting
        }
    }

    /// "Clear media cache" gives covers another chance after a rest or a
    /// perl that would not start, not after a library that cannot load.
    mutating func clearRest() {
        failures = 0
        restingUntil = 0
        if stoppedByLaunch {
            stopped = false
            stoppedByLaunch = false
        }
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
/// back off (`NowPlayingCoverBackoff`); a library that does not load ends
/// covers for the run, and a perl that fails to start twice in a row ends
/// them until "Clear media cache". Players then show their app icon.
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
    /// The file whose signature was last found good. A file that changed
    /// since (other inode, size or modification time) is checked again.
    private var verifiedLibrary: FileIdentity?
    /// The last helper run could not start (status -1, no output, no
    /// timeout). One such run may pass; two in a row end covers for the run.
    private var lastRunDidNotStart = false

    struct FileIdentity: Equatable {
        var device: Int64
        var inode: UInt64
        var size: Int64
        var modifiedSeconds: Int
        var modifiedNanoseconds: Int

        init?(path: String) {
            var info = stat()
            guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
            device = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            modifiedSeconds = Int(info.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int(info.st_mtimespec.tv_nsec)
        }
    }

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

    /// The uptime from which a read may run again: infinity once covers are
    /// off for the run.
    var readyAt: TimeInterval { backoff.stopped ? .infinity : backoff.restingUntil }

    /// "Clear media cache": covers that rest, or that perl could not start,
    /// try again, with a failed start forgotten.
    func clearRest() {
        backoff.clearRest()
        lastRunDidNotStart = false
    }

    /// The session's cover now, or nil when there is none or covers rest.
    func read() -> Cover? {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard backoff.allows(at: uptime) else { return nil }
        guard let libraryURL, FileManager.default.isReadableFile(atPath: libraryURL.path) else {
            note(.unavailable, "\(Self.libraryName) is not in the app bundle", at: uptime)
            return nil
        }
        // One resolved path is checked and given to perl.
        let library = libraryURL.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isInside(library, frameworks: frameworksURL) else {
            note(.unavailable, "\(Self.libraryName) is not inside the app's Frameworks folder", at: uptime)
            return nil
        }
        guard let identity = FileIdentity(path: library.path) else {
            note(.unavailable, "\(Self.libraryName) is not a regular file", at: uptime)
            return nil
        }
        if identity != verifiedLibrary {
            guard Self.isSignedLikeThisApp(library) else {
                verifiedLibrary = nil
                note(.unavailable, "\(Self.libraryName) fails its code signature check", at: uptime)
                return nil
            }
            verifiedLibrary = identity
        }
        // A Mac without a perl it may start gets no covers, like a missing
        // library, instead of failing and resting once per song.
        guard FileManager.default.isExecutableFile(atPath: Self.perlPath) else {
            note(.unavailable, "\(Self.perlPath) is not there or cannot be run", at: uptime)
            return nil
        }
        let result = BoundedProcessRunner.run(
            Self.perlPath, ["-e", Self.loader, library.path],
            timeout: Self.timeout, maxOutputBytes: Self.maximumOutputBytes,
            // Nothing from the app's environment (PERL5LIB, PERL5OPT) reaches perl.
            environment: NowPlayingSessionReader.childEnvironment)
        let cover = result.status == 0 ? Self.parse(result.output) : nil
        record(status: result.status, timedOut: result.timedOut, output: result.output, gotCover: cover != nil,
               at: uptime)
        return cover
    }

    /// Books one helper run: a cover clears the failures, anything else backs
    /// off as `outcome` says, and whether perl started is kept for the next
    /// run, which a success or any run that started forgets.
    func record(status: Int32, timedOut: Bool, output: Data, gotCover: Bool, at uptime: TimeInterval) {
        let didNotStart = Self.didNotStart(status: status, timedOut: timedOut, output: output)
        defer { lastRunDidNotStart = didNotStart }
        if gotCover {
            _ = backoff.record(.success, at: uptime)
            return
        }
        let detail = String(decoding: output.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = Self.outcome(status: status, timedOut: timedOut, output: output,
                                   didNotStartBefore: lastRunDidNotStart)
        let what = timedOut ? "timed out" : (status == -1 ? "could not start" : "exited \(status)")
        note(outcome, "perl helper \(what) \(detail)", at: uptime)
    }

    static let perlPath = "/usr/bin/perl"

    /// A run that never started: `BoundedProcessRunner` gives status -1 with
    /// no output and no timeout when `Process.run()` throws.
    static func didNotStart(status: Int32, timedOut: Bool, output: Data) -> Bool {
        status == -1 && !timedOut && output.isEmpty
    }

    /// What a failed helper run means. The loader exits 2 or 3 when the
    /// library does not load. A perl that could not be started may be a
    /// passing problem (no free descriptors, memory), so one such run only
    /// counts as a failure; a second one in a row means it will not start,
    /// and covers end until "Clear media cache". Anything else may pass, such
    /// as a timeout right after wake.
    static func outcome(status: Int32, timedOut: Bool, output: Data,
                        didNotStartBefore: Bool = false) -> NowPlayingCoverBackoff.Outcome {
        if status == 2 || status == 3 { return .unavailable }
        if didNotStart(status: status, timedOut: timedOut, output: output) {
            return didNotStartBefore ? .notStarting : .transientFailure
        }
        return .transientFailure
    }

    private func note(_ outcome: NowPlayingCoverBackoff.Outcome, _ reason: String, at uptime: TimeInterval) {
        switch backoff.record(outcome, at: uptime) {
        case .stopped where outcome == .notStarting:
            Self.log.notice("Now Playing covers off until the media cache is cleared: \(reason, privacy: .public)")
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

    /// The library's own signature is intact in every architecture, and when
    /// this app is signed by a team the library is signed by the same team.
    /// Every slice counts: perl runs natively (arm64 on Apple silicon) while
    /// the app may run under Rosetta, and without the flag only the slice of
    /// the app's own architecture is checked. Ad-hoc builds have no team to
    /// compare, so they get the integrity check only.
    static func isSignedLikeThisApp(_ library: URL) -> Bool {
        var staticCode: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCreateWithPath(library as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess
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
    /// cover read at a track change never lands on the next song. A cover
    /// that names its player is refused for a reading that names none, since
    /// nothing says it is the same player.
    static func cover(_ cover: Cover, belongsTo snapshot: NowPlayingSnapshot) -> Bool {
        guard let title = cover.title, title == snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if let bundle = cover.bundleID, bundle != snapshot.appBundleID { return false }
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
/// asked once more a few seconds later; never more. Only a read that ran
/// counts as a try: a request made while covers rest costs the song nothing,
/// and a later poll asks again once the rest is over.
struct NowPlayingSessionCover: Equatable {
    static let attempts = 2
    static let retryDelay: TimeInterval = 3

    let key: String
    var data: Data?
    /// Reads that ran for this song.
    var tries = 0
    /// When the last read ran (or the song was first seen, before any).
    var askedAt: TimeInterval
    /// A request is waiting on the cover queue; no second one is sent.
    var pending = false

    /// Whether a poll should send a request for this song now.
    func shouldAsk(at uptime: TimeInterval) -> Bool {
        guard data == nil, !pending, tries < Self.attempts else { return false }
        return tries == 0 || uptime - askedAt >= Self.retryDelay
    }

    /// A read ran at `uptime`; `data` is what it brought back.
    mutating func recordRead(at uptime: TimeInterval, data: Data?) {
        pending = false
        tries += 1
        askedAt = uptime
        if let data { self.data = data }
    }

    /// The request did not read: covers rest (asked again later) or are off
    /// for the run (never asked again).
    mutating func recordSkip(coversOff: Bool) {
        pending = false
        if coversOff { tries = Self.attempts }
    }
}
