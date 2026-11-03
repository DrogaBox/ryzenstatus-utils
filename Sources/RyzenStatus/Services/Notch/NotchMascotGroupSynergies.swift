// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// What a gang of three or more makes together by what they hold and are:
/// a band, a match, a campfire, a pillow fight. Pure data and rules: it
/// says which one a gang makes and who starts it, and the play director
/// acts it out. The duo combos stay in `NotchMascotSynergyCatalog`; these
/// need the whole gang.
///
/// The rules are read in the order of the cases, and the first that fits
/// wins, so a gang with both a marshmallow on a dragon and a band plays
/// the campfire:
/// - campfire: a marshmallow stick with a dragon or a phoenix in the gang
///   to light it, or two sticks or more at night (from eight in the
///   evening to six in the morning).
/// - kiteStorm: a kite and a storm cloud.
/// - pillowFight: two pillows or more.
/// - waterFight: two water pistols or more, or one with an umbrella to
///   hide behind.
/// - band: two instruments or more among the lute, the drum, the
///   microphone, the maracas and the headphones, not all of them
///   microphones.
/// - karaoke: a microphone with a second one or a disco ball.
/// - match: a soccer ball with a whistle or a second ball.
/// - juggling: juggling balls with a second set or a clown nose.
/// - picnic: a picnic basket with something to eat in it (an onigiri, a
///   ramen bowl, an ice cream, a boba tea) or a capybara, or two baskets.
/// - conga: three or more in party gear that dances: the party hat, the
///   maracas, the hula hoop, the Spanish fan and the disco ball.
enum NotchMascotGroupSynergy: String, CaseIterable, Identifiable {
    case campfire, kiteStorm, pillowFight, waterFight, band, karaoke, match, juggling, picnic, conga

    var id: String { rawValue }

    /// The fewest companions out together for a group synergy.
    static let minimumGang = 3

    /// What sounds in a band.
    static let instruments: Set<NotchMascotAccessory> = [.bardLute, .drum, .microphone, .maracas, .headphones]
    /// What goes in a picnic basket.
    static let picnicFood: Set<NotchMascotAccessory> = [.onigiri, .ramenBowl, .iceCreamCone, .bobaTea]
    /// What a conga line is made of.
    static let congaGear: Set<NotchMascotAccessory> = [.partyHat, .maracas, .hulaHoop, .spanishFan, .discoBall]

    /// Whether `hour`, 0 to 23, is night for the campfire.
    static func isNight(_ hour: Int) -> Bool { hour >= 20 || hour < 6 }

    /// The group synergy a gang makes, if any. `items` holds what each one
    /// holds, `.none` for empty hands, and `styles` their figures, in the
    /// same order; the gang is as big as the longer of the two. Fewer than
    /// `minimumGang` make none. `hour` decides whether it is night.
    static func find(_ items: [NotchMascotAccessory], styles: [NotchMascotStyle],
                     hour: Int = Calendar.current.component(.hour, from: Date())) -> NotchMascotGroupSynergy? {
        guard max(items.count, styles.count) >= minimumGang else { return nil }
        return allCases.first { $0.fits(items, styles: styles, hour: hour) }
    }

    /// Whether this one's rule holds for the gang, on its own: `find`
    /// checks the gang's size and which rule comes first.
    // swiftlint:disable:next cyclomatic_complexity
    func fits(_ items: [NotchMascotAccessory], styles: [NotchMascotStyle], hour: Int) -> Bool {
        func count(_ item: NotchMascotAccessory) -> Int { items.filter { $0 == item }.count }
        func has(_ item: NotchMascotAccessory) -> Bool { items.contains(item) }
        switch self {
        case .campfire:
            let sticks = count(.marshmallowStick)
            let fire = styles.contains(.dragon) || styles.contains(.phoenix)
            return (sticks >= 1 && fire) || (sticks >= 2 && Self.isNight(hour))
        case .kiteStorm:
            return has(.kite) && has(.stormCloud)
        case .pillowFight:
            return count(.pillow) >= 2
        case .waterFight:
            return count(.waterPistol) >= 2 || (has(.waterPistol) && has(.umbrella))
        case .band:
            let playing = items.filter { Self.instruments.contains($0) }
            return playing.count >= 2 && playing.contains { $0 != .microphone }
        case .karaoke:
            return has(.microphone) && (count(.microphone) >= 2 || has(.discoBall))
        case .match:
            return has(.soccerBall) && (has(.whistle) || count(.soccerBall) >= 2)
        case .juggling:
            return has(.jugglingBalls) && (count(.jugglingBalls) >= 2 || has(.clownNose))
        case .picnic:
            return has(.picnicBasket)
                && (items.contains { Self.picnicFood.contains($0) } || styles.contains(.capybara) || count(.picnicBasket) >= 2)
        case .conga:
            return items.filter { Self.congaGear.contains($0) }.count >= 3
        }
    }

    /// What a member holding it brings to this one: the things its rule
    /// names, the ones whose holder can lead it.
    var keyItems: Set<NotchMascotAccessory> {
        switch self {
        case .campfire: return [.marshmallowStick]
        case .kiteStorm: return [.kite, .stormCloud]
        case .pillowFight: return [.pillow]
        case .waterFight: return [.waterPistol, .umbrella]
        case .band: return Self.instruments
        case .karaoke: return [.microphone, .discoBall]
        case .match: return [.soccerBall, .whistle]
        case .juggling: return [.jugglingBalls, .clownNose]
        case .picnic: return [.picnicBasket]
        case .conga: return Self.congaGear
        }
    }

    /// The member that starts it: the first holding the thing the rule
    /// is about (the kite before the cloud, the drum before the rest of a
    /// band), else the first holding any of its key items; nil when none
    /// does, as for a picnic only a capybara brought.
    func starter(among items: [NotchMascotAccessory]) -> Int? {
        let lead: NotchMascotAccessory?
        switch self {
        case .campfire: lead = .marshmallowStick
        case .kiteStorm: lead = .kite
        case .pillowFight: lead = .pillow
        case .waterFight: lead = .waterPistol
        case .band: lead = items.contains(.drum) ? .drum : nil
        case .karaoke: lead = .microphone
        case .match: lead = items.contains(.whistle) ? .whistle : .soccerBall
        case .juggling: lead = .jugglingBalls
        case .picnic: lead = .picnicBasket
        case .conga: lead = nil
        }
        if let lead, let index = items.firstIndex(of: lead) { return index }
        return items.firstIndex { keyItems.contains($0) }
    }
}
