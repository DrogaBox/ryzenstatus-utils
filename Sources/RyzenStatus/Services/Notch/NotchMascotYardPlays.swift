// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

// The yard games that run about: fetch, whack-a-mole, bubbles, a path to
// follow and target practice. The table games are in NotchMascotYardTablePlays.

// MARK: - Fetch

/// A ball lies by it. Grabbed and flung, it flies and bounces; the companion
/// runs after it, jumps for it when it is high, brings it back toward the
/// pointer and drops it for more. After a few throws it is tired and happy.
final class NotchMascotFetchPlay: NotchMascotYardPlay {
    private enum Phase { case waiting, held, flying, carrying, tired }
    private var phase = Phase.waiting
    private var ball = NotchMascotYardBall(position: .zero)
    private var ballLayer: CALayer?
    private var shadowLayer: CALayer?
    private var radius: CGFloat = 8
    private var samples: [(point: CGPoint, time: CFTimeInterval)] = []
    private var grip = CGVector.zero
    private var fetched = 0
    private var lastThought: CFTimeInterval = 0
    /// Which way it faces as it carries the ball, for where the ball sits in its mouth.
    private var heading: CGFloat = 1
    /// The ball got far enough from it since it was let go to be worth fetching.
    private var wentFar = false

    init(player: NotchMascotDesktop) { super.init(game: .fetch, player: player) }

    override func begin() {
        radius = max(7, size * 0.16)
        heading = way
        ball = NotchMascotYardBall(position: CGPoint(x: inYard(feet.x + way * size * 0.85, width: radius * 2), y: ground + radius))
        let layer = NotchMascotYardGameArt.ball(radius: radius)
        layer.position = onFront(ball.position)
        let shadow = NotchMascotYardGameArt.shadow(radius: radius)
        shadow.position = onBack(CGPoint(x: ball.position.x, y: ground + 1))
        if let front, let back {
            NotchMascotYardGameArt.appear(shadow, in: back)
            NotchMascotYardGameArt.appear(layer, in: front)
        }
        ballLayer = layer
        shadowLayer = shadow
        look(toward: ball.position.x)
        react(.perk)
        face(.starstruck, for: 1.4)
        marker("FETCH!")
        sound(.boing)
        cheer()
    }

    override func pressed(at point: CGPoint) {
        guard phase == .waiting || phase == .flying,
              hypot(point.x - ball.position.x, point.y - ball.position.y) <= max(18, radius * 2.4)
        else { return }
        phase = .held
        grip = CGVector(dx: ball.position.x - point.x, dy: ball.position.y - point.y)
        samples = [(point, CACurrentMediaTime())]
        ball.resting = false
        ball.velocity = .zero
        look(toward: point.x)
        face(.determined)
        react(.bounce)
        startTicking()
    }

    override func dragged(to point: CGPoint) {
        guard phase == .held else { return }
        let now = CACurrentMediaTime()
        samples.append((point, now))
        samples.removeAll { now - $0.time > 0.12 }
        ball.position = CGPoint(x: min(yard.maxX - radius, max(yard.minX + radius, point.x + grip.dx)),
                                y: min(yard.maxY - radius, max(ground + radius, point.y + grip.dy)))
        look(toward: ball.position.x)
        showBall()
    }

    override func released(at point: CGPoint) {
        guard phase == .held else { return }
        dragged(to: point)
        var velocity = CGVector.zero
        if let first = samples.first, let last = samples.last, last.time - first.time > 0.01 {
            let span = CGFloat(last.time - first.time)
            velocity = CGVector(dx: (last.point.x - first.point.x) / span, dy: (last.point.y - first.point.y) / span)
        }
        ball.velocity = NotchMascotYardBall.fling(velocity)
        ball.resting = false
        wentFar = false
        phase = .flying
        lastThought = 0
        face(nil)
        if hypot(velocity.dx, velocity.dy) > 500 {
            sound(.whoosh, at: point.x)
            react(.surprised)
        }
    }

    override func step(by dt: TimeInterval, now: CFTimeInterval) {
        switch phase {
        case .flying:
            let falling = ball.velocity.dy
            let before = ball.position.x
            let rested = ball.step(by: dt, in: yard, radius: radius)
            if falling < -300, ball.velocity.dy > 0 { sound(.boing, at: ball.position.x) }
            showBall(rolled: reduceMotion ? 0 : ball.position.x - before)
            if !wentFar, hypot(ball.position.x - feet.x, ball.position.y - feet.y - size * 0.5) > size * 1.6 { wentFar = true }
            if rested, !wentFar {
                // Hardly thrown at all: it looks at the ball, and at you.
                phase = .waiting
                marker("?")
                face(.confused, for: 1)
                return
            }
            if wentFar, caught() { return }
            if rested || now - lastThought >= 0.22 {
                lastThought = now
                chase()
            }
        case .carrying:
            let mouth = CGPoint(x: feet.x + heading * size * 0.3, y: feet.y + size * 0.42)
            ball.position = mouth
            showBall()
        case .held:
            break
        case .waiting, .tired:
            stopTicking()
        }
    }

    /// The ball where it is now, turned by how far it `rolled`, and its shadow under it.
    private func showBall(rolled: CGFloat = 0) {
        guard let ballLayer, let shadowLayer else { return }
        let height = max(0, ball.position.y - ground - radius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ballLayer.position = onFront(ball.position)
        if rolled != 0 { ballLayer.setAffineTransform(ballLayer.affineTransform().rotated(by: -rolled / radius)) }
        shadowLayer.position = onBack(CGPoint(x: ball.position.x, y: ground + 1))
        shadowLayer.opacity = Float(max(0.15, 1 - height / (size * 6)))
        CATransaction.commit()
    }

    /// It runs where the ball will come down, and leaps for it when it is
    /// close and high enough to want a jump.
    private func chase() {
        look(toward: ball.position.x)
        guard onFloor else { return }
        let dx = ball.position.x - feet.x
        let rise = ball.position.y - feet.y
        if abs(dx) < size * 1.3, rise > size * 0.9, rise < size * 6, ball.velocity.dy < 250 {
            let lift = sqrt(2 * NotchMascotRoam.gravity * max(40, rise - size * 0.3))
            hop(dx: dx * 2.2, dy: min(1700, lift))
            return
        }
        let target = ball.resting ? ball.position.x : ball.landing(in: yard, radius: radius)
        if abs(target - feet.x) > size * 0.3 { stroll(to: target, pace: 3.6) }
    }

    /// The ball within its reach is caught: in the air, a fine catch.
    private func caught() -> Bool {
        let mouth = CGPoint(x: feet.x, y: feet.y + size * 0.55)
        guard hypot(ball.position.x - mouth.x, ball.position.y - mouth.y) < size * 0.55 + radius else { return false }
        let inAir = !onFloor || ball.position.y > ground + size * 0.9
        phase = .carrying
        ball.resting = true
        ball.velocity = .zero
        heading = ball.position.x >= feet.x ? 1 : -1
        fetched += 1
        noteActivity()
        sound(.pop)
        if inAir {
            marker("NICE CATCH!")
            react(.celebrate)
            face(.starstruck, for: 1.2)
            cheer(big: true)
        } else {
            marker("GOT IT!")
            cheer()
        }
        player?.yardStand()
        later(0.7) { [weak self] in self?.bringBack() }
        return true
    }

    /// Back toward the pointer with the ball, once it is on its feet.
    private func bringBack() {
        guard phase == .carrying else { return }
        guard onFloor else {
            later(0.2) { [weak self] in self?.bringBack() }
            return
        }
        let pointer = NSEvent.mouseLocation.x
        let toward: CGFloat = pointer >= feet.x ? 1 : -1
        let stop = NotchMascotYardMoves.clamp(pointer - toward * size * 0.9, to: floor)
        heading = stop >= feet.x ? 1 : -1
        let walk = stroll(to: stop, pace: 2.6)
        later(walk + 0.15) { [weak self] in self?.drop() }
    }

    /// It lets the ball go at its feet and asks for more, or is tired out.
    private func drop() {
        guard phase == .carrying else { return }
        let pointer = NSEvent.mouseLocation.x
        heading = pointer >= feet.x ? 1 : -1
        look(toward: pointer)
        ball.position = CGPoint(x: inYard(feet.x + heading * size * 0.85, width: radius * 2), y: ground + radius)
        ball.resting = true
        showBall()
        sound(.pop)
        noteActivity()
        guard fetched < NotchMascotYardBall.throwsBeforeTired else {
            tired()
            return
        }
        phase = .waiting
        react(.bounce)
        face(.happy, for: 1.6)
        marker(["AGAIN!", "MORE!", "THROW IT!", "AGAIN AGAIN!"].randomElement() ?? "AGAIN!")
    }

    /// Worn out and pleased with itself: it pants, loves you and is paid.
    private func tired() {
        phase = .tired
        face(.happy)
        react(.yawn)
        marker("PANT PANT")
        later(1.3) { [weak self] in
            guard let self else { return }
            self.react(.love)
            self.burst(.hearts)
            self.payOut(self.game.prize, instead: "GOOD GAME!")
            self.cheer(big: true)
        }
        finish(after: 3.6)
    }
}

// MARK: - Whack-a-mole

/// Holes open in the floor and it pops out of one, then another; a click on
/// it in time bonks it. It laughs at a miss, gets cross after a few bonks in
/// a row, and the score shows at the end.
final class NotchMascotMolePlay: NotchMascotYardPlay {
    private var holes: [CGFloat] = []
    private var holeLayers: [CALayer] = []
    private var current: Int?
    private var up = false
    private var pops = 0, score = 0, streak = 0
    private var angry = false
    private var started: CFTimeInterval = 0
    private var popToken = 0
    private var lastLaugh: CFTimeInterval = 0
    private var ending = false
    private var depth: CGFloat { size * 1.1 }

    init(player: NotchMascotDesktop) { super.init(game: .moles, player: player) }

    override func begin() {
        holes = NotchMascotYardMoves.row(count: NotchMascotWhackAMole.holes, spacing: max(size * 1.7, 64),
                                         around: feet.x, on: floor)
        for (index, x) in holes.enumerated() {
            later(Double(index) * 0.12) { [weak self] in
                guard let self, let back = self.back else { return }
                let hole = NotchMascotYardGameArt.hole(width: max(40, self.size * 1.15))
                hole.position = self.onBack(CGPoint(x: x, y: self.ground))
                NotchMascotYardGameArt.appear(hole, in: back)
                self.holeLayers.append(hole)
                self.sound(.pop, at: x)
            }
        }
        face(.mischievous)
        react(.wave)
        marker("CATCH ME!")
        later(1.4) { [weak self] in
            guard let self else { return }
            self.player?.yardStand()
            self.sound(.whoosh)
            self.player?.yardBurrow(to: self.depth, over: 0.3) {}
            self.started = CACurrentMediaTime()
            self.later(0.7) { [weak self] in self?.nextPop() }
        }
    }

    private func nextPop() {
        guard !isOver, !ending else { return }
        if pops >= NotchMascotWhackAMole.pops || CACurrentMediaTime() - started > NotchMascotWhackAMole.length {
            end()
            return
        }
        let index = NotchMascotWhackAMole.nextHole(after: current, count: holes.count, random: Double.random(in: 0..<1))
        current = index
        player?.yardMove(to: holes[index])
        let upTime = NotchMascotWhackAMole.upTime(pop: pops, angry: angry)
        pops += 1
        popToken += 1
        let token = popToken
        up = true
        face(angry ? .angry : (Bool.random() ? .mischievous : .smug))
        look(toward: NSEvent.mouseLocation.x)
        player?.yardBurrow(to: 0, over: 0.12) {}
        sound(.pop, at: holes[index])
        later(0.12 + upTime) { [weak self] in
            guard let self, self.popToken == token, self.up else { return }
            // Away before you got it: now and then it teases.
            if Bool.random() { self.marker(["NYAH!", "TOO SLOW!", "HEHE"].randomElement() ?? "NYAH!") }
            self.duck(after: Double.random(in: 0.25...0.6))
        }
    }

    /// Back down its hole, and out of another `gap` seconds later.
    private func duck(after gap: TimeInterval) {
        up = false
        player?.yardBurrow(to: depth, over: 0.12) {}
        later(0.12 + gap) { [weak self] in self?.nextPop() }
    }

    override func pressed(at point: CGPoint) {
        guard !ending, started > 0 else { return }
        if let front { NotchMascotYardGameArt.mallet(in: front, at: onFront(point), size: max(30, size * 0.8)) }
        if up, figure.insetBy(dx: -8, dy: -8).contains(point) {
            bonked()
            return
        }
        streak = 0
        let now = CACurrentMediaTime()
        guard now - lastLaugh > 0.9 else { return }
        lastLaugh = now
        if up {
            face(.smug, for: 0.8)
            marker("HAHA!")
            sound(.giggle)
        } else {
            marker("MISS", at: point)
        }
    }

    private func bonked() {
        score += 1
        streak += 1
        popToken += 1
        sound(.thud)
        marker("BONK!")
        float("★", color: 0xFFD54F, count: 2)
        face(.dizzy, for: 0.6)
        cheer()
        if streak >= NotchMascotWhackAMole.angryAfter, !angry {
            angry = true
            later(0.35) { [weak self] in
                self?.marker("GRR!")
                self?.face(.angry)
            }
        }
        duck(after: 0.35)
    }

    private func end() {
        ending = true
        up = false
        popToken += 1
        player?.yardBurrow(to: 0, over: 0.25) {}
        later(0.4) { [weak self] in
            guard let self else { return }
            self.marker("SCORE \(self.score)", at: CGPoint(x: self.head.x, y: self.head.y + self.size * 0.3))
            if self.score >= NotchMascotWhackAMole.paysFrom {
                self.face(.dizzy)
                self.react(.confused)
                self.cheer(big: true)
            } else {
                self.face(.smug)
                self.react(.celebrate)
            }
        }
        later(1.4) { [weak self] in
            guard let self else { return }
            self.payOut(NotchMascotWhackAMole.gold(for: self.score), instead: self.score >= 3 ? "NOT BAD" : "TOO SLOW!")
            self.holeLayers.forEach { NotchMascotYardGameArt.fadeAway($0, over: 0.6) }
        }
        finish(after: 3.6)
    }
}

// MARK: - Bubbles

/// It blows bubbles that drift up and away; a click pops one, a golden one
/// is worth more, and it cheers each pop.
final class NotchMascotBubblePlay: NotchMascotYardPlay {
    private final class Bubble {
        let layer: CALayer
        let radius: CGFloat
        let golden: Bool
        init(layer: CALayer, radius: CGFloat, golden: Bool) {
            self.layer = layer
            self.radius = radius
            self.golden = golden
        }
    }
    private var bubbles: [Bubble] = []
    private var score = 0
    private var blowing = false
    private var blown = 0
    private var lastCheer: CFTimeInterval = 0

    init(player: NotchMascotDesktop) { super.init(game: .bubbles, player: player) }

    override func begin() {
        face(.happy)
        react(.perk)
        marker("BUBBLES!")
        blowing = true
        later(0.8) { [weak self] in self?.blow() }
        later(0.8 + NotchMascotBubblePop.length) { [weak self] in
            self?.blowing = false
            self?.later(2.6) { [weak self] in self?.end() }
        }
    }

    private func blow() {
        guard blowing, !isOver else { return }
        spawn()
        later(TimeInterval.random(in: NotchMascotBubblePop.interval)) { [weak self] in self?.blow() }
    }

    /// One bubble from its mouth, toward the open side, rising and wobbling
    /// as it goes; it bursts by itself at the end of its life.
    private func spawn() {
        guard let front else { return }
        blown += 1
        if blown % 3 == 1 { react(.hush) }
        let golden = Double.random(in: 0..<1) < NotchMascotBubblePop.goldenChance
        let radius = max(9, golden ? size * 0.27 : size * CGFloat.random(in: 0.17...0.3))
        let layer = NotchMascotYardGameArt.bubble(radius: radius, golden: golden)
        let mouth = CGPoint(x: feet.x + way * size * 0.32, y: feet.y + size * 0.62)
        let lifetime = TimeInterval.random(in: NotchMascotBubblePop.lifetime)
        let rise = min(yard.maxY - radius - mouth.y, CGFloat(lifetime) * CGFloat.random(in: 45...80))
        let drift = way * CGFloat.random(in: size * 0.6...size * 3)
        let wobble = reduceMotion ? 0 : CGFloat.random(in: 10...26)
        let turns = CGFloat.random(in: 2...4)
        let steps = 24
        var points: [NSValue] = []
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let x = mouth.x + drift * sqrt(t) + sin(t * turns * .pi * 2) * wobble * t
            let point = CGPoint(x: min(yard.maxX - radius, max(yard.minX + radius, x)), y: mouth.y + rise * t)
            points.append(NSValue(point: onFront(point)))
        }
        let path = CAKeyframeAnimation(keyPath: "position")
        path.values = points
        path.duration = lifetime
        path.calculationMode = .cubic
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 1
        grow.duration = 0.35
        layer.position = points.last?.pointValue ?? onFront(mouth)
        layer.add(path, forKey: "float")
        layer.add(grow, forKey: "grow")
        front.addSublayer(layer)
        let bubble = Bubble(layer: layer, radius: radius, golden: golden)
        bubbles.append(bubble)
        later(lifetime) { [weak self, weak bubble] in
            guard let self, let bubble, self.bubbles.contains(where: { $0 === bubble }) else { return }
            self.burst(bubble, poppedAt: nil)
        }
    }

    /// `bubble` bursts where it is now: popped at a point on screen, or on its own.
    private func burst(_ bubble: Bubble, poppedAt point: CGPoint?) {
        bubbles.removeAll { $0 === bubble }
        let at = bubble.layer.presentation()?.position ?? bubble.layer.position
        bubble.layer.removeFromSuperlayer()
        if let front { NotchMascotYardGameArt.burst(in: front, at: at, radius: bubble.radius, golden: bubble.golden) }
        if let point { sound(.pop, at: point.x) }
    }

    override func pressed(at point: CGPoint) {
        let local = onFront(point)
        let hit = bubbles.last { bubble in
            let at = bubble.layer.presentation()?.position ?? bubble.layer.position
            return hypot(at.x - local.x, at.y - local.y) <= bubble.radius * 1.2 + 4
        }
        guard let bubble = hit else {
            // A poke at it instead of a bubble.
            if figure.insetBy(dx: -4, dy: -4).contains(point), CACurrentMediaTime() - lastCheer > 0.8 {
                lastCheer = CACurrentMediaTime()
                marker("HEY!")
                face(.embarrassed, for: 0.9)
            }
            return
        }
        burst(bubble, poppedAt: point)
        let worth = NotchMascotBubblePop.worth(golden: bubble.golden)
        score += worth
        marker("+\(worth)", at: point)
        let now = CACurrentMediaTime()
        if bubble.golden {
            face(.starstruck, for: 1.4)
            burst(.sparkles, at: point)
            react(.celebrate)
            cheer(big: true)
            lastCheer = now
        } else if now - lastCheer > 1.1 {
            lastCheer = now
            react(.celebrate)
            cheer()
        }
    }

    private func end() {
        guard !isOver else { return }
        marker("SCORE \(score)", at: CGPoint(x: head.x, y: head.y + size * 0.3))
        react(score >= 5 ? .love : .wave)
        later(1.0) { [weak self] in
            guard let self else { return }
            self.payOut(NotchMascotBubblePop.gold(for: self.score), instead: "POP POP")
        }
        finish(after: 3)
    }

    override func closing() {
        bubbles.forEach { $0.layer.removeFromSuperlayer() }
        bubbles.removeAll()
    }
}

// MARK: - A path to follow

/// A line dragged across the screen: it follows it along the floor, walking
/// where the line stays low and hopping where it rises, eats the line up
/// as it goes and bows at the end. A few paths, then it bows out.
final class NotchMascotPathPlay: NotchMascotYardPlay {
    private var points: [CGPoint] = []
    private var trail: CAShapeLayer?
    private var flag: CALayer?
    private var drawing = false
    private var following = false
    private var done = 0
    private var waitToken = 0

    init(player: NotchMascotDesktop) { super.init(game: .path, player: player) }

    override func begin() {
        face(.happy)
        react(.perk)
        marker("DRAW!")
        waitForPath()
    }

    /// Nothing drawn in a while: it bows out.
    private func waitForPath() {
        waitToken += 1
        let token = waitToken
        later(NotchMascotYardPath.waits) { [weak self] in
            guard let self, self.waitToken == token, !self.drawing, !self.following else { return }
            self.react(.wave)
            self.marker("BYE!")
            self.finish(after: 1.6)
        }
    }

    override func pressed(at point: CGPoint) {
        guard !following, let back else { return }
        trail.map { NotchMascotYardGameArt.fadeAway($0) }
        flag.map { NotchMascotYardGameArt.fadeAway($0) }
        drawing = true
        waitToken += 1
        points = [point]
        let line = NotchMascotYardGameArt.trail()
        back.addSublayer(line)
        trail = line
        look(toward: point.x)
        face(.thinking)
    }

    override func dragged(to point: CGPoint) {
        guard drawing, let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 5, points.count < 800 else { return }
        points.append(CGPoint(x: min(yard.maxX, max(yard.minX, point.x)), y: min(yard.maxY, max(ground, point.y))))
        let path = CGMutablePath()
        path.addLines(between: points.map(onBack))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trail?.path = path
        CATransaction.commit()
        look(toward: point.x)
    }

    override func released(at point: CGPoint) {
        guard drawing else { return }
        dragged(to: point)
        drawing = false
        guard NotchMascotYardPath.length(of: points) >= size * 1.5 else {
            trail.map { NotchMascotYardGameArt.fadeAway($0) }
            trail = nil
            face(nil)
            marker("?")
            waitForPath()
            return
        }
        if let back, let end = points.last {
            let mark = NotchMascotYardGameArt.flag(size: max(18, size * 0.5))
            mark.position = onBack(end)
            NotchMascotYardGameArt.appear(mark, in: back)
            flag = mark
        }
        follow()
    }

    private func follow() {
        following = true
        var beats = NotchMascotYardPath.beats(along: points, ground: ground, size: size, floor: floor)
        if let first = points.first, abs(NotchMascotYardMoves.clamp(first.x, to: floor) - feet.x) > size * 0.4 {
            beats.insert(.walk(to: NotchMascotYardMoves.clamp(first.x, to: floor)), at: 0)
        }
        face(.determined)
        marker("OK!")
        later(0.6) { [weak self] in self?.run(beats, from: 0) }
    }

    private func run(_ beats: [NotchMascotYardPath.Beat], from index: Int) {
        guard !isOver else { return }
        guard index < beats.count else {
            bow()
            return
        }
        guard onFloor else {
            later(0.15) { [weak self] in self?.run(beats, from: index) }
            return
        }
        // The line is eaten up behind it.
        if let trail {
            let share = CGFloat(index) / CGFloat(max(1, beats.count))
            let eat = CABasicAnimation(keyPath: "strokeStart")
            eat.fromValue = trail.presentation()?.strokeStart ?? trail.strokeStart
            eat.toValue = share
            eat.duration = 0.3
            trail.strokeStart = share
            trail.add(eat, forKey: "eat")
        }
        noteActivity()
        switch beats[index] {
        case .walk(let x):
            look(toward: x)
            let walk = stroll(to: x, pace: 2.4)
            later(walk + 0.12) { [weak self] in self?.run(beats, from: index + 1) }
        case .hop(let x, let height):
            let flight = hop(to: x, height: height)
            sound(.boing)
            later(flight + 0.32) { [weak self] in self?.run(beats, from: index + 1) }
        }
    }

    /// The end of the line: a bow, and maybe another.
    private func bow() {
        following = false
        done += 1
        trail.map { NotchMascotYardGameArt.fadeAway($0, over: 0.5) }
        trail = nil
        flag.map { NotchMascotYardGameArt.fadeAway($0, over: 0.5) }
        flag = nil
        let toward: CGFloat = NSEvent.mouseLocation.x >= feet.x ? 1 : -1
        look(toward: feet.x + toward * 100)
        face(.happy)
        player?.tilt(-toward * 0.45, for: 1.1)
        marker("TA-DA!")
        sound(.chime)
        burst(.confetti)
        cheer(big: true)
        later(1.2) { [weak self] in
            guard let self else { return }
            self.react(.love)
            self.payOut(NotchMascotYardPath.gold, instead: "♥")
        }
        guard done < NotchMascotYardPath.paths else {
            finish(after: 3.2)
            return
        }
        later(2.6) { [weak self] in
            guard let self, !self.isOver else { return }
            self.marker("AGAIN?")
            self.waitForPath()
        }
    }
}

// MARK: - Target practice

/// It holds up a target and walks about with it, the target bobbing and
/// swaying; each click throws a ball. A hit leaves it starstruck, a bonk on
/// the head leaves it dizzy, and the score shows at the end.
final class NotchMascotTargetPlay: NotchMascotYardPlay {
    private var target: CALayer?
    private var radius: CGFloat = 18
    private var thrown = 0, score = 0, bonks = 0
    private var started: CFTimeInterval = 0
    private var center = CGPoint.zero
    private var heading: CGFloat = 1
    private var span: ClosedRange<CGFloat> = 0...0
    private var nextStroll: CFTimeInterval = 0
    private var ending = false
    private var lastFright: CFTimeInterval = 0

    init(player: NotchMascotDesktop) { super.init(game: .target, player: player) }

    override func begin() {
        radius = max(16, size * 0.42)
        heading = way
        let reach = size * 4
        span = NotchMascotYardMoves.clamp(feet.x - reach, to: floor)...NotchMascotYardMoves.clamp(feet.x + reach, to: floor)
        let layer = NotchMascotYardGameArt.target(radius: radius)
        if let front { NotchMascotYardGameArt.appear(layer, in: front) }
        target = layer
        started = CACurrentMediaTime()
        nextStroll = started + 1.2
        face(.happy)
        react(.perk)
        startTicking()
        later(0.4) { [weak self] in
            guard let self else { return }
            self.marker("AIM HERE!", at: CGPoint(x: self.center.x, y: self.center.y + self.radius + 6))
        }
    }

    override func step(by dt: TimeInterval, now: CFTimeInterval) {
        guard let player, let target else { return }
        let hand = player.hand(toward: heading)
        let off = NotchMascotTargetPractice.sway(at: reduceMotion ? 0 : now - started, size: size, thrown: thrown)
        center = CGPoint(x: hand.x + off.dx, y: hand.y + size * 0.7 + radius + off.dy)
        NotchMascotYardGameArt.place(target, at: onFront(center))
        if !ending, now >= nextStroll, onFloor { strollOn(now: now) }
    }

    /// Off along its stretch of floor the other way, a little faster as the throws run out.
    private func strollOn(now: CFTimeInterval) {
        heading = -heading
        let edge = heading > 0 ? span.upperBound : span.lowerBound
        let to = feet.x + (edge - feet.x) * CGFloat.random(in: 0.5...1)
        let walk = stroll(to: to, pace: 1.4 + CGFloat(thrown) * 0.1)
        nextStroll = now + walk + TimeInterval.random(in: 0.2...0.9)
    }

    /// The pointer aimed at it rather than the target: it is scared stiff.
    override func moved(to point: CGPoint) {
        let now = CACurrentMediaTime()
        guard !ending, now - lastFright > 2.5, figure.insetBy(dx: -2, dy: -2).contains(point),
              hypot(point.x - center.x, point.y - center.y) > radius
        else { return }
        lastFright = now
        face(.terrified, for: 0.9)
        marker("EEK!")
    }

    override func pressed(at point: CGPoint) {
        guard !ending, thrown < NotchMascotTargetPractice.throwsAllowed, let front else { return }
        thrown += 1
        let from = CGPoint(x: (point.x + yard.midX) / 2, y: ground)
        NotchMascotYardGameArt.toss(in: front, from: onFront(from), to: onFront(point), duration: 0.22, radius: max(4, size * 0.1))
        sound(.whoosh, at: point.x)
        later(0.22) { [weak self] in self?.judge(point) }
    }

    private func judge(_ point: CGPoint) {
        let distance = hypot(point.x - center.x, point.y - center.y)
        let onIt = figure.insetBy(dx: -4, dy: -4).contains(point)
        let hit = NotchMascotTargetPractice.hit(distance: distance, radius: radius, onCompanion: onIt)
        score += hit.points
        switch hit {
        case .bullseye:
            marker("BULLSEYE!", at: CGPoint(x: center.x, y: center.y + radius))
            face(.starstruck, for: 1.6)
            react(.celebrate)
            burst(.sparkles, at: center)
            sound(.chime, at: center.x)
            cheer(big: true)
            wobbleTarget()
        case .ring:
            marker("+1", at: CGPoint(x: center.x, y: center.y + radius))
            face(.starstruck, for: 1.0)
            sound(.pop, at: center.x)
            cheer()
            wobbleTarget()
        case .companion:
            bonks += 1
            if let front { NotchMascotYardGameArt.splat(in: front, at: onFront(point), radius: max(5, size * 0.12)) }
            marker("OUCH!")
            face(bonks >= 3 ? .angry : .dizzy, for: 1.8)
            float("★", color: 0xFFD54F, count: 2)
            player?.sway(amplitude: 0.25, speed: 40, duration: 1.2)
            sound(.thud)
            if bonks == 3 { later(0.6) { [weak self] in self?.marker("HEY!") } }
        case .miss:
            if let front { NotchMascotYardGameArt.splat(in: front, at: onFront(point), radius: max(5, size * 0.12)) }
            marker("MISS!", at: point)
            face(.mischievous, for: 0.9)
            if Bool.random() { sound(.giggle) }
        }
        guard thrown >= NotchMascotTargetPractice.throwsAllowed else { return }
        later(0.9) { [weak self] in self?.end() }
    }

    private func wobbleTarget() {
        guard !reduceMotion, let target else { return }
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wobble.values = [0, 0.25, -0.18, 0.1, 0]
        wobble.duration = 0.5
        target.add(wobble, forKey: "wobble")
    }

    private func end() {
        guard !ending else { return }
        ending = true
        player?.yardStand()
        target.map { NotchMascotYardGameArt.fadeAway($0, over: 0.5) }
        marker("SCORE \(score)", at: CGPoint(x: head.x, y: head.y + size * 0.3))
        react(score >= 10 ? .love : .wave)
        later(1.0) { [weak self] in
            guard let self else { return }
            self.payOut(NotchMascotTargetPractice.gold(for: self.score), instead: self.bonks >= 3 ? "MY HEAD..." : "NICE TRY")
            self.stopTicking()
        }
        finish(after: 3)
    }
}
