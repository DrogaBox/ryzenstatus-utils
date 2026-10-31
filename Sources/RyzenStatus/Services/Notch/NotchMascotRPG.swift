// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Combine
import AppKit
import Foundation

// MARK: - Rules

/// The Wonder Boy side of the companion's life: hearts that fill and
/// empty, an hourglass of vitality that runs down while it rests, gold
/// found by living with it, snacks that grow in the track when it is
/// hungry, and secret doors in the island. The rules are plain values, so
/// they are tested without a window; the state that keeps them is
/// `NotchMascotRPGState`.
enum NotchMascotRPG {
    static let baseHeartContainers = 3
    static let maxHeartContainers = 10
    static let maxVitality = 100.0
    /// Below this the snacks grow in the track.
    static let snackThreshold = 30.0
    /// A full hourglass lasts about fourteen hours of the island running.
    static let drainPerSecond = maxVitality / (14 * 3600)
    /// Below this the hearts start to fade.
    static let starvingThreshold = 10.0
    /// Hearts lost per second while starving, and regained per second otherwise.
    static let heartLossPerSecond = 1.0 / 900
    static let heartGainPerSecond = 1.0 / 1800
    /// A pat in the island brings this much experience, at most this often.
    static let islandPatExperience = 15
    static let islandPatInterval: TimeInterval = 60
    /// What the boots from the shop and the wizard's charm last.
    static let buffLength: TimeInterval = 90
    /// The experience and gold the chest of the boss's lair holds.
    static let bossExperience = 50
    static let bossGold = 120
    /// Gold for a synergy found for the first time.
    static let discoveryGold = 30

    /// A heart container for every seven levels, from three to ten.
    static func heartContainers(forLevel level: Int) -> Int {
        min(maxHeartContainers, baseHeartContainers + max(0, level - 1) / 7)
    }

    static func clampVitality(_ value: Double) -> Double { min(maxVitality, max(0, value)) }

    static func isHungry(vitality: Double) -> Bool { vitality < snackThreshold }

    /// The hearts after `elapsed` seconds that began with `vitality` and ran
    /// it down at `drainPerSecond`: they come back slowly while it is fed
    /// and fade once it starves, never below one. A long pause, such as a
    /// locked screen, counts in one step what many short ones would.
    static func hearts(_ hearts: Double, containers: Int, vitality: Double, elapsed: TimeInterval) -> Double {
        let full = Double(containers)
        // The moment within `elapsed` the hourglass falls below the threshold.
        let fed = min(elapsed, max(0, (vitality - starvingThreshold) / drainPerSecond))
        var next = hearts
        if fed > 0 { next = min(full, next + fed * heartGainPerSecond) }
        if elapsed > fed { next = max(1, next - (elapsed - fed) * heartLossPerSecond) }
        return next
    }

    // MARK: Main-actor access for the rest of the island

    /// The shared state, for code that already runs on the main thread, as
    /// everything that draws the companion does.
    static var state: NotchMascotRPGState { MainActor.assumeIsolated { NotchMascotRPGState.shared } }

    static func collect(gold amount: Int) {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.collect(gold: amount) }
    }

    static func snapshot() -> NotchMascotRPGSnapshot {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.snapshot }
    }

    static func tick(elapsed: TimeInterval, level: Int) {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.tick(elapsed: elapsed, level: level) }
    }

    static func flush() {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.flush() }
    }

    static func feed(_ snack: NotchMascotSnack) {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.feed(snack) }
    }

    static func enter(_ door: WonderBoySecretDoor) {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.enter(door) }
    }

    @discardableResult
    static func discover(_ id: String) -> Bool {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.discover(id) }
    }

    static var stepBuffActive: Bool {
        MainActor.assumeIsolated { NotchMascotRPGState.shared.stepBuffActive }
    }

    /// What a play that ran to its end leaves behind: a snack fills the
    /// hourglass, a door gives what it holds, a combo is found.
    static func applyOutcome(of play: NotchMascotIslandPlay) {
        switch play.kind {
        case .snack:
            for beat in play.beats {
                if case .snack(let snack)? = beat.flight?.thing { feed(snack); break }
            }
        case .door(let door):
            enter(door)
        case .synergy(let id):
            discover(id)
            if case .door(let door)? = NotchMascotSynergyCatalog.synergy(id: id)?.script { enter(door) }
        case .ability:
            collect(gold: 1)
        default:
            break
        }
    }
}

/// What the island and the desktop read of the state as they choose a play.
struct NotchMascotRPGSnapshot: Equatable {
    var heartContainers = NotchMascotRPG.baseHeartContainers
    var currentHearts = Double(NotchMascotRPG.baseHeartContainers)
    var vitality = NotchMascotRPG.maxVitality
    var gold = 0
    var discovered: Set<String> = []

    var isHungry: Bool { NotchMascotRPG.isHungry(vitality: vitality) }
}

// MARK: - Doors, snacks and abilities

/// The secret doors that open in the island, behind the camera.
enum WonderBoySecretDoor: String, CaseIterable, Identifiable {
    /// Arms and winged boots: the steps get quicker for a while.
    case shop
    /// The inn: two seconds of music, hearts and vitality made full.
    case inn
    /// The tavern: a toast, and a hint of a combo not found yet.
    case tavern
    /// The wizard's hut: arcane smoke, and the arms leave trails.
    case wizardHut
    /// The boss's lair: a quick fight behind the camera, and a chest.
    case bossLair

    var id: String { rawValue }

    /// How long the door stays open in the play.
    var openLength: TimeInterval {
        switch self {
        case .shop: return 2.4
        case .inn: return 2.0
        case .tavern: return 2.6
        case .wizardHut: return 2.4
        case .bossLair: return 3.2
        }
    }

    var symbol: String {
        switch self {
        case .shop: return "bag.fill"
        case .inn: return "bed.double.fill"
        case .tavern: return "wineglass.fill"
        case .wizardHut: return "wand.and.stars"
        case .bossLair: return "flame.fill"
        }
    }

    /// The doors the Pocket Card offers to walk into.
    static let visitable: [WonderBoySecretDoor] = [.shop, .inn, .tavern]
}

/// What grows in the track when the hourglass is low.
enum NotchMascotSnack: String, CaseIterable, Identifiable {
    case apple, banana, iceCream, onigiri, ramen, bobaTea

    var id: String { rawValue }

    /// The arcade points that float up when it is eaten.
    var points: Int {
        switch self {
        case .apple: return 100
        case .banana: return 200
        case .iceCream: return 200
        case .onigiri: return 500
        case .ramen: return 500
        case .bobaTea: return 0
        }
    }

    /// The marker that floats up: points, or a heart for the boba.
    var marker: String { points > 0 ? "+\(points)" : "♥ +1" }

    var heartsBonus: Double { self == .bobaTea ? 1 : 0 }

    /// How much of the hourglass it fills.
    var vitality: Double {
        switch self {
        case .apple: return 15
        case .banana: return 20
        case .iceCream: return 20
        case .onigiri: return 30
        case .ramen: return 35
        case .bobaTea: return 25
        }
    }

    /// Gold in the pocket for it: a coin for every hundred points, one for the boba.
    var gold: Int { points > 0 ? points / 25 : 5 }
}

/// What a form can do that the others cannot, drawn on the strip and on
/// the desktop as a play of its own.
enum NotchMascotAbility: String, CaseIterable, Identifiable {
    /// Walks upside down along the island's upper edge.
    case ceilingWalk
    /// Breathes fireballs that bounce.
    case fireballBreath
    /// Glides down from the camera.
    case glide
    /// Dives into the liquid edge of the capsule.
    case dolphinDive
    /// A double jump off the friend, like Asha and Pepelogoo.
    case pepelogooSpringboard

    var id: String { rawValue }

    /// The ability a figure has, if any: the slime clings and dives, the
    /// cat is the mouse on the ceiling, the fan and the ghost glide, the
    /// chip and the robot breathe fire, and the comic's pair spring.
    static func of(_ style: NotchMascotStyle) -> NotchMascotAbility? {
        switch style {
        case .cat: return .ceilingWalk
        case .chip, .robot, .phoenix, .dragon, .kitsune: return .fireballBreath
        case .fan, .ghost, .devourer, .swan, .android: return .glide
        case .slime, .shifter, .axolotl, .frog: return .dolphinDive
        case .mouse, .penguin: return .dolphinDive
        case .cristobal, .whiteRabbit, .dog, .capybara, .ballerina, .danseur, .contemporary, .hologram:
            return .pepelogooSpringboard
        case .minimal: return nil
        }
    }
}

// MARK: - State

/// What the companion has gathered and how it fares: hearts, the hourglass,
/// gold and the combos it has tried. Kept in the preferences.
@MainActor
public final class NotchMascotRPGState: ObservableObject {
    static let shared = NotchMascotRPGState()

    /// From three to ten.
    @Published public var heartContainers: Int {
        didSet {
            let clamped = min(NotchMascotRPG.maxHeartContainers, max(NotchMascotRPG.baseHeartContainers, heartContainers))
            if clamped != heartContainers { heartContainers = clamped; return }
            defaults.set(heartContainers, forKey: DefaultsKey.notchMascotHeartContainers)
            if currentHearts > Double(heartContainers) { currentHearts = Double(heartContainers) }
        }
    }

    /// 0...10, never more than the containers.
    @Published public var currentHearts: Double {
        didSet {
            let clamped = min(Double(heartContainers), max(0, currentHearts))
            if clamped != currentHearts { currentHearts = clamped; return }
            scheduleSave()
        }
    }

    /// 0...100; it runs down very slowly while it rests.
    @Published public var hourglassVitality: Double {
        didSet {
            let clamped = NotchMascotRPG.clampVitality(hourglassVitality)
            if clamped != hourglassVitality { hourglassVitality = clamped; return }
            scheduleSave()
        }
    }

    /// Found by living with it: pats, moments, days and chests.
    @Published public var goldCoins: Int {
        didSet {
            if goldCoins < 0 { goldCoins = 0; return }
            scheduleSave()
        }
    }

    /// The ids of the synergies it has played.
    @Published public var discoveredSynergies: Set<String> {
        didSet { defaults.set(discoveredSynergies.sorted(), forKey: DefaultsKey.notchMascotSynergies) }
    }

    /// What the shop shows now. Kept in the preferences between visits.
    @Published private(set) var shopStock: [NotchMascotAccessory]
    /// Counts the purchases, so a view that lists what is owned redraws.
    @Published public private(set) var purchases = 0

    /// The last hint the tavern gave: the name of a combo not found yet.
    @Published public private(set) var lastHint: String?

    /// The hourglass and the hearts change every few seconds while it rests.
    /// Writing them each time would wake every preference observer in the app
    /// (the island syncs its whole state on any change), so they are saved
    /// together a minute later, and at once when the app quits.
    private var saveWork: DispatchWorkItem?
    private static let saveDelay: TimeInterval = 60

    private func scheduleSave() {
        guard saveWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes the hourglass and the hearts now.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        defaults.set(currentHearts, forKey: DefaultsKey.notchMascotCurrentHearts)
        defaults.set(hourglassVitality, forKey: DefaultsKey.notchMascotVitality)
        defaults.set(goldCoins, forKey: DefaultsKey.notchMascotGold)
    }

    private var stepBuffUntil: Date = .distantPast
    private var enchantUntil: Date = .distantPast
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let containers = defaults.object(forKey: DefaultsKey.notchMascotHeartContainers) as? Int
            ?? NotchMascotRPG.baseHeartContainers
        let clampedContainers = min(NotchMascotRPG.maxHeartContainers,
                                    max(NotchMascotRPG.baseHeartContainers, containers))
        heartContainers = clampedContainers
        let hearts = defaults.object(forKey: DefaultsKey.notchMascotCurrentHearts) as? Double
            ?? Double(clampedContainers)
        currentHearts = min(Double(clampedContainers), max(0, hearts))
        let vitality = defaults.object(forKey: DefaultsKey.notchMascotVitality) as? Double
            ?? NotchMascotRPG.maxVitality
        hourglassVitality = NotchMascotRPG.clampVitality(vitality)
        goldCoins = max(0, defaults.integer(forKey: DefaultsKey.notchMascotGold))
        discoveredSynergies = Set(defaults.stringArray(forKey: DefaultsKey.notchMascotSynergies) ?? [])
        NotchMascotShop.migrateOnce(level: NotchMascotSupport.shownLevel())
        shopStock = (defaults.stringArray(forKey: DefaultsKey.notchMascotShopStock) ?? [])
            .compactMap(NotchMascotAccessory.init(rawValue:))
            .filter { $0.isPurchasable && !NotchMascotShop.owns($0) }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    var snapshot: NotchMascotRPGSnapshot {
        NotchMascotRPGSnapshot(heartContainers: heartContainers, currentHearts: currentHearts,
                               vitality: hourglassVitality, gold: goldCoins, discovered: discoveredSynergies)
    }

    var isHungry: Bool { NotchMascotRPG.isHungry(vitality: hourglassVitality) }

    /// Winged boots from the shop make the steps quicker for a while.
    var stepBuffActive: Bool { stepBuffUntil > Date() }

    /// The wizard's charm leaves trails behind the arms for a while.
    var enchantActive: Bool { enchantUntil > Date() }

    func collect(gold amount: Int) {
        guard amount > 0 else { return }
        goldCoins += amount
    }

    /// `elapsed` seconds of rest: the hourglass runs down, the hearts follow
    /// it, and a new level may bring a heart container.
    func tick(elapsed: TimeInterval, level: Int) {
        guard elapsed > 0 else { return }
        let vitality = hourglassVitality
        hourglassVitality = NotchMascotRPG.clampVitality(vitality - elapsed * NotchMascotRPG.drainPerSecond)
        let containers = NotchMascotRPG.heartContainers(forLevel: level)
        if containers > heartContainers {
            heartContainers = containers
            currentHearts = Double(containers)
        }
        currentHearts = NotchMascotRPG.hearts(currentHearts, containers: heartContainers,
                                              vitality: vitality, elapsed: elapsed)
    }

    /// A snack eaten: the hourglass fills, the points become gold, the boba a heart.
    func feed(_ snack: NotchMascotSnack) {
        hourglassVitality += snack.vitality
        currentHearts += snack.heartsBonus
        collect(gold: snack.gold)
    }

    /// Walks through a door and takes what it holds.
    func enter(_ door: WonderBoySecretDoor) {
        switch door {
        case .shop:
            stepBuffUntil = Date().addingTimeInterval(NotchMascotRPG.buffLength)
            // Each visit finds the stall stocked differently.
            restock()
        case .inn:
            currentHearts = Double(heartContainers)
            hourglassVitality = NotchMascotRPG.maxVitality
        case .tavern:
            lastHint = NotchMascotSynergyCatalog.hint(excluding: discoveredSynergies)?.id
            hourglassVitality += 10
        case .wizardHut:
            enchantUntil = Date().addingTimeInterval(NotchMascotRPG.buffLength)
        case .bossLair:
            collect(gold: NotchMascotRPG.bossGold)
            NotchMascotBondStore.shared.award(experience: NotchMascotRPG.bossExperience)
        }
    }

    // MARK: The shop

    private func saveStock() {
        defaults.set(shopStock.map(\.rawValue), forKey: DefaultsKey.notchMascotShopStock)
    }

    private func restock() {
        shopStock = NotchMascotShop.roll(gold: goldCoins)
        saveStock()
    }

    /// Opens the stall: stocked on the first visit, as it was left after.
    func openShop() {
        if shopStock.isEmpty { restock() }
    }

    /// Pays for something shown. False when it is not shown or the gold falls short.
    @discardableResult
    func buy(_ item: NotchMascotAccessory) -> Bool {
        guard shopStock.contains(item), goldCoins >= item.price else { return false }
        goldCoins -= item.price
        // The item is kept at once, so the gold paid for it is too.
        flush()
        NotchMascotShop.grant(item)
        shopStock.removeAll { $0 == item }
        saveStock()
        purchases += 1
        return true
    }

    /// Changes the display for a few coins.
    @discardableResult
    func rerollShop() -> Bool {
        guard goldCoins >= NotchMascotShop.rerollPrice else { return false }
        goldCoins -= NotchMascotShop.rerollPrice
        flush()
        restock()
        return true
    }

    /// A combo played. True the first time, which brings a little gold.
    @discardableResult
    func discover(_ id: String) -> Bool {
        guard !discoveredSynergies.contains(id) else { return false }
        discoveredSynergies.insert(id)
        collect(gold: NotchMascotRPG.discoveryGold)
        return true
    }

    func resetProgress() {
        heartContainers = NotchMascotRPG.baseHeartContainers
        currentHearts = Double(NotchMascotRPG.baseHeartContainers)
        hourglassVitality = NotchMascotRPG.maxVitality
        goldCoins = 0
        discoveredSynergies = []
        lastHint = nil
        NotchMascotShop.resetOwned()
        shopStock = []
        saveStock()
        purchases += 1
        flush()
    }
}
