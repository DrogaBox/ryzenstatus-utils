// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The colours a transformation paints: the body, the aura around it and the
/// sparks that crackle over it.
struct NotchMascotFormPalette {
    let light: NSColor
    let shade: NSColor
    let core: NSColor
    let edge: NSColor
    let spark: NSColor

    init(_ form: NotchMascotForm) {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        switch form {
        case .golden:
            light = rgb(0xFFE45C); shade = rgb(0xF2A900); core = rgb(0xFFF6B0); edge = rgb(0xFFB300); spark = rgb(0xFFF6B0)
        case .goldenLightning:
            light = rgb(0xFFEA7A); shade = rgb(0xF5B400); core = rgb(0xFFF6B0); edge = rgb(0xFFB300); spark = rgb(0xA8ECFF)
        case .goldenFury:
            light = rgb(0xFFDD55); shade = rgb(0xE89400); core = rgb(0xFFF0A0); edge = rgb(0xFF9100); spark = rgb(0xA8ECFF)
        case .divine:
            light = rgb(0x8FDFFF); shade = rgb(0x1E7BE5); core = rgb(0xDDF6FF); edge = rgb(0x2F7BFF); spark = rgb(0xFFFFFF)
        }
    }
}

/// The aura a transformation wraps the companion in, drawn with Core
/// Animation like the rest of it: a flickering glow and rising flames behind
/// the body, and, from the second form on, lightning in front. Everything
/// loops in the render server; the app sets it up once per form.
/// Layers lay out from the top, y growing downward, like the companion's.
final class NotchMascotAura {
    /// Behind the body; the transformation scales it as a whole.
    let back = CALayer()
    /// In front of the body, for the lightning.
    let front = CALayer()

    private(set) var form: NotchMascotForm?
    private let glow = CAGradientLayer()
    private let flames = CAEmitterLayer()
    private var bolts: [CAShapeLayer] = []
    /// Sparks that only show while a transformation charges, in every form.
    private let chargeSparks = CALayer()
    /// The shock wave that rings out at the burst.
    private let ring = CAShapeLayer()

    init() {
        for layer in [back, front, glow] { layer.actions = Self.noActions }
        flames.actions = Self.noActions
        back.addSublayer(glow)
        back.addSublayer(flames)
        chargeSparks.actions = Self.noActions
        chargeSparks.opacity = 0
        front.addSublayer(chargeSparks)
        ring.actions = Self.noActions
        ring.opacity = 0
        ring.fillColor = nil
        front.addSublayer(ring)
        back.isHidden = true
        front.isHidden = true
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
        "frame": NSNull(), "sublayers": NSNull(), "colors": NSNull(), "contents": NSNull(), "birthRate": NSNull(),
    ]

    /// Sets the aura up for `form` around a companion of `size` points;
    /// nil takes it away. `reduceMotion` keeps the glow still and the
    /// flames and lightning out.
    func configure(form: NotchMascotForm?, size: CGFloat, scale: CGFloat, reduceMotion: Bool) {
        self.form = form
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        back.frame = box
        front.frame = box
        for layer in [back, front, glow, flames] { layer.contentsScale = scale }
        for bolt in bolts { bolt.removeFromSuperlayer() }
        bolts = []
        chargeSparks.sublayers = nil
        chargeSparks.frame = box
        ring.frame = box
        glow.removeAllAnimations()
        flames.birthRate = 0
        guard let form, size > 0 else {
            back.isHidden = true
            front.isHidden = true
            return
        }
        back.isHidden = false
        front.isHidden = false
        let palette = NotchMascotFormPalette(form)
        let reach = form == .goldenFury || form == .divine ? 1.25 : 1.0

        // A glow taller than wide, rising above the head like a flame.
        let width = size * (1.15 + 0.2 * reach)
        let height = size * (1.25 + 0.3 * reach)
        glow.type = .radial
        glow.frame = CGRect(x: (size - width) / 2, y: size * 0.98 - height, width: width, height: height)
        glow.colors = [palette.core.withAlphaComponent(0.85).cgColor, palette.edge.withAlphaComponent(0.55).cgColor,
                       palette.edge.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.62)
        glow.endPoint = CGPoint(x: 1, y: 1)

        ring.contentsScale = scale
        ring.path = CGPath(ellipseIn: box.insetBy(dx: size * 0.08, dy: size * 0.08), transform: nil)
        ring.strokeColor = palette.core.cgColor
        ring.lineWidth = max(1, size * 0.07)
        ring.shadowColor = palette.edge.cgColor
        ring.shadowOpacity = 1
        ring.shadowRadius = max(1, size * 0.08)
        ring.shadowOffset = .zero
        guard !reduceMotion else { return }
        for index in 0..<3 {
            chargeSparks.addSublayer(Self.bolt(index: index, size: size, scale: scale, color: palette.spark))
        }
        let flicker = CAKeyframeAnimation(keyPath: "transform")
        flicker.values = [(1, 1), (1.04, 1.08), (0.98, 0.97), (1.03, 1.05), (1, 1)].map {
            NSValue(caTransform3D: Self.rising(scaleX: $0.0, scaleY: $0.1, height: height))
        }
        flicker.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        flicker.duration = form == .goldenFury ? 0.32 : 0.45
        flicker.repeatCount = .infinity
        glow.add(flicker, forKey: "flicker")

        // Flames: soft dots born along the feet that rise and fade.
        flames.frame = box
        flames.emitterShape = .line
        flames.emitterPosition = CGPoint(x: size / 2, y: size * 0.88)
        flames.emitterSize = CGSize(width: size * 0.8, height: 1)
        flames.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = Self.dot
        cell.birthRate = Float(form == .golden ? 26 : form == .goldenLightning ? 32 : 44)
        cell.lifetime = 0.65
        cell.lifetimeRange = 0.2
        cell.velocity = 0
        cell.yAcceleration = -size * 5.5 * reach
        cell.xAcceleration = 0
        cell.emissionRange = .pi / 8
        cell.scale = size * 0.011
        cell.scaleRange = size * 0.004
        cell.scaleSpeed = -size * 0.012
        cell.alphaSpeed = -1.4
        cell.color = palette.edge.withAlphaComponent(0.9).cgColor
        flames.emitterCells = [cell]
        flames.birthRate = 1

        // Lightning from the second form on, more of it in the third.
        guard form != .golden else { return }
        let count = form == .goldenLightning ? 2 : 3
        for index in 0..<count {
            let bolt = Self.bolt(index: index, size: size, scale: scale, color: palette.spark)
            bolt.opacity = 0
            let crackle = CAKeyframeAnimation(keyPath: "opacity")
            crackle.values = [0, 1, 0, 0.8, 0, 0]
            crackle.keyTimes = [0, 0.04, 0.09, 0.13, 0.18, 1]
            crackle.calculationMode = .discrete
            crackle.duration = [1.3, 1.75, 2.2][index] / (form == .goldenFury ? 1.4 : 1)
            crackle.beginTime = CACurrentMediaTime() + Double(index) * 0.37
            crackle.repeatCount = .infinity
            bolt.add(crackle, forKey: "crackle")
            front.addSublayer(bolt)
            bolts.append(bolt)
        }
    }

    private static func bolt(index: Int, size: CGFloat, scale: CGFloat, color: NSColor) -> CAShapeLayer {
        let bolt = CAShapeLayer()
        bolt.actions = noActions
        bolt.frame = CGRect(x: 0, y: 0, width: size, height: size)
        bolt.contentsScale = scale
        bolt.path = boltPath(index: index, size: size)
        bolt.fillColor = nil
        bolt.strokeColor = color.cgColor
        bolt.lineWidth = max(0.8, size * 0.035)
        bolt.lineJoin = .miter
        bolt.shadowColor = color.cgColor
        bolt.shadowOpacity = 0.9
        bolt.shadowRadius = max(0.6, size * 0.05)
        bolt.shadowOffset = .zero
        return bolt
    }

    /// A scale that keeps the glow's foot where it is, so it grows upward.
    private static func rising(scaleX: CGFloat, scaleY: CGFloat, height: CGFloat) -> CATransform3D {
        CATransform3DConcat(CATransform3DMakeScale(scaleX, scaleY, 1),
                            CATransform3DMakeTranslation(0, height * 0.32 * (1 - scaleY), 0))
    }

    /// A short zigzag beside or above the body, a different one per index.
    private static func boltPath(index: Int, size: CGFloat) -> CGPath {
        let starts: [(CGFloat, CGFloat, CGFloat)] = [(0.12, 0.22, 1), (0.86, 0.3, -1), (0.5, -0.12, 1)]
        let (x, y, side) = starts[index % starts.count]
        let step = size * 0.11
        let path = CGMutablePath()
        var point = CGPoint(x: x * size, y: y * size)
        path.move(to: point)
        for segment in 0..<4 {
            let sway = (segment % 2 == 0 ? 1 : -1) * side * step * 0.7
            point = CGPoint(x: point.x + sway, y: point.y + step)
            path.addLine(to: point)
        }
        return path
    }

    /// A soft round dot for the flames, white so each form tints it.
    private static let dot: CGImage? = {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: CGFloat(side) / 2, options: [])
        return context.makeImage()
    }()

    // MARK: Transformation

    /// How long the whole transformation takes, and when the burst comes.
    static let transformationLength: CFTimeInterval = 2.4
    static let burstAt: CFTimeInterval = 0.95

    /// The aura's part of the transformation: barely there while it charges,
    /// then bursting out past its size and settling.
    func playTransformation(beginTime: CFTimeInterval) {
        guard form != nil else { return }
        let length = Self.transformationLength
        let burst = Self.burstAt / length
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.3, 0.45, 0.35, 1.45, 0.92, 1.0]
        grow.keyTimes = [0, NSNumber(value: burst * 0.5), NSNumber(value: burst), NSNumber(value: burst + 0.12),
                         NSNumber(value: burst + 0.3), 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.5, 0.25, 0.6, 1, 1]
        fade.keyTimes = [0, NSNumber(value: burst * 0.3), NSNumber(value: burst * 0.6), NSNumber(value: burst * 0.9),
                         NSNumber(value: burst + 0.05), 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = length
        group.beginTime = beginTime
        group.fillMode = .backwards
        back.add(group, forKey: "transformation")

        // A burst of flames as it breaks out, then the steady rate.
        let surge = CAKeyframeAnimation(keyPath: "birthRate")
        surge.values = [0.4, 0.4, 5, 1]
        surge.keyTimes = [0, NSNumber(value: burst), NSNumber(value: burst + 0.04), NSNumber(value: burst + 0.35)]
        surge.duration = length
        surge.beginTime = beginTime
        flames.add(surge, forKey: "surge")

        // The lightning crackles hard while it charges.
        let charge = CAKeyframeAnimation(keyPath: "opacity")
        charge.values = [1, 0.2, 1, 0.3, 1, 1]
        charge.keyTimes = [0, 0.1, 0.2, 0.3, NSNumber(value: burst), 1]
        charge.calculationMode = .discrete
        charge.duration = length
        charge.beginTime = beginTime
        front.add(charge, forKey: "charge")

        // Sparks snap around it while it gathers power, whatever the form.
        let sparks = CAKeyframeAnimation(keyPath: "opacity")
        sparks.values = [0, 1, 0, 1, 0, 1, 0, 1, 0, 0]
        sparks.keyTimes = [0, 0.06, 0.12, 0.18, 0.24, 0.3, 0.34, NSNumber(value: burst * 0.95), NSNumber(value: burst), 1]
        sparks.calculationMode = .discrete
        sparks.duration = length
        sparks.beginTime = beginTime
        chargeSparks.add(sparks, forKey: "sparks")

        let wave = CAKeyframeAnimation(keyPath: "transform.scale")
        wave.values = [0.3, 2.6]
        let waveFade = CAKeyframeAnimation(keyPath: "opacity")
        waveFade.values = [1, 0]
        let shock = CAAnimationGroup()
        shock.animations = [wave, waveFade]
        shock.duration = 0.55
        shock.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shock.beginTime = beginTime + Self.burstAt
        ring.add(shock, forKey: "shock")
    }
}

/// The shapes a pat brings out, in points from the top left corner, y
/// growing downward like the rest of the companion.
enum NotchMascotPatShapes {
    static func heart(side: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = side, h = side
        path.move(to: CGPoint(x: w / 2, y: h * 0.92))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.32), control1: CGPoint(x: w * 0.2, y: h * 0.72),
                      control2: CGPoint(x: 0, y: h * 0.55))
        path.addArc(center: CGPoint(x: w * 0.25, y: h * 0.3), radius: w * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.75, y: h * 0.3), radius: w * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addCurve(to: CGPoint(x: w / 2, y: h * 0.92), control1: CGPoint(x: w, y: h * 0.55),
                      control2: CGPoint(x: w * 0.8, y: h * 0.72))
        path.closeSubpath()
        return path
    }

    /// `string` as an outline `height` points tall, set in a bold rounded
    /// face, with its top left corner at the origin.
    static func text(_ string: String, height: CGFloat) -> CGPath {
        let base = NSFont.systemFont(ofSize: height, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: height) } ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        let glyphs = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(ids, positions) {
                guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                glyphs.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }
        // Glyphs grow upward; the companion's layers grow downward.
        let box = glyphs.boundingBoxOfPath
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -box.minX, ty: box.maxY)
        return glyphs.copy(using: &flip) ?? glyphs
    }
}
