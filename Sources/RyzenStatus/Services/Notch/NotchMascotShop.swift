// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// How rare a thing in the shop is: the rarer, the dearer and the less often shown.
enum NotchMascotRarity: Int, CaseIterable, Comparable {
    case common, uncommon, rare, legendary

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// How likely a slot of the shop is to hold this rarity, out of a hundred.
    var chance: Double {
        switch self {
        case .common: return 55
        case .uncommon: return 28
        case .rare: return 13
        case .legendary: return 4
        }
    }

    /// The least and the most it costs, in gold.
    var priceRange: ClosedRange<Int> {
        switch self {
        case .common: return 40...90
        case .uncommon: return 150...350
        case .rare: return 500...900
        case .legendary: return 1200...2000
        }
    }
}

extension NotchMascotAccessory {
    var rarity: NotchMascotRarity {
        switch self {
        case .iceCreamCone, .onigiri, .ramenBowl, .bobaTea, .sleepMask, .pacifier, .goldBag, .hourglass,
             .rubberDuck, .bananaPeel, .clownNose, .whoopeeCushion, .trafficCone, .wiltedFlower, .tissueBox,
             .piggyBank, .alarmClock:
            return .common
        case .legendShield, .knightHelm, .vikingHelm, .wingBoots, .rangerBow, .boomerang, .heartPotion, .bardLute,
             .dumbbells, .detectiveLens, .gameController, .goldenKey,
             .creamPie, .fakeMustache, .stormCloud, .lonelyBalloon, .teddyBear, .tinfoilHat, .dynamiteStick:
            return .uncommon
        case .legendSword, .katana, .wizardStaff, .magicTome, .crystalOrb, .fireballSpell, .tornadoSpell,
             .laserVisor, .jetpack,
             .brokenLocket, .magicMushroom, .discoBall, .alienAntenna, .mimicChest:
            return .rare
        case .kingScepter, .thunderTalisman, .angelWings, .crystalSkull, .cursedMask, .unicornHorn:
            return .legendary
        default:
            return .common
        }
    }

    /// Gold it costs: within its rarity's range, always the same for the same thing.
    var price: Int {
        guard isPurchasable else { return 0 }
        let range = rarity.priceRange
        let seed = rawValue.unicodeScalars.reduce(UInt32(5381)) { $0 &* 33 &+ $1.value }
        let span = range.upperBound - range.lowerBound + 1
        // Tens, so the prices read cleanly.
        let step = max(1, span / 10)
        return range.lowerBound + Int(seed % UInt32(max(1, span / step))) * step
    }
}

/// What has been bought, and what the shop shows. Readable from anywhere:
/// the wardrobe asks it while it draws.
enum NotchMascotShop {
    /// Items shown at a time.
    static let slots = 4
    /// What changing the display costs.
    static let rerollPrice = 25

    private static let lock = NSLock()
    private static var cached: Set<String>?

    /// Whether `item` is worn-ready: the name that unlocks everything owns it all.
    static func owns(_ item: NotchMascotAccessory) -> Bool {
        guard item.isPurchasable else { return true }
        if NotchMascotGrowth.unlocksEverything(name: UserDefaults.standard.string(forKey: DefaultsKey.notchMascotName)) {
            return true
        }
        return ownedSet().contains(item.rawValue)
    }

    static func ownedSet() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let loaded = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.notchMascotOwned) ?? [])
        cached = loaded
        return loaded
    }

    static func grant(_ item: NotchMascotAccessory) {
        guard item.isPurchasable else { return }
        var owned = ownedSet()
        owned.insert(item.rawValue)
        store(owned)
    }

    static func resetOwned() { store([]) }

    private static func store(_ owned: Set<String>) {
        lock.lock()
        cached = owned
        lock.unlock()
        UserDefaults.standard.set(owned.sorted(), forKey: DefaultsKey.notchMascotOwned)
    }

    /// Carries the old level unlocks over once: what a level had already
    /// opened stays owned.
    static func migrateOnce(level: Int) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.notchMascotShopMigrated) else { return }
        defaults.set(true, forKey: DefaultsKey.notchMascotShopMigrated)
        // The thirty-two used to open one a level, from the nineteenth.
        for (index, item) in NotchMascotAccessory.rpgItems.enumerated() where index + 19 <= level {
            grant(item)
        }
    }

    /// Everything that can still be bought.
    static var unowned: [NotchMascotAccessory] {
        let owned = ownedSet()
        return NotchMascotAccessory.rpgItems.filter { !owned.contains($0.rawValue) }
            + NotchMascotAccessory.shopItems.filter { !owned.contains($0.rawValue) }
    }

    /// What the shop shows now: a draw by rarity, never twice the same thing and
    /// never what is owned. A rarity with nothing left gives way to the next
    /// nearest. With `gold` too little for anything shown, the cheapest thing
    /// takes the last slot, so a visit always has something within reach.
    static func roll(gold: Int, random: () -> Double = { Double.random(in: 0..<1) }) -> [NotchMascotAccessory] {
        var pool = unowned
        var stock: [NotchMascotAccessory] = []
        while stock.count < slots, !pool.isEmpty {
            let rarity = draw(random: random)
            let order = NotchMascotRarity.allCases.sorted {
                abs($0.rawValue - rarity.rawValue) < abs($1.rawValue - rarity.rawValue)
            }
            guard let match = order.first(where: { tier in pool.contains { $0.rarity == tier } }) else { break }
            let options = pool.filter { $0.rarity == match }
            let pick = options[min(options.count - 1, Int(random() * Double(options.count)))]
            stock.append(pick)
            pool.removeAll { $0 == pick }
        }
        if !stock.isEmpty, !stock.contains(where: { $0.price <= gold }),
           let cheap = unowned.filter({ !stock.contains($0) }).min(by: { $0.price < $1.price }), cheap.price <= gold {
            stock[stock.count - 1] = cheap
        }
        return stock
    }

    /// The rarity a slot holds for a roll of `random`.
    static func draw(random: () -> Double) -> NotchMascotRarity {
        var roll = random() * 100
        for rarity in NotchMascotRarity.allCases {
            if roll < rarity.chance { return rarity }
            roll -= rarity.chance
        }
        return .common
    }
}
