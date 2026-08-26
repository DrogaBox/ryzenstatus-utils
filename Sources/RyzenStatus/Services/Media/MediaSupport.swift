// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Darwin
import Foundation
import UniformTypeIdentifiers

enum MediaTool: String, CaseIterable, Identifiable {
    case videoCompressor, gifMaker, imageCompressor, textExtractor

    var id: String { rawValue }
}

enum MediaImageFormat: String, CaseIterable, Identifiable {
    case jpeg, heic, png, pdf

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .pdf: return "pdf"
        }
    }

    static func sanitized(_ value: String) -> MediaImageFormat {
        MediaImageFormat(rawValue: value) ?? .jpeg
    }
}

enum MediaVideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaVideoCodec {
        MediaVideoCodec(rawValue: value) ?? .h264
    }
}

struct MediaTrimRange: Equatable {
    let start: Double
    let end: Double

    var duration: Double { max(0, end - start) }
}

/// How the video and GIF tools decide what to shrink.
///
/// `resolution` is the historical behavior: the output dimension is chosen and
/// the file weighs whatever it weighs. `targetSize` inverts it, the weight is
/// chosen and everything else is derived from it.
enum MediaSizingMode: String, CaseIterable, Identifiable {
    case resolution, targetSize

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaSizingMode {
        MediaSizingMode(rawValue: value) ?? .resolution
    }
}

struct MediaVideoSizePlan: Equatable {
    let size: CGSize
    let videoBitRate: Int
    let audioBitRate: Int
}

struct MediaGIFSizePlan: Equatable {
    let width: Int
    let fps: Double
}

enum MediaSupport {
    static let maximumGIFFrames = 300
    static let minimumTargetMegabytes = 1
    static let maximumTargetMegabytes = 512
    static let minimumTargetVideoBitRate = 240_000
    static let minimumTargetGIFWidth = 160
    static let maximumTargetGIFWidth = 1600
    static let minimumTargetGIFFPS: Double = 6
    static let maximumTargetGIFPasses = 4
    /// Muxer overhead plus what rate control overshoots by. Asking the encoder
    /// for slightly less than the ceiling is what makes the first pass land
    /// under it instead of just above.
    static let targetSizeHeadroom = 0.94
    /// Bits a pixel needs before H.264 starts smearing detail. A budget that
    /// cannot pay this for every source pixel buys fewer pixels rather than
    /// starving the ones it keeps.
    private static let targetBitsPerPixel = 0.07

    static func sanitizedTargetMegabytes(_ value: Int) -> Int {
        Swift.min(maximumTargetMegabytes, Swift.max(minimumTargetMegabytes, value))
    }

    /// Megabytes here are 1000 based, the way a sharing limit is written and
    /// the way Finder reports a file, so a file that fits a "20 MB" ceiling
    /// also fits a 20 MiB one and never the other way around.
    static func targetBytes(megabytes: Int) -> Int64 {
        Int64(sanitizedTargetMegabytes(megabytes)) * 1_000_000
    }

    /// A file size is a bitrate multiplied by a duration, so a target size is
    /// a bitrate budget. The budget then decides how many pixels are worth
    /// keeping, which is why this returns a size the caller did not pick.
    static func videoSizePlan(targetBytes: Int64,
                              duration: Double,
                              sourceSize: CGSize,
                              frameRate: Double,
                              hasAudio: Bool,
                              scale: Double = 1) -> MediaVideoSizePlan? {
        guard targetBytes > 0,
              duration.isFinite, duration > 0,
              sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0,
              scale.isFinite, scale > 0
        else { return nil }

        let fps = sanitizedFPS(frameRate, fallback: 30, maxFPS: 60)
        let audio = hasAudio ? targetAudioBitRate(targetBytes: targetBytes, duration: duration) : 0
        let budget = Int((Double(targetBytes) * 8 * targetSizeHeadroom / duration).rounded(.down)) - audio
        let video = Int(Double(budget) * Swift.min(1, scale))
        guard video >= minimumTargetVideoBitRate else { return nil }

        let affordablePixels = Double(video) / (fps * targetBitsPerPixel)
        let sourcePixels = Double(sourceSize.width) * Double(sourceSize.height)
        let longestEdge = Double(Swift.max(sourceSize.width, sourceSize.height))
        let ratio = Swift.min(1, (affordablePixels / sourcePixels).squareRoot())
        // A tiny frame is worse than a soft one, so scaling stops at 480 on the
        // long edge even when the budget would buy less.
        let floorRatio = Swift.min(1, 480 / longestEdge)
        let maxDimension = Int((longestEdge * Swift.max(ratio, floorRatio)).rounded())
        return MediaVideoSizePlan(size: scaledEvenSize(source: sourceSize, maxDimension: maxDimension),
                                  videoBitRate: video,
                                  audioBitRate: audio)
    }

    static func targetAudioBitRate(targetBytes: Int64, duration: Double) -> Int {
        guard duration.isFinite, duration > 0, targetBytes > 0 else { return 128_000 }
        return Double(targetBytes) * 8 / duration < 1_200_000 ? 64_000 : 128_000
    }

    /// One pass of rate control lands near the budget, not on it. A pass that
    /// overshoots derives the next scale from what it actually produced, and
    /// gives up at least a tenth so the sequence always converges.
    static func targetRetryScale(current: Double, actualBytes: Int64, targetBytes: Int64) -> Double? {
        guard current.isFinite, current > 0,
              actualBytes > 0, targetBytes > 0, actualBytes > targetBytes
        else { return nil }
        let next = current * Double(targetBytes) / Double(actualBytes) * targetSizeHeadroom
        guard next.isFinite, next > 0 else { return nil }
        return Swift.min(current * 0.9, next)
    }

    /// Aiming at a size means no frame rate was picked, so the first pass takes
    /// the highest one the frame ceiling allows and the measured passes take it
    /// down from there.
    static func targetGIFStartFPS(duration: Double, preferred: Double = 15) -> Double {
        guard duration.isFinite, duration > 0 else { return preferred }
        let fitting = (Double(maximumGIFFrames) / duration).rounded(.down)
        return Swift.max(minimumTargetGIFFPS, Swift.min(preferred, fitting))
    }

    static func targetGIFStartWidth(sourceWidth: CGFloat) -> Int {
        guard sourceWidth.isFinite, sourceWidth > 0 else { return maximumTargetGIFWidth }
        return Swift.max(minimumTargetGIFWidth,
                         Swift.min(maximumTargetGIFWidth, Int(sourceWidth.rounded())))
    }

    /// A GIF has no bitrate to aim at: its weight is frames times pixels, so
    /// overshooting is corrected by dropping frames first, since motion
    /// survives a lower rate better than detail survives a smaller frame.
    static func gifSizePlan(width: Int, fps: Double,
                            actualBytes: Int64, targetBytes: Int64) -> MediaGIFSizePlan? {
        guard actualBytes > 0, targetBytes > 0, actualBytes > targetBytes else { return nil }
        let currentWidth = Swift.max(1, width)
        let currentFPS = sanitizedFPS(fps, fallback: 12, maxFPS: 30)
        let ratio = Swift.min(0.9, Double(targetBytes) * targetSizeHeadroom / Double(actualBytes))
        let nextFPS = Swift.max(minimumTargetGIFFPS, (currentFPS * ratio).rounded())
        let remaining = Swift.min(1, ratio / (nextFPS / currentFPS))
        let nextWidth = Swift.max(minimumTargetGIFWidth,
                                  Int((Double(currentWidth) * remaining.squareRoot()).rounded()))
        guard nextWidth < currentWidth || nextFPS < currentFPS else { return nil }
        return MediaGIFSizePlan(width: nextWidth, fps: nextFPS)
    }
    static func sanitizedTool(_ value: String) -> MediaTool {
        MediaTool(rawValue: value) ?? .videoCompressor
    }

    static func sanitizedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return 0.7 }
        return min(1, max(0.1, value))
    }

    static func sanitizedFPS(_ value: Double, fallback: Double = 12, maxFPS: Double = 60) -> Double {
        guard value.isFinite, value > 0 else { return fallback }
        return min(maxFPS, max(1, value.rounded()))
    }

    static func sanitizedPixelDimension(_ value: Double, fallback: Int, min: Int = 64, max: Int = 7680) -> Int {
        guard value.isFinite, value > 0 else { return even(fallback) }
        return even(Swift.min(max, Swift.max(min, Int(value.rounded()))))
    }

    static func sanitizedTrim(start: Double, end: Double, assetDuration: Double) -> MediaTrimRange {
        guard assetDuration.isFinite, assetDuration > 0 else {
            return MediaTrimRange(start: 0, end: 0)
        }
        let cleanStart = start.isFinite ? max(0, min(start, assetDuration)) : 0
        let proposedEnd = end.isFinite && end > 0 ? end : assetDuration
        let cleanEnd = max(cleanStart, min(proposedEnd, assetDuration))
        return MediaTrimRange(start: cleanStart, end: cleanEnd)
    }

    static func scaledEvenSize(source: CGSize, maxDimension: Int) -> CGSize {
        let width = max(1, abs(source.width))
        let height = max(1, abs(source.height))
        let maxSide = CGFloat(max(2, maxDimension))
        let scale = min(1, maxSide / max(width, height))
        return CGSize(width: CGFloat(even(max(2, Int((width * scale).rounded())))),
                      height: CGFloat(even(max(2, Int((height * scale).rounded())))))
    }

    static func scaledVideoSize(source: CGSize, maxDimension: Int) -> CGSize {
        let size = scaledEvenSize(source: source, maxDimension: maxDimension)
        return CGSize(width: CGFloat(multipleOf16(Int(size.width))),
                      height: CGFloat(multipleOf16(Int(size.height))))
    }

    static func outputURL(for inputURL: URL, suffix: String, fileExtension: String) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let base = visibleOutputBaseName(for: inputURL)
        return directory
            .appendingPathComponent("\(base)\(suffix)")
            .appendingPathExtension(fileExtension)
    }

    static func visibleOutputBaseName(for inputURL: URL) -> String {
        let raw = inputURL.deletingPathExtension().lastPathComponent
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = trimmed.drop { $0 == "." }
        return visible.isEmpty ? "Output" : String(visible)
    }

    static func uniqueOutputURL(for inputURL: URL, suffix: String, fileExtension: String,
                                fileManager: FileManager = .default) -> URL {
        let candidate = outputURL(for: inputURL, suffix: suffix, fileExtension: fileExtension)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let directory = candidate.deletingLastPathComponent()
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for index in 2...999 {
            let url = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: url.path) { return url }
        }
        return candidate
    }

    static func makeVisibleIfNeeded(_ outputURL: URL, fileManager: FileManager = .default) {
        guard shouldForceVisibleOutput(outputURL),
              fileManager.fileExists(atPath: outputURL.path) else { return }
        try? (outputURL as NSURL).setResourceValue(false, forKey: .isHiddenKey)
        var info = stat()
        guard outputURL.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }) else { return }
        let flags = UInt32(info.st_flags)
        let visibleFlags = flags & ~UInt32(UF_HIDDEN)
        guard visibleFlags != flags else { return }
        outputURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, visibleFlags)
        }
    }

    /// Whether a dropped file fits the selected tool, mirroring the open
    /// panel's filter. Without this, dropping a PDF on the image tool would
    /// "succeed" by silently rasterizing page one (ImageIO opens PDFs).
    static func inputMatchesTool(contentType: UTType?, inputTypes: [UTType]) -> Bool {
        guard let contentType else { return false }
        return inputTypes.contains { contentType.conforms(to: $0) }
    }

    /// Whether the result deserves the "came out larger" caption: growth is
    /// normal (PDF wraps the image, high quality can beat the source) but a
    /// "compressor" should say so instead of looking broken. Unknown sizes
    /// (zero) never trigger it.
    static func outputGrew(originalBytes: Int64, outputBytes: Int64) -> Bool {
        originalBytes > 0 && outputBytes > originalBytes
    }

    static func recognitionLanguages(for languageRawValue: String) -> [String] {
        switch languageRawValue {
        case "pt-BR": return ["pt-BR", "en-US"]
        case "tr": return ["tr-TR", "en-US"]
        case "ru": return ["ru-RU", "en-US"]
        case "es": return ["es-ES", "en-US"]
        case "de": return ["de-DE", "en-US"]
        case "fr": return ["fr-FR", "en-US"]
        case "it": return ["it-IT", "en-US"]
        case "ja": return ["ja-JP", "en-US"]
        case "ko": return ["ko-KR", "en-US"]
        case "zh-Hans": return ["zh-Hans", "en-US"]
        case "zh-TW": return ["zh-TW", "en-US"]
        case "zh-HK": return ["zh-HK", "en-US"]
        default: return ["en-US"]
        }
    }

    private static func shouldForceVisibleOutput(_ outputURL: URL) -> Bool {
        let name = outputURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.hasPrefix(".")
    }

    private static func even(_ value: Int) -> Int {
        let positive = max(2, value)
        return positive.isMultiple(of: 2) ? positive : positive - 1
    }

    private static func multipleOf16(_ value: Int) -> Int {
        max(16, (max(16, value) / 16) * 16)
    }
}
