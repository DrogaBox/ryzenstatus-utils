// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import Foundation

/// Continuous telemetry logger for exporting system metrics to CSV or JSON-Lines on disk.
/// Includes rate-limiting and buffer flushing (every 10s) to prevent NVMe/HDD stuttering.
final class TelemetryLogger: ObservableObject {
    static let shared = TelemetryLogger()

    @Published private(set) var isLogging: Bool = false
    @Published private(set) var currentLogPath: String?


    private var cancellable: AnyCancellable?
    private let logQueue = DispatchQueue(label: "com.ryzenstatus.telemetrylogger", qos: .utility)
    private var fileHandle: FileHandle?
    private var buffer: [String] = []
    private var lastFlushTime: Date = Date()
    private let flushIntervalSeconds: TimeInterval = 10.0
    /// Reused across every logSnapshot call — ISO8601DateFormatter is expensive to construct.
    private let dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    private init() {}


    func startLogging() {
        // BUG-03 fix: move the isLogging check AND the transition inside the serial queue
        // so concurrent calls see the flag atomically and cannot open two files.
        logQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isLogging else { return }
            self.setupNewLogFile()
            DispatchQueue.main.async {
                self.isLogging = true
                self.subscribeToSnapshot()
            }
        }
    }

    func stopLogging() {
        guard isLogging else { return }
        cancellable?.cancel()
        cancellable = nil
        logQueue.async { [weak self] in
            guard let self else { return }
            self.flushBufferLocked()
            self.fileHandle?.closeFile()
            self.fileHandle = nil
            DispatchQueue.main.async {
                self.isLogging = false
            }
        }
    }

    private func subscribeToSnapshot() {
        cancellable = SystemMonitor.shared.$snapshot
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] snapshot in
                self?.logSnapshot(snapshot)
            }
    }

    private func logSnapshot(_ snapshot: SystemSnapshot) {
        let nowStr = dateFormatter.string(from: Date())
        let cpuUsage = snapshot.cpuUsage ?? 0
        let cpuTemp = snapshot.cpuTemperature ?? 0
        let gpuTemp = snapshot.gpuTemperature ?? 0
        let cpuPower = snapshot.cpuPower ?? 0
        let gpuPower = snapshot.gpuPower ?? 0
        let ccd0Temp = snapshot.ccd0Temperature ?? 0
        let ccd1Temp = snapshot.ccd1Temperature ?? 0

        let line = String(format: "%@,%.2f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f\n",
                          nowStr, cpuUsage * 100, cpuTemp, gpuTemp, cpuPower, gpuPower, ccd0Temp, ccd1Temp)

        logQueue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(line)
            let now = Date()
            if now.timeIntervalSince(self.lastFlushTime) >= self.flushIntervalSeconds || self.buffer.count >= 5 {
                self.flushBufferLocked()
            }
        }
    }

    private func flushBufferLocked() {
        guard let handle = fileHandle, !buffer.isEmpty else { return }
        let combined = buffer.joined()
        buffer.removeAll(keepingCapacity: true)
        lastFlushTime = Date()
        let data = Data(combined.utf8)
        // BUG-02 fix: the legacy handle.write(data) raises an uncatchable NSException when the
        // disk is full or the file is externally deleted. The modern throwing API lets us recover.
        do {
            try handle.write(contentsOf: data)
        } catch {
            // Close and nil the handle — next logSnapshot will safely skip until a new log is created.
            handle.closeFile()
            fileHandle = nil
        }
    }

    private func setupNewLogFile() {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RyzenStatusLogs", isDirectory: true)
        
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = String(format: "ryzenstatus_telemetry_%@.csv", ISO8601DateFormatter().string(from: Date()))
            let fileURL = folder.appendingPathComponent(filename)
            
            let header = "timestamp,cpu_usage_pct,cpu_temp_c,gpu_temp_c,cpu_power_w,gpu_power_w,ccd0_temp_c,ccd1_temp_c\n"
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
            
            self.fileHandle = try? FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
            DispatchQueue.main.async {
                self.currentLogPath = fileURL.path
            }
        }
    }
}
