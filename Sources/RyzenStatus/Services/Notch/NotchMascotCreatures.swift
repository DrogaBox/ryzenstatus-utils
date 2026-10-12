// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The outlines of the companions beyond the minimal one and the robot: a
/// little chip, a case fan, a cat, a ghost and a slime, and the props any of
/// them carries in a mood. Everything is a vector path in a square of `size`
/// points from its top left corner, y growing downward, like the rest of
/// `NotchMascotGeometry`. Paths a motion morphs between are built with the
/// same commands, so Core Animation can blend one into the other.
enum NotchMascotCreatures {
    // MARK: Faces

    static func face(_ style: NotchMascotStyle) -> NotchMascotFaceLayout? {
        switch style {
        case .minimal, .robot: return nil
        case .chip:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.39, y: 0.59), rightEye: CGPoint(x: 0.61, y: 0.59),
                                         eyeSize: CGSize(width: 0.085, height: 0.17),
                                         shineCenter: CGPoint(x: 0.31, y: 0.36), shineRadii: CGSize(width: 0.065, height: 0.035),
                                         shineAngle: -0.4)
        case .fan:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.43, y: 0.58), rightEye: CGPoint(x: 0.57, y: 0.58),
                                         eyeSize: CGSize(width: 0.065, height: 0.13),
                                         shineCenter: CGPoint(x: 0.25, y: 0.30), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.6)
        case .cat:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.37, y: 0.58), rightEye: CGPoint(x: 0.63, y: 0.58),
                                         eyeSize: CGSize(width: 0.09, height: 0.18),
                                         shineCenter: CGPoint(x: 0.30, y: 0.40), shineRadii: CGSize(width: 0.07, height: 0.04),
                                         shineAngle: -0.5)
        case .ghost:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.39, y: 0.50), rightEye: CGPoint(x: 0.61, y: 0.50),
                                         eyeSize: CGSize(width: 0.095, height: 0.20),
                                         shineCenter: CGPoint(x: 0.33, y: 0.31), shineRadii: CGSize(width: 0.07, height: 0.045),
                                         shineAngle: -0.6)
        case .slime:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.38, y: 0.60), rightEye: CGPoint(x: 0.62, y: 0.60),
                                         eyeSize: CGSize(width: 0.10, height: 0.19),
                                         shineCenter: CGPoint(x: 0.35, y: 0.40), shineRadii: CGSize(width: 0.08, height: 0.05),
                                         shineAngle: -0.7)
        }
    }

    /// The whole figure's box in shares of its size, ears, pins and tail
    /// included, so it can be centred by what shows.
    static func bounds(_ style: NotchMascotStyle) -> CGRect? {
        switch style {
        case .minimal, .robot: return nil
        case .chip: return CGRect(x: 0.09, y: 0.17, width: 0.82, height: 0.82)
        case .fan: return CGRect(x: 0.10, y: 0.18, width: 0.80, height: 0.80)
        case .cat: return CGRect(x: 0.06, y: 0.12, width: 0.94, height: 0.82)
        case .ghost: return CGRect(x: 0.16, y: 0.20, width: 0.68, height: 0.74)
        case .slime: return CGRect(x: 0.07, y: 0.22, width: 0.86, height: 0.76)
        }
    }

    // MARK: Bodies

    /// The body the palette's gradient fills.
    static func body(_ style: NotchMascotStyle, size: CGFloat) -> CGPath? {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .minimal, .robot: return nil
        case .chip:
            path.addRoundedRect(in: rect(0.18, 0.26, 0.64, 0.64, size), cornerWidth: 0.12 * size, cornerHeight: 0.12 * size)
        case .fan:
            path.addRoundedRect(in: rect(0.10, 0.18, 0.80, 0.80, size), cornerWidth: 0.2 * size, cornerHeight: 0.2 * size)
        case .cat:
            path.addEllipse(in: rect(0.12, 0.30, 0.76, 0.62, size))
        case .ghost:
            path.move(to: point(0.16, 0.56))
            path.addCurve(to: point(0.5, 0.20), control1: point(0.16, 0.36), control2: point(0.30, 0.20))
            path.addCurve(to: point(0.84, 0.56), control1: point(0.70, 0.20), control2: point(0.84, 0.36))
            path.addLine(to: point(0.84, 0.86))
            // A scalloped hem, three bumps across.
            path.addQuadCurve(to: point(0.727, 0.86), control: point(0.784, 0.99))
            path.addQuadCurve(to: point(0.613, 0.86), control: point(0.67, 0.99))
            path.addQuadCurve(to: point(0.5, 0.86), control: point(0.557, 0.99))
            path.addQuadCurve(to: point(0.387, 0.86), control: point(0.443, 0.99))
            path.addQuadCurve(to: point(0.273, 0.86), control: point(0.33, 0.99))
            path.addQuadCurve(to: point(0.16, 0.86), control: point(0.216, 0.99))
            path.closeSubpath()
        case .slime:
            path.move(to: point(0.09, 0.88))
            path.addCurve(to: point(0.5, 0.22), control1: point(0.06, 0.54), control2: point(0.28, 0.24))
            path.addCurve(to: point(0.91, 0.88), control1: point(0.72, 0.24), control2: point(0.94, 0.54))
            path.addQuadCurve(to: point(0.09, 0.88), control: point(0.5, 0.97))
            path.closeSubpath()
        }
        return path
    }

    // MARK: Chip

    /// Three pins on each side.
    static func chipPins(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let radius = 0.018 * size
        for center in [0.40, 0.58, 0.76] as [CGFloat] {
            path.addRoundedRect(in: rect(0.09, center - 0.0325, 0.10, 0.065, size), cornerWidth: radius, cornerHeight: radius)
            path.addRoundedRect(in: rect(0.81, center - 0.0325, 0.10, 0.065, size), cornerWidth: radius, cornerHeight: radius)
        }
        for center in [0.34, 0.50, 0.66] as [CGFloat] {
            path.addRoundedRect(in: rect(center - 0.0325, 0.17, 0.065, 0.10, size), cornerWidth: radius, cornerHeight: radius)
            path.addRoundedRect(in: rect(center - 0.0325, 0.89, 0.065, 0.10, size), cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    /// The pin-one triangle in a corner.
    static func chipMark(size: CGFloat) -> CGPath {
        polygon([(0.25, 0.84), (0.25, 0.75), (0.34, 0.84)], size: size)
    }

    // MARK: Fan

    /// Where the blades turn, and how far they reach, in shares of its size.
    static let fanCenter = CGPoint(x: 0.5, y: 0.58)
    static let fanReach: CGFloat = 0.33

    /// The dark opening the blades turn in.
    static func fanHole(size: CGFloat) -> CGPath {
        let radius: CGFloat = 0.355
        return CGPath(ellipseIn: rect(fanCenter.x - radius, fanCenter.y - radius, radius * 2, radius * 2, size),
                      transform: nil)
    }

    /// The hub the face sits on.
    static func fanHub(size: CGFloat) -> CGPath {
        let radius: CGFloat = 0.2
        return CGPath(ellipseIn: rect(fanCenter.x - radius, fanCenter.y - radius, radius * 2, radius * 2, size),
                      transform: nil)
    }

    /// A screw in each corner of the frame.
    static func fanScrews(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let radius: CGFloat = 0.028
        for (x, y) in [(0.185, 0.265), (0.815, 0.265), (0.185, 0.895), (0.815, 0.895)] as [(CGFloat, CGFloat)] {
            path.addEllipse(in: rect(x - radius, y - radius, radius * 2, radius * 2, size))
        }
        return path
    }

    /// Five swept blades in a square of `side` points, around its middle.
    static func fanBlades(side: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: side / 2, y: side / 2)
        let outer = side / 2 * 0.98, inner = side / 2 * 0.5
        func polar(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        for index in 0..<5 {
            let angle = CGFloat(index) / 5 * 2 * .pi
            path.move(to: polar(inner, angle))
            path.addQuadCurve(to: polar(outer, angle + 0.35), control: polar(outer * 0.85, angle + 0.02))
            path.addQuadCurve(to: polar(outer, angle + 0.95), control: polar(outer * 1.08, angle + 0.65))
            path.addQuadCurve(to: polar(inner, angle + 0.62), control: polar(inner * 1.35, angle + 0.9))
            path.closeSubpath()
        }
        return path
    }

    // MARK: Cat

    enum EarPose { case up, twitch, droop }
    enum TailPose { case rest, sway, curl }

    /// Both ears. `inner` is the shaded inside of each.
    static func catEars(_ pose: EarPose, inner: Bool, size: CGFloat) -> CGPath {
        let tip: (CGFloat, CGFloat)
        switch pose {
        case .up: tip = (0.20, 0.12)
        case .twitch: tip = (0.11, 0.17)
        case .droop: tip = (0.07, 0.38)
        }
        let path = CGMutablePath()
        for mirrored in [false, true] {
            func x(_ value: CGFloat) -> CGFloat { mirrored ? 1 - value : value }
            var corners: [CGPoint] = [CGPoint(x: x(0.15), y: 0.52), CGPoint(x: x(tip.0), y: tip.1),
                                      CGPoint(x: x(0.46), y: 0.34)]
            if inner {
                // The same triangle drawn smaller toward its middle.
                let middle = CGPoint(x: (corners[0].x + corners[1].x + corners[2].x) / 3,
                                     y: (corners[0].y + corners[1].y + corners[2].y) / 3)
                corners = corners.map { CGPoint(x: middle.x + ($0.x - middle.x) * 0.5, y: middle.y + ($0.y - middle.y) * 0.5) }
            }
            let scaled = corners.map { CGPoint(x: $0.x * size, y: $0.y * size) }
            path.move(to: scaled[0])
            path.addLine(to: lerp(scaled[0], scaled[1], 0.82))
            path.addQuadCurve(to: lerp(scaled[2], scaled[1], 0.82), control: scaled[1])
            path.addLine(to: scaled[2])
            path.closeSubpath()
        }
        return path
    }

    /// The tail, a stroke from behind the body.
    static func catTail(_ pose: TailPose, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.76, 0.84))
        switch pose {
        case .rest:
            path.addCurve(to: point(0.95, 0.50), control1: point(0.96, 0.86), control2: point(1.0, 0.66))
        case .sway:
            path.addCurve(to: point(0.87, 0.42), control1: point(0.98, 0.84), control2: point(0.82, 0.60))
        case .curl:
            path.addCurve(to: point(0.62, 0.94), control1: point(0.98, 0.90), control2: point(0.90, 1.0))
        }
        return path
    }

    static func catWhiskers(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (from, to) in [((0.06, 0.66), (0.25, 0.70)), ((0.07, 0.79), (0.25, 0.76)),
                           ((0.94, 0.66), (0.75, 0.70)), ((0.93, 0.79), (0.75, 0.76))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
            path.move(to: CGPoint(x: from.0 * size, y: from.1 * size))
            path.addLine(to: CGPoint(x: to.0 * size, y: to.1 * size))
        }
        return path
    }

    static func catNose(size: CGFloat) -> CGPath {
        polygon([(0.465, 0.715), (0.535, 0.715), (0.5, 0.76)], size: size)
    }

    // MARK: Ghost

    /// Its mouth, a small slit or an "o" as it says boo.
    static func ghostMouth(open: Bool, size: CGFloat) -> CGPath {
        let radii = open ? CGSize(width: 0.05, height: 0.065) : CGSize(width: 0.035, height: 0.012)
        return CGPath(ellipseIn: rect(0.5 - radii.width, 0.70 - radii.height, radii.width * 2, radii.height * 2, size),
                      transform: nil)
    }

    // MARK: Slime

    /// The drop it leaves beside it, a puddle as it melts asleep.
    static func slimeDrip(melted: Bool, size: CGFloat) -> CGPath {
        let center = melted ? CGPoint(x: 0.26, y: 0.915) : CGPoint(x: 0.19, y: 0.92)
        let radii = melted ? CGSize(width: 0.14, height: 0.035) : CGSize(width: 0.045, height: 0.035)
        return CGPath(ellipseIn: rect(center.x - radii.width, center.y - radii.height, radii.width * 2, radii.height * 2,
                                      size), transform: nil)
    }

    // MARK: Props

    /// Colors the props keep whatever the palette, so they read as what they are.
    static let sweat = NotchMascotColor(red: 0.55, green: 0.82, blue: 1.0)
    static let heat = NotchMascotColor(red: 1.0, green: 0.50, blue: 0.25)
    static let mug = NotchMascotColor(red: 0.97, green: 0.95, blue: 0.91)
    static let coffee = NotchMascotColor(red: 0.45, green: 0.28, blue: 0.18)
    static let download = NotchMascotColor(red: 0.45, green: 0.90, blue: 0.60)
    static let warning = NotchMascotColor(red: 1.0, green: 0.36, blue: 0.30)
    static let confetti: [NotchMascotColor] = [
        NotchMascotColor(red: 1.0, green: 0.42, blue: 0.42), NotchMascotColor(red: 1.0, green: 0.80, blue: 0.30),
        NotchMascotColor(red: 0.45, green: 0.88, blue: 0.55), NotchMascotColor(red: 0.40, green: 0.70, blue: 1.0),
        NotchMascotColor(red: 0.80, green: 0.55, blue: 1.0),
    ]

    /// A drop of sweat by its brow.
    static func sweatDrop(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.86, 0.20))
        path.addCurve(to: point(0.86, 0.42), control1: point(0.94, 0.30), control2: point(0.94, 0.42))
        path.addCurve(to: point(0.86, 0.20), control1: point(0.78, 0.42), control2: point(0.78, 0.30))
        path.closeSubpath()
        return path
    }

    /// Three wavy lines of heat rising over its head.
    static func heatLines(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for x in [0.30, 0.50, 0.70] as [CGFloat] {
            path.move(to: CGPoint(x: x * size, y: 0.16 * size))
            path.addCurve(to: CGPoint(x: x * size, y: -0.06 * size),
                          control1: CGPoint(x: (x + 0.06) * size, y: 0.09 * size),
                          control2: CGPoint(x: (x - 0.06) * size, y: 0.01 * size))
        }
        return path
    }

    /// A music note, filled.
    static func note(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.80, 0.24, 0.10, 0.075, size))
        path.addRect(rect(0.875, 0.04, 0.025, 0.24, size))
        path.move(to: point(0.9, 0.04))
        path.addQuadCurve(to: point(0.98, 0.16), control: point(1.0, 0.06))
        path.addQuadCurve(to: point(0.9, 0.10), control: point(0.96, 0.10))
        path.closeSubpath()
        return path
    }

    /// A coffee mug held at its side, with its handle.
    static func mug(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect(0.70, 0.64, 0.20, 0.25, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size)
        return path
    }

    static func mugHandle(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: rect(0.85, 0.69, 0.11, 0.12, size), transform: nil)
    }

    static func mugCoffee(size: CGFloat) -> CGPath {
        CGPath(rect: rect(0.72, 0.66, 0.16, 0.04, size), transform: nil)
    }

    /// Steam over the mug, two curls.
    static func steam(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for x in [0.76, 0.84] as [CGFloat] {
            path.move(to: CGPoint(x: x * size, y: 0.60 * size))
            path.addCurve(to: CGPoint(x: x * size, y: 0.44 * size),
                          control1: CGPoint(x: (x + 0.04) * size, y: 0.55 * size),
                          control2: CGPoint(x: (x - 0.04) * size, y: 0.49 * size))
        }
        return path
    }

    /// A "z" for sleeping.
    static func z(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points: [(CGFloat, CGFloat)] = [(0.80, 0.06), (0.94, 0.06), (0.80, 0.20), (0.94, 0.20)]
        path.move(to: CGPoint(x: points[0].0 * size, y: points[0].1 * size))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0 * size, y: point.1 * size)) }
        return path
    }

    /// The down arrow it watches during a big download.
    static func downArrow(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.95 * size, y: 0.08 * size))
        path.addLine(to: CGPoint(x: 0.95 * size, y: 0.32 * size))
        path.move(to: CGPoint(x: 0.88 * size, y: 0.25 * size))
        path.addLine(to: CGPoint(x: 0.95 * size, y: 0.33 * size))
        path.addLine(to: CGPoint(x: 1.02 * size, y: 0.25 * size))
        return path
    }

    /// An almost empty battery over its head.
    static func battery(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect(0.74, 0.06, 0.22, 0.12, size), cornerWidth: 0.025 * size, cornerHeight: 0.025 * size)
        path.addRect(rect(0.96, 0.095, 0.025, 0.05, size))
        return path
    }

    static func batteryLevel(size: CGFloat) -> CGPath {
        CGPath(rect: rect(0.765, 0.085, 0.04, 0.07, size), transform: nil)
    }

    /// A paw or hand that comes up to wave.
    static func paw(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: rect(0.84, 0.54, 0.15, 0.15, size), transform: nil)
    }

    /// One bit of confetti, centred on its layer's origin.
    static func confettiPiece(size: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: -0.035 * size, y: -0.02 * size, width: 0.07 * size, height: 0.04 * size), transform: nil)
    }

    /// Where each bit of confetti flies, from above its head, in shares of its size.
    static let confettiFlights: [CGPoint] = [
        CGPoint(x: -0.55, y: -0.35), CGPoint(x: -0.35, y: -0.6), CGPoint(x: -0.12, y: -0.75), CGPoint(x: 0.1, y: -0.7),
        CGPoint(x: 0.32, y: -0.62), CGPoint(x: 0.55, y: -0.4), CGPoint(x: -0.45, y: -0.1), CGPoint(x: 0.48, y: -0.12),
    ]

    // MARK: Helpers

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ size: CGFloat) -> CGRect {
        CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)], size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0 * size, y: $0.1 * size) })
        path.closeSubpath()
        return path
    }

    private static func lerp(_ from: CGPoint, _ to: CGPoint, _ share: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
    }
}
