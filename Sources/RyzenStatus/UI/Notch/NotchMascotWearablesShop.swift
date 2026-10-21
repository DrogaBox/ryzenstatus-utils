// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The twenty-four curiosities of the shop: funny, sad and mad things, traced
/// with a few bold paths like the rest, since the companion is about twenty
/// points tall in the island.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    static func shopParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        let right = CGPoint(x: f.outline.maxX + w * 0.02, y: f.outline.minY + f.outline.height * 0.62)
        let s = w * 0.56
        let eyeY = (f.leftEye.y + f.rightEye.y) / 2
        let eyeGap = abs(f.rightEye.x - f.leftEye.x)
        let mouth = CGPoint(x: cx, y: eyeY + f.outline.height * 0.2)

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
        // MARK: Funny

        case .rubberDuck:
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: right.x - s * 0.34, y: right.y - s * 0.12, width: s * 0.68, height: s * 0.4))
            return [Part(path: body, fill: rgb(0xFFD23F), stroke: rgb(0x16161C), lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0.18, -0.26), s * 0.16), fill: rgb(0xFFD23F), stroke: rgb(0x16161C),
                         lineWidth: line * 0.5),
                    Part(path: poly([p(right, 0.32, -0.28), p(right, 0.5, -0.22), p(right, 0.32, -0.16)]),
                         fill: rgb(0xFF8A2B)),
                    Part(path: circle(p(right, 0.2, -0.3), s * 0.03), fill: rgb(0x16161C))]

        case .bananaPeel:
            let skin = CGMutablePath()
            skin.move(to: p(right, -0.4, 0.2))
            skin.addQuadCurve(to: p(right, 0.4, 0.2), control: p(right, 0, -0.5))
            skin.addQuadCurve(to: p(right, -0.4, 0.2), control: p(right, 0, -0.1))
            let flaps = CGMutablePath()
            flaps.move(to: p(right, -0.3, 0.2))
            flaps.addQuadCurve(to: p(right, -0.5, 0.42), control: p(right, -0.5, 0.24))
            flaps.move(to: p(right, 0.3, 0.2))
            flaps.addQuadCurve(to: p(right, 0.5, 0.42), control: p(right, 0.5, 0.24))
            return [Part(path: skin, fill: rgb(0xFFE24A), stroke: rgb(0x8A6B00), lineWidth: line * 0.5),
                    Part(path: flaps, fill: nil, stroke: rgb(0xE6C31F), lineWidth: line * 1.3)]

        case .clownNose:
            return [Part(path: circle(CGPoint(x: cx, y: eyeY + f.outline.height * 0.12), s * 0.2), fill: rgb(0xE5384F),
                         stroke: rgb(0x8A1F2E), lineWidth: line * 0.5),
                    Part(path: circle(CGPoint(x: cx - s * 0.06, y: eyeY + f.outline.height * 0.08), s * 0.05),
                         fill: rgb(0xFFFFFF))]

        case .creamPie:
            let tin = poly([p(right, -0.36, 0.0), p(right, 0.36, 0.0), p(right, 0.28, 0.26), p(right, -0.28, 0.26)])
            let cream = CGMutablePath()
            cream.addEllipse(in: CGRect(x: right.x - s * 0.36, y: right.y - s * 0.22, width: s * 0.72, height: s * 0.28))
            return [Part(path: tin, fill: rgb(0xC98B4B), stroke: rgb(0x6B4423), lineWidth: line * 0.5),
                    Part(path: cream, fill: rgb(0xFFF8EE), stroke: rgb(0xD9CBB5), lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0.05, -0.3), s * 0.09), fill: rgb(0xE5384F))]

        case .whoopeeCushion:
            let cushion = CGMutablePath()
            cushion.addEllipse(in: CGRect(x: right.x - s * 0.42, y: right.y - s * 0.02, width: s * 0.84, height: s * 0.34))
            return [Part(path: cushion, fill: rgb(0xF08FB0), stroke: rgb(0x9C3E64), lineWidth: line * 0.5),
                    Part(path: stroke(p(right, 0.42, 0.14), p(right, 0.58, 0.14)), fill: nil, stroke: rgb(0x9C3E64),
                         lineWidth: line)]

        case .fakeMustache:
            let stache = CGMutablePath()
            stache.move(to: CGPoint(x: cx, y: mouth.y - s * 0.04))
            stache.addQuadCurve(to: CGPoint(x: cx - s * 0.46, y: mouth.y + s * 0.1), control: CGPoint(x: cx - s * 0.2, y: mouth.y - s * 0.2))
            stache.addQuadCurve(to: CGPoint(x: cx, y: mouth.y + s * 0.04), control: CGPoint(x: cx - s * 0.22, y: mouth.y + s * 0.14))
            stache.addQuadCurve(to: CGPoint(x: cx + s * 0.46, y: mouth.y + s * 0.1), control: CGPoint(x: cx + s * 0.22, y: mouth.y + s * 0.14))
            stache.addQuadCurve(to: CGPoint(x: cx, y: mouth.y - s * 0.04), control: CGPoint(x: cx + s * 0.2, y: mouth.y - s * 0.2))
            return [Part(path: stache, fill: rgb(0x3A2A1E), stroke: rgb(0x16161C), lineWidth: line * 0.4)]

        case .trafficCone:
            let cone = poly([CGPoint(x: cx - w * 0.22, y: top + w * 0.1), CGPoint(x: cx + w * 0.22, y: top + w * 0.1),
                             CGPoint(x: cx + w * 0.07, y: top - w * 0.4), CGPoint(x: cx - w * 0.07, y: top - w * 0.4)])
            let band = poly([CGPoint(x: cx - w * 0.15, y: top - w * 0.08), CGPoint(x: cx + w * 0.15, y: top - w * 0.08),
                             CGPoint(x: cx + w * 0.11, y: top - w * 0.2), CGPoint(x: cx - w * 0.11, y: top - w * 0.2)])
            return [Part(path: cone, fill: rgb(0xFF7A1A), stroke: rgb(0x8A3A00), lineWidth: line * 0.5),
                    Part(path: band, fill: rgb(0xFFFFFF))]

        case .piggyBank:
            let pig = CGMutablePath()
            pig.addEllipse(in: CGRect(x: right.x - s * 0.4, y: right.y - s * 0.16, width: s * 0.8, height: s * 0.52))
            return [Part(path: pig, fill: rgb(0xF6A9C0), stroke: rgb(0x9C3E64), lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0.42, 0.06), s * 0.12), fill: rgb(0xF08FB0), stroke: rgb(0x9C3E64),
                         lineWidth: line * 0.4),
                    Part(path: stroke(p(right, -0.12, -0.14), p(right, 0.1, -0.14)), fill: nil, stroke: rgb(0x16161C),
                         lineWidth: line),
                    Part(path: circle(p(right, 0.2, -0.02), s * 0.03), fill: rgb(0x16161C))]

        case .alarmClock:
            let bells = CGMutablePath()
            bells.addEllipse(in: CGRect(x: right.x - s * 0.34, y: right.y - s * 0.42, width: s * 0.22, height: s * 0.18))
            bells.addEllipse(in: CGRect(x: right.x + s * 0.12, y: right.y - s * 0.42, width: s * 0.22, height: s * 0.18))
            let hands = CGMutablePath()
            hands.move(to: p(right, 0, 0.08))
            hands.addLine(to: p(right, 0, -0.1))
            hands.move(to: p(right, 0, 0.08))
            hands.addLine(to: p(right, 0.14, 0.12))
            return [Part(path: bells, fill: rgb(0xFFC940), stroke: rgb(0x8A6B00), lineWidth: line * 0.4),
                    Part(path: circle(p(right, 0, 0.08), s * 0.36), fill: rgb(0xF7F4EE), stroke: rgb(0xE5384F),
                         lineWidth: line * 0.9),
                    Part(path: hands, fill: nil, stroke: rgb(0x16161C), lineWidth: line * 0.7)]

        // MARK: Sad

        case .stormCloud:
            let cloud = CGMutablePath()
            for (dx, r) in [(-0.22, 0.17), (0.0, 0.22), (0.24, 0.16)] as [(CGFloat, CGFloat)] {
                cloud.addEllipse(in: CGRect(x: cx + dx * w - r * w, y: top - w * 0.3 - r * w * 0.5, width: r * w * 2, height: r * w * 1.5))
            }
            let rain = CGMutablePath()
            for dx in [-0.2, 0.0, 0.2] as [CGFloat] {
                rain.move(to: CGPoint(x: cx + dx * w, y: top - w * 0.06))
                rain.addLine(to: CGPoint(x: cx + dx * w - w * 0.03, y: top + w * 0.12))
            }
            return [Part(path: cloud, fill: rgb(0x6C7690), stroke: rgb(0x3E4560), lineWidth: line * 0.5),
                    Part(path: rain, fill: nil, stroke: rgb(0x6FB8FF), lineWidth: line * 0.9)]

        case .wiltedFlower:
            let stem = CGMutablePath()
            stem.move(to: p(right, 0, 0.5))
            stem.addQuadCurve(to: p(right, 0.12, -0.2), control: p(right, -0.12, 0.14))
            let head = CGMutablePath()
            for (dx, dy) in [(-0.08, 0.0), (0.28, 0.0), (0.1, -0.2), (0.1, 0.2)] as [(CGFloat, CGFloat)] {
                head.addEllipse(in: CGRect(x: right.x + (0.12 + dx) * s - s * 0.1, y: right.y - 0.3 * s + dy * s - s * 0.07,
                                           width: s * 0.2, height: s * 0.14))
            }
            return [Part(path: stem, fill: nil, stroke: rgb(0x5E8C3A), lineWidth: line * 1.2),
                    Part(path: head, fill: rgb(0xB78AA8), stroke: rgb(0x6D4A62), lineWidth: line * 0.4),
                    Part(path: circle(p(right, 0.12, -0.3), s * 0.06), fill: rgb(0xC9A227)),
                    Part(path: circle(p(right, 0.34, 0.28), s * 0.04), fill: rgb(0xB78AA8))]

        case .lonelyBalloon:
            let string = CGMutablePath()
            string.move(to: p(right, 0.1, -0.2))
            string.addQuadCurve(to: p(right, -0.04, 0.5), control: p(right, 0.26, 0.14))
            let balloon = CGMutablePath()
            balloon.addEllipse(in: CGRect(x: right.x - s * 0.18, y: right.y - s * 0.78, width: s * 0.56, height: s * 0.64))
            return [Part(path: string, fill: nil, stroke: rgb(0xD9D9D9), lineWidth: line * 0.5),
                    Part(path: balloon, fill: rgb(0x6FA8FF), stroke: rgb(0x2F5FB5), lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0.02, -0.56), s * 0.07), fill: rgb(0xFFFFFF))]

        case .teddyBear:
            let ears = CGMutablePath()
            ears.addEllipse(in: CGRect(x: right.x - s * 0.34, y: right.y - s * 0.34, width: s * 0.2, height: s * 0.2))
            ears.addEllipse(in: CGRect(x: right.x + s * 0.14, y: right.y - s * 0.34, width: s * 0.2, height: s * 0.2))
            return [Part(path: ears, fill: rgb(0xA8744B), stroke: rgb(0x5E3E24), lineWidth: line * 0.4),
                    Part(path: circle(p(right, 0, 0.0), s * 0.34), fill: rgb(0xB9835A), stroke: rgb(0x5E3E24),
                         lineWidth: line * 0.5),
                    Part(path: circle(p(right, 0, 0.1), s * 0.14), fill: rgb(0xE6CBA8)),
                    Part(path: circle(p(right, 0, 0.06), s * 0.04), fill: rgb(0x16161C)),
                    Part(path: circle(p(right, -0.12, -0.08), s * 0.03), fill: rgb(0x16161C)),
                    Part(path: circle(p(right, 0.12, -0.08), s * 0.03), fill: rgb(0x16161C))]

        case .tissueBox:
            let box = CGRect(x: right.x - s * 0.34, y: right.y - s * 0.02, width: s * 0.68, height: s * 0.4)
            let tissue = CGMutablePath()
            tissue.move(to: p(right, -0.06, 0.0))
            tissue.addQuadCurve(to: p(right, 0.08, -0.34), control: p(right, -0.14, -0.2))
            tissue.addQuadCurve(to: p(right, 0.14, 0.0), control: p(right, 0.26, -0.16))
            return [Part(path: tissue, fill: rgb(0xFFFFFF), stroke: rgb(0xCFC9BC), lineWidth: line * 0.4),
                    Part(path: rounded(box, s * 0.06), fill: rgb(0x7DC8E8), stroke: rgb(0x2F7FA3), lineWidth: line * 0.5),
                    Part(path: stroke(p(right, -0.12, 0.1), p(right, 0.12, 0.1)), fill: nil, stroke: rgb(0xFFFFFF),
                         lineWidth: line * 0.8)]

        case .brokenLocket:
            let chain = CGMutablePath()
            chain.move(to: p(right, -0.2, -0.5))
            chain.addQuadCurve(to: p(right, 0.2, -0.5), control: p(right, 0, -0.04))
            let left = poly([p(right, -0.02, -0.18), p(right, -0.26, -0.18), p(right, -0.3, 0.06), p(right, -0.04, 0.3),
                             p(right, 0.0, 0.08)])
            let rightHalf = poly([p(right, 0.06, -0.14), p(right, 0.3, -0.18), p(right, 0.3, 0.08), p(right, 0.1, 0.3),
                                  p(right, 0.04, 0.1)])
            return [Part(path: chain, fill: nil, stroke: rgb(0xC9A227), lineWidth: line * 0.6),
                    Part(path: left, fill: rgb(0xE5384F), stroke: rgb(0x8A1F2E), lineWidth: line * 0.4),
                    Part(path: rightHalf, fill: rgb(0xE5384F), stroke: rgb(0x8A1F2E), lineWidth: line * 0.4)]

        // MARK: Mad

        case .tinfoilHat:
            let hat = poly([CGPoint(x: cx - w * 0.3, y: top + w * 0.1), CGPoint(x: cx + w * 0.3, y: top + w * 0.1),
                            CGPoint(x: cx + w * 0.04, y: top - w * 0.42), CGPoint(x: cx - w * 0.1, y: top - w * 0.36)])
            let creases = CGMutablePath()
            creases.move(to: CGPoint(x: cx - w * 0.12, y: top + w * 0.08))
            creases.addLine(to: CGPoint(x: cx - w * 0.02, y: top - w * 0.3))
            creases.move(to: CGPoint(x: cx + w * 0.12, y: top + w * 0.08))
            creases.addLine(to: CGPoint(x: cx + w * 0.03, y: top - w * 0.3))
            return [Part(path: hat, fill: rgb(0xCDD5DE), stroke: rgb(0x7B8794), lineWidth: line * 0.6),
                    Part(path: creases, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: line * 0.6)]

        case .magicMushroom:
            let cap = CGMutablePath()
            cap.addEllipse(in: CGRect(x: right.x - s * 0.4, y: right.y - s * 0.34, width: s * 0.8, height: s * 0.46))
            let stem = rounded(CGRect(x: right.x - s * 0.12, y: right.y + s * 0.04, width: s * 0.24, height: s * 0.34), s * 0.08)
            let spots = CGMutablePath()
            spots.addPath(circle(p(right, -0.2, -0.14), s * 0.07))
            spots.addPath(circle(p(right, 0.06, -0.24), s * 0.07))
            spots.addPath(circle(p(right, 0.24, -0.08), s * 0.06))
            return [Part(path: stem, fill: rgb(0xF7F4EE), stroke: rgb(0xCFC9BC), lineWidth: line * 0.4),
                    Part(path: cap, fill: rgb(0xE5384F), stroke: rgb(0x8A1F2E), lineWidth: line * 0.5),
                    Part(path: spots, fill: rgb(0xFFFFFF))]

        case .discoBall:
            let hang = stroke(CGPoint(x: cx, y: top - w * 0.4), CGPoint(x: cx, y: top - w * 0.2))
            let ball = circle(CGPoint(x: cx, y: top - w * 0.06), w * 0.2)
            let grid = CGMutablePath()
            grid.move(to: CGPoint(x: cx - w * 0.2, y: top - w * 0.06))
            grid.addLine(to: CGPoint(x: cx + w * 0.2, y: top - w * 0.06))
            grid.move(to: CGPoint(x: cx, y: top - w * 0.26))
            grid.addLine(to: CGPoint(x: cx, y: top + w * 0.14))
            grid.addEllipse(in: CGRect(x: cx - w * 0.1, y: top - w * 0.26, width: w * 0.2, height: w * 0.4))
            return [Part(path: hang, fill: nil, stroke: rgb(0x7B8794), lineWidth: line * 0.5),
                    Part(path: ball, fill: rgb(0xBFD6EA), stroke: rgb(0x5B7C99), lineWidth: line * 0.5),
                    Part(path: grid, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: line * 0.4),
                    Part(path: circle(CGPoint(x: cx - w * 0.07, y: top - w * 0.12), w * 0.03), fill: rgb(0xFFFFFF))]

        case .alienAntenna:
            let a = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                a.move(to: CGPoint(x: cx + side * w * 0.14, y: top + w * 0.02))
                a.addQuadCurve(to: CGPoint(x: cx + side * w * 0.26, y: top - w * 0.36),
                               control: CGPoint(x: cx + side * w * 0.3, y: top - w * 0.14))
            }
            let tips = CGMutablePath()
            tips.addPath(circle(CGPoint(x: cx - w * 0.26, y: top - w * 0.38), w * 0.07))
            tips.addPath(circle(CGPoint(x: cx + w * 0.26, y: top - w * 0.38), w * 0.07))
            return [Part(path: a, fill: nil, stroke: rgb(0x6BD66B), lineWidth: line * 1.1),
                    Part(path: tips, fill: rgb(0xB6FF4A), stroke: rgb(0x3C8A2B), lineWidth: line * 0.4)]

        case .dynamiteStick:
            let stick = rounded(CGRect(x: right.x - s * 0.14, y: right.y - s * 0.28, width: s * 0.28, height: s * 0.7), s * 0.06)
            let fuse = CGMutablePath()
            fuse.move(to: p(right, 0, -0.28))
            fuse.addQuadCurve(to: p(right, 0.2, -0.5), control: p(right, 0.02, -0.46))
            return [Part(path: stick, fill: rgb(0xD83A3A), stroke: rgb(0x7A1B1B), lineWidth: line * 0.5),
                    Part(path: stroke(p(right, -0.14, 0.0), p(right, 0.14, 0.0)), fill: nil, stroke: rgb(0xF7F4EE),
                         lineWidth: line * 0.9),
                    Part(path: fuse, fill: nil, stroke: rgb(0x3A2A1E), lineWidth: line * 0.7),
                    Part(path: circle(p(right, 0.22, -0.52), s * 0.08), fill: rgb(0xFFC940))]

        case .mimicChest:
            let lid = CGMutablePath()
            lid.move(to: p(right, -0.4, -0.04))
            lid.addQuadCurve(to: p(right, 0.4, -0.04), control: p(right, 0, -0.44))
            lid.closeSubpath()
            let teeth = poly([p(right, -0.3, -0.04), p(right, -0.2, 0.08), p(right, -0.1, -0.04), p(right, 0.0, 0.08),
                              p(right, 0.1, -0.04), p(right, 0.2, 0.08), p(right, 0.3, -0.04)])
            return [Part(path: rounded(CGRect(x: right.x - s * 0.4, y: right.y - s * 0.02, width: s * 0.8, height: s * 0.4), s * 0.05),
                         fill: rgb(0x8A5A2B), stroke: rgb(0x3A2410), lineWidth: line * 0.5),
                    Part(path: lid, fill: rgb(0xA06A32), stroke: rgb(0x3A2410), lineWidth: line * 0.5),
                    Part(path: teeth, fill: rgb(0xFFFFFF)),
                    Part(path: circle(p(right, 0, 0.2), s * 0.06), fill: rgb(0xFFC940))]

        case .crystalSkull:
            let skull = CGMutablePath()
            skull.addEllipse(in: CGRect(x: right.x - s * 0.34, y: right.y - s * 0.4, width: s * 0.68, height: s * 0.6))
            let jaw = rounded(CGRect(x: right.x - s * 0.2, y: right.y + s * 0.12, width: s * 0.4, height: s * 0.2), s * 0.05)
            let eyes = CGMutablePath()
            eyes.addPath(circle(p(right, -0.12, -0.12), s * 0.09))
            eyes.addPath(circle(p(right, 0.12, -0.12), s * 0.09))
            return [Part(path: jaw, fill: rgb(0xBFE8F7), stroke: rgb(0x5BA6C4), lineWidth: line * 0.4),
                    Part(path: skull, fill: rgb(0xD5F1FB), stroke: rgb(0x5BA6C4), lineWidth: line * 0.5),
                    Part(path: eyes, fill: rgb(0x2A1A5E)),
                    Part(path: poly([p(right, -0.02, 0.0), p(right, 0.02, 0.0), p(right, 0, 0.06)]), fill: rgb(0x2A1A5E))]

        case .cursedMask:
            let mask = CGMutablePath()
            mask.move(to: CGPoint(x: cx - eyeGap * 0.7, y: eyeY - eyeGap * 0.5))
            mask.addLine(to: CGPoint(x: cx + eyeGap * 0.7, y: eyeY - eyeGap * 0.5))
            mask.addQuadCurve(to: CGPoint(x: cx, y: eyeY + eyeGap * 1.1), control: CGPoint(x: cx + eyeGap * 0.8, y: eyeY + eyeGap * 0.8))
            mask.addQuadCurve(to: CGPoint(x: cx - eyeGap * 0.7, y: eyeY - eyeGap * 0.5), control: CGPoint(x: cx - eyeGap * 0.8, y: eyeY + eyeGap * 0.8))
            let slits = CGMutablePath()
            slits.move(to: CGPoint(x: f.leftEye.x - eyeGap * 0.2, y: f.leftEye.y - eyeGap * 0.1))
            slits.addLine(to: CGPoint(x: f.leftEye.x + eyeGap * 0.2, y: f.leftEye.y + eyeGap * 0.1))
            slits.move(to: CGPoint(x: f.rightEye.x + eyeGap * 0.2, y: f.rightEye.y - eyeGap * 0.1))
            slits.addLine(to: CGPoint(x: f.rightEye.x - eyeGap * 0.2, y: f.rightEye.y + eyeGap * 0.1))
            return [Part(path: mask, fill: rgb(0x5A2A7A), stroke: rgb(0x2A0F3E), lineWidth: line * 0.5),
                    Part(path: slits, fill: nil, stroke: rgb(0xFF4AE6), lineWidth: line * 1.1)]

        case .unicornHorn:
            let horn = poly([CGPoint(x: cx - w * 0.1, y: top + w * 0.06), CGPoint(x: cx + w * 0.1, y: top + w * 0.06),
                             CGPoint(x: cx, y: top - w * 0.5)])
            let spiral = CGMutablePath()
            for k in 1...3 {
                let y = top + w * 0.06 - CGFloat(k) * w * 0.14
                let half = w * 0.1 * (1 - CGFloat(k) * 0.24)
                spiral.move(to: CGPoint(x: cx - half, y: y + w * 0.05))
                spiral.addLine(to: CGPoint(x: cx + half, y: y - w * 0.03))
            }
            return [Part(path: horn, fill: rgb(0xFFE9A8), stroke: rgb(0xD9B64B), lineWidth: line * 0.5),
                    Part(path: spiral, fill: nil, stroke: rgb(0xFF8AD8), lineWidth: line * 0.8)]

        default:
            return []
        }
    }
}
