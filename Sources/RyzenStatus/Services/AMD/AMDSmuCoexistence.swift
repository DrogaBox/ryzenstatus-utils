// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import IOKit

/// Detects another driver that drives the same AMD SMU mailbox.
///
/// Our kext reaches the SMU through the SMN index/data pair at PCI config
/// 0x60/0x64 of the AMD host bridge (00:00.0) and serializes its commands
/// with `smuCmdLock`, waiting for the mailbox to be idle first. Another kext
/// on the host bridge can reach the same mailbox registers (message, response,
/// arguments) through its own SMN pair and its own lock, and may not wait for
/// the mailbox to be idle, so a command of ours can have its arguments or its
/// response overwritten. No lock can be shared with code we do not own, so the
/// app yields instead: while a foreign client is attached, the SMU write
/// selectors are refused and readings continue.
enum AMDSmuCoexistence {

    /// Bundle identifiers the project ships. Forks with another identifier
    /// are not ours, but the `wtf.spinach.` prefix catches our own variants.
    static let ownBundleIdentifiers: Set<String> = [
        "wtf.spinach.AMDRyzenCPUPowerManagement",
        "wtf.spinach.SMCAMDProcessor",
        "wtf.spinach.AMDCCDScheduler",
    ]

    /// True for a registry client that is neither ours nor Apple's.
    ///
    /// The PCI nubs themselves (`IOPCIDevice`, `IOPCIBridge`) are the bus,
    /// not a driver using the SMU, so they are ignored. A client with neither
    /// a bundle identifier nor a class cannot be named and is ignored too.
    static func isForeignClient(bundle: String?, ioClass: String?) -> Bool {
        let bundleID = bundle ?? ""
        let className = ioClass ?? ""
        if bundleID.isEmpty && className.isEmpty { return false }
        if bundleID.hasPrefix("com.apple.") || className.hasPrefix("Apple") { return false }
        if ownBundleIdentifiers.contains(bundleID) { return false }
        if bundleID.hasPrefix("wtf.spinach.") { return false }
        if className == "IOPCIDevice" || className == "IOPCIBridge" { return false }
        return true
    }

    /// Every third-party client attached to the AMD host bridge, by bundle
    /// identifier (or IOKit class when it has no identifier), sorted.
    ///
    /// Called at launch, after wake and before an SMU write. Reads the
    /// registry through IOKit only; no shell commands.
    static func foreignDriverNames() -> [String] {
        guard let matching = IOServiceMatching("IOPCIDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var names = Set<String>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard isAMDHostBridge(service) else { continue }

            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(children) }

            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                let bundleID = stringProperty(child, "CFBundleIdentifier")
                let ioClass = stringProperty(child, "IOClass")
                guard isForeignClient(bundle: bundleID, ioClass: ioClass) else { continue }
                if let bundleID, !bundleID.isEmpty {
                    names.insert(bundleID)
                } else if let ioClass, !ioClass.isEmpty {
                    names.insert(ioClass)
                }
            }
        }
        return names.sorted()
    }

    /// True when `selector` is one of the mailbox writes the app must not
    /// send while another driver shares the SMU.
    ///
    /// `AMDKextSelector.isSMUMailboxWrite` owns the list; the registry scan
    /// runs only for those selectors, so reads pay a single enum lookup.
    static func blocksWrites(for selector: UInt32) -> Bool {
        guard AMDKextSelector(rawValue: selector)?.isSMUMailboxWrite == true else { return false }
        return !foreignDriverNames().isEmpty
    }

    // MARK: - Registry helpers

    /// AMD (vendor 0x1022) PCI class 0x0600: the host bridge that owns the
    /// SMN window. The host bridge is 00:00.0 on these platforms.
    private static func isAMDHostBridge(_ entry: io_registry_entry_t) -> Bool {
        guard u32Property(entry, "vendor-id") == 0x1022,
              let classCode = u32Property(entry, "class-code") else { return false }
        return (classCode >> 16) & 0xFF == 0x06 && (classCode >> 8) & 0xFF == 0x00
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func u32Property(_ entry: io_registry_entry_t, _ key: String) -> UInt32? {
        guard let data = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data, data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(4))
        return UInt32(bytes[0]) | UInt32(bytes[1]) << 8
             | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }
}
