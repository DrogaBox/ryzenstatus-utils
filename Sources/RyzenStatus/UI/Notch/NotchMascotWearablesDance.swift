// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The seven dance and backstage accessories: rosin box, pointe shoes, warm-up
/// booties, ice pack, plantar ball, Spanish fan and swan crown.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    static func danceParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        // Held things sit in its right hand; what goes on its feet stands on
        // its own feet and is sized to them, never on the chin of a figure
        // whose outline is the head alone.
        let right = f.rightHand
        let s = f.prop
        let fc = f.feetCenter, floor = f.floor, fu = f.feetUnit

        func p(_ origin: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: origin.x + dx * s, y: origin.y + dy * s) }
        func poly(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
            return path
        }

        switch accessory {
        case .rosinBox:
            // A low rustic wooden box with crushed amber rosin crystals and
            // white dust, under both feet as it chalks its soles.
            let boxRect = CGRect(x: fc - fu * 0.34, y: floor - fu * 0.12, width: fu * 0.68, height: fu * 0.18)
            let innerRect = CGRect(x: fc - fu * 0.28, y: floor - fu * 0.10, width: fu * 0.56, height: fu * 0.14)
            let c1 = poly([CGPoint(x: fc - fu * 0.18, y: floor - fu * 0.04),
                           CGPoint(x: fc - fu * 0.10, y: floor - fu * 0.09),
                           CGPoint(x: fc - fu * 0.06, y: floor - fu * 0.03)])
            let c2 = poly([CGPoint(x: fc + fu * 0.02, y: floor - fu * 0.03),
                           CGPoint(x: fc + fu * 0.08, y: floor - fu * 0.08),
                           CGPoint(x: fc + fu * 0.16, y: floor - fu * 0.04)])
            let dust = CGMutablePath()
            dust.addPath(circle(CGPoint(x: fc - fu * 0.02, y: floor - fu * 0.06), fu * 0.03))
            dust.addPath(circle(CGPoint(x: fc + fu * 0.14, y: floor - fu * 0.07), fu * 0.025))
            return [Part(path: rounded(boxRect, fu * 0.03), fill: rgb(0x8B5A2B), stroke: rgb(0x4A2E12), lineWidth: line * 0.6),
                    Part(path: rounded(innerRect, fu * 0.02), fill: rgb(0x5C3818)),
                    Part(path: c1, fill: rgb(0xFFB703)),
                    Part(path: c2, fill: rgb(0xFB8500)),
                    Part(path: dust, fill: rgb(0xFFFFFF))]

        case .pointeShoes:
            // Two satin pink pointe shoes, one on each foot, with crossed ankle ribbons.
            let feet = f.feet(spread: 0.14)
            let leftBox = CGRect(x: feet.left - fu * 0.10, y: floor - fu * 0.16, width: fu * 0.20, height: fu * 0.22)
            let rightBox = CGRect(x: feet.right - fu * 0.10, y: floor - fu * 0.16, width: fu * 0.20, height: fu * 0.22)
            let ribbons = CGMutablePath()
            for box in [leftBox, rightBox] {
                ribbons.move(to: CGPoint(x: box.minX, y: box.minY + fu * 0.04))
                ribbons.addLine(to: CGPoint(x: box.maxX, y: box.minY - fu * 0.10))
                ribbons.move(to: CGPoint(x: box.maxX, y: box.minY + fu * 0.04))
                ribbons.addLine(to: CGPoint(x: box.minX, y: box.minY - fu * 0.10))
            }
            return [Part(path: rounded(leftBox, fu * 0.04), fill: rgb(0xFFCCD5), stroke: rgb(0xFF758F), lineWidth: line * 0.6),
                    Part(path: rounded(rightBox, fu * 0.04), fill: rgb(0xFFCCD5), stroke: rgb(0xFF758F), lineWidth: line * 0.6),
                    Part(path: ribbons, fill: nil, stroke: rgb(0xFF758F), lineWidth: line * 0.8)]

        case .warmUpBooties:
            // Fluffy puffy ripstop nylon warm-up booties in vivid neon pink, one on each foot.
            let feet = f.feet(spread: 0.155)
            let leftBoot = CGRect(x: feet.left - fu * 0.125, y: floor - fu * 0.24, width: fu * 0.25, height: fu * 0.28)
            let rightBoot = CGRect(x: feet.right - fu * 0.125, y: floor - fu * 0.24, width: fu * 0.25, height: fu * 0.28)
            let cuffLeft = CGRect(x: leftBoot.minX, y: leftBoot.minY, width: leftBoot.width, height: fu * 0.07)
            let cuffRight = CGRect(x: rightBoot.minX, y: rightBoot.minY, width: rightBoot.width, height: fu * 0.07)
            return [Part(path: rounded(leftBoot, fu * 0.08), fill: rgb(0xFF007F), stroke: rgb(0xC70039), lineWidth: line * 0.6),
                    Part(path: rounded(rightBoot, fu * 0.08), fill: rgb(0xFF007F), stroke: rgb(0xC70039), lineWidth: line * 0.6),
                    Part(path: rounded(cuffLeft, fu * 0.03), fill: rgb(0x222226)),
                    Part(path: rounded(cuffRight, fu * 0.03), fill: rgb(0x222226))]

        case .icePack:
            // A translucent icy blue ice pack with elastic bandage wrap, round
            // its ankles.
            let dome = CGRect(x: fc - fu * 0.26, y: floor - fu * 0.18, width: fu * 0.52, height: fu * 0.22)
            let cubes = CGMutablePath()
            cubes.addRect(CGRect(x: fc - fu * 0.16, y: floor - fu * 0.14, width: fu * 0.10, height: fu * 0.10))
            cubes.addRect(CGRect(x: fc + fu * 0.04, y: floor - fu * 0.15, width: fu * 0.11, height: fu * 0.11))
            let wrap = CGMutablePath()
            wrap.move(to: CGPoint(x: dome.minX - fu * 0.04, y: dome.midY - fu * 0.04))
            wrap.addLine(to: CGPoint(x: dome.maxX + fu * 0.04, y: dome.midY - fu * 0.04))
            wrap.move(to: CGPoint(x: dome.minX - fu * 0.02, y: dome.midY + fu * 0.04))
            wrap.addLine(to: CGPoint(x: dome.maxX + fu * 0.02, y: dome.midY + fu * 0.04))
            return [Part(path: rounded(dome, fu * 0.06), fill: rgb(0x48CAE4), stroke: rgb(0x0096C7), lineWidth: line * 0.6),
                    Part(path: cubes, fill: rgb(0xADE8F4)),
                    Part(path: wrap, fill: nil, stroke: rgb(0xEDF2F7), lineWidth: line * 1.1)]

        case .plantarBall:
            // Optic yellow-green tennis ball with white curved seams.
            let ballCenter = p(right, 0.12, 0.08)
            let r = s * 0.24
            let seams = CGMutablePath()
            seams.addArc(center: CGPoint(x: ballCenter.x - r * 0.7, y: ballCenter.y), radius: r * 0.75,
                         startAngle: -.pi * 0.4, endAngle: .pi * 0.4, clockwise: false)
            seams.addArc(center: CGPoint(x: ballCenter.x + r * 0.7, y: ballCenter.y), radius: r * 0.75,
                         startAngle: .pi * 0.6, endAngle: .pi * 1.4, clockwise: false)
            return [Part(path: circle(ballCenter, r), fill: rgb(0xD4E022), stroke: rgb(0x9EAA10), lineWidth: line * 0.5),
                    Part(path: seams, fill: nil, stroke: rgb(0xFFFFFF), lineWidth: line * 0.8)]

        case .spanishFan:
            // Kitri's open Spanish flamenco/ballet fan in crimson silk and black lace.
            let pivot = p(right, -0.04, 0.22)
            let fanRadius = s * 0.54
            let arc = CGMutablePath()
            arc.move(to: pivot)
            arc.addArc(center: pivot, radius: fanRadius, startAngle: -.pi * 0.85, endAngle: -.pi * 0.15, clockwise: false)
            arc.closeSubpath()
            let ribs = CGMutablePath()
            for i in 1...4 {
                let angle = -.pi * 0.85 + Double(i) * (.pi * 0.70 / 5)
                ribs.move(to: pivot)
                ribs.addLine(to: CGPoint(x: pivot.x + CGFloat(cos(angle)) * fanRadius,
                                         y: pivot.y + CGFloat(sin(angle)) * fanRadius))
            }
            let lace = CGMutablePath()
            lace.addArc(center: pivot, radius: fanRadius, startAngle: -.pi * 0.85, endAngle: -.pi * 0.15, clockwise: false)
            return [Part(path: arc, fill: rgb(0xD90429)),
                    Part(path: ribs, fill: nil, stroke: rgb(0x3D1A10), lineWidth: line * 0.7),
                    Part(path: lace, fill: nil, stroke: rgb(0x16161C), lineWidth: line * 1.2)]

        case .swanCrown:
            // Odette's feathered silver tiara with aquamarine jewel.
            let baseBand = CGMutablePath()
            baseBand.move(to: CGPoint(x: cx - w * 0.26, y: top + w * 0.08))
            baseBand.addQuadCurve(to: CGPoint(x: cx + w * 0.26, y: top + w * 0.08), control: CGPoint(x: cx, y: top - w * 0.02))
            let feathers = CGMutablePath()
            // Left feather wing
            feathers.move(to: CGPoint(x: cx - w * 0.18, y: top + w * 0.06))
            feathers.addQuadCurve(to: CGPoint(x: cx - w * 0.32, y: top - w * 0.18), control: CGPoint(x: cx - w * 0.30, y: top - w * 0.04))
            feathers.addQuadCurve(to: CGPoint(x: cx - w * 0.12, y: top + w * 0.02), control: CGPoint(x: cx - w * 0.20, y: top - w * 0.08))
            // Right feather wing
            feathers.move(to: CGPoint(x: cx + w * 0.18, y: top + w * 0.06))
            feathers.addQuadCurve(to: CGPoint(x: cx + w * 0.32, y: top - w * 0.18), control: CGPoint(x: cx + w * 0.30, y: top - w * 0.04))
            feathers.addQuadCurve(to: CGPoint(x: cx + w * 0.12, y: top + w * 0.02), control: CGPoint(x: cx + w * 0.20, y: top - w * 0.08))
            return [Part(path: baseBand, fill: nil, stroke: rgb(0xE0E1DD), lineWidth: line * 1.2),
                    Part(path: feathers, fill: rgb(0xFFFFFF), stroke: rgb(0xC5C6C7), lineWidth: line * 0.5),
                    Part(path: circle(CGPoint(x: cx, y: top - w * 0.01), w * 0.045), fill: rgb(0x48CAE4))]

        default:
            return []
        }
    }
}
