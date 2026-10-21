// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The thirty-two wearables of the Wonder Boy wardrobe, traced with paths
/// like the first eighteen: bold shapes, few of them, since the companion
/// is about twenty points tall in the island. Arms and gadgets are held at
/// its side, helmets sit on the head, wings and the jetpack show at its
/// back, the boots at its feet, and what goes on the face follows the eyes.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    static func rpgParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        let ink = NotchMascotColor.ink.cgColor
        // Where an item is held: at its right side, a little below the middle, and on the left.
        let right = CGPoint(x: f.outline.maxX + w * 0.02, y: f.outline.minY + f.outline.height * 0.62)
        let left = CGPoint(x: f.outline.minX - w * 0.02, y: f.outline.minY + f.outline.height * 0.62)
        let s = w * 0.56
        let eyeY = (f.leftEye.y + f.rightEye.y) / 2
        let eyeGap = abs(f.rightEye.x - f.leftEye.x)

        func p(_ origin: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: origin.x + dx * s, y: origin.y + dy * s) }

        switch accessory {
        // MARK: Arms and gear

        case .legendSword:
            let blade = CGMutablePath()
            blade.move(to: p(right, 0, 0.18))
            blade.addLine(to: p(right, 0, -0.95))
            let guardBar = CGMutablePath()
            guardBar.move(to: p(right, -0.2, -0.02))
            guardBar.addLine(to: p(right, 0.2, -0.02))
            return [Part(path: blade, fill: nil, stroke: rgb(0xE6EAF2), lineWidth: line * 1.7),
                    Part(path: guardBar, fill: nil, stroke: rgb(0xFFC940), lineWidth: line * 1.3),
                    Part(path: circle(p(right, 0, 0.22), s * 0.07), fill: rgb(0xE5384F))]

        case .legendShield:
            let shield = CGMutablePath()
            shield.move(to: p(left, -0.3, -0.42))
            shield.addLine(to: p(left, 0.3, -0.42))
            shield.addLine(to: p(left, 0.3, 0.02))
            shield.addQuadCurve(to: p(left, 0, 0.52), control: p(left, 0.26, 0.38))
            shield.addQuadCurve(to: p(left, -0.3, 0.02), control: p(left, -0.26, 0.38))
            shield.closeSubpath()
            let cross = CGMutablePath()
            cross.move(to: p(left, 0, -0.34))
            cross.addLine(to: p(left, 0, 0.3))
            cross.move(to: p(left, -0.2, -0.12))
            cross.addLine(to: p(left, 0.2, -0.12))
            return [Part(path: shield, fill: rgb(0x3358C9), stroke: rgb(0xFFC940), lineWidth: line),
                    Part(path: cross, fill: nil, stroke: rgb(0xFFC940), lineWidth: line)]

        case .wingBoots:
            let base = f.outline.maxY
            var parts: [Part] = []
            for side in [-1, 1] as [CGFloat] {
                let heel = CGPoint(x: cx + side * w * 0.25, y: base)
                let boot = CGMutablePath()
                boot.move(to: CGPoint(x: heel.x - w * 0.1, y: heel.y - w * 0.16))
                boot.addLine(to: CGPoint(x: heel.x + w * 0.1, y: heel.y - w * 0.16))
                boot.addLine(to: CGPoint(x: heel.x + w * 0.1, y: heel.y))
                boot.addLine(to: CGPoint(x: heel.x - side * w * 0.04 - w * 0.1, y: heel.y))
                boot.closeSubpath()
                let wing = CGMutablePath()
                wing.move(to: CGPoint(x: heel.x - side * w * 0.1, y: heel.y - w * 0.1))
                wing.addQuadCurve(to: CGPoint(x: heel.x - side * w * 0.3, y: heel.y - w * 0.28),
                                  control: CGPoint(x: heel.x - side * w * 0.26, y: heel.y - w * 0.06))
                wing.addQuadCurve(to: CGPoint(x: heel.x - side * w * 0.1, y: heel.y - w * 0.18),
                                  control: CGPoint(x: heel.x - side * w * 0.16, y: heel.y - w * 0.22))
                parts.append(Part(path: boot, fill: rgb(0xB07A45)))
                parts.append(Part(path: wing, fill: rgb(0xF7F4EE), stroke: rgb(0xCFC9BC), lineWidth: line * 0.4))
            }
            return parts

        case .knightHelm:
            let base = top + w * 0.2
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.44, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.44, y: base), control1: CGPoint(x: cx - w * 0.44, y: top - w * 0.34),
                          control2: CGPoint(x: cx + w * 0.44, y: top - w * 0.34))
            dome.closeSubpath()
            let slit = CGRect(x: cx - w * 0.3, y: base - w * 0.13, width: w * 0.6, height: w * 0.05)
            let plume = CGMutablePath()
            plume.move(to: CGPoint(x: cx, y: top - w * 0.18))
            plume.addQuadCurve(to: CGPoint(x: cx + w * 0.34, y: top - w * 0.3), control: CGPoint(x: cx + w * 0.14, y: top - w * 0.44))
            plume.addQuadCurve(to: CGPoint(x: cx, y: top - w * 0.1), control: CGPoint(x: cx + w * 0.18, y: top - w * 0.14))
            return [Part(path: plume, fill: rgb(0xE5384F)),
                    Part(path: dome, fill: rgb(0xAEB4C2), stroke: rgb(0x7B8294), lineWidth: line * 0.6),
                    Part(path: rounded(slit, w * 0.02), fill: rgb(0x2B2B33))]

        case .katana:
            let blade = CGMutablePath()
            blade.move(to: p(right, 0.04, 0.14))
            blade.addQuadCurve(to: p(right, 0.3, -0.9), control: p(right, -0.04, -0.4))
            let hilt = CGMutablePath()
            hilt.move(to: p(right, 0.04, 0.14))
            hilt.addLine(to: p(right, 0, 0.4))
            return [Part(path: blade, fill: nil, stroke: rgb(0xE6EAF2), lineWidth: line * 1.2),
                    Part(path: hilt, fill: nil, stroke: rgb(0x2B2B33), lineWidth: line * 1.7),
                    Part(path: circle(p(right, 0.05, 0.12), s * 0.09), fill: rgb(0xFFC940))]

        case .vikingHelm:
            let base = top + w * 0.2
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.42, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.42, y: base), control1: CGPoint(x: cx - w * 0.42, y: top - w * 0.3),
                          control2: CGPoint(x: cx + w * 0.42, y: top - w * 0.3))
            dome.closeSubpath()
            let horns = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                horns.move(to: CGPoint(x: cx + side * w * 0.36, y: top + w * 0.02))
                horns.addQuadCurve(to: CGPoint(x: cx + side * w * 0.56, y: top - w * 0.34),
                                   control: CGPoint(x: cx + side * w * 0.62, y: top - w * 0.02))
                horns.addQuadCurve(to: CGPoint(x: cx + side * w * 0.3, y: top + w * 0.06),
                                   control: CGPoint(x: cx + side * w * 0.46, y: top - w * 0.1))
                horns.closeSubpath()
            }
            let guardBar = CGMutablePath()
            guardBar.move(to: CGPoint(x: cx, y: base - w * 0.1))
            guardBar.addLine(to: CGPoint(x: cx, y: base + w * 0.12))
            return [Part(path: horns, fill: rgb(0xF7F4EE), stroke: rgb(0xCFC9BC), lineWidth: line * 0.4),
                    Part(path: dome, fill: rgb(0x8C93A3), stroke: rgb(0x5A6070), lineWidth: line * 0.6),
                    Part(path: guardBar, fill: nil, stroke: rgb(0x5A6070), lineWidth: line)]

        case .wizardStaff:
            let rod = CGMutablePath()
            rod.move(to: p(right, 0, 0.5))
            rod.addLine(to: p(right, 0, -0.8))
            return [Part(path: rod, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 1.6),
                    Part(path: circle(p(right, 0, -0.92), s * 0.2), fill: rgb(0xB57CFF), stroke: rgb(0x6C3FB0), lineWidth: line * 0.6),
                    Part(path: circle(p(right, -0.05, -0.97), s * 0.06), fill: rgb(0xF7F4EE))]

        case .magicTome:
            let book = CGRect(x: right.x - s * 0.34, y: right.y - s * 0.4, width: s * 0.62, height: s * 0.8)
            let star = CGMutablePath()
            let mid = CGPoint(x: book.midX, y: book.midY)
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                let b = a + .pi / 5
                star.move(to: CGPoint(x: mid.x + CGFloat(cos(a)) * s * 0.18, y: mid.y + CGFloat(sin(a)) * s * 0.18))
                star.addLine(to: CGPoint(x: mid.x + CGFloat(cos(b)) * s * 0.07, y: mid.y + CGFloat(sin(b)) * s * 0.07))
            }
            let page = CGMutablePath()
            page.move(to: CGPoint(x: book.maxX, y: book.minY + s * 0.04))
            page.addLine(to: CGPoint(x: book.maxX, y: book.maxY - s * 0.04))
            return [Part(path: rounded(book, s * 0.06), fill: rgb(0x5B3A8C), stroke: rgb(0x3A2360), lineWidth: line * 0.7),
                    Part(path: page, fill: nil, stroke: rgb(0xF7F4EE), lineWidth: line * 1.2),
                    Part(path: star, fill: nil, stroke: rgb(0xFFD23F), lineWidth: line * 0.7)]

        case .crystalOrb:
            let orb = circle(p(right, 0, -0.12), s * 0.36)
            let stand = CGRect(x: right.x - s * 0.24, y: right.y + s * 0.18, width: s * 0.48, height: s * 0.12)
            let shine = CGMutablePath()
            shine.addArc(center: p(right, 0, -0.12), radius: s * 0.24, startAngle: .pi * 1.1, endAngle: .pi * 1.55, clockwise: false)
            return [Part(path: rounded(stand, s * 0.04), fill: rgb(0x8B5A2B)),
                    Part(path: orb, fill: rgb(0x6FD6FF), stroke: rgb(0x2E9CCB), lineWidth: line * 0.7),
                    Part(path: shine, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: line * 0.9)]

        case .rangerBow:
            let bow = CGMutablePath()
            bow.move(to: p(right, 0.04, -0.7))
            bow.addQuadCurve(to: p(right, 0.04, 0.7), control: p(right, 0.5, 0))
            let string = CGMutablePath()
            string.move(to: p(right, 0.04, -0.7))
            string.addLine(to: p(right, 0.04, 0.7))
            return [Part(path: string, fill: nil, stroke: rgb(0xF7F4EE), lineWidth: line * 0.5),
                    Part(path: bow, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 1.6)]

        case .kingScepter:
            let rod = CGMutablePath()
            rod.move(to: p(right, 0, 0.5))
            rod.addLine(to: p(right, 0, -0.65))
            return [Part(path: rod, fill: nil, stroke: rgb(0xFFC940), lineWidth: line * 1.5),
                    Part(path: circle(p(right, 0, -0.78), s * 0.16), fill: rgb(0xE5384F), stroke: rgb(0xFFC940), lineWidth: line),
                    Part(path: circle(p(right, 0, 0.5), s * 0.07), fill: rgb(0xFFC940))]

        case .boomerang, .fireballSpell, .tornadoSpell, .goldenKey, .goldBag:
            let thing: NotchMascotIslandPlay.Thing
            switch accessory {
            case .boomerang: thing = .boomerang
            case .fireballSpell: thing = .fireball
            case .tornadoSpell: thing = .tornado
            case .goldenKey: thing = .key
            default: thing = .bag
            }
            let at = accessory == .goldenKey ? p(right, 0.1, -0.2) : p(right, 0.04, -0.25)
            return NotchMascotRPGShapes.prop(thing, at: at, side: s * 1.1) ?? []

        case .thunderTalisman:
            let paper = CGRect(x: right.x - s * 0.22, y: right.y - s * 0.62, width: s * 0.44, height: s * 0.8)
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: paper.midX + s * 0.05, y: paper.minY + s * 0.1))
            bolt.addLine(to: CGPoint(x: paper.midX - s * 0.1, y: paper.midY))
            bolt.addLine(to: CGPoint(x: paper.midX + s * 0.02, y: paper.midY))
            bolt.addLine(to: CGPoint(x: paper.midX - s * 0.05, y: paper.maxY - s * 0.1))
            return [Part(path: rounded(paper, s * 0.03), fill: rgb(0xFFE9A8), stroke: rgb(0xD9A82E), lineWidth: line * 0.6),
                    Part(path: bolt, fill: nil, stroke: rgb(0xE5384F), lineWidth: line * 1.2)]

        // MARK: Life and gadgets

        case .hourglass:
            let c = p(right, 0, -0.15)
            let glass = CGMutablePath()
            glass.move(to: CGPoint(x: c.x - s * 0.22, y: c.y - s * 0.38))
            glass.addLine(to: CGPoint(x: c.x + s * 0.22, y: c.y - s * 0.38))
            glass.addLine(to: CGPoint(x: c.x, y: c.y))
            glass.addLine(to: CGPoint(x: c.x + s * 0.22, y: c.y + s * 0.38))
            glass.addLine(to: CGPoint(x: c.x - s * 0.22, y: c.y + s * 0.38))
            glass.addLine(to: CGPoint(x: c.x, y: c.y))
            glass.closeSubpath()
            let sand = CGMutablePath()
            sand.move(to: CGPoint(x: c.x - s * 0.1, y: c.y + s * 0.38))
            sand.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y + s * 0.38))
            sand.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.18))
            sand.closeSubpath()
            let caps = CGMutablePath()
            caps.move(to: CGPoint(x: c.x - s * 0.28, y: c.y - s * 0.38))
            caps.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y - s * 0.38))
            caps.move(to: CGPoint(x: c.x - s * 0.28, y: c.y + s * 0.38))
            caps.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y + s * 0.38))
            return [Part(path: glass, fill: rgb(0xCFE6FF), stroke: rgb(0x8B5A2B), lineWidth: line * 0.8),
                    Part(path: sand, fill: rgb(0xFFC940)),
                    Part(path: caps, fill: nil, stroke: rgb(0x8B5A2B), lineWidth: line * 1.5)]

        case .heartPotion:
            let c = p(right, 0.04, -0.2)
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: c.x, y: c.y + s * 0.2))
            heart.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.02), control1: CGPoint(x: c.x - s * 0.24, y: c.y + s * 0.06),
                           control2: CGPoint(x: c.x - s * 0.14, y: c.y - s * 0.12))
            heart.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.2), control1: CGPoint(x: c.x + s * 0.14, y: c.y - s * 0.12),
                           control2: CGPoint(x: c.x + s * 0.24, y: c.y + s * 0.06))
            return (NotchMascotRPGShapes.prop(.potion, at: c, side: s * 1.1) ?? []) + [Part(path: heart, fill: rgb(0xFFFFFF))]

        case .iceCreamCone:
            return NotchMascotRPGShapes.snack(.iceCream, at: p(right, 0.04, -0.2), side: s * 1.2)
        case .onigiri:
            return NotchMascotRPGShapes.snack(.onigiri, at: p(right, 0.04, -0.15), side: s * 1.1)
        case .ramenBowl:
            return NotchMascotRPGShapes.snack(.ramen, at: p(right, 0.04, -0.2), side: s * 1.2)
        case .bobaTea:
            return NotchMascotRPGShapes.snack(.bobaTea, at: p(right, 0.04, -0.2), side: s * 1.2)

        case .sleepMask:
            let r = max(f.size * 0.07, eyeGap * 0.46)
            let band = CGRect(x: f.outline.minX + w * 0.02, y: eyeY - r * 1.1, width: w * 0.96, height: r * 2.2)
            let lids = CGMutablePath()
            for eye in [f.leftEye, f.rightEye] {
                lids.move(to: CGPoint(x: eye.x - r * 0.7, y: eye.y - r * 0.1))
                lids.addQuadCurve(to: CGPoint(x: eye.x + r * 0.7, y: eye.y - r * 0.1),
                                  control: CGPoint(x: eye.x, y: eye.y + r * 0.7))
            }
            return [Part(path: rounded(band, r), fill: rgb(0x4B4F9E), stroke: ink, lineWidth: line * 0.5),
                    Part(path: lids, fill: nil, stroke: rgb(0xF7F4EE), lineWidth: line * 0.8)]

        case .pacifier:
            let c = CGPoint(x: cx, y: eyeY + f.outline.height * 0.3)
            let shield = CGMutablePath()
            shield.addEllipse(in: CGRect(x: c.x - w * 0.17, y: c.y - w * 0.07, width: w * 0.34, height: w * 0.14))
            let nipple = circle(CGPoint(x: c.x, y: c.y), w * 0.06)
            let ring = circle(CGPoint(x: c.x, y: c.y + w * 0.13), w * 0.07)
            return [Part(path: shield, fill: rgb(0xFF9AC1), stroke: rgb(0xD93A68), lineWidth: line * 0.5),
                    Part(path: nipple, fill: rgb(0xFFD2E4)),
                    Part(path: ring, fill: nil, stroke: rgb(0xD93A68), lineWidth: line * 0.8)]

        case .bardLute:
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: right.x - s * 0.3, y: right.y - s * 0.02, width: s * 0.5, height: s * 0.5))
            let neck = CGMutablePath()
            neck.move(to: p(right, -0.05, 0.05))
            neck.addLine(to: p(right, 0.3, -0.55))
            let strings = CGMutablePath()
            strings.move(to: p(right, -0.12, 0.26))
            strings.addLine(to: p(right, 0.24, -0.42))
            return [Part(path: neck, fill: nil, stroke: rgb(0x6B4A22), lineWidth: line * 1.5),
                    Part(path: body, fill: rgb(0xD9A25C), stroke: rgb(0x8B5A2B), lineWidth: line * 0.8),
                    Part(path: circle(p(right, -0.05, 0.24), s * 0.07), fill: rgb(0x3B2A1E)),
                    Part(path: strings, fill: nil, stroke: rgb(0xF7F4EE), lineWidth: line * 0.4)]

        case .dumbbells:
            let c = p(right, 0, -0.05)
            let bar = CGMutablePath()
            bar.move(to: CGPoint(x: c.x - s * 0.38, y: c.y))
            bar.addLine(to: CGPoint(x: c.x + s * 0.38, y: c.y))
            let plates = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                plates.addPath(rounded(CGRect(x: c.x + side * s * 0.34 - s * 0.07, y: c.y - s * 0.2, width: s * 0.14, height: s * 0.4), s * 0.04))
            }
            return [Part(path: bar, fill: nil, stroke: rgb(0x8C93A3), lineWidth: line * 1.3),
                    Part(path: plates, fill: rgb(0x3A3F4B), stroke: rgb(0x8C93A3), lineWidth: line * 0.4)]

        case .detectiveLens:
            let r = max(f.size * 0.08, eyeGap * 0.5)
            let handle = CGMutablePath()
            handle.move(to: CGPoint(x: f.rightEye.x + r * 0.7, y: f.rightEye.y + r * 0.7))
            handle.addLine(to: CGPoint(x: f.rightEye.x + r * 1.9, y: f.rightEye.y + r * 1.9))
            return [Part(path: handle, fill: nil, stroke: rgb(0x6B4A22), lineWidth: line * 1.6),
                    Part(path: circle(f.rightEye, r), fill: nil, stroke: rgb(0xC9A227), lineWidth: line * 1.3),
                    Part(path: circle(f.rightEye, r * 0.86), fill: nil, stroke: rgb(0xCFE6FF), lineWidth: line * 0.4)]

        case .laserVisor:
            let r = max(f.size * 0.06, eyeGap * 0.4)
            let band = CGRect(x: f.outline.minX + w * 0.02, y: eyeY - r * 0.9, width: w * 0.96, height: r * 1.8)
            let beam = CGMutablePath()
            beam.move(to: CGPoint(x: f.outline.minX + w * 0.12, y: eyeY))
            beam.addLine(to: CGPoint(x: f.outline.maxX - w * 0.12, y: eyeY))
            return [Part(path: rounded(band, r * 0.9), fill: rgb(0x16161C), stroke: rgb(0x3A3F4B), lineWidth: line * 0.6),
                    Part(path: beam, fill: nil, stroke: rgb(0xFF3B5C), lineWidth: line * 1.2)]

        case .jetpack:
            var parts: [Part] = []
            let x = f.outline.minX - w * 0.04
            for index in 0..<2 {
                let tank = CGRect(x: x - w * 0.08 - CGFloat(index) * w * 0.12, y: f.outline.minY + f.outline.height * 0.28,
                                  width: w * 0.12, height: f.outline.height * 0.44)
                let flame = CGMutablePath()
                flame.move(to: CGPoint(x: tank.minX + tank.width * 0.15, y: tank.maxY))
                flame.addLine(to: CGPoint(x: tank.midX, y: tank.maxY + w * 0.22))
                flame.addLine(to: CGPoint(x: tank.maxX - tank.width * 0.15, y: tank.maxY))
                flame.closeSubpath()
                parts.append(Part(path: flame, fill: rgb(0xFF8C2B)))
                parts.append(Part(path: rounded(tank, w * 0.05), fill: rgb(0xAEB4C2), stroke: rgb(0x5A6070), lineWidth: line * 0.5))
            }
            return parts

        case .gameController:
            let pad = CGRect(x: right.x - s * 0.4, y: right.y - s * 0.28, width: s * 0.8, height: s * 0.4)
            let dpad = CGMutablePath()
            dpad.move(to: p(right, -0.24, -0.08))
            dpad.addLine(to: p(right, -0.04, -0.08))
            dpad.move(to: p(right, -0.14, -0.18))
            dpad.addLine(to: p(right, -0.14, 0.02))
            let buttons = CGMutablePath()
            buttons.addPath(circle(p(right, 0.1, -0.1), s * 0.05))
            buttons.addPath(circle(p(right, 0.24, -0.04), s * 0.05))
            return [Part(path: rounded(pad, s * 0.16), fill: rgb(0x3A3F4B), stroke: rgb(0x16161C), lineWidth: line * 0.5),
                    Part(path: dpad, fill: nil, stroke: rgb(0xF7F4EE), lineWidth: line * 0.9),
                    Part(path: buttons, fill: rgb(0xE5384F))]

        case .angelWings:
            var parts: [Part] = []
            for side in [-1, 1] as [CGFloat] {
                let root = CGPoint(x: cx + side * w * 0.46, y: f.outline.minY + f.outline.height * 0.42)
                let wing = CGMutablePath()
                wing.move(to: root)
                wing.addQuadCurve(to: CGPoint(x: root.x + side * w * 0.36, y: root.y - w * 0.4),
                                  control: CGPoint(x: root.x + side * w * 0.42, y: root.y - w * 0.1))
                wing.addQuadCurve(to: CGPoint(x: root.x + side * w * 0.3, y: root.y - w * 0.02),
                                  control: CGPoint(x: root.x + side * w * 0.46, y: root.y - w * 0.2))
                wing.addQuadCurve(to: CGPoint(x: root.x + side * w * 0.22, y: root.y + w * 0.18),
                                  control: CGPoint(x: root.x + side * w * 0.36, y: root.y + w * 0.06))
                wing.addQuadCurve(to: root, control: CGPoint(x: root.x + side * w * 0.1, y: root.y + w * 0.14))
                wing.closeSubpath()
                parts.append(Part(path: wing, fill: rgb(0xF7F4EE), stroke: rgb(0xCFC9BC), lineWidth: line * 0.5))
            }
            return parts

        default:
            return []
        }
    }
}
