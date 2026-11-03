// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// The parts of a face beyond its eyes: brows over each eye, a mouth under
/// them, and the marks a cartoon draws about a face, from red cheeks, sweat
/// and tears in streams to a throbbing vein, steam, twinkles, gloom, dollar
/// signs, circling stars and a green tinge. The rig mounts `eyeLevel` in its
/// face layer, so the brows and the dollar signs go where the eyes look, and
/// `around` beside the face, so the mouth and the other marks follow the head
/// but not the gaze. Everything is sized from an open eye and coloured like
/// the eyes: ink, or the robot's own light, glowing as its eyes do.
///
/// It keeps the face the companion keeps and shows another over it for a
/// moment, or held, as the eyes do. Each face shown over it is a set of
/// layers of its own, and going from one face to another fades one set out
/// as the other pops in, since mouths of different shapes cannot morph into
/// each other. Brows morph, being one curve bent another way. Marks move with
/// repeating Core Animation animations only while they show and motion is
/// welcome, and those animations go when the marks do; with Reduce Motion
/// they show still.
///
/// A figure whose drawing has its own mouth draws none here, so two mouths
/// never fight over one face: the devourer, whose big mouth is its whole
/// character, the dog and the axolotl with their drawn smiles, the comic's
/// two figures, and the phoenix, the swan and the penguin, whose beaks are
/// their mouths. They still pull faces with their brows and marks. The ghost,
/// whose mouth shows only as it says boo, takes these mouths the rest of the
/// time. Sprite figures draw none of it.
final class NotchMascotFeatures {
    /// In the face layer, over the eyes: the brows and the dollar signs.
    let eyeLevel = CALayer()
    /// Beside the face, under the eyes: the mouth and every other mark.
    let around = CALayer()
    var reduceMotion = false

    /// Its head in its square, in points, where marks gather round.
    private(set) var head = CGRect.zero
    /// The figure's topmost point in its square, antenna and ears and all.
    private(set) var crown: CGFloat = 0

    private var size: CGFloat = 0
    /// Sprite figures draw no features.
    private var enabled = true
    private var metrics = NotchMascotFaceMetrics()
    private let kept = NotchMascotFaceSet()
    /// The faces shown over the one it keeps, by the key that shows them.
    private var shown: [String: NotchMascotFaceSet] = [:]
    private var motion = false

    init() {
        for layer in [eyeLevel, around] { layer.actions = NotchMascotFaceSet.noActions }
        kept.mount(eyeLevel: eyeLevel, around: around)
    }

    /// Whether the figure's drawing already has a mouth of its own.
    static func drawsOwnMouth(_ style: NotchMascotStyle) -> Bool {
        switch style {
        case .devourer, .dog, .axolotl, .cristobal, .whiteRabbit, .phoenix, .swan, .penguin: return true
        default: return false
        }
    }

    // MARK: Look

    func configure(look: NotchMascotLook, size: CGFloat, scale: CGFloat) {
        self.size = size
        enabled = look.style.sprite == nil
        metrics = NotchMascotFaceMetrics(look: look, size: size)
        head = metrics.head
        crown = metrics.crown
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [eyeLevel, around] {
            layer.frame = box
            layer.contentsScale = scale
            layer.isHidden = !enabled
        }
        for set in [kept] + Array(shown.values) {
            set.stopAll()
            set.layout(box: box, scale: scale)
        }
        for set in shown.values { set.setOpacity(0) }
        kept.setOpacity(1)
        kept.draw(kept.expression, metrics)
        CATransaction.commit()
        syncMarks()
    }

    // MARK: Faces

    /// Keeps `expression`. Animated, brows bend to their new shape, a new
    /// mouth pops in and marks fade from one set to the next.
    func apply(_ expression: NotchMascotExpression, animated: Bool) {
        guard size > 0 else { return }
        let old = kept.expression
        let animated = animated && !reduceMotion && enabled
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            if old.brows != expression.brows {
                if old.brows != .none, expression.brows != .none {
                    kept.morphBrows(to: expression.brows, metrics)
                } else {
                    Self.crossfade(kept.brows, duration: 0.18)
                }
            }
            if old.mouth != expression.mouth {
                Self.crossfade(kept.mouth, duration: 0.14)
                if expression.mouth != .none { kept.mouth.add(Self.pop(), forKey: "pop") }
            }
            if old.marks != expression.marks {
                Self.crossfade(kept.marks, duration: 0.2)
                Self.crossfade(kept.eyeMarks, duration: 0.2)
            }
        }
        if old.marks != expression.marks { kept.stillMarks() }
        kept.draw(expression, metrics)
        CATransaction.commit()
        syncMarks()
    }

    /// Shows `expression` over the face it keeps for `duration`, from
    /// `beginTime` or now, and comes back to its own. Only the parts that
    /// differ change: a flash with the same brows leaves the brows be.
    func flash(_ expression: NotchMascotExpression, duration: TimeInterval, beginTime: CFTimeInterval?, key: String) {
        guard size > 0, enabled, duration > 0 else { return }
        let set = overlay(key)
        let own = kept.expression
        let begin = beginTime ?? CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        set.stillMarks()
        set.draw(expression, metrics)
        for (mine, theirs, differs) in pairs(set, own: own, shown: expression) {
            guard differs else {
                mine.removeAnimation(forKey: "flash." + key)
                theirs.removeAnimation(forKey: "show")
                continue
            }
            mine.add(fade([1, 0, 0, 1], begin: begin, duration: duration), forKey: "flash." + key)
            theirs.add(fade([0, 1, 1, 0], begin: begin, duration: duration), forKey: "show")
        }
        if expression.mouth != own.mouth, expression.mouth != .none, !reduceMotion {
            let pop = Self.pop()
            pop.beginTime = begin
            set.mouth.add(pop, forKey: "pop")
        }
        CATransaction.commit()
        if motion, !reduceMotion, expression.marks != own.marks {
            set.animateMarks(from: begin, for: duration, metrics)
        }
    }

    /// Turns to `expression` at `time` on the media clock and stays there
    /// until a reset, for a face set ahead of a moment.
    func turn(to expression: NotchMascotExpression, at time: CFTimeInterval) {
        hold(expression, key: "turn", at: time, duration: reduceMotion ? 0.01 : 0.16)
    }

    /// Shows `expression` over its own face from now until `release(key:)`.
    func hold(_ expression: NotchMascotExpression, key: String) {
        hold(expression, key: key, at: CACurrentMediaTime(), duration: reduceMotion ? 0.01 : 0.18)
    }

    /// Lets go of a face held with `key`, easing back to its own.
    func release(key: String) {
        guard let set = shown[key] else { return }
        let held = "hold." + key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (mine, theirs, _) in pairs(set, own: kept.expression, shown: set.expression) {
            for (layer, rest) in [(mine, Float(1)), (theirs, Float(0))] where layer.animation(forKey: held) != nil {
                let from = layer.presentation()?.opacity ?? rest
                layer.removeAnimation(forKey: held)
                guard !reduceMotion, from != rest else { continue }
                let back = CABasicAnimation(keyPath: "opacity")
                back.fromValue = from
                back.toValue = rest
                back.duration = 0.18
                layer.add(back, forKey: "release." + key)
            }
        }
        CATransaction.commit()
        set.stillMarks()
    }

    /// Back to `expression` with nothing shown over it and every motion off.
    func reset(to expression: NotchMascotExpression) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for set in shown.values {
            set.stopAll()
            set.setOpacity(0)
        }
        kept.stopAll()
        kept.setOpacity(1)
        if size > 0 { kept.draw(expression, metrics) }
        CATransaction.commit()
        syncMarks()
    }

    /// Its marks move only while it is in sight and motion is welcome.
    func setMotion(_ motion: Bool) {
        guard motion != self.motion else { return }
        self.motion = motion
        syncMarks()
    }

    private func syncMarks() {
        guard enabled, size > 0, motion, !reduceMotion, !kept.expression.marks.isEmpty else {
            kept.stillMarks()
            return
        }
        guard !kept.marksMove else { return }
        kept.animateMarks(from: CACurrentMediaTime(), for: nil, metrics)
    }

    private func hold(_ expression: NotchMascotExpression, key: String, at time: CFTimeInterval, duration: TimeInterval) {
        guard size > 0, enabled else { return }
        let set = overlay(key)
        let held = "hold." + key
        let own = kept.expression
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        set.stillMarks()
        set.draw(expression, metrics)
        for (mine, theirs, differs) in pairs(set, own: own, shown: expression) {
            mine.removeAnimation(forKey: "release." + key)
            theirs.removeAnimation(forKey: "release." + key)
            guard differs else {
                mine.removeAnimation(forKey: held)
                theirs.removeAnimation(forKey: held)
                continue
            }
            for (layer, from, to) in [(mine, Float(1), Float(0)), (theirs, Float(0), Float(1))] {
                let turn = CABasicAnimation(keyPath: "opacity")
                turn.fromValue = from
                turn.toValue = to
                turn.beginTime = time
                turn.duration = duration
                turn.fillMode = .both
                turn.isRemovedOnCompletion = false
                layer.add(turn, forKey: held)
            }
        }
        CATransaction.commit()
        if motion, !reduceMotion, expression.marks != own.marks {
            set.animateMarks(from: time, for: nil, metrics)
        }
    }

    /// The set that shows faces over its own with `key`, made the first time.
    private func overlay(_ key: String) -> NotchMascotFaceSet {
        if let set = shown[key] { return set }
        let set = NotchMascotFaceSet()
        set.mount(eyeLevel: eyeLevel, around: around)
        set.layout(box: CGRect(x: 0, y: 0, width: size, height: size), scale: around.contentsScale)
        set.setOpacity(0)
        shown[key] = set
        return set
    }

    /// The face it keeps and one shown over it, part by part, and whether
    /// that part differs between them.
    private func pairs(_ set: NotchMascotFaceSet, own: NotchMascotExpression,
                       shown: NotchMascotExpression) -> [(CALayer, CALayer, Bool)] {
        let marks = own.marks != shown.marks
        return [(kept.brows, set.brows, own.brows != shown.brows), (kept.mouth, set.mouth, own.mouth != shown.mouth),
                (kept.marks, set.marks, marks), (kept.eyeMarks, set.eyeMarks, marks)]
    }

    private func fade(_ values: [Float], begin: CFTimeInterval, duration: TimeInterval) -> CAKeyframeAnimation {
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = values
        fade.keyTimes = [0, 0.12, 0.88, 1]
        fade.beginTime = begin
        fade.duration = duration
        if reduceMotion { fade.calculationMode = .discrete }
        return fade
    }

    private static func crossfade(_ layer: CALayer, duration: TimeInterval) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        layer.add(fade, forKey: "fade")
    }

    /// A new mouth pops out a little past its size and settles.
    private static func pop() -> CAKeyframeAnimation {
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.5, 1.15, 1]
        pop.keyTimes = [0, 0.55, 1]
        pop.duration = 0.26
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return pop
    }
}

/// Where the features go on a figure and how they are drawn, in points in
/// its square.
private struct NotchMascotFaceMetrics {
    var left = CGPoint.zero
    var right = CGPoint.zero
    /// An open eye's width and height.
    var eye = CGSize.zero
    /// The middle of its mouth, or nil when the figure draws its own.
    var mouth: CGPoint?
    var mouthWidth: CGFloat = 0
    var head = CGRect.zero
    var crown: CGFloat = 0
    var line: CGFloat = 0.5
    /// Lines in the robot's light, glowing, rather than ink.
    var glows = false
    var ink = NotchMascotColor.ink.cgColor

    init() {}

    init(look: NotchMascotLook, size: CGFloat) {
        let face = look.face
        left = CGPoint(x: face.leftEye.x * size, y: face.leftEye.y * size)
        right = CGPoint(x: face.rightEye.x * size, y: face.rightEye.y * size)
        eye = CGSize(width: face.eyeSize.width * size, height: face.eyeSize.height * size)
        line = max(0.5, eye.width * 0.3)
        let robot = look.style == .robot
        glows = robot
        if robot {
            ink = look.bodyPalette.light.cgColor
            let parts = NotchMascotGeometry.robot(size: size)
            head = parts.head.boundingBoxOfPath
            crown = parts.bulb.boundingBoxOfPath.minY
        } else {
            let body = (NotchMascotCreatures.body(look.style, size: size)
                ?? NotchMascotGeometry.body(look.shape, size: size)).boundingBoxOfPath
            head = NotchMascotCreatures.headOutline(look.style, size: size) ?? body
            crown = NotchMascotCreatures.bounds(look.style).map { $0.minY * size } ?? body.minY
        }
        guard !NotchMascotFeatures.drawsOwnMouth(look.style) else { return }
        // About two and a half eyes wide, never wider than the eyes are apart;
        // the robot's fits inside its face plate.
        mouthWidth = max(2.5, min(eye.width * 2.6, abs(right.x - left.x) * 0.72) * (robot ? 0.7 : 1))
        if let spot = NotchMascotCreatures.anatomy(look.style)?.mouth {
            mouth = CGPoint(x: spot.x * size, y: spot.y * size)
        } else {
            // Between the eyes, about an eye's height under them.
            mouth = CGPoint(x: (left.x + right.x) / 2, y: max(left.y, right.y) + eye.height * (robot ? 0.75 : 0.85))
        }
    }
}

/// One face's brows, mouth and marks: the face it keeps, or one shown over it.
private final class NotchMascotFaceSet {
    static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        "sublayers": NSNull(), "shadowColor": NSNull(), "shadowOpacity": NSNull(), "lineDashPattern": NSNull(),
        "lineDashPhase": NSNull(), "mask": NSNull(), "contents": NSNull(),
    ]

    let brows = CALayer()
    let eyeMarks = CALayer()
    let mouth = CALayer()
    let marks = CALayer()
    private(set) var expression = NotchMascotExpression(left: .open, right: .open)
    /// Its marks are moving for as long as they show.
    private(set) var marksMove = false

    private let leftBrow = CAShapeLayer()
    private let rightBrow = CAShapeLayer()
    private let mouthFill = CAShapeLayer()
    private let mouthTongue = CAShapeLayer()
    private let tongueMask = CAShapeLayer()
    private let mouthTeeth = CAShapeLayer()
    private let mouthLine = CAShapeLayer()
    private let blush = CAShapeLayer()
    private let queasy = CAShapeLayer()
    private let tears = CAShapeLayer()
    private let gloom = CAShapeLayer()
    private let sweat = CAShapeLayer()
    private let vein = CAShapeLayer()
    private let steam = (0..<3).map { _ in CAShapeLayer() }
    private let sparkles = (0..<3).map { _ in CAShapeLayer() }
    private let stars = (0..<3).map { _ in CAShapeLayer() }
    private let money = (0..<2).map { _ in CAShapeLayer() }
    /// The ellipse the stars circle the head on.
    private var orbit: CGPath?

    private var markLayers: [CAShapeLayer] { [blush, queasy, tears, gloom, sweat, vein] + steam + sparkles + stars + money }
    private var shapeLayers: [CAShapeLayer] {
        [leftBrow, rightBrow, mouthFill, mouthTongue, tongueMask, mouthTeeth, mouthLine] + markLayers
    }

    init() {
        brows.addSublayer(leftBrow)
        brows.addSublayer(rightBrow)
        money.forEach(eyeMarks.addSublayer)
        for layer in [mouthFill, mouthTongue, mouthTeeth, mouthLine] { mouth.addSublayer(layer) }
        for layer in [blush, queasy, tears, gloom, sweat, vein] + steam + sparkles + stars { marks.addSublayer(layer) }
        for layer in [brows, eyeMarks, mouth, marks] + shapeLayers { layer.actions = Self.noActions }
        for layer in [leftBrow, rightBrow, mouthLine, tears, gloom, vein] {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
        }
    }

    func mount(eyeLevel: CALayer, around: CALayer) {
        eyeLevel.addSublayer(brows)
        eyeLevel.addSublayer(eyeMarks)
        around.addSublayer(marks)
        around.addSublayer(mouth)
    }

    func layout(box: CGRect, scale: CGFloat) {
        for layer in [brows, eyeMarks, marks] {
            layer.frame = box
            layer.contentsScale = scale
        }
        mouth.contentsScale = scale
        for layer in shapeLayers { layer.contentsScale = scale }
    }

    func setOpacity(_ opacity: Float) {
        for layer in [brows, eyeMarks, mouth, marks] { layer.opacity = opacity }
    }

    func stopAll() {
        for layer in [brows, eyeMarks, mouth, marks] + shapeLayers { layer.removeAllAnimations() }
        marksMove = false
    }

    // MARK: Drawing

    func draw(_ expression: NotchMascotExpression, _ metrics: NotchMascotFaceMetrics) {
        self.expression = expression
        drawBrows(expression.brows, metrics)
        drawMouth(expression.mouth, metrics)
        drawMarks(expression.marks, metrics)
    }

    /// The brows bend from where they are on screen to `brows`.
    func morphBrows(to brows: NotchMascotBrows, _ metrics: NotchMascotFaceMetrics) {
        for (layer, right) in [(leftBrow, false), (rightBrow, true)] {
            let bend = CABasicAnimation(keyPath: "path")
            bend.fromValue = layer.presentation()?.path ?? layer.path
            bend.toValue = browPath(brows, right: right, metrics)
            bend.duration = 0.22
            bend.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
            layer.add(bend, forKey: "morph")
        }
    }

    private func browPath(_ brows: NotchMascotBrows, right: Bool, _ m: NotchMascotFaceMetrics) -> CGPath {
        NotchMascotFaceShapes.brow(brows, right: right, length: max(2, m.eye.width * 1.5), raise: m.eye.height * 0.22)
    }

    private func glow(_ layer: CAShapeLayer, _ m: NotchMascotFaceMetrics) {
        layer.shadowOpacity = m.glows ? 0.9 : 0
        guard m.glows else { return }
        layer.shadowColor = m.ink
        layer.shadowRadius = max(0.6, m.line * 0.9)
        layer.shadowOffset = .zero
    }

    private func drawBrows(_ brows: NotchMascotBrows, _ m: NotchMascotFaceMetrics) {
        let lift = m.eye.height * 0.5 + m.line * 1.4
        for (layer, eye, right) in [(leftBrow, m.left, false), (rightBrow, m.right, true)] {
            layer.isHidden = brows == .none
            layer.position = CGPoint(x: eye.x, y: eye.y - lift)
            layer.path = browPath(brows, right: right, m)
            layer.strokeColor = m.ink
            layer.lineWidth = m.line * 1.05
            glow(layer, m)
        }
    }

    private func drawMouth(_ shape: NotchMascotMouth, _ m: NotchMascotFaceMetrics) {
        let parts = [mouthFill, mouthTongue, mouthTeeth, mouthLine]
        guard let spot = m.mouth, let drawing = NotchMascotFaceShapes.mouth(shape, width: m.mouthWidth) else {
            parts.forEach { $0.isHidden = true }
            return
        }
        let reach = m.mouthWidth * 1.2
        mouth.bounds = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
        mouth.position = spot
        for layer in parts + [tongueMask] {
            layer.bounds = mouth.bounds
            layer.position = .zero
        }
        mouthFill.path = drawing.inside
        mouthFill.isHidden = drawing.inside == nil
        mouthFill.fillColor = m.glows ? m.ink.copy(alpha: 0.3) : NotchMascotFaceShapes.color(0x4A1424)
        // The robot has no tongue; its open mouth only glows.
        mouthTongue.path = drawing.tongue
        mouthTongue.isHidden = drawing.tongue == nil || m.glows
        mouthTongue.fillColor = NotchMascotFaceShapes.color(0xFF6F91)
        tongueMask.path = drawing.inside
        mouthTongue.mask = drawing.inside == nil ? nil : tongueMask
        mouthTeeth.path = drawing.teeth
        mouthTeeth.isHidden = drawing.teeth == nil
        mouthTeeth.fillColor = m.glows ? m.ink.copy(alpha: 0.4) : NSColor.white.cgColor
        mouthLine.path = drawing.outline
        mouthLine.isHidden = false
        mouthLine.strokeColor = m.ink
        mouthLine.lineWidth = m.line * (drawing.inside == nil ? 1 : 0.8)
        glow(mouthLine, m)
    }

    // swiftlint:disable:next function_body_length
    private func drawMarks(_ shown: NotchMascotFaceMarks, _ m: NotchMascotFaceMetrics) {
        let unit = m.eye.width, tall = m.eye.height, head = m.head
        let sides: [(CGPoint, CGFloat)] = [(m.left, -1), (m.right, 1)]
        for layer in markLayers { layer.isHidden = true }

        if shown.contains(.blush) {
            let path = CGMutablePath()
            for (eye, side) in sides {
                let center = CGPoint(x: eye.x + side * unit * 0.75, y: eye.y + tall * 0.6)
                path.addEllipse(in: CGRect(x: center.x - unit * 0.8, y: center.y - unit * 0.42,
                                           width: unit * 1.6, height: unit * 0.84))
            }
            place(blush, at: .zero, path: path)
            blush.fillColor = NotchMascotFaceShapes.color(0xFF6F91, 0.55)
        }
        if shown.contains(.queasy) {
            let path = CGMutablePath()
            for (eye, _) in sides {
                let reach = CGSize(width: unit * 0.95, height: max(0.8, tall * 0.22))
                path.addEllipse(in: CGRect(x: eye.x - reach.width, y: eye.y + tall * 0.58 - reach.height,
                                           width: reach.width * 2, height: reach.height * 2))
            }
            place(queasy, at: .zero, path: path)
            queasy.fillColor = NotchMascotFaceShapes.color(0x8BC34A, 0.55)
        }
        if shown.contains(.tears) {
            // A stream from under each eye, down and a little out.
            let path = CGMutablePath()
            for (eye, side) in sides {
                let start = CGPoint(x: eye.x + side * unit * 0.15, y: eye.y + tall * 0.42)
                let length = max(tall, min(tall * 2.2, head.maxY - start.y - unit * 0.2))
                path.move(to: start)
                path.addQuadCurve(to: CGPoint(x: start.x + side * unit * 0.45, y: start.y + length),
                                  control: CGPoint(x: start.x + side * unit * 0.05, y: start.y + length * 0.6))
            }
            place(tears, at: .zero, path: path)
            tears.strokeColor = NotchMascotFaceShapes.color(0x7FD3FF, 0.92)
            tears.lineWidth = max(0.8, unit * 0.6)
            tears.lineDashPattern = [NSNumber(value: Double(unit * 0.9)), NSNumber(value: Double(unit * 0.5))]
        }
        if shown.contains(.gloom) {
            // Violet lines hanging down the top of its head, above the brows;
            // over a head with no room under its top, they hang above it.
            let top = head.minY + head.height * 0.04
            let limit = min(m.left.y, m.right.y) - tall * 0.5 - m.line * 3
            let roomy = limit - top > tall * 0.5
            let path = CGMutablePath()
            for index in 0..<5 {
                let x = head.minX + head.width * (0.24 + CGFloat(index) * 0.13)
                let length = head.height * (index.isMultiple(of: 2) ? 0.26 : 0.18)
                let from = roomy ? top : head.minY - tall * (index.isMultiple(of: 2) ? 1 : 0.8)
                let to = roomy ? min(limit, top + length) : head.minY - tall * 0.15
                path.move(to: CGPoint(x: x, y: from))
                path.addLine(to: CGPoint(x: x, y: to))
            }
            place(gloom, at: .zero, path: path)
            gloom.strokeColor = NotchMascotFaceShapes.color(0x7E57C2, 0.8)
            gloom.lineWidth = max(0.5, m.line * 0.7)
        }
        if shown.contains(.sweat) {
            place(sweat, at: CGPoint(x: head.minX + head.width * 0.2, y: head.minY + head.height * 0.3),
                  path: NotchMascotFaceShapes.drop(height: max(3, tall * 0.75)))
            sweat.fillColor = NotchMascotFaceShapes.color(0x7FD3FF)
            sweat.strokeColor = NotchMascotFaceShapes.color(0x2F8FD8, 0.7)
            sweat.lineWidth = m.line * 0.3
        }
        if shown.contains(.vein) {
            place(vein, at: CGPoint(x: head.maxX - head.width * 0.2, y: head.minY + head.height * 0.16),
                  path: NotchMascotFaceShapes.vein(radius: max(2, unit * 0.85)))
            vein.strokeColor = NotchMascotFaceShapes.color(0xE8323C)
            vein.lineWidth = max(0.6, m.line * 0.85)
        }
        if shown.contains(.steam) {
            for (index, puff) in steam.enumerated() {
                let radius = max(1.5, unit * 0.5) * [1, 1.2, 0.9][index]
                let x = head.midX + head.width * [-0.3, 0.02, 0.3][index]
                place(puff, at: CGPoint(x: x, y: head.minY - tall * 0.3),
                      path: CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                                   transform: nil))
                puff.fillColor = NSColor.white.withAlphaComponent(0.9).cgColor
            }
        }
        if shown.contains(.sparkle) {
            let spots = [CGPoint(x: head.minX - unit * 0.1, y: head.minY + head.height * 0.32),
                         CGPoint(x: head.maxX + unit * 0.2, y: head.minY + head.height * 0.08),
                         CGPoint(x: head.maxX - unit * 0.05, y: head.minY + head.height * 0.62)]
            for (index, twinkle) in sparkles.enumerated() {
                place(twinkle, at: spots[index],
                      path: NotchMascotFaceShapes.sparkle(radius: max(2, unit * 0.9) * [1, 0.75, 0.6][index]))
                twinkle.fillColor = NotchMascotFaceShapes.gold
            }
        }
        if shown.contains(.stars) {
            let center = CGPoint(x: head.midX, y: head.minY + tall * 0.15)
            let radii = CGSize(width: head.width * 0.42, height: max(unit * 0.7, head.height * 0.09))
            orbit = CGPath(ellipseIn: CGRect(x: center.x - radii.width, y: center.y - radii.height,
                                             width: radii.width * 2, height: radii.height * 2), transform: nil)
            for (index, star) in stars.enumerated() {
                let angle = CGFloat(index) * 2 * .pi / 3
                place(star, at: CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle)),
                      path: NotchMascotFaceShapes.star(radius: max(1.6, unit * 0.6)))
                star.fillColor = NotchMascotFaceShapes.gold
                star.strokeColor = NotchMascotFaceShapes.color(0xC79100)
                star.lineWidth = m.line * 0.3
            }
        }
        if shown.contains(.money) {
            let glyph = NotchMascotPatShapes.text("$", height: max(4, tall * 1.15))
            let box = glyph.boundingBoxOfPath
            var middle = CGAffineTransform(translationX: -box.midX, y: -box.midY)
            let centered = glyph.copy(using: &middle) ?? glyph
            for (index, sign) in money.enumerated() {
                place(sign, at: index == 0 ? m.left : m.right, path: centered)
                sign.fillColor = NotchMascotFaceShapes.color(0xFFC83D)
                sign.strokeColor = NotchMascotFaceShapes.color(0x7A4F00)
                sign.lineWidth = m.line * 0.3
            }
        }
    }

    /// A mark's path drawn about `point`, where it also turns and grows.
    private func place(_ layer: CAShapeLayer, at point: CGPoint, path: CGPath) {
        layer.bounds = .zero
        layer.position = point
        layer.path = path
        layer.isHidden = false
    }

    // MARK: Motion

    /// Sets its marks moving from `begin` on the media clock, for `length`
    /// seconds, or for as long as they show when nil.
    // swiftlint:disable:next function_body_length
    func animateMarks(from begin: CFTimeInterval, for length: TimeInterval?, _ m: NotchMascotFaceMetrics) {
        let shown = expression.marks
        guard !shown.isEmpty else { return }
        marksMove = length == nil
        let tall = m.eye.height
        func run(_ animation: CAAnimation, on layer: CALayer, offset: CFTimeInterval = 0) {
            animation.beginTime = begin
            animation.timeOffset = offset
            if let length { animation.repeatDuration = length } else { animation.repeatCount = .infinity }
            layer.add(animation, forKey: "mark")
        }
        func keyframes(_ keyPath: String, _ values: [Any], _ times: [NSNumber]? = nil,
                       duration: TimeInterval, additive: Bool = false) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.isAdditive = additive
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return animation
        }
        func group(_ animations: [CAAnimation], duration: TimeInterval) -> CAAnimationGroup {
            let group = CAAnimationGroup()
            animations.forEach { $0.duration = duration }
            group.animations = animations
            group.duration = duration
            return group
        }
        if shown.contains(.blush) { run(keyframes("opacity", [1, 0.65, 1], duration: 1.8), on: blush) }
        if shown.contains(.queasy) { run(keyframes("opacity", [1, 0.5, 1], duration: 1.4), on: queasy) }
        if shown.contains(.tears) {
            // The dashes run down the streams.
            let period = (tears.lineDashPattern ?? []).reduce(0) { $0 + $1.doubleValue }
            let flow = CABasicAnimation(keyPath: "lineDashPhase")
            flow.fromValue = 0
            flow.toValue = -period
            flow.duration = 0.3
            run(flow, on: tears)
        }
        if shown.contains(.gloom) {
            run(group([keyframes("opacity", [1, 0.45, 1], duration: 2),
                       keyframes("transform.translation.y", [0, tall * 0.12, 0], duration: 2, additive: true)],
                      duration: 2), on: gloom)
        }
        if shown.contains(.sweat) {
            let fall = keyframes("transform.translation.y", [0, 0, tall * 0.9], [0, 0.25, 1], duration: 1.3, additive: true)
            fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
            run(group([fall, keyframes("opacity", [0, 1, 1, 0], [0, 0.15, 0.7, 1], duration: 1.3)], duration: 1.3),
                on: sweat)
        }
        if shown.contains(.vein) {
            run(keyframes("transform.scale", [1, 1.3, 0.95, 1.2, 1], [0, 0.12, 0.26, 0.4, 1], duration: 0.85), on: vein)
        }
        if shown.contains(.steam) {
            for (index, puff) in steam.enumerated() {
                let rise = keyframes("transform.translation.y", [tall * 0.3, -tall * 1.1], duration: 1.2, additive: true)
                rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
                run(group([rise, keyframes("transform.scale", [0.5, 1.35], duration: 1.2),
                           keyframes("opacity", [0, 0.95, 0], [0, 0.25, 1], duration: 1.2)], duration: 1.2),
                    on: puff, offset: Double(index) * 0.4)
            }
        }
        if shown.contains(.sparkle) {
            for (index, twinkle) in sparkles.enumerated() {
                run(group([keyframes("transform.scale", [0.15, 1.1, 0.15], duration: 1),
                           keyframes("transform.rotation.z", [0, 0.9], duration: 1, additive: true)], duration: 1),
                    on: twinkle, offset: Double(index) * 0.33)
            }
        }
        if shown.contains(.stars), let orbit {
            for (index, star) in stars.enumerated() {
                let circle = CAKeyframeAnimation(keyPath: "position")
                circle.path = orbit
                circle.calculationMode = .paced
                let spin = keyframes("transform.rotation.z", [0, 2 * CGFloat.pi], duration: 1.4, additive: true)
                spin.timingFunction = CAMediaTimingFunction(name: .linear)
                run(group([circle, spin], duration: 1.4), on: star, offset: Double(index) * 1.4 / 3)
            }
        }
        if shown.contains(.money) {
            for sign in money { run(keyframes("transform.scale", [1, 1.25, 1], duration: 0.5), on: sign) }
        }
    }

    func stillMarks() {
        for layer in markLayers { layer.removeAnimation(forKey: "mark") }
        marksMove = false
    }
}

/// The outlines of the features, about their own middle, y growing downward.
enum NotchMascotFaceShapes {
    static let gold = color(0xFFD54A)

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// A brow over the left eye, or mirrored over the right one, `length`
    /// long; `raise` is how far a raised brow goes up. Every brow is the same
    /// one curve, so any bends into any other.
    static func brow(_ brows: NotchMascotBrows, right: Bool, length: CGFloat, raise: CGFloat) -> CGPath {
        let half = length / 2
        // The outer end, the bend and the end toward the nose, for the left
        // brow, whose nose side is toward positive x.
        var outer = CGPoint(x: -half, y: 0), bend = CGPoint(x: 0, y: -length * 0.16), inner = CGPoint(x: half, y: 0)
        switch brows {
        case .none:
            break
        case .angry:
            outer.y = -length * 0.22
            bend.y = -length * 0.1
            inner.y = length * 0.24
        case .worried:
            outer.y = length * 0.16
            bend.y = -length * 0.08
            inner.y = -length * 0.24
        case .raised:
            outer.y = -raise * 0.7
            bend.y = -raise - length * 0.3
            inner.y = -raise * 0.7
        case .skeptical:
            // The left one arches up high; the right one sits low and flat.
            if right {
                outer.y = raise * 0.25
                bend.y = raise * 0.2
                inner.y = raise * 0.45
            } else {
                outer.y = -raise
                bend.y = -raise * 1.4 - length * 0.3
                inner.y = -raise * 0.5
            }
        }
        func placed(_ point: CGPoint) -> CGPoint { CGPoint(x: right ? -point.x : point.x, y: point.y) }
        let path = CGMutablePath()
        path.move(to: placed(outer))
        path.addQuadCurve(to: placed(inner), control: placed(bend))
        return path
    }

    /// A mouth's parts: the dark inside of an open one, its teeth, its
    /// tongue, and the line drawn round it all.
    struct Mouth {
        var inside: CGPath?
        var teeth: CGPath?
        var tongue: CGPath?
        var outline: CGPath
    }

    /// `mouth` `width` points wide about its middle; nil for none.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func mouth(_ mouth: NotchMascotMouth, width w: CGFloat) -> Mouth? {
        let h = w * 0.5
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: (x - rx) * w, y: (y - ry) * h, width: rx * 2 * w, height: ry * 2 * h), transform: nil)
        }
        let line = CGMutablePath()
        switch mouth {
        case .none:
            return nil
        case .smile:
            line.move(to: at(-0.5, -0.1))
            line.addQuadCurve(to: at(0.5, -0.1), control: at(0, 0.8))
        case .frown:
            line.move(to: at(-0.42, 0.32))
            line.addQuadCurve(to: at(0.42, 0.32), control: at(0, -0.5))
        case .smirk:
            line.move(to: at(-0.38, 0.1))
            line.addQuadCurve(to: at(0.44, -0.26), control: at(0.12, 0.55))
            // The dimple at its raised corner.
            line.move(to: at(0.34, -0.44))
            line.addQuadCurve(to: at(0.5, -0.12), control: at(0.52, -0.34))
        case .wavy:
            line.move(to: at(-0.5, 0))
            for step in 0..<4 {
                let from = -0.5 + CGFloat(step) * 0.25
                line.addQuadCurve(to: at(from + 0.25, 0), control: at(from + 0.125, step.isMultiple(of: 2) ? -0.36 : 0.36))
            }
        case .pout:
            // Puckered lips, two little bumps.
            line.move(to: at(-0.2, 0.15))
            line.addQuadCurve(to: at(0, 0.12), control: at(-0.1, -0.32))
            line.addQuadCurve(to: at(0.2, 0.15), control: at(0.1, -0.32))
        case .gasp:
            let round = oval(0, 0.1, 0.19, 0.4)
            return Mouth(inside: round, outline: round)
        case .grin:
            let open = CGMutablePath()
            open.move(to: at(-0.5, -0.3))
            open.addLine(to: at(0.5, -0.3))
            open.addCurve(to: at(-0.5, -0.3), control1: at(0.46, 1.15), control2: at(-0.46, 1.15))
            open.closeSubpath()
            return Mouth(inside: open, tongue: oval(0, 0.62, 0.24, 0.3), outline: open)
        case .teeth:
            let rect = CGRect(x: -0.42 * w, y: -0.3 * h, width: 0.84 * w, height: 0.6 * h)
            let teeth = CGPath(roundedRect: rect, cornerWidth: h * 0.22, cornerHeight: h * 0.22, transform: nil)
            line.addPath(teeth)
            line.move(to: CGPoint(x: rect.minX, y: rect.midY))
            line.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            for x in [-0.21, 0, 0.21] as [CGFloat] {
                line.move(to: at(x, -0.3))
                line.addLine(to: at(x, 0.3))
            }
            return Mouth(teeth: teeth, outline: line)
        case .tongue:
            line.move(to: at(-0.42, -0.12))
            line.addQuadCurve(to: at(0.42, -0.12), control: at(0, 0.65))
            let tongue = CGMutablePath()
            tongue.move(to: at(0, 0.2))
            tongue.addCurve(to: at(0.3, 0.1), control1: at(0, 1.0), control2: at(0.32, 0.95))
            tongue.closeSubpath()
            line.addPath(tongue)
            return Mouth(tongue: tongue, outline: line)
        case .scream:
            let open = oval(0, 0.3, 0.3, 0.75)
            return Mouth(inside: open, tongue: oval(0, 0.95, 0.2, 0.32), outline: open)
        }
        return Mouth(outline: line)
    }

    /// A drop of water `height` tall, its point up.
    static func drop(height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -height * 0.5))
        path.addCurve(to: CGPoint(x: 0, y: height * 0.5), control1: CGPoint(x: height * 0.42, y: height * 0.05),
                      control2: CGPoint(x: height * 0.42, y: height * 0.5))
        path.addCurve(to: CGPoint(x: 0, y: -height * 0.5), control1: CGPoint(x: -height * 0.42, y: height * 0.5),
                      control2: CGPoint(x: -height * 0.42, y: height * 0.05))
        path.closeSubpath()
        return path
    }

    /// The cross-shaped vein of anger: four curves pinched toward the middle.
    static func vein(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func at(_ angle: CGFloat, _ reach: CGFloat) -> CGPoint { CGPoint(x: cos(angle) * reach, y: sin(angle) * reach) }
        for quarter in 0..<4 {
            let angle = CGFloat(quarter) * .pi / 2 + .pi / 4
            path.move(to: at(angle - 0.55, radius))
            path.addQuadCurve(to: at(angle + 0.55, radius), control: at(angle, radius * 0.2))
        }
        return path
    }

    /// A four-pointed twinkle with curved sides.
    static func sparkle(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let pinch = radius * 0.16
        path.move(to: CGPoint(x: 0, y: -radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: pinch, y: -pinch))
        path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: pinch, y: pinch))
        path.addQuadCurve(to: CGPoint(x: -radius, y: 0), control: CGPoint(x: -pinch, y: pinch))
        path.addQuadCurve(to: CGPoint(x: 0, y: -radius), control: CGPoint(x: -pinch, y: -pinch))
        path.closeSubpath()
        return path
    }

    /// A five-pointed star standing on two points.
    static func star(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let reach = index.isMultiple(of: 2) ? radius : radius * 0.45
            let point = CGPoint(x: reach * cos(angle), y: reach * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

extension NotchMascotReaction {
    /// The face it pulls as it reacts, mouth, brows and marks and all.
    var face: NotchMascotExpression {
        switch self {
        case .celebrate:
            return NotchMascotExpression(left: .happy, right: .happy, gaze: CGPoint(x: 0, y: -0.02),
                                         mouth: .grin, brows: .raised, marks: .sparkle)
        case .love: return NotchMascotMood.love.expression
        case .surprised: return NotchMascotMood.surprised.expression
        case .flash: return NotchMascotExpression(left: .wide, right: .wide, mouth: .gasp, brows: .raised)
        case .confused: return NotchMascotMood.confused.expression
        // A yawn, as wide as its mouth goes.
        case .wakeUp, .yawn:
            return NotchMascotExpression(left: .sleepy, right: .sleepy, gaze: CGPoint(x: 0, y: 0.03), tilt: 0.05,
                                         mouth: .scream)
        case .perk: return NotchMascotExpression(left: .wide, right: .wide, mouth: .smile, brows: .raised)
        case .bounce: return NotchMascotExpression(left: .wide, right: .wide, mouth: .grin, brows: .raised)
        case .hush: return NotchMascotExpression(left: .closed, right: .closed, mouth: .pout)
        case .ready: return NotchMascotMood.determined.expression
        case .groove: return NotchMascotExpression(left: .happy, right: .happy, mouth: .grin)
        case .sweat:
            return NotchMascotExpression(left: .determined, right: .determined, mouth: .teeth, brows: .worried, marks: .sweat)
        case .panic: return NotchMascotMood.terrified.expression
        case .relax: return NotchMascotMood.happy.expression
        case .sip: return NotchMascotExpression(left: .happy, right: .happy, mouth: .pout)
        case .peek:
            return NotchMascotExpression(left: .wide, right: .wide, gaze: CGPoint(x: 0.04, y: -0.03), mouth: .smile,
                                         brows: .raised)
        case .wave: return NotchMascotExpression(left: .happy, right: .happy, mouth: .grin)
        case .lookAround: return NotchMascotExpression(left: .open, right: .open, mouth: .pout, brows: .skeptical)
        }
    }
}
