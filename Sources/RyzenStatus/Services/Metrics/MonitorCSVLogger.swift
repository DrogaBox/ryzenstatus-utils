// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// Appends text to one file on its own serial queue. The handle is only
/// touched on that queue, so the main thread never waits on the disk.
final class CSVAppendWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ryzenstatus.utils.csv-log", qos: .utility)
    private var handle: FileHandle?

    /// Creates (or empties: the save panel already asked before replacing)
    /// the file and keeps it open for appending.
    func open(_ url: URL, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            self.closeOnQueue()
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else {
                completion(false)
                return
            }
            self.handle = handle
            completion(true)
        }
    }

    func append(_ text: String, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard let handle = self.handle else { return }
            do {
                try handle.write(contentsOf: Data(text.utf8))
                completion(true)
            } catch {
                self.closeOnQueue()
                completion(false)
            }
        }
    }

    /// `synchronously` is for quitting: the caller waits until every queued
    /// row is on disk and the handle is closed.
    func close(synchronously: Bool = false) {
        if synchronously {
            queue.sync { closeOnQueue() }
        } else {
            queue.async { self.closeOnQueue() }
        }
    }

    private func closeOnQueue() {
        guard let handle else { return }
        try? handle.synchronize()
        try? handle.close()
        self.handle = nil
    }
}

/// The continuous CSV log: one row per monitor snapshot, about every
/// second, into a file the user picked. It reads the snapshot the monitor
/// already publishes and only tells the monitor which families to keep
/// sampling while it runs. Nothing is remembered across launches, so a
/// relaunch never starts writing on its own.
@MainActor
final class MonitorCSVLogger: ObservableObject {
    static let shared = MonitorCSVLogger()

    /// The file being written, nil while not logging.
    @Published private(set) var fileURL: URL?
    @Published private(set) var rowCount = 0

    var isLogging: Bool { fileURL != nil }

    /// What the columns read: CPU load and temperature (the kext power and
    /// clock come with them), GPU temperature and the GPU power read.
    static let needs = SystemMonitorPanelNeeds(cpu: true, gpu: true, cpuTemperature: true, gpuTemperature: true)
    /// A second snapshot published right after a forced refresh is not
    /// another second of logging.
    static let minimumRowGap: TimeInterval = 0.9
    /// Snapshots to wait for the fan list before the header is fixed.
    static let fanWaitSamples = 5

    private let writer = CSVAppendWriter()
    private var cancellables = Set<AnyCancellable>()
    private var layout: MonitorCSVLayout?
    private var samplesWaitingForFans = 0
    private var lastRowAt: TimeInterval?
    private var pollingFans = false
    /// Bumped on every start and stop, so a write finishing for an old file
    /// cannot count rows or report a failure for the new one.
    private var generation = 0

    private init() {}

    func start(url: URL) {
        stop()
        generation += 1
        let current = generation
        fileURL = url
        rowCount = 0
        layout = nil
        samplesWaitingForFans = 0
        lastRowAt = nil
        writer.open(url) { ok in
            guard !ok else { return }
            DispatchQueue.main.async { MonitorCSVLogger.shared.writeFailed(generation: current) }
        }
        if ProcessorModel.shared.isConnected {
            FanCurveController.shared.startPolling()
            pollingFans = true
        }
        SystemMonitor.shared.setLoggingNeeds(Self.needs)
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.consume(snapshot)
            }
            .store(in: &cancellables)
        Notifier.requestPermission()
    }

    /// Ends the log and closes the file. `synchronously` is for quitting.
    func stop(synchronously: Bool = false) {
        guard isLogging else { return }
        generation += 1
        cancellables.removeAll()
        SystemMonitor.shared.setLoggingNeeds(.none)
        if pollingFans {
            FanCurveController.shared.stopPolling()
            pollingFans = false
        }
        writer.close(synchronously: synchronously)
        fileURL = nil
        layout = nil
    }

    private func consume(_ snapshot: SystemSnapshot) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastRowAt, now - lastRowAt < Self.minimumRowGap { return }
        let fans = pollingFans ? FanCurveController.shared.fans : []
        if layout == nil {
            let fanListPending = pollingFans && fans.isEmpty
                && !FanCurveController.shared.kextMissing
                && samplesWaitingForFans < Self.fanWaitSamples
            if fanListPending {
                samplesWaitingForFans += 1
                return
            }
            let next = MonitorCSVLayout(fans: fans.map { .init(id: $0.id, label: $0.effectiveDisplayName) })
            layout = next
            append(next.header, countsAsRow: false)
        }
        guard let layout else { return }
        lastRowAt = now
        append(layout.row(Self.sample(from: snapshot, fans: fans, epp: AutoEppService.shared.currentEPP)),
               countsAsRow: true)
    }

    nonisolated static func sample(from snapshot: SystemSnapshot, fans: [FanState], epp: UInt8?,
                       time: Date = Date()) -> MonitorCSVSample {
        var rpm: [Int: Double] = [:]
        for fan in fans where fan.rpmValid { rpm[fan.id] = Double(fan.rpm) }
        return MonitorCSVSample(time: time,
                                cpuUsage: snapshot.cpuUsage,
                                cpuTemperature: snapshot.cpuTemperature,
                                cpuPower: snapshot.cpuPower,
                                averageClock: snapshot.avgCPUFreq,
                                epp: epp,
                                gpuTemperature: snapshot.gpuTemperature,
                                gpuPower: snapshot.gpuPower,
                                fanRPM: rpm)
    }

    private func append(_ text: String, countsAsRow: Bool) {
        let current = generation
        writer.append(text) { ok in
            DispatchQueue.main.async {
                let logger = MonitorCSVLogger.shared
                guard logger.generation == current else { return }
                if !ok {
                    logger.writeFailed(generation: current)
                } else if countsAsRow {
                    logger.rowCount += 1
                }
            }
        }
    }

    /// The file could not be opened or written: stop once and say so once.
    private func writeFailed(generation failed: Int) {
        guard failed == generation, let url = fileURL else { return }
        stop()
        let strings = FeatureStrings.monitorCSV(L10n.shared.language)
        Notifier.post(title: strings.logFailedTitle,
                      body: String(format: strings.writeFailedBody, url.lastPathComponent))
    }

    // MARK: - History export

    /// Writes the long history for `range` to `url` off the main thread and
    /// reports a failure through the Notifier.
    nonisolated static func exportHistory(range: LongHistoryRange, to url: URL) {
        let strings = FeatureStrings.monitorCSV(L10n.shared.language)
        let title = strings.exportFailedTitle
        let body = String(format: strings.writeFailedBody, url.lastPathComponent)
        DispatchQueue.global(qos: .utility).async {
            let table = LongHistoryStore.shared.exportTable(range: range)
            do {
                try Data(table.csv().utf8).write(to: url, options: .atomic)
            } catch {
                Notifier.post(title: title, body: body)
            }
        }
    }

    /// "RyzenStatus-2026-11-21.csv" or "RyzenStatus-History-2026-11-21.csv".
    nonisolated static func defaultFileName(prefix: String = "RyzenStatus", date: Date = Date(),
                                timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(prefix)-\(formatter.string(from: date)).csv"
    }
}
