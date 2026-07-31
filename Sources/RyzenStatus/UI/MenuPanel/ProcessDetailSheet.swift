// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct ProcessDetailSheet: View {
    let row: ProcessUsage
    @Environment(\.dismiss) private var dismiss
    @State private var showingTerminateAlert = false

    private var glossaryEntry: ProcessGlossaryEntry? {
        ProcessGlossary.lookup(name: row.name)
    }

    private var isLeaking: Bool {
        ProcessUsageService.shared.leakingPIDs.contains(row.pid)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    Text("PID: \(row.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let entry = glossaryEntry {
                    Text(entry.category.rawValue.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }

            Divider()

            // Memory Leak Warning Alert Box
            if isLeaking {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory Leak Detected")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                        Text("This process is showing sustained memory growth over time.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Glossary Description
            if let entry = glossaryEntry {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Process Description")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(entry.name)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            // Actions
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
        .frame(width: 380, height: 260)
        .alert("Terminate \(row.name)?", isPresented: $showingTerminateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Force Quit", role: .destructive) {
                kill(row.pid, SIGKILL)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to force quit PID \(row.pid)? Unsaved data may be lost.")
        }
    }
}
