// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The axolotl: a little water salamander standing up, front on, its skin
/// in the body's colours. A wide flat head with eyes set far apart and the
/// wide content smile every axolotl wears, three feathery gill stalks
/// fanning out of each side of it in a deeper tone, a pale belly, stubby
/// arms and legs with little round fingers and toes, and a thick tail with
/// a see-through fin that curls out behind it. Its gills wave while it
/// idles, flare when it is startled and droop when it sleeps.
extension NotchMascotCreatures {
    /// How the axolotl holds itself in a pose: how far its gills are turned
    /// up from where they rest, in degrees, and how far they spread apart;
    /// each arm's angle from hanging down, out to its own side; how far its
    /// tail curls up; how high each foot is lifted.
    private struct AxolotlPose {
        var gills: CGFloat
        var spread: CGFloat
        var leftArm: CGFloat
        var rightArm: CGFloat
        var tail: CGFloat
        var leftFoot: CGFloat = 0
        var rightFoot: CGFloat = 0
    }

    private static func axolotlPose(_ pose: CritterPose) -> AxolotlPose {
        switch pose {
        case .rest: return AxolotlPose(gills: 0, spread: 1, leftArm: 34, rightArm: 34, tail: 1)
        case .asleep: return AxolotlPose(gills: -30, spread: 0.7, leftArm: 8, rightArm: 8, tail: 0.3)
        case .cheer: return AxolotlPose(gills: 14, spread: 1.25, leftArm: 150, rightArm: 150, tail: 1.3)
        case .wave: return AxolotlPose(gills: 6, spread: 1.1, leftArm: 34, rightArm: 145, tail: 1.1)
        case .waveOut: return AxolotlPose(gills: 6, spread: 1.1, leftArm: 34, rightArm: 105, tail: 1.1)
        case .bow: return AxolotlPose(gills: -14, spread: 0.9, leftArm: 70, rightArm: 70, tail: 0.9)
        case .twitch: return AxolotlPose(gills: 10, spread: 1.45, leftArm: 46, rightArm: 46, tail: 1.2)
        case .spread: return AxolotlPose(gills: 8, spread: 1.3, leftArm: 98, rightArm: 98, tail: 1.2)
        case .step: return AxolotlPose(gills: 3, spread: 1, leftArm: 50, rightArm: 20, tail: 0.8, leftFoot: 0.026)
        case .stepOther: return AxolotlPose(gills: -3, spread: 1, leftArm: 20, rightArm: 50, tail: 1.2, rightFoot: 0.026)
        }
    }

    private static let axolotlHead = (center: CGPoint(x: 0.5, y: 0.435), rx: CGFloat(0.235), ry: CGFloat(0.178))
    private static let axolotlChest = (center: CGPoint(x: 0.5, y: 0.71), rx: CGFloat(0.13), ry: CGFloat(0.14))
    /// Where the right arm joins the body, and how long it is.
    private static let axolotlShoulder = CGPoint(x: 0.6, y: 0.645)
    private static let axolotlArm: CGFloat = 0.075
    /// The right gill stalks: root, angle from hanging down, length and
    /// how wide each is at its plumpest.
    private static let axolotlGills: [(root: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat)] = [
        (CGPoint(x: 0.68, y: 0.34), 136, 0.135, 0.062),
        (CGPoint(x: 0.71, y: 0.41), 104, 0.14, 0.066),
        (CGPoint(x: 0.69, y: 0.48), 72, 0.12, 0.058),
    ]

    /// A wide flat head over a small round body.
    static func axolotlBody(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.oval(axolotlHead.center, axolotlHead.rx, axolotlHead.ry)
        pen.oval(axolotlChest.center, axolotlChest.rx, axolotlChest.ry)
        return pen.path
    }

    static var axolotlAnatomy: NotchMascotAnatomy {
        let hand = critterReach(axolotlShoulder, 34, axolotlArm)
        return NotchMascotAnatomy(rightHand: hand, leftHand: critterMirror(hand), floor: 0.894, leftFoot: 0.44,
                                  rightFoot: 0.56, foot: 0.09, torso: CGRect(x: 0.37, y: 0.59, width: 0.26, height: 0.25),
                                  nose: CGPoint(x: 0.5, y: 0.5), mouth: CGPoint(x: 0.5, y: 0.54))
    }

    // MARK: Parts

    static func axolotlParts(colors: NotchMascotCritterColors, size: CGFloat) -> [NotchMascotCritterPart] {
        typealias Part = NotchMascotCritterPart
        let tone = AxolotlTone(colors)
        return [
            Part(name: "fin", level: .back, paint: .color(tone.fin), idle: (3, 10)) { pose, phase in
                axolotlTail(pose, phase: phase, fin: true, size: size)
            },
            Part(name: "tail", level: .back, paint: .fur(tone: -0.04), idle: (3, 10)) { pose, phase in
                axolotlTail(pose, phase: phase, fin: false, size: size)
            },
            Part(name: "gills", level: .back, paint: .gradient([tone.gill, tone.gillDeep], from: CGPoint(x: 0.5, y: 0.22),
                                                               to: CGPoint(x: 0.5, y: 0.62)), idle: (2.2, 10)) { pose, phase in
                axolotlFronds(pose, phase: phase, frills: false, size: size)
            },
            Part(name: "ribs", level: .back, paint: .color(tone.frill), idle: (2.2, 10)) { pose, phase in
                axolotlFronds(pose, phase: phase, frills: true, size: size)
            },
            Part(name: "legs", level: .back, paint: .fur(tone: -0.08)) { pose, _ in
                axolotlLegs(pose, toes: false, size: size)
            },
            Part(name: "toes", level: .back, paint: .color(tone.toe)) { pose, _ in
                axolotlLegs(pose, toes: true, size: size)
            },
            Part(name: "belly", level: .middle, paint: .color(tone.belly)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.73), 0.085, 0.098)
                return pen.path
            },
            Part(name: "spots", level: .middle, paint: .color(tone.spot)) { _, _ in
                let pen = CritterPen(size: size)
                for (x, y, r) in [(0.33, 0.43, 0.009), (0.315, 0.455, 0.006), (0.345, 0.458, 0.006), (0.67, 0.43, 0.009),
                                  (0.685, 0.455, 0.006), (0.655, 0.458, 0.006)] as [(CGFloat, CGFloat, CGFloat)] {
                    pen.oval(CGPoint(x: x, y: y), r, r)
                }
                return pen.path
            },
            Part(name: "cheeks", level: .middle, paint: .color(tone.cheek)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.35, y: 0.5), 0.036, 0.021)
                pen.oval(CGPoint(x: 0.65, y: 0.5), 0.036, 0.021)
                return pen.path
            },
            Part(name: "smile", level: .middle, paint: .line(tone.smile, width: 0.013)) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.4, 0.505)
                pen.curve(0.6, 0.505, 0.44, 0.56, 0.56, 0.56)
                return pen.path
            },
            Part(name: "arms", level: .middle, paint: .fur(tone: -0.04)) { pose, _ in
                axolotlArms(pose, fingers: false, size: size)
            },
            Part(name: "fingers", level: .middle, paint: .color(tone.toe)) { pose, _ in
                axolotlArms(pose, fingers: true, size: size)
            },
        ]
    }

    /// The gill stalks, three out of each side of the head, turned and
    /// spread as the pose says and waving with `phase`, each a plump
    /// scalloped frond; or the paler rib down each.
    private static func axolotlFronds(_ pose: CritterPose, phase: CGFloat, frills: Bool, size: CGFloat) -> CGPath {
        let shape = axolotlPose(pose)
        let pen = CritterPen(size: size)
        for side in [-1, 1] as [CGFloat] {
            for (index, gill) in axolotlGills.enumerated() {
                let root = CGPoint(x: 0.5 + side * (gill.root.x - 0.5), y: gill.root.y)
                let wave = 9 * sin((phase + CGFloat(index) / 3) * 2 * .pi)
                let angle = 106 + (gill.angle - 106) * shape.spread + shape.gills + wave
                let tip = critterReach(root, side * angle, gill.length)
                if frills {
                    // A paler rib down the middle of each frond.
                    pen.limb(root, critterReach(root, side * angle, gill.length * 0.8), (0.011, 0.005))
                } else {
                    axolotlFrond(pen, root: root, tip: tip, width: gill.width)
                }
            }
        }
        return pen.path
    }

    /// One gill frond from `root` to `tip` in a single outline: narrow where
    /// it leaves the head, plump in the middle and round at the end, its
    /// edges scalloped into three soft lobes a side, the feathery fringe
    /// that says axolotl. One outline, so nothing overlapping punches holes
    /// in its fill.
    private static func axolotlFrond(_ pen: CritterPen, root: CGPoint, tip: CGPoint, width: CGFloat) {
        let (ux, uy) = critterUnit(root, tip)
        let (nx, ny) = (-uy, ux)
        let length = critterDistance(root, tip)
        let stations: [(along: CGFloat, half: CGFloat)] = [(0, 0.24), (0.34, 0.4), (0.62, 0.5), (0.86, 0.44)]
        func edge(_ station: Int, _ side: CGFloat, bulge: CGFloat = 0) -> CGPoint {
            let along = stations[station].along * length
            let out = stations[station].half * width + bulge
            return CGPoint(x: root.x + ux * along + nx * side * out, y: root.y + uy * along + ny * side * out)
        }
        func lobe(_ from: Int, _ to: Int, _ side: CGFloat) -> CGPoint {
            let along = (stations[from].along + stations[to].along) / 2 * length
            let out = (stations[from].half + stations[to].half) / 2 * width + width * 0.32
            return CGPoint(x: root.x + ux * along + nx * side * out, y: root.y + uy * along + ny * side * out)
        }
        pen.path.move(to: pen.point(edge(0, 1)))
        for station in 1..<stations.count {
            pen.path.addQuadCurve(to: pen.point(edge(station, 1)), control: pen.point(lobe(station - 1, station, 1)))
        }
        let reach = length * 0.2
        let (left, right) = (edge(stations.count - 1, 1), edge(stations.count - 1, -1))
        pen.path.addCurve(to: pen.point(right), control1: pen.point(CGPoint(x: left.x + ux * reach, y: left.y + uy * reach)),
                          control2: pen.point(CGPoint(x: right.x + ux * reach, y: right.y + uy * reach)))
        for station in stride(from: stations.count - 2, through: 0, by: -1) {
            pen.path.addQuadCurve(to: pen.point(edge(station, -1)), control: pen.point(lobe(station, station + 1, -1)))
        }
        let back = width * 0.3
        pen.path.addQuadCurve(to: pen.point(edge(0, 1)), control: pen.point(CGPoint(x: root.x - ux * back, y: root.y - uy * back)))
        pen.path.closeSubpath()
    }

    /// The stubby arms from the shoulders, or the four little round fingers
    /// at the end of each.
    private static func axolotlArms(_ pose: CritterPose, fingers: Bool, size: CGFloat) -> CGPath {
        let shape = axolotlPose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), shape.leftArm), (CGFloat(1), shape.rightArm)] {
            let shoulder = CGPoint(x: 0.5 + side * (axolotlShoulder.x - 0.5), y: axolotlShoulder.y)
            let hand = critterReach(shoulder, side * angle, axolotlArm)
            if fingers {
                for spread in [-48, -16, 16, 48] as [CGFloat] {
                    pen.oval(critterReach(hand, side * (angle + spread), 0.02), 0.0095, 0.0095)
                }
            } else {
                pen.limb(shoulder, hand, (0.05, 0.04))
            }
        }
        return pen.path
    }

    /// The stubby legs under the body, or the toes on them; one lifted in
    /// a step.
    private static func axolotlLegs(_ pose: CritterPose, toes: Bool, size: CGFloat) -> CGPath {
        let shape = axolotlPose(pose)
        let pen = CritterPen(size: size)
        for (side, lift) in [(CGFloat(-1), shape.leftFoot), (CGFloat(1), shape.rightFoot)] {
            let hip = CGPoint(x: 0.5 + side * 0.066, y: 0.8)
            let foot = CGPoint(x: 0.5 + side * 0.074, y: 0.858 - lift)
            if toes {
                for spread in [-0.024, 0, 0.024] as [CGFloat] {
                    pen.oval(CGPoint(x: foot.x + spread + side * 0.008, y: foot.y + 0.022), 0.0125, 0.012)
                }
            } else {
                pen.limb(hip, foot, (0.07, 0.066))
            }
        }
        return pen.path
    }

    /// The thick tail out from behind the body, curling up `tail` of the
    /// way and swaying with `phase`; or the see-through fin running round it.
    private static func axolotlTail(_ pose: CritterPose, phase: CGFloat, fin: Bool, size: CGFloat) -> CGPath {
        let curl = axolotlPose(pose).tail
        let sway = sin(phase * 2 * .pi) * 0.025
        let pen = CritterPen(size: size)
        // The fin rides a little above the tail, so it shows along its top.
        let lift: CGFloat = fin ? -0.022 : 0
        let spine = critterSpine(CGPoint(x: 0.56, y: 0.79 + lift), CGPoint(x: 0.7, y: 0.89 + lift),
                                 CGPoint(x: 0.83 + sway, y: 0.88 - 0.05 * curl + lift),
                                 CGPoint(x: 0.86 + sway * 1.4, y: 0.84 - 0.17 * curl + lift * 0.4), count: 12)
        pen.tube(spine, widths: fin ? (0.07, 0.05) : (0.075, 0.02))
        return pen.path
    }
}

/// The axolotl's gills, a deeper and richer tone of its own colour leaning
/// toward pink, with paler frills; a see-through fin; a pale belly, rosy
/// cheeks, a few darker freckles and the line of its smile.
private struct AxolotlTone {
    var gill: NotchMascotColor
    var gillDeep: NotchMascotColor
    var frill: NotchMascotColor
    var fin: NotchMascotColor
    var belly: NotchMascotColor
    var cheek: NotchMascotColor
    var spot: NotchMascotColor
    var smile: NotchMascotColor
    var toe: NotchMascotColor

    init(_ colors: NotchMascotCritterColors) {
        typealias C = NotchMascotCritterColors
        // A third of the way round the colour wheel toward pink, by the
        // shorter way, so a blue axolotl's gills go violet and a pink one's
        // deepen to rose.
        let pink: CGFloat = 0.94
        var turn = pink - colors.hue
        if turn > 0.5 { turn -= 1 } else if turn < -0.5 { turn += 1 }
        let hue = colors.grey ? pink : colors.hue + turn * 0.35
        let saturation = colors.grey ? 0.5 : min(0.85, max(0.45, colors.saturation + 0.22))
        let brightness = colors.dark ? 0.66 : 1
        gill = .hsb(hue, saturation * 0.62, brightness)
        gillDeep = .hsb(hue + 0.01, min(1, saturation + 0.08), brightness * 0.86)
        let soft = NotchMascotColor.hsb(hue, saturation * 0.6, min(1, brightness + 0.05))
        frill = NotchMascotColor.hsb(hue, saturation * 0.3, 1).withAlpha(0.7)
        fin = C.mix(soft, colors.light, 0.4).withAlpha(0.75)
        belly = colors.dark ? colors.light.brightened(0.25) : colors.light.brightened(0.55)
        cheek = C.rgb(0xFF7FA5).withAlpha(0.36)
        spot = colors.shade.darkened(0.12).withAlpha(0.45)
        smile = colors.dark ? colors.light.brightened(0.6) : colors.shade.darkened(0.55)
        toe = colors.fur(0.9).darkened(0.04)
    }
}
