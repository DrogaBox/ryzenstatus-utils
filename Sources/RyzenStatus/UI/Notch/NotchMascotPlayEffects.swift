// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The light the companions make playing together on the desktop: blades,
/// gathered energy, beams, sparks, flashes, aura bursts, lightning, a star
/// handed over, and the notes, hearts and z's that float off them. Each
/// draws into a layer whose y grows upward and takes itself away once done.
enum NotchMascotPlayEffects {
    static func color(_ energy: NotchMascotPlay.Energy, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: energy.red, green: energy.green, blue: energy.blue, alpha: alpha)
    }

    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// Where a sound is heard for something at `x` in `layer`, across every
    /// display: on a stage over a whole display, where it happens on screen;
    /// in the island, the two sides kept apart about where the island is.
    /// Across the layer alone when it is in no window.
    static func pan(x: CGFloat, in layer: CALayer) -> Float {
        let local = NotchMascotSoundMap.pan(x: x, width: layer.bounds.width)
        var root = layer
        while let above = root.superlayer { root = above }
        guard let view = root.delegate as? NSView, let window = view.window else { return local }
        let screens = NSScreen.screens.map(\.frame)
        if screens.contains(window.frame) {
            let inWindow = view.convert(layer.convert(CGPoint(x: x, y: 0), to: root), to: nil)
            return NotchMascotSoundMap.pan(screenX: window.convertPoint(toScreen: inWindow).x, across: screens)
        }
        return NotchMascotSoundMap.pan(local, about: NotchMascotSoundMap.pan(screenX: window.frame.midX, across: screens))
    }

    /// Takes `layer` away after `delay` seconds.
    static func remove(_ layer: CALayer, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak layer] in layer?.removeFromSuperlayer() }
    }

    private static func scale(of parent: CALayer) -> CGFloat {
        parent.contentsScale > 0 ? parent.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
    }

    // MARK: A blade

    /// A blade of light held at `hand`, pointing up and leaning `direction`
    /// (right when positive), `length` long. It lights from the hilt up.
    @discardableResult
    static func blade(in parent: CALayer, hand: CGPoint, direction: CGFloat, length: CGFloat,
                      energy: NotchMascotPlay.Energy) -> CALayer {
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        holder.position = hand
        holder.transform = CATransform3DMakeRotation(guardAngle(direction), 0, 0, 1)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: length))
        let glow = CAShapeLayer()
        glow.path = path
        glow.strokeColor = color(energy)
        glow.lineWidth = max(3, length * 0.09)
        glow.lineCap = .round
        glow.shadowColor = color(energy)
        glow.shadowOpacity = 1
        glow.shadowRadius = max(3, length * 0.12)
        glow.shadowOffset = .zero
        let core = CAShapeLayer()
        core.path = path
        core.strokeColor = white
        core.lineWidth = max(1.2, length * 0.035)
        core.lineCap = .round
        let hilt = CAShapeLayer()
        hilt.path = CGPath(roundedRect: CGRect(x: -1.6, y: -length * 0.2, width: 3.2, height: length * 0.2),
                           cornerWidth: 1, cornerHeight: 1, transform: nil)
        hilt.fillColor = CGColor(srgbRed: 0.55, green: 0.57, blue: 0.62, alpha: 1)
        [glow, core].forEach { layer in
            layer.fillColor = nil
            let light = CABasicAnimation(keyPath: "strokeEnd")
            light.fromValue = 0
            light.toValue = 1
            light.duration = 0.22
            light.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(light, forKey: "light")
        }
        holder.addSublayer(hilt)
        holder.addSublayer(glow)
        holder.addSublayer(core)
        // A hum: the glow breathes.
        let hum = CABasicAnimation(keyPath: "shadowRadius")
        hum.fromValue = glow.shadowRadius * 0.7
        hum.toValue = glow.shadowRadius * 1.3
        hum.duration = 0.12
        hum.autoreverses = true
        hum.repeatCount = .infinity
        glow.add(hum, forKey: "hum")
        parent.addSublayer(holder)
        return holder
    }

    /// The angle a blade is held at, ready: leaning forward.
    private static func guardAngle(_ direction: CGFloat) -> CGFloat { direction > 0 ? -0.55 : 0.55 }

    /// Swings `blade` forward and back.
    static func swing(_ blade: CALayer, direction: CGFloat) {
        let rest = guardAngle(direction)
        let strike = rest + (direction > 0 ? -1.15 : 1.15)
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = [rest, rest - (strike - rest) * 0.3, strike, rest]
        swing.keyTimes = [0, 0.3, 0.55, 1]
        swing.duration = 0.38
        swing.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
                                 CAMediaTimingFunction(name: .easeInEaseOut)]
        blade.add(swing, forKey: "swing")
    }

    /// Puts `blade` out, from the tip down, and takes it away.
    static func sheathe(_ blade: CALayer) {
        for case let shape as CAShapeLayer in blade.sublayers ?? [] where shape.lineWidth > 0 && shape.fillColor == nil {
            shape.strokeEnd = 0
            let out = CABasicAnimation(keyPath: "strokeEnd")
            out.fromValue = 1
            out.toValue = 0
            out.duration = 0.2
            shape.add(out, forKey: "out")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.18
        fade.duration = 0.12
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        blade.add(fade, forKey: "fade")
        remove(blade, after: 0.35)
    }

    // MARK: Energy

    /// A ball of energy gathering at `point`, growing to `radius` over
    /// `duration` and throbbing while it lasts, `life` seconds in all.
    @discardableResult
    static func orb(in parent: CALayer, at point: CGPoint, radius: CGFloat, energy: NotchMascotPlay.Energy,
                    duration: TimeInterval, life: TimeInterval) -> CALayer {
        let orb = CAGradientLayer()
        orb.type = .radial
        orb.colors = [white, color(energy), color(energy, alpha: 0.35), color(energy, alpha: 0)]
        orb.locations = [0, 0.3, 0.62, 1]
        orb.startPoint = CGPoint(x: 0.5, y: 0.5)
        orb.endPoint = CGPoint(x: 1, y: 1)
        orb.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        orb.position = point
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.05
        grow.toValue = 1
        grow.duration = max(0.05, duration)
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let throb = CABasicAnimation(keyPath: "transform.scale")
        throb.fromValue = 0.9
        throb.toValue = 1.1
        throb.duration = 0.09
        throb.autoreverses = true
        throb.repeatCount = .infinity
        throb.beginTime = CACurrentMediaTime() + grow.duration
        orb.add(grow, forKey: "grow")
        orb.add(throb, forKey: "throb")
        parent.addSublayer(orb)
        remove(orb, after: life)
        return orb
    }

    /// A beam of energy from `start` to `end`, `thickness` across, that
    /// shoots out and holds for `life` seconds, with a ball at its head.
    static func beam(in parent: CALayer, from start: CGPoint, to end: CGPoint, thickness: CGFloat,
                     energy: NotchMascotPlay.Energy, life: TimeInterval) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 1 else { return }
        let beam = CAGradientLayer()
        beam.colors = [color(energy, alpha: 0), color(energy, alpha: 0.8), white, color(energy, alpha: 0.8),
                       color(energy, alpha: 0)]
        beam.locations = [0, 0.22, 0.5, 0.78, 1]
        beam.startPoint = CGPoint(x: 0.5, y: 0)
        beam.endPoint = CGPoint(x: 0.5, y: 1)
        beam.anchorPoint = CGPoint(x: 0, y: 0.5)
        beam.bounds = CGRect(x: 0, y: 0, width: length, height: thickness)
        beam.position = start
        beam.transform = CATransform3DMakeRotation(atan2(end.y - start.y, end.x - start.x), 0, 0, 1)
        beam.shadowColor = color(energy)
        beam.shadowOpacity = 0.9
        beam.shadowRadius = thickness * 0.6
        beam.shadowOffset = .zero
        let shoot = CABasicAnimation(keyPath: "bounds.size.width")
        shoot.fromValue = 0
        shoot.toValue = length
        shoot.duration = 0.16
        shoot.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let flicker = CABasicAnimation(keyPath: "bounds.size.height")
        flicker.fromValue = thickness * 0.8
        flicker.toValue = thickness * 1.15
        flicker.duration = 0.06
        flicker.autoreverses = true
        flicker.repeatCount = .infinity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + max(0, life - 0.18)
        fade.duration = 0.18
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        beam.add(shoot, forKey: "shoot")
        beam.add(flicker, forKey: "flicker")
        beam.add(fade, forKey: "fade")
        parent.addSublayer(beam)
        remove(beam, after: life + 0.05)
        // Its head rides out with it and stays at the end.
        let head = orb(in: parent, at: end, radius: thickness * 1.1, energy: energy, duration: 0.16, life: life)
        let ride = CABasicAnimation(keyPath: "position")
        ride.fromValue = NSValue(point: start)
        ride.toValue = NSValue(point: end)
        ride.duration = 0.16
        head.add(ride, forKey: "ride")
    }

    /// A bright burst at `point`, `radius` wide at its biggest.
    static func flash(in parent: CALayer, at point: CGPoint, radius: CGFloat, energy: NotchMascotPlay.Energy) {
        let flash = CAGradientLayer()
        flash.type = .radial
        flash.colors = [white, color(energy, alpha: 0.85), color(energy, alpha: 0)]
        flash.locations = [0, 0.35, 1]
        flash.startPoint = CGPoint(x: 0.5, y: 0.5)
        flash.endPoint = CGPoint(x: 1, y: 1)
        flash.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        flash.position = point
        flash.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flash.add(group, forKey: "flash")
        parent.addSublayer(flash)
        remove(flash, after: 0.5)
    }

    /// Sparks flying out from `point`.
    static func sparks(in parent: CALayer, at point: CGPoint, reach: CGFloat, energy: NotchMascotPlay.Energy,
                       count: Int = 9) {
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.25...0.25)
            let spark = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: reach * 0.35, y: 0))
            spark.path = path
            spark.strokeColor = index.isMultiple(of: 3) ? white : color(energy)
            spark.lineWidth = 1.6
            spark.lineCap = .round
            spark.position = point
            spark.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            spark.opacity = 0
            let fly = CABasicAnimation(keyPath: "position")
            let far = reach * CGFloat.random(in: 0.7...1.1)
            fly.fromValue = NSValue(point: point)
            fly.toValue = NSValue(point: CGPoint(x: point.x + cos(angle) * far, y: point.y + sin(angle) * far))
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [fly, fade]
            group.duration = 0.4
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            spark.add(group, forKey: "spark")
            parent.addSublayer(spark)
            remove(spark, after: 0.45)
        }
    }

    /// A ring of its aura bursting out from `point`, with streaks rising.
    static func auraBurst(in parent: CALayer, at point: CGPoint, radius: CGFloat, energy: NotchMascotPlay.Energy) {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * 0.7, width: radius * 2, height: radius * 1.4),
                           transform: nil)
        ring.fillColor = color(energy, alpha: 0.18)
        ring.strokeColor = color(energy)
        ring.lineWidth = 2
        ring.shadowColor = color(energy)
        ring.shadowOpacity = 1
        ring.shadowRadius = 5
        ring.shadowOffset = .zero
        ring.position = point
        ring.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.1
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.2, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "burst")
        parent.addSublayer(ring)
        remove(ring, after: 0.55)
        for _ in 0..<6 {
            let streak = CAShapeLayer()
            let height = radius * CGFloat.random(in: 0.5...0.9)
            streak.path = CGPath(roundedRect: CGRect(x: -1, y: 0, width: 2, height: height),
                                 cornerWidth: 1, cornerHeight: 1, transform: nil)
            streak.fillColor = color(energy)
            let start = CGPoint(x: point.x + CGFloat.random(in: -radius * 0.8...radius * 0.8),
                                y: point.y - radius * 0.6)
            streak.position = start
            streak.opacity = 0
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = start.y
            rise.toValue = start.y + radius * 1.4
            let fadeStreak = CAKeyframeAnimation(keyPath: "opacity")
            fadeStreak.values = [0, 0.9, 0]
            let streaks = CAAnimationGroup()
            streaks.animations = [rise, fadeStreak]
            streaks.duration = 0.55
            streaks.beginTime = CACurrentMediaTime() + Double.random(in: 0...0.15)
            streak.add(streaks, forKey: "rise")
            parent.addSublayer(streak)
            remove(streak, after: 0.8)
        }
    }

    /// Lightning crackling round `point` for a moment.
    static func lightning(in parent: CALayer, around point: CGPoint, radius: CGFloat, energy: NotchMascotPlay.Energy) {
        for index in 0..<3 {
            let bolt = CAShapeLayer()
            let path = CGMutablePath()
            let angle = CGFloat.random(in: 0...(.pi * 2))
            var spot = CGPoint(x: point.x + cos(angle) * radius * 0.4, y: point.y + sin(angle) * radius * 0.4)
            path.move(to: spot)
            for _ in 0..<4 {
                spot = CGPoint(x: spot.x + cos(angle) * radius * 0.18 + CGFloat.random(in: -4...4),
                               y: spot.y + sin(angle) * radius * 0.18 + CGFloat.random(in: -4...4))
                path.addLine(to: spot)
            }
            bolt.path = path
            bolt.fillColor = nil
            bolt.strokeColor = index == 0 ? white : color(energy)
            bolt.lineWidth = 1.3
            bolt.lineJoin = .miter
            bolt.shadowColor = color(energy)
            bolt.shadowOpacity = 1
            bolt.shadowRadius = 3
            bolt.shadowOffset = .zero
            bolt.opacity = 0
            let blink = CAKeyframeAnimation(keyPath: "opacity")
            blink.values = [0, 1, 0.2, 1, 0]
            blink.duration = 0.22
            blink.beginTime = CACurrentMediaTime() + Double(index) * 0.07
            bolt.add(blink, forKey: "blink")
            parent.addSublayer(bolt)
            remove(bolt, after: 0.5)
        }
    }

    // MARK: Little things

    /// `symbol` floating up from `point` and fading, `count` of them one
    /// after another, drifting side to side.
    static func float(_ symbol: String, in parent: CALayer, at point: CGPoint, size: CGFloat, color: CGColor,
                      count: Int = 1, rise: CGFloat = 34) {
        for index in 0..<count {
            let text = CATextLayer()
            text.string = symbol
            text.font = NSFont.systemFont(ofSize: size, weight: .heavy)
            text.fontSize = size
            text.foregroundColor = color
            text.alignmentMode = .center
            text.contentsScale = scale(of: parent)
            text.bounds = CGRect(x: 0, y: 0, width: size * 1.4, height: size * 1.4)
            let start = CGPoint(x: point.x + CGFloat.random(in: -size * 0.5...size * 0.5), y: point.y)
            text.position = start
            text.opacity = 0
            text.shadowColor = CGColor(gray: 0, alpha: 0.6)
            text.shadowOpacity = 1
            text.shadowRadius = 1.5
            text.shadowOffset = .zero
            let drift = CAKeyframeAnimation(keyPath: "position")
            let side: CGFloat = Bool.random() ? 1 : -1
            drift.values = [start, CGPoint(x: start.x + side * size * 0.4, y: start.y + rise * 0.5),
                            CGPoint(x: start.x - side * size * 0.2, y: start.y + rise)].map { NSValue(point: $0) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.15, 0.7, 1]
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.4, 1.15, 1]
            pop.keyTimes = [0, 0.2, 1]
            let group = CAAnimationGroup()
            group.animations = [drift, fade, pop]
            group.duration = 1.3
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.35
            text.add(group, forKey: "float")
            parent.addSublayer(text)
            remove(text, after: 1.4 + Double(index) * 0.35)
        }
    }

    /// A star handed along an arc from `start` to `end` over `duration`,
    /// sparkling as it goes.
    static func star(in parent: CALayer, from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
        let gold = CGColor(srgbRed: 1, green: 0.86, blue: 0.3, alpha: 1)
        let text = CATextLayer()
        text.string = "★"
        text.font = NSFont.systemFont(ofSize: 16, weight: .black)
        text.fontSize = 16
        text.foregroundColor = gold
        text.alignmentMode = .center
        text.contentsScale = scale(of: parent)
        text.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        text.position = end
        text.shadowColor = gold
        text.shadowOpacity = 1
        text.shadowRadius = 4
        text.shadowOffset = .zero
        let arc = CGMutablePath()
        arc.move(to: start)
        arc.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 60))
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = arc
        fly.duration = duration
        fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -CGFloat.pi * 2
        spin.duration = duration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + duration
        fade.duration = 0.25
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        text.add(fly, forKey: "fly")
        text.add(spin, forKey: "spin")
        text.add(fade, forKey: "fade")
        parent.addSublayer(text)
        remove(text, after: duration + 0.3)
        let energy = NotchMascotPlay.Energy(red: 1, green: 0.86, blue: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak parent] in
            guard let parent else { return }
            sparks(in: parent, at: end, reach: 18, energy: energy, count: 7)
        }
    }
}

// MARK: - The Wonder Boy props

/// Doors, coins, smoke, arcade markers and the things thrown between the
/// two, as shape layers: paths and colours only, sharp at any scale.
extension NotchMascotPlayEffects {
    /// A layer `side` points square holding `parts`, centred on `point` in a
    /// parent whose y grows upward. The parts are drawn y-down.
    static func propLayer(_ parts: [NotchMascotWearablePart], side: CGFloat, at point: CGPoint,
                          scale scaleFactor: CGFloat) -> CALayer {
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        holder.position = point
        holder.isGeometryFlipped = true
        for part in parts {
            let layer = CAShapeLayer()
            layer.frame = holder.bounds
            layer.contentsScale = scaleFactor
            layer.path = part.path
            layer.fillColor = part.fill
            layer.strokeColor = part.stroke
            layer.lineWidth = part.lineWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            holder.addSublayer(layer)
        }
        return holder
    }

    private static func fadeOut(after delay: TimeInterval, length: TimeInterval = 0.25) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + delay
        fade.duration = length
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        return fade
    }

    // MARK: Secret door

    /// A stone door that grows out of the floor at `base`, swings open to
    /// a warm light, stays `duration` seconds and closes. `height` is the
    /// door's, and its width a little over half of it.
    static func secretDoor(in parent: CALayer, at base: CGPoint, height: CGFloat, duration: TimeInterval) {
        NotchMascotSound.play(.creak, pan: pan(x: base.x, in: parent))
        let width = height * 0.62
        let side = max(width, height)
        let rect = CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height)
        let closed = NotchMascotRPGShapes.door(in: rect, open: 0)
        let open = NotchMascotRPGShapes.door(in: rect, open: 1)
        let holder = propLayer(closed, side: side, at: CGPoint(x: base.x, y: base.y + height / 2),
                               scale: scale(of: parent))
        // The leaf and its knob swing; the arch and the light stay.
        if holder.sublayers?.count == closed.count {
            for index in [2, 3] {
                guard let layer = holder.sublayers?[index] as? CAShapeLayer else { continue }
                let swing = CAKeyframeAnimation(keyPath: "path")
                swing.values = [closed[index].path, open[index].path, open[index].path, closed[index].path]
                swing.keyTimes = [0, 0.25, 0.8, 1]
                swing.duration = duration
                layer.add(swing, forKey: "swing")
            }
        }
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.2, 1.08, 1, 1, 0.2]
        grow.keyTimes = [0, 0.15, 0.25, 0.85, 1]
        let appear = CAKeyframeAnimation(keyPath: "opacity")
        appear.values = [0, 1, 1, 1, 0]
        appear.keyTimes = [0, 0.1, 0.25, 0.85, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, appear]
        group.duration = duration
        holder.opacity = 0
        holder.add(group, forKey: "door")
        // The light the open door throws.
        let glow = CAShapeLayer()
        glow.path = CGPath(ellipseIn: CGRect(x: -width * 0.5, y: -height * 0.35, width: width * 2, height: height * 0.7),
                           transform: nil)
        glow.position = CGPoint(x: side / 2, y: side / 2)
        glow.fillColor = CGColor(srgbRed: 1, green: 0.91, blue: 0.64, alpha: 0.32)
        holder.insertSublayer(glow, at: 0)
        parent.addSublayer(holder)
        remove(holder, after: duration + 0.1)
    }

    /// A treasure chest that drops onto the desktop floor at `base`, pops open its lid,
    /// and showers sparkling gold coins for both companions to enjoy.
    static func treasureChest(in parent: CALayer, at base: CGPoint, size: CGFloat, duration: TimeInterval) {
        NotchMascotSound.play(.chime, pan: pan(x: base.x, in: parent))
        let width = size * 1.15
        let height = size * 0.9
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        holder.position = CGPoint(x: base.x, y: base.y + height / 2)
        holder.contentsScale = scale(of: parent)

        let rgb = NotchMascotRPGShapes.rgb
        let body = CAShapeLayer()
        body.bounds = CGRect(x: 0, y: 0, width: width, height: height * 0.55)
        body.position = CGPoint(x: width / 2, y: height * 0.28)
        body.path = CGPath(roundedRect: body.bounds, cornerWidth: width * 0.08, cornerHeight: width * 0.08, transform: nil)
        body.fillColor = rgb(0x8A5A2B)
        body.strokeColor = rgb(0x4A2E12)
        body.lineWidth = max(1, width * 0.04)

        let latch = CAShapeLayer()
        latch.bounds = CGRect(x: 0, y: 0, width: width * 0.16, height: height * 0.22)
        latch.position = CGPoint(x: width / 2, y: height * 0.45)
        latch.path = CGPath(roundedRect: latch.bounds, cornerWidth: 2, cornerHeight: 2, transform: nil)
        latch.fillColor = rgb(0xFFD23F)
        latch.strokeColor = rgb(0xB28E10)
        latch.lineWidth = 1

        let lid = CAShapeLayer()
        lid.bounds = CGRect(x: 0, y: 0, width: width * 1.04, height: height * 0.45)
        lid.position = CGPoint(x: width / 2, y: height * 0.72)
        let lidPath = CGMutablePath()
        lidPath.move(to: CGPoint(x: 0, y: 0))
        lidPath.addQuadCurve(to: CGPoint(x: width * 1.04, y: 0), control: CGPoint(x: width * 0.52, y: height * 0.38))
        lidPath.closeSubpath()
        lid.path = lidPath
        lid.fillColor = rgb(0xA06A32)
        lid.strokeColor = rgb(0x4A2E12)
        lid.lineWidth = max(1, width * 0.04)

        holder.addSublayer(body)
        holder.addSublayer(latch)
        holder.addSublayer(lid)

        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.1, 1.15, 1, 1, 0.2]
        grow.keyTimes = [0, 0.15, 0.25, 0.85, 1]

        let appear = CAKeyframeAnimation(keyPath: "opacity")
        appear.values = [0, 1, 1, 1, 0]
        appear.keyTimes = [0, 0.08, 0.25, 0.85, 1]

        let openLid = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        openLid.values = [0, 0, -0.45, -0.45, 0]
        openLid.keyTimes = [0, 0.22, 0.35, 0.85, 1]

        let group = CAAnimationGroup()
        group.animations = [grow, appear]
        group.duration = duration
        holder.add(group, forKey: "chest")
        lid.add(openLid, forKey: "openLid")

        parent.addSublayer(holder)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotchMascotSound.play(.coin, pan: pan(x: base.x, in: parent))
            goldCoins(in: parent, at: CGPoint(x: base.x, y: base.y + height * 0.4), radius: width * 0.12, count: 8)
            sparks(in: parent, at: CGPoint(x: base.x, y: base.y + height * 0.5), reach: width * 0.45,
                   energy: NotchMascotPlay.Energy(red: 1, green: 0.85, blue: 0.25), count: 10)
        }

        remove(holder, after: duration + 0.1)
    }

    // MARK: Coins

    /// Gold coins thrown up from `point` that fall back and bounce twice,
    /// each turning on its edge as it goes.
    static func goldCoins(in parent: CALayer, at point: CGPoint, radius: CGFloat, count: Int = 7) {
        let factor = scale(of: parent)
        for index in 0..<count {
            let side = radius * 2.4
            let holder = propLayer(NotchMascotRPGShapes.coin(at: CGPoint(x: side / 2, y: side / 2), radius: radius),
                                   side: side, at: point, scale: factor)
            let drift = CGFloat(index - count / 2) * radius * 1.6 + CGFloat.random(in: -radius...radius)
            let floorY = point.y - radius * 2
            let apex = point.y + radius * CGFloat.random(in: 5...8)
            let path = CGMutablePath()
            path.move(to: point)
            path.addQuadCurve(to: CGPoint(x: point.x + drift * 0.55, y: floorY),
                              control: CGPoint(x: point.x + drift * 0.25, y: apex * 2 - floorY))
            path.addQuadCurve(to: CGPoint(x: point.x + drift * 0.85, y: floorY),
                              control: CGPoint(x: point.x + drift * 0.7, y: floorY + radius * 3))
            path.addQuadCurve(to: CGPoint(x: point.x + drift, y: floorY),
                              control: CGPoint(x: point.x + drift * 0.92, y: floorY + radius * 1.2))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.duration = 1.1
            move.beginTime = CACurrentMediaTime() + Double(index) * 0.06
            move.fillMode = .both
            let turn = CAKeyframeAnimation(keyPath: "transform.scale.x")
            turn.values = [1, 0.2, 1, 0.2, 1, 0.2, 1]
            turn.keyTimes = [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1]
            turn.duration = 1.1
            turn.beginTime = move.beginTime
            turn.fillMode = .both
            holder.opacity = 0
            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0, 1, 1, 0]
            show.keyTimes = [0, 0.05, 0.85, 1]
            show.duration = 1.2
            show.beginTime = move.beginTime
            show.fillMode = .both
            holder.add(move, forKey: "arc")
            holder.add(turn, forKey: "turn")
            holder.add(show, forKey: "show")
            parent.addSublayer(holder)
            remove(holder, after: 1.4 + Double(index) * 0.06)
        }
    }

    // MARK: Smoke

    /// Puffs of arcane smoke rising from `point` in the colour of `energy`,
    /// with a few lit motes: the mark of a transformation.
    static func magicSmoke(in parent: CALayer, at point: CGPoint, radius: CGFloat, energy: NotchMascotPlay.Energy,
                           count: Int = 7) {
        for index in 0..<count {
            let size = radius * CGFloat.random(in: 0.5...0.9)
            let puff = CAShapeLayer()
            puff.path = CGPath(ellipseIn: CGRect(x: -size, y: -size, width: size * 2, height: size * 2), transform: nil)
            let tone: CGFloat = index.isMultiple(of: 2) ? 0.92 : 0.7
            puff.fillColor = CGColor(srgbRed: energy.red * 0.5 + tone * 0.5, green: energy.green * 0.4 + tone * 0.4,
                                     blue: energy.blue * 0.5 + tone * 0.5, alpha: 0.78)
            let start = CGPoint(x: point.x + CGFloat.random(in: -radius...radius) * 0.6, y: point.y)
            puff.position = start
            puff.opacity = 0
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: start)
            rise.toValue = NSValue(point: CGPoint(x: start.x + CGFloat.random(in: -radius...radius) * 0.5,
                                                  y: start.y + radius * CGFloat.random(in: 1.4...2.2)))
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.3
            grow.toValue = 1.5
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.85, 0.6, 0]
            fade.keyTimes = [0, 0.2, 0.6, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, grow, fade]
            group.duration = 1.0
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.05
            group.fillMode = .both
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            puff.add(group, forKey: "smoke")
            parent.addSublayer(puff)
            remove(puff, after: 1.2 + Double(index) * 0.05)
        }
        sparks(in: parent, at: point, reach: radius * 1.4, energy: energy, count: 6)
    }

    // MARK: Arcade markers

    /// A marker such as `+100`, `♥ +1` or `1UP`, lit in pixels over `point`,
    /// that pops, rises and fades. `cell` is one pixel's side.
    static func arcadeMarker(_ text: String, in parent: CALayer, at point: CGPoint, cell: CGFloat) {
        let size = NotchMascotRPGShapes.pixelSize(text, cell: cell)
        guard size.width > 0 else { return }
        if let effect = NotchMascotSoundMap.effect(forMarker: text) {
            NotchMascotSound.play(effect, pan: pan(x: point.x, in: parent))
        }
        let path = NotchMascotRPGShapes.pixelPath(text, cell: cell)
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        holder.position = point
        holder.isGeometryFlipped = true
        let shadow = CAShapeLayer()
        shadow.frame = holder.bounds.offsetBy(dx: cell * 0.6, dy: cell * 0.6)
        shadow.path = path
        shadow.fillColor = CGColor(gray: 0, alpha: 0.7)
        let lit = CAShapeLayer()
        lit.frame = holder.bounds
        lit.path = path
        lit.fillColor = NotchMascotRPGShapes.markerColor(text)
        lit.contentsScale = scale(of: parent)
        shadow.contentsScale = lit.contentsScale
        holder.addSublayer(shadow)
        holder.addSublayer(lit)
        holder.opacity = 0
        let rise = CABasicAnimation(keyPath: "position")
        rise.fromValue = NSValue(point: point)
        rise.toValue = NSValue(point: CGPoint(x: point.x, y: point.y + cell * 9))
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.4, 1.3, 1]
        pop.keyTimes = [0, 0.2, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.1, 0.75, 1]
        let group = CAAnimationGroup()
        group.animations = [rise, pop, fade]
        group.duration = NotchMascotIslandPlay.markerLength
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        holder.add(group, forKey: "marker")
        parent.addSublayer(holder)
        remove(holder, after: NotchMascotIslandPlay.markerLength + 0.1)
    }

    // MARK: Things in flight

    /// What a `thing` looks like in flight, in a square of side `side`.
    static func thingParts(_ thing: NotchMascotIslandPlay.Thing, side: CGFloat,
                           energy: NotchMascotPlay.Energy) -> [NotchMascotWearablePart] {
        let c = CGPoint(x: side / 2, y: side / 2)
        let rgb = NotchMascotRPGShapes.rgb
        if let parts = NotchMascotRPGShapes.prop(thing, at: c, side: side) { return parts }
        switch thing {
        case .heart:
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: c.x, y: c.y + side * 0.38))
            heart.addCurve(to: CGPoint(x: c.x, y: c.y - side * 0.12),
                           control1: CGPoint(x: c.x - side * 0.6, y: c.y + side * 0.1),
                           control2: CGPoint(x: c.x - side * 0.34, y: c.y - side * 0.48))
            heart.addCurve(to: CGPoint(x: c.x, y: c.y + side * 0.38),
                           control1: CGPoint(x: c.x + side * 0.34, y: c.y - side * 0.48),
                           control2: CGPoint(x: c.x + side * 0.6, y: c.y + side * 0.1))
            return [NotchMascotWearablePart(path: heart, fill: rgb(0xFF5E8A))]
        case .star:
            let star = CGMutablePath()
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi - .pi / 2
                let r = side * (i.isMultiple(of: 2) ? 0.48 : 0.2)
                let point = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            return [NotchMascotWearablePart(path: star, fill: rgb(0xFFD23F), stroke: rgb(0xD99A1E), lineWidth: max(0.5, side * 0.04))]
        case .note:
            var shift = CGAffineTransform(translationX: side * 0.12, y: side * 0.1)
            let glyph = NotchMascotRPGShapes.pixelPath("♪", cell: side / 4).copy(using: &shift) ?? CGMutablePath()
            return [NotchMascotWearablePart(path: glyph, fill: rgb(0xFFFFFF))]
        case .spark:
            return [NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(c, side * 0.3), fill: color(energy))]
        case .snowball:
            return [NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(c, side * 0.34), fill: rgb(0xFFFFFF),
                                            stroke: rgb(0xCFE6FF), lineWidth: max(0.5, side * 0.04))]
        case .flower:
            let petals = CGMutablePath()
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                petals.addPath(NotchMascotWearableShapes.circle(CGPoint(x: c.x + CGFloat(cos(a)) * side * 0.2,
                                                                         y: c.y + CGFloat(sin(a)) * side * 0.2), side * 0.14))
            }
            return [NotchMascotWearablePart(path: petals, fill: rgb(0xFF8FB1)),
                    NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(c, side * 0.1), fill: rgb(0xFFD23F))]
        case .cookie:
            let chips = CGMutablePath()
            for (dx, dy) in [(-0.14, -0.1), (0.12, -0.04), (0.0, 0.16)] as [(CGFloat, CGFloat)] {
                chips.addPath(NotchMascotWearableShapes.circle(CGPoint(x: c.x + dx * side, y: c.y + dy * side), side * 0.05))
            }
            return [NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(c, side * 0.36), fill: rgb(0xC68642)),
                    NotchMascotWearablePart(path: chips, fill: rgb(0x5C3B1E))]
        case .coin:
            return NotchMascotRPGShapes.coin(at: c, radius: side * 0.36)
        case .ball:
            let seam = CGMutablePath()
            seam.addArc(center: c, radius: side * 0.22, startAngle: -.pi * 0.3, endAngle: .pi * 0.3, clockwise: false)
            return [NotchMascotWearablePart(path: NotchMascotWearableShapes.circle(c, side * 0.34), fill: rgb(0xFFFFFF),
                                            stroke: rgb(0xCFC9BC), lineWidth: max(0.5, side * 0.04)),
                    NotchMascotWearablePart(path: seam, fill: nil, stroke: rgb(0xE5384F), lineWidth: max(0.5, side * 0.05))]
        default:
            return []
        }
    }

    /// `thing` thrown along a high arc from `start` to `end` over `duration`,
    /// turning as it goes, and gone on arrival or, `falls`, dropped short.
    /// With `alive`, its landing is heard only if `alive` still answers true.
    static func fly(_ thing: NotchMascotIslandPlay.Thing, in parent: CALayer, from start: CGPoint, to end: CGPoint,
                    duration: TimeInterval, side: CGFloat = 16, falls: Bool = false,
                    energy: NotchMascotPlay.Energy = NotchMascotPlay.Energy(red: 1, green: 0.86, blue: 0.3),
                    while alive: (() -> Bool)? = nil) {
        NotchMascotSound.play(NotchMascotSoundMap.launch(of: thing), pan: pan(x: start.x, in: parent))
        if !falls {
            let landing = NotchMascotSoundMap.landing(of: thing)
            let heard = pan(x: end.x, in: parent)
            if let alive {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.92) {
                    if alive() { NotchMascotSound.play(landing, pan: heard) }
                }
            } else {
                NotchMascotSound.play(landing, pan: heard, after: duration * 0.92)
            }
        }
        let holder = propLayer(thingParts(thing, side: side, energy: energy), side: side, at: start,
                               scale: scale(of: parent))
        let target = falls ? CGPoint(x: start.x + (end.x - start.x) * 0.7, y: min(start.y, end.y) - side) : end
        let arc = CGMutablePath()
        arc.move(to: start)
        arc.addQuadCurve(to: target, control: CGPoint(x: (start.x + target.x) / 2, y: max(start.y, target.y) + 60))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = arc
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        let spins: Bool
        switch thing {
        case .star, .ball, .coin, .cookie, .flower, .boomerang, .sword: spins = true
        default: spins = false
        }
        if spins {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -CGFloat.pi * 2 * (end.x >= start.x ? 1 : -1)
            spin.duration = duration
            holder.add(spin, forKey: "spin")
        }
        // Things that point travel facing their way.
        if end.x < start.x, !spins { holder.transform = CATransform3DMakeScale(-1, 1, 1) }
        holder.add(move, forKey: "fly")
        holder.add(fadeOut(after: duration), forKey: "fade")
        parent.addSublayer(holder)
        remove(holder, after: duration + 0.3)
    }

    // MARK: Bursts

    /// A little burst over `point`, `size` points across: confetti, sparkles,
    /// hearts, magic, a shower of coins, a puff of smoke or a door.
    static func burst(_ burst: NotchMascotIslandPlay.Burst, in parent: CALayer, at point: CGPoint, size: CGFloat,
                      energy: NotchMascotPlay.Energy, duration: TimeInterval = NotchMascotIslandPlay.burstLength) {
        if burst != .door {
            NotchMascotSound.play(NotchMascotSoundMap.effect(for: burst), pan: pan(x: point.x, in: parent))
        }
        switch burst {
        case .coins: goldCoins(in: parent, at: point, radius: max(3, size * 0.13))
        case .smoke: magicSmoke(in: parent, at: point, radius: size * 0.5, energy: energy)
        case .door: secretDoor(in: parent, at: CGPoint(x: point.x, y: point.y - size * 0.7), height: size * 1.4, duration: duration)
        case .magic: magicSmoke(in: parent, at: point, radius: size * 0.35, energy: energy, count: 3)
        case .sparkles: sparks(in: parent, at: point, reach: size * 0.9, energy: NotchMascotPlay.Energy(red: 1, green: 0.89, blue: 0.48), count: 9)
        case .hearts: float("♥", in: parent, at: point, size: max(9, size * 0.32), color: NotchMascotRPGShapes.rgb(0xFF5E8A), count: 3)
        case .confetti:
            let colors: [UInt32] = [0xFF5E8A, 0xFFD23F, 0x6C8CFF, 0x3FB8AF, 0xFF8C2B, 0xB57CFF]
            for index in 0..<10 {
                let piece = CAShapeLayer()
                piece.path = CGPath(rect: CGRect(x: -2, y: -3, width: 4, height: 6), transform: nil)
                piece.fillColor = NotchMascotRPGShapes.rgb(colors[index % colors.count])
                piece.position = point
                let angle = CGFloat(index) / 10 * .pi * 2
                let far = size * CGFloat.random(in: 0.6...1.1)
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: point)
                move.toValue = NSValue(point: CGPoint(x: point.x + cos(angle) * far, y: point.y + sin(angle) * far - size * 0.3))
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = CGFloat.pi * 3
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                let group = CAAnimationGroup()
                group.animations = [move, spin, fade]
                group.duration = 0.9
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                piece.add(group, forKey: "confetti")
                parent.addSublayer(piece)
                remove(piece, after: 1.0)
            }
        }
    }
}

/// A clear layer over the companion's own window, for what it holds and
/// what floats off it; its y grows upward.
final class NotchMascotPlayLayerView: NSView {
    /// What to draw into: its y grows upward whatever the layers above it do.
    let canvas = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        canvas.masksToBounds = false
        layer?.addSublayer(canvas)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        orient()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        orient()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        canvas.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Undoes any flip above the canvas, so a point's y counts up from the
    /// bottom as the screen's does.
    private func orient() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        var flipped = false
        var above = layer
        while let current = above {
            if current.isGeometryFlipped { flipped.toggle() }
            above = current.superlayer
        }
        if canvas.isGeometryFlipped != flipped { canvas.isGeometryFlipped = flipped }
        canvas.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    /// Takes away everything drawn.
    func clear() {
        canvas.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}

/// A transparent floating panel that NEVER takes or intercepts mouse events under any circumstance.
private final class NotchMascotPassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A clear window over the whole screen the companions play on, for what
/// passes between them: beams, sparks where blades meet, a star handed over.
/// It takes no clicks and shows only while they play.
final class NotchMascotPlayStage {
    private var panel: NSPanel?
    private var view: NotchMascotPlayLayerView?

    /// The layer to draw into over `screen`, in screen points less the
    /// screen's origin; `point(_:)` turns a screen point into its own.
    func layer(over screen: NSScreen) -> CALayer? {
        let panel = self.panel ?? makePanel()
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
            panel.ignoresMouseEvents = true
        }
        view?.frame = CGRect(origin: .zero, size: screen.frame.size)
        view?.layoutSubtreeIfNeeded()
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        panel.ignoresMouseEvents = true
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
        return view?.canvas
    }

    func point(_ screenPoint: CGPoint) -> CGPoint {
        guard let panel else { return screenPoint }
        return CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }

    /// Clears it and puts it away.
    func close() {
        view?.clear()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NotchMascotPassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                           defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Over the companions, as what they hold is.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.setAccessibilityElement(false)
        let view = NotchMascotPlayLayerView(frame: .zero)
        panel.contentView = view
        self.panel = panel
        self.view = view
        return panel
    }
}
