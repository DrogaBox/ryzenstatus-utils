// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Runs a fusion between two companions out on the desktop, as the catalog
/// in `NotchMascotFusion` says it turns out. They walk apart to mirrored
/// spots and dance it in three beats, shouting each: a step in with the arms
/// out, a sweep of the arms with a hop, and a lean in until their fingertips
/// meet. A blinding flash goes over the screen, and one of them stands where
/// both did, bigger, in both their colours and an aura, while the other is
/// inside it, out of sight. The fused one says its name once and shows off
/// its power moves for a minute or so, then splits with a puff and both are
/// back side by side, dizzy. A fusion gone wrong comes out lumpy and only
/// lasts a little. A press on either, or either going home, splits them at
/// once. One fusion at a time, and never with Reduce Motion or Low Power
/// Mode on. The gang keeps one director for everyone out.
final class NotchMascotFusionDirector {
    private let stage = NotchMascotPlayStage()
    private var steps: [DispatchWorkItem] = []
    /// The one that gives the body and stays out, and the one that goes in.
    private(set) var body: NotchMascotDesktop?
    private(set) var partner: NotchMascotDesktop?
    private var fused: NotchMascotFusion.Fused?
    /// The look the fused one wears, made as the dance starts.
    private var fusedLook: NotchMascotLook?
    /// Past the flash: one stands where two did.
    private var merged = false
    /// The floor they dance on, on screen.
    private var floorY: CGFloat = 0
    /// The first fusion of their own comes a few minutes after the app starts.
    private var lastFusion = CACurrentMediaTime() - NotchMascotFusion.interval + 240
    private var recentMoves: [NotchMascotFusion.Move] = []
    /// When the fused one last did a move for a press on it.
    private var lastTap: CFTimeInterval = -.infinity
    /// The sparks that follow the fused one's feet as it strolls.
    private var trailWork: [DispatchWorkItem] = []

    /// The others about who would stop to watch `one`.
    var watchers: (NotchMascotDesktop) -> [NotchMascotDesktop] = { _ in [] }
    /// The bond's level, which its blasts grow with.
    var level: () -> Int = { 1 }
    /// Whatever else `one` is doing with the others stops, for a fusion asked for.
    var release: (NotchMascotDesktop) -> Void = { _ in }
    /// The two split again; true when the fusion went well.
    var ended: ((NotchMascotDesktop, NotchMascotDesktop, Bool) -> Void)?

    /// Whether `one` is in the fusion under way.
    func involves(_ one: NotchMascotDesktop) -> Bool { one === body || one === partner }

    private var mayMove: Bool {
        NotchMascotFusion.allowed(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // MARK: Starting

    /// Asked as a pair would start a play: they fuse instead when one is
    /// due, they get on well and both stand free near each other. `relation`
    /// is nil for the island's own two.
    func invite(_ one: NotchMascotDesktop, with other: NotchMascotDesktop, pair: NotchMascotPlayDirector,
                relation: NotchMascotRelation?) -> Bool {
        guard body == nil, mayMove, pair.playing == nil, pair.allowed(), one.isFree, other.isFree,
              !one.isDozing, !other.isDozing, let a = one.feet, let b = other.feet, one.playScreen != nil,
              one.playScreen == other.playScreen, abs(a.x - b.x) <= NotchMascotFusion.reach,
              NotchMascotFusion.due(since: CACurrentMediaTime() - lastFusion, sincePlay: pair.since, relation: relation,
                                    today: NotchMascotFusion.fusionsToday(), random: Double.random(in: 0..<1))
        else { return false }
        pair.played()
        guard start(one, other) else { return false }
        NotchMascotFusion.noteFusion()
        return true
    }

    /// `one` was pressed: fused, it shows off a move for it rather than
    /// split, at most every so often. False when the press is not for it.
    func tapped(_ one: NotchMascotDesktop) -> Bool {
        guard merged, one === body, let fused, mayMove else { return false }
        let now = CACurrentMediaTime()
        guard now - lastTap >= NotchMascotFusion.tapCooldown else { return true }
        lastTap = now
        let move = NotchMascotFusion.nextMove(for: fused, recent: recentMoves, random: { Double.random(in: 0..<1) })
        recentMoves = Array((recentMoves + [move]).suffix(3))
        _ = perform(move, by: one, fused: fused)
        return true
    }

    /// Fuses `one` with `other` at once, as asked from `one`'s menu: what
    /// either was doing with the others stops.
    @discardableResult
    func fuse(_ one: NotchMascotDesktop, with other: NotchMascotDesktop) -> Bool {
        guard body == nil, mayMove, one !== other, one.isOut, other.isOut, !one.fusedAway, !other.fusedAway else { return false }
        release(one)
        release(other)
        guard one.feet != nil, other.feet != nil, one.playScreen != nil, one.playScreen == other.playScreen else { return false }
        return start(one, other)
    }

    private func start(_ first: NotchMascotDesktop, _ second: NotchMascotDesktop) -> Bool {
        guard let a = first.feet, let b = second.feet else { return false }
        let fused = NotchMascotFusion.fuse(first.playLook, second.playLook,
                                           names: (Self.name(of: first.playLook.style), Self.name(of: second.playLook.style)),
                                           hour: Calendar.current.component(.hour, from: Date()),
                                           random: { Double.random(in: 0..<1) })
        body = fused.bodyIsFirst ? first : second
        partner = fused.bodyIsFirst ? second : first
        self.fused = fused
        fusedLook = NotchMascotFusion.look(of: fused, first: first.playLook, second: second.playLook)
        merged = false
        floorY = min(a.y, b.y)
        recentMoves = []
        lastFusion = CACurrentMediaTime()
        first.beginPlay()
        second.beginPlay()
        // Apart to mirrored spots, room to dance between them.
        let figure = max(first.figureSize, second.figureSize)
        let floor = first.floor
        let places = NotchMascotPlay.places(leaderX: a.x, friendX: b.x, spacing: max(170, figure * 3.6),
                                            minX: floor.lowerBound, maxX: floor.upperBound)
        let ready = max(first.stroll(to: places.leader, pace: 1.7), second.stroll(to: places.friend, pace: 1.7)) + 0.45
        at(ready) { [weak self] in self?.dance(first, second) }
        return true
    }

    // MARK: The dance

    /// The three beats, each shouted by both, and their fingertips meeting.
    private func dance(_ first: NotchMascotDesktop, _ second: NotchMascotDesktop) {
        guard first.isOut, second.isOut else { cancel(); return }
        let text = FeatureStrings.notchMascotFusion(L10n.shared.language)
        let side = direction(from: first, to: second)
        first.face(toward: second.screenCenter.x)
        second.face(toward: first.screenCenter.x)
        first.pullFace(.determined, for: 4)
        second.pullFace(.determined, for: 4)
        // FU: a step in, the arms out wide.
        at(0.1) { [weak self] in
            guard let self else { return }
            let step = min(first.figureSize * 0.9, abs(self.x(second) - self.x(first)) * 0.16)
            first.stroll(to: self.x(first) + side * step, pace: 0.9)
            second.stroll(to: self.x(second) - side * step, pace: 0.9)
            first.tilt(-side * 0.28, for: 1.1)
            second.tilt(side * 0.28, for: 1.1)
            self.shout(text.fu, over: first, leans: -side, spiky: false)
            self.shout(text.fu, over: second, leans: side, spiky: false)
            NotchMascotSound.play(.whoosh, pan: self.heard(first, second))
        }
        // SION: a hop, the arms sweeping over.
        at(1.45) { [weak self] in
            guard let self else { return }
            for one in [first, second] {
                one.hop(dx: 0, dy: 240)
                one.sway(amplitude: 0.42, speed: 9, duration: 1.0)
            }
            self.shout(text.sion, over: first, leans: -side, spiky: false)
            self.shout(text.sion, over: second, leans: side, spiky: false)
            NotchMascotSound.play(.magic, pan: self.heard(first, second))
        }
        // HA: they lean in until their fingertips meet.
        at(2.75) { [weak self] in
            guard let self else { return }
            first.hop(dx: side * 110, dy: 260)
            second.hop(dx: -side * 110, dy: 260)
            first.tilt(side * 0.42, for: 1.1)
            second.tilt(-side * 0.42, for: 1.1)
            self.shout(text.ha, over: first, leans: -side, spiky: true)
            self.shout(text.ha, over: second, leans: side, spiky: true)
            NotchMascotSound.play(.zap, pan: self.heard(first, second))
        }
        at(3.1) { [weak self] in
            guard let self, let canvas = self.canvas() else { return }
            let touch = self.onCanvas(self.middle(first.hand(toward: side), second.hand(toward: -side)))
            let white = NotchMascotPlay.Energy(red: 1, green: 1, blue: 1)
            NotchMascotPlayEffects.sparks(in: canvas, at: touch, reach: 30, energy: white, count: 10)
            NotchMascotPlayEffects.flash(in: canvas, at: touch, radius: 26, energy: white)
            NotchMascotSound.play(.clash, pan: self.heard(first, second))
        }
        at(3.4) { [weak self] in self?.flash(first, second) }
    }

    /// The flash: one stands where two did, leaps up in its new aura and
    /// says who it is, or looks down at itself, gone wrong.
    private func flash(_ first: NotchMascotDesktop, _ second: NotchMascotDesktop) {
        guard let body, let partner, let fused, let fusedLook, first.isOut, second.isOut else { cancel(); return }
        let meetX = (x(first) + x(second)) / 2
        let figure = max(first.figureSize, second.figureSize)
        let colors = (fused.look.primary, fused.look.secondary)
        if let canvas = canvas() {
            NotchMascotFusionEffects.fusionFlash(in: canvas, at: onCanvas(CGPoint(x: meetX, y: floorY + figure * 0.5)),
                                                 floor: onCanvas(CGPoint(x: meetX, y: floorY)).y, figure: figure,
                                                 colors: colors)
        }
        let pan = NotchMascotSoundMap.pan(screenX: meetX, across: NSScreen.screens.map(\.frame))
        NotchMascotSound.play(.boom, pan: pan)
        NotchMascotSound.play(.magic, pan: pan, after: 0.15)
        NotchMascotSound.play(fused.flop == nil ? .chime : .warble, pan: pan, after: 0.5)
        let watching = Array(watchers(body).filter { !involves($0) }.prefix(4))
        for (index, one) in watching.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(index) * 0.12) { [weak one] in
                guard let one, one.isFree else { return }
                one.react(.surprised)
                one.pullFace(fused.flop == nil ? .starstruck : .happy, for: 3)
            }
        }
        // Under the flash, the two become one.
        at(0.12) { [weak self] in
            guard let self else { return }
            self.merged = true
            partner.setFusedAway(true)
            body.fusedLook = fusedLook
            body.glide(to: CGPoint(x: meetX, y: self.floorY), over: 0.08)
        }
        at(0.5) { body.hop(dx: 0, dy: fused.flop == nil ? 700 : 200) }
        let text = FeatureStrings.notchMascotFusion(L10n.shared.language)
        if fused.flop == nil {
            at(1.55) { [weak self] in
                guard let self else { return }
                if let canvas = self.canvas() {
                    NotchMascotFusionEffects.shockwave(in: canvas, at: self.onCanvas(CGPoint(x: self.x(body), y: self.floorY)),
                                                       reach: body.figureSize * 2.6, color: fused.look.secondary)
                    // The upgrade, said the arcade way.
                    NotchMascotPlayEffects.arcadeMarker("POWER UP", in: canvas,
                                                        at: self.onCanvas(CGPoint(x: self.x(body),
                                                                                  y: self.floorY + body.figureSize * 1.4)),
                                                        cell: max(1.8, body.figureSize * 0.055))
                }
                body.pullFace(.determined, for: 1.4)
                NotchMascotSound.play(.thud, pan: body.soundPan)
            }
            at(2.4) { [weak self] in
                body.pullFace(.smug, for: 2.6)
                self?.shout(text.introducing(fused.name), over: body, leans: 1, spiky: false, life: 2.4)
                NotchMascotSound.play(.chime, pan: body.soundPan)
            }
        } else {
            at(1.2) { [weak self] in
                guard let self else { return }
                body.pullFace(.embarrassed, for: 2.4)
                body.emote(.interrobang)
                if let canvas = self.canvas() {
                    NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onCanvas(body.head), radius: body.figureSize * 0.3,
                                                      energy: NotchMascotPlay.Energy(red: 0.6, green: 0.58, blue: 0.55), count: 4)
                }
                NotchMascotSound.play(.honk, pan: body.soundPan)
            }
            at(2.6) { [weak self] in
                body.pullFace(.crying, for: 2.2)
                self?.shout(text.flopped(fused.name), over: body, leans: 1, spiky: false, life: 2.2)
                NotchMascotSound.play(.sad, pan: body.soundPan)
            }
        }
        let length = NotchMascotFusion.duration(of: fused, random: Double.random(in: 0..<1))
        at(4) { [weak self] in self?.live() }
        at(4 + length) { [weak self] in self?.split() }
    }

    // MARK: Fused

    /// A power move, then a while of its own, and the next.
    private func live() {
        guard let body, let fused, body.isOut else { return }
        guard mayMove else { split(); return }
        let move = NotchMascotFusion.nextMove(for: fused, recent: recentMoves, random: { Double.random(in: 0..<1) })
        recentMoves = Array((recentMoves + [move]).suffix(3))
        let took = perform(move, by: body, fused: fused)
        // Between moves it strolls about, pleased with itself, sparks at
        // its heels and wisps of its aura drifting off it.
        if fused.flop == nil || Bool.random() {
            at(took + 0.8) { [weak self] in
                guard let self, body.feet != nil else { return }
                let floor = body.floor
                let x = self.x(body)
                let to = min(floor.upperBound, max(floor.lowerBound, x + CGFloat.random(in: -1...1) * body.figureSize * 3.5))
                let walk = body.stroll(to: to, pace: fused.flop == nil ? 1.6 : 0.6)
                body.pullFace(fused.flop == nil ? .smug : .bored, for: 2)
                if fused.flop == nil { self.trail(body, for: walk, color: fused.look.secondary) }
            }
        }
        if fused.flop == nil {
            at(took + 0.3) { [weak self] in
                guard let self, let canvas = self.canvas(), body.isOut else { return }
                NotchMascotFusionEffects.wisps(in: canvas, around: self.onCanvas(body.screenCenter),
                                               radius: body.figureSize * 0.8, color: fused.look.secondary, count: 3,
                                               duration: 1.6)
            }
        }
        at(took + Double.random(in: NotchMascotFusion.moveGap(level: level()))) { [weak self] in self?.live() }
    }

    /// Sparks at `one`'s feet every little while for `duration`.
    private func trail(_ one: NotchMascotDesktop, for duration: TimeInterval, color: NotchMascotColor) {
        trailWork.forEach { $0.cancel() }
        trailWork.removeAll()
        let energy = energy(color)
        var time: TimeInterval = NotchMascotFusion.trailStep
        while time < duration {
            let work = DispatchWorkItem { [weak self, weak one] in
                guard let self, let one, one.isOut, let feet = one.feet, let canvas = self.canvas(on: one) else { return }
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(CGPoint(x: feet.x, y: feet.y + 3)),
                                              reach: one.figureSize * 0.35, energy: energy, count: 3)
            }
            trailWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
            time += NotchMascotFusion.trailStep
        }
    }

    /// Plays `move`, and says how long it takes.
    private func perform(_ move: NotchMascotFusion.Move, by one: NotchMascotDesktop,
                         fused: NotchMascotFusion.Fused) -> TimeInterval {
        let figure = one.figureSize
        let floor = one.floor
        let x = self.x(one)
        let side: CGFloat = x < (floor.lowerBound + floor.upperBound) / 2 ? 1 : -1
        let own = energy(fused.look.primary)
        let heart = energy(fused.look.secondary)
        let pan = { one.soundPan }
        one.face(toward: x + side * 200)
        switch move {
        case .blast:
            let power = NotchMascotPlay.power(level: level()) * NotchMascotFusion.powerBoost
            one.pullFace(.determined, for: 2.4)
            one.react(.ready)
            if let layer = one.effects {
                NotchMascotPlayEffects.orb(in: layer, at: one.local(one.hand(toward: side)), radius: figure * 0.3 * power,
                                           energy: heart, duration: 1.1, life: 1.35)
            }
            for time in [0.4, 0.8] where fused.look.aura == .storm {
                at(time) {
                    guard let layer = one.effects else { return }
                    NotchMascotPlayEffects.lightning(in: layer, around: one.local(one.screenCenter), radius: figure * 0.8,
                                                     energy: own)
                }
            }
            at(1.3) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let from = one.hand(toward: side)
                let reach = side > 0 ? floor.upperBound + figure - from.x : from.x - floor.lowerBound + figure
                let to = CGPoint(x: from.x + side * min(560, max(figure * 2, reach)), y: from.y)
                NotchMascotPlayEffects.beam(in: canvas, from: self.onCanvas(from), to: self.onCanvas(to),
                                            thickness: figure * 0.22 * power, energy: heart, life: 0.7)
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(to), radius: figure * 1.1, energy: own)
                NotchMascotSound.play(.zap, pan: pan())
                NotchMascotSound.play(.boom, pan: pan(), after: 0.2)
                one.hop(dx: -side * 140, dy: 200)
            }
            at(2.3) { one.pullFace(.smug, for: 2) }
            return 3.2
        case .teleport:
            one.pullFace(.smug, for: 3)
            for hop in 0..<3 {
                at(Double(hop) * 0.7) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let here = self.x(one)
                    NotchMascotFusionEffects.afterimage(in: canvas, at: self.onCanvas(CGPoint(x: here, y: self.floorY)),
                                                        figure: figure, color: hop.isMultiple(of: 2) ? fused.look.primary
                                                            : fused.look.secondary)
                    let away = (hop.isMultiple(of: 2) ? side : -side) * figure * CGFloat.random(in: 1.6...3.4)
                    let to = min(floor.upperBound, max(floor.lowerBound, here + away))
                    one.glide(to: CGPoint(x: to, y: self.floorY), over: 0.06)
                    NotchMascotSound.play(.whoosh, pan: pan())
                    self.at(0.08) {
                        NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(one.screenCenter), reach: figure * 0.6,
                                                      energy: own)
                    }
                }
            }
            return 2.6
        case .kiShout:
            one.pullFace(.angry, for: 2.2)
            shout("!!", over: one, leans: side, spiky: true, life: 1.4)
            for (index, time) in [0, 0.25, 0.5].enumerated() {
                at(time) {
                    guard let layer = one.effects else { return }
                    NotchMascotPlayEffects.auraBurst(in: layer, at: one.local(one.screenCenter),
                                                     radius: figure * (0.7 + 0.2 * CGFloat(index)),
                                                     energy: index.isMultiple(of: 2) ? own : heart)
                }
            }
            one.cheatShake(amplitude: figure * 0.06, duration: 1.2)
            if let canvas = canvas() {
                NotchMascotFusionEffects.shockwave(in: canvas, at: onCanvas(CGPoint(x: x, y: floorY)), reach: figure * 3.4,
                                                   color: fused.look.secondary)
            }
            NotchMascotSound.play(.boom, pan: pan())
            NotchMascotSound.play(.whoosh, pan: pan(), after: 0.2)
            for other in watchers(one).filter({ !involves($0) }).prefix(3) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak other] in
                    guard let other, other.isFree else { return }
                    other.hop(dx: 0, dy: 220)
                    other.pullFace(.terrified, for: 1.6)
                }
            }
            at(1.6) { one.pullFace(.smug, for: 1.6) }
            return 2.6
        case .inferno:
            one.pullFace(.determined, for: 3)
            one.hop(dx: 0, dy: 760)
            NotchMascotSound.play(.fire, pan: pan())
            for index in 0..<6 {
                let offset = (CGFloat(index) - 2.5) * figure * 0.9 + CGFloat.random(in: -8...8)
                at(0.5 + Double(index) * 0.14) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let landing = CGPoint(x: x + offset, y: self.floorY + figure * 0.12)
                    NotchMascotFusionEffects.drop(in: canvas, from: self.onCanvas(CGPoint(x: x + offset * 0.3,
                                                                                          y: self.floorY + figure * 3.4)),
                                                  to: self.onCanvas(landing), radius: figure * 0.16,
                                                  energy: index.isMultiple(of: 2) ? own : heart, duration: 0.42)
                    self.at(0.42) {
                        NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(landing), radius: figure * 0.5, energy: heart)
                        NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(landing), reach: figure * 0.5, energy: own,
                                                      count: 6)
                    }
                }
            }
            NotchMascotSound.play(.boom, pan: pan(), after: 1.0)
            at(1.9) { one.pullFace(.smug, for: 2) }
            return 2.8
        case .pounce:
            one.pullFace(.mischievous, for: 3)
            leap(one, to: x + side * figure * 3.2)
            NotchMascotSound.play(.boing, pan: pan())
            at(1.15) { [weak self] in
                self?.leap(one, to: x)
                NotchMascotSound.play(.boing, pan: pan())
            }
            at(2.1) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.sparks(in: canvas, at: self.onCanvas(CGPoint(x: self.x(one), y: self.floorY + 4)),
                                              reach: figure * 0.7, energy: own)
            }
            return 2.6
        case .foxfire:
            one.pullFace(.mischievous, for: 3)
            if let canvas = canvas() {
                NotchMascotFusionEffects.wisps(in: canvas, around: onCanvas(one.screenCenter), radius: figure * 0.95,
                                               color: fused.look.primary, count: 5, duration: 2)
            }
            NotchMascotSound.play(.magic, pan: pan())
            NotchMascotSound.play(.whoosh, pan: pan(), after: 2)
            at(2.2) { one.pullFace(.smug, for: 1.6) }
            return 2.8
        case .overclock:
            one.pullFace(.determined, for: 2.4)
            one.sway(amplitude: 0.6, speed: 32, duration: 1.6)
            for (index, time) in [0, 0.4, 0.8, 1.2].enumerated() {
                at(time) {
                    guard let layer = one.effects else { return }
                    NotchMascotPlayEffects.lightning(in: layer, around: one.local(one.screenCenter), radius: figure * 0.9,
                                                     energy: index.isMultiple(of: 2) ? own : heart)
                    NotchMascotSound.play(index == 3 ? .bleep : .zap, pan: pan())
                }
            }
            at(1.7) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                one.hop(dx: 0, dy: 520)
                NotchMascotPlayEffects.flash(in: canvas, at: self.onCanvas(one.screenCenter), radius: figure * 1.2, energy: own)
                one.pullFace(.starstruck, for: 1.6)
            }
            return 2.8
        case .glitchStep:
            one.pullFace(.smug, for: 2.6)
            for hop in 0..<4 {
                at(Double(hop) * 0.45) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let here = self.x(one)
                    NotchMascotFusionEffects.afterimage(in: canvas, at: self.onCanvas(CGPoint(x: here, y: self.floorY)),
                                                        figure: figure, color: hop.isMultiple(of: 2) ? fused.look.primary
                                                            : fused.look.secondary)
                    let frame = CGRect(x: here - figure * 0.6, y: self.floorY, width: figure * 1.2, height: figure)
                    NotchMascotFusionEffects.glitchBars(in: canvas, over: CGRect(origin: self.onCanvas(frame.origin),
                                                                                 size: frame.size),
                                                        colors: [fused.look.primary, fused.look.secondary])
                    let to = min(floor.upperBound, max(floor.lowerBound, here + (hop.isMultiple(of: 2) ? side : -side * 0.4)
                                                       * figure * 1.3))
                    one.glide(to: CGPoint(x: to, y: self.floorY), over: 0.05)
                    NotchMascotSound.play(.bleep, pan: pan())
                }
            }
            return 2.4
        case .iceSlide:
            let to = min(floor.upperBound, max(floor.lowerBound, x + side * min(380, figure * 6)))
            one.pullFace(.starstruck, for: 2)
            one.glide(to: CGPoint(x: to, y: floorY), over: 1.0)
            if let canvas = canvas() {
                NotchMascotFusionEffects.iceTrail(in: canvas, from: onCanvas(CGPoint(x: x, y: floorY)).x,
                                                  to: onCanvas(CGPoint(x: to, y: floorY)).x,
                                                  floor: onCanvas(CGPoint(x: x, y: floorY)).y, color: fused.look.primary)
            }
            NotchMascotSound.play(.whoosh, pan: pan())
            NotchMascotSound.play(.chime, pan: pan(), after: 1)
            return 2.2
        case .grandJete:
            one.pullFace(.starstruck, for: 2.6)
            one.sway(amplitude: 0.55, speed: 26, duration: 0.8)
            at(0.8) { [weak self] in
                self?.leap(one, to: x + side * figure * 2.6)
                NotchMascotSound.play(.whoosh, pan: pan())
            }
            at(1.7) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotFusionEffects.petals(in: canvas, at: self.onCanvas(one.screenCenter), side: figure * 0.5,
                                                colors: [fused.look.primary, fused.look.secondary])
                NotchMascotSound.play(.chime, pan: pan())
            }
            return 2.6
        case .zenRipple:
            one.pullFace(.sleepy, for: 2.8)
            if let canvas = canvas() {
                NotchMascotFusionEffects.ripples(in: canvas, at: onCanvas(CGPoint(x: x, y: floorY)), reach: figure * 2.4,
                                                 color: fused.look.secondary)
                NotchMascotFusionEffects.bubbleStream(in: canvas, from: onCanvas(CGPoint(x: x, y: floorY + figure * 0.2)),
                                                      to: onCanvas(CGPoint(x: x + side * figure * 0.4, y: floorY + figure * 2.4)),
                                                      side: figure * 0.4, color: fused.look.secondary, count: 6)
            }
            NotchMascotSound.play(.chime, pan: pan())
            NotchMascotSound.play(.warble, pan: pan(), after: 1)
            at(2.9) { one.pullFace(.smug, for: 1.4) }
            return 3.0
        case .gulp:
            one.pullFace(.greedy, for: 1.6)
            one.cheatShake(amplitude: figure * 0.05, duration: 0.8)
            NotchMascotSound.play(.slurp, pan: pan())
            at(1.2) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onCanvas(one.head), radius: figure * 0.35, energy: heart,
                                                  count: 5)
                NotchMascotSound.play(.honk, pan: pan())
                one.pullFace(.embarrassed, for: 1.2)
            }
            at(2.5) { one.pullFace(.smug, for: 1.5) }
            return 2.6
        case .scurry:
            // A cat and a mouse in one body: it runs off scared, then turns to chase itself.
            for dash in 0..<4 {
                at(Double(dash) * 0.75) {
                    let away = (dash.isMultiple(of: 2) ? side : -side) * figure * 2.2
                    one.stroll(to: min(floor.upperBound, max(floor.lowerBound, x + away)), pace: 3.4)
                    one.pullFace(dash.isMultiple(of: 2) ? .terrified : .angry, for: 0.75)
                    one.emote(dash.isMultiple(of: 2) ? .exclaim : .curse)
                    NotchMascotSound.play(dash.isMultiple(of: 2) ? .squeak : .hoot, pan: pan())
                }
            }
            at(3.1) { one.pullFace(.dizzy, for: 1.6) }
            return 3.2
        case .bubbleBeam:
            one.pullFace(.determined, for: 2)
            at(0.4) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                let from = one.hand(toward: side)
                NotchMascotFusionEffects.bubbleStream(in: canvas, from: self.onCanvas(from),
                                                      to: self.onCanvas(CGPoint(x: from.x + side * figure * 6, y: from.y)),
                                                      side: figure * 0.5, color: fused.look.secondary, count: 12)
                for time in [0, 0.3, 0.6] { NotchMascotSound.play(.pop, pan: pan(), after: time + 0.6) }
            }
            at(1.8) { one.pullFace(.smug, for: 1.4) }
            return 2.2
        case .starfall:
            one.pullFace(.starstruck, for: 2.6)
            for index in 0..<4 {
                at(Double(index) * 0.3) { [weak self] in
                    guard let self, let canvas = self.canvas() else { return }
                    let offset = (CGFloat(index) - 1.5) * figure * 0.8
                    NotchMascotPlayEffects.star(in: canvas,
                                                from: self.onCanvas(CGPoint(x: x + offset * 1.6, y: self.floorY + figure * 3)),
                                                to: self.onCanvas(CGPoint(x: x + offset, y: self.floorY + figure * 0.2)),
                                                duration: 0.8)
                }
            }
            NotchMascotSound.play(.chime, pan: pan())
            NotchMascotSound.play(.magic, pan: pan(), after: 0.9)
            return 2.6
        case .fizzle:
            one.pullFace(.determined, for: 1.2)
            one.react(.ready)
            if let layer = one.effects {
                NotchMascotPlayEffects.orb(in: layer, at: one.local(one.hand(toward: side)), radius: figure * 0.1,
                                           energy: NotchMascotPlay.Energy(red: 0.7, green: 0.68, blue: 0.64), duration: 0.9,
                                           life: 1)
            }
            at(1.0) { [weak self] in
                guard let self, let canvas = self.canvas() else { return }
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: self.onCanvas(one.hand(toward: side)), radius: figure * 0.2,
                                                  energy: NotchMascotPlay.Energy(red: 0.6, green: 0.58, blue: 0.55), count: 3)
                NotchMascotSound.play(.poof, pan: pan())
                one.pullFace(.embarrassed, for: 2)
                one.emote(.ellipsis)
            }
            return 2.6
        case .wobble:
            one.pullFace(.terrified, for: 1.8)
            one.sway(amplitude: 0.35, speed: 7, duration: 1.8)
            NotchMascotSound.play(.boing, pan: pan())
            at(1.2) {
                one.hop(dx: side * 60, dy: 160)
                one.emote(.interrobang)
                NotchMascotSound.play(.warble, pan: pan())
            }
            at(2.0) { one.pullFace(.dizzy, for: 1.4) }
            return 2.6
        }
    }

    // MARK: Splitting

    /// Whatever stage it is at, the fusion ends: a fused one splits with a
    /// puff, and both stand side by side, dizzy.
    func cancel() { split() }

    /// `one` was pressed on, or sent home: the fusion it is in ends first.
    func interrupted(_ one: NotchMascotDesktop) {
        if involves(one) { split() }
    }

    private func split() {
        guard let body, let partner else { return }
        let fused = self.fused
        let wasMerged = merged
        steps.forEach { $0.cancel() }
        steps.removeAll()
        trailWork.forEach { $0.cancel() }
        trailWork.removeAll()
        self.body = nil
        self.partner = nil
        self.fused = nil
        fusedLook = nil
        merged = false
        if wasMerged {
            let x = self.x(body)
            if body.isOut, let canvas = canvas(on: body), let fused {
                let point = stage.point(body.screenCenter)
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: point, radius: body.figureSize * 0.45,
                                                  energy: energy(fused.look.primary))
                NotchMascotPlayEffects.magicSmoke(in: canvas, at: point, radius: body.figureSize * 0.35,
                                                  energy: energy(fused.look.secondary), count: 4)
            }
            NotchMascotSound.play(.poof, pan: body.soundPan)
            let gap = max(body.figureSize, partner.figureSize) * 0.9
            body.fusedLook = nil
            let floor = partner.floor
            let side: CGFloat = x + gap <= floor.upperBound ? 1 : -1
            partner.setFusedAway(false, at: x + side * gap)
            for one in [body, partner] where one.isOut {
                one.face(toward: one === body ? x + side * gap : x)
                one.sway(amplitude: 0.2, speed: 8, duration: 2.4)
                one.pullFace(.dizzy, for: 2.8)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak body, weak partner] in
                body?.emote(.question)
                partner?.emote(.interrobang)
            }
        }
        body.endPlay(after: 3.5)
        partner.endPlay(after: 4)
        let wentWell = wasMerged && fused?.flop == nil
        if wentWell { reward(body, partner) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.body == nil else { return }
            self.stage.close()
        }
        ended?(body, partner, wentWell)
    }

    /// A fusion that went well leaves both the wiser and the pocket fuller:
    /// experience for each, by its own bond, and gold with a shower of coins.
    private func reward(_ body: NotchMascotDesktop, _ partner: NotchMascotDesktop) {
        let store = NotchMascotBondStore.shared
        for one in [body, partner] { store.award(experience: NotchMascotFusion.experience, for: one.playLook.style) }
        NotchMascotRPG.collect(gold: NotchMascotFusion.gold)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self, weak body] in
            guard let self, let body, body.isOut, let canvas = self.canvas(on: body) else { return }
            let energy = NotchMascotPlay.Energy(red: 1, green: 0.85, blue: 0.3)
            NotchMascotPlayEffects.burst(.coins, in: canvas, at: self.stage.point(body.head), size: body.figureSize * 0.9,
                                         energy: energy)
            NotchMascotPlayEffects.arcadeMarker("+\(NotchMascotFusion.gold)", in: canvas,
                                                at: self.stage.point(CGPoint(x: body.head.x, y: body.head.y + body.figureSize * 0.4)),
                                                cell: max(1.6, body.figureSize * 0.05))
            NotchMascotSound.play(.chime, pan: body.soundPan)
        }
    }

    // MARK: The menu

    /// The fusion's entry in `one`'s menu: the others out on its screen to
    /// fuse with, or, fused, a way to split again. None with Reduce Motion or
    /// Low Power Mode on, or while a fusion of others is under way.
    func menuItem(for one: NotchMascotDesktop, partners: [NotchMascotDesktop]) -> NSMenuItem? {
        guard mayMove else { return nil }
        let text = FeatureStrings.notchMascotFusion(L10n.shared.language)
        if involves(one) {
            guard merged else { return nil }
            return Self.item(text.splitApart, symbol: "arrow.left.and.right") { [weak self] in self?.split() }
        }
        guard body == nil else { return nil }
        let item = NSMenuItem(title: text.fuseWith, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        let menu = NSMenu()
        let others = partners.filter { $0 !== one && $0.isOut && !$0.fusedAway }
        for other in others {
            menu.addItem(Self.item(Self.name(of: other), symbol: nil) { [weak self, weak one, weak other] in
                guard let self, let one, let other else { return }
                self.fuse(one, with: other)
            })
        }
        if others.isEmpty {
            let none = NSMenuItem(title: text.nobody, action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        item.submenu = menu
        return item
    }

    private final class MenuAction: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static func item(_ title: String, symbol: String?, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    // MARK: Names

    /// A figure's name in the app's language.
    static func name(of style: NotchMascotStyle) -> String {
        let language = L10n.shared.language
        return FeatureStrings.notchMascotAutomation(language).style(style, base: FeatureStrings.notchMascotSettings(language))
    }

    /// What a companion is called in a menu: the island's own by the name
    /// it was given, the rest by their figure.
    private static func name(of one: NotchMascotDesktop) -> String {
        if one.leads, let given = UserDefaults.standard.string(forKey: DefaultsKey.notchMascotName)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty { return given }
        return name(of: one.playLook.style)
    }

    // MARK: Helpers

    /// Runs `block` `delay` seconds from now, unless the fusion ends first.
    private func at(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func x(_ one: NotchMascotDesktop) -> CGFloat { one.feet?.x ?? one.screenCenter.x }

    private func direction(from one: NotchMascotDesktop, to other: NotchMascotDesktop) -> CGFloat {
        x(other) >= x(one) ? 1 : -1
    }

    private func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    private func energy(_ color: NotchMascotColor) -> NotchMascotPlay.Energy {
        NotchMascotPlay.Energy(red: color.red, green: color.green, blue: color.blue)
    }

    /// The layer over the screen the fusion plays on, and its points.
    private func canvas() -> CALayer? { (body ?? partner).flatMap { canvas(on: $0) } }
    private func canvas(on one: NotchMascotDesktop) -> CALayer? { one.playScreen.flatMap { stage.layer(over: $0) } }
    private func onCanvas(_ point: CGPoint) -> CGPoint { stage.point(point) }

    private func heard(_ first: NotchMascotDesktop, _ second: NotchMascotDesktop) -> Float {
        NotchMascotSoundMap.pan(screenX: (x(first) + x(second)) / 2, across: NSScreen.screens.map(\.frame))
    }

    /// A comic balloon over `one`'s head saying `text`.
    private func shout(_ text: String, over one: NotchMascotDesktop, leans: CGFloat, spiky: Bool, life: TimeInterval = 1.2) {
        guard one.isOut, let canvas = canvas(on: one) else { return }
        let figure = one.figureSize
        let tip = CGPoint(x: one.head.x + leans * figure * 0.12, y: one.head.y + figure * 0.04)
        NotchMascotFusionEffects.shout(text, in: canvas, at: stage.point(tip), height: max(18, figure * 0.42),
                                       spiky: spiky, life: life, leans: leans >= 0 ? 1 : -1)
    }

    /// A leap along the floor to `x`, over whatever stands between.
    private func leap(_ one: NotchMascotDesktop, to x: CGFloat) {
        guard let feet = one.feet else { return }
        let floor = one.floor
        let target = CGPoint(x: min(floor.upperBound, max(floor.lowerBound, x)), y: feet.y)
        let velocity = NotchMascotLedges.leap(from: feet, to: target, gravity: NotchMascotRoam.gravity,
                                              drag: NotchMascotRoam.airDrag, clearance: 110)
        one.hop(dx: velocity.dx, dy: velocity.dy)
    }
}
