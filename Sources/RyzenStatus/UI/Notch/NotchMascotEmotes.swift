// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What a comic balloon over a companion's head says.
enum NotchMascotEmote: Equatable {
    /// "!", "?", "!?", "…" and a curse, "#@!".
    case exclaim, question, interrobang, ellipsis, curse
    /// A drawn heart, a light bulb and the cross-shaped vein of anger.
    case heart, idea, anger
    /// A thought cloud holding `symbol`, a few characters at most.
    case thought(String)

    /// The text it says, for those that are text.
    var text: String? {
        switch self {
        case .exclaim: return "!"
        case .question: return "?"
        case .interrobang: return "!?"
        case .ellipsis: return "…"
        case .curse: return "#@!"
        case .thought(let symbol): return String(symbol.prefix(3))
        case .heart, .idea, .anger: return nil
        }
    }

    /// One balloon of a kind at a time.
    fileprivate var key: String {
        switch self {
        case .thought(let symbol): return "thought:" + symbol
        default: return String(describing: self)
        }
    }

    /// Pops a balloon `height` points tall into `layer`, which lays out from
    /// the top as the companion's layers do, its tail's tip at `point`: it
    /// springs out, holds a moment, rises a little as it fades, and takes
    /// itself away. The same balloon already up stays as it is; another one
    /// takes its place. With Reduce Motion it only fades in and out. The
    /// balloon keeps inside `layer`'s bounds when they are set.
    @discardableResult
    func pop(in layer: CALayer, at point: CGPoint, height: CGFloat, scale: CGFloat, reduceMotion: Bool) -> CALayer? {
        let name = "emote." + key
        let up = layer.sublayers?.filter { $0.name?.hasPrefix("emote.") == true } ?? []
        guard !up.contains(where: { $0.name == name }) else { return nil }
        up.forEach { $0.removeFromSuperlayer() }
        let balloon = NotchMascotEmoteArt.balloon(for: self, height: height, scale: scale)
        balloon.name = name
        var tip = point
        if layer.bounds.width > 0, layer.bounds.height > 0 {
            // Moved whole, tail and all, to stay in sight.
            let box = balloon.frame.offsetBy(dx: tip.x - balloon.position.x, dy: tip.y - balloon.position.y)
            tip.x += max(0, layer.bounds.minX - box.minX) - max(0, box.maxX - layer.bounds.maxX)
            tip.y += max(0, layer.bounds.minY - box.minY) - max(0, box.maxY - layer.bounds.maxY)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        balloon.position = tip
        balloon.opacity = 0
        layer.addSublayer(balloon)
        CATransaction.setCompletionBlock { balloon.removeFromSuperlayer() }
        let length: TimeInterval = 1.7
        let now = CACurrentMediaTime()
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, reduceMotion ? 0.12 : 0.04, 0.8, 1]
        fade.duration = length
        fade.beginTime = now
        balloon.add(fade, forKey: "show")
        if !reduceMotion {
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.15
            spring.toValue = 1
            spring.damping = 9
            spring.stiffness = 320
            spring.mass = 0.6
            spring.initialVelocity = 4
            spring.duration = min(length * 0.6, spring.settlingDuration)
            spring.beginTime = now
            balloon.add(spring, forKey: "pop")
            let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            tilt.values = [-0.25, 0.08, 0]
            tilt.keyTimes = [0, 0.5, 1]
            tilt.duration = 0.32
            tilt.beginTime = now
            tilt.isAdditive = true
            balloon.add(tilt, forKey: "tilt")
            let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
            rise.values = [0, 0, -height * 0.25]
            rise.keyTimes = [0, 0.8, 1]
            rise.duration = length
            rise.beginTime = now
            rise.isAdditive = true
            balloon.add(rise, forKey: "rise")
        }
        CATransaction.commit()
        return balloon
    }
}

/// The balloons' drawing, in points about the tail's tip, y growing downward.
private enum NotchMascotEmoteArt {
    static func balloon(for emote: NotchMascotEmote, height: CGFloat, scale: CGFloat) -> CALayer {
        let ink = NotchMascotColor.ink.cgColor
        let line = max(0.6, height * 0.07)
        let symbolHeight = height * 0.58
        let symbol = self.symbol(emote, height: symbolHeight)
        let width = max(height * 1.15, symbol.box.width + height * 0.6)
        let tail = height * 0.32
        // The body sits up and to the right of the tip, its tail coming
        // down to it from the lower left.
        let center = CGPoint(x: width * 0.28, y: -(tail + height / 2))
        let radii = CGSize(width: width / 2, height: height / 2)
        let outline: CGPath
        var puffs: [CGPath] = []
        if case .thought = emote {
            outline = cloud(center: center, radii: radii)
            // Two little bubbles trail from the cloud's lower edge down to the tip.
            let edge = CGPoint(x: center.x - radii.width * 0.3, y: center.y + radii.height * 0.85)
            for (share, radius) in [(0.35, 0.11), (0.8, 0.07)] as [(CGFloat, CGFloat)] {
                let spot = CGPoint(x: edge.x * (1 - share), y: edge.y * (1 - share))
                let r = height * radius
                puffs.append(CGPath(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r, width: r * 2, height: r * 2),
                                    transform: nil))
            }
        } else {
            outline = speech(center: center, radii: radii)
        }
        let path = CGMutablePath()
        path.addPath(outline)
        puffs.forEach { path.addPath($0) }
        let bounds = path.boundingBoxOfPath.insetBy(dx: -line, dy: -line)

        let holder = CALayer()
        holder.bounds = bounds
        // It springs from the tip of its tail.
        holder.anchorPoint = CGPoint(x: -bounds.minX / bounds.width, y: -bounds.minY / bounds.height)
        holder.contentsScale = scale
        let body = CAShapeLayer()
        body.path = path
        body.fillColor = NSColor.white.cgColor
        body.strokeColor = ink
        body.lineWidth = line
        body.lineJoin = .round
        let art = CAShapeLayer()
        var move = CGAffineTransform(translationX: center.x - symbol.box.midX, y: center.y - symbol.box.midY)
        art.path = symbol.path.copy(using: &move)
        art.fillColor = symbol.fill
        art.strokeColor = symbol.stroke
        art.lineWidth = symbol.stroke == nil ? 0 : symbol.line
        art.lineCap = .round
        art.lineJoin = .round
        for layer in [body, art] {
            layer.bounds = bounds
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            layer.contentsScale = scale
            holder.addSublayer(layer)
        }
        for layer in [holder, body, art] {
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(),
                             "path": NSNull(), "sublayers": NSNull()]
        }
        return holder
    }

    private struct Symbol {
        var path: CGPath
        var box: CGRect
        var fill: CGColor?
        var stroke: CGColor? = nil
        var line: CGFloat = 0
    }

    private static func symbol(_ emote: NotchMascotEmote, height: CGFloat) -> Symbol {
        let ink = NotchMascotColor.ink.cgColor
        if let text = emote.text {
            let path = NotchMascotPatShapes.text(text, height: emote == .ellipsis ? height * 0.5 : height)
            // A curse comes out red.
            let fill = emote == .curse ? NotchMascotFaceShapes.color(0xE53935) : ink
            return Symbol(path: path, box: path.boundingBoxOfPath, fill: fill)
        }
        switch emote {
        case .heart:
            let path = NotchMascotPatShapes.heart(side: height)
            return Symbol(path: path, box: path.boundingBoxOfPath, fill: NotchMascotFaceShapes.color(0xFF4F8B))
        case .anger:
            let path = NotchMascotFaceShapes.vein(radius: height * 0.48)
            return Symbol(path: path, box: path.boundingBoxOfPath, fill: nil,
                          stroke: NotchMascotFaceShapes.color(0xE8323C), line: max(0.8, height * 0.16))
        default:
            let path = bulb(height: height)
            return Symbol(path: path, box: path.boundingBoxOfPath, fill: NotchMascotFaceShapes.gold,
                          stroke: NotchMascotFaceShapes.color(0x8A6400), line: max(0.5, height * 0.06))
        }
    }

    /// A light bulb: the glass, its screw base and three short rays.
    private static func bulb(height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = height * 0.3
        let glass = CGPoint(x: 0, y: -height * 0.12)
        path.addEllipse(in: CGRect(x: glass.x - r, y: glass.y - r, width: r * 2, height: r * 2))
        path.addRoundedRect(in: CGRect(x: -r * 0.5, y: glass.y + r * 0.8, width: r, height: r * 0.75),
                            cornerWidth: r * 0.2, cornerHeight: r * 0.2)
        for angle in [-CGFloat.pi / 2, -CGFloat.pi / 2 - 0.75, -CGFloat.pi / 2 + 0.75] {
            let from = CGPoint(x: glass.x + cos(angle) * r * 1.35, y: glass.y + sin(angle) * r * 1.35)
            let to = CGPoint(x: glass.x + cos(angle) * r * 1.75, y: glass.y + sin(angle) * r * 1.75)
            path.addRoundedRect(in: CGRect(x: min(from.x, to.x) - r * 0.06, y: min(from.y, to.y) - r * 0.06,
                                           width: abs(to.x - from.x) + r * 0.12, height: abs(to.y - from.y) + r * 0.12),
                                cornerWidth: r * 0.06, cornerHeight: r * 0.06)
        }
        return path
    }

    /// A speech balloon: an oval whose tail runs down to the origin.
    private static func speech(center: CGPoint, radii: CGSize) -> CGPath {
        // Around the oval from one side of the tail's root to the other.
        let start = CGFloat(105) * .pi / 180, end = CGFloat(140) * .pi / 180 - 2 * .pi
        let steps = 48
        let path = CGMutablePath()
        for step in 0...steps {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }

    /// A thought cloud: scallops round an oval.
    private static func cloud(center: CGPoint, radii: CGSize) -> CGPath {
        let path = CGMutablePath()
        let bumps = 9
        func at(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radii.width * 0.88 * cos(angle), y: center.y + radii.height * 0.82 * sin(angle))
        }
        path.move(to: at(0))
        for bump in 0..<bumps {
            let from = CGFloat(bump) / CGFloat(bumps) * 2 * .pi
            let to = CGFloat(bump + 1) / CGFloat(bumps) * 2 * .pi
            let middle = (from + to) / 2
            let control = CGPoint(x: center.x + radii.width * 1.22 * cos(middle),
                                  y: center.y + radii.height * 1.22 * sin(middle))
            path.addQuadCurve(to: at(to), control: control)
        }
        path.closeSubpath()
        return path
    }
}

extension NotchMascotHostView {
    /// Pops a comic balloon over the companion's head.
    func emote(_ emote: NotchMascotEmote) {
        guard let layer, mascot.size > 0, !mascot.showsSprite else { return }
        let head = mascot.headTop
        emote.pop(in: layer, at: CGPoint(x: head.x + mascot.size * 0.14, y: head.y - mascot.size * 0.02),
                  height: max(12, mascot.size * 0.46), scale: mascot.root.contentsScale, reduceMotion: mascot.reduceMotion)
    }
}

extension NotchMascotDesktop {
    /// Pops a comic balloon over its head while it is out, as a cartoon says
    /// what it feels: one at a time, and the same one again only once the
    /// last has gone.
    func emote(_ emote: NotchMascotEmote) {
        guard isOut, let host else { return }
        host.emote(emote)
    }
}

/// Pats in quick succession, so a companion patted over and over says so:
/// a heart after a few, and the vein of anger once it has had enough.
struct NotchMascotPatStreak {
    private(set) var count = 0
    private var last: CFTimeInterval = -.infinity
    /// Pats further apart than this start the count again.
    static let gap: TimeInterval = 2.5

    /// Counts a pat at `time`, and what it says to it, if anything.
    mutating func note(at time: CFTimeInterval) -> NotchMascotEmote? {
        count = time - last <= Self.gap ? count + 1 : 1
        last = time
        switch count {
        case 4: return .heart
        case 8:
            count = 0
            return .anger
        default: return nil
        }
    }
}
