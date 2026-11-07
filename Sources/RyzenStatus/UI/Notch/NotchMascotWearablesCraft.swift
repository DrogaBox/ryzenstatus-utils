// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The eight things of the workshop, traced with a few bold paths like the
/// rest: a guitar slung at the hip with its neck up and out, a belt knotted
/// at the middle, a beret cocked on the head with a palette in the other
/// hand, a bowl and its whisk, two gloves, a telescope to the sky, a shovel
/// stood in the ground and a pogo stick under the feet.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func craftParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        let right = f.rightHand, left = f.leftHand
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
        func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
        }
        /// A thin bar from `a` to `b`, `thickness` wide.
        func bar(_ a: CGPoint, _ b: CGPoint, _ thickness: CGFloat) -> CGPath {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(0.001, hypot(dx, dy))
            let nx = -dy / length * thickness / 2, ny = dx / length * thickness / 2
            return poly([CGPoint(x: a.x + nx, y: a.y + ny), CGPoint(x: b.x + nx, y: b.y + ny),
                         CGPoint(x: b.x - nx, y: b.y - ny), CGPoint(x: a.x - nx, y: a.y - ny)])
        }

        switch accessory {
        case .electricGuitar:
            // A cherry-red body low at the hip, the neck up and out past the
            // shoulder, three strings and a little headstock with pegs.
            let body = p(right, -0.14, 0.14)
            let neckEnd = p(right, 0.62, -0.5)
            let lower = ellipse(p(body, -0.02, 0.08), 0.3 * s, 0.26 * s)
            let upper = ellipse(p(body, 0.1, -0.16), 0.22 * s, 0.19 * s)
            let horns = poly([p(body, 0.14, -0.3), p(body, 0.32, -0.42), p(body, 0.24, -0.18)])
            let neck = bar(p(body, 0.14, -0.14), neckEnd, 0.1 * s)
            let head = poly([p(neckEnd, -0.08, -0.02), p(neckEnd, 0.16, -0.2), p(neckEnd, 0.24, -0.1), p(neckEnd, 0.02, 0.1)])
            let strings = CGMutablePath()
            for offset in [-0.03, 0.0, 0.03] as [CGFloat] {
                strings.addPath(stroke(p(body, 0.05 + offset, 0.02 + offset), p(neckEnd, offset, offset)))
            }
            let pegs = CGMutablePath()
            for offset in [0.02, 0.08, 0.14] as [CGFloat] { pegs.addPath(ellipse(p(neckEnd, offset, -0.12 - offset * 0.5), 0.022 * s, 0.022 * s)) }
            let pickguard = ellipse(p(body, -0.08, 0.08), 0.12 * s, 0.09 * s)
            return [Part(path: horns, fill: rgb(0xD12B3A)),
                    Part(path: lower, fill: rgb(0xD12B3A), stroke: ink, lineWidth: line * 0.5),
                    Part(path: upper, fill: rgb(0xE33A4A), stroke: ink, lineWidth: line * 0.5),
                    Part(path: pickguard, fill: rgb(0xF6F2E8)),
                    Part(path: neck, fill: rgb(0x7A4B21), stroke: ink, lineWidth: line * 0.4),
                    Part(path: head, fill: ink),
                    Part(path: strings, fill: nil, stroke: rgb(0xEDEDF2), lineWidth: line * 0.35),
                    Part(path: pegs, fill: rgb(0xC9C9D1))]

        case .karateBelt:
            // A black belt tied at the middle, the knot in front and two
            // tails hanging, with a white tip on each.
            let torso = f.separateBody ? f.torso : f.outline
            let y = torso.minY + torso.height * (f.separateBody ? 0.62 : 0.86)
            let half = torso.width * 0.5
            let band = CGPath(rect: CGRect(x: torso.midX - half, y: y - w * 0.05, width: half * 2, height: w * 0.1), transform: nil)
            let knot = ellipse(CGPoint(x: torso.midX, y: y), w * 0.08, w * 0.07)
            let tailL = bar(CGPoint(x: torso.midX - w * 0.04, y: y + w * 0.04), CGPoint(x: torso.midX - w * 0.12, y: y + w * 0.34), w * 0.07)
            let tailR = bar(CGPoint(x: torso.midX + w * 0.04, y: y + w * 0.04), CGPoint(x: torso.midX + w * 0.1, y: y + w * 0.36), w * 0.07)
            let tips = CGMutablePath()
            tips.addPath(bar(CGPoint(x: torso.midX - w * 0.1, y: y + w * 0.28), CGPoint(x: torso.midX - w * 0.12, y: y + w * 0.34), w * 0.07))
            tips.addPath(bar(CGPoint(x: torso.midX + w * 0.09, y: y + w * 0.3), CGPoint(x: torso.midX + w * 0.1, y: y + w * 0.36), w * 0.07))
            return [Part(path: band, fill: ink, stroke: rgb(0x3A3A44), lineWidth: line * 0.3),
                    Part(path: tailL, fill: ink), Part(path: tailR, fill: ink),
                    Part(path: tips, fill: rgb(0xF2F2F5)),
                    Part(path: knot, fill: rgb(0x26262E), stroke: rgb(0x4A4A55), lineWidth: line * 0.3)]

        case .painterBeret:
            // A soft beret slumped to one side with its stalk, and a palette
            // with daubs of paint in the other hand.
            let crown = CGPoint(x: cx + w * 0.08, y: top + w * 0.04)
            let beret = CGMutablePath()
            beret.move(to: CGPoint(x: cx - w * 0.36, y: top + w * 0.1))
            beret.addQuadCurve(to: CGPoint(x: cx + w * 0.4, y: top + w * 0.06), control: CGPoint(x: cx + w * 0.04, y: top - w * 0.26))
            beret.addQuadCurve(to: CGPoint(x: cx - w * 0.36, y: top + w * 0.1), control: CGPoint(x: cx + w * 0.02, y: top + w * 0.16))
            beret.closeSubpath()
            let brim = bar(CGPoint(x: cx - w * 0.3, y: top + w * 0.1), CGPoint(x: cx + w * 0.34, y: top + w * 0.08), w * 0.05)
            let stalk = stroke(CGPoint(x: crown.x, y: crown.y - w * 0.16), CGPoint(x: crown.x + w * 0.05, y: crown.y - w * 0.24))
            let palette = ellipse(p(left, -0.1, -0.05), 0.36 * s, 0.26 * s)
            let hole = ellipse(p(left, 0.1, 0.04), 0.06 * s, 0.05 * s)
            let daubs: [(CGFloat, CGFloat, UInt32)] = [(-0.3, -0.1, 0xE63946), (-0.14, -0.2, 0xFFB703), (0.02, -0.18, 0x2A9D8F),
                                                       (-0.26, 0.08, 0x3A86FF), (0.14, -0.06, 0xF4A6C8)]
            var parts = [Part(path: beret, fill: rgb(0x1F2A6B), stroke: ink, lineWidth: line * 0.4),
                         Part(path: brim, fill: rgb(0x18204F)),
                         Part(path: stalk, fill: nil, stroke: ink, lineWidth: line * 0.6),
                         Part(path: palette, fill: rgb(0xC48A4A), stroke: rgb(0x7A4B21), lineWidth: line * 0.4),
                         Part(path: hole, fill: rgb(0x7A4B21))]
            for (dx, dy, color) in daubs { parts.append(Part(path: ellipse(p(left, dx, dy), 0.06 * s, 0.05 * s), fill: rgb(color))) }
            return parts

        case .matchaBowl:
            // A stoneware bowl cupped in the hand, frothy green tea in it,
            // a bamboo whisk standing in the bowl and two curls of steam.
            let rim = p(right, 0.05, -0.2)
            let bowl = CGMutablePath()
            bowl.move(to: p(rim, -0.36, 0))
            bowl.addQuadCurve(to: p(rim, 0.36, 0), control: p(rim, 0, 0.62))
            bowl.closeSubpath()
            let tea = ellipse(rim, 0.36 * s, 0.1 * s)
            let whisk = bar(p(rim, 0.14, -0.04), p(rim, 0.3, -0.5), 0.07 * s)
            let tines = CGMutablePath()
            for offset in [-0.08, -0.03, 0.03, 0.08] as [CGFloat] {
                tines.addPath(stroke(p(rim, 0.16 + offset, -0.02), p(rim, 0.08 + offset * 1.6, 0.14)))
            }
            let steam = CGMutablePath()
            for dx in [-0.16, 0.0] as [CGFloat] {
                steam.move(to: p(rim, dx, -0.14))
                steam.addCurve(to: p(rim, dx + 0.04, -0.5), control1: p(rim, dx - 0.12, -0.26), control2: p(rim, dx + 0.14, -0.38))
            }
            return [Part(path: bowl, fill: rgb(0x8E9A8A), stroke: ink, lineWidth: line * 0.5),
                    Part(path: tea, fill: rgb(0x7CB342), stroke: rgb(0x558B2F), lineWidth: line * 0.3),
                    Part(path: whisk, fill: rgb(0xD9B97A), stroke: rgb(0x8A6A32), lineWidth: line * 0.3),
                    Part(path: tines, fill: nil, stroke: rgb(0xB89A5A), lineWidth: line * 0.35),
                    Part(path: steam, fill: nil, stroke: rgb(0xFFFFFF).copy(alpha: 0.65) ?? rgb(0xFFFFFF), lineWidth: line * 0.45)]

        case .boxingGloves:
            // Two red gloves, one on each hand, with a white cuff.
            var parts: [Part] = []
            // Held low, at the hips, so they never cover the eyes of a
            // figure whose hands sit close under its face.
            let eyeY = max(f.leftEye.y, f.rightEye.y)
            for (hand, side) in [(right, CGFloat(1)), (left, CGFloat(-1))] {
                var center = p(hand, side * 0.04, 0.3)
                // On a figure that is one round shape its hands sit under its
                // eyes: the gloves hang well below them.
                if !f.separateBody { center.y = max(center.y, eyeY + (f.floor - eyeY) * 0.65) }
                let glove = ellipse(center, 0.24 * s, 0.21 * s)
                let thumb = ellipse(p(center, side * 0.16, -0.1), 0.09 * s, 0.08 * s)
                let cuff = bar(p(center, -side * 0.16, 0.08), p(center, -side * 0.24, 0.2), 0.2 * s)
                let shine = ellipse(p(center, -side * 0.06, -0.08), 0.06 * s, 0.04 * s)
                parts += [Part(path: cuff, fill: rgb(0xF2F2F5), stroke: ink, lineWidth: line * 0.3),
                          Part(path: glove, fill: rgb(0xD12B3A), stroke: ink, lineWidth: line * 0.5),
                          Part(path: thumb, fill: rgb(0xD12B3A), stroke: ink, lineWidth: line * 0.4),
                          Part(path: shine, fill: rgb(0xFF8A94))]
            }
            return parts

        case .telescope:
            // A brass tube on its eye, pointed up and out at the sky, a
            // wider lens at the far end and a ring where it draws.
            let eye = p(right, 0.0, -0.12)
            let far = p(right, 0.7, -0.72)
            let tube = bar(eye, far, 0.16 * s)
            let draw = bar(p(eye, 0.24, -0.24), p(eye, 0.44, -0.45), 0.22 * s)
            let lens = ellipse(far, 0.13 * s, 0.13 * s)
            let glass = ellipse(far, 0.08 * s, 0.08 * s)
            let eyepiece = ellipse(eye, 0.07 * s, 0.07 * s)
            let star = CGMutablePath()
            for (dx, dy) in [(0.86, -1.0), (1.0, -0.84)] as [(CGFloat, CGFloat)] {
                let c = p(right, dx, dy)
                star.addPath(stroke(p(c, -0.05, 0), p(c, 0.05, 0)))
                star.addPath(stroke(p(c, 0, -0.05), p(c, 0, 0.05)))
            }
            return [Part(path: tube, fill: rgb(0xC9972B), stroke: ink, lineWidth: line * 0.5),
                    Part(path: draw, fill: rgb(0xE0B24A), stroke: ink, lineWidth: line * 0.4),
                    Part(path: lens, fill: rgb(0x8A6420), stroke: ink, lineWidth: line * 0.4),
                    Part(path: glass, fill: rgb(0x7FD3FF)),
                    Part(path: eyepiece, fill: ink),
                    Part(path: star, fill: nil, stroke: rgb(0xFFE89A), lineWidth: line * 0.4)]

        case .shovel:
            // A shovel leaning in its hand, the blade down in the ground
            // beside its feet and a T grip at the top.
            let grip = p(right, 0.1, -0.5)
            let foot = CGPoint(x: right.x + 0.42 * s, y: f.floor - 0.2 * s)
            let shaft = bar(grip, foot, 0.08 * s)
            let handle = bar(p(grip, -0.16, 0.02), p(grip, 0.16, -0.02), 0.08 * s)
            let blade = poly([CGPoint(x: foot.x - 0.2 * s, y: foot.y - 0.3 * s), CGPoint(x: foot.x + 0.2 * s, y: foot.y - 0.3 * s),
                              CGPoint(x: foot.x + 0.16 * s, y: foot.y + 0.14 * s), CGPoint(x: foot.x, y: foot.y + 0.26 * s),
                              CGPoint(x: foot.x - 0.16 * s, y: foot.y + 0.14 * s)])
            let dirt = ellipse(CGPoint(x: foot.x + 0.1 * s, y: foot.y + 0.2 * s), 0.3 * s, 0.07 * s)
            return [Part(path: dirt, fill: rgb(0x6B4A2B)),
                    Part(path: blade, fill: rgb(0x9AA4B2), stroke: ink, lineWidth: line * 0.5),
                    Part(path: shaft, fill: rgb(0x8A5A2B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: handle, fill: rgb(0x8A5A2B), stroke: ink, lineWidth: line * 0.3)]

        case .pogoStick:
            // A pole between its feet from the ground up to its middle, a
            // foot bar it stands on, a spring at the bottom and handles at the top.
            let unit = f.feetUnit
            let x = f.feetCenter
            // Held at its middle where it has a body of its own; a figure
            // that is one round shape perches on it, the stick peeking out
            // underneath with the handles at the floor line.
            let round = !f.separateBody
            let floor = f.floor + unit * (round ? 0.3 : 0.22)
            let top = round ? f.floor + unit * 0.03 : f.torso.midY
            let barY = round ? f.floor + unit * 0.14 : f.floor + unit * 0.02
            let pole = bar(CGPoint(x: x, y: floor), CGPoint(x: x, y: top), unit * 0.09)
            let footBar = bar(CGPoint(x: x - unit * 0.36, y: barY), CGPoint(x: x + unit * 0.36, y: barY), unit * 0.09)
            let handles = bar(CGPoint(x: x - unit * 0.3, y: top), CGPoint(x: x + unit * 0.3, y: top), unit * 0.09)
            let spring = CGMutablePath()
            var y = barY + unit * 0.02
            spring.move(to: CGPoint(x: x - unit * 0.12, y: y))
            var side: CGFloat = 1
            while y < floor - unit * 0.02 {
                y += unit * 0.045
                spring.addLine(to: CGPoint(x: x + side * unit * 0.12, y: y))
                side = -side
            }
            let tip = ellipse(CGPoint(x: x, y: floor), unit * 0.1, unit * 0.05)
            return [Part(path: pole, fill: rgb(0x3A86FF), stroke: ink, lineWidth: line * 0.4),
                    Part(path: spring, fill: nil, stroke: rgb(0xC9C9D1), lineWidth: line * 0.5),
                    Part(path: tip, fill: ink),
                    Part(path: footBar, fill: rgb(0x26262E), stroke: ink, lineWidth: line * 0.3),
                    Part(path: handles, fill: rgb(0xD12B3A), stroke: ink, lineWidth: line * 0.3)]

        default:
            return []
        }
    }
}
