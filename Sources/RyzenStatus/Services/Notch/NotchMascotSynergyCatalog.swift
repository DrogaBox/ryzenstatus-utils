// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The twelve families the combos are grouped in.
enum SynergyCategory: Int, CaseIterable, Identifiable {
    case wonderBoy = 1, combat, magic, tavern, music, rogues, sciFi, twin, species, quests, curiosities, mascots

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
    /// Played on demand: from the Pocket Card, a click or a door.
    case quest

    /// A pair of things worn beats one worn, which beats one figure alone.
    var specificity: Int {
        switch self {
        case .pair, .twin, .styleWears: return 3
        case .styles: return 2
        case .wears, .style: return 1
        case .quest: return 0
        }
    }

    func matches(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                 leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle) -> Bool {
        switch self {
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
    /// thing named does, and with nothing to tell them apart, `fallback`.
    func starterIsLeader(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                         leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle, fallback: Bool) -> Bool {
        switch self {
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
    /// Its place in the catalog, 1...135.
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
                 leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle) -> Bool {
        match.matches(leaderWears: leaderWears, friendWears: friendWears,
                      leaderStyle: leaderStyle, friendStyle: friendStyle)
    }

    func starterIsLeader(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                         leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle, fallback: Bool) -> Bool {
        match.starterIsLeader(leaderWears: leaderWears, friendWears: friendWears,
                              leaderStyle: leaderStyle, friendStyle: friendStyle, fallback: fallback)
    }

    /// The play it makes, started by the companion or by its friend.
    func play(starterIsLeader: Bool) -> NotchMascotIslandPlay {
        var score = NotchMascotIslandPlay.Score(byLeader: starterIsLeader)
        script.write(into: &score)
        return NotchMascotIslandPlay(kind: .synergy(id), beats: score.beats)
    }

    /// Its name in `language`: Spanish where the app is, English elsewhere.
    func title(in language: AppLanguage) -> String { language == .es ? nameES : name }

    func detail(in language: AppLanguage) -> String { language == .es ? descriptionES : description }
}

/// The hundred and ninety-eight combos, and how a pair finds theirs.
enum NotchMascotSynergyCatalog {
    private static func S(_ number: Int, _ id: String, _ category: SynergyCategory, _ name: String, _ nameES: String,
                          _ description: String, _ descriptionES: String, _ match: NotchMascotSynergyMatch,
                          _ script: NotchMascotSynergyScript) -> NotchMascotSynergy {
        NotchMascotSynergy(number: number, id: id, category: category, name: name, nameES: nameES,
                           description: description, descriptionES: descriptionES, match: match, script: script)
    }

    static let all: [NotchMascotSynergy] = wonderBoy + combat + magic + tavern + music + rogues + sciFi + twin
        + species + quests + curiosities + mascots

    static var total: Int { all.count }

    private static let byID: [String: NotchMascotSynergy] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func synergy(id: String) -> NotchMascotSynergy? { byID[id] }

    static func synergies(in category: SynergyCategory) -> [NotchMascotSynergy] {
        all.filter { $0.category == category }
    }

    /// The combos this pair can play: when some are made of a pair of things
    /// worn, only those, otherwise all that fit. Never the quests.
    static func candidates(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                           leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle) -> [NotchMascotSynergy] {
        let fits = all.filter {
            $0.matches(leaderWears: leaderWears, friendWears: friendWears,
                       leaderStyle: leaderStyle, friendStyle: friendStyle)
        }
        guard let best = fits.map({ $0.match.specificity }).max() else { return [] }
        return best >= 3 ? fits.filter { $0.match.specificity >= 3 } : fits
    }

    /// The combo that best fits this pair, if any.
    static func resolveSynergy(leaderWears: NotchMascotAccessory, friendWears: NotchMascotAccessory,
                               leaderStyle: NotchMascotStyle, friendStyle: NotchMascotStyle) -> NotchMascotSynergy? {
        candidates(leaderWears: leaderWears, friendWears: friendWears,
                   leaderStyle: leaderStyle, friendStyle: friendStyle).first
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
}
