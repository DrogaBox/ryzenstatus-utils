// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

// MARK: - Stimuli

/// What one companion throws at another in a chain reaction: fire from a
/// torch, water from a balloon, a gust from a leaf blower, a spark from a
/// plasma ball, frost, light, a sound, pepper, a bonk, a magnet's pull,
/// the smell of something sweet, goo, a hypnotic spiral or a tickle.
enum NotchMascotStimulus: String, CaseIterable, Codable {
    case fire, water, wind, shock, frost, light, sound, pepper, impact, magnet, sweet, goo, hypno, tickle

    /// What flies from one to the other.
    var thing: NotchMascotIslandPlay.Thing {
        switch self {
        case .fire: return .fireball
        case .water: return .drop
        case .wind: return .tornado
        case .shock: return .bolt
        case .frost: return .snowball
        case .light: return .star
        case .sound: return .note
        case .pepper: return .pepper
        case .impact: return .ball
        case .magnet: return .coin
        case .sweet: return .heart
        case .goo: return .goo
        case .hypno: return .spiral
        case .tickle: return .feather
        }
    }

    /// The arcade marker that rises where it lands.
    var marker: String {
        switch self {
        case .fire: return "FWOOSH"
        case .water: return "SPLASH"
        case .wind: return "WHOOSH"
        case .shock: return "ZAP!"
        case .frost: return "BRRR"
        case .light: return "FLASH"
        case .sound: return "BWAAA"
        case .pepper: return "ACHOO!"
        case .impact: return "BONK"
        case .magnet: return "CLANK"
        case .sweet: return "YUM?"
        case .goo: return "SPLAT"
        case .hypno: return "OOOH"
        case .tickle: return "HIHI"
        }
    }

    /// The burst where it lands.
    var burst: NotchMascotIslandPlay.Burst {
        switch self {
        case .fire, .impact, .pepper: return .smoke
        case .water, .goo: return .confetti
        case .wind, .frost, .light: return .sparkles
        case .shock, .hypno, .magnet: return .magic
        case .sound, .tickle: return .confetti
        case .sweet: return .hearts
        }
    }
}

// MARK: - Reactions

/// What a companion makes of a stimulus that reaches it: what it does, and
/// whether it throws something on, and to whom.
struct NotchMascotChainReaction: Equatable {
    /// Who decided it: what it wears, its figure, or the plain way.
    enum Source: Equatable {
        case item(NotchMascotAccessory)
        case style(NotchMascotStyle)
        case plain
    }

    /// Where what it throws goes.
    enum Target: Equatable {
        /// The nearest one not reached yet.
        case next
        /// Straight back at the one that threw it.
        case back
        /// Every other one out, at once; the chain ends there.
        case everyone
        /// Anyone at all but itself, even one already reached.
        case random
    }

    /// For the log of what has been found: `item.stimulus`, `style.stimulus`
    /// or `plain.stimulus`, with a suffix for an outcome of luck.
    var id: String
    var source: Source
    var steps: [NotchMascotItemUse.Step]
    /// What it throws on, if anything.
    var emits: NotchMascotStimulus? = nil
    var target: Target = .next
    /// Something rare it set off.
    var rare: NotchMascotChainRare? = nil

    init(_ id: String, _ source: Source, _ steps: [(TimeInterval, NotchMascotItemAction)],
         emits: NotchMascotStimulus? = nil, target: Target = .next, rare: NotchMascotChainRare? = nil) {
        self.id = id
        self.source = source
        self.steps = steps.map { NotchMascotItemUse.Step(at: $0.0, action: $0.1) }
        self.emits = emits
        self.target = target
        self.rare = rare
    }

    /// Until it is done.
    var length: TimeInterval { steps.map { $0.at + $0.action.length }.max() ?? 0 }

    /// Whether it ends the chain: nothing thrown on.
    var stops: Bool { emits == nil }

    /// The same, throwing nothing on: a pass that luck did not let through.
    func held() -> NotchMascotChainReaction {
        var copy = self
        copy.emits = nil
        return copy
    }
}

/// How a chain starts: what is thrown and what the thrower does first.
struct NotchMascotChainEmission: Equatable {
    var stimulus: NotchMascotStimulus
    var windup: [NotchMascotItemUse.Step]

    init(_ stimulus: NotchMascotStimulus, _ windup: [(TimeInterval, NotchMascotItemAction)]) {
        self.stimulus = stimulus
        self.windup = windup.map { NotchMascotItemUse.Step(at: $0.0, action: $0.1) }
    }

    /// When the thing leaves its hand.
    var release: TimeInterval { (windup.map(\.at).max() ?? 0) + 0.35 }
}

// MARK: - Rare events

/// The rare things a chain can set off, each with a show of the whole gang.
enum NotchMascotChainRare: String, CaseIterable, Codable {
    /// The chain reached every one of four or more.
    case perfectChain
    /// The mystery egg hatched a baby dragon.
    case babyDragon
    /// The mystery egg was gold all along.
    case goldenEgg
    /// Water on the seeds grew a beanstalk to the top of the screen.
    case beanstalk
    /// The piñata was a golden one.
    case goldenPinata
    /// A spark went through a plasma ball or a battery, a lightning rod and a machine.
    case blackout
    /// Frost reached water someone held: everyone slides on the ice.
    case iceAge
    /// Light bounced off two mirrors or a disco ball: a laser show.
    case supernova
    /// The sneeze went round four or more: every hat flies off.
    case sneezeStorm
    /// The tickle went round three or more: everyone on the floor laughing.
    case laughingFit
    /// The hypnosis went round three or more: a zombie conga.
    case zombieConga
    /// Somebody pressed the big red button and it did everything.
    case bigBang
    /// The metal detector found real treasure.
    case treasure
    /// A firework went up with a torch or a sparkler near: a whole display.
    case fireworks
    /// The voodoo doll sent it all back to its own holder.
    case voodooCurse
    /// Dynamite and fire.
    case kaboom

    /// The gold it pays, within the day's share of luck.
    var gold: Int {
        switch self {
        case .perfectChain: return 40
        case .beanstalk: return 30
        case .bigBang: return 25
        // The egg, the piñata and the treasure pay theirs as they show it.
        case .goldenEgg, .goldenPinata, .treasure,
             .babyDragon, .blackout, .iceAge, .supernova, .sneezeStorm, .laughingFit, .zombieConga,
             .fireworks, .voodooCurse, .kaboom: return 0
        }
    }

    /// Its marker over the gang.
    var marker: String {
        switch self {
        case .perfectChain: return "PERFECT!"
        case .babyDragon: return "BABY DRAGON!"
        case .goldenEgg: return "GOLD EGG!"
        case .beanstalk: return "BEANSTALK!"
        case .goldenPinata: return "JACKPOT!"
        case .blackout: return "BLACKOUT"
        case .iceAge: return "ICE AGE"
        case .supernova: return "SUPERNOVA"
        case .sneezeStorm: return "ACHOO X4"
        case .laughingFit: return "HAHAHA"
        case .zombieConga: return "BRAINS"
        case .bigBang: return "BIG BANG"
        case .treasure: return "TREASURE!"
        case .fireworks: return "OOOH!"
        case .voodooCurse: return "CURSED"
        case .kaboom: return "KABOOM"
        }
    }

    var name: String {
        switch self {
        case .perfectChain: return "Perfect chain"
        case .babyDragon: return "Baby dragon"
        case .goldenEgg: return "Golden egg"
        case .beanstalk: return "Magic beanstalk"
        case .goldenPinata: return "Golden piñata"
        case .blackout: return "Blackout"
        case .iceAge: return "Ice age"
        case .supernova: return "Supernova"
        case .sneezeStorm: return "Sneeze storm"
        case .laughingFit: return "Laughing fit"
        case .zombieConga: return "Zombie conga"
        case .bigBang: return "Big bang"
        case .treasure: return "Buried treasure"
        case .fireworks: return "Fireworks display"
        case .voodooCurse: return "Voodoo curse"
        case .kaboom: return "Kaboom"
        }
    }

    var nameES: String {
        switch self {
        case .perfectChain: return "Cadena perfecta"
        case .babyDragon: return "Dragoncito"
        case .goldenEgg: return "Huevo de oro"
        case .beanstalk: return "Habichuela mágica"
        case .goldenPinata: return "Piñata dorada"
        case .blackout: return "Apagón"
        case .iceAge: return "Edad de hielo"
        case .supernova: return "Supernova"
        case .sneezeStorm: return "Tormenta de estornudos"
        case .laughingFit: return "Ataque de risa"
        case .zombieConga: return "Conga zombi"
        case .bigBang: return "Big bang"
        case .treasure: return "Tesoro enterrado"
        case .fireworks: return "Fuegos artificiales"
        case .voodooCurse: return "Maldición vudú"
        case .kaboom: return "Kabum"
        }
    }

    func title(in language: AppLanguage) -> String { language == .es ? nameES : name }
}

// MARK: - The chain

/// One of those out together, as the chain sees it.
struct NotchMascotChainMember: Equatable {
    var item: NotchMascotAccessory
    var style: NotchMascotStyle
    /// Where it stands across the screen.
    var x: CGFloat
    /// Transformed, which makes it shrug off what the plain ones do not.
    var formed = false

    init(_ item: NotchMascotAccessory, _ style: NotchMascotStyle, x: CGFloat, formed: Bool = false) {
        self.item = item
        self.style = style
        self.x = x
        self.formed = formed
    }
}

/// One throw of the chain and what came of it.
struct NotchMascotChainLink: Equatable {
    var from: Int
    var to: Int
    var stimulus: NotchMascotStimulus
    var reaction: NotchMascotChainReaction
    /// Thrown at every one at once, with the links beside it.
    var fanOut = false
}

/// A whole chain, worked out before it plays, so every rule is tested.
struct NotchMascotChainPlan: Equatable {
    var starter: Int
    var emission: NotchMascotChainEmission
    var links: [NotchMascotChainLink]
    /// The rare things it set off, each once, in the order they came.
    var rares: [NotchMascotChainRare]

    /// Every one it reached, the starter included.
    var reached: Set<Int> { Set([starter] + links.map(\.to)) }

    /// What the log keeps of it.
    var found: [String] { links.map(\.reaction.id) }
    /// The same, with its luck settled as it starts: the gold its reactions
    /// and its rare things bring is paid within the day's share, and what the
    /// day can no longer pay is left out rather than shown and not given.
    func settled(pay: @escaping (Int) -> Int = { NotchMascotLuck.pay($0) },
                 collect: @escaping (Int) -> Void = { NotchMascotRPG.collect(gold: $0) }) -> NotchMascotChainPlan {
        var copy = self
        copy.links = links.map { link in
            var link = link
            link.reaction.steps = NotchMascotItemUse(link.reaction.steps.map { ($0.at, $0.action) })
                .settled(pay: pay, collect: collect).steps
            return link
        }
        return copy
    }
}

/// Chain reactions: one throws what it holds at the nearest friend, who
/// makes something of it by what it wears, what it is or the plain way,
/// and maybe throws something on, and so on down the line.
enum NotchMascotChain {
    // MARK: When

    /// Out on the desktop, at least this long between two chains of the gang.
    static let interval: TimeInterval = 75
    /// Once one is due and one standing about could start it, the share of chances it does.
    static let chance = 0.35
    /// In the closed island, the share of item uses that become a chain
    /// when the other one rests there too.
    static let islandChance = 0.4
    /// No chain is longer than this many throws.
    static let maxLinks = 8
    /// The fewest out for a perfect chain.
    static let perfectMinimum = 4
    /// From one throw landing to the next leaving, at most.
    static let handoff: TimeInterval = 1.6

    static func shouldStart(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }

    // MARK: Who throws what

    /// What `item` on `style` throws to start a chain: what it holds first,
    /// else what its figure breathes or blows.
    static func emission(item: NotchMascotAccessory, style: NotchMascotStyle) -> NotchMascotChainEmission? {
        if style.takesAccessory, let thrown = NotchMascotChainReactions.itemEmission(item) { return thrown }
        return NotchMascotChainReactions.styleEmission(style)
    }

    /// What a member makes of `stimulus`: what it wears first, then its
    /// figure, then the plain way. `random` settles luck.
    static func reaction(of member: NotchMascotChainMember, to stimulus: NotchMascotStimulus,
                         random: () -> Double) -> NotchMascotChainReaction {
        if member.style.takesAccessory, member.item != .none,
           let own = NotchMascotChainReactions.itemReaction(member.item, to: stimulus, random: random) {
            return own
        }
        if let figure = NotchMascotChainReactions.styleReaction(member.style, to: stimulus, random: random) { return figure }
        return NotchMascotChainReactions.plainReaction(to: stimulus, random: random)
    }

    // MARK: Planning

    /// The chain `starter` sets off among `members`, if it throws anything
    /// and someone else is there. Each throw goes to the nearest one not
    /// reached yet, or where the reaction sends it; one thrown back counts
    /// once; it stops when a reaction throws nothing on, nobody is left, or
    /// after `maxLinks` throws.
    static func plan(_ members: [NotchMascotChainMember], starter: Int,
                     random: () -> Double = { Double.random(in: 0..<1) }) -> NotchMascotChainPlan? {
        guard members.indices.contains(starter), members.count >= 2,
              let emission = emission(item: members[starter].item, style: members[starter].style) else { return nil }
        var links: [NotchMascotChainLink] = []
        var reached: Set<Int> = [starter]
        var current = starter
        var previous: Int?
        var stimulus = emission.stimulus
        var target = NotchMascotChainReaction.Target.next
        var thrownBack = false

        while links.count < maxLinks {
            if target == .everyone {
                for other in members.indices where other != current {
                    let reaction = self.reaction(of: members[other], to: stimulus, random: random)
                    links.append(NotchMascotChainLink(from: current, to: other, stimulus: stimulus, reaction: reaction.held(),
                                                      fanOut: true))
                    reached.insert(other)
                }
                break
            }
            let next: Int?
            switch target {
            case .next: next = nearest(to: current, among: members, excluding: reached)
            case .back:
                if thrownBack { next = nearest(to: current, among: members, excluding: reached) } else {
                    thrownBack = true
                    next = previous
                }
            case .random:
                let others = members.indices.filter { $0 != current }
                next = others.isEmpty ? nil : others[min(others.count - 1, Int(random() * Double(others.count)))]
            case .everyone: next = nil
            }
            guard let to = next else { break }
            let reaction = self.reaction(of: members[to], to: stimulus, random: random)
            links.append(NotchMascotChainLink(from: current, to: to, stimulus: stimulus, reaction: reaction))
            reached.insert(to)
            guard let thrown = reaction.emits else { break }
            previous = current
            current = to
            stimulus = thrown
            target = reaction.target
        }
        guard !links.isEmpty else { return nil }
        let plan = NotchMascotChainPlan(starter: starter, emission: emission, links: links, rares: [])
        return NotchMascotChainPlan(starter: starter, emission: emission, links: links,
                                    rares: rares(of: plan, among: members))
    }

    /// The nearest to `index` across the screen not in `excluding`; the
    /// first in order on a tie.
    static func nearest(to index: Int, among members: [NotchMascotChainMember], excluding: Set<Int>) -> Int? {
        let here = members[index].x
        return members.indices.filter { $0 != index && !excluding.contains($0) }
            .min { abs(members[$0].x - here) < abs(members[$1].x - here) }
    }

    /// What is rare about a chain: what its reactions set off, then what
    /// the whole of it makes.
    static func rares(of plan: NotchMascotChainPlan, among members: [NotchMascotChainMember]) -> [NotchMascotChainRare] {
        var found: [NotchMascotChainRare] = []
        func add(_ rare: NotchMascotChainRare) { if !found.contains(rare) { found.append(rare) } }
        plan.links.compactMap(\.reaction.rare).forEach(add)

        func count(_ stimulus: NotchMascotStimulus) -> Int { plan.links.filter { $0.stimulus == stimulus }.count }
        if count(.pepper) >= 4 { add(.sneezeStorm) }
        if count(.tickle) >= 3 { add(.laughingFit) }
        if count(.hypno) >= 3 { add(.zombieConga) }

        // A spark through a plasma ball or a battery, a lightning rod and a machine.
        let shocked = Set(plan.links.filter { $0.stimulus == .shock }.map(\.to)
                          + (plan.emission.stimulus == .shock ? [plan.starter] : []))
        let shockedItems = Set(shocked.map { members[$0].item })
        let machines: Set<NotchMascotStyle> = [.robot, .chip, .android, .hologram]
        if !shockedItems.isDisjoint(with: [.plasmaBall, .batteryPack]), shockedItems.contains(.lightningRod),
           shocked.contains(where: { machines.contains(members[$0].style) }) {
            add(.blackout)
        }
        // Light off two mirrors, or off a disco ball.
        let mirrors = plan.links.filter { $0.stimulus == .light && $0.reaction.emits == .light }
            .filter { [.pocketMirror, .discoBall].contains(members[$0.to].item) }
        if mirrors.count >= 2 || mirrors.contains(where: { members[$0.to].item == .discoBall }) { add(.supernova) }

        // Fire reaching a firework while a torch or a sparkler stands in the gang.
        let fireworkLit = plan.links.contains { $0.stimulus == .fire && members[$0.to].item == .fireworkRocket }
        if fireworkLit, members.contains(where: { [.torch, .sparkler].contains($0.item) }) { add(.fireworks) }
        if members.count >= perfectMinimum, plan.reached.count == members.count { add(.perfectChain) }
        return found
    }
}

// MARK: - In the island
extension NotchMascotChain {
    /// A chain between the two resting in the island, the companion first:
    /// thrown across the room, taken there, and maybe thrown back. Where
    /// they cannot leave their places a move shows as its reaction.
    static func islandPlay(_ plan: NotchMascotChainPlan, item: NotchMascotAccessory) -> NotchMascotIslandPlay {
        let byLeader = plan.starter == 0
        var score = NotchMascotIslandPlay.Score(byLeader: byLeader)
        let windup = NotchMascotItemUse(plan.emission.windup.map { ($0.at, $0.action) })
        score.beats += windup.islandBeats(byLeader: byLeader)
        var at = plan.emission.release
        for link in plan.links {
            let fromStarter = (link.from == 0) == byLeader
            score.toss(at, link.stimulus.thing, fromStarter: fromStarter)
            let lands = at + NotchMascotIslandPlay.flightLength
            score.burst(lands, link.stimulus.burst, onStarter: !fromStarter)
            let taken = NotchMascotItemUse(link.reaction.steps.map { ($0.at, $0.action) })
            score.beats += taken.islandBeats(byLeader: link.to == 0).map { beat in
                var beat = beat
                beat.at += lands
                return beat
            }
            at = lands + min(handoff, max(0.6, link.reaction.length * 0.6))
        }
        return NotchMascotIslandPlay(kind: .item(item), beats: score.beats.sorted { $0.at < $1.at })
    }
}
// MARK: - The log

/// What chains have been seen: each reaction and each rare thing once, kept
/// in the preferences so Settings can say how many are left to find.
enum NotchMascotChainLog {
    static func found(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.notchMascotChainsFound) ?? [])
    }

    static func rares(in defaults: UserDefaults = .standard) -> Set<NotchMascotChainRare> {
        Set((defaults.stringArray(forKey: DefaultsKey.notchMascotChainRaresFound) ?? [])
            .compactMap(NotchMascotChainRare.init(rawValue:)))
    }

    /// Keeps what `plan` showed; the new ones it found, for a marker.
    @discardableResult
    static func record(_ plan: NotchMascotChainPlan, in defaults: UserDefaults = .standard) -> (reactions: Int, rares: [NotchMascotChainRare]) {
        let known = found(in: defaults)
        let fresh = Set(plan.found).subtracting(known)
        if !fresh.isEmpty { defaults.set(Array(known.union(fresh)).sorted(), forKey: DefaultsKey.notchMascotChainsFound) }
        let knownRares = rares(in: defaults)
        let newRares = plan.rares.filter { !knownRares.contains($0) }
        if !newRares.isEmpty {
            defaults.set(knownRares.union(newRares).map(\.rawValue).sorted(), forKey: DefaultsKey.notchMascotChainRaresFound)
        }
        return (fresh.count, newRares)
    }
}
