// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What the whole gang gets up to once three or more are out on the same
/// screen: a conga line, a human pyramid, a band, a match with a referee, a
/// campfire at night, a choir, a group photo, the stadium wave and more.
/// What they wear calls for some, the season and the hour for others, and
/// what they just did is less likely next. Pure, so every rule is tested
/// without a window.
enum NotchMascotGroupPlay {
    enum Kind: String, CaseIterable, Equatable {
        /// A line that dances along the floor, hip to hip.
        case conga
        /// Standing on each other's heads until the top one wobbles.
        case pyramid
        /// Each plays what it holds; the rest clap along.
        case band
        /// Two sides, a ball and one with a whistle to keep order.
        case soccer
        /// A fire at night and marshmallows on sticks; one burns.
        case campfire
        /// A song in turns, high and low, with one off key.
        case choir
        /// All pose with a face of their own, and a flash.
        case photo
        /// One after another they jump up and down, there and back.
        case stadiumWave
        /// A ring of clappers and one dancing in the middle, in turns.
        case danceCircle
        /// Everyone dozes off in a heap.
        case napPile
        /// One counts while the rest hide, and finds them one by one.
        case hideAndSeek
        /// A march across the screen behind one in front.
        case parade
        /// Pillows swung and feathers everywhere.
        case pillowFight
        /// A thing whispered along the line, and what comes out the end.
        case telephone
        /// Snow coming down and snowballs going across, in winter.
        case snowballFight
        /// Your birthday: they hide, then jump out with a cake.
        case surpriseParty
        /// A blanket, a basket and snacks for all; one steals.
        case picnic
        /// A kite on a string under a storm cloud, until the lightning.
        case kiteStorm
        /// Water squirted across, and one holding an umbrella.
        case waterFight
        /// One shouts through a megaphone and the rest fall in behind it.
        case megaphoneConga
        /// Two at the ends of the screen whispering across it.
        case walkieTalkies
        /// Balls passed round in arcs, faster, until one drops.
        case juggling
        /// One sings into the microphone, the rest sway and cheer.
        case karaoke
    }

    /// At least this many on one screen for a play of the whole gang.
    static let minimum = 3
    /// At least this long between two, and before the first once three are out.
    static let interval: TimeInterval = 150
    static let firstAfter: TimeInterval = 35
    /// Once one is due, the share of chances it is taken.
    static let chance = 0.5
    /// How many plays back still count as just done.
    static let memory = 5

    /// What the gang knows as it might start one.
    struct Context: Equatable {
        var count: Int
        var hour: Int
        /// The month, 1 to 12.
        var month: Int
        var birthday = false
        var music = false
        /// What each of them wears, and what each is.
        var items: [NotchMascotAccessory] = []
        var styles: [NotchMascotStyle] = []
        var personalities: [NotchMascotPersonality] = []
        var recent: [Kind] = []

        var night: Bool { hour >= 20 || hour < 5 }
        var winter: Bool { month == 12 || month <= 2 }
        func wears(_ item: NotchMascotAccessory) -> Bool { items.contains(item) }
    }

    /// The plays what they wear and are calls for. This is the one place the
    /// gang reads the wardrobe for its plays.
    static func called(by items: [NotchMascotAccessory], styles: [NotchMascotStyle]) -> Set<Kind> {
        var called: Set<Kind> = []
        let instruments: Set<NotchMascotAccessory> = [.bardLute, .drum, .microphone, .maracas, .headphones, .discoBall]
        if items.contains(where: instruments.contains) { called.insert(.band) }
        if items.contains(.soccerBall) || items.contains(.whistle) { called.insert(.soccer) }
        if items.contains(.marshmallowStick) || styles.contains(.dragon) || styles.contains(.phoenix) {
            called.insert(.campfire)
        }
        if items.contains(.instantCamera) { called.insert(.photo) }
        if items.contains(.pillow) || items.contains(.sleepMask) { called.insert(.pillowFight) }
        let food: Set<NotchMascotAccessory> = [.picnicBasket, .iceCreamCone, .onigiri, .ramenBowl, .bobaTea,
                                               .fortuneCookie, .creamPie]
        if items.contains(where: food.contains) { called.insert(.picnic) }
        if items.contains(.kite) || items.contains(.stormCloud) { called.insert(.kiteStorm) }
        if items.contains(.waterPistol) { called.insert(.waterFight) }
        if items.contains(.megaphone) { called.insert(.megaphoneConga) }
        if items.contains(.walkieTalkie) { called.insert(.walkieTalkies) }
        if items.contains(.jugglingBalls) { called.insert(.juggling) }
        if items.contains(.microphone) { called.insert(.karaoke) }
        if items.contains(.confettiCannon) || items.contains(.partyHat) || items.contains(.hulaHoop) {
            called.insert(.danceCircle)
        }
        // What the whole gang wears together calls its own play first.
        if let synergy = NotchMascotGroupSynergy.find(items, styles: styles) { called.insert(kind(for: synergy)) }
        return called
    }

    /// The play a gang synergy is acted out as.
    static func kind(for synergy: NotchMascotGroupSynergy) -> Kind {
        switch synergy {
        case .campfire: return .campfire
        case .kiteStorm: return .kiteStorm
        case .pillowFight: return .pillowFight
        case .waterFight: return .waterFight
        case .band: return .band
        case .karaoke: return .karaoke
        case .match: return .soccer
        case .juggling: return .juggling
        case .picnic: return .picnic
        case .conga: return .megaphoneConga
        }
    }

    /// Whether `kind` may come now at all.
    static func allowed(_ kind: Kind, in context: Context) -> Bool {
        guard context.count >= minimum else { return false }
        switch kind {
        case .snowballFight: return context.winter
        case .surpriseParty: return context.birthday
        case .campfire: return context.night
        case .waterFight: return context.wears(.waterPistol)
        case .megaphoneConga: return context.wears(.megaphone)
        case .walkieTalkies: return context.wears(.walkieTalkie)
        case .kiteStorm: return context.wears(.kite) || context.wears(.stormCloud)
        case .karaoke: return context.wears(.microphone)
        case .juggling: return context.wears(.jugglingBalls)
        case .band: return context.music || called(by: context.items, styles: context.styles).contains(.band)
        case .conga, .pyramid, .soccer, .choir, .photo, .stadiumWave, .danceCircle, .napPile, .hideAndSeek,
             .parade, .pillowFight, .telephone, .picnic:
            return true
        }
    }

    /// How much `kind` is wanted now: what they wear calls loudest, music
    /// calls for dancing, the small hours for a nap, and the play just done
    /// is never next.
    static func weight(of kind: Kind, in context: Context) -> Double {
        guard allowed(kind, in: context), context.recent.last != kind else { return 0 }
        var weight: Double
        switch kind {
        case .surpriseParty: weight = 30
        case .snowballFight: weight = 4
        case .napPile: weight = context.night ? 5 : 0.4
        case .conga, .danceCircle: weight = context.music ? 5 : 1.4
        case .campfire: weight = 3
        case .pyramid, .stadiumWave, .photo, .parade, .hideAndSeek, .telephone, .choir: weight = 1.4
        case .soccer, .pillowFight, .picnic: weight = 1
        case .band: weight = context.music ? 4 : 1.5
        case .waterFight, .megaphoneConga, .walkieTalkies, .kiteStorm, .karaoke, .juggling: weight = 2
        }
        if called(by: context.items, styles: context.styles).contains(kind) { weight *= 3.5 }
        for personality in context.personalities { weight *= personality.likes(kind) }
        if context.recent.suffix(memory).contains(kind) { weight *= 0.25 }
        return weight
    }

    /// The play the gang starts now, if any. `random` gives numbers in 0..<1.
    static func next(in context: Context, since: TimeInterval, random: () -> Double) -> Kind? {
        guard since >= interval, context.count >= minimum, random() < chance else { return nil }
        return NotchMascotRapport.weighted(Kind.allCases, weight: { weight(of: $0, in: context) }, random: random())
    }

    /// What lies at the end of a whisper passed along `steps` of them: each
    /// hears it a little wrong now and then. `random` gives numbers in 0..<1.
    static let whispers = ["★", "♥", "☂", "♪", "☀", "✿", "☁", "♠", "☕", "✈"]
    static func whisperChain(steps: Int, random: () -> Double) -> [String] {
        var chain = [whispers[min(whispers.count - 1, Int(random() * Double(whispers.count)))]]
        for _ in 1..<max(2, steps) {
            let last = chain[chain.count - 1]
            if random() < 0.45 {
                let others = whispers.filter { $0 != last }
                chain.append(others[min(others.count - 1, Int(random() * Double(others.count)))])
            } else {
                chain.append(last)
            }
        }
        return chain
    }

    /// The rows a pyramid of `count` stands in, from the bottom up.
    static func pyramidRows(_ count: Int) -> [Int] {
        switch count {
        case ...3: return [2, 1]
        case 4: return [2, 1, 1]
        case 5: return [3, 2]
        default: return [3, 2, 1]
        }
    }
}
