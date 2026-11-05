// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

extension DefaultsKey {
    static let notchMascotAlarms = "notchMascotAlarms"   // Data, JSON [NotchMascotAlarm]: the companion's alarm clocks
}

/// One of the companion's alarm clocks, as the phone's Clock app keeps
/// them: a time of day, the weekdays it rings on (none for once), a label,
/// a sound and whether it may be put off for a few minutes.
struct NotchMascotAlarm: Codable, Equatable, Identifiable {
    var id = UUID()
    var hour = 7
    var minute = 0
    /// Calendar weekdays it rings on, 1 for Sunday to 7 for Saturday; empty
    /// rings once, at the next time it comes round.
    var days: Set<Int> = []
    var label = ""
    var enabled = true
    /// A `NotchMascotAlarmSounds` identifier.
    var sound = NotchMascotAlarmSounds.defaultSound
    var snooze = true
    var snoozeMinutes = NotchMascotAlarmSchedule.snoozeMinutes
    /// The moment its next ring is counted from: when it was set, switched
    /// on or last rang, so a ring is never heard twice.
    var armed = Date()
    /// Put off until then, when it rings again whatever its days say.
    var snoozedUntil: Date?

    var repeats: Bool { !days.isEmpty }

    init() {}

    init(hour: Int, minute: Int, days: Set<Int> = [], label: String = "", sound: String = NotchMascotAlarmSounds.defaultSound,
         snooze: Bool = true, armed: Date = Date()) {
        self.hour = hour
        self.minute = minute
        self.days = days
        self.label = label
        self.sound = sound
        self.snooze = snooze
        self.armed = armed
    }

    // Written by hand so an alarm saved by an older build, missing a field,
    // still loads with that field's default.
    private enum CodingKeys: String, CodingKey {
        case id, hour, minute, days, label, enabled, sound, snooze, snoozeMinutes, armed, snoozedUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = NotchMascotAlarm()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? fresh.id
        hour = min(23, max(0, try container.decodeIfPresent(Int.self, forKey: .hour) ?? fresh.hour))
        minute = min(59, max(0, try container.decodeIfPresent(Int.self, forKey: .minute) ?? fresh.minute))
        days = (try container.decodeIfPresent(Set<Int>.self, forKey: .days) ?? []).filter { (1...7).contains($0) }
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? fresh.sound
        snooze = try container.decodeIfPresent(Bool.self, forKey: .snooze) ?? true
        snoozeMinutes = min(60, max(1, try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? fresh.snoozeMinutes))
        armed = try container.decodeIfPresent(Date.self, forKey: .armed) ?? fresh.armed
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(days.sorted(), forKey: .days)
        try container.encode(label, forKey: .label)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(sound, forKey: .sound)
        try container.encode(snooze, forKey: .snooze)
        try container.encode(snoozeMinutes, forKey: .snoozeMinutes)
        try container.encode(armed, forKey: .armed)
        try container.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
    }

    /// The list as saved, and back; a list that cannot be read is empty.
    /// Dates keep the encoder's own form, seconds from the reference date,
    /// which comes back to the exact same instant; counting from 1970 would
    /// round off the last bit of a time taken from the clock.
    static func encode(_ alarms: [NotchMascotAlarm]) -> Data? {
        try? JSONEncoder().encode(alarms)
    }

    static func decode(_ data: Data?) -> [NotchMascotAlarm] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([NotchMascotAlarm].self, from: data)) ?? []
    }
}

/// When the alarms ring: the next time for a set of weekdays or for once,
/// through clock changes and daylight saving, which are due now and which
/// were missed while the Mac slept too long ago to ring for. Pure, so it is
/// tested.
enum NotchMascotAlarmSchedule {
    /// How long after its time an alarm missed while the Mac slept still rings.
    static let grace: TimeInterval = 10 * 60
    static let snoozeMinutes = 9
    /// The longest one wait is trusted for before the time is looked at again.
    static let longestWait: TimeInterval = 30 * 60

    /// The first time after `date` that `hour`:`minute` comes round on one
    /// of `days`, or on any day with none. A time the clocks skip that day
    /// rings at the next time that exists; one they go through twice rings
    /// the first time.
    static func occurrence(hour: Int, minute: Int, days: Set<Int>, after date: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 0..<9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if !days.isEmpty, !days.contains(calendar.component(.weekday, from: day)) { continue }
            guard let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            else { continue }
            if time > date { return time }
        }
        return nil
    }

    /// When `alarm` rings next: its snooze first, then its time from when
    /// it was armed; nil while it is off and not snoozed.
    static func nextRing(of alarm: NotchMascotAlarm, calendar: Calendar) -> Date? {
        if let snoozed = alarm.snoozedUntil { return snoozed }
        guard alarm.enabled else { return nil }
        return occurrence(hour: alarm.hour, minute: alarm.minute, days: alarm.days, after: alarm.armed, calendar: calendar)
    }

    enum Status: Equatable {
        /// Nothing to ring.
        case off
        /// Rings at this time, still to come.
        case waiting(Date)
        /// Its time came this long ago or less: it rings now.
        case due(Date)
        /// Its time went by while the Mac slept, too long ago to ring for.
        case missed(Date)
    }

    static func status(of alarm: NotchMascotAlarm, now: Date, calendar: Calendar, grace: TimeInterval = grace) -> Status {
        guard let ring = nextRing(of: alarm, calendar: calendar) else { return .off }
        if ring > now { return .waiting(ring) }
        return now.timeIntervalSince(ring) <= grace ? .due(ring) : .missed(ring)
    }

    /// `alarm` once it rang, or was missed, at `time`: counted on from
    /// there, its snooze spent, and off if it rings only once.
    static func rang(_ alarm: NotchMascotAlarm, at time: Date) -> NotchMascotAlarm {
        var alarm = alarm
        alarm.armed = max(alarm.armed, time)
        alarm.snoozedUntil = nil
        if !alarm.repeats { alarm.enabled = false }
        return alarm
    }

    /// `alarm` put off at `now` for its snooze minutes.
    static func snoozed(_ alarm: NotchMascotAlarm, at now: Date) -> NotchMascotAlarm {
        var alarm = alarm
        alarm.snoozedUntil = now.addingTimeInterval(TimeInterval(max(1, alarm.snoozeMinutes)) * 60)
        return alarm
    }

    /// `alarm` switched on or off, or changed, at `now`: counted from then.
    static func rearmed(_ alarm: NotchMascotAlarm, enabled: Bool, at now: Date) -> NotchMascotAlarm {
        var alarm = alarm
        alarm.enabled = enabled
        alarm.armed = now
        alarm.snoozedUntil = nil
        return alarm
    }

    /// How long to wait before the next one rings, or before the time is
    /// looked at again, whichever comes first; nil with none to ring.
    static func wait(for alarms: [NotchMascotAlarm], now: Date, calendar: Calendar) -> TimeInterval? {
        let next = alarms.compactMap { alarm -> Date? in
            if case .waiting(let ring) = status(of: alarm, now: now, calendar: calendar) { return ring }
            return nil
        }.min()
        guard let next else { return nil }
        return min(longestWait, max(0, next.timeIntervalSince(now)))
    }

    // MARK: Days

    /// The weekdays Monday to Friday, and Saturday and Sunday.
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekend: Set<Int> = [1, 7]
    static let everyDay: Set<Int> = Set(1...7)

    /// The seven weekdays in the order the calendar's week runs.
    static func weekOrder(_ calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}
