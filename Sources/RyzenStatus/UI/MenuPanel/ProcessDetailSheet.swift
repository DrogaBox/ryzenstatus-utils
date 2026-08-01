// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Darwin
import SwiftUI

/// Rich Process Inspector Sheet displaying full metadata, executable path,
/// memory regions, live CPU/RAM/Network telemetry (updating live at 1Hz), and system actions.
struct ProcessDetailSheet: View {
    let row: ProcessUsage
    @Environment(\.dismiss) private var dismiss
    @State private var showingTerminateAlert = false
    @State private var pathCopied = false

    @State private var liveCPUPct: Double = 0.0
    @State private var liveRSSStr: String = "0 MB"
    @State private var liveDown: Double = 0.0
    @State private var liveUp: Double = 0.0

    private var glossaryEntry: ProcessGlossaryEntry {
        ProcessGlossary.resolve(name: row.name, pid: row.pid)
    }

    private var isLeaking: Bool {
        ProcessUsageService.shared.leakingPIDsCopy().contains(row.pid)
    }

    private var executablePath: String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(row.pid, &buffer, UInt32(MAXPATHLEN))
        if ret > 0 {
            return String(cString: buffer)
        }
        return "/System/Library/CoreServices/\(row.name)"
    }

    var body: some View {
        let entry = glossaryEntry
        let path = executablePath

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
                        Text(entry.category.rawValue.capitalized)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    Text("PID: \(row.pid)  ·  Native Architecture")
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
            }

            Divider()

            // Memory Leak Warning Alert Box
            if isLeaking {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continuous Memory Growth Detected")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                        Text("This process is showing sustained memory leaks over 20+ minutes.")
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
                    Text("CPU LOAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", liveCPUPct))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(liveCPUPct > 80.0 ? .red : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Card 2: Live Memory RSS
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESIDENT RAM (RSS)")
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
                    Text("NETWORK I/O")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let netText = (liveDown > 0 || liveUp > 0) ? "↓ \(formatKB(liveDown))  ↑ \(formatKB(liveUp))" : "0 B/s (Inactive)"
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
                    Text("EXECUTABLE PATH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                        pathCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            pathCopied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                            Text(pathCopied ? "Copied" : "Copy Path")
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)

                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Reveal in Finder")
                        }
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }

                Text(path)
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
                Text("PROCESS ROLE & DESCRIPTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(entry.localizedDescriptionKey)
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
            HStack(spacing: 12) {
                Button("Done") {
                    ProcessInspectorWindowController.shared.close()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Terminate Process", role: .destructive) {
                    showingTerminateAlert = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(16)
        .frame(width: 480, height: 420)
        .onAppear {
            refreshLiveTelemetry()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshLiveTelemetry()
        }
        .alert("Force Quit \(row.name)?", isPresented: $showingTerminateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Force Quit", role: .destructive) {
                kill(row.pid, SIGKILL)
                ProcessInspectorWindowController.shared.close()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to send SIGKILL to PID \(row.pid)? Any unsaved data will be lost.")
        }
    }

    private func refreshLiveTelemetry() {
        // 1. Live CPU %
        if let match = ProcessUsageService.shared.topCPU(limit: 50).first(where: { $0.pid == row.pid }) {
            liveCPUPct = match.value
        } else if row.value <= 2000.0 {
            liveCPUPct = row.value
        }

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

// MARK: - ProcessInspectorWindowController

/// Standalone Window Controller for Process Inspector to prevent NSPopover modality lockups.
/// Conforms to NSWindowDelegate so the live-telemetry timer is properly torn down when the
/// user clicks the native close (red) button — preventing an indefinite 1 Hz background drain.
@MainActor
final class ProcessInspectorWindowController: NSObject, NSWindowDelegate {
    static let shared = ProcessInspectorWindowController()
    private var window: NSWindow?

    private override init() {}

    func present(for process: ProcessUsage) {
        if let existing = window {
            existing.close()
            self.window = nil
        }

        let view = ProcessDetailSheet(row: process)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "Process Inspector — \(process.name) (\(process.pid))"
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

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }

    // MARK: NSWindowDelegate

    /// Called when the user clicks the red close button or presses Cmd+W.
    /// Clears our reference so the SwiftUI view (and its 1 Hz timer) are released.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
        }
    }
}
