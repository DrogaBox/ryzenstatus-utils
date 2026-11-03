// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// The sixteen oddities and wonders, traced with a few bold paths like the
/// rest. Each finds its own place on the figure that wears it: the hats on
/// top of the head, the gum, the kazoo and the beard at its mouth, the mask
/// over its eyes, the boa round its neck, the skates on its two feet, the
/// snail on its left shoulder and what it holds in its right hand, leaning
/// out and away from its face.
extension NotchMascotWearableShapes {
    private typealias Part = NotchMascotWearablePart

    static func rgba(_ hex: UInt32, _ alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func oddityParts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        let right = f.rightHand
        let s = f.prop
        // What goes on the face is sized to the head, as the clown nose is.
        let fs = w * 0.56
        let eyeY = (f.leftEye.y + f.rightEye.y) / 2
        let eyeGap = abs(f.rightEye.x - f.leftEye.x)
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

        switch accessory {
        case .pizzaSlice:
            // A slice held by its crust, the tip leaning out and up, away
            // from its face: melting cheese, three pepperoni and a drip.
            let tip = p(right, 0.5, -0.62)
            let crustLeft = p(right, -0.22, 0.04), crustRight = p(right, 0.3, 0.12)
            let slice = poly([crustLeft, tip, crustRight])
            let crust = CGMutablePath()
            crust.move(to: crustLeft)
            crust.addQuadCurve(to: crustRight, control: p(right, 0.02, 0.24))
            let pepperoni = CGMutablePath()
            for (dx, dy, r) in [(0.06, -0.06, 0.08), (0.26, -0.3, 0.065), (0.2, 0.02, 0.06)] as [(CGFloat, CGFloat, CGFloat)] {
                pepperoni.addPath(circle(p(right, dx, dy), s * r))
            }
            let drip = CGMutablePath()
            drip.addPath(rounded(CGRect(x: p(right, -0.08, 0).x, y: p(right, 0, 0.06).y, width: s * 0.06, height: s * 0.16),
                                 s * 0.03))
            return [Part(path: slice, fill: rgb(0xFFC94A), stroke: rgb(0xD9962B), lineWidth: line * 0.5),
                    Part(path: drip, fill: rgb(0xFFC94A)),
                    Part(path: pepperoni, fill: rgb(0xD7263D), stroke: rgb(0x8A1F2E), lineWidth: line * 0.3),
                    Part(path: crust, fill: nil, stroke: rgb(0xC07A35), lineWidth: line * 1.3)]

        case .kazoo:
            // A red kazoo in its mouth, sticking out to the side, with the
            // silver cap of its buzzing membrane on top. A beak up between
            // the eyes, as the phoenix's, plays it pointing down instead, so
            // it never crosses an eye.
            let mouth = f.mouthful
            let length = fs * 0.62, girth = fs * 0.14
            let down = mouth.y < eyeY + f.size * 0.06
            let turn = down ? CGAffineTransform(translationX: mouth.x, y: mouth.y).rotated(by: .pi / 2)
                .translatedBy(x: -mouth.x, y: -mouth.y) : .identity
            let body = CGMutablePath()
            body.addPath(poly([CGPoint(x: mouth.x - fs * 0.04, y: mouth.y - girth * 0.4),
                               CGPoint(x: mouth.x + length, y: mouth.y - girth * 0.75),
                               CGPoint(x: mouth.x + length, y: mouth.y + girth * 0.75),
                               CGPoint(x: mouth.x - fs * 0.04, y: mouth.y + girth * 0.4)]), transform: turn)
            let cap = CGMutablePath()
            cap.addPath(ellipse(CGPoint(x: mouth.x + length * 0.5, y: mouth.y - girth * 0.66), girth * 0.42, girth * 0.24),
                        transform: turn)
            let bell = CGMutablePath()
            bell.addPath(ellipse(CGPoint(x: mouth.x + length, y: mouth.y), girth * 0.18, girth * 0.7), transform: turn)
            return [Part(path: body, fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.4),
                    Part(path: cap, fill: rgb(0xC0C4CC), stroke: ink, lineWidth: line * 0.3),
                    Part(path: bell, fill: rgb(0x8A1F2E))]

        case .bubbleGum:
            // A pink bubble blown at its mouth, as big as the face lets it
            // grow before it would reach the eyes.
            let mouth = f.mouthful
            let room = max(fs * 0.14, (mouth.y - eyeY) * 0.82)
            let r = min(fs * 0.34, room)
            let center = CGPoint(x: mouth.x, y: mouth.y + r * 0.3)
            return [Part(path: circle(center, r), fill: rgb(0xFF8AC8), stroke: rgb(0xD94A93), lineWidth: line * 0.5),
                    Part(path: circle(CGPoint(x: center.x - r * 0.4, y: center.y - r * 0.4), r * 0.2), fill: rgba(0xFFFFFF, 0.85)),
                    Part(path: circle(CGPoint(x: center.x + r * 0.32, y: center.y - r * 0.5), r * 0.08), fill: rgba(0xFFFFFF, 0.7))]

        case .crackerCrown:
            // The paper crown out of a Christmas cracker, a little too big
            // and worn askew, with the folds still in it.
            let base = top + w * 0.06
            let half = w * 0.32, height = w * 0.2, tilt = w * 0.05
            var points: [CGPoint] = [CGPoint(x: cx - half, y: base + tilt)]
            for k in 0...6 {
                let t = CGFloat(k) / 6
                let x = cx - half + t * half * 2
                let lean = tilt * (1 - 2 * t)
                points.append(CGPoint(x: x, y: base + lean - (k.isMultiple(of: 2) ? height : height * 0.45)))
            }
            points.append(CGPoint(x: cx + half, y: base - tilt))
            let folds = CGMutablePath()
            for t in [0.33, 0.66] as [CGFloat] {
                let x = cx - half + t * half * 2
                folds.move(to: CGPoint(x: x, y: base + tilt * (1 - 2 * t) - height * 0.4))
                folds.addLine(to: CGPoint(x: x, y: base + tilt * (1 - 2 * t)))
            }
            return [Part(path: poly(points), fill: rgb(0xFFD93D), stroke: rgb(0xD9A82E), lineWidth: line * 0.5),
                    Part(path: folds, fill: nil, stroke: rgb(0xE8B92E), lineWidth: line * 0.4)]

        case .rubberChicken:
            // A rubber chicken held by its neck, its body flopping out and
            // down, beak wide open in a silent squawk.
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: -s * 0.3, y: -s * 0.13, width: s * 0.6, height: s * 0.26),
                            transform: CGAffineTransform(translationX: p(right, 0.26, 0.2).x, y: p(right, 0.26, 0.2).y)
                                .rotated(by: 0.7))
            let neck = stroke(p(right, 0, -0.1), p(right, 0.12, 0.08))
            let head = circle(p(right, -0.02, -0.18), s * 0.1)
            let comb = CGMutablePath()
            comb.addPath(circle(p(right, -0.06, -0.3), s * 0.045))
            comb.addPath(circle(p(right, 0.02, -0.31), s * 0.045))
            let beak = poly([p(right, -0.1, -0.2), p(right, -0.3, -0.24), p(right, -0.12, -0.16), p(right, -0.28, -0.1)])
            let legs = CGMutablePath()
            legs.move(to: p(right, 0.42, 0.42)); legs.addLine(to: p(right, 0.5, 0.56))
            legs.move(to: p(right, 0.5, 0.38)); legs.addLine(to: p(right, 0.62, 0.48))
            return [Part(path: legs, fill: nil, stroke: rgb(0xFF8A2B), lineWidth: line * 0.6),
                    Part(path: neck, fill: nil, stroke: rgb(0xFFE066), lineWidth: line * 1.6),
                    Part(path: body, fill: rgb(0xFFE066), stroke: rgb(0xC9A227), lineWidth: line * 0.5),
                    Part(path: comb, fill: rgb(0xE63946)),
                    Part(path: head, fill: rgb(0xFFE066), stroke: rgb(0xC9A227), lineWidth: line * 0.4),
                    Part(path: beak, fill: rgb(0xFF8A2B)),
                    Part(path: circle(p(right, -0.04, -0.2), s * 0.025), fill: ink)]

        case .snail:
            // A little pet snail on its left shoulder, as the parrot sits:
            // a spiral shell and two eye stalks up and looking about.
            let shoulder = f.anatomy == nil
                ? CGPoint(x: f.outline.minX + w * 0.1, y: f.outline.minY + f.outline.height * 0.24)
                : !f.separateBody ? CGPoint(x: cx - w * 0.22, y: top + f.outline.height * 0.08)
                : CGPoint(x: min(f.torso.minX + f.torso.width * 0.14, f.outline.minX + w * 0.06), y: f.torso.minY + w * 0.02)
            let body = CGMutablePath()
            body.move(to: p(shoulder, -0.28, 0.02))
            body.addQuadCurve(to: p(shoulder, 0.22, 0.02), control: p(shoulder, 0, -0.12))
            body.addLine(to: p(shoulder, 0.24, -0.06))
            body.addQuadCurve(to: p(shoulder, 0.12, -0.08), control: p(shoulder, 0.18, -0.14))
            body.addLine(to: p(shoulder, -0.28, 0.04))
            body.closeSubpath()
            let shellCenter = p(shoulder, -0.06, -0.16)
            let spiral = CGMutablePath()
            spiral.move(to: shellCenter)
            for k in 1...14 {
                let angle = Double(k) * 0.55
                let reach = s * 0.012 * CGFloat(k)
                spiral.addLine(to: CGPoint(x: shellCenter.x + CGFloat(cos(angle)) * reach,
                                           y: shellCenter.y + CGFloat(sin(angle)) * reach))
            }
            let stalks = CGMutablePath()
            stalks.move(to: p(shoulder, 0.18, -0.08)); stalks.addLine(to: p(shoulder, 0.22, -0.26))
            stalks.move(to: p(shoulder, 0.22, -0.07)); stalks.addLine(to: p(shoulder, 0.32, -0.22))
            let eyes = CGMutablePath()
            eyes.addPath(circle(p(shoulder, 0.22, -0.27), s * 0.03))
            eyes.addPath(circle(p(shoulder, 0.33, -0.23), s * 0.03))
            return [Part(path: body, fill: rgb(0xB8E0A0), stroke: rgb(0x5E8C46), lineWidth: line * 0.4),
                    Part(path: stalks, fill: nil, stroke: rgb(0x8DBB74), lineWidth: line * 0.4),
                    Part(path: eyes, fill: ink),
                    Part(path: circle(shellCenter, s * 0.18), fill: rgb(0xD9894A), stroke: rgb(0x7A4A1F), lineWidth: line * 0.4),
                    Part(path: spiral, fill: nil, stroke: rgb(0x7A4A1F), lineWidth: line * 0.4)]

        case .jesterHat:
            // A fool's cap of three floppy points, red and purple, a gold
            // bell on each tip.
            let band = CGRect(x: cx - w * 0.38, y: top - w * 0.02, width: w * 0.76, height: w * 0.13)
            let base = band.minY + w * 0.02
            func flap(_ from: CGFloat, _ to: CGFloat, tip: CGPoint, bend: CGPoint) -> CGPath {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx + from * w, y: base))
                path.addQuadCurve(to: tip, control: bend)
                path.addQuadCurve(to: CGPoint(x: cx + to * w, y: base),
                                  control: CGPoint(x: (tip.x + cx + to * w) / 2, y: (tip.y + base) / 2 + w * 0.04))
                path.closeSubpath()
                return path
            }
            let leftTip = CGPoint(x: cx - w * 0.52, y: top - w * 0.04)
            let middleTip = CGPoint(x: cx + w * 0.02, y: top - w * 0.46)
            let rightTip = CGPoint(x: cx + w * 0.54, y: top - w * 0.06)
            let left = flap(-0.36, -0.08, tip: leftTip, bend: CGPoint(x: cx - w * 0.36, y: top - w * 0.4))
            let middle = flap(-0.16, 0.16, tip: middleTip, bend: CGPoint(x: cx - w * 0.12, y: top - w * 0.3))
            let rightFlap = flap(0.08, 0.36, tip: rightTip, bend: CGPoint(x: cx + w * 0.36, y: top - w * 0.42))
            let bells = CGMutablePath()
            for tip in [leftTip, middleTip, rightTip] { bells.addPath(circle(tip, w * 0.065)) }
            return [Part(path: left, fill: rgb(0x7B2CBF), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rightFlap, fill: rgb(0x7B2CBF), stroke: ink, lineWidth: line * 0.4),
                    Part(path: middle, fill: rgb(0xE63946), stroke: ink, lineWidth: line * 0.4),
                    Part(path: rounded(band, w * 0.05), fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.4),
                    Part(path: bells, fill: rgb(0xFFD23F), stroke: rgb(0xB8860B), lineWidth: line * 0.4)]

        case .snorkelMask:
            // A diving mask over both eyes, the glass tinted blue, and the
            // snorkel running from its mouth up the side of its head.
            let r = min(max(f.size * 0.07, eyeGap * 0.46), w * 0.15)
            let lens = CGRect(x: min(f.leftEye.x, f.rightEye.x) - r, y: eyeY - r * 0.85,
                              width: eyeGap + r * 2, height: r * 1.7)
            let strap = stroke(CGPoint(x: f.outline.minX + w * 0.02, y: eyeY), CGPoint(x: f.outline.maxX - w * 0.02, y: eyeY))
            let mouth = f.mouthful
            let side = max(lens.maxX + r * 0.35, mouth.x + fs * 0.3)
            let tube = CGMutablePath()
            tube.move(to: CGPoint(x: mouth.x + fs * 0.06, y: mouth.y))
            tube.addQuadCurve(to: CGPoint(x: side, y: mouth.y - fs * 0.12), control: CGPoint(x: side, y: mouth.y + fs * 0.06))
            tube.addLine(to: CGPoint(x: side, y: top - w * 0.12))
            return [Part(path: strap, fill: nil, stroke: rgb(0x1D3557), lineWidth: line * 0.8),
                    Part(path: tube, fill: nil, stroke: ink, lineWidth: line * 1.5),
                    Part(path: tube, fill: nil, stroke: rgb(0xFF8C42), lineWidth: line * 0.9),
                    Part(path: circle(CGPoint(x: mouth.x + fs * 0.04, y: mouth.y), fs * 0.07), fill: rgb(0x1D3557)),
                    Part(path: rounded(lens, r * 0.6), fill: rgba(0x8ECAE6, 0.4), stroke: rgb(0x1D3557), lineWidth: line),
                    Part(path: stroke(CGPoint(x: lens.minX + r * 0.4, y: lens.minY + r * 0.35),
                                      CGPoint(x: lens.minX + r * 0.8, y: lens.minY + r * 0.35)),
                         fill: nil, stroke: rgba(0xFFFFFF, 0.8), lineWidth: line * 0.6)]

        case .pirateHook:
            // A silver hook out of a wooden cuff, curling up and out.
            let cuff = CGRect(x: right.x - s * 0.16, y: right.y - s * 0.04, width: s * 0.32, height: s * 0.24)
            let hook = CGMutablePath()
            hook.move(to: p(right, 0, -0.04))
            hook.addLine(to: p(right, 0, -0.34))
            hook.addQuadCurve(to: p(right, 0.3, -0.42), control: p(right, 0.04, -0.62))
            hook.addQuadCurve(to: p(right, 0.24, -0.26), control: p(right, 0.34, -0.32))
            return [Part(path: hook, fill: nil, stroke: ink, lineWidth: line * 1.3),
                    Part(path: hook, fill: nil, stroke: rgb(0xD8DCE4), lineWidth: line * 0.75),
                    Part(path: rounded(cuff, s * 0.06), fill: rgb(0x8B5A2B), stroke: ink, lineWidth: line * 0.5),
                    Part(path: stroke(CGPoint(x: cuff.minX, y: cuff.midY), CGPoint(x: cuff.maxX, y: cuff.midY)), fill: nil,
                         stroke: rgb(0xFFD23F), lineWidth: line * 0.5)]

        case .featherBoa:
            // A pink feather boa round its neck, one end flung over a
            // shoulder and the other hanging down its front.
            let y = f.neckY + w * 0.04
            let fluff = CGMutablePath()
            let tufts = CGMutablePath()
            let r = w * 0.062
            let half = w * 0.36
            var spine: [CGPoint] = []
            for k in 0...8 {
                let t = CGFloat(k) / 8
                spine.append(CGPoint(x: cx - half + t * half * 2, y: y + sin(t * .pi) * w * 0.05))
            }
            for k in 1...3 {
                let t = CGFloat(k) / 3
                spine.append(CGPoint(x: cx + w * 0.2 + sin(t * 2.4) * w * 0.06, y: y + t * w * 0.28))
            }
            for k in 1...2 {
                let t = CGFloat(k) / 2
                spine.append(CGPoint(x: cx - half - t * w * 0.08, y: y + t * t * w * 0.12))
            }
            for (index, point) in spine.enumerated() {
                fluff.addPath(circle(point, r * (index.isMultiple(of: 2) ? 1 : 0.9)))
                tufts.addPath(circle(CGPoint(x: point.x + r * 0.3, y: point.y - r * 0.3), r * 0.35))
            }
            return [Part(path: fluff, fill: rgb(0xFF6FB5), stroke: rgb(0xD94A93), lineWidth: line * 0.3),
                    Part(path: tufts, fill: rgb(0xFFB3DA))]

        case .rollerSkates:
            // A white roller boot on each foot, pink toe stop and laces,
            // two yellow wheels under each.
            let at = f.feet(spread: 0.21)
            let floor = f.floor, fu = f.feetUnit
            let boots = CGMutablePath()
            let laces = CGMutablePath()
            let stops = CGMutablePath()
            let wheels = CGMutablePath()
            for x in [at.left, at.right] {
                let boot = CGRect(x: x - fu * 0.17, y: floor - fu * 0.2, width: fu * 0.34, height: fu * 0.18)
                boots.addPath(rounded(boot, fu * 0.06))
                laces.move(to: CGPoint(x: boot.minX + fu * 0.08, y: boot.minY + fu * 0.05))
                laces.addLine(to: CGPoint(x: boot.minX + fu * 0.18, y: boot.minY + fu * 0.05))
                stops.addPath(circle(CGPoint(x: boot.maxX, y: boot.maxY - fu * 0.02), fu * 0.04))
                for dx in [-0.1, 0.1] as [CGFloat] {
                    wheels.addPath(circle(CGPoint(x: x + dx * fu, y: floor + fu * 0.03), fu * 0.05))
                }
            }
            return [Part(path: wheels, fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.4),
                    Part(path: boots, fill: rgb(0xF7F4EE), stroke: ink, lineWidth: line * 0.5),
                    Part(path: laces, fill: nil, stroke: rgb(0xFF6FB5), lineWidth: line * 0.6),
                    Part(path: stops, fill: rgb(0xFF6FB5), stroke: ink, lineWidth: line * 0.3)]

        case .lantern:
            // An old lantern hanging from its hand by the bail, a warm
            // flame glowing through the glass.
            let glass = CGRect(x: right.x - s * 0.16, y: right.y + s * 0.08, width: s * 0.32, height: s * 0.32)
            let bail = CGMutablePath()
            bail.move(to: p(right, -0.1, 0.04))
            bail.addQuadCurve(to: p(right, 0.1, 0.04), control: p(right, 0, -0.16))
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: glass.midX, y: glass.minY + s * 0.04))
            flame.addQuadCurve(to: CGPoint(x: glass.midX, y: glass.maxY - s * 0.05), control: CGPoint(x: glass.midX + s * 0.1, y: glass.midY + s * 0.04))
            flame.addQuadCurve(to: CGPoint(x: glass.midX, y: glass.minY + s * 0.04), control: CGPoint(x: glass.midX - s * 0.1, y: glass.midY + s * 0.04))
            return [Part(path: circle(CGPoint(x: glass.midX, y: glass.midY), s * 0.3), fill: rgba(0xFFD166, 0.22)),
                    Part(path: bail, fill: nil, stroke: rgb(0x3A3F4B), lineWidth: line * 0.6),
                    Part(path: rounded(glass, s * 0.04), fill: rgb(0xFFE8A3), stroke: rgb(0x3A3F4B), lineWidth: line * 0.5),
                    Part(path: flame, fill: rgb(0xFF8C42)),
                    Part(path: rounded(CGRect(x: glass.minX - s * 0.04, y: glass.minY - s * 0.06, width: glass.width + s * 0.08,
                                              height: s * 0.07), s * 0.03), fill: rgb(0x2B2D42)),
                    Part(path: rounded(CGRect(x: glass.minX - s * 0.04, y: glass.maxY - s * 0.01, width: glass.width + s * 0.08,
                                              height: s * 0.07), s * 0.03), fill: rgb(0x2B2D42))]

        case .wizardBeard:
            // A long white wizard's beard hung from its cheeks, under the
            // eyes, with a curling moustache over it.
            let mouth = f.mouthful
            let rise = max(mouth.y - fs * 0.08, eyeY + max(eyeGap * 0.42, f.size * 0.06))
            let half = min(max(fs * 0.36, eyeGap * 0.62), fs * 0.5)
            // Long, but never past its feet.
            let length = min(fs, max(fs * 0.5, f.floor - rise - fs * 0.1))
            let beard = CGMutablePath()
            beard.move(to: CGPoint(x: mouth.x - half, y: rise))
            beard.addQuadCurve(to: CGPoint(x: mouth.x + fs * 0.04, y: rise + length),
                               control: CGPoint(x: mouth.x - half * 0.9, y: rise + length * 0.7))
            beard.addQuadCurve(to: CGPoint(x: mouth.x + half, y: rise), control: CGPoint(x: mouth.x + half * 0.8, y: rise + length * 0.6))
            beard.addQuadCurve(to: CGPoint(x: mouth.x - half, y: rise), control: CGPoint(x: mouth.x, y: rise + fs * 0.24))
            let waves = CGMutablePath()
            for dx in [-0.16, 0.0, 0.16] as [CGFloat] {
                waves.move(to: CGPoint(x: mouth.x + dx * fs, y: rise + fs * 0.3))
                waves.addQuadCurve(to: CGPoint(x: mouth.x + dx * fs * 0.6, y: rise + length * 0.7),
                                   control: CGPoint(x: mouth.x + dx * fs + fs * 0.06, y: rise + fs * 0.5))
            }
            let stache = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                stache.move(to: CGPoint(x: mouth.x, y: rise + fs * 0.1))
                stache.addQuadCurve(to: CGPoint(x: mouth.x + side * half * 0.95, y: rise + fs * 0.06),
                                    control: CGPoint(x: mouth.x + side * half * 0.5, y: rise + fs * 0.26))
            }
            return [Part(path: beard, fill: rgb(0xF4F4F6), stroke: rgb(0xA9AEBB), lineWidth: line * 0.5),
                    Part(path: waves, fill: nil, stroke: rgb(0xC9CDD6), lineWidth: line * 0.4),
                    Part(path: stache, fill: nil, stroke: rgb(0xD9DCE3), lineWidth: line * 1.1)]

        case .beeHalo:
            // A ring of bees circling over its head, striped and winged,
            // on a faint trail of where they flew.
            let ring = CGRect(x: cx - w * 0.36, y: top - w * 0.3, width: w * 0.72, height: w * 0.18)
            let bodies = CGMutablePath()
            let stripes = CGMutablePath()
            let wings = CGMutablePath()
            let b = w * 0.075
            for k in 0..<5 {
                let angle = Double(k) / 5 * 2 * .pi + 0.4
                let c = CGPoint(x: ring.midX + CGFloat(cos(angle)) * ring.width / 2,
                                y: ring.midY + CGFloat(sin(angle)) * ring.height / 2)
                bodies.addPath(ellipse(c, b, b * 0.72))
                stripes.move(to: CGPoint(x: c.x - b * 0.2, y: c.y - b * 0.6)); stripes.addLine(to: CGPoint(x: c.x - b * 0.2, y: c.y + b * 0.6))
                stripes.move(to: CGPoint(x: c.x + b * 0.3, y: c.y - b * 0.55)); stripes.addLine(to: CGPoint(x: c.x + b * 0.3, y: c.y + b * 0.55))
                wings.addPath(ellipse(CGPoint(x: c.x - b * 0.2, y: c.y - b * 0.9), b * 0.42, b * 0.32))
                wings.addPath(ellipse(CGPoint(x: c.x + b * 0.3, y: c.y - b * 0.95), b * 0.42, b * 0.32))
            }
            return [Part(path: CGPath(ellipseIn: ring, transform: nil), fill: nil, stroke: rgba(0xFFE066, 0.45),
                         lineWidth: line * 0.5),
                    Part(path: wings, fill: rgba(0xFFFFFF, 0.85), stroke: rgb(0x9FB4C7), lineWidth: line * 0.25),
                    Part(path: bodies, fill: rgb(0xFFD23F), stroke: ink, lineWidth: line * 0.35),
                    Part(path: stripes, fill: nil, stroke: ink, lineWidth: line * 0.45)]

        case .spiderMonocle:
            // A magnifying monocle on its right eye, the lens tinted, and a
            // little spider let down from its rim on a silk thread.
            let r = min(max(f.size * 0.07, eyeGap * 0.44), w * 0.15)
            let eye = f.rightEye
            let anchor = CGPoint(x: eye.x + r * 0.9, y: eye.y + r * 0.4)
            let spider = CGPoint(x: eye.x + r * 1.5, y: eye.y + r * 2.1)
            let legs = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                for k in 0..<4 {
                    let dy = (CGFloat(k) - 1.5) * r * 0.16
                    legs.move(to: CGPoint(x: spider.x, y: spider.y + dy))
                    legs.addQuadCurve(to: CGPoint(x: spider.x + side * r * 0.5, y: spider.y + dy + r * 0.14),
                                      control: CGPoint(x: spider.x + side * r * 0.32, y: spider.y + dy - r * 0.2))
                }
            }
            return [Part(path: circle(eye, r * 1.05), fill: rgba(0xBDE0FE, 0.3), stroke: rgb(0xD9A82E), lineWidth: line * 1.1),
                    Part(path: stroke(CGPoint(x: eye.x - r * 0.5, y: eye.y - r * 0.5), CGPoint(x: eye.x - r * 0.2, y: eye.y - r * 0.7)),
                         fill: nil, stroke: rgba(0xFFFFFF, 0.8), lineWidth: line * 0.5),
                    Part(path: stroke(anchor, spider), fill: nil, stroke: rgba(0xFFFFFF, 0.75), lineWidth: line * 0.3),
                    Part(path: legs, fill: nil, stroke: ink, lineWidth: line * 0.35),
                    Part(path: circle(spider, r * 0.26), fill: rgb(0x2B2D42), stroke: ink, lineWidth: line * 0.3),
                    Part(path: circle(CGPoint(x: spider.x, y: spider.y - r * 0.28), r * 0.15), fill: rgb(0x2B2D42)),
                    Part(path: circle(CGPoint(x: spider.x, y: spider.y + r * 0.04), r * 0.08), fill: rgb(0xE63946))]

        case .ufoHat:
            // A tiny flying saucer hovering over its head, lights round its
            // rim and a pale green beam down onto it.
            let saucer = CGPoint(x: cx, y: top - w * 0.24)
            let beam = poly([CGPoint(x: saucer.x - w * 0.12, y: saucer.y + w * 0.05),
                             CGPoint(x: saucer.x + w * 0.12, y: saucer.y + w * 0.05),
                             CGPoint(x: cx + w * 0.3, y: top + w * 0.08), CGPoint(x: cx - w * 0.3, y: top + w * 0.08)])
            let lights = CGMutablePath()
            for dx in [-0.2, -0.07, 0.07, 0.2] as [CGFloat] {
                lights.addPath(circle(CGPoint(x: saucer.x + dx * w, y: saucer.y + w * 0.015), w * 0.025))
            }
            return [Part(path: beam, fill: rgba(0xA8FF9E, 0.3)),
                    Part(path: ellipse(CGPoint(x: saucer.x, y: saucer.y - w * 0.06), w * 0.13, w * 0.1), fill: rgba(0x9EF0FF, 0.85),
                         stroke: ink, lineWidth: line * 0.4),
                    Part(path: ellipse(saucer, w * 0.3, w * 0.075), fill: rgb(0xB8C0CC), stroke: ink, lineWidth: line * 0.5),
                    Part(path: lights, fill: rgb(0xA8FF9E))]

        default:
            return []
        }
    }
}
