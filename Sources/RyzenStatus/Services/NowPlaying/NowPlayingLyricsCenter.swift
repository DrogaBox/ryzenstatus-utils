// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// The lifecycle of a lyrics lookup as shown in the details pane.
enum NowPlayingLyricsPaneState: Equatable {
    case idle
    case loading
    case available
    case unavailable
    case failed
}

/// Orchestrates lyrics lookups for the popup's details pane, mirroring
/// PlayStatus's pipeline: lrclib.net exact match first (keyless public API),
/// then its search endpoint with candidate scoring, then the Music app's own
/// embedded lyrics via AppleScript. Results are cached per track fingerprint
/// and in-flight requests are cancelled on track change.
final class NowPlayingLyricsCenter: ObservableObject {
    static let shared = NowPlayingLyricsCenter()

    @Published private(set) var paneState: NowPlayingLyricsPaneState = .idle
    @Published private(set) var payload: NowPlayingLyricsPayload?

    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.now-playing-lyrics", qos: .utility)
    private let maxCacheEntries = 64
    private let requestTimeout: TimeInterval = 12

    private enum CacheEntry {
        case available(NowPlayingLyricsPayload)
        case unavailable
    }

    // All guarded state lives on `queue`.
    private var cache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private var activeKey = ""
    private var inflightTasks: [URLSessionDataTask] = []

    private init() {}

    // MARK: - Public API (main thread)

    /// Shows the cached or freshly fetched lyrics for the snapshot's track.
    /// Safe to call repeatedly: a cache hit publishes instantly, an in-flight
    /// lookup for the same track is not duplicated.
    func ensureLyrics(title: String,
                      artist: String,
                      album: String,
                      duration: TimeInterval?,
                      bundleID: String?) {
        let key = NowPlayingLyricsCacheKey.make(title: title, artist: artist,
                                                album: album, duration: duration)
        guard !title.isEmpty else {
            paneState = .unavailable
            payload = nil
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.activeKey = key
            if let entry = self.cache[key] {
                self.touchCacheKey(key)
                self.publish(entry: entry)
                return
            }
            self.publish(paneState: .loading, payload: nil)
            self.runPipeline(key: key, title: title, artist: artist,
                             album: album, duration: duration, bundleID: bundleID)
        }
    }

    /// A track change or a closed pane invalidates the in-flight lookup; the
    /// cached results stay around for when the track comes back.
    func cancelInflight() {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeKey = ""
            for task in self.inflightTasks {
                task.cancel()
            }
            self.inflightTasks.removeAll()
        }
    }

    /// Drops every cached lyrics result; the action behind "Clear media cache".
    func clearCache() {
        queue.async { [weak self] in
            self?.cache.removeAll()
            self?.cacheAccessOrder.removeAll()
        }
    }

    // MARK: - Pipeline (runs on `queue`)

    private func runPipeline(key: String,
                             title: String,
                             artist: String,
                             album: String,
                             duration: TimeInterval?,
                             bundleID: String?) {
        fetchLrclibExact(title: title, artist: artist, album: album, duration: duration) { [weak self] outcome in
            guard let self, self.activeKey == key else { return }
            switch outcome {
            case .available(let payload):
                self.finish(key: key, entry: .available(payload))
                return
            case .failed:
                // Network trouble: fall through to the local Music fallback,
                // then report the failure so the pane offers a retry.
                break
            case .miss:
                break
            }
            self.searchLrclib(title: title, artist: artist, duration: duration) { outcome in
                guard self.activeKey == key else { return }
                switch outcome {
                case .available(let payload):
                    self.finish(key: key, entry: .available(payload))
                case .miss:
                    self.fetchMusicAppLyrics(bundleID: bundleID) { payload in
                        guard self.activeKey == key else { return }
                        if let payload {
                            self.finish(key: key, entry: .available(payload))
                        } else {
                            self.finish(key: key, entry: .unavailable)
                        }
                    }
                case .failed:
                    self.fetchMusicAppLyrics(bundleID: bundleID) { payload in
                        guard self.activeKey == key else { return }
                        if let payload {
                            self.finish(key: key, entry: .available(payload))
                        } else {
                            self.finish(key: key, entry: .unavailable)
                            self.publish(paneState: .failed, payload: nil)
                        }
                    }
                }
            }
        }
    }

    private enum FetchOutcome {
        case available(NowPlayingLyricsPayload)
        case miss
        case failed
    }

    private func finish(key: String, entry: CacheEntry) {
        cache[key] = entry
        touchCacheKey(key)
        pruneCacheIfNeeded()
        publish(entry: entry)
    }

    /// lrclib's exact endpoint: track + artist + album + duration.
    private func fetchLrclibExact(title: String,
                                  artist: String,
                                  album: String,
                                  duration: TimeInterval?,
                                  completion: @escaping (FetchOutcome) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int((duration ?? 0).rounded()))),
        ]
        guard let url = components?.url else {
            completion(.failed)
            return
        }
        getJSON(url: url) { result in
            switch result {
            case .success(let json):
                let synced = (json["syncedLyrics"] as? String) ?? (json["synced_lyrics"] as? String)
                let plain = (json["plainLyrics"] as? String) ?? (json["plain_lyrics"] as? String)
                let candidate = NowPlayingLyricsCandidate(
                    trackName: title, artistName: artist, duration: duration,
                    syncedLyrics: synced, plainLyrics: plain)
                if let payload = NowPlayingLyricsCandidate.payload(from: candidate) {
                    completion(.available(payload))
                } else {
                    completion(.miss)
                }
            case .failure(let status):
                completion(status == 404 ? .miss : .failed)
            }
        }
    }

    /// lrclib's search endpoint: track + artist, scored with a loose-match
    /// threshold so near-misses never surface the wrong lyrics.
    private func searchLrclib(title: String,
                              artist: String,
                              duration: TimeInterval?,
                              completion: @escaping (FetchOutcome) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components?.url else {
            completion(.failed)
            return
        }
        getJSON(url: url) { result in
            switch result {
            case .success(let json):
                let items = (json["__array__"] as? [[String: Any]]) ?? []
                let candidates = items.compactMap(NowPlayingLyricsCandidate.from(dictionary:))
                if let payload = NowPlayingLyricsCandidate.bestPayload(
                    from: candidates, queryTitle: title,
                    queryArtist: artist, queryDuration: duration ?? 0) {
                    completion(.available(payload))
                } else {
                    completion(.miss)
                }
            case .failure(let status):
                completion(status == 404 ? .miss : .failed)
            }
        }
    }

    /// The Music app stores user/label lyrics on the track itself; reading
    /// them through AppleScript is PlayStatus's local fallback.
    private func fetchMusicAppLyrics(bundleID: String?,
                                     completion: @escaping (NowPlayingLyricsPayload?) -> Void) {
        guard bundleID == NowPlayingAutomation.musicBundleID,
              NowPlayingAutomation.isRunning(bundleID: NowPlayingAutomation.musicBundleID) else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            guard let raw = NowPlayingAutomation.fetchMusicLyrics() else {
                completion(nil)
                return
            }
            let lines = NowPlayingLyricsText.normalizePlain(raw)
            guard !lines.isEmpty else {
                completion(nil)
                return
            }
            completion(NowPlayingLyricsPayload(sourceName: "Music", lines: lines, isTimed: false))
        }
    }

    // MARK: - Networking

    private enum JSONResult {
        case success([String: Any])
        case failure(Int)
    }

    /// GET a JSON document; arrays come back under the "__array__" key so
    /// both endpoint shapes share one completion.
    private func getJSON(url: URL, completion: @escaping (JSONResult) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                self.inflightTasks.removeAll { $0.state == .completed }
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard error == nil, (200...299).contains(status), let data,
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                completion(.failure(status))
                return
            }
            if let array = object as? [[String: Any]] {
                completion(.success(["__array__": array]))
            } else if let dictionary = object as? [String: Any] {
                completion(.success(dictionary))
            } else {
                completion(.failure(status))
            }
        }
        queue.async { [weak self] in
            self?.inflightTasks.append(task)
        }
        task.resume()
    }

    // MARK: - Cache bookkeeping (on `queue`)

    private func touchCacheKey(_ key: String) {
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(key)
    }

    private func pruneCacheIfNeeded() {
        while cache.count > maxCacheEntries, !cacheAccessOrder.isEmpty {
            let evictKey = cacheAccessOrder.removeFirst()
            cache.removeValue(forKey: evictKey)
        }
    }

    // MARK: - Publishing

    private func publish(entry: CacheEntry) {
        switch entry {
        case .available(let payload):
            publish(paneState: .available, payload: payload)
        case .unavailable:
            publish(paneState: .unavailable, payload: nil)
        }
    }

    private func publish(paneState: NowPlayingLyricsPaneState, payload: NowPlayingLyricsPayload?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.paneState = paneState
            self.payload = payload
        }
    }
}

/// The provider-aware search lane: the query goes to the app owning the
/// current session, falling back to the preferred-provider setting. Music
/// searches and plays the library via AppleScript (PlayStatus's behavior),
/// Spotify opens its in-app search through the spotify: URL scheme.
enum NowPlayingSearch {
    /// Which provider the lane targets for the current session.
    static func resolvedProvider(snapshot: NowPlayingSnapshot) -> NowPlayingProvider {
        if snapshot.appBundleID == NowPlayingAutomation.spotifyBundleID { return .spotify }
        if snapshot.appBundleID == NowPlayingAutomation.musicBundleID { return .music }
        let preferred = NowPlayingProvider(rawValue: UserDefaults.standard
            .integer(forKey: DefaultsKey.nowPlayingPreferredProvider)) ?? .auto
        return preferred == .spotify ? .spotify : .music
    }

    static func run(query: String, provider: NowPlayingProvider) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch provider {
        case .music, .auto:
            NowPlayingAutomation.searchMusicLibrary(query: trimmed)
        case .spotify:
            openSpotifySearch(query: trimmed)
        }
    }

    private static func openSpotifySearch(query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let appURL = URL(string: "spotify:search:\(encoded)"),
           NSWorkspace.shared.open(appURL) {
            return
        }
        guard let webURL = URL(string: "https://open.spotify.com/search/\(encoded)") else { return }
        NSWorkspace.shared.open(webURL)
    }
}
