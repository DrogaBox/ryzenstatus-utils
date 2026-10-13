// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

// The companion's automatic moods: what it does on its own as the Mac works,
// plays music, sits idle or stays up on Keep Awake. Everything here is pure,
// so the mapping from the Mac's state to a mood, the order moods take when
// several hold at once, and the cooldowns that keep reactions rare can all
// be tested without the island. `NotchMascotAutomation` feeds it the readings
// the app already publishes and plays what it answers.

/// Which kinds of automatic behaviour are switched on.
struct MascotAutomationCategories: Equatable {
    /// Sweating under CPU load, panicking when hot, relaxing after.
    var load = true
    /// Dancing while music plays.
    var music = true
    /// Yawning and dozing off when you are away or late at night, waking up
    /// with a stretch when you come back.
    var rest = true
    /// Drinking coffee while Keep Awake holds the Mac up.
    var coffee = true
    /// Watching a big download come in.
    var network = true
    /// Celebrating what finishes well, and tiring as the battery runs low.
    var events = true
    /// Little things now and then: looking around, waving.
    var antics = true

    static let all = MascotAutomationCategories()
    static let none = MascotAutomationCategories(load: false, music: false, rest: false, coffee: false,
                                                 network: false, events: false, antics: false)
}

/// What the Mac is doing, as the app already reads it. A reading the app
/// does not have, or has not refreshed for a while, is nil.
struct MascotSignals: Equatable {
    /// Share of the CPU in use, 0 to 1.
    var cpuLoad: Double?
    /// The CPU's temperature in °C.
    var cpuTemperature: Double?
    /// Bytes coming in each second.
    var downloadRate: Double?
    var musicPlaying = false
    /// How loud the music is, 0 to 1, when the island reads its levels.
    var musicLevel: Double?
    var keepAwake = false
    /// Seconds since the last keyboard, mouse or trackpad event.
    var idleSeconds: TimeInterval = 0
    /// The hour of the day, 0 to 23.
    var hour = 12
    /// The battery's charge, 0 to 1, nil on a Mac without one.
    var batteryLevel: Double?
    /// Running on the battery, not on power.
    var onBattery = false
    /// The CPU fan's speed as a share of a fast one, 0 to 1, read from the
    /// AMD kext when the companion follows the hardware.
    var fanShare: Double?
    /// The package's power as a share of its limit, 0 to 1.
    var powerShare: Double?
}

/// The mood it keeps for as long as what brought it lasts.
enum MascotAmbient: String, CaseIterable, Equatable {
    case calm
    /// The CPU works hard: it sweats, and a fan spins faster.
    case working
    /// The CPU runs hot: it panics a little and fans itself.
    case overheated
    /// Music plays: it bobs to the beat.
    case dancing
    /// A big download comes in: it watches the arrows.
    case downloading
    /// The battery runs low: it tires.
    case lowBattery
    /// Keep Awake holds the Mac up: coffee in hand.
    case caffeinated
    /// You have been away a while, or it is late: heavy eyes.
    case drowsy
    /// Away for long: asleep.
    case asleep

    /// Whether it shows the CPU working, which it relaxes from.
    var isStrained: Bool { self == .working || self == .overheated }
    /// Whether it rests, which it wakes up from.
    var isResting: Bool { self == .drowsy || self == .asleep }
}

/// The mood, and how much of it, in steps coarse enough that it changes
/// only when the Mac's state really does.
struct MascotMoodState: Equatable {
    var ambient: MascotAmbient = .calm
    /// How hard the CPU works, in quarters from 0 to 1, for a fan's spin.
    /// Zero when the load is unknown or not followed.
    var effort: Double = 0
    /// How lively the music is, in quarters from 0 to 1, while it dances.
    var energy: Double = 0
    /// How brightly a chip's mark glows, in quarters of the package's power
    /// limit. Zero without a reading.
    var glow: Double = 0
}

/// A short reaction it plays on its own.
enum MascotImpulse: String, CaseIterable, Equatable {
    case panic, sweat, celebrate, wake, relax, dance, peek, yawn, sip, wave, lookAround
}

struct MascotMoodEngine {
    // MARK: Thresholds

    /// CPU load it starts sweating at, and the lower one it stops at, so a
    /// load hovering around the line does not flicker its mood.
    static let busyEnter = 0.70
    static let busyExit = 0.50
    /// CPU temperatures it panics at, and calms down below. Ryzen chips run
    /// warm by design, so only a really hot one counts.
    static let hotEnter = 90.0
    static let hotExit = 82.0
    /// Download speeds, in bytes a second, it starts and stops watching at.
    static let downloadEnter = 5.0 * 1_048_576
    static let downloadExit = 1.0 * 1_048_576
    /// Battery charge it tires at, on the battery, and is fine again above.
    static let lowBatteryEnter = 0.20
    static let lowBatteryExit = 0.25
    /// Under this much idle time, you are there: it wakes up.
    static let wakeIdle: TimeInterval = 10

    /// Late at night it grows sleepy much sooner.
    static func isNight(hour: Int) -> Bool { hour >= 23 || hour < 6 }

    /// Idle time after which its eyes grow heavy.
    static func drowsyIdle(hour: Int) -> TimeInterval { isNight(hour: hour) ? 90 : 300 }

    /// Idle time after which it falls asleep.
    static func asleepIdle(hour: Int) -> TimeInterval { isNight(hour: hour) ? 300 : 1200 }

    // MARK: Cooldowns

    /// No two automatic reactions come closer than this, whatever they are.
    static let spacing: TimeInterval = 20
    /// The same reaction does not come back sooner than this.
    static func cooldown(_ impulse: MascotImpulse) -> TimeInterval {
        switch impulse {
        case .panic: return 180
        case .sweat, .relax, .peek: return 300
        case .dance, .yawn: return 600
        case .wake: return 120
        case .celebrate: return 45
        case .sip: return 300
        case .wave, .lookAround: return 240
        }
    }
    /// Antics wait until nothing else has happened for this long.
    static let anticQuiet: TimeInterval = 120
    /// The chance, on each look at the Mac, of an antic or a sip once allowed.
    static let anticChance = 0.25
    static let sipChance = 0.5

    // MARK: State

    private(set) var state = MascotMoodState()
    /// Each condition latches on at its enter threshold and off at its exit
    /// one, even while a stronger mood hides it.
    private(set) var busy = false
    private(set) var hot = false
    private(set) var downloading = false
    private(set) var lowBattery = false
    private var played: [MascotImpulse: TimeInterval] = [:]
    private var lastPlayed: TimeInterval = -.infinity

    init() {}

    /// Takes in the Mac's state at `now` and answers the reaction to play,
    /// if any. `random`, from 0 to 1, decides the occasional antic, and is
    /// passed in so tests can choose it.
    mutating func update(_ signals: MascotSignals, categories: MascotAutomationCategories = .all,
                         now: TimeInterval, random: Double = 0.5) -> MascotImpulse? {
        latch(signals, categories: categories)
        let previous = state.ambient
        let ambient = Self.ambient(signals, busy: busy, hot: hot, downloading: downloading,
                                   lowBattery: lowBattery, categories: categories)
        // A real fan's speed, when the kext reports one, spins the fan.
        state = MascotMoodState(ambient: ambient,
                                effort: categories.load ? Self.quarter(signals.fanShare ?? signals.cpuLoad ?? 0) : 0,
                                energy: ambient == .dancing ? Self.quarter(signals.musicLevel ?? 0.5) : 0,
                                glow: categories.load ? Self.quarter(signals.powerShare ?? 0) : 0)
        for impulse in Self.candidates(from: previous, to: ambient, signals: signals,
                                       categories: categories, random: random) {
            if admits(impulse, at: now) { return impulse }
        }
        return nil
    }

    /// Something finished well, a cleanup that freed space: it celebrates,
    /// unless it just did. Events need not wait out other reactions.
    mutating func celebrate(categories: MascotAutomationCategories = .all, now: TimeInterval) -> MascotImpulse? {
        guard categories.events else { return nil }
        if let last = played[.celebrate], now - last < Self.cooldown(.celebrate) { return nil }
        played[.celebrate] = now
        lastPlayed = now
        return .celebrate
    }

    /// Back to calm with nothing remembered, as when switched off.
    mutating func reset() { self = MascotMoodEngine() }

    // MARK: Rules

    private mutating func latch(_ signals: MascotSignals, categories: MascotAutomationCategories) {
        busy = categories.load && Self.above(signals.cpuLoad, latched: busy, enter: Self.busyEnter, exit: Self.busyExit)
        hot = categories.load && Self.above(signals.cpuTemperature, latched: hot, enter: Self.hotEnter, exit: Self.hotExit)
        downloading = categories.network
            && Self.above(signals.downloadRate, latched: downloading, enter: Self.downloadEnter, exit: Self.downloadExit)
        let charge = signals.onBattery ? signals.batteryLevel : nil
        lowBattery = categories.events
            && Self.below(charge, latched: lowBattery, enter: Self.lowBatteryEnter, exit: Self.lowBatteryExit)
    }

    /// The mood that wins when several hold at once: heat first, then work,
    /// music, a download, a tired battery, coffee and last of all rest.
    static func ambient(_ signals: MascotSignals, busy: Bool, hot: Bool, downloading: Bool, lowBattery: Bool,
                        categories: MascotAutomationCategories) -> MascotAmbient {
        if hot { return .overheated }
        if busy { return .working }
        if categories.music, signals.musicPlaying { return .dancing }
        if downloading { return .downloading }
        if lowBattery { return .lowBattery }
        if categories.coffee, signals.keepAwake { return .caffeinated }
        if categories.rest {
            if signals.idleSeconds >= asleepIdle(hour: signals.hour) { return .asleep }
            if signals.idleSeconds >= drowsyIdle(hour: signals.hour) { return .drowsy }
        }
        return .calm
    }

    /// The reactions a change of mood, or a quiet moment, may bring, the
    /// most important first. Only the first one the cooldowns let through plays.
    static func candidates(from previous: MascotAmbient, to ambient: MascotAmbient, signals: MascotSignals,
                           categories: MascotAutomationCategories, random: Double) -> [MascotImpulse] {
        var list: [MascotImpulse] = []
        if previous != ambient {
            switch ambient {
            case .overheated: list.append(.panic)
            case .working: list.append(.sweat)
            case .dancing: list.append(.dance)
            case .downloading: list.append(.peek)
            case .drowsy: list.append(.yawn)
            default: break
            }
            if previous.isResting, !ambient.isResting, signals.idleSeconds < wakeIdle { list.append(.wake) }
            if previous.isStrained, !ambient.isStrained { list.append(.relax) }
        }
        if ambient == .caffeinated, random < sipChance { list.append(.sip) }
        if categories.antics, ambient == .calm, random < anticChance {
            list.append(random < anticChance / 2 ? .wave : .lookAround)
        }
        let order = MascotImpulse.allCases
        return list.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
    }

    private mutating func admits(_ impulse: MascotImpulse, at now: TimeInterval) -> Bool {
        guard now - lastPlayed >= Self.spacing else { return false }
        if let last = played[impulse], now - last < Self.cooldown(impulse) { return false }
        // Antics wait for a quiet spell, and share one cooldown.
        if impulse == .wave || impulse == .lookAround {
            guard now - lastPlayed >= Self.anticQuiet else { return false }
            for antic in [MascotImpulse.wave, .lookAround] {
                if let last = played[antic], now - last < Self.cooldown(antic) { return false }
            }
        }
        played[impulse] = now
        lastPlayed = now
        return true
    }

    // MARK: Helpers

    /// Latched on at or above `enter`, off below `exit`. No reading lets go.
    static func above(_ value: Double?, latched: Bool, enter: Double, exit: Double) -> Bool {
        guard let value, value.isFinite else { return false }
        return latched ? value >= exit : value >= enter
    }

    /// Latched on at or below `enter`, off above `exit`. No reading lets go.
    static func below(_ value: Double?, latched: Bool, enter: Double, exit: Double) -> Bool {
        guard let value, value.isFinite else { return false }
        return latched ? value <= exit : value <= enter
    }

    /// A share from 0 to 1 rounded to the nearest quarter.
    static func quarter(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (max(0, min(1, value)) * 4).rounded() / 4
    }
}
