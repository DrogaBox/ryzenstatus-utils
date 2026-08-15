// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftUI

/// Stream quality policies for animated artwork playback, mirroring the
/// PlayStatus (MIT, github.com/nbolar/PlayStatus) selection behavior:
/// closest-to-1080p with bandwidth tiebreak, largest variant, or smallest.
enum NowPlayingAnimatedArtworkQuality: Int, CaseIterable {
    case adaptive1080 = 0
    case maxQuality = 1
    case dataSaver = 2
}

/// Resolves and publishes the editorial animated artwork stream for the
/// current track. The pipeline mirrors PlayStatus (MIT) and is fully
/// keyless: the iTunes Search API (no developer key) finds the Apple Music
/// album page, the page's embedded motion artwork video URL is scraped, and
/// an HLS variant is picked per the quality policy. No Apple Music account
/// or token is involved at any step.
///
/// The published `streamURL` feeds the AVPlayer overlay on the popup's
/// artwork tile; nil means the track has no animated artwork (or the
/// feature is switched off), and the tile keeps the static cover.
final class NowPlayingAnimatedArtworkCenter: ObservableObject {
    static let shared = NowPlayingAnimatedArtworkCenter()

    @Published private(set) var streamURL: URL?

    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.animated-artwork", qos: .utility)
    /// Invalidates in-flight resolutions: a track change or a feature toggle
    /// bumps it, so a late answer for the previous track is dropped.
    private var generation = 0
    private var lastTrackKey = ""
    /// Resolution results memoized per track and quality policy; a searched
    /// track without a stream caches nil so it is never re-scraped.
    private var resolutionCache: [String: URL?] = [:]

    private init() {}

    private static let requestUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    // MARK: - Lifecycle

    /// Re-evaluates the stream for the given snapshot. Safe to call on every
    /// snapshot change: the track key and the result cache keep repeat calls
    /// free. Main thread only, like the service that drives it.
    func sync(with snapshot: NowPlayingSnapshot) {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.nowPlayingAnimatedArtwork)
        let quality = NowPlayingAnimatedArtworkQuality(
            rawValue: UserDefaults.standard.integer(forKey: DefaultsKey.nowPlayingAnimatedArtworkQuality))
            ?? .adaptive1080
        let trackKey = Self.trackKey(for: snapshot)

        guard enabled, snapshot.hasTrack, !trackKey.isEmpty else {
            generation += 1
            lastTrackKey = ""
            if streamURL != nil { streamURL = nil }
            return
        }
        guard trackKey != lastTrackKey else { return }
        lastTrackKey = trackKey
        generation += 1
        let gen = generation

        let cacheKey = "\(trackKey)|\(quality.rawValue)"
        if let cached = resolutionCache[cacheKey] {
            streamURL = cached
            return
        }
        streamURL = nil

        let descriptor = ResolutionDescriptor(bundleID: snapshot.appBundleID ?? "",
                                              artist: snapshot.artist ?? snapshot.displayArtist,
                                              albumArtist: snapshot.albumArtist ?? "",
                                              album: snapshot.album ?? "",
                                              cacheKey: cacheKey)
        queue.async { [weak self] in
            let resolved = Self.resolveStream(for: descriptor, quality: quality)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.resolutionCache[cacheKey] = resolved
                self.streamURL = resolved
            }
        }
    }

    /// Drops every cached resolution (the action behind "Clear media cache").
    func clearCache() {
        queue.async { [weak self] in
            self?.resolutionCache.removeAll()
        }
        generation += 1
        lastTrackKey = ""
        if streamURL != nil { streamURL = nil }
    }

    private static func trackKey(for snapshot: NowPlayingSnapshot) -> String {
        guard snapshot.hasTrack else { return "" }
        let artist = (snapshot.albumArtist ?? snapshot.artist ?? snapshot.displayArtist)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (snapshot.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !album.isEmpty else { return "" }
        return "\(snapshot.appBundleID ?? "")|\(artist)|\(album)"
    }

    // MARK: - Resolution pipeline

    private struct ResolutionDescriptor {
        let bundleID: String
        let artist: String
        let albumArtist: String
        let album: String
        let cacheKey: String
    }

    /// Spotify metadata drifts from the Apple Music catalog more often, so it
    /// takes the strict matching profile — exactly PlayStatus's split.
    private static func resolveStream(for descriptor: ResolutionDescriptor,
                                      quality: NowPlayingAnimatedArtworkQuality) -> URL? {
        let strict = descriptor.bundleID == NowPlayingAutomation.spotifyBundleID
        guard let albumURL = lookupAlbumURL(artist: descriptor.artist,
                                            albumArtist: descriptor.albumArtist,
                                            album: descriptor.album,
                                            strict: strict) else {
            return nil
        }
        guard let html = fetchPage(albumURL) else { return nil }
        let candidates = extractCandidateURLs(from: html)
        guard !candidates.isEmpty else { return nil }
        return choosePlaybackURL(from: candidates, quality: quality)
    }

    // MARK: - iTunes Search API album lookup

    private static func lookupAlbumURL(artist: String,
                                       albumArtist: String,
                                       album: String,
                                       strict: Bool) -> URL? {
        let lookupArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? artist.trimmingCharacters(in: .whitespacesAndNewlines)
            : albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistNorm = normalizeText(lookupArtist)
        let albumNorm = normalizeText(album)
        guard !albumNorm.isEmpty else { return nil }

        let storefront = currentStorefrontCode()
        var terms: [String] = []
        let joined = [lookupArtist, album].filter { !$0.isEmpty }.joined(separator: " ")
        if !joined.isEmpty { terms.append(joined) }
        if !album.isEmpty, album != joined { terms.append(album) }

        var candidates: [[String: Any]] = []
        for term in terms {
            let results = searchITunes(term: term, country: storefront)
            candidates.append(contentsOf: results)
            if !candidates.isEmpty { break }
        }
        guard !candidates.isEmpty else { return nil }

        var best: (raw: [String: Any], total: Int, album: Int, artist: Int)?
        for raw in candidates {
            let score = scoreCandidate(raw, artistNorm: artistNorm, albumNorm: albumNorm)
            if best == nil || score.total > best!.total {
                best = (raw, score.total, score.album, score.artist)
            }
        }
        guard let best else { return nil }

        // PlayStatus matching floors: standard 170/80/0, strict 230/130/70.
        if strict {
            guard best.total >= 230, best.album >= 130, best.artist >= 70 else { return nil }
        } else {
            guard best.total >= 170, best.album >= 80 else { return nil }
        }

        if let collectionID = int64Value(best.raw["collectionId"]) {
            return URL(string: "https://music.apple.com/\(storefront)/album/id\(collectionID)")
        }
        return (best.raw["collectionViewUrl"] as? String).flatMap(URL.init(string:))
    }

    private static func searchITunes(term: String, country: String) -> [[String: Any]] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(requestUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")

        let semaphore = DispatchSemaphore(value: 0)
        var results: [[String: Any]] = []
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = json["results"] as? [[String: Any]] else { return }
            results = raw
        }.resume()
        semaphore.wait()
        return results
    }

    private static func scoreCandidate(_ raw: [String: Any],
                                       artistNorm: String,
                                       albumNorm: String) -> (total: Int, album: Int, artist: Int) {
        let candidateAlbum = normalizeText(raw["collectionName"] as? String ?? "")
        let candidateArtist = normalizeText(raw["artistName"] as? String ?? "")

        var albumScore = 0
        if candidateAlbum == albumNorm {
            albumScore += 140
        } else if candidateAlbum.contains(albumNorm) || albumNorm.contains(candidateAlbum) {
            albumScore += 90
        }
        albumScore += tokenOverlapScore(tokenSet(albumNorm), tokenSet(candidateAlbum), maxPoints: 70)
        if candidateAlbum.isEmpty { albumScore -= 40 }

        var artistScore = 0
        if !artistNorm.isEmpty {
            if candidateArtist == artistNorm {
                artistScore += 90
            } else if candidateArtist.contains(artistNorm) || artistNorm.contains(candidateArtist) {
                artistScore += 55
            }
            artistScore += tokenOverlapScore(tokenSet(artistNorm), tokenSet(candidateArtist), maxPoints: 45)
        }

        return (albumScore + artistScore, albumScore, artistScore)
    }

    private static func tokenOverlapScore(_ lhs: Set<String>, _ rhs: Set<String>, maxPoints: Int) -> Int {
        let intersection = lhs.intersection(rhs).count
        guard intersection > 0 else { return 0 }
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Int((Double(intersection) / Double(union) * Double(maxPoints)).rounded())
    }

    private static func tokenSet(_ normalized: String) -> Set<String> {
        Set(normalized.split(separator: " ").map(String.init).filter { $0.count >= 2 })
    }

    private static func normalizeText(_ input: String) -> String {
        let folded = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let alphanumeric = folded.replacingOccurrences(of: "[^a-z0-9]+", with: " ",
                                                       options: .regularExpression)
        return alphanumeric.replacingOccurrences(of: "\\s+", with: " ",
                                                 options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentStorefrontCode() -> String {
        let regionCode = Locale.current.region?.identifier.lowercased() ?? ""
        return regionCode.count == 2 ? regionCode : "us"
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        switch raw {
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        case let value as NSNumber: return value.int64Value
        case let value as String: return Int64(value)
        default: return nil
        }
    }

    // MARK: - Album page scrape

    private static func fetchPage(_ url: URL) -> String? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let semaphore = DispatchSemaphore(value: 0)
        var html: String?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            html = String(data: data, encoding: .utf8)
        }.resume()
        semaphore.wait()
        return html
    }

    /// The album page embeds the editorial motion artwork as a JSON blob;
    /// the square-role video URL is preferred, with scored m3u8/mp4
    /// fallbacks. Regexes mirror PlayStatus's candidate extractor.
    static func extractCandidateURLs(from html: String) -> [URL] {
        let normalized = html
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        let preferredSquareCandidates = capturedMatches(
            in: normalized,
            pattern: #""motionDetailSquare"\s*:\s*\{[\s\S]{0,4000}?"video"\s*:\s*"(https://[^"]+\.(?:m3u8|mp4)[^"]*)"#
        )

        var rawCandidates: [String] = []
        let fallbackPatterns = [
            #"https://[^\"'\s<>]+\.m3u8[^\"'\s<>]*"#,
            #"https://[^\"'\s<>]+\.mp4[^\"'\s<>]*"#,
        ]
        for pattern in fallbackPatterns {
            rawCandidates.append(contentsOf: regexMatches(in: normalized, pattern: pattern))
        }

        let scoredFallbacks = deduplicated(rawCandidates).sorted { lhs, rhs in
            let lhsScore = candidateScore(lhs)
            let rhsScore = candidateScore(rhs)
            return lhsScore != rhsScore ? lhsScore > rhsScore : lhs < rhs
        }

        return deduplicated(preferredSquareCandidates + scoredFallbacks)
            .compactMap(URL.init(string:))
    }

    private static func candidateScore(_ candidate: String) -> Int {
        let lower = candidate.lowercased()
        var score = 0
        for (keyword, weight) in [("motion", 9), ("editorial", 7), ("artwork", 6),
                                  ("square", 5), ("video", 3), (".m3u8", 2)]
        where lower.contains(keyword) {
            score += weight
        }
        return score
    }

    private static func regexMatches(in input: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { match in
            guard let range = Range(match.range, in: input) else { return nil }
            return String(input[range])
        }
    }

    private static func capturedMatches(in input: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: input) else { return nil }
            return String(input[range])
        }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }
        return output
    }

    // MARK: - HLS variant selection

    /// First playable candidate wins: an m3u8 master playlist gets a variant
    /// picked by the quality policy, anything else passes through.
    private static func choosePlaybackURL(from candidates: [URL],
                                          quality: NowPlayingAnimatedArtworkQuality) -> URL? {
        for candidate in candidates {
            let lower = candidate.absoluteString.lowercased()
            if lower.contains(".m3u8") {
                return pickVariantURL(fromMasterURL: candidate, quality: quality) ?? candidate
            }
            if lower.contains(".mp4") {
                return candidate
            }
        }
        return candidates.first
    }

    private struct HLSVariant {
        let url: URL
        let width: Int
        let height: Int
        let bandwidth: Int
    }

    private static func pickVariantURL(fromMasterURL masterURL: URL,
                                       quality: NowPlayingAnimatedArtworkQuality) -> URL? {
        let request = URLRequest(url: masterURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        let semaphore = DispatchSemaphore(value: 0)
        var playlist: String?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            playlist = String(data: data, encoding: .utf8)
        }.resume()
        semaphore.wait()
        guard let playlist else { return nil }

        let variants = parseVariants(fromMasterPlaylist: playlist, baseURL: masterURL)
        guard !variants.isEmpty else { return nil }

        switch quality {
        case .maxQuality:
            return variants.max { variantRank($0) < variantRank($1) }?.url
        case .dataSaver:
            return variants.min { variantRank($0) < variantRank($1) }?.url
        case .adaptive1080:
            return variants.sorted { lhs, rhs in
                let lhsDistance = abs(max(lhs.width, lhs.height) - 1080)
                let rhsDistance = abs(max(rhs.width, rhs.height) - 1080)
                return lhsDistance != rhsDistance
                    ? lhsDistance < rhsDistance
                    : lhs.bandwidth > rhs.bandwidth
            }.first?.url
        }
    }

    private static func parseVariants(fromMasterPlaylist playlist: String, baseURL: URL) -> [HLSVariant] {
        let lines = playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var variants: [HLSVariant] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            guard index + 1 < lines.count, !lines[index + 1].hasPrefix("#"),
                  let variantURL = URL(string: lines[index + 1], relativeTo: baseURL)?.absoluteURL
            else { continue }
            let attributes = line.dropFirst("#EXT-X-STREAM-INF:".count)
            let resolution = firstMatch(in: String(attributes), pattern: #"RESOLUTION=(\d+)x(\d+)"#)
            let parts = resolution?.split(separator: "x") ?? []
            variants.append(HLSVariant(
                url: variantURL,
                width: parts.count == 2 ? Int(parts[0]) ?? 0 : 0,
                height: parts.count == 2 ? Int(parts[1]) ?? 0 : 0,
                bandwidth: firstMatch(in: String(attributes), pattern: #"BANDWIDTH=(\d+)"#).flatMap(Int.init) ?? 0
            ))
        }
        return variants
    }

    private static func variantRank(_ variant: HLSVariant) -> Int {
        let pixels = variant.width * variant.height
        return pixels > 0 ? pixels : variant.bandwidth
    }

    private static func firstMatch(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[resultRange])
    }
}

// MARK: - Playback surface

/// The muted, looping AVPlayer behind the animated artwork overlay. The
/// layer reports render readiness once the first frame decodes, and the
/// hosting view crossfades it in — PlayStatus's transition surface.
private final class NowPlayingAnimatedArtworkPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var layerReadinessObservation: NSKeyValueObservation?
    private var hasReportedReady = false
    private var lastNotifiedReadiness: Bool?
    var onRenderReadinessChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    deinit {
        teardownPlayer(shouldNotify: false)
    }

    func configure(streamURL: URL) {
        guard player == nil || playerLayer.player == nil else { return }
        setupPlayer(streamURL: streamURL)
    }

    func reset() {
        onRenderReadinessChanged = nil
        teardownPlayer(shouldNotify: false)
    }

    private func setupPlayer(streamURL: URL) {
        teardownPlayer(shouldNotify: false)
        hasReportedReady = false

        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        playerLayer.player = player
        self.player = player

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, _ in
            guard let self, observedItem.status == .failed else { return }
            self.hasReportedReady = false
            self.notifyRenderReadiness(false)
        }

        layerReadinessObservation = playerLayer.observe(\.isReadyForDisplay,
                                                        options: [.new, .initial]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay, !self.hasReportedReady else { return }
            self.hasReportedReady = true
            self.notifyRenderReadiness(true)
            self.player?.play()
        }

        // The artwork loop: seek to the start and keep playing at the end.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player?.seek(to: .zero)
            self.player?.play()
        }

        player.play()
    }

    private func teardownPlayer(shouldNotify: Bool) {
        itemStatusObservation = nil
        layerReadinessObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        hasReportedReady = false
        player?.pause()
        playerLayer.player = nil
        player = nil
        if shouldNotify {
            notifyRenderReadiness(false)
        } else {
            lastNotifiedReadiness = nil
        }
    }

    private func notifyRenderReadiness(_ isReady: Bool) {
        guard lastNotifiedReadiness != isReady else { return }
        lastNotifiedReadiness = isReady
        let callback = onRenderReadinessChanged
        DispatchQueue.main.async { callback?(isReady) }
    }
}

private struct NowPlayingAnimatedArtworkRepresentable: NSViewRepresentable {
    let streamURL: URL
    let onRenderReadinessChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NowPlayingAnimatedArtworkPlayerView {
        let view = NowPlayingAnimatedArtworkPlayerView()
        view.configure(streamURL: streamURL)
        view.onRenderReadinessChanged = onRenderReadinessChanged
        return view
    }

    func updateNSView(_ nsView: NowPlayingAnimatedArtworkPlayerView, context: Context) {
        nsView.onRenderReadinessChanged = onRenderReadinessChanged
        nsView.configure(streamURL: streamURL)
    }

    static func dismantleNSView(_ nsView: NowPlayingAnimatedArtworkPlayerView, coordinator: ()) {
        nsView.reset()
    }
}

/// Duration of the crossfade from static artwork to the animated video stream.
private let _artworkStreamCrossfadeDuration: Double = 2.8

/// Static artwork underneath, the video stream crossfaded on top once its
/// first frame is render-ready — the 2.8s easeInOut reveal PlayStatus uses
/// on its ArtworkStreamTransitionSurface.
struct NowPlayingArtworkStreamSurface<StaticContent: View>: View {
    let streamURL: URL?
    @ViewBuilder let staticContent: () -> StaticContent

    @State private var streamReadyForDisplay = false

    private let crossfadeDuration: Double = _artworkStreamCrossfadeDuration

    var body: some View {
        ZStack {
            staticContent()

            if let streamURL {
                NowPlayingAnimatedArtworkRepresentable(
                    streamURL: streamURL,
                    onRenderReadinessChanged: { isReady in
                        guard isReady != streamReadyForDisplay else { return }
                        withAnimation(.easeInOut(duration: _artworkStreamCrossfadeDuration)) {
                            streamReadyForDisplay = isReady
                        }
                    }
                )
                .opacity(streamReadyForDisplay ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: streamURL) { _, _ in
            withAnimation(.easeInOut(duration: _artworkStreamCrossfadeDuration)) {
                streamReadyForDisplay = false
            }
        }
    }
}
