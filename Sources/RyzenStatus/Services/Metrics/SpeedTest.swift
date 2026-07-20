// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// A user-triggered internet speed test: latency, then download, then upload,
/// using Cloudflare's public speed endpoints (the same backend speed.cloudflare.com
/// uses). Time-boxed so it stays bounded on any connection. No third-party
/// framework; no user data ever leaves the machine (the upload body is zeros).
///
/// All mutable state is touched only on the session's serial delegate queue;
/// published values are pushed to the main thread.
final class SpeedTest: NSObject, ObservableObject {
    static let shared = SpeedTest()

    enum Phase: Equatable {
        case idle, latency, download, upload, done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latencyMs: Double?
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?

    var isRunning: Bool {
        switch phase { case .latency, .download, .upload: return true; default: return false }
    }

    private enum Kind { case none, download, upload }

    private let host = "https://speed.cloudflare.com"
    private let sampleSeconds: Double = 5
    // Cloudflare's __down caps the size just under 100 MB (100 MB+ returns ~nothing),
    // so request under that and loop chunks back-to-back until the time box — that
    // keeps a fast link's pipe full for a full measurement window.
    private let downloadBytes = 90_000_000
    private let uploadBytes = 100_000_000

    private let queue = OperationQueue()
    private var session: URLSession!
    private var task: URLSessionTask?
    private var kind: Kind = .none           // touched only on `queue`
    private var transferred: Int64 = 0       // touched only on `queue`
    private var startedAt: CFAbsoluteTime = 0
    private var finished = false
    private var stopWork: DispatchWorkItem?

    private override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    func start() {
        guard !isRunning else { return }
        latencyMs = nil; downloadMbps = nil; uploadMbps = nil
        setPhase(.latency)
        queue.addOperation { [weak self] in
            self?.measureLatency(remaining: 5, best: .greatestFiniteMagnitude)
        }
    }

    func cancel() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.stopWork?.cancel(); self.stopWork = nil
            self.task?.cancel(); self.task = nil
            self.kind = .none
            self.finished = true
            self.setPhase(.idle)   // inside the op, so it orders after any pending transition
        }
    }

    private func setPhase(_ phase: Phase) {
        DispatchQueue.main.async { self.phase = phase }
    }

    // MARK: - Latency (completion-handler tasks bypass the byte-counting delegate)

    private func measureLatency(remaining: Int, best: Double) {
        guard remaining > 0 else {
            let value = best == .greatestFiniteMagnitude ? nil : best
            DispatchQueue.main.async { self.latencyMs = value }
            startTransfer(.download)
            return
        }
        let url = URL(string: "\(host)/__down?bytes=0")!
        let started = CFAbsoluteTimeGetCurrent()
        session.dataTask(with: url) { [weak self] _, response, error in
            guard let self else { return }
            let ok = error == nil && response is HTTPURLResponse
            let rtt = (CFAbsoluteTimeGetCurrent() - started) * 1000
            // Continue on the delegate queue so the transfer phase's `kind` is set
            // there too — otherwise the byte-counting delegate could miss it.
            self.queue.addOperation {
                self.measureLatency(remaining: remaining - 1, best: ok ? min(best, rtt) : best)
            }
        }.resume()
    }

    // MARK: - Download / upload (delegate tasks), time-boxed

    private func startTransfer(_ transfer: Kind) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.kind = transfer
            self.transferred = 0
            self.finished = false
            self.setPhase(transfer == .download ? .download : .upload)
            self.startedAt = CFAbsoluteTimeGetCurrent()

            let work = DispatchWorkItem { [weak self] in
                self?.queue.addOperation { self?.finishTransfer(timedOut: true) }
            }
            self.stopWork?.cancel()   // defensive: never leave a previous time box armed
            self.stopWork = work
            DispatchQueue.global().asyncAfter(deadline: .now() + self.sampleSeconds, execute: work)
            self.beginChunk()
        }
    }

    /// Starts one transfer. Download loops these (each capped under Cloudflare's
    /// limit) until the time box; upload is a single body.
    private func beginChunk() {
        guard !finished else { return }
        let task: URLSessionTask
        if kind == .download {
            task = session.dataTask(with: URL(string: "\(host)/__down?bytes=\(downloadBytes)")!)
        } else {
            var request = URLRequest(url: URL(string: "\(host)/__up")!)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            task = session.uploadTask(with: request, from: Data(count: uploadBytes))
        }
        self.task = task
        task.resume()
    }

    private func finishTransfer(timedOut: Bool) {
        guard !finished else { return }
        finished = true
        stopWork?.cancel(); stopWork = nil

        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        let bytes = transferred
        if timedOut { task?.cancel() }
        task = nil
        let finishedKind = kind
        kind = .none

        let mbps = elapsed > 0 ? max(0, Double(bytes) * 8 / elapsed / 1_000_000) : 0
        DispatchQueue.main.async {
            if finishedKind == .download { self.downloadMbps = mbps } else { self.uploadMbps = mbps }
        }

        if finishedKind == .download {
            startTransfer(.upload)
        } else {
            setPhase(.done)
        }
    }
}

extension SpeedTest: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if kind == .download { transferred += Int64(data.count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if kind == .upload { transferred = totalBytesSent }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ignore a stale completion from a task we already moved past (e.g. the
        // download chunk the time box just cancelled, arriving after upload began).
        guard task === self.task, kind != .none else { return }
        if let error = error as NSError?, error.code != NSURLErrorCancelled, transferred == 0 {
            finished = true
            stopWork?.cancel(); stopWork = nil
            self.task = nil
            kind = .none
            setPhase(.failed(error.localizedDescription))
            return
        }
        if kind == .download, !finished {
            beginChunk()   // keep the pipe full until the time box
        } else {
            finishTransfer(timedOut: false)
        }
    }
}
