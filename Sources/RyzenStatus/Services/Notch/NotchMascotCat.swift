// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The cat: a chibi kitten sitting up, front on, its fur in the body's
/// colours. A wide round head with fluffy cheeks under two pointed ears with
/// pink insides, tabby stripes on its brow, a pale muzzle with a little pink
/// nose and long whiskers, white socks on its front paws and hind feet, and
/// a thick striped tail that curls up beside it like a question mark.
/// Asleep it lets its ears relax, tucks its paws together and wraps its tail
/// round on the floor.
extension NotchMascotCreatures {
    /// How the cat holds itself in a pose: each ear turned out from upright,
    /// in degrees; each front leg's angle from hanging down, out to its own
    /// side; how its tail curls, from wrapped round on the floor at 0 to up
    /// beside it at 1 and held high above 1, and how far its tip leans; how
    /// high each foot is lifted.
    private struct CatPose {
        var leftEar: CGFloat
        var rightEar: CGFloat
        var leftArm: CGFloat
        var rightArm: CGFloat
        var tail: CGFloat
        var lean: CGFloat = 0
        var leftFoot: CGFloat = 0
        var rightFoot: CGFloat = 0
    }

    private static func catPose(_ pose: CritterPose) -> CatPose {
        switch pose {
        case .rest: return CatPose(leftEar: 0, rightEar: 0, leftArm: -8, rightArm: -8, tail: 1)
        case .asleep: return CatPose(leftEar: 14, rightEar: 14, leftArm: -34, rightArm: -34, tail: 0)
        case .cheer: return CatPose(leftEar: -6, rightEar: -6, leftArm: 155, rightArm: 155, tail: 1.25)
        case .wave: return CatPose(leftEar: 0, rightEar: 6, leftArm: -8, rightArm: 145, tail: 1.1, lean: 0.02)
        case .waveOut: return CatPose(leftEar: 0, rightEar: -4, leftArm: -8, rightArm: 108, tail: 1.05, lean: -0.02)
        case .bow: return CatPose(leftEar: 14, rightEar: 14, leftArm: 4, rightArm: 4, tail: 0.8)
        // A flick of one ear, and nothing else, so the cat can twitch its
        // ears now and then without moving the rest of it.
        case .twitch: return CatPose(leftEar: 4, rightEar: 28, leftArm: -8, rightArm: -8, tail: 1)
        case .spread: return CatPose(leftEar: -4, rightEar: -4, leftArm: 96, rightArm: 96, tail: 1.2)
        case .step: return CatPose(leftEar: 2, rightEar: -2, leftArm: -4, rightArm: -26, tail: 0.95, lean: 0.03,
                                   leftFoot: 0.026)
        case .stepOther: return CatPose(leftEar: -2, rightEar: 2, leftArm: -26, rightArm: -4, tail: 0.95, lean: -0.03,
                                        rightFoot: 0.026)
        }
    }

    private static let catChest = (center: CGPoint(x: 0.5, y: 0.735), rx: CGFloat(0.15), ry: CGFloat(0.155))
    /// The right haunch, where it sits; the left is its mirror.
    private static let catHaunch = (center: CGPoint(x: 0.612, y: 0.825), rx: CGFloat(0.078), ry: CGFloat(0.068))
    /// Where the right front leg joins the body, and how long it is.
    private static let catShoulder = CGPoint(x: 0.588, y: 0.648)
    private static let catArm: CGFloat = 0.096
    /// The right ear: its inner corner, its tip and its outer corner, and
    /// where it turns, at its root.
    private static let catEar = (inner: CGPoint(x: 0.565, y: 0.268), tip: CGPoint(x: 0.73, y: 0.112),
                                 outer: CGPoint(x: 0.716, y: 0.37), root: CGPoint(x: 0.645, y: 0.31))
    /// The head's box: wide at the cheeks, a little flat on top.
    static let catHeadBox = CGRect(x: 0.258, y: 0.248, width: 0.484, height: 0.352)

    /// A wide head with fluffy cheeks over a round chest and two haunches.
    static func catBody(size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        catHead(pen)
        pen.oval(catChest.center, catChest.rx, catChest.ry)
        for side in [-1, 1] as [CGFloat] {
            pen.oval(CGPoint(x: 0.5 + side * (catHaunch.center.x - 0.5), y: catHaunch.center.y), catHaunch.rx, catHaunch.ry)
        }
        return pen.path
    }

    /// The head: round on top, out to a soft tuft at each cheek and in to a
    /// round chin.
    private static func catHead(_ pen: CritterPen) {
        pen.move(0.5, 0.248)
        pen.curve(0.705, 0.352, 0.61, 0.248, 0.682, 0.29)
        pen.curve(0.742, 0.49, 0.728, 0.41, 0.74, 0.452)
        pen.quad(0.716, 0.52, 0.728, 0.502)
        pen.curve(0.5, 0.6, 0.69, 0.575, 0.605, 0.6)
        pen.curve(0.284, 0.52, 0.395, 0.6, 0.31, 0.575)
        pen.quad(0.258, 0.49, 0.272, 0.502)
        pen.curve(0.295, 0.352, 0.26, 0.452, 0.272, 0.41)
        pen.curve(0.5, 0.248, 0.318, 0.29, 0.39, 0.248)
        pen.close()
    }

    static var catAnatomy: NotchMascotAnatomy {
        let hand = critterReach(catShoulder, -8, catArm)
        return NotchMascotAnatomy(rightHand: hand, leftHand: critterMirror(hand), floor: 0.9, leftFoot: 0.415,
                                  rightFoot: 0.585, foot: 0.1, torso: CGRect(x: 0.36, y: 0.6, width: 0.28, height: 0.28),
                                  nose: CGPoint(x: 0.5, y: 0.515), mouth: CGPoint(x: 0.5, y: 0.552))
    }

    // MARK: Parts

    static func catParts(colors: NotchMascotCritterColors, hat: Bool, size: CGFloat) -> [NotchMascotCritterPart] {
        typealias Part = NotchMascotCritterPart
        let tone = CatTone(colors)
        return [
            Part(name: "tail", level: .back, paint: .fur(tone: -0.04), idle: (3.6, 12)) { pose, phase in
                catTail(pose, phase: phase, stripes: false, size: size)
            },
            Part(name: "tailStripes", level: .back, paint: .color(tone.stripe), idle: (3.6, 12)) { pose, phase in
                catTail(pose, phase: phase, stripes: true, size: size)
            },
            Part(name: "ears", level: .back, paint: .fur(tone: 0.02)) { pose, _ in
                catEars(pose, inner: false, hat: hat, size: size)
            },
            Part(name: "innerEars", level: .back, paint: .gradient([tone.innerEar, tone.innerEarDeep],
                                                                     from: CGPoint(x: 0.5, y: 0.14), to: CGPoint(x: 0.5, y: 0.32))) {
                pose, _ in
                catEars(pose, inner: true, hat: hat, size: size)
            },
            Part(name: "belly", level: .middle, paint: .color(tone.belly)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.5, y: 0.745), 0.082, 0.122)
                return pen.path
            },
            Part(name: "feet", level: .middle, paint: .color(tone.paw)) { pose, _ in
                let lifts = catPose(pose)
                let pen = CritterPen(size: size)
                for (side, lift) in [(CGFloat(-1), lifts.leftFoot), (CGFloat(1), lifts.rightFoot)] {
                    pen.oval(CGPoint(x: 0.5 + side * 0.085, y: 0.878 - lift), 0.05, 0.028, tilt: side * 8)
                }
                return pen.path
            },
            Part(name: "stripes", level: .middle, paint: .color(tone.stripe)) { _, _ in
                let pen = CritterPen(size: size)
                // An M on its brow, and two strokes out on each cheek.
                pen.feather(CGPoint(x: 0.5, y: 0.252), CGPoint(x: 0.5, y: 0.328), width: 0.02)
                for side in [-1, 1] as [CGFloat] {
                    pen.feather(CGPoint(x: 0.5 + side * 0.048, y: 0.256), CGPoint(x: 0.5 + side * 0.034, y: 0.316), width: 0.018)
                    pen.feather(CGPoint(x: 0.5 + side * 0.24, y: 0.424), CGPoint(x: 0.5 + side * 0.182, y: 0.434), width: 0.014)
                    pen.feather(CGPoint(x: 0.5 + side * 0.244, y: 0.46), CGPoint(x: 0.5 + side * 0.19, y: 0.466), width: 0.014)
                }
                return pen.path
            },
            Part(name: "cheeks", level: .middle, paint: .color(tone.cheek)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.36, y: 0.515), 0.034, 0.02)
                pen.oval(CGPoint(x: 0.64, y: 0.515), 0.034, 0.02)
                return pen.path
            },
            Part(name: "muzzle", level: .middle, paint: .color(tone.belly)) { _, _ in
                let pen = CritterPen(size: size)
                pen.oval(CGPoint(x: 0.47, y: 0.538), 0.04, 0.03)
                pen.oval(CGPoint(x: 0.53, y: 0.538), 0.04, 0.03)
                return pen.path
            },
            Part(name: "whiskers", level: .middle, paint: .line(tone.whisker, width: 0.0075)) { pose, _ in
                catWhiskers(pose, size: size)
            },
            Part(name: "nose", level: .middle, paint: .gradient([tone.noseLight, tone.nose], from: CGPoint(x: 0.5, y: 0.5),
                                                                to: CGPoint(x: 0.5, y: 0.53))) { _, _ in
                let pen = CritterPen(size: size)
                pen.move(0.5, 0.53)
                pen.curve(0.475, 0.508, 0.488, 0.528, 0.475, 0.518)
                pen.curve(0.525, 0.508, 0.475, 0.497, 0.525, 0.497)
                pen.curve(0.5, 0.53, 0.525, 0.518, 0.512, 0.528)
                pen.close()
                return pen.path
            },
            Part(name: "arms", level: .middle, paint: .fur(tone: -0.05)) { pose, _ in
                catArms(pose, paws: false, size: size)
            },
            Part(name: "paws", level: .middle, paint: .color(tone.paw)) { pose, _ in
                catArms(pose, paws: true, size: size)
            },
        ]
    }

    /// Both ears, pointed and turned out from their roots, or their pink
    /// insides. Under a hat they lie out to the sides, smaller, and peek
    /// out under its brim.
    private static func catEars(_ pose: CritterPose, inner: Bool, hat: Bool, size: CGFloat) -> CGPath {
        let angles = catPose(pose)
        let pen = CritterPen(size: size)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        for (side, angle) in [(CGFloat(-1), angles.leftEar), (CGFloat(1), angles.rightEar)] {
            func mirrored(_ p: CGPoint) -> CGPoint { CGPoint(x: 0.5 + side * (p.x - 0.5), y: p.y) }
            let root = mirrored(catEar.root)
            var corners = [catEar.inner, catEar.tip, catEar.outer].map(mirrored)
            if hat { corners = corners.map { lerp(root, $0, 0.8) } }
            if inner {
                // The same ear drawn smaller toward its middle, a little low.
                let middle = CGPoint(x: (corners[0].x + corners[1].x + corners[2].x) / 3,
                                     y: (corners[0].y + corners[1].y + corners[2].y) / 3 + 0.012)
                corners = corners.map { lerp(middle, $0, 0.6) }
            }
            pen.turning(side * (angle + (hat ? 50 : 0)), about: root)
            let (a, tip, b) = (corners[0], corners[1], corners[2])
            let low = lerp(lerp(a, b, 0.5), mirrored(CGPoint(x: 0.645, y: 0.36)), inner ? 0.2 : 1)
            pen.move(a.x, a.y)
            let up = lerp(a, tip, 0.74), down = lerp(b, tip, 0.74)
            pen.line(up.x, up.y)
            pen.quad(down.x, down.y, tip.x, tip.y)
            pen.line(b.x, b.y)
            pen.quad(a.x, a.y, low.x, low.y)
            pen.close()
            pen.straight()
        }
        return pen.path
    }

    /// The front legs from the shoulders, or the white socks at their ends.
    private static func catArms(_ pose: CritterPose, paws: Bool, size: CGFloat) -> CGPath {
        let angles = catPose(pose)
        let pen = CritterPen(size: size)
        for (side, angle) in [(CGFloat(-1), angles.leftArm), (CGFloat(1), angles.rightArm)] {
            let shoulder = CGPoint(x: 0.5 + side * (catShoulder.x - 0.5), y: catShoulder.y)
            let hand = critterReach(shoulder, side * angle, catArm)
            if paws {
                pen.oval(hand, 0.03, 0.025, tilt: side * angle * 0.3)
            } else {
                pen.limb(shoulder, hand, (0.052, 0.042))
            }
        }
        return pen.path
    }

    /// Three long whiskers either side of the muzzle, drooping a little
    /// asleep.
    private static func catWhiskers(_ pose: CritterPose, size: CGFloat) -> CGPath {
        let pen = CritterPen(size: size)
        let droop: CGFloat = pose == .asleep ? 0.018 : 0
        for side in [-1, 1] as [CGFloat] {
            for rise in [-0.026, 0, 0.026] as [CGFloat] {
                pen.move(0.5 + side * 0.085, 0.534 + rise * 0.3)
                pen.quad(0.5 + side * 0.3, 0.518 + rise * 1.35 + droop,
                         0.5 + side * 0.2, 0.522 + rise * 0.8 + droop * 0.4)
            }
        }
        return pen.path
    }

    /// The thick tail: out from behind it along the floor and up its side,
    /// its tip curling back over like a question mark, held as high as
    /// `tail` in the pose says and swaying with `phase`; or the stripes
    /// across it.
    private static func catTail(_ pose: CritterPose, phase: CGFloat, stripes: Bool, size: CGFloat) -> CGPath {
        let held = catPose(pose)
        let sway = sin(phase * 2 * .pi) * 0.032 + held.lean
        let floor = [CGPoint(x: 0.6, y: 0.855), CGPoint(x: 0.86, y: 0.9), CGPoint(x: 0.8, y: 0.975), CGPoint(x: 0.43, y: 0.935)]
        let up = [CGPoint(x: 0.6, y: 0.855), CGPoint(x: 0.88, y: 0.93), CGPoint(x: 0.93, y: 0.6), CGPoint(x: 0.81, y: 0.5)]
        let high = [CGPoint(x: 0.6, y: 0.855), CGPoint(x: 0.84, y: 0.9), CGPoint(x: 0.92, y: 0.48), CGPoint(x: 0.79, y: 0.37)]
        let (from, to, share) = held.tail <= 1 ? (floor, up, held.tail) : (up, high, (held.tail - 1) / 0.25)
        var keys = zip(from, to).map { a, b in CGPoint(x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share) }
        let reach = min(1, held.tail)
        keys[2].x += sway * 0.5 * reach
        keys[3].x += sway * reach
        let spine = critterSpine(keys[0], keys[1], keys[2], keys[3], count: 14)
        let widths: (CGFloat, CGFloat) = (0.064, 0.05)
        let pen = CritterPen(size: size)
        guard stripes else {
            pen.tube(spine, widths: widths)
            return pen.path
        }
        for index in [7, 9, 11] {
            let share = CGFloat(index) / CGFloat(spine.count - 1)
            let half = (widths.0 + (widths.1 - widths.0) * share) / 2 * 1.02
            let (ux, uy) = critterUnit(spine[index - 1], spine[index + 1])
            let center = spine[index]
            pen.feather(CGPoint(x: center.x - uy * half, y: center.y + ux * half),
                        CGPoint(x: center.x + uy * half, y: center.y - ux * half), width: 0.026)
        }
        return pen.path
    }
}

/// The cat's pinks, stripes and white socks: pink ear insides and nose that
/// lean toward its own hue, tabby stripes a deep tone of its fur, and a
/// belly, muzzle and paws much paler than it, so a dark cat wears a
/// tuxedo's white and a light one a ginger's or a grey's stripes.
private struct CatTone {
    var innerEar: NotchMascotColor
    var innerEarDeep: NotchMascotColor
    var nose: NotchMascotColor
    var noseLight: NotchMascotColor
    var paw: NotchMascotColor
    var belly: NotchMascotColor
    var cheek: NotchMascotColor
    var whisker: NotchMascotColor
    var stripe: NotchMascotColor

    init(_ colors: NotchMascotCritterColors) {
        typealias C = NotchMascotCritterColors
        let pink = C.rgb(0xFFA9C0)
        innerEar = C.mix(pink, colors.light, colors.dark ? 0.1 : 0.2)
        innerEarDeep = C.mix(C.rgb(0xF27FA0), colors.shade, 0.15)
        nose = C.rgb(0xF0648C)
        noseLight = C.rgb(0xFF9DB8)
        belly = colors.dark ? colors.light.brightened(0.72) : colors.light.brightened(0.62)
        paw = colors.dark ? colors.light.brightened(0.86) : colors.light.brightened(0.8)
        cheek = C.rgb(0xFF7F9F).withAlpha(0.34)
        whisker = colors.dark ? colors.light.brightened(0.5).withAlpha(0.75) : colors.shade.darkened(0.45).withAlpha(0.6)
        stripe = colors.dark ? colors.shade.darkened(0.35).withAlpha(0.55) : colors.shade.darkened(0.28).withAlpha(0.5)
    }
}
