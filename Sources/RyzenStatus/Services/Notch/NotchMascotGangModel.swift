// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// How often other companions come by the desktop on a visit of their own.
enum NotchMascotGangVisits: String, CaseIterable, Identifiable {
    case off, rare, normal, frequent

    var id: String { rawValue }

    /// How long until the next one comes, in seconds; nil when none do.
    var delay: ClosedRange<TimeInterval>? {
        switch self {
        case .off: return nil
        case .rare: return 900...1800
        case .normal: return 300...600
        case .frequent: return 90...210
        }
    }
    /// How long the first ones take once visits start, or the island
    /// starts: soon, so a setting just picked shows what it does.
    var firstDelay: ClosedRange<TimeInterval>? {
        switch self {
        case .off: return nil
        case .rare: return 240...600
        case .normal: return 60...180
        case .frequent: return 20...60
        }
    }
    /// How many come together when `free` more may be out: frequent visits
    /// come in bunches that can fill the desktop, the others one or two.
    func arrivals(free: Int, random: () -> Double) -> Int {
        guard free > 0 else { return 0 }
        switch self {
        case .off: return 0
        case .frequent: return 1 + min(free - 1, Int(random() * Double(free)))
        case .normal: return min(free, random() < 0.45 ? 2 : 1)
        case .rare: return min(free, random() < Self.pairChance ? 2 : 1)
        }
    }

    /// How many guests may be out at once: the setting's choices, its
    /// default, and the choice that lets every figure come.
    static let atOnceChoices = [1, 2, 3, 4, 6, 8, 12, everyone]
    static let defaultAtOnce = 2
    static let everyone = 99
    /// The most guests ever out: one of every figure.
    static var mostGuests: Int { NotchMascotStyle.allCases.count }
    /// No more than this many companions are ever out on the desktop: the
    /// island's two and every guest.
    static var mostOut: Int { mostGuests + 2 }
    /// How long a visit lasts.
    static let stay: ClosedRange<TimeInterval> = 180...600
    /// What "Stay longer" adds to it.
    static let longer: TimeInterval = 180
    /// The share of arrivals that bring a second guest along, when there is room.
    static let pairChance = 0.25

    static func current(in defaults: UserDefaults = .standard) -> NotchMascotGangVisits {
        NotchMascotGangVisits(rawValue: defaults.string(forKey: DefaultsKey.notchMascotGangVisits) ?? "") ?? .rare
    }

    static func atOnce(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: DefaultsKey.notchMascotGangAtOnce) as? Int ?? defaultAtOnce
        return min(mostGuests, max(1, stored))
    }
}

/// Who a guest of the gang is. It is the same for a figure every time it
/// comes, and shapes its pace, the plays it likes and how it takes things.
enum NotchMascotPersonality: String, CaseIterable {
    case shy, showOff, glutton, grumpy, prankster, sleepy

    /// The figure's own, from a stable hash of its name.
    static func of(_ style: NotchMascotStyle) -> NotchMascotPersonality {
        allCases[Int(NotchMascotRapport.stableHash(style.rawValue) % UInt64(allCases.count))]
    }

    /// How many times the walking pace it wanders at.
    var gait: CGFloat {
        switch self {
        case .shy: return 0.85
        case .showOff: return 1.25
        case .glutton: return 0.9
        case .grumpy: return 1
        case .prankster: return 1.35
        case .sleepy: return 0.6
        }
    }

    /// The mood it wears out there.
    var mood: NotchMascotMood {
        switch self {
        case .grumpy: return .bored
        case .showOff: return .happy
        case .shy, .glutton, .prankster, .sleepy: return .idle
        }
    }

    /// The face it pulls when patted.
    var pattedFace: NotchMascotMood {
        switch self {
        case .shy: return .embarrassed
        case .showOff: return .smug
        case .glutton: return .greedy
        case .grumpy: return .angry
        case .prankster: return .mischievous
        case .sleepy: return .bored
        }
    }

    /// The face it pulls as it arrives.
    var arrivalFace: NotchMascotMood {
        switch self {
        case .shy: return .embarrassed
        case .showOff: return .starstruck
        case .glutton: return .greedy
        case .grumpy: return .bored
        case .prankster: return .mischievous
        case .sleepy: return .sleepy
        }
    }

    /// How much more, or less, it likes each play with one other.
    var leanings: [NotchMascotPlay.Kind: Double] {
        switch self {
        case .shy: return [.hug: 0.5, .duel: 0.5, .blast: 0.5, .gift: 1.8, .mimic: 1.4]
        case .showOff: return [.powerUp: 2.2, .danceOff: 2, .duel: 1.4, .nap: 0.4]
        case .glutton: return [.choreography: 2, .gift: 1.6, .nap: 1.3]
        case .grumpy: return [.duel: 1.8, .blast: 1.8, .hug: 0.3, .highFive: 0.5, .gift: 0.5]
        case .prankster: return [.tag: 2.2, .leapfrog: 2, .mimic: 1.8, .blast: 1.3]
        case .sleepy: return [.nap: 4, .danceOff: 0.5, .tag: 0.5, .powerUp: 0.6]
        }
    }

    /// How much more, or less, it likes each play of the whole gang.
    func likes(_ kind: NotchMascotGroupPlay.Kind) -> Double {
        switch (self, kind) {
        case (.sleepy, .napPile), (.glutton, .picnic), (.glutton, .campfire), (.showOff, .karaoke),
             (.showOff, .photo), (.showOff, .danceCircle), (.prankster, .waterFight), (.prankster, .pillowFight),
             (.prankster, .snowballFight), (.prankster, .telephone), (.shy, .choir), (.grumpy, .soccer):
            return 2
        case (.sleepy, .soccer), (.sleepy, .conga), (.shy, .karaoke), (.shy, .danceCircle), (.grumpy, .conga),
             (.grumpy, .choir):
            return 0.5
        default: return 1
        }
    }

    /// How it enters, by weight: a show-off makes the biggest entrance, a
    /// shy one slips in from the side.
    func entranceWeight(_ entrance: NotchMascotEntrance) -> Double {
        switch (self, entrance) {
        case (.shy, .walkIn), (.shy, .door): return 3
        case (.showOff, .parachute), (.showOff, .teleport), (.showOff, .balloon): return 3
        case (.prankster, .pipe), (.prankster, .dockPop): return 3
        case (.sleepy, .balloon), (.sleepy, .walkIn): return 2.5
        case (.glutton, .door), (.grumpy, .walkIn): return 2
        default: return 1
        }
    }

    /// How it leaves, by weight.
    func exitWeight(_ exit: NotchMascotExit) -> Double {
        switch (self, exit) {
        case (.shy, .box), (.prankster, .box): return 3
        case (.sleepy, .balloon), (.showOff, .balloon): return 3
        case (.grumpy, .walkOff), (.glutton, .door): return 2.5
        default: return 1
        }
    }
}

/// How a guest comes onto the desktop.
enum NotchMascotEntrance: CaseIterable, Equatable {
    /// It walks in from the side of the screen.
    case walkIn
    /// It floats down from the top under a parachute.
    case parachute
    /// It comes down hanging from a balloon.
    case balloon
    /// It pops up from the Dock's edge in a puff of dust.
    case dockPop
    /// It climbs out of a green pipe that rises from the floor.
    case pipe
    /// A door appears, opens, and it steps out.
    case door
    /// A beam of light, and there it is.
    case teleport

    static func pick(for personality: NotchMascotPersonality, random: Double) -> NotchMascotEntrance {
        NotchMascotRapport.weighted(allCases, weight: personality.entranceWeight, random: random) ?? .walkIn
    }
}

/// How a guest leaves the desktop.
enum NotchMascotExit: CaseIterable, Equatable {
    /// It waves and walks off the side of the screen.
    case walkOff
    /// It floats away up off the screen on a balloon.
    case balloon
    /// It hops into a cardboard box, which goes.
    case box
    /// The door again: it walks in and the door closes.
    case door

    static func pick(for personality: NotchMascotPersonality, random: Double) -> NotchMascotExit {
        NotchMascotRapport.weighted(allCases, weight: personality.exitWeight, random: random) ?? .walkOff
    }
}

/// What two figures make of each other, from how their plays went.
enum NotchMascotRelation: Equatable {
    case strangers, friends, rivals, crush

    /// How much more it is picked for a play: good company most of all.
    var preference: Double {
        switch self {
        case .crush: return 2.6
        case .friends: return 2.2
        case .strangers: return 1
        case .rivals: return 1.2
        }
    }

    /// How much more, or less, each play is wanted between the two.
    var leanings: [NotchMascotPlay.Kind: Double] {
        switch self {
        case .strangers: return [:]
        case .friends: return [.hug: 2, .highFive: 1.6, .gift: 1.6, .danceOff: 1.3, .duel: 0.6, .blast: 0.6]
        case .rivals: return [.duel: 2.2, .blast: 2, .powerUp: 1.8, .tag: 1.3, .hug: 0.15, .gift: 0.3]
        case .crush: return [.hug: 2.5, .gift: 2.5, .danceOff: 1.5, .duel: 0.3, .blast: 0.2]
        }
    }
}

/// The gang's memory of who gets on with whom, figure by figure, kept in
/// the preferences. Each pair starts somewhere of its own, grows closer with
/// good plays and drifts apart with rough ones.
enum NotchMascotRapport {
    /// What a good play adds, and a rough one takes away.
    static let good = 0.06
    static let rough = -0.05
    /// Where friends, rivals and a crush begin, on a scale of -1 to 1.
    static let friendsFrom = 0.3
    static let rivalsBelow = -0.3
    static let crushFrom = 0.55

    /// FNV-1a over `text`'s bytes: the same on every launch, unlike `hashValue`.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The key a pair is kept under, the same either way round.
    static func key(_ a: NotchMascotStyle, _ b: NotchMascotStyle) -> String {
        [a.rawValue, b.rawValue].sorted().joined(separator: "+")
    }

    /// Where a pair starts before any play: a little apart or a little
    /// close, so some meet as friends and some as rivals.
    static func seed(_ a: NotchMascotStyle, _ b: NotchMascotStyle) -> Double {
        let roll = Double(stableHash(key(a, b)) % 1000) / 1000
        return -0.4 + roll * 0.9
    }

    /// Whether this pair would fall for each other rather than be friends.
    static func smitten(_ a: NotchMascotStyle, _ b: NotchMascotStyle) -> Bool {
        stableHash(key(a, b) + "♥") % 3 == 0
    }

    static func value(_ a: NotchMascotStyle, _ b: NotchMascotStyle, in defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.dictionary(forKey: DefaultsKey.notchMascotGangAffinity) as? [String: Double]
        return stored?[key(a, b)] ?? seed(a, b)
    }

    static func relation(_ a: NotchMascotStyle, _ b: NotchMascotStyle,
                         in defaults: UserDefaults = .standard) -> NotchMascotRelation {
        guard a != b else { return .friends }
        return relation(value: value(a, b, in: defaults), smitten: smitten(a, b))
    }

    static func relation(value: Double, smitten: Bool) -> NotchMascotRelation {
        if value >= crushFrom, smitten { return .crush }
        if value >= friendsFrom { return .friends }
        if value <= rivalsBelow { return .rivals }
        return .strangers
    }

    /// Moves the pair `change` closer, or apart when negative, within -1...1.
    static func record(_ change: Double, between a: NotchMascotStyle, and b: NotchMascotStyle,
                       in defaults: UserDefaults = .standard) {
        guard a != b, change != 0 else { return }
        var stored = defaults.dictionary(forKey: DefaultsKey.notchMascotGangAffinity) as? [String: Double] ?? [:]
        let key = key(a, b)
        stored[key] = min(1, max(-1, (stored[key] ?? seed(a, b)) + change))
        defaults.set(stored, forKey: DefaultsKey.notchMascotGangAffinity)
    }

    /// How a play between two moves them: rough plays push apart, the rest
    /// bring them closer.
    static func change(after play: NotchMascotPlay) -> Double {
        switch play {
        case .duel(_, let outcome): return outcome == .draw ? good * 0.5 : rough
        case .blast(_, let answer): return answer == .hit || answer == .deflect ? rough : rough * 0.2
        case .powerUp(_, let matched): return matched ? good * 0.4 : rough * 0.4
        case .tag, .leapfrog: return good * 0.5
        case .hug, .gift: return good * 1.4
        case .danceOff, .highFive, .mimic, .nap, .choreography: return good
        }
    }

    /// One of `items` drawn by `weight`, with `random` in 0..<1.
    static func weighted<T>(_ items: [T], weight: (T) -> Double, random: Double) -> T? {
        let total = items.reduce(0) { $0 + max(0, weight($1)) }
        guard total > 0 else { return nil }
        var mark = min(max(random, 0), 0.999_999) * total
        for item in items {
            mark -= max(0, weight(item))
            if mark < 0 { return item }
        }
        return items.last
    }
}

/// Who comes on a visit and how it looks.
enum NotchMascotGangCasting {
    /// The figures that may come for a companion named `name`, other than
    /// those already out: never the comic's own unless they are unlocked.
    static func styles(name: String?, excluding out: Set<NotchMascotStyle>) -> [NotchMascotStyle] {
        NotchMascotStyle.available(name: name).filter { !out.contains($0) }
    }

    /// A guest of `style` in the colour picked for that figure, or one of
    /// its own when none ever was, and a shape of its own, wearing
    /// something of its own: what its own level unlocks, what it brought
    /// along and what was bought for it, never the companion's things. Its
    /// transformation, if it has grown to one, is its own too.
    static func look(for style: NotchMascotStyle, random: () -> Double) -> NotchMascotLook {
        let store = NotchMascotBondStore.shared
        return look(for: style, level: store.shownLevel(for: style),
                    owns: { NotchMascotShop.owns($0, by: style) },
                    formChoice: UserDefaults.standard.string(forKey: DefaultsKey.notchMascotForm), random: random)
    }

    /// The same, from what is known of the guest: its `level`, what it
    /// `owns` and the companion's form choice, which it follows against
    /// its own level. Pure, so the rule is tested.
    static func look(for style: NotchMascotStyle, level: Int, owns: (NotchMascotAccessory) -> Bool,
                     formChoice: String?, random: () -> Double) -> NotchMascotLook {
        func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(random() * Double(items.count)))] }
        var look = NotchMascotLook(style: style, shape: style.takesShape ? pick(NotchMascotShape.allCases) : .ball,
                                   palette: pick(NotchMascotPalette.allCases))
        if let paint = NotchMascotStyleColors.paint(for: style) { look = paint.paint(look) }
        if style.takesAccessory {
            let own = wardrobe(for: style, level: level, owns: owns)
            // Its toys and party gear more often than its hats, so the gang
            // has something to play with.
            let playful = own.filter { $0.isPartyItem || $0.isToyItem || $0.isOddity || $0.isCraftItem || $0.isFairItem }
            let pool = random() < 0.6 && !playful.isEmpty ? playful : own
            if !pool.isEmpty { look.accessory = pick(pool) }
        }
        look.form = NotchMascotTransformation.friendForm(own: nil, companions: formChoice, level: level, style: style)
        return look
    }

    /// Everything a guest of `style` may wear: what its `level` unlocks and
    /// what it `owns`.
    static func wardrobe(for style: NotchMascotStyle, level: Int,
                         owns: (NotchMascotAccessory) -> Bool) -> [NotchMascotAccessory] {
        NotchMascotAccessory.wardrobe.filter { $0 != .none && ($0.isPurchasable ? owns($0) : $0.unlockLevel <= level) }
    }
}
