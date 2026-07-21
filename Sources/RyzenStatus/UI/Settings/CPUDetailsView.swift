import SwiftUI

struct CPUDetailsView: View {
    let details: ProcessorModel.CPUDetails
    
    init() {
        self.details = ProcessorModel.shared.getCPUDetails()
    }
    
    var body: some View {
        Form {
            Section(header: Text("Processor Identifier")) {
                LabeledContent("Name", value: details.name)
                LabeledContent("Vendor", value: details.vendor)
                LabeledContent("Physical cores", value: "\(details.physicalCores)")
                LabeledContent("Logical cores", value: "\(details.logicalCores)")
            }
            
            Section(header: Text("Architecture Info")) {
                LabeledContent("Family", value: "\(details.family)")
                LabeledContent("Model", value: "0x\(String(details.model, radix: 16, uppercase: true))")
                LabeledContent("Ext Model", value: "0x\(String(details.extModel, radix: 16, uppercase: true))")
                LabeledContent("Ext Family", value: "\(details.extFamily)")
                LabeledContent("Stepping", value: "\(details.stepping)")
                LabeledContent("Signature", value: "0x\(String(details.signature, radix: 16, uppercase: true))")
                LabeledContent("Brand", value: "\(details.brand)")
                LabeledContent("Microcode version", value: "\(details.microcodeVersion)")
            }
            
            Section(header: Text("Features")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.features)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Extended Features")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.extFeatures)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("CPU Details")
    }
}
