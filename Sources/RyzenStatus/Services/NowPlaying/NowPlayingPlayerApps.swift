// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

/// The music app opened when nothing is playing and a playback button or
/// the cover is clicked. Opening it never starts playback.
enum NowPlayingPreferredPlayer {
    /// Stored when the choice is left automatic.
    static let automatic = ""
    static let known = ["com.spotify.client", "com.apple.Music"]
    /// The music app that last played in this launch of the app. Not saved:
    /// it names what the person was listening to, not a setting.
    static var lastPlayed: String?

    static func choice(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: DefaultsKey.notchPreferredPlayer) ?? automatic
        return value.utf8.count <= 256 ? value : automatic
    }

    /// A chosen player wins while it is installed. Otherwise the music app
    /// that played last, then Spotify, then Apple Music.
    static func resolve(choice: String, lastPlayed: String?, isInstalled: (String) -> Bool) -> String? {
        if !choice.isEmpty, isInstalled(choice) { return choice }
        if let lastPlayed, isInstalled(lastPlayed) { return lastPlayed }
        return known.first(where: isInstalled)
    }

    static func current() -> String? {
        resolve(choice: choice(), lastPlayed: lastPlayed) { InstalledApps.url(for: $0) != nil }
    }

    /// Called by `NowPlayingService` on every reading: a known music app
    /// that is playing becomes the one to open next.
    static func remember(_ playback: NowPlayingPlayback?) {
        guard let playback, playback.isPlaying, let bundle = playback.track.appBundleIdentifier,
              known.contains(bundle) else { return }
        lastPlayed = bundle
    }

    typealias Choice = (bundleID: String, name: String)

    /// The installed choices are a snapshot. A saved choice stays available
    /// before the scan finishes, or when its app is no longer installed.
    static func choices(in installed: [Choice], including chosen: String) -> [Choice] {
        guard !chosen.isEmpty, !installed.contains(where: { $0.bundleID == chosen }) else { return installed }
        return installed + [(chosen, chosen)]
    }

    /// Scan away from the view's main thread. A task that left the screen
    /// while the scan ran cannot publish its late result.
    static func loadInstalled(using load: @escaping @Sendable () -> [Choice] = { installed() }) async -> [Choice]? {
        guard !Task.isCancelled else { return nil }
        let choices = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: load())
            }
        }
        return Task.isCancelled ? nil : choices
    }

    /// The known players that are installed, and any other music app.
    static func installed() -> [Choice] {
        var ids = known.filter { InstalledApps.url(for: $0) != nil }
        for app in InstalledApps.installedApplications(includeSystemApplications: true) {
            guard let id = app.bundleID, !ids.contains(id),
                  Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String == "public.app-category.music"
            else { continue }
            ids.append(id)
        }
        return ids.map { ($0, InstalledApps.name(for: $0)) }
    }

    /// "Open Spotify", for the tooltip and VoiceOver of what opens it.
    static func openTitle(for id: String) -> String {
        return String(format: FeatureStrings.notchMusicExtras(L10n.shared.language).openNamedPlayer, InstalledApps.name(for: id))
    }

    /// Opens the player, once; a second click while it launches is ignored by
    /// Launch Services.
    @discardableResult
    static func open() -> Bool {
        guard let id = current(), let url = InstalledApps.url(for: id), Bundle(url: url)?.bundleIdentifier == id else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

/// The app that owns a reading: its name, and bringing it forward.
enum NowPlayingApplication {
    static func runningApplication(for snapshot: NowPlayingTrack) -> NSRunningApplication? {
        if let bundleIdentifier = snapshot.appBundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return application
        }
        if let pid = snapshot.appPID {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
    }

    private static var icons: [String: NSImage] = [:]
    private static var missingIcons = Set<String>()

    /// The player's own icon, shown in place of a cover the player does not
    /// send (Firefox and Zen, for instance), so the song still says where it
    /// plays. Read once per player and remembered.
    static func icon(for track: NowPlayingTrack) -> NSImage? {
        let key = track.appBundleIdentifier ?? track.appPID.map { "pid:\($0)" } ?? ""
        if let icon = icons[key] { return icon }
        if missingIcons.contains(key) { return nil }
        let icon: NSImage?
        if let runningIcon = runningApplication(for: track)?.icon {
            icon = runningIcon
        } else if let identifier = track.appBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = nil
        }
        if let icon {
            icons[key] = icon
        } else {
            missingIcons.insert(key)
        }
        return icon
    }

    static func name(for snapshot: NowPlayingTrack) -> String? {
        if let name = runningApplication(for: snapshot)?.localizedName, !name.isEmpty { return name }
        guard let identifier = snapshot.appBundleIdentifier else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    static func open(_ snapshot: NowPlayingTrack) {
        if let application = runningApplication(for: snapshot) {
            guard application.activationPolicy == .regular else { return }
            if application.isHidden { application.unhide() }
            application.activate(options: [.activateAllWindows])
            if let url = application.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
