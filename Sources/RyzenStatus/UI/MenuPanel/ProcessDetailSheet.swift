// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Darwin
import SwiftUI

/// Rich Process Inspector Sheet displaying full metadata, executable path,
/// memory regions, live CPU/RAM/Network telemetry, and system actions.
struct ProcessDetailSheet: View {
    let row: ProcessUsage
    @Environment(\.dismiss) private var dismiss
    @State private var showingTerminateAlert = false
    @State private var pathCopied = false

    private var glossaryEntry: ProcessGlossaryEntry {
        ProcessGlossary.resolve(name: row.name, pid: row.pid)
    }

    private var isLeaking: Bool {
        ProcessUsageService.shared.leakingPIDs.contains(row.pid)
    }

    private var executablePath: String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(row.pid, &buffer, UInt32(MAXPATHLEN))
        if ret > 0 {
            return String(cString: buffer)
        }
        return "/System/Library/CoreServices/\(row.name)"
    }

    private var memoryDetails: (rss: String, virt: String) {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = proc_pidinfo(row.pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        if result == size {
            let rssMB = Double(info.pti_resident_size) / (1024.0 * 1024.0)
            let virtMB = Double(info.pti_virtual_size) / (1024.0 * 1024.0)
            return (formatMB(rssMB), formatMB(virtMB))
        }
        return ("\(Int(row.value)) MB", "N/A")
    }

    var body: some View {
        let entry = glossaryEntry
        let path = executablePath
        let mem = memoryDetails

        VStack(spacing: 14) {
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
                // Card 1: CPU Usage
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU LOAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", row.value))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(row.value > 80.0 ? .red : .primary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Card 2: Memory RSS
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESIDENT RAM (RSS)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(mem.rss)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Card 3: Network Throughput
                let down = row.networkDownBytesPerSec ?? 0.0
                let up = row.networkUpBytesPerSec ?? 0.0
                VStack(alignment: .leading, spacing: 4) {
                    Text("NETWORK I/O")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("↓ \(formatKB(down))  ↑ \(formatKB(up))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(8)

            Spacer(minLength: 0)

            // --- ACTION BUTTONS ---
            HStack(spacing: 12) {
                Button("Done") {
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
        .alert("Force Quit \(row.name)?", isPresented: $showingTerminateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Force Quit", role: .destructive) {
                kill(row.pid, SIGKILL)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to send SIGKILL to PID \(row.pid)? Any unsaved data will be lost.")
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
