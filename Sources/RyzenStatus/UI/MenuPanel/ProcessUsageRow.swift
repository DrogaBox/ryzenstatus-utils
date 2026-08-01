// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct ProcessUsageRow: View {
    let row: ProcessUsage
    let value: String
    var iconSize: CGFloat = 15
    var leadingPadding: CGFloat = 0

    @State private var showingDetail = false

    var body: some View {
        Button {
            ProcessInspectorWindowController.shared.present(for: row)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .help(row.name)
    }

    private var content: some View {
        let isLeaking = ProcessUsageService.shared.leakingPIDsCopy().contains(row.pid)
        let glossaryEntry = ProcessGlossary.lookup(name: row.name)

        return HStack(spacing: 7) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isLeaking {
                        Text("⚠️")
                            .font(.system(size: 9))
                            .help("Continuous memory growth detected (potential memory leak)")
                    }
                }
            }

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isLeaking ? Color.orange : Color.secondary)
        }
        .contentShape(Rectangle())
        .padding(.leading, leadingPadding)
        .help(glossaryEntry?.name ?? row.name)
    }
}
