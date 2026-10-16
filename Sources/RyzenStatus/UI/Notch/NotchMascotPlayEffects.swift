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
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        view?.frame = CGRect(origin: .zero, size: screen.frame.size)
        view?.layoutSubtreeIfNeeded()
        panel.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        if !panel.isVisible { panel.orderFrontRegardless() }
        return view?.canvas
    }

    func point(_ screenPoint: CGPoint) -> CGPoint {
        guard let panel else { return screenPoint }
        return CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }

    /// Clears it and puts it away.
    func close() {
        view?.clear()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
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
