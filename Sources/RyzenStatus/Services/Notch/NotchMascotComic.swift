// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The comic's two characters, drawn like every other figure so they wear
/// items and take a colour: the palette dyes Cristóbal's jumper and the
/// White Rabbit's apron, while skin, hair and fur keep their own. Paths are
/// in a square of `size` points from its top left corner, y growing
/// downward, and every pose of the arms is built with the same commands.
extension NotchMascotCreatures {
    /// The ink the comic draws its outlines in.
    static let comicInk: UInt32 = 0x23222B

    // MARK: Cristóbal

    /// His jumper, which the palette dyes: round shoulders, a body that
    /// narrows a little to a ribbed hem.
    static func cristobalJumper(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.40, 0.465))
        path.addLine(to: point(0.60, 0.465))
        path.addQuadCurve(to: point(0.69, 0.53), control: point(0.68, 0.47))
        path.addLine(to: point(0.675, 0.735))
        path.addQuadCurve(to: point(0.645, 0.755), control: point(0.675, 0.755))
        path.addLine(to: point(0.355, 0.755))
        path.addQuadCurve(to: point(0.325, 0.735), control: point(0.325, 0.755))
        path.addLine(to: point(0.31, 0.53))
        path.addQuadCurve(to: point(0.40, 0.465), control: point(0.32, 0.47))
        path.closeSubpath()
        return path
    }

    /// His neck, unlined, behind his head and jumper.
    static func cristobalNeck(size: CGFloat) -> CGPath {
        CGPath(rect: box(0.462, 0.43, 0.076, 0.06, size), transform: nil)
    }

    /// Head and ears.
    static func cristobalSkin(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.31, 0.255, 0.05, 0.085, size))
        path.addEllipse(in: box(0.64, 0.255, 0.05, 0.085, size))
        path.addRoundedRect(in: box(0.335, 0.13, 0.33, 0.33, size), cornerWidth: 0.13 * size, cornerHeight: 0.15 * size)
        return path
    }

    /// Thick black hair, messy on top, with short sideburns and a curl
    /// over his brow: one outline, so it fills as one.
    static func cristobalHair(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.33, 0.30))
        path.addLine(to: point(0.322, 0.21))
        path.addCurve(to: point(0.42, 0.085), control1: point(0.315, 0.13), control2: point(0.36, 0.09))
        for (x, y) in [(0.44, 0.045), (0.475, 0.08), (0.51, 0.035), (0.54, 0.075), (0.585, 0.05), (0.595, 0.095)] {
            path.addLine(to: point(x, y))
        }
        path.addCurve(to: point(0.678, 0.21), control1: point(0.65, 0.11), control2: point(0.685, 0.15))
        for (x, y) in [(0.67, 0.30), (0.648, 0.30), (0.642, 0.23), (0.60, 0.205), (0.575, 0.225), (0.53, 0.195),
                       (0.495, 0.215)] {
            path.addLine(to: point(x, y))
        }
        // The curl, hanging from the fringe.
        path.addQuadCurve(to: point(0.445, 0.25), control: point(0.45, 0.215))
        path.addQuadCurve(to: point(0.455, 0.205), control: point(0.44, 0.225))
        for (x, y) in [(0.41, 0.225), (0.375, 0.205), (0.358, 0.23), (0.352, 0.30)] {
            path.addLine(to: point(x, y))
        }
        path.closeSubpath()
        return path
    }

    /// The day's stubble along his jaw.
    static func cristobalStubble(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.345, 0.33))
        path.addCurve(to: point(0.50, 0.46), control1: point(0.345, 0.42), control2: point(0.40, 0.46))
        path.addCurve(to: point(0.655, 0.33), control1: point(0.60, 0.46), control2: point(0.655, 0.42))
        path.addCurve(to: point(0.50, 0.425), control1: point(0.625, 0.39), control2: point(0.58, 0.425))
        path.addCurve(to: point(0.345, 0.33), control1: point(0.42, 0.425), control2: point(0.375, 0.39))
        path.closeSubpath()
        return path
    }

    /// A small, easy smile.
    static func cristobalSmile(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.465, 0.392))
        path.addQuadCurve(to: point(0.55, 0.388), control: point(0.51, 0.418))
        path.addQuadCurve(to: point(0.465, 0.392), control: point(0.51, 0.404))
        path.closeSubpath()
        return path
    }

    /// His glasses: two square frames and the bridge, to be stroked.
    static func cristobalGlasses(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.372, 0.262, 0.112, 0.078, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        path.addRoundedRect(in: box(0.516, 0.262, 0.112, 0.078, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        path.move(to: CGPoint(x: 0.484 * size, y: 0.29 * size))
        path.addLine(to: CGPoint(x: 0.516 * size, y: 0.29 * size))
        path.move(to: CGPoint(x: 0.372 * size, y: 0.285 * size))
        path.addLine(to: CGPoint(x: 0.338 * size, y: 0.275 * size))
        path.move(to: CGPoint(x: 0.628 * size, y: 0.285 * size))
        path.addLine(to: CGPoint(x: 0.662 * size, y: 0.275 * size))
        return path
    }

    /// Dark trousers and shoes.
    static func cristobalTrousers(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.365, 0.70, 0.125, 0.20, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        path.addRoundedRect(in: box(0.51, 0.70, 0.125, 0.20, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        return path
    }

    static func cristobalShoes(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.345, 0.885, 0.15, 0.05, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        path.addRoundedRect(in: box(0.505, 0.885, 0.15, 0.05, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        return path
    }

    /// The mug he never puts down, held at his middle.
    static func cristobalMug(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.435, 0.545, 0.105, 0.115, size), cornerWidth: 0.015 * size, cornerHeight: 0.015 * size)
        // The handle, round on the side his hand is.
        path.addEllipse(in: box(0.405, 0.565, 0.05, 0.07, size))
        return path
    }

    /// Where his hands are: one round the mug, the other as `pose` has it.
    private static func cristobalJoints(_ pose: ArmsPose) -> (mug: [CGPoint], free: [CGPoint]) {
        let mug = [CGPoint(x: 0.335, y: 0.505), CGPoint(x: 0.30, y: 0.62), CGPoint(x: 0.425, y: 0.60)]
        let shoulder = CGPoint(x: 0.665, y: 0.505)
        let (elbow, hand): (CGPoint, CGPoint)
        switch pose {
        case .rest: (elbow, hand) = (CGPoint(x: 0.705, y: 0.62), CGPoint(x: 0.70, y: 0.73))
        case .wave: (elbow, hand) = (CGPoint(x: 0.775, y: 0.44), CGPoint(x: 0.785, y: 0.31))
        case .waveOut: (elbow, hand) = (CGPoint(x: 0.78, y: 0.44), CGPoint(x: 0.855, y: 0.33))
        case .up: (elbow, hand) = (CGPoint(x: 0.76, y: 0.40), CGPoint(x: 0.75, y: 0.26))
        case .folded: (elbow, hand) = (CGPoint(x: 0.70, y: 0.625), CGPoint(x: 0.56, y: 0.62))
        }
        return (mug, [shoulder, elbow, hand])
    }

    /// His sleeves, dyed with the jumper.
    static func cristobalSleeves(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let joints = cristobalJoints(pose)
        let path = CGMutablePath()
        limb(into: path, joints.mug, width: 0.08, hand: 0.001, size: size)
        limb(into: path, joints.free, width: 0.08, hand: 0.001, size: size)
        return path
    }

    static func cristobalHands(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let joints = cristobalJoints(pose)
        let path = CGMutablePath()
        for hand in [joints.mug.last, joints.free.last].compactMap({ $0 }) {
            path.addEllipse(in: box(hand.x - 0.034, hand.y - 0.034, 0.068, 0.068, size))
        }
        return path
    }

    // MARK: The White Rabbit

    /// Its apron, which the palette dyes: a bib with straps and a full skirt.
    static func rabbitApron(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.41, 0.53))
        path.addLine(to: point(0.59, 0.53))
        path.addLine(to: point(0.60, 0.63))
        path.addLine(to: point(0.665, 0.635))
        path.addQuadCurve(to: point(0.68, 0.80), control: point(0.69, 0.72))
        path.addQuadCurve(to: point(0.32, 0.80), control: point(0.50, 0.83))
        path.addQuadCurve(to: point(0.335, 0.635), control: point(0.31, 0.72))
        path.addLine(to: point(0.40, 0.63))
        path.closeSubpath()
        path.addRect(box(0.415, 0.47, 0.025, 0.07, size))
        path.addRect(box(0.56, 0.47, 0.025, 0.07, size))
        return path
    }

    /// The apron's pocket.
    static func rabbitPocket(size: CGFloat) -> CGPath {
        CGPath(roundedRect: box(0.445, 0.665, 0.11, 0.065, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size,
               transform: nil)
    }

    /// Its body and feet under the apron.
    static func rabbitBody(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.35, 0.46, 0.30, 0.36, size))
        path.addRoundedRect(in: box(0.375, 0.79, 0.11, 0.12, size), cornerWidth: 0.045 * size, cornerHeight: 0.045 * size)
        path.addRoundedRect(in: box(0.515, 0.79, 0.11, 0.12, size), cornerWidth: 0.045 * size, cornerHeight: 0.045 * size)
        return path
    }

    /// Its round head.
    static func rabbitHead(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: box(0.335, 0.215, 0.33, 0.29, size), transform: nil)
    }

    /// Two tall ears, a little apart; `inner` for their pink insides.
    static func rabbitEars(inner: Bool, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (x, lean) in [(0.405 as CGFloat, -0.12 as CGFloat), (0.595, 0.12)] {
            let width: CGFloat = inner ? 0.045 : 0.095, height: CGFloat = inner ? 0.17 : 0.24
            let top: CGFloat = inner ? 0.03 : 0.0
            let rect = box(x - width / 2, top, width, height, size)
            let pivot = CGPoint(x: x * size, y: 0.22 * size)
            let turn = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: lean)
                .translatedBy(x: -pivot.x, y: -pivot.y)
            path.addEllipse(in: rect.offsetBy(dx: 0, dy: 0.02 * size), transform: turn)
        }
        return path
    }

    /// A pink nose.
    static func rabbitNose(size: CGFloat) -> CGPath {
        polygonPath([(0.48, 0.405), (0.52, 0.405), (0.50, 0.428)], size: size)
    }

    /// Its little mouth under the nose, to be stroked.
    static func rabbitMouth(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.428))
        path.addLine(to: point(0.50, 0.44))
        path.move(to: point(0.465, 0.438))
        path.addQuadCurve(to: point(0.50, 0.44), control: point(0.48, 0.458))
        path.addQuadCurve(to: point(0.535, 0.438), control: point(0.52, 0.458))
        return path
    }

    /// Its arms, furred white: both down at rest, either up as `pose` has it.
    static func rabbitArms(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let left = CGPoint(x: 0.375, y: 0.53), right = CGPoint(x: 0.625, y: 0.53)
        let (leftElbow, leftHand, rightElbow, rightHand): (CGPoint, CGPoint, CGPoint, CGPoint)
        switch pose {
        case .rest: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.32, y: 0.62), .init(x: 0.33, y: 0.71),
                                                                    .init(x: 0.68, y: 0.62), .init(x: 0.67, y: 0.71))
        case .wave: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.32, y: 0.62), .init(x: 0.33, y: 0.71),
                                                                    .init(x: 0.73, y: 0.46), .init(x: 0.75, y: 0.34))
        case .waveOut: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.32, y: 0.62), .init(x: 0.33, y: 0.71),
                                                                       .init(x: 0.74, y: 0.46), .init(x: 0.82, y: 0.36))
        case .up: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.28, y: 0.43), .init(x: 0.27, y: 0.31),
                                                                  .init(x: 0.72, y: 0.43), .init(x: 0.73, y: 0.31))
        case .folded: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.33, y: 0.63), .init(x: 0.46, y: 0.64),
                                                                      .init(x: 0.67, y: 0.63), .init(x: 0.54, y: 0.64))
        }
        let path = CGMutablePath()
        limb(into: path, [left, leftElbow, leftHand], width: 0.07, hand: 0.038, size: size)
        limb(into: path, [right, rightElbow, rightHand], width: 0.07, hand: 0.038, size: size)
        return path
    }
}
