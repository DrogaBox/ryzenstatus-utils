// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

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
            let c6 = args.contains("amdcstate=0")
            let cppc = args.contains("-amdcppcactive")
            let pnopchk = args.contains("-amdpnopchk")

            await MainActor.run {
                self.currentBootArgs = args
                self.isC6Enabled = c6
                self.isCppcActiveEnabled = cppc
                self.isPnopchkEnabled = pnopchk
            }
        }
    }

    /// Constructs the recommended AMD boot-args string based on current NVRAM state.
    /// This string is for pasting into your bootloader config.plist — the app
    /// never writes to NVRAM directly.
    var amdBootArgsString: String {
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        return str
    }

    // MARK: - Read Helpers

    nonisolated static func readBootArgs() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        task.arguments = ["boot-args"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
