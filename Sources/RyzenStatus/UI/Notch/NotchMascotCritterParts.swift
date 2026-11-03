// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The parts of the five drawn animals beyond their body fill and eyes, in
/// three groups the decor stacks behind the body, over it and in front of
/// everything: ears, wings, tails, paws, bellies and the rest, each a layer
/// of its own painted as `NotchMascotCritterPart` says. They take the
/// animal's poses: asleep it curls up or tucks in, its fire sinking to
/// embers; it cheers, waves and bows; a cat flicks its ears; walking, it
/// steps. While motion is welcome its tails sway, gills wave, flames
/// flicker and embers rise, all in the render server with no timer in the
/// app. Hidden for every other figure.
final class NotchMascotCritterParts {
    let back = CALayer()
    let middle = CALayer()
    let front = CALayer()

    private(set) var style: NotchMascotStyle?
    private var size: CGFloat = 0
    private var sleeping = false
    private var striding = false
    private var parts: [NotchMascotCritterPart] = []
    /// What shows of each part, and the shape layer whose path it takes:
    /// the same layer, or the mask of a gradient.
    private var shown: [CALayer] = []
    private var shapes: [CAShapeLayer] = []

    init() {
        for layer in [back, middle, front] { layer.actions = Self.noActions }
        hide()
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "colors": NSNull(), "locations": NSNull(), "mask": NSNull(), "sublayers": NSNull(), "shadowColor": NSNull(),
        "shadowOpacity": NSNull(), "shadowRadius": NSNull(), "startPoint": NSNull(), "endPoint": NSNull(),
    ]

    /// Hidden, as for any figure but the five.
    func hide() {
        style = nil
        parts = []
        for layer in [back, middle, front] {
            layer.isHidden = true
            layer.sublayers = nil
        }
        shown = []
        shapes = []
        haloes = [:]
    }

    // MARK: Look

    /// Draws the animal of `look` at `size` points; any other figure hides
    /// it all.
    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat, sleeping: Bool) {
        guard NotchMascotCreatures.critters.contains(look.style), size > 0 else { return hide() }
        hide()
        let style = look.style
        self.style = style
        self.size = size
        self.sleeping = sleeping
        striding = false
        let colors = NotchMascotCritterColors(look)
        let fur = Self.fur(look)
        let hat = NotchMascotWearables.coversHead(look.accessory) || look.accessory == .swanCrown
        parts = NotchMascotCreatures.critterParts(style, colors: colors, hat: hat, size: size)
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [back, middle, front] {
            layer.frame = box
            layer.contentsScale = scale
            layer.isHidden = false
        }
        for part in parts {
            let shape = CAShapeLayer()
            var visible: CALayer = shape
            switch part.paint {
            case .color(let color):
                shape.fillColor = color.cgColor
            case .line(let color, let width):
                shape.fillColor = nil
                shape.strokeColor = color.cgColor
                shape.lineWidth = max(0.35, width * size)
                shape.lineCap = .round
                shape.lineJoin = .round
            case .fur(let tone):
                let gradient = CAGradientLayer()
                gradient.colors = fur.colors.map { (tone >= 0 ? $0.brightened(tone) : $0.darkened(-tone)).cgColor }
                gradient.locations = fur.locations
                gradient.startPoint = fur.start
                gradient.endPoint = fur.end
                gradient.mask = shape
                visible = gradient
            case .gradient(let colors, let from, let to):
                let gradient = CAGradientLayer()
                gradient.colors = colors.map(\.cgColor)
                gradient.startPoint = from
                gradient.endPoint = to
                gradient.mask = shape
                visible = gradient
            case .radial(let color, let center, let radius):
                let gradient = CAGradientLayer()
                gradient.type = .radial
                gradient.colors = [color.cgColor, color.withAlpha(color.alpha * 0.45).cgColor, color.withAlpha(0).cgColor]
                gradient.locations = [0, 0.55, 1]
                gradient.startPoint = center
                gradient.endPoint = CGPoint(x: center.x + radius.width, y: center.y + radius.height)
                gradient.mask = shape
                visible = gradient
            }
            for layer in [visible, shape] {
                layer.actions = Self.noActions
                layer.frame = box
                layer.contentsScale = scale
            }
            let level: CALayer
            switch part.level {
            case .back: level = back
            case .middle: level = middle
            case .front: level = front
            }
            if let glow = part.glow {
                // A gradient's mask would clip its own glow, so a copy of
                // the shape glows just behind it.
                let halo = CAShapeLayer()
                halo.actions = Self.noActions
                halo.frame = box
                halo.contentsScale = scale
                halo.fillColor = glow.cgColor
                halo.shadowColor = glow.cgColor
                halo.shadowOffset = .zero
                halo.shadowRadius = max(0.8, size * 0.035)
                halo.shadowOpacity = 0.8
                level.addSublayer(halo)
                haloes[shown.count] = halo
            }
            level.addSublayer(visible)
            shown.append(visible)
            shapes.append(shape)
        }
        for (index, part) in parts.enumerated() {
            shown[index].opacity = Float(sleeping ? part.asleep : 1)
            haloes[index]?.opacity = shown[index].opacity
        }
        hold(restPose)
        applyIdle()
    }

    /// The soft copies glowing behind the parts that glow, by part.
    private var haloes: [Int: CAShapeLayer] = [:]

    /// The body's own colours as the fill paints them: a fusion's, a
    /// transformation's or its own, top to bottom.
    private static func fur(_ look: NotchMascotLook)
        -> (colors: [NotchMascotColor], locations: [NSNumber]?, start: CGPoint, end: CGPoint) {
        if let fusion = look.fusion {
            return (fusion.bodyColors, fusion.fillLocations, fusion.fillStart, fusion.fillEnd)
        }
        if let form = look.form {
            let palette = NotchMascotFormPalette(form)
            func color(_ ns: NSColor) -> NotchMascotColor {
                let rgb = ns.usingColorSpace(.sRGB) ?? ns
                return NotchMascotColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            }
            return ([color(palette.light), color(palette.shade)], nil, CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        }
        let palette = look.bodyPalette
        return ([palette.light, palette.shade], nil, CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
    }

    // MARK: Poses

    private var restPose: NotchMascotCreatures.CritterPose { sleeping ? .asleep : .rest }

    /// Holds `pose` with no motion, as when it is drawn.
    func hold(_ pose: NotchMascotCreatures.CritterPose) {
        for (index, part) in parts.enumerated() {
            let path = part.path(pose, 0)
            shapes[index].path = path
            haloes[index]?.path = path
        }
    }

    /// Runs the parts through `poses`, evenly spaced unless `times` says,
    /// once over `duration` or for ever, from `beginTime` or now. Only the
    /// parts the poses move take part, so a cat's ears can flick while its
    /// tail keeps swaying.
    private func play(_ poses: [NotchMascotCreatures.CritterPose], times: [Double]? = nil, duration: TimeInterval,
                      key: String = "flourish", repeats: Bool = false, beginTime: CFTimeInterval? = nil) {
        guard style != nil, size > 0, poses.count > 1, duration > 0 else { return }
        let keyTimes = (times ?? poses.indices.map { Double($0) / Double(poses.count - 1) }).map { NSNumber(value: $0) }
        for (index, part) in parts.enumerated() {
            let frames = poses.map { part.path($0, 0) }
            guard frames.contains(where: { $0 != frames[0] }) else { continue }
            for layer in [shapes[index], haloes[index]].compactMap({ $0 }) {
                let move = CAKeyframeAnimation(keyPath: "path")
                move.values = frames
                move.keyTimes = keyTimes
                move.duration = duration
                move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if repeats { move.repeatCount = .infinity }
                if let beginTime { move.beginTime = beginTime }
                layer.add(move, forKey: key)
            }
        }
    }

    /// Asleep it curls up or tucks in and its fire sinks to embers; awake
    /// again it takes its pose and flares back up.
    func setSleeping(_ sleeping: Bool, animated: Bool) {
        guard style != nil, sleeping != self.sleeping else { return }
        let from = restPose
        self.sleeping = sleeping
        for layer in shapes + Array(haloes.values) { layer.removeAnimation(forKey: "stride") }
        if animated { play([from, restPose], duration: sleeping ? 0.8 : 0.4, key: "pose") }
        hold(restPose)
        for (index, part) in parts.enumerated() where part.asleep != 1 {
            let opacity = Float(sleeping ? part.asleep : 1)
            for layer in [shown[index], haloes[index]].compactMap({ $0 }) {
                if animated {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                    fade.toValue = opacity
                    fade.duration = sleeping ? 0.8 : 0.3
                    layer.add(fade, forKey: "sleepFade")
                }
                layer.opacity = opacity
            }
        }
        applyIdle()
    }

    /// Walking, it steps one foot and the other; stopping, it settles.
    func setStriding(_ striding: Bool, period: TimeInterval) {
        guard style != nil, striding != self.striding else { return }
        self.striding = striding
        for layer in shapes + Array(haloes.values) { layer.removeAnimation(forKey: "stride") }
        if striding, !sleeping {
            play([.step, .stepOther, .step], duration: period, key: "stride", repeats: true)
        }
        applyIdle()
    }

    // MARK: Idle

    /// Whether motion is welcome for the idle motions.
    private var idling = false
    /// With motion welcome, tails sway, gills wave, flames flicker and
    /// embers rise, each part at its own pace; asleep only the embers go on.
    func setIdle(_ motion: Bool) {
        guard motion != idling else { return }
        idling = motion
        applyIdle()
    }

    private func applyIdle() {
        for layer in shapes + Array(haloes.values) { layer.removeAnimation(forKey: "idle") }
        guard idling, !striding, style != nil, size > 0 else { return }
        let pose = restPose
        for (index, part) in parts.enumerated() {
            guard let idle = part.idle, !sleeping || part.idlesAsleep, idle.steps > 1 else { continue }
            let steps = (0...idle.steps).map { CGFloat($0) / CGFloat(idle.steps) }
            let frames = steps.map { part.path(pose, $0 == 1 ? 0 : $0) }
            for layer in [shapes[index], haloes[index]].compactMap({ $0 }) {
                let move = CAKeyframeAnimation(keyPath: "path")
                move.values = frames
                move.duration = idle.period * (sleeping ? 1.6 : 1)
                move.repeatCount = .infinity
                move.calculationMode = .linear
                // After any change of pose has played out.
                move.beginTime = CACurrentMediaTime() + 0.9
                layer.add(move, forKey: "idle")
            }
        }
    }

    // MARK: Reactions

    private static let cheers: Set<NotchMascotReaction> = [.celebrate, .bounce, .perk, .ready, .groove]
    private static let waves: Set<NotchMascotReaction> = [.wave, .wakeUp]
    private static let bows: Set<NotchMascotReaction> = [.love, .relax]
    private static let starts: Set<NotchMascotReaction> = [.surprised, .panic, .peek]

    /// Wings or paws up for a cheer, a wave for a greeting, a bow for love,
    /// a start that flares or flicks when surprised.
    func flourish(_ reaction: NotchMascotReaction) {
        guard style != nil, size > 0, !sleeping else { return }
        let length = min(1.6, max(0.8, reaction.length))
        if Self.cheers.contains(reaction) {
            play([.rest, .spread, .cheer, .spread, .cheer, .rest], times: [0, 0.15, 0.35, 0.55, 0.75, 1], duration: length)
        } else if Self.waves.contains(reaction) {
            play([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length)
        } else if Self.bows.contains(reaction) {
            play([.rest, .bow, .bow, .rest], times: [0, 0.3, 0.7, 1], duration: length)
        } else if Self.starts.contains(reaction) {
            play([.rest, .twitch, .rest], times: [0, 0.2, 1], duration: min(1, length))
        }
    }

    /// A flick of the ears now, or from `beginTime`.
    func twitch(beginTime: CFTimeInterval? = nil) {
        guard style != nil, size > 0, !sleeping else { return }
        play([.rest, .twitch, .rest, .twitch, .rest], times: [0, 0.2, 0.45, 0.65, 1], duration: 0.5, key: "twitch",
             beginTime: beginTime)
    }

    /// The steps of a solo dance on the desktop, while the desktop turns,
    /// tilts and lifts the whole figure: the swan's bourrée, port de bras
    /// and dying swan.
    func dance(_ move: NotchMascotSoloDance) {
        guard style != nil, size > 0, !sleeping else { return }
        let length = move.length
        switch move {
        case .bourree:
            play([.rest, .step, .stepOther, .step, .stepOther, .step, .stepOther, .rest], duration: length)
        case .portDeBras:
            play([.rest, .spread, .cheer, .spread, .wave, .waveOut, .rest], duration: length)
        case .dyingSwan:
            play([.rest, .spread, .bow, .bow, .asleep, .rest], times: [0, 0.15, 0.35, 0.55, 0.75, 1], duration: length)
        default:
            break
        }
    }

    /// Everything that plays stops.
    func removeAllAnimations() {
        for layer in shapes + shown + Array(haloes.values) { layer.removeAllAnimations() }
        striding = false
        applyIdle()
    }
}
