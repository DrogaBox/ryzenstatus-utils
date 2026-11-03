// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What the cheats typed lately do to one companion out on the desktop,
/// each until a moment on the media clock.
struct NotchMascotCheatState {
    /// God mode: thrown, dropped or shaken, it lands without getting dizzy.
    var invulnerableUntil: CFTimeInterval = -.infinity
    /// No clip: it is see-through, and no window holds it up.
    var ghostUntil: CFTimeInterval = -.infinity
    /// No clip: it falls through the bottom of the screen once, and drops in
    /// again from the top.
    var fallsThrough = false
    /// There is no spoon: it moves at a fraction of its pace.
    var slowUntil: CFTimeInterval = -.infinity
    /// Moonwalk: gravity barely holds it, and it walks backwards as it slides.
    var moonUntil: CFTimeInterval = -.infinity
    /// Big-head mode.
    var bigHeadUntil: CFTimeInterval = -.infinity
}

/// The cheats' hold on the companion out on the desktop: what its physics
/// reads as it moves, and the looks a show gives it for a while.
extension NotchMascotDesktop {
    // MARK: What its physics reads

    /// How many times its usual pace it moves at: a fraction of it in slow motion.
    var cheatPace: Double {
        CACurrentMediaTime() < cheat.slowUntil ? Double(NotchMascotCheatShows.slowPace) : 1
    }
    /// How many times gravity pulls it: barely, in low gravity.
    var cheatGravity: CGFloat {
        CACurrentMediaTime() < cheat.moonUntil ? NotchMascotCheatShows.moonGravity : 1
    }
    /// It lands hard without getting dizzy.
    var cheatInvulnerable: Bool { CACurrentMediaTime() < cheat.invulnerableUntil }
    /// No window holds it up.
    var cheatPassesThrough: Bool { CACurrentMediaTime() < cheat.ghostUntil }

    /// The way its legs go for a walk toward `direction`: the other way while
    /// it moonwalks, so it slides backwards.
    func cheatStride(_ direction: CGFloat?) -> CGFloat? {
        guard CACurrentMediaTime() < cheat.moonUntil else { return direction }
        return direction.map { -$0 }
    }

    /// The part of the screen it falls in, `area` as a rule. Falling through,
    /// the floor is gone; once well under the screen's bottom it is at the
    /// top of the screen again, falling, and the floor is back.
    func cheatArea(_ area: CGRect, body: inout NotchMascotRoam.Body) -> CGRect {
        guard cheat.fallsThrough else { return area }
        guard cheatPassesThrough else {
            cheat.fallsThrough = false
            return area
        }
        guard body.position.y < area.minY - figureSize * 1.6 else {
            return CGRect(x: area.minX, y: area.minY - 100_000, width: area.width, height: area.height + 100_000)
        }
        cheat.fallsThrough = false
        body.position.y = area.maxY - figureSize
        body.velocity = CGVector(dx: body.velocity.dx * 0.3, dy: -160)
        NotchMascotSound.play(.poof, pan: NotchMascotSoundMap.pan(screenX: body.position.x,
                                                                across: NSScreen.screens.map(\.frame)))
        return area
    }

    // MARK: Looks a show gives it

    /// The layer its figure is drawn in, inside its window's view.
    private var figureStage: CALayer? { host?.mascot.root.superlayer }

    /// Shakes where it stands, `amplitude` points either way, fading over `duration`.
    func cheatShake(amplitude: CGFloat, duration: TimeInterval) {
        guard isOut, let root = host?.mascot.root, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let steps = 10
        let shake = CAKeyframeAnimation(keyPath: "position")
        shake.values = (0...steps).map { step -> NSValue in
            let fade = 1 - CGFloat(step) / CGFloat(steps)
            guard step > 0, step < steps else { return NSValue(point: .zero) }
            let side: CGFloat = step.isMultiple(of: 2) ? 1 : -1
            return NSValue(point: CGPoint(x: side * amplitude * fade, y: CGFloat.random(in: -0.5...0.5) * amplitude * fade))
        }
        shake.duration = duration
        shake.isAdditive = true
        root.add(shake, forKey: "cheatShake")
    }

    /// Shows `mood` on its face for `length` seconds, then the face it had.
    func cheatFace(_ mood: NotchMascotMood, for length: TimeInterval) {
        guard isOut, let host else { return }
        host.mascot.setMood(mood, animated: true)
        let lasts = outingLasts
        DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in
            guard let self, lasts(), self.host?.mascot.mood == mood else { return }
            self.host?.mascot.setMood(self.mood, animated: true)
        }
    }

    /// Rises `lift` points off the floor, hangs there bobbing and comes down
    /// again over `duration`. Only its figure rises: its feet stay where it stood.
    func cheatLevitate(lift: CGFloat, duration: TimeInterval) {
        guard isOut, let root = host?.mascot.root, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // The figure's parent lays out from the top: up is less.
        let rise = CAKeyframeAnimation(keyPath: "position.y")
        rise.values = [0, -lift, -lift * 0.82, -lift, -lift * 0.82, -lift, 0]
        rise.keyTimes = [0, 0.18, 0.34, 0.5, 0.66, 0.82, 1]
        rise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rise.duration = duration
        rise.isAdditive = true
        root.add(rise, forKey: "cheatLevitate")
    }

    // MARK: Lasting a while

    /// God mode for `length` seconds: a golden glow about it, and no landing
    /// makes it dizzy.
    func grantGodMode(for length: TimeInterval) {
        guard isOut else { return }
        cheat.invulnerableUntil = CACurrentMediaTime() + length
        setGlow(CGColor(srgbRed: 1, green: 0.82, blue: 0.3, alpha: 1))
        after(length) { companion in
            guard !companion.cheatInvulnerable else { return }
            companion.setGlow(nil)
        }
    }

    /// See-through for `length` seconds, windows let it through, and it
    /// falls through the bottom of the screen once to drop in from the top.
    func grantNoClip(for length: TimeInterval) {
        guard isOut, let root = host?.mascot.root else { return }
        cheat.ghostUntil = CACurrentMediaTime() + length
        cheat.fallsThrough = true
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [1, 0.15, 0.8, 0.25, 0.6, NotchMascotCheatShows.ghostOpacity]
        flicker.duration = 0.45
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = Float(NotchMascotCheatShows.ghostOpacity)
        CATransaction.commit()
        root.add(flicker, forKey: "cheatGhost")
        after(length) { companion in
            guard !companion.cheatPassesThrough, let root = companion.host?.mascot.root else { return }
            companion.cheat.fallsThrough = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.opacity = 1
            CATransaction.commit()
            let back = CAKeyframeAnimation(keyPath: "opacity")
            back.values = [NotchMascotCheatShows.ghostOpacity, 0.9, 0.3, 1]
            back.duration = 0.35
            root.add(back, forKey: "cheatGhost")
        }
    }

    /// Slow motion for `length` seconds.
    func grantSlowMotion(for length: TimeInterval) {
        guard isOut else { return }
        cheat.slowUntil = CACurrentMediaTime() + length
    }

    /// Low gravity and a moonwalk for `length` seconds.
    func grantMoonwalk(for length: TimeInterval) {
        guard isOut else { return }
        cheat.moonUntil = CACurrentMediaTime() + length
    }

    /// Big-head mode for `length` seconds: its head swells with a boing and
    /// the rest of it shrinks under it, and it all goes back with a pop.
    func grantBigHead(for length: TimeInterval) {
        guard isOut, let stage = figureStage, let host else { return }
        let had = CACurrentMediaTime() < cheat.bigHeadUntil
        cheat.bigHeadUntil = CACurrentMediaTime() + length
        if !had {
            let feet = host.bounds.height / 2 - NotchMascotRoam.footInset(for: figureSize)
            let size = figureSize
            let frames: [(squeeze: CGFloat, swell: CGFloat)] = [(1, 0), (0.78, 0.68), (0.82, 0.5), (0.79, 0.64),
                                                                 (0.81, 0.57), NotchMascotCheatShows.bigHead]
            let swell = CAKeyframeAnimation(keyPath: "sublayerTransform")
            swell.values = frames.map {
                NSValue(caTransform3D: NotchMascotCheatShows.bigHeadTransform(squeeze: $0.squeeze, swell: $0.swell,
                                                                              size: size, feet: feet))
            }
            swell.duration = 0.7
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stage.sublayerTransform = NotchMascotCheatShows.bigHeadTransform(squeeze: NotchMascotCheatShows.bigHead.squeeze,
                                                                            swell: NotchMascotCheatShows.bigHead.swell,
                                                                            size: size, feet: feet)
            CATransaction.commit()
            stage.add(swell, forKey: "cheatBigHead")
            NotchMascotSound.play(.boing, pan: soundPan)
        }
        after(length) { companion in
            guard CACurrentMediaTime() >= companion.cheat.bigHeadUntil - 0.05 else { return }
            companion.endBigHead()
        }
    }

    /// Its head goes back to its size with a pop.
    private func endBigHead() {
        cheat.bigHeadUntil = -.infinity
        guard let stage = figureStage else { return }
        let shrink = CABasicAnimation(keyPath: "sublayerTransform")
        shrink.fromValue = NSValue(caTransform3D: stage.sublayerTransform)
        shrink.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        shrink.duration = 0.25
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()
        stage.add(shrink, forKey: "cheatBigHead")
        if isOut { NotchMascotSound.play(.pop, pan: soundPan) }
    }

    /// Where a sound it makes is heard.
    var soundPan: Float {
        NotchMascotSoundMap.pan(screenX: screenCenter.x, across: NSScreen.screens.map(\.frame))
    }

    /// A glow of `color` about its figure, or none.
    private func setGlow(_ color: CGColor?) {
        guard let layer = host?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = color
        layer.shadowOffset = .zero
        layer.shadowRadius = color == nil ? 0 : max(6, figureSize * 0.16)
        layer.shadowOpacity = color == nil ? 0 : 1
        CATransaction.commit()
        guard color != nil else {
            layer.removeAnimation(forKey: "cheatGlow")
            return
        }
        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = max(6, figureSize * 0.1)
        pulse.toValue = max(9, figureSize * 0.24)
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "cheatGlow")
    }

    /// Runs `block` with it `delay` seconds from now, whether it is out or
    /// in by then: what a cheat gave it ends either way.
    private func after(_ delay: TimeInterval, _ block: @escaping (NotchMascotDesktop) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) { [weak self] in
            guard let self else { return }
            block(self)
        }
    }
}
