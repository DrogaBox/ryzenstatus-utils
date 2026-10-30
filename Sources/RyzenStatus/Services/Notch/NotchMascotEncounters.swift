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

    /// Whether it can come now: by the hour, and by what it wears.
    func allowed(hour: Int, wearsItem: Bool) -> Bool {
        switch self {
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
             .satellite, .meteorShower, .lostBalloon, .rainbow, .secretAdmirer:
            return false
        }
    }
    /// How often it comes, against the others that may.
    var weight: Double {
        switch self {
        case .ghost: return 4
        case .shootingStar, .fireflies, .coffee: return 2
        case .dinosaur, .ufo, .ducklings, .magpie, .mimic, .merchant, .bubble, .cardboardBox, .glitch, .dockBoat,
             .trashCan, .satellite, .meteorShower, .lostBalloon, .rainbow, .secretAdmirer:
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
        }
    }
}

enum NotchMascotEncounters {
    /// At least this long between two, wherever the companion was meanwhile,
    /// and the chance of one each time it looks for something to do after.
    static let interval: TimeInterval = 8 * 60
    static let chance = 0.05
    /// The last few, which do not come again soon.
    static let memory = 3

    static func shouldHappen(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }

    /// One of those that may come now, by weight, other than the last few;
    /// nil when none may.
    static func pick(hour: Int, wearsItem: Bool, recent: [NotchMascotEncounter],
                     random: Double) -> NotchMascotEncounter? {
        let open = NotchMascotEncounter.allCases.filter { $0.allowed(hour: hour, wearsItem: wearsItem) }
        let fresh = open.filter { !recent.suffix(memory).contains($0) }
        let pool = fresh.isEmpty ? open : fresh
        let total = pool.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var mark = min(max(random, 0), 0.999_999) * total
        for encounter in pool {
            mark -= encounter.weight
            if mark < 0 { return encounter }
        }
        return pool.last
    }
}
