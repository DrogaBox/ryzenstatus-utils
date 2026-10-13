// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// Runs the safe part of the cleanup on a schedule the user picked: daily or
/// weekly at a chosen time. Only ever cleans what a manual scan would start
/// with already checked (the safe groups), everything still goes to the
/// Trash, and an optional notification reports the outcome. Nothing exists
/// while the schedule is off: no timer, no observers, no cost.
final class CleanerScheduler: ObservableObject {
    static let shared = CleanerScheduler()

    /// When the next automatic pass fires; the interface shows this line so
    /// arming the schedule gives visible confirmation on the spot.
    @Published private(set) var nextFire: Date?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObservers: [NSObjectProtocol] = []
    private var runObserver: AnyCancellable?

    private init() {}

    // MARK: - The decisions of one automatic pass

    /// A run missed while the Mac was off or asleep does not fire the instant
    /// the app comes up; it waits a couple of minutes so launch stays snappy.
    static let missedRunDelay: TimeInterval = 120

    /// The user is in the middle of a manual session: their review wins, and
    /// the pass tries again later instead of losing the day.
    static let busyRetryDelay: TimeInterval = 600

    /// What an unattended pass takes out of the scan's pre-checked selection:
    /// login items and root-owned items can raise an administrator prompt or
    /// disappear without anyone having looked at them.
    static let unattendedDeselectedCategories: [CleanerSupport.Category] = [.loginItems]

    /// When the next pass fires: soon after a run the Mac missed, otherwise at
    /// the next calendar moment. Nil when the schedule is off or the calendar
    /// has no answer.
    static func fireDate(now: Date,
                         lastRun: Date?,
                         frequency: CleanerSchedule.Frequency,
                         hour: Int,
                         minute: Int,
                         weekday: Int,
                         calendar: Calendar = .current) -> Date? {
        guard frequency != .off else { return nil }
        if CleanerSchedule.missedRun(now: now, lastRun: lastRun, frequency: frequency,
                                     hour: hour, minute: minute, weekday: weekday,
                                     calendar: calendar) {
            return now.addingTimeInterval(missedRunDelay)
        }
        return CleanerSchedule.nextFireDate(after: now, frequency: frequency,
                                            hour: hour, minute: minute,
                                            weekday: weekday, calendar: calendar)
    }

    /// What the outcome notification says, or nil when the user asked not to be
    /// told. A pass that moved nothing and left nothing still says so, so a
    /// fresh schedule gives proof of life on its first run.
    static func runSummary(freed: Int64,
                           failed: Int,
                           notify: Bool,
                           strings: Strings,
                           byteCount: (Int64) -> String) -> (title: String, body: String)? {
        guard notify else { return nil }
        var sentences: [String] = []
        if freed > 0 {
            sentences.append(String(format: strings.cleanerAutoNotificationFormat,
                                    byteCount(freed)))
        }
        // An unattended pass never escalates, so what it left behind has to be
        // said or a deferred find reads like one that was never there.
        if failed > 0 { sentences.append(strings.uninstallerSomeFailed) }
        if sentences.isEmpty { sentences.append(strings.cleanerNothingFound) }
        return (strings.cleanerScheduleTitle, sentences.joined(separator: " "))
    }

    func syncWithPreferences() {
        let frequency = CleanerSchedule.Frequency.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.cleanerScheduleFrequency) ?? "off")
        guard AppFeature.cleaner.isAvailable, frequency != .off else {
            stop()
            return
        }
        installWakeObserver()
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        for observer in clockObservers { NotificationCenter.default.removeObserver(observer) }
        clockObservers = []
        runObserver = nil
        if nextFire != nil { nextFire = nil }
    }

    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            // A fire date that passed during sleep never triggers its timer;
            // recomputing catches the miss within a couple of minutes.
            self?.scheduleNext()
        }
        // The chosen time means the user's wall clock: when the time zone
        // or the system clock changes, the armed fire date is stale and the
        // schedule recomputes against the new local time.
        clockObservers = [NSNotification.Name.NSSystemTimeZoneDidChange,
                          NSNotification.Name.NSSystemClockDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil,
                                                   queue: .main) { [weak self] _ in
                self?.scheduleNext()
            }
        }
    }

    private var settings: (frequency: CleanerSchedule.Frequency, hour: Int, minute: Int, weekday: Int) {
        let defaults = UserDefaults.standard
        return (CleanerSchedule.Frequency.sanitized(
                    defaults.string(forKey: DefaultsKey.cleanerScheduleFrequency) ?? "off"),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleHour),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleMinute),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleWeekday))
    }

    private func scheduleNext() {
        let current = settings
        guard current.frequency != .off else { return }

        let defaults = UserDefaults.standard
        let lastRunStamp = defaults.double(forKey: DefaultsKey.cleanerLastAutoRun)
        let lastRun = lastRunStamp > 0 ? Date(timeIntervalSince1970: lastRunStamp) : nil

        guard let fireDate = Self.fireDate(now: Date(), lastRun: lastRun,
                                           frequency: current.frequency,
                                           hour: current.hour, minute: current.minute,
                                           weekday: current.weekday) else { return }
        schedule(at: fireDate)
    }

    private func schedule(at fireDate: Date) {
        timer?.invalidate()
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.runAutomaticCleanup()
        }
        // Tight tolerance: one shot a day costs nothing, and a schedule that
        // fires a minute late reads as broken to anyone testing it.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if nextFire != fireDate { nextFire = fireDate }
    }

    /// One automatic pass: scan, clean exactly what the scan pre checked
    /// (the safe groups), record the outcome, leave the tool idle again.
    private func runAutomaticCleanup() {
        let cleaner = JunkCleaner.shared
        guard cleaner.phase == .idle, runObserver == nil else {
            // The user is in the middle of a manual session: their review
            // wins. Try again later instead of losing the day.
            schedule(at: Date().addingTimeInterval(Self.busyRetryDelay))
            return
        }

        // dropFirst: a published property replays its CURRENT value (.idle)
        // to every new subscriber, and that echo must not be read as "the
        // user interrupted the pass" before the pass even started.
        runObserver = cleaner.$phase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .results:
                    // In automated unsupervised runs, unselect login items and root-owned items
                    // to avoid unexpected admin prompts and accidental removal without user review.
                    for category in Self.unattendedDeselectedCategories {
                        cleaner.setInclude(false, forCategory: category)
                    }
                    if cleaner.selectedCount > 0 {
                        cleaner.cleanSelected(escalate: false)
                    } else {
                        self.finishRun(freed: 0, failed: 0)
                    }
                case let .done(freed, failed):
                    self.finishRun(freed: freed, failed: failed)
                case .idle:
                    // The user (or a reset) interrupted the automatic pass.
                    self.runObserver = nil
                    self.scheduleNext()
                default:
                    break
                }
            }
        cleaner.scan(attended: false)
    }

    private func finishRun(freed: Int64, failed: Int) {
        runObserver = nil
        JunkCleaner.shared.reset()
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.cleanerLastAutoRun)
        defaults.set(freed, forKey: DefaultsKey.cleanerLastAutoFreed)
        // A pass that freed nothing still reads as a quiet success unless what
        // it had to leave behind is recorded: the panel and the schedule card
        // say it beside the last run, which is the only visible trace an
        // unattended pass leaves.
        defaults.set(failed, forKey: DefaultsKey.cleanerLastAutoFailed)
        notifyIfWanted(freed: freed, failed: failed)
        scheduleNext()
    }

    /// Reports the outcome when the user asked to be told, through the
    /// app's regular notifier (which drops the note quietly if macOS
    /// notifications are not allowed). Even a run that found nothing posts,
    /// so a fresh schedule gives proof of life on its first pass.
    private func notifyIfWanted(freed: Int64, failed: Int) {
        guard let summary = Self.runSummary(
            freed: freed, failed: failed,
            notify: UserDefaults.standard.bool(forKey: DefaultsKey.cleanerScheduleNotify),
            strings: L10n.shared.s,
            byteCount: { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        ) else { return }
        Notifier.post(title: summary.title, body: summary.body)
    }
}
