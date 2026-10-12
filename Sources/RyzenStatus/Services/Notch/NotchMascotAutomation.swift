// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import CoreGraphics

/// The companion's automatic reactions. It listens to what the app already
/// publishes (the system monitor's snapshot, Now Playing, the island's audio
/// levels, Keep Awake, the Cleaner) plus one slow check for idle time and the
/// hour, hands it all to `MascotMoodEngine`, publishes the lasting mood for
/// the companion at rest, and plays the reactions the engine answers through
/// the island, which brings the companion out for them like any other.
///
/// It samples nothing itself: a reading the monitor is not taking for some
/// other reason simply stays unknown, and no mood follows from it.
final class NotchMascotAutomation: ObservableObject {
    static let shared = NotchMascotAutomation()

    /// The mood the companion keeps at rest.
    @Published private(set) var state = MascotMoodState()

    /// How often it looks at idle time and the hour, which nothing publishes.
    static let checkInterval: TimeInterval = 15
    /// A monitor reading older than this is no longer the Mac's state.
    static let freshness: TimeInterval = 30

    private var engine = MascotMoodEngine()
    private var running = false
    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private var cpuLoad: Double?
    private var cpuTemperature: Double?
    private var downloadRate: Double?
    private var power: PowerReading?
    private var sampledAt: CFTimeInterval = -.infinity
    private var musicPlaying = false
    private var musicLevel: Double?
    private var cleanerWasRunning = false

    private init() {}

    // MARK: Preferences

    /// Whether automatic reactions are on, for a companion that is on.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchMascotSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotAutomatic)
    }

    static func categories(in defaults: UserDefaults = .standard) -> MascotAutomationCategories {
        MascotAutomationCategories(load: defaults.bool(forKey: DefaultsKey.notchMascotAutoLoad),
                                   music: defaults.bool(forKey: DefaultsKey.notchMascotAutoMusic),
                                   rest: defaults.bool(forKey: DefaultsKey.notchMascotAutoRest),
                                   coffee: defaults.bool(forKey: DefaultsKey.notchMascotAutoCoffee),
                                   network: defaults.bool(forKey: DefaultsKey.notchMascotAutoNetwork),
                                   events: defaults.bool(forKey: DefaultsKey.notchMascotAutoEvents),
                                   antics: defaults.bool(forKey: DefaultsKey.notchMascotAutoAntics))
    }

    // MARK: Lifecycle

    /// Starts or stops with the island and the preferences. Called whenever
    /// either changes; cheap when nothing did.
    func sync(islandRunning: Bool) {
        let wanted = islandRunning && Self.isEnabled()
        if wanted != running {
            running = wanted
            wanted ? start() : stop()
        } else if running {
            evaluate()
        }
    }

    private func start() {
        engine.reset()
        let monitor = SystemMonitor.shared
        monitor.$snapshot
            .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] snapshot in self?.take(snapshot) }
            .store(in: &cancellables)
        NowPlayingService.shared.$snapshot
            .map(\.isPlaying)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.musicPlaying = playing
                self?.evaluate()
            }
            .store(in: &cancellables)
        // The island's live levels arrive thirty times a second; a look every
        // couple of seconds is plenty to tell a quiet song from a loud one.
        NotchAudioLevelService.shared.$levels
            .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] levels in
                guard let self else { return }
                let level = levels.flatMap { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
                let bucket = level.map(MascotMoodEngine.quarter)
                guard bucket != self.musicLevel.map(MascotMoodEngine.quarter) else { return }
                self.musicLevel = level
                self.evaluate()
            }
            .store(in: &cancellables)
        KeepAwakeManager.shared.$isActive
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        cleanerWasRunning = JunkCleaner.shared.phase.isRunning
        JunkCleaner.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.cleanerMoved(to: phase) }
            .store(in: &cancellables)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in self?.evaluate() }
        timer.tolerance = Self.checkInterval / 3
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        evaluate()
    }

    private func stop() {
        cancellables.removeAll()
        checkTimer?.invalidate()
        checkTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        engine.reset()
        cpuLoad = nil; cpuTemperature = nil; downloadRate = nil; power = nil
        musicPlaying = false; musicLevel = nil
        if state != MascotMoodState() { state = MascotMoodState() }
    }

    // MARK: Inputs

    private func take(_ snapshot: SystemSnapshot) {
        cpuLoad = snapshot.cpuUsage
        cpuTemperature = snapshot.cpuTemperature
        downloadRate = snapshot.netDownBytesPerSec
        power = snapshot.power
        sampledAt = CACurrentMediaTime()
        evaluate()
    }

    /// A cleanup that freed space is worth a celebration.
    private func cleanerMoved(to phase: JunkCleaner.Phase) {
        defer { cleanerWasRunning = phase.isRunning }
        guard cleanerWasRunning, case let .done(freed, _) = phase, freed > 0 else { return }
        if let impulse = engine.celebrate(categories: Self.categories(), now: CACurrentMediaTime()) { play(impulse) }
    }

    private var signals: MascotSignals {
        let fresh = CACurrentMediaTime() - sampledAt < Self.freshness
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                            eventType: CGEventType(rawValue: ~0) ?? .null)
        let battery = power.flatMap { $0.hasBattery ? $0 : nil }
        return MascotSignals(cpuLoad: fresh ? cpuLoad : nil,
                             cpuTemperature: fresh ? cpuTemperature : nil,
                             downloadRate: fresh ? downloadRate : nil,
                             musicPlaying: musicPlaying || musicLevel != nil,
                             musicLevel: musicLevel,
                             keepAwake: KeepAwakeManager.shared.isActive,
                             idleSeconds: idle,
                             hour: Calendar.current.component(.hour, from: Date()),
                             batteryLevel: battery.flatMap { $0.chargePercent }.map { Double($0) / 100 },
                             onBattery: battery.map { !$0.externalConnected } ?? false)
    }

    private func evaluate() {
        guard running else { return }
        let impulse = engine.update(signals, categories: Self.categories(), now: CACurrentMediaTime(),
                                    random: Double.random(in: 0..<1))
        if engine.state != state { state = engine.state }
        if let impulse { play(impulse) }
    }

    /// Plays a reaction through the island, which brings the companion out
    /// for it, or plays it where it rests.
    private func play(_ impulse: MascotImpulse) {
        NotchService.shared.reactMascot(impulse.reaction)
    }
}

extension MascotImpulse {
    var reaction: NotchMascotReaction {
        switch self {
        case .panic: return .panic
        case .sweat: return .sweat
        case .celebrate: return .celebrate
        case .wake: return .wakeUp
        case .relax: return .relax
        case .dance: return .groove
        case .peek: return .peek
        case .yawn: return .yawn
        case .sip: return .sip
        case .wave: return .wave
        case .lookAround: return .lookAround
        }
    }
}

extension MascotAmbient {
    /// The face a lasting mood gives it, when nothing else asks for one.
    var face: NotchMascotMood? {
        switch self {
        case .calm: return nil
        case .working: return .determined
        case .overheated: return .confused
        case .dancing: return .happy
        case .downloading: return .searching
        case .caffeinated: return .alert
        case .lowBattery, .drowsy, .asleep: return .sleepy
        }
    }
}
