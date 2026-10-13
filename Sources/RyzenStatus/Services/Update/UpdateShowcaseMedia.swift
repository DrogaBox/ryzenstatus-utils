// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

enum UpdateShowcaseInfo {
    static let releaseVersion = "1.0.2"
    static let mediaAssetName = "ryzenstatus-1.0.2-showcase-1.mp4"

    static var remoteMediaURL: URL {
        URL(string: "https://github.com/DrogaBox/ryzenstatus-utils/releases/download/v\(releaseVersion)/\(mediaAssetName)")!
    }

    static var localDeveloperMediaURL: URL? {
        guard AppInfo.isDeveloperBuild else { return nil }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseMediaOverride),
           let url = mediaURL(from: raw),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ryzenstatus.utils"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("UpdateShowcase", isDirectory: true)
            .appendingPathComponent(releaseVersion, isDirectory: true)
    }

    static var cachedMediaURL: URL {
        cacheDirectory.appendingPathComponent(mediaAssetName)
    }

    static func cleanupCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private static func mediaURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return nil
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }
}

final class UpdateShowcaseMediaLoader: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(URL)
        case failed
    }

    @Published private(set) var state: State = .idle
    private var session: URLSession?
    private static let maxDownloadBytes: Int64 = 50 * 1024 * 1024

    func load() {
        if case .ready = state { return }
        if case .loading = state { return }

        if let local = UpdateShowcaseInfo.localDeveloperMediaURL {
            state = .ready(local)
            return
        }

        let cached = UpdateShowcaseInfo.cachedMediaURL
        if FileManager.default.fileExists(atPath: cached.path) {
            state = .ready(cached)
            return
        }

        state = .loading
        let request = URLRequest(url: UpdateShowcaseInfo.remoteMediaURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 12)
        // Bounded while it downloads, not checked afterwards: a response can
        // fill the disk on its way to a size check, and a request timeout only
        // limits the gap between packets, which a slow trickle never exceeds.
        let delegate: BoundedUpdateDownloadDelegate
        do {
            delegate = try BoundedUpdateDownloadDelegate(
                byteLimit: Self.maxDownloadBytes,
                progress: { _, _ in },
                completion: { [weak self] tempURL, response, error in
                    guard let self else { return }
                    self.session?.finishTasksAndInvalidate()
                    DispatchQueue.main.async { self.session = nil }
                    let ok = (response as? HTTPURLResponse)
                        .map { (200..<300).contains($0.statusCode) } ?? true
                    let fileSize = tempURL
                        .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64 } ?? 0
                    guard let tempURL, error == nil, ok, fileSize > 0 else {
                        DispatchQueue.main.async { self.state = .failed }
                        return
                    }
                    do {
                        try FileManager.default.createDirectory(at: UpdateShowcaseInfo.cacheDirectory,
                                                                withIntermediateDirectories: true)
                        let target = UpdateShowcaseInfo.cachedMediaURL
                        try? FileManager.default.removeItem(at: target)
                        try FileManager.default.moveItem(at: tempURL, to: target)
                        DispatchQueue.main.async { self.state = .ready(target) }
                    } catch {
                        DispatchQueue.main.async { self.state = .failed }
                    }
                })
        } catch {
            state = .failed
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    func cleanupCache() {
        UpdateShowcaseInfo.cleanupCache()
    }
}
