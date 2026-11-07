// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// How a fused companion looks over the figure it borrows: the colours it is
/// painted in, the aura it blazes with, the earrings or the mark that say it
/// is two in one, how much bigger it stands and, for a fusion gone wrong,
/// how lumpy it came out. Carried on its look, so it is drawn wherever the
/// look is.
struct NotchMascotFusionLook: Equatable {
    var aura: NotchMascotFusion.Aura
    /// The first colour, the body's own blend or its first half.
    var primary: NotchMascotColor
    /// The second colour: its other half, and the heart of its aura.
    var secondary: NotchMascotColor
    /// Painted half in each colour, split on the slant, rather than blended.
    var split: Bool
    var mark: NotchMascotFusion.Mark
    /// How many times its usual size it stands.
    var scale: CGFloat
    /// Squashed or stretched about its feet, wider or taller, for a fusion
    /// gone wrong; 1 by 1 for one that went right.
    var stretch = CGSize(width: 1, height: 1)
    /// Leaning over sideways about its feet, in shares of its height.
    var shear: CGFloat = 0

    /// The body's colours from top to bottom, or from one half to the other.
    var bodyColors: [NotchMascotColor] {
        split ? [primary.brightened(0.2), primary, secondary, secondary.darkened(0.15)]
            : [primary.brightened(0.24), primary.darkened(0.18)]
    }

    /// Where the body's colours change: a hard edge down the middle when split.
    var bodyLocations: [Double]? { split ? [0, 0.5, 0.5, 1] : nil }
}

/// Two companions out on the desktop dance the fusion dance and become one
/// for a minute or so: one figure stays out, bigger, painted in both their
/// colours, wearing the other's thing and a pair of earrings, wrapped in an
/// aura and full of power moves, while the other is inside it. Some pairs
/// make a fusion of their own, with its own name, colours, aura and
/// signature move, a few only at night or with a given thing on; any other
/// pair follows one rule. Now and then the poses do not match and what comes
/// out is a lumpy mess for a little while. Pure, so every rule is tested
/// without a window.
enum NotchMascotFusion {
    // MARK: When

    /// At least this long between two fusions of their own: half an hour,
    /// so a fusion is a rarer sight than a transformation, which comes
    /// with a level.
    static let interval: TimeInterval = 1800
    /// Once one is due and a play would start, the share of chances it is a fusion.
    static let chance = 0.1
    /// No more than this many of their own accord a day; the menu always may.
    static let dailyCap = 2
    /// Farther apart than this they do not dance it; they play something else.
    static let reach: CGFloat = 640
    /// How long the fused one stays out, and a fusion gone wrong.
    static let length: ClosedRange<TimeInterval> = 45...90
    static let flopLength: ClosedRange<TimeInterval> = 12...18
    /// The share of fusions in which the poses do not match.
    static let flopChance = 0.12
    /// Between two power moves of the fused one, at level one.
    static let moveGap: ClosedRange<TimeInterval> = 6...11
    /// How many times the pair's power a fused one hits with: it is an
    /// upgrade, not a costume.
    static let powerBoost: CGFloat = 1.5
    /// What a fusion that went well leaves each of the two, and the pocket.
    static let experience = 20
    static let gold = 25
    /// A press on the fused one sets off a move, at most this often.
    static let tapCooldown: TimeInterval = 1.5
    /// How long after a stroll begins the sparks follow its feet, and how often.
    static let trailStep: TimeInterval = 0.35

    /// Between two power moves at `level`, the higher of the two's: the
    /// stronger the pair, the busier the fused one, down to about half the
    /// gap at the top.
    static func moveGap(level: Int) -> ClosedRange<TimeInterval> {
        let share = 1 - 0.45 * min(1, max(0, Double(level - 1) / 49))
        return (moveGap.lowerBound * share)...(moveGap.upperBound * share)
    }

    /// Whether two out together start a fusion of their own now: one is due,
    /// a play would be too, the day has one left, and they get on well. The
    /// island's own two, `relation` nil, always do.
    static func due(since: TimeInterval, sincePlay: TimeInterval, relation: NotchMascotRelation?,
                    today: Int = 0, random: Double) -> Bool {
        guard since >= interval, sincePlay >= NotchMascotPlay.interval, today < dailyCap else { return false }
        switch relation {
        case nil, .friends?, .crush?: return random < chance
        case .rivals?, .strangers?: return false
        }
    }

    /// How many fusions came of their own accord on `day`, from the
    /// "day:count" record kept in the preferences; none on another day.
    static func count(in record: String?, day: String) -> Int {
        let parts = (record ?? "").split(separator: ":")
        guard parts.count == 2, String(parts[0]) == day else { return 0 }
        return max(0, Int(parts[1]) ?? 0)
    }

    /// The record with one more on `day`.
    static func recording(_ record: String?, day: String) -> String {
        "\(day):\(count(in: record, day: day) + 1)"
    }

    static func fusionsToday(defaults: UserDefaults = .standard, now: Date = Date()) -> Int {
        count(in: defaults.string(forKey: DefaultsKey.notchMascotFusionsToday), day: NotchMascotSpecialDays.key(for: now))
    }

    static func noteFusion(defaults: UserDefaults = .standard, now: Date = Date()) {
        let day = NotchMascotSpecialDays.key(for: now)
        defaults.set(recording(defaults.string(forKey: DefaultsKey.notchMascotFusionsToday), day: day),
                     forKey: DefaultsKey.notchMascotFusionsToday)
    }

    /// Never with Reduce Motion or Low Power Mode: it is all motion and flashes.
    static func allowed(reduceMotion: Bool, lowPower: Bool) -> Bool { !reduceMotion && !lowPower }

    /// How long this one lasts, `random` in 0..<1.
    static func duration(of fused: Fused, random: Double) -> TimeInterval {
        let range = fused.flop == nil ? length : flopLength
        return range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, random))
    }

    /// The small hours, when the rare night fusions come.
    static func isNight(_ hour: Int) -> Bool { hour >= 21 || hour < 5 }

    // MARK: What it looks like

    /// What its aura is made of.
    enum Aura: String, CaseIterable, Equatable {
        /// Rising flames.
        case blaze
        /// Flames and lightning.
        case storm
        /// Wisps that swirl about it.
        case spirit
        /// Ice crystals and glitter.
        case frost
        /// Bubbles rising.
        case bubbles
        /// Twinkling stars.
        case stardust
        /// Petals in a swirl.
        case bloom
        /// Flickering squares of light.
        case glitch
        /// A fusion gone wrong: grey puffs that sputter.
        case fizzle

        /// The stronger of two, for a pair that brings two auras.
        static let strength: [Aura] = [.storm, .blaze, .spirit, .frost, .glitch, .bubbles, .bloom, .stardust, .fizzle]
    }

    /// What says it is two in one.
    enum Mark: Equatable {
        /// A pair of earrings, one from each.
        case earrings
        /// A gem on its brow.
        case gem
        case none
    }

    /// What the poses got wrong.
    enum Flop: String, CaseIterable, Equatable {
        /// Round and squat, puffing.
        case chubby
        /// Tall and thin, shaking at the knees.
        case scrawny
        /// Leaning over to one side, everything a little off.
        case wonky

        var stretch: CGSize {
            switch self {
            case .chubby: return CGSize(width: 1.38, height: 0.8)
            case .scrawny: return CGSize(width: 0.66, height: 1.28)
            case .wonky: return CGSize(width: 1.12, height: 0.92)
            }
        }

        var shear: CGFloat { self == .wonky ? 0.3 : 0 }
    }

    /// What the fused one does to show off.
    enum Move: String, CaseIterable, Equatable {
        // Every fused one's.
        /// Energy gathered in its hands and fired across the floor.
        case blast
        /// Gone in a flicker and there again, a few times over.
        case teleport
        /// A shout that shakes the air around it.
        case kiShout
        // The signature moves.
        /// Up in the air and a rain of fireballs.
        case inferno
        /// Two great pounces, along the floor and back.
        case pounce
        /// Blue wisps that circle it and fly off.
        case foxfire
        /// Spun up to a blur in a storm of sparks.
        case overclock
        /// Skipping along in glitches, leaving copies behind.
        case glitchStep
        /// A slide along the floor on a trail of ice.
        case iceSlide
        /// A pirouette and a great leap in a shower of petals.
        case grandJete
        /// Sitting still as ripples spread round it.
        case zenRipple
        /// It sucks in the air and lets out a burp of smoke.
        case gulp
        /// Two minds in one body: it runs one way, then the other.
        case scurry
        /// A stream of bubbles across the floor.
        case bubbleBeam
        /// Stars falling round it.
        case starfall
        // A fusion gone wrong.
        /// A blast that comes out as a puff.
        case fizzle
        /// It tries a pose and wobbles over.
        case wobble
    }

    /// Every fused one shows these off, besides its signature.
    static let common: [Move] = [.blast, .teleport, .kiShout]
    /// What a fusion gone wrong manages instead.
    static let flopMoves: [Move] = [.fizzle, .wobble]

    /// The next move of the fused one: its signature most often, never the
    /// one it just did.
    static func nextMove(for fused: Fused, recent: [Move], random: () -> Double) -> Move {
        let options: [(Move, Double)]
        if fused.flop != nil {
            options = flopMoves.map { ($0, 1) }
        } else {
            options = [(fused.signature, 3)] + common.filter { $0 != fused.signature }.map { ($0, $0 == .kiShout ? 1.4 : 2) }
        }
        let weighted = options.map { ($0.0, recent.last == $0.0 ? 0 : $0.1) }.filter { $0.1 > 0 }
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return options.first?.0 ?? .blast }
        var roll = random() * total
        for (move, weight) in weighted {
            if roll < weight { return move }
            roll -= weight
        }
        return weighted.last?.0 ?? .blast
    }

    // MARK: The fused one

    /// What two make together.
    struct Fused: Equatable {
        /// Its name: a special one's own, or the two names run together.
        var name: String
        /// One of the catalog's, rather than the rule for any pair.
        var special: Bool
        /// The first of the two gives the body and stays out; the other goes in.
        var bodyIsFirst: Bool
        var look: NotchMascotFusionLook
        var signature: Move
        /// The poses did not match.
        var flop: Flop?
    }

    /// What `first` and `second` make, named `names` in the app's language,
    /// at `hour`. `random` gives numbers in 0..<1.
    static func fuse(_ first: NotchMascotLook, _ second: NotchMascotLook, names: (String, String), hour: Int,
                     random: () -> Double) -> Fused {
        if random() < flopChance {
            let flop = Flop.allCases[min(Flop.allCases.count - 1, Int(random() * Double(Flop.allCases.count)))]
            return flopped(first, second, names: names, flop: flop, bodyIsFirst: random() < 0.5)
        }
        if let special = special(first, second, hour: hour) {
            let look = NotchMascotFusionLook(aura: special.aura, primary: rgb(special.primary),
                                             secondary: rgb(special.secondary), split: special.split, mark: special.mark,
                                             scale: special.scale)
            return Fused(name: special.name, special: true, bodyIsFirst: first.style == special.body, look: look,
                         signature: special.signature, flop: nil)
        }
        return generic(first, second, names: names)
    }

    /// The rule for any pair: the body of the first, unless the first is the
    /// plain shape and the second is a figure; the colours of both, blended
    /// when they are close and split when they are far apart; the stronger
    /// aura of the two; earrings; and the move of the one that goes in.
    static func generic(_ first: NotchMascotLook, _ second: NotchMascotLook, names: (String, String)) -> Fused {
        let bodyIsFirst = !(first.style == .minimal && second.style != .minimal)
        let a = color(of: first), b = color(of: second)
        let split = distance(a, b) > 0.5
        let auras = [element(of: first.style).aura, element(of: second.style).aura]
        let aura = Aura.strength.first { auras.contains($0) } ?? .storm
        let donor = bodyIsFirst ? second : first
        let look = NotchMascotFusionLook(aura: aura, primary: split ? a : mix(a, b), secondary: b, split: split,
                                         mark: .earrings, scale: 1.3)
        return Fused(name: portmanteau(names.0, names.1), special: false, bodyIsFirst: bodyIsFirst, look: look,
                     signature: element(of: donor.style).move, flop: nil)
    }

    /// A fusion gone wrong: muddy colours, a fizzling aura, no earrings, a
    /// lumpy body and its name the wrong way round.
    static func flopped(_ first: NotchMascotLook, _ second: NotchMascotLook, names: (String, String), flop: Flop,
                        bodyIsFirst: Bool) -> Fused {
        let mud = NotchMascotColor(red: 0.55, green: 0.5, blue: 0.44)
        let a = mix(color(of: first), mud, 0.45), b = mix(color(of: second), mud, 0.45)
        let look = NotchMascotFusionLook(aura: .fizzle, primary: flop == .wonky ? a : mix(a, b), secondary: b,
                                         split: flop == .wonky, mark: .none, scale: 1.12, stretch: flop.stretch,
                                         shear: flop.shear)
        return Fused(name: portmanteau(names.1, names.0), special: false, bodyIsFirst: bodyIsFirst, look: look,
                     signature: .fizzle, flop: flop)
    }

    /// The fused one's whole look: the body's figure and shape, painted in
    /// the fusion's colours, wearing the other's thing when it has one.
    static func look(of fused: Fused, first: NotchMascotLook, second: NotchMascotLook) -> NotchMascotLook {
        var look = fused.bodyIsFirst ? first : second
        let donor = fused.bodyIsFirst ? second : first
        look.form = nil
        look.customColor = fused.look.primary
        if donor.accessory != .none, look.style.takesAccessory { look.accessory = donor.accessory }
        look.fusion = fused.look
        return look
    }

    // MARK: The catalog

    /// A pair that makes a fusion of its own.
    struct Special: Equatable {
        var name: String
        /// The two figures, or one figure with any other.
        var styles: [NotchMascotStyle]
        /// Worn by either of them, when it takes a thing.
        var item: NotchMascotAccessory? = nil
        /// Only in the small hours.
        var night = false
        /// The figure that gives the body.
        var body: NotchMascotStyle
        var primary: UInt32
        var secondary: UInt32
        var split: Bool
        var aura: Aura
        var mark: Mark
        var signature: Move
        var scale: CGFloat = 1.35

        /// Whether `a` and `b`, at `hour`, make it.
        func matches(_ a: NotchMascotLook, _ b: NotchMascotLook, hour: Int) -> Bool {
            if night, !NotchMascotFusion.isNight(hour) { return false }
            if let item, a.accessory != item, b.accessory != item { return false }
            if styles.count == 2 { return styles.sorted { $0.rawValue < $1.rawValue } == [a.style, b.style].sorted { $0.rawValue < $1.rawValue } }
            return styles.first.map { $0 == a.style || $0 == b.style } ?? false
        }

        /// The more a fusion asks for, the more it wins over a plainer one.
        var rank: Int { (item == nil ? 0 : 2) + (night ? 1 : 0) }
    }

    /// The special one `a` and `b` make at `hour`, if any: the one that asks
    /// for the most, then the first in the catalog.
    static func special(_ a: NotchMascotLook, _ b: NotchMascotLook, hour: Int) -> Special? {
        catalog.enumerated().filter { $0.element.matches(a, b, hour: hour) }
            .max { ($0.element.rank, -$0.offset) < ($1.element.rank, -$1.offset) }?.element
    }

    static let catalog: [Special] = [
        // Fire and wings.
        Special(name: "Infernix", styles: [.dragon, .phoenix], body: .dragon, primary: 0xFF5A1F, secondary: 0xFFC93C,
                split: true, aura: .blaze, mark: .earrings, signature: .inferno, scale: 1.45),
        Special(name: "Eclipse Wyrm", styles: [.dragon, .phoenix], night: true, body: .dragon, primary: 0x4B2A8C,
                secondary: 0xFFB300, split: true, aura: .storm, mark: .gem, signature: .inferno, scale: 1.5),
        Special(name: "Firebird", styles: [.phoenix, .swan], body: .swan, primary: 0xFF7A2E, secondary: 0xFFF1E0,
                split: true, aura: .blaze, mark: .gem, signature: .grandJete),
        Special(name: "Wraithwing", styles: [.ghost, .phoenix], body: .phoenix, primary: 0x9C7BFF, secondary: 0xFF7A2E,
                split: true, aura: .spirit, mark: .earrings, signature: .inferno),
        Special(name: "Kitsuryū", styles: [.kitsune, .dragon], body: .dragon, primary: 0x58C8FF, secondary: 0xFF6A3D,
                split: true, aura: .spirit, mark: .gem, signature: .foxfire, scale: 1.4),
        // Furry friends, and not so friendly.
        Special(name: "Pawsome", styles: [.cat, .dog], body: .dog, primary: 0xE8A25C, secondary: 0x8E959E,
                split: true, aura: .stardust, mark: .earrings, signature: .pounce),
        Special(name: "Catastrophe", styles: [.mouse, .cat], body: .cat, primary: 0xB9AFC9, secondary: 0x6EE07A,
                split: true, aura: .glitch, mark: .earrings, signature: .scurry),
        Special(name: "Sledgehound", styles: [.dog, .penguin], body: .dog, primary: 0x2A3142, secondary: 0xE0A766,
                split: true, aura: .frost, mark: .earrings, signature: .iceSlide),
        // Spirits.
        Special(name: "Onibi", styles: [.kitsune, .ghost], body: .kitsune, primary: 0x7FD3FF, secondary: 0xC9B6FF,
                split: false, aura: .spirit, mark: .gem, signature: .foxfire),
        Special(name: "Ectoplasm", styles: [.ghost, .slime], body: .ghost, primary: 0xB8A6FF, secondary: 0xA8F05A,
                split: true, aura: .spirit, mark: .earrings, signature: .teleport),
        // Machines.
        Special(name: "Synthron", styles: [.robot, .android], body: .android, primary: 0xFF4D4D, secondary: 0xFFC861,
                split: true, aura: .storm, mark: .earrings, signature: .overclock),
        Special(name: "Neonova", styles: [.hologram, .android], body: .hologram, primary: 0xFF5CB8, secondary: 0x5CE1FF,
                split: true, aura: .glitch, mark: .gem, signature: .glitchStep),
        Special(name: "Turbochip", styles: [.fan, .chip], body: .chip, primary: 0x5CF2FF, secondary: 0xFFB23C,
                split: true, aura: .storm, mark: .earrings, signature: .overclock),
        Special(name: "Mainframe", styles: [.robot, .chip], body: .robot, primary: 0x9AA4B2, secondary: 0x3FD17A,
                split: true, aura: .glitch, mark: .gem, signature: .overclock),
        // Ice and feathers.
        Special(name: "Glacia", styles: [.penguin, .swan], body: .swan, primary: 0xF4F8FF, secondary: 0x1C2333,
                split: true, aura: .frost, mark: .gem, signature: .iceSlide),
        Special(name: "Blizzard", styles: [.fan, .penguin], body: .penguin, primary: 0xBDEBFF, secondary: 0x2FD8F0,
                split: false, aura: .frost, mark: .earrings, signature: .iceSlide),
        // Dancers.
        Special(name: "Pas de Deux", styles: [.ballerina, .danseur], body: .ballerina, primary: 0xFFB7D2, secondary: 0xC4283A,
                split: true, aura: .bloom, mark: .earrings, signature: .grandJete),
        Special(name: "Odette", styles: [.swan, .ballerina], body: .ballerina, primary: 0xFFFFFF, secondary: 0xFFB7D2,
                split: false, aura: .bloom, mark: .gem, signature: .grandJete),
        Special(name: "Odile", styles: [.swan, .ballerina], night: true, body: .ballerina, primary: 0x1A1A24,
                secondary: 0xC4283A, split: true, aura: .spirit, mark: .gem, signature: .grandJete, scale: 1.4),
        Special(name: "Lumen", styles: [.contemporary, .hologram], body: .contemporary, primary: 0x3FD1C7,
                secondary: 0xFF5CB8, split: true, aura: .glitch, mark: .gem, signature: .grandJete),
        // Pond and spa.
        Special(name: "Zenpond", styles: [.capybara, .frog], body: .capybara, primary: 0xC88A4A, secondary: 0x5BCB5F,
                split: true, aura: .bubbles, mark: .earrings, signature: .zenRipple),
        Special(name: "Onsen", styles: [.capybara, .axolotl], body: .capybara, primary: 0xD99A5B, secondary: 0xFF9ECF,
                split: false, aura: .bubbles, mark: .earrings, signature: .zenRipple),
        Special(name: "Ribbolotl", styles: [.axolotl, .frog], body: .axolotl, primary: 0xFF9ECF, secondary: 0x46D17A,
                split: true, aura: .bubbles, mark: .earrings, signature: .bubbleBeam),
        Special(name: "Gobbleglob", styles: [.devourer, .slime], body: .slime, primary: 0xFF8FC8, secondary: 0x9CF04A,
                split: false, aura: .bubbles, mark: .earrings, signature: .gulp, scale: 1.45),
        // With a thing on.
        Special(name: "Frog Prince", styles: [.frog], item: .crown, body: .frog, primary: 0x5BCB5F, secondary: 0xFFD23F,
                split: false, aura: .stardust, mark: .gem, signature: .bubbleBeam),
        Special(name: "Tamamo", styles: [.kitsune], item: .crystalOrb, body: .kitsune, primary: 0xFFF3D6, secondary: 0x9B7BFF,
                split: false, aura: .stardust, mark: .gem, signature: .foxfire, scale: 1.4),
        Special(name: "Raijin", styles: [.dragon], item: .thunderTalisman, body: .dragon, primary: 0x2E6BFF,
                secondary: 0xFFF06A, split: true, aura: .storm, mark: .earrings, signature: .overclock, scale: 1.45),
        Special(name: "Mega Muncher", styles: [.devourer], item: .magicMushroom, body: .devourer, primary: 0xFF5E8A,
                secondary: 0xFFE14D, split: true, aura: .stardust, mark: .earrings, signature: .gulp, scale: 1.6),
        Special(name: "Poltergeist", styles: [.ghost], item: .cursedMask, night: true, body: .ghost, primary: 0x3B2A55,
                secondary: 0x7CFF9E, split: true, aura: .spirit, mark: .gem, signature: .teleport, scale: 1.4),
    ]

    // MARK: Elements

    /// What a figure is made of, which picks the aura and the move it
    /// brings to a fusion of the plain rule.
    enum Element: Equatable {
        case fire, spirit, water, ice, tech, dance, beast, plain, comic

        var aura: Aura {
            switch self {
            case .fire: return .blaze
            case .spirit: return .spirit
            case .water: return .bubbles
            case .ice: return .frost
            case .tech, .plain: return .storm
            case .dance: return .bloom
            case .beast, .comic: return .stardust
            }
        }

        var move: Move {
            switch self {
            case .fire: return .inferno
            case .spirit: return .foxfire
            case .water: return .bubbleBeam
            case .ice: return .iceSlide
            case .tech: return .overclock
            case .dance: return .grandJete
            case .beast: return .pounce
            case .plain: return .kiShout
            case .comic: return .starfall
            }
        }
    }

    static func element(of style: NotchMascotStyle) -> Element {
        switch style {
        case .dragon, .phoenix: return .fire
        case .ghost, .kitsune, .shifter: return .spirit
        case .axolotl, .frog, .slime: return .water
        case .penguin, .swan: return .ice
        case .robot, .chip, .fan, .android, .hologram: return .tech
        case .ballerina, .danseur, .contemporary: return .dance
        case .cat, .dog, .mouse, .devourer, .capybara: return .beast
        case .minimal: return .plain
        case .cristobal, .whiteRabbit: return .comic
        }
    }

    // MARK: Colours

    /// The colour a companion brings: its hand-picked one, its swatch for
    /// the plain shape and the robot, else its figure's energy.
    static func color(of look: NotchMascotLook) -> NotchMascotColor {
        if let custom = look.customColor { return custom }
        if look.style == .minimal || look.style == .robot { return look.palette.shade }
        var plain = look
        plain.form = nil
        let energy = NotchMascotPlay.energy(for: plain)
        return NotchMascotColor(red: energy.red, green: energy.green, blue: energy.blue)
    }

    static func mix(_ a: NotchMascotColor, _ b: NotchMascotColor, _ share: CGFloat = 0.5) -> NotchMascotColor {
        NotchMascotColor(red: a.red + (b.red - a.red) * share, green: a.green + (b.green - a.green) * share,
                         blue: a.blue + (b.blue - a.blue) * share)
    }

    static func distance(_ a: NotchMascotColor, _ b: NotchMascotColor) -> CGFloat {
        sqrt(pow(a.red - b.red, 2) + pow(a.green - b.green, 2) + pow(a.blue - b.blue, 2))
    }

    private static func rgb(_ hex: UInt32) -> NotchMascotColor {
        NotchMascotColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                         blue: CGFloat(hex & 0xFF) / 255)
    }

    // MARK: Names

    /// Two names run into one: the start of the first and the end of the
    /// second, cut where a syllable ends and one begins, as "Cat" and "Dog"
    /// make "Catdog" and "Frog" and "Axolotl" make "Froglotl". Names in a
    /// script without vowels to cut at, as Japanese or Chinese, give half of
    /// each. Only the first word of the first and the last of the second.
    static func portmanteau(_ first: String, _ second: String) -> String {
        let a = Array(first.split(separator: " ").first.map(String.init) ?? first)
        let b = Array(second.split(separator: " ").last.map(String.init) ?? second)
        guard !a.isEmpty else { return String(b) }
        guard !b.isEmpty else { return String(a) }
        guard a.contains(where: isVowel), b.contains(where: isVowel) else {
            return String(a.prefix(max(1, (a.count + 1) / 2)) + b.suffix(max(1, b.count / 2)))
        }
        let head = a.count <= 4 ? a : Array(a.prefix(headEnd(a)))
        let tail = b.count <= 3 ? b : Array(b.suffix(from: tailStart(b)))
        let joined = String(head) + String(tail).lowercased()
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    /// Where the first name is cut: after the syllable that ends nearest its
    /// middle and, of two as near, the one closed by a consonant.
    private static func headEnd(_ name: [Character]) -> Int {
        let middle = Double(name.count + 1) / 2
        let ends = (2..<name.count).filter { end in
            isVowel(name[end - 1]) != isVowel(name[end])
        }
        func rank(_ end: Int) -> (Double, Int) { (abs(Double(end) - middle), isVowel(name[end - 1]) ? 1 : 0) }
        return ends.min { rank($0) < rank($1) } ?? (name.count + 1) / 2
    }

    /// Where the second name is taken from: a consonant that starts a
    /// syllable, the one nearest its middle and, of two as near, the first.
    private static func tailStart(_ name: [Character]) -> Int {
        let middle = Double(name.count) / 2
        let onsets = (0..<(name.count - 1)).filter { !isVowel(name[$0]) && isVowel(name[$0 + 1]) }
        return onsets.min { abs(Double($0) - middle) < abs(Double($1) - middle) } ?? name.count / 2
    }

    private static let vowels = Set("aeiouyáéíóúàèìòùâêîôûäëïöüãõåæœıаеёиоуыэюяіїє")

    private static func isVowel(_ character: Character) -> Bool {
        character.lowercased().first.map(vowels.contains) ?? false
    }
}
