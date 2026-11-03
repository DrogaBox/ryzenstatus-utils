// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The shows the cheats put on over the desktop, with the companions out
/// there as their cast: 1-UP mushrooms raining and a train of tiny copies,
/// a whole arsenal fired across the screen, god rays, a fall through the
/// floor, barrel rolls, a gold rush, confetti, a big head, falling code in
/// slow motion and a moonwalk. Each draws on clear stages over the screens
/// that take no clicks, holds its cast for the show and lets it go, and
/// closes everything it opened once it is over. With Reduce Motion or in
/// Low Power Mode nothing moves: the cast only cheers where it stands.
final class NotchMascotCheatShows {
    static let shared = NotchMascotCheatShows()

    /// God mode lasts this long.
    static let godLength: TimeInterval = 30
    /// Big-head mode lasts this long.
    static let bigHeadLength: TimeInterval = 45
    /// Slow motion lasts this long, at this many times the usual pace.
    static let slowLength: TimeInterval = 15
    static let slowPace: CGFloat = 0.3
    /// Low gravity and the moonwalk last this long, gravity pulling this many times as hard.
    static let moonLength: TimeInterval = 60
    static let moonGravity: CGFloat = 0.3
    /// See-through, and through the floor, this long; and how see-through.
    static let ghostLength: TimeInterval = 8
    static let ghostOpacity: CGFloat = 0.35
    /// The gold lies on the floor this long before it fades.
    static let coinLife: TimeInterval = 8
    /// The tiny copies in the train across the floor.
    static let trainLength = 30
    /// How much smaller the body and how much bigger the head in big-head mode.
    static let bigHead: (squeeze: CGFloat, swell: CGFloat) = (0.8, 0.6)

    /// Whether a show may move things about: not with Reduce Motion, nor in Low Power Mode.
    static var movesFreely: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// The big-head look, for a figure `size` tall whose feet are `feet`
    /// points below its layer's middle, counted down: everything is drawn
    /// `squeeze` times its size about the feet, and the higher a point
    /// stands the more it is drawn bigger still, up to `1 / (1 - swell *
    /// squeeze)` at the top of the head. The feet stay where they are.
    static func bigHeadTransform(squeeze: CGFloat, swell: CGFloat, size: CGFloat, feet: CGFloat) -> CATransform3D {
        var keystone = CATransform3DIdentity
        // Points above the feet have negative y here: they divide by less than one.
        keystone.m24 = swell / max(1, size)
        let shrunk = CATransform3DConcat(CATransform3DMakeTranslation(0, -feet, 0),
                                         CATransform3DMakeScale(squeeze, squeeze, 1))
        return CATransform3DConcat(CATransform3DConcat(shrunk, keystone), CATransform3DMakeTranslation(0, feet, 0))
    }

    private var stages: [(frame: CGRect, stage: NotchMascotPlayStage)] = []
    private var work: [DispatchWorkItem] = []
    private var cast: [NotchMascotDesktop] = []
    /// The tiny copies running in the train, kept until the show is over.
    private var rigs: [NotchMascotRig] = []
    private var coins: [Coin] = []
    /// How high the gold has piled, in columns, on each stage.
    private var piles: [[CGFloat]] = []
    private var coinTimer: DispatchSourceTimer?
    private var lastCoinTick: CFTimeInterval = 0
    private var lastClink: CFTimeInterval = -.infinity

    private init() {}

    // MARK: Playing

    /// Puts on `cheat`'s show with `cast`, the companions out on the
    /// desktop, ending any show still under way. With no one out, only
    /// what falls over the screens shows.
    func play(_ cheat: NotchMascotCheat, cast: [NotchMascotDesktop]) {
        stop()
        let cast = cast.filter(\.isOut)
        shake(cast)
        guard Self.movesFreely else {
            cast.forEach { $0.react(.celebrate) }
            return
        }
        self.cast = cast
        for companion in cast {
            if companion.inPlay { companion.interrupted?() }
            companion.beginPlay()
        }
        let length: TimeInterval
        switch cheat {
        case .konami: length = konami()
        case .idkfa: length = idkfa()
        case .iddqd: length = iddqd()
        case .idclip: length = idclip()
        case .roll: length = roll()
        case .motherlode: length = motherlode()
        case .party: length = party()
        case .bighead: length = bighead()
        case .thereisnospoon: length = thereIsNoSpoon()
        case .moonwalk: length = moonwalk()
        case .xyzzy, .plugh: length = 0.6
        }
        step(after: length) { [weak self] in self?.stop() }
    }

    /// The cast shakes where it stands, as a cheat comes in.
    func shake(_ cast: [NotchMascotDesktop]) {
        for companion in cast where companion.isOut {
            companion.cheatShake(amplitude: max(4, companion.figureSize * 0.12), duration: 0.5)
        }
    }

    /// Ends the show under way: its steps, its gold and its stages, and the cast goes on with its life.
    private func stop() {
        work.forEach { $0.cancel() }
        work.removeAll()
        coinTimer?.cancel()
        coinTimer = nil
        coins.removeAll()
        piles.removeAll()
        rigs.removeAll()
        stages.forEach { $0.stage.close() }
        stages.removeAll()
        for companion in cast where companion.inPlay { companion.endPlay(after: 2) }
        cast.removeAll()
    }

    private func step(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        work.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
    }

    /// The stage over `screen` and the layer to draw on there, in points
    /// from the screen's corner, y up.
    private func canvas(on screen: NSScreen) -> (layer: CALayer, stage: NotchMascotPlayStage)? {
        let stage = stages.first(where: { $0.frame == screen.frame })?.stage ?? {
            let made = NotchMascotPlayStage()
            stages.append((screen.frame, made))
            return made
        }()
        guard let layer = stage.layer(over: screen) else { return nil }
        return (layer, stage)
    }

    /// Every screen with its canvas, its bounds and its floor above the Dock.
    private func everyScreen(_ block: (CALayer, CGRect, CGFloat) -> Void) {
        for screen in NSScreen.screens {
            guard let canvas = canvas(on: screen) else { continue }
            block(canvas.layer, CGRect(origin: .zero, size: screen.frame.size), screen.visibleFrame.minY - screen.frame.minY)
        }
    }

    /// One of the cast with its screen's canvas, `delay` seconds into the
    /// show, the next one `stagger` seconds after: a wave along the cast.
    private func eachOfCast(stagger: TimeInterval = 0.25, delay: TimeInterval = 0,
                            _ block: @escaping (NotchMascotDesktop, CALayer, NotchMascotPlayStage, NSScreen) -> Void) {
        for (index, companion) in cast.enumerated() {
            step(after: delay + Double(index) * stagger) { [weak self] in
                guard let self, companion.isOut, let screen = companion.playScreen,
                      let canvas = self.canvas(on: screen) else { return }
                block(companion, canvas.layer, canvas.stage, screen)
            }
        }
    }

    private static func pan(_ screenX: CGFloat) -> Float {
        NotchMascotSoundMap.pan(screenX: screenX, across: NSScreen.screens.map(\.frame))
    }

    private static func scale(of screen: NSScreen?) -> CGFloat { screen?.backingScaleFactor ?? 2 }

    // MARK: 30 lives

    /// 1-UP mushrooms rain on every screen through a moment of old pixels;
    /// the cast grows big a while; a train of thirty tiny copies runs
    /// across the floor.
    private func konami() -> TimeInterval {
        everyScreen { canvas, area, floor in
            scanlines(in: canvas, area: area, for: 1.8)
            let count = min(34, max(12, Int(area.width / 60)))
            for index in 0..<count {
                mushroom(in: canvas, area: area, floor: floor, delay: Double.random(in: 0.1...2.6), marked: index < 5)
            }
        }
        eachOfCast(delay: 0.4) { companion, _, _, _ in
            companion.perform(.grow(9), toward: 1)
            companion.react(.celebrate)
            companion.cheatFace(.starstruck, for: 3)
        }
        let looks = cast.map(\.playLook)
        let screen = cast.first?.playScreen ?? NSScreen.main ?? NSScreen.screens.first
        let size = cast.first?.figureSize ?? NotchMascotRoam.drawnSize
        step(after: 1.5) { [weak self] in
            guard let self, let screen else { return }
            self.train(on: screen, looks: looks.isEmpty ? [NotchMascotSupport.look()] : looks, size: size)
        }
        return 10
    }

    /// Lines across the screen as an old monitor draws them, a pixel grid
    /// and a green cast, flickering for `length` seconds.
    private func scanlines(in canvas: CALayer, area: CGRect, for length: TimeInterval) {
        let holder = CALayer()
        holder.frame = area
        let tint = CALayer()
        tint.frame = area
        tint.backgroundColor = CGColor(srgbRed: 0.15, green: 1, blue: 0.45, alpha: 0.09)
        holder.addSublayer(tint)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: area.width, height: 1.5)
        line.backgroundColor = CGColor(gray: 0, alpha: 0.32)
        let rows = CAReplicatorLayer()
        rows.frame = area
        rows.instanceCount = Int(area.height / 4) + 1
        rows.instanceTransform = CATransform3DMakeTranslation(0, 4, 0)
        rows.addSublayer(line)
        holder.addSublayer(rows)
        let column = CALayer()
        column.frame = CGRect(x: 0, y: 0, width: 1, height: area.height)
        column.backgroundColor = CGColor(gray: 0, alpha: 0.14)
        let columns = CAReplicatorLayer()
        columns.frame = area
        columns.instanceCount = Int(area.width / 4) + 1
        columns.instanceTransform = CATransform3DMakeTranslation(4, 0, 0)
        columns.addSublayer(column)
        holder.addSublayer(columns)
        holder.opacity = 0
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [0, 1, 0.55, 1, 0.75, 1, 0.6, 0]
        flicker.keyTimes = [0, 0.06, 0.14, 0.24, 0.5, 0.62, 0.86, 1]
        flicker.duration = length
        holder.add(flicker, forKey: "flicker")
        canvas.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: length)
    }

    /// A green 1-UP mushroom falling from over the top of the screen to
    /// `floor`, where it lands with a squash and fades, `marked` with a
    /// rising 1UP as it lands.
    private func mushroom(in canvas: CALayer, area: CGRect, floor: CGFloat, delay: TimeInterval, marked: Bool) {
        let side = CGFloat.random(in: 26...40)
        let holder = Self.mushroomLayer(side: side)
        let x = CGFloat.random(in: side...max(side + 1, area.width - side))
        let top = CGPoint(x: x, y: area.height + side)
        let ground = CGPoint(x: x, y: floor + side / 2)
        let fall = TimeInterval.random(in: 1.4...2.3)
        holder.position = top
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = [top, ground, CGPoint(x: x, y: ground.y + side * 0.35), ground].map { NSValue(point: $0) }
        move.keyTimes = [0, 0.7, 0.8, 0.9]
        move.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeIn)]
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [1, 1, 0.7, 1.1, 1]
        squash.keyTimes = [0, 0.69, 0.72, 0.78, 0.9]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.9, 1]
        let group = CAAnimationGroup()
        group.animations = [move, squash, fade]
        group.duration = fall / 0.7
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        holder.add(group, forKey: "fall")
        canvas.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: delay + fall / 0.7 + 0.1)
        guard marked else { return }
        step(after: delay + fall) {
            NotchMascotPlayEffects.arcadeMarker("1UP", in: canvas, at: CGPoint(x: x, y: ground.y + side), cell: 2.6)
        }
    }

    /// A 1-UP mushroom drawn in a square of `side`, y up: a green cap with
    /// white spots over a pale stalk with two eyes.
    static func mushroomLayer(side s: CGFloat) -> CALayer {
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        let ink = CGColor(srgbRed: 0.08, green: 0.12, blue: 0.08, alpha: 1)
        func shape(_ path: CGPath, _ fill: CGColor, stroke: Bool = true) {
            let layer = CAShapeLayer()
            layer.frame = holder.bounds
            layer.path = path
            layer.fillColor = fill
            layer.strokeColor = stroke ? ink : nil
            layer.lineWidth = s * 0.04
            layer.lineJoin = .round
            holder.addSublayer(layer)
        }
        shape(CGPath(roundedRect: CGRect(x: s * 0.27, y: s * 0.05, width: s * 0.46, height: s * 0.42),
                     cornerWidth: s * 0.1, cornerHeight: s * 0.1, transform: nil),
              CGColor(srgbRed: 0.98, green: 0.92, blue: 0.78, alpha: 1))
        for eye in [0.4, 0.56] {
            shape(CGPath(roundedRect: CGRect(x: s * CGFloat(eye), y: s * 0.18, width: s * 0.05, height: s * 0.13),
                         cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil), ink, stroke: false)
        }
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: s * 0.03, y: s * 0.42))
        cap.addCurve(to: CGPoint(x: s * 0.97, y: s * 0.42), control1: CGPoint(x: s * 0.03, y: s * 1.06),
                     control2: CGPoint(x: s * 0.97, y: s * 1.06))
        cap.closeSubpath()
        shape(cap, CGColor(srgbRed: 0.22, green: 0.76, blue: 0.27, alpha: 1))
        for (x, y, r) in [(0.5, 0.72, 0.12), (0.2, 0.54, 0.08), (0.8, 0.54, 0.08)] {
            let spot = CGRect(x: s * CGFloat(x - r), y: s * CGFloat(y - r), width: s * CGFloat(r * 2), height: s * CGFloat(r * 2))
            shape(CGPath(ellipseIn: spot, transform: nil), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), stroke: false)
        }
        return holder
    }

    /// Thirty tiny copies of the cast, in `looks` in turn, running in a
    /// line across the floor of `screen`, bobbing as they go.
    private func train(on screen: NSScreen, looks: [NotchMascotLook], size: CGFloat) {
        guard let canvas = canvas(on: screen)?.layer else { return }
        let floor = screen.visibleFrame.minY - screen.frame.minY
        let tiny = max(12, (size * 0.32).rounded())
        let gap = tiny * 1.1
        let count = Self.trainLength
        let line = CALayer()
        line.bounds = CGRect(x: 0, y: 0, width: gap * CGFloat(count), height: tiny * 1.5)
        line.anchorPoint = CGPoint(x: 1, y: 0)
        let scale = Self.scale(of: screen)
        for index in 0..<count {
            let rig = NotchMascotRig()
            rig.configure(look: looks[index % looks.count], size: tiny, contentsScale: scale)
            // The rig lays out from the top, as in a flipped view.
            let seat = CALayer()
            seat.isGeometryFlipped = true
            seat.bounds = CGRect(x: 0, y: 0, width: tiny, height: tiny)
            seat.position = CGPoint(x: line.bounds.width - gap * (CGFloat(index) + 0.5), y: tiny / 2)
            rig.root.position = CGPoint(x: tiny / 2, y: tiny / 2)
            seat.addSublayer(rig.root)
            rig.setStride(toward: 1)
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = [0, tiny * 0.3, 0]
            bob.keyTimes = [0, 0.45, 1]
            bob.duration = 0.32
            bob.repeatCount = .infinity
            bob.timeOffset = Double(index) * 0.07
            seat.add(bob, forKey: "bob")
            line.addSublayer(seat)
            rigs.append(rig)
        }
        let distance = screen.frame.width + line.bounds.width
        let length = TimeInterval(min(6.5, max(4, distance / 340)))
        line.position = CGPoint(x: screen.frame.width + line.bounds.width, y: floor)
        let run = CABasicAnimation(keyPath: "position.x")
        run.fromValue = 0
        run.toValue = distance
        run.duration = length
        canvas.addSublayer(line)
        line.add(run, forKey: "run")
        NotchMascotPlayEffects.remove(line, after: length + 0.1)
        let pan = Self.pan(screen.frame.midX)
        for at in stride(from: 0.0, to: length, by: 0.45) {
            NotchMascotSound.play(at == 0 ? .toot : .bleep, pan: pan, after: at)
        }
    }

    // MARK: Full arsenal

    private enum Weapon: CaseIterable {
        case pistol, shotgun, chaingun, rocketLauncher, plasmaRifle, bfg, chainsaw, sword
    }

    private static let muzzle = NotchMascotPlay.Energy(red: 1, green: 0.78, blue: 0.3)

    /// Every weapon orbits each of the cast; it fires across the screen to
    /// both sides, shells flying and the screen shaking, and the arsenal
    /// bursts away.
    private func idkfa() -> TimeInterval {
        eachOfCast { [weak self] companion, canvas, stage, screen in
            guard let self else { return }
            let size = companion.figureSize
            let center = stage.point(companion.screenCenter)
            let ring = self.arsenal(around: center, radius: max(46, size * 1.35), length: max(24, size * 0.6),
                                    scale: Self.scale(of: screen))
            canvas.addSublayer(ring)
            companion.cheatFace(.determined, for: 4)
            NotchMascotSound.play(.clash, pan: companion.soundPan)
            for shot in 0..<12 {
                self.step(after: 0.7 + Double(shot) * 0.24) { [weak self] in
                    self?.fire(companion, shot: shot, canvas: canvas, stage: stage, screen: screen)
                }
            }
            self.step(after: 3.8) {
                let burst = CABasicAnimation(keyPath: "transform.scale")
                burst.fromValue = 1
                burst.toValue = 2.8
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                let group = CAAnimationGroup()
                group.animations = [burst, fade]
                group.duration = 0.45
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false
                group.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ring.add(group, forKey: "burst")
                NotchMascotPlayEffects.remove(ring, after: 0.5)
                NotchMascotPlayEffects.flash(in: canvas, at: center, radius: size * 1.6, energy: Self.muzzle)
                NotchMascotSound.play(.boom, pan: companion.soundPan)
                companion.react(.celebrate)
                companion.cheatFace(.smug, for: 2)
            }
        }
        return 5.8
    }

    /// The weapons in a ring about `center`, turning twice while each stays
    /// upright, popping in one after another.
    private func arsenal(around center: CGPoint, radius: CGFloat, length: CGFloat, scale: CGFloat) -> CALayer {
        let ring = CALayer()
        ring.bounds = .zero
        ring.position = center
        let weapons = Weapon.allCases
        let turn: TimeInterval = 3.8
        for (index, weapon) in weapons.enumerated() {
            let angle = CGFloat(index) / CGFloat(weapons.count) * .pi * 2
            let icon = Self.weaponLayer(weapon, length: length, scale: scale)
            icon.position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0, 1.3, 1]
            pop.keyTimes = [0, 0.6, 1]
            pop.duration = 0.3
            pop.beginTime = CACurrentMediaTime() + Double(index) * 0.06
            pop.fillMode = .backwards
            let upright = CABasicAnimation(keyPath: "transform.rotation.z")
            upright.fromValue = 0
            upright.toValue = -CGFloat.pi * 4
            upright.duration = turn
            icon.add(pop, forKey: "pop")
            icon.add(upright, forKey: "upright")
            ring.addSublayer(icon)
        }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 4
        spin.duration = turn
        ring.add(spin, forKey: "spin")
        return ring
    }

    /// A shot from the companion's hand to the edge of the screen, every
    /// other one the other way: a muzzle flash, a tracer, a shell flying
    /// back to the floor, a bang and a shake.
    private func fire(_ companion: NotchMascotDesktop, shot: Int, canvas: CALayer, stage: NotchMascotPlayStage,
                      screen: NSScreen) {
        guard companion.isOut else { return }
        let side: CGFloat = shot.isMultiple(of: 2) ? 1 : -1
        let size = companion.figureSize
        let hand = companion.hand(toward: side)
        let muzzle = stage.point(CGPoint(x: hand.x + side * size * 0.3, y: hand.y))
        let edge = side > 0 ? screen.frame.width + 40 : -40
        let target = CGPoint(x: edge, y: muzzle.y + CGFloat.random(in: -size...size) * 0.6)
        companion.face(toward: hand.x + side * 100)
        NotchMascotPlayEffects.beam(in: canvas, from: muzzle, to: target, thickness: max(3, size * 0.08),
                                    energy: Self.muzzle, life: 0.2)
        NotchMascotPlayEffects.flash(in: canvas, at: muzzle, radius: max(18, size * 0.55), energy: Self.muzzle)
        let floor = screen.visibleFrame.minY - screen.frame.minY
        shell(in: canvas, from: muzzle, toward: -side, floor: floor, size: size)
        let bangs: [NotchMascotSoundEffect] = [.boom, .clash, .zap]
        NotchMascotSound.play(bangs[shot % bangs.count], pan: companion.soundPan)
        companion.cheatShake(amplitude: max(2, size * 0.06), duration: 0.16)
        Self.shake(canvas, amplitude: 6, duration: 0.2)
    }

    /// A brass shell thrown back over the shoulder, turning, that bounces
    /// once on `floor` and fades.
    private func shell(in canvas: CALayer, from start: CGPoint, toward side: CGFloat, floor: CGFloat, size: CGFloat) {
        let shell = CAShapeLayer()
        let width = max(3, size * 0.07), height = max(6, size * 0.16)
        shell.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                            cornerWidth: width * 0.3, cornerHeight: width * 0.3, transform: nil)
        shell.fillColor = CGColor(srgbRed: 0.93, green: 0.72, blue: 0.27, alpha: 1)
        shell.strokeColor = CGColor(srgbRed: 0.55, green: 0.38, blue: 0.08, alpha: 1)
        shell.lineWidth = 0.8
        shell.position = start
        let land = CGPoint(x: start.x + side * CGFloat.random(in: 40...90), y: floor + height / 2)
        let rest = CGPoint(x: land.x + side * 18, y: land.y)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: land, control: CGPoint(x: (start.x + land.x) / 2, y: start.y + CGFloat.random(in: 60...110)))
        path.addQuadCurve(to: rest, control: CGPoint(x: (land.x + rest.x) / 2, y: land.y + 22))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .paced
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = side * .pi * 6
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.75, 1]
        let group = CAAnimationGroup()
        group.animations = [move, spin, fade]
        group.duration = 1.1
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        shell.add(group, forKey: "shell")
        canvas.addSublayer(shell)
        NotchMascotPlayEffects.remove(shell, after: 1.15)
    }

    /// `layer` shaken from side to side, fading over `duration`.
    private static func shake(_ layer: CALayer, amplitude: CGFloat, duration: TimeInterval) {
        let shake = CAKeyframeAnimation(keyPath: "position")
        shake.values = (0...6).map { step -> NSValue in
            let fade = 1 - CGFloat(step) / 6
            guard step > 0, step < 6 else { return NSValue(point: .zero) }
            return NSValue(point: CGPoint(x: (step.isMultiple(of: 2) ? 1 : -1) * amplitude * fade,
                                          y: CGFloat.random(in: -1...1) * amplitude * fade * 0.5))
        }
        shake.duration = duration
        shake.isAdditive = true
        layer.add(shake, forKey: "shake")
    }

    /// One weapon drawn side on, muzzle to the right, `length` long, y up.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func weaponLayer(_ weapon: Weapon, length l: CGFloat, scale: CGFloat) -> CALayer {
        let h = l * 0.5
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: l, height: h)
        let ink = CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        let steel = CGColor(srgbRed: 0.42, green: 0.45, blue: 0.52, alpha: 1)
        let dark = CGColor(srgbRed: 0.22, green: 0.24, blue: 0.29, alpha: 1)
        let wood = CGColor(srgbRed: 0.55, green: 0.33, blue: 0.16, alpha: 1)
        func part(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ fill: CGColor, round: CGFloat = 0.15) {
            let rect = CGRect(x: l * x0, y: h * y0, width: l * (x1 - x0), height: h * (y1 - y0))
            let corner = min(rect.width, rect.height) * round
            let layer = CAShapeLayer()
            layer.frame = holder.bounds
            layer.contentsScale = scale
            layer.path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            layer.fillColor = fill
            layer.strokeColor = ink
            layer.lineWidth = max(0.8, l * 0.025)
            holder.addSublayer(layer)
        }
        func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: CGColor) {
            let layer = CAShapeLayer()
            layer.frame = holder.bounds
            layer.contentsScale = scale
            layer.path = CGPath(ellipseIn: CGRect(x: l * x - h * r, y: h * y - h * r, width: h * r * 2, height: h * r * 2),
                                transform: nil)
            layer.fillColor = color
            layer.shadowColor = color
            layer.shadowOpacity = 1
            layer.shadowRadius = h * r
            layer.shadowOffset = .zero
            holder.addSublayer(layer)
        }
        switch weapon {
        case .pistol:
            part(0.3, 0.42, 0.1, 0.62, dark, round: 0.3)
            part(0.25, 0.8, 0.55, 0.8, steel)
        case .shotgun:
            part(0.02, 0.3, 0.32, 0.6, wood, round: 0.3)
            part(0.28, 0.98, 0.56, 0.7, steel)
            part(0.45, 0.66, 0.4, 0.56, wood)
        case .chaingun:
            part(0.08, 0.45, 0.25, 0.85, dark)
            for (index, y) in [0.3, 0.48, 0.66].enumerated() {
                part(0.42, 0.98, CGFloat(y), CGFloat(y) + 0.14, index == 1 ? dark : steel, round: 0.5)
            }
        case .rocketLauncher:
            part(0.02, 0.96, 0.48, 0.82, CGColor(srgbRed: 0.36, green: 0.42, blue: 0.23, alpha: 1), round: 0.4)
            part(0.35, 0.47, 0.1, 0.5, dark, round: 0.3)
            glow(0.96, 0.65, 0.16, CGColor(srgbRed: 1, green: 0.32, blue: 0.2, alpha: 1))
        case .plasmaRifle:
            part(0.05, 0.85, 0.42, 0.78, CGColor(srgbRed: 0.17, green: 0.62, blue: 0.7, alpha: 1), round: 0.3)
            part(0.3, 0.42, 0.12, 0.44, dark, round: 0.3)
            for x in [0.3, 0.45, 0.6] { glow(CGFloat(x), 0.6, 0.08, CGColor(srgbRed: 0.5, green: 1, blue: 1, alpha: 1)) }
        case .bfg:
            part(0.02, 0.78, 0.2, 0.92, CGColor(srgbRed: 0.24, green: 0.52, blue: 0.22, alpha: 1), round: 0.25)
            glow(0.84, 0.56, 0.3, CGColor(srgbRed: 0.45, green: 1, blue: 0.35, alpha: 1))
        case .chainsaw:
            part(0.02, 0.42, 0.22, 0.82, CGColor(srgbRed: 0.91, green: 0.45, blue: 0.16, alpha: 1), round: 0.3)
            part(0.4, 0.99, 0.38, 0.66, steel, round: 0.5)
            let teeth = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: l * 0.42, y: h * 0.68))
            for index in 0..<8 {
                let x = l * (0.42 + CGFloat(index) * 0.07)
                path.addLine(to: CGPoint(x: x + l * 0.035, y: h * 0.8))
                path.addLine(to: CGPoint(x: x + l * 0.07, y: h * 0.68))
            }
            teeth.frame = holder.bounds
            teeth.path = path
            teeth.fillColor = nil
            teeth.strokeColor = ink
            teeth.lineWidth = max(0.8, l * 0.025)
            holder.addSublayer(teeth)
        case .sword:
            part(0.02, 0.2, 0.42, 0.58, wood, round: 0.4)
            part(0.2, 0.26, 0.15, 0.85, CGColor(srgbRed: 0.95, green: 0.78, blue: 0.3, alpha: 1), round: 0.4)
            part(0.26, 0.98, 0.42, 0.58, CGColor(srgbRed: 0.86, green: 0.9, blue: 0.96, alpha: 1), round: 0.5)
        }
        return holder
    }

    // MARK: God mode

    /// God rays and a golden aura behind each of the cast; it rises with
    /// stars in its eyes, hangs there glowing, and comes down untouchable
    /// for a while.
    private func iddqd() -> TimeInterval {
        let length: TimeInterval = 6
        eachOfCast { [weak self] companion, canvas, stage, screen in
            let size = companion.figureSize
            let center = stage.point(companion.screenCenter)
            let lift = size * 0.42
            let reach = min(screen.frame.height * 0.6, 560)
            let glory = Self.godRays(reach: reach, aura: size * 1.5, length: length)
            glory.position = center
            let rise = CAKeyframeAnimation(keyPath: "position.y")
            rise.values = [0, lift, lift * 0.82, lift, lift * 0.82, lift, 0]
            rise.keyTimes = [0, 0.18, 0.34, 0.5, 0.66, 0.82, 1]
            rise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            rise.duration = length
            rise.isAdditive = true
            glory.add(rise, forKey: "rise")
            canvas.insertSublayer(glory, at: 0)
            NotchMascotPlayEffects.remove(glory, after: length + 0.1)
            companion.grantGodMode(for: Self.godLength)
            companion.cheatFace(.starstruck, for: length)
            companion.cheatLevitate(lift: lift, duration: length)
            let pan = companion.soundPan
            NotchMascotSound.play(.magic, pan: pan)
            NotchMascotSound.play(.chime, pan: pan, after: 1.0)
            NotchMascotSound.play(.chime, pan: pan, after: 3.0)
            NotchMascotSound.play(.magic, pan: pan, after: length - 0.8)
            for at in [1.2, 2.6, 4.0] {
                self?.step(after: at) {
                    NotchMascotPlayEffects.burst(.sparkles, in: canvas,
                                                 at: CGPoint(x: center.x, y: center.y + lift + size * 0.4), size: size * 1.2,
                                                 energy: NotchMascotPlay.Energy(red: 1, green: 0.85, blue: 0.35))
                }
            }
        }
        return length + 0.4
    }

    /// Rays of gold `reach` long turning slowly about a glow `aura` wide,
    /// fading in and out over `length`.
    private static func godRays(reach: CGFloat, aura: CGFloat, length: TimeInterval) -> CALayer {
        let gold = CGColor(srgbRed: 1, green: 0.84, blue: 0.36, alpha: 0.55)
        let clear = CGColor(srgbRed: 1, green: 0.84, blue: 0.36, alpha: 0)
        let glory = CALayer()
        glory.bounds = .zero
        let rays = CALayer()
        rays.bounds = .zero
        let count = 14
        for index in 0..<count {
            let width = reach * (index.isMultiple(of: 2) ? 0.2 : 0.12)
            let ray = CAGradientLayer()
            ray.colors = [gold, clear]
            ray.startPoint = CGPoint(x: 0, y: 0.5)
            ray.endPoint = CGPoint(x: 1, y: 0.5)
            ray.anchorPoint = CGPoint(x: 0, y: 0.5)
            ray.bounds = CGRect(x: 0, y: 0, width: reach, height: width)
            ray.position = .zero
            ray.transform = CATransform3DMakeRotation(CGFloat(index) / CGFloat(count) * .pi * 2, 0, 0, 1)
            let wedge = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: width / 2))
            path.addLine(to: CGPoint(x: reach, y: 0))
            path.addLine(to: CGPoint(x: reach, y: width))
            path.closeSubpath()
            wedge.path = path
            ray.mask = wedge
            rays.addSublayer(ray)
        }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = CGFloat.pi * 0.4
        turn.duration = length
        rays.add(turn, forKey: "turn")
        glory.addSublayer(rays)
        let halo = CAGradientLayer()
        halo.type = .radial
        halo.colors = [CGColor(srgbRed: 1, green: 0.95, blue: 0.7, alpha: 0.85), gold, clear]
        halo.locations = [0, 0.4, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.bounds = CGRect(x: 0, y: 0, width: aura * 2, height: aura * 2)
        halo.position = .zero
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.85
        pulse.toValue = 1.15
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        halo.add(pulse, forKey: "pulse")
        glory.addSublayer(halo)
        glory.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.85, 1]
        fade.duration = length
        glory.add(fade, forKey: "fade")
        return glory
    }

    // MARK: No clip

    /// Each of the cast turns see-through, hops, falls through the floor
    /// and the bottom of the screen, and drops in again from the top,
    /// through any window on the way down.
    private func idclip() -> TimeInterval {
        eachOfCast(stagger: 0.4) { companion, canvas, stage, _ in
            companion.grantNoClip(for: Self.ghostLength)
            companion.cheatFace(.mischievous, for: 3)
            NotchMascotSound.play(.poof, pan: companion.soundPan)
            NotchMascotPlayEffects.magicSmoke(in: canvas, at: stage.point(companion.screenCenter),
                                              radius: companion.figureSize * 0.6,
                                              energy: NotchMascotPlay.Energy(red: 0.7, green: 0.85, blue: 1))
            companion.hop(dx: 0, dy: 380)
        }
        return Self.ghostLength + 0.6
    }

    // MARK: Barrel roll

    /// Each of the cast rolls right round three times in a row, leaping,
    /// one after the other in a wave, and looks dizzy for it after.
    private func roll() -> TimeInterval {
        let stagger: TimeInterval = 0.35
        eachOfCast(stagger: stagger) { [weak self] companion, canvas, stage, _ in
            guard let self else { return }
            let floor = companion.floor
            let side: CGFloat = companion.screenCenter.x < (floor.lowerBound + floor.upperBound) / 2 ? 1 : -1
            companion.cheatFace(.mischievous, for: 2.4)
            for roll in 0..<3 {
                self.step(after: Double(roll) * 0.72) {
                    guard companion.isOut else { return }
                    let way = roll == 2 ? -side : side
                    companion.hop(dx: way * 230, dy: 640)
                    companion.host?.mascot.spin(turns: way, duration: 0.62)
                    NotchMascotSound.play(.whoosh, pan: companion.soundPan)
                    NotchMascotPlayEffects.sparks(in: canvas, at: stage.point(companion.screenCenter),
                                                  reach: companion.figureSize * 0.9,
                                                  energy: NotchMascotPlay.energy(for: companion.playLook))
                }
            }
            self.step(after: 2.3) { companion.cheatFace(.dizzy, for: 1.4) }
        }
        return stagger * Double(max(0, cast.count - 1)) + 4
    }

    // MARK: Motherlode

    /// A coin falling under gravity on a stage until it lies on the pile.
    private struct Coin {
        let layer: CALayer
        var position: CGPoint
        var velocity: CGVector
        let radius: CGFloat
        let stage: Int
        let floor: CGFloat
        let width: CGFloat
        let screenX: CGFloat
        let start: CFTimeInterval
        var resting = false
    }

    private static let coinGravity: CGFloat = 1900
    private static let coinColumn: CGFloat = 12

    /// Gold rains on every screen, bouncing and piling on the floor; the
    /// cast gets money in its eyes and hops about in the pile; the gold
    /// fades after a while.
    private func motherlode() -> TimeInterval {
        let now = CACurrentMediaTime()
        var budget = 220
        for screen in NSScreen.screens where budget > 0 {
            guard let canvas = canvas(on: screen)?.layer else { continue }
            let width = screen.frame.width
            let floor = screen.visibleFrame.minY - screen.frame.minY
            let index = piles.count
            piles.append(Array(repeating: 0, count: Int(width / Self.coinColumn) + 1))
            let count = min(budget, min(110, Int(width / 14)))
            budget -= count
            for _ in 0..<count {
                let radius = CGFloat.random(in: 5...8)
                let side = radius * 2.4
                let start = CGPoint(x: CGFloat.random(in: radius...(width - radius)),
                                    y: screen.frame.height + side + CGFloat.random(in: 0...120))
                let layer = NotchMascotPlayEffects.propLayer(
                    NotchMascotRPGShapes.coin(at: CGPoint(x: side / 2, y: side / 2), radius: radius),
                    side: side, at: start, scale: Self.scale(of: screen))
                let turn = CAKeyframeAnimation(keyPath: "transform.scale.x")
                turn.values = [1, 0.2, 1]
                turn.duration = 0.5
                turn.repeatCount = .infinity
                turn.timeOffset = Double.random(in: 0...0.5)
                layer.add(turn, forKey: "turn")
                canvas.addSublayer(layer)
                coins.append(Coin(layer: layer, position: start,
                                  velocity: CGVector(dx: CGFloat.random(in: -50...50), dy: CGFloat.random(in: -120...0)),
                                  radius: radius, stage: index, floor: floor, width: width, screenX: screen.frame.minX,
                                  start: now + Double.random(in: 0...2.4)))
            }
        }
        startCoins()
        eachOfCast(stagger: 0.15) { [weak self] companion, canvas, stage, _ in
            guard let self else { return }
            let size = companion.figureSize
            companion.cheatFace(.greedy, for: Self.coinLife)
            NotchMascotPlayEffects.arcadeMarker("+10000", in: canvas,
                                                at: stage.point(CGPoint(x: companion.head.x, y: companion.head.y + size * 0.3)),
                                                cell: max(2, size * 0.06))
            for (hop, at) in [1.2, 2.1, 3.0, 3.9, 4.8].enumerated() {
                self.step(after: at) {
                    guard companion.isOut else { return }
                    companion.hop(dx: CGFloat.random(in: -60...60), dy: hop.isMultiple(of: 2) ? 440 : 360)
                    let feet = companion.feet ?? CGPoint(x: companion.screenCenter.x, y: companion.screenCenter.y - size / 2)
                    NotchMascotPlayEffects.goldCoins(in: canvas, at: stage.point(feet), radius: max(3, size * 0.11), count: 5)
                    NotchMascotSound.play(.coin, pan: companion.soundPan)
                }
            }
        }
        step(after: Self.coinLife) { [weak self] in
            guard let self else { return }
            for coin in self.coins {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = 0.8
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                coin.layer.add(fade, forKey: "fade")
            }
        }
        return Self.coinLife + 1
    }

    /// The gold falls frame by frame while some of it is still in the air.
    private func startCoins() {
        coinTimer?.cancel()
        lastCoinTick = CACurrentMediaTime()
        let started = lastCoinTick
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if !self.tickCoins(now: now) || now - started > 7 {
                self.coinTimer?.cancel()
                self.coinTimer = nil
            }
        }
        coinTimer = timer
        timer.resume()
    }

    /// Moves the gold on to `now`: falling, bouncing off the screen's sides
    /// and the floor, and lying down on the pile once slow. False once all of
    /// it lies there.
    private func tickCoins(now: CFTimeInterval) -> Bool {
        let dt = CGFloat(min(0.05, now - lastCoinTick))
        lastCoinTick = now
        var falling = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in coins.indices where !coins[index].resting {
            falling = true
            guard now >= coins[index].start else { continue }
            var coin = coins[index]
            coin.velocity.dy -= Self.coinGravity * dt
            coin.position.x += coin.velocity.dx * dt
            coin.position.y += coin.velocity.dy * dt
            if coin.position.x < coin.radius || coin.position.x > coin.width - coin.radius {
                coin.position.x = min(coin.width - coin.radius, max(coin.radius, coin.position.x))
                coin.velocity.dx = -coin.velocity.dx * 0.5
            }
            let column = min(piles[coin.stage].count - 1, max(0, Int(coin.position.x / Self.coinColumn)))
            let ground = coin.floor + piles[coin.stage][column] + coin.radius * 0.5
            if coin.position.y <= ground, coin.velocity.dy < 0 {
                coin.position.y = ground
                if -coin.velocity.dy > 170 {
                    coin.velocity.dy = -coin.velocity.dy * 0.38
                    coin.velocity.dx *= 0.7
                    clink(at: coin.screenX + coin.position.x, now: now)
                } else {
                    coin.resting = true
                    piles[coin.stage][column] += coin.radius * 0.5
                    for near in [column - 1, column + 1] where piles[coin.stage].indices.contains(near) {
                        piles[coin.stage][near] += coin.radius * 0.2
                    }
                    coin.layer.removeAnimation(forKey: "turn")
                    coin.layer.transform = CATransform3DMakeScale(1, 0.55, 1)
                }
            }
            coin.layer.position = coin.position
            coins[index] = coin
        }
        CATransaction.commit()
        return falling
    }

    /// A coin rings on the floor at screen point `x`, at most so often.
    private func clink(at x: CGFloat, now: CFTimeInterval) {
        guard now - lastClink > 0.09 else { return }
        lastClink = now
        NotchMascotSound.play(.coin, pan: Self.pan(x))
    }

    // MARK: Party

    /// The gang is called out; confetti rains on every screen and bursts
    /// from its bottom corners; the cast cheers, hops and bursts with it.
    private func party() -> TimeInterval {
        everyScreen { canvas, area, floor in
            let count = min(150, max(40, Int(area.width / 10)))
            for _ in 0..<count { confetti(in: canvas, area: area, floor: floor) }
            for corner in [CGFloat(0), area.width] {
                for _ in 0..<26 { confettiShot(in: canvas, from: CGPoint(x: corner, y: floor), area: area) }
            }
            NotchMascotSound.play(.boom, pan: 0)
        }
        eachOfCast(stagger: 0.2) { [weak self] companion, canvas, stage, _ in
            guard let self else { return }
            let size = companion.figureSize
            companion.react(.celebrate)
            companion.cheatFace(.starstruck, for: 4)
            NotchMascotSound.play(.toot, pan: companion.soundPan)
            for (beat, at) in [0.0, 0.7, 1.4, 2.1].enumerated() {
                self.step(after: at) {
                    guard companion.isOut else { return }
                    NotchMascotPlayEffects.burst(.confetti, in: canvas, at: stage.point(companion.head), size: size * 1.8,
                                                 energy: NotchMascotPlay.energy(for: companion.playLook))
                    if beat > 0 { companion.hop(dx: 0, dy: 520) }
                }
            }
            self.step(after: 2.9) { companion.sway(amplitude: 0.35, speed: 14, duration: 1.6) }
        }
        return 5.4
    }

    private static let confettiColors: [UInt32] = [0xFF5E8A, 0xFFD23F, 0x6C8CFF, 0x3FB8AF, 0xFF8C2B, 0xB57CFF, 0x5CE07A]

    private static func confettiPiece() -> CAShapeLayer {
        let piece = CAShapeLayer()
        let width = CGFloat.random(in: 4...7), height = CGFloat.random(in: 7...12)
        piece.path = Bool.random()
            ? CGPath(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), transform: nil)
            : CGPath(ellipseIn: CGRect(x: -width / 2, y: -width / 2, width: width, height: width), transform: nil)
        piece.fillColor = NotchMascotRPGShapes.rgb(confettiColors.randomElement() ?? 0xFFD23F)
        return piece
    }

    /// A piece of confetti fluttering down from over the top of the screen to `floor`.
    private func confetti(in canvas: CALayer, area: CGRect, floor: CGFloat) {
        let piece = Self.confettiPiece()
        let x = CGFloat.random(in: 0...area.width)
        let fall = TimeInterval.random(in: 2.6...4.4)
        let delay = TimeInterval.random(in: 0...1.4)
        let drift = CGFloat.random(in: 20...60)
        let top = area.height + 12
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = (0...6).map { step -> NSValue in
            let t = CGFloat(step) / 6
            return NSValue(point: CGPoint(x: x + sin(t * .pi * 3) * drift, y: top - (top - floor + 10) * t))
        }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.random(in: -1...1) * .pi * 6
        let flutter = CAKeyframeAnimation(keyPath: "transform.scale.x")
        flutter.values = [1, -1, 1]
        flutter.duration = TimeInterval.random(in: 0.4...0.8)
        flutter.repeatCount = .infinity
        let group = CAAnimationGroup()
        group.animations = [move, spin, flutter]
        group.duration = fall
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        piece.position = CGPoint(x: x, y: top)
        piece.add(group, forKey: "fall")
        canvas.addSublayer(piece)
        NotchMascotPlayEffects.remove(piece, after: delay + fall)
    }

    /// A piece of confetti shot up and in from `start`, at a bottom corner, falling back as it goes.
    private func confettiShot(in canvas: CALayer, from start: CGPoint, area: CGRect) {
        let piece = Self.confettiPiece()
        let inward: CGFloat = start.x < area.midX ? 1 : -1
        let end = CGPoint(x: start.x + inward * CGFloat.random(in: 0.12...0.4) * area.width,
                          y: start.y + CGFloat.random(in: -10...80))
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 - inward * 40,
                                                    y: start.y + area.height * CGFloat.random(in: 0.35...0.7)))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = inward * .pi * 8
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.8, 1]
        let group = CAAnimationGroup()
        group.animations = [move, spin, fade]
        group.duration = TimeInterval.random(in: 1.6...2.4)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        piece.position = start
        piece.add(group, forKey: "shot")
        canvas.addSublayer(piece)
        NotchMascotPlayEffects.remove(piece, after: group.duration)
    }

    // MARK: Big head

    /// Each of the cast's head swells for a good while; it looks pleased
    /// with itself and hops to show it off.
    private func bighead() -> TimeInterval {
        eachOfCast(stagger: 0.3) { [weak self] companion, _, _, _ in
            companion.grantBigHead(for: Self.bigHeadLength)
            companion.cheatFace(.smug, for: 3)
            self?.step(after: 0.8) { if companion.isOut { companion.hop(dx: 0, dy: 420) } }
        }
        return 2.4
    }

    // MARK: There is no spoon

    /// Green code falls down every screen; the cast moves in slow motion a
    /// while, and leans far back as slow bullets pass it by.
    private func thereIsNoSpoon() -> TimeInterval {
        let length: TimeInterval = 7
        everyScreen { canvas, area, _ in codeRain(in: canvas, area: area, for: length) }
        NotchMascotSound.play(.warble, pan: 0)
        eachOfCast(stagger: 0.2) { [weak self] companion, canvas, stage, screen in
            guard let self else { return }
            companion.grantSlowMotion(for: Self.slowLength)
            companion.cheatFace(.determined, for: 5)
            let side: CGFloat = companion.screenCenter.x < screen.frame.midX ? 1 : -1
            self.step(after: 0.8) {
                guard companion.isOut else { return }
                companion.tilt(side * 0.85, for: 3.4)
                self.bullets(past: companion, from: side, canvas: canvas, stage: stage, screen: screen)
            }
        }
        return length + 0.4
    }

    /// Columns of green glyphs falling down the screen, brightest at their
    /// heads, over a darker screen, for `length` seconds.
    private func codeRain(in canvas: CALayer, area: CGRect, for length: TimeInterval) {
        let holder = CALayer()
        holder.frame = area
        let shade = CALayer()
        shade.frame = area
        shade.backgroundColor = CGColor(srgbRed: 0, green: 0.06, blue: 0.02, alpha: 0.42)
        holder.addSublayer(shade)
        let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜ0123456789Z:.=*+<>")
        let fontSize: CGFloat = 15
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let spacing: CGFloat = 20
        let columns = min(90, Int(area.width / spacing))
        let scale = canvas.contentsScale > 0 ? canvas.contentsScale : 2
        for column in 0..<columns {
            let rows = Int.random(in: 10...24)
            let text = NSMutableAttributedString()
            for row in 0..<rows {
                let head = row == rows - 1
                let alpha = head ? 1 : 0.15 + 0.75 * CGFloat(row) / CGFloat(rows)
                let color = head ? NSColor(srgbRed: 0.85, green: 1, blue: 0.88, alpha: 1)
                    : NSColor(srgbRed: 0.2, green: 1, blue: 0.4, alpha: alpha)
                text.append(NSAttributedString(string: String(glyphs.randomElement() ?? "0") + (head ? "" : "\n"),
                                               attributes: [.font: font, .foregroundColor: color]))
            }
            let line = CATextLayer()
            line.string = text
            line.contentsScale = scale
            line.alignmentMode = .center
            let height = CGFloat(rows) * fontSize * 1.2
            line.bounds = CGRect(x: 0, y: 0, width: spacing, height: height)
            line.shadowColor = CGColor(srgbRed: 0.2, green: 1, blue: 0.4, alpha: 1)
            line.shadowOpacity = 0.8
            line.shadowRadius = 3
            line.shadowOffset = .zero
            let x = (CGFloat(column) + 0.5) * spacing
            line.position = CGPoint(x: x, y: area.height + height / 2)
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = area.height + height / 2
            fall.toValue = -height / 2
            fall.duration = TimeInterval.random(in: 1.8...3.6)
            fall.repeatCount = Float(length / fall.duration).rounded(.up)
            fall.beginTime = CACurrentMediaTime() + TimeInterval.random(in: 0...1.6)
            fall.fillMode = .backwards
            line.add(fall, forKey: "fall")
            holder.addSublayer(line)
        }
        holder.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.88, 1]
        fade.duration = length
        holder.add(fade, forKey: "fade")
        canvas.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: length)
    }

    /// Three bullets crossing the screen slowly from side `side` past the
    /// companion's head, each trailing rings in the air.
    private func bullets(past companion: NotchMascotDesktop, from side: CGFloat, canvas: CALayer,
                         stage: NotchMascotPlayStage, screen: NSScreen) {
        let size = companion.figureSize
        let head = stage.point(companion.head)
        let width = screen.frame.width
        let cross: TimeInterval = 3.2
        for index in 0..<3 {
            let y = head.y + CGFloat(index - 1) * size * 0.35
            let start = CGPoint(x: side > 0 ? -20 : width + 20, y: y)
            let end = CGPoint(x: side > 0 ? width + 20 : -20, y: y)
            let delay = Double(index) * 0.35
            let bullet = CAShapeLayer()
            bullet.path = CGPath(roundedRect: CGRect(x: -7, y: -2.5, width: 14, height: 5), cornerWidth: 2.5,
                                 cornerHeight: 2.5, transform: nil)
            bullet.fillColor = CGColor(srgbRed: 0.75, green: 0.72, blue: 0.62, alpha: 1)
            bullet.position = start
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: start)
            move.toValue = NSValue(point: end)
            move.duration = cross
            move.beginTime = CACurrentMediaTime() + delay
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            bullet.add(move, forKey: "fly")
            canvas.addSublayer(bullet)
            NotchMascotPlayEffects.remove(bullet, after: delay + cross)
            for ring in 0..<10 {
                let t = (Double(ring) + 0.5) / 10
                let at = CGPoint(x: start.x + (end.x - start.x) * CGFloat(t), y: y)
                let circle = CAShapeLayer()
                circle.path = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
                circle.fillColor = nil
                circle.strokeColor = CGColor(srgbRed: 0.7, green: 1, blue: 0.75, alpha: 0.7)
                circle.lineWidth = 1.2
                circle.position = at
                circle.opacity = 0
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.3
                grow.toValue = 2.6
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.9
                fade.toValue = 0
                let group = CAAnimationGroup()
                group.animations = [grow, fade]
                group.duration = 1.2
                group.beginTime = CACurrentMediaTime() + delay + cross * t
                circle.add(group, forKey: "ripple")
                canvas.addSublayer(circle)
                NotchMascotPlayEffects.remove(circle, after: delay + cross * t + 1.25)
            }
            NotchMascotSound.play(.whoosh, pan: companion.soundPan, after: delay + cross / 2)
        }
    }

    // MARK: Moonwalk

    /// Gravity lets go of each of the cast a while: it floats up and drifts
    /// down, then slides backwards across the floor and back, stars at its feet.
    private func moonwalk() -> TimeInterval {
        eachOfCast(stagger: 0.3) { [weak self] companion, canvas, stage, _ in
            guard let self else { return }
            companion.grantMoonwalk(for: Self.moonLength)
            companion.cheatFace(.smug, for: 7)
            NotchMascotSound.play(.warble, pan: companion.soundPan)
            self.step(after: 0.3) { if companion.isOut { companion.hop(dx: 0, dy: 560) } }
            let floor = companion.floor
            let x = companion.screenCenter.x
            let side: CGFloat = x < (floor.lowerBound + floor.upperBound) / 2 ? 1 : -1
            self.step(after: 2.9) {
                guard companion.isOut else { return }
                companion.stroll(to: x + side * 240, pace: 1.7)
                NotchMascotSound.play(.whoosh, pan: companion.soundPan)
            }
            self.step(after: 6.4) { if companion.isOut { companion.stroll(to: x, pace: 1.7) } }
            for at in stride(from: 3.1, to: 9.6, by: 0.45) {
                self.step(after: at) {
                    guard companion.isOut, let feet = companion.feet else { return }
                    NotchMascotPlayEffects.float("✦", in: canvas, at: stage.point(feet), size: max(9, companion.figureSize * 0.2),
                                                 color: CGColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 1), rise: 18)
                }
            }
        }
        return 10
    }
}
