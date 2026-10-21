// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The vector props of the Wonder Boy side: the arcade markers, drawn from
/// a pixel font as paths, the snacks, the secret door, the coins and the
/// things that fly between the two. Everything is paths and colours, so the
/// shape layers on the desktop and the SwiftUI strip draw the same props,
/// sharp at any scale, without a bitmap.
enum NotchMascotRPGShapes {
    // MARK: Pixel font

    /// Three columns by five rows. `#` is lit.
    private static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".##", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
        "+": ["...", ".#.", "###", ".#.", "..."], "-": ["...", "...", "###", "...", "..."],
        "?": ["##.", "..#", ".#.", "...", ".#."], ".": ["...", "...", "...", "...", ".#."],
        "♥": ["#.#", "###", "###", ".#.", "..."], "♪": [".##", ".#.", ".#.", "##.", "##."],
    ]

    /// The marker's width in cells, with a column between letters and two
    /// for a space.
    static func cells(of text: String) -> Int {
        var width = 0
        for character in text.uppercased() {
            width += character == " " ? 2 : (glyphs[character] != nil ? 4 : 0)
        }
        return max(0, width - 1)
    }

    /// `text` as one path of square pixels, `cell` points on a side, with
    /// its top left corner at the origin and y growing downward.
    static func pixelPath(_ text: String, cell: CGFloat) -> CGPath {
        let path = CGMutablePath()
        var column = 0
        for character in text.uppercased() {
            if character == " " { column += 2; continue }
            guard let rows = glyphs[character] else { continue }
            for (y, row) in rows.enumerated() {
                for (x, mark) in row.enumerated() where mark == "#" {
                    path.addRect(CGRect(x: CGFloat(column + x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            column += 4
        }
        return path
    }

    /// The size `pixelPath` takes.
    static func pixelSize(_ text: String, cell: CGFloat) -> CGSize {
        CGSize(width: CGFloat(cells(of: text)) * cell, height: 5 * cell)
    }

    // MARK: Colours

    static func rgb(_ hex: UInt32) -> CGColor { NotchMascotWearableShapes.rgb(hex) }

    /// The colour an arcade marker is lit in: gold for points, pink for a heart, white otherwise.
    static func markerColor(_ text: String) -> CGColor {
        if text.contains("♥") { return rgb(0xFF5E8A) }
        if text.hasPrefix("+") { return rgb(0xFFD23F) }
        return rgb(0xFFFFFF)
    }

    // MARK: Snacks

    /// A snack in a square of side `s` centred on `c`.
    static func snack(_ snack: NotchMascotSnack, at c: CGPoint, side s: CGFloat) -> [NotchMascotWearablePart] {
        func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: c.x + dx * s, y: c.y + dy * s) }
        let circle = NotchMascotWearableShapes.circle
        let rounded = NotchMascotWearableShapes.rounded
        switch snack {
        case .apple:
            let leaf = CGMutablePath()
            leaf.move(to: p(0.02, -0.34))
            leaf.addQuadCurve(to: p(0.3, -0.5), control: p(0.2, -0.52))
            leaf.addQuadCurve(to: p(0.02, -0.34), control: p(0.22, -0.3))
            return [NotchMascotWearablePart(path: circle(p(0, 0.06), s * 0.36), fill: rgb(0xE5384F)),
                    NotchMascotWearablePart(path: leaf, fill: rgb(0x4CAF50)),
                    NotchMascotWearablePart(path: circle(p(-0.12, -0.02), s * 0.07), fill: rgb(0xFF9AA8))]
        case .banana:
            let banana = CGMutablePath()
            banana.move(to: p(-0.4, -0.2))
            banana.addQuadCurve(to: p(0.42, -0.12), control: p(0, 0.62))
            banana.addQuadCurve(to: p(-0.4, -0.2), control: p(0, 0.3))
            return [NotchMascotWearablePart(path: banana, fill: rgb(0xFFD23F), stroke: rgb(0xC99A1E),
                                            lineWidth: max(0.6, s * 0.05)),
                    NotchMascotWearablePart(path: circle(p(-0.4, -0.2), s * 0.05), fill: rgb(0x6B4A22))]
        case .iceCream:
            let cone = CGMutablePath()
            cone.move(to: p(-0.2, 0))
            cone.addLine(to: p(0.2, 0))
            cone.addLine(to: p(0, 0.5))
            cone.closeSubpath()
            let scoops = CGMutablePath()
            scoops.addPath(circle(p(0, -0.14), s * 0.24))
            return [NotchMascotWearablePart(path: cone, fill: rgb(0xD9A25C)),
                    NotchMascotWearablePart(path: scoops, fill: rgb(0xFFB6D2)),
                    NotchMascotWearablePart(path: circle(p(0.02, -0.34), s * 0.07), fill: rgb(0xE5384F))]
        case .onigiri:
            let ball = CGMutablePath()
            ball.move(to: p(0, -0.42))
            ball.addLine(to: p(0.4, 0.32))
            ball.addQuadCurve(to: p(-0.4, 0.32), control: p(0, 0.46))
            ball.closeSubpath()
            return [NotchMascotWearablePart(path: ball, fill: rgb(0xF7F4EE), stroke: rgb(0xCFC9BC),
                                            lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: rounded(CGRect(x: c.x - s * 0.2, y: c.y + s * 0.1,
                                                                  width: s * 0.4, height: s * 0.3), s * 0.04),
                                            fill: rgb(0x1F2A24))]
        case .ramen:
            let bowl = CGMutablePath()
            bowl.move(to: p(-0.44, -0.02))
            bowl.addLine(to: p(0.44, -0.02))
            bowl.addQuadCurve(to: p(-0.44, -0.02), control: p(0, 0.9))
            let noodles = CGMutablePath()
            for dx in [-0.22, 0, 0.22] as [CGFloat] {
                noodles.move(to: p(dx, -0.02))
                noodles.addQuadCurve(to: p(dx + 0.1, -0.34), control: p(dx - 0.12, -0.18))
            }
            return [NotchMascotWearablePart(path: noodles, fill: nil, stroke: rgb(0xFFD98A), lineWidth: max(0.8, s * 0.07)),
                    NotchMascotWearablePart(path: bowl, fill: rgb(0xE5384F), stroke: rgb(0x8E1F2E),
                                            lineWidth: max(0.5, s * 0.04))]
        case .bobaTea:
            let cup = CGMutablePath()
            cup.move(to: p(-0.24, -0.28))
            cup.addLine(to: p(0.24, -0.28))
            cup.addLine(to: p(0.18, 0.44))
            cup.addLine(to: p(-0.18, 0.44))
            cup.closeSubpath()
            let pearls = CGMutablePath()
            for dx in [-0.1, 0.02, 0.12] as [CGFloat] { pearls.addPath(circle(p(dx, 0.36), s * 0.055)) }
            let straw = CGMutablePath()
            straw.move(to: p(0.04, -0.28))
            straw.addLine(to: p(0.14, -0.5))
            return [NotchMascotWearablePart(path: straw, fill: nil, stroke: rgb(0xFF5E8A), lineWidth: max(0.8, s * 0.07)),
                    NotchMascotWearablePart(path: cup, fill: rgb(0xE8C9A0), stroke: rgb(0xB58A5B),
                                            lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: pearls, fill: rgb(0x3B2A1E))]
        }
    }

    // MARK: Secret door

    /// A door frame `width` wide: the stone arch, the dark opening and a
    /// knob. `open` is 0...1: the leaf swings toward the viewer's left.
    static func door(in rect: CGRect, open: CGFloat) -> [NotchMascotWearablePart] {
        let arch = CGMutablePath()
        let radius = rect.width / 2
        arch.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        arch.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        arch.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        arch.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        arch.closeSubpath()
        let inset = rect.width * 0.12
        let inner = rect.insetBy(dx: inset, dy: inset)
        let opening = CGMutablePath()
        let innerRadius = inner.width / 2
        opening.move(to: CGPoint(x: inner.minX, y: inner.maxY + inset))
        opening.addLine(to: CGPoint(x: inner.minX, y: inner.minY + innerRadius))
        opening.addArc(center: CGPoint(x: inner.midX, y: inner.minY + innerRadius), radius: innerRadius,
                       startAngle: .pi, endAngle: 0, clockwise: false)
        opening.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY + inset))
        opening.closeSubpath()
        let o = max(0, min(1, open))
        let leafWidth = inner.width * (1 - 0.85 * o)
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: inner.minX, y: inner.maxY + inset))
        leaf.addLine(to: CGPoint(x: inner.minX, y: inner.minY + innerRadius))
        leaf.addQuadCurve(to: CGPoint(x: inner.minX + leafWidth, y: inner.minY + innerRadius * (1 - 0.3 * o) + inset * 0.5),
                          control: CGPoint(x: inner.minX + leafWidth * 0.5, y: inner.minY - inset * 0.2))
        leaf.addLine(to: CGPoint(x: inner.minX + leafWidth, y: inner.maxY + inset - inset * 0.6 * o))
        leaf.closeSubpath()
        return [NotchMascotWearablePart(path: arch, fill: rgb(0x8A8F9C), stroke: rgb(0x5A5F6C),
                                        lineWidth: max(0.6, rect.width * 0.05)),
                NotchMascotWearablePart(path: opening, fill: rgb(0xFFE8A3)),
                NotchMascotWearablePart(path: leaf, fill: rgb(0x8B5A2B), stroke: rgb(0x5C3B1E),
                                        lineWidth: max(0.5, rect.width * 0.035)),
                NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(
                    CGPoint(x: inner.minX + leafWidth * 0.82, y: inner.midY + inner.height * 0.12), rect.width * 0.035),
                                        fill: rgb(0xFFD23F))]
    }

    // MARK: Coin and flying props

    /// A gold coin with its rim and a mark, side-on when `turn` is small.
    static func coin(at c: CGPoint, radius r: CGFloat, turn: CGFloat = 1) -> [NotchMascotWearablePart] {
        let width = max(r * 0.25, r * abs(turn))
        let face = CGRect(x: c.x - width, y: c.y - r, width: width * 2, height: r * 2)
        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: c.x, y: c.y - r * 0.5))
        mark.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.5))
        return [NotchMascotWearablePart(path: CGPath(ellipseIn: face, transform: nil), fill: rgb(0xFFC940),
                                        stroke: rgb(0xD99A1E), lineWidth: max(0.6, r * 0.18)),
                NotchMascotWearablePart(path: mark, fill: nil, stroke: rgb(0xD99A1E), lineWidth: max(0.5, r * 0.16))]
    }

    /// What flies between the two, in a square of side `s` centred on `c`,
    /// pointing right. Nil for the things the strip draws with symbols.
    static func prop(_ thing: NotchMascotIslandPlay.Thing, at c: CGPoint, side s: CGFloat) -> [NotchMascotWearablePart]? {
        func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: c.x + dx * s, y: c.y + dy * s) }
        let circle = NotchMascotWearableShapes.circle
        switch thing {
        case .snack(let item): return snack(item, at: c, side: s)
        case .fireball:
            let flame = CGMutablePath()
            flame.move(to: p(-0.5, 0))
            flame.addQuadCurve(to: p(0.1, -0.34), control: p(-0.2, -0.4))
            flame.addQuadCurve(to: p(0.1, 0.34), control: p(0.55, 0))
            flame.addQuadCurve(to: p(-0.5, 0), control: p(-0.2, 0.4))
            return [NotchMascotWearablePart(path: flame, fill: rgb(0xFF8C2B)),
                    NotchMascotWearablePart(path: circle(p(0.02, 0), s * 0.2), fill: rgb(0xFFE27A))]
        case .boomerang:
            let wing = CGMutablePath()
            wing.move(to: p(-0.4, -0.3))
            wing.addQuadCurve(to: p(0.4, -0.3), control: p(0, 0.5))
            wing.addQuadCurve(to: p(-0.4, -0.3), control: p(0, 0.18))
            return [NotchMascotWearablePart(path: wing, fill: rgb(0xD9A25C), stroke: rgb(0x8B5A2B),
                                            lineWidth: max(0.5, s * 0.05))]
        case .arrow:
            let shaft = CGMutablePath()
            shaft.move(to: p(-0.5, 0))
            shaft.addLine(to: p(0.38, 0))
            let head = CGMutablePath()
            head.move(to: p(0.5, 0))
            head.addLine(to: p(0.28, -0.16))
            head.addLine(to: p(0.28, 0.16))
            head.closeSubpath()
            let fletch = CGMutablePath()
            fletch.move(to: p(-0.5, 0))
            fletch.addLine(to: p(-0.38, -0.14))
            fletch.move(to: p(-0.5, 0))
            fletch.addLine(to: p(-0.38, 0.14))
            return [NotchMascotWearablePart(path: shaft, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: max(0.7, s * 0.07)),
                    NotchMascotWearablePart(path: head, fill: rgb(0xC9CED8)),
                    NotchMascotWearablePart(path: fletch, fill: nil, stroke: rgb(0xE5384F), lineWidth: max(0.6, s * 0.06))]
        case .key:
            let stem = CGMutablePath()
            stem.move(to: p(-0.2, 0))
            stem.addLine(to: p(0.46, 0))
            stem.move(to: p(0.34, 0))
            stem.addLine(to: p(0.34, 0.18))
            stem.move(to: p(0.46, 0))
            stem.addLine(to: p(0.46, 0.14))
            return [NotchMascotWearablePart(path: stem, fill: nil, stroke: rgb(0xFFC940), lineWidth: max(0.8, s * 0.09)),
                    NotchMascotWearablePart(path: circle(p(-0.3, 0), s * 0.17), fill: nil, stroke: rgb(0xFFC940),
                                            lineWidth: max(0.8, s * 0.09))]
        case .potion:
            let flask = CGMutablePath()
            flask.move(to: p(-0.1, -0.4))
            flask.addLine(to: p(0.1, -0.4))
            flask.addLine(to: p(0.1, -0.16))
            flask.addLine(to: p(0.32, 0.3))
            flask.addQuadCurve(to: p(-0.32, 0.3), control: p(0, 0.5))
            flask.addLine(to: p(-0.1, -0.16))
            flask.closeSubpath()
            return [NotchMascotWearablePart(path: flask, fill: rgb(0xE5384F), stroke: rgb(0xF7F4EE),
                                            lineWidth: max(0.5, s * 0.05)),
                    NotchMascotWearablePart(path: NotchMascotWearableShapes.rounded(
                        CGRect(x: c.x - s * 0.12, y: c.y - s * 0.5, width: s * 0.24, height: s * 0.12), s * 0.03),
                                            fill: rgb(0xB58A5B))]
        case .bag:
            let sack = CGMutablePath()
            sack.move(to: p(-0.14, -0.3))
            sack.addQuadCurve(to: p(-0.4, 0.3), control: p(-0.46, -0.04))
            sack.addQuadCurve(to: p(0.4, 0.3), control: p(0, 0.56))
            sack.addQuadCurve(to: p(0.14, -0.3), control: p(0.46, -0.04))
            sack.closeSubpath()
            let tie = CGMutablePath()
            tie.move(to: p(-0.16, -0.3))
            tie.addLine(to: p(0.16, -0.3))
            return [NotchMascotWearablePart(path: sack, fill: rgb(0xB58A5B), stroke: rgb(0x6B4A22),
                                            lineWidth: max(0.5, s * 0.05)),
                    NotchMascotWearablePart(path: tie, fill: nil, stroke: rgb(0xE5384F), lineWidth: max(0.8, s * 0.08)),
                    NotchMascotWearablePart(path: circle(p(0, 0.12), s * 0.12), fill: rgb(0xFFC940))]
        case .bolt:
            let zig = CGMutablePath()
            zig.move(to: p(0.1, -0.5))
            zig.addLine(to: p(-0.22, 0.04))
            zig.addLine(to: p(0, 0.04))
            zig.addLine(to: p(-0.1, 0.5))
            zig.addLine(to: p(0.26, -0.1))
            zig.addLine(to: p(0.04, -0.1))
            zig.closeSubpath()
            return [NotchMascotWearablePart(path: zig, fill: rgb(0xFFE27A), stroke: rgb(0xD9A82E),
                                            lineWidth: max(0.5, s * 0.04))]
        case .tornado:
            let funnel = CGMutablePath()
            for (index, y) in ([-0.4, -0.2, 0, 0.2, 0.4] as [CGFloat]).enumerated() {
                let half = 0.42 - CGFloat(index) * 0.08
                funnel.move(to: p(-half, y))
                funnel.addQuadCurve(to: p(half, y), control: p(0, y + 0.12))
            }
            return [NotchMascotWearablePart(path: funnel, fill: nil, stroke: rgb(0xCFE6FF), lineWidth: max(0.8, s * 0.07))]
        case .sword:
            let blade = CGMutablePath()
            blade.move(to: p(-0.2, 0))
            blade.addLine(to: p(0.5, 0))
            let guardBar = CGMutablePath()
            guardBar.move(to: p(-0.2, -0.18))
            guardBar.addLine(to: p(-0.2, 0.18))
            return [NotchMascotWearablePart(path: blade, fill: nil, stroke: rgb(0xE6EAF2), lineWidth: max(0.9, s * 0.1)),
                    NotchMascotWearablePart(path: guardBar, fill: nil, stroke: rgb(0xFFC940), lineWidth: max(0.8, s * 0.08)),
                    NotchMascotWearablePart(path: circle(p(-0.34, 0), s * 0.07), fill: rgb(0xB58A5B))]
        case .pie:
            let tin = CGMutablePath()
            tin.move(to: p(-0.4, 0.04)); tin.addLine(to: p(0.4, 0.04)); tin.addLine(to: p(0.3, 0.3)); tin.addLine(to: p(-0.3, 0.3))
            tin.closeSubpath()
            let cream = CGMutablePath()
            cream.addEllipse(in: CGRect(x: c.x - s * 0.4, y: c.y - s * 0.26, width: s * 0.8, height: s * 0.34))
            return [NotchMascotWearablePart(path: tin, fill: rgb(0xC98B4B)),
                    NotchMascotWearablePart(path: cream, fill: rgb(0xFFF8EE), stroke: rgb(0xD9CBB5), lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: circle(p(0.06, -0.3), s * 0.1), fill: rgb(0xE5384F))]
        case .peel:
            let skin = CGMutablePath()
            skin.move(to: p(-0.44, 0.16))
            skin.addQuadCurve(to: p(0.44, 0.16), control: p(0, -0.52))
            skin.addQuadCurve(to: p(-0.44, 0.16), control: p(0, -0.12))
            return [NotchMascotWearablePart(path: skin, fill: rgb(0xFFE24A), stroke: rgb(0x8A6B00), lineWidth: max(0.5, s * 0.05))]
        case .dynamite:
            let stick = CGMutablePath()
            stick.addRoundedRect(in: CGRect(x: c.x - s * 0.14, y: c.y - s * 0.3, width: s * 0.28, height: s * 0.7),
                                 cornerWidth: s * 0.06, cornerHeight: s * 0.06)
            let fuse = CGMutablePath()
            fuse.move(to: p(0, -0.3)); fuse.addQuadCurve(to: p(0.2, -0.5), control: p(0.02, -0.46))
            return [NotchMascotWearablePart(path: stick, fill: rgb(0xD83A3A), stroke: rgb(0x7A1B1B), lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: fuse, fill: nil, stroke: rgb(0x3A2A1E), lineWidth: max(0.5, s * 0.06)),
                    NotchMascotWearablePart(path: circle(p(0.22, -0.52), s * 0.1), fill: rgb(0xFFC940))]
        case .balloon:
            let string = CGMutablePath()
            string.move(to: p(0, 0.12)); string.addQuadCurve(to: p(-0.1, 0.5), control: p(0.16, 0.3))
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: c.x - s * 0.3, y: c.y - s * 0.5, width: s * 0.6, height: s * 0.66))
            return [NotchMascotWearablePart(path: string, fill: nil, stroke: rgb(0xD9D9D9), lineWidth: max(0.5, s * 0.03)),
                    NotchMascotWearablePart(path: body, fill: rgb(0x6FA8FF), stroke: rgb(0x2F5FB5), lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: circle(p(-0.1, -0.3), s * 0.07), fill: rgb(0xFFFFFF))]
        case .duck:
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: c.x - s * 0.36, y: c.y - s * 0.08, width: s * 0.72, height: s * 0.42))
            let beak = CGMutablePath()
            beak.move(to: p(0.36, -0.2)); beak.addLine(to: p(0.54, -0.14)); beak.addLine(to: p(0.36, -0.08)); beak.closeSubpath()
            return [NotchMascotWearablePart(path: body, fill: rgb(0xFFD23F), stroke: rgb(0x16161C), lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: circle(p(0.2, -0.18), s * 0.17), fill: rgb(0xFFD23F), stroke: rgb(0x16161C),
                                            lineWidth: max(0.5, s * 0.04)),
                    NotchMascotWearablePart(path: beak, fill: rgb(0xFF8A2B)),
                    NotchMascotWearablePart(path: circle(p(0.22, -0.22), s * 0.03), fill: rgb(0x16161C))]
        default: return nil
        }
    }
}
