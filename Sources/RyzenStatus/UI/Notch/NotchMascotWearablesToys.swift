// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The twelve toys and charms of luck, traced with a few bold paths like the
/// rest: what it holds sits in its right hand, what it wears on its feet
/// on its own two feet, and the parrot on its left shoulder.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func toyParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        let right = f.rightHand
        // Its left shoulder: the top corner of the torso where it has one
        // apart from its head, kept clear of the face. A figure that is one
        // round shape has no shoulder, and its sides slope away into thin
        // air, so the parrot perches on top of it, a little to the left.
        let shoulder = f.anatomy == nil
            ? CGPoint(x: f.outline.minX + w * 0.04, y: f.outline.minY + f.outline.height * 0.3)
            : !f.separateBody ? CGPoint(x: cx - w * 0.2, y: top + f.outline.height * 0.1)
            : CGPoint(x: min(f.torso.minX + f.torso.width * 0.12, f.outline.minX) - f.prop * 0.08, y: f.torso.minY + w * 0.04)
        let feet = f.floor
        let fc = f.feetCenter, fu = f.feetUnit
        let s = f.prop
        let ink = rgb(0x16161C)

        func p(_ origin: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: origin.x + dx * s, y: origin.y + dy * s) }
        func poly(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
            return path
        }
        func stroke(_ a: CGPoint, _ b: CGPoint) -> CGPath {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            return path
        }

        switch accessory {
        case .propellerCap:
            // A beanie in four colours with a red propeller on a stalk.
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.3, y: top + w * 0.08))
            dome.addQuadCurve(to: CGPoint(x: cx + w * 0.3, y: top + w * 0.08), control: CGPoint(x: cx, y: top - w * 0.3))
            dome.closeSubpath()
            let seams = CGMutablePath()
            seams.addPath(stroke(CGPoint(x: cx, y: top - w * 0.11), CGPoint(x: cx, y: top + w * 0.08)))
            seams.addPath(stroke(CGPoint(x: cx - w * 0.14, y: top - w * 0.06), CGPoint(x: cx - w * 0.16, y: top + w * 0.08)))
            seams.addPath(stroke(CGPoint(x: cx + w * 0.14, y: top - w * 0.06), CGPoint(x: cx + w * 0.16, y: top + w * 0.08)))
            let blades = CGMutablePath()
            blades.addEllipse(in: CGRect(x: cx - w * 0.26, y: top - w * 0.24, width: w * 0.24, height: w * 0.07))
            blades.addEllipse(in: CGRect(x: cx + w * 0.02, y: top - w * 0.24, width: w * 0.24, height: w * 0.07))
            return [Part(path: dome, fill: rgb(0x3A86FF), stroke: ink, lineWidth: line * 0.5),
                    Part(path: seams, fill: nil, stroke: rgb(0xFFD23F), lineWidth: line * 0.8),
                    Part(path: stroke(CGPoint(x: cx, y: top - w * 0.11), CGPoint(x: cx, y: top - w * 0.2)), fill: nil,
                         stroke: ink, lineWidth: line * 0.7),
                    Part(path: blades, fill: rgb(0xFF4D4D), stroke: ink, lineWidth: line * 0.4),
                    Part(path: circle(CGPoint(x: cx, y: top - w * 0.205), w * 0.03), fill: rgb(0xFFD23F))]

        case .parrot:
            // A green parrot on the shoulder: red cap, hooked beak, long tail.
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: shoulder.x - s * 0.22, y: shoulder.y - s * 0.42, width: s * 0.36, height: s * 0.5))
            let tail = poly([p(shoulder, -0.12, 0.02), p(shoulder, -0.02, 0.06), p(shoulder, -0.16, 0.46)])
            let beak = poly([p(shoulder, 0.1, -0.36), p(shoulder, 0.26, -0.32), p(shoulder, 0.12, -0.24)])
            return [Part(path: tail, fill: rgb(0x2EC4B6), stroke: ink, lineWidth: line * 0.4),
                    Part(path: body, fill: rgb(0x38B000), stroke: ink, lineWidth: line * 0.5),
                    Part(path: circle(p(shoulder, -0.02, -0.38), s * 0.1), fill: rgb(0xE63946)),
                    Part(path: beak, fill: rgb(0xFFB703), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(p(shoulder, 0.04, -0.32), s * 0.035), fill: ink)]

        case .springShoes:
            // Two red sneakers on silver coils, one on each foot.
            let at = f.feet(spread: 0.21)
            let left = CGRect(x: at.left - fu * 0.15, y: feet - fu * 0.06, width: fu * 0.3, height: fu * 0.12)
            let rightShoe = CGRect(x: at.right - fu * 0.15, y: feet - fu * 0.06, width: fu * 0.3, height: fu * 0.12)
            let coils = CGMutablePath()
            for shoe in [left, rightShoe] {
                let x = shoe.midX
                var y = shoe.maxY
                for k in 0..<3 {
                    let dx = (k.isMultiple(of: 2) ? 1 : -1) * fu * 0.07
                    coils.move(to: CGPoint(x: x - dx, y: y))
                    coils.addLine(to: CGPoint(x: x + dx, y: y + fu * 0.05))
                    y += fu * 0.05
                }
            }
            return [Part(path: coils, fill: nil, stroke: rgb(0xC0C4CC), lineWidth: line * 0.9),
                    Part(path: rounded(left, fu * 0.05), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.5),
                    Part(path: rounded(rightShoe, fu * 0.05), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.5)]

        case .skateboard:
            // A deck under its feet with two pairs of wheels, long enough for
            // both feet however far apart they stand.
            let at = f.feet(spread: 0.25)
            let half = max(fu * 0.5, (at.right - at.left) / 2 + fu * 0.18)
            let deck = CGRect(x: fc - half, y: feet - fu * 0.02, width: half * 2, height: fu * 0.08)
            let stripe = stroke(CGPoint(x: fc - half * 0.72, y: feet + fu * 0.02), CGPoint(x: fc + half * 0.72, y: feet + fu * 0.02))
            let wheels = CGMutablePath()
            for x in [fc - half * 0.64, fc + half * 0.64] {
                wheels.addPath(circle(CGPoint(x: x, y: feet + fu * 0.11), fu * 0.05))
            }
            return [Part(path: rounded(deck, fu * 0.04), fill: rgb(0x8338EC), stroke: ink, lineWidth: line * 0.5),
                    Part(path: stripe, fill: nil, stroke: rgb(0xFFBE0B), lineWidth: line * 0.7),
                    Part(path: wheels, fill: rgb(0xF1FAEE), stroke: ink, lineWidth: line * 0.4)]

        case .umbrella:
            // An open red umbrella held up by its hooked handle.
            let canopy = CGMutablePath()
            canopy.move(to: p(right, -0.5, -0.5))
            canopy.addQuadCurve(to: p(right, 0.5, -0.5), control: p(right, 0, -1.1))
            canopy.addQuadCurve(to: p(right, 0.17, -0.5), control: p(right, 0.33, -0.6))
            canopy.addQuadCurve(to: p(right, -0.17, -0.5), control: p(right, 0, -0.6))
            canopy.addQuadCurve(to: p(right, -0.5, -0.5), control: p(right, -0.33, -0.6))
            let handle = CGMutablePath()
            handle.move(to: p(right, 0, -0.78))
            handle.addLine(to: p(right, 0, 0.12))
            handle.addQuadCurve(to: p(right, -0.14, 0.12), control: p(right, -0.07, 0.24))
            return [Part(path: handle, fill: nil, stroke: rgb(0x5C3818), lineWidth: line * 0.8),
                    Part(path: canopy, fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.5)]

        case .yoyo:
            // A yo-yo hanging from its string.
            let string = stroke(p(right, 0, -0.3), p(right, 0, 0.18))
            return [Part(path: string, fill: nil, stroke: rgb(0xF1FAEE), lineWidth: line * 0.4),
                    Part(path: circle(p(right, 0, 0.3), s * 0.18), fill: rgb(0xFF006E), stroke: ink, lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0, 0.3), s * 0.07), fill: rgb(0xFFBE0B))]

        case .bubbleWand:
            // A wand with its ring and three bubbles drifting off.
            let wand = stroke(p(right, 0, 0.2), p(right, 0.1, -0.36))
            let bubbles = CGMutablePath()
            bubbles.addPath(circle(p(right, 0.36, -0.62), s * 0.1))
            bubbles.addPath(circle(p(right, 0.58, -0.86), s * 0.07))
            bubbles.addPath(circle(p(right, 0.3, -0.98), s * 0.05))
            return [Part(path: wand, fill: nil, stroke: rgb(0xFF8AD8), lineWidth: line * 0.8),
                    Part(path: circle(p(right, 0.12, -0.46), s * 0.12), fill: nil, stroke: rgb(0xFF8AD8), lineWidth: line * 0.7),
                    Part(path: bubbles, fill: rgb(0xBDE0FE), stroke: rgb(0x48CAE4), lineWidth: line * 0.3)]

        case .horseshoeMagnet:
            // A red horseshoe magnet with silver tips.
            let arc = CGMutablePath()
            arc.move(to: p(right, -0.22, -0.4))
            arc.addLine(to: p(right, -0.22, 0.02))
            arc.addQuadCurve(to: p(right, 0.22, 0.02), control: p(right, 0, 0.42))
            arc.addLine(to: p(right, 0.22, -0.4))
            let tips = CGMutablePath()
            tips.addPath(stroke(p(right, -0.22, -0.4), p(right, -0.22, -0.26)))
            tips.addPath(stroke(p(right, 0.22, -0.4), p(right, 0.22, -0.26)))
            return [Part(path: arc, fill: nil, stroke: rgb(0xE63946), lineWidth: line * 2.2),
                    Part(path: tips, fill: nil, stroke: rgb(0xD9D9D9), lineWidth: line * 2.2)]

        case .luckyDice:
            // Two dice, a five and a six, one leaning on the other.
            let one = CGRect(x: right.x - s * 0.36, y: right.y - s * 0.2, width: s * 0.34, height: s * 0.34)
            let two = CGRect(x: right.x + s * 0.02, y: right.y - s * 0.34, width: s * 0.34, height: s * 0.34)
            let pips = CGMutablePath()
            let r = s * 0.035
            for (dx, dy) in [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)] {
                pips.addPath(circle(CGPoint(x: one.minX + one.width * dx, y: one.minY + one.height * dy), r))
            }
            for (dx, dy) in [(0.28, 0.22), (0.28, 0.5), (0.28, 0.78), (0.72, 0.22), (0.72, 0.5), (0.72, 0.78)] {
                pips.addPath(circle(CGPoint(x: two.minX + two.width * dx, y: two.minY + two.height * dy), r))
            }
            return [Part(path: rounded(one, s * 0.06), fill: rgb(0xFFFFFF), stroke: ink, lineWidth: line * 0.5),
                    Part(path: rounded(two, s * 0.06), fill: rgb(0xFFF3B0), stroke: ink, lineWidth: line * 0.5),
                    Part(path: pips, fill: rgb(0xE63946))]

        case .fortuneCookie:
            // A folded cookie with its paper slip peeking out.
            let cookie = CGMutablePath()
            cookie.move(to: p(right, -0.36, 0.1))
            cookie.addQuadCurve(to: p(right, 0.36, 0.1), control: p(right, 0, -0.5))
            cookie.addQuadCurve(to: p(right, -0.36, 0.1), control: p(right, 0, -0.04))
            let slip = poly([p(right, 0.04, -0.04), p(right, 0.5, -0.12), p(right, 0.52, -0.02), p(right, 0.06, 0.04)])
            return [Part(path: cookie, fill: rgb(0xE9A23B), stroke: rgb(0x7A4A0F), lineWidth: line * 0.5),
                    Part(path: slip, fill: rgb(0xFFFFFF), stroke: rgb(0xB0B0B0), lineWidth: line * 0.3)]

        case .snowGlobe:
            // A glass globe on a wooden base, a tree and snow inside.
            let base = CGRect(x: right.x - s * 0.3, y: right.y + s * 0.1, width: s * 0.6, height: s * 0.16)
            let tree = poly([p(right, 0, -0.34), p(right, 0.14, -0.04), p(right, -0.14, -0.04)])
            let snow = CGMutablePath()
            for (dx, dy) in [(-0.16, -0.3), (0.12, -0.38), (0.2, -0.16), (-0.2, -0.1)] {
                snow.addPath(circle(p(right, CGFloat(dx), CGFloat(dy)), s * 0.03))
            }
            return [Part(path: rounded(base, s * 0.05), fill: rgb(0x8B5A2B), stroke: ink, lineWidth: line * 0.4),
                    Part(path: circle(p(right, 0, -0.18), s * 0.3), fill: rgb(0xCAF0F8), stroke: rgb(0x48CAE4),
                         lineWidth: line * 0.5),
                    Part(path: tree, fill: rgb(0x2D6A4F)),
                    Part(path: snow, fill: rgb(0xFFFFFF))]

        case .instantCamera:
            // A boxy instant camera with a big lens and a flash.
            let body = CGRect(x: right.x - s * 0.4, y: right.y - s * 0.3, width: s * 0.8, height: s * 0.56)
            let flash = CGRect(x: right.x + s * 0.12, y: right.y - s * 0.24, width: s * 0.2, height: s * 0.1)
            let stripes = CGMutablePath()
            stripes.addPath(stroke(CGPoint(x: body.minX, y: body.maxY - s * 0.1), CGPoint(x: body.maxX, y: body.maxY - s * 0.1)))
            return [Part(path: rounded(body, s * 0.08), fill: rgb(0xF1FAEE), stroke: ink, lineWidth: line * 0.5),
                    Part(path: stripes, fill: nil, stroke: rgb(0xFF006E), lineWidth: line * 0.9),
                    Part(path: circle(p(right, -0.06, 0.02), s * 0.17), fill: rgb(0x22223B), stroke: ink, lineWidth: line * 0.4),
                    Part(path: circle(p(right, -0.08, -0.01), s * 0.05), fill: rgb(0x8ECAE6)),
                    Part(path: rounded(flash, s * 0.03), fill: rgb(0xFFF3B0), stroke: ink, lineWidth: line * 0.3)]

        default:
            return []
        }
    }
}
