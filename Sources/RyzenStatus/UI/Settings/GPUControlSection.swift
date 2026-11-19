// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings > Sensors: what the GPU control in GPUSensors.kext reports about
/// itself. Read only, no controls; it only exists with a kext that has the
/// control (0.3.0 and later). Built like the page's other groups: a header
/// row that opens and closes it, label and value rows, a caption last.
struct GPUControlSection: View {
    let status: GPUControlStatus
    let strings: GPUControlStrings
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(status.rows(strings)) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: row.icon)
                                .frame(width: 24)
                                .foregroundColor(.secondary)
                            Text(row.label)
                            Spacer()
                            Text(row.value)
                                .font(row.isNumber ? .system(.body, design: .monospaced) : .body)
                                .multilineTextAlignment(.trailing)
                        }
                        // The kext's own reason, as it wrote it.
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 32)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(strings.footer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundColor(.orange)
                    Text(strings.title)
                        .font(.headline)
                    Spacer()
                    Text(status.summary(strings))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disclosureHeader(isExpanded: $isExpanded)
            }
        }
    }
}
