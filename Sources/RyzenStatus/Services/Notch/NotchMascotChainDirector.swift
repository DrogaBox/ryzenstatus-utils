// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Acts out a chain reaction out on the desktop: the starter winds up and
/// throws, what it threw flies to the one it was meant for, that one takes
/// it its own way and throws something on, a combo count rising over each
/// new link, and whatever rare thing the chain set off plays for the whole
/// gang at the end. A press on any of them, or one going home, ends it.
final class NotchMascotChainDirector {
    private let stage = NotchMascotPlayStage()
    private var steps: [DispatchWorkItem] = []
    private(set) var playing: NotchMascotChainPlan?
    /// Who is in it, in the order of the plan's members.
    private(set) var cast: [NotchMascotDesktop] = []

    /// It came to its end, or was cut short.
    var ended: ((NotchMascotChainPlan, [NotchMascotDesktop]) -> Void)?

    func involves(_ one: NotchMascotDesktop) -> Bool { cast.contains { $0 === one } }

    /// Plays `plan` with `members`, in the order its links name them.
    func start(_ plan: NotchMascotChainPlan, with members: [NotchMascotDesktop]) {
        guard playing == nil, members.count >= 2, plan.links.allSatisfy({ members.indices.contains($0.from)
                                                                         && members.indices.contains($0.to) })
        else { return }
        let plan = plan.settled()
        playing = plan
        cast = members
        let reached = plan.reached
        for (index, one) in members.enumerated() where reached.contains(index) { one.beginPlay() }
        let fresh = NotchMascotChainLog.record(plan)
        perform(plan, new: fresh.rares)
    }

    func cancel() {
        guard playing != nil else { return }
        steps.forEach { $0.cancel() }
        end()
    }

    private func end() {
        steps.removeAll()
        guard let plan = playing else { return }
        playing = nil
        stage.close()
        let everyone = cast
        cast = []
        for (index, one) in everyone.enumerated() where plan.reached.contains(index) {
            one.endPlay(after: 1.5 + Double(index) * 0.4)
        }
        ended?(plan, everyone)
    }

    // MARK: Helpers

    private func at(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard self?.playing != nil else { return }
            block()
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func x(_ one: NotchMascotDesktop) -> CGFloat { one.feet?.x ?? one.screenCenter.x }
    private var figure: CGFloat { cast.map(\.figureSize).max() ?? NotchMascotRoam.drawnSize }
    private func canvas() -> CALayer? { cast.first?.playScreen.flatMap { stage.layer(over: $0) } }
    private func onCanvas(_ point: CGPoint) -> CGPoint { stage.point(point) }
    private func side(from one: NotchMascotDesktop, to other: NotchMascotDesktop) -> CGFloat { x(other) >= x(one) ? 1 : -1 }

    private func marker(_ text: String, over one: NotchMascotDesktop, higher: CGFloat = 0.35) {
        guard let canvas = canvas() else { return }
        let head = one.head
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas,
                                            at: onCanvas(CGPoint(x: head.x, y: head.y + figure * higher)),
                                            cell: max(1.6, figure * 0.05))
    }

    private func bigMarker(_ text: String, at point: CGPoint) {
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.arcadeMarker(text, in: canvas, at: onCanvas(point), cell: max(2, figure * 0.08))
    }

    private func burst(_ burst: NotchMascotIslandPlay.Burst, over one: NotchMascotDesktop) {
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.burst(burst, in: canvas, at: onCanvas(one.head), size: one.figureSize * 0.9,
                                     energy: NotchMascotPlay.energy(for: one.playLook))
    }

    private func burst(_ burst: NotchMascotIslandPlay.Burst, at point: CGPoint, energy: NotchMascotPlay.Energy) {
        guard let canvas = canvas() else { return }
        NotchMascotPlayEffects.burst(burst, in: canvas, at: onCanvas(point), size: figure * 1.2, energy: energy)
    }

    private func fly(_ thing: NotchMascotIslandPlay.Thing, from one: NotchMascotDesktop, to other: NotchMascotDesktop,
                     duration: TimeInterval = NotchMascotIslandPlay.flightLength) {
        guard let canvas = canvas() else { return }
        let way = side(from: one, to: other)
        NotchMascotPlayEffects.fly(thing, in: canvas, from: onCanvas(one.hand(toward: way)), to: onCanvas(other.head),
                                   duration: duration, side: max(14, figure * 0.34),
                                   energy: NotchMascotPlay.energy(for: one.playLook))
    }

    /// `steps` played by `one` from `start` on, toward `way`.
    private func act(_ steps: [NotchMascotItemUse.Step], by one: NotchMascotDesktop, from start: TimeInterval,
                     toward way: CGFloat) {
        for step in steps {
            at(start + step.at) { [weak one] in one?.perform(step.action, toward: way) }
        }
    }

    private var middle: CGPoint {
        guard !cast.isEmpty else { return .zero }
        let heads = cast.map(\.head)
        return CGPoint(x: heads.map(\.x).reduce(0, +) / CGFloat(heads.count),
                       y: (heads.map(\.y).max() ?? 0) + figure * 0.9)
    }

    // MARK: The chain

    private func perform(_ plan: NotchMascotChainPlan, new rares: [NotchMascotChainRare]) {
        let starter = cast[plan.starter]
        let first = plan.links.first.map { cast[$0.to] } ?? starter
        let opening = side(from: starter, to: first)
        starter.face(toward: x(first))
        act(plan.emission.windup, by: starter, from: 0, toward: opening)

        var throwAt = plan.emission.release
        var finish: TimeInterval = throwAt
        var count = 0
        for (index, link) in plan.links.enumerated() {
            // Links thrown at everyone at once leave together: the time
            // only moves on after the last of them.
            let from = cast[link.from], to = cast[link.to]
            let leaves = throwAt
            let lands = leaves + NotchMascotIslandPlay.flightLength
            at(leaves) { [weak self] in
                guard let self else { return }
                from.face(toward: self.x(to))
                self.fly(link.stimulus.thing, from: from, to: to)
            }
            at(lands) { [weak self] in
                guard let self else { return }
                to.face(toward: self.x(from))
                self.burst(link.stimulus.burst, over: to)
            }
            act(link.reaction.steps, by: to, from: lands, toward: -side(from: from, to: to))
            if !link.fanOut {
                count += 1
                if count >= 2 {
                    let shown = count
                    at(lands + 0.5) { [weak self] in self?.marker("X\(shown)", over: to, higher: 0.85) }
                }
            }
            finish = max(finish, lands + link.reaction.length)
            let fanNext = index + 1 < plan.links.count && plan.links[index + 1].fanOut && link.fanOut
            if !fanNext {
                throwAt = lands + min(NotchMascotChain.handoff, max(0.6, link.reaction.length * 0.6))
            }
        }

        var time = finish + 0.4
        for rare in plan.rares {
            time += finale(rare, at: time, plan: plan, new: rares.contains(rare))
        }
        at(time + 0.6) { [weak self] in self?.end() }
    }

    // MARK: Rare things

    /// The whole gang's show for `rare`, `start` seconds in, and how long it takes.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func finale(_ rare: NotchMascotChainRare, at start: TimeInterval, plan: NotchMascotChainPlan,
                        new: Bool) -> TimeInterval {
        let reached = plan.reached.sorted().map { cast[$0] }
        let gold = NotchMascotItemUse([(0, .gold(rare.gold))]).settled().steps.first
        let gold2 = rare.gold > 0 ? gold : nil
        let star = NotchMascotPlay.Energy(red: 1, green: 0.85, blue: 0.3)
        at(start) { [weak self] in
            guard let self else { return }
            self.bigMarker(rare.marker, at: self.middle)
            if new { self.at(0.9) { self.bigMarker("NEW!", at: CGPoint(x: self.middle.x, y: self.middle.y + self.figure * 0.5)) } }
            NotchMascotSound.play(.chime, pan: 0)
        }
        if let gold2, let holder = reached.last {
            at(start + 0.6) { holder.perform(gold2.action, toward: 1) }
        }
        switch rare {
        case .perfectChain:
            for (index, one) in reached.enumerated() {
                at(start + 0.2 + Double(index) * 0.15) { [weak self] in
                    one.react(.celebrate)
                    self?.burst(.confetti, over: one)
                }
            }
            return 2.6
        case .blackout:
            // The screen goes dark a moment, sparks over everyone, and all of them jump.
            at(start) { [weak self] in
                guard let self, let canvas = self.canvas(), let screen = self.cast.first?.playScreen else { return }
                let dark = CALayer()
                dark.frame = CGRect(origin: .zero, size: screen.frame.size)
                dark.backgroundColor = CGColor(gray: 0, alpha: 0.72)
                dark.opacity = 0
                canvas.insertSublayer(dark, at: 0)
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 1, 0.3, 1, 0]
                fade.keyTimes = [0, 0.1, 0.5, 0.55, 0.7, 1]
                fade.duration = 2.2
                dark.add(fade, forKey: "blackout")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { dark.removeFromSuperlayer() }
            }
            for one in cast {
                at(start + 0.3) { one.perform(.lightning, toward: 1) }
                at(start + 1.4) {
                    one.react(.panic)
                    one.pullFace(.terrified, for: 1.4)
                }
            }
            return 3
        case .iceAge:
            for (index, one) in cast.enumerated() {
                at(start + Double(index) * 0.2) {
                    one.perform(.symbol("❄", .blue, count: 3), toward: 1)
                    one.pullFace(.surprised, for: 1.6)
                }
                at(start + 0.8 + Double(index) * 0.2) { one.perform(.move(.slip), toward: index.isMultiple(of: 2) ? 1 : -1) }
                at(start + 1.6 + Double(index) * 0.2) { one.perform(.move(.spin), toward: 1) }
            }
            return 3
        case .supernova:
            // Light criss-crosses between all of them, then a burst of stars over each.
            for round in 0..<3 {
                for (index, one) in cast.enumerated() {
                    let other = cast[(index + 1 + round) % cast.count]
                    guard other !== one else { continue }
                    at(start + Double(round) * 0.45 + Double(index) * 0.1) { [weak self] in
                        self?.fly(.star, from: one, to: other, duration: 0.6)
                    }
                }
            }
            for one in cast {
                at(start + 1.6) { [weak self] in
                    self?.burst(.sparkles, over: one)
                    one.pullFace(.starstruck, for: 1.4)
                }
            }
            return 3
        case .sneezeStorm:
            // Every hat and thing flies off at once.
            for (index, one) in cast.enumerated() {
                at(start + Double(index) * 0.12) {
                    one.perform(.marker("ACHOO!"), toward: 1)
                    one.perform(.hide(5), toward: 1)
                    one.perform(.move(.slip), toward: index.isMultiple(of: 2) ? -1 : 1)
                }
            }
            return 2.4
        case .laughingFit:
            for (index, one) in cast.enumerated() {
                at(start + Double(index) * 0.15) {
                    one.react(.celebrate)
                    one.pullFace(.happy, for: 2.4)
                    one.perform(.move(.spin), toward: 1)
                    one.perform(.symbol("HA", .pink, count: 3), toward: 1)
                }
                at(start + 1.4 + Double(index) * 0.15) { one.perform(.move(.slip), toward: 1) }
            }
            return 3
        case .zombieConga:
            // Hypnotised, they shuffle off in a line after the first, slow and dizzy.
            guard let lead = reached.first else { return 0 }
            let floor = lead.floor
            let way: CGFloat = x(lead) > (floor.lowerBound + floor.upperBound) / 2 ? -1 : 1
            for (index, one) in reached.enumerated() {
                at(start + Double(index) * 0.3) { [weak self] in
                    guard let self else { return }
                    one.pullFace(.dizzy, for: 4)
                    _ = one.stroll(to: self.x(lead) + way * self.figure * (2.5 - CGFloat(index) * 1.1), pace: 0.45)
                    one.perform(.symbol("Z", .purple, count: 1), toward: way)
                }
            }
            at(start + 3.6) { reached.forEach { $0.react(.wakeUp) } }
            return 4.4
        case .bigBang:
            // Everything at once: every stimulus thrown about, bursts of every kind.
            let all = NotchMascotStimulus.allCases
            for (index, stimulus) in all.enumerated() where cast.count >= 2 {
                let one = cast[index % cast.count], other = cast[(index + 1) % cast.count]
                at(start + Double(index) * 0.12) { [weak self] in self?.fly(stimulus.thing, from: one, to: other, duration: 0.7) }
            }
            for one in cast {
                at(start + 1.8) { [weak self] in
                    self?.burst(.confetti, over: one)
                    self?.burst(.magic, over: one)
                    one.react(.surprised)
                }
            }
            return 3.2
        case .fireworks:
            let sky = middle
            let colours: [NotchMascotPlay.Energy] = [star, NotchMascotPlay.Energy(red: 1, green: 0.4, blue: 0.6),
                                                      NotchMascotPlay.Energy(red: 0.5, green: 0.85, blue: 1),
                                                      NotchMascotPlay.Energy(red: 0.6, green: 1, blue: 0.5)]
            for shot in 0..<7 {
                let point = CGPoint(x: sky.x + CGFloat.random(in: -figure * 4...figure * 4),
                                    y: sky.y + CGFloat.random(in: figure * 0.6...figure * 2.4))
                at(start + Double(shot) * 0.35) { [weak self] in
                    self?.burst(shot.isMultiple(of: 2) ? .sparkles : .confetti, at: point, energy: colours[shot % colours.count])
                    NotchMascotSound.play(.boom, pan: 0)
                }
            }
            for one in cast { at(start + 0.4) { one.pullFace(.starstruck, for: 2.4) } }
            return 3
        case .kaboom:
            for one in cast {
                at(start) { one.perform(.burst(.smoke), toward: 1) }
                at(start + 0.2) { one.perform(.move(.highJump), toward: 1) }
                at(start + 1.2) { one.pullFace(.dizzy, for: 1.4) }
            }
            return 2.4
        case .babyDragon, .goldenEgg, .beanstalk, .goldenPinata, .treasure, .voodooCurse:
            // Everyone else turns to look and cheers.
            for (index, one) in cast.enumerated() {
                at(start + 0.2 + Double(index) * 0.1) {
                    one.react(index.isMultiple(of: 2) ? .surprised : .perk)
                }
                at(start + 1.2 + Double(index) * 0.1) {
                    one.react(rare == .voodooCurse ? .panic : .celebrate)
                }
            }
            if rare == .beanstalk || rare == .babyDragon, let holder = reached.last {
                at(start + 0.4) { [weak self] in
                    self?.burst(.sparkles, over: holder)
                    holder.perform(.grow(4), toward: 1)
                }
            }
            return 2.4
        }
    }
}
