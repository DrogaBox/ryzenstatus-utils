// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation
import os

/// One reading of the system media session, as the session reader sends it.
struct NowPlayingSessionReading: Equatable {
    var sequence: Int
    var snapshot: NowPlayingSnapshot
    var pid: Int32?
    /// The script answered that it cannot reach the session (MediaRemote or
    /// its request class did not load). The reader counts it as a failure.
    var unavailable = false

    /// Players that send no "is playing" key (TIDAL) are playing while their
    /// rate is above zero. A player that sends the key but no rate keeps the
    /// key's answer.
    static func isPlaying(flag: Bool?, rate: Double?) -> Bool {
        guard let flag else { return (rate ?? 0) > 0 }
        return flag && (rate.map { $0 > 0 } ?? true)
    }

    /// The session keeps the elapsed time of the last state change and when it
    /// was taken; a player such as TIDAL only republishes on play, pause and a
    /// new song. The playhead at `now` moves on from there at the rate.
    static func elapsed(_ elapsed: Double?, at timestamp: Date?, rate: Double, isPlaying: Bool,
                        duration: Double?, now: Date) -> Double? {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return nil }
        var position = elapsed
        if isPlaying, let timestamp, rate.isFinite, rate > 0 {
            position += max(0, now.timeIntervalSince(timestamp)) * rate
        }
        if let duration, duration.isFinite, duration > 0 { position = min(position, duration) }
        return position
    }

    /// Parses one line of the reader's output; nil for anything malformed.
    static func parse(line: Data, now: Date = Date()) -> NowPlayingSessionReading? {
        guard line.count <= 64 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let sequence = (object["seq"] as? NSNumber)?.intValue else { return nil }
        if object["error"] is String {
            return NowPlayingSessionReading(sequence: sequence, snapshot: NowPlayingSnapshot(), pid: nil, unavailable: true)
        }
        func text(_ key: String, limit: Int = 1_024) -> String? {
            guard let value = object[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(limit))
        }
        func number(_ key: String) -> Double? {
            guard let value = (object[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        var snapshot = NowPlayingSnapshot()
        snapshot.title = text("title")
        snapshot.artist = text("artist")
        snapshot.album = text("album")
        snapshot.appBundleID = text("bundle", limit: 256)
        let flag = (object["playing"] as? NSNumber).map { $0.boolValue }
        let rate = number("rate")
        snapshot.isPlaying = isPlaying(flag: flag, rate: rate)
        let duration = number("duration").flatMap { $0 > 0 ? $0 : nil }
        snapshot.duration = duration
        snapshot.elapsed = elapsed(number("elapsed"),
                                   at: number("timestamp").map(Date.init(timeIntervalSince1970:)),
                                   rate: rate ?? (snapshot.isPlaying ? 1 : 0),
                                   isPlaying: snapshot.isPlaying, duration: duration, now: now)
        snapshot.sampledAt = now
        let pid = (object["pid"] as? NSNumber)?.int32Value
        return NowPlayingSessionReading(sequence: sequence, snapshot: snapshot,
                                        pid: pid.flatMap { $0 > 0 ? $0 : nil })
    }
}

/// When the session reader may try. Three failed readings in a row rest it
/// for a minute, during which Now Playing falls back to the scripted players.
struct NowPlayingReaderHealth: Equatable {
    static let failuresBeforeRest = 3
    static let restInterval: TimeInterval = 60

    private(set) var failures = 0
    private(set) var restingUntil: TimeInterval = 0

    func allows(at uptime: TimeInterval) -> Bool { uptime >= restingUntil }

    mutating func recordSuccess() { failures = 0 }

    mutating func recordFailure(at uptime: TimeInterval) {
        failures += 1
        guard failures >= Self.failuresBeforeRest else { return }
        failures = 0
        restingUntil = uptime + Self.restInterval
    }
}

/// The newest polling run that ended, readable from any thread. The run is
/// retired the moment it stops, so work already queued for it sees that
/// before it starts a reader.
final class NowPlayingRetiredRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var newest = Int.min

    func retire(_ generation: Int) {
        lock.lock()
        newest = max(newest, generation)
        lock.unlock()
    }

    func isRetired(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation <= newest
    }
}

/// Reads the system media session on macOS 15.4 and later, where the media
/// daemon answers only processes it trusts and returns nothing to this app.
/// Apple's own `osascript` is one of them: a small JavaScript for Automation
/// script stays open while the feature polls and answers one reading per
/// request line, so a poll costs a pipe round trip, not a launch.
///
/// The session has no cover through this route (the cover is only sent to a
/// callback, which a script cannot pass), so players read here show their app
/// icon in place of a cover.
///
/// Not thread-safe: every call runs on the caller's serial queue, except
/// `terminateNow`.
final class NowPlayingSessionReader {
    /// A long-lived script keeps a little memory per reading; a fresh process
    /// after this many readings (about ten minutes at one every two seconds)
    /// keeps it near its starting size.
    static let readingsPerProcess = 300
    static let replyTimeout: TimeInterval = 1.0
    /// A fresh `osascript` loads JavaScriptCore and MediaRemote before its
    /// first answer (about 90 ms here, more under load or right after wake).
    static let firstReplyTimeout: TimeInterval = 3.0
    /// Nothing from the app's environment reaches the helpers.
    static let childEnvironment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]

    private var process: Process?
    private var requests: FileHandle?
    private var replies: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var served = 0
    private var health = NowPlayingReaderHealth()
    private var loggedUnavailable = false
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ryzenstatus",
                                    category: "NowPlayingSession")
    /// The running script, for `terminateNow` from another thread.
    private let liveLock = NSLock()
    private var live: Process?

    deinit { stop() }

    /// The current session, or nil when it cannot be read right now.
    func read(now: @autoclosure () -> Date = Date()) -> NowPlayingSessionReading? {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard health.allows(at: uptime) else { return nil }
        if served >= Self.readingsPerProcess { stop() }
        guard process != nil || launch() else {
            health.recordFailure(at: uptime)
            return nil
        }
        sequence &+= 1
        let timeout = served == 0 ? Self.firstReplyTimeout : Self.replyTimeout
        guard send("\(sequence)\n"), let reading = receive(sequence, timeout: timeout, now: now()) else {
            stop()
            health.recordFailure(at: ProcessInfo.processInfo.systemUptime)
            return nil
        }
        if reading.unavailable {
            // The route is gone (a later macOS may refuse the script too): no
            // script stays open for it, it rests like any failure, and the
            // first time is logged.
            stop()
            health.recordFailure(at: ProcessInfo.processInfo.systemUptime)
            if !loggedUnavailable {
                loggedUnavailable = true
                Self.log.notice("Now Playing session reader: MediaRemote is not available to osascript; using AppleScript players")
            }
            return nil
        }
        served += 1
        health.recordSuccess()
        return reading
    }

    /// Sends the running script SIGTERM at once, from any thread, without
    /// waiting for a read in progress on the caller's queue. That read then
    /// fails, and `stop` cleans up as usual.
    func terminateNow() {
        liveLock.lock()
        let running = live
        liveLock.unlock()
        if let running, running.isRunning { running.terminate() }
    }

    /// Ends the script. A script that does not leave on SIGTERM (stuck in a
    /// media daemon call) is killed half a second later.
    func stop() {
        if let process, process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        try? requests?.close()
        try? replies?.close()
        setLive(nil)
        process = nil
        requests = nil
        replies = nil
        buffer.removeAll()
        served = 0
    }

    private func launch() -> Bool {
        let input = Pipe()
        let output = Pipe()
        // A reader that died must not take this app down with SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return false }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        child.arguments = ["-l", "JavaScript", "-e", Self.script]
        child.environment = Self.childEnvironment
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return false }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        process = child
        setLive(child)
        requests = input.fileHandleForWriting
        replies = output.fileHandleForReading
        buffer.removeAll()
        served = 0
        return true
    }

    private func setLive(_ child: Process?) {
        liveLock.lock()
        live = child
        liveLock.unlock()
    }

    private func send(_ line: String) -> Bool {
        guard let requests else { return false }
        let bytes = Array(line.utf8)
        return bytes.withUnsafeBytes { raw in
            while true {
                let written = Darwin.write(requests.fileDescriptor, raw.baseAddress, raw.count)
                if written < 0, errno == EINTR { continue }
                return written == raw.count
            }
        }
    }

    /// Waits for the reply to `expected`, dropping late replies to requests
    /// that already timed out.
    private func receive(_ expected: Int, timeout: TimeInterval, now: Date) -> NowPlayingSessionReading? {
        guard let replies else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var chunk = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            if let reading = Self.takeReply(to: expected, from: &buffer, now: now) { return reading }
            guard buffer.count <= 256 * 1_024 else { return nil }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: replies.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, Int32(max(1, remaining * 1_000)))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { return nil }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(replies.fileDescriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    /// Takes complete lines off the front of `buffer` until the reply to
    /// `expected` is found. Replies to older requests and malformed lines are
    /// dropped; a partial last line stays for the next read.
    static func takeReply(to expected: Int, from buffer: inout Data, now: Date) -> NowPlayingSessionReading? {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let reading = NowPlayingSessionReading.parse(line: Data(line), now: now),
               reading.sequence == expected {
                return reading
            }
        }
        return nil
    }

    /// Answers each request line with the session as one JSON line carrying
    /// the request's number. Readings run from the run loop, so the objects of
    /// each one are released with it. End of input ends the script, so a
    /// reader whose app quit or crashed does not stay behind.
    ///
    /// A request class that did not load answers with an error. JXA hands a
    /// nil class back as an object whose `isNil()` is true (checked with
    /// `osascript` on macOS 26); anything else that is not a usable class
    /// (undefined, or a value that throws) counts as unavailable too.
    static let script = #"""
    ObjC.import("Foundation");
    ObjC.import("stdlib");
    $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
    const requests = $.NSClassFromString("MRNowPlayingRequest");
    const input = $.NSFileHandle.fileHandleWithStandardInput;
    const output = $.NSFileHandle.fileHandleWithStandardOutput;
    const present = (v) => v !== undefined && v !== null && !v.isNil();
    const text = (v) => present(v) && v.isKindOfClass($.NSString) ? ObjC.unwrap(v) : null;
    const number = (v) => present(v) && v.isKindOfClass($.NSNumber) ? v.doubleValue : null;
    function reading(sequence) {
        try {
            return session(sequence);
        } catch (error) {
            return { seq: sequence };
        }
    }
    function session(sequence) {
        const out = { seq: sequence };
        let available = false;
        try { available = !!requests && !requests.isNil(); } catch (error) { available = false; }
        if (!available) return { seq: sequence, error: "MediaRemote unavailable" };
        out.playing = requests.localIsPlaying;
        const path = requests.localNowPlayingPlayerPath;
        if (!path.isNil() && !path.client.isNil()) {
            out.bundle = text(path.client.bundleIdentifier);
            out.pid = path.client.processIdentifier;
        }
        const item = requests.localNowPlayingItem;
        const info = item.isNil() ? item : item.nowPlayingInfo;
        if (!info.isNil()) {
            const key = (name) => info.objectForKey("kMRMediaRemoteNowPlayingInfo" + name);
            out.title = text(key("Title"));
            out.artist = text(key("Artist"));
            out.album = text(key("Album"));
            out.elapsed = number(key("ElapsedTime"));
            out.duration = number(key("Duration"));
            out.rate = number(key("PlaybackRate"));
            const stamp = key("Timestamp");
            if (present(stamp) && stamp.isKindOfClass($.NSDate)) out.timestamp = stamp.timeIntervalSince1970;
        }
        return out;
    }
    ObjC.registerSubclass({
        name: "RyzenStatusNowPlayingReader",
        methods: {
            "answer:": {
                types: ["void", ["id"]],
                implementation: function (note) {
                    const data = note.userInfo.objectForKey("NSFileHandleNotificationDataItem");
                    const received = data.isNil() ? "" : ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
                    if (!received) $.exit(0);
                    const lines = received.trim().split("\n");
                    let line;
                    try {
                        line = JSON.stringify(reading(parseInt(lines[lines.length - 1], 10) || 0)) + "\n";
                    } catch (error) {
                        line = "{}\n";
                    }
                    output.writeData($(line).dataUsingEncoding($.NSUTF8StringEncoding));
                    input.readInBackgroundAndNotify;
                }
            }
        }
    });
    $.NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(
        $.RyzenStatusNowPlayingReader.alloc.init, "answer:", "NSFileHandleReadCompletionNotification", input);
    input.readInBackgroundAndNotify;
    $.NSRunLoop.currentRunLoop.run;
    """#
}
