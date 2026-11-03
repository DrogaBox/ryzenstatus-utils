// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The phoenix: a round little firebird, front on, its feathers in the
/// body's colours and everything that burns in fire's own. A crest of three
/// flames licks up from its crown, its wings are fans of feathers tipped
/// with flame, a long tail of flame plumes sweeps out behind it and curls,
/// and embers rise off it. Asleep the fire sinks to embers and the wings
/// fold; awake it flares back up.
extension NotchMascotCreatures {
    /// How the phoenix holds itself in a pose: each wing's angle from
    /// hanging down, out to its own side; how tall its crest burns, a share
    /// of its full height; how far its tail fans up, in degrees; how high
    /// each foot is lifted.
    private struct PhoenixPose {
        var leftWing: CGFloat
        var rightWing: CGFloat
        var crest: CGFloat
        var tail: CGFloat
        var leftFoot: CGFloat = 0
        var rightFoot: CGFloat = 0
    }

    private static func phoenixPose(_ pose: CritterPose) -> PhoenixPose {
        switch pose {
        case .rest: return PhoenixPose(leftWing: 38, rightWing: 38, crest: 1, tail: 0)
        case .asleep: return PhoenixPose(leftWing: 10, rightWing: 10, crest: 0.45, tail: -14)
        case .cheer: return PhoenixPose(leftWing: 152, rightWing: 152, crest: 1.12, tail: 14)
        case .wave: return PhoenixPose(leftWing: 38, rightWing: 140, crest: 1.05, tail: 4)
        case .waveOut: return PhoenixPose(leftWing: 38, rightWing: 104, crest: 1.05, tail: 4)
        case .bow: return PhoenixPose(leftWing: 74, rightWing: 74, crest: 0.85, tail: 10)
        case .twitch: return PhoenixPose(leftWing: 46, rightWing: 46, crest: 1.15, tail: 8)
        case .spread: return PhoenixPose(leftWing: 108, rightWing: 108, crest: 1.1, tail: 18)
        case .step: return PhoenixPose(leftWing: 50, rightWing: 30, crest: 1, tail: 4, leftFoot: 0.03)
        case .stepOther: return PhoenixPose(leftWing: 30, rightWing: 50, crest: 1, tail: -4, rightFoot: 0.03)
        }
    }

    private static let phoenixHead = (center: CGPoint(x: 0.5, y: 0.375), rx: CGFloat(0.215), ry: CGFloat(0.195))
    private static let phoenixChest = (center: CGPoint(x: 0.5, y: 0.655), rx: CGFloat(0.168), ry: CGFloat(0.17))
    /// Where the right wing joins the body; the left is its mirror.
    private static let phoenixShoulder = CGPoint(x: 0.636, y: 0.585)
    private static let phoenixWingLength: CGFloat = 0.215

    /// A round head over a round chest.
    static func phoenixBody(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.oval(phoenixHead.center, phoenixHead.rx, phoenixHead.ry)
        pen.oval(phoenixChest.center, phoenixChest.rx, phoenixChest.ry)
        return pen.path
    }

    static var phoenixAnatomy: NotchMascotAnatomy {
        let hand = critterReach(phoenixShoulder, 38, phoenixWingLength * 0.85)
        return NotchMascotAnatomy(rightHand: hand, leftHand: critterMirror(hand), floor: 0.9, leftFoot: 0.452,
                                  rightFoot: 0.548, foot: 0.08, torso: CGRect(x: 0.33, y: 0.52, width: 0.34, height: 0.28),
                                  nose: CGPoint(x: 0.5, y: 0.47), mouth: CGPoint(x: 0.5, y: 0.48))
    }

    // MARK: Parts

    static func phoenixParts(colors: NotchMascotCritterColors, hat: Bool, size: CGFloat) -> [NotchMascotCritterPart] {
        typealias Part = NotchMascotCritterPart
        let fire = PhoenixFire(colors)
        let top = CGPoint(x: 0.5, y: 0), bottom = CGPoint(x: 0.5, y: 1)
        var parts: [Part] = [
            Part(name: "halo", level: .back,
                 paint: .radial(fire.halo, center: CGPoint(x: 0.5, y: 0.5), radius: CGSize(width: 0.46, height: 0.46)),
                 asleep: 0.4, effect: true) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.5), 0.46, 0.46)
                return pen.path
            },
            Part(name: "tail", level: .back, paint: .gradient([fire.light, fire.outer, fire.deep], from: CGPoint(x: 0.95, y: 0.6),
                                                            to: CGPoint(x: 0.55, y: 0.85)),
                 glow: fire.outer, asleep: 0.55, idle: (1.4, 8)) { pose, phase in
                phoenixTail(pose, phase: phase, core: false, size: size)
            },
            Part(name: "tailCore", level: .back, paint: .gradient([fire.core, fire.light], from: CGPoint(x: 0.9, y: 0.65),
                                                                to: CGPoint(x: 0.6, y: 0.82)),
                 asleep: 0.4, idle: (1.4, 8)) { pose, phase in
                phoenixTail(pose, phase: phase, core: true, size: size)
            },
        ]
        if !hat {
            parts += [
                Part(name: "crest", level: .back, paint: .gradient([fire.deep, fire.outer, fire.light], from: top,
                                                                   to: CGPoint(x: 0.5, y: 0.24)),
                     glow: fire.outer, asleep: 0.6, idle: (0.9, 8)) { pose, phase in
                    phoenixCrest(pose, phase: phase, core: false, size: size)
                },
                Part(name: "crestCore", level: .back, paint: .gradient([fire.light, fire.core], from: CGPoint(x: 0.5, y: 0.06),
                                                                       to: CGPoint(x: 0.5, y: 0.22)),
                     asleep: 0.45, idle: (0.9, 8)) { pose, phase in
                    phoenixCrest(pose, phase: phase, core: true, size: size)
                },
            ]
        }
        parts += [
            Part(name: "legs", level: .back, paint: .color(fire.talon)) { pose, _ in phoenixFeet(pose, size: size) },
            Part(name: "belly", level: .middle, paint: .gradient([fire.belly, fire.bellyLow], from: CGPoint(x: 0.5, y: 0.56),
                                                                 to: CGPoint(x: 0.5, y: 0.8))) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.69), 0.112, 0.118)
                return pen.path
            },
            Part(name: "chestFeathers", level: .middle, paint: .color(fire.bellyMark)) { _, _ in
                let pen = CritterPen(size: size)
                for (x, y) in [(0.428, 0.632), (0.476, 0.62), (0.524, 0.62), (0.572, 0.632),
                               (0.452, 0.668), (0.5, 0.66), (0.548, 0.668)] as [(CGFloat, CGFloat)] {
                    pen.move(x - 0.02, y)
                    pen.quad(x + 0.02, y, x, y + 0.024)
                    pen.quad(x - 0.02, y, x, y + 0.012)
                    pen.close()
                }
                return pen.path
            },
            Part(name: "cheeks", level: .middle, paint: .color(fire.cheek)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.365, y: 0.445), 0.034, 0.02)
                pen.oval(CGPoint(x: 0.635, y: 0.445), 0.034, 0.02)
                return pen.path
            },
            Part(name: "wings", level: .middle, paint: .gradient([fire.wing, fire.wingLow], from: CGPoint(x: 0.5, y: 0.5),
                                                                 to: CGPoint(x: 0.5, y: 0.85))) { pose, _ in
                phoenixWings(pose, tips: false, size: size)
            },
            Part(name: "wingFlames", level: .middle, paint: .gradient([fire.light, fire.outer, fire.deep], from: CGPoint(x: 0.5, y: 0.6),
                                                                      to: bottom),
                 glow: fire.outer, asleep: 0.55) { pose, _ in
                phoenixWings(pose, tips: true, size: size)
            },
            Part(name: "beak", level: .middle, paint: .gradient([fire.beak, fire.beakLow], from: CGPoint(x: 0.5, y: 0.43),
                                                                to: CGPoint(x: 0.5, y: 0.49))) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.5, 0.424)
                pen.curve(0.54, 0.442, 0.522, 0.424, 0.54, 0.43)
                pen.curve(0.5, 0.494, 0.54, 0.46, 0.516, 0.484)
                pen.curve(0.46, 0.442, 0.484, 0.484, 0.46, 0.46)
                pen.curve(0.5, 0.424, 0.46, 0.43, 0.478, 0.424)
                pen.close()
                return pen.path
            },
            Part(name: "beakLine", level: .middle, paint: .line(fire.beakLine, width: 0.008)) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.472, 0.458)
                pen.quad(0.528, 0.458, 0.5, 0.468)
                return pen.path
            },
            Part(name: "embers", level: .front, paint: .color(fire.light), glow: fire.outer, idle: (2.6, 16),
                 idlesAsleep: true, effect: true) { _, phase in
                phoenixEmbers(phase: phase, size: size)
            },
        ]
        return parts
    }

    /// The crest: three flames up from the crown, the middle one tallest,
    /// burning `crest` of their height, flickering with `phase`; the core
    /// is the yellow heart inside each.
    private static func phoenixCrest(_ pose: CritterPose, phase: CGFloat, core: Bool, size: CGFloat) -> CGPath {
        let height = phoenixPose(pose).crest
        let pen = CritterPen(size: size)
        let flicker = sin(phase * 2 * .pi)
        let flames: [(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, curl: CGFloat, beat: CGFloat)] = [
            (CGPoint(x: 0.455, y: 0.215), -28, 0.15, 0.085, -0.22, 1),
            (CGPoint(x: 0.545, y: 0.215), 28, 0.15, 0.085, 0.22, -1),
            (CGPoint(x: 0.5, y: 0.205), 0, 0.185, 0.1, 0.12, 0.6),
        ]
        for flame in flames {
            let length = flame.length * height * (core ? 0.55 : 1) * (1 + 0.06 * flicker * flame.beat)
            let base = CGPoint(x: flame.base.x, y: flame.base.y + (core ? 0.012 : 0))
            let tip = critterReach(base, 180 + flame.angle + 6 * flicker * flame.beat, length)
            pen.flame(base, tip, width: flame.width * (core ? 0.55 : 1), curl: flame.curl + 0.08 * flicker * flame.beat)
        }
        return pen.path
    }

    /// The tail: three long plumes of flame sweeping out to the right of
    /// the screen and curling up, and a short one to the left, fanned up
    /// `tail` degrees and swaying with `phase`.
    private static func phoenixTail(_ pose: CritterPose, phase: CGFloat, core: Bool, size: CGFloat) -> CGPath {
        let fan = phoenixPose(pose).tail
        let pen = CritterPen(size: size)
        let sway = sin(phase * 2 * .pi)
        let plumes: [(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, curl: CGFloat)] = [
            (CGPoint(x: 0.56, y: 0.74), 58, 0.36, 0.12, 0.3),
            (CGPoint(x: 0.56, y: 0.77), 80, 0.36, 0.11, 0.24),
            (CGPoint(x: 0.54, y: 0.8), 108, 0.29, 0.1, 0.2),
            (CGPoint(x: 0.44, y: 0.78), -96, 0.2, 0.09, -0.24),
        ]
        for (index, plume) in plumes.enumerated() {
            let lift = index == 3 ? -fan * 0.6 : fan
            let beat = sway * (index % 2 == 0 ? 1 : -0.7)
            let length = plume.length * (core ? 0.62 : 1) * (1 + 0.04 * beat) * (fan < 0 ? 0.72 : 1)
            let angle = plume.angle + lift + 5 * beat
            let base = core ? critterReach(plume.base, angle, 0.03) : plume.base
            let tip = critterReach(base, angle, length)
            pen.flame(base, tip, width: plume.width * (core ? 0.5 : 1), curl: plume.curl + 0.06 * beat)
        }
        return pen.path
    }

    /// Both wings: a broad feathered arm out of each shoulder, or the
    /// three flame feathers fanning from its end.
    private static func phoenixWings(_ pose: CritterPose, tips: Bool, size: CGFloat) -> CGPath {
        let angles = phoenixPose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), angles.leftWing), (CGFloat(1), angles.rightWing)] {
            let shoulder = CGPoint(x: 0.5 + side * (phoenixShoulder.x - 0.5), y: phoenixShoulder.y)
            let heading = side * angle
            let wrist = critterReach(shoulder, heading, phoenixWingLength * 0.62)
            if tips {
                // Fanned toward the body's far side when the wing is raised,
                // so the flames always lick upward and out.
                let lean: CGFloat = angle > 90 ? -0.16 : 0.16
                for (index, spread) in [-30, 0, 30].enumerated() {
                    let length = phoenixWingLength * (index == 1 ? 0.62 : 0.5)
                    let base = critterReach(wrist, heading + side * CGFloat(spread) * 0.4, -0.01)
                    pen.flame(base, critterReach(base, heading + side * CGFloat(spread), length), width: 0.046,
                              curl: side * lean)
                }
            } else {
                pen.feather(critterReach(shoulder, heading, -0.03), critterReach(wrist, heading, 0.03), width: 0.112,
                            curl: side * 0.04)
            }
        }
        return pen.path
    }
    /// Two golden legs with three toes each, one lifted in a step.
    private static func phoenixFeet(_ pose: CritterPose, size: CGFloat) -> CGPath {
        let lifts = phoenixPose(pose)
        let pen = CritterPen(size: size)
        for (side, lift) in [(CGFloat(-1), lifts.leftFoot), (CGFloat(1), lifts.rightFoot)] {
            let x = 0.5 + side * 0.048
            let ankle = CGPoint(x: x, y: 0.865 - lift)
            pen.limb(CGPoint(x: x, y: 0.78), ankle, (0.03, 0.022))
            for toe in [-40, 0, 40] as [CGFloat] {
                pen.limb(ankle, critterReach(ankle, toe * 1.1, 0.034), (0.02, 0.014))
            }
        }
        return pen.path
    }

    /// Embers drifting up off its crown and wings, each glowing up and
    /// dying out on the way; `phase` carries them round.
    private static func phoenixEmbers(phase: CGFloat, size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        let starts: [(CGFloat, CGFloat, CGFloat)] = [(0.36, 0.3, -0.05), (0.66, 0.26, 0.06), (0.26, 0.6, -0.06), (0.76, 0.56, 0.05)]
        for (index, start) in starts.enumerated() {
            var u = phase + CGFloat(index) / CGFloat(starts.count)
            u -= floor(u)
            let x = start.0 + start.2 * u + 0.012 * sin(u * 3 * .pi)
            let y = start.1 - 0.24 * u
            let radius = 0.013 * sin(u * .pi)
            pen.oval(CGPoint(x: x, y: y), radius, radius)
        }
        return pen.path
    }
}

/// The phoenix's fire and trim: flames from a red heart to a white-gold
/// core, a soft halo of warmth, a gold beak and talons, and a warm cream
/// breast mixed from its own feathers, so it glows on any colour.
private struct PhoenixFire {
    var deep: NotchMascotColor
    var outer: NotchMascotColor
    var light: NotchMascotColor
    var core: NotchMascotColor
    var halo: NotchMascotColor
    var belly: NotchMascotColor
    var bellyLow: NotchMascotColor
    var bellyMark: NotchMascotColor
    var cheek: NotchMascotColor
    var wing: NotchMascotColor
    var wingLow: NotchMascotColor
    var beak: NotchMascotColor
    var beakLow: NotchMascotColor
    var beakLine: NotchMascotColor
    var talon: NotchMascotColor

    init(_ colors: NotchMascotCritterColors) {
        typealias C = NotchMascotCritterColors
        deep = C.rgb(0xF2412B)
        outer = C.rgb(0xFF7A1F)
        light = C.rgb(0xFFC93C)
        core = C.rgb(0xFFF4B8)
        halo = C.rgb(0xFF9A3A).withAlpha(0.3)
        // A warm breast, cream at the top and glowing peach lower down.
        belly = C.mix(colors.light, C.rgb(0xFFF3D2), colors.dark ? 0.45 : 0.75)
        bellyLow = C.mix(colors.fur(0.3), C.rgb(0xFFC27A), colors.dark ? 0.4 : 0.65)
        bellyMark = C.mix(bellyLow, C.rgb(0xF08A3C), 0.5).withAlpha(0.55)
        // The wings a tone deeper than the body, warming toward their tips.
        wing = colors.fur(0.7)
        wingLow = C.mix(colors.shade.darkened(0.12), C.rgb(0xFF8A3A), 0.2)
        cheek = C.rgb(0xFF6A3D).withAlpha(0.32)
        beak = C.rgb(0xFFC23A)
        beakLow = C.rgb(0xF08A1C)
        beakLine = C.rgb(0xB8571A)
        talon = C.rgb(0xF2A33A)
    }
}

extension NotchMascotColor {
    /// The same colour with `alpha`.
    func withAlpha(_ alpha: CGFloat) -> NotchMascotColor {
        NotchMascotColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
