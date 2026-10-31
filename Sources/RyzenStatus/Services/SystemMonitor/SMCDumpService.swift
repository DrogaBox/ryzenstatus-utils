import Foundation

struct SMCSensorReading: Identifiable {
    // The SMC key is the stable identity. A per-refresh UUID forced
    // SwiftUI to diff every row as insert+delete on each readAll() (flicker +
    // lost selection/scroll anchor).
    let id: String
    let key: String
    let value: Double
    let type: String
    let category: String

    init(key: String, value: Double, type: String, category: String) {
        self.id = key
        self.key = key
        self.value = value
        self.type = type
        self.category = category
    }
}

private final class SMCDumpReader: @unchecked Sendable {
    private var smcClient: SMCClient?
    private var keys: [SMCClient.Key] = []
    /// The key set does not change while the system runs, so it is listed
    /// (two SMC calls per key) once each time the Sensors page opens.
    private var needsDiscovery = true

    func invalidateKeys() {
        needsDiscovery = true
    }

    func readAll() -> [SMCSensorReading] {
        if smcClient == nil {
            smcClient = SMCClient()
        }
        guard let smc = smcClient else { return [] }

        if needsDiscovery || keys.isEmpty {
            keys = smc.keys { name in !name.isEmpty }
            needsDiscovery = false
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

    /// Lists the SMC keys again on the next refresh. The Sensors page calls
    /// this when it opens.
    func rediscoverKeys() {
        let reader = self.reader
        workQueue.async { reader.invalidateKeys() }
    }

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
