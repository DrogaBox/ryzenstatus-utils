// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The twenty-four of the fair and the field, traced with a few bold paths
/// like the rest of the wardrobe and placed by the figure's anatomy: what
/// is held hangs from the right hand, the hats sit on the head, the
/// binoculars over the eyes, the cape behind the body and the stilts under
/// the feet. y grows downward, as everywhere in the wearables.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func fairParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w: CGFloat = f.width, cx: CGFloat = f.center, top: CGFloat = f.top
        let line: CGFloat = max(0.8, f.size * 0.045)
        let right = f.rightHand
        let s: CGFloat = f.prop
        let ink = rgb(0x16161C)

        func p(_ origin: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + dx * s, y: origin.y + dy * s)
        }
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
        func circle(_ center: CGPoint, _ r: CGFloat) -> CGPath { ellipse(center, r, r) }
        /// A thin bar from `a` to `b`, `thickness` wide.
        func bar(_ a: CGPoint, _ b: CGPoint, _ thickness: CGFloat) -> CGPath {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(0.001, hypot(dx, dy))
            let nx = -dy / length * thickness / 2, ny = dx / length * thickness / 2
            return poly([CGPoint(x: a.x + nx, y: a.y + ny), CGPoint(x: b.x + nx, y: b.y + ny),
                         CGPoint(x: b.x - nx, y: b.y - ny), CGPoint(x: a.x - nx, y: a.y - ny)])
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        /// A five-petal flower of radius `r` at `c`.
        func flower(_ c: CGPoint, _ r: CGFloat) -> CGPath {
            let path = CGMutablePath()
            for index in 0..<5 {
                let angle = CGFloat(index) / 5 * 2 * .pi - .pi / 2
                path.addPath(circle(CGPoint(x: c.x + cos(angle) * r * 0.62, y: c.y + sin(angle) * r * 0.62), r * 0.46))
            }
            return path
        }

        switch accessory {
        case .fishingRod:
            // A cork grip in the hand, a long rod bent up and out, a reel,
            // and the line down to a red and white float.
            let grip0 = p(right, -0.06, 0.2), grip1 = p(right, 0.08, -0.02)
            let tip = p(right, 0.86, -0.92)
            let bend = CGMutablePath()
            bend.move(to: grip1)
            bend.addQuadCurve(to: tip, control: p(right, 0.32, -0.74))
            let float = p(right, 0.98, 0.04)
            let fishingLine = stroke(tip, float)
            let floatTop = CGMutablePath()
            floatTop.addPath(ellipse(p(float, 0, -0.02), 0.07 * s, 0.05 * s))
            return [Part(path: bar(grip0, grip1, 0.12 * s), fill: rgb(0xC9A16B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: bend, fill: nil, stroke: ink, lineWidth: max(1, s * 0.07)),
                    Part(path: bend, fill: nil, stroke: rgb(0x6D4C2E), lineWidth: max(0.6, s * 0.04)),
                    Part(path: circle(p(right, 0.12, 0.08), 0.09 * s), fill: rgb(0xB0B6C2), stroke: ink, lineWidth: line * 0.3),
                    Part(path: fishingLine, fill: nil, stroke: rgb(0xEDEDF2), lineWidth: max(0.4, line * 0.3)),
                    Part(path: ellipse(p(float, 0, 0.03), 0.07 * s, 0.06 * s), fill: rgb(0xF2F2F5), stroke: ink, lineWidth: line * 0.25),
                    Part(path: floatTop, fill: rgb(0xE5383B))]

        case .butterflyNet:
            // A long wooden handle and a hoop of white mesh up at its end.
            let hoop = p(right, 0.72, -0.84)
            let handle = bar(p(right, -0.02, 0.18), p(hoop, -0.16, 0.16), 0.07 * s)
            let bag = CGMutablePath()
            bag.move(to: p(hoop, -0.24, 0))
            bag.addQuadCurve(to: p(hoop, 0.24, 0), control: p(hoop, 0.12, 0.62))
            bag.closeSubpath()
            let mesh = CGMutablePath()
            for dx in [-0.12, 0.0, 0.12] as [CGFloat] {
                mesh.move(to: p(hoop, dx, 0.02))
                mesh.addLine(to: p(hoop, dx * 0.3 + 0.08, 0.38))
            }
            mesh.move(to: p(hoop, -0.18, 0.14)); mesh.addLine(to: p(hoop, 0.2, 0.14))
            mesh.move(to: p(hoop, -0.08, 0.28)); mesh.addLine(to: p(hoop, 0.16, 0.28))
            return [Part(path: handle, fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.3),
                    Part(path: bag, fill: rgb(0xFFFFFF).copy(alpha: 0.55) ?? rgb(0xFFFFFF), stroke: rgb(0xD8DCE4),
                         lineWidth: line * 0.3),
                    Part(path: mesh, fill: nil, stroke: rgb(0xC4CAD6), lineWidth: max(0.4, line * 0.25)),
                    Part(path: ellipse(hoop, 0.24 * s, 0.08 * s), fill: nil, stroke: ink, lineWidth: line * 0.6),
                    Part(path: ellipse(hoop, 0.24 * s, 0.08 * s), fill: nil, stroke: rgb(0x3A86FF), lineWidth: line * 0.35)]

        case .wateringCan:
            // A green can in the hand, its spout reaching out and up to a
            // rose that sprinkles three drops, and a handle over the top.
            let body = CGRect(x: right.x - 0.14 * s, y: right.y - 0.3 * s, width: 0.46 * s, height: 0.38 * s)
            let spoutEnd = p(right, 0.66, -0.42)
            let spout = bar(CGPoint(x: body.maxX - 0.04 * s, y: body.minY + 0.12 * s), spoutEnd, 0.08 * s)
            let rose = ellipse(spoutEnd, 0.06 * s, 0.09 * s)
            let handle = CGMutablePath()
            handle.move(to: CGPoint(x: body.minX + 0.04 * s, y: body.minY + 0.06 * s))
            handle.addQuadCurve(to: CGPoint(x: body.maxX - 0.08 * s, y: body.minY),
                                control: CGPoint(x: body.midX - 0.04 * s, y: body.minY - 0.3 * s))
            let drops = CGMutablePath()
            for (dx, dy) in [(0.04, 0.12), (0.12, 0.2), (0.0, 0.26)] as [(CGFloat, CGFloat)] {
                drops.addPath(ellipse(p(spoutEnd, dx, dy), 0.025 * s, 0.04 * s))
            }
            return [Part(path: handle, fill: nil, stroke: ink, lineWidth: max(1, s * 0.07)),
                    Part(path: handle, fill: nil, stroke: rgb(0x2E9E5B), lineWidth: max(0.6, s * 0.04)),
                    Part(path: spout, fill: rgb(0x2E9E5B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(body, 0.08 * s), fill: rgb(0x3CB371), stroke: ink, lineWidth: line * 0.5),
                    Part(path: CGPath(rect: CGRect(x: body.minX, y: body.midY - 0.03 * s, width: body.width, height: 0.06 * s),
                                      transform: nil), fill: rgb(0x2E9E5B)),
                    Part(path: rose, fill: rgb(0x2E9E5B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: drops, fill: rgb(0x7FC8FF))]

        case .pottedCactus:
            // A terracotta pot in the hand, a round green cactus with two
            // little arms, its spines, and a pink flower on top.
            let rim = p(right, 0.08, -0.06)
            let pot = poly([p(rim, -0.2, 0), p(rim, 0.2, 0), p(rim, 0.15, 0.28), p(rim, -0.15, 0.28)])
            let band = rounded(CGRect(x: rim.x - 0.22 * s, y: rim.y - 0.05 * s, width: 0.44 * s, height: 0.09 * s), 0.03 * s)
            let stem = rounded(CGRect(x: rim.x - 0.1 * s, y: rim.y - 0.56 * s, width: 0.2 * s, height: 0.56 * s), 0.1 * s)
            let armL = rounded(CGRect(x: rim.x - 0.26 * s, y: rim.y - 0.42 * s, width: 0.1 * s, height: 0.22 * s), 0.05 * s)
            let armLLink = bar(p(rim, -0.2, -0.24), p(rim, -0.08, -0.24), 0.08 * s)
            let armR = rounded(CGRect(x: rim.x + 0.16 * s, y: rim.y - 0.48 * s, width: 0.1 * s, height: 0.2 * s), 0.05 * s)
            let armRLink = bar(p(rim, 0.08, -0.32), p(rim, 0.2, -0.32), 0.08 * s)
            let spines = CGMutablePath()
            for (dx, dy) in [(-0.05, -0.46), (0.05, -0.36), (-0.05, -0.24), (0.05, -0.14), (-0.22, -0.36), (0.22, -0.42)]
                as [(CGFloat, CGFloat)] {
                spines.addPath(stroke(p(rim, dx - 0.025, dy), p(rim, dx + 0.025, dy - 0.02)))
            }
            return [Part(path: armLLink, fill: rgb(0x43A047)), Part(path: armRLink, fill: rgb(0x43A047)),
                    Part(path: armL, fill: rgb(0x43A047), stroke: ink, lineWidth: line * 0.3),
                    Part(path: armR, fill: rgb(0x43A047), stroke: ink, lineWidth: line * 0.3),
                    Part(path: stem, fill: rgb(0x4CAF50), stroke: ink, lineWidth: line * 0.4),
                    Part(path: spines, fill: nil, stroke: rgb(0xF5F1D8), lineWidth: max(0.4, line * 0.25)),
                    Part(path: flower(p(rim, 0, -0.58), 0.08 * s), fill: rgb(0xFF6FAE)),
                    Part(path: circle(p(rim, 0, -0.58), 0.03 * s), fill: rgb(0xFFD54F)),
                    Part(path: pot, fill: rgb(0xD9774B), stroke: ink, lineWidth: line * 0.4),
                    Part(path: band, fill: rgb(0xC0613A), stroke: ink, lineWidth: line * 0.3)]

        case .fryingPan:
            // A black pan held out by its handle, a golden pancake in it
            // with a pat of butter on top.
            let pan = p(right, 0.6, -0.26)
            let handle = bar(p(right, -0.04, 0.06), p(pan, -0.28, 0.06), 0.09 * s)
            return [Part(path: handle, fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.3),
                    Part(path: ellipse(p(pan, 0, 0.04), 0.32 * s, 0.13 * s), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(pan, 0.3 * s, 0.11 * s), fill: rgb(0x4A4A55)),
                    Part(path: ellipse(p(pan, 0, -0.02), 0.2 * s, 0.07 * s), fill: rgb(0xE8B04B), stroke: rgb(0xB57F23),
                         lineWidth: line * 0.3),
                    Part(path: rounded(CGRect(x: pan.x - 0.04 * s, y: pan.y - 0.08 * s, width: 0.08 * s, height: 0.05 * s), 0.01 * s),
                         fill: rgb(0xFFF1A6))]

        case .cupcake:
            // A striped paper case, a swirl of pink frosting, a cherry and a
            // little lit candle.
            let base = p(right, 0.06, -0.04)
            let wrapper = poly([p(base, -0.18, -0.08), p(base, 0.18, -0.08), p(base, 0.13, 0.16), p(base, -0.13, 0.16)])
            let stripes = CGMutablePath()
            for dx in [-0.09, 0.0, 0.09] as [CGFloat] { stripes.addPath(stroke(p(base, dx, -0.07), p(base, dx * 0.75, 0.15))) }
            let frosting = CGMutablePath()
            frosting.addPath(ellipse(p(base, 0, -0.14), 0.22 * s, 0.09 * s))
            frosting.addPath(ellipse(p(base, 0, -0.24), 0.15 * s, 0.07 * s))
            frosting.addPath(ellipse(p(base, 0, -0.32), 0.08 * s, 0.05 * s))
            let candle = rounded(CGRect(x: base.x + 0.06 * s, y: base.y - 0.56 * s, width: 0.04 * s, height: 0.2 * s), 0.01 * s)
            let flame = ellipse(p(base, 0.08, -0.62), 0.035 * s, 0.06 * s)
            return [Part(path: frosting, fill: rgb(0xFFB3D1), stroke: ink, lineWidth: line * 0.35),
                    Part(path: candle, fill: rgb(0x8EC5FF), stroke: ink, lineWidth: line * 0.25),
                    Part(path: flame, fill: rgb(0xFFC93C), stroke: rgb(0xFF7A00), lineWidth: line * 0.3),
                    Part(path: circle(p(base, -0.04, -0.38), 0.05 * s), fill: rgb(0xE01E37), stroke: ink, lineWidth: line * 0.25),
                    Part(path: wrapper, fill: rgb(0xF48FB1), stroke: ink, lineWidth: line * 0.4),
                    Part(path: stripes, fill: nil, stroke: rgb(0xFCE4EC), lineWidth: max(0.4, line * 0.3))]

        case .lollipop:
            // A white stick and a big round candy swirled pink and white.
            let candy = p(right, 0.32, -0.62)
            let r: CGFloat = 0.24 * s
            let swirl = CGMutablePath()
            var angle: CGFloat = 0
            var radius: CGFloat = r * 0.1
            swirl.move(to: CGPoint(x: candy.x + radius, y: candy.y))
            while radius < r * 0.92 {
                angle += 0.35
                radius += r * 0.03
                swirl.addLine(to: CGPoint(x: candy.x + cos(angle) * radius, y: candy.y + sin(angle) * radius))
            }
            return [Part(path: bar(p(right, 0, 0.14), p(candy, -0.06, 0.12), 0.06 * s), fill: rgb(0xF5F5F5), stroke: ink,
                         lineWidth: line * 0.25),
                    Part(path: circle(candy, r), fill: rgb(0xFF5C9A), stroke: ink, lineWidth: line * 0.45),
                    Part(path: swirl, fill: nil, stroke: rgb(0xFFF0F6), lineWidth: max(0.6, s * 0.05)),
                    Part(path: ellipse(p(candy, -0.09, -0.1), 0.05 * s, 0.03 * s), fill: rgb(0xFFFFFF))]

        case .trumpet:
            // A brass trumpet held out level: the tube, three valves, a loop
            // under it and the flared bell.
            let mouth = p(right, -0.12, -0.08)
            let bellStart = p(right, 0.5, -0.2)
            let bellEnd = p(right, 0.8, -0.27)
            let tube = bar(mouth, bellStart, 0.07 * s)
            let bell = poly([p(bellStart, 0, -0.04), p(bellEnd, 0, -0.17), p(bellEnd, 0, 0.17), p(bellStart, 0, 0.04)])
            let loop = rounded(CGRect(x: right.x + 0.06 * s, y: right.y - 0.12 * s, width: 0.36 * s, height: 0.14 * s), 0.07 * s)
            let valves = CGMutablePath()
            for dx in [0.12, 0.22, 0.32] as [CGFloat] {
                valves.addPath(rounded(CGRect(x: right.x + dx * s, y: right.y - 0.3 * s, width: 0.06 * s, height: 0.12 * s), 0.02 * s))
            }
            return [Part(path: loop, fill: nil, stroke: rgb(0xC99A2E), lineWidth: max(0.8, s * 0.05)),
                    Part(path: tube, fill: rgb(0xE8B93C), stroke: ink, lineWidth: line * 0.3),
                    Part(path: valves, fill: rgb(0xD4A52F), stroke: ink, lineWidth: line * 0.25),
                    Part(path: bell, fill: rgb(0xF0C64E), stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(bellEnd, 0.06 * s, 0.17 * s), fill: rgb(0xB8862A), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(mouth, 0.04 * s), fill: rgb(0xC0C4CC))]

        case .violin:
            // A violin held up in the hand, neck to the sky, and its bow
            // laid across the strings.
            var turn = CGAffineTransform(translationX: right.x + 0.12 * s, y: right.y - 0.18 * s).rotated(by: 0.5)
            let body = CGMutablePath()
            body.addPath(ellipse(CGPoint(x: 0, y: 0.13 * s), 0.19 * s, 0.16 * s))
            body.addPath(ellipse(CGPoint(x: 0, y: -0.1 * s), 0.15 * s, 0.13 * s))
            let neck = bar(CGPoint(x: 0, y: 0.04 * s), CGPoint(x: 0, y: -0.52 * s), 0.06 * s)
            let scroll = circle(CGPoint(x: 0, y: -0.55 * s), 0.04 * s)
            let holes = CGMutablePath()
            holes.addPath(stroke(CGPoint(x: -0.08 * s, y: 0.02 * s), CGPoint(x: -0.06 * s, y: 0.16 * s)))
            holes.addPath(stroke(CGPoint(x: 0.08 * s, y: 0.02 * s), CGPoint(x: 0.06 * s, y: 0.16 * s)))
            let strings = CGMutablePath()
            for dx in [-0.012, 0.012] as [CGFloat] {
                strings.addPath(stroke(CGPoint(x: dx * s, y: 0.24 * s), CGPoint(x: dx * s, y: -0.5 * s)))
            }
            let bow = bar(CGPoint(x: -0.4 * s, y: -0.04 * s), CGPoint(x: 0.42 * s, y: 0.1 * s), 0.035 * s)
            func turned(_ path: CGPath) -> CGPath { path.copy(using: &turn) ?? path }
            return [Part(path: turned(body), fill: rgb(0xB5651D), stroke: ink, lineWidth: line * 0.4),
                    Part(path: turned(holes), fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.35)),
                    Part(path: turned(neck), fill: rgb(0x1E1E24)),
                    Part(path: turned(strings), fill: nil, stroke: rgb(0xE8E8EE), lineWidth: max(0.3, line * 0.2)),
                    Part(path: turned(scroll), fill: rgb(0x8A4A14), stroke: ink, lineWidth: line * 0.25),
                    Part(path: turned(bow), fill: rgb(0x6D4C2E), stroke: rgb(0xF2EEE2), lineWidth: max(0.3, line * 0.2))]

        case .basketball:
            // An orange ball held up, with its black seams.
            let ball = p(right, 0.06, -0.16)
            let r: CGFloat = 0.25 * s
            let seams = CGMutablePath()
            seams.addPath(stroke(CGPoint(x: ball.x, y: ball.y - r), CGPoint(x: ball.x, y: ball.y + r)))
            seams.addPath(stroke(CGPoint(x: ball.x - r, y: ball.y), CGPoint(x: ball.x + r, y: ball.y)))
            seams.move(to: CGPoint(x: ball.x - r * 0.7, y: ball.y - r * 0.7))
            seams.addQuadCurve(to: CGPoint(x: ball.x - r * 0.7, y: ball.y + r * 0.7), control: CGPoint(x: ball.x - r * 0.2, y: ball.y))
            seams.move(to: CGPoint(x: ball.x + r * 0.7, y: ball.y - r * 0.7))
            seams.addQuadCurve(to: CGPoint(x: ball.x + r * 0.7, y: ball.y + r * 0.7), control: CGPoint(x: ball.x + r * 0.2, y: ball.y))
            return [Part(path: circle(ball, r), fill: rgb(0xF57C2B), stroke: ink, lineWidth: line * 0.45),
                    Part(path: seams, fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.35)),
                    Part(path: ellipse(p(ball, -0.1, -0.12), 0.05 * s, 0.03 * s), fill: rgb(0xFFB27A))]

        case .puzzleCube:
            // A cube of coloured stickers in the hand, seen from above a
            // corner: white on top, red and blue sides, a few out of place.
            let c = p(right, 0.06, -0.24)
            let e: CGFloat = 0.22 * s
            let topFace = [CGPoint(x: c.x, y: c.y - e), CGPoint(x: c.x + e * 0.95, y: c.y - e * 0.5),
                           CGPoint(x: c.x, y: c.y), CGPoint(x: c.x - e * 0.95, y: c.y - e * 0.5)]
            let leftFace = [CGPoint(x: c.x - e * 0.95, y: c.y - e * 0.5), CGPoint(x: c.x, y: c.y),
                            CGPoint(x: c.x, y: c.y + e * 1.05), CGPoint(x: c.x - e * 0.95, y: c.y + e * 0.55)]
            let rightFace = [CGPoint(x: c.x, y: c.y), CGPoint(x: c.x + e * 0.95, y: c.y - e * 0.5),
                             CGPoint(x: c.x + e * 0.95, y: c.y + e * 0.55), CGPoint(x: c.x, y: c.y + e * 1.05)]
            /// The 3×3 grid lines across a face given by its corners a b c d.
            func grid(_ q: [CGPoint]) -> CGPath {
                let path = CGMutablePath()
                for k in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    let a = CGPoint(x: q[0].x + (q[1].x - q[0].x) * k, y: q[0].y + (q[1].y - q[0].y) * k)
                    let b = CGPoint(x: q[3].x + (q[2].x - q[3].x) * k, y: q[3].y + (q[2].y - q[3].y) * k)
                    path.addPath(stroke(a, b))
                    let c2 = CGPoint(x: q[0].x + (q[3].x - q[0].x) * k, y: q[0].y + (q[3].y - q[0].y) * k)
                    let d2 = CGPoint(x: q[1].x + (q[2].x - q[1].x) * k, y: q[1].y + (q[2].y - q[1].y) * k)
                    path.addPath(stroke(c2, d2))
                }
                return path
            }
            /// One sticker of a face, at column i and row j.
            func cell(_ q: [CGPoint], _ i: CGFloat, _ j: CGFloat) -> CGPath {
                func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                    let top = CGPoint(x: q[0].x + (q[1].x - q[0].x) * u, y: q[0].y + (q[1].y - q[0].y) * u)
                    let bottom = CGPoint(x: q[3].x + (q[2].x - q[3].x) * u, y: q[3].y + (q[2].y - q[3].y) * u)
                    return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
                }
                let third: CGFloat = 1.0 / 3
                return poly([at(i * third, j * third), at((i + 1) * third, j * third),
                             at((i + 1) * third, (j + 1) * third), at(i * third, (j + 1) * third)])
            }
            return [Part(path: poly(topFace), fill: rgb(0xF4F4F6)),
                    Part(path: poly(leftFace), fill: rgb(0xE53935)),
                    Part(path: poly(rightFace), fill: rgb(0x1E88E5)),
                    Part(path: cell(topFace, 2, 0), fill: rgb(0xFFD600)),
                    Part(path: cell(leftFace, 1, 1), fill: rgb(0x43A047)),
                    Part(path: cell(rightFace, 0, 2), fill: rgb(0xFB8C00)),
                    Part(path: cell(rightFace, 2, 1), fill: rgb(0xFFD600)),
                    Part(path: grid(topFace), fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3)),
                    Part(path: grid(leftFace), fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3)),
                    Part(path: grid(rightFace), fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3)),
                    Part(path: poly([topFace[0], topFace[1], rightFace[2], rightFace[3], leftFace[3], topFace[3]]), fill: nil,
                         stroke: ink, lineWidth: line * 0.45)]

        case .answerBall:
            // A shiny black ball with a little window where the answer
            // floats up on a blue die.
            let ball = p(right, 0.06, -0.2)
            let window = p(ball, 0.05, -0.04)
            return [Part(path: circle(ball, 0.28 * s), fill: rgb(0x15151A), stroke: rgb(0x3A3A46), lineWidth: line * 0.4),
                    Part(path: circle(window, 0.11 * s), fill: rgb(0x1F2A57), stroke: rgb(0xD8DCE6), lineWidth: line * 0.3),
                    Part(path: poly([p(window, 0, -0.07), p(window, 0.065, 0.045), p(window, -0.065, 0.045)]), fill: rgb(0x4F7BFF)),
                    Part(path: ellipse(p(ball, -0.1, -0.13), 0.06 * s, 0.035 * s), fill: rgb(0xFFFFFF).copy(alpha: 0.7) ?? rgb(0xFFFFFF))]

        case .pinwheel:
            // A stick with a four-coloured paper wheel at the top.
            let hub = p(right, 0.18, -0.58)
            let colors: [UInt32] = [0xE63946, 0xFFB703, 0x2A9D8F, 0x3A86FF]
            var parts = [Part(path: bar(p(right, 0, 0.16), hub, 0.05 * s), fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.25)]
            for (index, color) in colors.enumerated() {
                let angle = CGFloat(index) * .pi / 2
                let tip = CGPoint(x: hub.x + cos(angle) * 0.28 * s, y: hub.y + sin(angle) * 0.28 * s)
                let side = CGPoint(x: hub.x + cos(angle + .pi / 2) * 0.16 * s, y: hub.y + sin(angle + .pi / 2) * 0.16 * s)
                let blade = CGMutablePath()
                blade.move(to: hub)
                blade.addLine(to: tip)
                blade.addQuadCurve(to: side, control: CGPoint(x: (tip.x + side.x) / 2 + cos(angle + .pi / 4) * 0.1 * s,
                                                              y: (tip.y + side.y) / 2 + sin(angle + .pi / 4) * 0.1 * s))
                blade.closeSubpath()
                parts.append(Part(path: blade, fill: rgb(color), stroke: ink, lineWidth: line * 0.3))
            }
            parts.append(Part(path: circle(hub, 0.035 * s), fill: rgb(0xF5F5F5), stroke: ink, lineWidth: line * 0.25))
            return parts

        case .slingshot:
            // A wooden Y, its band pulled back to a pouch with a pebble.
            let fork = p(right, 0.06, -0.14)
            let armL = p(fork, -0.16, -0.26), armR = p(fork, 0.18, -0.26)
            let pouch = p(fork, -0.3, -0.2)
            let band = CGMutablePath()
            band.move(to: armL); band.addLine(to: pouch); band.addLine(to: armR)
            return [Part(path: bar(p(right, -0.02, 0.18), fork, 0.08 * s), fill: rgb(0x8D5A2B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: bar(fork, armL, 0.07 * s), fill: rgb(0x8D5A2B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: bar(fork, armR, 0.07 * s), fill: rgb(0x8D5A2B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: band, fill: nil, stroke: rgb(0xD62839), lineWidth: max(0.6, s * 0.035)),
                    Part(path: ellipse(pouch, 0.07 * s, 0.05 * s), fill: rgb(0x6D4C2E), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(p(pouch, 0.02, -0.01), 0.035 * s), fill: rgb(0x9AA0A6))]

        case .balloonDog:
            // A twisted balloon dog held up: body, head and snout, ears up,
            // four short legs and a tail, all shiny pink.
            let b = p(right, 0.22, -0.34)
            let pink = rgb(0xFF5C8A)
            let shapes: [CGPath] = [
                ellipse(b, 0.2 * s, 0.085 * s),
                ellipse(p(b, 0.24, -0.16), 0.1 * s, 0.085 * s),
                ellipse(p(b, 0.36, -0.13), 0.08 * s, 0.05 * s),
                ellipse(p(b, 0.2, -0.3), 0.045 * s, 0.09 * s),
                ellipse(p(b, 0.29, -0.29), 0.045 * s, 0.09 * s),
                ellipse(p(b, -0.13, 0.12), 0.04 * s, 0.09 * s),
                ellipse(p(b, -0.05, 0.13), 0.04 * s, 0.09 * s),
                ellipse(p(b, 0.08, 0.13), 0.04 * s, 0.09 * s),
                ellipse(p(b, 0.15, 0.12), 0.04 * s, 0.09 * s),
                ellipse(p(b, -0.25, -0.1), 0.04 * s, 0.09 * s),
            ]
            var parts = shapes.map { Part(path: $0, fill: pink, stroke: ink, lineWidth: line * 0.3) }
            parts.append(Part(path: ellipse(p(b, -0.06, -0.03), 0.07 * s, 0.025 * s), fill: rgb(0xFFC2D4)))
            parts.append(Part(path: ellipse(p(b, 0.21, -0.19), 0.035 * s, 0.02 * s), fill: rgb(0xFFC2D4)))
            parts.append(Part(path: circle(p(b, 0.25, -0.18), 0.018 * s), fill: ink))
            return parts

        case .sparkler:
            // A wire stick burning at the top, sparks flying out of a glow.
            let tip = p(right, 0.38, -0.62)
            let rays = CGMutablePath()
            for index in 0..<10 {
                let angle = CGFloat(index) / 10 * 2 * .pi
                let reach: CGFloat = index % 2 == 0 ? 0.24 : 0.15
                rays.addPath(stroke(CGPoint(x: tip.x + cos(angle) * 0.05 * s, y: tip.y + sin(angle) * 0.05 * s),
                                    CGPoint(x: tip.x + cos(angle) * reach * s, y: tip.y + sin(angle) * reach * s)))
            }
            let dots = CGMutablePath()
            for (dx, dy) in [(0.2, -0.16), (-0.18, -0.12), (0.12, 0.2), (-0.1, 0.18)] as [(CGFloat, CGFloat)] {
                dots.addPath(circle(p(tip, dx, dy), 0.018 * s))
            }
            return [Part(path: bar(p(right, 0, 0.14), tip, 0.035 * s), fill: rgb(0x8E949E), stroke: ink, lineWidth: line * 0.2),
                    Part(path: circle(tip, 0.09 * s), fill: rgb(0xFFF3B0).copy(alpha: 0.85) ?? rgb(0xFFF3B0)),
                    Part(path: rays, fill: nil, stroke: rgb(0xFFC93C), lineWidth: max(0.5, line * 0.35)),
                    Part(path: dots, fill: rgb(0xFF8A00)),
                    Part(path: circle(tip, 0.035 * s), fill: rgb(0xFFFFFF))]

        case .boomBox:
            // A boombox carried by its handle at the side: two speakers, a
            // tape deck between them and an antenna.
            let box = CGRect(x: right.x - 0.3 * s, y: right.y + 0.06 * s, width: 0.62 * s, height: 0.34 * s)
            let handle = CGMutablePath()
            handle.move(to: CGPoint(x: box.minX + 0.12 * s, y: box.minY))
            handle.addQuadCurve(to: CGPoint(x: box.maxX - 0.12 * s, y: box.minY), control: CGPoint(x: box.midX, y: box.minY - 0.2 * s))
            let speakerL = CGPoint(x: box.minX + 0.13 * s, y: box.midY + 0.02 * s)
            let speakerR = CGPoint(x: box.maxX - 0.13 * s, y: box.midY + 0.02 * s)
            let deck = rounded(CGRect(x: box.midX - 0.09 * s, y: box.minY + 0.08 * s, width: 0.18 * s, height: 0.12 * s), 0.02 * s)
            let antenna = stroke(CGPoint(x: box.maxX - 0.06 * s, y: box.minY), CGPoint(x: box.maxX + 0.12 * s, y: box.minY - 0.36 * s))
            return [Part(path: antenna, fill: nil, stroke: rgb(0xC0C4CC), lineWidth: max(0.5, line * 0.35)),
                    Part(path: handle, fill: nil, stroke: ink, lineWidth: max(1, s * 0.06)),
                    Part(path: rounded(box, 0.05 * s), fill: rgb(0x3A3A46), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(speakerL, 0.1 * s), fill: rgb(0x1E1E24), stroke: rgb(0xB0B6C2), lineWidth: line * 0.3),
                    Part(path: circle(speakerR, 0.1 * s), fill: rgb(0x1E1E24), stroke: rgb(0xB0B6C2), lineWidth: line * 0.3),
                    Part(path: circle(speakerL, 0.04 * s), fill: rgb(0x6E7585)),
                    Part(path: circle(speakerR, 0.04 * s), fill: rgb(0x6E7585)),
                    Part(path: deck, fill: rgb(0xA7B4C8), stroke: ink, lineWidth: line * 0.25),
                    Part(path: CGPath(rect: CGRect(x: box.midX - 0.07 * s, y: box.maxY - 0.08 * s, width: 0.14 * s, height: 0.03 * s),
                                      transform: nil), fill: rgb(0xFF5C5C))]

        case .hardHat:
            // A yellow hard hat with a ridge down the middle and a brim
            // all round, and a little lamp at the front.
            let base = top + w * 0.12
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.4, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.4, y: base), control1: CGPoint(x: cx - w * 0.4, y: top - w * 0.34),
                          control2: CGPoint(x: cx + w * 0.4, y: top - w * 0.34))
            dome.closeSubpath()
            let brim = rounded(CGRect(x: cx - w * 0.5, y: base - w * 0.03, width: w, height: w * 0.08), w * 0.04)
            let ridge = rounded(CGRect(x: cx - w * 0.05, y: top - w * 0.2, width: w * 0.1, height: base - top + w * 0.17), w * 0.04)
            return [Part(path: dome, fill: rgb(0xF6C026), stroke: ink, lineWidth: line * 0.5),
                    Part(path: ridge, fill: rgb(0xE0A800)),
                    Part(path: brim, fill: rgb(0xF2B705), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(CGPoint(x: cx, y: base - w * 0.12), w * 0.06), fill: rgb(0xFFF6C8), stroke: ink, lineWidth: line * 0.3)]

        case .astronautHelmet:
            // A glass dome round the whole head, a white collar ring under
            // it, a glint on the glass and a little antenna with its light.
            let o = f.outline
            let dome = CGRect(x: cx - w * 0.64, y: top - w * 0.16, width: w * 1.28, height: max(o.height, w) * 1.08)
            let collarY = min(dome.maxY, f.neckY + w * 0.06)
            let collar = rounded(CGRect(x: cx - w * 0.5, y: collarY - w * 0.06, width: w, height: w * 0.12), w * 0.06)
            let glint = CGMutablePath()
            glint.addArc(center: CGPoint(x: dome.midX, y: dome.midY), radius: w * 0.5, startAngle: .pi * 1.12, endAngle: .pi * 1.38,
                         clockwise: false)
            let antenna = stroke(CGPoint(x: cx + w * 0.26, y: dome.minY + w * 0.06), CGPoint(x: cx + w * 0.36, y: dome.minY - w * 0.18))
            return [Part(path: ellipse(CGPoint(x: dome.midX, y: dome.midY), dome.width / 2, dome.height / 2),
                         fill: rgb(0xBFE6FF).copy(alpha: 0.22) ?? rgb(0xBFE6FF), stroke: rgb(0xF4F7FB), lineWidth: max(1, line * 0.9)),
                    Part(path: glint, fill: nil, stroke: rgb(0xFFFFFF).copy(alpha: 0.8) ?? rgb(0xFFFFFF), lineWidth: max(1, line * 0.8)),
                    Part(path: antenna, fill: nil, stroke: rgb(0xC0C4CC), lineWidth: max(0.6, line * 0.4)),
                    Part(path: circle(CGPoint(x: cx + w * 0.36, y: dome.minY - w * 0.2), w * 0.04), fill: rgb(0xFF3B30)),
                    Part(path: collar, fill: rgb(0xF4F7FB), stroke: rgb(0x9AA4B2), lineWidth: line * 0.4)]

        case .graduationCap:
            // A square mortarboard tilted on the head, the cap under it and a
            // gold tassel hanging off one corner.
            let board = [CGPoint(x: cx - w * 0.52, y: top - w * 0.06), CGPoint(x: cx, y: top - w * 0.26),
                         CGPoint(x: cx + w * 0.52, y: top - w * 0.06), CGPoint(x: cx, y: top + w * 0.12)]
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: cx - w * 0.32, y: top - w * 0.02))
            cap.addLine(to: CGPoint(x: cx - w * 0.3, y: top + w * 0.14))
            cap.addQuadCurve(to: CGPoint(x: cx + w * 0.3, y: top + w * 0.14), control: CGPoint(x: cx, y: top + w * 0.22))
            cap.addLine(to: CGPoint(x: cx + w * 0.32, y: top - w * 0.02))
            cap.closeSubpath()
            let cord = CGMutablePath()
            cord.move(to: CGPoint(x: cx, y: top - w * 0.07))
            cord.addLine(to: CGPoint(x: cx + w * 0.46, y: top - w * 0.06))
            cord.addLine(to: CGPoint(x: cx + w * 0.48, y: top + w * 0.2))
            let tassel = poly([CGPoint(x: cx + w * 0.45, y: top + w * 0.18), CGPoint(x: cx + w * 0.51, y: top + w * 0.18),
                               CGPoint(x: cx + w * 0.53, y: top + w * 0.32), CGPoint(x: cx + w * 0.43, y: top + w * 0.32)])
            return [Part(path: cap, fill: rgb(0x23232B), stroke: ink, lineWidth: line * 0.4),
                    Part(path: poly(board), fill: rgb(0x2E2E38), stroke: ink, lineWidth: line * 0.45),
                    Part(path: cord, fill: nil, stroke: rgb(0xF2C14E), lineWidth: max(0.6, line * 0.45)),
                    Part(path: tassel, fill: rgb(0xF2C14E), stroke: rgb(0xB8862A), lineWidth: line * 0.25),
                    Part(path: circle(CGPoint(x: cx, y: top - w * 0.07), w * 0.035), fill: rgb(0xF2C14E))]

        case .flowerCrown:
            // A green vine round the top of the head with five flowers on it.
            let vine = CGMutablePath()
            let y0 = top + w * 0.1
            vine.move(to: CGPoint(x: cx - w * 0.46, y: y0))
            vine.addQuadCurve(to: CGPoint(x: cx + w * 0.46, y: y0), control: CGPoint(x: cx, y: top - w * 0.12))
            var parts = [Part(path: vine, fill: nil, stroke: rgb(0x3E8E41), lineWidth: max(1, w * 0.05))]
            let colors: [UInt32] = [0xFF8FB8, 0xFFD54F, 0xFFFFFF, 0xC9A7FF, 0xFF8FB8]
            for index in 0..<5 {
                let t = CGFloat(index) / 4
                let x = cx - w * 0.46 + w * 0.92 * t
                let y = y0 + (1 - t) * (1 - t) * 0 + 2 * (1 - t) * t * (top - w * 0.12 - y0)
                let c = CGPoint(x: x, y: y)
                let leaf = ellipse(CGPoint(x: x + w * 0.06, y: y + w * 0.03), w * 0.05, w * 0.025)
                parts.append(Part(path: leaf, fill: rgb(0x66BB6A)))
                parts.append(Part(path: flower(c, w * (index == 2 ? 0.1 : 0.085)), fill: rgb(colors[index]), stroke: ink,
                                  lineWidth: line * 0.2))
                parts.append(Part(path: circle(c, w * 0.03), fill: rgb(0xFFB300)))
            }
            return parts

        case .binoculars:
            // Two barrels over the eyes joined by a bridge, blue glass with
            // a glint, and a strap hanging below.
            let gap = abs(f.rightEye.x - f.leftEye.x)
            let r: CGFloat = max(gap * 0.36, f.size * 0.06)
            let strap = CGMutablePath()
            strap.move(to: CGPoint(x: f.leftEye.x - r, y: f.leftEye.y + r * 0.4))
            strap.addQuadCurve(to: CGPoint(x: f.rightEye.x + r, y: f.rightEye.y + r * 0.4),
                               control: CGPoint(x: (f.leftEye.x + f.rightEye.x) / 2, y: max(f.leftEye.y, f.rightEye.y) + r * 3))
            let bridge = rounded(CGRect(x: f.leftEye.x, y: (f.leftEye.y + f.rightEye.y) / 2 - r * 0.3,
                                        width: f.rightEye.x - f.leftEye.x, height: r * 0.6), r * 0.2)
            var parts = [Part(path: strap, fill: nil, stroke: rgb(0x6D4C2E), lineWidth: max(0.6, line * 0.4)),
                         Part(path: bridge, fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.3)]
            for eye in [f.leftEye, f.rightEye] {
                parts.append(Part(path: circle(eye, r * 1.15), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.4))
                parts.append(Part(path: circle(eye, r * 0.78), fill: rgb(0x3D6FB5)))
                parts.append(Part(path: ellipse(CGPoint(x: eye.x - r * 0.28, y: eye.y - r * 0.3), r * 0.22, r * 0.14),
                                  fill: rgb(0xFFFFFF).copy(alpha: 0.8) ?? rgb(0xFFFFFF)))
            }
            return parts

        case .superCape:
            // A red cape from the shoulders, flaring wide and low behind the
            // body with a wavy hem, gold clasps at the neck.
            // A figure with a body of its own wears it from the shoulders to
            // the floor, flaring out past a narrow body so it shows; on one
            // that is a single round shape it hangs from under the chin and
            // just peeks out at the sides, never below the figure.
            let bodied = f.separateBody
            let torso = bodied ? f.torso : f.outline
            let neck = bodied ? torso.minY + torso.height * 0.04 : max(f.neckY - w * 0.1, torso.minY + torso.height * 0.45)
            let hemY = bodied ? max(f.floor - torso.height * 0.04, neck + w * 0.3) : f.floor + w * 0.04
            let half = bodied ? max(torso.width * 0.42, w * 0.3) : w * 0.34
            let flare: CGFloat = bodied ? 1.9 : 1.5
            let cape = CGMutablePath()
            cape.move(to: CGPoint(x: torso.midX - half * 0.7, y: neck))
            cape.addLine(to: CGPoint(x: torso.midX + half * 0.7, y: neck))
            cape.addQuadCurve(to: CGPoint(x: torso.midX + half * flare, y: hemY),
                              control: CGPoint(x: torso.midX + half * flare * 0.9, y: neck + (hemY - neck) * 0.4))
            let waves = 4
            for index in 0..<waves {
                let x0 = torso.midX + half * flare - CGFloat(index) * half * flare * 2 / CGFloat(waves)
                let x1 = x0 - half * flare * 2 / CGFloat(waves)
                cape.addQuadCurve(to: CGPoint(x: x1, y: hemY), control: CGPoint(x: (x0 + x1) / 2, y: hemY + w * 0.07))
            }
            cape.addQuadCurve(to: CGPoint(x: torso.midX - half * 0.7, y: neck),
                              control: CGPoint(x: torso.midX - half * flare * 0.9, y: neck + (hemY - neck) * 0.4))
            cape.closeSubpath()
            let fold = CGMutablePath()
            fold.move(to: CGPoint(x: torso.midX - half * 0.3, y: neck + w * 0.06))
            fold.addLine(to: CGPoint(x: torso.midX - half * 0.9, y: hemY - w * 0.04))
            fold.move(to: CGPoint(x: torso.midX + half * 0.3, y: neck + w * 0.06))
            fold.addLine(to: CGPoint(x: torso.midX + half * 0.9, y: hemY - w * 0.04))
            return [Part(path: cape, fill: rgb(0xD62839), stroke: ink, lineWidth: line * 0.45),
                    Part(path: fold, fill: nil, stroke: rgb(0x9E1B2A), lineWidth: max(0.6, line * 0.45)),
                    Part(path: circle(CGPoint(x: torso.midX - half * 0.66, y: neck), w * 0.04), fill: rgb(0xF2C14E),
                         stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(CGPoint(x: torso.midX + half * 0.66, y: neck), w * 0.04), fill: rgb(0xF2C14E),
                         stroke: ink, lineWidth: line * 0.25)]

        case .stilts:
            // Two wooden stilts under its feet: a pole each, reaching down
            // past the floor to rubber tips, and a footrest it stands on.
            let unit = f.feetUnit
            let feet = f.feet(spread: 0.18)
            let floor = f.floor
            var parts: [Part] = []
            for x in [feet.left, feet.right] {
                let pole = bar(CGPoint(x: x, y: floor - unit * 0.14), CGPoint(x: x, y: floor + unit * 0.62), unit * 0.08)
                let rest = bar(CGPoint(x: x - unit * 0.14, y: floor + unit * 0.03), CGPoint(x: x + unit * 0.14, y: floor + unit * 0.03),
                               unit * 0.06)
                let tip = ellipse(CGPoint(x: x, y: floor + unit * 0.64), unit * 0.06, unit * 0.04)
                parts += [Part(path: pole, fill: rgb(0xC08A4E), stroke: ink, lineWidth: line * 0.3),
                          Part(path: rest, fill: rgb(0x8D5A2B), stroke: ink, lineWidth: line * 0.3),
                          Part(path: tip, fill: ink)]
            }
            return parts

        default:
            return []
        }
    }
}
