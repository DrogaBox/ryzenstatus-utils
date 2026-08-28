// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Darwin

/// Finds the files an app leaves around — caches, preferences, logs, support
/// folders, containers — and moves the ones you pick to the Trash, then reports
/// the space recovered. Everything goes to the Trash (reversible), never an
/// unrecoverable delete, so the flow stays safe.
final class AppUninstaller: ObservableObject {
    static let shared = AppUninstaller()

    enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: [Leftover])
    }

    struct Target: Equatable {
        let name: String
        let bundleID: String?
        let url: URL
        let icon: NSImage

        static func == (lhs: Target, rhs: Target) -> Bool { lhs.url == rhs.url }
    }

    enum Category: Int, CaseIterable {
        case app, support, caches, preferences, containers, logs, state, other

        var sortRank: Int { rawValue }
    }

    struct Leftover: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let category: Category
        let size: Int64
        let ownerBundleID: String?
        let ownerGroupID: String?
        let evidenceBundleID: String?
        let confidence: UninstallerSupport.LeftoverMatch
        let fileIdentity: UninstallerSupport.FileIdentity
        var include: Bool = true

        var name: String { url.lastPathComponent }

        static func == (lhs: Leftover, rhs: Leftover) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var target: Target?
    @Published var items: [Leftover] = []
    private var allowedRemovalPaths = Set<String>()
    private var targetFileIdentity: UninstallerSupport.FileIdentity?
    private var targetInfoIdentity: UninstallerSupport.FileIdentity?

    private struct ScanCandidate {
        let url: URL
        let category: Category
        let ownerBundleID: String?
        let ownerGroupID: String?
        let evidenceBundleID: String?
        let confidence: UninstallerSupport.LeftoverMatch
        var include: Bool
    }

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    // MARK: - Selection & scan

    /// Reads an app bundle and starts scanning for its leftovers.
    func select(appURL: URL) {
        guard let bundle = Bundle(url: appURL) else { return }
        // System apps are SIP-protected and their support data is live OS
        // state; removing either would be wrong, so refuse the selection.
        guard !InstalledApps.isSystemApplication(at: appURL) else { return }
        // Only a verified bundle identifier becomes a path component. A
        // display name is presentation only and can never claim user data.
        guard let bundleID = UninstallerSupport.verifiedBundleID(bundle.bundleIdentifier) else { return }
        let selectedURL = appURL.standardizedFileURL
        guard selectedURL == selectedURL.resolvingSymlinksInPath() else { return }
        guard selectedURL != Bundle.main.bundleURL.standardizedFileURL else { return }
        guard !UninstallerSupport.isSymbolicLink(appURL) else { return }
        guard let selectedIdentity = UninstallerSupport.fileIdentity(at: selectedURL) else { return }
        let infoURL = selectedURL.appendingPathComponent("Contents/Info.plist")
        guard let selectedInfoIdentity = UninstallerSupport.fileIdentity(at: infoURL),
              UninstallerSupport.removalPathIsSafe(infoURL, within: selectedURL) else { return }
        var name = FileManager.default.displayName(atPath: appURL.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        target = Target(name: name, bundleID: bundleID, url: selectedURL, icon: icon)
        targetFileIdentity = selectedIdentity
        targetInfoIdentity = selectedInfoIdentity
        items = []
        allowedRemovalPaths = []
        phase = .scanning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ownedBundleIDs = Self.allBundleIDs(in: selectedURL, fm: .default)
            let mayClaimSharedData = UninstallerSupport.applicationIsInTrustedInstallRoot(
                selectedURL, home: FileManager.default.homeDirectoryForCurrentUser)
            let knownApplications = mayClaimSharedData
                ? Self.knownApplicationURLs(candidateBundleIDs: ownedBundleIDs)
                : []
            let knownApplicationIDs = Self.applicationBundleIdentifiers(in: knownApplications)
            let exclusiveBundleIDs = mayClaimSharedData
                ? Self.exclusiveOwnedBundleIDs(
                    in: selectedURL, candidates: ownedBundleIDs,
                    knownApplicationIDs: knownApplicationIDs)
                : []
            let signing = Self.signingIdentity(in: selectedURL, requireValidSignature: true)
            let exclusiveGroupIDs = mayClaimSharedData
                ? Self.exclusiveGroupIDs(
                    signing.groupIDs, selectedURL: selectedURL,
                    knownApplications: knownApplications)
                : []
            let found = Self.collect(appURL: selectedURL,
                                     primaryBundleID: bundleID,
                                     exclusiveBundleIDs: exclusiveBundleIDs,
                                     teamIDs: signing.teamIDs,
                                     exclusiveGroupIDs: exclusiveGroupIDs)
            DispatchQueue.main.async {
                guard let self, self.phase == .scanning, self.target?.url == selectedURL else { return }
                guard Self.applicationIdentityMatches(
                    selectedURL, appIdentity: selectedIdentity,
                    infoIdentity: selectedInfoIdentity) else {
                    self.reset()
                    return
                }
                self.items = found
                self.allowedRemovalPaths = Set(found.map { $0.url.standardizedFileURL.path })
                self.phase = .results
            }
        }
    }

    func setInclude(_ include: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    func reset() {
        target = nil
        targetFileIdentity = nil
        targetInfoIdentity = nil
        items = []
        allowedRemovalPaths = []
        phase = .empty
    }

    // MARK: - Removal

    /// Moves the selected items to the Trash via Finder, so the removal is
    /// reversible and elevation prompts go through the system UI.
    func removeSelected() {
        let targets = items.filter(\.include)
        guard !targets.isEmpty else { return }
        phase = .removing

        let allowed = allowedRemovalPaths
        let targetIdentity = targetFileIdentity
        let targetInfoIdentity = targetInfoIdentity
        let targetURL = target?.url

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            // Finder needs the app itself quit first, or it refuses the move.
            if let targetURL {
                for app in NSWorkspace.shared.runningApplications {
                    if app.bundleURL?.standardizedFileURL == targetURL {
                        app.terminate()
                    }
                }
            }

            var stubbornURLs: [URL] = []
            var failed: [Leftover] = []

            for item in targets {
                if item.category == .app,
                   !Self.applicationIdentityMatches(
                    item.url, appIdentity: targetIdentity,
                    infoIdentity: targetInfoIdentity) {
                    failed.append(item)
                    continue
                }
                guard Self.removalIsStillSafe(
                    item.url, expectedIdentity: item.fileIdentity,
                    allowedPaths: allowed, targetURL: targetURL) else {
                    failed.append(item)
                    continue
                }
                let resolvedURL = item.url.resolvingSymlinksInPath()
                do {
                    try fm.trashItem(at: resolvedURL, resultingItemURL: nil)
                } catch {
                    stubbornURLs.append(resolvedURL)
                }
            }

            if !stubbornURLs.isEmpty {
                let stillSafe = stubbornURLs.filter { url in
                    !UninstallerSupport.isSymbolicLink(url) && fm.fileExists(atPath: url.path)
                }
                Self.trashViaFinder(stillSafe)
            }

            var freed: Int64 = 0
            for item in targets where !failed.contains(where: { $0.id == item.id }) {
                if !fm.fileExists(atPath: item.url.path) {
                    freed += item.size
                } else {
                    failed.append(item)
                }
            }

            DispatchQueue.main.async {
                guard let self, self.phase == .removing else { return }
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    /// Asks Finder to trash `urls` in one batch. Finder owns the privilege
    /// elevation (the standard administrator prompt) and the result is a
    /// reversible move to the Trash, never a permanent delete. Waits until the
    /// user answers the prompt; a cancel simply leaves the items in place.
    private static func trashViaFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return }
        // In-process Apple Events (see AppleScriptRunner): the Finder Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Paths are embedded as
        // escaped string literals (no argv).
        let targets = urls
            .map { "set end of targets to POSIX file \(AppleScriptRunner.literal($0.path))" }
            .joined(separator: "\n")
        let source = """
        set targets to {}
        \(targets)
        tell application "Finder" to delete targets
        """
        _ = AppleScriptRunner.run(source)
    }

    // MARK: - Scanning

    private static func collect(appURL: URL,
                                primaryBundleID: String,
                                exclusiveBundleIDs: Set<String>,
                                teamIDs: Set<String>,
                                exclusiveGroupIDs: Set<String>) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var paths = [ScanCandidate(url: appURL, category: .app,
                                   ownerBundleID: nil, ownerGroupID: nil,
                                   evidenceBundleID: nil,
                                   confidence: .exact, include: true)]
        let bundle = Bundle(url: appURL)
        var displayNames = UninstallerSupport.displayNames(
            localizedName: fm.displayName(atPath: appURL.path),
            fileName: appURL.lastPathComponent,
            bundleName: bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundleDisplayName: bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        )
        if let executable = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            displayNames.append(executable)
        }
        let identity = UninstallerSupport.identity(
            primaryBundleID: primaryBundleID,
            bundleIDs: exclusiveBundleIDs,
            displayNames: displayNames,
            teamIDs: teamIDs,
            groupIDs: exclusiveGroupIDs
        )
        let allowedRoots = scanRoots(home: home)

        for folder in UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: home, isDirectory: true),
            darwinCache: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            darwinTemp: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        ) {
            appendMatches(in: folder, identity: identity, fm: fm, into: &paths)
        }
        appendSpotlightMatches(identity: identity, roots: spotlightRoots(home: home),
                               fm: fm, into: &paths)

        // Last line of defense: nothing outside the scanned roots (or the app
        // bundle itself) may ever reach the removal list.
        let appPath = appURL.standardizedFileURL.path
        let safe = dedupe(paths).filter { candidate in
            let path = candidate.url.standardizedFileURL.path
            if path == appPath {
                return !UninstallerSupport.isSymbolicLink(candidate.url)
            }
            guard let root = allowedRoots.first(where: { path.hasPrefix($0.path + "/") }) else {
                return false
            }
            return UninstallerSupport.removalPathIsSafe(candidate.url, within: root)
        }
        return safe
            .compactMap { candidate -> Leftover? in
                guard let fileIdentity = UninstallerSupport.fileIdentity(at: candidate.url) else {
                    return nil
                }
                return Leftover(url: candidate.url, category: candidate.category,
                                size: directorySize(of: candidate.url, fm: fm),
                                ownerBundleID: candidate.ownerBundleID,
                                ownerGroupID: candidate.ownerGroupID,
                                evidenceBundleID: candidate.evidenceBundleID,
                                confidence: candidate.confidence,
                                fileIdentity: fileIdentity,
                                include: candidate.include)
            }
            .sorted { ($0.category.sortRank, -$0.size) < ($1.category.sortRank, -$1.size) }
    }

    private static func appendMatches(in folder: UninstallerSupport.SearchFolder,
                                      identity: UninstallerSupport.Identity,
                                      fm: FileManager,
                                      into paths: inout [ScanCandidate]) {
        let listings = dirListings(at: folder.url, remainingDepth: folder.extraChildDepth, fm: fm)
        guard !listings.isEmpty else { return }
        let category = category(for: folder.kind)
        let matchingIdentity: UninstallerSupport.Identity
        if folder.requiresSignedGroup {
            matchingIdentity = UninstallerSupport.Identity(
                bundleIDs: [], nameTokens: [], teamIDs: [], groupIDs: identity.groupIDs)
        } else {
            matchingIdentity = folder.allowsNameMatches
                ? identity : UninstallerSupport.technicalIdentity(identity)
        }
        var claimed = Set<String>()
        for hit in UninstallerSupport.leftoverHitRecords(
            listings: listings,
            identity: matchingIdentity,
            extraChildDepth: folder.extraChildDepth,
            crashReporter: folder.crashReporter
        ) {
            claimed.insert(hit.path)
            appendHit(hit, folder: folder.url, category: category, identity: matchingIdentity,
                      crashReporter: folder.crashReporter, into: &paths)
        }
        if folder.readsContainerMetadata {
            appendContainerMetadataMatches(
                listings: listings, folder: folder.url, category: category,
                identity: matchingIdentity, claimedPaths: claimed, into: &paths)
        }
    }

    private static func appendHit(_ hit: UninstallerSupport.Hit,
                                  folder: URL,
                                  category: Category,
                                  identity: UninstallerSupport.Identity,
                                  crashReporter: Bool,
                                  into paths: inout [ScanCandidate]) {
        let url = folder.appendingPathComponent(hit.path)
        let groupID = UninstallerSupport.matchingGroupID(
            url.lastPathComponent, identity: identity)
        let evidence = hit.bundleIdentifier
            ?? (groupID == nil
                ? CleanerSupport.bundleIDCandidate(fromEntryName: url.lastPathComponent) : nil)
        let owner = groupID == nil
            ? (UninstallerSupport.ownerBundleID(
                for: evidence ?? url.lastPathComponent,
                identity: identity, crashReporter: crashReporter)
                ?? identity.bundleIDs.min(by: { $0.count < $1.count }))
            : nil
        guard owner != nil || groupID != nil else { return }
        paths.append(ScanCandidate(url: url, category: category,
                                   ownerBundleID: owner, ownerGroupID: groupID,
                                   evidenceBundleID: evidence,
                                   confidence: hit.confidence,
                                   include: hit.confidence == .exact))
    }

    private static func appendContainerMetadataMatches(
        listings: [UninstallerSupport.DirListing],
        folder: URL,
        category: Category,
        identity: UninstallerSupport.Identity,
        claimedPaths: Set<String>,
        into paths: inout [ScanCandidate]
    ) {
        for listing in listings where !claimedPaths.contains(listing.name) {
            guard let owner = containerMetadataOwner(at: folder.appendingPathComponent(listing.name))
            else { continue }
            let match = UninstallerSupport.containerMetadataMatches(owner, identity: identity)
            guard match != .none else { continue }
            let groupID = UninstallerSupport.matchingGroupID(owner, identity: identity)
            let evidence = groupID == nil ? CleanerSupport.bundleIDCandidate(fromEntryName: owner) : nil
            let ownerID = groupID == nil
                ? (UninstallerSupport.ownerBundleID(for: evidence ?? owner, identity: identity)
                    ?? identity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard ownerID != nil || groupID != nil else { continue }
            paths.append(ScanCandidate(url: folder.appendingPathComponent(listing.name),
                                       category: category, ownerBundleID: ownerID,
                                       ownerGroupID: groupID, evidenceBundleID: evidence,
                                       confidence: match, include: match == .exact))
        }
    }

    private static func containerMetadataOwner(at url: URL) -> String? {
        let plist = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let dict = NSDictionary(contentsOf: plist),
              let owner = dict["MCMMetadataIdentifier"] as? String else { return nil }
        return owner
    }

    private static func dirListings(at url: URL, remainingDepth: Int, fm: FileManager)
        -> [UninstallerSupport.DirListing] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let entries = try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: Array(keys),
                                                        options: []) else { return [] }
        var result: [UninstallerSupport.DirListing] = []
        for item in entries {
            let name = item.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let values = try? item.resourceValues(forKeys: keys)
            guard values?.isSymbolicLink != true else { continue }
            let isPackage = values?.isPackage == true
                || packageExtensions.contains(item.pathExtension.lowercased())
            let isDir = values?.isDirectory == true
            let id = isPackage ? Bundle(url: item)?.bundleIdentifier : nil
            let children: [UninstallerSupport.DirListing]
            if isDir, !isPackage, remainingDepth > 0 {
                children = dirListings(at: item, remainingDepth: remainingDepth - 1, fm: fm)
            } else {
                children = []
            }
            result.append(UninstallerSupport.DirListing(
                name: name, children: children, bundleIdentifier: id))
        }
        return result
    }

    private static func appendSpotlightMatches(identity: UninstallerSupport.Identity,
                                               roots: [URL],
                                               fm: FileManager,
                                               into paths: inout [ScanCandidate]) {
        guard let expression = UninstallerSupport.leftoverSpotlightExpression(identity: identity)
        else { return }
        let scopes = roots.map(\.path).filter { fm.fileExists(atPath: $0) }
        guard !scopes.isEmpty,
              let query = MDQueryCreate(kCFAllocatorDefault, expression as CFString, nil, nil)
        else { return }
        MDQuerySetMaxCount(query, 200)
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return }
        let count = min(MDQueryGetResultCount(query), 200)
        var added = 0
        for index in 0..<count {
            guard added < 80,
                  let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  UninstallerSupport.leftoverSpotlightPathIsAllowed(path, roots: roots)
            else { continue }
            let url = URL(fileURLWithPath: path)
            let matchingIdentity = UninstallerSupport.spotlightIdentity(for: path, identity: identity)
            let match = UninstallerSupport.leftoverMatch(
                url.lastPathComponent, identity: matchingIdentity)
            guard match != .none else { continue }
            let groupID = UninstallerSupport.matchingGroupID(
                url.lastPathComponent, identity: matchingIdentity)
            let evidence = groupID == nil
                ? CleanerSupport.bundleIDCandidate(fromEntryName: url.lastPathComponent) : nil
            let owner = groupID == nil
                ? (UninstallerSupport.ownerBundleID(
                    for: evidence ?? url.lastPathComponent, identity: matchingIdentity)
                    ?? matchingIdentity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard owner != nil || groupID != nil else { continue }
            paths.append(ScanCandidate(url: url, category: category(forPath: path),
                                       ownerBundleID: owner, ownerGroupID: groupID,
                                       evidenceBundleID: evidence,
                                       confidence: match, include: false))
            added += 1
        }
    }

    private static func category(forPath path: String) -> Category {
        if path.contains("/Caches") { return .caches }
        if path.contains("/Preferences") { return .preferences }
        if path.contains("/Group Containers") || path.contains("/Containers") { return .containers }
        if path.contains("/Logs") { return .logs }
        if path.contains("/Saved Application State") { return .state }
        if path.contains("/Application Support") { return .support }
        return .other
    }

    private static func codeSigningIdentity(at appURL: URL,
                                            requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return ([], []) }
        if requireValidSignature,
           SecStaticCodeCheckValidity(staticCode, [], nil) != errSecSuccess {
            return ([], [])
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info else { return ([], []) }
        let dict = info as NSDictionary
        var teamIDs: Set<String> = []
        if let team = dict[kSecCodeInfoTeamIdentifier] as? String {
            teamIDs.insert(team)
        }
        var groupIDs: Set<String> = []
        if let entitlements = dict[kSecCodeInfoEntitlementsDict] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            groupIDs.formUnion(groups.filter { !$0.isEmpty })
        }
        return (teamIDs, groupIDs)
    }

    /// Main app plus owned executable extensions. Resource bundles and
    /// arbitrary nested apps are excluded because their identifiers may be
    /// shared by unrelated products.
    private static func signingIdentity(in appURL: URL,
                                        requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        if requireValidSignature, !codeSignatureIsValid(at: appURL) {
            return ([], [])
        }
        var result = codeSigningIdentity(at: appURL,
                                         requireValidSignature: requireValidSignature)
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL) else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            let nested = codeSigningIdentity(at: url,
                                             requireValidSignature: requireValidSignature)
            result.teamIDs.formUnion(nested.teamIDs)
            result.groupIDs.formUnion(nested.groupIDs)
        }
        return result
    }

    private static func codeSignatureIsValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    private static func category(for kind: UninstallerSupport.Kind) -> Category {
        switch kind {
        case .support: return .support
        case .caches: return .caches
        case .preferences: return .preferences
        case .containers: return .containers
        case .logs: return .logs
        case .state: return .state
        case .other: return .other
        }
    }

    private static func knownApplicationURLs(candidateBundleIDs: Set<String>) -> [URL] {
        var urls = InstalledApps.installedApplications(includeSystemApplications: true).map(\.url)
        urls += NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        for id in candidateBundleIDs {
            urls += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  FileManager.default.fileExists(atPath: resolved.path),
                  seen.insert(resolved.path).inserted else { return nil }
            return resolved
        }
    }

    private static func exclusiveOwnedBundleIDs(in selectedURL: URL,
                                                candidates: Set<String>,
                                                knownApplicationIDs: [(url: URL, bundleID: String)],
                                                requiresCurrentOwnership: Bool = true) -> Set<String> {
        var eligible = candidates
        if requiresCurrentOwnership {
            let current = allBundleIDs(in: selectedURL, fm: .default)
            eligible = Set(candidates.filter { candidate in
                current.contains(where: {
                    $0.caseInsensitiveCompare(candidate) == .orderedSame
                })
            })
        }
        return UninstallerSupport.exclusiveBundleIDs(candidates: eligible,
                                                    selectedURL: selectedURL,
                                                    knownApplications: knownApplicationIDs)
    }

    private static func applicationBundleIdentifiers(in urls: [URL]) -> [(url: URL, bundleID: String)] {
        urls.compactMap { url in
            guard let id = UninstallerSupport.verifiedBundleID(Bundle(url: url)?.bundleIdentifier)
            else { return nil }
            return (url, id)
        }
    }

    private static func exclusiveGroupIDs(_ candidates: Set<String>,
                                          selectedURL: URL,
                                          knownApplications: [URL]) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let selectedPath = selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
        var claimedElsewhere = Set<String>()
        for url in knownApplications {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != selectedPath, !path.hasPrefix(selectedPath + "/") else { continue }
            let groups = signingIdentity(in: url, requireValidSignature: false).groupIDs
            claimedElsewhere.formUnion(groups.intersection(candidates))
            if claimedElsewhere == candidates { break }
        }
        return candidates.subtracting(claimedElsewhere)
    }

    private static func removalIsStillSafe(_ url: URL,
                                           expectedIdentity: UninstallerSupport.FileIdentity,
                                           allowedPaths: Set<String>,
                                           targetURL: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        guard allowedPaths.contains(path), let targetURL,
              UninstallerSupport.fileIdentity(at: url) == expectedIdentity else { return false }
        if path == targetURL.standardizedFileURL.path {
            return !UninstallerSupport.isSymbolicLink(url)
        }
        guard let root = scanRoots(home: NSHomeDirectory()).first(where: {
            path.hasPrefix($0.path + "/")
        }) else { return false }
        return UninstallerSupport.removalPathIsSafe(url, within: root)
    }

    private static func applicationIdentityMatches(
        _ url: URL,
        appIdentity: UninstallerSupport.FileIdentity?,
        infoIdentity: UninstallerSupport.FileIdentity?
    ) -> Bool {
        guard let appIdentity, let infoIdentity,
              UninstallerSupport.fileIdentity(at: url) == appIdentity else { return false }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        return UninstallerSupport.fileIdentity(at: infoURL) == infoIdentity
            && UninstallerSupport.removalPathIsSafe(infoURL, within: url)
    }

    private static func allBundleIDs(in appURL: URL, fm: FileManager) -> Set<String> {
        var result = Set<String>()
        if let primary = UninstallerSupport.verifiedBundleID(Bundle(url: appURL)?.bundleIdentifier) {
            result.insert(primary)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL),
                  let id = UninstallerSupport.verifiedBundleID(Bundle(url: url)?.bundleIdentifier)
            else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            result.insert(id)
        }
        return result
    }

    private static func ownedEmbeddedCode(_ url: URL, in appURL: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "appex", "xpc":
            return true
        case "app":
            let loginItems = appURL.appendingPathComponent(
                "Contents/Library/LoginItems", isDirectory: true).standardizedFileURL.path
            return url.standardizedFileURL.path.hasPrefix(loginItems + "/")
        default:
            return false
        }
    }

    private static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "webplugin",
        "prefpane", "qlgenerator", "mdimporter", "service", "saver",
        "colorpicker", "wdgt", "component", "vst", "vst3", "clap", "dpm",
        "aaxplugin", "dictionary", "action", "workflow", "mailbundle",
    ]

    private static func scanRoots(home: String) -> [URL] {
        var roots = [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: home + "/.config", isDirectory: true),
            URL(fileURLWithPath: home + "/.cache", isDirectory: true),
            URL(fileURLWithPath: home + "/.local/share", isDirectory: true),
            URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ]
        if let cache = darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR) { roots.append(cache) }
        if let temp = darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR) { roots.append(temp) }
        return roots.map(\.standardizedFileURL)
    }

    private static func spotlightRoots(home: String) -> [URL] {
        [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ].map(\.standardizedFileURL)
    }

    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true).standardizedFileURL
    }

    /// Drops exact duplicates and any path nested inside another already found.
    /// An exact match upgrades a related one already recorded at the same path.
    private static func dedupe(_ paths: [ScanCandidate]) -> [ScanCandidate] {
        var seen = Set<String>()
        var roots: [String] = []
        var out: [ScanCandidate] = []
        let exactPaths = paths.filter { $0.confidence == .exact }
            .map { $0.url.standardizedFileURL.path }
        for candidate in paths.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let path = candidate.url.standardizedFileURL.path
            if candidate.confidence == .related,
               exactPaths.contains(where: { $0.hasPrefix(path + "/") }) {
                continue
            }
            if let index = out.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                let include = out[index].include || candidate.include
                if out[index].confidence != .exact, candidate.confidence == .exact {
                    out[index] = candidate
                }
                out[index].include = include
                continue
            }
            if seen.contains(path) { continue }
            if roots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            seen.insert(path)
            roots.append(path)
            out.append(candidate)
        }
        return out
    }

    private static func directorySize(of url: URL, fm: FileManager) -> Int64 {
        if UninstallerSupport.isSymbolicLink(url) { return fileSize(url) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                          options: [], errorHandler: nil) {
            for case let item as URL in enumerator {
                if UninstallerSupport.isSymbolicLink(item) {
                    enumerator.skipDescendants()
                    continue
                }
                total += fileSize(item)
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}
