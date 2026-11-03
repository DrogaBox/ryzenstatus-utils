// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The sixteen party things, traced with a few bold paths like the toys:
/// what it holds sits in its right hand, the kite flies high over it on its
/// string, and the hula hoop rings its waist, where its torso says it is.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func partyParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let line = max(0.8, f.size * 0.045)
        let right = f.rightHand
        let s = f.prop
        let ink = rgb(0x16161C)

        func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: right.x + dx * s, y: right.y + dy * s) }
        func box(_ dx: CGFloat, _ dy: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: right.x + dx * s, y: right.y + dy * s, width: width * s, height: height * s)
        }
        func poly(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
            return path
        }
        func strokes(_ segments: [(CGPoint, CGPoint)]) -> CGPath {
            let path = CGMutablePath()
            for (a, b) in segments {
                path.move(to: a)
                path.addLine(to: b)
            }
            return path
        }

        switch accessory {
        case .drum:
            // A red snare with a white head, laced sides and two sticks
            // raised over it, ready for the solo.
            let shell = box(-0.34, -0.1, 0.68, 0.38)
            let lacing = CGMutablePath()
            lacing.move(to: p(-0.3, -0.02))
            for k in 1...6 {
                lacing.addLine(to: p(-0.3 + CGFloat(k) * 0.1, k.isMultiple(of: 2) ? -0.02 : 0.22))
            }
            let sticks = strokes([(p(-0.08, -0.16), p(-0.42, -0.62)), (p(0.1, -0.16), p(0.46, -0.58))])
            let tips = CGMutablePath()
            tips.addPath(circle(p(-0.42, -0.62), s * 0.05))
            tips.addPath(circle(p(0.46, -0.58), s * 0.05))
            return [Part(path: rounded(shell, s * 0.06), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.5),
                    Part(path: lacing, fill: nil, stroke: rgb(0xF1FAEE), lineWidth: line * 0.4),
                    Part(path: strokes([(p(-0.34, 0.26), p(0.34, 0.26))]), fill: nil, stroke: rgb(0xFFD23F),
                         lineWidth: line * 0.7),
                    Part(path: CGPath(ellipseIn: box(-0.34, -0.18, 0.68, 0.16), transform: nil), fill: rgb(0xF1FAEE),
                         stroke: ink, lineWidth: line * 0.5),
                    Part(path: sticks, fill: nil, stroke: rgb(0xC68B59), lineWidth: line * 0.8),
                    Part(path: tips, fill: rgb(0xE9C46A))]

        case .microphone:
            // A stage microphone: a dark handle, a silver collar and a round
            // grille head, with a little red light that says it is on.
            let handle = poly([p(-0.07, -0.12), p(0.07, -0.12), p(0.045, 0.4), p(-0.045, 0.4)])
            let grille = strokes([(p(-0.12, -0.3), p(0.12, -0.3)), (p(0, -0.44), p(0, -0.16)),
                                  (p(-0.09, -0.4), p(0.09, -0.2)), (p(0.09, -0.4), p(-0.09, -0.2))])
            return [Part(path: handle, fill: rgb(0x2B2D42), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rounded(box(-0.1, -0.17, 0.2, 0.08), s * 0.03), fill: rgb(0xC0C4CC)),
                    Part(path: circle(p(0, -0.3), s * 0.17), fill: rgb(0x8D99AE), stroke: ink, lineWidth: line * 0.5),
                    Part(path: grille, fill: nil, stroke: rgb(0xEDF2F4), lineWidth: line * 0.3),
                    Part(path: circle(p(0, 0.06), s * 0.035), fill: rgb(0xFF4D4D))]

        case .maracas:
            // Two maracas crossed in the hand, orange and yellow, each with a
            // painted zigzag band.
            let handles = strokes([(p(-0.04, 0.22), p(-0.2, -0.12)), (p(0.04, 0.22), p(0.2, -0.12))])
            func band(_ cx: CGFloat) -> CGPath {
                let path = CGMutablePath()
                path.move(to: p(cx - 0.13, -0.3))
                for k in 1...4 { path.addLine(to: p(cx - 0.13 + CGFloat(k) * 0.065, k.isMultiple(of: 2) ? -0.3 : -0.36)) }
                return path
            }
            return [Part(path: handles, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 0.9),
                    Part(path: CGPath(ellipseIn: box(-0.44, -0.5, 0.3, 0.36), transform: nil), fill: rgb(0xFF8C42),
                         stroke: ink, lineWidth: line * 0.4),
                    Part(path: CGPath(ellipseIn: box(0.14, -0.5, 0.3, 0.36), transform: nil), fill: rgb(0xFFD23F),
                         stroke: ink, lineWidth: line * 0.4),
                    Part(path: band(-0.29), fill: nil, stroke: rgb(0x2EC4B6), lineWidth: line * 0.5),
                    Part(path: band(0.29), fill: nil, stroke: rgb(0xE63946), lineWidth: line * 0.5)]

        case .soccerBall:
            // A white ball with a black patch in the middle and the edges of
            // five more showing round it.
            let center = p(0, 0.04)
            let r = s * 0.3
            func spoke(_ k: Int, _ reach: CGFloat) -> CGPoint {
                let angle = Double(k) / 5 * 2 * .pi - .pi / 2
                return CGPoint(x: center.x + CGFloat(cos(angle)) * reach, y: center.y + CGFloat(sin(angle)) * reach)
            }
            let middle = poly((0..<5).map { spoke($0, r * 0.36) })
            let seams = strokes((0..<5).map { (spoke($0, r * 0.36), spoke($0, r * 0.78)) })
            let edges = CGMutablePath()
            for k in 0..<5 { edges.addPath(circle(spoke(k, r * 0.92), r * 0.17)) }
            let ball = circle(center, r)
            return [Part(path: ball, fill: rgb(0xFFFFFF)),
                    Part(path: edges, fill: rgb(0x22223B)),
                    Part(path: seams, fill: nil, stroke: rgb(0x22223B), lineWidth: line * 0.35),
                    Part(path: middle, fill: rgb(0x22223B)),
                    Part(path: ball, fill: nil, stroke: ink, lineWidth: line * 0.5)]

        case .kite:
            // A diamond kite flying high on its string, two-tone, with a
            // tail of yellow bows.
            let top = p(0.32, -1.3), left = p(0.08, -1.02), right = p(0.56, -1.02), bottom = p(0.32, -0.62)
            let string = CGMutablePath()
            string.move(to: p(0, 0))
            string.addQuadCurve(to: bottom, control: p(0.38, -0.18))
            let tail = CGMutablePath()
            tail.move(to: bottom)
            tail.addQuadCurve(to: p(0.5, -0.3), control: p(0.24, -0.42))
            let bows = CGMutablePath()
            for (dx, dy) in [(0.3, -0.5), (0.44, -0.36)] as [(CGFloat, CGFloat)] {
                bows.addPath(poly([p(dx - 0.06, dy - 0.04), p(dx + 0.06, dy + 0.04), p(dx + 0.06, dy - 0.04),
                                   p(dx - 0.06, dy + 0.04)]))
            }
            return [Part(path: string, fill: nil, stroke: rgb(0xF1FAEE), lineWidth: line * 0.3),
                    Part(path: tail, fill: nil, stroke: rgb(0xF1FAEE), lineWidth: line * 0.3),
                    Part(path: bows, fill: rgb(0xFFD23F)),
                    Part(path: poly([top, left, bottom]), fill: rgb(0xFF006E)),
                    Part(path: poly([top, right, bottom]), fill: rgb(0x3A86FF)),
                    Part(path: strokes([(top, bottom), (left, right)]), fill: nil, stroke: rgb(0xFFF3B0),
                         lineWidth: line * 0.35),
                    Part(path: poly([top, right, bottom, left]), fill: nil, stroke: ink, lineWidth: line * 0.45)]

        case .pillow:
            // A plump pillow under its arm, its corners pinched out and a
            // tuft in the middle.
            let tl = p(-0.44, -0.3), tr = p(0.44, -0.3), br = p(0.44, 0.22), bl = p(-0.44, 0.22)
            let pillow = CGMutablePath()
            pillow.move(to: tl)
            pillow.addQuadCurve(to: tr, control: p(0, -0.2))
            pillow.addQuadCurve(to: br, control: p(0.34, -0.04))
            pillow.addQuadCurve(to: bl, control: p(0, 0.12))
            pillow.addQuadCurve(to: tl, control: p(-0.34, -0.04))
            pillow.closeSubpath()
            return [Part(path: pillow, fill: rgb(0xE8E4FF), stroke: rgb(0x7B6CD9), lineWidth: line * 0.5),
                    Part(path: strokes([(p(-0.18, -0.12), p(-0.06, -0.06)), (p(0.18, 0.0), p(0.06, -0.04))]), fill: nil,
                         stroke: rgb(0xB8AEF5), lineWidth: line * 0.4),
                    Part(path: circle(p(0, -0.05), s * 0.05), fill: rgb(0x9D8DF1))]

        case .marshmallowStick:
            // A long roasting stick held up, a marshmallow on the tip,
            // already golden underneath.
            let mallow = box(0.42, -0.98, 0.26, 0.28)
            let toast = CGMutablePath()
            toast.move(to: CGPoint(x: mallow.minX, y: mallow.midY + s * 0.02))
            toast.addQuadCurve(to: CGPoint(x: mallow.maxX, y: mallow.midY + s * 0.02),
                               control: CGPoint(x: mallow.midX, y: mallow.midY + s * 0.1))
            toast.addLine(to: CGPoint(x: mallow.maxX, y: mallow.maxY - s * 0.06))
            toast.addQuadCurve(to: CGPoint(x: mallow.minX, y: mallow.maxY - s * 0.06),
                               control: CGPoint(x: mallow.midX, y: mallow.maxY + s * 0.04))
            toast.closeSubpath()
            return [Part(path: strokes([(p(-0.06, 0.16), p(0.55, -0.72))]), fill: nil, stroke: rgb(0x8B5A2B),
                         lineWidth: line * 0.8),
                    Part(path: rounded(mallow, s * 0.09), fill: rgb(0xFFF8F0), stroke: rgb(0xBFA98A), lineWidth: line * 0.4),
                    Part(path: toast, fill: rgb(0xE9A23B))]

        case .waterPistol:
            // A chunky toy blaster: teal barrel, pink grip, a tank of water
            // on top and an orange nozzle.
            let grip = poly([p(-0.16, -0.02), p(0.04, -0.02), p(-0.02, 0.3), p(-0.22, 0.3)])
            let trigger = CGMutablePath()
            trigger.move(to: p(0.08, -0.02))
            trigger.addQuadCurve(to: p(0.06, 0.14), control: p(0.16, 0.08))
            return [Part(path: grip, fill: rgb(0xFF006E), stroke: ink, lineWidth: line * 0.4),
                    Part(path: trigger, fill: nil, stroke: ink, lineWidth: line * 0.4),
                    Part(path: rounded(box(-0.22, -0.24, 0.64, 0.24), s * 0.08), fill: rgb(0x2EC4B6), stroke: ink,
                         lineWidth: line * 0.5),
                    Part(path: rounded(box(-0.12, -0.44, 0.3, 0.2), s * 0.07), fill: rgb(0x8ECAE6), stroke: ink,
                         lineWidth: line * 0.4),
                    Part(path: strokes([(p(-0.06, -0.3), p(0.12, -0.3))]), fill: nil, stroke: rgb(0x3A86FF),
                         lineWidth: line * 0.5),
                    Part(path: rounded(box(0.42, -0.18, 0.12, 0.12), s * 0.03), fill: rgb(0xFF8C42), stroke: ink,
                         lineWidth: line * 0.3)]

        case .confettiCannon:
            // A party popper aimed up and away, striped gold and pink, with
            // a few bits of confetti already escaping.
            let cone = poly([p(-0.16, 0.12), p(0.14, -0.5), p(0.48, -0.2), p(-0.06, 0.24)])
            let stripes = strokes([(p(-0.06, -0.08), p(0.12, 0.06)), (p(0.04, -0.28), p(0.3, -0.06))])
            let bits = CGMutablePath()
            bits.addPath(circle(p(0.38, -0.66), s * 0.045))
            bits.addPath(circle(p(0.6, -0.5), s * 0.04))
            let blue = CGMutablePath()
            blue.addPath(circle(p(0.2, -0.76), s * 0.04))
            blue.addPath(circle(p(0.62, -0.74), s * 0.035))
            let streamer = CGMutablePath()
            streamer.move(to: p(0.32, -0.38))
            streamer.addQuadCurve(to: p(0.5, -0.86), control: p(0.24, -0.66))
            return [Part(path: cone, fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.5),
                    Part(path: stripes, fill: nil, stroke: rgb(0xFF006E), lineWidth: line * 0.8),
                    Part(path: CGPath(ellipseIn: box(0.12, -0.5, 0.36, 0.3), transform: nil), fill: rgb(0xFF8AD8),
                         stroke: ink, lineWidth: line * 0.4),
                    Part(path: streamer, fill: nil, stroke: rgb(0x38B000), lineWidth: line * 0.5),
                    Part(path: bits, fill: rgb(0xFF006E)),
                    Part(path: blue, fill: rgb(0x3A86FF))]

        case .paperPlane:
            // A folded paper plane, nose forward, ready to be thrown.
            let nose = p(0.5, -0.2)
            let wing = poly([nose, p(-0.38, -0.46), p(-0.1, -0.16)])
            let keel = poly([nose, p(-0.1, -0.16), p(-0.26, 0.04)])
            return [Part(path: keel, fill: rgb(0xC9D6E3), stroke: rgb(0x5C677D), lineWidth: line * 0.4),
                    Part(path: wing, fill: rgb(0xFFFFFF), stroke: rgb(0x5C677D), lineWidth: line * 0.4),
                    Part(path: strokes([(nose, p(-0.1, -0.16))]), fill: nil, stroke: rgb(0x5C677D), lineWidth: line * 0.3)]

        case .megaphone:
            // A white cone with a red bell and a mouthpiece at the narrow
            // end, held by its grip.
            let cone = poly([p(-0.12, -0.2), p(0.42, -0.42), p(0.42, 0.22), p(-0.12, 0.0)])
            return [Part(path: rounded(box(-0.02, -0.02, 0.1, 0.24), s * 0.03), fill: rgb(0x2B2D42)),
                    Part(path: cone, fill: rgb(0xF1FAEE), stroke: ink, lineWidth: line * 0.5),
                    Part(path: strokes([(p(0.16, -0.32), p(0.16, 0.12))]), fill: nil, stroke: rgb(0xE63946),
                         lineWidth: line * 0.8),
                    Part(path: CGPath(ellipseIn: box(0.36, -0.42, 0.14, 0.64), transform: nil), fill: rgb(0xE63946),
                         stroke: ink, lineWidth: line * 0.5),
                    Part(path: rounded(box(-0.24, -0.17, 0.14, 0.14), s * 0.04), fill: rgb(0x2B2D42))]

        case .whistle:
            // A silver referee's whistle on a red lanyard.
            let lanyard = CGMutablePath()
            lanyard.move(to: p(0.16, 0.12))
            lanyard.addQuadCurve(to: p(-0.2, 0.06), control: p(0.0, 0.62))
            return [Part(path: lanyard, fill: nil, stroke: rgb(0xE63946), lineWidth: line * 0.6),
                    Part(path: rounded(box(-0.36, -0.16, 0.3, 0.14), s * 0.04), fill: rgb(0xC0C4CC), stroke: ink,
                         lineWidth: line * 0.4),
                    Part(path: circle(p(0.06, 0), s * 0.2), fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.5),
                    Part(path: circle(p(0.06, 0), s * 0.07), fill: rgb(0x5C677D)),
                    Part(path: rounded(box(-0.12, -0.2, 0.08, 0.06), s * 0.02), fill: rgb(0x22223B))]

        case .hulaHoop:
            // A pink hoop tilted round its waist, banded in yellow.
            let torso = f.torso
            let half = max(torso.width, f.width * 0.8) * 0.68
            // On a round figure whose face sits low, the hoop drops to its
            // hips so its far rim passes under the eyes rather than over them.
            let underEyes = max(f.leftEye.y, f.rightEye.y) + f.size * 0.13 + half * 0.22 + line * 1.6
            let waist = max(underEyes,
                            f.anatomy == nil ? f.outline.minY + f.outline.height * 0.74 : torso.midY + torso.height * 0.12)
            let ring = CGRect(x: torso.midX - half, y: waist - half * 0.22, width: half * 2, height: half * 0.44)
            let bands = CGMutablePath()
            for k in stride(from: 0, to: 12, by: 2) {
                for step in 0...3 {
                    let angle = (Double(k) + Double(step) / 3) / 12 * 2 * .pi
                    let point = CGPoint(x: ring.midX + CGFloat(cos(angle)) * ring.width / 2,
                                        y: ring.midY + CGFloat(sin(angle)) * ring.height / 2)
                    if step == 0 { bands.move(to: point) } else { bands.addLine(to: point) }
                }
            }
            let hoop = CGPath(ellipseIn: ring, transform: nil)
            return [Part(path: hoop, fill: nil, stroke: ink, lineWidth: line * 1.6),
                    Part(path: hoop, fill: nil, stroke: rgb(0xFF006E), lineWidth: line * 1.1),
                    Part(path: bands, fill: nil, stroke: rgb(0xFFD23F), lineWidth: line * 1.1)]

        case .jugglingBalls:
            // Three balls in the air over its hand, red, blue and yellow,
            // each with a shine.
            let balls: [(CGFloat, CGFloat, UInt32)] = [(-0.3, -0.34, 0xE63946), (0, -0.66, 0x3A86FF), (0.3, -0.34, 0xFFD23F)]
            var parts = [Part(path: strokes([(p(-0.14, -0.08), p(-0.2, -0.16)), (p(0.14, -0.08), p(0.2, -0.16))]), fill: nil,
                              stroke: rgb(0xF1FAEE), lineWidth: line * 0.35)]
            for (dx, dy, color) in balls {
                parts.append(Part(path: circle(p(dx, dy), s * 0.14), fill: rgb(color), stroke: ink, lineWidth: line * 0.4))
                parts.append(Part(path: circle(p(dx - 0.04, dy - 0.04), s * 0.035), fill: rgb(0xFFFFFF)))
            }
            return parts

        case .walkieTalkie:
            // A yellow walkie-talkie with its antenna up, a speaker grille,
            // a little screen and a red talk button.
            let body = box(-0.18, -0.3, 0.36, 0.62)
            let grille = strokes([(p(-0.1, 0.06), p(0.1, 0.06)), (p(-0.1, 0.13), p(0.1, 0.13)), (p(-0.1, 0.2), p(0.1, 0.2))])
            return [Part(path: strokes([(p(-0.1, -0.3), p(-0.1, -0.64))]), fill: nil, stroke: ink, lineWidth: line * 0.9),
                    Part(path: circle(p(-0.1, -0.66), s * 0.04), fill: rgb(0xFF4D4D)),
                    Part(path: rounded(body, s * 0.07), fill: rgb(0xFFBE0B), stroke: ink, lineWidth: line * 0.5),
                    Part(path: rounded(box(-0.11, -0.22, 0.22, 0.14), s * 0.03), fill: rgb(0x8ECAE6), stroke: ink,
                         lineWidth: line * 0.3),
                    Part(path: grille, fill: nil, stroke: rgb(0x5C3818), lineWidth: line * 0.4),
                    Part(path: circle(p(0.22, -0.08), s * 0.05), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.3)]

        case .picnicBasket:
            // A wicker basket with a handle, a red and white checked cloth
            // along the top and an apple peeking out.
            let basket = poly([p(-0.4, -0.1), p(0.4, -0.1), p(0.32, 0.3), p(-0.32, 0.3)])
            let weave = strokes([(p(-0.37, 0.04), p(0.37, 0.04)), (p(-0.34, 0.18), p(0.34, 0.18)),
                                 (p(-0.16, -0.1), p(-0.13, 0.3)), (p(0.16, -0.1), p(0.13, 0.3)), (p(0, -0.1), p(0, 0.3))])
            let handle = CGMutablePath()
            handle.move(to: p(-0.3, -0.14))
            handle.addQuadCurve(to: p(0.3, -0.14), control: p(0, -0.72))
            let checks = CGMutablePath()
            for k in 0..<5 { checks.addPath(CGPath(rect: box(-0.42 + CGFloat(k) * 0.18, -0.2, 0.09, 0.1), transform: nil)) }
            return [Part(path: handle, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 0.9),
                    Part(path: circle(p(0.18, -0.24), s * 0.09), fill: rgb(0xE63946)),
                    Part(path: basket, fill: rgb(0xD19A5B), stroke: rgb(0x7A4A0F), lineWidth: line * 0.5),
                    Part(path: weave, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 0.35),
                    Part(path: CGPath(rect: box(-0.44, -0.2, 0.88, 0.1), transform: nil), fill: rgb(0xFFFFFF)),
                    Part(path: checks, fill: rgb(0xE63946))]

        default:
            return []
        }
    }
}
