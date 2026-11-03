// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The three dancers, drawn like the hologram and the android: vector paths
/// in a square of `size` points from its top left corner, y growing
/// downward. Each is a chibi with a big head of their own skin and hair over
/// a costume the palette dyes: the ballerina's bodice and platter tutu, the
/// danseur's embroidered tunic, the contemporary dancer's loose drapes. Their
/// arms and legs are drawn apart from the body so they can dance, and every
/// pose of one dancer is built with the same commands, so one morphs into
/// the next.
extension NotchMascotCreatures {
    static let dancers: Set<NotchMascotStyle> = [.ballerina, .danseur, .contemporary]

    /// How a dancer holds its arms and legs: at rest in its own pose, arms
    /// folded asleep, arms up for a cheer, a wave one way and the other, and
    /// the steps it dances: an arabesque, a retiré for turns, the split of a
    /// grand jeté, the crossed legs of a tour en l'air, a bow, a long reach,
    /// a curled contraction, and two alternating steps for walking.
    enum DancerPose: CaseIterable {
        case rest, folded, up, wave, waveOut, arabesque, passe, jete, tour, reverence, reach, contract, step, stepOther
    }

    /// Where a dancer's joints are in a pose: shoulder, elbow and hand of
    /// each arm; hip, knee, ankle and toe of each leg; left and right as seen
    /// on screen.
    struct DancerJoints: Equatable {
        var leftArm: [CGPoint]
        var rightArm: [CGPoint]
        var leftLeg: [CGPoint]
        var rightLeg: [CGPoint]
    }

    /// One arm's angles in degrees, upper arm then forearm, and one leg's,
    /// thigh, shin and foot: nought hangs straight down, a positive angle
    /// turns out to the dancer's own side, ninety is level and a hundred and
    /// eighty points straight up.
    private typealias Arm = (upper: CGFloat, fore: CGFloat)
    private typealias Leg = (thigh: CGFloat, shin: CGFloat, foot: CGFloat)

    /// The fixed points and lengths of each dancer's frame.
    private struct DancerFrame {
        var shoulder: CGPoint
        var hip: CGPoint
        var upperArm: CGFloat
        var forearm: CGFloat
        var thigh: CGFloat
        var shin: CGFloat
        var foot: CGFloat
    }

    private static func dancerFrame(_ style: NotchMascotStyle) -> DancerFrame {
        switch style {
        case .danseur:
            return DancerFrame(shoulder: CGPoint(x: 0.414, y: 0.497), hip: CGPoint(x: 0.468, y: 0.66),
                               upperArm: 0.084, forearm: 0.078, thigh: 0.118, shin: 0.112, foot: 0.05)
        case .contemporary:
            return DancerFrame(shoulder: CGPoint(x: 0.43, y: 0.50), hip: CGPoint(x: 0.468, y: 0.66),
                               upperArm: 0.082, forearm: 0.076, thigh: 0.118, shin: 0.112, foot: 0.046)
        default:
            return DancerFrame(shoulder: CGPoint(x: 0.448, y: 0.493), hip: CGPoint(x: 0.476, y: 0.622),
                               upperArm: 0.08, forearm: 0.074, thigh: 0.126, shin: 0.12, foot: 0.06)
        }
    }

    /// The angles of every pose, each dancer in its own way: the ballerina
    /// en pointe with soft round arms, the danseur standing proud in a
    /// strong second, the contemporary dancer barefoot and off balance.
    private static func dancerAngles(_ style: NotchMascotStyle, _ pose: DancerPose)
        -> (left: Arm, right: Arm, leftLeg: Leg, rightLeg: Leg) {
        let flat: CGFloat = style == .ballerina ? 76 : style == .danseur ? 70 : 80
        let stand: Leg = style == .ballerina ? (2, -6, -6) : style == .danseur ? (4, -1, flat) : (2, -1, flat)
        let rest: (Arm, Arm, Leg, Leg)
        switch style {
        case .danseur: rest = ((64, 84), (64, 84), stand, stand)
        case .contemporary: rest = ((16, 6), (94, 112), stand, (16, 12, 26))
        default: rest = ((40, 14), (40, 14), stand, stand)
        }
        let arabesqueSupport: Leg = style == .ballerina ? (0, 0, 0) : (1, 0, flat)
        let releve: Leg = style == .contemporary ? (0, 0, flat) : (0, 0, 4)
        switch pose {
        case .rest:
            return rest
        case .folded:
            return ((14, -98), (14, -98), (3, 0, flat), (3, 0, flat))
        case .up:
            return ((118, 140), (118, 140), rest.2, rest.3)
        case .wave:
            return (rest.0, (84, 166), rest.2, rest.3)
        case .waveOut:
            return (rest.0, (84, 132), rest.2, rest.3)
        case .arabesque:
            return ((124, 112), (96, 92), arabesqueSupport, (96, 100, 104))
        case .passe:
            return ((32, -58), (32, -58), releve, (82, -76, -96))
        case .jete:
            return ((132, 140), (102, 96), (76, 84, 92), (76, 84, 92))
        case .tour:
            return ((150, 176), (150, 176), (1, -4, -4), (1, -4, -4))
        case .reverence:
            if style == .danseur { return ((72, 96), (22, -84), (3, 0, flat), (22, 26, 44)) }
            return ((56, 66), (56, 66), (-2, 7, flat), (24, 28, 42))
        case .reach:
            return ((164, 176), (72, 90), (0, 0, flat), (40, 40, 52))
        case .contract:
            if style == .danseur { return ((72, 90), (72, 90), (34, -30, 74), (34, -30, 74)) }
            return ((34, -42), (34, -42), (22, -22, 64), (22, -22, 64))
        case .step, .stepOther:
            let swing: CGFloat = style == .ballerina ? 5 : 13
            let ahead: Leg = (stand.thigh + swing, stand.shin + swing * 0.5, style == .ballerina ? stand.foot + swing : 40)
            let behind: Leg = (stand.thigh - swing * 0.6, stand.shin - swing * 0.3, style == .ballerina ? stand.foot : flat)
            return pose == .step ? (rest.0, rest.1, ahead, behind) : (rest.0, rest.1, behind, ahead)
        }
    }

    /// The joints of `style` in `pose`, in shares of the figure's size.
    static func dancerJoints(_ style: NotchMascotStyle, _ pose: DancerPose) -> DancerJoints {
        let frame = dancerFrame(style)
        let angles = dancerAngles(style, pose)
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
            let knee = step(hip, angles.thigh, frame.thigh, side: side)
            let ankle = step(knee, angles.shin, frame.shin, side: side)
            return [hip, knee, ankle, step(ankle, angles.foot, frame.foot, side: side)]
        }
        return DancerJoints(leftArm: arm(angles.left, side: -1), rightArm: arm(angles.right, side: 1),
                            leftLeg: leg(angles.leftLeg, side: -1), rightLeg: leg(angles.rightLeg, side: 1))
    }

    /// Where a dancer holds things and stands, read off its own joints at
    /// rest, so what it wears follows the drawing: hands at the ends of its
    /// arms, the floor under its toes, each shoe on its foot.
    static func dancerAnatomy(_ style: NotchMascotStyle) -> NotchMascotAnatomy {
        let joints = dancerJoints(style, .rest)
        let feet = dancerFeet(style, .rest, size: 1).boundingBoxOfPath
        func middle(_ leg: [CGPoint]) -> CGFloat { (leg[2].x + leg[3].x) / 2 }
        let torso: CGRect
        switch style {
        case .danseur: torso = CGRect(x: 0.39, y: 0.465, width: 0.22, height: 0.235)
        case .contemporary: torso = CGRect(x: 0.39, y: 0.47, width: 0.235, height: 0.21)
        default: torso = CGRect(x: 0.44, y: 0.475, width: 0.12, height: 0.14)
        }
        return NotchMascotAnatomy(rightHand: joints.rightArm[2], leftHand: joints.leftArm[2], floor: feet.maxY,
                                  leftFoot: middle(joints.leftLeg), rightFoot: middle(joints.rightLeg),
                                  foot: style == .ballerina ? 0.05 : 0.07, torso: torso,
                                  nose: CGPoint(x: 0.5, y: 0.362), mouth: CGPoint(x: 0.5, y: 0.39))
    }
    // MARK: Body

    /// The head, neck and costume, which the palette's fill lies under; the
    /// arms and legs are left out, as they move.
    static func dancerBody(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(dancerSkin(style, size: size))
        path.addPath(dancerSkirt(style, size: size))
        path.addPath(dancerTorso(style, size: size))
        return path
    }

    /// The head, neck and bare shoulders.
    static func dancerSkin(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.33, 0.13, 0.34, 0.31, size))
        path.addRect(box(0.477, 0.42, 0.046, 0.06, size))
        switch style {
        case .danseur:
            break
        case .contemporary:
            path.addRoundedRect(in: box(0.425, 0.468, 0.15, 0.05, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        default:
            path.addRoundedRect(in: box(0.432, 0.466, 0.136, 0.05, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        }
        return path
    }

    /// The shadow the chin casts on the top of the neck.
    static func dancerChinShadow(size: CGFloat) -> CGPath {
        let shadow = CGPath(ellipseIn: box(0.47, 0.41, 0.06, 0.05, size), transform: nil)
        return shadow.subtracting(CGPath(ellipseIn: box(0.33, 0.13, 0.34, 0.31, size), transform: nil))
    }

    /// Soft rosy cheeks under the eyes.
    static func dancerCheeks(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for x in [0.405, 0.595] as [CGFloat] {
            path.addEllipse(in: box(x - 0.03, 0.352, 0.06, 0.03, size))
        }
        return path
    }

    /// The costume over the chest: a fitted bodice with a sweetheart
    /// neckline and a point at the waist, a tunic with shoulder caps that
    /// flares into a short skirt, or a loose blouse off one shoulder whose
    /// hem runs long on one side.
    static func dancerTorso(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.move(to: point(0.47, 0.462))
            path.addLine(to: point(0.53, 0.462))
            path.addCurve(to: point(0.592, 0.478), control1: point(0.556, 0.466), control2: point(0.576, 0.47))
            path.addCurve(to: point(0.614, 0.525), control1: point(0.608, 0.485), control2: point(0.615, 0.50))
            path.addCurve(to: point(0.574, 0.605), control1: point(0.612, 0.56), control2: point(0.584, 0.585))
            path.addCurve(to: point(0.602, 0.70), control1: point(0.585, 0.64), control2: point(0.60, 0.67))
            path.addQuadCurve(to: point(0.398, 0.70), control: point(0.50, 0.722))
            path.addCurve(to: point(0.426, 0.605), control1: point(0.40, 0.67), control2: point(0.415, 0.64))
            path.addCurve(to: point(0.386, 0.525), control1: point(0.416, 0.585), control2: point(0.388, 0.56))
            path.addCurve(to: point(0.408, 0.478), control1: point(0.385, 0.50), control2: point(0.392, 0.485))
            path.addCurve(to: point(0.47, 0.462), control1: point(0.424, 0.47), control2: point(0.444, 0.466))
            path.closeSubpath()
        case .contemporary:
            path.move(to: point(0.452, 0.49))
            path.addQuadCurve(to: point(0.536, 0.47), control: point(0.50, 0.518))
            path.addCurve(to: point(0.604, 0.498), control1: point(0.566, 0.468), control2: point(0.594, 0.478))
            path.addCurve(to: point(0.624, 0.62), control1: point(0.618, 0.54), control2: point(0.628, 0.59))
            path.addCurve(to: point(0.662, 0.735), control1: point(0.634, 0.66), control2: point(0.66, 0.70))
            path.addQuadCurve(to: point(0.585, 0.70), control: point(0.612, 0.712))
            path.addQuadCurve(to: point(0.398, 0.676), control: point(0.49, 0.698))
            path.addCurve(to: point(0.384, 0.56), control1: point(0.388, 0.63), control2: point(0.378, 0.59))
            path.addCurve(to: point(0.452, 0.49), control1: point(0.39, 0.52), control2: point(0.42, 0.496))
            path.closeSubpath()
        default:
            path.move(to: point(0.44, 0.49))
            path.addQuadCurve(to: point(0.47, 0.478), control: point(0.451, 0.476))
            path.addQuadCurve(to: point(0.50, 0.493), control: point(0.49, 0.478))
            path.addQuadCurve(to: point(0.53, 0.478), control: point(0.51, 0.478))
            path.addQuadCurve(to: point(0.56, 0.49), control: point(0.549, 0.476))
            path.addCurve(to: point(0.543, 0.586), control1: point(0.566, 0.53), control2: point(0.546, 0.562))
            path.addLine(to: point(0.50, 0.614))
            path.addLine(to: point(0.457, 0.586))
            path.addCurve(to: point(0.44, 0.49), control1: point(0.454, 0.562), control2: point(0.434, 0.53))
            path.closeSubpath()
        }
        return path
    }

    /// Under the torso: the ballerina's platter tutu, its top tier seen a
    /// little from above with a scalloped edge; the contemporary dancer's
    /// longer inner layer peeking under the blouse. The danseur has none.
    static func dancerSkirt(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        switch style {
        case .ballerina:
            return scallopedPlatter(center: CGPoint(x: 0.5, y: 0.604), radii: CGSize(width: 0.25, height: 0.054), scallops: 11,
                                    depth: 0.011, size: size)
        case .contemporary:
            let path = CGMutablePath()
            path.move(to: point(0.39, 0.63))
            path.addLine(to: point(0.63, 0.65))
            path.addQuadCurve(to: point(0.615, 0.73), control: point(0.64, 0.70))
            path.addQuadCurve(to: point(0.50, 0.712), control: point(0.56, 0.705))
            path.addQuadCurve(to: point(0.39, 0.70), control: point(0.44, 0.725))
            path.addQuadCurve(to: point(0.39, 0.63), control: point(0.375, 0.665))
            path.closeSubpath()
            return path
        default:
            return CGMutablePath()
        }
    }

    /// The tutu's lower tiers, a deeper frill showing under the top one.
    static func dancerUnderskirt(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        guard style == .ballerina else { return CGMutablePath() }
        let path = CGMutablePath()
        path.addPath(scallopedPlatter(center: CGPoint(x: 0.5, y: 0.624), radii: CGSize(width: 0.238, height: 0.05),
                                      scallops: 12, depth: 0.012, size: size))
        return path
    }

    /// The tulle's texture on the tutu's top tier, fine pleats running out
    /// from the waist and a ring where one layer lies on the next; on the
    /// contemporary dancer, the light catching the folds of her blouse.
    static func dancerPleats(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .ballerina:
            let center = CGPoint(x: 0.5, y: 0.604), rx: CGFloat = 0.25, ry: CGFloat = 0.054
            for index in 0..<9 {
                let angle = CGFloat.pi * (0.1 + 0.8 * CGFloat(index) / 8)
                let rim = CGPoint(x: center.x + rx * 0.93 * cos(angle), y: center.y + ry * 0.93 * sin(angle))
                let root = CGPoint(x: center.x + 0.045 * cos(angle), y: center.y + 0.006 + 0.012 * sin(angle))
                let nx = -sin(angle) * 0.0045, ny = cos(angle) * 0.0045
                path.move(to: point(root.x, root.y))
                path.addLine(to: point(rim.x + nx, rim.y + ny))
                path.addLine(to: point(rim.x - nx, rim.y - ny))
                path.closeSubpath()
            }
            let ring = CGMutablePath()
            ring.addEllipse(in: box(0.5 - 0.15, 0.604 - 0.024, 0.30, 0.054, size))
            ring.addEllipse(in: box(0.5 - 0.142, 0.604 - 0.02, 0.284, 0.046, size))
            path.addPath(ring.normalized(using: .evenOdd))
            return path
        case .contemporary:
            for (from, to, bend) in [((0.45, 0.53), (0.43, 0.66), (0.42, 0.60)), ((0.57, 0.52), (0.60, 0.68), (0.60, 0.60))]
                as [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] {
                path.move(to: point(from.0, from.1))
                path.addQuadCurve(to: point(to.0, to.1), control: point(bend.0, bend.1))
                path.addQuadCurve(to: point(from.0 + 0.008, from.1), control: point(bend.0 + 0.014, bend.1))
                path.closeSubpath()
            }
            return path
        default:
            return path
        }
    }

    /// A panel over the torso in a lighter tone: the danseur's plastron, the
    /// contemporary dancer's sheer wrap crossing her from shoulder to hip
    /// and flying loose, swung `sway` of the way out as she moves.
    static func dancerPanel(_ style: NotchMascotStyle, sway: CGFloat = 0, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.move(to: point(0.462, 0.474))
            path.addLine(to: point(0.538, 0.474))
            path.addLine(to: point(0.542, 0.60))
            path.addLine(to: point(0.458, 0.60))
            path.closeSubpath()
        case .contemporary:
            let tip = CGPoint(x: 0.365 - 0.04 * sway, y: 0.725 - 0.03 * sway)
            path.move(to: point(0.548, 0.474))
            path.addCurve(to: point(0.43, 0.632), control1: point(0.54, 0.55), control2: point(0.47, 0.60))
            path.addCurve(to: point(tip.x, tip.y), control1: point(0.40, 0.66), control2: point(0.37 - 0.03 * sway, 0.70))
            path.addCurve(to: point(0.42, 0.672), control1: point(tip.x + 0.045, 0.72 - 0.03 * sway), control2: point(0.40, 0.69))
            path.addCurve(to: point(0.588, 0.494), control1: point(0.50, 0.62), control2: point(0.58, 0.56))
            path.closeSubpath()
        default:
            break
        }
        return path
    }

    /// Darker details: the seams of the bodice and its point, the danseur's
    /// belt, the shadowed side of the blouse.
    static func dancerDetails(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.addRoundedRect(in: box(0.424, 0.594, 0.152, 0.022, size), cornerWidth: 0.006 * size, cornerHeight: 0.006 * size)
        case .contemporary:
            path.move(to: point(0.604, 0.498))
            path.addCurve(to: point(0.624, 0.62), control1: point(0.618, 0.54), control2: point(0.628, 0.59))
            path.addCurve(to: point(0.662, 0.735), control1: point(0.634, 0.66), control2: point(0.66, 0.70))
            path.addQuadCurve(to: point(0.61, 0.66), control: point(0.615, 0.70))
            path.addQuadCurve(to: point(0.604, 0.498), control: point(0.61, 0.57))
            path.closeSubpath()
        default:
            for mirrored in [false, true] {
                func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(mirrored ? 1 - x : x, y) }
                path.move(to: at(0.474, 0.486))
                path.addQuadCurve(to: at(0.484, 0.596), control: at(0.468, 0.55))
                path.addLine(to: at(0.478, 0.594))
                path.addQuadCurve(to: at(0.468, 0.488), control: at(0.462, 0.55))
                path.closeSubpath()
            }
        }
        return path
    }

    /// The metal and lace: the ballerina's tiara and the trim of her
    /// neckline; the danseur's gold collar, frogging, epaulettes, hem band
    /// and buckle; the tie round the contemporary dancer's topknot. Unless
    /// a hat sits on the head, which hides the tiara and the knot.
    static func dancerTrim(_ style: NotchMascotStyle, hat: Bool = false, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.addRoundedRect(in: box(0.462, 0.452, 0.076, 0.022, size), cornerWidth: 0.008 * size, cornerHeight: 0.008 * size)
            for y in [0.502, 0.530, 0.558] as [CGFloat] {
                path.addRoundedRect(in: box(0.452, y, 0.096, 0.008, size), cornerWidth: 0.004 * size, cornerHeight: 0.004 * size)
                path.addEllipse(in: box(0.444, y - 0.003, 0.014, 0.014, size))
                path.addEllipse(in: box(0.542, y - 0.003, 0.014, 0.014, size))
            }
            for x in [0.402, 0.598] as [CGFloat] {
                path.addEllipse(in: box(x - 0.024, 0.476, 0.048, 0.022, size))
            }
            path.move(to: point(0.40, 0.688))
            path.addQuadCurve(to: point(0.60, 0.688), control: point(0.50, 0.71))
            path.addLine(to: point(0.602, 0.70))
            path.addQuadCurve(to: point(0.398, 0.70), control: point(0.50, 0.722))
            path.closeSubpath()
            path.addRoundedRect(in: box(0.484, 0.591, 0.032, 0.028, size), cornerWidth: 0.006 * size, cornerHeight: 0.006 * size)
        case .contemporary:
            if !hat {
                path.addRoundedRect(in: box(0.51, 0.122, 0.054, 0.016, size), cornerWidth: 0.008 * size, cornerHeight: 0.008 * size)
            }
        default:
            if !hat {
                path.move(to: point(0.412, 0.196))
                path.addQuadCurve(to: point(0.588, 0.196), control: point(0.50, 0.168))
                path.addLine(to: point(0.578, 0.18))
                path.addLine(to: point(0.566, 0.168))
                path.addLine(to: point(0.552, 0.17))
                path.addLine(to: point(0.536, 0.146))
                path.addLine(to: point(0.52, 0.16))
                path.addLine(to: point(0.50, 0.124))
                path.addLine(to: point(0.48, 0.16))
                path.addLine(to: point(0.464, 0.146))
                path.addLine(to: point(0.448, 0.17))
                path.addLine(to: point(0.434, 0.168))
                path.addLine(to: point(0.422, 0.18))
                path.closeSubpath()
            }
            path.move(to: point(0.44, 0.49))
            path.addQuadCurve(to: point(0.47, 0.478), control: point(0.451, 0.476))
            path.addQuadCurve(to: point(0.50, 0.493), control: point(0.49, 0.478))
            path.addQuadCurve(to: point(0.53, 0.478), control: point(0.51, 0.478))
            path.addQuadCurve(to: point(0.56, 0.49), control: point(0.549, 0.476))
            path.addLine(to: point(0.561, 0.498))
            path.addQuadCurve(to: point(0.53, 0.487), control: point(0.549, 0.484))
            path.addQuadCurve(to: point(0.50, 0.502), control: point(0.51, 0.487))
            path.addQuadCurve(to: point(0.47, 0.487), control: point(0.49, 0.487))
            path.addQuadCurve(to: point(0.439, 0.498), control: point(0.451, 0.484))
            path.closeSubpath()
        }
        return path
    }

    /// A jewel: in the tiara and at the bodice's neckline.
    static func dancerGems(_ style: NotchMascotStyle, hat: Bool = false, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style == .ballerina else { return path }
        if !hat { path.addEllipse(in: box(0.489, 0.157, 0.022, 0.022, size)) }
        path.addEllipse(in: box(0.491, 0.486, 0.018, 0.018, size))
        return path
    }

    // MARK: Hair

    /// The hair behind the head: the ballerina's bun on her crown, the
    /// danseur's thick crop, and the contemporary dancer's loose hair to her
    /// shoulders under a messy topknot. A hat hides the bun and the knot.
    static func dancerHairBack(_ style: NotchMascotStyle, hat: Bool = false, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.addEllipse(in: box(0.318, 0.112, 0.364, 0.27, size))
        case .contemporary:
            path.move(to: point(0.5, 0.112))
            path.addCurve(to: point(0.692, 0.30), control1: point(0.62, 0.112), control2: point(0.70, 0.19))
            path.addCurve(to: point(0.684, 0.476), control1: point(0.688, 0.38), control2: point(0.70, 0.44))
            path.addQuadCurve(to: point(0.648, 0.452), control: point(0.668, 0.482))
            path.addQuadCurve(to: point(0.616, 0.49), control: point(0.636, 0.466))
            path.addLine(to: point(0.384, 0.49))
            path.addQuadCurve(to: point(0.352, 0.458), control: point(0.364, 0.468))
            path.addQuadCurve(to: point(0.318, 0.47), control: point(0.334, 0.48))
            path.addCurve(to: point(0.308, 0.30), control1: point(0.30, 0.42), control2: point(0.302, 0.36))
            path.addCurve(to: point(0.5, 0.112), control1: point(0.31, 0.19), control2: point(0.38, 0.112))
            path.closeSubpath()
            if !hat {
                path.addPath(CGPath(ellipseIn: box(-0.058, -0.046, 0.116, 0.092, size),
                                    transform: [CGAffineTransform(rotationAngle: 0.35)
                                        .concatenating(CGAffineTransform(translationX: 0.54 * size, y: 0.095 * size))]))
                path.move(to: point(0.58, 0.07))
                path.addQuadCurve(to: point(0.64, 0.06), control: point(0.61, 0.045))
                path.addQuadCurve(to: point(0.59, 0.085), control: point(0.61, 0.065))
                path.closeSubpath()
            }
        default:
            path.addEllipse(in: box(0.322, 0.122, 0.356, 0.25, size))
            if !hat { path.addEllipse(in: box(0.438, 0.04, 0.124, 0.112, size)) }
        }
        return path
    }

    /// The hair over the forehead and down the temples: the ballerina's
    /// sleek centre parting, the danseur's swept quiff, the contemporary
    /// dancer's long side-swept fringe and the locks down her cheeks.
    static func dancerHair(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .danseur:
            path.move(to: point(0.334, 0.35))
            path.addCurve(to: point(0.37, 0.15), control1: point(0.314, 0.27), control2: point(0.33, 0.19))
            path.addCurve(to: point(0.56, 0.088), control1: point(0.41, 0.10), control2: point(0.49, 0.072))
            path.addCurve(to: point(0.676, 0.27), control1: point(0.65, 0.11), control2: point(0.69, 0.19))
            path.addCurve(to: point(0.664, 0.345), control1: point(0.672, 0.30), control2: point(0.668, 0.325))
            path.addCurve(to: point(0.636, 0.245), control1: point(0.648, 0.30), control2: point(0.646, 0.265))
            path.addCurve(to: point(0.45, 0.226), control1: point(0.59, 0.208), control2: point(0.52, 0.248))
            path.addCurve(to: point(0.38, 0.27), control1: point(0.41, 0.214), control2: point(0.385, 0.234))
            path.addCurve(to: point(0.352, 0.35), control1: point(0.362, 0.29), control2: point(0.356, 0.32))
            path.closeSubpath()
        case .contemporary:
            path.move(to: point(0.318, 0.40))
            path.addCurve(to: point(0.42, 0.13), control1: point(0.30, 0.24), control2: point(0.34, 0.15))
            path.addCurve(to: point(0.684, 0.36), control1: point(0.60, 0.11), control2: point(0.702, 0.22))
            path.addCurve(to: point(0.666, 0.46), control1: point(0.682, 0.40), control2: point(0.676, 0.43))
            path.addCurve(to: point(0.642, 0.30), control1: point(0.648, 0.40), control2: point(0.638, 0.34))
            path.addCurve(to: point(0.60, 0.238), control1: point(0.642, 0.264), control2: point(0.625, 0.243))
            path.addQuadCurve(to: point(0.552, 0.256), control: point(0.575, 0.258))
            path.addQuadCurve(to: point(0.50, 0.214), control: point(0.522, 0.236))
            path.addQuadCurve(to: point(0.44, 0.206), control: point(0.47, 0.198))
            path.addCurve(to: point(0.362, 0.28), control1: point(0.40, 0.216), control2: point(0.372, 0.24))
            path.addCurve(to: point(0.346, 0.42), control1: point(0.352, 0.33), control2: point(0.36, 0.38))
            path.closeSubpath()
        default:
            path.move(to: point(0.332, 0.35))
            path.addCurve(to: point(0.5, 0.114), control1: point(0.302, 0.20), control2: point(0.385, 0.114))
            path.addCurve(to: point(0.668, 0.35), control1: point(0.615, 0.114), control2: point(0.698, 0.20))
            path.addCurve(to: point(0.632, 0.25), control1: point(0.654, 0.30), control2: point(0.648, 0.27))
            path.addQuadCurve(to: point(0.50, 0.214), control: point(0.57, 0.198))
            path.addQuadCurve(to: point(0.368, 0.25), control: point(0.43, 0.198))
            path.addCurve(to: point(0.337, 0.35), control1: point(0.352, 0.27), control2: point(0.346, 0.30))
            path.closeSubpath()
        }
        return path
    }

    /// Where the hair shines: a band round the crown, and the bun's coil or
    /// the quiff's sweep.
    static func dancerHairShine(_ style: NotchMascotStyle, hat: Bool = false, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        func crescent(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), _ bulge: (CGFloat, CGFloat), thickness: CGFloat) {
            path.move(to: point(from.0, from.1))
            path.addQuadCurve(to: point(to.0, to.1), control: point(bulge.0, bulge.1))
            path.addQuadCurve(to: point(from.0, from.1), control: point(bulge.0, bulge.1 + thickness))
            path.closeSubpath()
        }
        switch style {
        case .danseur:
            crescent((0.40, 0.155), (0.60, 0.115), (0.48, 0.09), thickness: 0.035)
        case .contemporary:
            crescent((0.38, 0.17), (0.60, 0.15), (0.48, 0.11), thickness: 0.032)
        default:
            crescent((0.39, 0.16), (0.61, 0.16), (0.50, 0.12), thickness: 0.026)
            if !hat { crescent((0.465, 0.07), (0.535, 0.07), (0.50, 0.05), thickness: 0.018) }
        }
        return path
    }

    // MARK: Limbs

    /// The arms in `pose`, skin to the fingertips, in the same commands
    /// whatever the pose.
    static func dancerArms(_ style: NotchMascotStyle, _ pose: DancerPose, size: CGFloat) -> CGPath {
        let joints = dancerJoints(style, pose)
        let (width, hand): (CGFloat, CGFloat) = style == .danseur ? (0.04, 0.022) : (0.033, 0.02)
        let path = CGMutablePath()
        for arm in [joints.leftArm, joints.rightArm] {
            segment(into: path, from: arm[0], to: arm[1], widths: (width, width * 0.9), size: size)
            segment(into: path, from: arm[1], to: arm[2], widths: (width * 0.9, width * 0.78), size: size)
            disc(into: path, at: arm[2], radius: hand, size: size)
        }
        return path
    }

    /// Sleeves over the arms: the danseur's to the wrist, the contemporary
    /// dancer's wide and loose to below the elbow; none on the ballerina.
    static func dancerSleeves(_ style: NotchMascotStyle, _ pose: DancerPose, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style != .ballerina else { return path }
        let joints = dancerJoints(style, pose)
        for arm in [joints.leftArm, joints.rightArm] {
            if style == .danseur {
                let wrist = along(arm[2], from: arm[1], by: -0.022)
                segment(into: path, from: arm[0], to: arm[1], widths: (0.052, 0.048), size: size)
                segment(into: path, from: arm[1], to: wrist, widths: (0.048, 0.046), size: size)
            } else {
                let cuff = CGPoint(x: arm[1].x + (arm[2].x - arm[1].x) * 0.45, y: arm[1].y + (arm[2].y - arm[1].y) * 0.45)
                segment(into: path, from: arm[0], to: arm[1], widths: (0.05, 0.052), size: size)
                segment(into: path, from: arm[1], to: cuff, widths: (0.052, 0.064), size: size)
            }
        }
        return path
    }

    /// The danseur's gold cuffs at his wrists.
    static func dancerCuffs(_ style: NotchMascotStyle, _ pose: DancerPose, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard style == .danseur else { return path }
        let joints = dancerJoints(style, pose)
        for arm in [joints.leftArm, joints.rightArm] {
            let wrist = along(arm[2], from: arm[1], by: -0.022)
            segment(into: path, from: along(wrist, from: arm[1], by: -0.016), to: wrist, widths: (0.054, 0.054), size: size)
        }
        return path
    }

    /// The legs in `pose`: pink tights, white tights or wide soft trousers;
    /// only the one on the left or the right of the screen when `left` says.
    static func dancerLegs(_ style: NotchMascotStyle, _ pose: DancerPose, left: Bool? = nil, size: CGFloat) -> CGPath {
        let joints = dancerJoints(style, pose)
        let widths: (hip: CGFloat, knee: CGFloat, ankle: CGFloat)
        switch style {
        case .danseur: widths = (0.058, 0.046, 0.036)
        case .contemporary: widths = (0.076, 0.07, 0.088)
        default: widths = (0.05, 0.04, 0.03)
        }
        let path = CGMutablePath()
        let legs = left.map { $0 ? [joints.leftLeg] : [joints.rightLeg] } ?? [joints.leftLeg, joints.rightLeg]
        for leg in legs {
            segment(into: path, from: leg[0], to: leg[1], widths: (widths.hip, widths.knee), size: size)
            segment(into: path, from: leg[1], to: leg[2], widths: (widths.knee, widths.ankle), size: size)
        }
        return path
    }

    /// The feet in `pose`: satin pointe shoes that carry on the line of the
    /// leg, soft slippers, or bare feet.
    static func dancerFeet(_ style: NotchMascotStyle, _ pose: DancerPose, size: CGFloat) -> CGPath {
        let joints = dancerJoints(style, pose)
        let path = CGMutablePath()
        for leg in [joints.leftLeg, joints.rightLeg] {
            switch style {
            case .ballerina: shoe(into: path, ankle: leg[2], toe: leg[3], heel: 0.024, width: 0.034, tip: 0.4, size: size)
            case .danseur: shoe(into: path, ankle: leg[2], toe: leg[3], heel: 0.016, width: 0.04, tip: 0.5, size: size)
            default: shoe(into: path, ankle: leg[2], toe: leg[3], heel: 0.016, width: 0.038, tip: 0.75, size: size)
            }
        }
        return path
    }

    /// The pointe shoes' satin ribbons criss-crossed up the ankle, or the
    /// elastic over the danseur's instep; the contemporary dancer goes bare.
    static func dancerLaces(_ style: NotchMascotStyle, _ pose: DancerPose, size: CGFloat) -> CGPath {
        let joints = dancerJoints(style, pose)
        let path = CGMutablePath()
        guard style != .contemporary else { return path }
        for leg in [joints.leftLeg, joints.rightLeg] {
            let ankle = leg[2]
            if style == .ballerina {
                let (sx, sy) = unit(from: leg[1], to: ankle)
                let (nx, ny) = (-sy * 0.017, sx * 0.017)
                for flip in [1, -1] as [CGFloat] {
                    let low = CGPoint(x: ankle.x - sx * 0.008 + nx * flip, y: ankle.y - sy * 0.008 + ny * flip)
                    let high = CGPoint(x: ankle.x - sx * 0.05 - nx * flip, y: ankle.y - sy * 0.05 - ny * flip)
                    band(into: path, from: low, to: high, thickness: 0.009, size: size)
                }
            } else {
                let (fx, fy) = unit(from: ankle, to: leg[3])
                let (nx, ny) = (-fy * 0.021, fx * 0.021)
                let at = CGPoint(x: ankle.x + fx * 0.01, y: ankle.y + fy * 0.01)
                band(into: path, from: CGPoint(x: at.x + nx, y: at.y + ny), to: CGPoint(x: at.x - nx, y: at.y - ny),
                     thickness: 0.008, size: size)
            }
        }
        return path
    }

    /// The chiffon veil the contemporary dancer wears from her right arm to
    /// her hip, hanging from the arm in `pose` like a wing of fabric with a
    /// rippling hem, swung `sway` of the way out as she moves.
    static func dancerVeil(_ style: NotchMascotStyle, _ pose: DancerPose, sway: CGFloat = 0, size: CGFloat) -> CGPath {
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size, y: p.y * size) }
        let path = CGMutablePath()
        guard style == .contemporary else { return path }
        let arm = dancerJoints(style, pose).rightArm
        let (shoulder, elbow, hand) = (arm[0], arm[1], arm[2])
        let hip = CGPoint(x: 0.60, y: 0.62)
        let corner = CGPoint(x: max(hand.x, 0.62) + 0.03 + 0.04 * sway, y: max(hand.y + 0.17, 0.66) - 0.05 * sway)
        let dip = CGPoint(x: (corner.x + hip.x) / 2, y: (corner.y + hip.y) / 2 + 0.03 - 0.01 * sway)
        path.move(to: point(shoulder))
        path.addLine(to: point(elbow))
        path.addLine(to: point(hand))
        path.addQuadCurve(to: point(corner), control: point(CGPoint(x: hand.x + 0.06 + 0.03 * sway, y: (hand.y + corner.y) / 2)))
        path.addQuadCurve(to: point(dip), control: point(CGPoint(x: corner.x - 0.015, y: corner.y + 0.035)))
        path.addQuadCurve(to: point(hip), control: point(CGPoint(x: dip.x - 0.03, y: dip.y - 0.035)))
        path.closeSubpath()
        return path
    }
    // MARK: Helpers

    /// A tutu tier: the top half of an ellipse, and the bottom half in
    /// scallops that bulge a little past it.
    private static func scallopedPlatter(center: CGPoint, radii: CGSize, scallops: Int, depth: CGFloat,
                                         size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        func rim(_ angle: CGFloat, _ grow: CGFloat = 0) -> CGPoint {
            point(center.x + (radii.width + grow) * cos(angle), center.y + (radii.height + grow * 0.7) * sin(angle))
        }
        let path = CGMutablePath()
        let k: CGFloat = 0.5523
        let (cx, cy, rx, ry) = (center.x, center.y, radii.width, radii.height)
        path.move(to: point(cx - rx, cy))
        path.addCurve(to: point(cx, cy - ry), control1: point(cx - rx, cy - ry * k), control2: point(cx - rx * k, cy - ry))
        path.addCurve(to: point(cx + rx, cy), control1: point(cx + rx * k, cy - ry), control2: point(cx + rx, cy - ry * k))
        for index in 0..<scallops {
            let from = CGFloat(index) / CGFloat(scallops) * .pi, to = CGFloat(index + 1) / CGFloat(scallops) * .pi
            path.addQuadCurve(to: rim(to), control: rim((from + to) / 2, depth * 2.2))
        }
        path.closeSubpath()
        return path
    }

    /// A tapered rounded segment from one joint to the next, always the
    /// same commands.
    private static func segment(into path: CGMutablePath, from: CGPoint, to: CGPoint, widths: (CGFloat, CGFloat),
                                size: CGFloat) {
        let (ux, uy) = unit(from: from, to: to)
        let (a, b) = (widths.0 / 2, widths.1 / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        path.move(to: point(from.x - uy * a, from.y + ux * a))
        path.addLine(to: point(to.x - uy * b, to.y + ux * b))
        path.addQuadCurve(to: point(to.x + uy * b, to.y - ux * b), control: point(to.x + ux * b * 1.4, to.y + uy * b * 1.4))
        path.addLine(to: point(from.x + uy * a, from.y - ux * a))
        path.addQuadCurve(to: point(from.x - uy * a, from.y + ux * a),
                          control: point(from.x - ux * a * 1.4, from.y - uy * a * 1.4))
        path.closeSubpath()
    }

    /// A round hand, turning the same way as the segments so where they
    /// overlap it fills rather than cancels out.
    private static func disc(into path: CGMutablePath, at center: CGPoint, radius: CGFloat, size: CGFloat) {
        let middle = CGPoint(x: center.x * size, y: center.y * size)
        path.move(to: CGPoint(x: middle.x + radius * size, y: middle.y))
        path.addArc(center: middle, radius: radius * size, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        path.closeSubpath()
    }

    /// A shoe or a foot from just above the ankle out to the toe, rounded at
    /// the heel and narrowing to the toe's tip.
    private static func shoe(into path: CGMutablePath, ankle: CGPoint, toe: CGPoint, heel: CGFloat, width: CGFloat,
                             tip: CGFloat, size: CGFloat) {
        let (fx, fy) = unit(from: ankle, to: toe)
        let (nx, ny) = (-fy, fx)
        let back = CGPoint(x: ankle.x - fx * heel, y: ankle.y - fy * heel)
        let (w, t) = (width / 2, width * tip / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        path.move(to: point(back.x + nx * w, back.y + ny * w))
        path.addLine(to: point(toe.x + nx * t, toe.y + ny * t))
        path.addQuadCurve(to: point(toe.x - nx * t, toe.y - ny * t), control: point(toe.x + fx * t * 1.6, toe.y + fy * t * 1.6))
        path.addLine(to: point(back.x - nx * w, back.y - ny * w))
        path.addQuadCurve(to: point(back.x + nx * w, back.y + ny * w), control: point(back.x - fx * w * 1.2, back.y - fy * w * 1.2))
        path.closeSubpath()
    }

    /// A thin straight band, for a ribbon or an elastic.
    private static func band(into path: CGMutablePath, from: CGPoint, to: CGPoint, thickness: CGFloat, size: CGFloat) {
        let (ux, uy) = unit(from: from, to: to)
        let (nx, ny) = (-uy * thickness / 2, ux * thickness / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        path.move(to: point(from.x + nx, from.y + ny))
        path.addLine(to: point(to.x + nx, to.y + ny))
        path.addLine(to: point(to.x - nx, to.y - ny))
        path.addLine(to: point(from.x - nx, from.y - ny))
        path.closeSubpath()
    }

    private static func unit(from: CGPoint, to: CGPoint) -> (CGFloat, CGFloat) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return (dx / length, dy / length)
    }

    /// `point` moved `distance` further along the line from `from`.
    private static func along(_ point: CGPoint, from: CGPoint, by distance: CGFloat) -> CGPoint {
        let (ux, uy) = unit(from: from, to: point)
        return CGPoint(x: point.x + ux * distance, y: point.y + uy * distance)
    }
}

/// The colours of the dancers. Skin, hair, tights and shoes are each
/// dancer's own; the costume is dyed from the body's light and shade, a
/// deeper and a lighter tone of it beside, so it belongs to every palette
/// and any hand-picked colour. A colour too grey to have a hue dresses them
/// in white and silver, as on a stage.
struct NotchMascotDancerColors: Equatable {
    var skin: NotchMascotColor
    var skinShade: NotchMascotColor
    var cheeks: NotchMascotColor
    var hair: NotchMascotColor
    var hairShine: NotchMascotColor
    var costume: NotchMascotColor
    var costumeLight: NotchMascotColor
    var costumeDeep: NotchMascotColor
    var trim: NotchMascotColor
    var gem: NotchMascotColor
    var legs: NotchMascotColor
    var farLeg: NotchMascotColor
    var feet: NotchMascotColor
    var laces: NotchMascotColor

    init(style: NotchMascotStyle, light: NotchMascotColor, shade: NotchMascotColor) {
        func rgb(_ hex: UInt32) -> NotchMascotColor {
            NotchMascotColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                             blue: CGFloat(hex & 0xFF) / 255)
        }
        let (hue, saturation, brightness) = shade.hsb
        let grey = saturation < 0.12
        // Deep yellows go olive, so a yellow costume deepens toward gold.
        let golden = grey ? 0 : max(0, 1 - abs(hue - 0.14) / 0.08)
        costume = grey ? .hsb(0.64, 0.04, brightness > 0.5 ? 0.97 : brightness)
            : .hsb(hue, min(1, saturation * 0.9 + 0.12), brightness)
        let dark = costume.hsb.2 < 0.4
        costumeLight = grey && !dark ? .hsb(0.62, 0.02, 1) : costume.brightened(dark ? 0.22 : 0.5)
        costumeDeep = grey ? .hsb(0.64, 0.12, dark ? costume.hsb.2 * 0.7 : 0.76)
            : .hsb(hue - 0.035 * golden, min(1, saturation + 0.14), costume.hsb.2 * (0.74 + 0.08 * golden))
        cheeks = rgb(0xFF8FA3)
        gem = grey ? .hsb(0.92, 0.45, 0.98) : .hsb(hue, min(1, saturation + 0.35), 0.96)
        switch style {
        case .danseur:
            skin = rgb(0xF0C29F); skinShade = rgb(0xD9A07D)
            hair = rgb(0xDCA94F); hairShine = rgb(0xF7DA94)
            trim = rgb(0xF2C14E)
            legs = rgb(0xF4F1F7); farLeg = rgb(0xDAD5E2)
            feet = rgb(0xD6C7B8); laces = rgb(0xB9A792)
        case .contemporary:
            skin = rgb(0xC08462); skinShade = rgb(0x9E6446)
            hair = rgb(0x2D2434); hairShine = rgb(0x625070)
            trim = costumeDeep
            legs = costumeDeep; farLeg = costumeDeep.darkened(0.14)
            feet = skin; laces = skin
        default:
            skin = rgb(0xFFE3D5); skinShade = rgb(0xF1C1B0)
            hair = rgb(0x6E3A2B); hairShine = rgb(0xA3664B)
            trim = rgb(0xF5F3FB)
            legs = rgb(0xF8D2DB); farLeg = rgb(0xEBB8C6)
            feet = rgb(0xF2A6BC); laces = rgb(0xFBD3DE)
        }
    }

    init(_ look: NotchMascotLook) {
        let palette = look.bodyPalette
        self.init(style: look.style, light: palette.light, shade: palette.shade)
    }
}
