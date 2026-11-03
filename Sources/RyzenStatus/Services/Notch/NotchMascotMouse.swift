// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The mouse: a tiny round mouse sitting up, front on, its fur in the
/// body's colours. Two big round ears with pink insides, a pale muzzle with
/// a pink nose and whiskers, little pink paws at its sides, two
/// feet, a pale belly and a long thin pink tail that curls up behind it.
/// Asleep it lays its ears back, tucks its paws under its chin and curls
/// its tail round on the floor.
extension NotchMascotCreatures {
    /// How the mouse holds itself in a pose: each ear turned out from
    /// upright, in degrees; each arm's angle from hanging down, out to its
    /// own side; how its tail curls, from lying on the floor at 0 to
    /// curled up behind it at 1; how high each foot is lifted.
    private struct MousePose {
        var leftEar: CGFloat
        var rightEar: CGFloat
        var leftArm: CGFloat
        var rightArm: CGFloat
        var tail: CGFloat
        var leftFoot: CGFloat = 0
        var rightFoot: CGFloat = 0
    }

    private static func mousePose(_ pose: CritterPose) -> MousePose {
        switch pose {
        case .rest: return MousePose(leftEar: 0, rightEar: 0, leftArm: 4, rightArm: 4, tail: 1)
        case .asleep: return MousePose(leftEar: 34, rightEar: 34, leftArm: -150, rightArm: -150, tail: 0)
        case .cheer: return MousePose(leftEar: -8, rightEar: -8, leftArm: 158, rightArm: 158, tail: 1.2)
        case .wave: return MousePose(leftEar: 0, rightEar: 6, leftArm: 4, rightArm: 150, tail: 1.1)
        case .waveOut: return MousePose(leftEar: 0, rightEar: -4, leftArm: 4, rightArm: 112, tail: 1)
        case .bow: return MousePose(leftEar: 16, rightEar: 16, leftArm: 12, rightArm: 12, tail: 0.8)
        case .twitch: return MousePose(leftEar: -14, rightEar: 14, leftArm: -30, rightArm: -30, tail: 1.25)
        case .spread: return MousePose(leftEar: -6, rightEar: -6, leftArm: 96, rightArm: 96, tail: 1.2)
        case .step: return MousePose(leftEar: 4, rightEar: -4, leftArm: 18, rightArm: -10, tail: 0.85, leftFoot: 0.028)
        case .stepOther: return MousePose(leftEar: -4, rightEar: 4, leftArm: -10, rightArm: 18, tail: 0.95, rightFoot: 0.028)
        }
    }

    private static let mouseHead = (center: CGPoint(x: 0.5, y: 0.44), rx: CGFloat(0.2), ry: CGFloat(0.172))
    private static let mouseChest = (center: CGPoint(x: 0.5, y: 0.725), rx: CGFloat(0.132), ry: CGFloat(0.14))
    /// Where the right arm joins the body, and how long it is.
    private static let mouseShoulder = CGPoint(x: 0.585, y: 0.64)
    private static let mouseArm: CGFloat = 0.085
    /// The middle of the right ear and where it turns, at its root.
    private static let mouseEar = (center: CGPoint(x: 0.705, y: 0.255), radius: CGFloat(0.135), root: CGPoint(x: 0.63, y: 0.34))

    /// A big round head over a small pear of a body.
    static func mouseBody(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        pen.oval(mouseHead.center, mouseHead.rx, mouseHead.ry)
        pen.oval(mouseChest.center, mouseChest.rx, mouseChest.ry)
        return pen.path
    }

    static var mouseAnatomy: NotchMascotAnatomy {
        let hand = critterReach(mouseShoulder, 4, mouseArm)
        return NotchMascotAnatomy(rightHand: hand, leftHand: critterMirror(hand), floor: 0.9, leftFoot: 0.445,
                                  rightFoot: 0.555, foot: 0.09, torso: CGRect(x: 0.37, y: 0.6, width: 0.26, height: 0.26),
                                  nose: CGPoint(x: 0.5, y: 0.49), mouth: CGPoint(x: 0.5, y: 0.535))
    }

    // MARK: Parts

    static func mouseParts(colors: NotchMascotCritterColors, size: CGFloat) -> [NotchMascotCritterPart] {
        typealias Part = NotchMascotCritterPart
        let tone = MouseTone(colors)
        return [
            Part(name: "tail", level: .back, paint: .color(tone.tail), idle: (3.2, 10)) { pose, phase in
                mouseTail(pose, phase: phase, size: size)
            },
            Part(name: "ears", level: .back, paint: .fur(tone: 0.04)) { pose, _ in
                mouseEars(pose, inner: false, size: size)
            },
            Part(name: "innerEars", level: .back, paint: .gradient([tone.innerEar, tone.innerEarDeep],
                                                                     from: CGPoint(x: 0.5, y: 0.14), to: CGPoint(x: 0.5, y: 0.36))) {
                pose, _ in
                mouseEars(pose, inner: true, size: size)
            },
            Part(name: "feet", level: .back, paint: .color(tone.paw)) { pose, _ in
                let lifts = mousePose(pose)
                let pen = CritterPen(size: size)
                for (side, lift) in [(CGFloat(-1), lifts.leftFoot), (CGFloat(1), lifts.rightFoot)] {
                    pen.oval(CGPoint(x: 0.5 + side * 0.058, y: 0.872 - lift), 0.048, 0.027, tilt: side * 12)
                }
                return pen.path
            },
            Part(name: "belly", level: .middle, paint: .color(tone.belly)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.745), 0.088, 0.1)
                return pen.path
            },
            Part(name: "cheeks", level: .middle, paint: .color(tone.cheek)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.37, y: 0.5), 0.032, 0.019)
                pen.oval(CGPoint(x: 0.63, y: 0.5), 0.032, 0.019)
                return pen.path
            },
            Part(name: "muzzle", level: .middle, paint: .color(tone.belly)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.47, y: 0.515), 0.042, 0.034)
                pen.oval(CGPoint(x: 0.53, y: 0.515), 0.042, 0.034)
                return pen.path
            },
            Part(name: "whiskers", level: .middle, paint: .line(tone.whisker, width: 0.008), idle: (2.4, 8)) { pose, phase in
                mouseWhiskers(pose, phase: phase, size: size)
            },
            Part(name: "nose", level: .middle, paint: .gradient([tone.noseLight, tone.nose], from: CGPoint(x: 0.5, y: 0.47),
                                                                to: CGPoint(x: 0.5, y: 0.505))) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.49), 0.024, 0.017)
                return pen.path
            },
            Part(name: "arms", level: .middle, paint: .fur(tone: -0.06)) { pose, _ in
                mouseArms(pose, paws: false, size: size)
            },
            Part(name: "paws", level: .middle, paint: .color(tone.paw)) { pose, _ in
                mouseArms(pose, paws: true, size: size)
            },
        ]
    }

    /// Both ears, round and big, turned out from their roots; or their
    /// pink insides, a little lower and nearer the middle.
    private static func mouseEars(_ pose: CritterPose, inner: Bool, size: CGFloat) -> CGPath {
        let angles = mousePose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), angles.leftEar), (CGFloat(1), angles.rightEar)] {
            let root = CGPoint(x: 0.5 + side * (mouseEar.root.x - 0.5), y: mouseEar.root.y)
            pen.turning(side * angle, about: root)
            let center = CGPoint(x: 0.5 + side * (mouseEar.center.x - 0.5), y: mouseEar.center.y)
            if inner {
                pen.oval(CGPoint(x: center.x - side * 0.012, y: center.y + 0.014), mouseEar.radius * 0.64, mouseEar.radius * 0.66)
            } else {
                pen.oval(center, mouseEar.radius, mouseEar.radius * 0.98)
            }
            pen.straight()
        }
        return pen.path
    }

    /// The arms from the shoulders, or the little round paws at their ends.
    private static func mouseArms(_ pose: CritterPose, paws: Bool, size: CGFloat) -> CGPath {
        let angles = mousePose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), angles.leftArm), (CGFloat(1), angles.rightArm)] {
            let shoulder = CGPoint(x: 0.5 + side * (mouseShoulder.x - 0.5), y: mouseShoulder.y)
            let hand = critterReach(shoulder, side * angle, mouseArm)
            if paws {
                pen.oval(hand, 0.024, 0.021, tilt: side * angle * 0.3)
            } else {
                pen.limb(shoulder, hand, (0.046, 0.036))
            }
        }
        return pen.path
    }

    /// Three whiskers either side of the nose, quivering with `phase`.
    private static func mouseWhiskers(_ pose: CritterPose, phase: CGFloat, size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        let quiver = sin(phase * 2 * .pi) * 0.008
        let droop: CGFloat = pose == .asleep ? 0.02 : 0
        for side in [-1, 1] as [CGFloat] {
            for (index, rise) in [-0.03, 0, 0.03].enumerated() {
                let wobble = quiver * (index == 1 ? -1 : 1)
                pen.move(0.5 + side * 0.055, 0.508 + rise * 0.25)
                pen.quad(0.5 + side * 0.205, 0.5 + rise * 1.4 + droop + wobble,
                         0.5 + side * 0.13, 0.497 + rise * 0.7 + droop * 0.5)
            }
        }
        return pen.path
    }

    /// The long thin tail: out from behind the body along the floor and,
    /// as `tail` in the pose grows, curling up behind it in a hook, swaying
    /// with `phase`.
    private static func mouseTail(_ pose: CritterPose, phase: CGFloat, size: CGFloat) -> CGPath {
        let curl = mousePose(pose).tail
        let sway = sin(phase * 2 * .pi) * 0.022
        let pen = CritterPen(size: size)
        let start = CGPoint(x: 0.56, y: 0.83)
        let tip = CGPoint(x: 0.88 - 0.1 * (1 - curl) + sway, y: 0.9 - 0.32 * curl)
        let spine = critterSpine(start, CGPoint(x: 0.7, y: 0.93),
                                 CGPoint(x: 0.94 + sway * 0.5, y: 0.94 - 0.12 * curl),
                                 tip, count: 14)
        pen.tube(spine, widths: (0.028, 0.012))
        // The hook at its tip.
        let hookEnd = CGPoint(x: tip.x - 0.05 * curl - 0.02, y: tip.y - 0.035 * curl + 0.02 * (1 - curl))
        pen.tube(critterSpine(spine[spine.count - 2], CGPoint(x: tip.x + 0.02, y: tip.y - 0.05 * curl),
                              CGPoint(x: hookEnd.x + 0.03, y: hookEnd.y - 0.03), hookEnd, count: 6), widths: (0.013, 0.009))
        return pen.path
    }
}

/// The mouse's pinks and pale parts: pink ear insides, nose, paws and tail
/// that lean toward its own hue, and a belly and muzzle a little paler than
/// its fur, so it is a mouse on any colour.
private struct MouseTone {
    var innerEar: NotchMascotColor
    var innerEarDeep: NotchMascotColor
    var nose: NotchMascotColor
    var noseLight: NotchMascotColor
    var paw: NotchMascotColor
    var tail: NotchMascotColor
    var belly: NotchMascotColor
    var cheek: NotchMascotColor
    var whisker: NotchMascotColor

    init(_ colors: NotchMascotCritterColors) {
        typealias C = NotchMascotCritterColors
        let pink = C.rgb(0xFFA9C0)
        innerEar = C.mix(pink, colors.light, colors.dark ? 0.1 : 0.22)
        innerEarDeep = C.mix(C.rgb(0xF27FA0), colors.shade, 0.15)
        nose = C.rgb(0xF0648C)
        noseLight = C.rgb(0xFF9DB8)
        paw = C.mix(C.rgb(0xFFC2D2), colors.light, colors.dark ? 0.15 : 0.35)
        tail = C.mix(C.rgb(0xF2A0B6), colors.shade, 0.25)
        belly = colors.dark ? colors.light.brightened(0.3) : colors.light.brightened(0.6)
        cheek = C.rgb(0xFF7F9F).withAlpha(0.34)
        whisker = colors.dark ? colors.light.brightened(0.5).withAlpha(0.75) : colors.shade.darkened(0.45).withAlpha(0.6)
    }
}
