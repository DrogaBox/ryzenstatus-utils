// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The parts of a companion beyond its body and eyes, and the props it
/// carries in a mood: a chip's pins, a fan's blades, a cat's ears and tail,
/// a ghost's mouth, a slime's drip; sweat, heat, music notes, a coffee mug,
/// a download arrow, a tired battery, a "z" and confetti. Drawn with shape
/// layers like the rest of the companion. A mood that lasts runs as repeating
/// Core Animation animations in the render server, only while the companion
/// is in sight and motion is welcome, and none of it needs a timer in the app.
final class NotchMascotDecor {
    /// Behind the body: pins, ears and tail.
    let back = CALayer()
    /// Over the body, under the eyes: the fan's opening, blades and hub, the
    /// chip's mark, the cat's nose and whiskers, the ghost's mouth.
    let middle = CALayer()
    /// In front of everything: the props.
    let props = CALayer()

    private(set) var look = NotchMascotLook.standard
    private(set) var size: CGFloat = 0
    private(set) var sleeping = false
    private var ambient = MascotMoodState()
    private var motion = false

    // Creature parts.
    private let pins = CAShapeLayer()
    private let chipMark = CAShapeLayer()
    private let fanHole = CAShapeLayer()
    private let bladeHolder = CALayer()
    private let blades = CAShapeLayer()
    private let fanHub = CAShapeLayer()
    private let fanScrews = CAShapeLayer()
    private let catTail = CAShapeLayer()
    private let catEars = CAShapeLayer()
    private let catInnerEars = CAShapeLayer()
    private let catNose = CAShapeLayer()
    private let whiskers = CAShapeLayer()
    private let ghostMouth = CAShapeLayer()
    private let slimeDrip = CAShapeLayer()

    // Props.
    private let sweatDrop = CAShapeLayer()
    private let heat = CAShapeLayer()
    private let note = CAShapeLayer()
    private let mug = CALayer()
    private let mugBody = CAShapeLayer()
    private let mugHandle = CAShapeLayer()
    private let mugCoffee = CAShapeLayer()
    private let steam = CAShapeLayer()
    private let zee = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let battery = CAShapeLayer()
    private let batteryLevel = CAShapeLayer()
    private let paw = CAShapeLayer()
    private var confetti: [CAShapeLayer] = []

    private var creatureLayers: [CALayer] {
        [pins, chipMark, fanHole, bladeHolder, blades, fanHub, fanScrews, catTail, catEars, catInnerEars, catNose,
         whiskers, ghostMouth, slimeDrip]
    }

    private var propLayers: [CALayer] {
        [sweatDrop, heat, note, mug, mugBody, mugHandle, mugCoffee, steam, zee, arrow, battery, batteryLevel, paw]
            + confetti
    }

    init() {
        for layer in [pins, catTail, catEars, catInnerEars, slimeDrip] { back.addSublayer(layer) }
        bladeHolder.addSublayer(blades)
        for layer in [fanHole, bladeHolder, fanHub, fanScrews, chipMark, catNose, whiskers, ghostMouth] {
            middle.addSublayer(layer)
        }
        for layer in [mugBody, mugCoffee, mugHandle] { mug.addSublayer(layer) }
        for layer in [sweatDrop, heat, note, mug, steam, zee, arrow, battery, batteryLevel, paw] { props.addSublayer(layer) }
        confetti = (0..<NotchMascotCreatures.confettiFlights.count).map { _ in CAShapeLayer() }
        confetti.forEach(props.addSublayer)
        for layer in [back, middle, props] + creatureLayers + propLayers {
            layer.actions = Self.noActions
        }
        catTail.fillColor = nil
        catTail.lineCap = .round
        whiskers.fillColor = nil
        whiskers.lineCap = .round
        heat.fillColor = nil
        heat.lineCap = .round
        steam.fillColor = nil
        steam.lineCap = .round
        zee.fillColor = nil
        zee.lineCap = .round
        zee.lineJoin = .round
        arrow.fillColor = nil
        arrow.lineCap = .round
        arrow.lineJoin = .round
        battery.fillColor = nil
        mugHandle.fillColor = nil
        for layer in propLayers { layer.opacity = 0 }
        // The mug's own parts show whenever the mug does.
        for layer in [mugBody, mugHandle, mugCoffee] { layer.opacity = 1 }
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "sublayers": NSNull(), "speed": NSNull(), "timeOffset": NSNull(), "beginTime": NSNull(),
    ]

    // MARK: Look

    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat) {
        self.look = look
        self.size = size
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        // The blades turn about their own middle and the confetti flies from
        // its own spot; every other layer covers the companion's square.
        let placedElsewhere: Set<ObjectIdentifier> = Set(([blades, bladeHolder] + confetti).map { ObjectIdentifier($0) })
        for layer in [back, middle, props] + creatureLayers + propLayers
        where !placedElsewhere.contains(ObjectIdentifier(layer)) {
            layer.frame = box
            layer.contentsScale = scale
        }
        let palette = look.palette
        let style = look.style
        let line = max(0.6, size * 0.06)

        for layer in creatureLayers { layer.isHidden = true }
        switch style {
        case .minimal, .robot, .cristobal, .whiteRabbit:
            break
        case .devourer:
            pins.path = NotchMascotCreatures.devourerLimbs(size: size)
            pins.fillColor = palette.shade.cgColor
            show(pins)
        case .shifter:
            slimeDrip.path = NotchMascotCreatures.slimeDrip(melted: sleeping, size: size)
            slimeDrip.fillColor = palette.shade.cgColor
            show(slimeDrip)
        case .chip:
            pins.path = NotchMascotCreatures.chipPins(size: size)
            pins.fillColor = palette.shade.cgColor
            chipMark.path = NotchMascotCreatures.chipMark(size: size)
            chipMark.fillColor = palette.shade.cgColor
            show(pins, chipMark)
        case .fan:
            fanHole.path = NotchMascotCreatures.fanHole(size: size)
            fanHole.fillColor = NotchMascotColor.visor.cgColor
            let center = CGPoint(x: NotchMascotCreatures.fanCenter.x * size, y: NotchMascotCreatures.fanCenter.y * size)
            let side = NotchMascotCreatures.fanReach * 2 * size
            bladeHolder.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            bladeHolder.position = center
            bladeHolder.contentsScale = scale
            blades.frame = bladeHolder.bounds
            blades.contentsScale = scale
            blades.path = NotchMascotCreatures.fanBlades(side: side)
            blades.fillColor = palette.light.cgColor
            blades.opacity = 0.92
            fanHub.path = NotchMascotCreatures.fanHub(size: size)
            fanHub.fillColor = palette.light.cgColor
            fanHub.strokeColor = palette.shade.cgColor
            fanHub.lineWidth = max(0.4, size * 0.025)
            fanScrews.path = NotchMascotCreatures.fanScrews(size: size)
            fanScrews.fillColor = palette.shade.cgColor
            show(fanHole, bladeHolder, blades, fanHub, fanScrews)
        case .cat:
            catTail.path = NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size)
            catTail.strokeColor = palette.shade.cgColor
            catTail.lineWidth = max(0.8, size * 0.075)
            catEars.path = NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: false, size: size)
            catEars.fillColor = palette.light.cgColor
            catInnerEars.path = NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: true, size: size)
            catInnerEars.fillColor = palette.shade.cgColor
            catNose.path = NotchMascotCreatures.catNose(size: size)
            catNose.fillColor = palette.shade.cgColor
            whiskers.path = NotchMascotCreatures.catWhiskers(size: size)
            whiskers.strokeColor = NotchMascotColor.ink.cgColor
            whiskers.opacity = 0.55
            whiskers.lineWidth = max(0.35, size * 0.025)
            show(catTail, catEars, catInnerEars, catNose, whiskers)
        case .ghost:
            ghostMouth.path = NotchMascotCreatures.ghostMouth(open: false, size: size)
            ghostMouth.fillColor = NotchMascotColor.ink.cgColor
            ghostMouth.opacity = 0
            show(ghostMouth)
        case .slime:
            slimeDrip.path = NotchMascotCreatures.slimeDrip(melted: sleeping, size: size)
            slimeDrip.fillColor = palette.shade.cgColor
            show(slimeDrip)
        }
        pins.opacity = sleeping ? 0.45 : 1

        // Props, the same for every style.
        sweatDrop.path = NotchMascotCreatures.sweatDrop(size: size)
        sweatDrop.fillColor = NotchMascotCreatures.sweat.cgColor
        heat.path = NotchMascotCreatures.heatLines(size: size)
        heat.strokeColor = NotchMascotCreatures.heat.cgColor
        heat.lineWidth = line * 0.8
        note.path = NotchMascotCreatures.note(size: size)
        note.fillColor = palette.light.cgColor
        mugBody.path = NotchMascotCreatures.mug(size: size)
        mugBody.fillColor = NotchMascotCreatures.mug.cgColor
        mugHandle.path = NotchMascotCreatures.mugHandle(size: size)
        mugHandle.strokeColor = NotchMascotCreatures.mug.cgColor
        mugHandle.lineWidth = line * 0.7
        mugCoffee.path = NotchMascotCreatures.mugCoffee(size: size)
        mugCoffee.fillColor = NotchMascotCreatures.coffee.cgColor
        steam.path = NotchMascotCreatures.steam(size: size)
        steam.strokeColor = NSColor.white.withAlphaComponent(0.75).cgColor
        steam.lineWidth = line * 0.5
        zee.path = NotchMascotCreatures.z(size: size)
        zee.strokeColor = palette.light.cgColor
        zee.lineWidth = line * 0.6
        arrow.path = NotchMascotCreatures.downArrow(size: size)
        arrow.strokeColor = NotchMascotCreatures.download.cgColor
        arrow.lineWidth = line * 0.8
        battery.path = NotchMascotCreatures.battery(size: size)
        battery.strokeColor = palette.light.cgColor
        battery.lineWidth = line * 0.4
        batteryLevel.path = NotchMascotCreatures.batteryLevel(size: size)
        batteryLevel.fillColor = NotchMascotCreatures.warning.cgColor
        paw.path = NotchMascotCreatures.paw(size: size)
        paw.fillColor = palette.light.cgColor
        paw.strokeColor = palette.shade.cgColor
        paw.lineWidth = line * 0.3
        let colors = NotchMascotCreatures.confetti + [palette.light]
        for (index, piece) in confetti.enumerated() {
            piece.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            piece.position = CGPoint(x: size * 0.5, y: size * 0.3)
            piece.contentsScale = scale
            piece.path = NotchMascotCreatures.confettiPiece(size: size)
                .copy(using: [CGAffineTransform(translationX: size / 2, y: size / 2)])
            piece.fillColor = colors[index % colors.count].cgColor
        }
        applyAmbient()
    }

    private func show(_ layers: CALayer...) { layers.forEach { $0.isHidden = false } }

    // MARK: Sleep

    /// Asleep, each creature settles in its own way: the cat's ears droop and
    /// its tail curls round, the fan's blades stop, the ghost grows faint, the
    /// slime melts into a little puddle and the chip's pins go dim.
    func setSleeping(_ sleeping: Bool, animated: Bool, fill: CALayer) {
        guard sleeping != self.sleeping else { return }
        self.sleeping = sleeping
        guard size > 0 else { return }
        let duration = sleeping ? 0.6 : 0.3
        switch look.style {
        case .cat:
            morph(catEars, to: NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: false, size: size),
                  duration: duration, animated: animated)
            morph(catInnerEars, to: NotchMascotCreatures.catEars(sleeping ? .droop : .up, inner: true, size: size),
                  duration: duration, animated: animated)
            morph(catTail, to: NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size),
                  duration: duration, animated: animated)
        case .slime, .shifter:
            morph(slimeDrip, to: NotchMascotCreatures.slimeDrip(melted: sleeping, size: size),
                  duration: duration, animated: animated)
        case .chip:
            fade(pins, to: sleeping ? 0.45 : 1, duration: duration, animated: animated)
        case .ghost:
            fade(fill, to: sleeping ? 0.55 : 0.92, duration: duration, animated: animated)
        case .fan, .minimal, .robot, .cristobal, .whiteRabbit, .devourer:
            break
        }
        applyAmbient()
    }

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

    private func fade(_ layer: CALayer, to opacity: Float, duration: TimeInterval, animated: Bool) {
        if animated {
            let change = CABasicAnimation(keyPath: "opacity")
            change.fromValue = layer.presentation()?.opacity ?? layer.opacity
            change.toValue = opacity
            change.duration = duration
            layer.add(change, forKey: "sleepFade")
        }
        layer.opacity = opacity
    }

    // MARK: Moods that last

    /// Shows the props of a lasting mood. With `motion`, they move: sweat
    /// runs, heat rises, notes float, steam curls, a "z" drifts up, the fan
    /// spins with the CPU's load. Without it they stay still.
    func setAmbient(_ state: MascotMoodState, motion: Bool) {
        guard state != ambient || motion != self.motion else { return }
        ambient = state
        self.motion = motion
        applyAmbient()
    }

    private func applyAmbient() {
        guard size > 0 else { return }
        let mood = sleeping && !ambient.ambient.isResting ? MascotAmbient.asleep : ambient.ambient
        let shown: [CALayer: Bool] = [
            sweatDrop: mood == .working || mood == .overheated,
            heat: mood == .overheated,
            note: mood == .dancing,
            mug: mood == .caffeinated,
            steam: mood == .caffeinated,
            zee: mood == .asleep,
            arrow: mood == .downloading,
            battery: mood == .lowBattery,
            batteryLevel: mood == .lowBattery,
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, on) in shown {
            layer.removeAnimation(forKey: "ambient")
            layer.opacity = on ? 1 : 0
            guard on, motion else { continue }
            layer.add(loop(for: layer, mood: mood), forKey: "ambient")
        }
        CATransaction.commit()
        setSpin(look.style == .fan && motion && !sleeping ? Self.spinRate(effort: ambient.effort, mood: mood) : 0)
        applyGlow(sleeping ? 0 : ambient.glow)
    }

    /// The chip's pin-one mark lights up with the package's power: dark at
    /// idle, a warm glow near its limit, pulsing only when motion is welcome.
    private func applyGlow(_ glow: Double) {
        chipMark.removeAnimation(forKey: "glow")
        guard look.style == .chip, glow > 0 else {
            chipMark.shadowOpacity = 0
            chipMark.fillColor = look.palette.shade.cgColor
            return
        }
        let warm = NotchMascotWearableShapes.rgb(glow >= 0.75 ? 0xFF6A3D : 0xFFC940)
        chipMark.fillColor = warm
        chipMark.shadowColor = warm
        chipMark.shadowOffset = .zero
        chipMark.shadowRadius = max(0.8, size * 0.08)
        chipMark.shadowOpacity = Float(0.4 + glow * 0.6)
        guard motion else { return }
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = Float(0.25 + glow * 0.3)
        pulse.toValue = Float(0.5 + glow * 0.5)
        pulse.duration = 1.6 - glow * 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        chipMark.add(pulse, forKey: "glow")
    }

    /// Turns a second for a fan with the CPU at `effort`: still when idle,
    /// a blur when it works flat out, and a little faster still when hot.
    static func spinRate(effort: Double, mood: MascotAmbient) -> Double {
        let base: Double
        switch effort {
        case ..<0.125: base = 0
        case ..<0.375: base = 0.4
        case ..<0.625: base = 1
        case ..<0.875: base = 2
        default: base = 3.2
        }
        return mood == .overheated ? max(base, 3.2) * 1.2 : base
    }

    /// The repeating motion of one prop.
    private func loop(for layer: CALayer, mood: MascotAmbient) -> CAAnimation {
        let group = CAAnimationGroup()
        group.repeatCount = .infinity
        switch layer {
        case sweatDrop:
            let fall = keyframes("transform.translation.y", [0, 0, size * 0.16], [0, 0.3, 1], additive: true)
            let shine = keyframes("opacity", [0, 1, 1, 0], [0, 0.2, 0.7, 1])
            group.animations = [fall, shine]
            group.duration = mood == .overheated ? 0.9 : 1.7 - ambient.effort * 0.6
        case heat:
            let rise = keyframes("transform.translation.y", [size * 0.04, -size * 0.06], [0, 1], additive: true)
            let shimmer = keyframes("opacity", [0.2, 1, 0.2], [0, 0.5, 1])
            group.animations = [rise, shimmer]
            group.duration = 1.0
        case note:
            let float = keyframes("transform.translation.y", [size * 0.12, -size * 0.12], [0, 1], additive: true)
            let drift = keyframes("transform.translation.x", [0, size * 0.04, -size * 0.02], [0, 0.5, 1], additive: true)
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.2, 0.75, 1])
            group.animations = [float, drift, show]
            group.duration = 1.6 - ambient.energy * 0.5
        case steam:
            let rise = keyframes("transform.translation.y", [size * 0.03, -size * 0.06], [0, 1], additive: true)
            let show = keyframes("opacity", [0, 0.9, 0], [0, 0.4, 1])
            group.animations = [rise, show]
            group.duration = 2.0
        case zee:
            let rise = keyframes("transform.translation.y", [size * 0.08, -size * 0.1], [0, 1], additive: true)
            let drift = keyframes("transform.translation.x", [-size * 0.05, size * 0.03], [0, 1], additive: true)
            let show = keyframes("opacity", [0, 1, 0], [0, 0.4, 1])
            group.animations = [rise, drift, show]
            group.duration = 2.6
        case arrow:
            let bob = keyframes("transform.translation.y", [0, size * 0.06, 0], [0, 0.5, 1], additive: true)
            let blink = keyframes("opacity", [1, 0.35, 1], [0, 0.5, 1])
            group.animations = [bob, blink]
            group.duration = 0.9
        case batteryLevel:
            group.animations = [keyframes("opacity", [1, 0.15, 1], [0, 0.5, 1])]
            group.duration = 1.6
        default:
            // Shown and still: the mug, the battery's outline.
            group.animations = [keyframes("opacity", [1, 1], [0, 1])]
            group.duration = 10
        }
        return fitted(group)
    }

    /// A group whose animations all last as long as it does.
    private func fitted(_ group: CAAnimationGroup) -> CAAnimationGroup {
        group.animations?.forEach { $0.duration = group.duration }
        return group
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

    // MARK: Fan

    /// Spins the blades at `rate` turns a second, from where they are now,
    /// by changing the speed of one endless turn rather than restarting it.
    private func setSpin(_ rate: Double) {
        if blades.animation(forKey: "spin") == nil {
            guard rate > 0 else { return }
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = 2 * Double.pi
            turn.duration = 1
            turn.repeatCount = .infinity
            blades.speed = 0
            blades.timeOffset = 0
            blades.beginTime = 0
            blades.add(turn, forKey: "spin")
        }
        let now = CACurrentMediaTime()
        let local = blades.convertTime(now, from: nil)
        blades.speed = Float(rate)
        blades.timeOffset = local
        blades.beginTime = now
    }

    // MARK: Reactions

    /// What each creature adds to a reaction, and the props it brings.
    func flourish(_ reaction: NotchMascotReaction, reduceMotion: Bool) {
        guard size > 0 else { return }
        let now = CACurrentMediaTime()
        // Props first: these show with or without motion.
        switch reaction {
        case .sweat:
            flash(sweatDrop, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [0, 0, size * 0.16, size * 0.16]))
        case .panic:
            flash(heat, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [size * 0.05, 0, -size * 0.04, -size * 0.06]))
            flash(sweatDrop, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [0, size * 0.06, size * 0.12, size * 0.16]))
        case .sip:
            // Already in hand during Keep Awake, the mug stays out.
            if ambient.ambient != .caffeinated {
                flash(mug, for: reaction.length, motion: false, move: nil)
                flash(steam, for: reaction.length, motion: !reduceMotion,
                      move: ("transform.translation.y", [0, 0, -size * 0.04, -size * 0.06]))
            }
            if !reduceMotion {
                // Up to its face, a tilt for the sip, and back down.
                let lift = keyframes("transform.translation.y", [0, -size * 0.12, -size * 0.12, 0], [0, 0.3, 0.7, 1],
                                     additive: true)
                let toward = keyframes("transform.translation.x", [0, -size * 0.14, -size * 0.14, 0], [0, 0.3, 0.7, 1],
                                       additive: true)
                let tilt = keyframes("transform.rotation.z", [0, -0.25, -0.25, 0], [0, 0.35, 0.7, 1], additive: true)
                let sip = CAAnimationGroup()
                sip.animations = [lift, toward, tilt]
                sip.duration = reaction.length
                mug.add(fitted(sip), forKey: "sip")
            }
        case .peek:
            flash(arrow, for: reaction.length, motion: !reduceMotion,
                  move: ("transform.translation.y", [0, size * 0.06, 0, size * 0.06]))
        case .wave:
            flash(paw, for: reaction.length, motion: false, move: nil)
            if !reduceMotion {
                let wave = keyframes("transform.translation.y", [size * 0.1, -size * 0.12, -size * 0.12, -size * 0.12, size * 0.1],
                                     [0, 0.2, 0.5, 0.8, 1], additive: true)
                let wiggle = keyframes("transform.translation.x", [0, size * 0.05, -size * 0.04, size * 0.05, 0],
                                       [0, 0.3, 0.5, 0.7, 1], additive: true)
                let group = CAAnimationGroup()
                group.animations = [wave, wiggle]
                group.duration = reaction.length
                paw.add(fitted(group), forKey: "wave")
            }
        case .celebrate:
            if !reduceMotion { burstConfetti() }
        default:
            break
        }
        guard !reduceMotion else { return }
        // Then each creature's own flourish, for anything but a hush or a flash.
        guard reaction != .hush, reaction != .flash else { return }
        switch look.style {
        case .cat:
            twitchEars(beginTime: now)
            if reaction != .lookAround {
                let sway = CAKeyframeAnimation(keyPath: "path")
                let rest = NotchMascotCreatures.catTail(sleeping ? .curl : .rest, size: size)
                sway.values = [rest, NotchMascotCreatures.catTail(.sway, size: size), rest,
                               NotchMascotCreatures.catTail(.sway, size: size), rest]
                sway.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                sway.duration = min(1.4, reaction.length)
                sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                catTail.add(sway, forKey: "sway")
            }
        case .fan:
            // A gust: two quick extra turns that ease off.
            let gust = CABasicAnimation(keyPath: "transform.rotation.z")
            gust.fromValue = 0
            gust.toValue = (reaction == .relax ? 1 : 2) * 2 * Double.pi
            gust.duration = reaction == .relax ? 1.2 : 0.8
            gust.isAdditive = true
            gust.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            bladeHolder.add(gust, forKey: "gust")
        case .ghost:
            let mouth = CAKeyframeAnimation(keyPath: "path")
            let shut = NotchMascotCreatures.ghostMouth(open: false, size: size)
            let open = NotchMascotCreatures.ghostMouth(open: true, size: size)
            mouth.values = [shut, open, open, shut]
            mouth.keyTimes = [0, 0.2, 0.75, 1]
            mouth.duration = min(1.2, reaction.length)
            ghostMouth.add(mouth, forKey: "boo")
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.15, 0.8, 1])
            show.duration = mouth.duration
            ghostMouth.add(show, forKey: "booShow")
        case .chip:
            let glow = CAKeyframeAnimation(keyPath: "fillColor")
            glow.values = [look.palette.shade.cgColor, look.palette.light.cgColor, look.palette.shade.cgColor,
                           look.palette.light.cgColor, look.palette.shade.cgColor]
            glow.keyTimes = [0, 0.2, 0.45, 0.7, 1]
            glow.duration = min(1, reaction.length)
            pins.add(glow, forKey: "glow")
        case .slime, .minimal, .robot, .cristobal, .whiteRabbit, .devourer, .shifter:
            break
        }
    }

    /// A cat's ears flick once, on their own now and then or as it reacts.
    func twitchEars(beginTime: CFTimeInterval? = nil) {
        guard look.style == .cat, size > 0, !sleeping else { return }
        for (layer, inner) in [(catEars, false), (catInnerEars, true)] {
            let twitch = CAKeyframeAnimation(keyPath: "path")
            let up = NotchMascotCreatures.catEars(.up, inner: inner, size: size)
            let flick = NotchMascotCreatures.catEars(.twitch, inner: inner, size: size)
            twitch.values = [up, flick, up, flick, up]
            twitch.keyTimes = [0, 0.2, 0.45, 0.65, 1]
            twitch.duration = 0.5
            if let beginTime { twitch.beginTime = beginTime }
            layer.add(twitch, forKey: "twitch")
        }
    }

    /// Shows a prop for `duration` and hides it again, moving it with `move`
    /// along the way when motion is welcome.
    private func flash(_ layer: CALayer, for duration: TimeInterval, motion: Bool,
                       move: (keyPath: String, values: [CGFloat])?) {
        let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.12, 0.85, 1])
        var animations: [CAAnimation] = [show]
        if motion, let move {
            animations.append(keyframes(move.keyPath, move.values, [0, 0.3, 0.7, 1], additive: true))
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        layer.add(fitted(group), forKey: "flourish")
    }

    /// Bits of confetti fly up and out from over its head and fall away.
    private func burstConfetti() {
        for (index, piece) in confetti.enumerated() {
            let flight = NotchMascotCreatures.confettiFlights[index]
            let start = CGPoint(x: size * 0.5, y: size * 0.3)
            let top = CGPoint(x: start.x + flight.x * size, y: start.y + flight.y * size)
            let end = CGPoint(x: top.x + flight.x * size * 0.3, y: top.y + size * 0.7)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: top.x, y: top.y - size * 0.15))
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = path
            fly.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.6, 1)
            let spin = keyframes("transform.rotation.z", [0, CGFloat(index % 2 == 0 ? 1 : -1) * 6], [0, 1])
            let show = keyframes("opacity", [0, 1, 1, 0], [0, 0.08, 0.7, 1])
            let group = CAAnimationGroup()
            group.animations = [fly, spin, show]
            group.duration = 0.95 + Double(index % 3) * 0.08
            piece.add(fitted(group), forKey: "confetti")
        }
    }

    /// Everything that plays stops, as when the companion is reset.
    func removeAllAnimations() {
        for layer in creatureLayers + propLayers where layer !== blades { layer.removeAllAnimations() }
        applyAmbient()
    }
}
