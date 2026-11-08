// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import QuartzCore

/// The weather that passes over a companion out on the desktop: a rain
/// cloud that drifts across above it, dropping rain all the way, and the
/// stars that come out when gravity lets go. Drawn with Core Animation
/// like the other rare things, so nothing ticks in the app.
extension NotchMascotEncounterArt {
    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func layer(_ path: CGPath, fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineCap = .round
        return layer
    }

    private static func oval(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    private static func frames(_ keyPath: String, _ values: [Any], times: [NSNumber]? = nil, duration: TimeInterval,
                               repeats: Float = 1, beginTime: CFTimeInterval = 0) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.repeatCount = repeats
        animation.beginTime = beginTime == 0 ? 0 : CACurrentMediaTime() + beginTime
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }

    /// A grey cloud `width` wide drifting from `start` to `end`, over
    /// `duration`, rain falling `reach` points under it the whole way.
    static func rainCloud(in parent: CALayer, from start: CGPoint, to end: CGPoint, width: CGFloat, reach: CGFloat,
                          duration: TimeInterval) {
        let cloud = CALayer()
        cloud.position = start
        let unit = width / 10
        let grey = color(0x8C93A3), dark = color(0x6E7585)
        for (dx, dy, r) in [(-3.0, 0.4, 2.1), (-1.0, -0.8, 2.8), (1.6, -0.2, 2.5), (3.4, 0.6, 1.9), (0.2, 1.0, 2.2)] as [(CGFloat, CGFloat, CGFloat)] {
            cloud.addSublayer(layer(oval(CGPoint(x: dx * unit, y: dy * unit), r * unit, r * unit * 0.9), fill: grey,
                                    stroke: dark, width: 0.8))
        }
        cloud.addSublayer(layer(oval(CGPoint(x: 0, y: 1.2 * unit), 4.4 * unit, 1.6 * unit), fill: grey))
        // Drops falling in rows, each on its own beat.
        let drop = color(0x7FB8FF, 0.9)
        for index in 0..<7 {
            let x = (CGFloat(index) - 3) * unit * 1.25
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 2.4 * unit))
            path.addLine(to: CGPoint(x: x - unit * 0.3, y: 2.4 * unit + unit * 1.2))
            let streak = layer(path, fill: nil, stroke: drop, width: max(1, unit * 0.25))
            let fall = frames("transform.translation.y", [0, reach], duration: 0.7 + Double(index % 3) * 0.1,
                              repeats: .infinity, beginTime: Double(index) * 0.11)
            let drift = frames("transform.translation.x", [0, -reach * 0.25], duration: 0.7 + Double(index % 3) * 0.1,
                               repeats: .infinity, beginTime: Double(index) * 0.11)
            let fade = frames("opacity", [0.9, 0.9, 0], times: [0, 0.7, 1], duration: 0.7 + Double(index % 3) * 0.1,
                              repeats: .infinity, beginTime: Double(index) * 0.11)
            streak.add(fall, forKey: "fall")
            streak.add(drift, forKey: "drift")
            streak.add(fade, forKey: "fade")
            cloud.addSublayer(streak)
        }
        cloud.add(frames("position", [NSValue(point: start), NSValue(point: end)], duration: duration), forKey: "drift")
        cloud.add(frames("opacity", [0, 1, 1, 0], times: [0, 0.08, 0.9, 1], duration: duration), forKey: "fade")
        cloud.add(frames("transform.translation.y", [0, -unit * 0.4, 0], duration: 2.6, repeats: .infinity), forKey: "bob")
        cloud.position = end
        parent.addSublayer(cloud)
        NotchMascotPlayEffects.remove(cloud, after: duration + 0.1)
    }

    /// A few little stars that wink on around `center`, `reach` points
    /// about, while gravity is off, and go when it comes back.
    static func weightlessStars(in parent: CALayer, around center: CGPoint, reach: CGFloat, duration: TimeInterval) {
        let holder = CALayer()
        holder.position = center
        for index in 0..<6 {
            let angle = CGFloat(index) / 6 * .pi * 2
            let distance = reach * (0.6 + CGFloat(index % 2) * 0.35)
            let point = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            let path = CGMutablePath()
            let r = max(1.5, reach * 0.05)
            path.move(to: CGPoint(x: point.x - r, y: point.y)); path.addLine(to: CGPoint(x: point.x + r, y: point.y))
            path.move(to: CGPoint(x: point.x, y: point.y - r)); path.addLine(to: CGPoint(x: point.x, y: point.y + r))
            let star = layer(path, fill: nil, stroke: color(0xFFF1A8), width: max(1, r * 0.5))
            star.add(frames("opacity", [0, 1, 0.2, 1, 0], times: [0, 0.2, 0.5, 0.8, 1], duration: duration,
                            beginTime: Double(index) * 0.15), forKey: "twinkle")
            star.add(frames("transform.translation.y", [0, -reach * 0.3], duration: duration), forKey: "rise")
            holder.addSublayer(star)
        }
        parent.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: duration + 1)
    }
}
