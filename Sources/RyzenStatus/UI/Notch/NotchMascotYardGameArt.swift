// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What the yard games draw into the clear layers over the screen: a ball,
/// cups and a coin, holes in the floor, a tic-tac-toe board, coloured pads,
/// bubbles, the line drawn for it, a target and the line that says how a
/// game is played. Points are the layer's own, y up; each drawing is a layer
/// placed by its middle, or by its foot for what stands on the floor, that
/// the game moves and takes away.
enum NotchMascotYardGameArt {
    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        NotchMascotRPGShapes.rgb(hex).copy(alpha: alpha) ?? NotchMascotRPGShapes.rgb(hex)
    }

    private static var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    private static func shape(_ path: CGPath, fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = stroke
        layer.lineWidth = width
        layer.lineJoin = .round
        layer.lineCap = .round
        layer.contentsScale = scale
        return layer
    }

    private static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    /// An empty layer whose origin is its position, to hang drawings on.
    private static func holder(at point: CGPoint) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.anchorPoint = .zero
        layer.position = point
        return layer
    }

    /// Moves `layer` to `point` at once, with no implicit animation.
    static func place(_ layer: CALayer, at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = point
        CATransaction.commit()
    }

    /// Fades `layer` out over `length` and takes it away.
    static func fadeAway(_ layer: CALayer, over length: TimeInterval = 0.3) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = 0
        fade.duration = length
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        layer.add(fade, forKey: "fadeAway")
        NotchMascotPlayEffects.remove(layer, after: length + 0.05)
    }

    /// Fades `layer` in as it is added to `parent`.
    static func appear(_ layer: CALayer, in parent: CALayer, over length: TimeInterval = 0.25) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = layer.opacity
        fade.duration = length
        layer.add(fade, forKey: "appear")
        parent.addSublayer(layer)
    }

    // MARK: How to play

    /// A dark pill with `text` in it centred over `point`, for `duration`.
    static func hint(_ text: String, in parent: CALayer, at point: CGPoint, duration: TimeInterval) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 28
        let pill = CALayer()
        pill.bounds = CGRect(x: 0, y: 0, width: width, height: 28)
        pill.position = point
        pill.cornerRadius = 14
        pill.backgroundColor = rgb(0x1B1F2A, 0.86)
        pill.borderColor = rgb(0xFFFFFF, 0.22)
        pill.borderWidth = 1
        let label = CATextLayer()
        label.string = text
        label.font = font
        label.fontSize = 13
        label.foregroundColor = rgb(0xFFFFFF)
        label.alignmentMode = .center
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: 6, width: width, height: 18)
        pill.addSublayer(label)
        pill.opacity = 0
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 1, 1, 0]
        show.keyTimes = [0, NSNumber(value: 0.25 / duration), NSNumber(value: 1 - 0.5 / duration), 1]
        show.duration = duration
        pill.add(show, forKey: "show")
        parent.addSublayer(pill)
        NotchMascotPlayEffects.remove(pill, after: duration + 0.1)
    }

    // MARK: Fetch

    /// A tennis ball `radius` round, placed by its middle.
    static func ball(radius r: CGFloat) -> CALayer {
        let ball = holder(at: .zero)
        let seam = CGMutablePath()
        seam.addArc(center: CGPoint(x: -r * 1.05, y: 0), radius: r * 0.75, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
        seam.addArc(center: CGPoint(x: r * 1.05, y: 0), radius: r * 0.75, startAngle: .pi * 2 / 3, endAngle: .pi * 4 / 3,
                    clockwise: false)
        ball.addSublayer(shape(ellipse(.zero, r, r), fill: rgb(0xD4E157), stroke: rgb(0x827717), width: 1))
        ball.addSublayer(shape(seam, fill: nil, stroke: rgb(0xFFFFFF, 0.95), width: max(1.2, r * 0.16)))
        ball.addSublayer(shape(ellipse(CGPoint(x: -r * 0.35, y: r * 0.4), r * 0.22, r * 0.14), fill: rgb(0xFFFFFF, 0.45)))
        return ball
    }

    /// A soft shadow on the floor under what flies over it.
    static func shadow(radius r: CGFloat) -> CAShapeLayer {
        shape(ellipse(.zero, r, r * 0.3), fill: rgb(0x000000, 0.22))
    }

    // MARK: The shell game

    /// A cup upside down, `width` wide, placed by the middle of its rim on
    /// the floor.
    static func cup(width w: CGFloat) -> CALayer {
        let cup = holder(at: .zero)
        let h = w * 0.92
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -w / 2, y: 0))
        body.addLine(to: CGPoint(x: -w * 0.32, y: h))
        body.addQuadCurve(to: CGPoint(x: w * 0.32, y: h), control: CGPoint(x: 0, y: h * 1.06))
        body.addLine(to: CGPoint(x: w / 2, y: 0))
        body.closeSubpath()
        let stripe = CGMutablePath()
        stripe.move(to: CGPoint(x: -w * 0.44, y: h * 0.18))
        stripe.addLine(to: CGPoint(x: w * 0.44, y: h * 0.18))
        stripe.move(to: CGPoint(x: -w * 0.38, y: h * 0.72))
        stripe.addLine(to: CGPoint(x: w * 0.38, y: h * 0.72))
        let gleam = CGMutablePath()
        gleam.move(to: CGPoint(x: -w * 0.3, y: h * 0.3))
        gleam.addLine(to: CGPoint(x: -w * 0.22, y: h * 0.85))
        cup.addSublayer(shape(body, fill: rgb(0xE53935), stroke: rgb(0x8E1B1B), width: 1.4))
        cup.addSublayer(shape(stripe, fill: nil, stroke: rgb(0xFFEBEE), width: max(1.5, w * 0.06)))
        cup.addSublayer(shape(gleam, fill: nil, stroke: rgb(0xFFFFFF, 0.5), width: max(1.5, w * 0.05)))
        cup.addSublayer(shape(ellipse(CGPoint(x: 0, y: 0), w / 2, w * 0.07), fill: rgb(0x7F1515)))
        return cup
    }

    /// A gold coin `radius` round, placed by its middle.
    static func coin(radius r: CGFloat) -> CALayer {
        let coin = holder(at: .zero)
        coin.addSublayer(shape(ellipse(.zero, r, r), fill: rgb(0xFFC107), stroke: rgb(0xB8860B), width: 1.2))
        coin.addSublayer(shape(ellipse(.zero, r * 0.66, r * 0.66), fill: nil, stroke: rgb(0xFFE082), width: max(1, r * 0.14)))
        coin.addSublayer(shape(ellipse(CGPoint(x: -r * 0.3, y: r * 0.32), r * 0.2, r * 0.12), fill: rgb(0xFFFFFF, 0.6)))
        coin.shadowColor = rgb(0xFFD54F)
        coin.shadowOpacity = 0.9
        coin.shadowRadius = 5
        coin.shadowOffset = .zero
        return coin
    }

    // MARK: Whack-a-mole

    /// A hole in the floor `width` across with a mound of earth round it,
    /// placed by its middle on the floor.
    static func hole(width w: CGFloat) -> CALayer {
        let hole = holder(at: .zero)
        let mound = CGMutablePath()
        mound.move(to: CGPoint(x: -w * 0.62, y: 0))
        mound.addQuadCurve(to: CGPoint(x: w * 0.62, y: 0), control: CGPoint(x: 0, y: w * 0.36))
        mound.closeSubpath()
        hole.addSublayer(shape(mound, fill: rgb(0x795548), stroke: rgb(0x4E342E), width: 1))
        for (dx, dy) in [(-0.4, 0.06), (0.36, 0.08), (-0.12, 0.14), (0.16, 0.13)] as [(CGFloat, CGFloat)] {
            hole.addSublayer(shape(ellipse(CGPoint(x: dx * w, y: dy * w), w * 0.03, w * 0.025), fill: rgb(0x5D4037)))
        }
        hole.addSublayer(shape(ellipse(CGPoint(x: 0, y: w * 0.03), w * 0.44, w * 0.1), fill: rgb(0x1A120E),
                               stroke: rgb(0x3E2723), width: 1))
        return hole
    }

    /// A mallet's swing at `point`: it comes down and goes.
    static func mallet(in parent: CALayer, at point: CGPoint, size s: CGFloat) {
        let mallet = holder(at: point)
        let swing = holder(at: .zero)
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: s * 0.1, y: s * 0.1))
        handle.addLine(to: CGPoint(x: s * 0.7, y: s * 0.55))
        swing.addSublayer(shape(handle, fill: nil, stroke: rgb(0xA1887F), width: max(2, s * 0.08)))
        let head = CGPath(roundedRect: CGRect(x: -s * 0.18, y: -s * 0.02, width: s * 0.36, height: s * 0.26),
                          cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil)
        swing.addSublayer(shape(head, fill: rgb(0xFF7043), stroke: rgb(0xBF360C), width: 1.2))
        mallet.addSublayer(swing)
        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        turn.values = [0.9, -0.25, 0]
        turn.keyTimes = [0, 0.45, 1]
        turn.duration = 0.3
        swing.add(turn, forKey: "swing")
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.7, 1]
        fade.duration = 0.45
        mallet.opacity = 0
        mallet.add(fade, forKey: "fade")
        parent.addSublayer(mallet)
        NotchMascotPlayEffects.remove(mallet, after: 0.5)
    }

    // MARK: Tic-tac-toe

    /// A board `side` square, placed by its middle: a card with the grid on it.
    static func board(side s: CGFloat) -> CALayer {
        let board = CALayer()
        board.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        board.cornerRadius = s * 0.08
        board.backgroundColor = rgb(0xFFF8E1, 0.96)
        board.borderColor = rgb(0x8D6E63)
        board.borderWidth = 2
        board.shadowColor = rgb(0x000000)
        board.shadowOpacity = 0.3
        board.shadowRadius = 6
        board.shadowOffset = CGSize(width: 0, height: -2)
        let grid = CGMutablePath()
        let inset = s * 0.1
        for index in 1...2 {
            let at = inset + (s - inset * 2) * CGFloat(index) / 3
            grid.move(to: CGPoint(x: at, y: inset))
            grid.addLine(to: CGPoint(x: at, y: s - inset))
            grid.move(to: CGPoint(x: inset, y: at))
            grid.addLine(to: CGPoint(x: s - inset, y: at))
        }
        board.addSublayer(shape(grid, fill: nil, stroke: rgb(0x8D6E63), width: max(2, s * 0.025)))
        return board
    }

    /// The middle of `cell` (0 to 8, from the top left) on a board `side`
    /// square, in the board's own points.
    static func cellCenter(_ cell: Int, side s: CGFloat) -> CGPoint {
        let inset = s * 0.1
        let step = (s - inset * 2) / 3
        return CGPoint(x: inset + step * (CGFloat(cell % 3) + 0.5), y: s - inset - step * (CGFloat(cell / 3) + 0.5))
    }

    /// The cell under `point`, in the board's own points, if any.
    static func cell(at point: CGPoint, side s: CGFloat) -> Int? {
        let inset = s * 0.1
        let step = (s - inset * 2) / 3
        let column = Int(floor((point.x - inset) / step))
        let row = Int(floor((s - inset - point.y) / step))
        guard (0..<3).contains(column), (0..<3).contains(row) else { return nil }
        return row * 3 + column
    }

    /// Your mark or its, drawn stroke by stroke into `cell` of `board`.
    static func mark(_ mark: NotchMascotTicTacToe.Mark, cell: Int, on board: CALayer, side s: CGFloat) {
        let center = cellCenter(cell, side: s)
        let r = s * 0.1
        let path = CGMutablePath()
        let color: CGColor
        switch mark {
        case .yours:
            path.move(to: CGPoint(x: center.x - r, y: center.y + r))
            path.addLine(to: CGPoint(x: center.x + r, y: center.y - r))
            path.move(to: CGPoint(x: center.x + r, y: center.y + r))
            path.addLine(to: CGPoint(x: center.x - r, y: center.y - r))
            color = rgb(0x1E88E5)
        case .its:
            path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            color = rgb(0xEC407A)
        }
        let stroke = shape(path, fill: nil, stroke: color, width: max(3, s * 0.04))
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.25
        stroke.add(draw, forKey: "draw")
        board.addSublayer(stroke)
    }

    /// A line struck through the three cells of `line` on `board`.
    static func strike(_ line: [Int], on board: CALayer, side s: CGFloat, color: CGColor) {
        guard let first = line.first, let last = line.last else { return }
        let path = CGMutablePath()
        path.move(to: cellCenter(first, side: s))
        path.addLine(to: cellCenter(last, side: s))
        let stroke = shape(path, fill: nil, stroke: color, width: max(4, s * 0.05))
        stroke.opacity = 0.85
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.35
        stroke.add(draw, forKey: "draw")
        board.addSublayer(stroke)
    }

    // MARK: Simon says

    /// The colours of the four pads: red, blue, green and yellow.
    static let padColors: [UInt32] = [0xFF5252, 0x448AFF, 0x00E676, 0xFFD740]

    /// Pad `index`, `width` wide, lying flat on the floor, placed by the
    /// middle of its bottom edge.
    static func pad(_ index: Int, width w: CGFloat) -> CAShapeLayer {
        let h = w * 0.26
        let path = CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerWidth: h * 0.45,
                          cornerHeight: h * 0.45, transform: nil)
        let color = padColors[index % padColors.count]
        let pad = shape(path, fill: rgb(color, 0.45), stroke: rgb(color), width: 2)
        pad.shadowColor = rgb(color)
        pad.shadowOffset = .zero
        pad.shadowRadius = 10
        pad.shadowOpacity = 0
        return pad
    }

    /// Lights `pad` up for `length`, glowing, and lets it dim again.
    static func light(_ pad: CAShapeLayer, index: Int, for length: TimeInterval) {
        let color = padColors[index % padColors.count]
        let fill = CAKeyframeAnimation(keyPath: "fillColor")
        fill.values = [rgb(color, 1), rgb(color, 1), rgb(color, 0.45)]
        fill.keyTimes = [0, 0.7, 1]
        fill.duration = length
        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [1, 1, 0]
        glow.keyTimes = [0, 0.7, 1]
        glow.duration = length
        let press = CAKeyframeAnimation(keyPath: "transform.scale.y")
        press.values = [0.7, 1, 1]
        press.keyTimes = [0, 0.3, 1]
        press.duration = length
        pad.add(fill, forKey: "fill")
        pad.add(glow, forKey: "glow")
        pad.add(press, forKey: "press")
    }

    // MARK: Bubbles

    /// A soap bubble `radius` round, placed by its middle; a golden one
    /// shines.
    static func bubble(radius r: CGFloat, golden: Bool) -> CALayer {
        let bubble = holder(at: .zero)
        let tint: UInt32 = golden ? 0xFFD54F : 0x81D4FA
        bubble.addSublayer(shape(ellipse(.zero, r, r), fill: rgb(tint, golden ? 0.32 : 0.16), stroke: rgb(tint, 0.9),
                                 width: max(1, r * 0.08)))
        let shine = CGMutablePath()
        shine.addArc(center: .zero, radius: r * 0.68, startAngle: .pi * 0.6, endAngle: .pi * 0.9, clockwise: false)
        bubble.addSublayer(shape(shine, fill: nil, stroke: rgb(0xFFFFFF, 0.85), width: max(1.2, r * 0.12)))
        bubble.addSublayer(shape(ellipse(CGPoint(x: r * 0.4, y: -r * 0.38), r * 0.1, r * 0.1), fill: rgb(0xFFFFFF, 0.6)))
        if golden {
            bubble.shadowColor = rgb(0xFFD54F)
            bubble.shadowOpacity = 0.9
            bubble.shadowRadius = 6
            bubble.shadowOffset = .zero
        }
        return bubble
    }

    /// A bubble bursting at `point`: a ring that grows and goes, and droplets.
    static func burst(in parent: CALayer, at point: CGPoint, radius r: CGFloat, golden: Bool) {
        let tint: UInt32 = golden ? 0xFFD54F : 0xB3E5FC
        let ring = shape(ellipse(.zero, r, r), fill: nil, stroke: rgb(tint), width: 1.5)
        ring.position = point
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.25
        ring.opacity = 0
        ring.add(group, forKey: "burst")
        parent.addSublayer(ring)
        NotchMascotPlayEffects.remove(ring, after: 0.3)
        for index in 0..<6 {
            let drop = shape(ellipse(.zero, max(1.2, r * 0.1), max(1.2, r * 0.1)), fill: rgb(tint))
            drop.position = point
            let angle = CGFloat(index) / 6 * .pi * 2
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: point)
            move.toValue = NSValue(point: CGPoint(x: point.x + cos(angle) * r * 1.6, y: point.y + sin(angle) * r * 1.6 - r * 0.4))
            let gone = CABasicAnimation(keyPath: "opacity")
            gone.fromValue = 1
            gone.toValue = 0
            let drops = CAAnimationGroup()
            drops.animations = [move, gone]
            drops.duration = 0.35
            drops.timingFunction = CAMediaTimingFunction(name: .easeOut)
            drop.opacity = 0
            drop.add(drops, forKey: "drop")
            parent.addSublayer(drop)
            NotchMascotPlayEffects.remove(drop, after: 0.4)
        }
    }

    // MARK: A path to follow

    /// The line drawn for it to follow: a dotted trail with a soft glow.
    static func trail() -> CAShapeLayer {
        let trail = shape(CGMutablePath(), fill: nil, stroke: rgb(0xFFFFFF, 0.95), width: 4)
        trail.lineDashPattern = [1, 9]
        trail.shadowColor = rgb(0x7C4DFF)
        trail.shadowOpacity = 1
        trail.shadowRadius = 4
        trail.shadowOffset = .zero
        return trail
    }

    /// A little flag where the line ends.
    static func flag(size s: CGFloat) -> CALayer {
        let flag = holder(at: .zero)
        let pole = CGMutablePath()
        pole.move(to: .zero)
        pole.addLine(to: CGPoint(x: 0, y: s))
        let cloth = CGMutablePath()
        cloth.move(to: CGPoint(x: 0, y: s))
        cloth.addLine(to: CGPoint(x: s * 0.55, y: s * 0.82))
        cloth.addLine(to: CGPoint(x: 0, y: s * 0.64))
        cloth.closeSubpath()
        flag.addSublayer(shape(pole, fill: nil, stroke: rgb(0xECEFF1), width: 2))
        flag.addSublayer(shape(cloth, fill: rgb(0x7C4DFF), stroke: rgb(0x4527A0), width: 1))
        return flag
    }

    // MARK: Target practice

    /// A target on a stick `radius` round, placed by the middle of the
    /// target; the stick hangs down to where it is held.
    static func target(radius r: CGFloat) -> CALayer {
        let target = holder(at: .zero)
        let stick = CGMutablePath()
        stick.move(to: CGPoint(x: 0, y: -r))
        stick.addLine(to: CGPoint(x: 0, y: -r * 2.1))
        target.addSublayer(shape(stick, fill: nil, stroke: rgb(0x8D6E63), width: max(2, r * 0.14)))
        let rings: [(CGFloat, UInt32)] = [(1, 0xFFFFFF), (0.8, 0xE53935), (0.6, 0xFFFFFF), (0.4, 0xE53935), (0.2, 0xFFD740)]
        for (share, color) in rings {
            target.addSublayer(shape(ellipse(.zero, r * share, r * share), fill: rgb(color),
                                     stroke: share == 1 ? rgb(0x5D4037) : nil, width: share == 1 ? 1.5 : 0))
        }
        return target
    }

    /// A soft ball thrown from `start` to `end` over `duration`, gone as it gets there.
    static func toss(in parent: CALayer, from start: CGPoint, to end: CGPoint, duration: TimeInterval, radius r: CGFloat) {
        let ball = shape(ellipse(.zero, r, r), fill: rgb(0xFF7043), stroke: rgb(0xBF360C), width: 1)
        ball.position = end
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + r * 8))
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = path
        fly.duration = duration
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.6
        shrink.toValue = 0.8
        shrink.duration = duration
        ball.add(fly, forKey: "fly")
        ball.add(shrink, forKey: "shrink")
        parent.addSublayer(ball)
        NotchMascotPlayEffects.remove(ball, after: duration)
    }

    /// A splat of paint where a throw landed, fading.
    static func splat(in parent: CALayer, at point: CGPoint, radius r: CGFloat) {
        let splat = holder(at: point)
        let blot = CGMutablePath()
        blot.addPath(ellipse(.zero, r, r * 0.8))
        for index in 0..<5 {
            let angle = CGFloat(index) / 5 * .pi * 2 + 0.4
            blot.addPath(ellipse(CGPoint(x: cos(angle) * r * 1.3, y: sin(angle) * r * 1.1), r * 0.28, r * 0.28))
        }
        splat.addSublayer(shape(blot, fill: rgb(0xFF7043, 0.85)))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        fade.duration = 1.2
        splat.opacity = 0
        splat.add(fade, forKey: "fade")
        parent.addSublayer(splat)
        NotchMascotPlayEffects.remove(splat, after: 1.3)
    }
}
