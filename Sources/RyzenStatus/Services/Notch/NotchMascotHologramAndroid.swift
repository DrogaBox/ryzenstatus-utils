// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The hologram and the android, drawn like every other figure: vector
/// paths in a square of `size` points from its top left corner, y growing
/// downward. The palette fills the body; hair, outfit, visor, joints, gauge
/// and light are layers of their own over and under it, in colours worked
/// out from the palette by `NotchMascotSignalColors`.
extension NotchMascotCreatures {
    /// How the two hold their arms: one hand on the hip and the other down,
    /// waving one way or the other, both thrown up, or folded asleep. Every
    /// pose is built with the same commands, so one morphs into the next.
    enum ArmsPose: CaseIterable { case rest, wave, waveOut, up, folded }

    // MARK: Hologram

    /// A chibi idol of light: a big round head, a neck, a little dress that
    /// flares at the hem and two slim legs.
    static func hologramBody(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(hologramSkin(size: size))
        path.addPath(hologramDress(size: size))
        return path
    }

    /// Her face, neck and legs, lit in her own light whatever the palette.
    static func hologramSkin(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.325, 0.135, 0.35, 0.32, size))
        path.addRect(box(0.477, 0.44, 0.046, 0.05, size))
        path.addPath(hologramLegs(size: size))
        return path
    }

    /// Her dress, from narrow shoulders to a flared, rounded hem.
    static func hologramDress(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.425, 0.475))
        path.addLine(to: point(0.575, 0.475))
        path.addQuadCurve(to: point(0.612, 0.51), control: point(0.607, 0.476))
        path.addLine(to: point(0.574, 0.585))
        path.addCurve(to: point(0.668, 0.712), control1: point(0.60, 0.62), control2: point(0.652, 0.665))
        path.addQuadCurve(to: point(0.332, 0.712), control: point(0.50, 0.752))
        path.addCurve(to: point(0.426, 0.585), control1: point(0.348, 0.665), control2: point(0.40, 0.62))
        path.addLine(to: point(0.388, 0.51))
        path.addQuadCurve(to: point(0.425, 0.475), control: point(0.393, 0.476))
        path.closeSubpath()
        return path
    }

    /// Her legs, boots and all.
    static func hologramLegs(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for x in [0.432, 0.523] as [CGFloat] {
            path.addRoundedRect(in: box(x, 0.69, 0.045, 0.19, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        }
        path.addPath(hologramBoots(size: size))
        return path
    }

    /// Two little boots, a toe each.
    static func hologramBoots(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (x, toe) in [(0.424, -0.012), (0.515, 0.012)] as [(CGFloat, CGFloat)] {
            path.addRoundedRect(in: box(x, 0.80, 0.061, 0.07, size), cornerWidth: 0.022 * size, cornerHeight: 0.022 * size)
            path.addRoundedRect(in: box(x + toe, 0.85, 0.061, 0.045, size), cornerWidth: 0.02 * size, cornerHeight: 0.02 * size)
        }
        return path
    }

    /// The hair behind her head: a round crown falling to the shoulders and
    /// two long twin tails that swing out and curl away at the tips.
    static func hologramHairBack(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.305, 0.112, 0.39, 0.37, size))
        for mirrored in [false, true] {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (mirrored ? 1 - x : x) * size, y: y * size) }
            path.move(to: point(0.37, 0.17))
            path.addCurve(to: point(0.175, 0.43), control1: point(0.25, 0.155), control2: point(0.16, 0.28))
            path.addCurve(to: point(0.14, 0.77), control1: point(0.19, 0.57), control2: point(0.10, 0.66))
            path.addCurve(to: point(0.265, 0.47), control1: point(0.22, 0.68), control2: point(0.27, 0.58))
            path.addCurve(to: point(0.345, 0.25), control1: point(0.26, 0.37), control2: point(0.29, 0.28))
            path.closeSubpath()
        }
        return path
    }

    /// Her fringe in pointed locks, a lock down each cheek and, unless a hat
    /// sits on her head, the one strand that will not lie flat.
    static func hologramHair(ahoge: Bool = true, size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.318, 0.33))
        path.addCurve(to: point(0.50, 0.11), control1: point(0.30, 0.185), control2: point(0.39, 0.11))
        path.addCurve(to: point(0.682, 0.33), control1: point(0.61, 0.11), control2: point(0.70, 0.185))
        // The lock down her right cheek, as seen on screen.
        path.addCurve(to: point(0.668, 0.47), control1: point(0.692, 0.40), control2: point(0.684, 0.44))
        path.addCurve(to: point(0.642, 0.29), control1: point(0.646, 0.42), control2: point(0.636, 0.36))
        // The fringe in soft, rounded locks, right to left, parted a little
        // off the middle.
        path.addQuadCurve(to: point(0.585, 0.198), control: point(0.636, 0.215))
        path.addQuadCurve(to: point(0.528, 0.248), control: point(0.57, 0.245))
        path.addQuadCurve(to: point(0.505, 0.205), control: point(0.515, 0.225))
        path.addQuadCurve(to: point(0.452, 0.25), control: point(0.49, 0.248))
        path.addQuadCurve(to: point(0.41, 0.202), control: point(0.425, 0.245))
        path.addQuadCurve(to: point(0.358, 0.29), control: point(0.37, 0.215))
        // The lock down her left cheek.
        path.addCurve(to: point(0.332, 0.47), control1: point(0.364, 0.36), control2: point(0.354, 0.42))
        path.addCurve(to: point(0.318, 0.33), control1: point(0.316, 0.44), control2: point(0.308, 0.40))
        path.closeSubpath()
        if ahoge {
            path.move(to: point(0.488, 0.125))
            path.addQuadCurve(to: point(0.545, 0.04), control: point(0.462, 0.058))
            path.addQuadCurve(to: point(0.512, 0.122), control: point(0.50, 0.07))
            path.closeSubpath()
        }
        return path
    }

    /// The ring of shine round her crown, and a glint down each tail.
    static func hologramHairShine(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.385, 0.158))
        path.addQuadCurve(to: point(0.60, 0.15), control: point(0.49, 0.112))
        path.addQuadCurve(to: point(0.592, 0.163), control: point(0.60, 0.158))
        path.addQuadCurve(to: point(0.393, 0.17), control: point(0.49, 0.13))
        path.addQuadCurve(to: point(0.385, 0.158), control: point(0.383, 0.166))
        path.closeSubpath()
        for mirrored in [false, true] {
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(mirrored ? 1 - x : x, y) }
            path.move(to: at(0.20, 0.33))
            path.addQuadCurve(to: at(0.19, 0.50), control: at(0.175, 0.41))
            path.addQuadCurve(to: at(0.208, 0.34), control: at(0.192, 0.41))
            path.closeSubpath()
        }
        return path
    }

    /// A round collar, the band of light round her hem and her boot cuffs.
    static func hologramTrim(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.addEllipse(in: box(0.418, 0.462, 0.084, 0.05, size))
        path.addEllipse(in: box(0.498, 0.462, 0.084, 0.05, size))
        path.move(to: point(0.345, 0.69))
        path.addQuadCurve(to: point(0.655, 0.69), control: point(0.50, 0.728))
        path.addLine(to: point(0.668, 0.712))
        path.addQuadCurve(to: point(0.332, 0.712), control: point(0.50, 0.752))
        path.closeSubpath()
        for x in [0.424, 0.515] as [CGFloat] {
            path.addRoundedRect(in: box(x - 0.004, 0.792, 0.069, 0.024, size), cornerWidth: 0.012 * size, cornerHeight: 0.012 * size)
        }
        return path
    }

    /// A bow at her collar, a sash round her waist and the clips that hold
    /// her twin tails.
    static func hologramRibbons(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(polygonPath([(0.50, 0.512), (0.455, 0.49), (0.46, 0.54)], size: size))
        path.addPath(polygonPath([(0.50, 0.512), (0.545, 0.49), (0.54, 0.54)], size: size))
        path.addEllipse(in: box(0.486, 0.498, 0.028, 0.028, size))
        path.addRoundedRect(in: box(0.425, 0.578, 0.15, 0.018, size), cornerWidth: 0.009 * size, cornerHeight: 0.009 * size)
        for x in [0.335, 0.665] as [CGFloat] {
            path.addEllipse(in: box(x - 0.03, 0.172, 0.06, 0.06, size))
        }
        return path
    }

    /// Fine lines of light across her, faint enough to read as a glow.
    static func hologramScanlines(size: CGFloat) -> CGPath {
        let stripes = CGMutablePath()
        var y: CGFloat = 0.10
        while y < 0.90 {
            stripes.addRect(box(0, y, 1, 0.007, size))
            y += 0.028
        }
        return stripes.intersection(hologramBody(size: size))
    }

    /// All of her, hair and dress, for the colour fringes and the glitches
    /// of the projection.
    static func hologramSilhouette(size: CGFloat) -> CGPath {
        let figure = CGMutablePath()
        figure.addPath(hologramBody(size: size))
        figure.addPath(hologramHairBack(size: size))
        figure.addPath(hologramHair(size: size))
        return figure.normalized()
    }

    /// Slices of her shifted aside, shown as the projection glitches.
    static func hologramGlitch(size: CGFloat) -> CGPath {
        let figure = hologramSilhouette(size: size)
        let path = CGMutablePath()
        for (y, height, shift) in [(0.30, 0.03, -0.045), (0.55, 0.022, 0.06), (0.64, 0.014, -0.03)] as [(CGFloat, CGFloat, CGFloat)] {
            let slice = figure.intersection(CGPath(rect: box(0, y, 1, height, size), transform: nil))
            path.addPath(slice, transform: CGAffineTransform(translationX: shift * size, y: 0))
        }
        return path
    }

    /// The cone of light from the projector up to her head.
    static func hologramBeam(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.40, 0.915))
        path.addLine(to: point(0.60, 0.915))
        path.addLine(to: point(0.80, 0.20))
        path.addQuadCurve(to: point(0.20, 0.20), control: point(0.50, 0.10))
        path.closeSubpath()
        return path
    }

    /// The disc of light she stands on.
    static func hologramPlatform(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: box(0.315, 0.872, 0.37, 0.046, size), transform: nil)
    }

    /// The little projector under her, a puck with a lens on top.
    static func hologramProjector(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.40, 0.91, 0.20, 0.06, size), cornerWidth: 0.05 * size, cornerHeight: 0.03 * size)
        return path
    }

    /// The lens on the projector's top, and the light round its side.
    static func hologramLens(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: box(0.415, 0.904, 0.17, 0.024, size))
        path.addRoundedRect(in: box(0.42, 0.946, 0.16, 0.009, size), cornerWidth: 0.0045 * size, cornerHeight: 0.0045 * size)
        return path
    }

    static func hologramArms(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let left = CGPoint(x: 0.405, y: 0.497), right = CGPoint(x: 0.595, y: 0.497)
        let (leftElbow, leftHand, rightElbow, rightHand): (CGPoint, CGPoint, CGPoint, CGPoint)
        switch pose {
        case .rest: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.338, y: 0.553), .init(x: 0.418, y: 0.592),
                                                                    .init(x: 0.636, y: 0.575), .init(x: 0.66, y: 0.648))
        case .wave: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.338, y: 0.553), .init(x: 0.418, y: 0.592),
                                                                    .init(x: 0.70, y: 0.46), .init(x: 0.735, y: 0.36))
        case .waveOut: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.338, y: 0.553), .init(x: 0.418, y: 0.592),
                                                                       .init(x: 0.71, y: 0.465), .init(x: 0.80, y: 0.39))
        case .up: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.32, y: 0.43), .init(x: 0.285, y: 0.33),
                                                                  .init(x: 0.68, y: 0.43), .init(x: 0.715, y: 0.33))
        case .folded: (leftElbow, leftHand, rightElbow, rightHand) = (.init(x: 0.375, y: 0.575), .init(x: 0.55, y: 0.548),
                                                                      .init(x: 0.625, y: 0.575), .init(x: 0.45, y: 0.548))
        }
        let path = CGMutablePath()
        limb(into: path, [left, leftElbow, leftHand], width: 0.046, hand: 0.026, size: size)
        limb(into: path, [right, rightElbow, rightHand], width: 0.046, hand: 0.026, size: size)
        return path
    }

    // MARK: Android

    /// A rounded helmet, an egg of a chest and two tapered legs that end a
    /// hand above the floor.
    static func androidBody(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(androidHelmet(size: size))
        path.addPath(androidTorso(size: size))
        path.addPath(androidLegs(size: size))
        return path
    }

    static func androidHelmet(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.092))
        path.addCurve(to: point(0.705, 0.26), control1: point(0.655, 0.092), control2: point(0.705, 0.16))
        path.addCurve(to: point(0.50, 0.432), control1: point(0.705, 0.385), control2: point(0.625, 0.432))
        path.addCurve(to: point(0.295, 0.26), control1: point(0.375, 0.432), control2: point(0.295, 0.385))
        path.addCurve(to: point(0.50, 0.092), control1: point(0.295, 0.16), control2: point(0.345, 0.092))
        path.closeSubpath()
        return path
    }

    static func androidTorso(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.458))
        path.addCurve(to: point(0.652, 0.54), control1: point(0.61, 0.458), control2: point(0.652, 0.478))
        path.addCurve(to: point(0.50, 0.718), control1: point(0.652, 0.645), control2: point(0.585, 0.718))
        path.addCurve(to: point(0.348, 0.54), control1: point(0.415, 0.718), control2: point(0.348, 0.645))
        path.addCurve(to: point(0.50, 0.458), control1: point(0.348, 0.478), control2: point(0.39, 0.458))
        path.closeSubpath()
        return path
    }

    /// Two legs tapering to a rounded point.
    static func androidLegs(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for mirrored in [false, true] {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (mirrored ? 1 - x : x) * size, y: y * size) }
            path.move(to: point(0.418, 0.685))
            path.addLine(to: point(0.492, 0.685))
            path.addCurve(to: point(0.474, 0.85), control1: point(0.494, 0.76), control2: point(0.484, 0.815))
            path.addQuadCurve(to: point(0.442, 0.85), control: point(0.458, 0.874))
            path.addCurve(to: point(0.418, 0.685), control1: point(0.43, 0.81), control2: point(0.414, 0.75))
            path.closeSubpath()
        }
        return path
    }

    /// The glass face screen its eyes light up on.
    static func androidVisor(size: CGFloat) -> CGPath {
        CGPath(roundedRect: box(0.33, 0.165, 0.34, 0.212, size), cornerWidth: 0.1 * size, cornerHeight: 0.095 * size,
               transform: nil)
    }

    /// The light the glass catches along its top.
    static func androidVisorGloss(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.37, 0.188))
        path.addQuadCurve(to: point(0.63, 0.188), control: point(0.50, 0.168))
        path.addQuadCurve(to: point(0.62, 0.198), control: point(0.63, 0.196))
        path.addQuadCurve(to: point(0.38, 0.198), control: point(0.50, 0.182))
        path.addQuadCurve(to: point(0.37, 0.188), control: point(0.37, 0.196))
        path.closeSubpath()
        return path
    }

    /// A bright band that sweeps across the glass as it scans.
    static func androidVisorSweep(size: CGFloat) -> CGPath {
        polygonPath([(0.44, 0.16), (0.49, 0.16), (0.44, 0.39), (0.39, 0.39)], size: size)
    }

    /// The dark parts between the shell: ear pods and the antenna on one,
    /// neck and shoulder joints, and the soles of its feet.
    static func androidJoints(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: box(0.262, 0.20, 0.056, 0.12, size), cornerWidth: 0.026 * size, cornerHeight: 0.03 * size)
        path.addRoundedRect(in: box(0.682, 0.20, 0.056, 0.12, size), cornerWidth: 0.026 * size, cornerHeight: 0.03 * size)
        path.addPath(polygonPath([(0.712, 0.205), (0.742, 0.105), (0.752, 0.108), (0.726, 0.21)], size: size))
        path.addRoundedRect(in: box(0.462, 0.418, 0.076, 0.05, size), cornerWidth: 0.015 * size, cornerHeight: 0.015 * size)
        path.addEllipse(in: box(0.317, 0.468, 0.066, 0.066, size))
        path.addEllipse(in: box(0.617, 0.468, 0.066, 0.066, size))
        path.addPath(androidLegs(size: size).intersection(CGPath(rect: box(0, 0.80, 1, 0.1, size), transform: nil)))
        return path
    }

    /// Its little lights: the rings in its ear pods, the antenna's tip and
    /// the studs of its shoulders.
    static func androidLights(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for x in [0.29, 0.71] as [CGFloat] {
            path.addRoundedRect(in: box(x - 0.012, 0.228, 0.024, 0.064, size), cornerWidth: 0.012 * size, cornerHeight: 0.012 * size)
        }
        path.addEllipse(in: box(0.728, 0.075, 0.042, 0.042, size))
        path.addEllipse(in: box(0.338, 0.489, 0.024, 0.024, size))
        path.addEllipse(in: box(0.638, 0.489, 0.024, 0.024, size))
        return path
    }

    /// Panel lines on its shell, to be stroked.
    static func androidSeams(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.40, 0.11))
        path.addQuadCurve(to: point(0.60, 0.11), control: point(0.50, 0.135))
        path.move(to: point(0.395, 0.48))
        path.addQuadCurve(to: point(0.41, 0.67), control: point(0.375, 0.58))
        path.move(to: point(0.605, 0.48))
        path.addQuadCurve(to: point(0.59, 0.67), control: point(0.625, 0.58))
        return path
    }

    /// Where its shell catches the light: down the side of its helmet and
    /// across its chest.
    static func androidSheen(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        path.move(to: point(0.315, 0.30))
        path.addQuadCurve(to: point(0.36, 0.385), control: point(0.318, 0.36))
        path.addQuadCurve(to: point(0.325, 0.30), control: point(0.33, 0.35))
        path.closeSubpath()
        path.move(to: point(0.40, 0.50))
        path.addQuadCurve(to: point(0.47, 0.476), control: point(0.42, 0.478))
        path.addQuadCurve(to: point(0.41, 0.508), control: point(0.43, 0.49))
        path.closeSubpath()
        path.move(to: point(0.365, 0.58))
        path.addQuadCurve(to: point(0.39, 0.66), control: point(0.366, 0.63))
        path.addQuadCurve(to: point(0.375, 0.58), control: point(0.375, 0.625))
        path.closeSubpath()
        return path
    }

    /// The middle of its heart, where the load gauge sits.
    static let androidCoreCenter = CGPoint(x: 0.50, y: 0.578)
    static let androidGaugeRadii: (inner: CGFloat, outer: CGFloat) = (0.036, 0.057)

    /// The socket of the load gauge at its heart.
    static func androidGauge(size: CGFloat) -> CGPath {
        let c = androidCoreCenter
        return CGPath(ellipseIn: box(c.x - 0.07, c.y - 0.07, 0.14, 0.14, size), transform: nil)
    }

    /// The gauge's ring, all of it, for the dim track under the lit part.
    static func androidGaugeTrack(size: CGFloat) -> CGPath { androidRing(level: 4, size: size) }

    /// The gauge's lit quarters, clockwise from the top, `level` of four.
    static func androidGaugeCells(level: Int, size: CGFloat) -> CGPath { androidRing(level: level, size: size) }

    /// The light at the very middle of the gauge.
    static func androidCore(size: CGFloat) -> CGPath {
        let c = androidCoreCenter
        return CGPath(ellipseIn: box(c.x - 0.02, c.y - 0.02, 0.04, 0.04, size), transform: nil)
    }

    private static func androidRing(level: Int, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: androidCoreCenter.x * size, y: androidCoreCenter.y * size)
        let gap = CGFloat.pi / 14
        for quarter in 0..<4 {
            let start = -CGFloat.pi / 2 + CGFloat(quarter) * .pi / 2 + gap / 2
            // An unlit quarter has no sweep, so every level morphs into the next.
            let sweep = quarter < level ? CGFloat.pi / 2 - gap : 0
            arc(into: path, center: center, radius: androidGaugeRadii.outer * size, from: start, sweep: sweep, moving: true)
            arc(into: path, center: center, radius: androidGaugeRadii.inner * size, from: start + sweep, sweep: -sweep,
                moving: false)
            path.closeSubpath()
        }
        return path
    }

    /// An arc of two curves whatever its sweep, so arcs of any length morph.
    private static func arc(into path: CGMutablePath, center: CGPoint, radius: CGFloat, from start: CGFloat, sweep: CGFloat,
                            moving: Bool) {
        func at(_ angle: CGFloat) -> CGPoint { CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)) }
        let step = sweep / 2
        let k = 4 / 3 * tan(step / 4) * radius
        if moving { path.move(to: at(start)) } else { path.addLine(to: at(start)) }
        for index in 0..<2 {
            let a = start + step * CGFloat(index), b = a + step
            let from = at(a), to = at(b)
            path.addCurve(to: to, control1: CGPoint(x: from.x - k * sin(a), y: from.y + k * cos(a)),
                          control2: CGPoint(x: to.x + k * sin(b), y: to.y - k * cos(b)))
        }
    }

    /// The flames of its thrusters, one under each foot.
    static func androidThrusters(size: CGFloat) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        let path = CGMutablePath()
        for x in [0.458, 0.542] as [CGFloat] {
            path.move(to: point(x - 0.024, 0.852))
            path.addLine(to: point(x + 0.024, 0.852))
            path.addQuadCurve(to: point(x, 0.955), control: point(x + 0.02, 0.91))
            path.addQuadCurve(to: point(x - 0.024, 0.852), control: point(x - 0.02, 0.91))
            path.closeSubpath()
        }
        return path
    }

    /// The pool of light it floats over.
    static func androidHover(size: CGFloat) -> CGPath {
        CGPath(ellipseIn: box(0.355, 0.93, 0.29, 0.04, size), transform: nil)
    }

    static func androidArms(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let (left, right, leftElbow, leftHand, rightElbow, rightHand) = androidArmPoints(pose)
        let path = CGMutablePath()
        limb(into: path, [left, leftElbow, leftHand], width: 0.05, hand: 0.026, size: size)
        limb(into: path, [right, rightElbow, rightHand], width: 0.05, hand: 0.026, size: size)
        return path
    }

    /// Its round hands, at the ends of its arms in `pose`.
    static func androidHands(_ pose: ArmsPose, size: CGFloat) -> CGPath {
        let points = androidArmPoints(pose)
        let path = CGMutablePath()
        for hand in [points.3, points.5] {
            path.addEllipse(in: box(hand.x - 0.03, hand.y - 0.03, 0.06, 0.06, size))
        }
        return path
    }

    private static func androidArmPoints(_ pose: ArmsPose)
        -> (CGPoint, CGPoint, CGPoint, CGPoint, CGPoint, CGPoint) {
        let left = CGPoint(x: 0.35, y: 0.50), right = CGPoint(x: 0.65, y: 0.50)
        switch pose {
        case .rest: return (left, right, .init(x: 0.305, y: 0.585), .init(x: 0.312, y: 0.67),
                            .init(x: 0.695, y: 0.585), .init(x: 0.688, y: 0.67))
        case .wave: return (left, right, .init(x: 0.305, y: 0.585), .init(x: 0.312, y: 0.67),
                            .init(x: 0.735, y: 0.45), .init(x: 0.76, y: 0.345))
        case .waveOut: return (left, right, .init(x: 0.305, y: 0.585), .init(x: 0.312, y: 0.67),
                               .init(x: 0.745, y: 0.455), .init(x: 0.83, y: 0.37))
        case .up: return (left, right, .init(x: 0.27, y: 0.43), .init(x: 0.245, y: 0.325),
                          .init(x: 0.73, y: 0.43), .init(x: 0.755, y: 0.325))
        case .folded: return (left, right, .init(x: 0.355, y: 0.625), .init(x: 0.545, y: 0.64),
                              .init(x: 0.645, y: 0.625), .init(x: 0.455, y: 0.64))
        }
    }

    /// The colour a figure's eyes glow in when they are lights on glass,
    /// as the android's are, rather than ink.
    static func eyeGlow(_ look: NotchMascotLook) -> NotchMascotColor? {
        look.style == .android ? NotchMascotSignalColors(look).glow : nil
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

/// The colours of the hologram and the android, worked out from the body's
/// own light and shade so they belong together on every palette and on any
/// hand-picked colour: the hologram's hair and dress a deeper tone of the
/// body, her ribbons and light a neighbouring hue; the android's joints and
/// glass a dark tint of its shell, its eyes and lights a neon of its hue.
/// A colour too grey to have a hue takes cyan light instead.
struct NotchMascotSignalColors: Equatable {
    var hair: NotchMascotColor
    var dress: NotchMascotColor
    var dressHem: NotchMascotColor
    /// Her skin of light, lit at the top and a touch deeper at her feet.
    var skin: NotchMascotColor
    var skinLow: NotchMascotColor
    var trim: NotchMascotColor
    var ribbon: NotchMascotColor
    /// The projection's light, and the fringe on each side of her.
    var light: NotchMascotColor
    var fringe: NotchMascotColor
    /// The android's dark parts, its glass from top to bottom, its arms
    /// and the light of its eyes, gauge and thrusters.
    var graphite: NotchMascotColor
    var glassTop: NotchMascotColor
    var glassBottom: NotchMascotColor
    var arms: NotchMascotColor
    var glow: NotchMascotColor

    init(light bodyLight: NotchMascotColor, shade: NotchMascotColor) {
        let (hue, saturation, _) = shade.hsb
        let grey = saturation < 0.12
        let rich = grey ? 0.14 : min(1, saturation * 0.85 + 0.3)
        // Deep yellows go olive, so yellow hair turns toward gold instead.
        let golden = grey ? 0 : max(0, 1 - abs(hue - 0.14) / 0.08)
        hair = .hsb(grey ? 0.64 : hue - 0.05 * golden, rich, 0.62 + 0.2 * golden)
        dress = .hsb(hue - 0.03 * golden, grey ? 0.12 : min(1, saturation * 0.8 + 0.22), 0.80 + 0.14 * golden)
        dressHem = .hsb(hue, grey ? 0.08 : min(1, saturation * 0.6 + 0.1), 0.98)
        // Always light, however dark the colour: she is made of light.
        let lit = bodyLight.hsb
        skin = .hsb(lit.0, min(lit.1, 0.3), max(lit.2, 0.93))
        skinLow = .hsb(grey ? lit.0 : hue, grey ? 0.06 : min(0.55, saturation * 0.7 + 0.12), max(lit.2, 0.93) * 0.9)
        trim = bodyLight.brightened(0.75)
        let neighbour = grey ? 0.53 : (hue + 0.1).truncatingRemainder(dividingBy: 1)
        ribbon = .hsb(neighbour, grey ? 0.6 : 0.62, 1)
        light = .hsb(neighbour, grey ? 0.45 : 0.42, 1)
        fringe = .hsb(grey ? 0.88 : (hue + 0.9).truncatingRemainder(dividingBy: 1), grey ? 0.45 : 0.55, 1)
        let tint = grey ? 0.62 : hue
        graphite = .hsb(tint, 0.28, 0.24)
        glassTop = .hsb(tint, 0.42, 0.28)
        glassBottom = .hsb(tint, 0.5, 0.09)
        arms = shade
        glow = grey ? .hsb(0.52, 0.55, 1) : .hsb(hue, 0.58, 1)
    }

    init(_ look: NotchMascotLook) {
        let palette = look.bodyPalette
        self.init(light: palette.light, shade: palette.shade)
    }
}

extension NotchMascotColor {
    /// Hue, saturation and brightness, each from 0 to 1.
    var hsb: (CGFloat, CGFloat, CGFloat) {
        let high = max(red, green, blue), low = min(red, green, blue), spread = high - low
        guard spread > 0.0001 else { return (0, 0, high) }
        var hue: CGFloat
        if high == red { hue = (green - blue) / spread } else if high == green { hue = 2 + (blue - red) / spread }
        else { hue = 4 + (red - green) / spread }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, spread / high, high)
    }

    static func hsb(_ hue: CGFloat, _ saturation: CGFloat, _ brightness: CGFloat, alpha: CGFloat = 1) -> NotchMascotColor {
        let h = (hue - floor(hue)) * 6, sector = Int(h) % 6, f = h - floor(h)
        let p = brightness * (1 - saturation), q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        return NotchMascotColor(red: r, green: g, blue: b, alpha: alpha)
    }
}
