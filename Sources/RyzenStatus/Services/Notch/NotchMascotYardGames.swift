// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import CoreGraphics

/// The yard games played with the companion out on the desktop, picked from
/// its "Play" menu: fetch, the shell game, whack-a-mole, tic-tac-toe, Simon
/// says, bubbles to pop, a path to follow and target practice. What each one
/// pays and every rule they keep are here, pure, so they are tested without
/// a window; `NotchMascotYardPlay` plays them.
enum NotchMascotYardGame: String, CaseIterable, Equatable {
    case fetch, shells, moles, ticTacToe, simon, bubbles, path, target

    /// The SF Symbol by its entry in the menu.
    var symbol: String {
        switch self {
        case .fetch: return "tennisball"
        case .shells: return "cup.and.saucer"
        case .moles: return "hammer"
        case .ticTacToe: return "number"
        case .simon: return "circle.grid.2x2"
        case .bubbles: return "bubbles.and.sparkles"
        case .path: return "scribble.variable"
        case .target: return "target"
        }
    }

    /// The most gold one game pays, and how many games a day pay at all.
    var prize: Int {
        switch self {
        case .fetch: return 40
        case .shells: return 25
        case .moles: return 45
        case .ticTacToe: return 60
        case .simon: return 50
        case .bubbles: return 40
        case .path: return 15
        case .target: return 45
        }
    }
    var paidPerDay: Int {
        switch self {
        case .shells: return 6
        case .path: return 4
        default: return 3
        }
    }

    /// Every click while it plays is part of the game, even one on the
    /// companion, which then cannot be grabbed: it is the mole, the one in
    /// the way of the target, the one on the pads or the one blowing the
    /// bubbles that float up over it.
    var takesEveryClick: Bool {
        switch self {
        case .moles, .simon, .target, .bubbles: return true
        default: return false
        }
    }
}

extension DefaultsKey {
    /// String "day|game:count|game:count", the yard games that paid today.
    static let notchMascotYardPrizes = "notchMascotYardPrizes"
}

// MARK: - Gold

/// What the yard games pay, a few games a day each, as rock, paper,
/// scissors does: a game past today's paid ones is played for fun.
enum NotchMascotYardPrizes {
    /// How many of `game` paid on `today`, in `saved` as kept.
    static func paid(_ game: NotchMascotYardGame, in saved: String?, today: String) -> Int {
        let parts = (saved ?? "").split(separator: "|").map(String.init)
        guard parts.first == today else { return 0 }
        for part in parts.dropFirst() {
            let pair = part.split(separator: ":")
            if pair.count == 2, String(pair[0]) == game.rawValue { return Int(pair[1]) ?? 0 }
        }
        return 0
    }

    /// `saved` with one more paid game of `game` on `today`; another day's
    /// counts are dropped.
    static func recording(_ game: NotchMascotYardGame, in saved: String?, today: String) -> String {
        var counts = NotchMascotYardGame.allCases.map { ($0, paid($0, in: saved, today: today)) }
        if let index = counts.firstIndex(where: { $0.0 == game }) { counts[index].1 += 1 }
        let kept = counts.filter { $0.1 > 0 }.map { "\($0.0.rawValue):\($0.1)" }
        return ([today] + kept).joined(separator: "|")
    }

    /// The gold `amount` of `game` is worth now: all of it, up to the game's
    /// prize, while today's paid games last, and nothing after.
    static func payout(_ game: NotchMascotYardGame, amount: Int, paidToday: Int) -> Int {
        paidToday < game.paidPerDay ? min(game.prize, max(0, amount)) : 0
    }

    /// Pays `amount` of `game` in gold, counting it against today's; the gold paid.
    @discardableResult
    static func pay(_ game: NotchMascotYardGame, amount: Int, defaults: UserDefaults = .standard,
                    date: Date = Date()) -> Int {
        guard amount > 0 else { return 0 }
        let today = NotchMascotSpecialDays.key(for: date)
        let saved = defaults.string(forKey: DefaultsKey.notchMascotYardPrizes)
        let gold = payout(game, amount: amount, paidToday: paid(game, in: saved, today: today))
        guard gold > 0 else { return 0 }
        defaults.set(recording(game, in: saved, today: today), forKey: DefaultsKey.notchMascotYardPrizes)
        NotchMascotRPG.collect(gold: gold)
        return gold
    }
}

// MARK: - Moving about

enum NotchMascotYardMoves {
    /// A hop from `x` that lands near `target`, `height` points up at its
    /// peak: the speeds to give it and how long it is in the air. It slides
    /// a little once down, which the sideways speed allows for.
    static func hop(from x: CGFloat, to target: CGFloat, height: CGFloat) -> (dx: CGFloat, dy: CGFloat, flight: TimeInterval) {
        let gravity = NotchMascotRoam.gravity
        let dy = sqrt(2 * gravity * max(20, height))
        let flight = 2 * dy / gravity
        let slide: CGFloat = 0.13
        return ((target - x) / (flight + slide), dy, TimeInterval(flight))
    }

    /// `x` kept on `floor`.
    static func clamp(_ x: CGFloat, to floor: ClosedRange<CGFloat>) -> CGFloat {
        min(floor.upperBound, max(floor.lowerBound, x))
    }

    /// `count` places `spacing` apart, centred as near `center` as `floor`
    /// lets them be; fewer when the floor is too short for all of them.
    static func row(count: Int, spacing: CGFloat, around center: CGFloat, on floor: ClosedRange<CGFloat>) -> [CGFloat] {
        let room = floor.upperBound - floor.lowerBound
        let fits = max(1, min(count, Int(room / max(1, spacing)) + 1))
        let width = CGFloat(fits - 1) * spacing
        let start = min(floor.upperBound - width, max(floor.lowerBound, center - width / 2))
        return (0..<fits).map { start + CGFloat($0) * spacing }
    }
}

// MARK: - Fetch

/// The ball thrown for fetch: it flies, bounces off the floor, the sides and
/// the top of the screen's usable area, rolls and comes to rest.
struct NotchMascotYardBall: Equatable {
    static let gravity: CGFloat = 2000
    static let bounce: CGFloat = 0.58
    static let wallBounce: CGFloat = 0.6
    /// Speed kept every 16 ms rolling.
    static let rolling: CGFloat = 0.96
    static let restSpeed: CGFloat = 18
    static let fastest: CGFloat = 3000
    /// Throws it fetches before it is tired and happy.
    static let throwsBeforeTired = 5

    var position: CGPoint
    var velocity = CGVector.zero
    var resting = true

    /// On by `dt` seconds in `area` with `radius`; true when it came to rest.
    mutating func step(by dt: TimeInterval, in area: CGRect, radius: CGFloat) -> Bool {
        guard !resting, dt > 0 else { return false }
        let dt = CGFloat(min(dt, 0.05))
        let frames = dt * 1000 / 16
        let floor = area.minY + radius
        let onFloor = position.y <= floor + 0.5 && abs(velocity.dy) < 60
        if onFloor {
            position.y = floor
            velocity.dy = 0
            velocity.dx *= pow(Self.rolling, frames)
        } else {
            velocity.dy -= Self.gravity * dt
        }
        position.x += velocity.dx * dt
        position.y += velocity.dy * dt
        if position.x < area.minX + radius {
            position.x = area.minX + radius
            velocity.dx = abs(velocity.dx) * Self.wallBounce
        } else if position.x > area.maxX - radius {
            position.x = area.maxX - radius
            velocity.dx = -abs(velocity.dx) * Self.wallBounce
        }
        if position.y > area.maxY - radius {
            position.y = area.maxY - radius
            velocity.dy = -abs(velocity.dy) * Self.wallBounce
        }
        if position.y < floor {
            position.y = floor
            velocity.dy = abs(velocity.dy) * Self.bounce
            velocity.dx *= 0.85
            if velocity.dy < 90 { velocity.dy = 0 }
        }
        if position.y <= floor + 0.5, velocity.dy == 0, abs(velocity.dx) < Self.restSpeed {
            velocity = .zero
            resting = true
            return true
        }
        return false
    }

    /// Where along the floor it comes down from here, near enough: the side
    /// walls are left out, as it would think.
    func landing(in area: CGRect, radius: CGFloat) -> CGFloat {
        let height = max(0, position.y - (area.minY + radius))
        let g = Self.gravity
        let time = (velocity.dy + sqrt(velocity.dy * velocity.dy + 2 * g * height)) / g
        return min(area.maxX - radius, max(area.minX + radius, position.x + velocity.dx * time))
    }

    /// A fling from the pointer's last moves, as fast as it may go.
    static func fling(_ velocity: CGVector) -> CGVector {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > fastest else { return velocity }
        return CGVector(dx: velocity.dx / speed * fastest, dy: velocity.dy / speed * fastest)
    }
}

// MARK: - The shell game

enum NotchMascotShellGame {
    static let cups = 3
    static let rounds = 3

    /// How many times it swaps two cups in `round`, counted from zero.
    static func swaps(in round: Int) -> Int { 4 + round * 3 }

    /// How long one swap takes in `round`: faster each round.
    static func swapLength(in round: Int) -> TimeInterval { max(0.2, 0.55 - Double(round) * 0.14) }

    /// The swaps of `round`, each two different places, never the same pair
    /// twice running.
    static func shuffle(round: Int, random: () -> Double) -> [(Int, Int)] {
        let pairs = [(0, 1), (1, 2), (0, 2)]
        var picked: [(Int, Int)] = []
        var last = -1
        for _ in 0..<swaps(in: round) {
            var index = min(pairs.count - 1, Int(random() * Double(pairs.count)))
            if index == last { index = (index + 1) % pairs.count }
            last = index
            picked.append(random() < 0.5 ? pairs[index] : (pairs[index].1, pairs[index].0))
        }
        return picked
    }

    /// Where each cup is after `swaps`, as the cup at each place.
    static func places(after swaps: [(Int, Int)], from start: [Int] = [0, 1, 2]) -> [Int] {
        var places = start
        for (a, b) in swaps { places.swapAt(a, b) }
        return places
    }
}

// MARK: - Whack-a-mole

enum NotchMascotWhackAMole {
    static let holes = 5
    /// How many times it pops up, and how long the game lasts at most.
    static let pops = 22
    static let length: TimeInterval = 32
    /// Hits in a row that make it angry.
    static let angryAfter = 3
    /// The score from which it pays, and three gold a bonk.
    static let paysFrom = 6
    static func gold(for score: Int) -> Int { score >= paysFrom ? score * 3 : 0 }

    /// How long it stays up on pop `index`: less each time, and less again
    /// once it is angry.
    static func upTime(pop index: Int, angry: Bool) -> TimeInterval {
        let base = max(0.55, 1.25 - Double(index) * 0.035)
        return angry ? base * 0.78 : base
    }

    /// The next hole, never the one it just left.
    static func nextHole(after current: Int?, count: Int, random: Double) -> Int {
        guard count > 1 else { return 0 }
        let choices = (0..<count).filter { $0 != current }
        return choices[min(choices.count - 1, max(0, Int(random * Double(choices.count))))]
    }
}

// MARK: - Tic-tac-toe

enum NotchMascotTicTacToe {
    enum Mark: Equatable { case yours, its }
    typealias Board = [Mark?]

    static let empty: Board = Array(repeating: nil, count: 9)
    static let lines: [[Int]] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    /// Who has three in a row, and which row.
    static func winner(of board: Board) -> (mark: Mark, line: [Int])? {
        for line in lines {
            if let mark = board[line[0]], board[line[1]] == mark, board[line[2]] == mark { return (mark, line) }
        }
        return nil
    }

    static func isFull(_ board: Board) -> Bool { !board.contains(where: { $0 == nil }) }

    /// The cell that completes a row of `mark`, if one does.
    static func finishing(_ mark: Mark, on board: Board) -> Int? {
        for line in lines {
            let marks = line.map { board[$0] }
            if marks.filter({ $0 == mark }).count == 2, let gap = line.first(where: { board[$0] == nil }) { return gap }
        }
        return nil
    }

    /// Its move: decent, but it can be beaten. It mostly takes a win it
    /// sees, often blocks yours, likes the middle and the corners, and now
    /// and then simply does not see something.
    static func move(on board: Board, random: () -> Double) -> Int? {
        let free = board.indices.filter { board[$0] == nil }
        guard !free.isEmpty else { return nil }
        if let win = finishing(.its, on: board), random() < 0.9 { return win }
        if let block = finishing(.yours, on: board), random() < 0.72 { return block }
        if board[4] == nil, random() < 0.65 { return 4 }
        let corners = [0, 2, 6, 8].filter { board[$0] == nil }
        if !corners.isEmpty, random() < 0.6 {
            return corners[min(corners.count - 1, Int(random() * Double(corners.count)))]
        }
        return free[min(free.count - 1, Int(random() * Double(free.count)))]
    }
}

// MARK: - Simon says

enum NotchMascotSimonSays {
    static let pads = 4
    /// Rounds to the end, the sequence growing by one each.
    static let rounds = 10
    /// How long it waits for each of your steps before it calls time.
    static let patience: TimeInterval = 7
    /// How long one step of the sequence takes it to show, by round from zero.
    static func step(in round: Int) -> TimeInterval { max(0.5, 0.78 - Double(round) * 0.03) }
    /// Six gold a round you repeated, from three rounds.
    static func gold(forRounds rounds: Int) -> Int { rounds >= 3 ? rounds * 6 : 0 }

    /// The sequence one longer, never three of a pad running.
    static func grown(_ sequence: [Int], random: Double) -> [Int] {
        var pad = min(pads - 1, max(0, Int(random * Double(pads))))
        if sequence.count >= 2, sequence.suffix(2).allSatisfy({ $0 == pad }) { pad = (pad + 1) % pads }
        return sequence + [pad]
    }
}

// MARK: - Bubbles

enum NotchMascotBubblePop {
    /// How long it blows bubbles.
    static let length: TimeInterval = 20
    static let interval: ClosedRange<TimeInterval> = 0.42...0.8
    /// How long a bubble lasts before it bursts on its own.
    static let lifetime: ClosedRange<TimeInterval> = 5.5...8.5
    static let goldenChance = 0.1
    static func worth(golden: Bool) -> Int { golden ? 5 : 1 }
    /// Two gold a point, from five points.
    static func gold(for score: Int) -> Int { score >= 5 ? score * 2 : 0 }
}

// MARK: - A path to follow

enum NotchMascotYardPath {
    /// What it does to follow a stretch of the line: walk along the floor
    /// to `x`, or hop over to it as high as the line went.
    enum Beat: Equatable {
        case walk(to: CGFloat)
        case hop(to: CGFloat, height: CGFloat)
    }

    /// Paths it follows before it bows out, and how long it waits for another.
    static let paths = 3
    static let waits: TimeInterval = 12
    static let gold = 15

    /// The line's length.
    static func length(of points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// The beats that follow `points`, a line drawn over the floor at
    /// `ground`, for a companion `size` tall on `floor`: the line split
    /// where it turns back and into stretches a few of its sizes long, each
    /// stretch walked when it stays low and hopped when it rises above its
    /// head, at most `most` of them.
    static func beats(along points: [CGPoint], ground: CGFloat, size: CGFloat, floor: ClosedRange<CGFloat>,
                      most: Int = 14) -> [Beat] {
        guard let first = points.first else { return [] }
        let turn = max(8, size * 0.4)
        let longest = max(40, size * 4)
        let low = size * 1.2
        var beats: [Beat] = []
        var start = first, end = first
        var direction: CGFloat = 0
        var peak = first.y
        func close() {
            let x = NotchMascotYardMoves.clamp(end.x, to: floor)
            let height = peak - ground
            guard abs(end.x - start.x) >= 2 || height > low else { return }
            beats.append(height > low ? .hop(to: x, height: min(height - size * 0.3, size * 6)) : .walk(to: x))
            start = end
            peak = end.y
        }
        for point in points.dropFirst() {
            let dx = point.x - end.x
            if dx != 0 {
                let way: CGFloat = dx > 0 ? 1 : -1
                // Turned back after going far enough one way: that stretch is a beat.
                if direction != 0, way != direction, abs(end.x - start.x) >= turn { close() }
                direction = way
            }
            end = point
            peak = max(peak, point.y)
            if abs(end.x - start.x) >= longest { close() }
        }
        close()
        return Array(beats.prefix(most))
    }
}

// MARK: - Target practice

enum NotchMascotTargetPractice {
    static let throwsAllowed = 10
    /// How the throw went, and the points it scores.
    enum Hit: Equatable {
        case bullseye, ring, companion, miss
        var points: Int {
            switch self {
            case .bullseye: return 3
            case .ring: return 1
            case .companion, .miss: return 0
            }
        }
    }

    /// A throw landing `distance` from the target's middle, `radius` round,
    /// and whether it hit the companion holding it instead.
    static func hit(distance: CGFloat, radius: CGFloat, onCompanion: Bool) -> Hit {
        if distance <= radius * 0.34 { return .bullseye }
        if distance <= radius { return .ring }
        return onCompanion ? .companion : .miss
    }

    /// Three gold a point, from ten points.
    static func gold(for score: Int) -> Int { score >= 10 ? score * 3 : 0 }

    /// How far the target is held off its hand at `time`: it bobs up and
    /// down and sways side to side, faster as the throws run out.
    static func sway(at time: TimeInterval, size: CGFloat, thrown: Int) -> CGVector {
        let speed = 1 + Double(thrown) * 0.12
        return CGVector(dx: CGFloat(sin(time * 1.7 * speed)) * size * 0.35,
                        dy: CGFloat(sin(time * 2.3 * speed + 0.6)) * size * 0.55)
    }
}
