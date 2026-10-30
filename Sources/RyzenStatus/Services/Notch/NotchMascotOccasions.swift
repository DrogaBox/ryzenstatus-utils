// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import CoreGraphics

/// Something the Mac or the calendar brings for the companion to show: the
/// CPU boosting, running hot or cold, the battery running out and coming
/// back, the network dropping and returning, and the days of the year it
/// keeps. Pure, so every rule is tested without a window.
enum NotchMascotOccasion: String, CaseIterable, Equatable {
    case boost, cold, hot, lowBattery, charged, offline, online
    case birthday, halloween, christmas, newYear, aprilFools

    /// The arcade marker that floats over it on the desktop.
    var marker: String {
        switch self {
        case .boost: return "MAX BOOST!"
        case .cold: return "BRRR!"
        case .hot: return "HOT!"
        case .lowBattery: return "PLUG ME!"
        case .charged: return "CHARGED!"
        case .offline: return "OFFLINE"
        case .online: return "ONLINE!"
        case .birthday: return "HAPPY BIRTHDAY!"
        case .halloween: return "TRICK OR TREAT"
        case .christmas: return "HO HO HO!"
        case .newYear: return "HAPPY NEW YEAR!"
        case .aprilFools: return "?!"
        }
    }

    /// A shorter one for the closed island, where there is little room.
    var islandMarker: String {
        switch self {
        case .boost: return "BOOST!"
        case .cold: return "BRRR!"
        case .hot: return "HOT!"
        case .lowBattery: return "PLUG ME"
        case .charged: return "CHARGED"
        case .offline: return "OFFLINE"
        case .online: return "ONLINE!"
        case .birthday: return "B-DAY!"
        case .halloween: return "BOO!"
        case .christmas: return "HO HO"
        case .newYear: return "HAPPY NY"
        case .aprilFools: return "?!"
        }
    }

    /// What it puts on for the moment, if it wears things at all.
    var costume: NotchMascotAccessory? {
        switch self {
        case .cold: return .scarf
        case .hot: return .sunglasses
        case .offline: return .gameController
        case .birthday, .newYear: return .partyHat
        case .halloween: return .witchHat
        case .christmas: return .santaHat
        case .boost, .lowBattery, .charged, .online, .aprilFools: return nil
        }
    }

    /// Whether the calendar brings it, rather than the Mac.
    var isDay: Bool {
        switch self {
        case .birthday, .halloween, .christmas, .newYear, .aprilFools: return true
        default: return false
        }
    }

    /// How it shows resting in the closed island: its reactions, a burst
    /// and the marker, on the one it happens to.
    func islandBeats(byLeader: Bool) -> [NotchMascotIslandPlay.Beat] {
        var score = NotchMascotIslandPlay.Score(byLeader: byLeader)
        switch self {
        case .boost:
            score.act(0, starter: .ready)
            score.burst(0.4, .sparkles, onStarter: true)
            score.act(1.2, starter: .flash)
        case .cold:
            score.act(0, starter: .sweat)
            score.burst(0.5, .smoke, onStarter: true)
            score.act(1.4, starter: .hush)
        case .hot:
            score.act(0, starter: .sweat)
            score.act(1.3, starter: .relax)
        case .lowBattery:
            score.act(0, starter: .yawn)
            score.act(1.6, starter: .sweat)
        case .charged:
            score.act(0, starter: .flash)
            score.burst(0.3, .sparkles, onStarter: true)
            score.act(0.9, starter: .celebrate)
        case .offline:
            score.act(0, starter: .confused)
            score.act(1.4, starter: .relax)
        case .online:
            score.act(0, starter: .perk)
            score.act(0.7, starter: .celebrate)
        case .birthday, .newYear:
            score.act(0, starter: .celebrate)
            score.burst(0.3, .confetti, onStarter: true)
            score.act(1.4, starter: .bounce)
        case .halloween:
            score.act(0, starter: .peek)
            score.burst(0.5, .magic, onStarter: true)
            score.act(1.2, starter: .surprised)
        case .christmas:
            score.act(0, starter: .wave)
            score.burst(0.4, .sparkles, onStarter: true)
            score.act(1.3, starter: .love)
        case .aprilFools:
            score.act(0, starter: .confused)
            score.act(1.2, starter: .lookAround)
        }
        score.marker(0.3, islandMarker, onStarter: true)
        return score.beats.sorted { $0.at < $1.at }
    }
}

// MARK: - Watching the Mac

/// What the Mac is doing, as the companion's moments read it, and which of
/// them it brings now. Each moment latches on when its condition starts and
/// off when it has clearly ended, so a reading that hovers about a line
/// brings nothing twice; none comes back within its cooldown.
struct NotchMascotHardwareWatch {
    /// CPU load or package power, as shares, held this long, is a boost.
    static let boostShare = 0.85
    static let boostEnds = 0.6
    static let boostHold: TimeInterval = 20
    /// A CPU this cool, barely working, is cold; warmer than `coldEnds`, not.
    static let coldTemperature = 35.0
    static let coldEnds = 40.0
    static let coldLoad = 0.15
    /// A CPU this hot is hot, until it cools below `hotEnds`.
    static let hotTemperature = 85.0
    static let hotEnds = 78.0
    /// On the battery at or below this, it is running out.
    static let lowBattery = 0.15
    static let batteryFine = 0.2
    /// The network gone this long counts as gone.
    static let offlineHold: TimeInterval = 8
    /// No moment of the Mac's comes back sooner than this.
    static let cooldown: TimeInterval = 20 * 60

    struct Reading {
        var load: Double?
        var temperature: Double?
        var power: Double?
        var battery: Double?
        var onBattery = false
        var online: Bool?
        var loadFollowed = true
        var batteryFollowed = true
        var networkFollowed = true
    }

    private var busySince: TimeInterval?
    private var boosting = false, cold = false, hot = false, low = false
    private var offlineSince: TimeInterval?
    private var offline = false
    private var last: [NotchMascotOccasion: TimeInterval] = [:]

    /// Takes in the Mac's state at `now` and answers the moment it brings, if any.
    mutating func update(_ reading: Reading, now: TimeInterval) -> NotchMascotOccasion? {
        var fresh: [NotchMascotOccasion] = []
        // Battery: running out, and plugged in again after.
        if reading.batteryFollowed, let battery = reading.battery {
            if reading.onBattery, battery <= Self.lowBattery, !low {
                low = true
                fresh.append(.lowBattery)
            } else if low, !reading.onBattery {
                low = false
                fresh.append(.charged)
            } else if low, battery > Self.batteryFine {
                low = false
            }
        } else {
            low = false
        }
        // The network: gone a while, and back.
        if reading.networkFollowed, let online = reading.online {
            if !online {
                if offlineSince == nil { offlineSince = now }
                if !offline, let since = offlineSince, now - since >= Self.offlineHold {
                    offline = true
                    fresh.append(.offline)
                }
            } else {
                offlineSince = nil
                if offline {
                    offline = false
                    fresh.append(.online)
                }
            }
        }
        // The CPU: hot, boosting, cold.
        if reading.loadFollowed {
            if let temperature = reading.temperature {
                if !hot, temperature >= Self.hotTemperature {
                    hot = true
                    fresh.append(.hot)
                } else if hot, temperature < Self.hotEnds {
                    hot = false
                }
                if !cold, temperature <= Self.coldTemperature, (reading.load ?? 1) <= Self.coldLoad {
                    cold = true
                    fresh.append(.cold)
                } else if cold, temperature > Self.coldEnds {
                    cold = false
                }
            }
            let share = max(reading.load ?? 0, reading.power ?? 0)
            if share >= Self.boostShare {
                if busySince == nil { busySince = now }
                if !boosting, let since = busySince, now - since >= Self.boostHold {
                    boosting = true
                    fresh.append(.boost)
                }
            } else {
                busySince = nil
                if boosting, share < Self.boostEnds { boosting = false }
            }
        }
        // The most important one the cooldowns let through.
        let order: [NotchMascotOccasion] = [.charged, .online, .offline, .lowBattery, .hot, .boost, .cold]
        for moment in order where fresh.contains(moment) {
            // Coming back is always worth a cheer: it answers the moment before.
            let paired = moment == .charged || moment == .online
            if !paired, let when = last[moment], now - when < Self.cooldown { continue }
            last[moment] = now
            return moment
        }
        return nil
    }
}

// MARK: - The calendar

enum NotchMascotSpecialDays {
    /// The day `date` is, if one it keeps: your birthday when you gave it,
    /// Halloween, Christmas Eve and Day, New Year's Eve and Day, April Fools'.
    static func moment(on date: Date, birthday: DateComponents?, calendar: Calendar = .current) -> NotchMascotOccasion? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        if let birthday, birthday.month == month, birthday.day == day { return .birthday }
        switch (month, day) {
        case (10, 31): return .halloween
        case (12, 24), (12, 25): return .christmas
        case (12, 31), (1, 1): return .newYear
        case (4, 1): return .aprilFools
        default: return nil
        }
    }

    /// The birthday kept as "MM-dd", if any.
    static func birthday(from text: String?) -> DateComponents? {
        let parts = (text ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        return DateComponents(month: parts[0], day: parts[1])
    }
    /// `date`'s month and day as a birthday is kept.
    static func birthdayText(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 1, parts.day ?? 1)
    }
    /// A date in this year on the birthday kept, for a date picker.
    static func date(fromBirthday text: String, calendar: Calendar = .current) -> Date? {
        guard var parts = birthday(from: text) else { return nil }
        parts.year = calendar.component(.year, from: Date())
        return calendar.date(from: parts)
    }
    /// The first minutes of a new year, for the fireworks.
    static func isNewYearMidnight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return parts.month == 1 && parts.day == 1 && parts.hour == 0 && (parts.minute ?? 99) < 10
    }

    /// A key for `date`'s day, so each day's moment is played once.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// What it says on April Fools' Day, the wrong animal's sound.
    static func foolsCall(for style: NotchMascotStyle) -> String {
        switch style {
        case .dog: return "MEOW?"
        case .cat: return "WOOF?"
        case .frog: return "QUACK?"
        case .mouse: return "ROAR?"
        case .dragon: return "SQUEAK?"
        case .kitsune: return "OINK?"
        case .penguin: return "ROAR?"
        default: return "MOO?"
        }
    }
}

// MARK: - Cravings and tantrums

/// What it longs for now and then, shown in a thought bubble over it.
enum NotchMascotCraving: String, CaseIterable, Equatable {
    case coffee, pizza, ramen, iceCream, moon, ball

    /// By the hour and what it is.
    static func pick(hour: Int, style: NotchMascotStyle, random: Double) -> NotchMascotCraving {
        if style == .dog, random < 0.5 { return .ball }
        // Fried tofu in broth is what a fox spirit dreams of; ice for a penguin.
        if style == .kitsune, random < 0.5 { return .ramen }
        if style == .penguin, random < 0.5 { return .iceCream }
        switch hour {
        case 6..<11: return .coffee
        case 11..<15: return random < 0.5 ? .pizza : .ramen
        case 15..<19: return .iceCream
        case 19..<22: return random < 0.5 ? .ramen : .pizza
        default: return .moon
        }
    }

    /// What flies to it when it is understood.
    var thing: NotchMascotIslandPlay.Thing {
        switch self {
        case .coffee: return .snack(.bobaTea)
        case .pizza: return .cookie
        case .ramen: return .snack(.ramen)
        case .iceCream: return .snack(.iceCream)
        case .moon: return .star
        case .ball: return .ball
        }
    }
}

enum NotchMascotCravings {
    /// At least this long between two, and the chance of one after that
    /// each time it looks for something to do.
    static let interval: TimeInterval = 5 * 60
    static let chance = 0.25
    /// How long it waits to be understood before it throws a little tantrum.
    static let patience: TimeInterval = 10

    static func shouldStart(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }
}

// MARK: - Things dropped on it

enum NotchMascotSnackDrop: Equatable {
    /// Something to eat: it catches it and eats it.
    case food
    /// Something else: it sniffs at it and wonders.
    case other

    private static let foodEmoji: Set<Character> = [
        "🍕", "🍔", "🍟", "🌭", "🍿", "🥐", "🥨", "🥯", "🥞", "🧇", "🧀", "🍗", "🍖", "🥓", "🥪", "🌮", "🌯", "🥗",
        "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🍙", "🍚", "🍘", "🍥", "🥠", "🍡", "🍧", "🍨", "🍦", "🥧", "🧁",
        "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍩", "🍪", "🍯", "🍎", "🍏", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓",
        "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥕", "🌽", "🥔", "🍠", "🥜", "🌰", "🍳", "🥚",
        "☕", "🍵", "🧋", "🥛", "🧃", "🦴", "🐟", "🧆", "🥙", "🫓", "🍞", "🥖", "🫔", "🥘", "🫕", "🥫", "🍤", "🦐"
    ]
    /// Words for food in file names, in the languages the app speaks.
    private static let foodWords = [
        "pizza", "burger", "hamburg", "sushi", "ramen", "noodle", "fideo", "taco", "burrito", "donut",
        "cookie", "galleta", "cake", "pastel", "tarta", "torta", "bread", "croissant", "apple", "manzana",
        "banana", "platano", "plátano", "fruit", "fruta", "candy", "dulce", "caramelo", "chocolate", "ice cream",
        "icecream", "helado", "snack", "food", "comida", "meal", "cheese", "queso", "onigiri", "dumpling",
        "pasta", "spaghetti", "salad", "ensalada", "sandwich", "bocadillo", "fries", "papas", "patatas",
        "coffee", "cafe", "café", "boba", "milk", "leche", "huevo", "chicken", "pollo",
        "steak", "carne", "fish", "pescado", "hueso", "pomme", "gâteau", "gateau", "kuchen", "apfel",
        "brot", "biscotto", "gelato", "bolo", "maçã", "sorvete", "jedlo",
        "jabłko", "ciasto", "jídlo", "яблоко", "торт", "еда", "りんご", "ケーキ", "ラーメン", "寿司", "苹果", "蛋糕",
        "사과", "케이크", "라면", "음식"
    ]

    /// Whether what was dropped — text and file names — is food. Only the
    /// names are read, never a file's contents. Nil when nothing came.
    static func classify(text: String?, fileNames: [String]) -> NotchMascotSnackDrop? {
        let text = text ?? ""
        guard !text.isEmpty || !fileNames.isEmpty else { return nil }
        if text.contains(where: { foodEmoji.contains($0) }) { return .food }
        let names = ([text] + fileNames).map { $0.lowercased() }
        if names.contains(where: { name in foodWords.contains(where: { name.contains($0) }) }) { return .food }
        if fileNames.contains(where: { $0.contains(where: { foodEmoji.contains($0) }) }) { return .food }
        return .other
    }
}

// MARK: - Rock, paper, scissors

enum NotchMascotRoshambo: String, CaseIterable, Equatable {
    case rock, paper, scissors

    enum Outcome: Equatable { case youWin, itWins, tie }

    func beats(_ other: NotchMascotRoshambo) -> Bool {
        switch (self, other) {
        case (.rock, .scissors), (.paper, .rock), (.scissors, .paper): return true
        default: return false
        }
    }

    /// You played `self`; it played `its`.
    func outcome(against its: NotchMascotRoshambo) -> Outcome {
        if self == its { return .tie }
        return beats(its) ? .youWin : .itWins
    }

    static func pick(random: Double) -> NotchMascotRoshambo {
        allCases[min(allCases.count - 1, max(0, Int(random * Double(allCases.count))))]
    }

    /// Gold it pays when you win; only the first few wins a day pay.
    static let prize = 50
    static let paidWinsPerDay = 3
    static func payout(winsToday: Int) -> Int { winsToday < paidWinsPerDay ? prize : 0 }
}

// MARK: - Fishing

enum NotchMascotCatch: String, CaseIterable, Equatable {
    case goldfish, boot, key, pearl

    var marker: String {
        switch self {
        case .goldfish: return "+100"
        case .boot: return "..."
        case .key: return "+50"
        case .pearl: return "+500"
        }
    }

    /// What it pulls out when you help it: mostly a fish, sometimes a boot,
    /// now and then a key or a pearl.
    static func pull(random: Double) -> NotchMascotCatch {
        switch random {
        case ..<0.5: return .goldfish
        case ..<0.75: return .boot
        case ..<0.9: return .key
        default: return .pearl
        }
    }
}

enum NotchMascotFishing {
    /// At least this long between two outings, and the chance of one after.
    static let interval: TimeInterval = 6 * 60
    static let chance = 0.3
    /// How long the bobber waits for a bite, at least and at most.
    static let wait: ClosedRange<TimeInterval> = 4...9
    /// How long you have to help it pull once it bites.
    static let window: TimeInterval = 2.5

    static func shouldStart(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }
}

// MARK: - The pointer as a toy

/// Tickles: the pointer rubbed back and forth over its belly. Counts the
/// turns of direction made over it; enough of them close together tickle.
struct NotchMascotTickleTracker {
    static let turnsNeeded = 6
    static let within: TimeInterval = 2.5
    /// A turn counts after at least this much travel the other way.
    static let travel: CGFloat = 6

    private var lastX: CGFloat?
    private var direction: CGFloat = 0
    private var travelled: CGFloat = 0
    private var turns: [TimeInterval] = []

    mutating func reset() {
        lastX = nil; direction = 0; travelled = 0; turns.removeAll()
    }

    /// The pointer at `x`, over its belly or not, at `time`. True when that
    /// makes it a tickle, which starts the count again.
    mutating func track(x: CGFloat, over: Bool, time: TimeInterval) -> Bool {
        guard over else { reset(); return false }
        defer { lastX = x }
        guard let lastX else { return false }
        let delta = x - lastX
        guard delta != 0 else { return false }
        let way: CGFloat = delta > 0 ? 1 : -1
        if way == direction {
            travelled += abs(delta)
        } else {
            if direction != 0, travelled >= Self.travel { turns.append(time) }
            direction = way
            travelled = abs(delta)
        }
        turns.removeAll { time - $0 > Self.within }
        guard turns.count >= Self.turnsNeeded else { return false }
        reset()
        return true
    }
}

enum NotchMascotTrampoline {
    /// Falling this fast at least, it can bounce.
    static let fallSpeed: CGFloat = 250
    /// How far under its feet, and above them, the pointer catches it.
    static let below: CGFloat = 26
    static let above: CGFloat = 8
    /// The speed a bounce sends it back up with, at least.
    static let lift: CGFloat = 1250

    /// Whether the pointer at `pointer` catches its feet at `feet`, `width`
    /// wide, falling at `velocityY`.
    static func bounces(feet: CGPoint, width: CGFloat, velocityY: CGFloat, pointer: CGPoint) -> Bool {
        velocityY <= -fallSpeed && abs(pointer.x - feet.x) <= width / 2
            && pointer.y <= feet.y + above && pointer.y >= feet.y - below
    }

    /// The speed up it leaves the pointer with.
    static func bounce(velocityY: CGFloat) -> CGFloat { max(lift, -velocityY * 1.05) }

    /// Bounces in a row before it lands whatever the pointer does: each one
    /// falls back faster, so a pointer left in place would never let go.
    static let most = 5

    /// A pointer resting just under a window's top edge sits on that window's
    /// title bar, where the companion lands when it climbs; that is not a
    /// pointer held out to catch it.
    static func onLedge(pointer: CGPoint, ledges: [NotchMascotLedges.Ledge]) -> Bool {
        ledges.contains {
            pointer.x >= $0.minX && pointer.x <= $0.maxX
                && pointer.y <= $0.y + above && pointer.y >= $0.y - below * 2
        }
    }
}

enum NotchMascotHideAndSeek {
    /// Left to itself this long, it gets bored and hides.
    static let boredAfter: TimeInterval = 20 * 60
    /// How long it stays hidden before it gives up and comes out.
    static let gives: TimeInterval = 60
    /// How deep it hides: all but the top of its head.
    static let depth: CGFloat = 0.84
}

enum NotchMascotLaser {
    /// How long the laser plays before it goes out by itself.
    static let length: TimeInterval = 30
    /// How often it thinks again where to run or leap.
    static let think: TimeInterval = 0.35
}
// MARK: - Dancing alone
/// The moves the dancers make on their own, out on the desktop, and the
/// routines of the kitsune and the penguin, played the same way.
enum NotchMascotSoloDance: String, CaseIterable, Equatable {
    // The swan.
    case bourree, portDeBras, dyingSwan
    // The ballerina.
    case arabesque, fouettes, grandJete, reverence
    // The danseur.
    case pirouettes, sautDeBasque, doubleTour, cabriole
    // The contemporary dancer.
    case floorwork, contractRelease, fallRecovery, handstand
    // The kitsune: foxfire, a fox's high pounce, and the leaf trick.
    case foxfire, pounce, leafTrick
    // The penguin: a belly slide, a try at flying, and a pebble for you.
    case bellySlide, flightAttempt, pebbleGift
    /// At least this long between two, and the chance of one after.
    static let interval: TimeInterval = 4 * 60
    static let chance = 0.35
    /// Fresh rosin keeps its grip this long.
    static let rosinLasts: TimeInterval = 15
    /// Idle this long, a dancer rests with an ice pack instead.
    static let restAfterIdle: TimeInterval = 3 * 60
    static func moves(for style: NotchMascotStyle) -> [NotchMascotSoloDance] {
        switch style {
        case .swan: return [.bourree, .portDeBras, .dyingSwan]
        case .ballerina: return [.arabesque, .fouettes, .grandJete, .reverence, .bourree]
        case .danseur: return [.pirouettes, .sautDeBasque, .doubleTour, .cabriole]
        case .contemporary: return [.floorwork, .contractRelease, .fallRecovery, .handstand]
        case .kitsune: return [.foxfire, .pounce, .leafTrick]
        case .penguin: return [.bellySlide, .flightAttempt, .pebbleGift]
        default: return []
        }
    }
    /// Only the dancers rest with an ice pack after a long rehearsal.
    static func restsWithIce(_ style: NotchMascotStyle) -> Bool {
        [.swan, .ballerina, .danseur, .contemporary].contains(style)
    }
    static func shouldStart(since: TimeInterval, random: Double) -> Bool {
        since >= interval && random < chance
    }
    var marker: String {
        switch self {
        case .bourree: return "BOURREE"
        case .portDeBras: return "PORT DE BRAS"
        case .dyingSwan: return "CAMBRE"
        case .arabesque: return "ARABESQUE"
        case .fouettes: return "32 FOUETTES!"
        case .grandJete: return "GRAND JETE!"
        case .reverence: return "REVERENCE"
        case .pirouettes: return "A LA SECONDE!"
        case .sautDeBasque: return "SAUT DE BASQUE"
        case .doubleTour: return "DOUBLE TOUR!"
        case .cabriole: return "CABRIOLE"
        case .floorwork: return "FLOORWORK"
        case .contractRelease: return "RELEASE!"
        case .fallRecovery: return "RECOVERY"
        case .handstand: return "HANDSTAND"
        case .foxfire: return "KITSUNEBI"
        case .pounce: return "POUNCE!"
        case .leafTrick: return "POOF!"
        case .bellySlide: return "WHEEE!"
        case .flightAttempt: return "FLAP FLAP!"
        case .pebbleGift: return "FOR YOU ♥"
        }
    }
    /// A great jump, which wants fresh rosin under the feet first.
    var leaps: Bool { [.grandJete, .sautDeBasque, .doubleTour, .cabriole].contains(self) }
    /// A run of turns, which slips on a window's glass without rosin.
    var turns: Bool { [.fouettes, .pirouettes].contains(self) }
    /// How long the move takes, near enough, after any rosin.
    var length: TimeInterval {
        switch self {
        case .bourree: return 4
        case .portDeBras, .dyingSwan, .floorwork, .handstand: return 4
        case .arabesque, .reverence: return 3
        case .fouettes: return 5.5
        case .pirouettes: return 6.5
        case .grandJete, .sautDeBasque, .doubleTour, .contractRelease, .fallRecovery: return 2.6
        case .cabriole: return 2.4
        case .foxfire, .flightAttempt: return 4.2
        case .pounce: return 2.8
        case .leafTrick: return 3.6
        case .bellySlide: return 3.8
        case .pebbleGift: return 3.2
        }
    }
}
