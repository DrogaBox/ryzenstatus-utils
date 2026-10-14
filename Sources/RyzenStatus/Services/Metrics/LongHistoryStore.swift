// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// A reading kept in the long history. Raw values are stored in the units
/// the monitor publishes: usage as 0...1, traffic in bytes per second,
/// temperatures in °C and power in watts.
enum LongHistoryMetric: Int, CaseIterable {
    case cpu, gpu, memory, networkDown, networkUp, diskRead, diskWrite
    case cpuTemperature, gpuTemperature, systemPower
}

/// How far back a long-history graph reaches. Every range is drawn with the
/// same number of columns, each the average of its share of the range.
enum LongHistoryRange: Int, CaseIterable, Identifiable {
    case tenMinutes = 600
    case oneHour = 3_600
    case threeHours = 10_800
    case sixHours = 21_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case threeDays = 259_200
    case sevenDays = 604_800
    case fourteenDays = 1_209_600
    case thirtyDays = 2_592_000

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue) }

    /// "10m", "1h", "3d" in the app's language.
    func label(_ language: AppLanguage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language.rawValue)
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.maximumUnitCount = 1
        return formatter.string(from: duration) ?? "\(rawValue)s"
    }
}

/// One resolution of the history: a ring of fixed-width time slots, each
/// holding the running mean of the samples that fell in it. A slot is
/// addressed by its absolute index (seconds since 1970 / step), so a ring
/// written before a restart lines up with the clock after it.
struct LongHistoryTier {
    let step: TimeInterval
    let capacity: Int
    private(set) var means: [Float]
    private(set) var counts: [UInt16]
    /// The newest slot written, or nil while the ring is empty.
    private(set) var newestSlot: Int64?

    init(step: TimeInterval, capacity: Int) {
        self.step = step
        self.capacity = capacity
        means = [Float](repeating: 0, count: capacity)
        counts = [UInt16](repeating: 0, count: capacity)
    }

    func slot(at time: TimeInterval) -> Int64 {
        Int64((time / step).rounded(.down))
    }

    private func position(_ slot: Int64) -> Int {
        Int(((slot % Int64(capacity)) + Int64(capacity)) % Int64(capacity))
    }

    mutating func record(_ value: Double, at time: TimeInterval) {
        guard value.isFinite else { return }
        let current = slot(at: time)
        if let newest = newestSlot {
            // A sample older than the ring is dropped (the clock went back);
            // one still inside it lands in its own slot.
            if current > newest {
                let cleared = min(Int64(capacity), current - newest)
                for offset in 1...cleared { reset(position(newest + offset)) }
                newestSlot = current
            } else if newest - current >= Int64(capacity) {
                return
            }
        } else {
            newestSlot = current
        }
        let index = position(current)
        guard counts[index] < UInt16.max else { return }
        counts[index] += 1
        means[index] += (Float(value) - means[index]) / Float(counts[index])
    }

    private mutating func reset(_ index: Int) {
        means[index] = 0
        counts[index] = 0
    }

    /// The slot's mean, or nil when nothing was recorded in it or it has
    /// left the ring.
    func mean(slot: Int64) -> Float? {
        guard let newest = newestSlot, slot <= newest, newest - slot < Int64(capacity) else { return nil }
        let index = position(slot)
        return counts[index] > 0 ? means[index] : nil
    }

    /// `buckets` averages across `[end - duration, end)`, oldest first. A
    /// bucket with no samples is NaN, so a gap stays a gap.
    func averages(end: TimeInterval, duration: TimeInterval, buckets: Int) -> [Double] {
        guard buckets > 0, duration > 0 else { return [] }
        let width = duration / Double(buckets)
        let start = end - duration
        return (0..<buckets).map { bucket in
            let from = slot(at: start + Double(bucket) * width)
            let to = max(from, slot(at: start + Double(bucket + 1) * width) - 1)
            var sum = 0.0
            var filled = 0
            for slot in from...to {
                if let value = mean(slot: slot) {
                    sum += Double(value)
                    filled += 1
                }
            }
            return filled > 0 ? sum / Double(filled) : .nan
        }
    }

    /// Restores slot means read from disk, oldest first, ending at `newest`.
    mutating func restore(means stored: [Float], newest: Int64) {
        let kept = stored.suffix(capacity)
        var slot = newest - Int64(kept.count) + 1
        for value in kept {
            if value.isFinite {
                let index = position(slot)
                means[index] = value
                counts[index] = 1
            }
            slot += 1
        }
        newestSlot = newest
    }

    /// Every slot's mean, oldest first, NaN where empty; nil while empty.
    func snapshot() -> (means: [Float], newest: Int64)? {
        guard let newest = newestSlot else { return nil }
        let values = (0..<Int64(capacity)).map { offset -> Float in
            mean(slot: newest - Int64(capacity) + 1 + offset) ?? .nan
        }
        return (values, newest)
    }
}

/// Keeps what the system monitor already samples for up to thirty days: a
/// five-second ring for the last hour and a one-minute ring for the month.
/// It never samples on its own, so a reading nobody shows leaves a gap
/// rather than costing energy. The month ring is saved to Application
/// Support every few minutes and when the app quits.
final class LongHistoryStore {
    static let shared = LongHistoryStore()

    /// Columns per graph, whatever the range.
    static let bucketCount = 120
    static let fineStep: TimeInterval = 5
    static let fineCapacity = 720
    static let coarseStep: TimeInterval = 60
    static let coarseCapacity = 43_200
    static let saveInterval: TimeInterval = 15 * 60

    private let lock = NSLock()
    private var fine: [LongHistoryTier]
    private var coarse: [LongHistoryTier]
    private var lastSave: TimeInterval
    private var dirty = false
    private let fileURL: URL?
    private let ioQueue = DispatchQueue(label: "RyzenStatus.LongHistoryStore.io", qos: .utility)

    init(fileURL: URL? = PrivateFileStore.containerURL?.appendingPathComponent("long-history.bin"),
         now: TimeInterval = Date().timeIntervalSince1970) {
        self.fileURL = fileURL
        fine = LongHistoryMetric.allCases.map { _ in
            LongHistoryTier(step: Self.fineStep, capacity: Self.fineCapacity)
        }
        coarse = LongHistoryMetric.allCases.map { _ in
            LongHistoryTier(step: Self.coarseStep, capacity: Self.coarseCapacity)
        }
        lastSave = now
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            Self.decode(data, into: &coarse)
        }
    }

    func record(_ metric: LongHistoryMetric, _ value: Double,
                at time: TimeInterval = Date().timeIntervalSince1970) {
        guard value.isFinite else { return }
        lock.lock()
        fine[metric.rawValue].record(value, at: time)
        coarse[metric.rawValue].record(value, at: time)
        dirty = true
        let saveDue = time - lastSave >= Self.saveInterval
        if saveDue { lastSave = time }
        lock.unlock()
        if saveDue { save() }
    }

    /// `bucketCount` averages for `range` ending at `end`, oldest first; NaN
    /// where nothing was recorded. Ranges up to an hour come from the
    /// five-second ring, longer ones from the minute ring.
    func averages(_ metric: LongHistoryMetric, range: LongHistoryRange,
                  end: TimeInterval = Date().timeIntervalSince1970) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let tier = range.duration <= Self.fineStep * Double(Self.fineCapacity)
            ? fine[metric.rawValue] : coarse[metric.rawValue]
        return tier.averages(end: end, duration: range.duration, buckets: Self.bucketCount)
    }

    /// Writes the minute ring off the caller's thread. `synchronously` is for
    /// quitting, when there is no later turn of the queue.
    func save(synchronously: Bool = false) {
        lock.lock()
        guard dirty, let fileURL else {
            lock.unlock()
            return
        }
        dirty = false
        let data = Self.encode(coarse)
        lock.unlock()
        let write: () -> Void = {
            PrivateFileStore.createDirectory(at: fileURL.deletingLastPathComponent())
            PrivateFileStore.write(data, to: fileURL)
        }
        if synchronously {
            ioQueue.sync(execute: write)
        } else {
            ioQueue.async(execute: write)
        }
    }

    // MARK: - File format

    /// "RSLH", version, metric count, slot count, then per metric the newest
    /// slot (Int64, -1 when empty) and its slot means as Float32, little-endian.
    static let magic: UInt32 = 0x484C_5352
    static let version: UInt32 = 1

    static func encode(_ tiers: [LongHistoryTier]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(magic)
        append(version)
        append(UInt32(tiers.count))
        append(UInt32(coarseCapacity))
        for tier in tiers {
            if let (means, newest) = tier.snapshot() {
                append(newest)
                for value in means { append(value.bitPattern) }
            } else {
                append(Int64(-1))
            }
        }
        return data
    }

    static func decode(_ data: Data, into tiers: inout [LongHistoryTier]) {
        let bytes = [UInt8](data)
        var offset = 0
        func read<T: FixedWidthInteger>(_: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= bytes.count else { return nil }
            let value = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
            offset += size
            return T(littleEndian: value)
        }
        guard read(UInt32.self) == magic, read(UInt32.self) == version,
              let metricCount = read(UInt32.self), let slots = read(UInt32.self),
              Int(slots) == coarseCapacity
        else { return }
        for index in 0..<Int(metricCount) {
            guard let newest = read(Int64.self) else { return }
            guard newest >= 0 else { continue }
            var means = [Float]()
            means.reserveCapacity(Int(slots))
            for _ in 0..<Int(slots) {
                guard let bits = read(UInt32.self) else { return }
                means.append(Float(bitPattern: bits))
            }
            if index < tiers.count {
                tiers[index].restore(means: means, newest: newest)
            }
        }
    }
}
