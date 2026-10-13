// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Foundation

/// A Focus as the island names it: the name and symbol the person gave it in
/// System Settings when those can be read, otherwise the system's own.
struct NotchFocusMode: Equatable {
    let identifier: String
    let name: String
    let symbol: String
}

enum NotchFocusSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.routes(.focus, in: defaults)
    }

    /// The system's symbol for a built-in Focus, by its mode identifier.
    static func symbol(for identifier: String) -> String {
        let table: [(String, String)] = [
            ("sleep", "bed.double.fill"), ("driving", "car.fill"), ("workout", "figure.run"),
            ("fitness", "figure.run"), ("work", "person.lanyardcard.fill"), ("personal", "person.fill"),
            ("reading", "book.fill"), ("mindfulness", "brain.head.profile"), ("gaming", "gamecontroller.fill"),
            ("reduce-interruptions", "bell.badge.slash.fill")
        ]
        let lower = identifier.lowercased()
        return table.first { lower.hasSuffix("." + $0.0) || lower.hasSuffix("-" + $0.0) }?.1 ?? "moon.fill"
    }

    /// Names and symbols from the Focus configurations System Settings keeps,
    /// keyed by mode identifier. Unreadable or missing, the island falls back
    /// to the system's symbol and a generic name.
    static func configuredModes(at url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")) -> [String: NotchFocusMode] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return [:] }
        var modes: [String: NotchFocusMode] = [:]
        for entry in entries {
            guard let configurations = entry["modeConfigurations"] as? [String: Any] else { continue }
            for (identifier, value) in configurations {
                guard let configuration = value as? [String: Any],
                      let mode = configuration["mode"] as? [String: Any] else { continue }
                let name = (mode["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let symbol = (mode["symbolImageName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? Self.symbol(for: identifier)
                let focus = NotchFocusMode(identifier: identifier, name: name ?? "", symbol: symbol)
                modes[identifier] = focus
                // Log lines may name the mode by its UUID instead.
                if let uuid = mode["identifier"] as? String { modes[uuid] = focus }
            }
        }
        return modes
    }

    /// The mode a log line reports as now active, `""` when it reports none,
    /// or nil when the line says nothing about the active mode.
    static func activeMode(inLogMessage message: String) -> String? {
        nil
    }
}

/// Watches the system log for the Focus becoming active or inactive, the way
/// `log stream` shows it to any user, and shows the change on the island.
/// Nothing is read while the setting is off.
final class NotchFocusService {
    static let shared = NotchFocusService()

    private var process: Process?
    private var pending = Data()
    private var restartWork: DispatchWorkItem?
    /// The active mode's identifier, empty with none, nil before the first report.
    private(set) var active: String?

    func syncWithPreferences() {
        guard NotchFocusSupport.isEnabled() else { stop(); return }
        guard process == nil, restartWork == nil else { return }
        start()
    }

    func stop() {
        restartWork?.cancel(); restartWork = nil
        guard let process else { return }
        self.process = nil
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        pending.removeAll()
        active = nil
    }

    private func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--level", "info",
                             "--predicate", "subsystem == \"com.apple.donotdisturb\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.process = nil
                // The log tool can end with the session; try again shortly.
                let work = DispatchWorkItem { [weak self] in
                    self?.restartWork = nil
                    self?.syncWithPreferences()
                }
                self.restartWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
        }
    }

    private func consume(_ data: Data) {
        guard process != nil, !data.isEmpty else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending.subdata(in: pending.startIndex..<newline)
            pending.removeSubrange(pending.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = object["eventMessage"] as? String,
                  let mode = NotchFocusSupport.activeMode(inLogMessage: message) else { continue }
            report(mode)
        }
        // A line never this long is not one the log tool wrote whole.
        if pending.count > 1 << 20 { pending.removeAll() }
    }

    private func report(_ mode: String) {
        // The log reports changes, not the state at launch: with nothing
        // reported yet, no Focus is taken to have been on.
        let previous = active ?? ""
        active = mode
        guard previous != mode else { return }
        let text = FeatureStrings.notchIslandExtras(L10n.shared.language)
        let modes = NotchFocusSupport.configuredModes()
        let shown = mode.isEmpty ? previous : mode
        let focus = modes[shown]
        let name = focus.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? text.focus
        let symbol = focus?.symbol ?? NotchFocusSupport.symbol(for: shown)
        NotchService.shared.show(NotchNotice(event: .focus, title: name,
                                             detail: mode.isEmpty ? text.focusOff : text.focusOn,
                                             symbol: symbol))
    }
}
