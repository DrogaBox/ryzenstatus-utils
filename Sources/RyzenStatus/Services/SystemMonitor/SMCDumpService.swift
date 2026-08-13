import Foundation

struct SMCSensorReading: Identifiable {
    let id = UUID()
    let key: String
    let value: Double
    let type: String
    let category: String
}

private final class SMCDumpReader: @unchecked Sendable {
    private var smcClient: SMCClient?
    private var keys: [SMCClient.Key] = []
    private var lastKeyDiscovery = Date.distantPast

    func readAll() -> [SMCSensorReading] {
        if smcClient == nil {
            smcClient = SMCClient()
        }
        guard let smc = smcClient else { return [] }

        let now = Date()
        if keys.isEmpty || now.timeIntervalSince(lastKeyDiscovery) >= 30 {
            keys = smc.keys { name in !name.isEmpty }
            lastKeyDiscovery = now
        }

        var newReadings: [SMCSensorReading] = []
        for key in keys {
            if let value = smc.readValue(key) {
                let category: String
                if key.name.hasPrefix("T") { category = "Temperature" }
                else if key.name.hasPrefix("F") { category = "Fan" }
                else if key.name.hasPrefix("V") { category = "Voltage" }
                else if key.name.hasPrefix("P") { category = "Power" }
                else if key.name.hasPrefix("I") { category = "Current" }
                else { category = "Other" }
                newReadings.append(SMCSensorReading(key: key.name,
                                                    value: value,
                                                    type: key.dataType,
                                                    category: category))
            }
        }
        return newReadings.sorted { $0.key < $1.key }
    }
}

@MainActor
class SMCDumpService: ObservableObject {
    static let shared = SMCDumpService()
    
    @Published var readings: [SMCSensorReading] = []
    private let workQueue = DispatchQueue(label: "com.ryzenstatus.smc-dump", qos: .utility)
    private let reader = SMCDumpReader()
    private var refreshInFlight = false
    
    private init() {}
    
    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let reader = self.reader
        workQueue.async { [weak self, reader] in
            let newReadings = reader.readAll()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.readings = newReadings
                self.refreshInFlight = false
            }
        }
    }
}
