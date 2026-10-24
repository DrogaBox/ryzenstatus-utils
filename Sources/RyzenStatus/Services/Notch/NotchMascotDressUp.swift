// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Dress-up play: while a companion is out on the desktop, now and then it
/// digs into everything it owns and puts on whatever it feels like for a
/// while — a bought curiosity, an old favourite — then goes back to what its
/// person picked for it. Pure rules, so every choice is tested.
enum NotchMascotDressUp {
    /// At least this long between digs into the wardrobe.
    static let rest: TimeInterval = 40
    /// The chance a free moment becomes dress-up, checked as it stands around.
    static let chance = 0.07
    /// How long it keeps the thing on: 30 to 90 seconds.
    static func duration(random: Double) -> TimeInterval {
        30 + (random.isFinite ? min(max(random, 0), 1) : 0.5) * 60
    }

    /// Everything it may wear by itself: what its level opened, plus what was
    /// bought. Costumes it cannot pick are not its to play with.
    static func wardrobe(level: Int, owns: (NotchMascotAccessory) -> Bool) -> [NotchMascotAccessory] {
        NotchMascotAccessory.wardrobe.filter {
            $0 != .none && ($0.isPurchasable ? owns($0) : $0.unlockLevel <= level)
        }
    }

    /// The thing it puts on now, never the one it already wears; nil with an
    /// empty wardrobe, so a companion with nothing of its own stays as it is.
    static func pick(current: NotchMascotAccessory, level: Int, owns: (NotchMascotAccessory) -> Bool,
                     random: Double) -> NotchMascotAccessory? {
        let options = wardrobe(level: level, owns: owns).filter { $0 != current }
        guard !options.isEmpty else { return nil }
        let clamped = random.isFinite ? min(max(random, 0), 0.999) : 0.5
        return options[Int(clamped * Double(options.count))]
    }

    /// Whether a free moment becomes dress-up: rested long enough, and the
    /// roll says yes.
    static func shouldStart(sinceLastDig: TimeInterval, random: Double) -> Bool {
        sinceLastDig >= rest && random < chance
    }
}
