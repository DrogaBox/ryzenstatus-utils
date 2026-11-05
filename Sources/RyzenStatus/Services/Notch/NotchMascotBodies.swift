// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The bodies the four head-only figures grow out on the desktop: the
/// minimal companion, the robot, the chip and the fan are only a head in
/// the island, and walking about the screen they stand on a little chibi
/// body under a smaller head. The robot gets a boxy metal body with ball
/// joints and a heart light, the chip a package body on bent pin legs, the
/// fan a vented frame on splayed stand struts with rubber feet, and the
/// minimal companion a small clean body in the shape of its own head.
/// Vector paths in a square of `size` points from its top left corner, y
/// growing downward, like the rest of the figures. Every pose of one body
/// is built with the same commands, so one morphs into the next.
extension NotchMascotCreatures {
    /// The figures that are only a head in the island and grow a body on
    /// the desktop.
    static let headOnly: Set<NotchMascotStyle> = [.minimal, .robot, .chip, .fan]

    /// How a body holds its arms and legs: at rest, hands on its tummy
    /// asleep, arms thrown up, a wave one way and the other, fists on its
    /// hips, fists up by its chest, limp and knock-kneed, and the two steps
    /// of a march for walking.
    enum BodyPose: CaseIterable {
        case rest, folded, up, wave, waveOut, akimbo, fists, droop, step, stepOther
    }

    /// The pose a body keeps for a face: hands on its hips when cross or
    /// sure of itself, arms up in a fright, fists up when thrilled, limp
    /// when bored or sad, hands on its tummy asleep.
    static func bodyPose(for mood: NotchMascotMood) -> BodyPose {
        switch mood {
        case .sleepy: return .folded
        case .angry, .determined, .smug: return .akimbo
        case .terrified, .surprised: return .up
        case .starstruck, .greedy, .love, .mischievous: return .fists
        case .bored, .crying, .dizzy, .disgusted: return .droop
        default: return .rest
        }
    }

    /// Where a body's joints are in a pose: shoulder, elbow and hand of each
    /// arm; hip, knee and ankle of each leg; left and right as seen on screen.
    struct BodyJoints: Equatable {
        var leftArm: [CGPoint]
        var rightArm: [CGPoint]
        var leftLeg: [CGPoint]
        var rightLeg: [CGPoint]
    }

    /// Where the head's chin sits once the head is made small for the body,
    /// in shares of the figure's size.
    static let bodyChin: CGFloat = 0.575

    // MARK: Head

    /// The head's own box in the island: everything of it that shows, the
    /// robot's antenna and the chip's pins included.
    private static func headBox(_ look: NotchMascotLook) -> CGRect {
        switch look.style {
        case .robot:
            let parts = NotchMascotGeometry.robot(size: 1)
            return [parts.ears, parts.antenna, parts.bulb].reduce(parts.head.boundingBoxOfPath) { $0.union($1.boundingBoxOfPath) }
        case .chip, .fan:
            return bounds(look.style) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        default:
            return NotchMascotGeometry.body(look.shape, size: 1).boundingBoxOfPath
        }
    }

    /// How low the head's chin is in the island: the bottom of its fill,
    /// under which only the chip's pins hang.
    private static func headChin(_ look: NotchMascotLook) -> CGFloat {
        switch look.style {
        case .robot: return NotchMascotGeometry.robot(size: 1).head.boundingBoxOfPath.maxY
        case .chip: return 0.90
        default: return headBox(look).maxY
        }
    }

    /// How much smaller the head is drawn over a body.
    private static func headScale(_ style: NotchMascotStyle) -> CGFloat {
        switch style {
        case .robot: return 0.6
        case .chip: return 0.64
        case .fan: return 0.64
        default: return 0.62
        }
    }

    /// Takes the island's head, in shares, to where it sits over the body:
    /// smaller, centred across, its chin on the body's shoulders.
    static func headFit(_ look: NotchMascotLook) -> CGAffineTransform {
        let scale = headScale(look.style)
        let box = headBox(look)
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: 0.5 - box.midX * scale, ty: bodyChin - headChin(look) * scale)
    }

    /// The same, in points, for a figure `size` points tall.
    static func headFit(_ look: NotchMascotLook, size: CGFloat) -> CGAffineTransform {
        let fit = headFit(look)
        return CGAffineTransform(a: fit.a, b: 0, c: 0, d: fit.d, tx: fit.tx * size, ty: fit.ty * size)
    }

    /// The face of `look` where the smaller head puts it.
    static func bodiedFace(_ look: NotchMascotLook) -> NotchMascotFaceLayout {
        let face = look.face
        let fit = headFit(look)
        return NotchMascotFaceLayout(leftEye: face.leftEye.applying(fit), rightEye: face.rightEye.applying(fit),
                                     eyeSize: CGSize(width: face.eyeSize.width * fit.a, height: face.eyeSize.height * fit.a),
                                     shineCenter: face.shineCenter.applying(fit),
                                     shineRadii: CGSize(width: face.shineRadii.width * fit.a,
                                                        height: face.shineRadii.height * fit.a),
                                     shineAngle: face.shineAngle)
    }

    /// The whole figure with its body, head to soles, in shares.
    static func bodiedBounds(_ look: NotchMascotLook) -> CGRect {
        let head = headBox(look).applying(headFit(look))
        let floor = bodyFeet(look.style, .rest, size: 1).boundingBoxOfPath.maxY
        let reach = bodyHands(look.style, .rest, size: 1).boundingBoxOfPath
        let minX = min(head.minX, reach.minX), maxX = max(head.maxX, reach.maxX)
        return CGRect(x: minX, y: head.minY, width: maxX - minX, height: floor - head.minY)
    }

    /// Where its hands, feet and chest are on the body, so what it holds is
    /// in its hands and what it wears on its feet is on its feet.
    static func bodiedAnatomy(_ style: NotchMascotStyle) -> NotchMascotAnatomy {
        let rest = bodyJoints(style, .rest)
        let frame = bodyFrame(style)
        let feet = bodyFeet(style, .rest, size: 1).boundingBoxOfPath
        let out = frame.footOut
        return NotchMascotAnatomy(rightHand: rest.rightArm[2], leftHand: rest.leftArm[2], floor: feet.maxY,
                                  leftFoot: rest.leftLeg[2].x - out, rightFoot: rest.rightLeg[2].x + out,
                                  foot: frame.foot.width, torso: frame.torso)
    }

    /// Where a grown body's soles come to in its box once placed, about
    /// where a head-only figure's bottom comes to.
    static let bodiedFloor: CGFloat = 0.95

    /// Where a scarf goes round its neck, just under the head.
    static let bodiedNeck: CGFloat = 0.585

    /// It walks on its own two legs: quick little steps and a small bob.
    static func bodiedGait(_ style: NotchMascotStyle) -> NotchMascotGait {
        switch style {
        // The robot marches, stiff and heavy.
        case .robot: return NotchMascotGait(period: 0.32, bob: 0.03, rock: 0.05)
        case .chip: return NotchMascotGait(period: 0.22, bob: 0.035, rock: 0)
        case .fan: return NotchMascotGait(period: 0.28, bob: 0.03, rock: 0.03)
        default: return NotchMascotGait(period: 0.26, bob: 0.045, rock: 0)
        }
    }

    // MARK: Frame and joints

    /// The fixed points and sizes of each body.
    private struct BodyFrame {
        /// The left shoulder and hip; the right ones mirror them.
        var shoulder: CGPoint
        var hip: CGPoint
        var upperArm: CGFloat
        var forearm: CGFloat
        var thigh: CGFloat
        var shin: CGFloat
        var arm: CGFloat
        var leg: CGFloat
        var hand: CGFloat
        var foot: CGSize
        /// How far each foot sits out past its ankle.
        var footOut: CGFloat
        var footRound: CGFloat
        /// How each leg stands at rest: thigh and shin.
        var stand: (thigh: CGFloat, shin: CGFloat)
        var torso: CGRect
    }

    private static func bodyFrame(_ style: NotchMascotStyle) -> BodyFrame {
        switch style {
        case .robot:
            return BodyFrame(shoulder: CGPoint(x: 0.34, y: 0.612), hip: CGPoint(x: 0.452, y: 0.79),
                             upperArm: 0.066, forearm: 0.062, thigh: 0.062, shin: 0.068, arm: 0.04, leg: 0.05,
                             hand: 0.03, foot: CGSize(width: 0.088, height: 0.048), footOut: 0.006, footRound: 0.018,
                             stand: (3, -1), torso: CGRect(x: 0.36, y: 0.565, width: 0.28, height: 0.215))
        case .chip:
            return BodyFrame(shoulder: CGPoint(x: 0.362, y: 0.606), hip: CGPoint(x: 0.452, y: 0.768),
                             upperArm: 0.07, forearm: 0.064, thigh: 0.07, shin: 0.105, arm: 0.026, leg: 0.03,
                             hand: 0.022, foot: CGSize(width: 0.078, height: 0.026), footOut: 0.016, footRound: 0.01,
                             stand: (34, -2), torso: CGRect(x: 0.37, y: 0.565, width: 0.26, height: 0.205))
        case .fan:
            return BodyFrame(shoulder: CGPoint(x: 0.362, y: 0.608), hip: CGPoint(x: 0.448, y: 0.758),
                             upperArm: 0.07, forearm: 0.064, thigh: 0.08, shin: 0.095, arm: 0.03, leg: 0.034,
                             hand: 0.026, foot: CGSize(width: 0.086, height: 0.032), footOut: 0.012, footRound: 0.016,
                             stand: (12, 10), torso: CGRect(x: 0.37, y: 0.565, width: 0.26, height: 0.2))
        default:
            return BodyFrame(shoulder: CGPoint(x: 0.39, y: 0.612), hip: CGPoint(x: 0.458, y: 0.76),
                             upperArm: 0.064, forearm: 0.058, thigh: 0.074, shin: 0.085, arm: 0.054, leg: 0.06,
                             hand: 0.031, foot: CGSize(width: 0.08, height: 0.05), footOut: 0.01, footRound: 0.025,
                             stand: (3, 0), torso: CGRect(x: 0.385, y: 0.55, width: 0.23, height: 0.225))
        }
    }

    /// One arm's angles in degrees, upper arm then forearm, and one leg's,
    /// thigh then shin: nought hangs straight down, a positive angle turns
    /// out to the body's own side and a hundred and eighty points straight up.
    /// A leg's `reach` is how much of its thigh shows: a knee raised toward
    /// the viewer foreshortens it, lifting the foot straight up.
    private typealias Arm = (upper: CGFloat, fore: CGFloat)
    private typealias Leg = (thigh: CGFloat, shin: CGFloat, reach: CGFloat)

    private static func bodyAngles(_ style: NotchMascotStyle, _ pose: BodyPose)
        -> (left: Arm, right: Arm, leftLeg: Leg, rightLeg: Leg) {
        let frame = bodyFrame(style).stand
        let stand: Leg = (frame.thigh, frame.shin, 1)
        let hang: Arm = style == .robot ? (16, 5) : (18, 8)
        // A step raises one knee toward the viewer, its foot coming straight up.
        let lifted: Leg = (stand.thigh + 10, stand.shin - 6, 0.4)
        switch pose {
        case .rest: return (hang, hang, stand, stand)
        case .folded: return ((10, -95), (10, -95), stand, stand)
        case .up: return ((118, 148), (118, 148), stand, stand)
        case .wave: return (hang, (100, 162), stand, stand)
        case .waveOut: return (hang, (100, 128), stand, stand)
        case .akimbo: return ((50, -62), (50, -62), (stand.thigh + 6, stand.shin + 2, 1), (stand.thigh + 6, stand.shin + 2, 1))
        case .fists: return ((30, -150), (30, -150), stand, stand)
        case .droop:
            let knock: Leg = (stand.thigh - 6, stand.shin + 10, 1)
            return ((4, 0), (4, 0), knock, knock)
        case .step: return ((30, 14), (6, -4), lifted, stand)
        case .stepOther: return ((6, -4), (30, 14), stand, lifted)
        }
    }

    /// The joints of `style`'s body in `pose`, in shares of the figure's size.
    static func bodyJoints(_ style: NotchMascotStyle, _ pose: BodyPose) -> BodyJoints {
        let frame = bodyFrame(style)
        let angles = bodyAngles(style, pose)
        func step(_ from: CGPoint, _ degrees: CGFloat, _ length: CGFloat, side: CGFloat) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: from.x + side * sin(angle) * length, y: from.y + cos(angle) * length)
        }
        func arm(_ angles: Arm, side: CGFloat) -> [CGPoint] {
            let shoulder = CGPoint(x: side < 0 ? frame.shoulder.x : 1 - frame.shoulder.x, y: frame.shoulder.y)
            let elbow = step(shoulder, angles.upper, frame.upperArm, side: side)
            return [shoulder, elbow, step(elbow, angles.fore, frame.forearm, side: side)]
        }
        func leg(_ angles: Leg, side: CGFloat) -> [CGPoint] {
            let hip = CGPoint(x: side < 0 ? frame.hip.x : 1 - frame.hip.x, y: frame.hip.y)
            let knee = step(hip, angles.thigh, frame.thigh * angles.reach, side: side)
            return [hip, knee, step(knee, angles.shin, frame.shin, side: side)]
        }
        return BodyJoints(leftArm: arm(angles.left, side: -1), rightArm: arm(angles.right, side: 1),
                          leftLeg: leg(angles.leftLeg, side: -1), rightLeg: leg(angles.rightLeg, side: 1))
    }

    // MARK: Limbs

    /// Both arms, to the wrist; the hands are drawn over them.
    static func bodyArms(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let frame = bodyFrame(style)
        let joints = bodyJoints(style, pose)
        let path = CGMutablePath()
        for arm in [joints.leftArm, joints.rightArm] {
            limb(into: path, arm, width: frame.arm, hand: frame.arm * 0.5, size: size)
        }
        return path
    }

    /// Both hands: the robot's round mitts, the chip's solder balls, the
    /// fan's rubber grommets, the minimal companion's round little hands.
    static func bodyHands(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let frame = bodyFrame(style)
        let joints = bodyJoints(style, pose)
        let path = CGMutablePath()
        for hand in [joints.leftArm[2], joints.rightArm[2]] {
            path.addEllipse(in: box(hand.x - frame.hand, hand.y - frame.hand, frame.hand * 2, frame.hand * 2, size))
        }
        return path
    }

    /// The middle of each hand: the fan's grommet holes. Empty for the rest.
    static func bodyHandHubs(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style == .fan else { return path }
        let joints = bodyJoints(style, pose)
        let radius = bodyFrame(style).hand * 0.42
        for hand in [joints.leftArm[2], joints.rightArm[2]] {
            path.addEllipse(in: box(hand.x - radius, hand.y - radius, radius * 2, radius * 2, size))
        }
        return path
    }

    /// Both legs, hip to ankle.
    static func bodyLegs(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let frame = bodyFrame(style)
        let joints = bodyJoints(style, pose)
        let path = CGMutablePath()
        for leg in [joints.leftLeg, joints.rightLeg] {
            limb(into: path, leg, width: frame.leg, hand: frame.leg * 0.5, size: size)
        }
        return path
    }

    /// Both feet, a little out past each ankle: the robot's boots, the
    /// chip's flat solder pads, the fan's rubber feet, round little feet.
    static func bodyFeet(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let frame = bodyFrame(style)
        let joints = bodyJoints(style, pose)
        let path = CGMutablePath()
        for (ankle, side) in [(joints.leftLeg[2], CGFloat(-1)), (joints.rightLeg[2], CGFloat(1))] {
            let center = CGPoint(x: ankle.x + side * frame.footOut, y: ankle.y + frame.foot.height * 0.2)
            path.addRoundedRect(in: box(center.x - frame.foot.width / 2, center.y - frame.foot.height / 2,
                                        frame.foot.width, frame.foot.height, size),
                                cornerWidth: frame.footRound * size, cornerHeight: frame.footRound * size)
        }
        return path
    }

    /// The robot's ball joints at shoulders, elbows, hips and knees. Empty
    /// for the rest, whose limbs bend without them.
    static func bodyJointBalls(_ style: NotchMascotStyle, _ pose: BodyPose, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style == .robot else { return path }
        let joints = bodyJoints(style, pose)
        let ball: CGFloat = 0.021
        for point in [joints.leftArm[0], joints.leftArm[1], joints.rightArm[0], joints.rightArm[1],
                      joints.leftLeg[1], joints.rightLeg[1]] {
            path.addEllipse(in: box(point.x - ball, point.y - ball, ball * 2, ball * 2, size))
        }
        return path
    }

    // MARK: Torso

    /// The chest the body's gradient fills: a boxy metal chest, a chip's
    /// package, the fan's frame, or the minimal companion's head shape again.
    static func bodyTorso(_ look: NotchMascotLook, size: CGFloat) -> CGPath {
        let torso = bodyFrame(look.style).torso
        let rect = box(torso.minX, torso.minY, torso.width, torso.height, size)
        switch look.style {
        case .robot:
            return CGPath(roundedRect: rect, cornerWidth: 0.055 * size, cornerHeight: 0.055 * size, transform: nil)
        case .chip:
            return CGPath(roundedRect: rect, cornerWidth: 0.03 * size, cornerHeight: 0.03 * size, transform: nil)
        case .fan:
            return CGPath(roundedRect: rect, cornerWidth: 0.05 * size, cornerHeight: 0.05 * size, transform: nil)
        default:
            // Its own head's shape, made to fit the chest.
            let shape = NotchMascotGeometry.body(look.shape, size: 1)
            let from = shape.boundingBoxOfPath
            var fit = CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / from.width, y: rect.height / from.height)
                .translatedBy(x: -from.minX, y: -from.minY)
            return shape.copy(using: &fit) ?? CGPath(rect: rect, transform: nil)
        }
    }

    /// The dark parts of the chest: the robot's screen, belt and hip block,
    /// the fan's grille.
    static func bodyPanel(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
            path.addRoundedRect(in: box(x, y, width, height, size), cornerWidth: radius * size, cornerHeight: radius * size)
        }
        switch style {
        case .robot:
            rounded(0.41, 0.6, 0.18, 0.108, 0.03)
            rounded(0.372, 0.738, 0.256, 0.022, 0.01)
            rounded(0.415, 0.772, 0.17, 0.032, 0.012)
        case .fan:
            rounded(0.4, 0.594, 0.2, 0.142, 0.036)
        default:
            break
        }
        return path
    }

    /// Details in the body's shade: the robot's rivets, the chip's side pins
    /// and pin-one dot, the fan's slats and corner screws.
    static func bodyAccents(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: box(x - radius, y - radius, radius * 2, radius * 2, size))
        }
        func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
            path.addRoundedRect(in: box(x, y, width, height, size), cornerWidth: radius * size, cornerHeight: radius * size)
        }
        switch style {
        case .robot:
            for (x, y) in [(0.386, 0.592), (0.614, 0.592), (0.386, 0.722), (0.614, 0.722)] as [(CGFloat, CGFloat)] {
                dot(x, y, 0.008)
            }
        case .chip:
            // Two pins down each side under the arms, and the pin-one dot.
            for y in [0.7, 0.742] as [CGFloat] {
                rounded(0.342, y - 0.011, 0.034, 0.022, 0.006)
                rounded(0.624, y - 0.011, 0.034, 0.022, 0.006)
            }
            dot(0.402, 0.603, 0.013)
        case .fan:
            for y in [0.622, 0.657, 0.692] as [CGFloat] {
                rounded(0.418, y, 0.164, 0.016, 0.008)
            }
            for (x, y) in [(0.388, 0.583), (0.612, 0.583), (0.388, 0.747), (0.612, 0.747)] as [(CGFloat, CGFloat)] {
                dot(x, y, 0.009)
            }
        default:
            break
        }
        return path
    }

    /// The robot's heart light, lit in its eyes' colour. Empty for the rest.
    static func bodyGlow(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style == .robot else { return path }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        // A little heart in the middle of its screen.
        path.move(to: point(0.5, 0.684))
        path.addCurve(to: point(0.466, 0.642), control1: point(0.484, 0.672), control2: point(0.466, 0.659))
        path.addCurve(to: point(0.5, 0.632), control1: point(0.466, 0.622), control2: point(0.492, 0.619))
        path.addCurve(to: point(0.534, 0.642), control1: point(0.508, 0.619), control2: point(0.534, 0.622))
        path.addCurve(to: point(0.5, 0.684), control1: point(0.534, 0.659), control2: point(0.516, 0.672))
        path.closeSubpath()
        return path
    }

    /// A soft highlight up on the chest of the minimal companion, as on its
    /// head. Empty for the rest.
    static func bodyShine(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        guard style == .minimal else { return CGMutablePath() }
        var tilt = CGAffineTransform(translationX: 0.438 * size, y: 0.6 * size).rotated(by: -0.5)
        return CGPath(ellipseIn: box(-0.03, -0.017, 0.06, 0.034, size), transform: &tilt)
    }
}

/// The colours of a grown body, worked out from the body's light and shade
/// so the body belongs to its head on every palette and any hand-picked
/// colour: limbs in the shade, hands and pads in the light, joints and
/// rubber in a dark tint of the hue, the robot's heart in its eyes' light.
struct NotchMascotBodyColors: Equatable {
    var limbs: NotchMascotColor
    var hands: NotchMascotColor
    var hubs: NotchMascotColor
    var feet: NotchMascotColor
    var panel: NotchMascotColor
    var accents: NotchMascotColor
    var joints: NotchMascotColor
    var glow: NotchMascotColor

    init(style: NotchMascotStyle, light: NotchMascotColor, shade: NotchMascotColor) {
        let (hue, saturation, _) = shade.hsb
        let tint = saturation < 0.12 ? 0.62 : hue
        let graphite = NotchMascotColor.hsb(tint, 0.22, 0.2)
        panel = NotchMascotColor.visor
        glow = light
        joints = graphite
        hubs = light
        switch style {
        case .robot:
            limbs = shade
            hands = light
            feet = shade.darkened(0.25)
            accents = shade.darkened(0.15)
        case .chip:
            // Pins in the shade, as on its head, with bright tinned tips.
            limbs = shade
            hands = light.brightened(0.35)
            feet = light.brightened(0.35)
            accents = shade
        case .fan:
            limbs = shade
            hands = graphite
            feet = graphite
            accents = shade
        default:
            limbs = NotchMascotColor(red: (light.red + shade.red) / 2, green: (light.green + shade.green) / 2,
                                     blue: (light.blue + shade.blue) / 2)
            hands = light
            feet = shade
            accents = shade
        }
    }

    init(_ look: NotchMascotLook) {
        let palette = look.bodyPalette
        self.init(style: look.style, light: palette.light, shade: palette.shade)
    }
}
