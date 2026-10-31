// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Darwin
import SwiftUI

/// Rich Process Inspector Sheet displaying full metadata, executable path,
/// memory regions, live CPU/RAM/Network telemetry (updating live at 1Hz), and system actions.
struct ProcessDetailSheet: View {
    let row: ProcessUsage
    /// Whether the window can be seen: the live refresh runs only then.
    @ObservedObject var visibility: ProcessInspectorVisibility
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingTerminateAlert = false
    @State private var pathCopied = false

    /// Read once when the window opens: a kill is refused for any process
    /// that no longer has this start time, so a reused PID is never hit.
    @State private var startedAt: UInt64?
    @State private var path: String?
    @State private var isLeaking = false
    @State private var killing = false
    @State private var killFailed = false

    /// Nil until the process shows up in the CPU list.
    @State private var liveCPUPct: Double?
    @State private var liveRSSStr: String = "—"
    @State private var liveDown: Double = 0.0
    @State private var liveUp: Double = 0.0

    private var glossaryEntry: ProcessGlossaryEntry {
        ProcessGlossary.resolve(name: row.name, pid: row.pid)
    }

    private var strings: ProcessInspectorStrings {
        FeatureStrings.processInspector(l10n.language)
    }

    /// The executable of `pid`, or nil when the system does not say.
    nonisolated static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN)) > 0 else { return nil }
        return String(cString: buffer)
    }

    var body: some View {
        let entry = glossaryEntry
        let strings = strings

        VStack(alignment: .leading, spacing: 14) {
            // --- HEADER BAR ---
            HStack(spacing: 12) {
                Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                    .resizable()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 16, weight: .bold))
                        Text(strings.categoryName(entry.category))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    Text(String(format: strings.pidFormat, row.pid))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    ProcessInspectorWindowController.shared.close()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.s.menuClose)
                .accessibilityLabel(l10n.s.menuClose)
            }

            Divider()

            // Memory Leak Warning Alert Box
            if isLeaking {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.leakTitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                        Text(strings.leakDetail)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            // --- LIVE TELEMETRY CARDS GRID ---
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Card 1: Live CPU Usage
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.cpuLoad)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(liveCPUPct.map { String(format: "%.1f%%", $0) } ?? "—")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor((liveCPUPct ?? 0) > 80.0 ? .red : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Card 2: Live Memory RSS
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.residentMemory)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(liveRSSStr)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Card 3: Live Network Throughput
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.networkIO)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let netText = (liveDown > 0 || liveUp > 0)
                        ? "↓ \(formatKB(liveDown))  ↑ \(formatKB(liveUp))" : strings.networkIdle
                    Text(netText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(liveDown > 0 || liveUp > 0 ? .cyan : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)
            }

            // --- EXECUTABLE PATH PANEL ---
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(strings.executablePath)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()

                    Button {
                        guard let path else { return }
                        GeneralPasteboardAccess.shared.copyString(path, ownCopy: false)
                        pathCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            pathCopied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                            Text(pathCopied ? strings.copied : strings.copyPath)
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(path == nil)

                    Button {
                        guard let path else { return }
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(strings.revealInFinder)
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(path == nil)
                }

                Text(path ?? strings.pathUnavailable)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
            }

            // --- PROCESS GLOSSARY EXPLANATION ---
            VStack(alignment: .leading, spacing: 6) {
                Text(strings.processRole)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(strings.role(entry.category))
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(8)

            Spacer(minLength: 0)

            // --- ACTION BUTTONS ---
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 12) {
                    Button(strings.done) {
                        ProcessInspectorWindowController.shared.close()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)

                    Spacer()

                    Button(strings.terminate, role: .destructive) {
                        showingTerminateAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(killing)
                }
                if killFailed {
                    Text(strings.terminateFailed)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(16)
        .frame(width: 480, height: 420)
        .task {
            // Path and identity once; they do not change for a running process.
            startedAt = KillProcessService.startTime(for: row.pid)
            path = Self.executablePath(of: row.pid)
        }
        // While the window is hidden, occluded or behind the lock screen no
        // `ps` runs and the network sampler is not kept alive.
        .task(id: visibility.isVisible) {
            guard visibility.isVisible else { return }
            while !Task.isCancelled {
                refreshLiveTelemetry()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .alert(String(format: strings.forceQuitTitleFormat, row.name), isPresented: $showingTerminateAlert) {
            Button(strings.cancel, role: .cancel) {}
            Button(strings.forceQuit, role: .destructive) {
                forceQuit()
            }
        } message: {
            Text(String(format: strings.forceQuitMessageFormat, row.pid))
        }
    }

    /// Kills through the shared safe path, which re-checks the start time
    /// right before the signal. A process still there afterwards with the
    /// same start time was not stopped (protected, or refused).
    private func forceQuit() {
        guard let startedAt else { killFailed = true; return }
        killFailed = false
        killing = true
        let pid = row.pid
        KillProcessService.shared.kill(pid: pid, name: row.name, startedAt: startedAt, force: true) {
            killing = false
            if KillProcessService.startTime(for: pid) == startedAt {
                killFailed = true
            } else {
                ProcessInspectorWindowController.shared.close()
                dismiss()
            }
        }
    }

    private func refreshLiveTelemetry() {
        // 1. Live CPU %
        liveCPUPct = ProcessUsageService.shared.topCPU(limit: 50).first(where: { $0.pid == row.pid })?.value
        isLeaking = ProcessUsageService.shared.leakingPIDsCopy().contains(row.pid)

        // 2. Live RSS RAM
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        if proc_pidinfo(row.pid, PROC_PIDTASKINFO, 0, &info, Int32(size)) == size {
            let rssMB = Double(info.pti_resident_size) / (1024.0 * 1024.0)
            liveRSSStr = formatMB(rssMB)
        } else if row.value > 2000.0 {
            liveRSSStr = formatMB(row.value / (1024.0 * 1024.0))
        }

        // 3. Live Network I/O
        if let match = ProcessUsageService.shared.topNetwork(limit: 200).first(where: { $0.pid == row.pid }) {
            liveDown = match.networkDownBytesPerSec ?? 0.0
            liveUp = match.networkUpBytesPerSec ?? 0.0
        } else {
            liveDown = 0.0
            liveUp = 0.0
        }
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    private func formatKB(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024.0
        if kb >= 1024.0 {
            return String(format: "%.1f MB/s", kb / 1024.0)
        }
        return String(format: "%.0f KB/s", kb)
    }
}

/// Whether the inspector's window is on screen and not covered: the window
/// controller follows its occlusion state, the sheet's refresh follows this.
@MainActor
final class ProcessInspectorVisibility: ObservableObject {
    @Published var isVisible = true
}

// MARK: - ProcessInspectorWindowController

/// Standalone Window Controller for Process Inspector to prevent NSPopover modality lockups.
/// Conforms to NSWindowDelegate so the live-telemetry refresh is properly torn down when the
/// user clicks the native close (red) button — preventing an indefinite 1 Hz background drain.
@MainActor
final class ProcessInspectorWindowController: NSObject, NSWindowDelegate {
    static let shared = ProcessInspectorWindowController()
    private var window: NSWindow?
    private var occlusionObserver: NSObjectProtocol?

    private override init() {}

    func present(for process: ProcessUsage) {
        if let existing = window {
            existing.close()
            self.window = nil
        }
        removeOcclusionObserver()

        let visibility = ProcessInspectorVisibility()
        let view = ProcessDetailSheet(row: process, visibility: visibility)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = String(format: FeatureStrings.processInspector(L10n.shared.language).windowTitleFormat,
                              process.name, process.pid)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // isReleasedWhenClosed = false is required so we control the lifetime ourselves.
        // Without this the NSWindow would be deallocated on close, leaving window a dangling ref.
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()

        // Covered, minimized, on another Space or behind the lock screen, the
        // window is occluded and the sheet stops sampling.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak window, weak visibility] _ in
            MainActor.assumeIsolated {
                guard let window, let visibility else { return }
                let visible = window.occlusionState.contains(.visible)
                if visibility.isVisible != visible { visibility.isVisible = visible }
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        removeOcclusionObserver()
        window?.close()
        window = nil
    }

    private func removeOcclusionObserver() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }

    // MARK: NSWindowDelegate

    /// Called when the user clicks the red close button or presses Cmd+W.
    /// Clears our reference so the SwiftUI view (and its refresh) are released.
    nonisolated func windowWillClose(_ notification: Notification) {
        // Only the window still shown: closing the previous one from
        // `present` must not drop the one that replaced it.
        let closing = (notification.object as AnyObject?).map(ObjectIdentifier.init)
        Task { @MainActor in
            guard let window = self.window, ObjectIdentifier(window) == closing else { return }
            self.removeOcclusionObserver()
            self.window = nil
        }
    }
}
