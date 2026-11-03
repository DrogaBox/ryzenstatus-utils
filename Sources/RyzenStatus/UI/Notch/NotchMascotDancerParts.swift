// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// Everything the three dancers are drawn with beyond their body fill and
/// eyes, in two groups the decor stacks behind the body and over it: hair,
/// skin, a costume in the palette's colours with its trim, and arms and
/// legs that take the poses of the dance. Asleep they fold their arms and
/// come down off their toes; they cheer, wave and bow with their arms; on
/// the desktop they hold an arabesque, draw up a retiré to turn, split in a
/// grand jeté; and they step lightly as they go. The contemporary dancer's
/// veil sways on its own while motion is welcome. Hidden for every other
/// figure.
final class NotchMascotDancerParts {
    let back = CALayer()
    let middle = CALayer()

    private(set) var style: NotchMascotStyle?
    private var size: CGFloat = 0
    private var sleeping = false
    private var striding = false
    private var colors = NotchMascotDancerColors(style: .ballerina, light: NotchMascotPalette.sky.light,
                                                 shade: NotchMascotPalette.sky.shade)

    private let hairBack = CAShapeLayer()
    private let veil = CAShapeLayer()
    /// The leg on the right of the screen, a shade deeper, behind the other.
    private let farLeg = CAShapeLayer()
    private let legs = CAShapeLayer()
    private let feet = CAShapeLayer()
    private let laces = CAShapeLayer()
    private let underskirt = CAShapeLayer()
    private let skirt = CAGradientLayer()
    private let skirtMask = CAShapeLayer()
    private let pleats = CAShapeLayer()
    private let skin = CAShapeLayer()
    private let chin = CAShapeLayer()
    private let cheeks = CAShapeLayer()
    private let torso = CAGradientLayer()
    private let torsoMask = CAShapeLayer()
    private let panel = CAGradientLayer()
    private let panelMask = CAShapeLayer()
    private let details = CAShapeLayer()
    private let hair = CAShapeLayer()
    private let hairShine = CAShapeLayer()
    private let trim = CAShapeLayer()
    private let gems = CAShapeLayer()
    private let arms = CAShapeLayer()
    private let sleeves = CAShapeLayer()
    private let cuffs = CAShapeLayer()

    /// The layers whose paths follow the pose.
    private var limbLayers: [CAShapeLayer] { [veil, farLeg, legs, feet, laces, arms, sleeves, cuffs] }

    private var allLayers: [CALayer] {
        [hairBack, veil, farLeg, legs, feet, laces, underskirt, skirt, skirtMask, pleats, skin, chin, cheeks, torso, torsoMask,
         panel, panelMask, details, hair, hairShine, trim, gems, arms, sleeves, cuffs]
    }

    init() {
        back.addSublayer(veil)
        back.addSublayer(hairBack)
        for layer in [farLeg, legs, feet, laces, underskirt, skirt, pleats, skin, chin, cheeks, torso, panel, details, hair, hairShine,
                      trim, gems, arms, sleeves, cuffs] {
            middle.addSublayer(layer)
        }
        skirt.mask = skirtMask
        torso.mask = torsoMask
        panel.mask = panelMask
        for layer in [back, middle] + allLayers { layer.actions = Self.noActions }
        for gradient in [skirt, torso, panel] {
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        feet.lineJoin = .round
        hide()
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "colors": NSNull(), "locations": NSNull(), "mask": NSNull(),
    ]

    /// Hidden, as for any figure but the dancers.
    func hide() {
        style = nil
        for layer in [back, middle] { layer.isHidden = true }
        for layer in allLayers { layer.removeAllAnimations() }
    }

    // MARK: Look

    /// Draws the dancer of `look` at `size` points; any other figure hides
    /// it all.
    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat, sleeping: Bool) {
        guard NotchMascotCreatures.dancers.contains(look.style) else { return hide() }
        let style = look.style
        self.style = style
        self.size = size
        self.sleeping = sleeping
        colors = NotchMascotDancerColors(look)
        let c = colors
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [back, middle] + allLayers {
            layer.frame = box
            layer.contentsScale = scale
            layer.removeAllAnimations()
        }
        for layer in [back, middle] { layer.isHidden = false }
        typealias C = NotchMascotCreatures
        // A swan's crown takes the place of her tiara.
        let hat = NotchMascotWearables.coversHead(look.accessory) || look.accessory == .swanCrown
        let line = max(0.35, size * 0.009)

        hairBack.path = C.dancerHairBack(style, hat: hat, size: size)
        hairBack.fillColor = c.hair.darkened(0.14).cgColor
        veil.fillColor = c.costume.brightened(0.15).cgColor.copy(alpha: 0.75)

        legs.fillColor = c.legs.cgColor
        farLeg.fillColor = c.farLeg.cgColor
        feet.fillColor = c.feet.cgColor
        feet.strokeColor = (style == .contemporary ? c.skinShade : c.feet.darkened(0.16)).cgColor
        feet.lineWidth = line
        laces.fillColor = c.laces.cgColor

        underskirt.path = C.dancerUnderskirt(style, size: size)
        underskirt.fillColor = c.costumeDeep.brightened(0.18).cgColor
        skirtMask.path = C.dancerSkirt(style, size: size)
        skirt.colors = [c.costumeLight.cgColor, c.costume.cgColor]
        skirt.locations = style == .ballerina ? [0.56, 0.66] : [0.64, 0.74]
        pleats.path = C.dancerPleats(style, size: size)
        pleats.fillColor = c.costumeLight.brightened(0.3).cgColor.copy(alpha: style == .ballerina ? 0.75 : 0.45)

        skin.path = C.dancerSkin(style, size: size)
        skin.fillColor = c.skin.cgColor
        chin.path = C.dancerChinShadow(size: size)
        chin.fillColor = c.skinShade.cgColor
        cheeks.path = C.dancerCheeks(size: size)
        cheeks.fillColor = c.cheeks.cgColor.copy(alpha: style == .contemporary ? 0.22 : 0.3)

        torsoMask.path = C.dancerTorso(style, size: size)
        torso.colors = [c.costume.cgColor, c.costumeDeep.cgColor]
        torso.locations = style == .ballerina ? [0.5, 0.64] : [0.5, 0.76]
        panelMask.path = C.dancerPanel(style, size: size)
        panel.colors = style == .contemporary
            ? [c.costumeLight.cgColor.copy(alpha: 0.92)!, c.costumeLight.cgColor.copy(alpha: 0.75)!]
            : [c.costumeLight.cgColor, c.costume.cgColor]
        panel.locations = [0.48, 0.66]
        details.path = C.dancerDetails(style, size: size)
        details.fillColor = style == .danseur ? c.costumeDeep.darkened(0.35).cgColor
            : c.costumeDeep.cgColor.copy(alpha: style == .contemporary ? 0.45 : 0.8)

        hair.path = C.dancerHair(style, size: size)
        hair.fillColor = c.hair.cgColor
        hairShine.path = C.dancerHairShine(style, hat: hat, size: size)
        hairShine.fillColor = c.hairShine.cgColor.copy(alpha: 0.85)
        trim.path = C.dancerTrim(style, hat: hat, size: size)
        trim.fillColor = c.trim.cgColor
        gems.path = C.dancerGems(style, hat: hat, size: size)
        gems.fillColor = c.gem.cgColor

        arms.fillColor = c.skin.cgColor
        sleeves.fillColor = (style == .danseur ? c.costumeDeep.brightened(0.2) : c.costume).cgColor
        cuffs.fillColor = c.trim.cgColor
        hold(restPose)
    }

    // MARK: Poses

    private var restPose: NotchMascotCreatures.DancerPose { sleeping ? .folded : .rest }

    private func paths(_ pose: NotchMascotCreatures.DancerPose) -> [CGPath] {
        guard let style else { return [] }
        typealias C = NotchMascotCreatures
        // The veil streams out as she steps and leaps.
        let sway: CGFloat
        switch pose {
        case .step, .stepOther: sway = 0.8
        case .jete, .arabesque, .reach: sway = 0.6
        default: sway = 0
        }
        return [C.dancerVeil(style, pose, sway: sway, size: size), C.dancerLegs(style, pose, left: false, size: size), C.dancerLegs(style, pose, left: true, size: size),
                C.dancerFeet(style, pose, size: size), C.dancerLaces(style, pose, size: size),
                C.dancerArms(style, pose, size: size), C.dancerSleeves(style, pose, size: size),
                C.dancerCuffs(style, pose, size: size)]
    }

    /// Holds `pose` with no motion, as when it is drawn.
    func hold(_ pose: NotchMascotCreatures.DancerPose) {
        for (layer, path) in zip(limbLayers, paths(pose)) { layer.path = path }
    }

    /// Runs the limbs through `poses`, evenly spaced unless `times` says,
    /// once over `duration` or for ever.
    private func play(_ poses: [NotchMascotCreatures.DancerPose], times: [Double]? = nil, duration: TimeInterval,
                      key: String = "flourish", repeats: Bool = false) {
        guard style != nil, size > 0, poses.count > 1, duration > 0 else { return }
        let keyTimes = (times ?? poses.indices.map { Double($0) / Double(poses.count - 1) }).map { NSNumber(value: $0) }
        let frames = poses.map(paths)
        for (index, layer) in limbLayers.enumerated() {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = frames.map { $0[index] }
            move.keyTimes = keyTimes
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if repeats { move.repeatCount = .infinity }
            layer.add(move, forKey: key)
        }
    }

    /// Asleep it folds its arms and comes down off its toes; awake again it
    /// takes its pose.
    func setSleeping(_ sleeping: Bool, animated: Bool) {
        guard style != nil, sleeping != self.sleeping else { return }
        let from = restPose
        self.sleeping = sleeping
        for layer in limbLayers { layer.removeAnimation(forKey: "stride") }
        if animated { play([from, restPose], duration: sleeping ? 0.7 : 0.35, key: "pose") }
        hold(restPose)
        applyIdle()
    }

    /// Walking, the ballerina runs in tiny bourrée steps on her toes and the
    /// others step lightly; stopping, they settle back into their pose.
    func setStriding(_ striding: Bool, period: TimeInterval) {
        guard let style, striding != self.striding else { return }
        self.striding = striding
        for layer in limbLayers { layer.removeAnimation(forKey: "stride") }
        if striding, !sleeping {
            play([.step, .stepOther, .step], duration: style == .ballerina ? period * 0.6 : period, key: "stride", repeats: true)
        }
        applyIdle()
    }

    // MARK: Idle

    /// Whether motion is welcome for the idle sway.
    private var idling = false
    /// With motion welcome and awake, the contemporary dancer's veil and
    /// wrap sway slowly, in the render server with no timer in the app.
    func setIdle(_ motion: Bool) {
        idling = motion
        applyIdle()
    }
    private func applyIdle() {
        for layer in [veil, panelMask] { layer.removeAnimation(forKey: "idle") }
        guard idling, !sleeping, !striding, let style, style == .contemporary, size > 0 else { return }
        let sways: [CGFloat] = [0, 0.6, 0]
        let veils = sways.map { NotchMascotCreatures.dancerVeil(style, restPose, sway: $0, size: size) }
        let wraps = sways.map { NotchMascotCreatures.dancerPanel(style, sway: $0, size: size) }
        for (layer, paths) in [(veil, veils), (panelMask, wraps)] {
            let move = CAKeyframeAnimation(keyPath: "path")
            move.values = paths
            move.keyTimes = [0, 0.5, 1]
            move.duration = 3.4
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // After any change of pose has played out.
            move.beginTime = CACurrentMediaTime() + 0.8
            layer.add(move, forKey: "idle")
        }
    }
    // MARK: Reactions

    private static let cheers: Set<NotchMascotReaction> = [.celebrate, .bounce, .perk, .ready]
    private static let waves: Set<NotchMascotReaction> = [.wave, .wakeUp]
    private static let bows: Set<NotchMascotReaction> = [.love, .relax]

    /// Arms up for a cheer, with a turn of the leg for the ballerina and a
    /// reach for the contemporary dancer; a wave for a greeting; a bow for
    /// love; a start with arms flung up when surprised.
    func flourish(_ reaction: NotchMascotReaction) {
        guard let style, size > 0, !sleeping else { return }
        let length = min(1.6, max(0.8, reaction.length))
        if Self.cheers.contains(reaction) {
            switch style {
            case .ballerina: play([.rest, .passe, .up, .up, .rest], times: [0, 0.25, 0.5, 0.8, 1], duration: length)
            case .danseur: play([.rest, .contract, .tour, .rest], times: [0, 0.3, 0.6, 1], duration: length)
            default: play([.rest, .contract, .reach, .rest], times: [0, 0.3, 0.6, 1], duration: length)
            }
        } else if Self.waves.contains(reaction) {
            play([.rest, .wave, .waveOut, .wave, .waveOut, .rest], duration: length)
        } else if Self.bows.contains(reaction) {
            play([.rest, .reverence, .reverence, .rest], times: [0, 0.3, 0.7, 1], duration: length)
        } else if reaction == .surprised {
            play([.rest, .up, .rest], times: [0, 0.2, 1], duration: min(1, length))
        }
    }

    /// The steps of a solo dance on the desktop, while the desktop turns,
    /// tilts and lifts the whole figure.
    func dance(_ move: NotchMascotSoloDance) {
        guard style != nil, size > 0, !sleeping else { return }
        let length = move.length
        switch move {
        case .arabesque:
            play([.rest, .arabesque, .arabesque, .rest], times: [0, 0.15, 0.8, 1], duration: length)
        case .fouettes, .pirouettes:
            play([.rest, .contract, .passe, .passe, .reverence, .rest], times: [0, 0.06, 0.12, 0.72, 0.85, 1], duration: length)
        case .grandJete, .sautDeBasque, .cabriole:
            play([.rest, .contract, .jete, .jete, .contract, .rest], times: [0, 0.1, 0.22, 0.42, 0.55, 0.75], duration: length)
        case .doubleTour:
            play([.rest, .contract, .tour, .tour, .contract, .rest], times: [0, 0.1, 0.22, 0.45, 0.55, 0.75], duration: length)
        case .reverence:
            play([.rest, .reverence, .reverence, .rest], times: [0, 0.25, 0.75, 1], duration: length)
        case .bourree:
            play([.rest, .step, .stepOther, .step, .stepOther, .step, .stepOther, .rest], duration: length)
        case .floorwork, .contractRelease:
            play([.rest, .contract, .contract, .reach, .rest], times: [0, 0.15, 0.4, 0.6, 1], duration: length)
        case .fallRecovery:
            play([.rest, .reach, .contract, .rest], times: [0, 0.3, 0.55, 1], duration: length)
        case .handstand:
            play([.rest, .up, .up, .rest], times: [0, 0.1, 0.7, 0.85], duration: length)
        default:
            break
        }
    }

    /// Everything that plays stops.
    func removeAllAnimations() {
        for layer in allLayers { layer.removeAllAnimations() }
        striding = false
    }
}
