// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import Foundation

@MainActor
final class MacPortsManager: ObservableObject {
    static let shared = MacPortsManager()
    @Published private(set) var available = false
    @Published private(set) var installed: [MacPortsPackage] = []
    @Published private(set) var searchResults: [MacPortsPackage] = []
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var handedOffCommand: String?
    private let queue = DispatchQueue(label: "com.ryzenstatus.macports", qos: .utility)

    private init() {
        available = FileManager.default.isExecutableFile(atPath: MacPortsSupport.executable)
    }

    func refresh() {
        guard !busy else { return }
        available = FileManager.default.isExecutableFile(atPath: MacPortsSupport.executable)
        guard available else { installed = []; return }
        busy = true
        error = nil
        queue.async { [weak self] in
            let result = BoundedProcessRunner.run(MacPortsSupport.executable, ["-q", "installed"],
                                                  timeout: MacPortsSupport.timeout,
                                                  maxOutputBytes: MacPortsSupport.outputLimit)
            let outdated = result.status == 0 ? BoundedProcessRunner.run(
                MacPortsSupport.executable, ["-q", "outdated"], timeout: MacPortsSupport.timeout,
                maxOutputBytes: MacPortsSupport.outputLimit) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard result.status == 0, result.output.count < MacPortsSupport.outputLimit,
                      let outdated, outdated.status == 0, outdated.output.count < MacPortsSupport.outputLimit else {
                    self.error = result.status == 0
                        ? String(decoding: outdated?.output ?? Data(), as: UTF8.self)
                        : String(decoding: result.output, as: UTF8.self)
                    if self.error?.isEmpty != false {
                        self.error = FeatureStrings.packageManager(L10n.shared.language).queryFailed
                    }
                    return
                }
                let updates = MacPortsSupport.outdated(String(decoding: outdated.output, as: UTF8.self))
                self.installed = MacPortsSupport.installed(String(decoding: result.output, as: UTF8.self)).map {
                    var package = $0
                    package.latestVersion = updates[package.name]
                    return package
                }
            }
        }
    }

    func search(_ query: String) {
        guard available, !busy, let arguments = MacPortsSupport.searchArguments(query) else { return }
        busy = true
        error = nil
        queue.async { [weak self] in
            let result = BoundedProcessRunner.run(MacPortsSupport.executable, arguments,
                                                  timeout: MacPortsSupport.timeout,
                                                  maxOutputBytes: MacPortsSupport.outputLimit)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard result.status == 0, result.output.count < MacPortsSupport.outputLimit else {
                    self.error = String(decoding: result.output, as: UTF8.self)
                    if self.error?.isEmpty != false {
                        self.error = FeatureStrings.packageManager(L10n.shared.language).queryFailed
                    }
                    return
                }
                self.searchResults = MacPortsSupport.searchResults(String(decoding: result.output, as: UTF8.self))
            }
        }
    }

    // This is invoked only by the confirmed button in MacPortsView, never
    // by lifecycle/preferences. The password stays in the terminal, not this
    // app. The command opens in the person's own terminal, as Homebrew's do
    // (see `HomebrewTerminalScript`), so no Automation consent is involved.
    func handOff(_ action: MacPortsSupport.Action, package: String?) {
        guard available, !busy,
              let command = MacPortsSupport.shellCommand(action: action, package: package) else { return }
        error = nil
        let script: URL
        do {
            script = try HomebrewTerminalScript.write(command: command)
        } catch {
            self.error = error.localizedDescription
            return
        }
        busy = true
        NSWorkspace.shared.open(script, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let error {
                    // Nothing ran the script, so nothing deleted it.
                    try? FileManager.default.removeItem(at: script)
                    self.error = error.localizedDescription
                } else {
                    self.handedOffCommand = command
                }
                // A successful handoff is NOT a successful package operation.
                // Refresh is explicit after the user completes terminal work.
            }
        }
    }
}
