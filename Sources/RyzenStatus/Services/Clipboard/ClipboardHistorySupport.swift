// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import SwiftUI

enum ClipboardHistoryEntryKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    /// The content for text entries; empty for images and files, whose display
    /// strings are derived so they never go stale in storage.
    var text: String
    var copiedAt: Date
    var pinnedAt: Date?
    let kind: ClipboardHistoryEntryKind
    /// Absolute paths for `.files` entries, in the order they were copied.
    let filePaths: [String]
    /// PNG file name inside the clipboard image store for `.image` entries.
    let imageFile: String?
    /// SHA-256 of the PNG data, so re-copying the same image refreshes the
    /// existing entry instead of storing a duplicate file.
    let imageHash: String?
    let imageWidth: Int?
    let imageHeight: Int?

    init(id: UUID = UUID(),
         text: String,
         copiedAt: Date = Date(),
         pinnedAt: Date? = nil,
         kind: ClipboardHistoryEntryKind = .text,
         filePaths: [String] = [],
         imageFile: String? = nil,
         imageHash: String? = nil,
         imageWidth: Int? = nil,
         imageHeight: Int? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.pinnedAt = pinnedAt
        self.kind = kind
        self.filePaths = filePaths
        self.imageFile = imageFile
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    var fileNames: [String] {
        filePaths.map { ($0 as NSString).lastPathComponent }
    }

    var imageDimensionsLabel: String {
        guard let imageWidth, let imageHeight else { return "" }
        return "\(imageWidth)×\(imageHeight)"
    }

    /// The color a text entry spells out, if that is all it holds.
    var color: ColorValue? {
        kind == .text ? ColorValue(text: text) : nil
    }

    var preview: String {
        switch kind {
        case .text:
            let collapsed = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? text : collapsed
        case .image:
            return imageDimensionsLabel
        case .files:
            return fileNames.joined(separator: ", ")
        }
    }

    /// Same clipboard content, regardless of when it was copied: re-copying
    /// refreshes the existing entry instead of duplicating it.
    func matchesContent(of other: ClipboardHistoryEntry) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imageHash != nil && imageHash == other.imageHash
        case .files: return filePaths == other.filePaths
        }
    }

    /// What the search box can match. Image entries carry the localized label
    /// plus dimensions so typing "image"/"imagem" finds them.
    func searchableText(imageLabel: String) -> String {
        switch kind {
        case .text: return text
        case .image: return "\(imageLabel) png \(imageDimensionsLabel)"
        case .files:
            let names = fileNames.joined(separator: " ")
            let hasImageFiles = filePaths.contains(where: ClipboardHistoryImageSupport.isImageFileName)
            return hasImageFiles ? "\(names) \(imageLabel)" : names
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, pinnedAt, kind, filePaths, imageFile, imageHash, imageWidth, imageHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decodeIfPresent(Date.self, forKey: .copiedAt) ?? Date()
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        // Histories written before images and files existed decode as text.
        kind = try container.decodeIfPresent(ClipboardHistoryEntryKind.self, forKey: .kind) ?? .text
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        imageFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
    }
}

enum ClipboardHistoryEditing {
    static let maxCharacters = 20_000

    static func storableText(_ text: String) -> String? {
        guard text.count <= maxCharacters,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    static func canSave(original: String, draft: String) -> Bool {
        guard let text = storableText(draft) else { return false }
        return text != original
    }
}

struct ClipboardHistorySearchCandidate {
    var index: Int
    var text: String
    var isPinned: Bool
}

enum ClipboardHistorySearch {
    static func rankedIndexes(candidates: [ClipboardHistorySearchCandidate],
                              matching query: String) -> [Int] {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return candidates.map(\.index) }

        return candidates
            .compactMap { candidate -> (index: Int, score: Int, originalOrder: Int)? in
                let text = normalized(candidate.text)
                guard tokens.allSatisfy({ text.contains($0) }) else { return nil }
                return (candidate.index,
                        score(for: text,
                              normalizedQuery: normalizedQuery,
                              tokens: tokens,
                              isPinned: candidate.isPinned),
                        candidate.index)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalOrder < $1.originalOrder
            }
            .map(\.index)
    }

    static func matches(_ text: String, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return true }
        let normalizedText = normalized(text)
        return tokens.allSatisfy { normalizedText.contains($0) }
    }

    private static func score(for text: String,
                              normalizedQuery: String,
                              tokens: [String],
                              isPinned: Bool) -> Int {
        var score = isPinned ? 30 : 0
        if text == normalizedQuery { score += 1_200 }
        if text.hasPrefix(normalizedQuery) { score += 900 }
        if text.contains(normalizedQuery) { score += 700 }

        let words = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
        for token in tokens {
            if words.contains(token) {
                score += 140
            } else if words.contains(where: { $0.hasPrefix(token) }) {
                score += 80
            } else {
                score += 40
            }
        }
        return score
    }

    private static func queryTokens(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-empty search tokens from a raw query, split by whitespace.
    static func searchTokens(for query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Finds all matching character ranges in `text` for the given tokens,
    /// matching case-insensitively, diacritic-insensitively, and width-insensitively.
    static func highlightRanges(in text: String, tokens: [String]) -> [Range<String.Index>] {
        guard !text.isEmpty, !tokens.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            guard !token.isEmpty else { continue }
            var search = text.startIndex..<text.endIndex
            while search.lowerBound < text.endIndex,
                  let r = text.range(of: token,
                                     options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                     range: search) {
                ranges.append(r)
                if r.upperBound == search.lowerBound {
                    break
                }
                search = r.upperBound..<text.endIndex
            }
        }
        return ranges
    }
}

/// Marks what a clipboard search matched in a row's text.
enum SearchHighlightText {
    static let visibleCharacters = 500

    static func excerpt(_ string: String) -> String {
        guard let end = string.index(string.startIndex, offsetBy: visibleCharacters, limitedBy: string.endIndex),
              end < string.endIndex else { return string }
        return String(string[..<end]) + "…"
    }

    static func highlighted(_ string: String,
                            tokens: [String],
                            fontSize: CGFloat,
                            highlightColor: Color? = .accentColor,
                            highlightWeight: Font.Weight = .semibold) -> AttributedString {
        let visible = excerpt(string)
        var attributed = AttributedString(visible)
        for range in ClipboardHistorySearch.highlightRanges(in: visible, tokens: tokens) {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            if let highlightColor { attributed[attributedRange].foregroundColor = highlightColor }
            attributed[attributedRange].font = .system(size: fontSize, weight: highlightWeight)
        }
        return attributed
    }

    static func text(_ string: String,
                     tokens: [String],
                     fontSize: CGFloat,
                     highlightColor: Color? = .accentColor) -> Text {
        guard !tokens.isEmpty else { return Text(string) }
        return Text(highlighted(string, tokens: tokens, fontSize: fontSize, highlightColor: highlightColor))
    }
}

enum ClipboardHistorySelection {
    static func initialIndex(totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        return 0
    }

    static func previewEntry(preferredID: UUID?,
                             visibleEntries: [ClipboardHistoryEntry],
                             selectedEntry: ClipboardHistoryEntry?) -> ClipboardHistoryEntry? {
        if let preferredID,
           let entry = visibleEntries.first(where: { $0.id == preferredID }) {
            return entry
        }
        return selectedEntry
    }
}

enum ClipboardHistoryEscape {
    enum Action: Equatable {
        case clearBatchSelection
        case hideWindow
    }

    /// Esc backs out one layer at a time — selection, then the window.
    /// Preview is a persistent view setting, not a layer: only clicking its
    /// own toggle turns it off, so a keystroke meant to close the panel
    /// can never silently re-hide it first.
    static func action(batchCount: Int) -> Action {
        batchCount > 0 ? .clearBatchSelection : .hideWindow
    }
}

enum ClipboardHistoryBatch {
    static func combinedText(_ texts: [String]) -> String {
        texts.joined(separator: "\n")
    }

    static func orderedSelectedIndexes<ID: Hashable>(allIDs: [ID], selectedIDs: Set<ID>) -> [Int] {
        allIDs.indices.filter { selectedIDs.contains(allIDs[$0]) }
    }

    /// The ids a shift-click covers, Finder style: from the anchor row (the
    /// last one the user touched) to the clicked one, inclusive, in either
    /// direction.
    static func rangeSelectionIDs<ID>(allIDs: [ID], anchor: Int, target: Int) -> [ID] {
        guard !allIDs.isEmpty else { return [] }
        let low = min(max(min(anchor, target), 0), allIDs.count - 1)
        let high = min(max(max(anchor, target), 0), allIDs.count - 1)
        return Array(allIDs[low...high])
    }

    /// How a multi-item selection travels on the pasteboard. A selection made
    /// only of file items pastes as the files themselves, so Finder receives
    /// real files. A selection with any image in it pastes as rich text with
    /// the images embedded (Notes, Mail and TextEdit take both together),
    /// with the text parts doubling as the plain-text fallback. Anything else
    /// combines as text, file items contributing their paths.
    enum PasteMode: Equatable {
        case files([String])
        case text(String)
        case rich([RichPart])
    }

    enum RichPart: Equatable {
        case text(String)
        /// The image store file name for an `.image` entry.
        case image(String)
    }

    static func pasteMode(for entries: [ClipboardHistoryEntry]) -> PasteMode? {
        guard !entries.isEmpty else { return nil }
        if entries.allSatisfy({ $0.kind == .files }) {
            return .files(entries.flatMap(\.filePaths))
        }
        if entries.contains(where: { $0.kind == .image }) {
            let parts = entries.compactMap { entry -> RichPart? in
                switch entry.kind {
                case .text: return .text(entry.text)
                case .files: return .text(entry.filePaths.joined(separator: "\n"))
                case .image: return entry.imageFile.map(RichPart.image)
                }
            }
            return parts.isEmpty ? nil : .rich(parts)
        }
        let texts = entries.map { entry in
            entry.kind == .files ? entry.filePaths.joined(separator: "\n") : entry.text
        }
        return .text(combinedText(texts))
    }

    /// Whether a window-level ⌘C/⌘A belongs to the entry list instead of the
    /// search field. Only an explicit multi-selection claims the shortcut:
    /// arrow-key highlight alone must not steal copy or select-all from text
    /// editing in the field (⇧Enter still copies the highlighted row).
    /// ⌘A additionally falls to the list while the query is empty, where the
    /// field has nothing to select.
    static func listOwnsCopyShortcut(batchCount: Int) -> Bool {
        batchCount > 0
    }

    static func listOwnsSelectAllShortcut(batchCount: Int, queryIsEmpty: Bool) -> Bool {
        batchCount > 0 || queryIsEmpty
    }

    /// The plain-text side of a rich batch, for targets that only take text.
    static func richPlainText(_ parts: [RichPart]) -> String {
        combinedText(parts.compactMap { part in
            if case let .text(text) = part { return text }
            return nil
        })
    }
}

enum ClipboardHistoryPasteboardText {
    static func preferredText(webURLString: String?, plainText: String?) -> String? {
        let plain = trimmed(plainText)
        if let plain,
           let normalizedPlain = normalizedWebURL(plain) {
            return normalizedPlain
        }

        guard let webURL = normalizedWebURL(webURLString) else { return plain }
        guard let plain else { return webURL }
        return shouldPreferWebURL(webURL, over: plain) ? webURL : plain
    }

    private static func shouldPreferWebURL(_ webURL: String, over plain: String) -> Bool {
        if plain.hasPrefix("//") { return true }
        let stripped = stripWebScheme(webURL)
        return plain == stripped.withSlashes || plain == stripped.withoutSlashes
    }

    private static func normalizedWebURL(_ raw: String?) -> String? {
        guard let text = trimmed(raw),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    private static func stripWebScheme(_ value: String) -> (withSlashes: String, withoutSlashes: String) {
        let lower = value.lowercased()
        let withSlashes: String
        if lower.hasPrefix("http://") {
            withSlashes = "//" + String(value.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            withSlashes = "//" + String(value.dropFirst("https://".count))
        } else {
            withSlashes = value
        }
        return (withSlashes, String(withSlashes.drop { $0 == "/" }))
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

enum ClipboardHistorySensitiveText {
    static func looksSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let obviousWords = [
            "password", "passwd", "pwd", "secret", "token", "apikey", "api_key",
            "authorization", "bearer", "session", "credential", "otp", "private_key",
            "auth_token", "access_token"
        ]
        if obviousWords.contains(where: lowered.contains) { return true }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
           url.host != nil {
            if let query = url.query?.lowercased() {
                let sensitiveQueryKeys = ["token", "auth", "key", "secret", "sig", "signature", "pwd", "password", "session", "bearer"]
                if sensitiveQueryKeys.contains(where: { query.contains($0 + "=") || query.hasPrefix($0 + "=") }) {
                    return true
                }
            }
            return false
        }

        guard trimmed.count >= 12, trimmed.count <= 160, !trimmed.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let hasLetter = trimmed.contains { $0.isLetter }
        let hasDigit = trimmed.contains { $0.isNumber }
        let hasSymbol = trimmed.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        return hasLetter && hasDigit && (hasSymbol || trimmed.count >= 24)
    }
}

enum ClipboardHistoryImageSupport {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "ico", "icns", "svg", "avif"
    ]

    static func isImageFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    static func isImageFilePath(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard isImageFileName(path) else { return false }
        return fileManager.fileExists(atPath: path)
    }
}

extension NSPasteboard {
    func declareRyzenStatusSource() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        setString(bundleID, forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
    }
}

/// A color read from text that is only a color value. The accepted forms are
/// the CSS ones designers copy and the ones the color picker writes: `#RGB`,
/// `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()`, `hsl()`, `hsla()` and
/// SwiftUI's `Color(red:green:blue:opacity:)`. The value must be the whole
/// entry; a color inside a longer text is not one, and a bare `RRGGBB` would
/// also match plain numbers and hashes.
struct ColorValue: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Longer than any accepted form with generous spacing; the cap keeps a
    /// render from trimming or scanning a large entry.
    static let maxLength = 96

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(text: String) {
        guard text.utf8.count <= Self.maxLength else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") {
            self.init(hexDigits: value.dropFirst())
        } else if let arguments = Self.arguments(of: value, names: ["rgba", "rgb"]) {
            self.init(rgbArguments: arguments)
        } else if let arguments = Self.arguments(of: value, names: ["hsla", "hsl"]) {
            self.init(hslArguments: arguments)
        } else if value.hasPrefix("color("), value.hasSuffix(")") {
            self.init(swiftUIArguments: value.dropFirst(6).dropLast())
        } else {
            return nil
        }
    }

    private init?(hexDigits: Substring) {
        guard [3, 4, 6, 8].contains(hexDigits.count),
              hexDigits.allSatisfy(\.isHexDigit)
        else { return nil }
        let expanded = hexDigits.count <= 4
            ? String(hexDigits.flatMap { [$0, $0] })
            : String(hexDigits)
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let hasAlpha = expanded.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    private init?(rgbArguments: [String]) {
        guard (3...4).contains(rgbArguments.count) else { return nil }
        var channels: [Double] = []
        for argument in rgbArguments.prefix(3) {
            if let percent = Self.percentage(argument) {
                channels.append(percent)
            } else if let number = Self.number(argument), (0...255).contains(number) {
                channels.append(number / 255)
            } else {
                return nil
            }
        }
        guard let alpha = Self.alpha(rgbArguments.dropFirst(3).first) else { return nil }
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// `red: 0.2, green: 0.4, blue: 0.6`, optionally followed by
    /// `opacity: 0.5`, with or without spaces around the labels.
    private init?(swiftUIArguments: Substring) {
        let labels = ["red", "green", "blue", "opacity"]
        let pairs = swiftUIArguments.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false) }
        guard (3...4).contains(pairs.count) else { return nil }
        var components: [Double] = []
        for (label, pair) in zip(labels, pairs) {
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines) == label,
                  let value = Self.number(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  (0...1).contains(value)
            else { return nil }
            components.append(value)
        }
        self.init(red: components[0], green: components[1], blue: components[2],
                  alpha: components.count == 4 ? components[3] : 1)
    }

    private init?(hslArguments: [String]) {
        guard (3...4).contains(hslArguments.count) else { return nil }
        let hueText = hslArguments[0].hasSuffix("deg")
            ? String(hslArguments[0].dropLast(3))
            : hslArguments[0]
        guard let hue = Self.number(hueText),
              let saturation = Self.percentage(hslArguments[1]),
              let lightness = Self.percentage(hslArguments[2]),
              let alpha = Self.alpha(hslArguments.dropFirst(3).first)
        else { return nil }
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        func channel(_ offset: Double) -> Double {
            let k = (offset + h * 12).truncatingRemainder(dividingBy: 12)
            return lightness - chroma / 2 * max(-1, min(k - 3, 9 - k, 1))
        }
        self.init(red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
    }

    /// The arguments of `name(...)`, split on commas, spaces and the slash
    /// that CSS puts before the alpha value.
    private static func arguments(of value: String, names: [String]) -> [String]? {
        guard value.hasSuffix(")"),
              let name = names.first(where: { value.hasPrefix($0 + "(") })
        else { return nil }
        let inner = value.dropFirst(name.count + 1).dropLast()
        return inner
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
    }

    private static func number(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// A `0%`...`100%` value as a fraction.
    private static func percentage(_ text: String) -> Double? {
        guard text.hasSuffix("%"),
              let value = number(String(text.dropLast())),
              (0...100).contains(value)
        else { return nil }
        return value / 100
    }

    /// Opaque when absent; otherwise a `0`...`1` number or a percentage.
    private static func alpha(_ text: String?) -> Double? {
        guard let text else { return 1 }
        if let percent = percentage(text) { return percent }
        guard let value = number(text), (0...1).contains(value) else { return nil }
        return value
    }
}

/// How a color is written out.
enum ColorCopyFormat: String, CaseIterable, Identifiable {
    case hex
    case rgb
    case hsl
    case swiftui

    var id: String { rawValue }

    /// Short technical label; intentionally not localized.
    var label: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftui: return "SwiftUI"
        }
    }

    static func sanitized(_ raw: String) -> ColorCopyFormat {
        ColorCopyFormat(rawValue: raw) ?? .hex
    }
}

extension ColorValue {
    /// Formats sRGB components (0...1) in the chosen copy format. Components
    /// out of range are clamped so extended-gamut samples never produce
    /// invalid strings. `bareHex` drops the leading # (issue #168: some design
    /// tools reject pasted values that carry it); it only affects `.hex`.
    /// A non-nil `alpha` writes the alpha form.
    static func string(red: Double,
                       green: Double,
                       blue: Double,
                       alpha: Double? = nil,
                       format: ColorCopyFormat,
                       bareHex: Bool = false) -> String {
        let r = min(max(red, 0), 1)
        let g = min(max(green, 0), 1)
        let b = min(max(blue, 0), 1)
        let a = alpha.map { min(max($0, 0), 1) }
        // Three decimals are the fewest that bring every 8-bit alpha back.
        let alphaText = a.map { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"),
                                       ($0 * 1000).rounded() / 1000) }
        switch format {
        case .hex:
            let hex = String(format: bareHex ? "%02X%02X%02X" : "#%02X%02X%02X",
                             Int((r * 255).rounded()),
                             Int((g * 255).rounded()),
                             Int((b * 255).rounded()))
            return a.map { hex + String(format: "%02X", Int(($0 * 255).rounded())) } ?? hex
        case .rgb:
            let channels = String(format: "%d, %d, %d",
                                  Int((r * 255).rounded()),
                                  Int((g * 255).rounded()),
                                  Int((b * 255).rounded()))
            return alphaText.map { "rgba(\(channels), \($0))" } ?? "rgb(\(channels))"
        case .hsl:
            let (h, s, l) = hsl(red: r, green: g, blue: b)
            let channels = String(format: "%d, %d%%, %d%%",
                                  Int(h.rounded()),
                                  Int((s * 100).rounded()),
                                  Int((l * 100).rounded()))
            return alphaText.map { "hsla(\(channels), \($0))" } ?? "hsl(\(channels))"
        case .swiftui:
            // Source code, not prose: a comma here would paste something that
            // does not compile, whatever region the reader is in.
            let posix = Locale(identifier: "en_US_POSIX")
            let rgb = String(format: "red: %.3f, green: %.3f, blue: %.3f", locale: posix, r, g, b)
            return a.map { "Color(\(rgb), opacity: \(String(format: "%.3f", locale: posix, $0)))" }
                ?? "Color(\(rgb))"
        }
    }

    static func hsl(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, lightness: Double) {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2

        guard delta > 0.000001 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maxComponent == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxComponent == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, min(max(saturation, 0), 1), lightness)
    }
}


