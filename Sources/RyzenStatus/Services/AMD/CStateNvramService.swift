// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// Service to inspect and safely toggle AMD kext `boot-args` in NVRAM:
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
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        let args = Self.readBootArgs()
        currentBootArgs = args
        
        // amdcstate=0 explicitly enables C6 MSR polling in kext
        isC6Enabled = args.contains("amdcstate=0")
        // -amdcppcactive enables CPPC dynamic energy preference mode
        isCppcActiveEnabled = args.contains("-amdcppcactive")
        // -amdpnopchk enables user-space privilege bypass
        isPnopchkEnabled = args.contains("-amdpnopchk")
    }
    /// Constructs string containing only our application's AMD parameters
    var amdBootArgsString: String {
        var items: [String] = []
        if isCppcActiveEnabled { items.append("-amdcppcactive") }
        if isPnopchkEnabled { items.append("-amdpnopchk") }
        items.append(isC6Enabled ? "amdcstate=0" : "amdcstate=1")
        return items.joined(separator: " ")
    }

    /// Copies only our app's AMD parameters string to macOS system pasteboard
    @discardableResult
    func copyAmdArgsToClipboard() -> String {
        let str = amdBootArgsString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        return str
    }

    /// Toggles the C6 boot-arg in NVRAM and offers to reboot the system.
    func toggleCState() {
        toggleBootArg(key: "amdcstate", targetState: !isC6Enabled, featureName: "Deep C-States (C6)")
    }

    /// Toggles `-amdcppcactive` in NVRAM and offers to reboot the system.
    func toggleCppcActive() {
        toggleBootArg(key: "-amdcppcactive", targetState: !isCppcActiveEnabled, featureName: "CPPC Active Mode")
    }

    /// Toggles `-amdpnopchk` in NVRAM and offers to reboot the system.
    func togglePnopchk() {
        toggleBootArg(key: "-amdpnopchk", targetState: !isPnopchkEnabled, featureName: "Bypass Privilegios Root (-amdpnopchk)")
    }

    private func toggleBootArg(key: String, targetState: Bool, featureName: String) {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil

        let updatedArgs = Self.modifiedBootArgs(current: currentBootArgs, key: key, enable: targetState)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.writeBootArgs(updatedArgs)
            Task { @MainActor in
                self.isUpdating = false
                if result.success {
                    self.refresh()
                    self.promptForReboot(featureName: featureName, enabled: targetState)
                } else {
                    let msg = result.error ?? "No se pudo actualizar la NVRAM."
                    self.errorMessage = msg
                    self.promptForError(msg)
                }
            }
        }
    }

    // MARK: - Internal Helpers

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

    nonisolated static func modifiedBootArgs(current: String, key: String, enable: Bool) -> String {
        var tokens = current.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if key == "amdcstate" {
            tokens.removeAll { $0.hasPrefix("amdcstate=") }
            if enable {
                tokens.append("amdcstate=0")
            } else {
                tokens.append("amdcstate=1")
            }
        } else {
            tokens.removeAll { $0 == key }
            if enable {
                tokens.append(key)
            }
        }

        return tokens.joined(separator: " ")
    }

    nonisolated static func writeBootArgs(_ newArgs: String) -> (success: Bool, error: String?) {
        // 1. Try direct nvram call first
        let directTask = Process()
        directTask.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        directTask.arguments = ["boot-args=\(newArgs)"]
        let directErrPipe = Pipe()
        directTask.standardError = directErrPipe

        do {
            try directTask.run()
            directTask.waitUntilExit()
            if directTask.terminationStatus == 0 {
                return (true, nil)
            }
        } catch {}

        // 2. Fallback to osascript with administrator privileges (prompts for Admin password natively)
        let appleScriptCommand = "do shell script \"nvram boot-args=\\\"\(newArgs)\\\"\" with administrator privileges"
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", appleScriptCommand]
        let errorPipe = Pipe()
        osascript.standardError = errorPipe

        do {
            try osascript.run()
            osascript.waitUntilExit()
            if osascript.terminationStatus == 0 {
                return (true, nil)
            }
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, errStr ?? "Cancelado por el usuario o permisos insuficientes.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func promptForReboot(featureName: String, enabled: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "NVRAM Boot-Args Actualizado"
        let statusStr = enabled ? "Activado" : "Desactivado"
        alert.informativeText = "Se configuró '\(featureName)' como '\(statusStr)' en la NVRAM.\n\nboot-args actuales:\n\(currentBootArgs)\n\n¿Deseás reiniciar la Mac ahora para que el kernel aplique los cambios?"
        alert.addButton(withTitle: "Reiniciar Ahora")
        alert.addButton(withTitle: "Reiniciar Luego")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Self.rebootSystem()
        }
    }

    private func promptForError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No se Pudo Modificar la NVRAM"
        alert.informativeText = "Ocurrió el siguiente problema:\n\(message)\n\nVerificá si tu usuario tiene permisos de administrador o si la NVRAM está protegida."
        alert.addButton(withTitle: "Entendido")
        alert.runModal()
    }

    private static func rebootSystem() {
        let script = "tell application \"System Events\" to restart"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}
