// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// The companion's alarm clocks: the list, kept in the defaults, and one
/// wait to the next alarm due, worked out again whenever the list changes,
/// the Mac wakes or the clock, the time zone or the day changes. An alarm
/// whose time went by while the Mac slept rings if that was only minutes
/// ago and is passed over if longer. Ringing is the companion's to show.
final class NotchMascotAlarms: ObservableObject {
    static let shared = NotchMascotAlarms()

    @Published private(set) var alarms: [NotchMascotAlarm]
    /// The alarm ringing now, if one is.
    @Published private(set) var ringing: NotchMascotAlarm?

    private let defaults: UserDefaults
    private var timer: DispatchSourceTimer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var started = false
    private var show: NotchMascotAlarmRing?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alarms = NotchMascotAlarm.decode(defaults.data(forKey: DefaultsKey.notchMascotAlarms))
    }

    private var calendar: Calendar { .autoupdatingCurrent }

    /// Starts keeping time, once, as the app launches.
    func start() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let recheck: (Notification) -> Void = { [weak self] _ in self?.check() }
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                              using: recheck)),
            (local, local.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recheck)),
            (local, local.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: recheck)),
            (local, local.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: recheck)),
        ]
        NotchMascotAlarmPlayer.shared.rangOut = { [weak self] in self?.finishRing(snoozing: false, rangOut: true) }
        check()
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
        timer?.cancel()
    }

    // MARK: The list

    func add(_ alarm: NotchMascotAlarm) {
        alarms.append(NotchMascotAlarmSchedule.rearmed(alarm, enabled: true, at: Date()))
        changed()
    }

    /// Keeps the changes made to `alarm`; it counts from now, switched on.
    func update(_ alarm: NotchMascotAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { add(alarm); return }
        alarms[index] = NotchMascotAlarmSchedule.rearmed(alarm, enabled: true, at: Date())
        changed()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }), alarms[index].enabled != enabled else { return }
        alarms[index] = NotchMascotAlarmSchedule.rearmed(alarms[index], enabled: enabled, at: Date())
        changed()
    }

    func remove(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        if ringing?.id == id { stop() }
        changed()
    }

    /// An added sound taken off the list is replaced in the alarms that used it.
    func forgetSound(_ sound: String) {
        var touched = false
        for index in alarms.indices where alarms[index].sound == sound {
            alarms[index].sound = NotchMascotAlarmSounds.defaultSound
            touched = true
        }
        NotchMascotAlarmSounds.remove(sound)
        if touched { changed() }
    }

    /// When `alarm` rings next, for the list.
    func nextRing(of alarm: NotchMascotAlarm) -> Date? { NotchMascotAlarmSchedule.nextRing(of: alarm, calendar: calendar) }

    private func changed() {
        defaults.set(NotchMascotAlarm.encode(alarms), forKey: DefaultsKey.notchMascotAlarms)
        schedule()
    }

    // MARK: Keeping time

    /// Rings what is due, passes over what was missed too long ago, and
    /// waits for the next one.
    func check() {
        let now = Date()
        var due: [(alarm: NotchMascotAlarm, at: Date)] = []
        var touched = false
        for index in alarms.indices {
            switch NotchMascotAlarmSchedule.status(of: alarms[index], now: now, calendar: calendar) {
            case .due(let time):
                due.append((alarms[index], time))
                alarms[index] = NotchMascotAlarmSchedule.rang(alarms[index], at: time)
                touched = true
            case .missed(let time):
                alarms[index] = NotchMascotAlarmSchedule.rang(alarms[index], at: time)
                touched = true
            case .off, .waiting:
                break
            }
        }
        if touched { defaults.set(NotchMascotAlarm.encode(alarms), forKey: DefaultsKey.notchMascotAlarms) }
        // Two due at once ring as one, the first set; each is told of.
        for (index, item) in due.enumerated() {
            notify(item.alarm)
            if index == 0 { ring(item.alarm) }
        }
        schedule()
    }

    private func schedule() {
        timer?.cancel(); timer = nil
        guard started, let wait = NotchMascotAlarmSchedule.wait(for: alarms, now: Date(), calendar: calendar) else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // On the wall clock, which goes on while the Mac sleeps.
        timer.schedule(wallDeadline: .now() + wait + 0.05, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
    }

    // MARK: Ringing

    private func notify(_ alarm: NotchMascotAlarm) {
        let text = FeatureStrings.notchMascotAlarms(L10n.shared.language)
        Notifier.post(title: alarm.label.isEmpty ? text.alarm : alarm.label, body: text.time(alarm, calendar: calendar))
    }

    private func ring(_ alarm: NotchMascotAlarm) {
        // A new alarm takes over from one still ringing.
        show?.end(snoozed: false)
        ringing = alarm
        NotchMascotAlarmSign.shared.close()
        NotchMascotAlarmPlayer.shared.ring(alarm.sound)
        let show = NotchMascotAlarmRing(alarm: alarm)
        show.stop = { [weak self] in self?.stop() }
        show.snooze = { [weak self] in self?.snooze() }
        self.show = show
        show.begin()
    }

    /// Stops the alarm ringing now.
    func stop() { finishRing(snoozing: false, rangOut: false) }

    /// Puts the alarm ringing now off for its snooze minutes.
    func snooze() { finishRing(snoozing: true, rangOut: false) }

    private func finishRing(snoozing: Bool, rangOut: Bool) {
        guard let alarm = ringing else { return }
        NotchMascotAlarmPlayer.shared.stop()
        ringing = nil
        if snoozing, alarm.snooze, let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = NotchMascotAlarmSchedule.snoozed(alarms[index], at: Date())
            changed()
        }
        show?.end(snoozed: snoozing && alarm.snooze, rangOut: rangOut)
        show = nil
    }

    // MARK: Trying it

    /// Rings `alarm` now without touching the list, as its sign's test does.
    func test(_ alarm: NotchMascotAlarm) {
        guard ringing == nil else { return }
        var trial = alarm
        trial.snooze = false
        ring(trial)
    }
}
