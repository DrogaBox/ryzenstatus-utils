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
        case .minimal, .robot, .cristobal, .whiteRabbit: return nil
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
        case .devourer:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.40, y: 0.52), rightEye: CGPoint(x: 0.60, y: 0.52),
                                         eyeSize: CGSize(width: 0.075, height: 0.21),
                                         shineCenter: CGPoint(x: 0.37, y: 0.40), shineRadii: CGSize(width: 0.05, height: 0.05),
                                         shineAngle: 0)
        case .shifter:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.42, y: 0.55), rightEye: CGPoint(x: 0.58, y: 0.55),
                                         eyeSize: CGSize(width: 0.05, height: 0.08),
                                         shineCenter: CGPoint(x: 0.41, y: 0.52), shineRadii: CGSize(width: 0.02, height: 0.02),
                                         shineAngle: 0)
        case .phoenix:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.39, y: 0.48), rightEye: CGPoint(x: 0.61, y: 0.48),
                                         eyeSize: CGSize(width: 0.07, height: 0.18),
                                         shineCenter: CGPoint(x: 0.35, y: 0.34), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.5)
        case .axolotl:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.37, y: 0.30), rightEye: CGPoint(x: 0.63, y: 0.30),
                                         eyeSize: CGSize(width: 0.065, height: 0.14),
                                         shineCenter: CGPoint(x: 0.34, y: 0.24), shineRadii: CGSize(width: 0.04, height: 0.025),
                                         shineAngle: -0.3)
        case .dog:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.38, y: 0.24), rightEye: CGPoint(x: 0.62, y: 0.24),
                                         eyeSize: CGSize(width: 0.07, height: 0.15),
                                         shineCenter: CGPoint(x: 0.34, y: 0.15), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.4)
        case .mouse:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.41, y: 0.30), rightEye: CGPoint(x: 0.59, y: 0.30),
                                         eyeSize: CGSize(width: 0.06, height: 0.13),
                                         shineCenter: CGPoint(x: 0.38, y: 0.22), shineRadii: CGSize(width: 0.04, height: 0.025),
                                         shineAngle: -0.3)
        case .capybara:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.35, y: 0.32), rightEye: CGPoint(x: 0.65, y: 0.32),
                                         eyeSize: CGSize(width: 0.055, height: 0.09),
                                         shineCenter: CGPoint(x: 0.34, y: 0.30), shineRadii: CGSize(width: 0.03, height: 0.02),
                                         shineAngle: 0)
        case .dragon:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.36, y: 0.30), rightEye: CGPoint(x: 0.64, y: 0.30),
                                         eyeSize: CGSize(width: 0.07, height: 0.16),
                                         shineCenter: CGPoint(x: 0.33, y: 0.22), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.4)
        case .frog:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.29, y: 0.17), rightEye: CGPoint(x: 0.71, y: 0.17),
                                         eyeSize: CGSize(width: 0.08, height: 0.14),
                                         shineCenter: CGPoint(x: 0.27, y: 0.13), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.2)
        case .swan:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.44, y: 0.24), rightEye: CGPoint(x: 0.56, y: 0.24),
                                         eyeSize: CGSize(width: 0.055, height: 0.12),
                                         shineCenter: CGPoint(x: 0.42, y: 0.18), shineRadii: CGSize(width: 0.04, height: 0.02),
                                         shineAngle: -0.3)
        case .ballerina:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.42, y: 0.28), rightEye: CGPoint(x: 0.58, y: 0.28),
                                         eyeSize: CGSize(width: 0.065, height: 0.14),
                                         shineCenter: CGPoint(x: 0.40, y: 0.22), shineRadii: CGSize(width: 0.04, height: 0.025),
                                         shineAngle: -0.3)
        case .danseur:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.41, y: 0.26), rightEye: CGPoint(x: 0.59, y: 0.26),
                                         eyeSize: CGSize(width: 0.065, height: 0.14),
                                         shineCenter: CGPoint(x: 0.38, y: 0.20), shineRadii: CGSize(width: 0.045, height: 0.025),
                                         shineAngle: -0.4)
        case .contemporary:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.40, y: 0.30), rightEye: CGPoint(x: 0.60, y: 0.30),
                                         eyeSize: CGSize(width: 0.065, height: 0.13),
                                         shineCenter: CGPoint(x: 0.38, y: 0.24), shineRadii: CGSize(width: 0.04, height: 0.025),
                                         shineAngle: -0.3)
        case .kitsune:
            // Narrow, knowing eyes set high on the mask.
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.40, y: 0.44), rightEye: CGPoint(x: 0.60, y: 0.44),
                                         eyeSize: CGSize(width: 0.06, height: 0.12),
                                         shineCenter: CGPoint(x: 0.36, y: 0.30), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.4)
        case .penguin:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.42, y: 0.31), rightEye: CGPoint(x: 0.58, y: 0.31),
                                         eyeSize: CGSize(width: 0.055, height: 0.11),
                                         shineCenter: CGPoint(x: 0.40, y: 0.18), shineRadii: CGSize(width: 0.05, height: 0.03),
                                         shineAngle: -0.4)
        case .hologram:
            // Small eyes, seen through the band of her visor.
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.43, y: 0.307), rightEye: CGPoint(x: 0.57, y: 0.307),
                                         eyeSize: CGSize(width: 0.05, height: 0.07),
                                         shineCenter: CGPoint(x: 0.41, y: 0.19), shineRadii: CGSize(width: 0.04, height: 0.02),
                                         shineAngle: -0.4)
        case .android:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.43, y: 0.28), rightEye: CGPoint(x: 0.57, y: 0.28),
                                         eyeSize: CGSize(width: 0.055, height: 0.10),
                                         shineCenter: CGPoint(x: 0.62, y: 0.17), shineRadii: CGSize(width: 0.03, height: 0.015),
                                         shineAngle: -0.4)
        }
    }

    /// The whole figure's box in shares of its size, ears, pins and tail
    /// included, so it can be centred by what shows.
    static func bounds(_ style: NotchMascotStyle) -> CGRect? {
        switch style {
        case .minimal, .robot, .cristobal, .whiteRabbit: return nil
        case .chip: return CGRect(x: 0.09, y: 0.17, width: 0.82, height: 0.82)
        case .fan: return CGRect(x: 0.10, y: 0.18, width: 0.80, height: 0.80)
        case .cat: return CGRect(x: 0.06, y: 0.12, width: 0.94, height: 0.82)
        case .ghost: return CGRect(x: 0.16, y: 0.20, width: 0.68, height: 0.74)
        case .slime: return CGRect(x: 0.07, y: 0.22, width: 0.86, height: 0.76)
        case .devourer: return CGRect(x: 0.04, y: 0.20, width: 0.92, height: 0.78)
        case .shifter: return CGRect(x: 0.07, y: 0.30, width: 0.86, height: 0.66)
        case .phoenix: return CGRect(x: 0.02, y: 0.01, width: 0.96, height: 0.98)
        case .axolotl: return CGRect(x: 0.02, y: 0.12, width: 0.96, height: 0.82)
        case .dog: return CGRect(x: 0.04, y: 0.04, width: 0.94, height: 0.88)
        case .mouse: return CGRect(x: 0.10, y: 0.04, width: 0.88, height: 0.86)
        case .capybara: return CGRect(x: 0.12, y: 0.05, width: 0.76, height: 0.89)
        case .dragon: return CGRect(x: 0.04, y: 0.04, width: 0.94, height: 0.90)
        case .frog: return CGRect(x: 0.12, y: 0.06, width: 0.76, height: 0.86)
        case .swan: return CGRect(x: 0.08, y: 0.05, width: 0.84, height: 0.88)
        case .ballerina: return CGRect(x: 0.08, y: 0.04, width: 0.84, height: 0.92)
        case .danseur: return CGRect(x: 0.12, y: 0.06, width: 0.76, height: 0.90)
        case .contemporary: return CGRect(x: 0.10, y: 0.08, width: 0.80, height: 0.88)
        case .kitsune: return CGRect(x: 0.06, y: 0.03, width: 0.92, height: 0.94)
        case .penguin: return CGRect(x: 0.04, y: 0.09, width: 0.92, height: 0.88)
        case .hologram: return CGRect(x: 0.17, y: 0.04, width: 0.70, height: 0.95)
        case .android: return CGRect(x: 0.18, y: 0.035, width: 0.64, height: 0.945)
        }
    }

    /// The head alone, where a hat or glasses belong, for the shapes whose
    /// body is more than a head. Nil keeps the whole body as the outline, as
    /// for the minimal companion and the robot.
    static func headOutline(_ style: NotchMascotStyle, size: CGFloat) -> CGRect? {
        switch style {
        case .minimal, .robot, .cristobal, .whiteRabbit: return nil
        case .chip: return rect(0.18, 0.26, 0.64, 0.64, size)
        case .fan: return rect(0.10, 0.18, 0.80, 0.80, size)
        case .cat: return rect(0.20, 0.24, 0.60, 0.40, size)
        case .ghost: return rect(0.16, 0.20, 0.68, 0.56, size)
        case .slime: return rect(0.09, 0.22, 0.82, 0.64, size)
        case .devourer: return rect(0.12, 0.20, 0.76, 0.66, size)
        case .shifter: return rect(0.10, 0.30, 0.80, 0.60, size)
        case .phoenix: return rect(0.33, 0.10, 0.34, 0.34, size)
        case .axolotl: return rect(0.16, 0.14, 0.68, 0.42, size)
        case .dog: return rect(0.22, 0.08, 0.56, 0.44, size)
        case .mouse: return rect(0.30, 0.18, 0.40, 0.34, size)
        case .capybara: return rect(0.24, 0.18, 0.52, 0.44, size)
        case .dragon: return rect(0.26, 0.12, 0.48, 0.42, size)
        case .frog: return rect(0.20, 0.08, 0.60, 0.46, size)
        case .swan: return rect(0.36, 0.10, 0.28, 0.26, size)
        case .ballerina: return rect(0.32, 0.14, 0.36, 0.32, size)
        case .danseur: return rect(0.32, 0.12, 0.36, 0.34, size)
        case .contemporary: return rect(0.30, 0.16, 0.40, 0.34, size)
        case .kitsune: return rect(0.20, 0.20, 0.60, 0.42, size)
        case .penguin: return rect(0.28, 0.10, 0.44, 0.34, size)
        case .hologram: return rect(0.32, 0.11, 0.36, 0.33, size)
        case .android: return rect(0.31, 0.10, 0.38, 0.32, size)
        }
    }

    /// Where a scarf goes, from 0 to 1 down the figure, for those whose neck
    /// is not just under the head outline nor well under the eyes: a cat that
    /// is all head, a phoenix whose eyes sit low, a frog with no neck at all
    /// and a swan with a long one.
    static func neck(_ style: NotchMascotStyle) -> CGFloat? {
        switch style {
        case .cat: return 0.78
        case .phoenix: return 0.6
        case .frog: return 0.5
        case .swan: return 0.4
        default: return nil
        }
    }

    // MARK: Bodies

    /// The body the palette's gradient fills.
    static func body(_ style: NotchMascotStyle, size: CGFloat) -> CGPath? {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        switch style {
        case .minimal, .robot, .cristobal, .whiteRabbit: return nil
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
        case .devourer:
            path.addEllipse(in: rect(0.12, 0.20, 0.76, 0.70, size))
        case .shifter:
            // Lopsided and soft, a blob that has not decided yet.
            path.move(to: point(0.08, 0.90))
            path.addCurve(to: point(0.34, 0.34), control1: point(0.05, 0.62), control2: point(0.18, 0.36))
            path.addCurve(to: point(0.74, 0.40), control1: point(0.50, 0.30), control2: point(0.62, 0.46))
            path.addCurve(to: point(0.93, 0.90), control1: point(0.90, 0.36), control2: point(0.96, 0.66))
            path.addQuadCurve(to: point(0.08, 0.90), control: point(0.5, 0.98))
            path.closeSubpath()
        case .slime:
            path.move(to: point(0.09, 0.88))
            path.addCurve(to: point(0.5, 0.22), control1: point(0.06, 0.54), control2: point(0.28, 0.24))
            path.addCurve(to: point(0.91, 0.88), control1: point(0.72, 0.24), control2: point(0.94, 0.54))
            path.addQuadCurve(to: point(0.09, 0.88), control: point(0.5, 0.97))
            path.closeSubpath()
        case .phoenix:
            // A flame bird, front on: a round head under a two-lick crest, a
            // round chest, and three licks of tail fanning below.
            path.addEllipse(in: rect(0.33, 0.10, 0.34, 0.34, size))
            path.addEllipse(in: rect(0.26, 0.36, 0.48, 0.46, size))
            path.move(to: point(0.46, 0.13))
            path.addQuadCurve(to: point(0.40, 0.02), control: point(0.38, 0.08))
            path.addQuadCurve(to: point(0.50, 0.11), control: point(0.44, 0.05))
            path.closeSubpath()
            path.move(to: point(0.52, 0.12))
            path.addQuadCurve(to: point(0.56, 0.01), control: point(0.55, 0.07))
            path.addQuadCurve(to: point(0.60, 0.14), control: point(0.58, 0.06))
            path.closeSubpath()
            path.move(to: point(0.40, 0.74))
            path.addQuadCurve(to: point(0.28, 0.95), control: point(0.30, 0.86))
            path.addQuadCurve(to: point(0.46, 0.80), control: point(0.36, 0.86))
            path.closeSubpath()
            path.move(to: point(0.46, 0.80))
            path.addQuadCurve(to: point(0.50, 0.99), control: point(0.44, 0.92))
            path.addQuadCurve(to: point(0.56, 0.80), control: point(0.54, 0.91))
            path.closeSubpath()
            path.move(to: point(0.56, 0.80))
            path.addQuadCurve(to: point(0.70, 0.94), control: point(0.66, 0.88))
            path.addQuadCurve(to: point(0.58, 0.74), control: point(0.64, 0.84))
            path.closeSubpath()
        case .axolotl:
            // The wide flat head every axolotl wears, over a slim body that
            // rounds off into its tail.
            path.addRoundedRect(in: rect(0.16, 0.14, 0.68, 0.42, size), cornerWidth: 0.21 * size, cornerHeight: 0.21 * size)
            path.addEllipse(in: rect(0.32, 0.46, 0.36, 0.42, size))
        case .dog:
            // A sitting pup, front on: a broad round head over a rounded chest.
            path.addEllipse(in: rect(0.22, 0.08, 0.56, 0.44, size))
            path.addEllipse(in: rect(0.17, 0.42, 0.66, 0.50, size))
        case .mouse:
            // Big round ears over a pear-sized body and a short muzzle.
            path.addEllipse(in: rect(0.13, 0.06, 0.30, 0.30, size))
            path.addEllipse(in: rect(0.57, 0.06, 0.30, 0.30, size))
            path.addEllipse(in: rect(0.30, 0.18, 0.40, 0.34, size))
            path.addEllipse(in: rect(0.33, 0.42, 0.34, 0.44, size))
        case .capybara:
            // A sitting capybara: rounded rectangular snout and a heavy rounded body.
            path.addRoundedRect(in: rect(0.24, 0.18, 0.52, 0.44, size), cornerWidth: 0.18 * size, cornerHeight: 0.18 * size)
            path.addEllipse(in: rect(0.16, 0.44, 0.68, 0.48, size))
        case .dragon:
            // A round wyrmling head over a compact pear chest.
            path.addEllipse(in: rect(0.26, 0.14, 0.48, 0.42, size))
            path.addEllipse(in: rect(0.22, 0.44, 0.56, 0.48, size))
        case .frog:
            // Bulbous crown eyes over a wide plump body.
            path.addEllipse(in: rect(0.20, 0.08, 0.20, 0.20, size))
            path.addEllipse(in: rect(0.60, 0.08, 0.20, 0.20, size))
            path.addEllipse(in: rect(0.20, 0.18, 0.60, 0.42, size))
            path.addEllipse(in: rect(0.16, 0.42, 0.68, 0.48, size))
        case .swan:
            // A magnificent royal swan floating serenely:
            // Gracefully contoured head, slender arched neck, proud puffed breast,
            // buoyant floating body and smooth waterline hull.
            path.move(to: point(0.50, 0.10))
            path.addQuadCurve(to: point(0.63, 0.20), control: point(0.61, 0.11))
            path.addQuadCurve(to: point(0.58, 0.29), control: point(0.63, 0.26))
            path.addCurve(to: point(0.55, 0.39), control1: point(0.56, 0.32), control2: point(0.55, 0.35))
            path.addCurve(to: point(0.68, 0.54), control1: point(0.55, 0.45), control2: point(0.62, 0.50))
            path.addCurve(to: point(0.77, 0.69), control1: point(0.74, 0.58), control2: point(0.77, 0.63))
            path.addQuadCurve(to: point(0.71, 0.84), control: point(0.77, 0.79))
            path.addQuadCurve(to: point(0.50, 0.86), control: point(0.61, 0.85))
            path.addQuadCurve(to: point(0.29, 0.84), control: point(0.39, 0.85))
            path.addQuadCurve(to: point(0.23, 0.69), control: point(0.23, 0.79))
            path.addCurve(to: point(0.32, 0.54), control1: point(0.23, 0.63), control2: point(0.26, 0.58))
            path.addCurve(to: point(0.45, 0.39), control1: point(0.38, 0.50), control2: point(0.45, 0.45))
            path.addCurve(to: point(0.42, 0.29), control1: point(0.45, 0.35), control2: point(0.44, 0.32))
            path.addQuadCurve(to: point(0.37, 0.20), control: point(0.37, 0.26))
            path.addQuadCurve(to: point(0.50, 0.10), control: point(0.39, 0.11))
            path.closeSubpath()
        case .ballerina:
            // High bun (chignon), delicate head, slender bodice, platter tutu and crossed pointes.
            path.addEllipse(in: rect(0.42, 0.04, 0.16, 0.14, size))
            path.addEllipse(in: rect(0.33, 0.14, 0.34, 0.30, size))
            path.move(to: point(0.38, 0.44))
            path.addLine(to: point(0.62, 0.44))
            path.addLine(to: point(0.57, 0.62))
            path.addLine(to: point(0.43, 0.62))
            path.closeSubpath()
            path.addEllipse(in: rect(0.12, 0.58, 0.76, 0.20, size))
            path.addRoundedRect(in: rect(0.42, 0.72, 0.07, 0.24, size), cornerWidth: 0.03 * size, cornerHeight: 0.03 * size)
            path.addRoundedRect(in: rect(0.51, 0.72, 0.07, 0.24, size), cornerWidth: 0.03 * size, cornerHeight: 0.03 * size)
        case .danseur:
            // Head, noble tunic with broad shoulders, dancer legs in fifth position.
            path.addEllipse(in: rect(0.32, 0.12, 0.36, 0.34, size))
            path.move(to: point(0.24, 0.44))
            path.addLine(to: point(0.76, 0.44))
            path.addLine(to: point(0.66, 0.66))
            path.addLine(to: point(0.34, 0.66))
            path.closeSubpath()
            path.addRoundedRect(in: rect(0.36, 0.66, 0.11, 0.30, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size)
            path.addRoundedRect(in: rect(0.53, 0.66, 0.11, 0.30, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size)
        case .contemporary:
            // Expressive head, fluid asymmetrical tunic drape and organic stance.
            path.addEllipse(in: rect(0.30, 0.14, 0.40, 0.34, size))
            path.move(to: point(0.22, 0.46))
            path.addCurve(to: point(0.78, 0.44), control1: point(0.40, 0.40), control2: point(0.60, 0.42))
            path.addLine(to: point(0.82, 0.76))
            path.addCurve(to: point(0.18, 0.78), control1: point(0.60, 0.84), control2: point(0.36, 0.74))
            path.closeSubpath()
            path.addRoundedRect(in: rect(0.32, 0.78, 0.12, 0.18, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size)
            path.addRoundedRect(in: rect(0.56, 0.78, 0.12, 0.18, size), cornerWidth: 0.04 * size, cornerHeight: 0.04 * size)
        case .kitsune:
            // A fox mask, wide at the cheek tufts and pointed at the chin,
            // over a sitting body with its two front paws together.
            path.move(to: point(0.30, 0.30))
            path.addCurve(to: point(0.70, 0.30), control1: point(0.40, 0.18), control2: point(0.60, 0.18))
            path.addQuadCurve(to: point(0.80, 0.44), control: point(0.78, 0.33))
            path.addLine(to: point(0.84, 0.51))
            path.addQuadCurve(to: point(0.50, 0.63), control: point(0.70, 0.60))
            path.addQuadCurve(to: point(0.16, 0.51), control: point(0.30, 0.60))
            path.addLine(to: point(0.20, 0.44))
            path.addQuadCurve(to: point(0.30, 0.30), control: point(0.22, 0.33))
            path.closeSubpath()
            path.addEllipse(in: rect(0.28, 0.50, 0.44, 0.42, size))
            path.addEllipse(in: rect(0.33, 0.85, 0.14, 0.09, size))
            path.addEllipse(in: rect(0.53, 0.85, 0.14, 0.09, size))
        case .penguin:
            // An emperor's egg-shaped body, head and all in one sweep.
            path.move(to: point(0.50, 0.10))
            path.addCurve(to: point(0.76, 0.40), control1: point(0.66, 0.10), control2: point(0.74, 0.24))
            path.addCurve(to: point(0.70, 0.88), control1: point(0.80, 0.62), control2: point(0.80, 0.80))
            path.addQuadCurve(to: point(0.30, 0.88), control: point(0.50, 0.95))
            path.addCurve(to: point(0.24, 0.40), control1: point(0.20, 0.80), control2: point(0.20, 0.62))
            path.addCurve(to: point(0.50, 0.10), control1: point(0.26, 0.24), control2: point(0.34, 0.10))
            path.closeSubpath()
        case .hologram:
            path.addPath(hologramBody(size: size))
        case .android:
            path.addPath(androidBody(size: size))
        }
        return path
    }

    // MARK: Devourer

    /// Stubby arms and two round feet.
    static func devourerLimbs(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.04, 0.46, 0.20, 0.17, size))
        path.addEllipse(in: rect(0.76, 0.46, 0.20, 0.17, size))
        path.addEllipse(in: rect(0.14, 0.84, 0.30, 0.14, size))
        path.addEllipse(in: rect(0.56, 0.84, 0.30, 0.14, size))
        return path
    }

    // MARK: Phoenix

    /// Two wings of three swept feathers each, raised behind the body.
    static func phoenixWings(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirror in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirror ? 1 - v : v }
            for (baseX, baseY, tipX, tipY, bow) in [(0.34, 0.44, 0.10, 0.16, 0.13),
                                                    (0.32, 0.50, 0.05, 0.34, 0.15),
                                                    (0.33, 0.56, 0.10, 0.52, 0.13)] {
                path.move(to: point(x(baseX), baseY))
                path.addQuadCurve(to: point(x(tipX), tipY), control: point(x(baseX - bow), baseY - bow * 0.7))
                path.addQuadCurve(to: point(x(baseX + 0.055), baseY + 0.07), control: point(x(tipX + 0.075), tipY + 0.11))
                path.closeSubpath()
            }
        }
        return path
    }

    /// The hooked beak under the eyes, and two talons at the chest's foot.
    static func phoenixBeakAndTalons(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.5, 0.27))
        path.addLine(to: point(0.565, 0.335))
        path.addLine(to: point(0.5, 0.40))
        path.addLine(to: point(0.435, 0.335))
        path.closeSubpath()
        path.addEllipse(in: rect(0.36, 0.80, 0.12, 0.055, size))
        path.addEllipse(in: rect(0.52, 0.80, 0.12, 0.055, size))
        return path
    }

    // MARK: Axolotl

    /// Three gill stalks fanning out of each side of the head, each ending
    /// in a rounded tip — the fronds that say axolotl.
    static func axolotlGills(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirror in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirror ? 1 - v : v }
            for (baseX, baseY, tipX, tipY) in [(0.22, 0.26, 0.06, 0.13),
                                               (0.18, 0.36, 0.02, 0.37),
                                               (0.21, 0.46, 0.05, 0.61)] {
                path.move(to: point(x(baseX), baseY))
                path.addQuadCurve(to: point(x(tipX), tipY), control: point(x(baseX - 0.10), baseY - 0.11))
                path.addQuadCurve(to: point(x(baseX + 0.03), baseY + 0.06), control: point(x(tipX + 0.07), tipY + 0.08))
                path.closeSubpath()
                path.addEllipse(in: CGRect(x: x(tipX) * size - 0.035 * size, y: tipY * size - 0.035 * size,
                                           width: 0.07 * size, height: 0.07 * size))
            }
        }
        return path
    }

    /// The wide content smile, and two little front feet.
    static func axolotlFeetAndSmile(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.36, 0.40))
        path.addQuadCurve(to: point(0.64, 0.40), control: point(0.5, 0.47))
        path.addQuadCurve(to: point(0.36, 0.40), control: point(0.5, 0.435))
        path.closeSubpath()
        path.addEllipse(in: rect(0.34, 0.82, 0.12, 0.05, size))
        path.addEllipse(in: rect(0.54, 0.82, 0.12, 0.05, size))
        return path
    }

    // MARK: Dog

    /// The long floppy ears that hang clear of the head, a wagging tail,
    /// and little paws resting at the base.
    static func dogEarsTail(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        // Floppy ears that arch over the crown and droop past the cheeks
        for mirrored in [false, true] {
            func x(_ value: CGFloat) -> CGFloat { mirrored ? 1 - value : value }
            path.move(to: point(x(0.35), 0.10))
            path.addCurve(to: point(x(0.06), 0.20), control1: point(x(0.26), 0.02), control2: point(x(0.12), 0.04))
            path.addCurve(to: point(x(0.14), 0.57), control1: point(x(0.01), 0.34), control2: point(x(0.04), 0.50))
            path.addCurve(to: point(x(0.28), 0.42), control1: point(x(0.22), 0.61), control2: point(x(0.28), 0.54))
            path.addCurve(to: point(x(0.35), 0.10), control1: point(x(0.28), 0.30), control2: point(x(0.30), 0.18))
            path.closeSubpath()
        }
        // Wagging tail, clear of the right ear
        path.move(to: point(0.74, 0.70))
        path.addQuadCurve(to: point(0.96, 0.44), control: point(0.96, 0.64))
        path.addQuadCurve(to: point(0.73, 0.74), control: point(0.88, 0.54))
        path.closeSubpath()
        // Front paws peeking out from under the chest
        path.addEllipse(in: rect(0.27, 0.85, 0.18, 0.10, size))
        path.addEllipse(in: rect(0.55, 0.85, 0.18, 0.10, size))
        return path
    }

    /// The soft pale muzzle over the head.
    static func dogSnout(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: rect(0.37, 0.28, 0.26, 0.19, size), transform: nil)
    }

    /// The rounded triangular nose, philtrum seam, and happy puppy split lips (:3).
    static func dogNoseAndMouth(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        // Soft rounded inverted triangle nose
        path.move(to: point(0.445, 0.325))
        path.addQuadCurve(to: point(0.555, 0.325), control: point(0.50, 0.318))
        path.addQuadCurve(to: point(0.512, 0.370), control: point(0.565, 0.355))
        path.addQuadCurve(to: point(0.488, 0.370), control: point(0.50, 0.373))
        path.addQuadCurve(to: point(0.445, 0.325), control: point(0.435, 0.355))
        path.closeSubpath()
        // Philtrum seam & smiling puppy jowls (:3)
        path.move(to: point(0.495, 0.368))
        path.addLine(to: point(0.505, 0.368))
        path.addLine(to: point(0.505, 0.395))
        path.addQuadCurve(to: point(0.560, 0.395), control: point(0.535, 0.425))
        path.addQuadCurve(to: point(0.535, 0.440), control: point(0.565, 0.415))
        path.addQuadCurve(to: point(0.505, 0.405), control: point(0.505, 0.425))
        path.addLine(to: point(0.495, 0.405))
        path.addQuadCurve(to: point(0.465, 0.440), control: point(0.495, 0.425))
        path.addQuadCurve(to: point(0.440, 0.395), control: point(0.435, 0.415))
        path.addQuadCurve(to: point(0.495, 0.395), control: point(0.465, 0.425))
        path.closeSubpath()
        return path
    }

    // MARK: Mouse

    /// The ears' soft inner half, and a long thin curling tail.
    static func mouseInnerEarsTail(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.19, 0.12, 0.18, 0.18, size))
        path.addEllipse(in: rect(0.63, 0.12, 0.18, 0.18, size))
        path.move(to: point(0.66, 0.72))
        path.addQuadCurve(to: point(0.97, 0.78), control: point(0.88, 0.64))
        path.addQuadCurve(to: point(0.68, 0.82), control: point(0.84, 0.88))
        path.closeSubpath()
        return path
    }

    // MARK: Capybara

    /// The peaceful little ears, sleepy nostrils and front paws.
    static func capybaraSnoutAndEars(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.18, 0.22, 0.10, 0.10, size))
        path.addEllipse(in: rect(0.72, 0.22, 0.10, 0.10, size))
        path.addEllipse(in: rect(0.42, 0.40, 0.05, 0.04, size))
        path.addEllipse(in: rect(0.53, 0.40, 0.05, 0.04, size))
        path.addEllipse(in: rect(0.30, 0.84, 0.16, 0.09, size))
        path.addEllipse(in: rect(0.54, 0.84, 0.16, 0.09, size))
        return path
    }

    /// The iconic onsen orange (yuzu/mandarin) with its tiny leaf sitting on its crown.
    static func capybaraOrange(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.43, 0.06, 0.14, 0.13, size))
        path.move(to: point(0.50, 0.06))
        path.addQuadCurve(to: point(0.56, 0.02), control: point(0.52, 0.02))
        path.addQuadCurve(to: point(0.50, 0.06), control: point(0.56, 0.06))
        path.closeSubpath()
        return path
    }

    // MARK: Dragon

    /// Two cute curved horns on the crown, folded wings behind and a spade tail.
    static func dragonWingsAndTail(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirrored in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirrored ? 1 - v : v }
            path.move(to: point(x(0.32), 0.16))
            path.addCurve(to: point(x(0.20), 0.04), control1: point(x(0.30), 0.10), control2: point(x(0.24), 0.05))
            path.addCurve(to: point(x(0.36), 0.18), control1: point(x(0.26), 0.08), control2: point(x(0.34), 0.12))
            path.closeSubpath()
        }
        for mirrored in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirrored ? 1 - v : v }
            path.move(to: point(x(0.24), 0.44))
            path.addQuadCurve(to: point(x(0.06), 0.36), control: point(x(0.12), 0.32))
            path.addQuadCurve(to: point(x(0.12), 0.52), control: point(x(0.08), 0.46))
            path.addQuadCurve(to: point(x(0.24), 0.56), control: point(x(0.16), 0.54))
            path.closeSubpath()
        }
        path.move(to: point(0.72, 0.70))
        path.addQuadCurve(to: point(0.94, 0.54), control: point(0.92, 0.68))
        path.addLine(to: point(0.97, 0.50))
        path.addLine(to: point(0.91, 0.49))
        path.addQuadCurve(to: point(0.70, 0.76), control: point(0.86, 0.62))
        path.closeSubpath()
        return path
    }

    /// The soft lighter underbelly and snout for the dragon.
    static func dragonHornsAndSnout(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.38, 0.28, 0.24, 0.16, size))
        path.addEllipse(in: rect(0.32, 0.52, 0.36, 0.32, size))
        return path
    }

    // MARK: Frog

    /// The pale throat patch and wide webbed front feet.
    static func frogThroatAndPaws(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.32, 0.32, 0.36, 0.26, size))
        path.addEllipse(in: rect(0.16, 0.82, 0.18, 0.08, size))
        path.addEllipse(in: rect(0.66, 0.82, 0.18, 0.08, size))
        return path
    }

    // MARK: Devourer

    /// The wide open mouth that is the glutton's whole character.
    static func devourerMouth(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.32, 0.60))
        path.addQuadCurve(to: point(0.68, 0.60), control: point(0.5, 0.84))
        path.addQuadCurve(to: point(0.32, 0.60), control: point(0.5, 0.68))
        path.closeSubpath()
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

    // MARK: Swan

    /// Proud arched swan wings and upturned tail feathers floating behind the body.
    static func swanWings(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirror in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirror ? 1 - v : v }
            // Arched wing with 3 layered primary and secondary flight feathers
            path.move(to: point(x(0.30), 0.66))
            path.addCurve(to: point(x(0.10), 0.34), control1: point(x(0.24), 0.58), control2: point(x(0.12), 0.46))
            path.addQuadCurve(to: point(x(0.16), 0.43), control: point(x(0.12), 0.39))
            path.addQuadCurve(to: point(x(0.13), 0.48), control: point(x(0.14), 0.45))
            path.addQuadCurve(to: point(x(0.20), 0.54), control: point(x(0.15), 0.51))
            path.addQuadCurve(to: point(x(0.17), 0.59), control: point(x(0.18), 0.56))
            path.addQuadCurve(to: point(x(0.28), 0.68), control: point(x(0.20), 0.64))
            path.closeSubpath()

            // Upturned rear tail feather peeking behind waterline
            path.move(to: point(x(0.38), 0.82))
            path.addQuadCurve(to: point(x(0.44), 0.92), control: point(x(0.39), 0.88))
            path.addQuadCurve(to: point(x(0.50), 0.85), control: point(x(0.47), 0.90))
            path.closeSubpath()
        }
        return path
    }

    /// Distinctive amber waterfowl bill.
    static func swanBeak(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.45, 0.25))
        path.addQuadCurve(to: point(0.50, 0.34), control: point(0.46, 0.31))
        path.addQuadCurve(to: point(0.55, 0.25), control: point(0.54, 0.31))
        path.closeSubpath()
        return path
    }

    /// The iconic black mask (lores) and basal knob between the eyes and bill.
    static func swanMask(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.47, 0.18, 0.06, 0.05, size))
        path.move(to: point(0.44, 0.25))
        path.addLine(to: point(0.41, 0.22))
        path.addLine(to: point(0.45, 0.21))
        path.addLine(to: point(0.50, 0.23))
        path.addLine(to: point(0.55, 0.21))
        path.addLine(to: point(0.59, 0.22))
        path.addLine(to: point(0.56, 0.25))
        path.closeSubpath()
        return path
    }

    /// Odette's royal crown resting delicately on the head.
    static func swanTiara(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.41, 0.11))
        path.addLine(to: point(0.43, 0.04))
        path.addLine(to: point(0.47, 0.08))
        path.addLine(to: point(0.50, 0.02))
        path.addLine(to: point(0.53, 0.08))
        path.addLine(to: point(0.57, 0.04))
        path.addLine(to: point(0.59, 0.11))
        path.addQuadCurve(to: point(0.41, 0.11), control: point(0.50, 0.13))
        path.closeSubpath()
        return path
    }

    /// Delicate plumage scallops along the folded breast.
    static func swanChestDetails(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirror in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirror ? 1 - v : v }
            path.move(to: point(x(0.33), 0.55))
            path.addCurve(to: point(x(0.38), 0.72), control1: point(x(0.31), 0.62), control2: point(x(0.35), 0.68))
            path.addQuadCurve(to: point(x(0.35), 0.56), control: point(x(0.33), 0.64))
            path.closeSubpath()
        }
        return path
    }

    // MARK: Ballerina

    /// Classical arms arched in fifth position (en haut / couronne) framing the head.
    static func ballerinaArmsEnHaut(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for mirror in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { mirror ? 1 - v : v }
            path.move(to: point(x(0.38), 0.42))
            path.addCurve(to: point(x(0.44), 0.03), control1: point(x(0.22), 0.26), control2: point(x(0.28), 0.08))
            path.addCurve(to: point(x(0.40), 0.42), control1: point(x(0.32), 0.09), control2: point(x(0.26), 0.27))
            path.closeSubpath()
        }
        return path
    }

    /// Criss-crossed satin ribbons winding up the ballerina's ankles.
    static func ballerinaPointesRibbons(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        // Left leg ribbons
        path.move(to: point(0.42, 0.86))
        path.addLine(to: point(0.49, 0.81))
        path.addLine(to: point(0.49, 0.83))
        path.addLine(to: point(0.42, 0.88))
        path.closeSubpath()
        path.move(to: point(0.49, 0.86))
        path.addLine(to: point(0.42, 0.81))
        path.addLine(to: point(0.42, 0.83))
        path.addLine(to: point(0.49, 0.88))
        path.closeSubpath()
        // Right leg ribbons
        path.move(to: point(0.51, 0.86))
        path.addLine(to: point(0.58, 0.81))
        path.addLine(to: point(0.58, 0.83))
        path.addLine(to: point(0.51, 0.88))
        path.closeSubpath()
        path.move(to: point(0.58, 0.86))
        path.addLine(to: point(0.51, 0.81))
        path.addLine(to: point(0.51, 0.83))
        path.addLine(to: point(0.58, 0.88))
        path.closeSubpath()
        return path
    }

    /// Fitted velvet bodice with sweetheart neckline.
    static func ballerinaBodice(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.40 * size, y: 0.46 * size))
        path.addLine(to: CGPoint(x: 0.60 * size, y: 0.46 * size))
        path.addLine(to: CGPoint(x: 0.56 * size, y: 0.60 * size))
        path.addLine(to: CGPoint(x: 0.44 * size, y: 0.60 * size))
        path.closeSubpath()
        return path
    }

    // MARK: Danseur

    /// Gold embroidered V-neck collar and royal buttons.
    static func danseurTunicTrim(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.36, 0.42))
        path.addLine(to: point(0.50, 0.54))
        path.addLine(to: point(0.64, 0.42))
        path.addLine(to: point(0.60, 0.42))
        path.addLine(to: point(0.50, 0.51))
        path.addLine(to: point(0.40, 0.42))
        path.closeSubpath()
        path.addEllipse(in: rect(0.48, 0.56, 0.04, 0.03, size))
        path.addEllipse(in: rect(0.48, 0.61, 0.04, 0.03, size))
        return path
    }

    // MARK: Contemporary

    /// Diagonal fluid draped sash.
    static func contemporarySash(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.34 * size, y: 0.46 * size))
        path.addQuadCurve(to: CGPoint(x: 0.72 * size, y: 0.74 * size), control: CGPoint(x: 0.54 * size, y: 0.58 * size))
        path.addLine(to: CGPoint(x: 0.64 * size, y: 0.78 * size))
        path.addQuadCurve(to: CGPoint(x: 0.28 * size, y: 0.50 * size), control: CGPoint(x: 0.46 * size, y: 0.62 * size))
        path.closeSubpath()
        return path
    }

    // MARK: Kitsune

    /// How its tails are held: at rest, swaying, streaming behind it as it
    /// trots, fanned out in a flourish, or curled round its paws asleep.
    enum TailsPose { case rest, sway, stream, fan, curl }

    /// One tail at first, one more every six levels, nine at most, as the
    /// old stories tell of a fox that grows wiser with the years.
    static func kitsuneTailCount(level: Int) -> Int {
        min(9, 1 + max(0, level) / 6)
    }

    /// Its tails, each a plump brush from behind its haunch. The paths of
    /// every pose for one count share their commands, so a pose morphs into
    /// the next.
    static func kitsuneTails(count: Int, pose: TailsPose, tips: Bool, size: CGFloat) -> CGPath {
        let count = max(1, count)
        let base = CGPoint(x: 0.60, y: 0.82)
        let (heading, fan): (CGFloat, CGFloat)
        let span = CGFloat(count - 1)
        switch pose {
        case .rest: (heading, fan) = (35, count > 1 ? min(10, 60 / span) : 0)
        case .sway: (heading, fan) = (50, count > 1 ? min(12, 70 / span) : 0)
        case .stream: (heading, fan) = (12, count > 1 ? min(6, 40 / span) : 0)
        case .fan: (heading, fan) = (72, count > 1 ? min(24, 112 / span) : 0)
        case .curl: (heading, fan) = (186, count > 1 ? min(4, 24 / span) : 0)
        }
        let length: CGFloat = pose == .curl ? 0.50 : 0.40
        let width = max(0.12, 0.20 - 0.01 * span)
        let path = CGMutablePath()
        for index in 0..<count {
            let degrees = heading + fan * (CGFloat(index) - span / 2)
            if tips {
                brushTip(into: path, from: base, degrees: degrees, length: length, width: width, size: size)
            } else {
                brush(into: path, from: base, degrees: degrees, length: length, width: width, size: size)
            }
        }
        return path
    }

    /// Both tall ears, the inside shaded when `inner`.
    static func kitsuneEars(_ pose: EarPose, inner: Bool, size: CGFloat) -> CGPath {
        let tip: (CGFloat, CGFloat)
        switch pose {
        case .up: tip = (0.22, 0.04)
        case .twitch: tip = (0.12, 0.10)
        case .droop: tip = (0.05, 0.30)
        }
        let path = CGMutablePath()
        for mirrored in [false, true] {
            func x(_ value: CGFloat) -> CGFloat { mirrored ? 1 - value : value }
            var corners: [CGPoint] = [CGPoint(x: x(0.21), y: 0.38), CGPoint(x: x(tip.0), y: tip.1),
                                      CGPoint(x: x(0.44), y: 0.25)]
            if inner {
                let middle = CGPoint(x: (corners[0].x + corners[1].x + corners[2].x) / 3,
                                     y: (corners[0].y + corners[1].y + corners[2].y) / 3)
                corners = corners.map { CGPoint(x: middle.x + ($0.x - middle.x) * 0.55, y: middle.y + ($0.y - middle.y) * 0.55) }
            }
            let scaled = corners.map { CGPoint(x: $0.x * size, y: $0.y * size) }
            path.move(to: scaled[0])
            path.addLine(to: lerp(scaled[0], scaled[1], 0.86))
            path.addQuadCurve(to: lerp(scaled[2], scaled[1], 0.86), control: scaled[1])
            path.addLine(to: scaled[2])
            path.closeSubpath()
        }
        return path
    }

    /// The pale cheeks of the mask and the bib down its chest.
    static func kitsuneMuzzleAndBib(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.20, 0.50))
        path.addQuadCurve(to: point(0.50, 0.625), control: point(0.34, 0.62))
        path.addQuadCurve(to: point(0.80, 0.50), control: point(0.66, 0.62))
        path.addQuadCurve(to: point(0.50, 0.48), control: point(0.64, 0.45))
        path.addQuadCurve(to: point(0.20, 0.50), control: point(0.36, 0.45))
        path.closeSubpath()
        path.addEllipse(in: rect(0.39, 0.60, 0.22, 0.26, size))
        return path
    }

    static func kitsuneNose(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: rect(0.472, 0.562, 0.056, 0.036, size), transform: nil)
    }

    /// The flame-shaped mark on its brow.
    static func kitsuneMark(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.25))
        path.addQuadCurve(to: point(0.525, 0.325), control: point(0.535, 0.29))
        path.addQuadCurve(to: point(0.50, 0.35), control: point(0.52, 0.345))
        path.addQuadCurve(to: point(0.475, 0.325), control: point(0.48, 0.345))
        path.addQuadCurve(to: point(0.50, 0.25), control: point(0.465, 0.29))
        path.closeSubpath()
        return path
    }

    /// Two wisps of foxfire floating beside its head.
    static func foxfire(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (x, y, scale) in [(0.10, 0.34, 1.0), (0.90, 0.28, 0.8)] as [(CGFloat, CGFloat, CGFloat)] {
            func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
                CGPoint(x: (x + dx * scale) * size, y: (y + dy * scale) * size)
            }
            path.move(to: point(0, -0.10))
            path.addQuadCurve(to: point(0.055, 0.02), control: point(0.06, -0.04))
            path.addQuadCurve(to: point(0, 0.07), control: point(0.05, 0.07))
            path.addQuadCurve(to: point(-0.055, 0.02), control: point(-0.05, 0.07))
            path.addQuadCurve(to: point(0, -0.10), control: point(-0.04, -0.03))
            path.closeSubpath()
        }
        return path
    }

    // MARK: Penguin

    /// How its flippers are held: at its sides, both up in a flap, one up
    /// at a time as it waddles, or tucked in tight asleep.
    enum FlipperPose { case rest, up, leftUp, rightUp, tucked }

    static func penguinFlippers(_ pose: FlipperPose, size: CGFloat) -> CGPath {
        let rest: CGFloat = -112, up: CGFloat = 148, tucked: CGFloat = -98
        let left: CGFloat, right: CGFloat
        switch pose {
        case .rest: (left, right) = (rest, rest)
        case .up: (left, right) = (up, up)
        case .leftUp: (left, right) = (up, rest)
        case .rightUp: (left, right) = (rest, up)
        case .tucked: (left, right) = (tucked, tucked)
        }
        let path = CGMutablePath()
        brush(into: path, from: CGPoint(x: 0.27, y: 0.44), degrees: left, length: 0.30, width: 0.11, size: size)
        brush(into: path, from: CGPoint(x: 0.73, y: 0.44), degrees: 180 - right, length: 0.30, width: 0.11, size: size)
        return path
    }

    /// The white face and belly, one piece, the eyes on its two lobes.
    static func penguinBelly(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.25))
        path.addCurve(to: point(0.66, 0.35), control1: point(0.56, 0.18), control2: point(0.68, 0.22))
        path.addCurve(to: point(0.67, 0.60), control1: point(0.64, 0.43), control2: point(0.69, 0.50))
        path.addCurve(to: point(0.50, 0.90), control1: point(0.69, 0.78), control2: point(0.62, 0.90))
        path.addCurve(to: point(0.33, 0.60), control1: point(0.38, 0.90), control2: point(0.31, 0.78))
        path.addCurve(to: point(0.34, 0.35), control1: point(0.31, 0.50), control2: point(0.36, 0.43))
        path.addCurve(to: point(0.50, 0.25), control1: point(0.32, 0.22), control2: point(0.44, 0.18))
        path.closeSubpath()
        return path
    }

    /// Its little beak and two webbed feet, in orange.
    static func penguinBeakAndFeet(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.455, 0.37))
        path.addQuadCurve(to: point(0.545, 0.37), control: point(0.50, 0.355))
        path.addQuadCurve(to: point(0.50, 0.43), control: point(0.53, 0.41))
        path.addQuadCurve(to: point(0.455, 0.37), control: point(0.47, 0.41))
        path.closeSubpath()
        path.addEllipse(in: rect(0.32, 0.87, 0.15, 0.07, size))
        path.addEllipse(in: rect(0.53, 0.87, 0.15, 0.07, size))
        return path
    }

    /// An emperor's golden patches either side of its head.
    static func penguinCheeks(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect(0.255, 0.26, 0.075, 0.12, size))
        path.addEllipse(in: rect(0.67, 0.26, 0.075, 0.12, size))
        return path
    }

    // MARK: Brushes

    /// A teardrop from `base` toward `degrees` (0 to the right, 90 straight
    /// up), as long as `length` and as wide as `width`, in shares of `size`.
    private static func brush(into path: CGMutablePath, from base: CGPoint, degrees: CGFloat, length: CGFloat,
                              width: CGFloat, size: CGFloat) {
        let (along, across) = axes(degrees)
        func point(_ forward: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: (base.x + along.x * forward + across.x * side) * size,
                    y: (base.y + along.y * forward + across.y * side) * size)
        }
        path.move(to: point(0, width * 0.32))
        path.addQuadCurve(to: point(length, 0), control: point(length * 0.55, width))
        path.addQuadCurve(to: point(0, -width * 0.32), control: point(length * 0.55, -width))
        path.closeSubpath()
    }

    /// The pale end of the same brush.
    private static func brushTip(into path: CGMutablePath, from base: CGPoint, degrees: CGFloat, length: CGFloat,
                                 width: CGFloat, size: CGFloat) {
        let (along, across) = axes(degrees)
        func point(_ forward: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: (base.x + along.x * forward + across.x * side) * size,
                    y: (base.y + along.y * forward + across.y * side) * size)
        }
        path.move(to: point(length * 0.70, width * 0.58))
        path.addQuadCurve(to: point(length, 0), control: point(length * 0.92, width * 0.45))
        path.addQuadCurve(to: point(length * 0.70, -width * 0.58), control: point(length * 0.92, -width * 0.45))
        path.addQuadCurve(to: point(length * 0.70, width * 0.58), control: point(length * 0.64, 0))
        path.closeSubpath()
    }

    /// Unit vectors along and across a heading, y growing downward.
    private static func axes(_ degrees: CGFloat) -> (along: CGPoint, across: CGPoint) {
        let angle = degrees * .pi / 180
        return (CGPoint(x: cos(angle), y: -sin(angle)), CGPoint(x: sin(angle), y: cos(angle)))
    }
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
