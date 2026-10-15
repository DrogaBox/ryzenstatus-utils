// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// The address the internet sees. Unlike the local addresses it needs an
/// outside answer, so it is asked for only after the user turns it on, and
/// the panel names the provider: Cloudflare's trace page, which echoes the
/// caller's address and keeps no account.
final class PublicIPService: ObservableObject {
    static let shared = PublicIPService()
    static let traceURL = URL(string: "https://one.one.one.one/cdn-cgi/trace")!
    /// The address rarely changes; one request per ten minutes is plenty.
    static let maxAge: TimeInterval = 600

    @Published private(set) var address: String?
    @Published private(set) var failed = false
    private var fetchedAt: Date?
    private var task: URLSessionDataTask?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Asks again when the answer is older than `maxAge`, or `force`.
    func refresh(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard task == nil else { return }
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.maxAge { return }
        var request = URLRequest(url: Self.traceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            let address = data.flatMap { Self.address(fromTrace: String(decoding: $0, as: UTF8.self)) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.task = nil
                self.address = address ?? self.address
                self.failed = address == nil
                if address != nil { self.fetchedAt = Date() }
            }
        }
        self.task = task
        task.resume()
    }

    /// Forgets the address when the user turns the lookup off.
    func clear() {
        dispatchPrecondition(condition: .onQueue(.main))
        task?.cancel()
        task = nil
        address = nil
        failed = false
        fetchedAt = nil
    }

    /// The `ip=` line of a trace page, checked to be an IPv4 or IPv6 address.
    static func address(fromTrace text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var v4 = in_addr()
            var v6 = in6_addr()
            if inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1 {
                return value
            }
        }
        return nil
    }
}

/// Round-trip time to a public resolver, measured with the system `ping`
/// every few seconds while the latency block is on screen and the user has
/// turned it on.
final class PingService: ObservableObject {
    static let shared = PingService()
    static let host = "1.1.1.1"
    static let interval: TimeInterval = 5
    static let historyCapacity = 60

    /// Milliseconds of each reply, oldest first; NaN for a lost probe.
    @Published private(set) var history: [Double] = []
    private var timer: Timer?
    private var probing = false
    private var watchers = 0

    var latest: Double? { history.last.flatMap { $0.isFinite ? $0 : nil } }
    var lastLost: Bool { history.last.map(\.isNaN) ?? false }

    /// Starts probing for one more watcher; balanced by `endWatching`.
    func beginWatching() {
        dispatchPrecondition(condition: .onQueue(.main))
        watchers += 1
        guard timer == nil else { return }
        probe()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.probe()
        }
    }

    func endWatching() {
        dispatchPrecondition(condition: .onQueue(.main))
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func probe() {
        guard !probing else { return }
        probing = true
        DispatchQueue.global(qos: .utility).async {
            // One probe, two seconds to answer: a lost reply never blocks the next.
            let result = Shell.run("/sbin/ping", ["-n", "-q", "-c", "1", "-t", "2", Self.host], timeout: 4)
            let milliseconds = Self.roundTrip(fromPingOutput: result.output) ?? .nan
            DispatchQueue.main.async {
                self.probing = false
                guard self.timer != nil else { return }
                self.history.append(milliseconds)
                if self.history.count > Self.historyCapacity {
                    self.history.removeFirst(self.history.count - Self.historyCapacity)
                }
            }
        }
    }

    /// The round trip from `ping -q` output ("round-trip min/avg/max/stddev =
    /// 12.1/12.1/12.1/0.0 ms"), or nil when no reply came back.
    static func roundTrip(fromPingOutput output: String) -> Double? {
        guard let line = output.split(whereSeparator: \.isNewline).first(where: { $0.contains("min/avg/max") }),
              let equals = line.firstIndex(of: "=") else { return nil }
        let figures = line[line.index(after: equals)...]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "/")
        guard figures.count >= 2, let average = Double(figures[1]), average.isFinite, average >= 0 else { return nil }
        return average
    }
}
