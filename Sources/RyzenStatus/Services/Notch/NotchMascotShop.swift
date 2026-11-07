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
             .piggyBank, .alarmClock, .rosinBox, .plantarBall,
             .umbrella, .yoyo, .bubbleWand, .fortuneCookie,
             .maracas, .soccerBall, .pillow, .marshmallowStick, .paperPlane, .whistle,
             .pizzaSlice, .kazoo, .bubbleGum, .crackerCrown, .rubberChicken:
            return .common
        case .matchaBowl, .shovel:
            return .common
        case .karateBelt, .painterBeret, .boxingGloves, .pogoStick:
            return .uncommon
        case .electricGuitar, .telescope:
            return .rare
        case .legendShield, .knightHelm, .vikingHelm, .wingBoots, .rangerBow, .boomerang, .heartPotion, .bardLute,
             .dumbbells, .detectiveLens, .gameController, .goldenKey,
             .creamPie, .fakeMustache, .stormCloud, .lonelyBalloon, .teddyBear, .tinfoilHat, .dynamiteStick,
             .icePack, .warmUpBooties, .pointeShoes,
             .propellerCap, .springShoes, .skateboard, .horseshoeMagnet,
             .kite, .waterPistol, .megaphone, .hulaHoop, .jugglingBalls, .walkieTalkie, .picnicBasket,
             .snail, .jesterHat, .snorkelMask, .pirateHook, .featherBoa, .rollerSkates, .lantern:
            return .uncommon
        case .legendSword, .katana, .wizardStaff, .magicTome, .crystalOrb, .fireballSpell, .tornadoSpell,
             .laserVisor, .jetpack,
             .brokenLocket, .magicMushroom, .discoBall, .alienAntenna, .mimicChest, .spanishFan,
             .parrot, .snowGlobe, .instantCamera,
             .drum, .microphone, .confettiCannon,
             .wizardBeard, .beeHalo, .spiderMonocle:
            return .rare
        case .kingScepter, .thunderTalisman, .angelWings, .crystalSkull, .cursedMask, .unicornHorn, .swanCrown,
             .luckyDice, .ufoHat:
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

/// What each companion has bought and brought along, and what the shop
/// shows. Readable from anywhere: the wardrobe asks it while it draws.
/// Every figure keeps a wardrobe of its own: the island's companion, its
/// friend and every guest own what was bought for them and a couple of
/// things they came with, and none of them wears another's.
enum NotchMascotShop {
    /// Items shown at a time.
    static let slots = 4
    /// What changing the display costs.
    static let rerollPrice = 25
    /// How many things a figure brings along from home before anything is
    /// bought for it, so a guest has something to play with.
    static let kitSize = 2
    private static let lock = NSLock()
    /// Style raw value to what was bought for it.
    private static var cached: [String: Set<String>]?
    /// The figure a plain question is about: the island's own companion.
    static func activeStyle(in defaults: UserDefaults = .standard) -> NotchMascotStyle {
        NotchMascotStyle.resolved(defaults.string(forKey: DefaultsKey.notchMascotStyle),
                                  name: defaults.string(forKey: DefaultsKey.notchMascotName))
    }
    /// Whether the island's companion may wear `item`.
    static func owns(_ item: NotchMascotAccessory) -> Bool { owns(item, by: activeStyle()) }
    /// Whether `style` may wear `item`: bought for it, brought along by it,
    /// or everything for the island's companion when its name unlocks it
    /// all. The name lifts only the companion itself, never its friend or a
    /// guest, so they keep wardrobes of their own.
    static func owns(_ item: NotchMascotAccessory, by style: NotchMascotStyle) -> Bool {
        guard item.isPurchasable else { return true }
        if style == activeStyle(),
           NotchMascotGrowth.unlocksEverything(name: UserDefaults.standard.string(forKey: DefaultsKey.notchMascotName)) {
            return true
        }
        return bought(by: style).contains(item.rawValue) || startingKit(for: style).contains(item)
    }
    /// What was bought for `style`, raw values.
    static func bought(by style: NotchMascotStyle) -> Set<String> {
        inventories()[style.rawValue] ?? []
    }
    /// The island's companion's own bought things, as it has always read.
    static func ownedSet() -> Set<String> { bought(by: activeStyle()) }
    /// Everything `style` may wear that is bought with gold: bought or brought along.
    static func inventory(of style: NotchMascotStyle) -> Set<NotchMascotAccessory> {
        var items = Set(bought(by: style).compactMap(NotchMascotAccessory.init(rawValue:)))
        items.formUnion(startingKit(for: style))
        return items
    }
    /// The two things a figure brings along from home: always the same for
    /// the same figure, drawn from the toys, the party gear and the
    /// oddities, so every figure has its own habits from the first visit.
    static func startingKit(for style: NotchMascotStyle) -> [NotchMascotAccessory] {
        let pool = NotchMascotAccessory.toyItems + NotchMascotAccessory.partyItems + NotchMascotAccessory.oddityItems
        var kit: [NotchMascotAccessory] = []
        var hash = NotchMascotRapport.stableHash(style.rawValue + "·kit")
        while kit.count < kitSize, kit.count < pool.count {
            let pick = pool[Int(hash % UInt64(pool.count))]
            if !kit.contains(pick) { kit.append(pick) }
            hash = NotchMascotRapport.stableHash(String(hash))
        }
        return kit
    }
    private static func inventories() -> [String: Set<String>] {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let defaults = UserDefaults.standard
        var loaded: [String: Set<String>] = [:]
        if let stored = defaults.dictionary(forKey: DefaultsKey.notchMascotInventories) as? [String: [String]] {
            loaded = stored.mapValues(Set.init)
        }
        // What was bought before every figure had a wardrobe of its own
        // belongs to the companion it was bought for: the island's own.
        if !defaults.bool(forKey: DefaultsKey.notchMascotInventoryMigrated) {
            let legacy = Set(defaults.stringArray(forKey: DefaultsKey.notchMascotOwned) ?? [])
            if !legacy.isEmpty {
                let owner = activeStyle(in: defaults).rawValue
                loaded[owner, default: []].formUnion(legacy)
            }
            defaults.set(true, forKey: DefaultsKey.notchMascotInventoryMigrated)
            defaults.set(loaded.mapValues { $0.sorted() }, forKey: DefaultsKey.notchMascotInventories)
        }
        cached = loaded
        return loaded
    }
    /// Buys `item` for `style`, the island's companion by default.
    static func grant(_ item: NotchMascotAccessory, to style: NotchMascotStyle? = nil) {
        guard item.isPurchasable else { return }
        let owner = style ?? activeStyle()
        var all = inventories()
        all[owner.rawValue, default: []].insert(item.rawValue)
        store(all)
    }
    /// Starts `style` over with only what it brought along; every figure with nil.
    static func resetOwned(for style: NotchMascotStyle? = nil) {
        var all = inventories()
        if let style { all[style.rawValue] = nil } else { all = [:] }
        store(all)
    }
    private static func store(_ all: [String: Set<String>]) {
        lock.lock()
        cached = all
        lock.unlock()
        let defaults = UserDefaults.standard
        defaults.set(all.mapValues { $0.sorted() }, forKey: DefaultsKey.notchMascotInventories)
        // The companion's own, as older readers of the single list expect.
        defaults.set((all[activeStyle(in: defaults).rawValue] ?? []).sorted(), forKey: DefaultsKey.notchMascotOwned)
    }
    /// Carries the old level unlocks over once: what a level had already
    /// opened stays owned by the island's companion.
    static func migrateOnce(level: Int) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.notchMascotShopMigrated) else { return }
        defaults.set(true, forKey: DefaultsKey.notchMascotShopMigrated)
        // The thirty-two used to open one a level, from the nineteenth.
        for (index, item) in NotchMascotAccessory.rpgItems.enumerated() where index + 19 <= level {
            grant(item)
        }
    }
    /// Everything that can be bought at all.
    static var forSale: [NotchMascotAccessory] {
        NotchMascotAccessory.rpgItems + NotchMascotAccessory.shopItems
            + NotchMascotAccessory.danceItems + NotchMascotAccessory.toyItems + NotchMascotAccessory.partyItems
            + NotchMascotAccessory.oddityItems + NotchMascotAccessory.craftItems
    }
    /// Everything the island's companion can still be bought.
    static var unowned: [NotchMascotAccessory] { unowned(for: activeStyle()) }
    /// Everything `style` does not have yet.
    static func unowned(for style: NotchMascotStyle) -> [NotchMascotAccessory] {
        let owned = inventory(of: style)
        return forSale.filter { !owned.contains($0) }
    }

    /// What the shop shows now: a draw by rarity, never twice the same thing and
    /// never what is owned. A rarity with nothing left gives way to the next
    /// nearest. With `gold` too little for anything shown, the cheapest thing
    /// takes the last slot, so a visit always has something within reach.
    static func roll(gold: Int, for style: NotchMascotStyle? = nil,
                     random: () -> Double = { Double.random(in: 0..<1) }) -> [NotchMascotAccessory] {
        let unowned = unowned(for: style ?? activeStyle())
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
