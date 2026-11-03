// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Everything the hologram and the android are drawn with beyond their
/// body and eyes, in three groups the decor stacks behind the body, over
/// it and in front of everything. The hologram: a cone of light from a
/// little projector, colour fringes and fine lines of light round a chibi
/// idol with twin tails, a dress and ribbons, glitching as she reacts. The
/// android: a helmet with a glass face screen, dark joints and little
/// lights, a ring at its heart that fills with the CPU's load, and the
/// thrusters it floats on. Hidden for every other figure.
final class NotchMascotSignalParts {
    let back = CALayer()
    let middle = CALayer()
    let front = CALayer()

    private(set) var style: NotchMascotStyle?
    private var size: CGFloat = 0
    private var sleeping = false
    private var level = 1
    private var colors = NotchMascotSignalColors(light: NotchMascotPalette.sky.light, shade: NotchMascotPalette.sky.shade)

    // The hologram.
    private let beam = CAGradientLayer()
    private let beamMask = CAShapeLayer()
    private let fringeLeft = CAShapeLayer()
    private let fringeRight = CAShapeLayer()
    private let hairBack = CAShapeLayer()
    private let platform = CAShapeLayer()
    private let projector = CAShapeLayer()
    private let lens = CAShapeLayer()
    private let skin = CAGradientLayer()
    private let skinMask = CAShapeLayer()
    private let dress = CAGradientLayer()
    private let dressMask = CAShapeLayer()
    private let legFade = CAGradientLayer()
    private let legMask = CAShapeLayer()
    private let boots = CAShapeLayer()
    private let trim = CAShapeLayer()
    private let ribbons = CAShapeLayer()
    private let hair = CAShapeLayer()
    private let hairShine = CAShapeLayer()
    private let scanlines = CAShapeLayer()
    private let glitch = CAShapeLayer()

    // The android.
    private let thrusters = CAGradientLayer()
    private let thrusterMask = CAShapeLayer()
    private let hover = CAShapeLayer()
    private let seams = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let lights = CAShapeLayer()
    private let visor = CALayer()
    private let visorMask = CAShapeLayer()
    private let glass = CAGradientLayer()
    private let gloss = CAShapeLayer()
    private let sweep = CAShapeLayer()
    private let socket = CAShapeLayer()
    private let track = CAShapeLayer()
    private let cells = CAShapeLayer()
    private let core = CAShapeLayer()
    private let hands = CAShapeLayer()
    private let sheen = CAShapeLayer()

    /// Both figures' arms, over the body so folded arms read.
    private let arms = CAShapeLayer()

    private var hologramLayers: [CALayer] {
        [beam, fringeLeft, fringeRight, hairBack, platform, projector, lens, skin, dress, legFade, boots, trim, ribbons, hair,
         hairShine, scanlines, glitch]
    }

    private var androidLayers: [CALayer] {
        [thrusters, hover, seams, sheen, joints, lights, visor, socket, track, cells, core, hands]
    }

    private var allLayers: [CALayer] {
        hologramLayers + androidLayers + [arms, beamMask, skinMask, dressMask, legMask, thrusterMask, visorMask, glass, gloss, sweep]
    }

    init() {
        for layer in [beam, fringeLeft, fringeRight, hairBack, platform, projector, lens, thrusters, hover] {
            back.addSublayer(layer)
        }
        visor.addSublayer(glass)
        visor.addSublayer(gloss)
        visor.addSublayer(sweep)
        visor.mask = visorMask
        for layer in [skin, dress, legFade, scanlines, boots, trim, ribbons, hair, hairShine,
                      seams, sheen, joints, lights, visor, socket, track, cells, core, arms, hands] {
            middle.addSublayer(layer)
        }
        front.addSublayer(glitch)
        beam.mask = beamMask
        skin.mask = skinMask
        dress.mask = dressMask
        legFade.mask = legMask
        thrusters.mask = thrusterMask
        for layer in [back, middle, front] + allLayers { layer.actions = Self.noActions }
        seams.fillColor = nil
        seams.lineCap = .round
        hide()
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "colors": NSNull(), "shadowOpacity": NSNull(), "shadowRadius": NSNull(), "mask": NSNull(),
    ]

    /// Hidden, as for any figure but these two.
    func hide() {
        style = nil
        for layer in [back, middle, front] { layer.isHidden = true }
        for layer in allLayers { layer.removeAllAnimations() }
    }

    // MARK: Look

    /// Draws the hologram or the android for `look` at `size` points, with
    /// the gauge at `level` of four; any other figure hides it all.
    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat, sleeping: Bool, level: Int) {
        guard look.style == .hologram || look.style == .android else { return hide() }
        style = look.style
        self.size = size
        self.sleeping = sleeping
        self.level = level
        colors = NotchMascotSignalColors(look)
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [back, middle, front] + allLayers {
            layer.frame = box
            layer.contentsScale = scale
            layer.removeAllAnimations()
            layer.shadowOpacity = 0
        }
        for layer in [back, middle, front] { layer.isHidden = false }
        let hologram = look.style == .hologram
        for layer in hologramLayers { layer.isHidden = !hologram }
        for layer in androidLayers { layer.isHidden = hologram }
        arms.isHidden = false
        arms.opacity = 1
        if hologram {
            configureHologram(look: look)
        } else {
            configureAndroid()
        }
        applyRest()
    }

    private func configureHologram(look: NotchMascotLook) {
        typealias C = NotchMascotCreatures
        let c = colors
        beamMask.path = C.hologramBeam(size: size)
        beam.colors = [c.light.cgColor.copy(alpha: 0)!, c.light.cgColor.copy(alpha: 0.12)!, c.light.cgColor.copy(alpha: 0.42)!]
        beam.locations = [0.15, 0.55, 0.95]
        beam.startPoint = CGPoint(x: 0.5, y: 0)
        beam.endPoint = CGPoint(x: 0.5, y: 1)

        let figure = C.hologramSilhouette(size: size)
        let shift = max(0.5, size * 0.012)
        fringeLeft.path = figure.copy(using: [CGAffineTransform(translationX: -shift, y: 0)])
        fringeLeft.fillColor = c.light.cgColor
        glow(fringeLeft, c.light, radius: 0.035)
        fringeRight.path = figure.copy(using: [CGAffineTransform(translationX: shift, y: 0)])
        fringeRight.fillColor = c.fringe.cgColor

        hairBack.path = C.hologramHairBack(size: size)
        hairBack.fillColor = c.hair.darkened(0.12).cgColor
        platform.path = C.hologramPlatform(size: size)
        platform.fillColor = c.light.cgColor.copy(alpha: 0.85)
        glow(platform, c.light, radius: 0.06)
        projector.path = C.hologramProjector(size: size)
        projector.fillColor = NotchMascotColor.hsb(c.hair.hsb.0, 0.25, 0.22).cgColor
        lens.path = C.hologramLens(size: size)
        lens.fillColor = c.light.brightened(0.4).cgColor
        glow(lens, c.light, radius: 0.04)

        skinMask.path = C.hologramSkin(size: size)
        skin.colors = [c.skin.cgColor, c.skin.cgColor, c.skinLow.cgColor]
        skin.locations = [0, 0.3, 0.9]
        skin.startPoint = CGPoint(x: 0.5, y: 0)
        skin.endPoint = CGPoint(x: 0.5, y: 1)
        dressMask.path = C.hologramDress(size: size)
        dress.colors = [c.dress.cgColor, c.dress.cgColor, c.dressHem.cgColor]
        dress.locations = [0, 0.5, 0.74]
        dress.startPoint = CGPoint(x: 0.5, y: 0)
        dress.endPoint = CGPoint(x: 0.5, y: 1)
        legMask.path = C.hologramLegs(size: size)
        legFade.colors = [c.skin.cgColor.copy(alpha: 0)!, c.light.cgColor.copy(alpha: 0.85)!]
        legFade.locations = [0.74, 0.9]
        legFade.startPoint = CGPoint(x: 0.5, y: 0)
        legFade.endPoint = CGPoint(x: 0.5, y: 1)
        boots.path = C.hologramBoots(size: size)
        boots.fillColor = c.hair.cgColor
        boots.opacity = 0.9
        trim.path = C.hologramTrim(size: size)
        trim.fillColor = c.trim.cgColor
        ribbons.path = C.hologramRibbons(size: size)
        ribbons.fillColor = c.ribbon.cgColor
        glow(ribbons, c.ribbon, radius: 0.025)
        hair.path = C.hologramHair(ahoge: !NotchMascotWearables.coversHead(look.accessory), size: size)
        hair.fillColor = c.hair.cgColor
        hairShine.path = C.hologramHairShine(size: size)
        hairShine.fillColor = c.light.brightened(0.5).cgColor.copy(alpha: 0.7)
        scanlines.path = C.hologramScanlines(size: size)
        scanlines.fillColor = NSColor.white.withAlphaComponent(0.1).cgColor
        glitch.path = C.hologramGlitch(size: size)
        glitch.fillColor = c.light.cgColor.copy(alpha: 0.8)
        glitch.opacity = 0
        arms.path = C.hologramArms(armsPose, size: size)
        arms.fillColor = c.skin.cgColor
    }

    private func configureAndroid() {
        typealias C = NotchMascotCreatures
        let c = colors
        thrusterMask.path = C.androidThrusters(size: size)
        thrusters.colors = [c.glow.brightened(0.6).cgColor, c.glow.cgColor.copy(alpha: 0.75)!, c.glow.cgColor.copy(alpha: 0)!]
        thrusters.locations = [0.85, 0.9, 0.96]
        thrusters.startPoint = CGPoint(x: 0.5, y: 0)
        thrusters.endPoint = CGPoint(x: 0.5, y: 1)
        hover.path = C.androidHover(size: size)
        hover.fillColor = c.glow.cgColor.copy(alpha: 0.7)
        glow(hover, c.glow, radius: 0.07)

        seams.path = C.androidSeams(size: size)
        seams.strokeColor = c.graphite.cgColor.copy(alpha: 0.3)
        seams.lineWidth = max(0.35, size * 0.01)
        sheen.path = C.androidSheen(size: size)
        sheen.fillColor = NSColor.white.withAlphaComponent(0.55).cgColor
        joints.path = C.androidJoints(size: size)
        joints.fillColor = c.graphite.cgColor
        lights.path = C.androidLights(size: size)
        lights.fillColor = c.glow.brightened(0.3).cgColor
        glow(lights, c.glow, radius: 0.03)
        visorMask.path = C.androidVisor(size: size)
        glass.colors = [c.glassTop.cgColor, c.glassBottom.cgColor]
        glass.locations = [0.17, 0.38]
        glass.startPoint = CGPoint(x: 0.5, y: 0)
        glass.endPoint = CGPoint(x: 0.5, y: 1)
        gloss.path = C.androidVisorGloss(size: size)
        gloss.fillColor = NSColor.white.withAlphaComponent(0.3).cgColor
        sweep.path = C.androidVisorSweep(size: size)
        sweep.fillColor = c.glow.brightened(0.5).cgColor.copy(alpha: 0.35)
        sweep.opacity = 0
        socket.path = C.androidGauge(size: size)
        socket.fillColor = c.glassBottom.cgColor
        socket.strokeColor = c.graphite.cgColor
        socket.lineWidth = max(0.4, size * 0.012)
        track.path = C.androidGaugeTrack(size: size)
        track.fillColor = c.glow.cgColor.copy(alpha: 0.18)
        cells.fillColor = c.glow.cgColor
        glow(cells, c.glow, radius: 0.035)
        core.path = C.androidCore(size: size)
        core.fillColor = c.glow.brightened(0.55).cgColor
        glow(core, c.glow, radius: 0.04)
        arms.path = C.androidArms(armsPose, size: size)
        arms.fillColor = c.arms.cgColor
        hands.path = C.androidHands(armsPose, size: size)
        hands.fillColor = c.graphite.cgColor
    }

    /// A soft halo of `color` round a layer's shape, `radius` a share of the figure.
    private func glow(_ layer: CAShapeLayer, _ color: NotchMascotColor, radius: CGFloat) {
        layer.shadowColor = color.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = max(0.8, size * radius)
        layer.shadowOpacity = 0.9
    }

    // MARK: State

    private var armsPose: NotchMascotCreatures.ArmsPose { sleeping ? .folded : .rest }

    private func armsPath(_ pose: NotchMascotCreatures.ArmsPose) -> CGPath {
        style == .android ? NotchMascotCreatures.androidArms(pose, size: size) : NotchMascotCreatures.hologramArms(pose, size: size)
    }

    /// How bright the lights are, awake or asleep: the projection dims, the
    /// android's thrusters idle low and its gauge goes dark.
    private func applyRest() {
        let dim: Float = sleeping ? 0.35 : 1
        for layer in [beam, platform, lens, fringeLeft, fringeRight, hover, thrusters, lights] { layer.opacity = dim }
        fringeLeft.opacity = sleeping ? 0.2 : 0.45
        fringeRight.opacity = sleeping ? 0.15 : 0.35
        scanlines.opacity = sleeping ? 0.5 : 1
        cells.path = NotchMascotCreatures.androidGaugeCells(level: sleeping ? 0 : level, size: size)
        core.opacity = sleeping ? 0.3 : Float(0.55 + 0.45 * Double(level) / 4)
        core.shadowRadius = max(0.8, size * (0.02 + 0.012 * CGFloat(sleeping ? 0 : level)))
    }

    /// Asleep the two fold their arms and their light dims; awake again it
    /// comes back up.
    func setSleeping(_ sleeping: Bool, animated: Bool) {
        guard style != nil, sleeping != self.sleeping else { return }
        self.sleeping = sleeping
        let duration = sleeping ? 0.6 : 0.3
        morph(arms, to: armsPath(armsPose), duration: duration, animated: animated)
        if style == .android {
            morph(hands, to: NotchMascotCreatures.androidHands(armsPose, size: size), duration: duration, animated: animated)
        }
        if animated {
            for layer in [beam, platform, lens, fringeLeft, fringeRight, hover, thrusters, lights, scanlines, core] {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                fade.duration = duration
                layer.add(fade, forKey: "sleepFade")
            }
        }
        applyRest()
    }

    /// The gauge follows the CPU, a quarter of the ring at a time.
    func setLevel(_ level: Int) {
        guard self.level != level else { return }
        self.level = level
        guard style == .android else { return }
        applyRest()
    }

    /// The gauge runs from empty to full over `duration` and settles back on
    /// what the CPU says.
    func charge(for duration: TimeInterval) {
        guard style == .android, size > 0, !sleeping, duration > 0 else { return }
        let levels = [0, 1, 2, 3, 4, 4]
        let fill = CAKeyframeAnimation(keyPath: "path")
        fill.values = levels.map { NotchMascotCreatures.androidGaugeCells(level: $0, size: size) }
        fill.keyTimes = levels.indices.map { NSNumber(value: Double($0) / Double(levels.count - 1)) }
        fill.calculationMode = .discrete
        fill.duration = duration
        cells.add(fill, forKey: "charge")
        let bright = keyframes("opacity", [0.6, 1, 1, 0.6], [0, 0.8, 0.9, 1])
        bright.duration = duration
        core.add(bright, forKey: "charge")
    }

    // MARK: Idle

    /// With motion welcome and awake, the projection breathes and glitches
    /// now and then, and the android's core pulses and its jets flicker; all
    /// of it runs in the render server, with no timer in the app.
    func setIdle(_ motion: Bool) {
        for layer in [beam, glitch, platform, core, thrusters, hover] { layer.removeAnimation(forKey: "idle") }
        guard motion, !sleeping, let style else { return }
        if style == .hologram {
            let breathe = keyframes("opacity", [1, 0.7, 1], [0, 0.5, 1])
            breathe.duration = 2.8
            breathe.repeatCount = .infinity
            for layer in [beam, platform] { layer.add(breathe, forKey: "idle") }
            let blip = keyframes("opacity", [0, 0, 1, 0, 0.8, 0], [0, 0.9, 0.915, 0.93, 0.95, 0.97])
            blip.duration = 6.5
            blip.repeatCount = .infinity
            glitch.add(blip, forKey: "idle")
        } else {
            let pulse = keyframes("transform.scale", [1, 1.18, 1], [0, 0.5, 1])
            pulse.duration = 1.8
            pulse.repeatCount = .infinity
            core.add(centered(pulse, at: NotchMascotCreatures.androidCoreCenter), forKey: "idle")
            let flicker = keyframes("opacity", [1, 0.75, 1, 0.85, 1], [0, 0.25, 0.5, 0.75, 1])
            flicker.duration = 0.5
            flicker.repeatCount = .infinity
            thrusters.add(flicker, forKey: "idle")
        }
    }

    // MARK: Reactions

    private static let cheers: Set<NotchMascotReaction> = [.celebrate, .bounce, .perk, .ready]
    private static let waves: Set<NotchMascotReaction> = [.wave, .love, .wakeUp]

    /// Arms up for a cheer and a wave for a greeting; then the hologram's
    /// projection stutters, slices of her slipping aside, and the android
    /// scans with its visor while its heart and jets flare.
    func flourish(_ reaction: NotchMascotReaction) {
        guard let style, size > 0 else { return }
        let length = min(1.4, max(0.7, reaction.length))
        if Self.cheers.contains(reaction) {
            playArms([.rest, .up, .up, .rest], duration: length)
        } else if Self.waves.contains(reaction) {
            playArms([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length)
        }
        if style == .hologram {
            let span = min(0.8, length)
            let flicker = keyframes("opacity", [1, 0.25, 1, 0.5, 1], [0, 0.12, 0.3, 0.42, 0.6])
            flicker.duration = span
            for layer in [beam, scanlines, platform, lens, hairShine] { layer.add(flicker, forKey: "flicker") }
            let slices = keyframes("opacity", [0, 1, 0, 0.9, 0], [0, 0.1, 0.22, 0.34, 0.5])
            let jitter = keyframes("transform.translation.x", [0, size * 0.02, -size * 0.03, size * 0.015, 0],
                                   [0, 0.1, 0.22, 0.34, 0.5])
            let group = CAAnimationGroup()
            group.animations = [slices, jitter]
            group.duration = span
            slices.duration = span
            jitter.duration = span
            glitch.add(group, forKey: "flicker")
            let split = keyframes("transform.translation.x", [0, -size * 0.03, size * 0.01, -size * 0.02, 0],
                                  [0, 0.1, 0.25, 0.4, 0.6], additive: true)
            split.duration = span
            fringeLeft.add(split, forKey: "flicker")
            let other = keyframes("transform.translation.x", [0, size * 0.03, -size * 0.01, size * 0.02, 0],
                                  [0, 0.1, 0.25, 0.4, 0.6], additive: true)
            other.duration = span
            fringeRight.add(other, forKey: "flicker")
        } else {
            let span = min(0.9, length)
            let white = NSColor.white.cgColor, glowColor = colors.glow.cgColor
            let flare = CAKeyframeAnimation(keyPath: "fillColor")
            flare.values = [glowColor, white, glowColor]
            flare.keyTimes = [0, 0.3, 1]
            flare.duration = span
            for layer in [cells, lights] { layer.add(flare, forKey: "flare") }
            let swell = keyframes("transform.scale", [1, 1.45, 1], [0, 0.3, 1])
            swell.duration = span
            core.add(centered(swell, at: NotchMascotCreatures.androidCoreCenter), forKey: "flare")
            let jet = keyframes("transform.scale.y", [1, 1.4, 1], [0, 0.3, 1])
            jet.duration = span
            thrusters.add(centered(jet, at: CGPoint(x: 0.5, y: 0.852)), forKey: "flare")
            let wide = keyframes("transform.scale.x", [1, 1.35, 1], [0, 0.3, 1])
            wide.duration = span
            hover.add(centered(wide, at: CGPoint(x: 0.5, y: 0.95)), forKey: "flare")
            let scan = keyframes("transform.translation.x", [-size * 0.2, size * 0.32], [0, 1])
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.15, 0.8, 1])
            let pass = CAAnimationGroup()
            scan.duration = span
            show.duration = span
            pass.animations = [scan, show]
            pass.duration = span
            sweep.add(pass, forKey: "flare")
        }
    }

    private func playArms(_ poses: [NotchMascotCreatures.ArmsPose], duration: TimeInterval) {
        let times = poses.indices.map { NSNumber(value: Double($0) / Double(max(1, poses.count - 1))) }
        func move(_ paths: [CGPath]) -> CAKeyframeAnimation {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = paths
            move.keyTimes = times
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return move
        }
        arms.add(move(poses.map(armsPath)), forKey: "flourish")
        if style == .android {
            hands.add(move(poses.map { NotchMascotCreatures.androidHands($0, size: size) }), forKey: "flourish")
        }
    }

    /// Everything that plays stops.
    func removeAllAnimations() {
        for layer in allLayers { layer.removeAllAnimations() }
    }

    // MARK: Helpers

    private func morph(_ layer: CAShapeLayer, to path: CGPath, duration: TimeInterval, animated: Bool) {
        if animated {
            let change = CABasicAnimation(keyPath: "path")
            change.fromValue = layer.presentation()?.path ?? layer.path
            change.toValue = path
            change.duration = duration
            change.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(change, forKey: "pose")
        }
        layer.path = path
    }

    private func keyframes(_ keyPath: String, _ values: [CGFloat], _ times: [Double],
                           additive: Bool = false) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.isAdditive = additive
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// A scale about `point`, a share of the figure, rather than about the
    /// middle of the layer, which covers the whole square.
    private func centered(_ scale: CAKeyframeAnimation, at point: CGPoint) -> CAAnimation {
        let anchor = CGPoint(x: (point.x - 0.5) * size, y: (point.y - 0.5) * size)
        let values = (scale.values as? [CGFloat]) ?? []
        let keyPath = scale.keyPath ?? "transform.scale"
        let transforms = values.map { value -> NSValue in
            var t = CATransform3DMakeTranslation(anchor.x, anchor.y, 0)
            switch keyPath {
            case "transform.scale.x": t = CATransform3DScale(t, value, 1, 1)
            case "transform.scale.y": t = CATransform3DScale(t, 1, value, 1)
            default: t = CATransform3DScale(t, value, value, 1)
            }
            return NSValue(caTransform3D: CATransform3DTranslate(t, -anchor.x, -anchor.y, 0))
        }
        let move = CAKeyframeAnimation(keyPath: "transform")
        move.values = transforms
        move.keyTimes = scale.keyTimes
        move.timingFunction = scale.timingFunction
        move.duration = scale.duration
        move.repeatCount = scale.repeatCount
        return move
    }
}
