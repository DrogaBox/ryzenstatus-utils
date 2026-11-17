// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The twenty-four of mayhem, traced with a few bold paths like the rest of
/// the wardrobe and placed by the figure's anatomy: what is held hangs from
/// the right hand, the garlic goes round the neck, the tap shoes and the
/// trampoline under the feet, and the battery and the raincoat behind the
/// body, peeking out round it. y grows downward, as everywhere in the
/// wearables.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func mayhemParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w: CGFloat = f.width, cx: CGFloat = f.center
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
        /// Slanted warning stripes across `rect`, filled dark over a yellow
        /// band.
        func hazard(_ rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            let h = rect.height
            guard h > 0.0001 else { return path }
            var x = rect.minX - h
            while x < rect.maxX {
                let xs: [CGFloat] = [x, x + h * 0.5, x + h * 1.5, x + h]
                let ys: [CGFloat] = [rect.maxY, rect.maxY, rect.minY, rect.minY]
                path.addPath(poly(zip(xs, ys).map { pair in CGPoint(x: min(max(pair.0, rect.minX), rect.maxX), y: pair.1) }))
                x += h
            }
            return path
        }
        /// A flame `h` tall standing on `c`, its tip up.
        func flame(_ c: CGPoint, _ h: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let tip = CGPoint(x: c.x, y: c.y - h * 0.5)
            path.move(to: tip)
            path.addQuadCurve(to: CGPoint(x: c.x + h * 0.3, y: c.y + h * 0.15), control: CGPoint(x: c.x + h * 0.3, y: c.y - h * 0.15))
            path.addQuadCurve(to: CGPoint(x: c.x - h * 0.3, y: c.y + h * 0.15), control: CGPoint(x: c.x, y: c.y + h * 0.62))
            path.addQuadCurve(to: tip, control: CGPoint(x: c.x - h * 0.3, y: c.y - h * 0.15))
            path.closeSubpath()
            return path
        }
        /// A soft thing made of several pieces, outlined round its whole
        /// silhouette only: every piece in ink a little fatter first, then
        /// every piece in colour over them, so the seams where the pieces
        /// meet do not show.
        func silhouette(_ shapes: [CGPath], _ color: CGColor) -> [Part] {
            let outlines = shapes.map { Part(path: $0, fill: ink, stroke: ink, lineWidth: line * 0.6) }
            let fills = shapes.map { Part(path: $0, fill: color) }
            return outlines + fills
        }
        let glint = rgb(0xFFFFFF).copy(alpha: 0.8) ?? rgb(0xFFFFFF)

        switch accessory {
        case .giantMagnet:
            // A big red horseshoe magnet held by its bend, the two arms up
            // and their silver tips.
            let c = p(right, 0.1, -0.3)
            let r: CGFloat = 0.2 * s
            let armTop = c.y - 0.2 * s
            let shoe = CGMutablePath()
            shoe.move(to: CGPoint(x: c.x - r, y: armTop))
            shoe.addLine(to: CGPoint(x: c.x - r, y: c.y))
            shoe.addCurve(to: CGPoint(x: c.x + r, y: c.y), control1: CGPoint(x: c.x - r, y: c.y + r * 1.33),
                          control2: CGPoint(x: c.x + r, y: c.y + r * 1.33))
            shoe.addLine(to: CGPoint(x: c.x + r, y: armTop))
            var parts = [Part(path: shoe, fill: nil, stroke: ink, lineWidth: max(1.4, s * 0.2)),
                         Part(path: shoe, fill: nil, stroke: rgb(0xE0262D), lineWidth: max(1, s * 0.14))]
            for x in [c.x - r, c.x + r] {
                let tip = CGRect(x: x - 0.1 * s, y: armTop - 0.13 * s, width: 0.2 * s, height: 0.15 * s)
                parts.append(Part(path: rounded(tip, 0.02 * s), fill: rgb(0xD8DCE4), stroke: ink, lineWidth: line * 0.35))
            }
            parts.append(Part(path: ellipse(CGPoint(x: c.x - r * 0.62, y: c.y + r * 0.5), 0.03 * s, 0.06 * s), fill: rgb(0xFF8A8F)))
            return parts

        case .honeyJar:
            // A round amber jar under a red cloth lid, a label with a comb
            // cell on it, a drip down the side and a wooden dipper standing
            // up out of it, honey running off its head.
            let jar = CGRect(x: right.x - 0.18 * s, y: right.y - 0.34 * s, width: 0.4 * s, height: 0.38 * s)
            let head = CGPoint(x: jar.midX + 0.26 * s, y: jar.minY - 0.3 * s)
            let handle = bar(CGPoint(x: jar.midX + 0.02 * s, y: jar.minY + 0.06 * s), head, 0.05 * s)
            let lid = rounded(CGRect(x: jar.minX - 0.03 * s, y: jar.minY - 0.06 * s, width: jar.width + 0.06 * s, height: 0.1 * s),
                              0.03 * s)
            let grooves = CGMutablePath()
            for dy in [-0.04, 0.0, 0.04] as [CGFloat] {
                grooves.addPath(stroke(p(head, -0.065, dy), p(head, 0.065, dy)))
            }
            let drip = CGMutablePath()
            drip.addPath(rounded(CGRect(x: jar.minX + 0.06 * s, y: jar.minY + 0.02 * s, width: 0.07 * s, height: 0.14 * s), 0.03 * s))
            drip.addPath(ellipse(p(head, 0, 0.14), 0.03 * s, 0.045 * s))
            let label = CGPoint(x: jar.midX, y: jar.midY + 0.05 * s)
            let cell = poly((0..<6).map { k -> CGPoint in
                let angle = CGFloat(k) / 6 * 2 * .pi
                return CGPoint(x: label.x + cos(angle) * 0.05 * s, y: label.y + sin(angle) * 0.05 * s)
            })
            return [Part(path: handle, fill: rgb(0xC98A4B), stroke: ink, lineWidth: line * 0.3),
                    Part(path: ellipse(head, 0.08 * s, 0.1 * s), fill: rgb(0xF2A516), stroke: ink, lineWidth: line * 0.35),
                    Part(path: grooves, fill: nil, stroke: rgb(0xB0700A), lineWidth: max(0.4, line * 0.3)),
                    Part(path: rounded(jar, 0.12 * s), fill: rgb(0xF2A516), stroke: ink, lineWidth: line * 0.5),
                    Part(path: drip, fill: rgb(0xD98A00)),
                    Part(path: ellipse(label, 0.12 * s, 0.09 * s), fill: rgb(0xFFF3D6), stroke: ink, lineWidth: line * 0.25),
                    Part(path: cell, fill: rgb(0xF2A516), stroke: rgb(0xB0700A), lineWidth: line * 0.2),
                    Part(path: lid, fill: rgb(0xE85A4F), stroke: ink, lineWidth: line * 0.35),
                    Part(path: ellipse(CGPoint(x: jar.minX + 0.08 * s, y: jar.midY - 0.02 * s), 0.025 * s, 0.06 * s), fill: glint)]

        case .slimeBlaster:
            // A chunky green blaster: a purple grip in the hand, a bubbling
            // tank of slime on top and a flared muzzle with a blob of goo.
            let body = CGRect(x: right.x - 0.14 * s, y: right.y - 0.3 * s, width: 0.56 * s, height: 0.18 * s)
            let grip = poly([CGPoint(x: right.x - 0.1 * s, y: body.maxY - 0.02 * s), CGPoint(x: right.x + 0.05 * s, y: body.maxY - 0.02 * s),
                             CGPoint(x: right.x + 0.03 * s, y: right.y + 0.12 * s), CGPoint(x: right.x - 0.1 * s, y: right.y + 0.1 * s)])
            let muzzle = poly([CGPoint(x: body.maxX - 0.02 * s, y: body.minY + 0.03 * s),
                               CGPoint(x: body.maxX + 0.12 * s, y: body.minY - 0.03 * s),
                               CGPoint(x: body.maxX + 0.12 * s, y: body.maxY + 0.03 * s),
                               CGPoint(x: body.maxX - 0.02 * s, y: body.maxY - 0.03 * s)])
            let tank = CGPoint(x: body.minX + 0.2 * s, y: body.minY - 0.08 * s)
            let goo = CGMutablePath()
            goo.addPath(ellipse(CGPoint(x: body.maxX + 0.19 * s, y: body.midY), 0.06 * s, 0.07 * s))
            goo.addPath(circle(CGPoint(x: body.maxX + 0.15 * s, y: body.maxY + 0.09 * s), 0.03 * s))
            let bubbles = CGMutablePath()
            bubbles.addPath(circle(p(tank, -0.03, -0.03), 0.025 * s))
            bubbles.addPath(circle(p(tank, 0.04, 0.02), 0.018 * s))
            let stripe = CGRect(x: body.minX + 0.06 * s, y: body.midY - 0.02 * s, width: body.width - 0.12 * s, height: 0.04 * s)
            return [Part(path: grip, fill: rgb(0x8E44D9), stroke: ink, lineWidth: line * 0.35),
                    Part(path: circle(tank, 0.1 * s), fill: rgb(0xA6FF4D), stroke: ink, lineWidth: line * 0.35),
                    Part(path: bubbles, fill: rgb(0xE8FFD0)),
                    Part(path: rounded(body, 0.07 * s), fill: rgb(0x46C24A), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: stripe, transform: nil), fill: rgb(0x2E8F35)),
                    Part(path: muzzle, fill: rgb(0x8E44D9), stroke: ink, lineWidth: line * 0.35),
                    Part(path: goo, fill: rgb(0xA6FF4D), stroke: ink, lineWidth: line * 0.25)]

        case .airHorn:
            // A white can with a blue label, a black button on top and a big
            // red horn flaring up out of it, three loud lines over the mouth.
            let can = CGRect(x: right.x - 0.1 * s, y: right.y - 0.3 * s, width: 0.2 * s, height: 0.38 * s)
            let cap = CGRect(x: can.midX - 0.06 * s, y: can.minY - 0.06 * s, width: 0.12 * s, height: 0.07 * s)
            let mouthY = cap.minY - 0.3 * s
            let horn = poly([CGPoint(x: can.midX - 0.04 * s, y: cap.minY + 0.01 * s), CGPoint(x: can.midX + 0.04 * s, y: cap.minY + 0.01 * s),
                             CGPoint(x: can.midX + 0.15 * s, y: mouthY), CGPoint(x: can.midX - 0.15 * s, y: mouthY)])
            let mouth = CGPoint(x: can.midX, y: mouthY)
            let loud = CGMutablePath()
            loud.addPath(stroke(p(mouth, -0.16, -0.08), p(mouth, -0.24, -0.16)))
            loud.addPath(stroke(p(mouth, 0, -0.1), p(mouth, 0, -0.2)))
            loud.addPath(stroke(p(mouth, 0.16, -0.08), p(mouth, 0.24, -0.16)))
            let label = CGRect(x: can.minX, y: can.minY + 0.12 * s, width: can.width, height: 0.14 * s)
            return [Part(path: rounded(can, 0.04 * s), fill: rgb(0xE8EBF0), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: label, transform: nil), fill: rgb(0x2F6FD6)),
                    Part(path: rounded(cap, 0.02 * s), fill: rgb(0x26262E), stroke: ink, lineWidth: line * 0.3),
                    Part(path: horn, fill: rgb(0xE5262D), stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(mouth, 0.15 * s, 0.04 * s), fill: rgb(0xA3141B), stroke: ink, lineWidth: line * 0.35),
                    Part(path: loud, fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.4))]

        case .hypnoSpiral:
            // A white stick and a round white disc with a black spiral wound
            // into its middle.
            let disc = p(right, 0.3, -0.62)
            let r: CGFloat = 0.26 * s
            let swirl = CGMutablePath()
            var angle: CGFloat = 0
            var radius: CGFloat = r * 0.04
            swirl.move(to: CGPoint(x: disc.x + radius, y: disc.y))
            while radius < r * 0.9 {
                angle += 0.3
                radius += r * 0.021
                swirl.addLine(to: CGPoint(x: disc.x + cos(angle) * radius, y: disc.y + sin(angle) * radius))
            }
            return [Part(path: bar(p(right, 0, 0.14), p(disc, -0.06, 0.12), 0.06 * s), fill: rgb(0xF5F5F5), stroke: ink,
                         lineWidth: line * 0.25),
                    Part(path: circle(disc, r), fill: rgb(0xFFFFFF), stroke: ink, lineWidth: line * 0.45),
                    Part(path: swirl, fill: nil, stroke: ink, lineWidth: max(0.6, r * 0.2)),
                    Part(path: circle(disc, r * 0.08), fill: ink)]

        case .tickleFeather:
            // A long pink feather held by its white quill, a lighter vein of
            // barbs down one side.
            let base = p(right, 0.1, -0.1)
            let tip = p(right, 0.52, -0.86)
            let dx = tip.x - base.x, dy = tip.y - base.y
            let length = max(0.001, hypot(dx, dy))
            let nx = -dy / length, ny = dx / length
            let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
            let vane = CGMutablePath()
            vane.move(to: base)
            vane.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx * 0.26 * s, y: mid.y + ny * 0.26 * s))
            vane.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx * 0.22 * s, y: mid.y - ny * 0.22 * s))
            vane.closeSubpath()
            let barbs = CGMutablePath()
            for t in [0.3, 0.5, 0.7] as [CGFloat] {
                let on = CGPoint(x: base.x + dx * t, y: base.y + dy * t)
                let reach: CGFloat = 0.12 * s * (1 - abs(t - 0.5))
                let along: CGFloat = reach * 0.6 / length
                barbs.addPath(stroke(on, CGPoint(x: on.x + nx * reach + dx * along, y: on.y + ny * reach + dy * along)))
            }
            return [Part(path: vane, fill: rgb(0xFF7EB6), stroke: ink, lineWidth: line * 0.4),
                    Part(path: barbs, fill: nil, stroke: rgb(0xFFC4DD), lineWidth: max(0.4, line * 0.3)),
                    Part(path: stroke(p(right, -0.02, 0.14), tip), fill: nil, stroke: rgb(0xF5F1E8), lineWidth: max(0.5, s * 0.035))]

        case .hotSauce:
            // A red bottle with a long neck and a green cap, a cream label
            // with a flame on it.
            let body = CGRect(x: right.x - 0.12 * s, y: right.y - 0.36 * s, width: 0.24 * s, height: 0.42 * s)
            let neck = CGRect(x: right.x - 0.04 * s, y: right.y - 0.54 * s, width: 0.08 * s, height: 0.2 * s)
            let cap = CGRect(x: right.x - 0.055 * s, y: right.y - 0.62 * s, width: 0.11 * s, height: 0.09 * s)
            let label = CGRect(x: right.x - 0.1 * s, y: right.y - 0.26 * s, width: 0.2 * s, height: 0.2 * s)
            let fire = CGPoint(x: right.x, y: label.midY + 0.01 * s)
            return [Part(path: rounded(neck, 0.02 * s), fill: rgb(0xD7261E), stroke: ink, lineWidth: line * 0.35),
                    Part(path: rounded(cap, 0.02 * s), fill: rgb(0x2E9E3E), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(body, 0.08 * s), fill: rgb(0xD7261E), stroke: ink, lineWidth: line * 0.45),
                    Part(path: rounded(label, 0.03 * s), fill: rgb(0xFFF1C9), stroke: ink, lineWidth: line * 0.25),
                    Part(path: flame(fire, 0.17 * s), fill: rgb(0xFF7A00)),
                    Part(path: flame(p(fire, 0, 0.03), 0.09 * s), fill: rgb(0xFFD23F)),
                    Part(path: ellipse(CGPoint(x: body.minX + 0.05 * s, y: body.minY + 0.06 * s), 0.02 * s, 0.035 * s), fill: glint)]

        case .bigRedButton:
            // A big shiny red dome on a yellow base with a black and yellow
            // warning stripe round its foot.
            let base = CGRect(x: right.x - 0.16 * s, y: right.y - 0.18 * s, width: 0.48 * s, height: 0.2 * s)
            let band = CGRect(x: base.minX, y: base.maxY - 0.09 * s, width: base.width, height: 0.06 * s)
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: base.midX - 0.15 * s, y: base.minY))
            dome.addCurve(to: CGPoint(x: base.midX + 0.15 * s, y: base.minY),
                          control1: CGPoint(x: base.midX - 0.15 * s, y: base.minY - 0.2 * s),
                          control2: CGPoint(x: base.midX + 0.15 * s, y: base.minY - 0.2 * s))
            dome.closeSubpath()
            return [Part(path: rounded(base, 0.04 * s), fill: rgb(0xFFC928), stroke: ink, lineWidth: line * 0.45),
                    Part(path: hazard(band), fill: ink),
                    Part(path: ellipse(CGPoint(x: base.midX, y: base.minY), 0.19 * s, 0.06 * s), fill: rgb(0xA3141B), stroke: ink,
                         lineWidth: line * 0.35),
                    Part(path: dome, fill: rgb(0xE5262D), stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(CGPoint(x: base.midX - 0.06 * s, y: base.minY - 0.1 * s), 0.04 * s, 0.025 * s), fill: glint)]

        case .stickyHand:
            // A stretchy magenta hand flung out on its string, five fingers
            // spread to slap and stick.
            let h = p(right, 0.6, -0.52)
            let string = CGMutablePath()
            string.move(to: p(right, 0, 0.04))
            string.addQuadCurve(to: p(h, -0.02, 0.12), control: p(right, 0.42, 0.12))
            var shapes: [CGPath] = [ellipse(h, 0.1 * s, 0.11 * s), bar(p(h, 0, 0.06), p(h, -0.02, 0.13), 0.06 * s)]
            for dx in [-0.075, -0.025, 0.025, 0.075] as [CGFloat] {
                let fingertip = p(h, dx * 1.5, -0.25 + abs(dx) * 0.7)
                shapes.append(bar(p(h, dx, -0.04), fingertip, 0.05 * s))
                shapes.append(circle(fingertip, 0.025 * s))
            }
            let thumb = p(h, -0.2, -0.05)
            shapes.append(bar(p(h, -0.06, 0.02), thumb, 0.05 * s))
            shapes.append(circle(thumb, 0.025 * s))
            var parts = [Part(path: string, fill: nil, stroke: rgb(0xFF7AC8), lineWidth: max(0.6, s * 0.035))]
            parts += silhouette(shapes, rgb(0xE6339F))
            parts.append(Part(path: ellipse(p(h, -0.03, -0.03), 0.035 * s, 0.05 * s), fill: rgb(0xFF8FD0)))
            return parts

        case .fireworkRocket:
            // A red rocket with a yellow band, a blue nose cone and fins, on
            // a long stick in the hand, its fuse curling out at the bottom
            // with a spark at the end.
            let tube = CGRect(x: right.x + 0.06 * s, y: right.y - 0.72 * s, width: 0.18 * s, height: 0.4 * s)
            let nose = poly([CGPoint(x: tube.minX - 0.02 * s, y: tube.minY), CGPoint(x: tube.maxX + 0.02 * s, y: tube.minY),
                             CGPoint(x: tube.midX, y: tube.minY - 0.2 * s)])
            let fins = CGMutablePath()
            fins.addPath(poly([CGPoint(x: tube.minX, y: tube.maxY - 0.1 * s), CGPoint(x: tube.minX - 0.08 * s, y: tube.maxY + 0.04 * s),
                               CGPoint(x: tube.minX, y: tube.maxY)]))
            fins.addPath(poly([CGPoint(x: tube.maxX, y: tube.maxY - 0.1 * s), CGPoint(x: tube.maxX + 0.08 * s, y: tube.maxY + 0.04 * s),
                               CGPoint(x: tube.maxX, y: tube.maxY)]))
            let spark = CGPoint(x: tube.midX + 0.14 * s, y: tube.maxY + 0.14 * s)
            let fuse = CGMutablePath()
            fuse.move(to: CGPoint(x: tube.midX, y: tube.maxY))
            fuse.addQuadCurve(to: spark, control: CGPoint(x: tube.midX + 0.12 * s, y: tube.maxY))
            let rays = CGMutablePath()
            for index in 0..<6 {
                let angle = CGFloat(index) / 6 * 2 * .pi
                rays.addPath(stroke(CGPoint(x: spark.x + cos(angle) * 0.03 * s, y: spark.y + sin(angle) * 0.03 * s),
                                    CGPoint(x: spark.x + cos(angle) * 0.08 * s, y: spark.y + sin(angle) * 0.08 * s)))
            }
            let stick = bar(p(right, 0, 0.16), CGPoint(x: tube.minX + 0.02 * s, y: tube.minY + 0.12 * s), 0.04 * s)
            let band = CGRect(x: tube.minX, y: tube.minY + 0.14 * s, width: tube.width, height: 0.07 * s)
            return [Part(path: stick, fill: rgb(0xC08A4E), stroke: ink, lineWidth: line * 0.25),
                    Part(path: fuse, fill: nil, stroke: ink, lineWidth: max(0.5, line * 0.35)),
                    Part(path: fins, fill: rgb(0x2F6FD6), stroke: ink, lineWidth: line * 0.3),
                    Part(path: rounded(tube, 0.03 * s), fill: rgb(0xE53935), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: band, transform: nil), fill: rgb(0xFFD23F)),
                    Part(path: nose, fill: rgb(0x2F6FD6), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rays, fill: nil, stroke: rgb(0xFFC93C), lineWidth: max(0.4, line * 0.3)),
                    Part(path: circle(spark, 0.03 * s), fill: rgb(0xFF7A00))]

        case .bubbleWrap:
            // A square of pale blue bubble wrap held by a corner, three rows
            // of round bubbles with a glint each, and one already popped.
            let sheet = CGRect(x: right.x - 0.08 * s, y: right.y - 0.5 * s, width: 0.48 * s, height: 0.46 * s)
            let bubbles = CGMutablePath()
            let shines = CGMutablePath()
            let popped = CGMutablePath()
            for i in 0..<3 {
                for j in 0..<3 {
                    let c = CGPoint(x: sheet.minX + (0.08 + CGFloat(i) * 0.16) * s, y: sheet.minY + (0.08 + CGFloat(j) * 0.15) * s)
                    if i == 2 && j == 0 {
                        popped.addPath(stroke(p(c, -0.04, -0.04), p(c, 0.04, 0.04)))
                        popped.addPath(stroke(p(c, 0.04, -0.04), p(c, -0.04, 0.04)))
                        continue
                    }
                    bubbles.addPath(circle(c, 0.06 * s))
                    shines.addPath(circle(p(c, -0.02, -0.02), 0.018 * s))
                }
            }
            return [Part(path: rounded(sheet, 0.03 * s), fill: rgb(0xBFE6FA).copy(alpha: 0.92) ?? rgb(0xBFE6FA), stroke: ink,
                         lineWidth: line * 0.4),
                    Part(path: bubbles, fill: rgb(0xEAF8FF), stroke: rgb(0x5E9CC0), lineWidth: line * 0.3),
                    Part(path: shines, fill: rgb(0xFFFFFF)),
                    Part(path: popped, fill: nil, stroke: rgb(0x5E9CC0), lineWidth: max(0.4, line * 0.3))]

        case .metalDetector:
            // A grey shaft from a black grip down and out to a yellow search
            // coil near the ground, a yellow control box with a red light.
            let coil = p(right, 0.66, 0.34)
            let box = CGRect(x: right.x + 0.1 * s, y: right.y - 0.08 * s, width: 0.16 * s, height: 0.1 * s)
            return [Part(path: bar(p(right, -0.06, -0.12), p(coil, -0.04, -0.02), 0.05 * s), fill: rgb(0x9AA0AE), stroke: ink,
                         lineWidth: line * 0.3),
                    Part(path: bar(p(right, -0.08, -0.13), p(right, 0.08, -0.03), 0.09 * s), fill: rgb(0x26262E), stroke: ink,
                         lineWidth: line * 0.3),
                    Part(path: rounded(box, 0.02 * s), fill: rgb(0xFFC928), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(CGPoint(x: box.midX + 0.03 * s, y: box.midY), 0.025 * s), fill: rgb(0xFF3B30)),
                    Part(path: ellipse(coil, 0.2 * s, 0.07 * s), fill: rgb(0xFFC928), stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(coil, 0.12 * s, 0.035 * s), fill: rgb(0x26262E))]

        case .compass:
            // A round brass compass with a ring to hang it by, a cream face
            // with four ticks and a red and grey needle.
            let c = p(right, 0.08, -0.22)
            let r: CGFloat = 0.2 * s
            let ring = circle(CGPoint(x: c.x, y: c.y - r - 0.04 * s), 0.045 * s)
            let ticks = CGMutablePath()
            for index in 0..<4 {
                let angle = CGFloat(index) * .pi / 2
                ticks.addPath(stroke(CGPoint(x: c.x + cos(angle) * r * 0.58, y: c.y + sin(angle) * r * 0.58),
                                     CGPoint(x: c.x + cos(angle) * r * 0.72, y: c.y + sin(angle) * r * 0.72)))
            }
            let heading: CGFloat = -1.25
            let reach: CGFloat = 0.13 * s, half: CGFloat = 0.035 * s
            let ahead = CGPoint(x: cos(heading) * reach, y: sin(heading) * reach)
            let side = CGPoint(x: -sin(heading) * half, y: cos(heading) * half)
            let flankA = CGPoint(x: c.x + side.x, y: c.y + side.y), flankB = CGPoint(x: c.x - side.x, y: c.y - side.y)
            let north = poly([CGPoint(x: c.x + ahead.x, y: c.y + ahead.y), flankA, flankB])
            let south = poly([CGPoint(x: c.x - ahead.x, y: c.y - ahead.y), flankA, flankB])
            return [Part(path: ring, fill: nil, stroke: ink, lineWidth: max(1, s * 0.05)),
                    Part(path: ring, fill: nil, stroke: rgb(0xD9A43B), lineWidth: max(0.5, s * 0.025)),
                    Part(path: circle(c, r), fill: rgb(0xD9A43B), stroke: ink, lineWidth: line * 0.45),
                    Part(path: circle(c, r * 0.76), fill: rgb(0xF7F3E8), stroke: rgb(0xA87A22), lineWidth: line * 0.25),
                    Part(path: ticks, fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.3)),
                    Part(path: south, fill: rgb(0x9AA0AE), stroke: ink, lineWidth: line * 0.2),
                    Part(path: north, fill: rgb(0xE53935), stroke: ink, lineWidth: line * 0.2),
                    Part(path: circle(c, 0.02 * s), fill: ink)]

        case .batteryPack:
            // A giant AA battery strapped to its back, tilted so the copper
            // top and its plus nub stick out over the left shoulder, a
            // yellow bolt on it. Worn behind the body: a figure with a body
            // of its own carries it from the torso up; one that is a single
            // round shape has it peeking out at the top left.
            let bodied = f.separateBody
            let body = bodied ? f.torso : f.outline
            let length: CGFloat = bodied ? max(body.height * 1.05, w * 0.8) : body.height * 0.9
            let bw: CGFloat = bodied ? max(body.width * 0.4, w * 0.28) : w * 0.34
            let tilt: CGFloat = -0.6
            let reach: CGFloat = body.height * (bodied ? 0.3 : 0.32)
            let center = CGPoint(x: body.midX + sin(tilt) * reach, y: body.midY - cos(tilt) * reach)
            var turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: tilt)
            func turned(_ path: CGPath) -> CGPath { path.copy(using: &turn) ?? path }
            let half = length / 2
            let corner = bw * 0.2
            let shell = rounded(CGRect(x: -bw / 2, y: -half, width: bw, height: length), corner)
            let split = -half + length * 0.32
            let cut = corner * 0.6
            let black = poly([CGPoint(x: -bw / 2, y: split), CGPoint(x: bw / 2, y: split), CGPoint(x: bw / 2, y: half - cut),
                              CGPoint(x: bw / 2 - cut, y: half), CGPoint(x: -bw / 2 + cut, y: half), CGPoint(x: -bw / 2, y: half - cut)])
            let nub = rounded(CGRect(x: -bw * 0.2, y: -half - bw * 0.18, width: bw * 0.4, height: bw * 0.24), bw * 0.06)
            let strap = CGPath(rect: CGRect(x: -bw * 0.62, y: length * 0.12, width: bw * 1.24, height: bw * 0.18), transform: nil)
            let boltY = -half + length * 0.16
            let bolt = poly([CGPoint(x: bw * 0.08, y: boltY - bw * 0.3), CGPoint(x: -bw * 0.2, y: boltY + bw * 0.04),
                             CGPoint(x: -bw * 0.01, y: boltY + bw * 0.04), CGPoint(x: -bw * 0.1, y: boltY + bw * 0.32),
                             CGPoint(x: bw * 0.2, y: boltY - bw * 0.06), CGPoint(x: bw * 0.01, y: boltY - bw * 0.06)])
            return [Part(path: turned(nub), fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.35),
                    Part(path: turned(shell), fill: rgb(0xE8892B)),
                    Part(path: turned(black), fill: rgb(0x2B2B33)),
                    Part(path: turned(strap), fill: rgb(0x6D4C2E), stroke: ink, lineWidth: line * 0.3),
                    Part(path: turned(shell), fill: nil, stroke: ink, lineWidth: line * 0.5),
                    Part(path: turned(bolt), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.3)]

        case .tapShoes:
            // A shiny black shoe on each foot, toes out, a silver buckle, a
            // gleam on the toe and silver taps under toe and heel.
            let at = f.feet(spread: 0.21)
            let floor = f.floor, fu = f.feetUnit, fc = f.feetCenter
            let shoes = CGMutablePath()
            let taps = CGMutablePath()
            let gleams = CGMutablePath()
            let buckles = CGMutablePath()
            for x in [at.left, at.right] {
                let out: CGFloat = x < fc ? -1 : 1
                let shoe = CGRect(x: x - fu * 0.17 + out * fu * 0.03, y: floor - fu * 0.16, width: fu * 0.34, height: fu * 0.15)
                shoes.addPath(rounded(shoe, fu * 0.06))
                let toe = x + out * fu * 0.1, heel = x - out * fu * 0.09
                taps.addPath(rounded(CGRect(x: toe - fu * 0.07, y: floor - fu * 0.02, width: fu * 0.14, height: fu * 0.045), fu * 0.02))
                taps.addPath(rounded(CGRect(x: heel - fu * 0.045, y: floor - fu * 0.02, width: fu * 0.09, height: fu * 0.045), fu * 0.02))
                gleams.addPath(ellipse(CGPoint(x: x + out * fu * 0.08, y: floor - fu * 0.115), fu * 0.045, fu * 0.02))
                buckles.addPath(circle(CGPoint(x: x - out * fu * 0.03, y: floor - fu * 0.13), fu * 0.025))
            }
            return [Part(path: taps, fill: rgb(0xD8DCE4), stroke: ink, lineWidth: line * 0.25),
                    Part(path: shoes, fill: rgb(0x1E1E26), stroke: ink, lineWidth: line * 0.45),
                    Part(path: gleams, fill: glint),
                    Part(path: buckles, fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.2)]

        case .jelly:
            // A red jelly on a white plate, wobbly sides, two ridges down it
            // and a glint.
            let b = p(right, 0.1, -0.02)
            let jelly = CGMutablePath()
            jelly.move(to: p(b, -0.2, 0))
            jelly.addQuadCurve(to: p(b, -0.15, -0.32), control: p(b, -0.26, -0.16))
            jelly.addQuadCurve(to: p(b, 0.15, -0.32), control: p(b, 0, -0.42))
            jelly.addQuadCurve(to: p(b, 0.2, 0), control: p(b, 0.26, -0.16))
            jelly.closeSubpath()
            let ridges = CGMutablePath()
            for dx in [-0.08, 0.08] as [CGFloat] {
                ridges.move(to: p(b, dx * 0.7, -0.3))
                ridges.addQuadCurve(to: p(b, dx, -0.03), control: p(b, dx * 1.5, -0.16))
            }
            return [Part(path: ellipse(p(b, 0, 0.01), 0.3 * s, 0.07 * s), fill: rgb(0xF4F4F8), stroke: ink, lineWidth: line * 0.4),
                    Part(path: jelly, fill: rgb(0xFF4D6D), stroke: ink, lineWidth: line * 0.45),
                    Part(path: ridges, fill: nil, stroke: rgb(0xC42340), lineWidth: max(0.5, line * 0.35)),
                    Part(path: ellipse(p(b, -0.09, -0.22), 0.03 * s, 0.06 * s), fill: glint)]

        case .trampoline:
            // A little round trampoline under its feet: a black mat in a
            // padded blue rim, standing on three short grey legs.
            let fu = f.feetUnit, fc = f.feetCenter, floor = f.floor
            let at = f.feet(spread: 0.18)
            let rx: CGFloat = max(fu * 0.62, abs(at.right - at.left) / 2 + fu * 0.26)
            let ry: CGFloat = rx * 0.2
            let cy = floor + ry * 0.75
            // A figure drawn without anatomy (the island's small sprites) has
            // no room under it, so its legs are stubs there.
            let legLength = f.anatomy == nil ? min(fu * 0.14, f.size * 0.06) : fu * 0.16
            var parts: [Part] = []
            for dx in [-0.78, 0, 0.78] as [CGFloat] {
                let leg = bar(CGPoint(x: fc + dx * rx, y: cy), CGPoint(x: fc + dx * rx * 1.05, y: cy + ry + legLength), fu * 0.06)
                parts.append(Part(path: leg, fill: rgb(0x8E949E), stroke: ink, lineWidth: line * 0.3))
            }
            let rim = ellipse(CGPoint(x: fc, y: cy), rx, ry)
            parts += [Part(path: ellipse(CGPoint(x: fc, y: cy), rx * 0.88, ry * 0.8), fill: rgb(0x26262E)),
                      Part(path: rim, fill: nil, stroke: ink, lineWidth: max(1.2, fu * 0.09)),
                      Part(path: rim, fill: nil, stroke: rgb(0x3A86FF), lineWidth: max(0.8, fu * 0.06))]
            return parts

        case .raincoat:
            // A yellow rain poncho behind the body, flaring past it to a
            // curved hem, and its hood standing up round the back of the
            // head so a yellow rim shows over the top. As with the cape, a
            // figure with a body of its own wears it from the shoulders
            // down; on one that is a single round shape it hangs from under
            // the chin and peeks out at the sides.
            let bodied = f.separateBody
            let torso = bodied ? f.torso : f.outline
            let neck = bodied ? torso.minY + torso.height * 0.02 : max(f.neckY - w * 0.12, torso.minY + torso.height * 0.42)
            let hemY = bodied ? max(f.floor - torso.height * 0.08, neck + w * 0.3) : f.floor + w * 0.02
            let half = bodied ? max(torso.width * 0.44, w * 0.3) : w * 0.36
            let flare: CGFloat = bodied ? 1.7 : 1.4
            let poncho = CGMutablePath()
            poncho.move(to: CGPoint(x: torso.midX - half * 0.7, y: neck))
            poncho.addLine(to: CGPoint(x: torso.midX + half * 0.7, y: neck))
            poncho.addLine(to: CGPoint(x: torso.midX + half * flare, y: hemY))
            poncho.addQuadCurve(to: CGPoint(x: torso.midX - half * flare, y: hemY), control: CGPoint(x: torso.midX, y: hemY + w * 0.08))
            poncho.closeSubpath()
            let folds = CGMutablePath()
            folds.addPath(stroke(CGPoint(x: torso.midX - half * 0.35, y: neck + w * 0.06),
                                 CGPoint(x: torso.midX - half * 0.95, y: hemY - w * 0.02)))
            folds.addPath(stroke(CGPoint(x: torso.midX + half * 0.35, y: neck + w * 0.06),
                                 CGPoint(x: torso.midX + half * 0.95, y: hemY - w * 0.02)))
            let head = f.outline
            let hood = bodied
                ? CGPoint(x: head.midX, y: head.midY - head.height * 0.02)
                : CGPoint(x: head.midX, y: head.minY + head.height * 0.3)
            let hoodX: CGFloat = bodied ? head.width * 0.6 : w * 0.56
            let hoodY: CGFloat = bodied ? head.height * 0.58 : head.height * 0.36
            let seam = CGMutablePath()
            seam.move(to: CGPoint(x: hood.x - hoodX * 0.92, y: hood.y))
            seam.addQuadCurve(to: CGPoint(x: hood.x + hoodX * 0.92, y: hood.y), control: CGPoint(x: hood.x, y: hood.y - hoodY * 1.9))
            return [Part(path: poncho, fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.45),
                    Part(path: folds, fill: nil, stroke: rgb(0xE0A800), lineWidth: max(0.6, line * 0.45)),
                    Part(path: ellipse(hood, hoodX, hoodY), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.45),
                    Part(path: seam, fill: nil, stroke: rgb(0xE0A800), lineWidth: max(0.5, line * 0.4))]

        case .garlicNecklace:
            // A string round its neck with five white garlic bulbs hanging
            // off it, each with a pointed top and faint purple cloves.
            let y = f.neckY + w * 0.03
            let half = w * 0.36
            let sag = w * 0.12
            let r = w * 0.068
            let string = CGMutablePath()
            string.move(to: CGPoint(x: cx - half, y: y))
            string.addQuadCurve(to: CGPoint(x: cx + half, y: y), control: CGPoint(x: cx, y: y + sag))
            let bulbs = CGMutablePath()
            let cloves = CGMutablePath()
            for t in [0.1, 0.3, 0.5, 0.7, 0.9] as [CGFloat] {
                let c = CGPoint(x: cx - half + half * 2 * t, y: y + 2 * (1 - t) * t * sag + r * 0.9)
                let tip = CGPoint(x: c.x, y: c.y - r * 1.25)
                bulbs.move(to: tip)
                bulbs.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y + r * 0.1), control: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.6))
                bulbs.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y + r * 0.1), control: CGPoint(x: c.x, y: c.y + r * 1.75))
                bulbs.addQuadCurve(to: tip, control: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.6))
                bulbs.closeSubpath()
                for side in [-1, 1] as [CGFloat] {
                    cloves.move(to: CGPoint(x: c.x + side * r * 0.1, y: c.y - r * 0.6))
                    cloves.addQuadCurve(to: CGPoint(x: c.x + side * r * 0.4, y: c.y + r * 0.8),
                                        control: CGPoint(x: c.x + side * r * 0.6, y: c.y))
                }
            }
            return [Part(path: string, fill: nil, stroke: rgb(0xC9B48A), lineWidth: max(0.6, line * 0.4)),
                    Part(path: bulbs, fill: rgb(0xF7F2E6), stroke: ink, lineWidth: line * 0.3),
                    Part(path: cloves, fill: nil, stroke: rgb(0xB89BD0), lineWidth: max(0.4, line * 0.25))]

        case .voodooDoll:
            // A burlap doll held by a leg: one blue button eye and one
            // stitched cross, a stitched mouth, and two pins stuck in it.
            let c = p(right, 0.1, -0.32)
            let shapes: [CGPath] = [
                circle(p(c, 0, -0.2), 0.13 * s),
                rounded(CGRect(x: c.x - 0.1 * s, y: c.y - 0.1 * s, width: 0.2 * s, height: 0.26 * s), 0.07 * s),
                bar(p(c, -0.22, -0.05), p(c, 0.22, -0.05), 0.09 * s),
                circle(p(c, -0.22, -0.05), 0.045 * s), circle(p(c, 0.22, -0.05), 0.045 * s),
                bar(p(c, -0.05, 0.12), p(c, -0.1, 0.3), 0.09 * s), bar(p(c, 0.05, 0.12), p(c, 0.1, 0.3), 0.09 * s),
                circle(p(c, -0.1, 0.3), 0.045 * s), circle(p(c, 0.1, 0.3), 0.045 * s),
            ]
            let stitches = CGMutablePath()
            stitches.addPath(stroke(p(c, 0.02, -0.25), p(c, 0.08, -0.19)))
            stitches.addPath(stroke(p(c, 0.08, -0.25), p(c, 0.02, -0.19)))
            stitches.addPath(stroke(p(c, -0.06, -0.13), p(c, 0.06, -0.13)))
            for dx in [-0.04, 0.0, 0.04] as [CGFloat] {
                stitches.addPath(stroke(p(c, dx, -0.155), p(c, dx, -0.105)))
            }
            let pins = CGMutablePath()
            pins.addPath(stroke(p(c, 0.28, -0.38), p(c, 0.08, -0.24)))
            pins.addPath(stroke(p(c, -0.3, 0.08), p(c, -0.04, 0.02)))
            var parts = silhouette(shapes, rgb(0xC9A57A))
            parts += [Part(path: circle(p(c, -0.05, -0.22), 0.035 * s), fill: rgb(0x2F80ED), stroke: ink, lineWidth: line * 0.25),
                      Part(path: stitches, fill: nil, stroke: ink, lineWidth: max(0.4, line * 0.25)),
                      Part(path: pins, fill: nil, stroke: rgb(0xC0C4CC), lineWidth: max(0.5, line * 0.3)),
                      Part(path: circle(p(c, 0.28, -0.38), 0.04 * s), fill: rgb(0xE53935), stroke: ink, lineWidth: line * 0.2),
                      Part(path: circle(p(c, -0.3, 0.08), 0.04 * s), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.2)]
            return parts

        case .cheeseWheel:
            // A round wheel of cheese face on, a wedge cut out of it up to
            // the middle, a golden rind round the edge and a few holes.
            let c = p(right, 0.1, -0.24)
            let r: CGFloat = 0.26 * s
            let gap: CGFloat = -.pi / 4, wedge: CGFloat = 0.42
            /// The wheel at `radius`, the wedge left out.
            func wheel(_ radius: CGFloat) -> CGPath {
                var points = [c]
                let steps = 24
                for k in 0...steps {
                    let angle = gap + wedge + (2 * .pi - 2 * wedge) * CGFloat(k) / CGFloat(steps)
                    points.append(CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius))
                }
                return poly(points)
            }
            let holes = CGMutablePath()
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(-0.12, -0.02, 0.05), (0.04, 0.12, 0.04), (-0.05, -0.14, 0.035),
                                                         (0.13, 0.04, 0.03), (-0.07, 0.1, 0.025)]
            for (dx, dy, hr) in spots {
                holes.addPath(circle(p(c, dx, dy), hr * s))
            }
            return [Part(path: wheel(r), fill: rgb(0xF2A516), stroke: ink, lineWidth: line * 0.45),
                    Part(path: wheel(r * 0.84), fill: rgb(0xFFD54F)),
                    Part(path: holes, fill: rgb(0xE0A800))]

        case .ghostTrap:
            // A grey trap box with a black and yellow hazard stripe, its
            // closed lid on top, a red light, and the cable to its pedal.
            let box = CGRect(x: right.x - 0.16 * s, y: right.y - 0.26 * s, width: 0.46 * s, height: 0.22 * s)
            let lid = CGRect(x: box.minX + 0.02 * s, y: box.minY - 0.07 * s, width: box.width - 0.04 * s, height: 0.08 * s)
            let band = CGRect(x: box.minX, y: box.maxY - 0.09 * s, width: box.width, height: 0.06 * s)
            let pedal = CGPoint(x: box.maxX + 0.12 * s, y: box.maxY + 0.18 * s)
            let cable = CGMutablePath()
            cable.move(to: CGPoint(x: box.maxX, y: box.maxY - 0.05 * s))
            cable.addQuadCurve(to: pedal, control: CGPoint(x: box.maxX + 0.14 * s, y: box.maxY - 0.04 * s))
            let step = CGRect(x: pedal.x - 0.06 * s, y: pedal.y - 0.02 * s, width: 0.12 * s, height: 0.05 * s)
            return [Part(path: cable, fill: nil, stroke: ink, lineWidth: max(0.6, line * 0.4)),
                    Part(path: rounded(step, 0.02 * s), fill: rgb(0x4A4F5A), stroke: ink, lineWidth: line * 0.25),
                    Part(path: rounded(lid, 0.02 * s), fill: rgb(0x6E7585), stroke: ink, lineWidth: line * 0.35),
                    Part(path: stroke(CGPoint(x: lid.midX, y: lid.minY), CGPoint(x: lid.midX, y: lid.maxY)), fill: nil, stroke: ink,
                         lineWidth: max(0.4, line * 0.3)),
                    Part(path: rounded(box, 0.03 * s), fill: rgb(0x4A4F5A), stroke: ink, lineWidth: line * 0.45),
                    Part(path: CGPath(rect: band, transform: nil), fill: rgb(0xFFC928)),
                    Part(path: hazard(band), fill: ink),
                    Part(path: circle(CGPoint(x: box.minX + 0.08 * s, y: box.minY + 0.06 * s), 0.03 * s), fill: rgb(0xFF3B30),
                         stroke: ink, lineWidth: line * 0.2)]

        case .lavaLamp:
            // A lava lamp held by its silver base: purple glass swelling out
            // from the waist, orange blobs floating in it, a silver cap.
            let lx = right.x + 0.08 * s
            let waist = right.y - 0.08 * s
            let crown = waist - 0.44 * s
            let glass = CGMutablePath()
            glass.move(to: CGPoint(x: lx - 0.07 * s, y: waist))
            glass.addQuadCurve(to: CGPoint(x: lx - 0.06 * s, y: crown), control: CGPoint(x: lx - 0.15 * s, y: waist - 0.18 * s))
            glass.addLine(to: CGPoint(x: lx + 0.06 * s, y: crown))
            glass.addQuadCurve(to: CGPoint(x: lx + 0.07 * s, y: waist), control: CGPoint(x: lx + 0.15 * s, y: waist - 0.18 * s))
            glass.closeSubpath()
            let base = poly([CGPoint(x: lx - 0.07 * s, y: waist), CGPoint(x: lx + 0.07 * s, y: waist),
                             CGPoint(x: lx + 0.14 * s, y: waist + 0.14 * s), CGPoint(x: lx - 0.14 * s, y: waist + 0.14 * s)])
            let cap = poly([CGPoint(x: lx - 0.06 * s, y: crown), CGPoint(x: lx + 0.06 * s, y: crown),
                            CGPoint(x: lx + 0.03 * s, y: crown - 0.08 * s), CGPoint(x: lx - 0.03 * s, y: crown - 0.08 * s)])
            let blobs = CGMutablePath()
            blobs.addPath(ellipse(CGPoint(x: lx, y: waist - 0.07 * s), 0.065 * s, 0.045 * s))
            blobs.addPath(ellipse(CGPoint(x: lx + 0.02 * s, y: waist - 0.22 * s), 0.04 * s, 0.05 * s))
            blobs.addPath(circle(CGPoint(x: lx - 0.02 * s, y: waist - 0.34 * s), 0.025 * s))
            return [Part(path: glass, fill: rgb(0x8E3FD1), stroke: ink, lineWidth: line * 0.4),
                    Part(path: blobs, fill: rgb(0xFF8A2B)),
                    Part(path: ellipse(CGPoint(x: lx - 0.06 * s, y: waist - 0.2 * s), 0.015 * s, 0.07 * s), fill: glint),
                    Part(path: base, fill: rgb(0xB8BEC9), stroke: ink, lineWidth: line * 0.4),
                    Part(path: cap, fill: rgb(0xB8BEC9), stroke: ink, lineWidth: line * 0.35)]

        case .icePop:
            // A blue ice pop on a wooden stick, a bite taken out of its top
            // corner, and a frosty stripe down one side.
            let left = right.x - 0.05 * s
            let popWidth: CGFloat = 0.24 * s
            let r = popWidth / 2
            let topY = right.y - 0.48 * s, bottom = right.y - 0.06 * s
            let pop = CGMutablePath()
            pop.move(to: CGPoint(x: left, y: bottom))
            pop.addLine(to: CGPoint(x: left, y: topY + r))
            pop.addQuadCurve(to: CGPoint(x: left + r, y: topY), control: CGPoint(x: left, y: topY))
            pop.addLine(to: CGPoint(x: left + r * 1.05, y: topY))
            pop.addQuadCurve(to: CGPoint(x: left + r * 1.6, y: topY + r * 0.55), control: CGPoint(x: left + r * 1.15, y: topY + r * 0.55))
            pop.addQuadCurve(to: CGPoint(x: left + popWidth, y: topY + r * 1.25),
                             control: CGPoint(x: left + r * 1.65, y: topY + r * 1.15))
            pop.addLine(to: CGPoint(x: left + popWidth, y: bottom))
            pop.closeSubpath()
            let stick = rounded(CGRect(x: left + r - 0.04 * s, y: bottom - 0.06 * s, width: 0.08 * s, height: 0.28 * s), 0.035 * s)
            let frost = rounded(CGRect(x: left + 0.04 * s, y: topY + r * 0.9, width: 0.04 * s, height: bottom - topY - r * 1.2), 0.018 * s)
            return [Part(path: stick, fill: rgb(0xE8C99A), stroke: ink, lineWidth: line * 0.3),
                    Part(path: pop, fill: rgb(0x39B6F0), stroke: ink, lineWidth: line * 0.45),
                    Part(path: frost, fill: rgb(0xA8E4FF))]

        default:
            return []
        }
    }
}
