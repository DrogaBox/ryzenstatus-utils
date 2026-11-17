// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The twenty-four of the lab, traced with a few bold paths like the rest
/// of the wardrobe and placed by the figure's anatomy: almost everything
/// is held in the right hand, the lightning rod sits on the head, the gas
/// mask over the eyes, and the rubber boots and the skates on the two
/// feet. y grows downward, as everywhere in the wearables.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func labParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
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
        /// A star of `points` points and radius `r` at `c`, its inner
        /// corners at `inner` of the radius.
        func star(_ c: CGPoint, _ r: CGFloat, _ points: Int, inner: CGFloat = 0.45) -> CGPath {
            var corners: [CGPoint] = []
            for index in 0..<(points * 2) {
                let angle = CGFloat(index) / CGFloat(points * 2) * 2 * .pi - .pi / 2
                let radius: CGFloat = index.isMultiple(of: 2) ? r : r * inner
                corners.append(CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius))
            }
            return poly(corners)
        }
        /// A teardrop flame standing on `base`: a round bulb of radius `r`
        /// at the bottom and its tip `h` above the base.
        func flame(_ base: CGPoint, _ r: CGFloat, _ h: CGFloat) -> CGPath {
            let bulb = CGPoint(x: base.x, y: base.y - r)
            let tip = CGPoint(x: base.x, y: base.y - h)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addQuadCurve(to: CGPoint(x: bulb.x + r, y: bulb.y), control: CGPoint(x: bulb.x + r, y: (tip.y + bulb.y) / 2))
            path.addArc(center: bulb, radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
            path.addQuadCurve(to: tip, control: CGPoint(x: bulb.x - r, y: (tip.y + bulb.y) / 2))
            path.closeSubpath()
            return path
        }
        /// A pointed leaf reaching `r` either side of `c`, lying at `angle`.
        func leaf(_ c: CGPoint, _ r: CGFloat, _ angle: CGFloat) -> CGPath {
            let dx = cos(angle) * r, dy = sin(angle) * r
            let a = CGPoint(x: c.x - dx, y: c.y - dy), b = CGPoint(x: c.x + dx, y: c.y + dy)
            let path = CGMutablePath()
            path.move(to: a)
            path.addQuadCurve(to: b, control: CGPoint(x: c.x - dy * 0.8, y: c.y + dx * 0.8))
            path.addQuadCurve(to: a, control: CGPoint(x: c.x + dy * 0.8, y: c.y - dx * 0.8))
            path.closeSubpath()
            return path
        }
        /// A boot on the foot at `x`, its toe turned out to side `d` (-1
        /// left, 1 right) and its shaft `height` of the feet unit tall.
        func boot(_ x: CGFloat, _ d: CGFloat, _ height: CGFloat) -> CGPath {
            let floor = f.floor, fu = f.feetUnit
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - d * fu * 0.12, y: floor - fu * height))
            path.addLine(to: CGPoint(x: x + d * fu * 0.07, y: floor - fu * height))
            path.addLine(to: CGPoint(x: x + d * fu * 0.07, y: floor - fu * 0.11))
            path.addQuadCurve(to: CGPoint(x: x + d * fu * 0.19, y: floor - fu * 0.02),
                              control: CGPoint(x: x + d * fu * 0.19, y: floor - fu * 0.11))
            path.addLine(to: CGPoint(x: x + d * fu * 0.19, y: floor))
            path.addLine(to: CGPoint(x: x - d * fu * 0.12, y: floor))
            path.closeSubpath()
            return path
        }

        switch accessory {
        case .torch:
            // A wooden torch held up, a dark iron cup at its head and a tall
            // flame in two colours, a few sparks lifting off it.
            let head = p(right, 0.22, -0.44)
            let handle = bar(p(right, -0.04, 0.18), head, 0.1 * s)
            let cup = poly([p(head, -0.13, -0.08), p(head, 0.13, -0.08), p(head, 0.07, 0.08), p(head, -0.07, 0.08)])
            let sparks = CGMutablePath()
            for (dx, dy) in [(0.18, -0.5), (-0.15, -0.44), (0.08, -0.64)] as [(CGFloat, CGFloat)] {
                sparks.addPath(circle(p(head, dx, dy), 0.028 * s))
            }
            return [Part(path: handle, fill: rgb(0x9C6B3C), stroke: ink, lineWidth: line * 0.3),
                    Part(path: flame(p(head, 0, -0.04), 0.15 * s, 0.5 * s), fill: rgb(0xFF7A00), stroke: ink, lineWidth: line * 0.35),
                    Part(path: flame(p(head, 0, -0.06), 0.08 * s, 0.3 * s), fill: rgb(0xFFD23F)),
                    Part(path: cup, fill: rgb(0x4A4A55), stroke: ink, lineWidth: line * 0.35),
                    Part(path: sparks, fill: rgb(0xFFC93C))]

        case .waterBalloon:
            // A round red balloon full of water, tied with a knot down at
            // the hand, a shine on it and two drops running off.
            let c = p(right, 0.1, -0.34)
            let knot = poly([p(c, 0, 0.25), p(c, 0.06, 0.34), p(c, -0.06, 0.34)])
            let drops = CGMutablePath()
            drops.addPath(ellipse(p(c, 0.29, 0.02), 0.03 * s, 0.045 * s))
            drops.addPath(ellipse(p(c, 0.33, 0.16), 0.025 * s, 0.038 * s))
            return [Part(path: ellipse(c, 0.24 * s, 0.27 * s), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.45),
                    Part(path: knot, fill: rgb(0xB5172B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: ellipse(p(c, -0.09, -0.12), 0.07 * s, 0.04 * s), fill: rgba(0xFFFFFF, 0.75)),
                    Part(path: drops, fill: rgb(0x4CC9F0), stroke: ink, lineWidth: line * 0.2)]

        case .leafBlower:
            // An orange engine carried by its handle, a long grey tube out
            // front, gusts of air and two leaves tumbling off its mouth.
            let body = CGRect(x: right.x - 0.18 * s, y: right.y - 0.28 * s, width: 0.36 * s, height: 0.3 * s)
            let handle = CGMutablePath()
            handle.move(to: CGPoint(x: body.minX + 0.06 * s, y: body.minY + 0.02 * s))
            handle.addQuadCurve(to: CGPoint(x: body.maxX - 0.06 * s, y: body.minY + 0.02 * s),
                                control: CGPoint(x: body.midX, y: body.minY - 0.24 * s))
            let mouth = p(right, 0.56, 0.04)
            let tube = bar(CGPoint(x: body.maxX - 0.04 * s, y: body.midY), mouth, 0.11 * s)
            let gusts = CGMutablePath()
            for (dy, length) in [(-0.08, 0.14), (0.03, 0.2), (0.14, 0.12)] as [(CGFloat, CGFloat)] {
                gusts.addPath(stroke(p(mouth, 0.1, dy), p(mouth, 0.1 + length, dy + length * 0.12)))
            }
            return [Part(path: handle, fill: nil, stroke: ink, lineWidth: max(1, s * 0.07)),
                    Part(path: handle, fill: nil, stroke: rgb(0x2B2B33), lineWidth: max(0.6, s * 0.04)),
                    Part(path: tube, fill: rgb(0x8E949E), stroke: ink, lineWidth: line * 0.3),
                    Part(path: ellipse(mouth, 0.04 * s, 0.07 * s), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.25),
                    Part(path: rounded(body, 0.08 * s), fill: rgb(0xF77F00), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(CGPoint(x: body.midX - 0.03 * s, y: body.midY + 0.02 * s), 0.07 * s), fill: rgb(0x2B2B33)),
                    Part(path: gusts, fill: nil, stroke: rgba(0xFFFFFF, 0.8), lineWidth: max(0.5, line * 0.35)),
                    Part(path: leaf(p(mouth, 0.26, -0.16), 0.07 * s, 0.6), fill: rgb(0xF4A261), stroke: ink, lineWidth: line * 0.2),
                    Part(path: leaf(p(mouth, 0.32, 0.12), 0.06 * s, -0.4), fill: rgb(0x6A994E), stroke: ink, lineWidth: line * 0.2)]

        case .plasmaBall:
            // A glass globe on a black stand, purple lightning crawling
            // from the bright core out to the glass.
            let c = p(right, 0.06, -0.42)
            let r: CGFloat = 0.28 * s
            let base = poly([p(right, -0.18, 0.06), p(right, 0.3, 0.06), p(right, 0.2, -0.16), p(right, -0.08, -0.16)])
            let bolts = CGMutablePath()
            for index in 0..<6 {
                let angle = CGFloat(index) / 6 * 2 * .pi + 0.3
                let ux = cos(angle), uy = sin(angle)
                let nx = -uy, ny = ux
                bolts.move(to: CGPoint(x: c.x + ux * r * 0.15, y: c.y + uy * r * 0.15))
                for (t, side) in [(0.4, 0.12), (0.65, -0.1), (0.9, 0.06)] as [(CGFloat, CGFloat)] {
                    bolts.addLine(to: CGPoint(x: c.x + (ux * t + nx * side) * r, y: c.y + (uy * t + ny * side) * r))
                }
            }
            return [Part(path: base, fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.35),
                    Part(path: circle(c, r), fill: rgb(0x1B1036), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(c, r * 0.86), fill: rgba(0x7B2CBF, 0.4)),
                    Part(path: bolts, fill: nil, stroke: rgb(0xD39BFF), lineWidth: max(0.5, line * 0.4)),
                    Part(path: circle(c, r * 0.17), fill: rgb(0xF5D0FF), stroke: rgb(0xB46CFF), lineWidth: line * 0.3),
                    Part(path: ellipse(p(c, -0.1, -0.13), 0.06 * s, 0.035 * s), fill: rgba(0xFFFFFF, 0.6))]

        case .freezeRay:
            // A white sci-fi blaster, grip in the hand, a fin on top, a cyan
            // barrel with dark rings and a snowflake coming off its muzzle.
            let body = CGRect(x: right.x - 0.12 * s, y: right.y - 0.36 * s, width: 0.52 * s, height: 0.18 * s)
            let grip = poly([CGPoint(x: body.minX + 0.04 * s, y: body.maxY - 0.02 * s),
                             CGPoint(x: body.minX + 0.18 * s, y: body.maxY - 0.02 * s),
                             p(right, 0.08, 0.14), p(right, -0.06, 0.12)])
            let fin = poly([CGPoint(x: body.minX + 0.08 * s, y: body.minY + 0.02 * s),
                            CGPoint(x: body.minX + 0.3 * s, y: body.minY + 0.02 * s),
                            CGPoint(x: body.minX + 0.12 * s, y: body.minY - 0.1 * s)])
            let muzzle = CGPoint(x: body.maxX + 0.2 * s, y: body.midY)
            let barrel = bar(CGPoint(x: body.maxX - 0.02 * s, y: body.midY), muzzle, 0.08 * s)
            let rings = CGMutablePath()
            for dx in [0.05, 0.12] as [CGFloat] {
                rings.addPath(rounded(CGRect(x: body.maxX + dx * s, y: body.midY - 0.065 * s, width: 0.035 * s, height: 0.13 * s),
                                      0.01 * s))
            }
            let flakeCenter = CGPoint(x: muzzle.x + 0.18 * s, y: muzzle.y)
            let flake = CGMutablePath()
            for index in 0..<3 {
                let angle = CGFloat(index) * .pi / 3 + .pi / 2
                let dx = cos(angle) * 0.1 * s, dy = sin(angle) * 0.1 * s
                flake.addPath(stroke(CGPoint(x: flakeCenter.x - dx, y: flakeCenter.y - dy),
                                     CGPoint(x: flakeCenter.x + dx, y: flakeCenter.y + dy)))
            }
            let stripe = CGRect(x: body.minX + 0.06 * s, y: body.midY - 0.02 * s, width: body.width - 0.12 * s, height: 0.04 * s)
            return [Part(path: grip, fill: rgb(0x1D3557), stroke: ink, lineWidth: line * 0.35),
                    Part(path: fin, fill: rgb(0x4CC9F0), stroke: ink, lineWidth: line * 0.3),
                    Part(path: barrel, fill: rgb(0x4CC9F0), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rings, fill: rgb(0x1D3557)),
                    Part(path: rounded(body, 0.07 * s), fill: rgb(0xE8F1FA), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: stripe, transform: nil), fill: rgb(0x4CC9F0)),
                    Part(path: ellipse(muzzle, 0.045 * s, 0.1 * s), fill: rgb(0xBDE0FE), stroke: ink, lineWidth: line * 0.3),
                    Part(path: flake, fill: nil, stroke: rgb(0x8ECAE6), lineWidth: max(0.5, line * 0.45)),
                    Part(path: circle(flakeCenter, 0.025 * s), fill: rgb(0xFFFFFF))]

        case .laserPointer:
            // A slim black pointer with a silver tip and a red button, its
            // thin beam reaching out to a glowing red dot.
            let tip = p(right, 0.34, -0.2)
            let dot = p(right, 0.92, -0.52)
            return [Part(path: stroke(tip, dot), fill: nil, stroke: rgba(0xFF1E3C, 0.75), lineWidth: max(0.5, line * 0.4)),
                    Part(path: bar(p(right, -0.12, 0.08), tip, 0.1 * s), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.35),
                    Part(path: bar(p(right, 0.26, -0.15), tip, 0.1 * s), fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(p(right, 0.08, -0.04), 0.03 * s), fill: rgb(0xFF1E3C)),
                    Part(path: circle(dot, 0.11 * s), fill: rgba(0xFF1E3C, 0.3)),
                    Part(path: circle(dot, 0.05 * s), fill: rgb(0xFF1E3C), stroke: ink, lineWidth: line * 0.2),
                    Part(path: circle(dot, 0.018 * s), fill: rgb(0xFFFFFF))]

        case .tuningFork:
            // A silver fork on a short stem held up, its two tines humming
            // with little curved lines either side.
            let b = p(right, 0.06, -0.18)
            let fork = CGMutablePath()
            fork.move(to: p(b, -0.1, -0.56))
            fork.addLine(to: p(b, -0.1, -0.1))
            fork.addQuadCurve(to: p(b, 0.1, -0.1), control: p(b, 0, 0.06))
            fork.addLine(to: p(b, 0.1, -0.56))
            let hum = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                for k in [0.2, 0.3] as [CGFloat] {
                    hum.move(to: p(b, side * k, -0.5))
                    hum.addQuadCurve(to: p(b, side * k, -0.26), control: p(b, side * (k + 0.06), -0.38))
                }
            }
            return [Part(path: bar(p(right, 0, 0.16), b, 0.07 * s), fill: rgb(0xB0B6C2), stroke: ink, lineWidth: line * 0.3),
                    Part(path: fork, fill: nil, stroke: ink, lineWidth: max(1.2, s * 0.1)),
                    Part(path: fork, fill: nil, stroke: rgb(0xD8DCE4), lineWidth: max(0.7, s * 0.06)),
                    Part(path: circle(p(right, 0, 0.16), 0.05 * s), fill: rgb(0x6E7585), stroke: ink, lineWidth: line * 0.25),
                    Part(path: hum, fill: nil, stroke: rgb(0x8ECAE6), lineWidth: max(0.5, line * 0.35))]

        case .pepperShaker:
            // A glass shaker full of black pepper, a silver cap with holes
            // and a pinch of pepper flying off the top.
            let jar = CGRect(x: right.x - 0.14 * s, y: right.y - 0.42 * s, width: 0.28 * s, height: 0.46 * s)
            let pepper = CGRect(x: jar.minX + 0.03 * s, y: jar.minY + 0.16 * s, width: jar.width - 0.06 * s, height: jar.height - 0.2 * s)
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: jar.minX - 0.01 * s, y: jar.minY + 0.04 * s))
            cap.addCurve(to: CGPoint(x: jar.maxX + 0.01 * s, y: jar.minY + 0.04 * s), control1: CGPoint(x: jar.minX, y: jar.minY - 0.2 * s),
                         control2: CGPoint(x: jar.maxX, y: jar.minY - 0.2 * s))
            cap.closeSubpath()
            let collar = CGRect(x: jar.minX - 0.02 * s, y: jar.minY + 0.02 * s, width: jar.width + 0.04 * s, height: 0.06 * s)
            let holes = CGMutablePath()
            for (dx, dy) in [(-0.06, -0.02), (0.0, -0.07), (0.06, -0.02)] as [(CGFloat, CGFloat)] {
                holes.addPath(circle(CGPoint(x: jar.midX + dx * s, y: jar.minY + dy * s), 0.02 * s))
            }
            let specks = CGMutablePath()
            for (dx, dy) in [(-0.05, 0.24), (0.04, 0.3), (-0.02, 0.36), (0.06, 0.4)] as [(CGFloat, CGFloat)] {
                specks.addPath(circle(CGPoint(x: jar.midX + dx * s, y: jar.minY + dy * s), 0.015 * s))
            }
            let pinch = CGMutablePath()
            for (dx, dy) in [(-0.04, -0.22), (0.05, -0.28), (0.0, -0.36), (0.1, -0.2)] as [(CGFloat, CGFloat)] {
                pinch.addPath(circle(CGPoint(x: jar.midX + dx * s, y: jar.minY + dy * s), 0.022 * s))
            }
            return [Part(path: rounded(jar, 0.08 * s), fill: rgb(0xF1F3F5), stroke: ink, lineWidth: line * 0.45),
                    Part(path: rounded(pepper, 0.06 * s), fill: rgb(0x2F2F2F)),
                    Part(path: specks, fill: rgb(0x9C9C9C)),
                    Part(path: cap, fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rounded(collar, 0.02 * s), fill: rgb(0x9AA0A6), stroke: ink, lineWidth: line * 0.3),
                    Part(path: holes, fill: ink),
                    Part(path: pinch, fill: rgb(0x3A3A3A))]

        case .squeakyHammer:
            // A toy mallet: a yellow handle and a big red barrel of a head
            // with blue rubber ends, and a squeak coming off it.
            let head = p(right, 0.16, -0.62)
            let barrel = CGRect(x: head.x - 0.26 * s, y: head.y - 0.13 * s, width: 0.52 * s, height: 0.26 * s)
            let shine = CGRect(x: barrel.minX + 0.08 * s, y: barrel.minY + 0.04 * s, width: barrel.width - 0.16 * s, height: 0.04 * s)
            let squeak = CGMutablePath()
            squeak.addPath(stroke(CGPoint(x: barrel.maxX + 0.04 * s, y: barrel.minY - 0.02 * s),
                                  CGPoint(x: barrel.maxX + 0.12 * s, y: barrel.minY - 0.1 * s)))
            squeak.addPath(stroke(CGPoint(x: barrel.maxX + 0.07 * s, y: barrel.minY + 0.06 * s),
                                  CGPoint(x: barrel.maxX + 0.17 * s, y: barrel.minY + 0.02 * s)))
            return [Part(path: bar(p(right, 0, 0.16), p(head, 0, 0.1), 0.08 * s), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(barrel, 0.06 * s), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.45),
                    Part(path: ellipse(CGPoint(x: barrel.minX, y: barrel.midY), 0.05 * s, 0.13 * s), fill: rgb(0x3A86FF), stroke: ink,
                         lineWidth: line * 0.35),
                    Part(path: ellipse(CGPoint(x: barrel.maxX, y: barrel.midY), 0.05 * s, 0.13 * s), fill: rgb(0x3A86FF), stroke: ink,
                         lineWidth: line * 0.35),
                    Part(path: rounded(shine, 0.02 * s), fill: rgba(0xFFFFFF, 0.55)),
                    Part(path: squeak, fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.35))]

        case .popcornBucket:
            // A striped red and white bucket heaped with popcorn, one
            // kernel jumping out of it.
            let rim = p(right, 0.08, -0.26)
            let topHalf: CGFloat = 0.25 * s, bottomHalf: CGFloat = 0.17 * s, depth: CGFloat = 0.42 * s
            /// A point on the bucket, `t` across from -1 to 1 and `v` down
            /// from 0 at the rim to 1 at the bottom.
            func edge(_ t: CGFloat, _ v: CGFloat) -> CGPoint {
                let half = topHalf + (bottomHalf - topHalf) * v
                return CGPoint(x: rim.x + t * half, y: rim.y + v * depth)
            }
            let bucket = poly([edge(-1, 0), edge(1, 0), edge(1, 1), edge(-1, 1)])
            let stripes = CGMutablePath()
            for k in [0, 2, 4] {
                let t0 = -1 + CGFloat(k) * 0.4, t1 = t0 + 0.4
                stripes.addPath(poly([edge(t0, 0), edge(t1, 0), edge(t1, 1), edge(t0, 1)]))
            }
            let kernels = CGMutablePath()
            let butter = CGMutablePath()
            for (dx, dy) in [(-0.18, -0.03), (-0.08, -0.1), (0.04, -0.12), (0.15, -0.06), (0.22, -0.01), (-0.02, -0.2), (0.1, -0.22),
                             (-0.13, -0.15)] as [(CGFloat, CGFloat)] {
                kernels.addPath(circle(p(rim, dx, dy), 0.075 * s))
                butter.addPath(circle(p(rim, dx + 0.025, dy + 0.02), 0.022 * s))
            }
            let jumper = p(rim, 0.36, -0.4)
            return [Part(path: kernels, fill: rgb(0xFFF4D6), stroke: ink, lineWidth: line * 0.25),
                    Part(path: butter, fill: rgb(0xFFD23F)),
                    Part(path: bucket, fill: rgb(0xFAFAFA)),
                    Part(path: stripes, fill: rgb(0xE63946)),
                    Part(path: bucket, fill: nil, stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(jumper, 0.06 * s), fill: rgb(0xFFF4D6), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(p(jumper, 0.02, 0.015), 0.02 * s), fill: rgb(0xFFD23F))]

        case .mysteryEgg:
            // A big speckled egg held up, pale cream with purple spots and
            // a fine crack starting across it.
            let c = p(right, 0.06, -0.3)
            let rx: CGFloat = 0.2 * s, ry: CGFloat = 0.27 * s
            let egg = CGMutablePath()
            egg.move(to: CGPoint(x: c.x, y: c.y - ry))
            egg.addCurve(to: CGPoint(x: c.x + rx, y: c.y + ry * 0.2), control1: CGPoint(x: c.x + rx * 0.62, y: c.y - ry),
                         control2: CGPoint(x: c.x + rx, y: c.y - ry * 0.4))
            egg.addCurve(to: CGPoint(x: c.x, y: c.y + ry), control1: CGPoint(x: c.x + rx, y: c.y + ry * 0.72),
                         control2: CGPoint(x: c.x + rx * 0.56, y: c.y + ry))
            egg.addCurve(to: CGPoint(x: c.x - rx, y: c.y + ry * 0.2), control1: CGPoint(x: c.x - rx * 0.56, y: c.y + ry),
                         control2: CGPoint(x: c.x - rx, y: c.y + ry * 0.72))
            egg.addCurve(to: CGPoint(x: c.x, y: c.y - ry), control1: CGPoint(x: c.x - rx, y: c.y - ry * 0.4),
                         control2: CGPoint(x: c.x - rx * 0.62, y: c.y - ry))
            egg.closeSubpath()
            let spots = CGMutablePath()
            for (dx, dy, r) in [(-0.08, -0.1, 0.03), (0.07, -0.02, 0.026), (-0.03, 0.1, 0.035), (0.1, 0.13, 0.02), (0.02, -0.19, 0.02),
                                (-0.12, 0.06, 0.02)] as [(CGFloat, CGFloat, CGFloat)] {
                spots.addPath(circle(p(c, dx, dy), r * s))
            }
            let crack = CGMutablePath()
            crack.move(to: p(c, 0.04, -0.06))
            crack.addLine(to: p(c, 0.09, -0.01))
            crack.addLine(to: p(c, 0.12, -0.05))
            crack.addLine(to: p(c, 0.17, 0.0))
            return [Part(path: egg, fill: rgb(0xFFF3DC), stroke: ink, lineWidth: line * 0.45),
                    Part(path: spots, fill: rgb(0x8E5CC4)),
                    Part(path: crack, fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.3)),
                    Part(path: ellipse(p(c, -0.08, -0.15), 0.045 * s, 0.03 * s), fill: rgba(0xFFFFFF, 0.8))]

        case .seedPacket:
            // A paper seed packet with a crimped top, a picture of a pink
            // flower on the front and two seeds tumbling out of a corner.
            let pack = CGRect(x: right.x - 0.16 * s, y: right.y - 0.52 * s, width: 0.36 * s, height: 0.52 * s)
            let crimp = CGRect(x: pack.minX, y: pack.minY, width: pack.width, height: 0.08 * s)
            let picture = CGRect(x: pack.minX + 0.05 * s, y: pack.minY + 0.12 * s, width: pack.width - 0.1 * s, height: 0.28 * s)
            let label = CGRect(x: pack.minX + 0.06 * s, y: picture.maxY + 0.04 * s, width: pack.width - 0.12 * s, height: 0.03 * s)
            let bloom = CGPoint(x: picture.midX, y: picture.minY + 0.1 * s)
            let seeds = CGMutablePath()
            seeds.addPath(ellipse(CGPoint(x: pack.maxX + 0.07 * s, y: pack.minY + 0.04 * s), 0.025 * s, 0.035 * s))
            seeds.addPath(ellipse(CGPoint(x: pack.maxX + 0.12 * s, y: pack.minY + 0.15 * s), 0.025 * s, 0.035 * s))
            return [Part(path: rounded(pack, 0.03 * s), fill: rgb(0xFFF8E7), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: crimp, transform: nil), fill: rgb(0xE9C46A), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(picture, 0.03 * s), fill: rgb(0xBDE0FE)),
                    Part(path: bar(bloom, CGPoint(x: picture.midX, y: picture.maxY), 0.03 * s), fill: rgb(0x43A047)),
                    Part(path: leaf(CGPoint(x: picture.midX + 0.05 * s, y: picture.maxY - 0.07 * s), 0.05 * s, -0.5), fill: rgb(0x66BB6A)),
                    Part(path: flower(bloom, 0.09 * s), fill: rgb(0xFF5C8A), stroke: ink, lineWidth: line * 0.2),
                    Part(path: circle(bloom, 0.03 * s), fill: rgb(0xFFD23F)),
                    Part(path: CGPath(rect: label, transform: nil), fill: rgb(0x8D5A2B)),
                    Part(path: seeds, fill: rgb(0x8D5A2B), stroke: ink, lineWidth: line * 0.2)]

        case .fireExtinguisher:
            // A red extinguisher with a white label, a black valve and its
            // lever on top, the yellow pin, and a black hose to a nozzle.
            let body = CGRect(x: right.x - 0.13 * s, y: right.y - 0.42 * s, width: 0.26 * s, height: 0.52 * s)
            let valve = CGRect(x: body.midX - 0.06 * s, y: body.minY - 0.1 * s, width: 0.12 * s, height: 0.12 * s)
            let lever = bar(CGPoint(x: body.midX - 0.02 * s, y: valve.minY), CGPoint(x: body.midX - 0.26 * s, y: valve.minY - 0.06 * s),
                            0.045 * s)
            let hoseEnd = CGPoint(x: body.maxX + 0.24 * s, y: body.minY + 0.1 * s)
            let hose = CGMutablePath()
            hose.move(to: CGPoint(x: valve.maxX, y: valve.midY))
            hose.addCurve(to: hoseEnd, control1: CGPoint(x: body.maxX + 0.14 * s, y: valve.minY - 0.04 * s),
                          control2: CGPoint(x: body.maxX + 0.12 * s, y: body.minY + 0.26 * s))
            let nozzle = bar(hoseEnd, CGPoint(x: hoseEnd.x + 0.12 * s, y: hoseEnd.y - 0.05 * s), 0.07 * s)
            let label = CGRect(x: body.minX + 0.02 * s, y: body.midY - 0.06 * s, width: body.width - 0.04 * s, height: 0.12 * s)
            let mark = CGRect(x: body.midX - 0.06 * s, y: body.midY - 0.015 * s, width: 0.12 * s, height: 0.03 * s)
            let shine = bar(CGPoint(x: body.minX + 0.05 * s, y: body.minY + 0.1 * s), CGPoint(x: body.minX + 0.05 * s, y: body.midY - 0.1 * s),
                            0.03 * s)
            return [Part(path: lever, fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.3),
                    Part(path: hose, fill: nil, stroke: ink, lineWidth: max(1, s * 0.07)),
                    Part(path: rounded(body, 0.12 * s), fill: rgb(0xD62828), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: label, transform: nil), fill: rgb(0xF5F5F5)),
                    Part(path: CGPath(rect: mark, transform: nil), fill: rgb(0xD62828)),
                    Part(path: shine, fill: rgba(0xFFFFFF, 0.5)),
                    Part(path: rounded(valve, 0.02 * s), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(CGPoint(x: valve.minX - 0.03 * s, y: valve.midY), 0.035 * s), fill: nil, stroke: rgb(0xFFD23F),
                         lineWidth: max(0.5, line * 0.35)),
                    Part(path: nozzle, fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.25)]

        case .lightningRod:
            // A little rubber cap pulled over the head with a copper band,
            // a metal rod standing up from its crown to a copper ball, and a
            // spark playing round the ball.
            let base = top + w * 0.14
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.42, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.42, y: base), control1: CGPoint(x: cx - w * 0.42, y: top - w * 0.32),
                          control2: CGPoint(x: cx + w * 0.42, y: top - w * 0.32))
            dome.closeSubpath()
            let band = rounded(CGRect(x: cx - w * 0.45, y: base - w * 0.06, width: w * 0.9, height: w * 0.09), w * 0.04)
            let ball = CGPoint(x: cx, y: top - w * 0.62)
            let rod = bar(CGPoint(x: cx, y: top - w * 0.12), ball, w * 0.055)
            let mount = rounded(CGRect(x: cx - w * 0.08, y: top - w * 0.24, width: w * 0.16, height: w * 0.08), w * 0.03)
            let coils = CGMutablePath()
            for dy in [0.34, 0.44] as [CGFloat] {
                coils.addPath(stroke(CGPoint(x: cx - w * 0.06, y: top - w * dy), CGPoint(x: cx + w * 0.06, y: top - w * (dy + 0.03))))
            }
            let spark = CGMutablePath()
            spark.move(to: CGPoint(x: cx + w * 0.12, y: top - w * 0.76))
            spark.addLine(to: CGPoint(x: cx + w * 0.2, y: top - w * 0.66))
            spark.addLine(to: CGPoint(x: cx + w * 0.15, y: top - w * 0.64))
            spark.addLine(to: CGPoint(x: cx + w * 0.24, y: top - w * 0.53))
            return [Part(path: dome, fill: rgb(0x3D5A80), stroke: ink, lineWidth: line * 0.5),
                    Part(path: band, fill: rgb(0xB87333), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rod, fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.3),
                    Part(path: coils, fill: nil, stroke: rgb(0xB87333), lineWidth: max(0.5, line * 0.4)),
                    Part(path: mount, fill: rgb(0x9AA0A6), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(ball, w * 0.085), fill: rgb(0xE0A84F), stroke: ink, lineWidth: line * 0.35),
                    Part(path: circle(CGPoint(x: ball.x - w * 0.03, y: ball.y - w * 0.03), w * 0.025), fill: rgb(0xFFF1C9)),
                    Part(path: spark, fill: nil, stroke: rgb(0xFFD23F), lineWidth: max(0.6, line * 0.5))]

        case .rubberBoots:
            // A yellow rubber boot on each foot, toes turned out, a darker
            // cuff at the top, a black sole and a shine down the shaft.
            let at = f.feet(spread: 0.21)
            let floor = f.floor, fu = f.feetUnit
            let boots = CGMutablePath()
            let cuffs = CGMutablePath()
            let soles = CGMutablePath()
            let shine = CGMutablePath()
            for (x, d) in [(at.left, -1), (at.right, 1)] as [(CGFloat, CGFloat)] {
                boots.addPath(boot(x, d, 0.26))
                cuffs.addPath(CGPath(rect: CGRect(x: min(x - d * fu * 0.12, x + d * fu * 0.07), y: floor - fu * 0.26, width: fu * 0.19,
                                                  height: fu * 0.05), transform: nil))
                soles.addPath(rounded(CGRect(x: min(x - d * fu * 0.12, x + d * fu * 0.19), y: floor - fu * 0.04, width: fu * 0.31,
                                             height: fu * 0.05), fu * 0.02))
                shine.addPath(stroke(CGPoint(x: x - d * fu * 0.06, y: floor - fu * 0.18), CGPoint(x: x - d * fu * 0.06, y: floor - fu * 0.09)))
            }
            return [Part(path: boots, fill: rgb(0xFFC300), stroke: ink, lineWidth: line * 0.5),
                    Part(path: cuffs, fill: rgb(0xE0A100), stroke: ink, lineWidth: line * 0.3),
                    Part(path: shine, fill: nil, stroke: rgba(0xFFFFFF, 0.7), lineWidth: max(0.5, line * 0.4)),
                    Part(path: soles, fill: rgb(0x3A3A46), stroke: ink, lineWidth: line * 0.25)]

        case .pocketMirror:
            // A gold compact held open: the case below with a pink gem, the
            // lid above with its round glass catching a glint and a sparkle.
            let base = p(right, 0.06, -0.06)
            let lid = p(right, 0.06, -0.48)
            let hinge = CGRect(x: base.x - 0.06 * s, y: base.y - 0.27 * s, width: 0.12 * s, height: 0.06 * s)
            let glints = CGMutablePath()
            glints.addPath(stroke(p(lid, -0.09, 0.0), p(lid, -0.01, -0.09)))
            glints.addPath(stroke(p(lid, -0.06, 0.06), p(lid, 0.05, -0.06)))
            return [Part(path: rounded(hinge, 0.02 * s), fill: rgb(0xB8862A), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(base, 0.17 * s), fill: rgb(0xF2C14E), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(base, 0.06 * s), fill: rgb(0xFF6FAE), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(lid, 0.2 * s), fill: rgb(0xFF6FAE), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(lid, 0.15 * s), fill: rgb(0xCFE8FF), stroke: ink, lineWidth: line * 0.25),
                    Part(path: glints, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: max(0.5, line * 0.4)),
                    Part(path: star(p(lid, 0.25, -0.18), 0.08 * s, 4, inner: 0.3), fill: rgb(0xFFF3B0), stroke: ink, lineWidth: line * 0.2)]

        case .windChime:
            // A crooked stick held up with a wind chime hanging from its
            // end: a wooden disc, four silver tubes, the clapper and a
            // little blue sail to catch the breeze.
            let tip = p(right, 0.44, -0.86)
            let crook = CGMutablePath()
            crook.move(to: p(right, -0.02, 0.16))
            crook.addQuadCurve(to: tip, control: p(right, 0.06, -0.96))
            let disc = p(tip, 0, 0.18)
            let strings = CGMutablePath()
            strings.addPath(stroke(tip, p(disc, -0.15, 0)))
            strings.addPath(stroke(tip, p(disc, 0.15, 0)))
            strings.addPath(stroke(disc, p(disc, 0, 0.46)))
            let tubes = CGMutablePath()
            for (dx, length) in [(-0.12, 0.3), (-0.04, 0.4), (0.04, 0.36), (0.12, 0.26)] as [(CGFloat, CGFloat)] {
                tubes.addPath(rounded(CGRect(x: disc.x + (dx - 0.025) * s, y: disc.y + 0.04 * s, width: 0.05 * s, height: length * s),
                                      0.02 * s))
            }
            let sail = CGRect(x: disc.x - 0.05 * s, y: disc.y + 0.46 * s, width: 0.1 * s, height: 0.14 * s)
            return [Part(path: crook, fill: nil, stroke: ink, lineWidth: max(1, s * 0.07)),
                    Part(path: crook, fill: nil, stroke: rgb(0x8D5A2B), lineWidth: max(0.6, s * 0.04)),
                    Part(path: strings, fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.25)),
                    Part(path: tubes, fill: rgb(0xD8DCE4), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(p(disc, 0, 0.26), 0.04 * s), fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.25),
                    Part(path: rounded(sail, 0.02 * s), fill: rgb(0x3A86FF), stroke: ink, lineWidth: line * 0.25),
                    Part(path: ellipse(disc, 0.17 * s, 0.045 * s), fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.35)]

        case .fishBowl:
            // A round glass bowl with its rim, blue water in it and an
            // orange goldfish blowing two bubbles.
            let c = p(right, 0.08, -0.28)
            let r: CGFloat = 0.28 * s
            let water = CGMutablePath()
            water.addArc(center: c, radius: r * 0.9, startAngle: -0.3, endAngle: .pi + 0.3, clockwise: false)
            water.closeSubpath()
            let fish = p(c, -0.02, 0.06)
            let tail = poly([p(fish, 0.08, 0), p(fish, 0.18, -0.07), p(fish, 0.18, 0.07)])
            let bubbles = CGMutablePath()
            bubbles.addPath(circle(p(fish, -0.13, -0.1), 0.025 * s))
            bubbles.addPath(circle(p(fish, -0.17, -0.19), 0.035 * s))
            let glint = CGMutablePath()
            glint.addArc(center: c, radius: r * 0.78, startAngle: .pi * 1.1, endAngle: .pi * 1.35, clockwise: false)
            return [Part(path: circle(c, r), fill: rgba(0xDDF3FF, 0.35), stroke: ink, lineWidth: line * 0.45),
                    Part(path: water, fill: rgba(0x4CC9F0, 0.75)),
                    Part(path: tail, fill: rgb(0xF77F00), stroke: ink, lineWidth: line * 0.25),
                    Part(path: ellipse(fish, 0.1 * s, 0.065 * s), fill: rgb(0xFF9F1C), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(p(fish, -0.05, -0.015), 0.016 * s), fill: ink),
                    Part(path: bubbles, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: max(0.4, line * 0.3)),
                    Part(path: glint, fill: nil, stroke: rgba(0xFFFFFF, 0.8), lineWidth: max(0.6, line * 0.5)),
                    Part(path: ellipse(p(c, 0, -0.24), 0.15 * s, 0.04 * s), fill: rgb(0xDDF3FF), stroke: ink, lineWidth: line * 0.35)]

        case .hotCocoa:
            // A red mug of cocoa with marshmallows bobbing on top and two
            // curls of steam rising off it.
            let mug = CGRect(x: right.x - 0.16 * s, y: right.y - 0.36 * s, width: 0.34 * s, height: 0.36 * s)
            let handle = ellipse(CGPoint(x: mug.maxX, y: mug.midY), 0.1 * s, 0.11 * s)
            let steam = CGMutablePath()
            for dx in [-0.06, 0.06] as [CGFloat] {
                steam.move(to: CGPoint(x: mug.midX + dx * s, y: mug.minY - 0.12 * s))
                steam.addCurve(to: CGPoint(x: mug.midX + dx * s, y: mug.minY - 0.42 * s),
                               control1: CGPoint(x: mug.midX + (dx + 0.08) * s, y: mug.minY - 0.2 * s),
                               control2: CGPoint(x: mug.midX + (dx - 0.1) * s, y: mug.minY - 0.32 * s))
            }
            let rim = CGPoint(x: mug.midX, y: mug.minY + 0.03 * s)
            let mallows = CGMutablePath()
            mallows.addPath(rounded(CGRect(x: mug.midX - 0.12 * s, y: mug.minY - 0.04 * s, width: 0.09 * s, height: 0.08 * s), 0.02 * s))
            mallows.addPath(rounded(CGRect(x: mug.midX + 0.02 * s, y: mug.minY - 0.05 * s, width: 0.09 * s, height: 0.08 * s), 0.02 * s))
            return [Part(path: steam, fill: nil, stroke: rgba(0xFFFFFF, 0.75), lineWidth: max(0.5, line * 0.45)),
                    Part(path: handle, fill: nil, stroke: ink, lineWidth: max(1.2, s * 0.1)),
                    Part(path: handle, fill: nil, stroke: rgb(0xD62839), lineWidth: max(0.7, s * 0.06)),
                    Part(path: rounded(mug, 0.06 * s), fill: rgb(0xD62839), stroke: ink, lineWidth: line * 0.45),
                    Part(path: ellipse(rim, mug.width / 2, 0.06 * s), fill: rgb(0xB51F2E), stroke: ink, lineWidth: line * 0.35),
                    Part(path: ellipse(rim, mug.width / 2 - 0.03 * s, 0.04 * s), fill: rgb(0x6B3E26)),
                    Part(path: mallows, fill: rgb(0xFFFFFF), stroke: ink, lineWidth: line * 0.25),
                    Part(path: circle(CGPoint(x: mug.midX - 0.01 * s, y: mug.minY), 0.035 * s), fill: rgb(0xFFC2D4), stroke: ink,
                         lineWidth: line * 0.2)]

        case .iceSkates:
            // A white skating boot on each foot, blue laces crossed down the
            // front, and a silver blade under each, curling up at the toe.
            let at = f.feet(spread: 0.21)
            let floor = f.floor, fu = f.feetUnit
            let boots = CGMutablePath()
            let laces = CGMutablePath()
            let posts = CGMutablePath()
            let blades = CGMutablePath()
            for (x, d) in [(at.left, -1), (at.right, 1)] as [(CGFloat, CGFloat)] {
                boots.addPath(boot(x, d, 0.24))
                for k in [0, 1] as [CGFloat] {
                    let y = floor - fu * (0.2 - k * 0.06)
                    laces.addPath(stroke(CGPoint(x: x - fu * 0.03, y: y), CGPoint(x: x + fu * 0.04, y: y + fu * 0.03)))
                    laces.addPath(stroke(CGPoint(x: x + fu * 0.04, y: y), CGPoint(x: x - fu * 0.03, y: y + fu * 0.03)))
                }
                for dx in [-0.07, 0.12] as [CGFloat] {
                    posts.addPath(bar(CGPoint(x: x + d * fu * dx, y: floor - fu * 0.01), CGPoint(x: x + d * fu * dx, y: floor + fu * 0.07),
                                      fu * 0.035))
                }
                blades.move(to: CGPoint(x: x - d * fu * 0.14, y: floor + fu * 0.07))
                blades.addLine(to: CGPoint(x: x + d * fu * 0.18, y: floor + fu * 0.07))
                blades.addQuadCurve(to: CGPoint(x: x + d * fu * 0.22, y: floor + fu * 0.01),
                                    control: CGPoint(x: x + d * fu * 0.25, y: floor + fu * 0.07))
            }
            return [Part(path: posts, fill: rgb(0x9AA0A6), stroke: ink, lineWidth: line * 0.2),
                    Part(path: blades, fill: nil, stroke: ink, lineWidth: max(1, fu * 0.045)),
                    Part(path: blades, fill: nil, stroke: rgb(0xD8DCE4), lineWidth: max(0.6, fu * 0.025)),
                    Part(path: boots, fill: rgb(0xF7F4EE), stroke: ink, lineWidth: line * 0.5),
                    Part(path: laces, fill: nil, stroke: rgb(0x3A86FF), lineWidth: max(0.5, line * 0.4))]

        case .gasMask:
            // A rubber gas mask over the face: round goggles over the eyes,
            // a snout down to a round filter with its grille, and the straps
            // running back to the sides of the head.
            let gap = abs(f.rightEye.x - f.leftEye.x)
            let r: CGFloat = max(gap * 0.36, f.size * 0.06)
            let eyeY = (f.leftEye.y + f.rightEye.y) / 2
            let midX = (f.leftEye.x + f.rightEye.x) / 2
            let minX = min(f.leftEye.x, f.rightEye.x), maxX = max(f.leftEye.x, f.rightEye.x)
            let face = rounded(CGRect(x: minX - r * 1.5, y: eyeY - r * 1.35, width: maxX - minX + r * 3, height: r * 2.9), r * 1.2)
            let straps = CGMutablePath()
            straps.addPath(stroke(CGPoint(x: f.outline.minX + w * 0.02, y: eyeY - r * 0.2), CGPoint(x: minX - r * 1.4, y: eyeY - r * 0.2)))
            straps.addPath(stroke(CGPoint(x: maxX + r * 1.4, y: eyeY - r * 0.2), CGPoint(x: f.outline.maxX - w * 0.02, y: eyeY - r * 0.2)))
            let snout = poly([CGPoint(x: midX - r * 0.7, y: eyeY + r * 0.6), CGPoint(x: midX + r * 0.7, y: eyeY + r * 0.6),
                              CGPoint(x: midX + r * 0.55, y: eyeY + r * 1.9), CGPoint(x: midX - r * 0.55, y: eyeY + r * 1.9)])
            let filter = CGPoint(x: midX, y: eyeY + r * 2.2)
            let grille = CGMutablePath()
            for dy in [-0.2, 0.2] as [CGFloat] {
                grille.addPath(stroke(CGPoint(x: filter.x - r * 0.38, y: filter.y + r * dy),
                                      CGPoint(x: filter.x + r * 0.38, y: filter.y + r * dy)))
            }
            var parts = [Part(path: straps, fill: nil, stroke: rgb(0x2B2B33), lineWidth: line * 0.8),
                         Part(path: face, fill: rgb(0x4A5A48), stroke: ink, lineWidth: line * 0.45),
                         Part(path: snout, fill: rgb(0x3B4A3A), stroke: ink, lineWidth: line * 0.35),
                         Part(path: circle(filter, r * 0.85), fill: rgb(0x2B2B33), stroke: ink, lineWidth: line * 0.4),
                         Part(path: circle(filter, r * 0.55), fill: rgb(0x6C757D)),
                         Part(path: grille, fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3))]
            for eye in [f.leftEye, f.rightEye] {
                parts.append(Part(path: circle(eye, r * 1.1), fill: rgb(0x9AA0A6), stroke: ink, lineWidth: line * 0.4))
                parts.append(Part(path: circle(eye, r * 0.82), fill: rgba(0xA8DADC, 0.75)))
                parts.append(Part(path: ellipse(CGPoint(x: eye.x - r * 0.28, y: eye.y - r * 0.3), r * 0.22, r * 0.14),
                                  fill: rgba(0xFFFFFF, 0.8)))
            }
            return parts

        case .pinata:
            // A striped pink donkey piñata up on a stick: body, four legs,
            // a long neck and head with tall ears, and a little tail.
            let b = p(right, 0.12, -0.46)
            let body = CGRect(x: b.x - 0.24 * s, y: b.y - 0.1 * s, width: 0.44 * s, height: 0.18 * s)
            let legs = CGMutablePath()
            for dx in [-0.2, -0.1, 0.04, 0.12] as [CGFloat] {
                legs.addPath(rounded(CGRect(x: b.x + dx * s, y: b.y + 0.04 * s, width: 0.06 * s, height: 0.16 * s), 0.015 * s))
            }
            let ears = CGMutablePath()
            for dx in [0.09, 0.16] as [CGFloat] {
                ears.addPath(rounded(CGRect(x: b.x + dx * s, y: b.y - 0.52 * s, width: 0.05 * s, height: 0.16 * s), 0.02 * s))
            }
            let neck = CGRect(x: b.x + 0.08 * s, y: b.y - 0.3 * s, width: 0.11 * s, height: 0.24 * s)
            let head = CGRect(x: b.x + 0.06 * s, y: b.y - 0.4 * s, width: 0.28 * s, height: 0.14 * s)
            let bands = CGMutablePath()
            bands.addPath(CGPath(rect: CGRect(x: body.minX + 0.01 * s, y: b.y - 0.045 * s, width: body.width - 0.02 * s, height: 0.045 * s),
                                 transform: nil))
            bands.addPath(CGPath(rect: CGRect(x: neck.minX, y: b.y - 0.22 * s, width: neck.width, height: 0.05 * s), transform: nil))
            let blueBand = CGRect(x: body.minX + 0.01 * s, y: b.y + 0.02 * s, width: body.width - 0.02 * s, height: 0.035 * s)
            let tail = bar(CGPoint(x: body.minX, y: b.y - 0.06 * s), CGPoint(x: body.minX - 0.1 * s, y: b.y + 0.06 * s), 0.04 * s)
            return [Part(path: bar(p(right, 0, 0.16), p(b, 0, 0.08), 0.05 * s), fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.25),
                    Part(path: tail, fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.2),
                    Part(path: legs, fill: rgb(0xFF5CA8), stroke: ink, lineWidth: line * 0.3),
                    Part(path: ears, fill: rgb(0xFF5CA8), stroke: ink, lineWidth: line * 0.3),
                    Part(path: CGPath(rect: neck, transform: nil), fill: rgb(0xFF5CA8), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(body, 0.04 * s), fill: rgb(0xFF5CA8), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rounded(head, 0.05 * s), fill: rgb(0xFF5CA8), stroke: ink, lineWidth: line * 0.4),
                    Part(path: bands, fill: rgb(0xFFD23F)),
                    Part(path: CGPath(rect: blueBand, transform: nil), fill: rgb(0x3A86FF)),
                    Part(path: circle(p(b, 0.25, -0.35), 0.022 * s), fill: ink)]

        case .bubblingFlask:
            // A glass Erlenmeyer flask of bright green potion, bubbles
            // inside and more rising out of its mouth.
            let fb = p(right, 0.04, 0.08)
            let glass = poly([p(fb, -0.07, -0.6), p(fb, 0.07, -0.6), p(fb, 0.07, -0.36), p(fb, 0.26, -0.04), p(fb, 0.22, 0),
                              p(fb, -0.22, 0), p(fb, -0.26, -0.04), p(fb, -0.07, -0.36)])
            let potion = poly([p(fb, -0.133, -0.22), p(fb, 0.133, -0.22), p(fb, 0.235, -0.05), p(fb, 0.2, -0.02), p(fb, -0.2, -0.02),
                               p(fb, -0.235, -0.05)])
            let inside = CGMutablePath()
            for (dx, dy, r) in [(-0.08, -0.1, 0.03), (0.06, -0.15, 0.025), (0.11, -0.06, 0.02)] as [(CGFloat, CGFloat, CGFloat)] {
                inside.addPath(circle(p(fb, dx, dy), r * s))
            }
            let rising = CGMutablePath()
            for (dx, dy, r) in [(0.02, -0.74, 0.045), (-0.06, -0.86, 0.035), (0.08, -0.94, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
                rising.addPath(circle(p(fb, dx, dy), r * s))
            }
            let lip = CGRect(x: fb.x - 0.1 * s, y: fb.y - 0.64 * s, width: 0.2 * s, height: 0.06 * s)
            return [Part(path: glass, fill: rgba(0xE8F4FA, 0.55), stroke: ink, lineWidth: line * 0.45),
                    Part(path: potion, fill: rgb(0x57CC04)),
                    Part(path: inside, fill: rgb(0xB8F28B)),
                    Part(path: glass, fill: nil, stroke: ink, lineWidth: line * 0.45),
                    Part(path: rounded(lip, 0.02 * s), fill: rgb(0xE8F4FA), stroke: ink, lineWidth: line * 0.35),
                    Part(path: stroke(p(fb, -0.03, -0.56), p(fb, -0.03, -0.4)), fill: nil, stroke: rgba(0xFFFFFF, 0.85),
                         lineWidth: max(0.5, line * 0.4)),
                    Part(path: rising, fill: rgba(0xB8F28B, 0.85), stroke: ink, lineWidth: line * 0.2)]

        case .jackInTheBox:
            // A red box with a yellow star, its blue lid flung open, a
            // clown's head on a spring popped out of it in a purple jester's
            // hat, and the crank on the side.
            let box = CGRect(x: right.x - 0.18 * s, y: right.y - 0.3 * s, width: 0.36 * s, height: 0.36 * s)
            let springTop = box.minY - 0.2 * s
            let spring = CGMutablePath()
            spring.move(to: CGPoint(x: box.midX, y: box.minY))
            for k in 1...6 {
                let y = box.minY - CGFloat(k) / 6 * 0.2 * s
                let swing: CGFloat = k == 6 ? 0 : (k.isMultiple(of: 2) ? -0.06 : 0.06)
                spring.addLine(to: CGPoint(x: box.midX + swing * s, y: y))
            }
            let hc = CGPoint(x: box.midX, y: springTop - 0.11 * s)
            let hatTip = CGPoint(x: hc.x + 0.1 * s, y: hc.y - 0.34 * s)
            let hat = poly([CGPoint(x: hc.x - 0.12 * s, y: hc.y - 0.06 * s), CGPoint(x: hc.x + 0.12 * s, y: hc.y - 0.06 * s), hatTip])
            let eyes = CGMutablePath()
            eyes.addPath(circle(CGPoint(x: hc.x - 0.045 * s, y: hc.y - 0.015 * s), 0.018 * s))
            eyes.addPath(circle(CGPoint(x: hc.x + 0.045 * s, y: hc.y - 0.015 * s), 0.018 * s))
            let smile = CGMutablePath()
            smile.move(to: CGPoint(x: hc.x - 0.06 * s, y: hc.y + 0.055 * s))
            smile.addQuadCurve(to: CGPoint(x: hc.x + 0.06 * s, y: hc.y + 0.055 * s), control: CGPoint(x: hc.x, y: hc.y + 0.11 * s))
            let lid = bar(CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX - 0.12 * s, y: box.minY - 0.34 * s), 0.05 * s)
            let crankBend = CGPoint(x: box.maxX + 0.1 * s, y: box.midY)
            let crankEnd = CGPoint(x: crankBend.x, y: box.midY + 0.12 * s)
            return [Part(path: lid, fill: rgb(0x3A86FF), stroke: ink, lineWidth: line * 0.3),
                    Part(path: spring, fill: nil, stroke: ink, lineWidth: max(1, s * 0.06)),
                    Part(path: spring, fill: nil, stroke: rgb(0xD8DCE4), lineWidth: max(0.6, s * 0.035)),
                    Part(path: circle(hc, 0.12 * s), fill: rgb(0xFFF1E6), stroke: ink, lineWidth: line * 0.4),
                    Part(path: hat, fill: rgb(0x7B2CBF), stroke: ink, lineWidth: line * 0.35),
                    Part(path: circle(hatTip, 0.04 * s), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.25),
                    Part(path: eyes, fill: ink),
                    Part(path: circle(CGPoint(x: hc.x, y: hc.y + 0.02 * s), 0.035 * s), fill: rgb(0xE63946)),
                    Part(path: smile, fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3)),
                    Part(path: rounded(box, 0.03 * s), fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.45),
                    Part(path: star(CGPoint(x: box.midX, y: box.midY), 0.11 * s, 5), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.25),
                    Part(path: bar(CGPoint(x: box.maxX, y: box.midY), crankBend, 0.04 * s), fill: rgb(0xC0C4CC), stroke: ink,
                         lineWidth: line * 0.2),
                    Part(path: bar(crankBend, crankEnd, 0.04 * s), fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.2),
                    Part(path: circle(crankEnd, 0.04 * s), fill: rgb(0xB07A45), stroke: ink, lineWidth: line * 0.25)]

        default:
            return []
        }
    }
}
