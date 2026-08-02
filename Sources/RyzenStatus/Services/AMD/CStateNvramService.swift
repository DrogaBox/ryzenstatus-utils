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
        toggleBootArg(key: "-amdpnopchk", targetState: !isPnopchkEnabled, featureName: "Privilege Check Bypass (-amdpnopchk)")
    }

    private func toggleBootArg(key: String, targetState: Bool, featureName: String) {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil

        let updatedArgs = Self.modifiedBootArgs(current: currentBootArgs, key: key, enable: targetState)

        DispatchQueue.global(qos: .userInitiated).async {
            let success = Self.writeBootArgs(updatedArgs)
            Task { @MainActor in
                self.isUpdating = false
                if success {
                    self.refresh()
                    self.promptForReboot(featureName: featureName, enabled: targetState)
                } else {
                    self.errorMessage = "No se pudo actualizar la NVRAM. Verificá los permisos del sistema."
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

    nonisolated static func writeBootArgs(_ newArgs: String) -> Bool {
        let script = "nvram boot-args=\"\(newArgs)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/usr/sbin/nvram", "boot-args=\(newArgs)"]
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
            return executeWithAuthorization(script: script)
        } catch {
            return executeWithAuthorization(script: script)
        }
    }

    nonisolated private static func executeWithAuthorization(script: String) -> Bool {
        let appleScript = "do shell script \"\(script)\" with administrator privileges"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            _ = scriptObject.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }

    private func promptForReboot(featureName: String, enabled: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "NVRAM Boot-Args Actualizado"
        let statusStr = enabled ? "Activado" : "Desactivado"
        alert.informativeText = "Se configuró '\(featureName)' como '\(statusStr)' en los boot-args de la NVRAM. Se requiere reiniciar la Mac para aplicar los cambios en el kernel."
        alert.addButton(withTitle: "Reiniciar Ahora")
        alert.addButton(withTitle: "Reiniciar Luego")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Self.rebootSystem()
        }
    }

    private static func rebootSystem() {
        let script = "tell application \"System Events\" to restart"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
