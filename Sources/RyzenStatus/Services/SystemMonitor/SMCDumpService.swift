import Foundation

struct SMCSensorReading: Identifiable {
    let id = UUID()
    let key: String
    let value: Double
    let type: String
    let category: String
}

@MainActor
class SMCDumpService: ObservableObject {
    static let shared = SMCDumpService()
    
    @Published var readings: [SMCSensorReading] = []
    private var smcClient: SMCClient?
    
    private init() {
        self.smcClient = SMCClient()
    }
    
    func refresh() {
        guard let smc = smcClient else { return }
        
        // We will fetch all keys and then read their values
        // T* keys are usually Temperatures
        // F* keys are usually Fans
        // V* keys are usually Voltages
        // P* keys are usually Power
        
        let keys = smc.keys { name in
            name.hasPrefix("T") || name.hasPrefix("F") || name.hasPrefix("V") || name.hasPrefix("P") || name.hasPrefix("I")
        }
        
        var newReadings: [SMCSensorReading] = []
        
        for key in keys {
            if let val = smc.readValue(key) {
                let category: String
                if key.name.hasPrefix("T") { category = "Temperature" }
                else if key.name.hasPrefix("F") { category = "Fan" }
                else if key.name.hasPrefix("V") { category = "Voltage" }
                else if key.name.hasPrefix("P") { category = "Power" }
                else if key.name.hasPrefix("I") { category = "Current" }
                else { category = "Other" }
                
                newReadings.append(SMCSensorReading(key: key.name, value: val, type: key.dataType, category: category))
            }
        }
        
        self.readings = newReadings.sorted(by: { $0.key < $1.key })
    }
}
