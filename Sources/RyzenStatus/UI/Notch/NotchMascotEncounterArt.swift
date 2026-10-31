// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What passes by in a rare encounter, drawn into the clear layer over the
/// screen: each one draws itself, moves along its way and takes itself away.
/// Points are the layer's own, y up.
enum NotchMascotEncounterArt {
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
        return layer
    }

    private static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    /// A layer of no size at `point`, for parts drawn around its origin.
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
        animation.calculationMode = .linear
        return animation
    }

    private static func points(_ points: [CGPoint]) -> [NSValue] { points.map { NSValue(point: $0) } }

    // MARK: The tail

    /// A great green tail, its root at the screen's edge `edgeX` on `floor`,
    /// reaching `inward` (right when positive) `length` long. It slides in,
    /// sways a while and slides back out, `duration` in all.
    static func tail(in parent: CALayer, edgeX: CGFloat, floor: CGFloat, inward: CGFloat, length: CGFloat,
                     duration: TimeInterval) {
        let height = length * 0.3
        let root = CGPoint(x: 0, y: height)
        let control = CGPoint(x: length * 0.45, y: height * 1.15)
        let tip = CGPoint(x: length, y: height * 0.75)
        let body = CGMutablePath()
        body.move(to: .zero)
        body.addLine(to: root)
        body.addQuadCurve(to: tip, control: control)
        body.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.55, y: height * 0.15))
        body.closeSubpath()
        func onTop(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * root.x + 2 * u * t * control.x + t * t * tip.x,
                           y: u * u * root.y + 2 * u * t * control.y + t * t * tip.y)
        }
        let spikes = CGMutablePath()
        for t in stride(from: CGFloat(0.12), through: 0.84, by: 0.12) {
            let left = onTop(t - 0.045), right = onTop(t + 0.045), middle = onTop(t)
            let reach = height * 0.3 * (1 - t * 0.6)
            spikes.move(to: left)
            spikes.addLine(to: CGPoint(x: middle.x - length * 0.01, y: middle.y + reach))
            spikes.addLine(to: right)
            spikes.closeSubpath()
        }
        let spots = CGMutablePath()
        for (t, r) in [(0.25, 0.09), (0.5, 0.07), (0.7, 0.05)] as [(CGFloat, CGFloat)] {
            let top = onTop(t)
            spots.addPath(ellipse(CGPoint(x: top.x, y: top.y * 0.55), height * r * 1.4, height * r))
        }
        let wagger = holder(at: .zero)
        wagger.addSublayer(shape(spikes, fill: rgb(0x2E7D32), stroke: rgb(0x1B5E20), width: 1.5))
        wagger.addSublayer(shape(body, fill: rgb(0x4CAF50), stroke: rgb(0x1B5E20), width: 2))
        wagger.addSublayer(shape(spots, fill: rgb(0x388E3C)))
        let sway = keyframes("transform.rotation.z", [0, 0.13, -0.03, 0.15, -0.01, 0.11, 0],
                             duration: 1.1, repeats: Float(duration / 1.1))
        wagger.add(sway, forKey: "sway")
        let flip = holder(at: .zero)
        flip.transform = CATransform3DMakeScale(inward >= 0 ? 1 : -1, 1, 1)
        flip.addSublayer(wagger)
        let mover = holder(at: CGPoint(x: edgeX, y: floor))
        mover.addSublayer(flip)
        let hidden = CGPoint(x: edgeX - inward * length * 1.05, y: floor)
        let shown = CGPoint(x: edgeX - inward * length * 0.2, y: floor)
        let slide = keyframes("position", points([hidden, shown, shown, hidden]),
                              times: [0, 0.18, 0.8, 1], duration: duration)
        slide.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear),
                                 CAMediaTimingFunction(name: .easeIn)]
        mover.position = hidden
        mover.add(slide, forKey: "slide")
        parent.addSublayer(mover)
        NotchMascotPlayEffects.remove(mover, after: duration + 0.1)
    }

    /// A puff of dust where a great foot came down.
    static func dust(in parent: CALayer, at point: CGPoint, radius: CGFloat) {
        NotchMascotPlayEffects.magicSmoke(in: parent, at: point, radius: radius,
                                          energy: NotchMascotPlay.Energy(red: 0.72, green: 0.68, blue: 0.6), count: 5)
    }

    // MARK: The shooting star

    /// A star streaking from `start` to `end` over `duration`, its trail
    /// drawn after it and fading.
    static func shootingStar(in parent: CALayer, from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
        let line = CGMutablePath()
        line.move(to: start)
        line.addLine(to: end)
        let trail = shape(line, fill: nil, stroke: rgb(0xFFF6D5, 0.85), width: 2)
        trail.lineCap = .round
        trail.shadowColor = rgb(0xFFE38A)
        trail.shadowOpacity = 1
        trail.shadowRadius = 4
        trail.shadowOffset = .zero
        trail.strokeEnd = 1
        trail.strokeStart = 1
        let grow = CABasicAnimation(keyPath: "strokeEnd")
        grow.fromValue = 0
        grow.toValue = 1
        grow.duration = duration
        grow.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let chase = CABasicAnimation(keyPath: "strokeStart")
        chase.fromValue = 0
        chase.toValue = 1
        chase.duration = duration * 1.25
        chase.timingFunction = CAMediaTimingFunction(name: .easeIn)
        trail.add(grow, forKey: "grow")
        trail.add(chase, forKey: "chase")
        let head = shape(ellipse(.zero, 3.5, 3.5), fill: rgb(0xFFFFFF))
        head.shadowColor = rgb(0xFFE38A)
        head.shadowOpacity = 1
        head.shadowRadius = 6
        head.shadowOffset = .zero
        head.position = end
        let fly = CABasicAnimation(keyPath: "position")
        fly.fromValue = NSValue(point: start)
        fly.toValue = NSValue(point: end)
        fly.duration = duration
        fly.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let fade = keyframes("opacity", [0, 1, 1, 0], times: [0, 0.1, 0.85, 1], duration: duration)
        let group = CAAnimationGroup()
        group.animations = [fly, fade]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        head.add(group, forKey: "fly")
        parent.addSublayer(trail)
        parent.addSublayer(head)
        NotchMascotPlayEffects.remove(trail, after: duration * 1.3)
        NotchMascotPlayEffects.remove(head, after: duration + 0.1)
    }

    // MARK: The rainbow

    /// A rainbow standing on `center`, `radius` to its outer band, that
    /// draws itself up from both feet, stays a while and fades, `duration`
    /// in all.
    static func rainbow(in parent: CALayer, center: CGPoint, radius: CGFloat, duration: TimeInterval) {
        let colors: [UInt32] = [0xFF5A5A, 0xFF9F43, 0xFFD93D, 0x6BCB77, 0x4D96FF, 0x9B5DE5]
        let band = max(4, radius * 0.045)
        let bow = CALayer()
        for (index, color) in colors.enumerated() {
            let r = radius - CGFloat(index) * band
            let arc = CGMutablePath()
            arc.addArc(center: center, radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
            let layer = shape(arc, fill: nil, stroke: rgb(color, 0.7), width: band)
            layer.strokeEnd = 1
            layer.add(keyframes("strokeEnd", [0, 1, 1], times: [0, 0.25, 1], duration: duration), forKey: "draw")
            bow.addSublayer(layer)
        }
        bow.add(keyframes("opacity", [0, 1, 1, 0], times: [0, 0.1, 0.75, 1], duration: duration), forKey: "fade")
        parent.addSublayer(bow)
        NotchMascotPlayEffects.remove(bow, after: duration + 0.1)
    }

    // MARK: The satellite

    /// A little satellite `size` wide drifting from `start` to `end` over
    /// `duration`: a gold body between two blue panels, its light blinking
    /// and a ring of signal going out from its dish now and then.
    static func satellite(in parent: CALayer, from start: CGPoint, to end: CGPoint, size: CGFloat, duration: TimeInterval) {
        let craft = holder(at: start)
        let unit = size / 10
        let panel = rgb(0x3B6FD8)
        for side in [-1.0, 1.0] as [CGFloat] {
            let wing = CGRect(x: side < 0 ? -5 * unit : 1.6 * unit, y: -1.1 * unit, width: 3.4 * unit, height: 2.2 * unit)
            craft.addSublayer(shape(CGPath(rect: wing, transform: nil), fill: panel, stroke: rgb(0x9CC2FF), width: 0.6))
            let strut = CGRect(x: side < 0 ? -1.6 * unit : 1.0 * unit, y: -0.2 * unit, width: 0.6 * unit, height: 0.4 * unit)
            craft.addSublayer(shape(CGPath(rect: strut, transform: nil), fill: rgb(0xB8BCC6)))
        }
        let body = CGPath(roundedRect: CGRect(x: -unit, y: -1.4 * unit, width: 2 * unit, height: 2.8 * unit),
                          cornerWidth: 0.4 * unit, cornerHeight: 0.4 * unit, transform: nil)
        craft.addSublayer(shape(body, fill: rgb(0xE8B64C), stroke: rgb(0x8A6420), width: 0.6))
        craft.addSublayer(shape(ellipse(CGPoint(x: 0, y: 2.0 * unit), 1.1 * unit, 0.5 * unit), fill: rgb(0xDADDE3)))
        let light = shape(ellipse(CGPoint(x: 0, y: -1.9 * unit), 0.45 * unit, 0.45 * unit), fill: rgb(0xFF5A5A))
        light.shadowColor = rgb(0xFF5A5A)
        light.shadowOpacity = 1
        light.shadowRadius = 4
        light.shadowOffset = .zero
        light.add(keyframes("opacity", [1, 0.1, 1], times: [0, 0.5, 1], duration: 1, repeats: .infinity), forKey: "blink")
        craft.addSublayer(light)
        let ring = shape(ellipse(CGPoint(x: 0, y: 2.0 * unit), 2 * unit, 2 * unit), fill: nil, stroke: rgb(0x9CF2FF, 0.8), width: 1)
        ring.add(keyframes("opacity", [0, 0.9, 0], times: [0, 0.2, 1], duration: 2.2, repeats: .infinity), forKey: "ping")
        ring.add(keyframes("transform.scale", [0.4, 2.2], duration: 2.2, repeats: .infinity), forKey: "spread")
        craft.addSublayer(ring)
        craft.add(keyframes("position", points([start, end]), duration: duration), forKey: "drift")
        craft.add(keyframes("transform.rotation.z", [-0.12, 0.12, -0.12], duration: duration), forKey: "tumble")
        craft.position = end
        parent.addSublayer(craft)
        NotchMascotPlayEffects.remove(craft, after: duration + 0.1)
    }

    // MARK: The saucer

    /// A flying saucer `size` across, flying through `stops` at `times`
    /// (0 to 1) over `duration`, its lights blinking and bobbing as it goes.
    static func saucer(in parent: CALayer, size: CGFloat, stops: [CGPoint], times: [NSNumber], duration: TimeInterval) {
        let ship = holder(at: stops.first ?? .zero)
        let dome = shape(ellipse(CGPoint(x: 0, y: size * 0.1), size * 0.22, size * 0.2), fill: rgb(0x9BE7FF, 0.75),
                         stroke: rgb(0xE1F7FF), width: 1)
        let hull = shape(ellipse(.zero, size * 0.5, size * 0.13), fill: rgb(0xB0BEC5), stroke: rgb(0x607D8B), width: 1.5)
        let rim = shape(ellipse(CGPoint(x: 0, y: -size * 0.02), size * 0.36, size * 0.05), fill: rgb(0x78909C))
        ship.addSublayer(dome)
        ship.addSublayer(hull)
        ship.addSublayer(rim)
        let colors: [UInt32] = [0xFF5252, 0xFFD740, 0x69F0AE, 0x40C4FF]
        for (index, color) in colors.enumerated() {
            let x = (CGFloat(index) - 1.5) * size * 0.2
            let light = shape(ellipse(CGPoint(x: x, y: -size * 0.02), size * 0.035, size * 0.035), fill: rgb(color))
            let blink = keyframes("opacity", [1, 0.2, 1], duration: 0.5, repeats: .infinity)
            blink.beginTime = CACurrentMediaTime() + Double(index) * 0.12
            light.add(blink, forKey: "blink")
            ship.addSublayer(light)
        }
        let fly = keyframes("position", points(stops), times: times, duration: duration)
        fly.calculationMode = .cubic
        ship.position = stops.last ?? .zero
        ship.add(fly, forKey: "fly")
        let bob = keyframes("transform.rotation.z", [0, 0.06, 0, -0.06, 0], duration: 1.2,
                            repeats: Float(duration / 1.2))
        ship.add(bob, forKey: "bob")
        parent.addSublayer(ship)
        NotchMascotPlayEffects.remove(ship, after: duration + 0.1)
    }

    /// The saucer's beam, from `top` down to `floor`, `width` wide at the
    /// bottom, after `delay` for `length`.
    static func beam(in parent: CALayer, top: CGPoint, floor: CGFloat, width: CGFloat, delay: TimeInterval,
                     length: TimeInterval) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: top.x - width * 0.15, y: top.y))
        path.addLine(to: CGPoint(x: top.x + width * 0.15, y: top.y))
        path.addLine(to: CGPoint(x: top.x + width / 2, y: floor))
        path.addLine(to: CGPoint(x: top.x - width / 2, y: floor))
        path.closeSubpath()
        let light = shape(path, fill: rgb(0xFFF59D, 0.32))
        light.opacity = 0
        let shine = keyframes("opacity", [0, 1, 0.75, 1, 0.8, 1, 0], times: [0, 0.08, 0.3, 0.5, 0.7, 0.9, 1],
                              duration: length)
        shine.beginTime = CACurrentMediaTime() + delay
        light.add(shine, forKey: "shine")
        parent.addSublayer(light)
        NotchMascotPlayEffects.remove(light, after: delay + length + 0.1)
    }

    // MARK: The ghost

    /// A little ghost `size` tall drifting through `stops` over `duration`,
    /// fading in and out and wavering as it goes.
    static func ghost(in parent: CALayer, size: CGFloat, stops: [CGPoint], duration: TimeInterval) {
        let r = size * 0.42
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -r, y: 0))
        body.addArc(center: CGPoint(x: 0, y: 0), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        body.addLine(to: CGPoint(x: r, y: -size * 0.5))
        let scallops = 4
        for index in 0..<scallops {
            let x0 = r - CGFloat(index) * (2 * r / CGFloat(scallops))
            let x1 = x0 - 2 * r / CGFloat(scallops)
            body.addQuadCurve(to: CGPoint(x: x1, y: -size * 0.5),
                              control: CGPoint(x: (x0 + x1) / 2, y: -size * (index.isMultiple(of: 2) ? 0.36 : 0.62)))
        }
        body.closeSubpath()
        let ghost = holder(at: stops.first ?? .zero)
        let sheet = shape(body, fill: rgb(0xF5F7FF, 0.92), stroke: rgb(0xC5CAE9), width: 1)
        sheet.shadowColor = rgb(0xBBDEFB)
        sheet.shadowOpacity = 0.9
        sheet.shadowRadius = 6
        sheet.shadowOffset = .zero
        let eyes = CGMutablePath()
        eyes.addPath(ellipse(CGPoint(x: -r * 0.38, y: r * 0.05), r * 0.13, r * 0.2))
        eyes.addPath(ellipse(CGPoint(x: r * 0.38, y: r * 0.05), r * 0.13, r * 0.2))
        let mouth = ellipse(CGPoint(x: 0, y: -r * 0.42), r * 0.14, r * 0.18)
        ghost.addSublayer(sheet)
        ghost.addSublayer(shape(eyes, fill: rgb(0x263238)))
        ghost.addSublayer(shape(mouth, fill: rgb(0x263238)))
        let drift = keyframes("position", points(stops), duration: duration)
        drift.calculationMode = .cubic
        let fade = keyframes("opacity", [0, 0.95, 0.95, 0], times: [0, 0.15, 0.8, 1], duration: duration)
        let waver = keyframes("transform.rotation.z", [-0.12, 0.12, -0.12], duration: 1.4,
                              repeats: Float(duration / 1.4))
        ghost.position = stops.last ?? .zero
        ghost.opacity = 0
        ghost.add(drift, forKey: "drift")
        ghost.add(fade, forKey: "fade")
        ghost.add(waver, forKey: "waver")
        parent.addSublayer(ghost)
        NotchMascotPlayEffects.remove(ghost, after: duration + 0.1)
    }

    // MARK: The bird

    /// A magpie `size` long flying through `stops` at `times` over
    /// `duration`, flapping, facing the way it goes. With `carries` from
    /// `carryFrom` to `carryUntil` (0 to 1), something shiny hangs from its feet.
    static func magpie(in parent: CALayer, size: CGFloat, stops: [CGPoint], times: [NSNumber], duration: TimeInterval,
                       carryFrom: Double, carryUntil: Double) {
        let bird = holder(at: stops.first ?? .zero)
        let facing = holder(at: .zero)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -size * 0.15, y: size * 0.02))
        tail.addLine(to: CGPoint(x: -size * 0.62, y: size * 0.12))
        tail.addLine(to: CGPoint(x: -size * 0.6, y: -size * 0.02))
        tail.closeSubpath()
        let beak = CGMutablePath()
        beak.move(to: CGPoint(x: size * 0.36, y: size * 0.14))
        beak.addLine(to: CGPoint(x: size * 0.5, y: size * 0.1))
        beak.addLine(to: CGPoint(x: size * 0.36, y: size * 0.06))
        beak.closeSubpath()
        facing.addSublayer(shape(tail, fill: rgb(0x1A237E)))
        facing.addSublayer(shape(ellipse(.zero, size * 0.26, size * 0.15), fill: rgb(0x111111)))
        facing.addSublayer(shape(ellipse(CGPoint(x: size * 0.02, y: -size * 0.04), size * 0.16, size * 0.09),
                                 fill: rgb(0xFAFAFA)))
        facing.addSublayer(shape(ellipse(CGPoint(x: size * 0.28, y: size * 0.1), size * 0.11, size * 0.11),
                                 fill: rgb(0x111111)))
        facing.addSublayer(shape(beak, fill: rgb(0x424242)))
        facing.addSublayer(shape(ellipse(CGPoint(x: size * 0.31, y: size * 0.13), size * 0.022, size * 0.022),
                                 fill: rgb(0xFFFFFF)))
        let wingPath = CGMutablePath()
        wingPath.move(to: CGPoint(x: -size * 0.05, y: size * 0.05))
        wingPath.addQuadCurve(to: CGPoint(x: -size * 0.2, y: size * 0.42), control: CGPoint(x: -size * 0.25, y: size * 0.2))
        wingPath.addQuadCurve(to: CGPoint(x: size * 0.12, y: size * 0.06), control: CGPoint(x: size * 0.05, y: size * 0.3))
        wingPath.closeSubpath()
        let wing = shape(wingPath, fill: rgb(0x111111), stroke: rgb(0xFAFAFA), width: 1)
        let flap = keyframes("transform.scale.y", [1, -0.4, 1], duration: 0.22, repeats: .infinity)
        wing.add(flap, forKey: "flap")
        facing.addSublayer(wing)
        // Something shiny in its feet.
        let loot = shape(ellipse(CGPoint(x: size * 0.05, y: -size * 0.24), size * 0.09, size * 0.09),
                         fill: rgb(0xFFD23F), stroke: rgb(0xD99A1E), width: 1)
        loot.shadowColor = rgb(0xFFE38A)
        loot.shadowOpacity = 1
        loot.shadowRadius = 4
        loot.shadowOffset = .zero
        loot.opacity = 0
        let carry = keyframes("opacity", [0, 0, 1, 1, 0, 0],
                              times: [0, NSNumber(value: carryFrom), NSNumber(value: carryFrom + 0.001),
                                      NSNumber(value: carryUntil), NSNumber(value: carryUntil + 0.001), 1],
                              duration: duration)
        loot.add(carry, forKey: "carry")
        facing.addSublayer(loot)
        bird.addSublayer(facing)
        // It turns to face where it flies next.
        var turns: [CGFloat] = []
        for index in stops.indices {
            let next = index + 1 < stops.count ? stops[index + 1].x - stops[index].x : 0
            turns.append(next == 0 ? (turns.last ?? 1) : (next > 0 ? 1 : -1))
        }
        let face = keyframes("transform.scale.x", turns, times: times, duration: duration)
        face.calculationMode = .discrete
        facing.add(face, forKey: "face")
        let fly = keyframes("position", points(stops), times: times, duration: duration)
        bird.position = stops.last ?? .zero
        bird.add(fly, forKey: "fly")
        parent.addSublayer(bird)
        NotchMascotPlayEffects.remove(bird, after: duration + 0.1)
    }

    // MARK: Fireflies

    /// `count` little lights wandering round `center`, within `radius`, for
    /// `duration`, blinking each on its own.
    static func fireflies(in parent: CALayer, around center: CGPoint, radius: CGFloat, count: Int, duration: TimeInterval) {
        for index in 0..<count {
            let fly = shape(ellipse(.zero, 2.6, 2.6), fill: rgb(0xE6FF7A))
            fly.shadowColor = rgb(0xC6FF3D)
            fly.shadowOpacity = 1
            fly.shadowRadius = 5
            fly.shadowOffset = .zero
            var stops: [CGPoint] = []
            for _ in 0..<8 {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let reach = radius * CGFloat.random(in: 0.3...1)
                stops.append(CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach * 0.7))
            }
            let wander = keyframes("position", points(stops), duration: duration)
            wander.calculationMode = .cubic
            let blink = keyframes("opacity", [0, 1, 0.2, 1, 0.1, 1, 0],
                                  times: [0, 0.1, 0.3, 0.45, 0.65, 0.85, 1], duration: duration)
            blink.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            fly.position = stops.last ?? center
            fly.opacity = 0
            fly.add(wander, forKey: "wander")
            fly.add(blink, forKey: "blink")
            parent.addSublayer(fly)
            NotchMascotPlayEffects.remove(fly, after: duration + Double(index) * 0.15 + 0.1)
        }
    }

    // MARK: Ducks

    private static func duck(size: CGFloat, mother: Bool) -> CALayer {
        let duck = holder(at: .zero)
        let bodyColor = mother ? rgb(0xF5F5F5) : rgb(0xFFE14D)
        let edge = mother ? rgb(0xBDBDBD) : rgb(0xE0B400)
        let beak = CGMutablePath()
        beak.move(to: CGPoint(x: size * 0.4, y: size * 0.62))
        beak.addLine(to: CGPoint(x: size * 0.58, y: size * 0.58))
        beak.addLine(to: CGPoint(x: size * 0.4, y: size * 0.52))
        beak.closeSubpath()
        duck.addSublayer(shape(ellipse(CGPoint(x: 0, y: size * 0.25), size * 0.36, size * 0.24), fill: bodyColor,
                               stroke: edge, width: 1))
        duck.addSublayer(shape(ellipse(CGPoint(x: size * 0.24, y: size * 0.58), size * 0.18, size * 0.18),
                               fill: bodyColor, stroke: edge, width: 1))
        duck.addSublayer(shape(beak, fill: rgb(0xFF9800)))
        duck.addSublayer(shape(ellipse(CGPoint(x: size * 0.3, y: size * 0.63), size * 0.03, size * 0.03),
                               fill: rgb(0x212121)))
        duck.addSublayer(shape(ellipse(CGPoint(x: -size * 0.05, y: size * 0.28), size * 0.16, size * 0.09),
                               fill: mother ? rgb(0xE0E0E0) : rgb(0xFFD000)))
        return duck
    }

    /// A mother duck and `babies` ducklings in a line walking along `floor`
    /// from `fromX` to `toX` over `duration`, waddling.
    static func ducklings(in parent: CALayer, fromX: CGFloat, toX: CGFloat, floor: CGFloat, size: CGFloat,
                          babies: Int, duration: TimeInterval) {
        let way: CGFloat = toX >= fromX ? 1 : -1
        for index in 0...babies {
            let mother = index == 0
            let scale = mother ? size : size * 0.55
            let gap = mother ? 0 : size * 0.8 + CGFloat(index - 1) * size * 0.55
            let duck = duck(size: scale, mother: mother)
            let start = CGPoint(x: fromX - way * gap, y: floor)
            let end = CGPoint(x: toX - way * gap, y: floor)
            let walk = CABasicAnimation(keyPath: "position")
            walk.fromValue = NSValue(point: start)
            walk.toValue = NSValue(point: end)
            walk.duration = duration
            walk.fillMode = .forwards
            walk.isRemovedOnCompletion = false
            let waddle = keyframes("transform.rotation.z", [-0.1, 0.1, -0.1], duration: mother ? 0.5 : 0.32,
                                   repeats: Float(duration / (mother ? 0.5 : 0.32)))
            let holder = self.holder(at: start)
            // Turned on the holder: the waddle turns the duck itself.
            holder.transform = CATransform3DMakeScale(way, 1, 1)
            holder.addSublayer(duck)
            holder.position = end
            holder.add(walk, forKey: "walk")
            duck.add(waddle, forKey: "waddle")
            parent.addSublayer(holder)
            NotchMascotPlayEffects.remove(holder, after: duration + 0.1)
        }
    }

    // MARK: The mimic
    /// A chest `size` wide going through `stops` at `times` over `duration`,
    /// its feet on each. Between `openAt` and `closeAt` (0 to 1) its lid
    /// gapes and snaps, with teeth, a tongue and eyes.
    static func mimic(in parent: CALayer, size: CGFloat, stops: [CGPoint], times: [NSNumber], duration: TimeInterval,
                      openAt: Double, closeAt: Double) {
        let chest = holder(at: stops.first ?? .zero)
        let w = size, base = size * 0.5, lidHeight = size * 0.3
        let mouth = holder(at: .zero)
        mouth.addSublayer(shape(CGPath(rect: CGRect(x: -w * 0.44, y: base - size * 0.08, width: w * 0.88, height: size * 0.2),
                                       transform: nil), fill: rgb(0x4A0E14)))
        mouth.addSublayer(shape(ellipse(CGPoint(x: w * 0.05, y: base - size * 0.02), w * 0.22, size * 0.07), fill: rgb(0xE5506A)))
        let teeth = CGMutablePath()
        let count = 6
        for index in 0..<count {
            let x0 = -w * 0.44 + CGFloat(index) * w * 0.88 / CGFloat(count)
            let x1 = x0 + w * 0.88 / CGFloat(count)
            teeth.move(to: CGPoint(x: x0, y: base))
            teeth.addLine(to: CGPoint(x: (x0 + x1) / 2, y: base + size * 0.09))
            teeth.addLine(to: CGPoint(x: x1, y: base))
            teeth.closeSubpath()
        }
        mouth.addSublayer(shape(teeth, fill: rgb(0xFFFDF2), stroke: rgb(0xBDB6A0), width: 0.8))
        mouth.opacity = 0
        let gape = keyframes("opacity", [0, 0, 1, 1, 0, 0],
                             times: [0, NSNumber(value: openAt), NSNumber(value: openAt + 0.001), NSNumber(value: closeAt),
                                     NSNumber(value: closeAt + 0.001), 1], duration: duration)
        mouth.add(gape, forKey: "gape")
        let box = CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: base), cornerWidth: 3, cornerHeight: 3,
                         transform: nil)
        let bands = CGMutablePath()
        bands.addRect(CGRect(x: -w * 0.42, y: 0, width: w * 0.1, height: base))
        bands.addRect(CGRect(x: w * 0.32, y: 0, width: w * 0.1, height: base))
        chest.addSublayer(shape(box, fill: rgb(0x9C5A2B), stroke: rgb(0x4E2A12), width: 1.5))
        chest.addSublayer(shape(bands, fill: rgb(0xC9A227), stroke: rgb(0x7A5E12), width: 0.8))
        chest.addSublayer(shape(CGPath(rect: CGRect(x: -w * 0.07, y: base * 0.45, width: w * 0.14, height: base * 0.32),
                                       transform: nil), fill: rgb(0xE8C547), stroke: rgb(0x7A5E12), width: 0.8))
        chest.addSublayer(mouth)
        // The lid, hinged at the back on the left.
        let lid = holder(at: CGPoint(x: -w / 2, y: base))
        let top = CGMutablePath()
        top.move(to: .zero)
        top.addLine(to: CGPoint(x: 0, y: lidHeight * 0.55))
        top.addQuadCurve(to: CGPoint(x: w, y: lidHeight * 0.55), control: CGPoint(x: w / 2, y: lidHeight * 1.35))
        top.addLine(to: CGPoint(x: w, y: 0))
        top.closeSubpath()
        lid.addSublayer(shape(top, fill: rgb(0xA8642F), stroke: rgb(0x4E2A12), width: 1.5))
        let lidTeeth = CGMutablePath()
        for index in 0..<count {
            let x0 = w * 0.06 + CGFloat(index) * w * 0.88 / CGFloat(count)
            let x1 = x0 + w * 0.88 / CGFloat(count)
            lidTeeth.move(to: CGPoint(x: x0, y: 0))
            lidTeeth.addLine(to: CGPoint(x: (x0 + x1) / 2, y: -size * 0.08))
            lidTeeth.addLine(to: CGPoint(x: x1, y: 0))
            lidTeeth.closeSubpath()
        }
        let fangs = shape(lidTeeth, fill: rgb(0xFFFDF2), stroke: rgb(0xBDB6A0), width: 0.8)
        let eyes = CGMutablePath()
        eyes.addPath(ellipse(CGPoint(x: w * 0.33, y: lidHeight * 0.55), size * 0.05, size * 0.06))
        eyes.addPath(ellipse(CGPoint(x: w * 0.67, y: lidHeight * 0.55), size * 0.05, size * 0.06))
        let glare = shape(eyes, fill: rgb(0xFFE14D))
        glare.shadowColor = rgb(0xFF9800)
        glare.shadowOpacity = 1
        glare.shadowRadius = 4
        glare.shadowOffset = .zero
        for part in [fangs, glare] {
            part.opacity = 0
            part.add(gape, forKey: "gape")
            lid.addSublayer(part)
        }
        chest.addSublayer(lid)
        // It gapes, and snaps three times, and shuts.
        let span = closeAt - openAt
        var angles: [CGFloat] = [0, 0]
        var marks: [Double] = [0, openAt]
        for index in 0..<7 {
            angles.append(index.isMultiple(of: 2) ? 0.75 : 0.12)
            marks.append(openAt + span * Double(index + 1) / 8)
        }
        angles += [0, 0]
        marks += [closeAt, 1]
        lid.add(keyframes("transform.rotation.z", angles, times: marks.map { NSNumber(value: $0) }, duration: duration),
                forKey: "snap")
        let hop = keyframes("position", points(stops), times: times, duration: duration)
        chest.position = stops.last ?? .zero
        chest.add(hop, forKey: "hop")
        chest.add(keyframes("opacity", [0, 1, 1, 0], times: [0, 0.04, 0.95, 1], duration: duration), forKey: "fade")
        chest.opacity = 0
        parent.addSublayer(chest)
        NotchMascotPlayEffects.remove(chest, after: duration + 0.1)
    }
    // MARK: The merchant
    /// A hooded seller `size` tall with a great pack and a lantern, walking
    /// along `floor` from `fromX` to `stopX` by `arriveAt`, waiting there
    /// until `leaveAt` (0 to 1) and walking on to `toX`, over `duration`.
    static func merchant(in parent: CALayer, fromX: CGFloat, stopX: CGFloat, toX: CGFloat, floor: CGFloat, size: CGFloat,
                         duration: TimeInterval, arriveAt: Double, leaveAt: Double) {
        let figure = holder(at: .zero)
        let pack = CGPath(roundedRect: CGRect(x: -size * 0.5, y: size * 0.2, width: size * 0.42, height: size * 0.55),
                          cornerWidth: 4, cornerHeight: 4, transform: nil)
        figure.addSublayer(shape(pack, fill: rgb(0x8D6E63), stroke: rgb(0x4E342E), width: 1.2))
        figure.addSublayer(shape(ellipse(CGPoint(x: -size * 0.29, y: size * 0.8), size * 0.24, size * 0.08),
                                 fill: rgb(0xC62828), stroke: rgb(0x7F1D1D), width: 1))
        figure.addSublayer(shape(ellipse(CGPoint(x: -size * 0.42, y: size * 0.36), size * 0.07, size * 0.07),
                                 fill: rgb(0x90A4AE), stroke: rgb(0x455A64), width: 0.8))
        let cloak = CGMutablePath()
        cloak.move(to: CGPoint(x: -size * 0.24, y: 0))
        cloak.addQuadCurve(to: CGPoint(x: 0, y: size * 0.88), control: CGPoint(x: -size * 0.24, y: size * 0.7))
        cloak.addQuadCurve(to: CGPoint(x: size * 0.24, y: 0), control: CGPoint(x: size * 0.24, y: size * 0.7))
        cloak.closeSubpath()
        figure.addSublayer(shape(cloak, fill: rgb(0x5E35B1), stroke: rgb(0x311B92), width: 1.2))
        figure.addSublayer(shape(ellipse(CGPoint(x: size * 0.04, y: size * 0.62), size * 0.13, size * 0.12), fill: rgb(0x1A1033)))
        let eyes = CGMutablePath()
        eyes.addPath(ellipse(CGPoint(x: size * 0.0, y: size * 0.63), size * 0.025, size * 0.025))
        eyes.addPath(ellipse(CGPoint(x: size * 0.09, y: size * 0.63), size * 0.025, size * 0.025))
        let glow = shape(eyes, fill: rgb(0xFFF59D))
        glow.shadowColor = rgb(0xFFEB3B)
        glow.shadowOpacity = 1
        glow.shadowRadius = 3
        glow.shadowOffset = .zero
        figure.addSublayer(glow)
        let staff = CGMutablePath()
        staff.move(to: CGPoint(x: size * 0.3, y: 0))
        staff.addLine(to: CGPoint(x: size * 0.3, y: size * 0.95))
        staff.addLine(to: CGPoint(x: size * 0.42, y: size * 0.95))
        figure.addSublayer(shape(staff, fill: nil, stroke: rgb(0x6D4C41), width: 2))
        let lantern = shape(ellipse(CGPoint(x: size * 0.42, y: size * 0.84), size * 0.05, size * 0.07), fill: rgb(0xFFCA28),
                            stroke: rgb(0x8D6E63), width: 0.8)
        lantern.shadowColor = rgb(0xFFB300)
        lantern.shadowOpacity = 1
        lantern.shadowRadius = 6
        lantern.shadowOffset = .zero
        lantern.add(keyframes("shadowRadius", [6, 9, 5, 8, 6], duration: 1.6, repeats: .infinity), forKey: "flicker")
        figure.addSublayer(lantern)
        let way: CGFloat = stopX >= fromX ? 1 : -1
        let turn = holder(at: .zero)
        turn.transform = CATransform3DMakeScale(way, 1, 1)
        turn.addSublayer(figure)
        // It turns round to go when it walks back the way it came.
        if (toX - stopX) * way < 0 {
            turn.add(keyframes("transform.scale.x", [way, way, -way, -way],
                               times: [0, NSNumber(value: leaveAt), NSNumber(value: min(1, leaveAt + 0.01)), 1],
                               duration: duration), forKey: "turn")
        }
        let walker = holder(at: CGPoint(x: fromX, y: floor))
        walker.addSublayer(turn)
        let walk = keyframes("position", points([CGPoint(x: fromX, y: floor), CGPoint(x: stopX, y: floor),
                                                 CGPoint(x: stopX, y: floor), CGPoint(x: toX, y: floor)]),
                             times: [0, NSNumber(value: arriveAt), NSNumber(value: leaveAt), 1], duration: duration)
        walker.position = CGPoint(x: toX, y: floor)
        walker.add(walk, forKey: "walk")
        walker.add(keyframes("opacity", [0, 1, 1, 0], times: [0, 0.06, 0.94, 1], duration: duration), forKey: "fade")
        walker.opacity = 0
        figure.add(keyframes("transform.rotation.z", [-0.05, 0.05, -0.05], duration: 0.6, repeats: Float(duration / 0.6)),
                   forKey: "bob")
        parent.addSublayer(walker)
        NotchMascotPlayEffects.remove(walker, after: duration + 0.1)
    }
    // MARK: Bubbles
    /// A soap bubble `size` across drifting through `stops` over `duration`,
    /// wobbling, after `delay`; at the last stop it pops in droplets.
    static func bubble(in parent: CALayer, size: CGFloat, stops: [CGPoint], duration: TimeInterval, delay: TimeInterval = 0) {
        let r = size / 2
        let ball = holder(at: stops.first ?? .zero)
        let film = shape(ellipse(.zero, r, r), fill: rgb(0xB3E5FC, 0.18), stroke: rgb(0xE1F5FE, 0.85), width: 1.5)
        film.shadowColor = rgb(0xF48FB1)
        film.shadowOpacity = 0.8
        film.shadowRadius = 3
        film.shadowOffset = .zero
        let shine = CGMutablePath()
        shine.addArc(center: .zero, radius: r * 0.72, startAngle: .pi * 0.6, endAngle: .pi * 0.9, clockwise: false)
        let gleam = shape(shine, fill: nil, stroke: rgb(0xFFFFFF, 0.9), width: max(1.5, r * 0.12))
        gleam.lineCap = .round
        ball.addSublayer(film)
        ball.addSublayer(gleam)
        ball.addSublayer(shape(ellipse(CGPoint(x: r * 0.42, y: -r * 0.38), r * 0.08, r * 0.08), fill: rgb(0xFFFFFF, 0.8)))
        let start = CACurrentMediaTime() + delay
        let drift = keyframes("position", points(stops), duration: duration)
        drift.calculationMode = .cubic
        drift.beginTime = start
        let wobble = keyframes("transform", [CATransform3DIdentity, CATransform3DMakeScale(1.06, 0.95, 1),
                                             CATransform3DIdentity, CATransform3DMakeScale(0.95, 1.06, 1),
                                             CATransform3DIdentity].map { NSValue(caTransform3D: $0) },
                               duration: 0.9, repeats: Float(duration / 0.9))
        wobble.beginTime = start
        let show = keyframes("opacity", [1, 1, 0], times: [0, 0.97, 1], duration: duration)
        show.beginTime = start
        ball.position = stops.last ?? .zero
        ball.opacity = 0
        ball.add(drift, forKey: "drift")
        ball.add(wobble, forKey: "wobble")
        ball.add(show, forKey: "show")
        parent.addSublayer(ball)
        NotchMascotPlayEffects.remove(ball, after: delay + duration + 0.1)
        guard let end = stops.last else { return }
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi
            let drop = shape(ellipse(.zero, max(1.5, r * 0.09), max(1.5, r * 0.09)), fill: rgb(0xB3E5FC, 0.9))
            drop.position = end
            drop.opacity = 0
            let fly = CABasicAnimation(keyPath: "position")
            fly.fromValue = NSValue(point: end)
            fly.toValue = NSValue(point: CGPoint(x: end.x + cos(angle) * r * 1.4, y: end.y + sin(angle) * r * 1.4))
            let fade = keyframes("opacity", [1, 0], duration: 0.35)
            let group = CAAnimationGroup()
            group.animations = [fly, fade]
            group.duration = 0.35
            group.beginTime = start + duration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            drop.add(group, forKey: "splash")
            parent.addSublayer(drop)
            NotchMascotPlayEffects.remove(drop, after: delay + duration + 0.5)
        }
    }
    // MARK: The box
    /// A cardboard box `size` wide going through `stops` at `times` over
    /// `duration`, its bottom on each, trembling a little as it goes.
    static func box(in parent: CALayer, size: CGFloat, stops: [CGPoint], times: [NSNumber], duration: TimeInterval) {
        let crate = holder(at: stops.first ?? .zero)
        let w = size, h = size * 0.82
        let inside = holder(at: .zero)
        inside.addSublayer(shape(CGPath(rect: CGRect(x: -w / 2, y: 0, width: w, height: h), transform: nil),
                                 fill: rgb(0xC8A26B), stroke: rgb(0x7A5A2E), width: 1.5))
        let flaps = CGMutablePath()
        flaps.move(to: CGPoint(x: -w / 2, y: h * 0.82))
        flaps.addLine(to: CGPoint(x: w / 2, y: h * 0.82))
        inside.addSublayer(shape(flaps, fill: nil, stroke: rgb(0x9C7A45), width: 1))
        inside.addSublayer(shape(CGPath(rect: CGRect(x: -w * 0.08, y: h * 0.55, width: w * 0.16, height: h * 0.45),
                                        transform: nil), fill: rgb(0xD9C49A, 0.9)))
        let arrows = CGMutablePath()
        for x in [-w * 0.28, -w * 0.18] {
            arrows.move(to: CGPoint(x: x, y: h * 0.25))
            arrows.addLine(to: CGPoint(x: x, y: h * 0.45))
            arrows.move(to: CGPoint(x: x - w * 0.03, y: h * 0.4))
            arrows.addLine(to: CGPoint(x: x, y: h * 0.45))
            arrows.addLine(to: CGPoint(x: x + w * 0.03, y: h * 0.4))
        }
        inside.addSublayer(shape(arrows, fill: nil, stroke: rgb(0x6B4E24), width: 1.2))
        // A slit to look out of.
        inside.addSublayer(shape(CGPath(roundedRect: CGRect(x: w * 0.12, y: h * 0.5, width: w * 0.24, height: h * 0.07),
                                        cornerWidth: 2, cornerHeight: 2, transform: nil), fill: rgb(0x2B1D0E)))
        crate.addSublayer(inside)
        inside.add(keyframes("transform.rotation.z", [0, 0.025, 0, -0.025, 0], duration: 0.35,
                             repeats: Float(duration / 0.35)), forKey: "tremble")
        let move = keyframes("position", points(stops), times: times, duration: duration)
        crate.position = stops.last ?? .zero
        crate.add(move, forKey: "move")
        crate.add(keyframes("opacity", [1, 1, 0], times: [0, 0.92, 1], duration: duration), forKey: "fade")
        crate.opacity = 0
        parent.addSublayer(crate)
        NotchMascotPlayEffects.remove(crate, after: duration + 0.1)
    }
    // MARK: The crack
    /// A crack of loose pixels `height` tall opening at `center` for
    /// `duration`, flickering, bits of it leaking out.
    static func glitch(in parent: CALayer, at center: CGPoint, height: CGFloat, duration: TimeInterval) {
        let cell = max(4, (height / 12).rounded())
        let crack = holder(at: center)
        let colors: [UInt32] = [0xFF00E5, 0x00E5FF, 0x76FF03, 0xFFEA00]
        var offset = 0
        for row in 0..<12 {
            offset = max(-2, min(2, offset + Int.random(in: -1...1)))
            let width = Int.random(in: 1...3)
            for column in 0..<width {
                let pixel = CALayer()
                pixel.frame = CGRect(x: CGFloat(offset + column) * cell - cell, y: CGFloat(row - 6) * cell,
                                     width: cell, height: cell)
                pixel.backgroundColor = Int.random(in: 0..<4) == 0 ? rgb(colors.randomElement() ?? 0xFF00E5) : rgb(0x050505)
                crack.addSublayer(pixel)
            }
        }
        let open = keyframes("transform.scale.y", [0.01, 1, 1.1, 1, 1, 0.01], times: [0, 0.12, 0.2, 0.3, 0.88, 1],
                             duration: duration)
        let flicker = keyframes("opacity", [1, 0.4, 1, 1, 0.3, 1, 1, 0.5, 1],
                                times: [0, 0.15, 0.2, 0.45, 0.5, 0.55, 0.75, 0.8, 1], duration: duration)
        crack.add(open, forKey: "open")
        crack.add(flicker, forKey: "flicker")
        parent.addSublayer(crack)
        NotchMascotPlayEffects.remove(crack, after: duration + 0.1)
        // Bars torn sideways, the way a picture breaks.
        for index in 0..<5 {
            let bar = CALayer()
            let width = height * CGFloat.random(in: 0.5...1.2)
            bar.frame = CGRect(x: center.x - width / 2 + CGFloat.random(in: -height...height) * 0.4,
                               y: center.y + CGFloat.random(in: -0.5...0.5) * height, width: width, height: cell * 0.6)
            bar.backgroundColor = rgb(colors[index % colors.count], 0.55)
            bar.opacity = 0
            let blink = keyframes("opacity", [0, 1, 0, 1, 0], duration: 0.3)
            blink.beginTime = CACurrentMediaTime() + duration * Double.random(in: 0.15...0.8)
            bar.add(blink, forKey: "blink")
            parent.addSublayer(bar)
            NotchMascotPlayEffects.remove(bar, after: duration + 0.1)
        }
        // Loose pixels leaking out and falling.
        for _ in 0..<10 {
            let bit = CALayer()
            bit.bounds = CGRect(x: 0, y: 0, width: cell * 0.7, height: cell * 0.7)
            bit.backgroundColor = rgb(colors.randomElement() ?? 0x00E5FF)
            bit.position = center
            bit.opacity = 0
            let to = CGPoint(x: center.x + CGFloat.random(in: -1...1) * height * 0.9,
                             y: center.y - CGFloat.random(in: 0.2...0.9) * height)
            let fall = CABasicAnimation(keyPath: "position")
            fall.fromValue = NSValue(point: center)
            fall.toValue = NSValue(point: to)
            let fade = keyframes("opacity", [1, 1, 0], times: [0, 0.6, 1], duration: 0.9)
            let group = CAAnimationGroup()
            group.animations = [fall, fade]
            group.duration = 0.9
            group.beginTime = CACurrentMediaTime() + duration * Double.random(in: 0.2...0.75)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            bit.add(group, forKey: "leak")
            parent.addSublayer(bit)
            NotchMascotPlayEffects.remove(bit, after: duration + 1)
        }
    }
    // MARK: The boat
    /// A little paper boat `size` long sailing along `water` from `fromX` to
    /// `toX` over `duration`, on its own bit of waves, rocking.
    static func boat(in parent: CALayer, fromX: CGFloat, toX: CGFloat, water: CGFloat, size: CGFloat,
                     duration: TimeInterval) {
        let craft = holder(at: .zero)
        let hull = CGMutablePath()
        hull.move(to: CGPoint(x: -size * 0.5, y: size * 0.22))
        hull.addLine(to: CGPoint(x: size * 0.5, y: size * 0.22))
        hull.addLine(to: CGPoint(x: size * 0.32, y: 0))
        hull.addLine(to: CGPoint(x: -size * 0.32, y: 0))
        hull.closeSubpath()
        let mast = CGMutablePath()
        mast.move(to: CGPoint(x: 0, y: size * 0.22))
        mast.addLine(to: CGPoint(x: 0, y: size * 0.85))
        let sail = CGMutablePath()
        sail.move(to: CGPoint(x: size * 0.03, y: size * 0.82))
        sail.addLine(to: CGPoint(x: size * 0.36, y: size * 0.3))
        sail.addLine(to: CGPoint(x: size * 0.03, y: size * 0.3))
        sail.closeSubpath()
        let jib = CGMutablePath()
        jib.move(to: CGPoint(x: -size * 0.03, y: size * 0.7))
        jib.addLine(to: CGPoint(x: -size * 0.26, y: size * 0.3))
        jib.addLine(to: CGPoint(x: -size * 0.03, y: size * 0.3))
        jib.closeSubpath()
        let flag = CGMutablePath()
        flag.move(to: CGPoint(x: 0, y: size * 0.85))
        flag.addLine(to: CGPoint(x: size * 0.14, y: size * 0.8))
        flag.addLine(to: CGPoint(x: 0, y: size * 0.75))
        flag.closeSubpath()
        craft.addSublayer(shape(mast, fill: nil, stroke: rgb(0x6D4C41), width: 1.5))
        craft.addSublayer(shape(sail, fill: rgb(0xFFFFFF), stroke: rgb(0x90A4AE), width: 1))
        craft.addSublayer(shape(jib, fill: rgb(0xFFF3E0), stroke: rgb(0x90A4AE), width: 1))
        craft.addSublayer(shape(flag, fill: rgb(0xE53935)))
        craft.addSublayer(shape(hull, fill: rgb(0x1E88E5), stroke: rgb(0x0D47A1), width: 1.2))
        craft.add(keyframes("transform.rotation.z", [-0.07, 0.07, -0.07], duration: 1.3, repeats: Float(duration / 1.3)),
                  forKey: "rock")
        let waves = CGMutablePath()
        let reach = size * 1.6
        waves.move(to: CGPoint(x: -reach, y: size * 0.05))
        var x = -reach
        var up = true
        while x < reach {
            waves.addQuadCurve(to: CGPoint(x: x + size * 0.2, y: size * 0.05),
                               control: CGPoint(x: x + size * 0.1, y: size * (up ? 0.16 : -0.06)))
            x += size * 0.2
            up.toggle()
        }
        let sea = shape(waves, fill: nil, stroke: rgb(0x4FC3F7, 0.9), width: 2)
        sea.lineCap = .round
        sea.add(keyframes("transform.translation.x", [0, size * 0.4], duration: 0.8, repeats: Float(duration / 0.8)),
                forKey: "roll")
        let way: CGFloat = toX >= fromX ? 1 : -1
        let turn = holder(at: .zero)
        turn.transform = CATransform3DMakeScale(way, 1, 1)
        turn.addSublayer(craft)
        turn.addSublayer(sea)
        let sailer = holder(at: CGPoint(x: fromX, y: water))
        sailer.addSublayer(turn)
        let cruise = CABasicAnimation(keyPath: "position")
        cruise.fromValue = NSValue(point: CGPoint(x: fromX, y: water))
        cruise.toValue = NSValue(point: CGPoint(x: toX, y: water))
        cruise.duration = duration
        cruise.fillMode = .forwards
        cruise.isRemovedOnCompletion = false
        sailer.position = CGPoint(x: toX, y: water)
        sailer.add(cruise, forKey: "sail")
        parent.addSublayer(sailer)
        NotchMascotPlayEffects.remove(sailer, after: duration + 0.1)
    }
    // MARK: The bin
    /// A waste bin `size` tall with eyes going through `stops` at `times`
    /// over `duration`, waddling; its lid pops up at each of `burps` (0 to 1).
    static func trashCan(in parent: CALayer, size: CGFloat, stops: [CGPoint], times: [NSNumber], duration: TimeInterval,
                         burps: [Double]) {
        let bin = holder(at: stops.first ?? .zero)
        let w = size * 0.7, h = size * 0.8
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -w * 0.42, y: 0))
        body.addLine(to: CGPoint(x: w * 0.42, y: 0))
        body.addLine(to: CGPoint(x: w / 2, y: h))
        body.addLine(to: CGPoint(x: -w / 2, y: h))
        body.closeSubpath()
        let ridges = CGMutablePath()
        for t in [-0.22, 0, 0.22] as [CGFloat] {
            ridges.move(to: CGPoint(x: w * t * 0.9, y: h * 0.1))
            ridges.addLine(to: CGPoint(x: w * t, y: h * 0.62))
        }
        let waddle = holder(at: .zero)
        waddle.addSublayer(shape(body, fill: rgb(0x90A4AE), stroke: rgb(0x455A64), width: 1.5))
        waddle.addSublayer(shape(ridges, fill: nil, stroke: rgb(0x607D8B), width: 1.5))
        let eyes = CGMutablePath()
        eyes.addPath(ellipse(CGPoint(x: -w * 0.16, y: h * 0.78), w * 0.08, w * 0.1))
        eyes.addPath(ellipse(CGPoint(x: w * 0.16, y: h * 0.78), w * 0.08, w * 0.1))
        waddle.addSublayer(shape(eyes, fill: rgb(0xFFFFFF), stroke: rgb(0x455A64), width: 0.8))
        let pupils = CGMutablePath()
        pupils.addPath(ellipse(CGPoint(x: -w * 0.14, y: h * 0.77), w * 0.035, w * 0.045))
        pupils.addPath(ellipse(CGPoint(x: w * 0.18, y: h * 0.77), w * 0.035, w * 0.045))
        waddle.addSublayer(shape(pupils, fill: rgb(0x212121)))
        let lid = holder(at: CGPoint(x: 0, y: h))
        lid.addSublayer(shape(CGPath(roundedRect: CGRect(x: -w * 0.56, y: 0, width: w * 1.12, height: h * 0.1),
                                     cornerWidth: 2, cornerHeight: 2, transform: nil),
                              fill: rgb(0x78909C), stroke: rgb(0x455A64), width: 1.2))
        lid.addSublayer(shape(CGPath(roundedRect: CGRect(x: -w * 0.12, y: h * 0.1, width: w * 0.24, height: h * 0.07),
                                     cornerWidth: 2, cornerHeight: 2, transform: nil), fill: rgb(0x546E7A)))
        waddle.addSublayer(lid)
        var lifts: [CGFloat] = [0]
        var marks: [Double] = [0]
        for burp in burps.sorted() {
            lifts += [0, h * 0.35, 0]
            marks += [max(marks.last ?? 0, burp - 0.01), burp + 0.015, min(1, burp + 0.05)]
        }
        lifts.append(0)
        marks.append(1)
        lid.add(keyframes("transform.translation.y", lifts, times: marks.map { NSNumber(value: $0) }, duration: duration),
                forKey: "burp")
        waddle.add(keyframes("transform.rotation.z", [-0.08, 0.08, -0.08], duration: 0.45, repeats: Float(duration / 0.45)),
                   forKey: "waddle")
        bin.addSublayer(waddle)
        let move = keyframes("position", points(stops), times: times, duration: duration)
        bin.position = stops.last ?? .zero
        bin.add(move, forKey: "move")
        bin.add(keyframes("opacity", [0, 1, 1, 0], times: [0, 0.05, 0.95, 1], duration: duration), forKey: "fade")
        bin.opacity = 0
        parent.addSublayer(bin)
        NotchMascotPlayEffects.remove(bin, after: duration + 0.1)
    }
    /// A ball of crumpled paper spat from `mouth` to `spot` after `spillAt`,
    /// lying there until `tossAt`, then thrown back into `mouth`.
    static func paperBall(in parent: CALayer, mouth: CGPoint, spot: CGPoint, size: CGFloat, spillAt: TimeInterval,
                          tossAt: TimeInterval, flight: TimeInterval = 0.6) {
        let ball = holder(at: mouth)
        ball.addSublayer(shape(ellipse(.zero, size / 2, size * 0.45), fill: rgb(0xF5F5F5), stroke: rgb(0x9E9E9E), width: 1))
        let creases = CGMutablePath()
        creases.move(to: CGPoint(x: -size * 0.25, y: size * 0.1))
        creases.addLine(to: CGPoint(x: 0, y: -size * 0.05))
        creases.addLine(to: CGPoint(x: size * 0.2, y: size * 0.15))
        creases.move(to: CGPoint(x: -size * 0.1, y: -size * 0.25))
        creases.addLine(to: CGPoint(x: size * 0.05, y: -size * 0.05))
        ball.addSublayer(shape(creases, fill: nil, stroke: rgb(0xBDBDBD), width: 1))
        let total = tossAt + flight
        let rest = CGPoint(x: spot.x, y: spot.y + size * 0.45)
        let apex1 = CGPoint(x: (mouth.x + rest.x) / 2, y: max(mouth.y, rest.y) + size * 3)
        let apex2 = CGPoint(x: (mouth.x + rest.x) / 2, y: max(mouth.y, rest.y) + size * 3.5)
        let stops = [mouth, mouth, apex1, rest, rest, apex2, mouth]
        let marks = [0, spillAt, spillAt + flight / 2, spillAt + flight, tossAt, tossAt + flight / 2, total]
            .map { NSNumber(value: $0 / total) }
        let path = keyframes("position", points(stops), times: marks, duration: total)
        path.calculationMode = .cubic
        let show = keyframes("opacity", [0, 0, 1, 1, 0], times: [0, NSNumber(value: spillAt / total),
                                                                 NSNumber(value: (spillAt + 0.01) / total),
                                                                 NSNumber(value: (total - 0.05) / total), 1],
                             duration: total)
        ball.position = mouth
        ball.opacity = 0
        ball.add(path, forKey: "path")
        ball.add(show, forKey: "show")
        ball.add(keyframes("transform.rotation.z", [0, CGFloat.pi * 2], duration: 0.5, repeats: Float(total / 0.5)),
                 forKey: "spin")
        parent.addSublayer(ball)
        NotchMascotPlayEffects.remove(ball, after: total + 0.1)
    }
    // MARK: Coffee
    /// A steaming cup of coffee `size` tall set down on `floor` at `x`,
    /// dropping in and staying `duration`; empty after `emptyAt` (0 to 1).
    static func coffee(in parent: CALayer, x: CGFloat, floor: CGFloat, size: CGFloat, duration: TimeInterval,
                       emptyAt: Double) {
        let cup = holder(at: CGPoint(x: x, y: floor))
        cup.addSublayer(shape(ellipse(CGPoint(x: 0, y: size * 0.04), size * 0.5, size * 0.07), fill: rgb(0xECEFF1),
                              stroke: rgb(0x90A4AE), width: 1))
        let handle = CGMutablePath()
        handle.addArc(center: CGPoint(x: size * 0.3, y: size * 0.42), radius: size * 0.14, startAngle: -.pi / 2,
                      endAngle: .pi / 2, clockwise: false)
        cup.addSublayer(shape(handle, fill: nil, stroke: rgb(0xFAFAFA), width: max(2, size * 0.07)))
        let mug = CGMutablePath()
        mug.move(to: CGPoint(x: -size * 0.3, y: size * 0.7))
        mug.addLine(to: CGPoint(x: size * 0.3, y: size * 0.7))
        mug.addLine(to: CGPoint(x: size * 0.24, y: size * 0.08))
        mug.addLine(to: CGPoint(x: -size * 0.24, y: size * 0.08))
        mug.closeSubpath()
        cup.addSublayer(shape(mug, fill: rgb(0xFAFAFA), stroke: rgb(0xB0BEC5), width: 1.2))
        cup.addSublayer(shape(CGPath(rect: CGRect(x: -size * 0.27, y: size * 0.36, width: size * 0.54, height: size * 0.1),
                                     transform: nil), fill: rgb(0xD84315)))
        let brew = shape(ellipse(CGPoint(x: 0, y: size * 0.68), size * 0.28, size * 0.05), fill: rgb(0x5D4037))
        brew.add(keyframes("opacity", [1, 1, 0], times: [0, NSNumber(value: emptyAt), NSNumber(value: min(1, emptyAt + 0.02))],
                           duration: duration), forKey: "drunk")
        cup.addSublayer(brew)
        for index in 0..<3 {
            let wisp = CGMutablePath()
            let x0 = (CGFloat(index) - 1) * size * 0.14
            wisp.move(to: CGPoint(x: x0, y: size * 0.78))
            wisp.addQuadCurve(to: CGPoint(x: x0, y: size * 1.05), control: CGPoint(x: x0 + size * 0.1, y: size * 0.9))
            wisp.addQuadCurve(to: CGPoint(x: x0, y: size * 1.3), control: CGPoint(x: x0 - size * 0.1, y: size * 1.18))
            let steam = shape(wisp, fill: nil, stroke: rgb(0xFFFFFF, 0.7), width: 1.5)
            steam.lineCap = .round
            let rise = keyframes("opacity", [0, 0.8, 0], duration: 1.6, repeats: Float(duration * emptyAt / 1.6))
            rise.beginTime = CACurrentMediaTime() + Double(index) * 0.5
            steam.opacity = 0
            steam.add(rise, forKey: "rise")
            cup.addSublayer(steam)
        }
        let drop = keyframes("position", points([CGPoint(x: x, y: floor + size * 2), CGPoint(x: x, y: floor),
                                                 CGPoint(x: x, y: floor + size * 0.15), CGPoint(x: x, y: floor)]),
                             times: [0, 0.6, 0.8, 1], duration: 0.5)
        cup.add(drop, forKey: "drop")
        cup.add(keyframes("opacity", [0, 1, 1, 0], times: [0, 0.03, 0.94, 1], duration: duration), forKey: "fade")
        cup.opacity = 0
        parent.addSublayer(cup)
        NotchMascotPlayEffects.remove(cup, after: duration + 0.1)
    }
}
