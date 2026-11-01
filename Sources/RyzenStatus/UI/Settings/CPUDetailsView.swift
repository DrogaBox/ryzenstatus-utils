// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

struct CPUDetailsView: View {
    let details: ProcessorModel.CPUDetails
    @ObservedObject private var l10n = L10n.shared
    
    init() {
        self.details = ProcessorModel.shared.getCPUDetails()
    }
    
    var body: some View {
        let s = FeatureStrings.sensors(l10n.language)
        Form {
            Section(header: Text(s.processorSection)) {
                LabeledContent(s.name, value: details.name)
                LabeledContent(s.vendor, value: details.vendor)
                LabeledContent(s.physicalCores, value: "\(details.physicalCores)")
                LabeledContent(s.logicalCores, value: "\(details.logicalCores)")
            }
            
            Section(header: Text(s.architectureSection)) {
                LabeledContent(s.family, value: "\(details.family)")
                LabeledContent(s.model, value: "0x\(String(details.model, radix: 16, uppercase: true))")
                LabeledContent(s.extModel, value: "0x\(String(details.extModel, radix: 16, uppercase: true))")
                LabeledContent(s.extFamily, value: "\(details.extFamily)")
                LabeledContent(s.stepping, value: "\(details.stepping)")
                LabeledContent(s.signature, value: "0x\(String(details.signature, radix: 16, uppercase: true))")
                LabeledContent(s.brand, value: "\(details.brand)")
                LabeledContent(s.microcode, value: "\(details.microcodeVersion)")
            }
            
            Section(header: Text(s.featuresSection)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.features)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text(s.extFeaturesSection)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.extFeatures)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(s.cpuDetailsTitle)
    }
}
