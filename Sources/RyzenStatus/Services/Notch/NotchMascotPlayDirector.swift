// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Runs the life the two companions out on the desktop share: the plays
/// `NotchMascotPlay` picks, acted out step by step with their light, and
/// the little things in between. One minds the other being patted, runs to
/// it after a hard fall, takes up its yawn when it dozes off, and answers
/// what it reacts to with a take of its own. A press on either, or either
/// going home, ends a play at once.
final class NotchMascotPlayDirector {
    private let leader: NotchMascotDesktop
    private let friend: NotchMascotDesktop
    private let stage = NotchMascotPlayStage()
    private var steps: [DispatchWorkItem] = []
    private(set) var playing: NotchMascotPlay?
    private var lastPlay = CACurrentMediaTime()
    private var recent: [NotchMascotPlay.Kind] = []
    private var lastPatResponse: CFTimeInterval = -.infinity
    private var dozedAlone: CFTimeInterval?

    /// Whether they may play at all.
    var allowed: () -> Bool = { false }
    /// Whether a song is playing.
    var music: () -> Bool = { false }
    /// The bond's level, which their energy grows with.
    var level: () -> Int = { 1 }

    init(leader: NotchMascotDesktop, friend: NotchMascotDesktop) {
        self.leader = leader
        self.friend = friend
        for (one, other) in [(leader, friend), (friend, leader)] {
            one.invitePlay = { [weak self] in self?.invite() ?? false }
            one.interrupted = { [weak self] in self?.cancel() }
            one.patted = { [weak self, weak one, weak other] in
                guard let self, let one, let other else { return }
                self.patted(one, other: other)
            }
            one.landedHard = { [weak self, weak one, weak other] in
                guard let self, let one, let other else { return }
                self.fell(one, other: other)
            }
        }
    }

    /// Both are out: their first play comes before long.
    func cameOut() {
        lastPlay = CACurrentMediaTime() - NotchMascotPlay.interval + 14
        dozedAlone = nil
    }

    /// One of them went in: whatever they were doing stops.
    func wentIn() {
        cancel()
        dozedAlone = nil
    }

    // MARK: Starting

    /// Asked by either one standing with nothing to do.
    private func invite() -> Bool {
        guard playing == nil, leader.isOut, friend.isOut else { return false }
        if joinDoze() { return true }
        guard allowed(), leader.isFree, friend.isFree, !leader.isDozing, !friend.isDozing,
              leader.playScreen == friend.playScreen, let a = leader.feet, let b = friend.feet else { return false }
        let context = NotchMascotPlay.Context(distance: abs(a.x - b.x), music: music(),
                                              since: CACurrentMediaTime() - lastPlay,
                                              hour: Calendar.current.component(.hour, from: Date()), recent: recent,
                                              leaderLook: leader.playLook, friendLook: friend.playLook,
                                              rpg: NotchMascotRPG.snapshot())
        guard let play = NotchMascotPlay.next(in: context, random: { Double.random(in: 0..<1) }) else { return false }
        start(play)
        return true
    }

    private func start(_ play: NotchMascotPlay) {
        playing = play
        lastPlay = CACurrentMediaTime()
        recent.append(play.kind)
        if recent.count > NotchMascotPlay.memory { recent.removeFirst(recent.count - NotchMascotPlay.memory) }
        leader.beginPlay()
        friend.beginPlay()
        var ready: TimeInterval = 0.2
        if let spacing = play.spacing, let a = leader.feet, let b = friend.feet {
            let floor = leader.floor
            let places = NotchMascotPlay.places(leaderX: a.x, friendX: b.x, spacing: spacing,
                                                minX: floor.lowerBound, maxX: floor.upperBound)
            // One dozing already stays where it lies.
            // Winged boots from the shop quicken the steps for a while.
            let pace: CGFloat = NotchMascotRPG.stepBuffActive ? 2.3 : 1.6
            let leaderWalk = leader.isDozing ? 0 : leader.stroll(to: places.leader, pace: pace)
            let friendWalk = friend.isDozing ? 0 : friend.stroll(to: places.friend, pace: pace)
            ready = max(leaderWalk, friendWalk) + 0.35
        }
        at(ready) { [weak self] in self?.act(play) }
    }

    /// Runs `block` `delay` seconds from now, unless the play ends first.
    private func at(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func finish(after delay: TimeInterval) {
        at(delay) { [weak self] in self?.end() }
    }

    private func end() {
        steps.removeAll()
        playing = nil
        stage.close()
        leader.endPlay(after: 2.5)
        friend.endPlay(after: 3.5)
    }

    /// Stops the play under way, if any, at once.
    func cancel() {
        guard playing != nil else { return }
        steps.forEach { $0.cancel() }
        end()
    }

    // MARK: Helpers

    private func direction(from one: NotchMascotDesktop, to other: NotchMascotDesktop) -> CGFloat {
        (other.feet?.x ?? other.screenCenter.x) >= (one.feet?.x ?? one.screenCenter.x) ? 1 : -1
    }

    private func energy(_ one: NotchMascotDesktop) -> NotchMascotPlay.Energy {
        NotchMascotPlay.energy(for: one.playLook)
    }

    private var power: CGFloat { NotchMascotPlay.power(level: level()) }

    /// The layer over the whole screen they play on, and its points.
    private func canvas() -> CALayer? { stage.layer(over: leader.playScreen) }
    private func onCanvas(_ point: CGPoint) -> CGPoint { stage.point(point) }

    private func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    private func float(_ symbol: String, over one: NotchMascotDesktop, color: CGColor, count: Int = 1) {
        guard let layer = one.effects else { return }
        NotchMascotPlayEffects.float(symbol, in: layer, at: one.local(one.head), size: max(9, one.figureSize * 0.2),
                                     color: color, count: count)
    }

    private static let noteColors: [CGColor] = [
        CGColor(srgbRed: 1, green: 0.85, blue: 0.35, alpha: 1), CGColor(srgbRed: 0.55, green: 0.9, blue: 1, alpha: 1),
        CGColor(srgbRed: 1, green: 0.55, blue: 0.75, alpha: 1), CGColor(srgbRed: 0.6, green: 1, blue: 0.6, alpha: 1),
    ]
    private static let heart = CGColor(srgbRed: 1, green: 0.38, blue: 0.55, alpha: 1)
    private static let mark = CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)
    private static let snore = CGColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 1)

    private func notes(over one: NotchMascotDesktop, count: Int = 2) {
        float(Bool.random() ? "♪" : "♫", over: one, color: Self.noteColors.randomElement() ?? Self.mark, count: count)
    }

    // MARK: The plays

    private func act(_ play: NotchMascotPlay) {
        guard leader.isOut, friend.isOut else { cancel(); return }
        let toward = direction(from: leader, to: friend)
        leader.face(toward: friend.screenCenter.x)
        friend.face(toward: leader.screenCenter.x)
        switch play {
        case .duel(let clashes, let outcome): duel(clashes: clashes, outcome: outcome, toward: toward)
        case .blast(let byLeader, let answer):
            blast(by: byLeader ? leader : friend, at: byLeader ? friend : leader, answer: answer)
        case .powerUp(let byLeader, let matched):
            powerUp(by: byLeader ? leader : friend, watcher: byLeader ? friend : leader, matched: matched)
        case .danceOff(let rounds): danceOff(rounds: rounds)
        case .highFive: highFive(toward: toward)
        case .tag(let byLeader): tag(by: byLeader ? leader : friend, it: byLeader ? friend : leader)
        case .leapfrog(let byLeader): leapfrog(by: byLeader ? leader : friend, over: byLeader ? friend : leader)
        case .hug: hug(toward: toward)
        case .mimic(let rounds): mimic(rounds: rounds)
        case .gift(let byLeader): gift(from: byLeader ? leader : friend, to: byLeader ? friend : leader)
        case .nap: nap()
        case .choreography(let play): choreograph(play)
        }
    }

    /// A play of the island's, acted out on the desktop: its beats in order,
    /// with the props flying between the two, bursts over them, arcade
    /// markers rising, and the door standing on the floor between them.
    private func choreograph(_ play: NotchMascotIslandPlay) {
        for beat in play.beats {
            at(beat.at) { [weak self] in self?.perform(beat) }
        }
        if case .ability(let ability) = play.kind { abilityMoves(ability) }
        at(play.length) { NotchMascotRPG.applyOutcome(of: play) }
        finish(after: play.length + 0.9)
    }

    private func perform(_ beat: NotchMascotIslandPlay.Beat) {
        guard leader.isOut, friend.isOut else { return }
        if let reaction = beat.leader { leader.react(reaction) }
        if let reaction = beat.friend { friend.react(reaction) }
        guard let canvas = canvas() else { return }
        let figure = leader.figureSize
        if let flight = beat.flight {
            let from = flight.fromLeader ? leader : friend
            let to = flight.fromLeader ? friend : leader
            let side = direction(from: from, to: to)
            NotchMascotPlayEffects.fly(flight.thing, in: canvas, from: onCanvas(from.hand(toward: side)),
                                       to: onCanvas(to.hand(toward: -side)), duration: flight.duration,
                                       side: max(14, figure * 0.34), falls: flight.falls, energy: energy(from))
        }
        if let burst = beat.burst {
            let one = burst.onLeader ? leader : friend
            if burst.burst == .door, let a = leader.feet, let b = friend.feet {
                NotchMascotPlayEffects.secretDoor(in: canvas, at: onCanvas(middle(a, b)), height: figure * 1.5,
                                                  duration: burst.duration)
            } else {
                NotchMascotPlayEffects.burst(burst.burst, in: canvas, at: onCanvas(one.head), size: figure * 0.9,
                                             energy: energy(one), duration: burst.duration)
            }
        }
        if let marker = beat.marker {
            let one = marker.onLeader ? leader : friend
            let head = one.head
            NotchMascotPlayEffects.arcadeMarker(marker.text, in: canvas,
                                                at: onCanvas(CGPoint(x: head.x, y: head.y + figure * 0.35)),
                                                cell: max(1.6, figure * 0.05))
        }
    }

    /// What an ability asks of the body: the one that has it springs, glides,
    /// dives or climbs, where the strip only shows it.
    private func abilityMoves(_ ability: NotchMascotAbility) {
        let doer = NotchMascotAbility.of(leader.playLook.style) == ability ? leader : friend
        let other = doer === leader ? friend : leader
        let side = direction(from: doer, to: other)
        switch ability {
        case .glide:
            at(0.6) { doer.hop(dx: side * 200, dy: 140) }
        case .pepelogooSpringboard:
            at(0.7) { doer.hop(dx: 0, dy: 150) }
            at(1.2) { doer.hop(dx: side * 30, dy: 220) }
        case .dolphinDive:
            at(0.5) { doer.hop(dx: side * 50, dy: 120) }
            at(1.4) { doer.hop(dx: side * 50, dy: 120) }
        case .ceilingWalk:
            at(0.6) { doer.hop(dx: side * 60, dy: 200) }
        case .fireballBreath:
            break
        }
    }

    /// Blades out, a few clashes in a shower of sparks, and one knocks the
    /// other back, or they put them away and bow.
    private func duel(clashes: Int, outcome: NotchMascotPlay.Outcome, toward: CGFloat) {
        let length = { (one: NotchMascotDesktop) in one.figureSize * 0.72 }
        func draw(_ one: NotchMascotDesktop, _ side: CGFloat) -> CALayer? {
            guard let layer = one.effects else { return nil }
            return NotchMascotPlayEffects.blade(in: layer, hand: one.local(one.hand(toward: side)), direction: side,
                                                length: length(one), energy: energy(one))
        }
        func swing(_ blade: CALayer?, _ side: CGFloat) {
            if let blade { NotchMascotPlayEffects.swing(blade, direction: side) }
        }
        func sheathe(_ blade: CALayer?) {
            if let blade { NotchMascotPlayEffects.sheathe(blade) }
        }
        let ownBlade = draw(leader, toward)
        let friendBlade = draw(friend, -toward)
        for index in 0..<clashes {
            let time = 0.55 + Double(index) * 0.8
            at(time) { [weak self] in
                guard let self else { return }
                self.leader.hop(dx: toward * 150, dy: 300)
                self.friend.hop(dx: -toward * 150, dy: 300)
            }
            at(time + 0.12) {
                swing(ownBlade, toward)
                swing(friendBlade, -toward)
            }
            at(time + 0.26) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                var meet = self.middle(self.leader.hand(toward: toward), self.friend.hand(toward: -toward))
                meet.y += self.leader.figureSize * 0.3
                let point = self.onCanvas(meet)
                NotchMascotPlayEffects.sparks(in: canvas, at: point, reach: 26, energy: self.energy(self.leader))
                NotchMascotPlayEffects.sparks(in: canvas, at: point, reach: 20, energy: self.energy(self.friend), count: 6)
                NotchMascotPlayEffects.flash(in: canvas, at: point, radius: 16, energy: self.energy(self.leader))
            }
            at(time + 0.46) { [weak self] in
                guard let self else { return }
                self.leader.hop(dx: -toward * 170, dy: 240)
                self.friend.hop(dx: toward * 170, dy: 240)
            }
        }
        let close = 0.55 + Double(clashes) * 0.8 + 0.35
        switch outcome {
        case .draw:
            at(close) { [weak self] in
                guard let self else { return }
                sheathe(ownBlade)
                sheathe(friendBlade)
                self.leader.react(.wave)
                self.friend.react(.wave)
            }
            at(close + 1.4) { [weak self] in
                self?.leader.react(.celebrate)
                self?.friend.react(.celebrate)
            }
            finish(after: close + 3)
        case .leaderWins, .friendWins:
            let winner = outcome == .leaderWins ? leader : friend
            let loser = outcome == .leaderWins ? friend : leader
            let winnerBlade = outcome == .leaderWins ? ownBlade : friendBlade
            let loserBlade = outcome == .leaderWins ? friendBlade : ownBlade
            let side = direction(from: winner, to: loser)
            at(close) { [weak self] in
                guard let self else { return }
                swing(winnerBlade, side)
                winner.hop(dx: side * 120, dy: 260)
            }
            at(close + 0.18) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(loser.screenCenter), reach: 30,
                                              energy: self.energy(winner))
                sheathe(loserBlade)
                loser.hop(dx: side * 380, dy: 420)
                loser.react(.surprised)
            }
            at(close + 1.3) {
                loser.react(.confused)
                winner.react(.celebrate)
            }
            at(close + 2.1) { sheathe(winnerBlade) }
            at(close + 2.9) { loser.react(.wave) }
            finish(after: close + 4)
        }
    }

    /// Energy gathered in the hands and let go at the other, who holds it off
    /// with its own, takes it, jumps it or knocks it back.
    private func blast(by shooter: NotchMascotDesktop, at target: NotchMascotDesktop,
                       answer: NotchMascotPlay.BlastAnswer) {
        let side = direction(from: shooter, to: target)
        let own = energy(shooter)
        let theirs = energy(target)
        let crackles = NotchMascotPlay.crackles(shooter.playLook)
        let ball = shooter.figureSize * 0.3 * power
        let thickness = shooter.figureSize * 0.2 * power
        at(0) {
            shooter.react(.ready)
            guard let layer = shooter.effects else { return }
            NotchMascotPlayEffects.orb(in: layer, at: shooter.local(shooter.hand(toward: side)), radius: ball,
                                       energy: own, duration: 1.2, life: 1.5)
        }
        if crackles {
            for time in [0.35, 0.75, 1.15] {
                at(time) {
                    guard let layer = shooter.effects else { return }
                    NotchMascotPlayEffects.lightning(in: layer, around: shooter.local(shooter.screenCenter),
                                                     radius: shooter.figureSize * 0.8, energy: own)
                }
            }
        }
        at(0.5) { target.react(.surprised) }
        let fire = 1.45
        switch answer {
        case .struggle:
            at(0.75) {
                target.react(.ready)
                guard let layer = target.effects else { return }
                NotchMascotPlayEffects.orb(in: layer, at: target.local(target.hand(toward: -side)), radius: ball,
                                           energy: theirs, duration: 0.6, life: 0.75)
            }
            at(fire) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let from = shooter.hand(toward: side), to = target.hand(toward: -side)
                let meet = self.middle(from, to)
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(from), to: self.onCanvas(meet),
                                            thickness: thickness, energy: own, life: 1.3)
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(to), to: self.onCanvas(meet),
                                            thickness: thickness, energy: theirs, life: 1.3)
                NotchMascotPlayEffects.orb(in: canvas, at: self.onCanvas(meet), radius: thickness * 1.7, energy: own,
                                           duration: 0.2, life: 1.3)
            }
            for time in [fire + 0.4, fire + 0.85] {
                at(time) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let meet = self.middle(shooter.hand(toward: side), target.hand(toward: -side))
                    NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(meet), reach: 30,
                                                  energy: Bool.random() ? own : theirs)
                }
            }
            at(fire + 1.3) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let meet = self.middle(shooter.hand(toward: side), target.hand(toward: -side))
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(meet), radius: shooter.figureSize * 1.3,
                                             energy: own)
                shooter.hop(dx: -side * 260, dy: 380)
                target.hop(dx: side * 260, dy: 380)
                shooter.react(.surprised)
                target.react(.surprised)
            }
            at(fire + 2.4) {
                shooter.react(.celebrate)
                target.react(.celebrate)
            }
            finish(after: fire + 3.5)
        case .hit:
            at(fire) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(shooter.hand(toward: side)),
                                            to: self.onCanvas(target.screenCenter), thickness: thickness, energy: own,
                                            life: 0.55)
            }
            at(fire + 0.16) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(target.screenCenter),
                                             radius: target.figureSize, energy: own)
                target.hop(dx: side * 420, dy: 480)
                target.react(.surprised)
            }
            at(fire + 1.3) {
                target.react(.confused)
                shooter.react(.celebrate)
            }
            at(fire + 2.5) { target.react(.wave) }
            finish(after: fire + 3.5)
        case .dodge:
            at(fire - 0.1) { target.hop(dx: 0, dy: 720) }
            at(fire) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let floor = shooter.floor
                let from = shooter.hand(toward: side)
                let beyond = CGPoint(x: min(floor.upperBound + 60, max(floor.lowerBound - 60,
                                                                     target.screenCenter.x + side * 260)), y: from.y)
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(from), to: self.onCanvas(beyond),
                                            thickness: thickness, energy: own, life: 0.42)
            }
            at(fire + 1.0) { shooter.react(.surprised) }
            at(fire + 1.25) { target.react(.celebrate) }
            finish(after: fire + 2.7)
        case .deflect:
            at(fire) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(shooter.hand(toward: side)),
                                            to: self.onCanvas(target.hand(toward: -side)), thickness: thickness,
                                            energy: own, life: 0.35)
            }
            at(fire + 0.2) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                target.react(.perk)
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(target.hand(toward: -side)), reach: 28,
                                              energy: theirs)
            }
            at(fire + 0.32) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(target.hand(toward: -side)),
                                            to: self.onCanvas(shooter.screenCenter), thickness: thickness,
                                            energy: own, life: 0.4)
            }
            at(fire + 0.5) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(shooter.screenCenter),
                                             radius: shooter.figureSize, energy: own)
                shooter.hop(dx: -side * 400, dy: 460)
                shooter.react(.surprised)
            }
            at(fire + 1.5) {
                shooter.react(.confused)
                target.react(.bounce)
            }
            finish(after: fire + 2.9)
        }
    }

    /// Bursts of aura and a leap; the other tries the same, and manages or
    /// fizzles out.
    private func powerUp(by one: NotchMascotDesktop, watcher: NotchMascotDesktop, matched: Bool) {
        let own = energy(one)
        let theirs = energy(watcher)
        let crackles = NotchMascotPlay.crackles(one.playLook)
        func burst(_ who: NotchMascotDesktop, _ energy: NotchMascotPlay.Energy, scale: CGFloat) {
            guard let layer = who.effects else { return }
            NotchMascotPlayEffects.auraBurst(in: layer, at: who.local(who.screenCenter),
                                             radius: who.figureSize * 0.7 * scale, energy: energy)
        }
        at(0) { one.react(.ready) }
        for time in [0.1, 0.5, 0.9] {
            at(time) { [weak self] in
                guard let self else { return }
                burst(one, own, scale: self.power)
                if crackles, let layer = one.effects {
                    NotchMascotPlayEffects.lightning(in: layer, around: one.local(one.screenCenter),
                                                     radius: one.figureSize * 0.8, energy: own)
                }
            }
        }
        at(0.6) { watcher.react(.surprised) }
        at(1.25) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            one.hop(dx: 0, dy: 340)
            NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(one.screenCenter),
                                         radius: one.figureSize * 0.9 * self.power, energy: own)
        }
        at(2.0) { watcher.react(.ready) }
        if matched {
            for time in [2.1, 2.5] { at(time) { burst(watcher, theirs, scale: 1) } }
            at(2.85) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                watcher.hop(dx: 0, dy: 300)
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(watcher.screenCenter),
                                             radius: watcher.figureSize * 0.8, energy: theirs)
            }
            at(3.6) {
                one.react(.celebrate)
                watcher.react(.celebrate)
            }
            finish(after: 5)
        } else {
            at(2.3) {
                guard let layer = watcher.effects else { return }
                NotchMascotPlayEffects.sparks(in: layer, at: watcher.local(watcher.screenCenter), reach: 10,
                                              energy: theirs, count: 4)
            }
            at(2.6) { [weak self] in
                watcher.react(.confused)
                self?.float("?", over: watcher, color: Self.mark)
            }
            at(3.2) { one.react(.bounce) }
            at(4.0) { watcher.react(.wave) }
            finish(after: 4.9)
        }
    }

    /// Turns at dancing, notes flying, then both together.
    private func danceOff(rounds: Int) {
        let moves: [NotchMascotReaction] = [.groove, .bounce, .perk, .wave, .celebrate, .groove].shuffled()
        for round in 0..<rounds {
            let time = 0.2 + Double(round) * 1.9
            at(time) { [weak self] in
                guard let self else { return }
                self.leader.react(moves[(round * 2) % moves.count])
                self.notes(over: self.leader)
            }
            at(time + 0.95) { [weak self] in
                guard let self else { return }
                self.friend.react(moves[(round * 2 + 1) % moves.count])
                self.notes(over: self.friend)
            }
        }
        let finale = 0.2 + Double(rounds) * 1.9
        for (index, time) in [finale, finale + 0.85].enumerated() {
            at(time) { [weak self] in
                guard let self else { return }
                if index == 0 {
                    self.leader.react(.groove)
                    self.friend.react(.groove)
                }
                self.leader.hop(dx: 0, dy: 260)
                self.friend.hop(dx: 0, dy: 260)
                self.notes(over: self.leader, count: 2)
                self.notes(over: self.friend, count: 2)
            }
        }
        at(finale + 1.9) { [weak self] in
            self?.leader.react(.celebrate)
            self?.friend.react(.celebrate)
        }
        finish(after: finale + 3)
    }

    /// Up to each other with a hop, and hands slapped in a sparkle.
    private func highFive(toward: CGFloat) {
        at(0.1) { [weak self] in
            self?.leader.hop(dx: toward * 70, dy: 360)
            self?.friend.hop(dx: -toward * 70, dy: 360)
        }
        at(0.26) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            var top = self.middle(self.leader.head, self.friend.head)
            top.y -= self.leader.figureSize * 0.1
            let gold = NotchMascotPlay.Energy(red: 1, green: 0.88, blue: 0.4)
            NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(top), reach: 24, energy: gold)
            NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(top), radius: 18, energy: gold)
        }
        at(0.9) { [weak self] in
            self?.leader.react(.celebrate)
            self?.friend.react(.celebrate)
        }
        finish(after: 2.4)
    }

    /// One runs up, tags the other and runs off; the other gives chase.
    private func tag(by runner: NotchMascotDesktop, it chaser: NotchMascotDesktop) {
        guard let start = chaser.feet else { finish(after: 0); return }
        let side = direction(from: runner, to: chaser)
        let reach = runner.stroll(to: start.x - side * 32, pace: 2.4)
        at(reach) { [weak self] in
            guard let self else { return }
            self.float("!", over: chaser, color: Self.mark)
            chaser.react(.surprised)
            runner.react(.bounce)
            let floor = runner.floor
            let away = min(floor.upperBound, max(floor.lowerBound, (runner.feet?.x ?? start.x) - side * 280))
            runner.stroll(to: away, pace: 2.6)
            self.at(0.55) { [weak self] in
                guard let self else { return }
                let chase = chaser.stroll(to: away + side * 34, pace: 2.2)
                self.at(chase) { [weak self] in
                    guard let self else { return }
                    self.float("!", over: runner, color: Self.mark)
                    runner.react(.surprised)
                    chaser.react(.celebrate)
                    self.at(0.8) {
                        runner.react(.celebrate)
                    }
                    self.finish(after: 2.4)
                }
            }
        }
    }

    /// One jumps clean over the other, who ducks.
    private func leapfrog(by jumper: NotchMascotDesktop, over other: NotchMascotDesktop) {
        let side = direction(from: jumper, to: other)
        at(0) { jumper.react(.ready) }
        at(0.6) { jumper.hop(dx: side * 470, dy: 700) }
        at(0.66) { other.react(.hush) }
        at(1.5) { jumper.react(.celebrate) }
        at(1.75) { other.react(.surprised) }
        at(2.5) { other.react(.wave) }
        finish(after: 3.3)
    }

    /// A hop into each other's arms, and hearts.
    private func hug(toward: CGFloat) {
        at(0.1) { [weak self] in
            self?.leader.hop(dx: toward * 50, dy: 180)
            self?.friend.hop(dx: -toward * 50, dy: 180)
        }
        at(0.35) { [weak self] in
            guard let self else { return }
            self.leader.react(.love)
            self.friend.react(.love)
            guard let canvas = self.canvas() else { return }
            NotchMascotPlayEffects.float("♥", in: canvas, at: self.onCanvas(self.middle(self.leader.head, self.friend.head)),
                                         size: max(10, self.leader.figureSize * 0.22), color: Self.heart, count: 3)
        }
        finish(after: 2.6)
    }

    /// The friend copies the companion move for move, until it gets one wrong.
    private func mimic(rounds: Int) {
        let moves = Array([NotchMascotReaction.wave, .bounce, .perk, .lookAround, .groove, .celebrate, .peek]
            .shuffled().prefix(rounds))
        for (index, move) in moves.enumerated() {
            let time = 0.2 + Double(index) * 1.7
            at(time) { [weak self] in self?.leader.react(move) }
            at(time + 0.85) { [weak self] in
                self?.friend.react(index == moves.count - 1 ? .confused : move)
            }
        }
        let close = 0.2 + Double(moves.count) * 1.7
        at(close) { [weak self] in
            guard let self else { return }
            self.leader.react(.bounce)
            self.float("?", over: self.friend, color: Self.mark)
        }
        at(close + 0.9) { [weak self] in self?.friend.react(.celebrate) }
        finish(after: close + 2.1)
    }

    /// A little star handed over, and a happy one for it.
    private func gift(from giver: NotchMascotDesktop, to taker: NotchMascotDesktop) {
        let side = direction(from: giver, to: taker)
        at(0) {
            giver.react(.perk)
            guard let layer = giver.effects else { return }
            NotchMascotPlayEffects.sparks(in: layer, at: giver.local(giver.hand(toward: side)), reach: 12,
                                          energy: NotchMascotPlay.Energy(red: 1, green: 0.86, blue: 0.3), count: 6)
        }
        at(0.5) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            NotchMascotPlayEffects.star(in: canvas, from: self.onCanvas(giver.hand(toward: side)),
                                        to: self.onCanvas(taker.hand(toward: -side)), duration: 0.75)
        }
        at(1.3) { [weak self] in
            taker.react(.love)
            self?.float("♥", over: taker, color: Self.heart, count: 2)
        }
        at(1.8) { giver.react(.celebrate) }
        finish(after: 3.2)
    }

    /// A yawn goes round, and both doze off side by side until it is time to
    /// wake, or one is woken.
    private func nap() {
        at(0) { [weak self] in self?.leader.react(.yawn) }
        at(1.1) { [weak self] in self?.friend.react(.yawn) }
        at(2.3) { [weak self] in
            self?.leader.setNapping(true)
            self?.friend.setNapping(true)
        }
        let length = NotchMascotPlay.napLength(random: Double.random(in: 0..<1))
        var time = 3.0
        while time < length {
            at(time) { [weak self] in
                guard let self else { return }
                self.float("z", over: self.leader, color: Self.snore)
            }
            at(time + 0.8) { [weak self] in
                guard let self else { return }
                self.float("z", over: self.friend, color: Self.snore)
            }
            time += 2.6
        }
        at(length) { [weak self] in
            self?.leader.setNapping(false)
            self?.leader.react(.wakeUp)
        }
        at(length + 0.7) { [weak self] in
            self?.friend.setNapping(false)
            self?.friend.react(.wakeUp)
        }
        finish(after: length + 2.2)
    }

    // MARK: In between

    /// The friend's own take on what the companion just reacted to, a moment
    /// later, where it stands on the desktop.
    func echo(_ reaction: NotchMascotReaction) {
        guard playing == nil, friend.isOut, let echo = NotchMascotPlay.echo(of: reaction) else { return }
        let delay = Double.random(in: NotchMascotPlay.echoDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.playing == nil, self.friend.isOut else { return }
            self.friend.react(echo)
        }
    }

    /// The music plays on or stops: both bob to it while they may.
    func syncMusic(dancing: Bool) {
        leader.setDancing(dancing)
        friend.setDancing(dancing)
    }

    /// One was patted: the other minds, wants one too or cheers it on.
    private func patted(_ one: NotchMascotDesktop, other: NotchMascotDesktop) {
        guard playing == nil, other.isOut else { return }
        // A pat wakes a nap for both.
        if other.napping {
            other.setNapping(false)
            other.react(.wakeUp)
            return
        }
        let now = CACurrentMediaTime()
        guard other.isFree, now - lastPatResponse > NotchMascotPlay.patResponseInterval,
              let a = one.feet, let b = other.feet else { return }
        lastPatResponse = now
        let side = direction(from: other, to: one)
        switch NotchMascotPlay.patResponse(distance: abs(a.x - b.x), random: Double.random(in: 0..<1)) {
        case .comesOver:
            let walk = other.stroll(to: a.x - side * 64, pace: 1.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.2) { [weak other] in
                guard let other, other.isFree else { return }
                other.react(.bounce)
            }
        case .wantsOne:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak other] in
                guard let self, let other, other.isFree else { return }
                other.face(toward: a.x)
                other.hop(dx: side * 60, dy: 260)
                self.float("!", over: other, color: Self.mark)
            }
        case .cheers:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak other] in
                guard let other, other.isFree else { return }
                other.react(.celebrate)
            }
        }
    }

    /// One came down hard: the other gasps and goes to see it's all right.
    private func fell(_ one: NotchMascotDesktop, other: NotchMascotDesktop) {
        guard playing == nil, other.isOut, other.isFree else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak one, weak other] in
            guard let self, let one, let other, other.isFree else { return }
            other.react(.surprised)
            guard let a = one.feet, let b = other.feet else { return }
            let side: CGFloat = a.x >= b.x ? 1 : -1
            let walk = abs(a.x - b.x) > 90 ? other.stroll(to: a.x - side * 60, pace: 2) : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + walk + 0.9) { [weak self, weak other] in
                guard let self, let other, other.isFree else { return }
                other.react(.love)
                self.float("♥", over: other, color: Self.heart)
            }
        }
    }

    /// One dozed off on its own a while ago: the other yawns and joins it.
    private func joinDoze() -> Bool {
        let leaderDozes = leader.isDozing && !leader.napping
        let friendDozes = friend.isDozing && !friend.napping
        guard leaderDozes != friendDozes else { dozedAlone = nil; return false }
        let now = CACurrentMediaTime()
        guard let since = dozedAlone else { dozedAlone = now; return false }
        let awake = leaderDozes ? friend : leader
        guard now - since >= NotchMascotPlay.dozeJoinDelay, awake.isFree, allowed() else { return false }
        dozedAlone = nil
        start(.nap)
        return true
    }
}
