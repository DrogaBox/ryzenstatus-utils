// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation
import IOKit

/// Read-only service that reads the current NVRAM `boot-args` and exposes
/// the AMD kext parameter state. To change parameters, use the "Copy AMD
/// Boot-Args" button and paste the string into your bootloader config.plist.
///
/// Parameters tracked (read-only):
/// - `amdcstate=0`/`amdcstate=1`: Deep C-States (C6+)
/// - `-amdcppcactive`: CPPC Energy Performance Preference Mode
/// - `-amdpnopchk`: Root Privilege Check Bypass for Fan & EPP Controls
@MainActor
final class CStateNvramService: ObservableObject {
    static let shared = CStateNvramService()

    @Published private(set) var isC6Enabled: Bool = false
    @Published private(set) var isCppcActiveEnabled: Bool = false
    @Published private(set) var isPnopchkEnabled: Bool = false
    @Published private(set) var currentBootArgs: String = ""

    private init() {
        refresh()
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let args = Self.readBootArgs()
            let flags = Self.amdFlags(inBootArgs: args)

            await MainActor.run {
                self.currentBootArgs = args
                self.isC6Enabled = flags.c6Enabled
                self.isCppcActiveEnabled = flags.cppcActive
                self.isPnopchkEnabled = flags.pnopchk
            }
        }
    }

    /// Constructs the recommended AMD boot-args string based on current NVRAM state.
    /// This string is for pasting into your bootloader config.plist — the app
    /// never writes to NVRAM directly.
    var amdBootArgsString: String {
        Self.formatAmdBootArgs(
            isC6Enabled: isC6Enabled,
            isCppcActiveEnabled: isCppcActiveEnabled,
            isPnopchkEnabled: isPnopchkEnabled
        )
    }

    /// Pure formatter for AMD boot-args string generation.
    nonisolated static func formatAmdBootArgs(
        isC6Enabled: Bool,
        isCppcActiveEnabled: Bool,
        isPnopchkEnabled: Bool
    ) -> String {
        var items: [String] = []
        if isCppcActiveEnabled { items.append("-amdcppcactive") }
        if isPnopchkEnabled    { items.append("-amdpnopchk") }
        items.append(isC6Enabled ? "amdcstate=0" : "amdcstate=1")
        return items.joined(separator: " ")
    }

    /// Copies the AMD parameters string to the macOS system pasteboard.
    /// The user can then paste it into OpenCore Configurator / ProperTree.
    @discardableResult
    func copyAmdArgsToClipboard() -> String {
        let str = amdBootArgsString
        GeneralPasteboardAccess.shared.copyString(str, ownCopy: false)
        return str
    }

    // MARK: - Read Helpers

    /// The AMD kext arguments in a boot-args string, matched as whole
    /// arguments: `-amdpnopchkx` or `amdcstate=01` are not these flags.
    nonisolated static func amdFlags(inBootArgs args: String)
        -> (c6Enabled: Bool, cppcActive: Bool, pnopchk: Bool) {
        let arguments = Set(args.split(whereSeparator: \.isWhitespace).map(String.init))
        return (arguments.contains("amdcstate=0"),
                arguments.contains("-amdcppcactive"),
                arguments.contains("-amdpnopchk"))
    }

    /// boot-args from the NVRAM node of the I/O Registry, the same place
    /// `nvram` reads, without starting a process. Falls back to `nvram` when
    /// the node cannot be read.
    nonisolated static func readBootArgs() -> String {
        let options = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        guard options != 0 else { return readBootArgsWithTool() }
        defer { IOObjectRelease(options) }
        guard let value = IORegistryEntryCreateCFProperty(options, "boot-args" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            // The node is there but boot-args is not set.
            return ""
        }
        if let data = value as? Data {
            return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    nonisolated private static func readBootArgsWithTool() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        task.arguments = ["boot-args"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            // Read before waiting: a child blocked on a full pipe never exits.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let raw = String(data: data, encoding: .utf8) else { return "" }
            if let tabIndex = raw.firstIndex(of: "\t") {
                return String(raw[raw.index(after: tabIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}
