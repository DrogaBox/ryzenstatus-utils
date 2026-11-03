// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

// The yard games played at a table, as it were: the shell game, tic-tac-toe
// and Simon says. The ones that run about are in NotchMascotYardPlays.

// MARK: - The shell game

/// Three cups on the floor and a coin under one. It shows the coin, shuffles
/// the cups, faster each round, and you click the one you think hides it: a
/// win pays and leaves it red in the face, a miss gets its smuggest face.
final class NotchMascotShellPlay: NotchMascotYardPlay {
    private var cups: [CALayer] = []
    private var slots: [CGFloat] = []
    /// The cup at each place.
    private var places = [0, 1, 2]
    private let coinCup = 1
    private var coin: CALayer?
    private var round = 0
    private var picking = false
    private var cupWidth: CGFloat = 40
    private var lift: CGFloat { cupWidth * 0.95 }

    init(player: NotchMascotDesktop) { super.init(game: .shells, player: player) }

    override func begin() {
        cupWidth = max(34, size * 0.8)
        let spacing = cupWidth * 1.45
        let room = (yard.minX + cupWidth)...max(yard.minX + cupWidth, yard.maxX - cupWidth)
        slots = NotchMascotYardMoves.row(count: NotchMascotShellGame.cups, spacing: spacing,
                                         around: feet.x + way * (size * 0.7 + spacing * 1.4), on: room)
        guard slots.count == NotchMascotShellGame.cups, let back else {
            finish(after: 0)
            return
        }
        // It stands beside the cups, not over them.
        let near = way > 0 ? slots[0] - spacing : slots[slots.count - 1] + spacing
        let far = way > 0 ? slots[slots.count - 1] + spacing : slots[0] - spacing
        let stand = floor.contains(near) ? near : (floor.contains(far) ? far : feet.x)
        if abs(stand - feet.x) > 2 { stroll(to: stand, pace: 2.4) }
        let coin = NotchMascotYardGameArt.coin(radius: cupWidth * 0.22)
        coin.position = onBack(CGPoint(x: slots[1], y: ground + cupWidth * 0.24))
        coin.opacity = 0
        coin.zPosition = -1
        back.addSublayer(coin)
        self.coin = coin
        for (index, x) in slots.enumerated() {
            let cup = NotchMascotYardGameArt.cup(width: cupWidth)
            cup.position = onBack(CGPoint(x: x, y: ground))
            NotchMascotYardGameArt.appear(cup, in: back)
            cups.append(cup)
            sound(.pop, at: x, after: Double(index) * 0.1)
        }
        face(.mischievous)
        marker("WATCH!")
        later(0.8) { [weak self] in
            guard let self else { return }
            self.look(toward: self.slots[1])
            self.raise(place: 1)
            self.showCoin(at: 1)
        }
        later(2.0) { [weak self] in self?.lowerAll() }
        later(2.5) { [weak self] in self?.shuffle() }
    }

    private func raise(place: Int) {
        let cup = cups[places[place]]
        move(cup, to: CGPoint(x: slots[place], y: ground + lift), over: 0.22)
        sound(.whoosh, at: slots[place])
    }

    private func lowerAll() {
        for (place, cupIndex) in places.enumerated() {
            move(cups[cupIndex], to: CGPoint(x: slots[place], y: ground), over: 0.2)
        }
        guard let coin else { return }
        let hide = CABasicAnimation(keyPath: "opacity")
        hide.fromValue = coin.opacity
        hide.toValue = 0
        hide.duration = 0.15
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coin.opacity = 0
        CATransaction.commit()
        coin.add(hide, forKey: "hide")
    }

    private func showCoin(at place: Int) {
        guard let coin else { return }
        NotchMascotYardGameArt.place(coin, at: onBack(CGPoint(x: slots[place], y: ground + cupWidth * 0.24)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coin.opacity = 1
        CATransaction.commit()
    }

    private func move(_ cup: CALayer, to point: CGPoint, over length: TimeInterval) {
        let from = cup.presentation()?.position ?? cup.position
        let to = onBack(point)
        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: from)
        slide.toValue = NSValue(point: to)
        slide.duration = length
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        NotchMascotYardGameArt.place(cup, at: to)
        cup.add(slide, forKey: "move")
    }

    /// The swaps of this round, one after another, then your pick.
    private func shuffle() {
        guard !isOver else { return }
        picking = false
        let swaps = NotchMascotShellGame.shuffle(round: round, random: { Double.random(in: 0..<1) })
        let length = NotchMascotShellGame.swapLength(in: round)
        face(.mischievous)
        if round > 0 { marker("FASTER!") }
        player?.sway(amplitude: 0.12, speed: 22, duration: Double(swaps.count) * length)
        for (index, swap) in swaps.enumerated() {
            later(Double(index) * (length + 0.04)) { [weak self] in self?.swap(swap.0, swap.1, over: length) }
        }
        later(Double(swaps.count) * (length + 0.04) + 0.2) { [weak self] in
            guard let self, !self.isOver else { return }
            self.picking = true
            self.face(.smug)
            self.marker("PICK ONE!")
            self.noteActivity()
        }
    }

    /// The cups at `a` and `b` change places, one hopping over the other.
    private func swap(_ a: Int, _ b: Int, over length: TimeInterval) {
        let over = cups[places[a]], under = cups[places[b]]
        arc(over, from: slots[a], to: slots[b], height: cupWidth * 0.7, over: length)
        arc(under, from: slots[b], to: slots[a], height: 0, over: length)
        places.swapAt(a, b)
        if Bool.random() { sound(.whoosh, at: (slots[a] + slots[b]) / 2) }
    }

    private func arc(_ cup: CALayer, from: CGFloat, to: CGFloat, height: CGFloat, over length: TimeInterval) {
        let start = onBack(CGPoint(x: from, y: ground)), end = onBack(CGPoint(x: to, y: ground))
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: start.y + height * 2))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = length
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // The one hopping over is drawn in front of the one sliding under.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cup.zPosition = height > 0 ? 1 : 0
        CATransaction.commit()
        NotchMascotYardGameArt.place(cup, at: end)
        cup.add(move, forKey: "move")
    }

    override func pressed(at point: CGPoint) {
        guard picking else { return }
        guard let place = slots.indices.first(where: { abs(point.x - slots[$0]) <= cupWidth * 0.6 }),
              point.y >= ground - 4, point.y <= ground + cupWidth * 1.25
        else { return }
        picking = false
        raise(place: place)
        if places[place] == coinCup {
            showCoin(at: place)
            won()
        } else {
            missed()
        }
    }

    private func won() {
        round += 1
        face(.embarrassed, for: 1.8)
        react(.surprised)
        cheer(big: true)
        later(0.3) { [weak self] in self?.payOut(self?.game.prize ?? 0, instead: "LUCKY!") }
        later(1.0) { [weak self] in self?.marker("HOW?!") }
        guard round < NotchMascotShellGame.rounds else {
            later(2.0) { [weak self] in
                guard let self else { return }
                self.face(.starstruck)
                self.react(.love)
                self.marker("CHAMP!")
                self.burst(.confetti)
            }
            finish(after: 4.4)
            return
        }
        later(2.3) { [weak self] in self?.lowerAll() }
        later(2.9) { [weak self] in self?.shuffle() }
    }

    private func missed() {
        marker("NOPE!")
        later(0.8) { [weak self] in
            guard let self, let at = self.places.firstIndex(of: self.coinCup) else { return }
            self.raise(place: at)
            self.showCoin(at: at)
            self.face(.smug)
            self.react(.celebrate)
            self.marker("HEHE!")
            self.sound(.giggle)
            self.spin(turns: 1, duration: 0.6)
        }
        // And the coin is its own now.
        later(2.0) { [weak self] in
            guard let self, let coin = self.coin else { return }
            self.face(.greedy)
            self.marker("MINE!")
            self.sound(.coin)
            NotchMascotYardGameArt.fadeAway(coin, over: 0.4)
        }
        finish(after: 3.8)
    }
}

// MARK: - Tic-tac-toe

/// A small board beside it. You are X and go first; it thinks a moment
/// before each move and plays a decent game that can be beaten. It
/// celebrates a win, cries or stamps its feet at a loss, and is embarrassed
/// by a draw.
final class NotchMascotTicTacToePlay: NotchMascotYardPlay {
    private var board = NotchMascotTicTacToe.empty
    private var card: CALayer?
    private var span: CGFloat = 140
    private var frame = CGRect.zero
    private var yourTurn = false

    init(player: NotchMascotDesktop) { super.init(game: .ticTacToe, player: player) }

    override func begin() {
        span = max(132, min(210, size * 2.9))
        let x = inYard(feet.x + way * (size * 0.8 + span / 2 + 8), width: span)
        let y = min(yard.maxY - span / 2 - 8, ground + size * 0.3 + span / 2)
        frame = CGRect(x: x - span / 2, y: y - span / 2, width: span, height: span)
        // Squeezed against a side, it steps round to the other side of the board.
        if frame.insetBy(dx: -size * 0.3, dy: 0).contains(CGPoint(x: feet.x, y: frame.midY)) {
            let left = frame.minX - size * 0.7, right = frame.maxX + size * 0.7
            stroll(to: floor.contains(left) ? left : right, pace: 2.4)
        }
        let card = NotchMascotYardGameArt.board(side: span)
        card.position = onBack(CGPoint(x: frame.midX, y: frame.midY))
        if let back { NotchMascotYardGameArt.appear(card, in: back) }
        self.card = card
        look(toward: frame.midX)
        face(.determined)
        sound(.pop, at: frame.midX)
        later(0.5) { [weak self] in
            guard let self else { return }
            self.marker("YOUR MOVE!")
            self.yourTurn = true
        }
    }

    override func pressed(at point: CGPoint) {
        guard yourTurn, frame.contains(point), let card,
              let cell = NotchMascotYardGameArt.cell(at: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), side: span),
              board[cell] == nil
        else { return }
        yourTurn = false
        board[cell] = .yours
        NotchMascotYardGameArt.mark(.yours, cell: cell, on: card, side: span)
        sound(.bleep, at: point.x)
        guard !over() else { return }
        face(.thinking)
        if Bool.random() { react(.lookAround) }
        if Bool.random() { marker("HMM...") }
        later(TimeInterval.random(in: 0.8...1.6)) { [weak self] in self?.itsMove() }
    }

    private func itsMove() {
        guard !isOver, let card, let move = NotchMascotTicTacToe.move(on: board, random: { Double.random(in: 0..<1) })
        else { return }
        board[move] = .its
        NotchMascotYardGameArt.mark(.its, cell: move, on: card, side: span)
        sound(.pop, at: frame.midX)
        hop(dx: 0, dy: 260)
        face(nil)
        noteActivity()
        guard !over() else { return }
        yourTurn = true
    }

    /// Whether the game is over now, playing out how it ended.
    private func over() -> Bool {
        if let row = NotchMascotTicTacToe.winner(of: board) {
            let yours = row.mark == .yours
            if let card {
                NotchMascotYardGameArt.strike(row.line, on: card, side: span,
                                              color: NotchMascotYardGameArt.rgb(yours ? 0x1E88E5 : 0xEC407A))
            }
            if yours { youWon() } else { itWon() }
            return true
        }
        guard NotchMascotTicTacToe.isFull(board) else { return false }
        face(.embarrassed)
        react(.confused)
        marker("DRAW...")
        later(1.2) { [weak self] in self?.marker("AGAIN SOMETIME?") }
        finish(after: 3.6)
        return true
    }

    /// You beat it: it pays up, then cries, or throws a little tantrum.
    private func youWon() {
        cheer(big: true)
        later(0.4) { [weak self] in self?.payOut(self?.game.prize ?? 0, instead: "YOU WIN") }
        if Bool.random() {
            face(.crying)
            sound(.sad)
            later(0.9) { [weak self] in
                guard let self else { return }
                self.marker("WAAAH!")
                self.float("💧", at: CGPoint(x: self.head.x - self.size * 0.2, y: self.head.y - self.size * 0.3),
                           color: 0x4FC3F7, count: 3)
            }
        } else {
            face(.angry)
            for (index, at) in [0.6, 1.0, 1.4].enumerated() {
                later(at) { [weak self] in
                    guard let self else { return }
                    self.hop(dx: 0, dy: 300)
                    self.sound(.thud)
                    if let front = self.front {
                        NotchMascotPlayEffects.magicSmoke(in: front, at: self.onFront(CGPoint(x: self.head.x, y: self.head.y - self.size * 0.6)),
                                                          radius: self.size * 0.3,
                                                          energy: NotchMascotPlay.Energy(red: 0.95, green: 0.95, blue: 0.95), count: 3)
                    }
                    if index == 0 { self.marker("HMPH!") }
                }
            }
        }
        finish(after: 4.2)
    }

    private func itWon() {
        face(.smug)
        react(.celebrate)
        marker("I WIN!")
        spin(turns: 1, duration: 0.6)
        cheer()
        later(0.8) { [weak self] in self?.hop(dx: 0, dy: 460) }
        later(1.5) { [weak self] in
            guard let self else { return }
            self.hop(dx: 0, dy: 460)
            self.burst(.hearts)
        }
        finish(after: 3.8)
    }
}

// MARK: - Simon says

/// Four coloured pads on the floor, each with its own tone. It shows the
/// sequence by jumping from pad to pad, one step longer each round, and you
/// play it back by clicking them. A wrong pad, or too long a wait, ends it.
final class NotchMascotSimonPlay: NotchMascotYardPlay {
    private static let tones: [NotchMascotSoundEffect] = [.chime, .bleep, .toot, .hoot]
    private var pads: [CAShapeLayer] = []
    private var padX: [CGFloat] = []
    private var padWidth: CGFloat = 48
    private var sequence: [Int] = []
    private var entered = 0
    private var listening = false
    private var round = 0
    private var turnToken = 0
    private var aside: CGFloat = 0

    init(player: NotchMascotDesktop) { super.init(game: .simon, player: player) }

    override func begin() {
        padWidth = max(46, size * 1.15)
        let spacing = padWidth * 1.22
        let room = (yard.minX + padWidth / 2 + 6)...max(yard.minX + padWidth / 2 + 6, yard.maxX - padWidth / 2 - 6)
        padX = NotchMascotYardMoves.row(count: NotchMascotSimonSays.pads, spacing: spacing,
                                        around: feet.x + way * spacing * 1.5, on: room)
        guard padX.count == NotchMascotSimonSays.pads, let back else {
            finish(after: 0)
            return
        }
        let near = way > 0 ? padX[0] - spacing : padX[padX.count - 1] + spacing
        let far = way > 0 ? padX[padX.count - 1] + spacing : padX[0] - spacing
        aside = floor.contains(near) ? near : (floor.contains(far) ? far : feet.x)
        for (index, x) in padX.enumerated() {
            let pad = NotchMascotYardGameArt.pad(index, width: padWidth)
            pad.position = onBack(CGPoint(x: x, y: ground))
            NotchMascotYardGameArt.appear(pad, in: back)
            pads.append(pad)
            later(0.2 + Double(index) * 0.18) { [weak self] in self?.light(index) }
        }
        stroll(to: aside, pace: 2.4)
        face(.happy)
        marker("SIMON SAYS!")
        later(1.8) { [weak self] in self?.nextRound() }
    }

    private func light(_ pad: Int) {
        guard pads.indices.contains(pad) else { return }
        NotchMascotYardGameArt.light(pads[pad], index: pad, for: 0.45)
        sound(Self.tones[pad % Self.tones.count], at: padX[pad])
    }

    private func nextRound() {
        guard !isOver else { return }
        sequence = NotchMascotSimonSays.grown(sequence, random: Double.random(in: 0..<1))
        entered = 0
        listening = false
        face(.determined)
        if round > 0 { marker("ROUND \(round + 1)") }
        later(round > 0 ? 0.8 : 0.2) { [weak self] in self?.show(0) }
    }

    /// Step `index` of the sequence: it jumps onto the pad, which lights as it lands.
    private func show(_ index: Int) {
        guard !isOver else { return }
        guard index < sequence.count else {
            later(0.4) { [weak self] in self?.yourTurn() }
            return
        }
        let pad = sequence[index]
        let flight = hop(to: padX[pad], height: size * 0.55)
        later(flight) { [weak self] in self?.light(pad) }
        later(NotchMascotSimonSays.step(in: round)) { [weak self] in self?.show(index + 1) }
    }

    private func yourTurn() {
        guard !isOver else { return }
        let walk = stroll(to: aside, pace: 2.8)
        later(walk + 0.1) { [weak self] in
            guard let self, !self.isOver else { return }
            self.listening = true
            self.face(.happy)
            self.marker("YOUR TURN!")
            self.look(toward: NSEvent.mouseLocation.x)
            self.wait()
        }
    }

    /// Too long between two of your steps: time is up.
    private func wait() {
        turnToken += 1
        let token = turnToken
        later(NotchMascotSimonSays.patience) { [weak self] in
            guard let self, self.turnToken == token, self.listening else { return }
            self.listening = false
            self.face(.bored)
            self.marker("TOO SLOW!")
            self.later(1.0) { [weak self] in self?.end() }
        }
    }

    override func pressed(at point: CGPoint) {
        guard listening,
              let pad = padX.indices.first(where: { abs(point.x - padX[$0]) <= padWidth / 2 + 6 }),
              point.y >= ground - 6, point.y <= ground + padWidth * 0.26 + 24
        else { return }
        light(pad)
        guard pad == sequence[entered] else {
            wrong()
            return
        }
        entered += 1
        wait()
        guard entered == sequence.count else { return }
        listening = false
        turnToken += 1
        round += 1
        react(.celebrate)
        marker(["GOOD!", "YES!", "WOW!", "NICE!"].randomElement() ?? "GOOD!")
        cheer(big: round % 3 == 0)
        guard round < NotchMascotSimonSays.rounds else {
            face(.starstruck)
            marker("PERFECT!")
            burst(.confetti)
            cheer(big: true)
            later(1.2) { [weak self] in self?.end() }
            return
        }
        later(1.3) { [weak self] in self?.nextRound() }
    }

    private func wrong() {
        listening = false
        turnToken += 1
        sound(.sad)
        marker("NOPE!")
        face(.smug)
        react(.celebrate)
        // The pad it should have been lights up, for a groan.
        if sequence.indices.contains(entered) {
            let right = sequence[entered]
            later(0.6) { [weak self] in self?.light(right) }
        }
        later(1.4) { [weak self] in self?.end() }
    }

    private func end() {
        guard !isOver else { return }
        marker("SCORE \(round)", at: CGPoint(x: head.x, y: head.y + size * 0.3))
        later(0.9) { [weak self] in
            guard let self else { return }
            self.payOut(NotchMascotSimonSays.gold(forRounds: self.round), instead: "TRY AGAIN!")
        }
        finish(after: 3)
    }
}
