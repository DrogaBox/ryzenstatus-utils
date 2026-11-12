// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Something rare that passes by while the companion is out on the desktop,
/// for it to meet. Most can come at any hour; some keep to the night, and
/// one to a single hour of it.
enum NotchMascotEncounter: String, CaseIterable, Equatable {
    /// Footsteps, then a great tail sweeping in at the screen's edge.
    case dinosaur
    /// A star crossing the top of the screen, at night: it makes a wish.
    case shootingStar
    /// A saucer that lifts it in its beam, and goes.
    case ufo
    /// A little ghost that floats through it, at three in the morning only.
    case ghost
    /// A bird that takes what it wears, perches a while and gives it back.
    case magpie
    /// Lights that drift around it after dark, for it to chase.
    case fireflies
    /// A mother duck and her ducklings walking across, and it follows.
    case ducklings
    /// A chest that turns out to have teeth, and leaves a coin or two.
    case mimic
    /// A wandering seller with a great pack, for a trade of a coin.
    case merchant
    /// Bubbles rising, one big enough to hold it a moment.
    case bubble
    /// A cardboard box to hide under and sneak along in.
    case cardboardBox
    /// A crack of loose pixels opening in the screen beside it.
    case glitch
    /// A little boat sailing along the Dock.
    case dockBoat
    /// A waste bin that spills its paper, for it to tidy up.
    case trashCan
    /// A cup of coffee left by it, in the daytime, and what comes after.
    case coffee
    /// A satellite crossing the night sky, blinking; a hologram or an
    /// android picks up its signal and answers.
    case satellite
    /// A shower of shooting stars late at night: a wish for each.
    case meteorShower
    /// A balloon someone let go of, floating up past it in the daytime.
    case lostBalloon
    /// A rainbow arching over the screen in the afternoon.
    case rainbow
    /// A heart from someone it cannot see, flying in from the edge.
    case secretAdmirer
    /// Gravity lets go a moment: it drifts up among little stars and
    /// comes down with a bump.
    case zeroGravity
    /// A rain cloud drifts over it: with an umbrella it stays dry and
    /// smug, without one it gets soaked and shakes itself off.
    case rainShower
    /// A flutter of butterflies drifting across in the daytime: with a net
    /// it catches one and lets it go, under a crown of flowers they land on it.
    case butterflies
    /// A fish leaping out of the floor and back in: with a rod it lands it,
    /// without one it gets splashed.
    case fishJump

    /// Whether it can come now: by the hour, and by what it wears.
    func allowed(hour: Int, wearsItem: Bool) -> Bool {
        switch self {
        case .zeroGravity, .rainShower, .fishJump: return true
        case .butterflies: return hour >= 8 && hour < 20
        case .ghost: return hour == 3
        case .shootingStar: return hour >= 20 || hour < 6
        case .fireflies: return hour >= 21 || hour < 5
        case .magpie: return wearsItem
        case .coffee: return hour >= 6 && hour < 14
        case .satellite: return hour >= 22 || hour < 5
        case .meteorShower: return hour >= 23 || hour < 4
        case .lostBalloon: return hour >= 9 && hour < 19
        case .rainbow: return hour >= 10 && hour < 18
        case .secretAdmirer: return true
        case .dinosaur, .ufo, .ducklings, .mimic, .merchant, .bubble, .cardboardBox, .glitch, .dockBoat, .trashCan:
            return true
        }
    }

    /// Whether it needs the floor: it does not come while the companion
    /// stands on a window.
    var grounded: Bool {
        switch self {
        case .mimic, .merchant, .cardboardBox, .trashCan, .coffee: return true
        case .dinosaur, .shootingStar, .ufo, .ghost, .magpie, .fireflies, .ducklings, .bubble, .glitch, .dockBoat,
             .satellite, .meteorShower, .lostBalloon, .rainbow, .secretAdmirer, .zeroGravity, .rainShower,
             .butterflies, .fishJump:
            return false
        }
    }
    /// How often it comes, against the others that may.
    var weight: Double {
        switch self {
        case .ghost: return 4
        case .shootingStar, .fireflies, .coffee: return 2
        case .dinosaur, .ufo, .ducklings, .magpie, .mimic, .merchant, .bubble, .cardboardBox, .glitch, .dockBoat,
             .trashCan, .satellite, .meteorShower, .lostBalloon, .rainbow, .secretAdmirer, .zeroGravity, .rainShower,
             .butterflies, .fishJump:
            return 1
        }
    }

    /// How long it keeps the companion busy, near enough.
    var length: TimeInterval {
        switch self {
        case .dinosaur: return 9
        case .shootingStar: return 4
        case .ufo: return 9
        case .ghost: return 7
        case .magpie: return 13
        case .fireflies: return 10
        case .ducklings: return 12
        case .mimic: return 9
        case .merchant: return 11
        case .bubble: return 9
        case .cardboardBox: return 11
        case .glitch: return 7
        case .dockBoat: return 10
        case .trashCan: return 11
        case .coffee: return 11
        case .satellite: return 9
        case .meteorShower: return 8
        case .lostBalloon: return 7
        case .rainbow: return 7
        case .secretAdmirer: return 6
        case .zeroGravity: return 8
        case .rainShower: return 9
        case .butterflies: return 8
        case .fishJump: return 7
        }
    }

    /// The other companion, seeing it from where it stands.
    var witnessReaction: NotchMascotReaction {
        switch self {
        case .dinosaur, .ghost: return .panic
        case .shootingStar, .fireflies: return .love
        case .satellite: return .peek
        case .meteorShower, .rainbow: return .love
        case .lostBalloon: return .bounce
        case .secretAdmirer: return .surprised
        case .ufo, .magpie, .mimic, .glitch: return .surprised
        case .ducklings, .bubble: return .bounce
        case .merchant, .dockBoat: return .wave
        case .cardboardBox, .trashCan: return .confused
        case .coffee: return .sip
        case .zeroGravity: return .surprised
        case .rainShower: return .sweat
        case .butterflies: return .love
        case .fishJump: return .surprised
        }
    }
}

/// What the others out on the desktop do about something rare together,
/// rather than each watching it from where it stands.
enum NotchMascotGroupEncounter: Equatable {
    /// Scared, they all run into each other's arms and shake in a heap.
    case pile
    /// One is taken, and the others run after the one that took it.
    case chase
    /// They line up behind it for a turn of their own.
    case queue
}

extension NotchMascotEncounter {
    /// What a crowd makes of it; nil where each just watches.
    var gathers: NotchMascotGroupEncounter? {
        switch self {
        case .ghost: return .pile
        case .ufo: return .chase
        case .merchant: return .queue
        default: return nil
        }
    }
}

enum NotchMascotEncounters {
    /// At most this many queue at the seller's, each taking this long.
    static let queueLength = 3
    static let queueTurn: TimeInterval = 3.2
    /// At least this long between two, wherever the companion was meanwhile,
    /// and the chance of one each time it looks for something to do after.
    static let interval: TimeInterval = 8 * 60
    static let chance = 0.05
    /// The last few, which do not come again soon.
    static let memory = 3

    static func shouldHappen(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }

    /// How many times as likely something it lures is to come.
    static let lureWeight = 3.0

    /// What a thing worn draws in, whatever the hour: a telescope the
    /// stars, binoculars the birds, an astronaut's helmet the sky's
    /// visitors, a net the butterflies and fireflies, a rod the fish and
    /// the little boat, a watering can the rainbow and a crown of flowers
    /// the butterflies.
    static func lured(by item: NotchMascotAccessory) -> Set<NotchMascotEncounter> {
        switch item {
        case .telescope: return [.shootingStar, .meteorShower]
        case .binoculars: return [.magpie, .ducklings, .satellite]
        case .astronautHelmet: return [.zeroGravity, .ufo, .satellite, .meteorShower]
        case .butterflyNet: return [.butterflies, .fireflies]
        case .flowerCrown: return [.butterflies, .rainbow]
        case .fishingRod: return [.fishJump, .dockBoat]
        case .wateringCan: return [.rainbow, .rainShower]
        default: return []
        }
    }

    /// One of those that may come now, by weight, other than the last few;
    /// nil when none may. With a `telescope` to its eye the stars come by
    /// day as well, and what its `lure` draws in comes at any hour and
    /// more often.
    static func pick(hour: Int, wearsItem: Bool, recent: [NotchMascotEncounter],
                     random: Double, telescope: Bool = false,
                     lure: NotchMascotAccessory = .none) -> NotchMascotEncounter? {
        let lured = lured(by: telescope ? .telescope : lure)
        let open = NotchMascotEncounter.allCases.filter {
            ($0.allowed(hour: hour, wearsItem: wearsItem) || lured.contains($0)) && ($0 != .magpie || wearsItem)
        }
        let fresh = open.filter { !recent.suffix(memory).contains($0) }
        let pool = fresh.isEmpty ? open : fresh
        func weight(_ encounter: NotchMascotEncounter) -> Double {
            encounter.weight * (lured.contains(encounter) ? lureWeight : 1)
        }
        let total = pool.reduce(0) { $0 + weight($1) }
        guard total > 0 else { return nil }
        var mark = min(max(random, 0), 0.999_999) * total
        for encounter in pool {
            mark -= weight(encounter)
            if mark < 0 { return encounter }
        }
        return pool.last
    }
}
