// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Centralizes file writes and directory creation for user-private data
/// (clipboard history, shelf files, recording links, scratchpad).
///
/// The macOS sandbox gives each app a private Application Support container,
/// but the OS itself does not tighten the POSIX mode bits it uses when the
/// directory is first created. An earlier installation may have left those
/// directories world-readable. Every `write` and `createDirectory` call here
/// sets 0o700 on directories and 0o600 on files — owner-only, same as
/// Keychain entries — and walks upward from the written leaf to the container
/// root to tighten any parent that a previous version left wide open.
enum PrivateFileStore {

    // MARK: - Container

    /// The Application Support sub-folder for this bundle. All private data
    /// lives under it so the tightening walk can stop here.
    static var containerURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    // MARK: - Directory creation

    /// Creates `url` (and any intermediate directories), then tightens the
    /// POSIX permissions of every component up to and including the container.
    @discardableResult
    static func createDirectory(at url: URL,
                                container: URL? = containerURL) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: url,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        tighten(directoriesToTighten(from: url, container: container ?? url))
        return true
    }

    // MARK: - File writing

    /// Writes `data` atomically to `url` and sets the file mode to 0o600.
    /// The parent directory and the container are tightened as well.
    @discardableResult
    static func write(_ data: Data, to url: URL, container: URL? = containerURL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: url.path)
        } catch {
            return false
        }
        tighten(directoriesToTighten(from: url.deletingLastPathComponent(),
                                     container: container ?? url.deletingLastPathComponent()))
        return true
    }

    // MARK: - Tightening helpers (internal for testing)

    /// The ordered list of directory URLs that need their modes tightened,
    /// starting from `from` and walking upward until `container` (inclusive).
    static func directoriesToTighten(from url: URL, container: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        let root = container.standardizedFileURL
        // Guard: don't walk past the container into system directories.
        guard current.path.hasPrefix(root.path) else {
            return [current]
        }
        while true {
            result.append(current)
            if current.path == root.path { break }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break } // filesystem root guard
            current = parent
        }
        return result
    }

    private static func tighten(_ urls: [URL]) {
        let manager = FileManager.default
        for url in urls {
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
}
