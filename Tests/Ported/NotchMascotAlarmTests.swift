// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The companion's alarm clocks: when an alarm rings next for a set of
/// weekdays or once, how a missed one is told from a due one, what ringing,
/// snoozing and rearming do to it, and that the list survives the defaults.
enum NotchMascotAlarmTests {
    typealias Schedule = NotchMascotAlarmSchedule

    static func run(_ suite: TestSuite) {
        occurrences(suite)
        statuses(suite)
        afterRinging(suite)
        storage(suite)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires") ?? .current
        return calendar
    }

    /// A time on a day of November 2026: the 2nd is a Monday.
    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private static func occurrences(_ suite: TestSuite) {
        let monday9 = at(2, 9)
        suite.expect(Schedule.occurrence(hour: 7, minute: 30, days: [], after: monday9, calendar: calendar) == at(3, 7, 30),
                     "a once alarm already past today rings tomorrow")
        suite.expect(Schedule.occurrence(hour: 10, minute: 0, days: [], after: monday9, calendar: calendar) == at(2, 10),
                     "a once alarm still to come today rings today")
        let friday9 = at(6, 9)
        suite.expect(Schedule.occurrence(hour: 7, minute: 0, days: Schedule.weekdays, after: friday9, calendar: calendar)
                     == at(9, 7), "a weekday alarm passes over the weekend to Monday")
        suite.expect(Schedule.occurrence(hour: 8, minute: 0, days: Schedule.weekend, after: monday9, calendar: calendar)
                     == at(7, 8), "a weekend alarm waits for Saturday")
        suite.expect(Schedule.occurrence(hour: 9, minute: 0, days: Schedule.everyDay, after: monday9, calendar: calendar)
                     == at(3, 9), "an alarm at the very time it is armed rings the next day")
    }

    private static func statuses(_ suite: TestSuite) {
        var alarm = NotchMascotAlarm()
        alarm.hour = 7
        alarm.minute = 0
        alarm.armed = at(2, 6)
        suite.expect(Schedule.status(of: alarm, now: at(2, 6, 30), calendar: calendar) == .waiting(at(2, 7)),
                     "before its time it waits")
        suite.expect(Schedule.status(of: alarm, now: at(2, 7, 5), calendar: calendar) == .due(at(2, 7)),
                     "minutes after its time, as after a short sleep, it still rings")
        suite.expect(Schedule.status(of: alarm, now: at(2, 9), calendar: calendar) == .missed(at(2, 7)),
                     "hours after its time it is passed over")
        alarm.enabled = false
        suite.expect(Schedule.status(of: alarm, now: at(2, 7, 5), calendar: calendar) == .off, "switched off it is silent")
    }

    private static func afterRinging(_ suite: TestSuite) {
        var once = NotchMascotAlarm()
        once.hour = 7
        once.armed = at(2, 6)
        let rang = Schedule.rang(once, at: at(2, 7))
        suite.expect(!rang.enabled, "a once alarm switches itself off after ringing")
        var daily = once
        daily.days = Schedule.everyDay
        let again = Schedule.rang(daily, at: at(2, 7))
        suite.expect(again.enabled && Schedule.nextRing(of: again, calendar: calendar) == at(3, 7),
                     "a repeating alarm rings again the next day")
        let snoozed = Schedule.snoozed(daily, at: at(2, 7, 1))
        suite.expect(Schedule.nextRing(of: snoozed, calendar: calendar) == at(2, 7, 1 + Schedule.snoozeMinutes),
                     "snoozed, it rings again \(Schedule.snoozeMinutes) minutes later")
        suite.expect(Schedule.wait(for: [daily], now: at(2, 6), calendar: calendar).map { $0 <= Schedule.longestWait } == true,
                     "no single wait is trusted for longer than the longest")
    }

    private static func storage(_ suite: TestSuite) {
        var alarm = NotchMascotAlarm()
        alarm.hour = 6
        alarm.minute = 45
        alarm.days = Schedule.weekdays
        alarm.label = "Trabajo"
        alarm.sound = "system:Glass"
        let decoded = NotchMascotAlarm.decode(NotchMascotAlarm.encode([alarm]))
        suite.expect(decoded == [alarm], "the list of alarms survives a trip through the defaults")
        suite.expect(NotchMascotAlarm.decode(Data("not json".utf8)).isEmpty, "unreadable data gives an empty list")
    }
}
