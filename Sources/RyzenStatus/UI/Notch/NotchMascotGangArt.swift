// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What the gang's comings, goings and plays together are drawn with, in
/// the clear layer over the screen: parachutes, balloons, a green pipe, a
/// beam of light, a box, a campfire, goals, a camera, a cake, a blanket, a
/// kite and its storm, water and speech bubbles. Each draws itself, moves
/// along its way and takes itself away. Points are the layer's own, y up.
enum NotchMascotGangArt {
    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
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

    /// Fades `layer` in at once and out over its last moments, gone after `duration`.
    private static func show(_ layer: CALayer, in parent: CALayer, for duration: TimeInterval, fade: TimeInterval = 0.3) {
        let share = NSNumber(value: min(0.45, fade / max(duration, 0.01)))
        let end = NSNumber(value: 1 - share.doubleValue)
        layer.opacity = 0
        layer.add(keyframes("opacity", [0, 1, 1, 0], times: [0, share, end, 1], duration: duration), forKey: "show")
        parent.addSublayer(layer)
        NotchMascotPlayEffects.remove(layer, after: duration + 0.1)
    }

    private static func text(_ string: String, size: CGFloat, color: CGColor, in parent: CALayer) -> CATextLayer {
        let text = CATextLayer()
        text.string = string
        text.font = NSFont.systemFont(ofSize: size, weight: .heavy)
        text.fontSize = size
        text.foregroundColor = color
        text.alignmentMode = .center
        text.contentsScale = parent.contentsScale > 0 ? parent.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
        text.bounds = CGRect(x: 0, y: 0, width: size * 1.6, height: size * 1.35)
        return text
    }

    // MARK: Comings and goings

    /// A striped canopy on lines, its harness at `from`, coming straight down
    /// to `to` over `duration`, where it folds up and goes.
    static func parachute(in parent: CALayer, from start: CGPoint, to end: CGPoint, size: CGFloat, duration: TimeInterval) {
        let chute = holder(at: start)
        let width = size * 1.9, lift = size * 1.45
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -width / 2, y: lift))
        canopy.addCurve(to: CGPoint(x: width / 2, y: lift), control1: CGPoint(x: -width / 2, y: lift + width * 0.62),
                        control2: CGPoint(x: width / 2, y: lift + width * 0.62))
        canopy.addQuadCurve(to: CGPoint(x: -width / 2, y: lift), control: CGPoint(x: 0, y: lift + width * 0.12))
        chute.addSublayer(shape(canopy, fill: rgb(0xFF5E5E), stroke: rgb(0x9E2B2B), width: 1.2))
        let stripes = CGMutablePath()
        for share in [-0.17, 0.17] as [CGFloat] {
            stripes.move(to: CGPoint(x: width * share, y: lift + width * 0.06))
            stripes.addQuadCurve(to: CGPoint(x: width * share * 0.6, y: lift + width * 0.46),
                                 control: CGPoint(x: width * share * 1.1, y: lift + width * 0.3))
        }
        chute.addSublayer(shape(stripes, fill: nil, stroke: rgb(0xFFFFFF, 0.85), width: width * 0.07))
        let lines = CGMutablePath()
        for x in [-width / 2, -width / 6, width / 6, width / 2] {
            lines.move(to: CGPoint(x: x, y: lift))
            lines.addLine(to: CGPoint(x: x * 0.18, y: size * 0.75))
        }
        chute.addSublayer(shape(lines, fill: nil, stroke: rgb(0x2B2B2B, 0.8), width: 0.8))
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start)
        move.toValue = NSValue(point: end)
        move.duration = duration
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        chute.position = end
        chute.add(move, forKey: "fall")
        chute.add(keyframes("transform.rotation.z", [0, 0.08, 0, -0.08, 0], duration: 1.6,
                            repeats: Float(duration / 1.6)), forKey: "sway")
        let fold = keyframes("transform.scale.y", [1, 1, 0.1], times: [0, NSNumber(value: duration / (duration + 0.5)), 1],
                             duration: duration + 0.5)
        chute.add(fold, forKey: "fold")
        show(chute, in: parent, for: duration + 0.5, fade: 0.35)
    }

    /// A round balloon on a string, the string's end at `from`, carried to
    /// `to` over `duration`, bobbing as it goes.
    static func balloon(in parent: CALayer, from start: CGPoint, to end: CGPoint, size: CGFloat, duration: TimeInterval,
                        color: CGColor = rgb(0xFF4F7B)) {
        let mover = holder(at: start)
        let radius = size * 0.52, rise = size * 1.55
        let string = CGMutablePath()
        string.move(to: .zero)
        string.addCurve(to: CGPoint(x: 0, y: rise - radius), control1: CGPoint(x: size * 0.12, y: rise * 0.3),
                        control2: CGPoint(x: -size * 0.12, y: rise * 0.6))
        mover.addSublayer(shape(string, fill: nil, stroke: rgb(0xEDEDED, 0.9), width: 1))
        let body = CGMutablePath()
        body.addEllipse(in: CGRect(x: -radius, y: rise - radius * 0.2, width: radius * 2, height: radius * 2.3))
        mover.addSublayer(shape(body, fill: color, stroke: rgb(0x000000, 0.25), width: 1))
        let knot = CGMutablePath()
        knot.move(to: CGPoint(x: -radius * 0.18, y: rise - radius * 0.42))
        knot.addLine(to: CGPoint(x: radius * 0.18, y: rise - radius * 0.42))
        knot.addLine(to: CGPoint(x: 0, y: rise - radius * 0.18))
        knot.closeSubpath()
        mover.addSublayer(shape(knot, fill: color))
        mover.addSublayer(shape(CGPath(ellipseIn: CGRect(x: -radius * 0.55, y: rise + radius * 1.1, width: radius * 0.45,
                                                         height: radius * 0.7), transform: nil),
                                fill: rgb(0xFFFFFF, 0.45)))
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start)
        move.toValue = NSValue(point: end)
        move.duration = duration
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        mover.position = end
        mover.add(move, forKey: "carry")
        mover.add(keyframes("transform.rotation.z", [0, 0.05, 0, -0.05, 0], duration: 2.2,
                            repeats: Float(duration / 2.2)), forKey: "bob")
        show(mover, in: parent, for: duration + 0.3, fade: 0.3)
    }

    /// A green pipe rising out of the floor at `base`, `width` across,
    /// standing for `duration` and sinking back.
    static func pipe(in parent: CALayer, at base: CGPoint, width: CGFloat, duration: TimeInterval) {
        let pipe = holder(at: base)
        let height = width * 1.05, lip = width * 0.26
        let green = rgb(0x2FBF4A), dark = rgb(0x146B24), light = rgb(0x8CF09C)
        pipe.addSublayer(shape(CGPath(rect: CGRect(x: -width * 0.42, y: 0, width: width * 0.84, height: height - lip),
                                      transform: nil), fill: green, stroke: dark, width: 2))
        pipe.addSublayer(shape(CGPath(roundedRect: CGRect(x: -width / 2, y: height - lip, width: width, height: lip),
                                      cornerWidth: 3, cornerHeight: 3, transform: nil), fill: green, stroke: dark, width: 2))
        pipe.addSublayer(shape(CGPath(rect: CGRect(x: -width * 0.3, y: 2, width: width * 0.09, height: height - lip - 4),
                                      transform: nil), fill: light))
        pipe.addSublayer(shape(CGPath(rect: CGRect(x: -width * 0.38, y: height - lip + 3, width: width * 0.1,
                                                   height: lip - 6), transform: nil), fill: light))
        let rise = keyframes("transform.scale.y", [0.02, 1, 1, 0.02], times: [0, 0.12, 0.88, 1], duration: duration)
        pipe.add(rise, forKey: "rise")
        NotchMascotSound.play(.boing, pan: NotchMascotPlayEffects.pan(x: base.x, in: parent))
        show(pipe, in: parent, for: duration, fade: 0.15)
    }

    /// A column of light coming down on `base`, rings sliding along it.
    static func beam(in parent: CALayer, at base: CGPoint, width: CGFloat, height: CGFloat, duration: TimeInterval,
                     energy: NotchMascotPlay.Energy) {
        let column = holder(at: base)
        let glow = CAGradientLayer()
        glow.colors = [NotchMascotPlayEffects.color(energy, alpha: 0.75), NotchMascotPlayEffects.color(energy, alpha: 0)]
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.frame = CGRect(x: -width / 2, y: 0, width: width, height: height)
        column.addSublayer(glow)
        let core = CAGradientLayer()
        core.colors = [CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0)]
        core.startPoint = CGPoint(x: 0.5, y: 0)
        core.endPoint = CGPoint(x: 0.5, y: 1)
        core.frame = CGRect(x: -width * 0.15, y: 0, width: width * 0.3, height: height)
        column.addSublayer(core)
        for index in 0..<3 {
            let ring = shape(CGPath(ellipseIn: CGRect(x: -width * 0.6, y: -width * 0.12, width: width * 1.2,
                                                      height: width * 0.24), transform: nil),
                             fill: nil, stroke: NotchMascotPlayEffects.color(energy, alpha: 0.9), width: 2)
            let slide = keyframes("position", points([CGPoint(x: 0, y: height * 0.8), .zero]), duration: 0.7,
                                  repeats: Float(duration / 0.7))
            slide.beginTime = CACurrentMediaTime() + Double(index) * 0.23
            ring.add(slide, forKey: "slide")
            column.addSublayer(ring)
        }
        column.add(keyframes("transform.scale.x", [0.05, 1, 1, 0.05], times: [0, 0.2, 0.8, 1], duration: duration),
                   forKey: "open")
        NotchMascotSound.play(.zap, pan: NotchMascotPlayEffects.pan(x: base.x, in: parent))
        show(column, in: parent, for: duration, fade: 0.2)
    }

    /// A cardboard box on the floor at `base`, its flaps open, that closes,
    /// shakes and slides off toward `away` (right when positive).
    static func box(in parent: CALayer, at base: CGPoint, size: CGFloat, closeAt: TimeInterval, duration: TimeInterval,
                    away: CGFloat) {
        let box = holder(at: base)
        let w = size, h = size * 0.75
        box.addSublayer(shape(CGPath(rect: CGRect(x: -w / 2, y: 0, width: w, height: h), transform: nil),
                              fill: rgb(0xC8A26B), stroke: rgb(0x7A5A2E), width: 1.5))
        box.addSublayer(shape(CGPath(rect: CGRect(x: -w * 0.08, y: h * 0.45, width: w * 0.16, height: h * 0.55),
                                     transform: nil), fill: rgb(0xD9C49A, 0.9)))
        for side in [-1, 1] as [CGFloat] {
            let flap = CAShapeLayer()
            let open = CGMutablePath()
            open.move(to: CGPoint(x: side * w / 2, y: h))
            open.addLine(to: CGPoint(x: side * w * 0.78, y: h + h * 0.42))
            open.addLine(to: CGPoint(x: side * w * 0.3, y: h + h * 0.36))
            open.addLine(to: CGPoint(x: 0, y: h))
            open.closeSubpath()
            let shut = CGMutablePath()
            shut.move(to: CGPoint(x: side * w / 2, y: h))
            shut.addLine(to: CGPoint(x: side * w / 2, y: h + 1))
            shut.addLine(to: CGPoint(x: 0, y: h + 1))
            shut.addLine(to: CGPoint(x: 0, y: h))
            shut.closeSubpath()
            flap.path = open
            flap.fillColor = rgb(0xB48D57)
            flap.strokeColor = rgb(0x7A5A2E)
            flap.lineWidth = 1.2
            let close = keyframes("path", [open, open, shut], times: [0, NSNumber(value: closeAt / duration),
                                                                      NSNumber(value: min(1, (closeAt + 0.3) / duration))],
                                  duration: duration)
            flap.add(close, forKey: "close")
            box.addSublayer(flap)
        }
        let slideStart = NSNumber(value: min(0.95, (closeAt + 0.9) / duration))
        let slide = keyframes("position", points([base, base, CGPoint(x: base.x + away * size * 4, y: base.y)]),
                              times: [0, slideStart, 1], duration: duration)
        box.position = CGPoint(x: base.x + away * size * 4, y: base.y)
        box.add(slide, forKey: "slide")
        let shake = keyframes("transform.rotation.z", [0, 0.06, -0.06, 0.04, 0], duration: 0.5)
        shake.beginTime = CACurrentMediaTime() + closeAt + 0.3
        shake.fillMode = .backwards
        box.add(shake, forKey: "shake")
        show(box, in: parent, for: duration, fade: 0.3)
    }

    // MARK: Around the fire

    /// Logs and a fire on the floor at `base`, flickering for `duration`.
    static func campfire(in parent: CALayer, at base: CGPoint, size: CGFloat, duration: TimeInterval) {
        let fire = holder(at: base)
        let logs = CGMutablePath()
        logs.addRoundedRect(in: CGRect(x: -size * 0.55, y: 0, width: size * 1.1, height: size * 0.16),
                            cornerWidth: size * 0.08, cornerHeight: size * 0.08)
        fire.addSublayer(shape(logs, fill: rgb(0x6B3E1F), stroke: rgb(0x3A1F0C), width: 1.2))
        let cross = shape(logs, fill: rgb(0x7C4A26), stroke: rgb(0x3A1F0C), width: 1.2)
        cross.transform = CATransform3DMakeRotation(0.35, 0, 0, 1)
        fire.addSublayer(cross)
        let glow = shape(CGPath(ellipseIn: CGRect(x: -size * 1.2, y: -size * 0.2, width: size * 2.4, height: size * 1.6),
                                transform: nil), fill: rgb(0xFFB347, 0.18))
        glow.add(keyframes("opacity", [0.7, 1, 0.8, 1, 0.7], duration: 0.9, repeats: Float(duration / 0.9)),
                 forKey: "glow")
        fire.insertSublayer(glow, at: 0)
        for (index, (color, scale)) in [(rgb(0xFF5A1F), 1.0), (rgb(0xFFA21F), 0.7), (rgb(0xFFF07A), 0.4)].enumerated() {
            let flame = CGMutablePath()
            let h = size * 1.1 * scale, w = size * 0.5 * scale
            flame.move(to: CGPoint(x: -w, y: size * 0.1))
            flame.addCurve(to: CGPoint(x: 0, y: size * 0.1 + h), control1: CGPoint(x: -w * 1.1, y: h * 0.6),
                           control2: CGPoint(x: -w * 0.2, y: h * 0.7))
            flame.addCurve(to: CGPoint(x: w, y: size * 0.1), control1: CGPoint(x: w * 0.2, y: h * 0.7),
                           control2: CGPoint(x: w * 1.1, y: h * 0.6))
            flame.closeSubpath()
            let layer = shape(flame, fill: color)
            layer.anchorPoint = .zero
            layer.add(keyframes("transform.scale.y", [1, 1.15, 0.92, 1.1, 1], duration: 0.5 + Double(index) * 0.13,
                                repeats: Float(duration / 0.5)), forKey: "flicker")
            fire.addSublayer(layer)
        }
        show(fire, in: parent, for: duration, fade: 0.6)
    }

    /// A stick held out from `hand` toward `toward` with a marshmallow on
    /// its end that toasts golden, or, `burns`, catches and turns black.
    static func marshmallow(in parent: CALayer, hand: CGPoint, toward: CGFloat, length: CGFloat, duration: TimeInterval,
                            burns: Bool) {
        let stick = holder(at: hand)
        let tip = CGPoint(x: toward * length, y: length * 0.35)
        let line = CGMutablePath()
        line.move(to: .zero)
        line.addLine(to: tip)
        stick.addSublayer(shape(line, fill: nil, stroke: rgb(0x8A5A2B), width: 1.6))
        let puff = shape(CGPath(roundedRect: CGRect(x: tip.x - length * 0.11, y: tip.y - length * 0.09, width: length * 0.22,
                                                    height: length * 0.18), cornerWidth: 3, cornerHeight: 3,
                                transform: nil), fill: rgb(0xFFF8EE), stroke: rgb(0xE0D2BE), width: 0.8)
        let toast = keyframes("fillColor", [rgb(0xFFF8EE), rgb(0xF2C27A), burns ? rgb(0x2B1A10) : rgb(0xD9953F)],
                              duration: duration)
        puff.add(toast, forKey: "toast")
        stick.addSublayer(puff)
        show(stick, in: parent, for: duration + 0.6, fade: 0.3)
        guard burns else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.7) { [weak parent] in
            guard let parent else { return }
            NotchMascotPlayEffects.sparks(in: parent, at: CGPoint(x: hand.x + tip.x, y: hand.y + tip.y), reach: 10,
                                          energy: NotchMascotPlay.Energy(red: 1, green: 0.5, blue: 0.1), count: 6)
        }
    }

    // MARK: The match

    /// A goal standing on the floor at `base`, its open side toward `facing`.
    static func goal(in parent: CALayer, at base: CGPoint, height: CGFloat, facing: CGFloat, duration: TimeInterval) {
        let goal = holder(at: base)
        let depth = height * 0.55
        let frame = CGMutablePath()
        frame.move(to: CGPoint(x: 0, y: 0))
        frame.addLine(to: CGPoint(x: 0, y: height))
        frame.addLine(to: CGPoint(x: -facing * depth, y: height * 0.8))
        frame.addLine(to: CGPoint(x: -facing * depth, y: 0))
        let net = CGMutablePath()
        for step in 1..<5 {
            let share = CGFloat(step) / 5
            net.move(to: CGPoint(x: -facing * depth * share, y: 0))
            net.addLine(to: CGPoint(x: -facing * depth * share, y: height - height * 0.2 * share))
            net.move(to: CGPoint(x: 0, y: height * share * 0.95))
            net.addLine(to: CGPoint(x: -facing * depth, y: height * share * 0.78))
        }
        goal.addSublayer(shape(net, fill: nil, stroke: rgb(0xFFFFFF, 0.45), width: 0.7))
        goal.addSublayer(shape(frame, fill: nil, stroke: rgb(0xFFFFFF), width: 2.4))
        show(goal, in: parent, for: duration, fade: 0.4)
    }

    /// A card held up over `point`: yellow, or red when `red`.
    static func card(in parent: CALayer, at point: CGPoint, size: CGFloat, red: Bool = false) {
        let card = shape(CGPath(roundedRect: CGRect(x: -size * 0.32, y: 0, width: size * 0.64, height: size * 0.9),
                                cornerWidth: 2, cornerHeight: 2, transform: nil),
                         fill: red ? rgb(0xE53935) : rgb(0xFFD600), stroke: rgb(0x000000, 0.35), width: 1)
        card.position = point
        card.add(keyframes("transform.rotation.z", [-0.4, 0.15, 0], duration: 0.3), forKey: "flick")
        show(card, in: parent, for: 1.6, fade: 0.25)
    }

    // MARK: The photo

    /// A camera on a tripod standing on the floor at `base`, facing `facing`.
    static func camera(in parent: CALayer, at base: CGPoint, size: CGFloat, facing: CGFloat, duration: TimeInterval) {
        let camera = holder(at: base)
        let legs = CGMutablePath()
        let top = CGPoint(x: 0, y: size * 0.9)
        for x in [-size * 0.35, 0, size * 0.35] {
            legs.move(to: top)
            legs.addLine(to: CGPoint(x: x, y: 0))
        }
        camera.addSublayer(shape(legs, fill: nil, stroke: rgb(0x3A3A3A), width: 1.6))
        camera.addSublayer(shape(CGPath(roundedRect: CGRect(x: -size * 0.4, y: size * 0.88, width: size * 0.8,
                                                            height: size * 0.5), cornerWidth: 4, cornerHeight: 4,
                                        transform: nil), fill: rgb(0x26282E), stroke: rgb(0x0E0F12), width: 1))
        camera.addSublayer(shape(CGPath(ellipseIn: CGRect(x: facing * size * 0.12 - size * 0.17, y: size * 0.96,
                                                          width: size * 0.34, height: size * 0.34), transform: nil),
                                 fill: rgb(0x5A6B8C), stroke: rgb(0xC9D3E6), width: 1.5))
        camera.addSublayer(shape(CGPath(rect: CGRect(x: -facing * size * 0.3 - size * 0.06, y: size * 1.38,
                                                     width: size * 0.12, height: size * 0.08), transform: nil),
                                 fill: rgb(0xE0E0E0)))
        show(camera, in: parent, for: duration, fade: 0.3)
    }

    /// The flash going off over the whole of `area`.
    static func flash(in parent: CALayer, area: CGRect) {
        let white = CALayer()
        white.frame = area
        white.backgroundColor = CGColor(gray: 1, alpha: 0.85)
        white.add(keyframes("opacity", [0, 1, 0], times: [0, 0.08, 1], duration: 0.45), forKey: "flash")
        white.opacity = 0
        parent.addSublayer(white)
        NotchMascotPlayEffects.remove(white, after: 0.5)
        NotchMascotSound.play(.zap, pan: 0)
    }

    /// The print that slides out after, rising over `point` and spinning
    /// slowly as it falls away.
    static func polaroid(in parent: CALayer, at point: CGPoint, size: CGFloat) {
        let photo = holder(at: point)
        photo.addSublayer(shape(CGPath(rect: CGRect(x: -size / 2, y: -size * 0.6, width: size, height: size * 1.2),
                                       transform: nil), fill: rgb(0xFAFAF5), stroke: rgb(0x000000, 0.2), width: 1))
        let picture = shape(CGPath(rect: CGRect(x: -size * 0.42, y: -size * 0.32, width: size * 0.84, height: size * 0.84),
                                   transform: nil), fill: rgb(0x2A2E3A))
        picture.add(keyframes("fillColor", [rgb(0x2A2E3A), rgb(0x2A2E3A), rgb(0x8FB7E8)], times: [0, 0.3, 1],
                              duration: 1.8), forKey: "develop")
        photo.addSublayer(picture)
        let drift = keyframes("position", points([point, CGPoint(x: point.x + size * 0.6, y: point.y + size * 1.2),
                                                  CGPoint(x: point.x - size * 0.4, y: point.y + size * 0.3)]),
                              duration: 2.6)
        photo.add(drift, forKey: "drift")
        photo.add(keyframes("transform.rotation.z", [0, 0.4, -0.2], duration: 2.6), forKey: "spin")
        show(photo, in: parent, for: 2.7, fade: 0.4)
    }

    // MARK: Little things

    /// A speech bubble over `point` holding `symbol`, for `duration`.
    static func bubble(in parent: CALayer, at point: CGPoint, symbol: String, size: CGFloat, duration: TimeInterval,
                       crackles: Bool = false) {
        let bubble = holder(at: point)
        let w = size * 1.7, h = size * 1.35
        let outline = CGMutablePath()
        outline.addRoundedRect(in: CGRect(x: -w / 2, y: size * 0.3, width: w, height: h), cornerWidth: h * 0.45,
                               cornerHeight: h * 0.45)
        outline.move(to: CGPoint(x: -size * 0.15, y: size * 0.32))
        outline.addLine(to: CGPoint(x: -size * 0.3, y: 0))
        outline.addLine(to: CGPoint(x: size * 0.12, y: size * 0.32))
        bubble.addSublayer(shape(outline, fill: rgb(0xFFFFFF, 0.95),
                                 stroke: crackles ? rgb(0x4FC3F7) : rgb(0x1E1E1E, 0.6), width: crackles ? 1.6 : 1))
        let label = text(symbol, size: size * 0.95, color: rgb(0x2B2B2B), in: parent)
        label.position = CGPoint(x: 0, y: size * 0.3 + h / 2 - size * 0.05)
        bubble.addSublayer(label)
        bubble.add(keyframes("transform.scale", [0.3, 1.12, 1], times: [0, 0.12, 0.2], duration: duration),
                   forKey: "pop")
        show(bubble, in: parent, for: duration, fade: 0.2)
    }

    /// Feathers bursting from `point` and drifting down.
    static func feathers(in parent: CALayer, at point: CGPoint, reach: CGFloat, count: Int = 7) {
        for _ in 0..<count {
            let feather = shape(CGPath(ellipseIn: CGRect(x: -reach * 0.09, y: -reach * 0.03, width: reach * 0.18,
                                                         height: reach * 0.06), transform: nil),
                                fill: rgb(0xFFFFFF, 0.95), stroke: rgb(0xD6D6D6), width: 0.5)
            let out = CGPoint(x: point.x + CGFloat.random(in: -reach...reach), y: point.y + CGFloat.random(in: 0...reach * 0.7))
            let down = CGPoint(x: out.x + CGFloat.random(in: -reach * 0.4...reach * 0.4), y: point.y - reach * 0.9)
            feather.position = down
            feather.add(keyframes("position", points([point, out, down]), times: [0, 0.2, 1], duration: 2.2),
                        forKey: "drift")
            feather.add(keyframes("transform.rotation.z", [0, 1.4, -0.6, 1], duration: 2.2), forKey: "turn")
            show(feather, in: parent, for: 2.2, fade: 0.5)
        }
    }

    /// Snow falling over `area` for `duration`.
    static func snowfall(in parent: CALayer, area: CGRect, duration: TimeInterval, count: Int = 26) {
        for index in 0..<count {
            let radius = CGFloat.random(in: 1.4...3.2)
            let flake = shape(CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                                     transform: nil), fill: rgb(0xFFFFFF, 0.9))
            let x = area.minX + area.width * CGFloat(index) / CGFloat(count) + CGFloat.random(in: -20...20)
            let fall = CABasicAnimation(keyPath: "position")
            fall.fromValue = NSValue(point: CGPoint(x: x, y: area.maxY + 10))
            fall.toValue = NSValue(point: CGPoint(x: x + CGFloat.random(in: -40...40), y: area.minY))
            fall.duration = Double.random(in: 4...7)
            fall.repeatCount = Float(duration / fall.duration) + 1
            fall.beginTime = CACurrentMediaTime() - Double.random(in: 0...fall.duration)
            flake.add(fall, forKey: "fall")
            show(flake, in: parent, for: duration, fade: 0.8)
        }
    }

    /// A cake on the floor at `base` with `candles` lit on top.
    static func cake(in parent: CALayer, at base: CGPoint, size: CGFloat, candles: Int, duration: TimeInterval) {
        let cake = holder(at: base)
        let w = size * 1.2
        cake.addSublayer(shape(CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: size * 0.42),
                                      cornerWidth: 4, cornerHeight: 4, transform: nil),
                               fill: rgb(0xF7C6D9), stroke: rgb(0xC97A9A), width: 1.2))
        cake.addSublayer(shape(CGPath(roundedRect: CGRect(x: -w * 0.36, y: size * 0.42, width: w * 0.72, height: size * 0.3),
                                      cornerWidth: 3, cornerHeight: 3, transform: nil),
                               fill: rgb(0xFFF1F5), stroke: rgb(0xC97A9A), width: 1.2))
        let count = max(1, min(5, candles))
        for index in 0..<count {
            let x = -w * 0.28 + w * 0.56 * CGFloat(index) / CGFloat(max(1, count - 1))
            let x0 = count == 1 ? 0 : x
            cake.addSublayer(shape(CGPath(rect: CGRect(x: x0 - 1.5, y: size * 0.72, width: 3, height: size * 0.2),
                                          transform: nil), fill: rgb(0x81D4FA)))
            let flame = shape(CGPath(ellipseIn: CGRect(x: x0 - 2.5, y: size * 0.92, width: 5, height: 8), transform: nil),
                              fill: rgb(0xFFC107))
            flame.add(keyframes("opacity", [1, 0.6, 1], duration: 0.3, repeats: Float(duration / 0.3)), forKey: "flicker")
            cake.addSublayer(flame)
        }
        cake.add(keyframes("transform.scale", [0.2, 1.1, 1], times: [0, 0.6, 1], duration: 0.4), forKey: "pop")
        show(cake, in: parent, for: duration, fade: 0.4)
    }

    /// A checked blanket spread on the floor at `base`, `width` across.
    static func blanket(in parent: CALayer, at base: CGPoint, width: CGFloat, duration: TimeInterval) {
        let blanket = holder(at: base)
        let h = max(8, width * 0.08), cells = 10
        for index in 0..<cells {
            let cell = CGRect(x: -width / 2 + width * CGFloat(index) / CGFloat(cells), y: -h * 0.3,
                              width: width / CGFloat(cells), height: h)
            blanket.addSublayer(shape(CGPath(rect: cell, transform: nil),
                                      fill: index.isMultiple(of: 2) ? rgb(0xE53935) : rgb(0xFFFFFF)))
        }
        blanket.add(keyframes("transform.scale.x", [0.05, 1], duration: 0.4), forKey: "spread")
        show(blanket, in: parent, for: duration, fade: 0.4)
    }

    // MARK: Weather

    /// A kite on its string from `hand`, flown up to `top` and swaying there
    /// for `duration`.
    static func kite(in parent: CALayer, from hand: CGPoint, to top: CGPoint, size: CGFloat, duration: TimeInterval) {
        let kite = holder(at: top)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0, y: size * 0.6))
        body.addLine(to: CGPoint(x: size * 0.38, y: 0))
        body.addLine(to: CGPoint(x: 0, y: -size * 0.55))
        body.addLine(to: CGPoint(x: -size * 0.38, y: 0))
        body.closeSubpath()
        kite.addSublayer(shape(body, fill: rgb(0xFFCA28), stroke: rgb(0xE65100), width: 1.4))
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 0, y: -size * 0.55))
        tail.addCurve(to: CGPoint(x: -size * 0.2, y: -size * 1.6), control1: CGPoint(x: size * 0.3, y: -size * 0.9),
                      control2: CGPoint(x: -size * 0.4, y: -size * 1.2))
        kite.addSublayer(shape(tail, fill: nil, stroke: rgb(0xE53935), width: 1.4))
        kite.add(keyframes("position", points([hand, top]), duration: 1.4), forKey: "climb")
        kite.add(keyframes("transform.rotation.z", [0, 0.18, -0.12, 0.1, 0], duration: 1.8,
                           repeats: Float(duration / 1.8)), forKey: "sway")
        show(kite, in: parent, for: duration, fade: 0.3)
        let string = shape({
            let line = CGMutablePath()
            line.move(to: hand)
            line.addQuadCurve(to: top, control: CGPoint(x: (hand.x + top.x) / 2, y: hand.y + (top.y - hand.y) * 0.25))
            return line
        }(), fill: nil, stroke: rgb(0xFFFFFF, 0.7), width: 0.8)
        string.add(keyframes("strokeEnd", [0, 1], duration: 1.4), forKey: "unwind")
        show(string, in: parent, for: duration, fade: 0.3)
    }

    /// A dark storm cloud drifting in to hang over `point` for `duration`.
    static func stormCloud(in parent: CALayer, over point: CGPoint, size: CGFloat, duration: TimeInterval) {
        let cloud = holder(at: point)
        let puffs = CGMutablePath()
        for (x, y, r) in [(-0.45, 0.0, 0.32), (0.0, 0.12, 0.42), (0.45, 0.0, 0.32), (-0.2, -0.12, 0.3), (0.22, -0.12, 0.3)]
            as [(CGFloat, CGFloat, CGFloat)] {
            puffs.addEllipse(in: CGRect(x: (x - r) * size, y: (y - r) * size, width: r * 2 * size, height: r * 2 * size))
        }
        cloud.addSublayer(shape(puffs, fill: rgb(0x4A4F5C), stroke: rgb(0x2E323B), width: 1))
        cloud.add(keyframes("position", points([CGPoint(x: point.x - size * 3, y: point.y), point]), duration: 1.6),
                  forKey: "drift")
        show(cloud, in: parent, for: duration, fade: 0.4)
    }

    /// A jagged bolt from `start` down to `end`, and a flash where it lands.
    static func bolt(in parent: CALayer, from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath()
        path.move(to: start)
        let steps = 5
        for step in 1..<steps {
            let share = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * share + CGFloat.random(in: -12...12),
                                     y: start.y + (end.y - start.y) * share))
        }
        path.addLine(to: end)
        let bolt = shape(path, fill: nil, stroke: rgb(0xFFF59D), width: 3)
        bolt.shadowColor = rgb(0xFFF59D)
        bolt.shadowOpacity = 1
        bolt.shadowRadius = 6
        bolt.shadowOffset = .zero
        bolt.add(keyframes("opacity", [1, 0.2, 1, 0], duration: 0.45), forKey: "blink")
        parent.addSublayer(bolt)
        NotchMascotPlayEffects.remove(bolt, after: 0.5)
        NotchMascotPlayEffects.flash(in: parent, at: end, radius: 26, energy: NotchMascotPlay.Energy(red: 1, green: 0.96, blue: 0.6))
        NotchMascotSound.play(.zap, pan: NotchMascotPlayEffects.pan(x: end.x, in: parent))
    }

    /// A squirt of water arcing from `start` to `end` over `duration`.
    static func squirt(in parent: CALayer, from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
        let arc = CGMutablePath()
        arc.move(to: start)
        arc.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 40))
        for index in 0..<6 {
            let drop = shape(CGPath(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5), transform: nil),
                             fill: rgb(0x4FC3F7, 0.9))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = arc
            move.duration = duration
            move.beginTime = CACurrentMediaTime() + Double(index) * 0.06
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            drop.position = end
            drop.add(move, forKey: "fly")
            show(drop, in: parent, for: duration + 0.4, fade: 0.15)
        }
        NotchMascotSound.play(.slurp, pan: NotchMascotPlayEffects.pan(x: start.x, in: parent))
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak parent] in
            guard let parent else { return }
            NotchMascotPlayEffects.sparks(in: parent, at: end, reach: 14,
                                          energy: NotchMascotPlay.Energy(red: 0.4, green: 0.8, blue: 1), count: 7)
        }
    }

    /// An umbrella held open over `point` for `duration`.
    static func umbrella(in parent: CALayer, over point: CGPoint, size: CGFloat, duration: TimeInterval) {
        let umbrella = holder(at: point)
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -size * 0.7, y: 0))
        canopy.addQuadCurve(to: CGPoint(x: size * 0.7, y: 0), control: CGPoint(x: 0, y: size * 0.9))
        canopy.closeSubpath()
        umbrella.addSublayer(shape(canopy, fill: rgb(0x7E57C2), stroke: rgb(0x4527A0), width: 1.2))
        let handle = CGMutablePath()
        handle.move(to: .zero)
        handle.addLine(to: CGPoint(x: 0, y: -size * 0.6))
        handle.addQuadCurve(to: CGPoint(x: size * 0.12, y: -size * 0.6), control: CGPoint(x: size * 0.06, y: -size * 0.72))
        umbrella.addSublayer(shape(handle, fill: nil, stroke: rgb(0x3A3A3A), width: 1.6))
        show(umbrella, in: parent, for: duration, fade: 0.25)
    }
}
