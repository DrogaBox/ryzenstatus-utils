// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import QuartzCore

/// What the fair and the field bring by a companion out on the desktop: a
/// flutter of butterflies drifting across, and a fish that leaps out of the
/// floor and back in. Drawn with Core Animation like the other rare things,
/// so nothing ticks in the app. Stage coordinates grow downward.
extension NotchMascotEncounterArt {
    private static func fairColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func fairShape(_ path: CGPath, fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private static func fairOval(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    private static func fairFrames(_ keyPath: String, _ values: [Any], times: [NSNumber]? = nil, duration: TimeInterval,
                                   repeats: Float = 1, beginTime: CFTimeInterval = 0) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.repeatCount = repeats
        animation.beginTime = beginTime == 0 ? 0 : CACurrentMediaTime() + beginTime
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// `count` butterflies, `size` points across, fluttering from `start` to
    /// `end` over `duration` along wavy paths of their own, wings beating.
    static func butterflies(in parent: CALayer, from start: CGPoint, to end: CGPoint, count: Int, size: CGFloat,
                            duration: TimeInterval) {
        let palettes: [(UInt32, UInt32)] = [(0xFFB347, 0xE07B00), (0x8EC5FF, 0x3A7BD5), (0xF7A1D1, 0xD0488F),
                                           (0xFFE066, 0xC9A400), (0xB9F18C, 0x5BA829)]
        for index in 0..<max(1, count) {
            let fly = CALayer()
            let (light, dark) = palettes[index % palettes.count]
            let wingSpan = size * (0.8 + CGFloat(index % 3) * 0.12)
            // Each wing on its own layer, hinged at the body, so it beats.
            for side in [CGFloat(-1), 1] {
                let wing = CALayer()
                wing.anchorPoint = CGPoint(x: side < 0 ? 1 : 0, y: 0.5)
                wing.bounds = CGRect(x: 0, y: 0, width: wingSpan / 2, height: wingSpan)
                wing.position = .zero
                let upper = fairOval(CGPoint(x: side < 0 ? wingSpan * 0.25 : wingSpan * 0.25, y: wingSpan * 0.32),
                                     wingSpan * 0.24, wingSpan * 0.26)
                let lower = fairOval(CGPoint(x: wingSpan * 0.22, y: wingSpan * 0.7), wingSpan * 0.17, wingSpan * 0.19)
                wing.addSublayer(fairShape(upper, fill: fairColor(light), stroke: fairColor(dark), width: max(0.6, size * 0.04)))
                wing.addSublayer(fairShape(lower, fill: fairColor(light), stroke: fairColor(dark), width: max(0.6, size * 0.04)))
                wing.addSublayer(fairShape(fairOval(CGPoint(x: wingSpan * 0.26, y: wingSpan * 0.3), wingSpan * 0.06, wingSpan * 0.06),
                                           fill: fairColor(dark)))
                wing.add(fairFrames("transform.scale.x", [1, 0.2, 1], duration: 0.22 + Double(index % 2) * 0.05,
                                    repeats: .infinity), forKey: "beat")
                fly.addSublayer(wing)
            }
            let body = fairShape(fairOval(.zero, size * 0.06, wingSpan * 0.32), fill: fairColor(0x2B2B33))
            fly.addSublayer(body)
            // A wavy path of its own across, a little higher or lower.
            let lane = (CGFloat(index) - CGFloat(count - 1) / 2) * size * 0.9
            var points: [NSValue] = []
            let steps = 8
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let wave = sin(t * .pi * 3 + CGFloat(index)) * size * 1.2
                points.append(NSValue(point: CGPoint(x: start.x + (end.x - start.x) * t,
                                                     y: start.y + (end.y - start.y) * t + lane + wave)))
            }
            let lag = Double(index) * 0.35
            fly.add(fairFrames("position", points, duration: duration - lag, beginTime: lag), forKey: "flutter")
            fly.add(fairFrames("opacity", [0, 1, 1, 0], times: [0, 0.1, 0.85, 1], duration: duration - lag, beginTime: lag),
                    forKey: "fade")
            fly.opacity = 0
            fly.position = points.last?.pointValue ?? end
            parent.addSublayer(fly)
            NotchMascotPlayEffects.remove(fly, after: duration + 0.2)
        }
    }

    /// A fish `size` points long leaping from `start` to `end`, rising
    /// `height` points at the top of its arc, over `duration`, with a splash
    /// where it goes out and where it comes back in.
    static func leapingFish(in parent: CALayer, from start: CGPoint, to end: CGPoint, height: CGFloat, size: CGFloat,
                            duration: TimeInterval) {
        let fish = CALayer()
        let bodyPath = fairOval(.zero, size * 0.5, size * 0.24)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: -size * 0.42, y: 0))
        tail.addLine(to: CGPoint(x: -size * 0.75, y: -size * 0.22))
        tail.addLine(to: CGPoint(x: -size * 0.75, y: size * 0.22))
        tail.closeSubpath()
        let fin = CGMutablePath()
        fin.move(to: CGPoint(x: -size * 0.1, y: -size * 0.2))
        fin.addLine(to: CGPoint(x: size * 0.08, y: -size * 0.38))
        fin.addLine(to: CGPoint(x: size * 0.18, y: -size * 0.18))
        fin.closeSubpath()
        let scales = CGMutablePath()
        for dx in [-0.18, 0.0, 0.18] as [CGFloat] {
            scales.move(to: CGPoint(x: size * dx, y: -size * 0.12))
            scales.addQuadCurve(to: CGPoint(x: size * dx, y: size * 0.12), control: CGPoint(x: size * (dx + 0.08), y: 0))
        }
        let ink = fairColor(0x1C2433)
        fish.addSublayer(fairShape(tail, fill: fairColor(0xF08A24), stroke: ink, width: max(0.6, size * 0.04)))
        fish.addSublayer(fairShape(fin, fill: fairColor(0xF08A24), stroke: ink, width: max(0.6, size * 0.04)))
        fish.addSublayer(fairShape(bodyPath, fill: fairColor(0xFFA94D), stroke: ink, width: max(0.6, size * 0.05)))
        fish.addSublayer(fairShape(scales, fill: nil, stroke: fairColor(0xE07B00), width: max(0.5, size * 0.03)))
        fish.addSublayer(fairShape(fairOval(CGPoint(x: size * 0.3, y: -size * 0.05), size * 0.06, size * 0.06), fill: ink))
        // The arc, and the fish turned along it.
        let steps = 10
        var points: [NSValue] = []
        var angles: [NSNumber] = []
        let direction: CGFloat = end.x >= start.x ? 1 : -1
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t - height * 4 * t * (1 - t)
            points.append(NSValue(point: CGPoint(x: x, y: y)))
            let slope = (end.y - start.y) - height * 4 * (1 - 2 * t)
            angles.append(NSNumber(value: Double(atan2(slope, (end.x - start.x)))))
        }
        if direction < 0 { fish.transform = CATransform3DMakeScale(-1, 1, 1) }
        let leap = fairFrames("position", points, duration: duration)
        leap.timingFunction = CAMediaTimingFunction(name: .linear)
        fish.add(leap, forKey: "leap")
        fish.add(fairFrames("transform.rotation.z", angles, duration: duration), forKey: "turn")
        fish.add(fairFrames("opacity", [0, 1, 1, 0], times: [0, 0.06, 0.94, 1], duration: duration), forKey: "fade")
        fish.position = end
        fish.opacity = 0
        parent.addSublayer(fish)
        NotchMascotPlayEffects.remove(fish, after: duration + 0.2)
        splash(in: parent, at: start, size: size, after: 0)
        splash(in: parent, at: end, size: size, after: duration * 0.92)
    }

    /// A ring of drops thrown up and out from `point`.
    private static func splash(in parent: CALayer, at point: CGPoint, size: CGFloat, after delay: TimeInterval) {
        let holder = CALayer()
        holder.position = point
        for index in 0..<6 {
            let angle = -CGFloat.pi * (0.15 + CGFloat(index) / 5 * 0.7)
            let drop = fairShape(fairOval(.zero, size * 0.07, size * 0.1), fill: fairColor(0x7FC8FF, 0.9))
            let reach = size * (0.6 + CGFloat(index % 2) * 0.3)
            let out = CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
            drop.add(fairFrames("position", [NSValue(point: .zero), NSValue(point: out),
                                             NSValue(point: CGPoint(x: out.x * 1.2, y: out.y * 0.2 + size * 0.3))],
                                duration: 0.6, beginTime: delay), forKey: "throw")
            drop.add(fairFrames("opacity", [0, 1, 0], duration: 0.6, beginTime: delay), forKey: "fade")
            drop.opacity = 0
            holder.addSublayer(drop)
        }
        let ring = fairShape(fairOval(.zero, size * 0.5, size * 0.12), fill: nil, stroke: fairColor(0x7FC8FF, 0.8),
                             width: max(0.8, size * 0.05))
        ring.add(fairFrames("transform.scale", [0.2, 1.4], duration: 0.6, beginTime: delay), forKey: "spread")
        ring.add(fairFrames("opacity", [0, 1, 0], duration: 0.6, beginTime: delay), forKey: "fade")
        ring.opacity = 0
        holder.addSublayer(ring)
        parent.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: delay + 0.8)
    }
}
