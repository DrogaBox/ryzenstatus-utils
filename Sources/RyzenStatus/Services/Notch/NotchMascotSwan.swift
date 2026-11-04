// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The swan: a plump little swan standing up, front on, its feathers in the
/// body's colours. A round head on a long neck with a gentle bend in it, an
/// orange bill with the black knob at its base, a little gold tiara on its
/// crown, a soft breast of scalloped feathers, two broad wings folded at its
/// sides like a tutu, a short tail tipped up behind it and two little
/// webbed feet. It dances: wings up for a cheer, out wide in a port de
/// bras, one raised in a wave, and asleep it folds its wings in close and
/// lets its tail droop.
extension NotchMascotCreatures {
    /// How the swan holds itself in a pose: each wing's angle from hanging
    /// down, out to its own side; how far the long feathers at their ends
    /// fan apart; how far its tail tips up, in degrees; how high each foot
    /// is lifted.
    private struct SwanPose {
        var leftWing: CGFloat
        var rightWing: CGFloat
        var fan: CGFloat
        var tail: CGFloat
        var leftFoot: CGFloat = 0
        var rightFoot: CGFloat = 0
    }

    private static func swanPose(_ pose: CritterPose) -> SwanPose {
        switch pose {
        case .rest: return SwanPose(leftWing: 30, rightWing: 30, fan: 1, tail: 0)
        case .asleep: return SwanPose(leftWing: 14, rightWing: 14, fan: 0.55, tail: -22)
        case .cheer: return SwanPose(leftWing: 150, rightWing: 150, fan: 1.35, tail: 12)
        case .wave: return SwanPose(leftWing: 30, rightWing: 142, fan: 1.2, tail: 6)
        case .waveOut: return SwanPose(leftWing: 30, rightWing: 106, fan: 1.2, tail: 6)
        case .bow: return SwanPose(leftWing: 62, rightWing: 62, fan: 0.9, tail: 14)
        case .twitch: return SwanPose(leftWing: 52, rightWing: 52, fan: 1.5, tail: 16)
        case .spread: return SwanPose(leftWing: 100, rightWing: 100, fan: 1.4, tail: 10)
        case .step: return SwanPose(leftWing: 40, rightWing: 24, fan: 1, tail: 6, leftFoot: 0.026)
        case .stepOther: return SwanPose(leftWing: 24, rightWing: 40, fan: 1, tail: -6, rightFoot: 0.026)
        }
    }

    private static let swanHead = (center: CGPoint(x: 0.5, y: 0.28), rx: CGFloat(0.18), ry: CGFloat(0.16))
    private static let swanChest = (center: CGPoint(x: 0.5, y: 0.7), rx: CGFloat(0.188), ry: CGFloat(0.152))
    /// Where the right wing joins the body, and how long it is to the wrist.
    private static let swanShoulder = CGPoint(x: 0.615, y: 0.6)
    private static let swanWingLength: CGFloat = 0.165

    /// A round head over a plump round body; the neck between them is a
    /// part of its own behind both.
    static func swanBody(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.oval(swanHead.center, swanHead.rx, swanHead.ry)
        pen.oval(swanChest.center, swanChest.rx, swanChest.ry)
        return pen.path
    }

    static var swanAnatomy: NotchMascotAnatomy {
        let hand = critterReach(swanShoulder, 30, swanWingLength)
        return NotchMascotAnatomy(rightHand: hand, leftHand: critterMirror(hand), floor: 0.9, leftFoot: 0.45,
                                  rightFoot: 0.55, foot: 0.09, torso: CGRect(x: 0.34, y: 0.57, width: 0.32, height: 0.28),
                                  nose: CGPoint(x: 0.5, y: 0.335), mouth: CGPoint(x: 0.5, y: 0.365))
    }

    // MARK: Parts

    static func swanParts(colors: NotchMascotCritterColors, hat: Bool, size: CGFloat) -> [NotchMascotCritterPart] {
        typealias Part = NotchMascotCritterPart
        let tone = SwanTone(colors)
        var parts: [Part] = [
            Part(name: "tail", level: .back, paint: .fur(tone: -0.04), idle: (3.4, 10)) { pose, phase in
                swanTail(pose, phase: phase, size: size)
            },
            Part(name: "neck", level: .back, paint: .fur(tone: 0)) { _, _ in
                swanNeck(size: size)
            },
            Part(name: "feet", level: .back, paint: .color(tone.foot)) { pose, _ in
                swanFeet(pose, size: size)
            },
        ]
        if !hat {
            parts += [
                Part(name: "tiara", level: .middle, paint: .gradient([tone.gold, tone.goldDeep], from: CGPoint(x: 0.5, y: 0.08),
                                                                   to: CGPoint(x: 0.5, y: 0.15))) { _, _ in
                    swanTiara(size: size)
                },
                Part(name: "jewel", level: .middle, paint: .color(tone.jewel)) { _, _ in
                    let pen = CritterPen(size: size)
                    pen.oval(CGPoint(x: 0.5, y: 0.112), 0.011, 0.013)
                    return pen.path
                },
            ]
        }
        parts += [
            Part(name: "breast", level: .middle, paint: .gradient([tone.breast, tone.breastLow], from: CGPoint(x: 0.5, y: 0.58),
                                                                  to: CGPoint(x: 0.5, y: 0.84))) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.715), 0.105, 0.115)
                return pen.path
            },
            Part(name: "breastFeathers", level: .middle, paint: .color(tone.scallop)) { _, _ in
                let pen = CritterPen(size: size)
                for (x, y) in [(0.455, 0.655), (0.5, 0.645), (0.545, 0.655), (0.478, 0.695), (0.522, 0.695)]
                    as [(CGFloat, CGFloat)] {
                    pen.move(x - 0.02, y)
                    pen.quad(x + 0.02, y, x, y + 0.022)
                    pen.quad(x - 0.02, y, x, y + 0.011)
                    pen.close()
                }
                return pen.path
            },
            Part(name: "cheeks", level: .middle, paint: .color(tone.cheek)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.38, y: 0.348), 0.034, 0.02)
                pen.oval(CGPoint(x: 0.62, y: 0.348), 0.034, 0.02)
                return pen.path
            },
            Part(name: "primaries", level: .middle, paint: .gradient([tone.wingLow, tone.tip], from: CGPoint(x: 0.5, y: 0.55),
                                                                     to: CGPoint(x: 0.5, y: 0.95))) { pose, _ in
                swanWings(pose, primaries: true, size: size)
            },
            Part(name: "wings", level: .middle, paint: .gradient([tone.wing, tone.wingLow], from: CGPoint(x: 0.5, y: 0.5),
                                                                 to: CGPoint(x: 0.5, y: 0.9))) { pose, _ in
                swanWings(pose, primaries: false, size: size)
            },
            Part(name: "knob", level: .middle, paint: .color(tone.knob)) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.47, 0.322)
                pen.curve(0.5, 0.286, 0.468, 0.302, 0.482, 0.286)
                pen.curve(0.53, 0.322, 0.518, 0.286, 0.532, 0.302)
                pen.quad(0.47, 0.322, 0.5, 0.33)
                pen.close()
                return pen.path
            },
            Part(name: "bill", level: .middle, paint: .gradient([tone.bill, tone.billLow], from: CGPoint(x: 0.5, y: 0.315),
                                                                to: CGPoint(x: 0.5, y: 0.385))) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.5, 0.314)
                pen.curve(0.536, 0.334, 0.52, 0.314, 0.536, 0.32)
                pen.curve(0.5, 0.386, 0.536, 0.36, 0.518, 0.386)
                pen.curve(0.464, 0.334, 0.482, 0.386, 0.464, 0.36)
                pen.curve(0.5, 0.314, 0.464, 0.32, 0.48, 0.314)
                pen.close()
                return pen.path
            },
            Part(name: "billTip", level: .middle, paint: .color(tone.billTip)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.376), 0.013, 0.007)
                return pen.path
            },
        ]
        return parts
    }

    /// The long neck from the top of the body up behind the head, bending
    /// gently to one side and back as a swan's does.
    private static func swanNeck(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.tube(critterSpine(CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.56, y: 0.52), CGPoint(x: 0.44, y: 0.44),
                              CGPoint(x: 0.5, y: 0.34), count: 12), widths: (0.19, 0.13))
        return pen.path
    }

    /// The little gold tiara on its crown: a band with five points, the
    /// middle one tallest, tipped with round beads.
    private static func swanTiara(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.move(0.44, 0.142)
        pen.line(0.436, 0.112)
        pen.line(0.462, 0.126)
        pen.line(0.48, 0.096)
        pen.line(0.5, 0.078)
        pen.line(0.52, 0.096)
        pen.line(0.538, 0.126)
        pen.line(0.564, 0.112)
        pen.line(0.56, 0.142)
        pen.quad(0.44, 0.142, 0.5, 0.15)
        pen.close()
        for (x, y, r) in [(0.436, 0.108, 0.008), (0.5, 0.074, 0.009), (0.564, 0.108, 0.008)] as [(CGFloat, CGFloat, CGFloat)] {
            pen.oval(CGPoint(x: x, y: y), r, r)
        }
        return pen.path
    }

    /// Both wings: a broad wing folded down each side from the shoulder, or
    /// the three long feathers at its end, raised and spread as the pose
    /// says.
    private static func swanWings(_ pose: CritterPose, primaries: Bool, size: CGFloat) -> CGPath {
        let shape = swanPose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), shape.leftWing), (CGFloat(1), shape.rightWing)] {
            let shoulder = CGPoint(x: 0.5 + side * (swanShoulder.x - 0.5), y: swanShoulder.y)
            let heading = side * angle
            let wrist = critterReach(shoulder, heading, swanWingLength)
            if primaries {
                // Three soft rounded feather tips peeking out from under the
                // wing's end, fanned as the pose says.
                for (index, spread) in [-17, 0, 17].enumerated() {
                    let turn = heading + side * CGFloat(spread) * shape.fan
                    let reach: CGFloat = index == 1 ? 0.034 : 0.022
                    pen.oval(critterReach(wrist, turn, reach), 0.024, index == 1 ? 0.046 : 0.04, tilt: -turn)
                }
            } else {
                pen.feather(critterReach(shoulder, heading, -0.035), critterReach(wrist, heading, 0.02), width: 0.14,
                            curl: side * 0.05)
            }
        }
        return pen.path
    }

    /// Two little webbed feet on short legs, one lifted in a step.
    private static func swanFeet(_ pose: CritterPose, size: CGFloat) -> CGPath {
        let shape = swanPose(pose)
        let pen = CritterPen(size: size)
        for (side, lift) in [(CGFloat(-1), shape.leftFoot), (CGFloat(1), shape.rightFoot)] {
            let x = 0.5 + side * 0.055
            let ankle = CGPoint(x: x, y: 0.868 - lift)
            pen.limb(CGPoint(x: x, y: 0.82), ankle, (0.03, 0.024))
            // A webbed foot: three toes joined by scalloped webbing.
            pen.move(ankle.x, ankle.y - 0.008)
            pen.line(ankle.x - 0.042, ankle.y + 0.026)
            pen.quad(ankle.x - 0.014, ankle.y + 0.028, ankle.x - 0.028, ankle.y + 0.036)
            pen.quad(ankle.x + 0.014, ankle.y + 0.028, ankle.x, ankle.y + 0.036)
            pen.quad(ankle.x + 0.042, ankle.y + 0.026, ankle.x + 0.028, ankle.y + 0.036)
            pen.close()
        }
        return pen.path
    }

    /// The short tail behind the body to the right of the screen, three
    /// soft feathers in a little fan, tipped up `tail` degrees and swaying
    /// with `phase`.
    private static func swanTail(_ pose: CritterPose, phase: CGFloat, size: CGFloat) -> CGPath {
        let lift = swanPose(pose).tail
        let sway = 5 * sin(phase * 2 * .pi)
        let pen = CritterPen(size: size)
        let base = CGPoint(x: 0.6, y: 0.76)
        for (index, angle) in [108, 124, 140].enumerated() {
            let length: CGFloat = index == 1 ? 0.17 : 0.145
            let turn = CGFloat(angle) + lift + sway * (index == 1 ? 1 : 0.7)
            pen.oval(critterReach(base, turn, length * 0.55), 0.034, length * 0.55, tilt: -turn)
        }
        return pen.path
    }
}

/// The swan's trim: a pale breast and wings a breath deeper than its body
/// with darker tips, an orange bill with a black knob and a pale nail at
/// its tip, orange feet, and a gold tiara with a jewel; a dark swan gets a
/// red bill with a white tip and light scallops, as a black swan has.
private struct SwanTone {
    var breast: NotchMascotColor
    var breastLow: NotchMascotColor
    var scallop: NotchMascotColor
    var wing: NotchMascotColor
    var wingLow: NotchMascotColor
    var tip: NotchMascotColor
    var bill: NotchMascotColor
    var billLow: NotchMascotColor
    var billTip: NotchMascotColor
    var knob: NotchMascotColor
    var foot: NotchMascotColor
    var cheek: NotchMascotColor
    var gold: NotchMascotColor
    var goldDeep: NotchMascotColor
    var jewel: NotchMascotColor

    init(_ colors: NotchMascotCritterColors) {
        typealias C = NotchMascotCritterColors
        breast = colors.dark ? colors.light.brightened(0.18) : colors.light.brightened(0.5)
        breastLow = colors.dark ? colors.fur(0.3).brightened(0.1) : colors.fur(0.25).brightened(0.25)
        scallop = colors.dark ? colors.light.brightened(0.45).withAlpha(0.45) : colors.shade.withAlpha(0.35)
        wing = colors.dark ? colors.fur(0.2).brightened(0.08) : colors.light.brightened(0.3)
        wingLow = colors.fur(0.55)
        tip = colors.dark ? colors.shade.darkened(0.25) : colors.shade.darkened(0.08)
        if colors.dark {
            bill = C.rgb(0xF2564A)
            billLow = C.rgb(0xC9302C)
            billTip = C.rgb(0xF4F1EA)
        } else {
            bill = C.rgb(0xFFA63D)
            billLow = C.rgb(0xF27A1A)
            billTip = C.rgb(0xFFD9A0)
        }
        knob = C.rgb(0x22222A)
        foot = colors.dark ? C.rgb(0x5A5A66) : C.rgb(0xF58A2A)
        cheek = C.rgb(0xFF7FA0).withAlpha(0.34)
        gold = C.rgb(0xFFE38A)
        goldDeep = C.rgb(0xE8A93A)
        jewel = C.rgb(0xFF7FB0)
    }
}
