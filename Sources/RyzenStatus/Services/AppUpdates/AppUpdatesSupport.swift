// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Everything the app update check decides, with no file system, no network
/// and no processes: version comparison, which findings are real, how the
/// two sources are merged and when the next background check is due. Kept
/// pure so `./build.sh --test` can pin the rules that matter.
enum AppUpdatesSupport {

    // MARK: - Model

    /// Where a pending update comes from, which is also what the app can do
    /// about it: the package manager can install it right here, the store
    /// can only be opened.
    enum Source: String, Hashable {
        case packageManager
        case appStore
    }

    struct Item: Identifiable, Hashable {
        let id: String
        let source: Source
        /// Name as the person knows it, from the app bundle when there is one.
        let name: String
        let installedVersion: String
        let latestVersion: String
        /// Package token, present only for package-manager rows.
        let token: String?
        /// Path of the app bundle this row stands for, when one was matched.
        let bundlePath: String?
        /// Store page for this app, present only for store rows.
        let storePage: String?

        var canInstallInPlace: Bool { source == .packageManager && token != nil }
        var versionSummary: String { "\(installedVersion) → \(latestVersion)" }
    }

    /// An installed app as the scanner sees it.
    struct InstalledApp: Hashable {
        let name: String
        let bundleID: String
        let path: String
        let version: String
        let isFromAppStore: Bool
    }

    /// One app's current version in the store.
    struct StoreEntry: Hashable {
        let bundleID: String
        let version: String
        let page: String?
    }

    // MARK: - Version comparison

    /// Package versions carry a revision after a comma ("3.5.262,260717d");
    /// only the part in front of it lines up with what an app bundle reports.
    static func versionCore(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ",") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<comma])
    }

    /// Versions that carry no version at all. A package pinned to "latest"
    /// has no number to compare, so it can never be reported honestly as an
    /// update and is left out instead of nagging forever.
    static func isUncomparable(_ version: String) -> Bool {
        let value = versionCore(version).lowercased()
        return value.isEmpty || value == "latest"
    }

    /// Numeric-aware comparison: each dot-separated part is compared as a
    /// number when both sides are digits, so 130 beats 129 and leading zeros
    /// do not lie. A shorter version only loses when the extra parts are not
    /// all zero, so "1.2" and "1.2.0" are the same release.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(of: lhs)
        let right = parts(of: rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : ""
            let b = index < right.count ? right[index] : ""
            let result = comparePart(a, b)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(versionCore(candidate), versionCore(installed)) == .orderedDescending
    }

    private static func parts(of version: String) -> [String] {
        version
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }
    }

    private static func comparePart(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftDigits = lhs.allSatisfy(\.isNumber) && !lhs.isEmpty
        let rightDigits = rhs.allSatisfy(\.isNumber) && !rhs.isEmpty
        if leftDigits && rightDigits {
            let a = stripLeadingZeros(lhs)
            let b = stripLeadingZeros(rhs)
            if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
            if a == b { return .orderedSame }
            return a < b ? .orderedAscending : .orderedDescending
        }
        if lhs.isEmpty { return rightDigits && stripLeadingZeros(rhs).isEmpty ? .orderedSame : .orderedAscending }
        if rhs.isEmpty { return leftDigits && stripLeadingZeros(lhs).isEmpty ? .orderedSame : .orderedDescending }
        if lhs == rhs { return .orderedSame }
        return lhs.lowercased() < rhs.lowercased() ? .orderedAscending : .orderedDescending
    }

    private static func stripLeadingZeros(_ value: String) -> String {
        let trimmed = value.drop(while: { $0 == "0" })
        return String(trimmed)
    }

    // MARK: - Package manager source

    /// Turns what the package manager reports into rows a person can act on.
    static func packageUpdates(outdated: [HomebrewPackageUpdate],
                               installed: [HomebrewCaskRecord],
                               bundleVersion: (String) -> (name: String, version: String, path: String)?)
        -> [Item] {
        let recordsByToken = Dictionary(installed.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        return outdated.compactMap { update -> Item? in
            guard update.kind == .cask, !update.isPinned else { return nil }
            guard !isUncomparable(update.currentVersion) else { return nil }
            let record = recordsByToken[update.name]
            let bundle = candidateBundleNames(for: record).lazy.compactMap(bundleVersion).first
            let receipt = update.installedVersions.first ?? record?.installedVersion ?? ""
            let installedVersion = bundle?.version ?? versionCore(receipt)
            guard !installedVersion.isEmpty else { return nil }
            guard isNewer(update.currentVersion, than: installedVersion) else { return nil }
            return Item(id: "\(Source.packageManager.rawValue):\(update.name)",
                        source: .packageManager,
                        name: bundle?.name ?? record?.displayName ?? update.name,
                        installedVersion: installedVersion,
                        latestVersion: versionCore(update.currentVersion),
                        token: update.name,
                        bundlePath: bundle?.path,
                        storePage: nil)
        }
    }

    private static func candidateBundleNames(for record: HomebrewCaskRecord?) -> [String] {
        guard let record else { return [] }
        guard record.appFileNames.isEmpty else { return record.appFileNames }
        return record.displayName.isEmpty ? [] : ["\(record.displayName).app"]
    }

    // MARK: - App Store source

    static func appStoreCandidates(apps: [InstalledApp],
                                   coveredPaths: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { app in
            app.isFromAppStore
                && !app.bundleID.isEmpty
                && !app.version.isEmpty
                && !coveredPaths.contains(app.path)
                && seen.insert(app.bundleID).inserted
        }
    }

    static let storeLookupBatchSize = 20

    static func storeLookupURL(bundleIDs: [String], country: String?) -> URL? {
        guard !bundleIDs.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var query = [URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator: ",")),
                     URLQueryItem(name: "entity", value: "macSoftware")]
        if let country, !country.isEmpty {
            query.append(URLQueryItem(name: "country", value: country))
        }
        components?.queryItems = query
        return components?.url
    }

    static func parseStoreLookup(_ data: Data) -> [String: StoreEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [:] }
        var entries: [String: StoreEntry] = [:]
        for result in results {
            guard let bundleID = result["bundleId"] as? String,
                  let version = result["version"] as? String,
                  !version.isEmpty else { continue }
            entries[bundleID] = StoreEntry(bundleID: bundleID,
                                           version: version,
                                           page: result["trackViewUrl"] as? String)
        }
        return entries
    }

    static func appStoreUpdates(apps: [InstalledApp],
                                storeVersions: [String: StoreEntry]) -> [Item] {
        apps.compactMap { app in
            guard let entry = storeVersions[app.bundleID],
                  isNewer(entry.version, than: app.version) else { return nil }
            return Item(id: "\(Source.appStore.rawValue):\(app.bundleID)",
                        source: .appStore,
                        name: app.name,
                        installedVersion: app.version,
                        latestVersion: entry.version,
                        token: nil,
                        bundlePath: app.path,
                        storePage: entry.page)
        }
    }

    static func merged(_ groups: [Item]...) -> [Item] {
        var seen = Set<String>()
        let all = groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        return all.sorted { lhs, rhs in
            if lhs.canInstallInPlace != rhs.canInstallInPlace { return lhs.canInstallInPlace }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func tokens(in items: [Item], selection: Set<String>) -> [String] {
        items.filter { selection.contains($0.id) }.compactMap(\.token)
    }

    static func hasStoreSelection(in items: [Item], selection: Set<String>) -> Bool {
        items.contains { selection.contains($0.id) && $0.source == .appStore }
    }

    static func reconciledSelection(previous: Set<String>,
                                    knownIDs: Set<String>,
                                    items: [Item]) -> Set<String> {
        var next = previous.intersection(Set(items.map(\.id)))
        for item in items where !knownIDs.contains(item.id) {
            next.insert(item.id)
        }
        return next
    }

    // MARK: - Background schedule

    enum CheckFrequency: String, CaseIterable, Identifiable {
        case off, daily, weekly

        var id: String { rawValue }

        static func sanitized(_ raw: String?) -> CheckFrequency {
            CheckFrequency(rawValue: raw ?? "") ?? .off
        }

        var interval: TimeInterval {
            switch self {
            case .off: return 0
            case .daily: return 24 * 60 * 60
            case .weekly: return 7 * 24 * 60 * 60
            }
        }
    }

    static let catchUpDelay: TimeInterval = 180
    static let staleAfter: TimeInterval = 10 * 60

    static func shouldRecheck(hasCheckedThisSession: Bool,
                              handoffPending: Bool,
                              lastCheck: Date?,
                              now: Date) -> Bool {
        if handoffPending { return true }
        guard hasCheckedThisSession, let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= staleAfter
    }

    static func nextCheckDate(lastCheck: Date?,
                              frequency: CheckFrequency,
                              now: Date) -> Date? {
        guard frequency != .off else { return nil }
        guard let lastCheck else { return now.addingTimeInterval(catchUpDelay) }
        let due = lastCheck.addingTimeInterval(frequency.interval)
        return due <= now ? now.addingTimeInterval(catchUpDelay) : due
    }
}
