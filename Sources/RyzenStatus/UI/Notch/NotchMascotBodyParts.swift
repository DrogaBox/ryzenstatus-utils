// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The body a head-only figure grows on the desktop, in one group the rig
/// stacks behind the head and in front of what grows out of its back:
/// legs and feet, a chest in the body's gradient with its panel and
/// details, arms and hands, and the robot's joints. Its arms and legs keep
/// a pose for each face, fold asleep, cheer and wave in a reaction and
/// march as it walks; the robot's heart light pulses while motion is
/// welcome. Hidden for every other figure, and in the island.
final class NotchMascotBodyParts {
    let layer = CALayer()

    private(set) var style: NotchMascotStyle?
    private var size: CGFloat = 0
    /// The pose its face asks for, and whether it is walking.
    private(set) var pose = NotchMascotCreatures.BodyPose.rest
    private var striding = false
    private var idling = false

    private let legs = CAShapeLayer()
    private let feet = CAShapeLayer()
    private let torso = CAGradientLayer()
    private let torsoMask = CAShapeLayer()
    private let panel = CAShapeLayer()
    private let accents = CAShapeLayer()
    private let glow = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let arms = CAShapeLayer()
    private let hands = CAShapeLayer()
    private let hubs = CAShapeLayer()
    private let joints = CAShapeLayer()

    /// The layers whose paths follow the pose.
    private var limbLayers: [CAShapeLayer] { [legs, feet, arms, hands, hubs, joints] }

    private var allLayers: [CALayer] {
        [legs, feet, torso, torsoMask, panel, accents, glow, shine, arms, hands, hubs, joints]
    }

    init() {
        for sublayer in [legs, feet, torso, panel, accents, glow, shine, arms, hands, hubs, joints] {
            layer.addSublayer(sublayer)
        }
        torso.mask = torsoMask
        torso.startPoint = CGPoint(x: 0.5, y: 0)
        torso.endPoint = CGPoint(x: 0.5, y: 1)
        for sublayer in [layer] + allLayers { sublayer.actions = Self.noActions }
        hide()
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "colors": NSNull(),
        "mask": NSNull(), "shadowOpacity": NSNull(), "shadowColor": NSNull(),
    ]

    /// Hidden, as in the island and for any figure but the four heads.
    func hide() {
        style = nil
        layer.isHidden = true
        for sublayer in allLayers { sublayer.removeAllAnimations() }
    }

    // MARK: Look

    /// Draws the body of `look` at `size` points, its chest in the `fill`
    /// gradient the head is drawn in, in `pose`.
    func configure(look: NotchMascotLook, fill: [CGColor], size: CGFloat, scale: CGFloat,
                   pose: NotchMascotCreatures.BodyPose) {
        guard NotchMascotCreatures.headOnly.contains(look.style), size > 0 else { return hide() }
        let style = look.style
        self.style = style
        self.size = size
        self.pose = pose
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        layer.frame = box
        layer.contentsScale = scale
        for sublayer in allLayers {
            sublayer.frame = box
            sublayer.contentsScale = scale
            sublayer.removeAllAnimations()
        }
        layer.isHidden = false
        typealias C = NotchMascotCreatures
        let colors = NotchMascotBodyColors(look)
        let ink = max(0.35, size * 0.008)

        torsoMask.path = C.bodyTorso(look, size: size)
        torso.colors = fill.count > 1 ? fill : [look.bodyPalette.light.cgColor, look.bodyPalette.shade.cgColor]
        // The gradient runs down the chest alone, light at the collar.
        torso.locations = nil
        let chest = torsoMask.path?.boundingBoxOfPath ?? box
        torso.startPoint = CGPoint(x: 0.5, y: chest.minY / size)
        torso.endPoint = CGPoint(x: 0.5, y: chest.maxY / size)
        panel.path = C.bodyPanel(style, size: size)
        panel.fillColor = colors.panel.cgColor
        accents.path = C.bodyAccents(style, size: size)
        accents.fillColor = colors.accents.cgColor
        glow.path = C.bodyGlow(style, size: size)
        glow.fillColor = colors.glow.cgColor
        glow.shadowColor = colors.glow.cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = max(0.6, size * 0.03)
        glow.shadowOpacity = 0.9
        shine.path = C.bodyShine(style, size: size)
        shine.fillColor = NotchMascotColor.shine.cgColor

        legs.fillColor = colors.limbs.darkened(0.08).cgColor
        feet.fillColor = colors.feet.cgColor
        arms.fillColor = colors.limbs.cgColor
        hands.fillColor = colors.hands.cgColor
        hubs.fillColor = colors.hubs.cgColor
        joints.fillColor = colors.joints.cgColor
        // A fine line round the hands and feet keeps them apart from the
        // chest they cross.
        for shape in [hands, feet] {
            shape.strokeColor = colors.joints.cgColor.copy(alpha: style == .minimal ? 0 : 0.5)
            shape.lineWidth = ink
        }
        hold(pose)
        applyIdle()
    }

    // MARK: Poses


    private func paths(_ pose: NotchMascotCreatures.BodyPose) -> [CGPath] {
        guard let style else { return [] }
        typealias C = NotchMascotCreatures
        return [C.bodyLegs(style, pose, size: size), C.bodyFeet(style, pose, size: size),
                C.bodyArms(style, pose, size: size), C.bodyHands(style, pose, size: size),
                C.bodyHandHubs(style, pose, size: size), C.bodyJointBalls(style, pose, size: size)]
    }

    /// Holds `pose` with no motion, as when it is drawn.
    func hold(_ pose: NotchMascotCreatures.BodyPose) {
        for (shape, path) in zip(limbLayers, paths(pose)) { shape.path = path }
    }

    /// Runs the limbs through `poses`, evenly spaced unless `times` says,
    /// once over `duration` or for ever.
    private func play(_ poses: [NotchMascotCreatures.BodyPose], times: [Double]? = nil, duration: TimeInterval,
                      key: String = "flourish", repeats: Bool = false) {
        guard style != nil, size > 0, poses.count > 1, duration > 0 else { return }
        let keyTimes = (times ?? poses.indices.map { Double($0) / Double(poses.count - 1) }).map { NSNumber(value: $0) }
        let frames = poses.map(paths)
        for (index, shape) in limbLayers.enumerated() {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = frames.map { $0[index] }
            move.keyTimes = keyTimes
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if repeats { move.repeatCount = .infinity }
            shape.add(move, forKey: key)
        }
    }

    /// Takes the pose of `mood`: hands on its hips when cross, arms up in a
    /// fright, fists up when thrilled, limp when bored, hands on its tummy
    /// asleep.
    func setMood(_ mood: NotchMascotMood, animated: Bool) {
        let next = NotchMascotCreatures.bodyPose(for: mood)
        guard style != nil, next != pose else { return }
        let from = pose
        pose = next
        if animated, !striding { play([from, next], duration: next == .folded ? 0.7 : 0.3, key: "pose") }
        hold(next)
        applyIdle()
    }

    /// Walking it marches, knees up one after the other and arms swinging;
    /// stopping, it settles back into its pose.
    func setStriding(_ striding: Bool, period: TimeInterval) {
        guard style != nil, striding != self.striding else { return }
        self.striding = striding
        for shape in limbLayers { shape.removeAnimation(forKey: "stride") }
        if striding {
            play([pose, .step, pose, .stepOther, pose], duration: period, key: "stride", repeats: true)
        }
        applyIdle()
    }

    // MARK: Idle

    /// With motion welcome and awake, the robot's heart light beats slowly,
    /// in the render server with no timer in the app.
    func setIdle(_ motion: Bool) {
        idling = motion
        applyIdle()
    }

    private func applyIdle() {
        glow.removeAnimation(forKey: "idle")
        let asleep = pose == .folded
        glow.opacity = asleep ? 0.35 : 1
        guard idling, !asleep, style == .robot, size > 0 else { return }
        let beat = CAKeyframeAnimation(keyPath: "shadowOpacity")
        beat.values = [0.5, 1, 0.6, 1, 0.5]
        beat.keyTimes = [0, 0.12, 0.24, 0.36, 1]
        beat.duration = 1.6
        beat.repeatCount = .infinity
        glow.add(beat, forKey: "idle")
    }

    // MARK: Reactions

    private static let cheers: Set<NotchMascotReaction> = [.celebrate, .bounce, .perk, .ready]
    private static let waves: Set<NotchMascotReaction> = [.wave, .wakeUp, .love]

    /// Arms up for a cheer, a wave for a greeting or for love, a start with
    /// arms flung up when surprised or panicking, fists for a job begun,
    /// and a limp shrug when something failed.
    func flourish(_ reaction: NotchMascotReaction) {
        guard style != nil, size > 0, pose != .folded, !striding else { return }
        let length = min(1.6, max(0.8, reaction.length))
        if Self.cheers.contains(reaction) {
            play([pose, .up, .fists, .up, pose], times: [0, 0.25, 0.5, 0.75, 1], duration: length)
        } else if Self.waves.contains(reaction) {
            play([pose, .wave, .waveOut, .wave, .waveOut, pose], duration: length)
        } else if reaction == .surprised || reaction == .panic {
            play([pose, .up, .up, pose], times: [0, 0.15, 0.7, 1], duration: min(1.2, length))
        } else if reaction == .sweat || reaction == .groove {
            play([pose, .fists, .fists, pose], times: [0, 0.2, 0.75, 1], duration: length)
        } else if reaction == .confused || reaction == .yawn {
            play([pose, .droop, .droop, pose], times: [0, 0.25, 0.75, 1], duration: length)
        }
    }

    /// Everything that plays stops.
    func removeAllAnimations() {
        for sublayer in allLayers { sublayer.removeAllAnimations() }
        striding = false
        applyIdle()
    }
}
