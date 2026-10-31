// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The hologram and the android, drawn like every other figure: vector
/// paths in a square of `size` points from its top left corner, y growing
/// downward. The palette fills the body; hair, visor, trim, gauge and glow
/// are layers of their own over it.
extension NotchMascotCreatures {
    /// How the two hold their arms: one hand on the hip and the other down,
    /// waving one way or the other, both thrown up, or folded asleep. Every
    /// pose is built with the same commands, so one morphs into the next.
    enum ArmsPose: CaseIterable { case rest, wave, waveOut, up, folded }

    // MARK: Hologram

    /// Head, neck, a hoodie that flares a little at the hem and two legs.
    static func hologramBody(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: box(0.335, 0.12, 0.33, 0.32, size))
        path.addRect(box(0.465, 0.41, 0.07, 0.06, size))
        path.move(to: point(0.37, 0.45))
        path.addLine(to: point(0.63, 0.45))
        path.addQuadCurve(to: point(0.69, 0.51), control: point(0.69, 0.45))
        path.addLine(to: point(0.70, 0.71))
        path.addLine(to: point(0.30, 0.71))
        path.addLine(to: point(0.31, 0.51))
        path.addQuadCurve(to: point(0.37, 0.45), control: point(0.31, 0.45))
        path.closeSubpath()
        path.addRoundedRect(in: box(0.385, 0.69, 0.09, 0.21, size), cornerWidth: 0.035 * size, cornerHeight: 0.035 * size)
        path.addRoundedRect(in: box(0.525, 0.69, 0.09, 0.21, size), cornerWidth: 0.035 * size, cornerHeight: 0.035 * size)
        return path
    }

    /// A spiky pixie crop with jagged bangs, one long lock down the left
    /// side of her face and a short one on the right.
    static func hologramHair(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.325, 0.29))
        path.addCurve(to: point(0.50, 0.105), control1: point(0.315, 0.16), control2: point(0.40, 0.105))
        path.addCurve(to: point(0.675, 0.29), control1: point(0.60, 0.105), control2: point(0.685, 0.16))
        path.addLines(between: [point(0.675, 0.29), point(0.645, 0.235), point(0.615, 0.26), point(0.575, 0.215),
                                point(0.535, 0.255), point(0.49, 0.215), point(0.445, 0.255), point(0.40, 0.22),
                                point(0.365, 0.255), point(0.345, 0.235), point(0.325, 0.29)])
        path.closeSubpath()
        for spike in [[(0.395, 0.135), (0.425, 0.06), (0.465, 0.115)],
                      [(0.465, 0.11), (0.515, 0.04), (0.55, 0.11)],
                      [(0.55, 0.115), (0.60, 0.07), (0.615, 0.145)]] {
            path.addLines(between: spike.map { point($0.0, $0.1) })
            path.closeSubpath()
        }
        path.move(to: point(0.345, 0.21))
        path.addQuadCurve(to: point(0.285, 0.36), control: point(0.29, 0.27))
        path.addQuadCurve(to: point(0.305, 0.50), control: point(0.28, 0.44))
        path.addQuadCurve(to: point(0.345, 0.43), control: point(0.335, 0.47))
        path.addQuadCurve(to: point(0.35, 0.29), control: point(0.35, 0.36))
        path.closeSubpath()
        path.move(to: point(0.655, 0.21))
        path.addQuadCurve(to: point(0.695, 0.33), control: point(0.70, 0.26))
        path.addQuadCurve(to: point(0.665, 0.38), control: point(0.69, 0.37))
        path.addLine(to: point(0.655, 0.29))
        path.closeSubpath()
        return path
    }

    /// The band of light across her eyes.
    static func hologramVisor(size: CGFloat) -> CGPath {
        CGPath(roundedRect: box(0.315, 0.265, 0.37, 0.085, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size,
               transform: nil)
    }

    /// Two slanted glints on the visor, the larger one first.
    static func hologramVisorGlint(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(polygonPath([(0.345, 0.335), (0.37, 0.28), (0.395, 0.28), (0.37, 0.335)], size: size))
        path.addPath(polygonPath([(0.40, 0.335), (0.415, 0.30), (0.43, 0.30), (0.415, 0.335)], size: size))
        return path
    }

    /// Her boots, the hoodie's collar and the band round its hem.
    static func hologramTrim(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.37, 0.865, 0.12, 0.065, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        path.addRoundedRect(in: box(0.51, 0.865, 0.12, 0.065, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        path.addPath(polygonPath([(0.42, 0.45), (0.50, 0.535), (0.58, 0.45), (0.55, 0.45), (0.50, 0.50), (0.45, 0.45)],
                                 size: size))
        path.addRect(box(0.30, 0.665, 0.40, 0.04, size))
        return path
    }

    /// Fine lines of light across all of her, as a projection is drawn.
    static func hologramScanlines(size: CGFloat) -> CGPath {
        let stripes = CGMutablePath()
        var y: CGFloat = 0.03
        while y < 0.95 {
            stripes.addRect(box(0, y, 1, 0.013, size))
            y += 0.042
        }
        let figure = CGMutablePath()
        figure.addPath(hologramBody(size: size))
        figure.addPath(hologramHair(size: size))
        figure.addPath(hologramArms(.rest, size: size))
        return stripes.intersection(figure)
    }

    /// The disc of light she is cast from, under her feet.
    static func hologramProjector(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: box(0.24, 0.925, 0.52, 0.055, size), transform: nil)
    }

    static func hologramArms(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let left = CGPoint(x: 0.33, y: 0.49), right = CGPoint(x: 0.67, y: 0.49)
        let (leftElbow, leftHand, rightElbow, rightHand): (CGPoint, CGPoint, CGPoint, CGPoint)
        switch pose {
        case .rest: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.22, y: 0.58), .init(x: 0.32, y: 0.65),
                                                                    .init(x: 0.73, y: 0.59), .init(x: 0.72, y: 0.69))
        case .wave: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.22, y: 0.58), .init(x: 0.32, y: 0.65),
                                                                    .init(x: 0.78, y: 0.43), .init(x: 0.79, y: 0.30))
        case .waveOut: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.22, y: 0.58), .init(x: 0.32, y: 0.65),
                                                                       .init(x: 0.79, y: 0.43), .init(x: 0.86, y: 0.32))
        case .up: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.23, y: 0.39), .init(x: 0.21, y: 0.26),
                                                                  .init(x: 0.77, y: 0.39), .init(x: 0.79, y: 0.26))
        case .folded: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.29, y: 0.60), .init(x: 0.41, y: 0.61),
                                                                      .init(x: 0.71, y: 0.60), .init(x: 0.59, y: 0.61))
        }
        let path = CGMutablePath()
        limb(into: path, [left, leftElbow, leftHand], width: 0.075, hand: 0.042, size: size)
        limb(into: path, [right, rightElbow, rightHand], width: 0.075, hand: 0.042, size: size)
        return path
    }

    // MARK: Android

    /// A rounded helmet, a broad chest tapering to the waist, and two legs
    /// that end in points, a hand above the floor.
    static func androidBody(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.31, 0.10, 0.38, 0.32, size), cornerWidth: 0.13 * size, cornerHeight: 0.13 * size)
        path.addRect(box(0.46, 0.40, 0.08, 0.07, size))
        path.move(to: point(0.34, 0.45))
        path.addLine(to: point(0.66, 0.45))
        path.addQuadCurve(to: point(0.72, 0.51), control: point(0.72, 0.45))
        path.addLine(to: point(0.66, 0.64))
        path.addLine(to: point(0.60, 0.70))
        path.addLine(to: point(0.40, 0.70))
        path.addLine(to: point(0.34, 0.64))
        path.addLine(to: point(0.28, 0.51))
        path.addQuadCurve(to: point(0.34, 0.45), control: point(0.28, 0.45))
        path.closeSubpath()
        path.addPath(polygonPath([(0.39, 0.68), (0.485, 0.68), (0.475, 0.80), (0.455, 0.885), (0.435, 0.885), (0.40, 0.80)],
                                 size: size))
        path.addPath(polygonPath([(0.515, 0.68), (0.61, 0.68), (0.60, 0.80), (0.565, 0.885), (0.545, 0.885), (0.525, 0.80)],
                                 size: size))
        return path
    }

    /// Shoulder plates, the fin on its helmet, the discs where ears would
    /// be, its belt and knees.
    static func androidPlates(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.235, 0.44, 0.135, 0.095, size))
        path.addEllipse(in: box(0.63, 0.44, 0.135, 0.095, size))
        path.addRoundedRect(in: box(0.475, 0.035, 0.05, 0.085, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        path.addEllipse(in: box(0.285, 0.21, 0.05, 0.10, size))
        path.addEllipse(in: box(0.665, 0.21, 0.05, 0.10, size))
        path.addRect(box(0.35, 0.635, 0.30, 0.03, size))
        path.addEllipse(in: box(0.41, 0.76, 0.055, 0.04, size))
        path.addEllipse(in: box(0.535, 0.76, 0.055, 0.04, size))
        return path
    }

    /// The window of the load gauge at its heart.
    static func androidGauge(size: CGFloat) -> CGPath {
        CGPath(roundedRect: box(0.45, 0.495, 0.10, 0.13, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size,
               transform: nil)
    }

    /// The gauge's lit cells, from the bottom up, `level` of four.
    static func androidGaugeCells(level: Int, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for cell in 0..<4 {
            // An unlit cell has no height, so every level morphs into the next.
            let lit: CGFloat = cell < level ? 0.018 : 0
            path.addRect(box(0.465, 0.597 - CGFloat(cell) * 0.027, 0.07, lit, size))
        }
        return path
    }

    /// The light on the helmet's crown.
    static func androidShine(size: CGFloat) -> CGPath {
        CGPath(roundedRect: box(0.36, 0.135, 0.10, 0.035, size), cornerWidth: 0.017 * size, cornerHeight: 0.017 * size,
               transform: nil)
    }

    /// The light it floats on.
    static func androidHover(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: box(0.34, 0.925, 0.32, 0.05, size), transform: nil)
    }

    static func androidArms(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let left = CGPoint(x: 0.30, y: 0.50), right = CGPoint(x: 0.70, y: 0.50)
        let (leftElbow, leftHand, rightElbow, rightHand): (CGPoint, CGPoint, CGPoint, CGPoint)
        switch pose {
        case .rest: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.25, y: 0.60), .init(x: 0.27, y: 0.69),
                                                                    .init(x: 0.75, y: 0.60), .init(x: 0.73, y: 0.69))
        case .wave: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.25, y: 0.60), .init(x: 0.27, y: 0.69),
                                                                    .init(x: 0.79, y: 0.42), .init(x: 0.80, y: 0.29))
        case .waveOut: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.25, y: 0.60), .init(x: 0.27, y: 0.69),
                                                                       .init(x: 0.80, y: 0.42), .init(x: 0.87, y: 0.31))
        case .up: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.21, y: 0.40), .init(x: 0.19, y: 0.28),
                                                                  .init(x: 0.79, y: 0.40), .init(x: 0.81, y: 0.28))
        case .folded: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.30, y: 0.61), .init(x: 0.41, y: 0.60),
                                                                      .init(x: 0.70, y: 0.61), .init(x: 0.59, y: 0.60))
        }
        let path = CGMutablePath()
        limb(into: path, [left, leftElbow, leftHand], width: 0.06, hand: 0.038, size: size)
        limb(into: path, [right, rightElbow, rightHand], width: 0.06, hand: 0.038, size: size)
        return path
    }

    // MARK: Helpers

    /// An arm: a rounded segment from joint to joint, and a round hand at its
    /// end. Always the same commands, whatever the points.
    static func limb(into path: CGMutablePath, _ joints: [CGPoint], width: CGFloat, hand: CGFloat, size: CGFloat) {
        for (from, to) in zip(joints, joints.dropFirst()) {
            let dx = to.x - from.x, dy = to.y - from.y
            let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
            let ux = dx / length, uy = dy / length
            let nx = -uy * width / 2, ny = ux * width / 2
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
            path.move(to: point(from.x + nx, from.y + ny))
            path.addLine(to: point(to.x + nx, to.y + ny))
            path.addQuadCurve(to: point(to.x - nx, to.y - ny),
                              control: point(to.x + ux * width * 0.7, to.y + uy * width * 0.7))
            path.addLine(to: point(from.x - nx, from.y - ny))
            path.addQuadCurve(to: point(from.x + nx, from.y + ny),
                              control: point(from.x - ux * width * 0.7, from.y - uy * width * 0.7))
            path.closeSubpath()
        }
        // The hand turns the same way round as the segments, so where they
        // overlap it fills rather than cancels out.
        if let end = joints.last {
            let center = CGPoint(x: end.x * size, y: end.y * size)
            path.move(to: CGPoint(x: center.x + hand * size, y: center.y))
            path.addArc(center: center, radius: hand * size, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            path.closeSubpath()
        }
    }

    static func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ size: CGFloat) -> CGRect {
        CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
    }

    static func polygonPath(_ points: [(CGFloat, CGFloat)], size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0 * size, y: $0.1 * size) })
        path.closeSubpath()
        return path
    }
}
