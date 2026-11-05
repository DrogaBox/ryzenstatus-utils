// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What a fused companion wears over its figure: an aura in both its
/// colours behind it, made of flames, wisps, ice, bubbles, stars, petals or
/// flickering light, and, in front, the pair of earrings or the gem on its
/// brow that say it is two in one. Everything loops in the render server;
/// the app sets it up once per look. With Reduce Motion only the glow and
/// the still shapes of the aura show. Layers lay out from the top, y growing
/// downward, like the companion's.
final class NotchMascotFusionArt {
    /// Behind the body.
    let back = CALayer()
    /// In front of the body, leaning with it.
    let front = CALayer()

    private var configuredState: (look: NotchMascotLook, size: CGFloat, scale: CGFloat, reduceMotion: Bool)?
    private let glow = CAGradientLayer()
    private let motifs = CALayer()
    private let particles = CAEmitterLayer()
    private let sparks = CALayer()
    private let marks = CALayer()

    init() {
        for layer in [back, front, glow, motifs, sparks, marks] { layer.actions = Self.noActions }
        particles.actions = Self.noActions
        back.addSublayer(glow)
        back.addSublayer(motifs)
        back.addSublayer(particles)
        front.addSublayer(sparks)
        front.addSublayer(marks)
        back.isHidden = true
        front.isHidden = true
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
        "frame": NSNull(), "sublayers": NSNull(), "colors": NSNull(), "contents": NSNull(), "birthRate": NSNull(),
        "path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(),
    ]

    /// Sets it up for `look` at `size` points; a look that is not fused
    /// takes it all away.
    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat, reduceMotion: Bool) {
        if let configuredState, configuredState.look == look, configuredState.size == size,
           configuredState.scale == scale, configuredState.reduceMotion == reduceMotion {
            return
        }
        configuredState = (look, size, scale, reduceMotion)
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [back, front, motifs, particles, sparks, marks] {
            layer.frame = box
            layer.contentsScale = scale
            layer.removeAllAnimations()
        }
        glow.removeAllAnimations()
        motifs.sublayers = nil
        sparks.sublayers = nil
        marks.sublayers = nil
        particles.birthRate = 0
        particles.emitterCells = nil
        guard let fusion = look.fusion, size > 0 else {
            back.isHidden = true
            front.isHidden = true
            return
        }
        back.isHidden = false
        front.isHidden = false
        let colors = [fusion.primary.brightened(0.15), fusion.secondary.brightened(0.15)]
        let fizzles = fusion.aura == .fizzle

        // A glow taller than wide, like a flame round it, its heart in the second colour.
        let width = size * (fizzles ? 1.15 : 1.5)
        let height = size * (fizzles ? 1.2 : 1.75)
        glow.contentsScale = scale
        glow.type = .radial
        glow.frame = CGRect(x: (size - width) / 2, y: size * 0.98 - height, width: width, height: height)
        let heart = fizzles ? NotchMascotColor(red: 0.6, green: 0.58, blue: 0.55) : fusion.secondary.brightened(0.5)
        let edge = fizzles ? NotchMascotColor(red: 0.45, green: 0.43, blue: 0.4) : fusion.primary
        glow.colors = [heart.cgColor.copy(alpha: fizzles ? 0.45 : 0.85) ?? heart.cgColor,
                       edge.cgColor.copy(alpha: fizzles ? 0.3 : 0.55) ?? edge.cgColor,
                       edge.cgColor.copy(alpha: 0) ?? edge.cgColor]
        glow.locations = [0, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.62)
        glow.endPoint = CGPoint(x: 1, y: 1)

        placeMotifs(fusion.aura, colors: colors, size: size, scale: scale)
        placeMarks(fusion, look: look, size: size, scale: scale)
        guard !reduceMotion else { return }
        animate(fusion.aura, colors: colors, size: size, scale: scale, glowHeight: height)
    }

    // MARK: Still shapes

    /// The aura's own shapes round the body: they show even with Reduce
    /// Motion, and move once it may.
    private func placeMotifs(_ aura: NotchMascotFusion.Aura, colors: [NotchMascotColor], size: CGFloat, scale: CGFloat) {
        let count = aura == .fizzle ? 4 : 7
        let center = CGPoint(x: size / 2, y: size * 0.56)
        let radii = CGSize(width: size * 0.66, height: size * 0.6)
        let side = size * (aura == .fizzle ? 0.2 : 0.13)
        for index in 0..<count {
            let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(count) * .pi * 2 + 0.3
            let point = CGPoint(x: center.x + cos(angle) * radii.width, y: center.y + sin(angle) * radii.height)
            let motif = CAShapeLayer()
            motif.actions = Self.noActions
            motif.contentsScale = scale
            motif.path = Self.motif(aura, side: side * (index.isMultiple(of: 2) ? 1 : 0.75), angle: angle)
            let color = aura == .fizzle ? NotchMascotColor(red: 0.62, green: 0.6, blue: 0.57)
                : colors[index % colors.count]
            if Self.stroked(aura) {
                motif.fillColor = nil
                motif.strokeColor = color.cgColor
                motif.lineWidth = max(0.7, size * 0.022)
                motif.lineCap = .round
                motif.lineJoin = .round
            } else {
                motif.fillColor = color.cgColor
            }
            motif.shadowColor = color.cgColor
            motif.shadowOpacity = aura == .fizzle ? 0 : 0.9
            motif.shadowRadius = max(0.6, size * 0.03)
            motif.shadowOffset = .zero
            motif.position = point
            motif.opacity = aura == .fizzle ? 0.75 : 0.9
            motifs.addSublayer(motif)
        }
    }

    private static func stroked(_ aura: NotchMascotFusion.Aura) -> Bool {
        aura == .storm || aura == .frost || aura == .bubbles
    }

    /// One shape of an aura, `side` points across about its middle.
    static func motif(_ aura: NotchMascotFusion.Aura, side s: CGFloat, angle: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        switch aura {
        case .blaze:
            // A flame, its tip up.
            path.move(to: CGPoint(x: 0, y: -s * 0.62))
            path.addCurve(to: CGPoint(x: s * 0.3, y: s * 0.32), control1: CGPoint(x: s * 0.12, y: -s * 0.3),
                          control2: CGPoint(x: s * 0.42, y: -s * 0.02))
            path.addArc(center: CGPoint(x: 0, y: s * 0.26), radius: s * 0.3, startAngle: 0.2, endAngle: .pi - 0.2,
                        clockwise: false)
            path.addCurve(to: CGPoint(x: 0, y: -s * 0.62), control1: CGPoint(x: -s * 0.42, y: -s * 0.02),
                          control2: CGPoint(x: -s * 0.12, y: -s * 0.3))
            path.closeSubpath()
        case .storm:
            path.move(to: CGPoint(x: -s * 0.15, y: -s * 0.5))
            path.addLine(to: CGPoint(x: s * 0.2, y: -s * 0.1))
            path.addLine(to: CGPoint(x: -s * 0.12, y: s * 0.05))
            path.addLine(to: CGPoint(x: s * 0.18, y: s * 0.5))
        case .spirit:
            // A wisp: a ball with a curling tail.
            path.addEllipse(in: CGRect(x: -s * 0.26, y: -s * 0.1, width: s * 0.52, height: s * 0.52))
            path.move(to: CGPoint(x: -s * 0.24, y: s * 0.05))
            path.addQuadCurve(to: CGPoint(x: s * 0.1, y: -s * 0.6), control: CGPoint(x: -s * 0.45, y: -s * 0.4))
            path.addQuadCurve(to: CGPoint(x: s * 0.24, y: s * 0.05), control: CGPoint(x: -s * 0.05, y: -s * 0.25))
            path.closeSubpath()
        case .frost:
            for index in 0..<3 {
                let turn = CGFloat(index) * .pi / 3
                path.move(to: CGPoint(x: cos(turn) * s * 0.5, y: sin(turn) * s * 0.5))
                path.addLine(to: CGPoint(x: -cos(turn) * s * 0.5, y: -sin(turn) * s * 0.5))
            }
        case .bubbles:
            path.addEllipse(in: CGRect(x: -s * 0.36, y: -s * 0.36, width: s * 0.72, height: s * 0.72))
            path.move(to: CGPoint(x: -s * 0.16, y: -s * 0.12))
            path.addQuadCurve(to: CGPoint(x: s * 0.02, y: -s * 0.22), control: CGPoint(x: -s * 0.12, y: -s * 0.24))
        case .stardust:
            for index in 0..<8 {
                let turn = CGFloat(index) * .pi / 4 - .pi / 2
                let reach = index.isMultiple(of: 2) ? s * 0.55 : s * 0.16
                let point = CGPoint(x: cos(turn) * reach, y: sin(turn) * reach)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        case .bloom:
            // A petal, pointing out from the body.
            let turn = CGAffineTransform(rotationAngle: angle)
            path.addEllipse(in: CGRect(x: -s * 0.5, y: -s * 0.2, width: s, height: s * 0.4), transform: turn)
        case .glitch:
            path.addRect(CGRect(x: -s * 0.24, y: -s * 0.24, width: s * 0.48, height: s * 0.48))
            path.addRect(CGRect(x: s * 0.3, y: -s * 0.08, width: s * 0.18, height: s * 0.16))
        case .fizzle:
            for (x, y, r) in [(-0.22, 0.05, 0.26), (0.12, -0.08, 0.3), (0.2, 0.18, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: (x - r) * s, y: (y - r) * s, width: r * 2 * s, height: r * 2 * s))
            }
        }
        return path
    }

    // MARK: Earrings and the gem

    private func placeMarks(_ fusion: NotchMascotFusionLook, look: NotchMascotLook, size: CGFloat, scale: CGFloat) {
        let face = look.face
        let eyeY = (face.leftEye.y + face.rightEye.y) / 2
        switch fusion.mark {
        case .none:
            break
        case .earrings:
            let y = (eyeY + face.eyeSize.height * 0.55) * size
            let xs: [CGFloat]
            if let head = NotchMascotCreatures.headOutline(look.style, size: size) {
                xs = [head.minX - size * 0.01, head.maxX + size * 0.01]
            } else {
                xs = [(face.leftEye.x - 0.21) * size, (face.rightEye.x + 0.21) * size]
            }
            for x in xs { marks.addSublayer(Self.earring(at: CGPoint(x: x, y: y), size: size, scale: scale)) }
        case .gem:
            let point = CGPoint(x: (face.leftEye.x + face.rightEye.x) / 2 * size,
                                y: max(size * 0.08, (eyeY - face.eyeSize.height * 0.85 - 0.06) * size))
            marks.addSublayer(Self.gem(at: point, size: size, scale: scale, fusion: fusion))
        }
    }

    /// A gold stud with a green bead hanging from it, as the old earrings that fuse two.
    private static func earring(at point: CGPoint, size: CGFloat, scale: CGFloat) -> CALayer {
        let holder = CALayer()
        holder.actions = noActions
        holder.frame = CGRect(x: point.x - size * 0.08, y: point.y - size * 0.05, width: size * 0.16, height: size * 0.2)
        let gold = CGColor(srgbRed: 1, green: 0.77, blue: 0.24, alpha: 1)
        let ink = NotchMascotColor.ink.cgColor
        let mid = size * 0.08
        let stud = CAShapeLayer()
        stud.path = CGPath(ellipseIn: CGRect(x: mid - size * 0.03, y: size * 0.02, width: size * 0.06, height: size * 0.06),
                           transform: nil)
        stud.fillColor = gold
        stud.strokeColor = ink
        stud.lineWidth = max(0.4, size * 0.01)
        let hook = CAShapeLayer()
        let line = CGMutablePath()
        line.move(to: CGPoint(x: mid, y: size * 0.08))
        line.addLine(to: CGPoint(x: mid, y: size * 0.1))
        hook.path = line
        hook.strokeColor = gold
        hook.lineWidth = max(0.6, size * 0.018)
        let bead = CAShapeLayer()
        bead.path = CGPath(ellipseIn: CGRect(x: mid - size * 0.05, y: size * 0.095, width: size * 0.1, height: size * 0.1),
                           transform: nil)
        bead.fillColor = CGColor(srgbRed: 0.7, green: 0.9, blue: 0.3, alpha: 1)
        bead.strokeColor = ink
        bead.lineWidth = max(0.4, size * 0.01)
        let shine = CAShapeLayer()
        shine.path = CGPath(ellipseIn: CGRect(x: mid - size * 0.028, y: size * 0.11, width: size * 0.03, height: size * 0.025),
                            transform: nil)
        shine.fillColor = CGColor(gray: 1, alpha: 0.85)
        for layer in [hook, stud, bead, shine] {
            layer.actions = noActions
            layer.contentsScale = scale
            layer.frame = holder.bounds
            holder.addSublayer(layer)
        }
        return holder
    }

    /// A diamond in both colours with a glint, set on its brow.
    private static func gem(at point: CGPoint, size: CGFloat, scale: CGFloat, fusion: NotchMascotFusionLook) -> CALayer {
        let w = size * 0.06, h = size * 0.085
        let holder = CALayer()
        holder.actions = noActions
        holder.frame = CGRect(x: point.x - w, y: point.y - h, width: w * 2, height: h * 2)
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: w, y: 0))
        outline.addLine(to: CGPoint(x: w * 2, y: h))
        outline.addLine(to: CGPoint(x: w, y: h * 2))
        outline.addLine(to: CGPoint(x: 0, y: h))
        outline.closeSubpath()
        let stone = CAShapeLayer()
        stone.path = outline
        stone.fillColor = fusion.secondary.brightened(0.25).cgColor
        stone.strokeColor = fusion.primary.darkened(0.35).cgColor
        stone.lineWidth = max(0.5, size * 0.012)
        stone.shadowColor = fusion.secondary.cgColor
        stone.shadowOpacity = 1
        stone.shadowRadius = max(0.8, size * 0.04)
        stone.shadowOffset = .zero
        let half = CAShapeLayer()
        let lower = CGMutablePath()
        lower.move(to: CGPoint(x: w * 2, y: h))
        lower.addLine(to: CGPoint(x: w, y: h * 2))
        lower.addLine(to: CGPoint(x: 0, y: h))
        lower.closeSubpath()
        half.path = lower
        half.fillColor = fusion.primary.cgColor
        let glint = CAShapeLayer()
        glint.path = CGPath(ellipseIn: CGRect(x: w * 0.6, y: h * 0.45, width: w * 0.45, height: h * 0.3), transform: nil)
        glint.fillColor = CGColor(gray: 1, alpha: 0.9)
        for layer in [stone, half, glint] {
            layer.actions = noActions
            layer.contentsScale = scale
            layer.frame = holder.bounds
            holder.addSublayer(layer)
        }
        return holder
    }

    // MARK: Motion

    private func animate(_ aura: NotchMascotFusion.Aura, colors: [NotchMascotColor], size: CGFloat, scale: CGFloat,
                         glowHeight: CGFloat) {
        let fizzles = aura == .fizzle
        let flicker = CAKeyframeAnimation(keyPath: "transform")
        flicker.values = [(1, 1), (1.05, 1.1), (0.97, 0.96), (1.04, 1.07), (1, 1)].map { (x: CGFloat, y: CGFloat) in
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(x, y, 1),
                                                       CATransform3DMakeTranslation(0, glowHeight * 0.32 * (1 - y), 0)))
        }
        flicker.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        flicker.duration = aura == .storm ? 0.3 : fizzles ? 0.9 : 0.45
        flicker.repeatCount = .infinity
        glow.add(flicker, forKey: "flicker")

        // The still shapes turn about it, twinkle or flicker, each its own way.
        switch aura {
        case .spirit, .bloom, .stardust, .frost:
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = aura == .frost ? -CGFloat.pi * 2 : CGFloat.pi * 2
            turn.duration = aura == .spirit ? 3.2 : 7
            turn.repeatCount = .infinity
            motifs.add(turn, forKey: "turn")
            for (index, motif) in (motifs.sublayers ?? []).enumerated() {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = 0.95
                twinkle.toValue = 0.3
                twinkle.duration = 0.5 + Double(index % 3) * 0.17
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                motif.add(twinkle, forKey: "twinkle")
            }
        case .glitch, .storm:
            for (index, motif) in (motifs.sublayers ?? []).enumerated() {
                let blink = CAKeyframeAnimation(keyPath: "opacity")
                blink.values = [1, 0, 0.8, 0, 1, 1]
                blink.keyTimes = [0, 0.1, 0.18, 0.3, 0.36, 1]
                blink.calculationMode = .discrete
                blink.duration = 0.9 + Double(index) * 0.13
                blink.repeatCount = .infinity
                motif.add(blink, forKey: "blink")
            }
        case .blaze, .bubbles, .fizzle:
            for (index, motif) in (motifs.sublayers ?? []).enumerated() {
                let bob = CABasicAnimation(keyPath: "transform.translation.y")
                bob.fromValue = 0
                bob.toValue = -size * (fizzles ? 0.04 : 0.1)
                bob.duration = 0.6 + Double(index % 3) * 0.2
                bob.autoreverses = true
                bob.repeatCount = .infinity
                motif.add(bob, forKey: "bob")
            }
        }

        emit(aura, colors: colors, size: size, scale: scale)
        if aura == .storm { addBolts(colors: colors, size: size, scale: scale) }
    }

    /// The aura's particles: flames and bubbles rise from its feet, ice
    /// falls from above, stars and petals drift out, squares flicker about
    /// it and a failed one sputters grey puffs.
    private func emit(_ aura: NotchMascotFusion.Aura, colors: [NotchMascotColor], size: CGFloat, scale: CGFloat) {
        guard let image = Self.image(aura) else { return }
        particles.renderMode = aura == .fizzle ? .unordered : .additive
        var shape = CAEmitterLayerEmitterShape.line
        var position = CGPoint(x: size / 2, y: size * 0.88)
        var extent = CGSize(width: size * 0.8, height: 1)
        switch aura {
        case .frost:
            position = CGPoint(x: size / 2, y: -size * 0.1)
            extent = CGSize(width: size * 1.2, height: 1)
        case .spirit, .stardust, .bloom:
            shape = .circle
            position = CGPoint(x: size / 2, y: size * 0.55)
            extent = CGSize(width: size * 1.1, height: size * 1.1)
        case .glitch:
            shape = .rectangle
            position = CGPoint(x: size / 2, y: size * 0.5)
            extent = CGSize(width: size * 1.3, height: size * 1.1)
        case .fizzle:
            shape = .point
            position = CGPoint(x: size * 0.5, y: size * 0.12)
            extent = .zero
        case .blaze, .storm, .bubbles:
            break
        }
        particles.emitterShape = shape
        particles.emitterPosition = position
        particles.emitterSize = extent
        particles.emitterMode = shape == .circle ? .outline : .points
        let palette = aura == .fizzle ? [NotchMascotColor(red: 0.7, green: 0.68, blue: 0.64)] : colors
        particles.emitterCells = palette.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor.copy(alpha: 0.9)
            cell.scale = size * 0.006
            cell.scaleRange = size * 0.002
            cell.emissionRange = .pi / 8
            cell.alphaSpeed = -1.2
            switch aura {
            case .blaze, .storm:
                cell.birthRate = aura == .storm ? 16 : 22
                cell.lifetime = 0.65
                cell.yAcceleration = -size * 6
                cell.scaleSpeed = -size * 0.008
            case .bubbles:
                cell.birthRate = 5
                cell.lifetime = 1.6
                cell.velocity = size * 0.6
                cell.emissionLongitude = -.pi / 2
                cell.yAcceleration = -size * 0.6
                cell.xAcceleration = size * 0.2
                cell.alphaSpeed = -0.5
            case .frost:
                cell.birthRate = 6
                cell.lifetime = 1.8
                cell.yAcceleration = size * 0.8
                cell.spin = 1.2
                cell.spinRange = 2
                cell.alphaSpeed = -0.5
            case .spirit, .bloom:
                cell.birthRate = 5
                cell.lifetime = 1.4
                cell.velocity = size * 0.25
                cell.emissionRange = .pi * 2
                cell.yAcceleration = -size * 0.5
                cell.spin = aura == .bloom ? 2 : 0.5
                cell.spinRange = 2
                cell.alphaSpeed = -0.7
            case .stardust:
                cell.birthRate = 7
                cell.lifetime = 1
                cell.velocity = size * 0.3
                cell.emissionRange = .pi * 2
                cell.scaleSpeed = -size * 0.005
                cell.alphaSpeed = -0.9
            case .glitch:
                cell.birthRate = 9
                cell.lifetime = 0.22
                cell.lifetimeRange = 0.1
                cell.alphaSpeed = -3
            case .fizzle:
                cell.birthRate = 2.5
                cell.lifetime = 1.2
                cell.velocity = size * 0.5
                cell.emissionLongitude = -.pi / 2
                cell.emissionRange = .pi / 5
                cell.scale = size * 0.009
                cell.scaleSpeed = size * 0.006
                cell.alphaSpeed = -0.8
            }
            return cell
        }
        particles.birthRate = 1
        guard aura == .fizzle else { return }
        // It sputters: puffs, a pause, puffs.
        let sputter = CAKeyframeAnimation(keyPath: "birthRate")
        sputter.values = [1, 0, 2, 0, 0]
        sputter.keyTimes = [0, 0.2, 0.45, 0.6, 1]
        sputter.calculationMode = .discrete
        sputter.duration = 2.2
        sputter.repeatCount = .infinity
        particles.add(sputter, forKey: "sputter")
    }

    private func addBolts(colors: [NotchMascotColor], size: CGFloat, scale: CGFloat) {
        let starts: [(CGFloat, CGFloat, CGFloat)] = [(0.08, 0.2, 1), (0.92, 0.28, -1), (0.5, -0.16, 1)]
        for (index, start) in starts.enumerated() {
            let bolt = CAShapeLayer()
            bolt.actions = Self.noActions
            bolt.contentsScale = scale
            bolt.frame = CGRect(x: 0, y: 0, width: size, height: size)
            let path = CGMutablePath()
            var point = CGPoint(x: start.0 * size, y: start.1 * size)
            path.move(to: point)
            for segment in 0..<4 {
                point = CGPoint(x: point.x + (segment.isMultiple(of: 2) ? 1 : -1) * start.2 * size * 0.08,
                                y: point.y + size * 0.11)
                path.addLine(to: point)
            }
            bolt.path = path
            bolt.fillColor = nil
            let color = colors[index % colors.count].brightened(0.4).cgColor
            bolt.strokeColor = color
            bolt.lineWidth = max(0.8, size * 0.032)
            bolt.shadowColor = color
            bolt.shadowOpacity = 1
            bolt.shadowRadius = max(0.6, size * 0.05)
            bolt.shadowOffset = .zero
            bolt.opacity = 0
            let crackle = CAKeyframeAnimation(keyPath: "opacity")
            crackle.values = [0, 1, 0, 0.8, 0, 0]
            crackle.keyTimes = [0, 0.04, 0.09, 0.13, 0.18, 1]
            crackle.calculationMode = .discrete
            crackle.duration = [1.1, 1.5, 1.9][index]
            crackle.beginTime = CACurrentMediaTime() + Double(index) * 0.31
            crackle.repeatCount = .infinity
            bolt.add(crackle, forKey: "crackle")
            sparks.addSublayer(bolt)
        }
    }

    /// The aura's shape in white, for its particles to tint.
    private static func image(_ aura: NotchMascotFusion.Aura) -> CGImage? {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        context.scaleBy(x: 1, y: -1)
        if aura == .blaze || aura == .storm {
            // Flames are soft dots, as the transformations' are.
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                            locations: [0, 1]) else { return nil }
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                       endRadius: CGFloat(side) / 2, options: [])
            return context.makeImage()
        }
        context.addPath(motif(aura, side: CGFloat(side) * 0.9))
        if stroked(aura) {
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(3)
            context.setLineCap(.round)
            context.strokePath()
        } else {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
        }
        return context.makeImage()
    }
}

extension NotchMascotFusionLook {
    var fillColors: [CGColor] { bodyColors.map(\.cgColor) }
    var fillLocations: [NSNumber]? { bodyLocations?.map { NSNumber(value: $0) } }
    /// Split, its colours part on the slant, from the top left down.
    var fillStart: CGPoint { split ? CGPoint(x: 0.15, y: 0) : CGPoint(x: 0.5, y: 0) }
    var fillEnd: CGPoint { split ? CGPoint(x: 0.85, y: 1) : CGPoint(x: 0.5, y: 1) }

    /// How a fusion gone wrong is drawn, about its feet in a square of
    /// `size` points laid out from the top: squashed, stretched or leaning,
    /// its feet where they were.
    func figureTransform(size: CGFloat) -> CATransform3D {
        guard stretch != CGSize(width: 1, height: 1) || shear != 0 else { return CATransform3DIdentity }
        let scale = CATransform3DMakeScale(stretch.width, stretch.height, 1)
        var lean = CATransform3DIdentity
        lean.m21 = shear
        let feet = size / 2 * stretch.height
        let back = CATransform3DMakeTranslation(-shear * feet, size / 2 * (1 - stretch.height), 0)
        return CATransform3DConcat(CATransform3DConcat(scale, lean), back)
    }
}

/// What a fusion draws on the stage over the screen, in screen points less
/// the screen's origin, y growing upward: the shouts of the dance, the
/// blinding flash, shock waves on the floor, copies left by a teleport, and
/// the props of the power moves.
enum NotchMascotFusionEffects {
    private static let ink = NotchMascotColor.ink.cgColor

    private static func scale(of layer: CALayer) -> CGFloat { max(1, layer.contentsScale) }

    private static func remove(_ layer: CALayer, after delay: TimeInterval) {
        NotchMascotPlayEffects.remove(layer, after: delay)
    }

    // MARK: Shouts

    /// A comic balloon holding `text`, `height` points tall, its tail's tip
    /// at `tip`: round for a word, spiky for a shout. It springs out, holds
    /// for `life` and fades.
    static func shout(_ text: String, in canvas: CALayer, at tip: CGPoint, height: CGFloat, spiky: Bool,
                      life: TimeInterval = 1.2, leans: CGFloat = 1) {
        let base = NSFont.systemFont(ofSize: height * 0.5, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: height * 0.5) } ?? base
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let width = max(height * 1.3, measured.width + height * (spiky ? 0.95 : 0.7))
        let tail = height * 0.35
        let holder = CALayer()
        holder.bounds = CGRect(x: -width / 2, y: 0, width: width, height: height + tail)
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.position = tip
        let center = CGPoint(x: leans * width * 0.1, y: tail + height / 2)
        let outline = CGMutablePath()
        if spiky {
            let points = 14
            for index in 0..<(points * 2) {
                let angle = CGFloat(index) / CGFloat(points * 2) * .pi * 2
                let reach: CGFloat = index.isMultiple(of: 2) ? 1 : 0.78
                let point = CGPoint(x: center.x + cos(angle) * width / 2 * reach, y: center.y + sin(angle) * height / 2 * reach)
                if index == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
            }
            outline.closeSubpath()
        } else {
            outline.addEllipse(in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        }
        // The tail, from the balloon's lower edge down to the tip, drawn
        // first so the balloon covers where they meet.
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: center.x - leans * width * 0.05, y: tail + height * 0.1))
        tailPath.addLine(to: .zero)
        tailPath.addLine(to: CGPoint(x: center.x - leans * width * 0.2, y: tail + height * 0.12))
        tailPath.closeSubpath()
        for path in [tailPath, outline] {
            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = CGColor(gray: 1, alpha: 1)
            shape.strokeColor = ink
            shape.lineWidth = max(0.8, height * 0.06)
            shape.lineJoin = .round
            shape.contentsScale = scale(of: canvas)
            holder.addSublayer(shape)
        }
        let words = CATextLayer()
        words.string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: spiky ? NSColor(srgbRed: 0.85, green: 0.12, blue: 0.1, alpha: 1)
                : NSColor(cgColor: ink) ?? .black,
        ])
        words.alignmentMode = .center
        words.contentsScale = scale(of: canvas)
        words.bounds = CGRect(x: 0, y: 0, width: width, height: measured.height + 2)
        words.position = CGPoint(x: center.x, y: center.y)
        holder.addSublayer(words)
        holder.opacity = 0
        let now = CACurrentMediaTime()
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.2
        spring.toValue = 1
        spring.damping = 8
        spring.stiffness = 340
        spring.mass = 0.6
        spring.duration = spring.settlingDuration
        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        tilt.values = [leans * 0.3, -leans * 0.08, 0]
        tilt.keyTimes = [0, 0.5, 1]
        tilt.duration = 0.3
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.06, 0.82, 1]
        fade.duration = life
        for animation in [spring, tilt, fade] as [CAAnimation] {
            animation.beginTime = now
            holder.add(animation, forKey: nil)
        }
        canvas.addSublayer(holder)
        remove(holder, after: life + 0.05)
    }

    // MARK: The flash

    /// The blinding flash as two become one at `point`: the screen goes
    /// white, a column of light shoots up from `floor`, and rings in both
    /// colours race out along the floor.
    static func fusionFlash(in canvas: CALayer, at point: CGPoint, floor: CGFloat, figure: CGFloat,
                            colors: (NotchMascotColor, NotchMascotColor)) {
        let area = canvas.bounds
        let white = CALayer()
        white.frame = area
        white.backgroundColor = CGColor(gray: 1, alpha: 1)
        white.opacity = 0
        let blind = CAKeyframeAnimation(keyPath: "opacity")
        blind.values = [0, 0.72, 0.5, 0]
        blind.keyTimes = [0, 0.07, 0.3, 1]
        blind.duration = 1.2
        white.add(blind, forKey: "blind")
        canvas.addSublayer(white)
        remove(white, after: 1.25)

        let reach = max(area.width, area.height) * 0.7
        let burst = CAGradientLayer()
        burst.type = .radial
        burst.colors = [CGColor(gray: 1, alpha: 1), colors.1.brightened(0.3).cgColor, colors.0.cgColor.copy(alpha: 0.5)
                        ?? colors.0.cgColor, colors.0.cgColor.copy(alpha: 0) ?? colors.0.cgColor]
        burst.locations = [0, 0.15, 0.4, 1]
        burst.startPoint = CGPoint(x: 0.5, y: 0.5)
        burst.endPoint = CGPoint(x: 1, y: 1)
        burst.bounds = CGRect(x: 0, y: 0, width: reach * 2, height: reach * 2)
        burst.position = point
        burst.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.02
        grow.toValue = 1
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.35, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.0
        burst.add(group, forKey: "burst")
        canvas.addSublayer(burst)
        remove(burst, after: 1.05)

        // A column of light from the floor to the top of the screen.
        let column = CAGradientLayer()
        column.colors = [colors.0.cgColor.copy(alpha: 0) ?? colors.0.cgColor, colors.0.brightened(0.3).cgColor,
                         CGColor(gray: 1, alpha: 1), colors.1.brightened(0.3).cgColor,
                         colors.1.cgColor.copy(alpha: 0) ?? colors.1.cgColor]
        column.locations = [0, 0.3, 0.5, 0.7, 1]
        column.startPoint = CGPoint(x: 0, y: 0.5)
        column.endPoint = CGPoint(x: 1, y: 0.5)
        column.anchorPoint = CGPoint(x: 0.5, y: 0)
        column.bounds = CGRect(x: 0, y: 0, width: figure * 2.2, height: max(1, area.maxY - floor))
        column.position = CGPoint(x: point.x, y: floor)
        column.opacity = 0
        let widen = CAKeyframeAnimation(keyPath: "transform.scale.x")
        widen.values = [0.05, 1, 1.3, 0.1]
        widen.keyTimes = [0, 0.12, 0.6, 1]
        let rise = CABasicAnimation(keyPath: "transform.scale.y")
        rise.fromValue = 0.1
        rise.toValue = 1
        rise.duration = 0.2
        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = [0, 1, 0.9, 0]
        glow.keyTimes = [0, 0.1, 0.6, 1]
        let columnGroup = CAAnimationGroup()
        columnGroup.animations = [widen, rise, glow]
        columnGroup.duration = 1.4
        column.add(columnGroup, forKey: "column")
        canvas.addSublayer(column)
        remove(column, after: 1.45)

        for (index, color) in [colors.0, colors.1].enumerated() {
            shockwave(in: canvas, at: CGPoint(x: point.x, y: floor), reach: reach * (index == 0 ? 0.9 : 0.6),
                      color: color, delay: Double(index) * 0.12)
        }
        NotchMascotPlayEffects.sparks(in: canvas, at: point, reach: figure * 1.6,
                                      energy: NotchMascotPlay.Energy(red: 1, green: 1, blue: 1), count: 14)
    }

    /// A ring racing out along the floor from `point`, `reach` points to
    /// either side, after `delay`.
    static func shockwave(in canvas: CALayer, at point: CGPoint, reach: CGFloat, color: NotchMascotColor,
                          delay: TimeInterval = 0, length: TimeInterval = 0.8) {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -reach, y: -reach * 0.18, width: reach * 2, height: reach * 0.36),
                           transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.brightened(0.3).cgColor
        ring.lineWidth = 3
        ring.shadowColor = color.cgColor
        ring.shadowOpacity = 1
        ring.shadowRadius = 6
        ring.shadowOffset = .zero
        ring.position = point
        ring.opacity = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.04
        grow.toValue = 1
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.8, 0]
        fade.keyTimes = [0, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = length
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        ring.add(group, forKey: "wave")
        canvas.addSublayer(ring)
        remove(ring, after: delay + length + 0.05)
    }

    // MARK: Moves

    /// A faded copy of the fused one's outline left where it stood, for a
    /// teleport or a glitch.
    static func afterimage(in canvas: CALayer, at feet: CGPoint, figure: CGFloat, color: NotchMascotColor) {
        let ghost = CAShapeLayer()
        ghost.path = CGPath(roundedRect: CGRect(x: -figure * 0.4, y: 0, width: figure * 0.8, height: figure * 0.9),
                            cornerWidth: figure * 0.38, cornerHeight: figure * 0.38, transform: nil)
        ghost.fillColor = color.cgColor.copy(alpha: 0.45)
        ghost.strokeColor = color.brightened(0.4).cgColor
        ghost.lineWidth = 1.5
        ghost.position = feet
        ghost.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.9, 0.5, 0]
        let stretch = CABasicAnimation(keyPath: "transform.scale.x")
        stretch.fromValue = 1
        stretch.toValue = 0.2
        let group = CAAnimationGroup()
        group.animations = [fade, stretch]
        group.duration = 0.55
        ghost.add(group, forKey: "fade")
        canvas.addSublayer(ghost)
        remove(ghost, after: 0.6)
    }

    /// `count` wisps circling `center`, `radius` out, for `duration`, then
    /// flying off outward.
    static func wisps(in canvas: CALayer, around center: CGPoint, radius: CGFloat, color: NotchMascotColor,
                      count: Int, duration: TimeInterval) {
        let energy = NotchMascotPlay.Energy(red: color.red, green: color.green, blue: color.blue)
        for index in 0..<count {
            let start = CGFloat(index) / CGFloat(count) * .pi * 2
            let orb = NotchMascotPlayEffects.orb(in: canvas, at: center, radius: radius * 0.16, energy: energy,
                                                 duration: 0.3, life: duration + 0.6)
            let circle = CGMutablePath()
            circle.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .pi * 4, clockwise: false)
            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.path = circle
            orbit.duration = duration
            orbit.calculationMode = .paced
            let out = CABasicAnimation(keyPath: "position")
            out.fromValue = NSValue(point: CGPoint(x: center.x + cos(start) * radius, y: center.y + sin(start) * radius))
            out.toValue = NSValue(point: CGPoint(x: center.x + cos(start) * radius * 5, y: center.y + sin(start) * radius * 5))
            out.beginTime = duration
            out.duration = 0.5
            out.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let group = CAAnimationGroup()
            group.animations = [orbit, out]
            group.duration = duration + 0.5
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            orb.add(group, forKey: "wisp")
        }
    }

    /// Rings spreading out over the floor round `point`, one after another.
    static func ripples(in canvas: CALayer, at point: CGPoint, reach: CGFloat, color: NotchMascotColor, count: Int = 3) {
        for index in 0..<count {
            shockwave(in: canvas, at: point, reach: reach, color: color, delay: Double(index) * 0.45, length: 1.3)
        }
    }

    /// Bubbles flying from `start` to `end`, wobbling, and popping there.
    static func bubbleStream(in canvas: CALayer, from start: CGPoint, to end: CGPoint, side: CGFloat,
                             color: NotchMascotColor, count: Int = 9) {
        for index in 0..<count {
            let bubble = CAShapeLayer()
            let r = side * CGFloat.random(in: 0.18...0.32)
            bubble.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            bubble.fillColor = color.cgColor.copy(alpha: 0.25)
            bubble.strokeColor = color.brightened(0.5).cgColor
            bubble.lineWidth = 1.2
            bubble.position = start
            bubble.opacity = 0
            let path = CGMutablePath()
            path.move(to: start)
            let wobble = CGFloat.random(in: -1...1) * side * 0.6
            path.addQuadCurve(to: CGPoint(x: end.x, y: end.y + wobble),
                              control: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + wobble * 2))
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = path
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.85, 1]
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.4, 1, 1, 1.6]
            pop.keyTimes = [0, 0.2, 0.85, 1]
            let group = CAAnimationGroup()
            group.animations = [fly, fade, pop]
            group.duration = 0.9
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.08
            group.fillMode = .backwards
            bubble.add(group, forKey: "bubble")
            canvas.addSublayer(bubble)
            remove(bubble, after: 1.0 + Double(index) * 0.08)
        }
    }

    /// A trail of ice along the floor from `from` to `to`, glinting and melting.
    static func iceTrail(in canvas: CALayer, from: CGFloat, to: CGFloat, floor: CGFloat, color: NotchMascotColor) {
        let ice = CAGradientLayer()
        ice.colors = [color.brightened(0.6).cgColor.copy(alpha: 0) ?? color.cgColor, color.brightened(0.6).cgColor,
                      CGColor(gray: 1, alpha: 0.95)]
        ice.startPoint = CGPoint(x: from < to ? 0 : 1, y: 0.5)
        ice.endPoint = CGPoint(x: from < to ? 1 : 0, y: 0.5)
        ice.frame = CGRect(x: min(from, to), y: floor - 3, width: abs(to - from), height: 6)
        ice.cornerRadius = 3
        ice.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.1, 0.6, 1]
        fade.duration = 2.2
        ice.add(fade, forKey: "melt")
        canvas.addSublayer(ice)
        remove(ice, after: 2.25)
        for step in 0..<5 {
            let x = from + (to - from) * CGFloat(step) / 4
            NotchMascotPlayEffects.sparks(in: canvas, at: CGPoint(x: x, y: floor + 4), reach: 12,
                                          energy: NotchMascotPlay.Energy(red: 0.85, green: 0.95, blue: 1), count: 4)
        }
    }

    /// Petals bursting out from `point`, turning as they drift down.
    static func petals(in canvas: CALayer, at point: CGPoint, side: CGFloat, colors: [NotchMascotColor], count: Int = 12) {
        for index in 0..<count {
            let petal = CAShapeLayer()
            petal.path = CGPath(ellipseIn: CGRect(x: -side * 0.25, y: -side * 0.1, width: side * 0.5, height: side * 0.2),
                                transform: nil)
            petal.fillColor = colors[index % max(1, colors.count)].brightened(0.2).cgColor
            petal.position = point
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let far = side * CGFloat.random(in: 1.2...2.2)
            let path = CGMutablePath()
            path.move(to: point)
            let out = CGPoint(x: point.x + cos(angle) * far, y: point.y + abs(sin(angle)) * far * 0.6 + side * 0.4)
            path.addQuadCurve(to: CGPoint(x: out.x + side * 0.3, y: point.y - side * 0.8), control: out)
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = path
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * CGFloat.random(in: 2...4)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.7, 1]
            let group = CAAnimationGroup()
            group.animations = [fly, spin, fade]
            group.duration = 1.4
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            petal.add(group, forKey: "petal")
            canvas.addSublayer(petal)
            remove(petal, after: 1.45)
        }
    }

    /// A ball of fire falling from `start` to `end` over `duration`.
    static func drop(in canvas: CALayer, from start: CGPoint, to end: CGPoint, radius: CGFloat,
                     energy: NotchMascotPlay.Energy, duration: TimeInterval) {
        let orb = NotchMascotPlayEffects.orb(in: canvas, at: end, radius: radius, energy: energy, duration: 0.1,
                                             life: duration)
        let fall = CABasicAnimation(keyPath: "position")
        fall.fromValue = NSValue(point: start)
        fall.toValue = NSValue(point: end)
        fall.duration = duration
        fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        orb.add(fall, forKey: "fall")
    }

    /// Bars of light flickering across `rect`, as a picture breaking up.
    static func glitchBars(in canvas: CALayer, over rect: CGRect, colors: [NotchMascotColor]) {
        for index in 0..<5 {
            let bar = CALayer()
            let height = rect.height * CGFloat.random(in: 0.05...0.12)
            bar.frame = CGRect(x: rect.minX - rect.width * CGFloat.random(in: 0...0.3),
                               y: rect.minY + rect.height * CGFloat.random(in: 0...0.9),
                               width: rect.width * CGFloat.random(in: 1...1.5), height: height)
            bar.backgroundColor = colors[index % max(1, colors.count)].cgColor.copy(alpha: 0.7)
            bar.opacity = 0
            let blink = CAKeyframeAnimation(keyPath: "opacity")
            blink.values = [0, 1, 0, 0.8, 0]
            blink.keyTimes = [0, 0.2, 0.4, 0.6, 1]
            blink.calculationMode = .discrete
            blink.duration = 0.35
            blink.beginTime = CACurrentMediaTime() + Double(index) * 0.04
            bar.add(blink, forKey: "blink")
            canvas.addSublayer(bar)
            remove(bar, after: 0.6)
        }
    }
}
