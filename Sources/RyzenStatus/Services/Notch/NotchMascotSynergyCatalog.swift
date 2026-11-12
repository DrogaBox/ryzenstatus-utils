// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The families the combos are grouped in.
enum SynergyCategory: Int, CaseIterable, Identifiable {
    case wonderBoy = 1, combat, magic, tavern, music, rogues, sciFi, twin, species, quests, curiosities, mascots, dance
    case toys, legends, signals, party, oddities
    /// A transformed companion meeting what the other wears.
    case forms
    /// The workshop's things.
    case workshop
    /// The fair and the field.
    case fair

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wonderBoy: return "Wonder Boy tributes"
        case .combat: return "RPG combat"
        case .magic: return "Magic and alchemy"
        case .tavern: return "Tavern and feast"
        case .music: return "Music and dance"
        case .rogues: return "Rogues and exploration"
        case .sciFi: return "Sci-fi and Ryzen hardware"
        case .twin: return "Twin and mirror combos"
        case .species: return "Species synergies"
        case .quests: return "Mini-quests and your input"
        case .curiosities: return "Shop curiosities"
        case .mascots: return "Glutton and Shifter"
        case .dance: return "Ballet and stage dance"
        case .toys: return "Toys and luck"
        case .legends: return "Kitsune and Penguin"
        case .signals: return "Hologram and Android"
        case .party: return "Party and play"
        case .oddities: return "Oddities and wonders"
        case .forms: return "Transformations"
        case .workshop: return "The workshop"
        case .fair: return "The fair and the field"
        }
    }

    var titleES: String {
        switch self {
        case .wonderBoy: return "Homenajes a Wonder Boy"
        case .combat: return "Combate RPG"
        case .magic: return "Magia y alquimia"
        case .tavern: return "Taberna y banquete"
        case .music: return "Música y baile"
        case .rogues: return "Pícaros y exploración"
        case .sciFi: return "Sci-fi y hardware Ryzen"
        case .twin: return "Combos gemelos y espejo"
        case .species: return "Sinergias de especie"
        case .quests: return "Mini-quests e interacción"
        case .curiosities: return "Curiosidades de la tienda"
        case .mascots: return "Tragón y Metamorfo"
        case .dance: return "Ballet y danza escénica"
        case .toys: return "Juguetes y suerte"
        case .legends: return "Kitsune y Pingüino"
        case .signals: return "Holograma y Androide"
        case .party: return "Fiesta y juego"
        case .oddities: return "Rarezas y maravillas"
        case .forms: return "Transformaciones"
        case .workshop: return "El taller"
        case .fair: return "La feria y el campo"
        }
    }
}

/// What the two of them wear or are that makes a combo theirs.
enum NotchMascotSynergyMatch: Equatable {
    /// The two wear these, in either order.
    case pair(NotchMascotAccessory, NotchMascotAccessory)
    /// Both wear this one.
    case twin(NotchMascotAccessory)
    /// Either wears it.
    case wears(NotchMascotAccessory)
    /// Their figures are these, in either order.
    case styles(NotchMascotStyle, NotchMascotStyle)
    /// A figure of this style wears this.
    case styleWears(NotchMascotStyle, NotchMascotAccessory)
    /// Either is this figure.
    case style(NotchMascotStyle)
    /// One is transformed, whatever its form, and the other wears this:
    /// a thing bought for one companion meets the power of another.
    case formWears(NotchMascotAccessory)
    /// Both are transformed.
    case bothFormed
    /// Played on demand: from the Pocket Card, a click or a door.
    case quest

    /// A pair of things worn beats one worn, which beats one figure alone.
    var specificity: Int {
        switch self {
        case .pair, .twin, .styleWears, .formWears: return 3
        case .styles, .bothFormed: return 2
        case .wears, .style: return 1
        case .quest: return 0
        }
    }

    func matches(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                 leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                 leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil) -> Bool {
        switch self {
        case .formWears(let a):
            return (leaderForm != nil && friendWears == a) || (friendForm != nil && leaderWears == a)
        case .bothFormed:
            return leaderForm != nil && friendForm != nil
        case .pair(let a, let b):
            return (leaderWears == a && friendWears == b) || (leaderWears == b && friendWears == a)
        case .twin(let a): return leaderWears == a && friendWears == a
        case .wears(let a): return leaderWears == a || friendWears == a
        case .styles(let s, let t):
            return (leaderStyle == s && friendStyle == t) || (leaderStyle == t && friendStyle == s)
        case .styleWears(let s, let a):
            return (leaderStyle == s && leaderWears == a) || (friendStyle == s && friendWears == a)
        case .style(let s): return leaderStyle == s || friendStyle == s
        case .quest: return false
        }
    }

    /// Whether the companion starts it: the one wearing or being the first
    /// thing named does, the transformed one where a form meets a thing,
    /// and with nothing to tell them apart, `fallback`.
    func starterIsLeader(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                         leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                         leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil, fallback: Bool) -> Bool {
        switch self {
        case .formWears(let a):
            if leaderForm != nil, friendWears == a { return true }
            if friendForm != nil, leaderWears == a { return false }
            return fallback
        case .bothFormed:
            return fallback
        case .pair(let a, let b):
            if a == b { return fallback }
            if leaderWears == a && friendWears == b { return true }
            if friendWears == a && leaderWears == b { return false }
            return fallback
        case .wears(let a):
            if leaderWears == a && friendWears != a { return true }
            if friendWears == a && leaderWears != a { return false }
            return fallback
        case .styles(let s, let t):
            if s == t { return fallback }
            return leaderStyle == s && friendStyle == t ? true : (friendStyle == s && leaderStyle == t ? false : fallback)
        case .styleWears(let s, let a):
            if leaderStyle == s && leaderWears == a && !(friendStyle == s && friendWears == a) { return true }
            if friendStyle == s && friendWears == a && !(leaderStyle == s && leaderWears == a) { return false }
            return fallback
        case .style(let s):
            if leaderStyle == s && friendStyle != s { return true }
            if friendStyle == s && leaderStyle != s { return false }
            return fallback
        case .twin, .quest: return fallback
        }
    }
}

/// How a combo plays out between the two. Seven shapes, each with its own
/// props, reactions, bursts and arcade markers per combo.
enum NotchMascotSynergyScript: Equatable {
    typealias Thing = NotchMascotIslandPlay.Thing
    typealias Burst = NotchMascotIslandPlay.Burst

    /// The starter readies, sends `thing`, and the other takes it.
    case give(Thing, NotchMascotReaction, Burst?, String?)
    /// `thing` goes to and fro `rounds` times; the last one is missed.
    case volley(Thing, Int, Burst?, String?)
    /// Both ready and let go `thing`, one after the other; the starter wins.
    case duel(Thing, Burst, String?)
    /// Both act, then a burst over each.
    case ritual(NotchMascotReaction, NotchMascotReaction, Burst, String?)
    /// Notes or stars both ways, then both groove.
    case chorus(Thing, NotchMascotReaction, String?)
    /// A slow moment: one, the other, then both.
    case calm(NotchMascotReaction, NotchMascotReaction, Burst, String?)
    /// A secret door opens.
    case door(WonderBoySecretDoor)

    func write(into score: inout NotchMascotIslandPlay.Score) {
        let lands = NotchMascotIslandPlay.flightLength
        switch self {
        case .give(let thing, let catches, let burst, let marker):
            score.act(0, starter: .ready)
            score.toss(0.4, thing, fromStarter: true)
            let at = 0.4 + lands
            score.act(at, other: catches)
            if let burst { score.burst(at, burst, onStarter: false) }
            if let marker { score.marker(at + 0.2, marker, onStarter: false) }
            score.act(at + 1.1, starter: .celebrate)

        case .volley(let thing, let rounds, let burst, let marker):
            score.act(0, starter: .ready)
            for round in 0..<max(1, rounds) {
                let fromStarter = round % 2 == 0
                let start = 0.3 + Double(round) * 1.05
                let last = round == max(1, rounds) - 1
                score.toss(start, thing, fromStarter: fromStarter, falls: last)
                let at = start + lands
                if last {
                    score.act(at, starter: fromStarter ? .celebrate : .surprised,
                              other: fromStarter ? .surprised : .celebrate)
                    if let burst { score.burst(at, burst, onStarter: !fromStarter) }
                    if let marker { score.marker(at + 0.2, marker, onStarter: fromStarter) }
                } else {
                    score.act(at - 0.1, starter: fromStarter ? nil : .perk, other: fromStarter ? .perk : nil)
                }
            }

        case .duel(let thing, let burst, let marker):
            score.act(0, starter: .ready, other: .ready)
            score.act(0.8, starter: .flash, other: .flash)
            score.toss(0.9, thing, fromStarter: true)
            score.toss(0.9 + lands + 0.05, thing, fromStarter: false)
            let at = 0.9 + 2 * lands + 0.1
            score.act(at, starter: .celebrate, other: .surprised)
            score.burst(at, burst, onStarter: false)
            if let marker { score.marker(at + 0.2, marker, onStarter: true) }

        case .ritual(let first, let second, let burst, let marker):
            score.act(0, starter: first)
            score.act(0.9, other: second)
            score.act(1.8, starter: first, other: second)
            score.burst(1.8, burst, onStarter: true)
            score.burst(2.0, burst, onStarter: false)
            if let marker { score.marker(2.1, marker, onStarter: true) }

        case .chorus(let thing, let reaction, let marker):
            score.act(0, starter: .groove)
            score.toss(0.4, thing, fromStarter: true)
            score.act(0.4 + lands, other: reaction)
            score.toss(1.5, thing, fromStarter: false)
            score.act(1.5 + lands, starter: reaction, other: .groove)
            if let marker { score.marker(1.5 + lands, marker, onStarter: true) }

        case .calm(let first, let second, let burst, let marker):
            score.act(0, starter: first)
            score.act(1.3, other: second)
            score.act(2.6, starter: .relax, other: .relax)
            score.burst(2.6, burst, onStarter: true)
            score.burst(2.8, burst, onStarter: false)
            if let marker { score.marker(2.8, marker, onStarter: false) }

        case .door(let door):
            NotchMascotIslandPlay.writeDoor(door, into: &score)
        }
    }
}

/// One combo of the catalog: a name, a family, what makes it theirs and how
/// it plays. Played in the closed island and out on the desktop alike.
struct NotchMascotSynergy: Identifiable, Equatable {
    /// Its place in the catalog, 1...340.
    let number: Int
    let id: String
    let category: SynergyCategory
    let name: String
    let nameES: String
    let description: String
    let descriptionES: String
    let match: NotchMascotSynergyMatch
    let script: NotchMascotSynergyScript

    func matches(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                 leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                 leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil) -> Bool {
        match.matches(leaderWears: leaderWears, friendWears: friendWears,
                      leaderStyle: leaderStyle, friendStyle: friendStyle, leaderForm: leaderForm, friendForm: friendForm)
    }

    func starterIsLeader(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                         leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                         leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil, fallback: Bool) -> Bool {
        match.starterIsLeader(leaderWears: leaderWears, friendWears: friendWears,
                              leaderStyle: leaderStyle, friendStyle: friendStyle,
                              leaderForm: leaderForm, friendForm: friendForm, fallback: fallback)
    }

    /// The play it makes, started by the companion or by its friend.
    func play(starterIsLeader: Bool) -> NotchMascotIslandPlay {
        var score = NotchMascotIslandPlay.Score(byLeader: starterIsLeader)
        NotchMascotComboChoreography.write(id: id, script: script, match: match, into: &score)
        return NotchMascotIslandPlay(kind: .synergy(id), beats: score.beats)
    }

    /// Its name in `language`: Spanish where the app is, English elsewhere.
    func title(in language: AppLanguage) -> String { language == .es ? nameES : name }

    func detail(in language: AppLanguage) -> String { language == .es ? descriptionES : description }
}

/// The combos, and how a pair finds theirs.
enum NotchMascotSynergyCatalog {
    private static func S(_ number: Int, _ id: String, _ category: SynergyCategory, _ name: String, _ nameES: String,
                          _ description: String, _ descriptionES: String, _ match: NotchMascotSynergyMatch,
                          _ script: NotchMascotSynergyScript) -> NotchMascotSynergy {
        NotchMascotSynergy(number: number, id: id, category: category, name: name, nameES: nameES,
                           description: description, descriptionES: descriptionES, match: match, script: script)
    }

    static let all: [NotchMascotSynergy] = wonderBoy + combat + magic + tavern + music + rogues + sciFi + twin
        + species + quests + curiosities + mascots + dance + toys + legends + signals + party + oddities + fairground

    static var total: Int { all.count }

    private static let byID: [String: NotchMascotSynergy] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func synergy(id: String) -> NotchMascotSynergy? { byID[id] }

    static func synergies(in category: SynergyCategory) -> [NotchMascotSynergy] {
        all.filter { $0.category == category }
    }

    /// The combos this pair can play: when some are made of a pair of things
    /// worn, only those, otherwise all that fit. Never the quests.
    static func candidates(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                           leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                           leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil) -> [NotchMascotSynergy] {
        let fits = all.filter {
            $0.matches(leaderWears: leaderWears, friendWears: friendWears,
                       leaderStyle: leaderStyle, friendStyle: friendStyle, leaderForm: leaderForm, friendForm: friendForm)
        }
        guard let best = fits.map({ $0.match.specificity }).max() else { return [] }
        return best >= 3 ? fits.filter { $0.match.specificity >= 3 } : fits
    }

    /// What the friend can wear to make a combo with `item`, each thing once,
    /// with the combo it makes; the same thing for a twin combo.
    static func partners(of item: NotchMascotAccessory) -> [(item: NotchMascotAccessory, synergy: NotchMascotSynergy)] {
        var seen = Set<NotchMascotAccessory>()
        return all.compactMap { synergy -> (item: NotchMascotAccessory, synergy: NotchMascotSynergy)? in
            let partner: NotchMascotAccessory
            switch synergy.match {
            case .pair(let a, let b) where a == item: partner = b
            case .pair(let a, let b) where b == item: partner = a
            case .twin(let a) where a == item: partner = a
            // A transformed friend partners it with nothing of its own.
            case .formWears(let a) where a == item: partner = .none
            default: return nil
            }
            guard seen.insert(partner).inserted else { return nil }
            return (partner, synergy)
        }
    }
    /// The combo that best fits this pair, if any.
    static func resolveSynergy(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                               leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle,
                               leaderForm: NotchMascotForm? = nil, friendForm: NotchMascotForm? = nil) -> NotchMascotSynergy? {
        candidates(leaderWears: leaderWears, friendWears: friendWears,
                   leaderStyle: leaderStyle, friendStyle: friendStyle, leaderForm: leaderForm, friendForm: friendForm).first
    }

    /// A combo not found yet, for the tavern to hint at: one that plays by
    /// itself before the quests.
    static func hint(excluding found: Set<String>) -> NotchMascotSynergy? {
        let open = all.filter { !found.contains($0.id) }
        return open.first { $0.match != .quest } ?? open.first
    }

    // MARK: The catalog

    private static let wonderBoy: [NotchMascotSynergy] = [
        S(1, "pepelogooCarry", .wonderBoy, "Pepelogoo Carry & Glide", "Pepelogoo: llevar y planear",
          "Asha rides her blue pet and they glide off together.",
          "Asha monta a su mascota azul y planean juntos.",
          .styles(.cristobal, .slime), .give(.heart, .love, .hearts, "1UP")),
        S(2, "springboardJump", .wonderBoy, "Trampoline Jump", "Salto trampolín",
          "One springs off the other for a double jump.",
          "Uno rebota en el otro para un doble salto.",
          .styles(.whiteRabbit, .slime), .ritual(.bounce, .bounce, .confetti, "+200")),
        S(3, "swordShieldDuo", .wonderBoy, "Sword & Shield Duo", "Dúo espada y escudo",
          "Blade and shield, shoulder to shoulder.",
          "Espada y escudo, hombro con hombro.",
          .pair(.legendSword, .legendShield), .duel(.sword, .sparkles, "+100")),
        S(4, "boomerangReturn", .wonderBoy, "Boomerang", "Bumerán",
          "It throws and the boomerang always comes back.",
          "Lo lanza y el bumerán siempre vuelve.",
          .wears(.boomerang), .volley(.boomerang, 2, .sparkles, "+100")),
        S(5, "fireEater", .wonderBoy, "Fire Eater", "Come-fuego",
          "One breathes fire, the other swallows it.",
          "Uno lanza fuego y el otro se lo come.",
          .wears(.fireballSpell), .volley(.fireball, 2, .smoke, "+200")),
        S(6, "wingedWhirlwind", .wonderBoy, "Winged Whirlwind", "Torbellino alado",
          "A tornado lifts the winged boots off the ground.",
          "Un tornado levanta las botas aladas.",
          .pair(.tornadoSpell, .wingBoots), .give(.tornado, .bounce, .sparkles, "+200")),
        S(7, "timeRescue", .wonderBoy, "Time Rescue", "Rescate de tiempo",
          "The hourglass runs out and a potion saves the day.",
          "Se acaba el reloj de arena y una poción salva el día.",
          .wears(.hourglass), .give(.potion, .relax, .hearts, "♥ +1")),
        S(8, "bootsShop", .wonderBoy, "Boots Shop", "Tienda de botas",
          "Gold for winged boots, and off they run.",
          "Oro por botas aladas, y a correr.",
          .pair(.wingBoots, .goldBag), .ritual(.perk, .celebrate, .coins, "+200")),
        S(9, "ceilingWalk", .wonderBoy, "Ceiling Walk", "Caminata por techo",
          "The cat walks upside down along the island.",
          "El gato camina boca abajo por la isla.",
          .style(.cat), .ritual(.peek, .surprised, .sparkles, nil)),
        S(10, "liquidDive", .wonderBoy, "Liquid Dive", "Zambullida líquida",
          "The slime dives into the edge of the capsule.",
          "El slime se zambulle en el borde de la cápsula.",
          .style(.slime), .ritual(.ready, .surprised, .sparkles, nil)),
        S(11, "thunderSword", .wonderBoy, "Thunder Sword", "Espada trueno",
          "The blade catches the talisman's lightning.",
          "La hoja atrapa el rayo del talismán.",
          .pair(.legendSword, .thunderTalisman), .duel(.bolt, .sparkles, "+500")),
        S(12, "chestKey", .wonderBoy, "Chest Key", "Llave de cofre",
          "A golden key opens a chest full of coins.",
          "Una llave dorada abre un cofre lleno de monedas.",
          .wears(.goldenKey), .give(.key, .celebrate, .coins, "+500")),
        S(13, "hospitalElixir", .wonderBoy, "Hospital Elixir", "Elixir de hospital",
          "A red potion heals the other one.",
          "Una poción roja cura al otro.",
          .wears(.heartPotion), .give(.potion, .love, .hearts, "♥ +1")),
        S(14, "ocarina", .wonderBoy, "Ocarina", "Ocarina",
          "A melody that opens a door nobody saw.",
          "Una melodía que abre una puerta que nadie veía.",
          .wears(.bardLute), .chorus(.note, .groove, "♪")),
        S(15, "mekaDragonCurse", .wonderBoy, "Meka-Dragon Curse", "Maldición Meka-Dragón",
          "Robot against chip, fire against fire.",
          "Robot contra chip, fuego contra fuego.",
          .styles(.robot, .chip), .duel(.fireball, .smoke, "BOSS")),
    ]

    private static let combat: [NotchMascotSynergy] = [
        S(16, "steelCross", .combat, "Steel Cross", "Cruz de acero",
          "Two blades cross and ring.",
          "Dos hojas se cruzan y suenan.",
          .pair(.legendSword, .katana), .duel(.sword, .sparkles, nil)),
        S(17, "spellblade", .combat, "Spellblade", "Hoja hechizada",
          "The wizard charges the blade with sparks.",
          "El mago carga la hoja de chispas.",
          .pair(.legendSword, .wizardStaff), .give(.spark, .surprised, .magic, "+200")),
        S(18, "katanaVsCowboy", .combat, "Katana vs Cowboy", "Katana contra vaquero",
          "Noon in the West, the blade against the revolver.",
          "Mediodía en el Oeste, la hoja contra el revólver.",
          .pair(.katana, .cowboyHat), .duel(.spark, .sparkles, "DUEL")),
        S(19, "eastWestDuel", .combat, "East-West Duel", "Duelo Este-Oeste",
          "The samurai and the ranger measure each other.",
          "El samurái y el arquero se miden.",
          .pair(.katana, .rangerBow), .duel(.arrow, .sparkles, "DUEL")),
        S(20, "royalOath", .combat, "Royal Oath", "Juramento real",
          "The crown knights the sword.",
          "La corona arma caballero a la espada.",
          .pair(.crown, .legendSword), .ritual(.hush, .hush, .sparkles, "OATH")),
        S(21, "williamTell", .combat, "William Tell", "Flecha de Guillermo Tell",
          "An arrow, a fruit and a very steady hand.",
          "Una flecha, una fruta y pulso firme.",
          .pair(.rangerBow, .beanie), .give(.arrow, .surprised, .sparkles, "+500")),
        S(22, "archerBullseye", .combat, "Archer's Bullseye", "Diana de arquero",
          "Arrow after arrow into the same spot.",
          "Flecha tras flecha al mismo punto.",
          .wears(.rangerBow), .volley(.arrow, 2, .sparkles, "+100")),
        S(23, "berserkerClash", .combat, "Berserker Clash", "Choque berserker",
          "Horns against viking helm, head first.",
          "Cuernos contra casco vikingo, de cabeza.",
          .pair(.vikingHelm, .horns), .duel(.spark, .smoke, "CLASH")),
        S(24, "nordicWall", .combat, "Nordic Wall", "Muro nórdico",
          "Helm and shield, the wall holds.",
          "Casco y escudo, el muro aguanta.",
          .pair(.vikingHelm, .legendShield), .ritual(.ready, .ready, .sparkles, "WALL")),
        S(25, "imperialCut", .combat, "Imperial Cut", "Corte imperial",
          "One clean cut for the crowned.",
          "Un corte limpio para el coronado.",
          .pair(.katana, .crown), .give(.sword, .hush, .sparkles, "+200")),
        S(26, "shieldDome", .combat, "Shield Dome", "Domo de escudos",
          "Two shields make a dome of light.",
          "Dos escudos forman un domo de luz.",
          .twin(.legendShield), .ritual(.ready, .ready, .magic, "DOME")),
        S(27, "knightVigil", .combat, "Knight's Vigil", "Vigilia del caballero",
          "The night watch under a halo.",
          "La guardia nocturna bajo un halo.",
          .pair(.knightHelm, .halo), .ritual(.hush, .love, .sparkles, nil)),
        S(28, "knightSquire", .combat, "Knight & Squire", "Caballero y escudero",
          "The knight hands his sword to the squire.",
          "El caballero entrega su espada al escudero.",
          .pair(.knightHelm, .legendSword), .give(.sword, .celebrate, .sparkles, "+200")),
        S(29, "vikingAxe", .combat, "Viking Axe", "Hacha vikinga",
          "A raid in the island, all sparks and shouts.",
          "Una incursión en la isla, todo chispas y gritos.",
          .wears(.vikingHelm), .volley(.spark, 2, .smoke, "+100")),
        S(30, "sceptreCommand", .combat, "Sceptre Command", "Mandato del cetro",
          "The sceptre points and the helm obeys.",
          "El cetro señala y el casco obedece.",
          .pair(.kingScepter, .knightHelm), .ritual(.ready, .perk, .sparkles, "ORDER")),
        S(31, "royalGuard", .combat, "Royal Guard", "Guardia del rey",
          "The sceptre commands, the shield answers.",
          "El cetro manda, el escudo responde.",
          .pair(.kingScepter, .legendShield), .ritual(.ready, .ready, .sparkles, nil)),
        S(32, "joustTournament", .combat, "Joust", "Torneo de justas",
          "Knight against viking, lance and axe.",
          "Caballero contra vikingo, lanza y hacha.",
          .pair(.knightHelm, .vikingHelm), .duel(.sword, .confetti, "JOUST")),
        S(33, "bowAndBlade", .combat, "Bow & Blade", "Arco y hoja",
          "Arrows cover the one who charges.",
          "Las flechas cubren al que carga.",
          .pair(.rangerBow, .legendSword), .volley(.arrow, 2, .sparkles, "+200")),
        S(34, "lightningParry", .combat, "Lightning Parry", "Parada relámpago",
          "The shield returns the bolt.",
          "El escudo devuelve el rayo.",
          .pair(.thunderTalisman, .legendShield), .duel(.bolt, .sparkles, "PARRY")),
        S(35, "sparring", .combat, "Sparring", "Entrenamiento",
          "Weights and blade, strength and edge.",
          "Pesas y hoja, fuerza y filo.",
          .pair(.dumbbells, .katana), .volley(.spark, 3, .sparkles, "+100")),
    ]

    private static let magic: [NotchMascotSynergy] = [
        S(36, "monsterCauldron", .magic, "Monster World Cauldron", "Caldero Monster World",
          "A witch's brew with a bowl of noodles.",
          "Un brebaje de bruja con un cuenco de fideos.",
          .pair(.witchHat, .ramenBowl), .ritual(.ready, .surprised, .smoke, "BREW")),
        S(37, "arcaneCircle", .magic, "Arcane Circle", "Círculo arcano",
          "Staff and orb draw a circle of light.",
          "Báculo y orbe dibujan un círculo de luz.",
          .pair(.wizardStaff, .crystalOrb), .ritual(.ready, .ready, .magic, "MAGIC")),
        S(38, "notchOracle", .magic, "Oracle of the Notch", "Oráculo del Notch",
          "The orb sees what the monocle reads.",
          "El orbe ve lo que el monóculo lee.",
          .pair(.crystalOrb, .monocle), .ritual(.peek, .surprised, .magic, nil)),
        S(39, "yinYangEclipse", .magic, "Yin-Yang Eclipse", "Eclipse Yin-Yang",
          "Halo and horns, light and shadow.",
          "Halo y cuernos, luz y sombra.",
          .pair(.halo, .horns), .ritual(.love, .surprised, .magic, "ECLIPSE")),
        S(40, "airDuel", .magic, "Air Duel", "Duelo aéreo",
          "Wind against fire above the island.",
          "Viento contra fuego sobre la isla.",
          .pair(.tornadoSpell, .fireballSpell), .duel(.tornado, .smoke, "AIR")),
        S(41, "seraphBlessing", .magic, "Seraph's Blessing", "Bendición serafín",
          "Wings and halo bless the other one.",
          "Alas y halo bendicen al otro.",
          .pair(.angelWings, .halo), .ritual(.love, .relax, .sparkles, "♥ +1")),
        S(42, "supremeAlchemy", .magic, "Supreme Alchemy", "Alquimia suprema",
          "A tome and a potion make something new.",
          "Un tomo y una poción hacen algo nuevo.",
          .pair(.magicTome, .heartPotion), .give(.potion, .celebrate, .magic, "+500")),
        S(43, "scholars", .magic, "Scholars", "Eruditos",
          "Book and glasses, a bright idea.",
          "Libro y gafas, una gran idea.",
          .pair(.magicTome, .glasses), .ritual(.peek, .surprised, .sparkles, "IDEA")),
        S(44, "fireworks", .magic, "Fireworks", "Fuegos artificiales",
          "A fireball under a party hat.",
          "Una bola de fuego bajo un gorro de fiesta.",
          .pair(.fireballSpell, .partyHat), .ritual(.celebrate, .celebrate, .confetti, "BOOM")),
        S(45, "wizardDuel", .magic, "Wizards' Duel", "Duelo de magos",
          "Staff against witch, spark against spark.",
          "Báculo contra bruja, chispa contra chispa.",
          .pair(.wizardStaff, .witchHat), .duel(.spark, .magic, "DUEL")),
        S(46, "tomeLore", .magic, "Tome of Lore", "Saber del tomo",
          "The tome reads itself and a star falls out.",
          "El tomo se lee solo y cae una estrella.",
          .wears(.magicTome), .give(.star, .surprised, .magic, "+200")),
        S(47, "orbVision", .magic, "Orb Vision", "Visión del orbe",
          "The orb shows something far away.",
          "El orbe muestra algo lejano.",
          .wears(.crystalOrb), .ritual(.peek, .lookAround, .magic, nil)),
        S(48, "staffSparks", .magic, "Staff Sparks", "Chispas del báculo",
          "The staff throws sparks to the other.",
          "El báculo lanza chispas al otro.",
          .wears(.wizardStaff), .give(.spark, .surprised, .sparkles, "+100")),
        S(49, "stormCaller", .magic, "Storm Caller", "Invocador de tormentas",
          "Wind and lightning, the island shakes.",
          "Viento y rayo, la isla tiembla.",
          .pair(.tornadoSpell, .thunderTalisman), .duel(.bolt, .smoke, "STORM")),
        S(50, "talismanLuck", .magic, "Talisman Luck", "Suerte del talismán",
          "A bolt of luck for the other.",
          "Un rayo de suerte para el otro.",
          .wears(.thunderTalisman), .give(.bolt, .perk, .sparkles, "+100")),
    ]

    private static let tavern: [NotchMascotSynergy] = [
        S(51, "ramenMaster", .tavern, "Ramen Master", "Maestro del ramen",
          "The chef serves a bowl, and love comes with it.",
          "El chef sirve un cuenco, y el cariño va incluido.",
          .pair(.chefHat, .ramenBowl), .give(.snack(.ramen), .love, .hearts, "+500")),
        S(52, "onigiriJuggling", .tavern, "Onigiri Juggling", "Malabares onigiri",
          "Rice balls in the air, none falls.",
          "Bolas de arroz en el aire, ninguna cae.",
          .pair(.chefHat, .onigiri), .volley(.snack(.onigiri), 3, .confetti, "+500")),
        S(53, "iceCreamParlor", .tavern, "Monster Land Ice Cream", "Heladería Monster Land",
          "A cone for the chef's friend.",
          "Un cucurucho para el amigo del chef.",
          .pair(.iceCreamCone, .chefHat), .give(.snack(.iceCream), .love, .hearts, "+200")),
        S(54, "royalBanquet", .tavern, "Royal Banquet", "Banquete real",
          "Ramen at the king's table.",
          "Ramen en la mesa del rey.",
          .pair(.crown, .ramenBowl), .ritual(.love, .love, .sparkles, "FEAST")),
        S(55, "bobaToast", .tavern, "Boba Toast", "Brindis boba",
          "Two cups touch: cheers.",
          "Dos vasos chocan: salud.",
          .twin(.bobaTea), .ritual(.sip, .sip, .sparkles, "CHEERS")),
        S(56, "ninjaSushi", .tavern, "Ninja Sushi", "Sushi ninja",
          "A rice ball thrown like a star.",
          "Una bola de arroz lanzada como estrella.",
          .pair(.onigiri, .katana), .give(.snack(.onigiri), .surprised, .sparkles, "+500")),
        S(57, "innNight", .tavern, "Night at the Inn", "Noche en la posada",
          "Mask and scarf, a long night's rest.",
          "Antifaz y bufanda, una noche de descanso.",
          .pair(.sleepMask, .scarf), .calm(.yawn, .yawn, .hearts, "ZZZ")),
        S(58, "littlePrince", .tavern, "The Little Prince", "El pequeño príncipe",
          "A scarf, a crown and a flower for someone.",
          "Una bufanda, una corona y una flor para alguien.",
          .pair(.scarf, .crown), .give(.flower, .love, .hearts, nil)),
        S(59, "siesta", .tavern, "Siesta", "Hora de siesta",
          "The mask comes down and the yawn goes round.",
          "Baja el antifaz y el bostezo da la vuelta.",
          .wears(.sleepMask), .calm(.yawn, .hush, .hearts, "ZZZ")),
        S(60, "dragonFlambe", .tavern, "Dragon Flambé", "Flambé dragón",
          "The chef lights the dish with a fireball.",
          "El chef flamea el plato con una bola de fuego.",
          .pair(.chefHat, .fireballSpell), .give(.fireball, .surprised, .smoke, "FLAMBE")),
        S(61, "bobaTavern", .tavern, "Boba Tavern", "Taberna de boba",
          "A cup of pearls for the other one.",
          "Un vaso de perlas para el otro.",
          .wears(.bobaTea), .give(.snack(.bobaTea), .love, .hearts, "♥ +1")),
        S(62, "nursery", .tavern, "Nursery", "Guardería",
          "Pacifier and boba, a soft moment.",
          "Chupete y boba, un momento tierno.",
          .pair(.pacifier, .bobaTea), .calm(.love, .relax, .hearts, nil)),
        S(63, "lullaby", .tavern, "Lullaby", "Nana",
          "The lute sings the baby to sleep.",
          "El laúd duerme al bebé.",
          .pair(.pacifier, .bardLute), .calm(.groove, .yawn, .hearts, "ZZZ")),
        S(64, "coneDelivery", .tavern, "Cone Delivery", "Reparto de helados",
          "A cone goes from hand to hand.",
          "Un cucurucho pasa de mano en mano.",
          .wears(.iceCreamCone), .give(.snack(.iceCream), .celebrate, .sparkles, "+200")),
        S(65, "ramenDuo", .tavern, "Ramen for Two", "Ramen a dúo",
          "Two bowls, two slurps.",
          "Dos cuencos, dos sorbos.",
          .twin(.ramenBowl), .ritual(.sip, .sip, .hearts, "SLURP")),
    ]

    private static let music: [NotchMascotSynergy] = [
        S(66, "chiptuneVsSynth", .music, "Chiptune vs Synthwave", "Chiptune 8-bit contra Synthwave",
          "Controller against headphones, a battle of beats.",
          "Mando contra auriculares, batalla de ritmos.",
          .pair(.gameController, .headphones), .chorus(.note, .groove, "8BIT")),
        S(67, "galaWaltz", .music, "Gala Waltz", "Vals de gala",
          "Top hat and bow tie, one-two-three.",
          "Chistera y pajarita, uno-dos-tres.",
          .pair(.topHat, .bowTie), .ritual(.groove, .groove, .sparkles, "WALTZ")),
        S(68, "tapDance", .music, "Tap Dance", "Claqué",
          "Winged boots on a stage of light.",
          "Botas aladas en un escenario de luz.",
          .pair(.topHat, .wingBoots), .ritual(.bounce, .bounce, .confetti, "TAP")),
        S(69, "neonFestival", .music, "Neon Festival", "Festival neón",
          "Visors and shades under the lights.",
          "Visores y gafas bajo las luces.",
          .pair(.sunglasses, .laserVisor), .chorus(.star, .groove, "NEON")),
        S(70, "monsterWorldBallad", .music, "Monster World Ballad", "Balada Monster World",
          "The bard sings to the crown.",
          "El bardo le canta a la corona.",
          .pair(.bardLute, .crown), .chorus(.note, .love, nil)),
        S(71, "arcadePinata", .music, "Arcade Piñata", "Piñata arcade",
          "The party hat swings and coins fall.",
          "El gorro de fiesta golpea y caen monedas.",
          .pair(.gameController, .partyHat), .ritual(.celebrate, .celebrate, .coins, "+500")),
        S(72, "serenade", .music, "Serenade", "Serenata",
          "A song and a flower under the window.",
          "Una canción y una flor bajo la ventana.",
          .pair(.bardLute, .flower), .give(.heart, .love, .hearts, nil)),
        S(73, "breakdance", .music, "Breakdance", "Breakdance",
          "Cap and headphones, spins on the floor.",
          "Gorra y auriculares, giros en el suelo.",
          .pair(.cap, .headphones), .ritual(.groove, .bounce, .sparkles, "BBOY")),
        S(74, "winterConcert", .music, "Winter Concert", "Concierto de invierno",
          "A lute by the fire, hats on.",
          "Un laúd junto al fuego, con gorro.",
          .pair(.beanie, .bardLute), .chorus(.note, .groove, nil)),
        S(75, "headphoneDuet", .music, "Headphone Duet", "Dúo de auriculares",
          "The same beat in two heads.",
          "El mismo ritmo en dos cabezas.",
          .twin(.headphones), .chorus(.note, .groove, nil)),
        S(76, "luteSolo", .music, "Lute Solo", "Solo de laúd",
          "The bard plays and the other listens.",
          "El bardo toca y el otro escucha.",
          .wears(.bardLute), .chorus(.note, .groove, "SOLO")),
        S(77, "coOpMode", .music, "Co-op Mode", "Modo cooperativo",
          "Two controllers, one goal.",
          "Dos mandos, un objetivo.",
          .twin(.gameController), .ritual(.ready, .ready, .sparkles, "2P")),
    ]

    private static let rogues: [NotchMascotSynergy] = [
        S(78, "captainsTreasure", .rogues, "Captain's Treasure", "Tesoro del capitán",
          "The eye patch guards a bag of gold.",
          "El parche guarda una bolsa de oro.",
          .pair(.eyePatch, .goldBag), .give(.bag, .celebrate, .coins, "+500")),
        S(79, "crownHeist", .rogues, "Crown Heist", "Robo de corona",
          "A pirate eyes the crown.",
          "Un pirata echa el ojo a la corona.",
          .pair(.eyePatch, .crown), .ritual(.peek, .surprised, .sparkles, "HEIST")),
        S(80, "hiddenDoorDetectives", .rogues, "Hidden Door Detectives", "Detectives de puertas ocultas",
          "Two lenses find the secret door.",
          "Dos lentes encuentran la puerta secreta.",
          .pair(.detectiveLens, .monocle), .ritual(.peek, .peek, .door, nil)),
        S(81, "coinTrail", .rogues, "Coin Trail", "Rastro de monedas",
          "A hole in the bag leaves a trail.",
          "Un agujero en la bolsa deja un rastro.",
          .wears(.goldBag), .volley(.coin, 2, .coins, "+100")),
        S(82, "adventurersPulse", .rogues, "Adventurers' Pulse", "Pulso de aventureros",
          "Helm and lens set off together.",
          "Casco y lupa parten juntos.",
          .pair(.knightHelm, .detectiveLens), .ritual(.ready, .perk, .sparkles, nil)),
        S(83, "sphinxRiddle", .rogues, "Sphinx Riddle", "Acertijo de la esfinge",
          "The lens and the orb ask a question.",
          "La lupa y el orbe hacen una pregunta.",
          .pair(.detectiveLens, .crystalOrb), .ritual(.confused, .peek, .magic, nil)),
        S(84, "fireflyHunt", .rogues, "Firefly Hunt", "Caza de luciérnagas",
          "Ghost and cat chase little lights.",
          "Fantasma y gato persiguen lucecitas.",
          .styles(.ghost, .cat), .volley(.spark, 3, .sparkles, nil)),
        S(85, "pickpocket", .rogues, "Pickpocket", "Carterista",
          "A coin changes pockets.",
          "Una moneda cambia de bolsillo.",
          .pair(.eyePatch, .detectiveLens), .give(.coin, .surprised, .coins, "+1")),
        S(86, "keyHunt", .rogues, "Key Hunt", "Búsqueda de la llave",
          "The lens finds what the key opens.",
          "La lupa halla lo que abre la llave.",
          .pair(.goldenKey, .detectiveLens), .give(.key, .celebrate, .sparkles, "+500")),
        S(87, "forestBandit", .rogues, "Forest Bandit", "Bandido del bosque",
          "Arrows for the purse.",
          "Flechas por la bolsa.",
          .pair(.rangerBow, .eyePatch), .volley(.arrow, 2, .coins, "+200")),
        S(88, "mapReading", .rogues, "Map Reading", "Lectura del mapa",
          "The lens reads a map that is not there.",
          "La lupa lee un mapa que no está.",
          .wears(.detectiveLens), .ritual(.peek, .lookAround, .sparkles, nil)),
        S(89, "smugglers", .rogues, "Smugglers", "Contrabandistas",
          "The key and the bag change hands.",
          "La llave y la bolsa cambian de manos.",
          .pair(.goldBag, .goldenKey), .give(.bag, .celebrate, .coins, "+500")),
    ]

    private static let sciFi: [NotchMascotSynergy] = [
        S(90, "scanner9000", .sciFi, "Scanner over 9000 MHz", "Escáner de más de 9000 MHz",
          "The visor reads a number too big for the screen.",
          "El visor lee un número demasiado grande.",
          .pair(.laserVisor, .detectiveLens), .ritual(.surprised, .surprised, .sparkles, "9000")),
        S(91, "masterSystemCoop", .sciFi, "Master System Co-op", "Cooperativo Master System",
          "Controller and visor, two players at once.",
          "Mando y visor, dos jugadores a la vez.",
          .pair(.gameController, .laserVisor), .ritual(.ready, .ready, .confetti, "SMS")),
        S(92, "speedrun", .sciFi, "Monster Land Speedrun", "Speedrun Monster Land",
          "Controller and boots, the clock does not stop.",
          "Mando y botas, el reloj no para.",
          .pair(.gameController, .wingBoots), .volley(.spark, 3, .sparkles, "RUN")),
        S(93, "jetpackVsBoots", .sciFi, "Jetpack vs Boots", "Carrera jetpack contra botas",
          "Fuel against feathers, a race over the island.",
          "Combustible contra plumas, carrera sobre la isla.",
          .pair(.jetpack, .wingBoots), .duel(.tornado, .smoke, "RACE")),
        S(94, "jetpackLoop", .sciFi, "Jetpack Loop", "Looping jetpack",
          "A loop in the air and a bow.",
          "Un looping en el aire y una reverencia.",
          .wears(.jetpack), .ritual(.bounce, .surprised, .smoke, "LOOP")),
        S(95, "cpuTuning", .sciFi, "CPU Tuning", "Tuning de CPU",
          "The chip is pushed a little further.",
          "El chip se lleva un poco más allá.",
          .styleWears(.chip, .laserVisor), .ritual(.sweat, .ready, .sparkles, "TUNE")),
        S(96, "turboBoost", .sciFi, "Turbo Boost", "Turbo Boost",
          "The fan spins up with a jetpack on.",
          "El ventilador acelera con jetpack.",
          .styleWears(.fan, .jetpack), .ritual(.panic, .bounce, .smoke, "TURBO")),
        S(97, "overclock", .sciFi, "Overclock", "Overclock",
          "Chip and fan push the limit together.",
          "Chip y ventilador llevan el límite juntos.",
          .styles(.chip, .fan), .ritual(.sweat, .sweat, .smoke, "OC")),
        S(98, "robotUplink", .sciFi, "Robot Uplink", "Enlace robot",
          "A spark runs along the link.",
          "Una chispa recorre el enlace.",
          .styles(.robot, .chip), .chorus(.spark, .ready, "LINK")),
        S(99, "laserTag", .sciFi, "Laser Tag", "Láser tag",
          "Visors on, bolts across the island.",
          "Visores puestos, rayos por la isla.",
          .twin(.laserVisor), .duel(.bolt, .sparkles, "TAG")),
        S(100, "cooling", .sciFi, "Cooling", "Refrigeración",
          "The fan cools the ghost down.",
          "El ventilador enfría al fantasma.",
          .styles(.fan, .ghost), .calm(.relax, .relax, .sparkles, "COOL")),
        S(101, "benchmark", .sciFi, "Benchmark", "Benchmark",
          "Weights and controller, who scores more.",
          "Pesas y mando, quién puntúa más.",
          .pair(.dumbbells, .gameController), .ritual(.sweat, .celebrate, .confetti, "SCORE")),
    ]

    private static let twin: [NotchMascotSynergy] = [
        S(102, "doubleCrown", .twin, "Double Crown", "Doble corona",
          "Two crowns bow to each other.",
          "Dos coronas se saludan.",
          .twin(.crown), .ritual(.hush, .hush, .sparkles, "DUO")),
        S(103, "doubleWitch", .twin, "Coven", "Aquelarre",
          "Two witch hats stir the same pot.",
          "Dos sombreros de bruja, el mismo caldero.",
          .twin(.witchHat), .ritual(.ready, .ready, .magic, "COVEN")),
        S(104, "giftFactory", .twin, "Gift Factory", "Fábrica de regalos",
          "Two Santa hats toss presents back and forth.",
          "Dos gorros de Santa se pasan regalos.",
          .twin(.santaHat), .volley(.star, 3, .confetti, "+200")),
        S(105, "doubleChef", .twin, "Cook-off", "Duelo culinario",
          "Two chefs, one apple, one winner.",
          "Dos chefs, una manzana, un ganador.",
          .twin(.chefHat), .duel(.snack(.apple), .smoke, "COOK")),
        S(106, "doubleCowboy", .twin, "Double Draw", "Doble duelo vaquero",
          "Two hats at noon, who draws first.",
          "Dos sombreros a mediodía, quién desenfunda antes.",
          .twin(.cowboyHat), .duel(.spark, .smoke, "DRAW")),
        S(107, "mirrorGlasses", .twin, "Mirror Pose", "Pose en espejo",
          "Two pairs of glasses, one anime pose.",
          "Dos pares de gafas, una pose de anime.",
          .twin(.glasses), .ritual(.ready, .ready, .sparkles, "POSE")),
        S(108, "doubleBoots", .twin, "Double Race", "Carrera doble",
          "Two winged boots, one finish line.",
          "Dos botas aladas, una meta.",
          .twin(.wingBoots), .duel(.tornado, .smoke, "RACE")),
        S(109, "doubleParty", .twin, "Double Party", "Doble fiesta",
          "Two party hats, twice the confetti.",
          "Dos gorros de fiesta, el doble de confeti.",
          .twin(.partyHat), .ritual(.celebrate, .celebrate, .confetti, "PARTY")),
        S(110, "doubleHalo", .twin, "Double Halo", "Doble halo",
          "Two halos, one quiet blessing.",
          "Dos halos, una bendición tranquila.",
          .twin(.halo), .ritual(.love, .love, .sparkles, "HALO")),
        S(111, "doubleHorns", .twin, "Double Mischief", "Doble travesura",
          "Two pairs of horns, one prank.",
          "Dos pares de cuernos, una travesura.",
          .twin(.horns), .ritual(.peek, .peek, .smoke, "HEHE")),
        S(112, "doubleShades", .twin, "Double Shades", "Doble gafas de sol",
          "Two pairs of shades, too cool.",
          "Dos gafas de sol, demasiado fresco.",
          .twin(.sunglasses), .ritual(.ready, .ready, .sparkles, "COOL")),
        S(113, "snowFight", .twin, "Snow Fight", "Pelea de nieve",
          "Two beanies, a snowball each.",
          "Dos gorros de lana, una bola de nieve cada uno.",
          .twin(.beanie), .duel(.snowball, .sparkles, "SNOW")),
        S(114, "doubleBow", .twin, "Double Bow", "Doble lazo",
          "Two bows, one hug.",
          "Dos lazos, un abrazo.",
          .twin(.bow), .ritual(.love, .love, .hearts, nil)),
        S(115, "doubleScarf", .twin, "Double Scarf", "Doble bufanda",
          "Two scarves, one shared warmth.",
          "Dos bufandas, un calor compartido.",
          .twin(.scarf), .calm(.relax, .relax, .hearts, nil)),
        S(116, "doubleSword", .twin, "Mirror Blades", "Espadas espejo",
          "Two swords, the same swing.",
          "Dos espadas, el mismo golpe.",
          .twin(.legendSword), .duel(.sword, .sparkles, "CLASH")),
        S(117, "doubleCap", .twin, "Catch", "Pelota doble",
          "Two caps, a ball between them.",
          "Dos gorras, una pelota entre ellas.",
          .twin(.cap), .volley(.ball, 3, .sparkles, nil)),
    ]

    private static let species: [NotchMascotSynergy] = [
        S(118, "lionClaw", .species, "Lion-Man Claw", "Tajo felino",
          "The cat's claws flash like a katana.",
          "Las garras del gato brillan como una katana.",
          .styleWears(.cat, .katana), .give(.sword, .surprised, .smoke, "SLASH")),
        S(119, "ghostDoorOpener", .species, "Ghost Door Opener", "Fantasma abre-puertas",
          "The ghost passes through a door that was not there.",
          "El fantasma cruza una puerta que no estaba.",
          .styleWears(.ghost, .goldenKey), .ritual(.hush, .surprised, .door, nil)),
        S(120, "pepelogooHealer", .species, "Giant Healing Pepelogoo", "Pepelogoo gigante curativo",
          "The slime shares a potion that heals.",
          "El slime comparte una poción que cura.",
          .styleWears(.slime, .heartPotion), .give(.potion, .love, .hearts, "♥ +1")),
        S(121, "timeFlies", .species, "Time Flies", "El tiempo vuela",
          "The rabbit is late, as always.",
          "El conejo llega tarde, como siempre.",
          .styleWears(.whiteRabbit, .hourglass), .ritual(.surprised, .perk, .sparkles, "LATE")),
        S(122, "authorTalk", .species, "Author's Talk", "Charla de autor",
          "Two storytellers trade a tale.",
          "Dos narradores se cuentan un cuento.",
          .styles(.cristobal, .whiteRabbit), .chorus(.star, .love, nil)),
        S(123, "robotOverload", .species, "Robot Overload", "Sobrecarga eléctrica",
          "A talisman and a robot: too much current.",
          "Un talismán y un robot: demasiada corriente.",
          .styleWears(.robot, .thunderTalisman), .ritual(.panic, .surprised, .smoke, "ZAP")),
        S(124, "chipHeat", .species, "Chip Heat", "Calor del chip",
          "The chip holds a fireball and sweats.",
          "El chip sostiene una bola de fuego y suda.",
          .styleWears(.chip, .fireballSpell), .ritual(.sweat, .panic, .smoke, "HOT")),
        S(125, "fanWhirl", .species, "Fan Whirl", "Remolino del ventilador",
          "The fan spins a tornado of its own.",
          "El ventilador gira un tornado propio.",
          .styleWears(.fan, .tornadoSpell), .ritual(.groove, .surprised, .sparkles, "WHIRL")),
        S(126, "slimeWobble", .species, "Slime Wobble", "Chapoteo slime",
          "Two slimes jiggle together.",
          "Dos slimes se menean juntos.",
          .styles(.slime, .slime), .ritual(.bounce, .bounce, .sparkles, "BLOB")),
        S(127, "minimalZen", .species, "Minimal Zen", "Zen mínimo",
          "Two minimal friends, nothing needed.",
          "Dos amigos mínimos, nada hace falta.",
          .styles(.minimal, .minimal), .calm(.relax, .relax, .sparkles, "ZEN")),
    ]

    // MARK: Shop curiosities

    private static let curiosities: [NotchMascotSynergy] = [
        S(136, "duckSqueak", .curiosities, "Squeaky Surprise", "Susto con chirrido",
          "The duck squeaks and the other jumps out of its skin.",
          "El pato chirría y el otro salta del susto.",
          .wears(.rubberDuck), .give(.duck, .surprised, .sparkles, "QUACK")),
        S(137, "peelSlip", .curiosities, "Slip and Slide", "Resbalón clásico",
          "A banana peel on the floor, and a very slow fall.",
          "Una cáscara en el suelo y una caída muy lenta.",
          .wears(.bananaPeel), .give(.peel, .confused, .smoke, "WHOA")),
        S(138, "noseHonk", .curiosities, "Honk Honk", "Pip pip",
          "A red nose, a honk and both of them in stitches.",
          "Nariz roja, bocinazo y los dos muertos de risa.",
          .wears(.clownNose), .ritual(.celebrate, .celebrate, .confetti, "HONK")),
        S(139, "pieFight", .curiosities, "Cream Pie Fight", "Guerra de tartas",
          "Two pies in the air and one landing in the face.",
          "Dos tartas en el aire y una en plena cara.",
          .wears(.creamPie), .duel(.pie, .smoke, "SPLAT")),
        S(140, "cushionPfft", .curiosities, "Rude Noise", "Ruido inoportuno",
          "Somebody sits down. Nobody speaks of it again.",
          "Alguien se sienta. Nadie vuelve a hablar de ello.",
          .wears(.whoopeeCushion), .ritual(.surprised, .hush, .smoke, "PFFT")),
        S(141, "mustacheSpy", .curiosities, "Suspicious Mustache", "Bigote sospechoso",
          "That mustache is not real. The other one knows.",
          "Ese bigote no es de verdad. El otro lo sabe.",
          .wears(.fakeMustache), .calm(.lookAround, .confused, .magic, "HMM")),
        S(142, "coneMegaphone", .curiosities, "Cone Megaphone", "Megáfono de cono",
          "A traffic cone turns into a loudspeaker.",
          "Un cono de tráfico se vuelve altavoz.",
          .wears(.trafficCone), .chorus(.note, .surprised, "HEY")),
        S(143, "piggyShake", .curiosities, "Piggy Bank Shake", "Hucha sacudida",
          "Shake it and the gold comes out.",
          "La sacuden y sale el oro.",
          .wears(.piggyBank), .give(.coin, .celebrate, .coins, "+50")),
        S(144, "alarmRing", .curiosities, "Alarm Clock Panic", "Pánico de despertador",
          "It rings and the other wakes up with a start.",
          "Suena y el otro despierta de golpe.",
          .wears(.alarmClock), .ritual(.surprised, .wakeUp, .sparkles, "RING")),
        S(145, "cloudShare", .curiosities, "Rain Cloud, Shared", "Nube compartida",
          "A private storm, and an umbrella for two.",
          "Una tormenta privada y un paraguas para dos.",
          .wears(.stormCloud), .calm(.sweat, .perk, .hearts, "AWW")),
        S(146, "wiltedGift", .curiosities, "Wilted Gift", "Regalo marchito",
          "A flower offered, its petals falling one by one.",
          "Una flor ofrecida y sus pétalos cayendo uno a uno.",
          .wears(.wiltedFlower), .give(.flower, .sweat, .sparkles, nil)),
        S(147, "balloonGoodbye", .curiosities, "Goodbye, Balloon", "Adiós, globo",
          "It slips away. They watch it get small.",
          "Se escapa. Lo ven hacerse pequeño.",
          .wears(.lonelyBalloon), .give(.balloon, .lookAround, .sparkles, nil)),
        S(148, "bearHug", .curiosities, "Bear Hug", "Abrazo de oso",
          "Sometimes a plush is all it takes.",
          "A veces basta con un peluche.",
          .wears(.teddyBear), .calm(.love, .love, .hearts, nil)),
        S(149, "tissueKindness", .curiosities, "A Tissue for You", "Un pañuelo para ti",
          "Handed over without a word.",
          "Entregado sin decir nada.",
          .wears(.tissueBox), .give(.snowball, .relax, .hearts, nil)),
        S(150, "locketMend", .curiosities, "Mending the Locket", "Reparar el relicario",
          "The heart breaks in two; a potion puts it right.",
          "El corazón se parte en dos; una poción lo arregla.",
          .wears(.brokenLocket), .give(.potion, .love, .magic, "♥ +1")),
        S(151, "foilTheory", .curiosities, "Foil Hat Theory", "Teoría del gorro",
          "They know. They have always known.",
          "Lo saben. Siempre lo han sabido.",
          .wears(.tinfoilHat), .ritual(.panic, .confused, .magic, "???")),
        S(152, "mushroomTrip", .curiosities, "Mushroom Moment", "Momento seta",
          "Grow, shrink, and a rainbow for no reason.",
          "Crecer, encoger y un arcoíris sin motivo.",
          .wears(.magicMushroom), .ritual(.surprised, .celebrate, .confetti, "1UP")),
        S(153, "discoFever", .curiosities, "Disco Fever", "Fiebre disco",
          "The ball spins; the stars come down.",
          "La bola gira y bajan las estrellas.",
          .wears(.discoBall), .chorus(.star, .groove, "DISCO")),
        S(154, "ufoAbduct", .curiosities, "Close Encounter", "Encuentro cercano",
          "A beam from nowhere and a very surprised friend.",
          "Un rayo de la nada y un amigo muy sorprendido.",
          .wears(.alienAntenna), .ritual(.surprised, .panic, .magic, "UFO")),
        S(155, "dynamiteBoom", .curiosities, "Short Fuse", "Mecha corta",
          "Lit, thrown, and nobody is sure why.",
          "Encendida, lanzada, y nadie sabe por qué.",
          .wears(.dynamiteStick), .give(.dynamite, .panic, .smoke, "BOOM")),
        S(156, "chestChomp", .curiosities, "The Chest Bites Back", "El cofre muerde",
          "It was not a chest. It spits coins out of spite.",
          "No era un cofre. Escupe monedas por rencor.",
          .wears(.mimicChest), .ritual(.panic, .celebrate, .coins, "CHOMP")),
        S(157, "skullBoo", .curiosities, "Skull Whispers", "Susurros de calavera",
          "Ghost smoke and a scare that goes both ways.",
          "Humo fantasma y un susto de ida y vuelta.",
          .wears(.crystalSkull), .ritual(.hush, .panic, .smoke, "BOO")),
        S(158, "maskPossessed", .curiosities, "Possessed", "Poseído",
          "The mask takes over and the storm follows.",
          "La máscara toma el mando y la tormenta la sigue.",
          .wears(.cursedMask), .duel(.tornado, .smoke, "HEX")),
        S(159, "unicornSparkle", .curiosities, "Unicorn Parade", "Desfile unicornio",
          "A trail of sparks and an unreasonable amount of joy.",
          "Un rastro de chispas y una alegría desmedida.",
          .wears(.unicornHorn), .chorus(.spark, .celebrate, "MAGIC")),
        S(160, "rainAndBear", .curiosities, "Cozy in the Rain", "Acurrucados bajo la lluvia",
          "A storm cloud meets a teddy bear.",
          "Una nube de tormenta se encuentra con un osito.",
          .pair(.stormCloud, .teddyBear), .calm(.sweat, .love, .hearts, "COZY")),
        S(161, "slapstick", .curiosities, "Slapstick", "Slapstick",
          "The peel first, the pie right after.",
          "Primero la cáscara, luego la tarta.",
          .pair(.bananaPeel, .creamPie), .duel(.pie, .confetti, "SLAP")),
        S(162, "conspiracyProved", .curiosities, "Proof at Last", "Por fin, pruebas",
          "The hat and the antenna agree: it was true.",
          "El gorro y la antena coinciden: era verdad.",
          .pair(.tinfoilHat, .alienAntenna), .ritual(.celebrate, .celebrate, .magic, "TRUE")),
        S(163, "runForIt", .curiosities, "Run!", "¡Corre!",
          "Dynamite and a traffic cone. Nothing good follows.",
          "Dinamita y un cono de tráfico. Nada bueno viene.",
          .pair(.dynamiteStick, .trafficCone), .ritual(.panic, .panic, .smoke, "RUN")),
        S(164, "discoTrip", .curiosities, "Disco Trip", "Viaje disco",
          "A mirror ball and a mushroom walk into a bar.",
          "Una bola de espejos y una seta entran en un bar.",
          .pair(.discoBall, .magicMushroom), .chorus(.star, .groove, "TRIP")),
        S(165, "doom", .curiosities, "Doom", "Perdición",
          "A skull and a mask: the room goes cold.",
          "Una calavera y una máscara: la sala se enfría.",
          .pair(.crystalSkull, .cursedMask), .duel(.tornado, .smoke, "DOOM")),
        S(166, "heist", .curiosities, "The Heist", "El golpe",
          "The piggy bank and the mimic trade coins.",
          "La hucha y el mímico se pasan monedas.",
          .pair(.piggyBank, .mimicChest), .volley(.coin, 3, .coins, "HEIST")),
        S(167, "cryingTogether", .curiosities, "A Good Cry", "Un buen llanto",
          "A wilted flower, a tissue and no judgement.",
          "Una flor marchita, un pañuelo y cero juicios.",
          .pair(.wiltedFlower, .tissueBox), .calm(.sweat, .love, .hearts, "SNIF")),
    ]

    // MARK: Glutton and Shifter

    private static let mascots: [NotchMascotSynergy] = [
        S(168, "gluttonSpit", .mascots, "Swallow and Spit", "Tragar y escupir",
          "It inhales what comes its way and spits it back as a star.",
          "Aspira lo que le llega y lo devuelve en forma de estrella.",
          .style(.devourer), .give(.star, .celebrate, .sparkles, "POYO")),
        S(169, "gluttonFire", .mascots, "Fire Copy", "Copia de fuego",
          "It swallows the spell and breathes it out.",
          "Se traga el hechizo y lo exhala.",
          .styleWears(.devourer, .fireballSpell), .give(.fireball, .surprised, .smoke, "FIRE")),
        S(170, "gluttonIce", .mascots, "Ice Copy", "Copia de hielo",
          "A cold cone, a cold breath.",
          "Un cucurucho frío, un aliento frío.",
          .styleWears(.devourer, .iceCreamCone), .give(.snowball, .surprised, .sparkles, "ICE")),
        S(171, "gluttonSpark", .mascots, "Spark Copy", "Copia de rayo",
          "It eats a bolt and gets static hair.",
          "Se come un rayo y le queda el pelo erizado.",
          .styleWears(.devourer, .thunderTalisman), .give(.bolt, .surprised, .sparkles, "SPARK")),
        S(172, "gluttonSword", .mascots, "Sword Copy", "Copia de espada",
          "It swallows the blade and comes out a knight.",
          "Se traga la hoja y sale hecho un caballero.",
          .styleWears(.devourer, .legendSword), .give(.sword, .celebrate, .sparkles, "SLASH")),
        S(173, "gluttonCutter", .mascots, "Cutter Copy", "Copia de bumerán",
          "A boomerang goes in and comes back twice.",
          "Un bumerán entra y vuelve dos veces.",
          .styleWears(.devourer, .boomerang), .volley(.boomerang, 2, .sparkles, "CUTTER")),
        S(174, "gluttonTornado", .mascots, "Tornado Copy", "Copia de tornado",
          "It swallows the storm and spins.",
          "Se traga la tormenta y gira.",
          .styleWears(.devourer, .tornadoSpell), .give(.tornado, .panic, .smoke, "TWIST")),
        S(175, "gluttonFeast", .mascots, "Slurp", "Slurp",
          "It inhales the ramen, bowl and all, nearly.",
          "Aspira el ramen, casi con tazón y todo.",
          .styleWears(.devourer, .ramenBowl), .ritual(.sip, .sip, .hearts, "YUM")),
        S(176, "gluttonBoba", .mascots, "Bubble Gulp", "Trago de burbujas",
          "Every pearl in one breath.",
          "Todas las perlas de un solo soplo.",
          .styleWears(.devourer, .bobaTea), .ritual(.sip, .love, .hearts, "GULP")),
        S(177, "gluttonArcher", .mascots, "Archer Copy", "Copia de arquero",
          "It swallows an arrow and aims with its whole face.",
          "Se traga una flecha y apunta con toda la cara.",
          .styleWears(.devourer, .rangerBow), .give(.arrow, .perk, .sparkles, "SNIPE")),
        S(178, "gluttonMimic", .mascots, "Bad Swallow", "Mal trago",
          "It swallowed a mimic. The mimic is not pleased.",
          "Se tragó un mímico. Al mímico no le hace gracia.",
          .styleWears(.devourer, .mimicChest), .ritual(.surprised, .panic, .coins, "OOPS")),
        S(179, "gluttonDynamite", .mascots, "Hot Mouthful", "Bocado explosivo",
          "Never swallow what is lit.",
          "Nunca te tragues lo que está encendido.",
          .styleWears(.devourer, .dynamiteStick), .give(.dynamite, .panic, .smoke, "BOOM")),
        S(180, "gluttonShifter", .mascots, "Copy and Paste", "Copiar y pegar",
          "One swallows, the other copies; stars everywhere.",
          "Uno traga, el otro copia; estrellas por todas partes.",
          .styles(.devourer, .shifter), .volley(.star, 3, .sparkles, "COPY")),
        S(181, "gluttonSlime", .mascots, "Blob Party", "Fiesta de blobs",
          "Two soft friends bounce about.",
          "Dos blandos amigos rebotando.",
          .styles(.devourer, .slime), .ritual(.bounce, .bounce, .confetti, "BLOB")),
        S(182, "gluttonCat", .mascots, "Snack Time", "Hora del tentempié",
          "The cat shares a cookie, mostly.",
          "El gato comparte una galleta, más o menos.",
          .styles(.devourer, .cat), .give(.cookie, .celebrate, .hearts, "NOM")),
        S(183, "shifterCopy", .mascots, "Copycat", "Imitador",
          "It becomes whoever it is playing with.",
          "Se convierte en con quien juega.",
          .style(.shifter), .ritual(.perk, .surprised, .magic, "COPY")),
        S(184, "shifterCat", .mascots, "Cat Impression", "Imitación de gato",
          "It does a very convincing cat.",
          "Hace un gato muy convincente.",
          .styles(.shifter, .cat), .ritual(.perk, .celebrate, .magic, "MEOW")),
        S(185, "shifterGhost", .mascots, "Ghost Impression", "Imitación de fantasma",
          "Booing in a borrowed sheet.",
          "Asustando con una sábana prestada.",
          .styles(.shifter, .ghost), .ritual(.hush, .panic, .smoke, "BOO")),
        S(186, "shifterRobot", .mascots, "Robot Impression", "Imitación de robot",
          "Beep, boop, and a stiff walk.",
          "Bip, bop y un andar rígido.",
          .styles(.shifter, .robot), .ritual(.perk, .groove, .sparkles, "BEEP")),
        S(187, "shifterFan", .mascots, "Fan Impression", "Imitación de ventilador",
          "It spins, nobody asked it to.",
          "Gira, nadie se lo pidió.",
          .styles(.shifter, .fan), .ritual(.perk, .surprised, .magic, "WHIR")),
        S(188, "shifterChip", .mascots, "Chip Impression", "Imitación de chip",
          "A few pins sprout and it counts to a million.",
          "Le brotan unos pines y cuenta hasta un millón.",
          .styles(.shifter, .chip), .ritual(.perk, .celebrate, .sparkles, "BYTE")),
        S(189, "shifterSlime", .mascots, "Which Blob?", "¿Qué blob es?",
          "Two blobs, nobody knows who is who.",
          "Dos blobs, nadie sabe cuál es cuál.",
          .styles(.shifter, .slime), .ritual(.confused, .confused, .smoke, "WHO")),
        S(190, "shifterMinimal", .mascots, "Perfect Copy", "Copia perfecta",
          "Nobody can tell them apart. Even they cannot.",
          "Nadie los distingue. Ni ellos mismos.",
          .styles(.shifter, .minimal), .ritual(.perk, .love, .hearts, "AWW")),
        // Curiosities meet gear: pairs of shop things with Wonder Boy items.
        S(191, "bubbleBath", .curiosities, "Bubble Bath", "Baño de burbujas",
          "A duck, a boba and a long soak.",
          "Un pato, un bubble tea y un buen remojo.",
          .pair(.rubberDuck, .bobaTea), .calm(.relax, .groove, .sparkles, "SOAK")),
        S(192, "prankDuo", .curiosities, "The Prank Duo", "El dúo bromista",
          "The cushion goes off under the fake mustache.",
          "La almohadilla truena bajo el bigote postizo.",
          .pair(.whoopeeCushion, .fakeMustache), .ritual(.perk, .confused, .smoke, "GAG")),
        S(193, "rudeAwakening", .curiosities, "Rude Awakening", "Despertar maleducado",
          "The alarm rings; the mask stays on anyway.",
          "Suena el despertador; la antifaz sigue puesta.",
          .pair(.alarmClock, .sleepMask), .give(.bolt, .surprised, .sparkles, "AM")),
        S(194, "balloonRide", .curiosities, "Balloon Ride", "Paseo en globo",
          "A horn of wonder and one lonely balloon, finally held.",
          "Un cuerno de fantasía y un globo solitario, al fin sujeto.",
          .pair(.lonelyBalloon, .unicornHorn), .ritual(.bounce, .celebrate, .hearts, "FLY")),
        S(195, "chestGame", .curiosities, "The Chest Game", "El juego del cofre",
          "The key turns, the mimic bites, the coins fly.",
          "La llave gira, el mímico muerde, vuelan las monedas.",
          .pair(.goldenKey, .mimicChest), .duel(.key, .coins, "+500")),
        S(196, "hotAndCold", .curiosities, "Hot & Cold", "Frío y calor",
          "A fireball and a cone of ice cream, thrown with care.",
          "Una bola de fuego y un cucurucho, lanzados con cuidado.",
          .pair(.fireballSpell, .iceCreamCone), .volley(.fireball, 2, .smoke, "STEAM")),
        S(197, "houseParty", .curiosities, "House Party", "Fiesta en casa",
          "The lute plays, the ball spins, everyone dances.",
          "Suena el laúd, gira la bola, todos bailan.",
          .pair(.bardLute, .discoBall), .chorus(.note, .groove, "LIVE")),
        S(198, "firstContact", .curiosities, "First Contact", "Primer contacto",
          "A jetpack lands by the antenna: hello, hello.",
          "Un jet aterriza junto a la antena: hola, hola.",
          .pair(.jetpack, .alienAntenna), .ritual(.surprised, .wave, .magic, "HELLO")),
        // The flame bird and the water salamander, plays of their own.
        S(199, "rebirth", .mascots, "Ash to Ember", "De la ceniza a la ascua",
          "It flares, dims and comes back brighter.",
          "Se enciende, se apaga y vuelve más brillante.",
          .style(.phoenix), .ritual(.flash, .celebrate, .sparkles, "REBORN")),
        S(200, "bubbleLounge", .mascots, "Bubble Lounge", "Salón de burbujas",
          "It floats a while, blowing bubbles at nothing.",
          "Flota un rato, soltando burbujas a la nada.",
          .style(.axolotl), .calm(.relax, .groove, .magic, "BLOOP")),
        S(201, "emberTide", .mascots, "Steam & Spark", "Vapor y chispa",
          "The bird's embers meet the salamander's splash.",
          "Las ascuas del pájaro se encuentran con el chapoteo del ajolote.",
          .styles(.phoenix, .axolotl), .duel(.fireball, .magic, "STEAM")),
        S(202, "fireDrill", .mascots, "Fire Drill", "Simulacro de incendio",
          "One breathes fire; the slime, unbothered, puts it out.",
          "Uno lanza fuego; la geleca, tranquila, lo apaga.",
          .styles(.phoenix, .slime), .volley(.snowball, 2, .smoke, "HISS")),
        // The pets: a dog, a cat and a little mouse, and their classic rows.
        S(203, "fetch", .mascots, "Fetch", "Lanzar la pelota",
          "The ball goes out and always comes back. Good dog.",
          "La pelota sale y siempre vuelve. Buen perro.",
          .style(.dog), .volley(.ball, 2, .sparkles, "FETCH")),
        S(204, "squeakPeek", .mascots, "Squeak Peek", "Asomito",
          "A little mouse looks out, squeaks, and ducks away.",
          "Una ratita asoma, chilla y se esconde.",
          .style(.mouse), .calm(.peek, .lookAround, .smoke, "SQUEAK")),
        S(205, "catAndDog", .mascots, "Cat & Dog", "Gato y perro",
          "The age-old standoff, settled with sparks.",
          "La disputa de siempre, saldada a chispas.",
          .styles(.cat, .dog), .duel(.spark, .smoke, "GRR")),
        S(206, "catAndMouse", .mascots, "Cat and Mouse", "Gato y ratita",
          "Three dashes, one pounce, and the mouse gets away.",
          "Tres carreras, un zarpazo, y la ratita escapa.",
          .styles(.cat, .mouse), .volley(.spark, 3, .smoke, "MISS")),
        S(207, "bestFriends", .mascots, "Best Friends", "Mejores amigos",
          "A dog and a mouse, being impossible together.",
          "Un perro y una ratita, siendo imposibles juntos.",
          .styles(.dog, .mouse), .calm(.love, .love, .hearts, "AWW")),
        // Capybara, dragon and frog: peaceful moments, flames and pond hops.
        S(208, "onsenNap", .mascots, "Onsen Nap", "Siesta onsen",
          "A warm soak with a citrus crown, at peace with the world.",
          "Un baño tibio con una naranja en la coronilla, en paz con el mundo.",
          .style(.capybara), .calm(.relax, .sip, .sparkles, "ZEN")),
        S(209, "capyOrangeShare", .mascots, "Orange Share", "Compartir naranja",
          "A gentle nod rolls the fruit over to its companion.",
          "Un cabeceo suave hace rodar la fruta hacia su compañero.",
          .style(.capybara), .give(.snack(.apple), .celebrate, .hearts, "CHILL")),
        S(210, "capyTeaParty", .mascots, "Boba Harmony", "Armonía boba",
          "Slow sips and deep breaths: peak tranquility.",
          "Sorbos lentos y suspiros hondos: tranquilidad pura.",
          .styleWears(.capybara, .bobaTea), .ritual(.sip, .relax, .sparkles, "BOBA")),
        S(211, "hotSpringDuo", .mascots, "Hot Spring Duo", "Dúo termal",
          "The water salamander and the capybara share the warm currents.",
          "El ajolote y el carpincho comparten las corrientes cálidas.",
          .styles(.capybara, .axolotl), .calm(.relax, .groove, .magic, "WARM")),
        S(212, "capyAndBird", .mascots, "Perch of Peace", "Posa de paz",
          "The phoenix perches softly; neither makes a sound.",
          "El fénix se posa suavemente; ninguno hace un solo ruido.",
          .styles(.capybara, .phoenix), .ritual(.relax, .love, .hearts, "PEACE")),
        S(213, "dragonRoar", .mascots, "Tiny Flame", "Llamita",
          "It puffs up its chest and breathes a proud spark.",
          "Infla el pecho y exhala una chispa orgullosa.",
          .style(.dragon), .give(.fireball, .celebrate, .smoke, "ROAR")),
        S(214, "dragonCookout", .mascots, "Midnight Ramen", "Ramen nocturno",
          "One breathe of fire heats the soup to piping perfection.",
          "Una bocanada de fuego calienta la sopa a punto perfecto.",
          .styleWears(.dragon, .ramenBowl), .give(.snack(.ramen), .celebrate, .smoke, "TOAST")),
        S(215, "dragonHoard", .mascots, "Dragon Hoard", "Tesoro de dragón",
          "It curls around its gold, keeping it safe for the duo.",
          "Se enrosca sobre su oro, cuidándolo para el dúo.",
          .styleWears(.dragon, .goldBag), .ritual(.perk, .celebrate, .coins, "SHINY")),
        S(216, "dracoSlime", .mascots, "Flame & Jelly", "Fuego y gelatina",
          "A playful spark sizzles into the slime with a giggle.",
          "Una chispa juguetona chisporrotea en el slime entre risas.",
          .styles(.dragon, .slime), .volley(.fireball, 2, .smoke, "POOF")),
        S(217, "dragonDogDuo", .mascots, "Spark Fetch", "Búsqueda con chispa",
          "The pup fetches the fireball before it hits the ground.",
          "El perrito atrapa la bola de fuego antes de tocar el suelo.",
          .styles(.dragon, .dog), .duel(.spark, .sparkles, "SPARK")),
        S(218, "frogLilyHop", .mascots, "Lily Hop", "Salto de nenúfar",
          "A rhythmic series of high bounces across the water.",
          "Una serie rítmica de rebotes altos sobre el agua.",
          .style(.frog), .ritual(.bounce, .bounce, .sparkles, "CROAK")),
        S(219, "frogFlyCatch", .mascots, "Quick Reflex", "Reflejo rápido",
          "A swift flick of the tongue snaps the ball right out of the air.",
          "Un veloz lengüetazo atrapa la pelota directo en el aire.",
          .style(.frog), .volley(.ball, 2, .sparkles, "CATCH")),
        S(220, "frogTeaLeaf", .mascots, "Tea on a Leaf", "Té en el nenúfar",
          "A cool boba drink enjoyed under a sheltering leaf.",
          "Un té de perlas bien fresco bajo una hoja que hace de sombrilla.",
          .styleWears(.frog, .bobaTea), .calm(.sip, .groove, .hearts, "SLURP")),
        S(221, "rainyPond", .mascots, "Rain Dance", "Danza de lluvia",
          "A little storm cloud gathers, and the frog rejoices.",
          "Se asoma una nubecita y la ranita baila encantada.",
          .styleWears(.frog, .stormCloud), .chorus(.note, .groove, "RAIN")),
        S(222, "frogAndDuck", .mascots, "Pond Pals", "Amigos del estanque",
          "Rubber duck and frog splash around the puddle together.",
          "El patito de goma y la rana chapotean juntos en el charco.",
          .styleWears(.frog, .rubberDuck), .ritual(.bounce, .celebrate, .magic, "SPLASH")),
        // Dynamic wardrobe synergies: pairs across items and gadgets.
        S(223, "gamerDuo", .curiosities, "LAN Party", "Fiesta LAN",
          "Headphones on, controllers ready: co-op victory achieved.",
          "Auriculares listos y mandos en mano: victoria cooperativa lograda.",
          .pair(.gameController, .headphones), .duel(.bolt, .sparkles, "GG")),
        S(224, "bobaBreak", .curiosities, "Sweet Afternoon", "Tarde dulce",
          "A bubble tea and a cold ice cream cone shared after a long walk.",
          "Un té de boba y un cucurucho frío compartidos tras el paseo.",
          .pair(.bobaTea, .iceCreamCone), .calm(.sip, .love, .hearts, "SWEET")),
        S(225, "spaceOdyssey", .curiosities, "Orbital Team", "Equipo orbital",
          "Laser sights calibrated, thrusters fired: to the stars.",
          "Miras láser fijas y propulsores al máximo: rumbo a las estrellas.",
          .pair(.laserVisor, .jetpack), .ritual(.flash, .bounce, .sparkles, "ORBIT")),
        S(226, "detectiveCase", .curiosities, "Mystery Solved", "Misterio resuelto",
          "A lens looks close, the case is cracked, and hats tip.",
          "El lente busca pistas, el caso se aclara y se saludan con sombrero.",
          .pair(.detectiveLens, .topHat), .calm(.lookAround, .perk, .magic, "AHA")),
        S(227, "campfireCook", .curiosities, "Flambé Feast", "Banquete flambeado",
          "A fireball meets the chef hat for a spectacular five-star bake.",
          "El fuego y el gorro de chef se juntan para un flambeado cinco estrellas.",
          .pair(.chefHat, .fireballSpell), .give(.snack(.apple), .celebrate, .smoke, "CHEF")),
        S(228, "royalCourt", .curiosities, "Royal Audience", "Audiencia real",
          "The crown and scepter unite: all hail the dynamic duo.",
          "La corona y el cetro se unen: ovación para el dúo dinámico.",
          .pair(.crown, .kingScepter), .ritual(.ready, .celebrate, .confetti, "HAIL")),
        S(229, "witchBrew", .curiosities, "Alchemy Duet", "Dúo alquímico",
          "Ancient pages turn as the witch hat sparks with arcane light.",
          "Páginas antiguas pasan mientras el sombrero de bruja destella luz arcana.",
          .pair(.witchHat, .magicTome), .ritual(.flash, .celebrate, .magic, "HEX")),
        S(230, "cosmicParty", .curiosities, "Disco Grooves", "Pasos de disco",
          "Dark sunglasses beneath the spinning mirrored sphere.",
          "Gafas oscuras bajo la esfera espejada que gira sin parar.",
          .pair(.discoBall, .sunglasses), .chorus(.note, .groove, "FUNK")),
        S(231, "pirateRaid", .curiosities, "Buried Secret", "Secreto enterrado",
          "The eye patch spots the mark; the golden key does the rest.",
          "El parche encuentra la marca; la llave dorada abre el resto.",
          .pair(.eyePatch, .goldenKey), .give(.key, .celebrate, .coins, "AHOY")),
        S(232, "zenGarden", .curiosities, "Zen Garden", "Jardín zen",
          "A peaceful moment of blossom petals and rice balls.",
          "Un momento de calma entre pétalos de flor y bocadillos de arroz.",
          .pair(.flower, .onigiri), .calm(.relax, .love, .hearts, "ZEN")),
    ]

    private static let quests: [NotchMascotSynergy] = [
        S(128, "secretShop", .quests, "Secret Shop", "Tienda secreta",
          "A door opens behind the camera: boots and arms.",
          "Se abre una puerta tras la cámara: botas y armas.",
          .quest, .door(.shop)),
        S(129, "monsterInn", .quests, "Monster Land Inn", "Posada Monster Land",
          "A bed, a song and full hearts.",
          "Una cama, una canción y corazones llenos.",
          .quest, .door(.inn)),
        S(130, "coinCloud", .quests, "Coin Cloud", "Nube de monedas",
          "A shower of coins over the pair.",
          "Una lluvia de monedas sobre los dos.",
          .quest, .ritual(.celebrate, .celebrate, .coins, "+500")),
        S(131, "dragonMiniboss", .quests, "Dragon Mini-Boss", "Mini-boss dragón",
          "A quick fight behind the camera and a chest.",
          "Un combate rápido tras la cámara y un cofre.",
          .quest, .door(.bossLair)),
        S(132, "cameraHighFive", .quests, "High Five at the Camera", "Choque de manos en la cámara",
          "They meet over the camera and clap.",
          "Se encuentran sobre la cámara y chocan manos.",
          .quest, .ritual(.bounce, .bounce, .sparkles, nil)),
        S(133, "fruitThrow", .quests, "Fruit Throw", "Lanzar fruta",
          "A click sends an apple across the island.",
          "Un clic lanza una manzana por la isla.",
          .quest, .give(.snack(.apple), .celebrate, .sparkles, "+500")),
        S(134, "sharedCuddles", .quests, "Shared Cuddles", "Mimos compartidos",
          "A pat for one is a hug for both.",
          "Un mimo para uno es un abrazo para los dos.",
          .quest, .ritual(.love, .love, .hearts, "♥ +1")),
        S(135, "castleGate", .quests, "Castle Gate", "Portón de castillo",
          "A great gate opens for the two.",
          "Se abre un gran portón para los dos.",
          .quest, .ritual(.ready, .celebrate, .door, nil)),
    ]

    // MARK: Ballet and stage dance

    private static let dance: [NotchMascotSynergy] = [
        S(233, "grandPasDeDeux", .dance, "Grand Pas de Deux", "Grand Pas de Deux",
          "An imperial adagio, 360 promenade and overhead press lift.",
          "Un adagio imperial, promenade a 360 y alzada sobre la cabeza.",
          .styles(.ballerina, .danseur), .ritual(.groove, .celebrate, .confetti, "BRAVO!")),
        S(234, "donQBattle", .dance, "Don Quixote Coda", "Coda de Don Quijote",
          "Spanish fan snaps, double saut de basque and grand pirouettes.",
          "Chasquidos de abanico, double saut de basque y giros a la segunda.",
          .pair(.spanishFan, .pointeShoes), .ritual(.ready, .groove, .sparkles, "DON Q!")),
        S(235, "swanLakeDuet", .dance, "Dance of the Little Swans", "Danza de los cuatro cisnes",
          "Linked arms, rapid bourrées and synchronized head tilts.",
          "Brazos cruzados, bourrées rápidos y cabecitas al unísono.",
          .styles(.swan, .ballerina), .ritual(.bounce, .bounce, .sparkles, "LAKE")),
        S(236, "fouetteShowdown", .dance, "32 Fouettés en Tournant", "32 Fouettés en tournant",
          "Fierce spotting and whip turns right in place.",
          "Spotting veloz y latigazos de pierna clavados en el centro.",
          .styleWears(.ballerina, .pointeShoes), .chorus(.star, .groove, "32X!")),
        S(237, "sharedRosinBox", .dance, "Rosin Box Ritual", "Ritual de la caja de resina",
          "Crunching crystals in the wings before a grand jump.",
          "Triturando cristales en bastidores antes de un gran salto.",
          .wears(.rosinBox), .calm(.perk, .celebrate, .smoke, "CRUNCH!")),
        S(238, "dancerRecovery", .dance, "Ice Pack & Tendinitis", "Hielo y recuperación",
          "Resting weary arches with cold packs and deep sighs.",
          "Alivio frío en los empeines cansados con un hondo suspiro.",
          .wears(.icePack), .calm(.relax, .love, .hearts, "SORE FEET")),
        S(239, "plantarMassage", .dance, "Plantar Fascia Release", "Masaje de fascia plantar",
          "Rolling a tennis ball under tired feet to soothe the arch.",
          "Rodando una pelota de tenis para calmar el arco del pie.",
          .wears(.plantarBall), .calm(.sip, .relax, .sparkles, "RELIEF")),
        S(240, "warmUpBootiesShuffle", .dance, "Warm-Up Booties Shuffle", "Carrerita en botitas",
          "Fluffy neon booties shuffling around between rehearsals.",
          "Botitas acolchadas flúor trotando entre ensayo y ensayo.",
          .wears(.warmUpBooties), .ritual(.bounce, .groove, .confetti, "BOOTIES!")),
        S(241, "princeAndSwan", .dance, "Siegfried and Odette", "Sigfrido y Odette",
          "A tender bow as the swan rests its curved neck on his shoulder.",
          "Una reverencia mientras el cisne apoya su cuello en el hombro.",
          .styles(.swan, .danseur), .calm(.love, .love, .hearts, "ODETTE")),
        S(242, "theCatchPanic", .dance, "Fish Dive Catch", "Pánico en el Fish Dive",
          "A daring dive caught just inches above the floor.",
          "Una zambullida acrobática atrapada a milímetros del suelo.",
          .pair(.pointeShoes, .rosinBox), .give(.heart, .surprised, .smoke, "CAUGHT!")),
        S(243, "contactWave", .dance, "Contact Wave", "Ola de contact",
          "One rolls over the other's back in a seamless liquid transfer.",
          "Uno rueda sobre la espalda del otro en una transición líquida.",
          .styles(.contemporary, .contemporary), .ritual(.relax, .groove, .sparkles, "FLOW")),
        S(244, "elevationVsGravity", .dance, "Elevation vs Gravity", "Elevación contra gravedad",
          "Classical tours en l'air meet contemporary floorwork.",
          "Tours en l'air clásicos contra espirales de suelo contemporáneo.",
          .styles(.danseur, .contemporary), .ritual(.bounce, .relax, .confetti, "DANCE!")),
        S(245, "swanCrownGaze", .dance, "Swan Lake Tiara", "Corona del Lago",
          "The feathered crown glistens with enchanted moonlight.",
          "La diadema de plumas destella bajo la luna encantada.",
          .wears(.swanCrown), .chorus(.star, .love, "PURE")),
        S(246, "standingOvation", .dance, "Standing Ovation", "Ovación de pie",
          "Roses rain across the stage as the curtain falls.",
          "Lluvia de rosas en el escenario al caer el telón.",
          .pair(.swanCrown, .spanishFan), .ritual(.celebrate, .celebrate, .confetti, "BRAVO!")),
    ]

    // MARK: Toys and luck

    private static let toys: [NotchMascotSynergy] = [
        S(247, "propellerRace", .toys, "Propeller Race", "Carrera de hélices",
          "A propeller cap and a jetpack race each other to the clouds.",
          "Una gorra con hélice y una mochila cohete se pican hasta las nubes.",
          .pair(.propellerCap, .jetpack), .ritual(.perk, .bounce, .sparkles, "LIFTOFF")),
        S(248, "pirateParrot", .toys, "Pirate's Parrot", "El loro del pirata",
          "The parrot squawks orders and the pirate hands out doubloons.",
          "El loro grita órdenes y el pirata reparte doblones.",
          .pair(.parrot, .eyePatch), .give(.coin, .celebrate, .coins, "ARRR!")),
        S(249, "springDuel", .toys, "Spring Duel", "Duelo de muelles",
          "Two pairs of spring shoes bounce a ball back and forth.",
          "Dos pares de zapatos de muelle se pasan una pelota a botes.",
          .twin(.springShoes), .volley(.ball, 3, .confetti, "BOING")),
        S(250, "skateTrick", .toys, "Skate Session", "Sesión de skate",
          "Caps backwards, one kickflips while the other films it.",
          "Gorra hacia atrás, uno hace un kickflip y el otro lo graba.",
          .pair(.skateboard, .cap), .ritual(.ready, .celebrate, .smoke, "KICKFLIP")),
        S(251, "rainyDay", .toys, "Rainy Day", "Día de lluvia",
          "The storm cloud pours and the umbrella makes room for two.",
          "La nube descarga y el paraguas hace sitio para dos.",
          .pair(.umbrella, .stormCloud), .calm(.relax, .love, .sparkles, "COZY")),
        S(252, "yoyoBattle", .toys, "Yo-yo Battle", "Batalla de yoyós",
          "Walk the dog, around the world: the yo-yos clash in mid-air.",
          "Paseo del perro, vuelta al mundo: los yoyós chocan en el aire.",
          .twin(.yoyo), .duel(.ball, .sparkles, "YO-YO!")),
        S(253, "bubbleRegatta", .toys, "Bubble Regatta", "Regata de pompas",
          "Bubbles float up and the rubber duck sails right through them.",
          "Suben las pompas y el pato de goma navega entre ellas.",
          .pair(.bubbleWand, .rubberDuck), .ritual(.bounce, .groove, .sparkles, "REGATTA")),
        S(254, "magnetHeist", .toys, "Magnet Heist", "El golpe del imán",
          "The magnet coaxes every coin out of the piggy bank.",
          "El imán saca de la hucha hasta la última moneda.",
          .pair(.horseshoeMagnet, .piggyBank), .give(.coin, .surprised, .coins, "CLINK!")),
        S(255, "highRollers", .toys, "High Rollers", "Apuesta fuerte",
          "Dice against a bag of gold: winner takes the lot.",
          "Dados contra una bolsa de oro: el que gana se lo lleva todo.",
          .pair(.luckyDice, .goldBag), .duel(.star, .coins, "JACKPOT")),
        S(256, "fortuneTeller", .toys, "Fortune Teller", "La pitonisa",
          "The crystal orb and the cookie agree on what the future holds.",
          "La bola de cristal y la galleta coinciden en lo que viene.",
          .pair(.fortuneCookie, .crystalOrb), .chorus(.cookie, .peek, "DESTINY")),
        S(257, "winterWonder", .toys, "Snow Day", "Día de nieve",
          "One shakes the snow globe and the other catches snowflakes.",
          "Uno agita la bola de nieve y el otro atrapa copos.",
          .pair(.snowGlobe, .beanie), .chorus(.snowball, .love, "SNOW DAY")),
        S(258, "photoBooth", .toys, "Photo Booth", "Fotomatón",
          "Squeeze in, pull a face, flash: a snapshot for the album.",
          "Juntitos, una mueca y flash: una foto para el álbum.",
          .wears(.instantCamera), .ritual(.flash, .celebrate, .confetti, "CHEESE!")),
    ]

    // MARK: Kitsune and Penguin

    private static let legends: [NotchMascotSynergy] = [
        S(259, "fireAndIce", .legends, "Fire and Ice", "Fuego y hielo",
          "Blue foxfire meets polar frost, and neither melts the other.",
          "El fuego zorruno se cruza con la escarcha polar y ninguno derrite al otro.",
          .styles(.kitsune, .penguin), .calm(.perk, .relax, .magic, "FIRE N ICE")),
        S(260, "foxWedding", .legends, "Fox Wedding", "Boda de zorros",
          "Two kitsune walk under a sun shower, the old sign of a fox wedding.",
          "Dos kitsune pasean bajo la lluvia con sol, la señal de una boda de zorros.",
          .styles(.kitsune, .kitsune), .ritual(.love, .love, .sparkles, "SUN SHOWER")),
        S(261, "emperorHuddle", .legends, "Emperor Huddle", "Abrazo emperador",
          "Two penguins huddle close and take turns at the warm middle.",
          "Dos pingüinos se apiñan y se turnan para estar en el medio calentito.",
          .styles(.penguin, .penguin), .calm(.relax, .love, .hearts, "HUDDLE")),
        S(262, "foxAndHound", .legends, "Fox and Hound", "El zorro y el sabueso",
          "A chase round and round until both flop down, best friends again.",
          "Una persecución en círculos hasta que caen rendidos, amigos otra vez.",
          .styles(.kitsune, .dog), .volley(.ball, 3, .confetti, "TALLY HO")),
        S(263, "nightProwlers", .legends, "Night Prowlers", "Merodeadores nocturnos",
          "Fox and cat stalk the same moonbeam; the fox pounces first.",
          "Zorro y gato acechan el mismo rayo de luna; el zorro salta antes.",
          .styles(.kitsune, .cat), .duel(.star, .sparkles, "PROWL")),
        S(264, "spiritFlames", .legends, "Spirit Flames", "Llamas espirituales",
          "Blue foxfire against dragon fire: the sky lights up twice.",
          "Fuego zorruno azul contra fuego de dragón: el cielo se enciende dos veces.",
          .styles(.kitsune, .dragon), .duel(.fireball, .magic, "KITSUNEBI")),
        S(265, "nightParade", .legends, "Night Parade", "Desfile nocturno",
          "A ghost and a fox spirit lead a parade of lanterns through the dark.",
          "Un fantasma y un espíritu zorro guían un desfile de farolillos en la noche.",
          .styles(.kitsune, .ghost), .ritual(.surprised, .celebrate, .smoke, "BOO")),
        S(266, "shrineFortune", .legends, "Shrine Fortune", "La suerte del santuario",
          "The kitsune reads the fortune slip aloud: the very best luck.",
          "El kitsune lee en voz alta el papelito de la suerte: la mejor de todas.",
          .styleWears(.kitsune, .fortuneCookie), .give(.cookie, .celebrate, .coins, "DAIKICHI")),
        S(267, "kitsuneUdon", .legends, "Kitsune Udon", "Udon de zorro",
          "Noodles with fried tofu on top, a fox spirit's favourite bowl.",
          "Fideos con tofu frito encima, el cuenco favorito de un espíritu zorro.",
          .styleWears(.kitsune, .ramenBowl), .give(.snack(.ramen), .love, .hearts, "SLURP")),
        S(268, "starPearl", .legends, "Star Pearl", "La perla estrella",
          "The orb glows like the pearl a kitsune keeps its magic in.",
          "La esfera brilla como la perla donde un kitsune guarda su magia.",
          .styleWears(.kitsune, .crystalOrb), .chorus(.star, .peek, "HOSHI")),
        S(269, "blackTieBall", .legends, "Black Tie Ball", "Baile de etiqueta",
          "A swan and a penguin in full tuxedo waltz across the stage.",
          "Un cisne y un pingüino de riguroso frac bailan un vals por el escenario.",
          .styles(.penguin, .swan), .chorus(.note, .groove, "WALTZ")),
        S(270, "hotSpringVisit", .legends, "Hot Spring Visit", "Visita a las termas",
          "The capybara offers the warm spring; the penguin dips one toe in.",
          "El carpincho ofrece las termas; el pingüino mete un dedito.",
          .styles(.penguin, .capybara), .calm(.relax, .surprised, .sparkles, "ONSEN")),
        S(271, "deepDive", .legends, "Deep Dive", "Inmersión profunda",
          "Penguin and axolotl race to the bottom of the pond and back.",
          "Pingüino y ajolote echan una carrera al fondo del estanque y vuelta.",
          .styles(.penguin, .axolotl), .volley(.duck, 2, .sparkles, "SPLASH")),
        S(272, "tuxedoGala", .legends, "Tuxedo Gala", "Gala de frac",
          "Bow tie straightened, the penguin greets every guest at the door.",
          "Con la pajarita en su sitio, el pingüino recibe a cada invitado.",
          .styleWears(.penguin, .bowTie), .ritual(.perk, .celebrate, .confetti, "BLACK TIE")),
        S(273, "toboggan", .legends, "Toboggan Run", "Tobogán helado",
          "Belly down on the board, it slides farther than anyone ever has.",
          "Panza abajo sobre la tabla, se desliza más lejos que nadie jamás.",
          .styleWears(.penguin, .skateboard), .ritual(.ready, .celebrate, .smoke, "WHEEE")),
        S(274, "homeSweetHome", .legends, "Home, Sweet Home", "Hogar, dulce hogar",
          "It shakes the snow globe and gazes at the little icy world inside.",
          "Agita la bola de nieve y contempla el mundito helado de adentro.",
          .styleWears(.penguin, .snowGlobe), .calm(.love, .relax, .sparkles, "HOME")),
    ]

    // MARK: Hologram and Android

    private static let signals: [NotchMascotSynergy] = [
        S(275, "signalAndSteel", .signals, "Signal and Steel", "Señal y acero",
          "Light and metal fall into step, their clocks ticking as one.",
          "La luz y el metal se acompasan, con los relojes latiendo a la vez.",
          .styles(.hologram, .android), .calm(.perk, .relax, .magic, "SYNC")),
        S(276, "mirrorFeed", .signals, "Mirror Feed", "Señal en espejo",
          "Two holograms on the same channel wave at once, a beat apart.",
          "Dos hologramas en el mismo canal saludan a la vez, con un pelín de retraso.",
          .styles(.hologram, .hologram), .ritual(.wave, .wave, .sparkles, "ECHO")),
        S(277, "firmwareUpdate", .signals, "Firmware Update", "Actualización",
          "One android shares its newest patch, and both reboot a little smarter.",
          "Un androide comparte su último parche y los dos reinician un poco más listos.",
          .styles(.android, .android), .calm(.ready, .celebrate, .sparkles, "UPDATE")),
        S(278, "projectorRepair", .signals, "Projector Repair", "El técnico",
          "The robot tightens one bolt and the hologram comes through crystal clear.",
          "El robot aprieta un tornillo y el holograma se ve nítido como nunca.",
          .styles(.hologram, .robot), .give(.bolt, .love, .sparkles, "FIXED")),
        S(279, "spectralCousins", .signals, "Spectral Cousins", "Primos espectrales",
          "A ghost and a hologram compare who is harder to see through.",
          "Un fantasma y un holograma comparan quién es más transparente.",
          .styles(.hologram, .ghost), .calm(.surprised, .love, .smoke, "BOO?")),
        S(280, "liveFeed", .signals, "Live Feed", "En directo",
          "The chip streams the signal and the hologram dances to it.",
          "El chip emite la señal y el holograma baila al ritmo.",
          .styles(.hologram, .chip), .chorus(.spark, .groove, "STREAM")),
        S(281, "generations", .signals, "Generations", "Generaciones",
          "Old robot and new android trade beeps, each in its own dialect.",
          "El robot de siempre y el androide nuevo se cruzan pitidos, cada uno en su dialecto.",
          .styles(.android, .robot), .volley(.bolt, 2, .sparkles, "BEEP BOOP")),
        S(282, "redline", .signals, "Redline", "A tope",
          "The chip pushes the clocks and the android's gauge runs all the way up.",
          "El chip sube las frecuencias y el medidor del androide se llena hasta arriba.",
          .styles(.android, .chip), .ritual(.ready, .sweat, .smoke, "REDLINE")),
        S(283, "coolingLoop", .signals, "Cooling Loop", "Refrigeración",
          "The fan blows cool air over the android until it hums happily again.",
          "El ventilador sopla aire fresco sobre el androide hasta que vuelve a ronronear.",
          .styles(.android, .fan), .calm(.panic, .relax, .sparkles, "COOL")),
        S(284, "synthwave", .signals, "Synthwave", "Synthwave",
          "Headphones on, the hologram glows in time with the bassline.",
          "Con los auriculares puestos, el holograma brilla al ritmo del bajo.",
          .styleWears(.hologram, .headphones), .chorus(.note, .groove, "SYNTH")),
        S(285, "lightShow", .signals, "Light Show", "Espectáculo de luces",
          "The disco ball splits her light into a hundred dancing beams.",
          "La bola de discoteca parte su luz en cien rayos que bailan.",
          .styleWears(.hologram, .discoBall), .ritual(.groove, .celebrate, .confetti, "LASERS")),
        S(286, "glitchedSelfie", .signals, "Glitched Selfie", "Selfi con glitch",
          "Every photo of a hologram comes out a little scrambled, and she loves it.",
          "Cada foto de un holograma sale un poco revuelta, y a ella le encanta.",
          .styleWears(.hologram, .instantCamera), .ritual(.flash, .confused, .sparkles, "GLITCH")),
        S(287, "doubleThrust", .signals, "Double Thrust", "Doble propulsión",
          "Jetpack and hover jet together: the android has never flown so high.",
          "Mochila cohete y chorro propio a la vez: el androide nunca voló tan alto.",
          .styleWears(.android, .jetpack), .ritual(.ready, .celebrate, .smoke, "BOOST")),
        S(288, "targetLock", .signals, "Target Lock", "Blanco fijado",
          "The visor sweeps the room and locks onto the nearest friend.",
          "El visor barre la sala y fija al amigo más cercano.",
          .styleWears(.android, .laserVisor), .ritual(.peek, .ready, .sparkles, "LOCKED")),
        S(289, "playerTwo", .signals, "Player Two", "Jugador dos",
          "Controller in hand, the android challenges anyone to a rematch.",
          "Mando en mano, el androide reta a cualquiera a la revancha.",
          .styleWears(.android, .gameController), .volley(.ball, 3, .coins, "P2")),
        S(290, "deepSpace", .signals, "Deep Space", "Espacio profundo",
          "Antennae up, the hologram picks up a faint signal from very far away.",
          "Con las antenas en alto, el holograma capta una señal débil desde muy lejos.",
          .styleWears(.hologram, .alienAntenna), .calm(.peek, .surprised, .magic, "PING")),
        S(291, "illusionists", .signals, "Illusionists", "Ilusionistas",
          "A fox spirit and a girl of light trade tricks: which one is really there?",
          "Un espíritu zorro y una chica de luz se cruzan trucos: ¿cuál está ahí de verdad?",
          .styles(.hologram, .kitsune), .duel(.star, .magic, "ILLUSION")),
        S(292, "coldBoot", .signals, "Cold Boot", "Arranque en frío",
          "The penguin lends the android a little polar air, and it starts up first time.",
          "El pingüino le presta un poco de aire polar al androide y arranca a la primera.",
          .styles(.android, .penguin), .calm(.sweat, .relax, .sparkles, "COLD BOOT")),
        S(293, "fetchProtocol", .signals, "Fetch Protocol", "Protocolo: buscar",
          "The dog explains fetch; the android runs it a thousand times without a bug.",
          "El perro explica cómo traer la pelota; el androide lo ejecuta mil veces sin un error.",
          .styles(.android, .dog), .volley(.ball, 3, .confetti, "FETCH.EXE")),
        S(294, "lightBallet", .signals, "Light Ballet", "Ballet de luz",
          "The ballerina dances and the hologram copies every step in light.",
          "La bailarina baila y el holograma copia cada paso hecho de luz.",
          .styles(.hologram, .ballerina), .chorus(.note, .groove, "PAS DE DEUX")),
        S(295, "powerSaving", .signals, "Power Saving", "Ahorro de energía",
          "Beside the calmest capybara, even an android learns to idle.",
          "Junto al carpincho más tranquilo, hasta un androide aprende a estar en reposo.",
          .styles(.android, .capybara), .calm(.relax, .relax, .sparkles, "IDLE")),
        S(296, "crystalProjection", .signals, "Crystal Projection", "Proyección de cristal",
          "Light passes through the orb and the hologram sees what is to come.",
          "La luz atraviesa la esfera y el holograma ve lo que está por venir.",
          .styleWears(.hologram, .crystalOrb), .ritual(.peek, .surprised, .magic, "VISION")),
    ]

    // MARK: Party and play

    private static let party: [NotchMascotSynergy] = [
        S(297, "kiteStorm", .party, "Kite in the Storm", "Barrilete en la tormenta",
          "The kite climbs into the storm cloud and a bolt runs down its string.",
          "El barrilete sube hasta la nube y un rayo baja por el hilo.",
          .pair(.kite, .stormCloud), .give(.bolt, .surprised, .sparkles, "ZAP!")),
        S(298, "dragonCampfire", .party, "Dragon Campfire", "Fogata de dragón",
          "No matches needed: the dragon toasts the marshmallow with one small puff.",
          "Sin fósforos: el dragón tuesta el malvavisco con un soplido chiquito.",
          .styleWears(.dragon, .marshmallowStick), .give(.fireball, .love, .smoke, "TOASTY")),
        S(299, "phoenixRoast", .party, "Phoenix Roast", "Asado del fénix",
          "The phoenix flares up and the marshmallow comes out a perfect gold.",
          "El fénix se enciende y el malvavisco sale dorado perfecto.",
          .styleWears(.phoenix, .marshmallowStick), .ritual(.flash, .love, .smoke, "GOLDEN")),
        S(300, "squirtShield", .party, "Squirt and Shield", "Chorro y escudo",
          "Squirt after squirt, and the umbrella blocks every one.",
          "Chorro tras chorro, y el paraguas los ataja todos.",
          .pair(.waterPistol, .umbrella), .volley(.snowball, 3, .sparkles, "BLOCKED")),
        S(301, "pillowFight", .party, "Pillow Fight", "Guerra de almohadas",
          "Two pillows, one swing each, and feathers everywhere.",
          "Dos almohadas, un almohadazo cada uno y plumas por todos lados.",
          .twin(.pillow), .duel(.heart, .confetti, "POMF!")),
        S(302, "overAndOut", .party, "Over and Out", "Cambio y fuera",
          "Two walkie-talkies, a secret mission and far too much static.",
          "Dos walkie-talkies, una misión secreta y demasiada estática.",
          .twin(.walkieTalkie), .chorus(.spark, .peek, "OVER")),
        S(303, "bardDrums", .party, "Bard and Drums", "Bardo y tambor",
          "The lute plays the tune and the drum keeps the tavern on its feet.",
          "El laúd pone la melodía y el tambor tiene a la taberna de pie.",
          .pair(.drum, .bardLute), .chorus(.note, .groove, "ENCORE")),
        S(304, "soundCheck", .party, "Sound Check", "Prueba de sonido",
          "One taps the microphone, the other listens in the headphones: one, two.",
          "Uno golpea el micrófono, el otro escucha con los auriculares: probando.",
          .pair(.microphone, .headphones), .ritual(.groove, .perk, .confetti, "1 2 1 2")),
        S(305, "refereeKickoff", .party, "Kickoff", "Saque inicial",
          "The whistle blows, the ball goes back and forth and someone scores.",
          "Suena el silbato, la pelota va y viene y alguien hace un gol.",
          .pair(.soccerBall, .whistle), .volley(.ball, 3, .confetti, "GOAL!")),
        S(306, "surpriseParty", .party, "Surprise Party", "Fiesta sorpresa",
          "Party hat on, eyes shut, and the cannon goes off: surprise!",
          "Gorrito puesto, ojos cerrados y estalla el cañón: ¡sorpresa!",
          .pair(.confettiCannon, .partyHat), .ritual(.celebrate, .surprised, .confetti, "SURPRISE!")),
        S(307, "riceBallPicnic", .party, "Rice Ball Picnic", "Pícnic de onigiris",
          "The basket opens and out comes a rice ball for each.",
          "Se abre la canasta y sale un onigiri para cada uno.",
          .pair(.picnicBasket, .onigiri), .give(.snack(.onigiri), .love, .hearts, "ITADAKIMASU")),
        S(308, "noodlePicnic", .party, "Noodle Picnic", "Pícnic de fideos",
          "A hot bowl of ramen on a picnic cloth, steam rising in the sun.",
          "Un ramen calentito sobre el mantel, con el vapor subiendo al sol.",
          .pair(.picnicBasket, .ramenBowl), .give(.snack(.ramen), .relax, .smoke, "NOODLES")),
        S(309, "airMail", .party, "Air Mail", "Correo aéreo",
          "The paper plane flies off and the propeller cap chases it down.",
          "El avión de papel sale volando y la gorra con hélice lo persigue.",
          .pair(.paperPlane, .propellerCap), .volley(.arrow, 2, .sparkles, "AIRMAIL")),
        S(310, "hoopFever", .party, "Hoop Fever", "Fiebre del aro",
          "Under the disco ball the hoop never stops spinning.",
          "Bajo la bola de discoteca el aro no para de girar.",
          .pair(.hulaHoop, .discoBall), .chorus(.star, .groove, "DISCO")),
        S(311, "circusAct", .party, "Circus Act", "Número de circo",
          "The juggler tosses, the clown honks, and nobody drops a thing.",
          "El malabarista lanza, el payaso hace bocina y nadie deja caer nada.",
          .pair(.jugglingBalls, .clownNose), .volley(.ball, 4, .confetti, "HONK HONK")),
        S(312, "roadworks", .party, "Roadworks", "Obras en la calle",
          "Megaphone in hand, the foreman sends everyone round the cone.",
          "Megáfono en mano, el capataz manda a todos a rodear el cono.",
          .pair(.megaphone, .trafficCone), .ritual(.ready, .confused, .smoke, "DETOUR!")),
        S(313, "flamencoFiesta", .party, "Flamenco Fiesta", "Fiesta flamenca",
          "Maracas keep the beat and the fan snaps open on every turn.",
          "Las maracas marcan el ritmo y el abanico se abre en cada vuelta.",
          .pair(.maracas, .spanishFan), .chorus(.note, .groove, "OLE!")),
        S(314, "zenPicnic", .party, "Zen Picnic", "Pícnic zen",
          "The capybara spreads the cloth and nobody hurries at all.",
          "El carpincho tiende el mantel y nadie tiene ningún apuro.",
          .styleWears(.capybara, .picnicBasket), .calm(.relax, .love, .hearts, "ZEN")),
        S(315, "rhythmSection", .party, "Rhythm Section", "Sección rítmica",
          "Drum and maracas lock into a groove nobody can sit still to.",
          "Tambor y maracas arman un ritmo con el que nadie se queda quieto.",
          .pair(.drum, .maracas), .chorus(.note, .bounce, "CHA CHA")),
        S(316, "waterFight", .party, "Water Fight", "Guerra de agua",
          "Two water pistols at ten paces: the first squirt wins.",
          "Dos pistolas de agua a diez pasos: gana el primer chorro.",
          .twin(.waterPistol), .duel(.snowball, .sparkles, "SPLOOSH")),
        S(317, "controlTower", .party, "Control Tower", "Torre de control",
          "Cleared for take-off: the walkie-talkie talks the paper plane down.",
          "Pista libre: el walkie-talkie guía al avión de papel hasta aterrizar.",
          .pair(.paperPlane, .walkieTalkie), .give(.arrow, .perk, .sparkles, "CLEARED")),
        S(318, "feedbackLoop", .party, "Feedback Loop", "Acople",
          "Megaphone meets microphone and the speakers shriek.",
          "El megáfono se cruza con el micrófono y los parlantes chillan.",
          .pair(.megaphone, .microphone), .duel(.note, .smoke, "SKREE!")),
        S(319, "sleepover", .party, "Sleepover", "Pijamada",
          "A pillow, a sleep mask and stories whispered until both doze off.",
          "Una almohada, un antifaz y cuentos en voz baja hasta que se duermen.",
          .pair(.pillow, .sleepMask), .calm(.yawn, .relax, .hearts, "ZZZ")),
        S(320, "kiteFlyers", .party, "Kite Flyers", "Remontando barriletes",
          "Two kites side by side, their tails tangling high in the wind.",
          "Dos barriletes juntos, con las colas enredándose en el viento.",
          .twin(.kite), .calm(.perk, .love, .sparkles, "WHEE")),
    ]

    // MARK: Oddities and wonders
    private static let oddities: [NotchMascotSynergy] = [
        S(321, "pizzeria", .oddities, "Pizzeria", "Pizzería",
          "The chef tosses the dough and the slice comes out hot for the one waiting.",
          "El chef revolea la masa y sale una porción calentita para el que espera.",
          .pair(.pizzaSlice, .chefHat), .give(.pie, .love, .hearts, "MAMMA MIA")),
        S(322, "beekeeper", .oddities, "Beekeeper", "Apicultor",
          "The bees leave a head for a flower and everyone calms down.",
          "Las abejas dejan la cabeza por una flor y todos se calman.",
          .pair(.beeHalo, .flower), .calm(.relax, .love, .sparkles, "BUZZ")),
        S(323, "honeyThief", .oddities, "Honey Thief", "Ladrón de miel",
          "The teddy bear goes for the honey; the bees go for the bear.",
          "El osito va por la miel; las abejas van por el osito.",
          .pair(.beeHalo, .teddyBear), .duel(.spark, .smoke, "OUCH!")),
        S(324, "royalJester", .oddities, "The King's Fool", "El bufón del rey",
          "The jester tumbles and jingles until the king laughs out loud.",
          "El bufón da volteretas y hace sonar los cascabeles hasta que el rey se ríe.",
          .pair(.jesterHat, .crown), .ritual(.celebrate, .wave, .confetti, "HA HA")),
        S(325, "crackerPull", .oddities, "Pull the Cracker", "Tirar del petardo",
          "One end each, a pull, a bang, and two paper crowns.",
          "Una punta cada uno, un tirón, un estallido y dos coronas de papel.",
          .twin(.crackerCrown), .duel(.star, .confetti, "BANG!")),
        S(326, "kazooBand", .oddities, "Kazoo Band", "Banda de kazoo",
          "The drum keeps time and the kazoo buzzes the tune, sort of.",
          "El tambor lleva el ritmo y el kazoo zumba la melodía, más o menos.",
          .pair(.kazoo, .drum), .chorus(.note, .groove, "TOOT")),
        S(327, "itsyBitsy", .oddities, "Itsy Bitsy", "Arañita",
          "Two lenses, one spider, and both of them jump.",
          "Dos lentes, una arañita y los dos pegan un salto.",
          .pair(.spiderMonocle, .detectiveLens), .give(.key, .panic, .smoke, "EEK!")),
        S(328, "takeMeToYourLeader", .oddities, "Take Me to Your Leader", "Llévame con tu líder",
          "The antennae pick up the saucer's signal and the beam comes down.",
          "Las antenas captan la señal del platillo y baja el rayo.",
          .pair(.ufoHat, .alienAntenna), .ritual(.perk, .surprised, .magic, "BEAM ME UP")),
        S(329, "cattleRustlers", .oddities, "Cattle Rustlers", "Abigeato espacial",
          "The cowboy guards the herd; the saucer has other plans.",
          "El vaquero cuida el ganado; el platillo tiene otros planes.",
          .pair(.ufoHat, .cowboyHat), .give(.star, .surprised, .magic, "YEEHAW?")),
        S(330, "duckDive", .oddities, "Duck Dive", "Chapuzón con pato",
          "Mask on, a dive, and back up with a rubber duck for the friend.",
          "Máscara puesta, un chapuzón y de vuelta con un patito para el amigo.",
          .pair(.snorkelMask, .rubberDuck), .give(.duck, .love, .sparkles, "SPLASH")),
        S(331, "pirateCrew", .oddities, "Pirate Crew", "Tripulación pirata",
          "A hook and an eye patch: the treasure map is theirs.",
          "Un garfio y un parche: el mapa del tesoro es suyo.",
          .pair(.pirateHook, .eyePatch), .ritual(.ready, .peek, .coins, "ARRR!")),
        S(332, "piecesOfEight", .oddities, "Pieces of Eight", "Monedas de a ocho",
          "The parrot counts the gold and the captain counts it again.",
          "El loro cuenta el oro y el capitán lo vuelve a contar.",
          .pair(.pirateHook, .parrot), .chorus(.coin, .peek, "PIECES OF 8")),
        S(333, "councilOfSages", .oddities, "Council of Sages", "Consejo de sabios",
          "A long beard, a staff, and a spell argued over for ages.",
          "Una barba larga, un báculo y un hechizo discutido durante siglos.",
          .pair(.wizardBeard, .wizardStaff), .ritual(.flash, .peek, .magic, "ABRACADABRA")),
        S(334, "cryptLantern", .oddities, "Lantern in the Crypt", "Farol en la cripta",
          "The lantern finds the crystal skull, and the skull finds them.",
          "El farol encuentra la calavera de cristal, y la calavera los encuentra a ellos.",
          .pair(.lantern, .crystalSkull), .give(.spark, .panic, .smoke, "BOO!")),
        S(335, "rollerDisco", .oddities, "Roller Disco", "Disco sobre ruedas",
          "Under the mirror ball the skates go round and round.",
          "Bajo la bola de espejos los patines giran y giran.",
          .pair(.rollerSkates, .discoBall), .chorus(.star, .groove, "ROLLER DISCO")),
        S(336, "rollerDerby", .oddities, "Roller Derby", "Roller derby",
          "Two on skates, one ball, and elbows out.",
          "Dos en patines, una pelota y codos afuera.",
          .twin(.rollerSkates), .volley(.ball, 3, .confetti, "DERBY")),
        S(337, "cabaret", .oddities, "Cabaret", "Cabaret",
          "A boa thrown over the shoulder and a song into the microphone.",
          "Una boa al hombro y una canción al micrófono.",
          .pair(.featherBoa, .microphone), .ritual(.groove, .perk, .hearts, "DIVA")),
        S(338, "snailMail", .oddities, "Snail Mail", "Correo caracol",
          "The paper plane is sent; the snail delivers it, eventually.",
          "Se manda el avión de papel; el caracol lo entrega, algún día.",
          .pair(.snail, .paperPlane), .give(.arrow, .yawn, .sparkles, "SLOW MAIL")),
        S(339, "bubbleTrouble", .oddities, "Bubble Trouble", "Lío de burbujas",
          "Soap bubbles one way, a gum bubble the other, and they all pop.",
          "Burbujas de jabón para un lado, un globo de chicle para el otro, y explotan todas.",
          .pair(.bubbleGum, .bubbleWand), .volley(.balloon, 3, .confetti, "POP!")),
        S(340, "chickenDance", .oddities, "Chicken Dance", "Baile del pollito",
          "A squeak for every flap: the whole party joins the chicken dance.",
          "Un chillido por cada aleteo: toda la fiesta se suma al baile del pollito.",
          .pair(.rubberChicken, .partyHat), .chorus(.note, .bounce, "BAWK BAWK")),
        // A transformation meets what the other wears: a thing bought for
        // one companion mixes with the power of another.
        S(341, "midasTouch", .forms, "Midas Touch", "Toque de Midas",
          "A transformed one and a bag of gold: everything it touches rains coins.",
          "Un transformado y una bolsa de oro: todo lo que toca llueve monedas.",
          .formWears(.goldBag), .ritual(.celebrate, .perk, .coins, "MIDAS")),
        S(342, "stormLord", .forms, "Storm Lord", "Señor de la tormenta",
          "Lightning answers lightning: a transformed one duels the thunder talisman.",
          "El rayo responde al rayo: un transformado duela con el talismán del trueno.",
          .formWears(.thunderTalisman), .duel(.bolt, .magic, "THUNDER")),
        S(343, "sharedAura", .forms, "Shared Aura", "Aura compartida",
          "Two transformed at once: their auras meet in a shower of sparks.",
          "Dos transformados a la vez: sus auras se encuentran en una lluvia de chispas.",
          .bothFormed, .chorus(.spark, .perk, "POWER")),
        S(344, "haloChoir", .forms, "Halo Choir", "Coro del halo",
          "A halo over one and an aura round the other: a moment of grace.",
          "Un halo sobre uno y un aura en el otro: un momento de gracia.",
          .formWears(.halo), .calm(.relax, .love, .sparkles, nil)),
        S(345, "legendClash", .forms, "Legend Clash", "Choque de leyendas",
          "The sword of legend against a transformed one: steel rings on power.",
          "La espada legendaria contra un transformado: el acero tañe contra el poder.",
          .formWears(.legendSword), .duel(.sword, .sparkles, "CLASH")),
        S(346, "goldenFeast", .forms, "Golden Feast", "Festín dorado",
          "Ramen served to a transformed one: it is a feast fit for its aura.",
          "Ramen servido a un transformado: un festín a la altura de su aura.",
          .formWears(.ramenBowl), .give(.snack(.ramen), .celebrate, .confetti, "+500")),
        S(347, "sparkingPunch", .forms, "Sparking Punch", "Puñetazo chispeante",
          "Boxing gloves against an aura: every jab throws sparks.",
          "Guantes de boxeo contra un aura: cada golpe lanza chispas.",
          .formWears(.boxingGloves), .duel(.spark, .smoke, "KO!")),
        S(348, "forgedBelt", .forms, "Forged Belt", "Cinturón forjado",
          "A black belt bows to a transformed master, and the dojo lights up.",
          "Un cinturón negro saluda a un maestro transformado, y el dojo se enciende.",
          .formWears(.karateBelt), .ritual(.ready, .ready, .magic, "HIYA!")),
        S(349, "litStage", .forms, "Lit Stage", "Escenario encendido",
          "A guitar solo with an aura for stage lights: the crowd wants more.",
          "Un solo de guitarra con un aura de foco: el público pide más.",
          .formWears(.electricGuitar), .chorus(.note, .groove, "ENCORE")),
        S(350, "starGazing", .forms, "Star Gazing", "Mirando estrellas",
          "A telescope turned on a transformed one: the brightest star in the room.",
          "Un telescopio apuntado a un transformado: la estrella más brillante de la sala.",
          .formWears(.telescope), .calm(.peek, .love, .sparkles, "WOW")),
        S(351, "goldDig", .forms, "Gold Dig", "Cavando oro",
          "A shovel beside a transformed one: the ground gives up its coins.",
          "Una pala junto a un transformado: el suelo suelta sus monedas.",
          .formWears(.shovel), .give(.coin, .celebrate, .coins, "+100")),
        S(352, "powerBounce", .forms, "Power Bounce", "Rebote de poder",
          "A pogo stick and an aura: it bounces higher than ever.",
          "Un saltarín y un aura: rebota más alto que nunca.",
          .formWears(.pogoStick), .volley(.ball, 3, .sparkles, "BOING")),
        // The workshop's things, together and with the right figure.
        S(353, "rockDuet", .workshop, "Rock Duet", "Dúo de rock",
          "An electric guitar and a lute: the oldest and the loudest make a band.",
          "Una guitarra eléctrica y un laúd: lo más viejo y lo más ruidoso hacen una banda.",
          .pair(.electricGuitar, .bardLute), .chorus(.note, .groove, "ROCK ON")),
        S(354, "dojo", .workshop, "Dojo", "Dojo",
          "A karate belt faces boxing gloves: a friendly bout, and a bow.",
          "Una cinta de karate frente a guantes de boxeo: un combate amistoso, y una reverencia.",
          .pair(.karateBelt, .boxingGloves), .duel(.spark, .smoke, "HIYA")),
        S(355, "pleinAir", .workshop, "Plein Air", "Al aire libre",
          "A painter and a flower: the model holds still, mostly.",
          "Un pintor y una flor: la modelo se queda quieta, más o menos.",
          .pair(.painterBeret, .flower), .give(.flower, .love, .sparkles, "ART")),
        S(356, "teaCeremony", .workshop, "Tea Ceremony", "Ceremonia del té",
          "A bowl of matcha and a chef's hat: whisked, served and sipped in silence.",
          "Un cuenco de matcha y un gorro de chef: batido, servido y sorbido en silencio.",
          .pair(.matchaBowl, .chefHat), .calm(.sip, .relax, .sparkles, nil)),
        S(357, "nightWatch", .workshop, "Night Watch", "Guardia nocturna",
          "A telescope and a lantern: one lights the way, the other finds the star.",
          "Un telescopio y un farol: uno alumbra el camino, el otro encuentra la estrella.",
          .pair(.telescope, .lantern), .calm(.peek, .surprised, .magic, "STAR")),
        S(358, "treasureHunt", .workshop, "Treasure Hunt", "Caza del tesoro",
          "A shovel and a detective's lens: X marks the spot, and the spot pays.",
          "Una pala y una lupa de detective: la X marca el lugar, y el lugar paga.",
          .pair(.shovel, .detectiveLens), .give(.key, .celebrate, .coins, "FOUND")),
        S(359, "pogoRace", .workshop, "Pogo Race", "Carrera de saltarines",
          "Two pogo sticks: a race across the floor, boing by boing.",
          "Dos saltarines: una carrera por el suelo, bote a bote.",
          .twin(.pogoStick), .volley(.ball, 4, .confetti, "BOING")),
        S(360, "capyMatcha", .workshop, "Capy Matcha", "Capi matcha",
          "A capybara with a bowl of matcha: the whole desktop calms down.",
          "Un capibara con un cuenco de matcha: todo el escritorio se calma.",
          .styleWears(.capybara, .matchaBowl), .calm(.relax, .sip, .sparkles, "ZEN")),
    ]
}
