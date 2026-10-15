// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Darwin
import Foundation

/// A mounted file share (SMB, AFP, NFS, WebDAV…).
struct NetworkVolume: Identifiable, Equatable {
    /// Where it is mounted, e.g. "/Volumes/Media".
    let mountPoint: String
    /// What is mounted, e.g. "//user@nas.local/Media".
    let source: String
    let fileSystem: String
    let totalBytes: UInt64
    let availableBytes: UInt64

    var id: String { mountPoint }
    var name: String { (mountPoint as NSString).lastPathComponent }

    /// The server part of `source`, without the user: "nas.local".
    var server: String {
        var rest = Substring(source)
        if rest.hasPrefix("//") { rest = rest.dropFirst(2) }
        if let slash = rest.firstIndex(of: "/") { rest = rest[..<slash] }
        if let at = rest.lastIndex(of: "@") { rest = rest[rest.index(after: at)...] }
        if let colon = rest.firstIndex(of: ":"), fileSystem == "nfs" { rest = rest[..<colon] }
        return String(rest)
    }

    var usedFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(totalBytes - min(availableBytes, totalBytes)) / Double(totalBytes)
    }

    /// File systems that reach another machine.
    static let networkFileSystems: Set<String> = ["smbfs", "afpfs", "nfs", "webdav", "cifs", "ftp"]

    /// A volume from one `statfs` entry, or nil when it is local.
    init?(fileSystem: String, mountPoint: String, source: String,
          blockSize: UInt64, blocks: UInt64, availableBlocks: UInt64, isLocal: Bool) {
        guard !isLocal, Self.networkFileSystems.contains(fileSystem) else { return nil }
        self.fileSystem = fileSystem
        self.mountPoint = mountPoint
        self.source = source
        totalBytes = blocks.multipliedReportingOverflow(by: blockSize).overflow ? 0 : blocks &* blockSize
        availableBytes = availableBlocks.multipliedReportingOverflow(by: blockSize).overflow ? 0 : availableBlocks &* blockSize
    }

    /// The network volumes mounted now. Uses the kernel's cached figures
    /// (MNT_NOWAIT), so a server that stopped answering cannot stall it.
    static func mounted() -> [NetworkVolume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        // `statfs` names both the struct and a function, so the array is
        // spelled out and filled in place by the kernel.
        let entries = Array<statfs>(unsafeUninitializedCapacity: Int(count)) { buffer, initialized in
            let filled = getfsstat(buffer.baseAddress, Int32(buffer.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
            initialized = max(0, min(Int(filled), buffer.count))
        }
        return entries.compactMap { entry in
            var entry = entry
            return NetworkVolume(fileSystem: string(&entry.f_fstypename),
                                 mountPoint: string(&entry.f_mntonname),
                                 source: string(&entry.f_mntfromname),
                                 blockSize: UInt64(entry.f_bsize),
                                 blocks: entry.f_blocks,
                                 availableBlocks: entry.f_bavail,
                                 isLocal: entry.f_flags & UInt32(MNT_LOCAL) != 0)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func string<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
