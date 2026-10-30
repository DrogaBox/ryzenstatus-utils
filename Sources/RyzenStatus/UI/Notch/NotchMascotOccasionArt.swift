// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What the companion's own moments draw into the clear layer over the
/// screen: thought bubbles, a fishing rod, a turbo fan, a plug sign, a rosin
/// box, and the days of the year. Each one draws itself and takes itself
/// away. Points are the layer's own, y up.
enum NotchMascotOccasionArt {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        NotchMascotRPGShapes.rgb(hex).copy(alpha: alpha) ?? NotchMascotRPGShapes.rgb(hex)
    }

    private static func shape(_ path: CGPath, fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }

    private static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    private static func holder(at point: CGPoint) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.anchorPoint = .zero
        layer.position = point
        return layer
    }

    private static func keyframes(_ keyPath: String, _ values: [Any], times: [NSNumber]? = nil,
                                  duration: TimeInterval, repeats: Float = 1) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.repeatCount = repeats
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Fades `layer` in and out over `duration` and takes it away after.
    private static func show(_ layer: CALayer, in parent: CALayer, for duration: TimeInterval) {
        layer.opacity = 0
        layer.add(keyframes("opacity", [0, 1, 1, 0], times: [0, NSNumber(value: min(0.2, 0.25 / duration)),
                                                              NSNumber(value: max(0.8, 1 - 0.35 / duration)), 1],
                            duration: duration), forKey: "show")
        parent.addSublayer(layer)
        NotchMascotPlayEffects.remove(layer, after: duration + 0.1)
    }

    // MARK: Thought bubbles

    /// What a thought bubble shows.
    enum Icon: Equatable {
        case craving(NotchMascotCraving)
        case roshambo(NotchMascotRoshambo)
    }

    /// A thought bubble `size` across over `head`, with `icon` in it, for
    /// `duration`, bobbing a little.
    static func thought(in parent: CALayer, over head: CGPoint, size: CGFloat, icon: Icon, duration: TimeInterval) {
        let bubble = holder(at: CGPoint(x: head.x + size * 0.35, y: head.y + size * 0.55))
        let cloud = CGMutablePath()
        for (dx, dy, r) in [(-0.28, 0.0, 0.3), (0.0, 0.12, 0.34), (0.28, 0.0, 0.3), (0.0, -0.12, 0.3)] as [(CGFloat, CGFloat, CGFloat)] {
            cloud.addPath(ellipse(CGPoint(x: dx * size, y: dy * size), r * size, r * size * 0.9))
        }
        bubble.addSublayer(shape(cloud, fill: rgb(0xFFFFFF, 0.96), stroke: rgb(0x90A4AE), width: 1))
        bubble.addSublayer(shape(ellipse(CGPoint(x: -size * 0.32, y: -size * 0.42), size * 0.07, size * 0.07),
                                 fill: rgb(0xFFFFFF, 0.96), stroke: rgb(0x90A4AE), width: 1))
        bubble.addSublayer(shape(ellipse(CGPoint(x: -size * 0.42, y: -size * 0.56), size * 0.04, size * 0.04),
                                 fill: rgb(0xFFFFFF, 0.96), stroke: rgb(0x90A4AE), width: 1))
        for part in drawing(icon, side: size * 0.5) { bubble.addSublayer(part) }
        bubble.add(keyframes("transform.translation.y", [0, size * 0.05, 0], duration: 1.2, repeats: .infinity), forKey: "bob")
        show(bubble, in: parent, for: duration)
    }

    /// `icon` drawn in a square of `side` round the origin.
    private static func drawing(_ icon: Icon, side s: CGFloat) -> [CALayer] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        switch icon {
        case .craving(.coffee):
            let mug = CGPath(roundedRect: CGRect(x: -0.3 * s, y: -0.35 * s, width: 0.5 * s, height: 0.55 * s),
                             cornerWidth: 0.06 * s, cornerHeight: 0.06 * s, transform: nil)
            let handle = CGMutablePath()
            handle.addArc(center: p(0.22, -0.08), radius: 0.12 * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            let steam = CGMutablePath()
            steam.move(to: p(-0.1, 0.28))
            steam.addQuadCurve(to: p(-0.1, 0.5), control: p(0.02, 0.4))
            return [shape(handle, fill: nil, stroke: rgb(0x6D4C41), width: 0.07 * s),
                    shape(mug, fill: rgb(0xFAFAFA), stroke: rgb(0x6D4C41), width: 1.2),
                    shape(ellipse(p(-0.05, 0.16), 0.22 * s, 0.05 * s), fill: rgb(0x5D4037)),
                    shape(steam, fill: nil, stroke: rgb(0xB0BEC5), width: 1.5)]
        case .craving(.pizza):
            let slice = CGMutablePath()
            slice.move(to: p(0, -0.42))
            slice.addLine(to: p(0.36, 0.3))
            slice.addQuadCurve(to: p(-0.36, 0.3), control: p(0, 0.45))
            slice.closeSubpath()
            let crust = CGMutablePath()
            crust.move(to: p(0.36, 0.3))
            crust.addQuadCurve(to: p(-0.36, 0.3), control: p(0, 0.45))
            let pepperoni = CGMutablePath()
            for (x, y) in [(-0.1, 0.12), (0.12, 0.15), (0.0, -0.12)] as [(CGFloat, CGFloat)] {
                pepperoni.addPath(ellipse(p(x, y), 0.07 * s, 0.07 * s))
            }
            return [shape(slice, fill: rgb(0xFFCA28), stroke: rgb(0xE65100), width: 1),
                    shape(crust, fill: nil, stroke: rgb(0xB26A00), width: 0.08 * s),
                    shape(pepperoni, fill: rgb(0xD32F2F))]
        case .craving(.ramen):
            let bowl = CGMutablePath()
            bowl.move(to: p(-0.42, 0.02))
            bowl.addLine(to: p(0.42, 0.02))
            bowl.addQuadCurve(to: p(-0.42, 0.02), control: p(0, -0.6))
            let noodles = CGMutablePath()
            for x in [-0.2, 0.0, 0.2] as [CGFloat] {
                noodles.move(to: p(x, 0.02))
                noodles.addQuadCurve(to: p(x + 0.05, 0.38), control: p(x + 0.12, 0.2))
            }
            return [shape(noodles, fill: nil, stroke: rgb(0xFFE082), width: 1.6),
                    shape(bowl, fill: rgb(0xE53935), stroke: rgb(0x8E0000), width: 1),
                    shape(ellipse(p(0, 0.02), 0.42 * s, 0.06 * s), fill: rgb(0xFFB74D))]
        case .craving(.iceCream):
            let cone = CGMutablePath()
            cone.move(to: p(-0.2, 0))
            cone.addLine(to: p(0.2, 0))
            cone.addLine(to: p(0, -0.45))
            cone.closeSubpath()
            return [shape(cone, fill: rgb(0xD7A15A), stroke: rgb(0x8D5A1E), width: 1),
                    shape(ellipse(p(0, 0.14), 0.24 * s, 0.2 * s), fill: rgb(0xF8BBD0), stroke: rgb(0xC2185B), width: 1),
                    shape(ellipse(p(0.02, 0.36), 0.06 * s, 0.06 * s), fill: rgb(0xD32F2F))]
        case .craving(.moon):
            let moon = CGMutablePath()
            moon.addArc(center: .zero, radius: 0.32 * s, startAngle: .pi * 0.35, endAngle: .pi * 1.65, clockwise: false)
            moon.addArc(center: p(0.14, 0), radius: 0.26 * s, startAngle: .pi * 1.55, endAngle: .pi * 0.45, clockwise: true)
            moon.closeSubpath()
            let stars = CGMutablePath()
            for (x, y) in [(0.32, 0.3), (0.38, -0.2)] as [(CGFloat, CGFloat)] {
                stars.addPath(ellipse(p(x, y), 0.04 * s, 0.04 * s))
            }
            return [shape(moon, fill: rgb(0xFFE082), stroke: rgb(0xF9A825), width: 1), shape(stars, fill: rgb(0xFFD54F))]
        case .craving(.ball):
            let seam = CGMutablePath()
            seam.move(to: p(-0.3, 0.18))
            seam.addQuadCurve(to: p(0.3, 0.18), control: p(0, -0.1))
            seam.move(to: p(-0.3, -0.18))
            seam.addQuadCurve(to: p(0.3, -0.18), control: p(0, 0.1))
            return [shape(ellipse(.zero, 0.34 * s, 0.34 * s), fill: rgb(0xCDDC39), stroke: rgb(0x827717), width: 1),
                    shape(seam, fill: nil, stroke: rgb(0xFFFFFF), width: 1.4)]
        case .roshambo(.rock):
            let rock = CGMutablePath()
            rock.move(to: p(-0.38, -0.25))
            rock.addLine(to: p(-0.3, 0.12))
            rock.addLine(to: p(-0.05, 0.32))
            rock.addLine(to: p(0.28, 0.22))
            rock.addLine(to: p(0.4, -0.12))
            rock.addLine(to: p(0.2, -0.3))
            rock.closeSubpath()
            let crack = CGMutablePath()
            crack.move(to: p(-0.05, 0.2))
            crack.addLine(to: p(0.02, 0.0))
            crack.addLine(to: p(-0.08, -0.12))
            return [shape(rock, fill: rgb(0x9E9E9E), stroke: rgb(0x424242), width: 1.2),
                    shape(crack, fill: nil, stroke: rgb(0x616161), width: 1)]
        case .roshambo(.paper):
            let sheet = CGMutablePath()
            sheet.move(to: p(-0.28, -0.38))
            sheet.addLine(to: p(0.28, -0.38))
            sheet.addLine(to: p(0.28, 0.24))
            sheet.addLine(to: p(0.14, 0.38))
            sheet.addLine(to: p(-0.28, 0.38))
            sheet.closeSubpath()
            let lines = CGMutablePath()
            for y in [0.18, 0.02, -0.14, -0.28] as [CGFloat] {
                lines.move(to: p(-0.18, y))
                lines.addLine(to: p(0.18, y))
            }
            return [shape(sheet, fill: rgb(0xFFFDE7), stroke: rgb(0x8D6E63), width: 1.2),
                    shape(lines, fill: nil, stroke: rgb(0x90CAF9), width: 1)]
        case .roshambo(.scissors):
            let blades = CGMutablePath()
            blades.move(to: p(-0.05, -0.05))
            blades.addLine(to: p(0.4, 0.38))
            blades.move(to: p(0.05, -0.05))
            blades.addLine(to: p(-0.4, 0.38))
            let rings = CGMutablePath()
            rings.addPath(ellipse(p(-0.18, -0.26), 0.12 * s, 0.12 * s))
            rings.addPath(ellipse(p(0.18, -0.26), 0.12 * s, 0.12 * s))
            return [shape(blades, fill: nil, stroke: rgb(0x90A4AE), width: 0.09 * s),
                    shape(rings, fill: nil, stroke: rgb(0xE53935), width: 0.07 * s)]
        }
    }

    // MARK: Fishing

    /// A rod held at `hand` reaching out toward `way`, its line hanging to a
    /// bobber at `water`, for `duration`; the bobber bobs, and at `biteAt`
    /// seconds the rod bends and the bobber dips until `pullAt`.
    static func rod(in parent: CALayer, hand: CGPoint, way: CGFloat, water: CGFloat, size: CGFloat,
                    duration: TimeInterval, biteAt: TimeInterval, pullAt: TimeInterval) {
        let rig = holder(at: hand)
        let tip = CGPoint(x: way * size * 1.3, y: size * 0.9)
        let pole = CGMutablePath()
        pole.move(to: .zero)
        pole.addQuadCurve(to: tip, control: CGPoint(x: way * size * 0.7, y: size * 0.75))
        let rodLayer = shape(pole, fill: nil, stroke: rgb(0xC8A26B), width: max(2, size * 0.05))
        let bent = CGMutablePath()
        bent.move(to: .zero)
        bent.addQuadCurve(to: CGPoint(x: tip.x * 0.95, y: tip.y * 0.55), control: CGPoint(x: way * size * 0.9, y: size * 0.9))
        let bend = keyframes("path", [pole, pole, bent, bent, pole], times: [0, NSNumber(value: biteAt / duration),
                                                                          NSNumber(value: (biteAt + 0.1) / duration),
                                                                          NSNumber(value: pullAt / duration),
                                                                          NSNumber(value: min(1, (pullAt + 0.2) / duration))],
                             duration: duration)
        rodLayer.add(bend, forKey: "bend")
        let bobberAt = CGPoint(x: tip.x + way * size * 0.3, y: water - hand.y)
        let line = CGMutablePath()
        line.move(to: tip)
        line.addLine(to: bobberAt)
        let tight = CGMutablePath()
        tight.move(to: CGPoint(x: tip.x * 0.95, y: tip.y * 0.55))
        tight.addLine(to: CGPoint(x: bobberAt.x, y: bobberAt.y - size * 0.15))
        let lineLayer = shape(line, fill: nil, stroke: rgb(0xECEFF1, 0.9), width: 1)
        lineLayer.add(keyframes("path", [line, line, tight, tight, line], times: bend.keyTimes, duration: duration), forKey: "pull")
        let bobber = holder(at: bobberAt)
        bobber.addSublayer(shape(ellipse(.zero, size * 0.08, size * 0.08), fill: rgb(0xFFFFFF), stroke: rgb(0x424242), width: 0.8))
        let top = CGMutablePath()
        top.addArc(center: .zero, radius: size * 0.08, startAngle: 0, endAngle: .pi, clockwise: false)
        top.closeSubpath()
        bobber.addSublayer(shape(top, fill: rgb(0xE53935)))
        let dip = keyframes("position", [bobberAt, bobberAt, CGPoint(x: bobberAt.x, y: bobberAt.y - size * 0.15),
                                         CGPoint(x: bobberAt.x, y: bobberAt.y - size * 0.15), bobberAt].map { NSValue(point: $0) },
                            times: bend.keyTimes, duration: duration)
        bobber.add(dip, forKey: "dip")
        let bob = keyframes("transform.translation.y", [0, size * 0.03, 0], duration: 1.1, repeats: Float(biteAt / 1.1))
        bob.isAdditive = true
        bobber.add(bob, forKey: "bob")
        rig.addSublayer(lineLayer)
        rig.addSublayer(rodLayer)
        rig.addSublayer(bobber)
        show(rig, in: parent, for: duration)
    }

    /// What it pulls out, flying from `from` up over `head` and held there.
    static func caught(_ thing: NotchMascotCatch, in parent: CALayer, from: CGPoint, head: CGPoint, size: CGFloat) {
        let item = holder(at: head)
        let s = size
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        switch thing {
        case .goldfish:
            let tail = CGMutablePath()
            tail.move(to: p(-0.25, 0))
            tail.addLine(to: p(-0.5, 0.18))
            tail.addLine(to: p(-0.5, -0.18))
            tail.closeSubpath()
            item.addSublayer(shape(tail, fill: rgb(0xFF8F00), stroke: rgb(0xE65100), width: 1))
            item.addSublayer(shape(ellipse(.zero, 0.32 * s, 0.2 * s), fill: rgb(0xFFB300), stroke: rgb(0xE65100), width: 1))
            item.addSublayer(shape(ellipse(p(0.16, 0.05), 0.04 * s, 0.04 * s), fill: rgb(0x212121)))
        case .boot:
            let boot = CGMutablePath()
            boot.move(to: p(-0.15, 0.4))
            boot.addLine(to: p(0.12, 0.4))
            boot.addLine(to: p(0.12, -0.05))
            boot.addLine(to: p(0.42, -0.12))
            boot.addLine(to: p(0.42, -0.32))
            boot.addLine(to: p(-0.15, -0.32))
            boot.closeSubpath()
            item.addSublayer(shape(boot, fill: rgb(0x6D4C41), stroke: rgb(0x3E2723), width: 1.2))
            let drip = shape(ellipse(p(0.3, -0.45), 0.04 * s, 0.06 * s), fill: rgb(0x4FC3F7))
            drip.add(keyframes("transform.translation.y", [0, -s * 0.3], duration: 0.6, repeats: 4), forKey: "drip")
            item.addSublayer(drip)
        case .key:
            let key = CGMutablePath()
            key.addPath(ellipse(p(-0.25, 0), 0.14 * s, 0.14 * s))
            key.move(to: p(-0.11, 0))
            key.addLine(to: p(0.4, 0))
            key.move(to: p(0.3, 0))
            key.addLine(to: p(0.3, -0.12))
            key.move(to: p(0.38, 0))
            key.addLine(to: p(0.38, -0.1))
            item.addSublayer(shape(key, fill: nil, stroke: rgb(0xFFC107), width: 0.08 * s))
        case .pearl:
            item.addSublayer(shape(ellipse(.zero, 0.2 * s, 0.2 * s), fill: rgb(0xFAFAFA), stroke: rgb(0xCFD8DC), width: 1))
            item.addSublayer(shape(ellipse(p(-0.06, 0.07), 0.06 * s, 0.06 * s), fill: rgb(0xFFFFFF)))
            item.shadowColor = rgb(0xE1F5FE)
            item.shadowOpacity = 1
            item.shadowRadius = 6
            item.shadowOffset = .zero
        }
        let over = CGPoint(x: head.x, y: head.y + s * 0.6)
        let arc = keyframes("position", [from, CGPoint(x: (from.x + over.x) / 2, y: max(from.y, over.y) + s * 1.5), over]
                                .map { NSValue(point: $0) }, duration: 0.6)
        arc.calculationMode = .cubic
        item.position = over
        item.add(arc, forKey: "arc")
        show(item, in: parent, for: 3.2)
    }

    // MARK: The Mac's moments

    /// A little turbo fan at `point`, `size` across, spinning flat out.
    static func turboFan(in parent: CALayer, at point: CGPoint, size: CGFloat, duration: TimeInterval) {
        let fan = holder(at: point)
        fan.addSublayer(shape(ellipse(.zero, size / 2, size / 2), fill: rgb(0x263238), stroke: rgb(0x90A4AE), width: 1.5))
        let blades = holder(at: .zero)
        for index in 0..<5 {
            let blade = CGMutablePath()
            blade.move(to: .zero)
            blade.addQuadCurve(to: CGPoint(x: size * 0.42, y: size * 0.12), control: CGPoint(x: size * 0.22, y: size * 0.24))
            blade.addQuadCurve(to: .zero, control: CGPoint(x: size * 0.26, y: -size * 0.02))
            let layer = shape(blade, fill: rgb(0x4FC3F7, 0.9))
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(index) * 2 * .pi / 5))
            blades.addSublayer(layer)
        }
        blades.add(keyframes("transform.rotation.z", [0, -2 * CGFloat.pi], duration: 0.18, repeats: .infinity), forKey: "spin")
        fan.addSublayer(blades)
        fan.addSublayer(shape(ellipse(.zero, size * 0.08, size * 0.08), fill: rgb(0xFFD54F)))
        show(fan, in: parent, for: duration)
    }

    /// A sign held up at `point` with a plug that blinks, `size` tall.
    static func plugSign(in parent: CALayer, at point: CGPoint, size: CGFloat, duration: TimeInterval) {
        let sign = holder(at: point)
        let stick = CGMutablePath()
        stick.move(to: .zero)
        stick.addLine(to: CGPoint(x: 0, y: size * 0.6))
        sign.addSublayer(shape(stick, fill: nil, stroke: rgb(0x8D6E63), width: 2))
        sign.addSublayer(shape(CGPath(roundedRect: CGRect(x: -size * 0.4, y: size * 0.55, width: size * 0.8, height: size * 0.5),
                                      cornerWidth: 4, cornerHeight: 4, transform: nil),
                               fill: rgb(0xFFF8E1), stroke: rgb(0x8D6E63), width: 1.5))
        let plug = CGMutablePath()
        plug.addRect(CGRect(x: -size * 0.12, y: size * 0.68, width: size * 0.24, height: size * 0.16))
        plug.move(to: CGPoint(x: -size * 0.06, y: size * 0.84))
        plug.addLine(to: CGPoint(x: -size * 0.06, y: size * 0.95))
        plug.move(to: CGPoint(x: size * 0.06, y: size * 0.84))
        plug.addLine(to: CGPoint(x: size * 0.06, y: size * 0.95))
        plug.move(to: CGPoint(x: 0, y: size * 0.68))
        plug.addLine(to: CGPoint(x: 0, y: size * 0.6))
        let plugLayer = shape(plug, fill: rgb(0xE53935), stroke: rgb(0xB71C1C), width: 1.5)
        plugLayer.add(keyframes("opacity", [1, 0.15, 1], duration: 0.8, repeats: .infinity), forKey: "blink")
        sign.addSublayer(plugLayer)
        sign.add(keyframes("transform.rotation.z", [-0.06, 0.06, -0.06], duration: 1.4, repeats: .infinity), forKey: "wave")
        show(sign, in: parent, for: duration)
    }

    /// A beach towel laid along `floor` under it, from `left` `width` wide,
    /// with the sun beating down over it.
    static func beach(in parent: CALayer, left: CGFloat, floor: CGFloat, width: CGFloat, sunAt: CGPoint, duration: TimeInterval) {
        let towel = holder(at: CGPoint(x: left, y: floor))
        let stripes = max(3, Int(width / 14))
        for index in 0..<stripes {
            let stripe = CALayer()
            stripe.frame = CGRect(x: CGFloat(index) * width / CGFloat(stripes), y: -3, width: width / CGFloat(stripes) + 0.5, height: 6)
            stripe.backgroundColor = index.isMultiple(of: 2) ? rgb(0xFF7043) : rgb(0xFFFFFF)
            towel.addSublayer(stripe)
        }
        show(towel, in: parent, for: duration)
        let sun = holder(at: sunAt)
        let rays = CGMutablePath()
        for index in 0..<10 {
            let angle = CGFloat(index) / 10 * 2 * .pi
            rays.move(to: CGPoint(x: cos(angle) * 22, y: sin(angle) * 22))
            rays.addLine(to: CGPoint(x: cos(angle) * 32, y: sin(angle) * 32))
        }
        let rayLayer = shape(rays, fill: nil, stroke: rgb(0xFFB300), width: 2.5)
        rayLayer.add(keyframes("transform.rotation.z", [0, CGFloat.pi * 2], duration: 12, repeats: .infinity), forKey: "turn")
        sun.addSublayer(rayLayer)
        let disc = shape(ellipse(.zero, 17, 17), fill: rgb(0xFFD54F))
        disc.shadowColor = rgb(0xFFB300)
        disc.shadowOpacity = 1
        disc.shadowRadius = 12
        disc.shadowOffset = .zero
        sun.addSublayer(disc)
        show(sun, in: parent, for: duration)
    }

    // MARK: Dancing

    /// A low wooden box of amber rosin on `floor` at `x`.
    static func rosinBox(in parent: CALayer, x: CGFloat, floor: CGFloat, size: CGFloat, duration: TimeInterval) {
        let box = holder(at: CGPoint(x: x, y: floor))
        box.addSublayer(shape(CGPath(rect: CGRect(x: -size / 2, y: 0, width: size, height: size * 0.3), transform: nil),
                              fill: rgb(0xA1887F), stroke: rgb(0x5D4037), width: 1.5))
        let crystals = CGMutablePath()
        for index in 0..<7 {
            let cx = -size * 0.4 + CGFloat(index) * size * 0.13
            crystals.addPath(ellipse(CGPoint(x: cx, y: size * 0.3), size * 0.06, size * 0.045))
        }
        box.addSublayer(shape(crystals, fill: rgb(0xFFB300, 0.9), stroke: rgb(0xE65100), width: 0.6))
        show(box, in: parent, for: duration)
    }

    /// A little white footprint of rosin at `point`, fading over `duration`.
    static func footprint(in parent: CALayer, at point: CGPoint, size: CGFloat, duration: TimeInterval) {
        let print = shape(ellipse(point, size * 0.09, size * 0.04), fill: rgb(0xFFFFFF, 0.75))
        print.add(keyframes("opacity", [0.9, 0], duration: duration), forKey: "fade")
        parent.addSublayer(print)
        NotchMascotPlayEffects.remove(print, after: duration + 0.1)
    }

    // MARK: The days of the year

    /// Bats flapping across `area` over `duration`.
    static func bats(in parent: CALayer, area: CGRect, count: Int, duration: TimeInterval) {
        for index in 0..<count {
            let bat = holder(at: .zero)
            let s = CGFloat.random(in: 18...30)
            let wing = CGMutablePath()
            wing.move(to: .zero)
            wing.addQuadCurve(to: CGPoint(x: s * 0.6, y: s * 0.2), control: CGPoint(x: s * 0.3, y: s * 0.35))
            wing.addLine(to: CGPoint(x: s * 0.45, y: 0))
            wing.addLine(to: CGPoint(x: s * 0.3, y: s * 0.08))
            wing.closeSubpath()
            let right = shape(wing, fill: rgb(0x212121))
            let left = shape(wing, fill: rgb(0x212121))
            left.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            for side in [right, left] {
                side.add(keyframes("transform.scale.y", [1, -0.5, 1], duration: 0.25, repeats: .infinity), forKey: "flap")
                bat.addSublayer(side)
            }
            bat.addSublayer(shape(ellipse(.zero, s * 0.12, s * 0.15), fill: rgb(0x212121)))
            let fromLeft = index.isMultiple(of: 2)
            let y = area.minY + area.height * CGFloat.random(in: 0.4...0.9)
            var stops: [NSValue] = []
            for step in 0...6 {
                let t = CGFloat(step) / 6
                let x = fromLeft ? area.minX - 40 + (area.width + 80) * t : area.maxX + 40 - (area.width + 80) * t
                stops.append(NSValue(point: CGPoint(x: x, y: y + sin(t * .pi * 3) * 40)))
            }
            let fly = keyframes("position", stops, duration: duration * Double.random(in: 0.7...1))
            fly.calculationMode = .cubic
            fly.beginTime = CACurrentMediaTime() + Double(index) * 0.6
            bat.position = CGPoint(x: -500, y: -500)
            bat.add(fly, forKey: "fly")
            parent.addSublayer(bat)
            NotchMascotPlayEffects.remove(bat, after: duration + Double(index) * 0.6 + 0.1)
        }
    }

    /// A glowing jack-o'-lantern on `floor` at `x`.
    static func pumpkin(in parent: CALayer, x: CGFloat, floor: CGFloat, size: CGFloat, duration: TimeInterval) {
        let pumpkin = holder(at: CGPoint(x: x, y: floor))
        pumpkin.addSublayer(shape(ellipse(CGPoint(x: 0, y: size * 0.38), size * 0.5, size * 0.38), fill: rgb(0xFB8C00),
                                  stroke: rgb(0xBF360C), width: 1.5))
        let stem = CGMutablePath()
        stem.addRect(CGRect(x: -size * 0.05, y: size * 0.72, width: size * 0.1, height: size * 0.14))
        pumpkin.addSublayer(shape(stem, fill: rgb(0x558B2F)))
        let face = CGMutablePath()
        for x in [-0.2, 0.2] as [CGFloat] {
            face.move(to: CGPoint(x: x * size - size * 0.08, y: size * 0.42))
            face.addLine(to: CGPoint(x: x * size + size * 0.08, y: size * 0.42))
            face.addLine(to: CGPoint(x: x * size, y: size * 0.56))
            face.closeSubpath()
        }
        face.move(to: CGPoint(x: -size * 0.28, y: size * 0.26))
        face.addQuadCurve(to: CGPoint(x: size * 0.28, y: size * 0.26), control: CGPoint(x: 0, y: size * 0.1))
        face.closeSubpath()
        let glow = shape(face, fill: rgb(0xFFEB3B))
        glow.shadowColor = rgb(0xFFC107)
        glow.shadowOpacity = 1
        glow.shadowRadius = 5
        glow.shadowOffset = .zero
        glow.add(keyframes("opacity", [1, 0.6, 1, 0.8, 1], duration: 1.3, repeats: .infinity), forKey: "flicker")
        pumpkin.addSublayer(glow)
        show(pumpkin, in: parent, for: duration)
    }

    /// Snow falling softly over `area` for `duration`.
    static func snow(in parent: CALayer, area: CGRect, count: Int, duration: TimeInterval) {
        for _ in 0..<count {
            let r = CGFloat.random(in: 1.5...3.5)
            let flake = shape(ellipse(.zero, r, r), fill: rgb(0xFFFFFF, 0.9))
            let x = CGFloat.random(in: area.minX...area.maxX)
            let fall = TimeInterval.random(in: 5...9)
            let drift = CGFloat.random(in: -40...40)
            let move = keyframes("position", [CGPoint(x: x, y: area.maxY + 10), CGPoint(x: x + drift, y: area.midY),
                                              CGPoint(x: x - drift, y: area.minY)].map { NSValue(point: $0) },
                                 duration: fall, repeats: Float(max(1, duration / fall)))
            move.calculationMode = .cubic
            move.beginTime = CACurrentMediaTime() + TimeInterval.random(in: 0...fall)
            flake.position = CGPoint(x: -100, y: -100)
            flake.add(move, forKey: "fall")
            parent.addSublayer(flake)
            NotchMascotPlayEffects.remove(flake, after: duration + fall)
        }
    }

    /// Fireworks bursting over `area` for `duration`.
    static func fireworks(in parent: CALayer, area: CGRect, duration: TimeInterval) {
        let colors: [UInt32] = [0xFF5252, 0xFFD740, 0x69F0AE, 0x40C4FF, 0xE040FB, 0xFFFFFF]
        var at: TimeInterval = 0
        while at < duration - 1 {
            let center = CGPoint(x: CGFloat.random(in: area.minX + area.width * 0.1...area.maxX - area.width * 0.1),
                                 y: CGFloat.random(in: area.midY...area.maxY - 40))
            let color = colors.randomElement() ?? 0xFFFFFF
            let reach = CGFloat.random(in: 50...110)
            let begin = CACurrentMediaTime() + at
            for index in 0..<16 {
                let angle = CGFloat(index) / 16 * 2 * .pi
                let spark = shape(ellipse(.zero, 2.4, 2.4), fill: rgb(color))
                spark.shadowColor = rgb(color)
                spark.shadowOpacity = 1
                spark.shadowRadius = 4
                spark.shadowOffset = .zero
                spark.position = center
                spark.opacity = 0
                let fly = CABasicAnimation(keyPath: "position")
                fly.fromValue = NSValue(point: center)
                fly.toValue = NSValue(point: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach - 20))
                fly.timingFunction = CAMediaTimingFunction(name: .easeOut)
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.6, 1]
                let group = CAAnimationGroup()
                group.animations = [fly, fade]
                group.duration = 1.2
                group.beginTime = begin
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false
                spark.add(group, forKey: "burst")
                parent.addSublayer(spark)
                NotchMascotPlayEffects.remove(spark, after: at + 1.3)
            }
            at += TimeInterval.random(in: 0.35...0.8)
        }
    }

    /// A birthday cake with a candle on `floor` at `x`.
    static func cake(in parent: CALayer, x: CGFloat, floor: CGFloat, size: CGFloat, duration: TimeInterval) {
        let cake = holder(at: CGPoint(x: x, y: floor))
        cake.addSublayer(shape(CGPath(rect: CGRect(x: -size / 2, y: 0, width: size, height: size * 0.45), transform: nil),
                               fill: rgb(0xF8BBD0), stroke: rgb(0xC2185B), width: 1.2))
        cake.addSublayer(shape(CGPath(rect: CGRect(x: -size / 2, y: size * 0.36, width: size, height: size * 0.09), transform: nil),
                               fill: rgb(0xFFFFFF)))
        cake.addSublayer(shape(CGPath(rect: CGRect(x: -size * 0.04, y: size * 0.45, width: size * 0.08, height: size * 0.25),
                                      transform: nil), fill: rgb(0x64B5F6)))
        let flame = shape(ellipse(CGPoint(x: 0, y: size * 0.78), size * 0.05, size * 0.09), fill: rgb(0xFFC107))
        flame.shadowColor = rgb(0xFF9800)
        flame.shadowOpacity = 1
        flame.shadowRadius = 5
        flame.shadowOffset = .zero
        flame.add(keyframes("transform.scale", [1, 1.2, 0.9, 1], duration: 0.5, repeats: .infinity), forKey: "flicker")
        cake.addSublayer(flame)
        show(cake, in: parent, for: duration)
    }

    /// A garland of little flags hanging across the top of `area`.
    static func garland(in parent: CALayer, area: CGRect, duration: TimeInterval) {
        let line = holder(at: .zero)
        let colors: [UInt32] = [0xFF5252, 0xFFD740, 0x69F0AE, 0x40C4FF, 0xE040FB]
        let string = CGMutablePath()
        string.move(to: CGPoint(x: area.minX, y: area.maxY - 4))
        string.addQuadCurve(to: CGPoint(x: area.maxX, y: area.maxY - 4), control: CGPoint(x: area.midX, y: area.maxY - 60))
        line.addSublayer(shape(string, fill: nil, stroke: rgb(0xBDBDBD), width: 1))
        let flags = max(8, Int(area.width / 60))
        for index in 0..<flags {
            let t = (CGFloat(index) + 0.5) / CGFloat(flags)
            let x = area.minX + area.width * t
            let y = area.maxY - 4 - 4 * t * (1 - t) * 56
            let flag = CGMutablePath()
            flag.move(to: CGPoint(x: x - 9, y: y))
            flag.addLine(to: CGPoint(x: x + 9, y: y))
            flag.addLine(to: CGPoint(x: x, y: y - 20))
            flag.closeSubpath()
            line.addSublayer(shape(flag, fill: rgb(colors[index % colors.count])))
        }
        show(line, in: parent, for: duration)
    }
}
