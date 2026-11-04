// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// The five animals drawn like the hologram, the android and the dancers:
/// the phoenix, the mouse, the axolotl, the swan and the cat. Each is a
/// chibi with a big head over a small body, its fur or feathers in the
/// body's own colours, and every other part of it, from ears and wings to
/// paws and tail, a layer of its own the figure can move. Each part is
/// described here as a path for every pose, built with the same commands
/// whatever the pose so one morphs into the next, and the paint it wears;
/// `NotchMascotCritterParts` stacks and moves them.
extension NotchMascotCreatures {
    static let critters: Set<NotchMascotStyle> = [.phoenix, .mouse, .axolotl, .swan, .cat]

    /// How an animal holds its limbs, wings, ears and tail: in its own way
    /// at rest, curled up or tucked in asleep, paws or wings up for a cheer,
    /// a wave one way and the other, a bow, a start that flicks the ears or
    /// flares the gills, wings or paws spread wide, and two alternating
    /// steps for walking.
    enum CritterPose: CaseIterable {
        case rest, asleep, cheer, wave, waveOut, bow, twitch, spread, step, stepOther
    }

    /// The parts of `style` drawn at `size` points, back to front within
    /// each level, in `colors`; `hat` says something sits on its head, so
    /// what would poke through it is left out.
    static func critterParts(_ style: NotchMascotStyle, colors: NotchMascotCritterColors, hat: Bool = false,
                             size: CGFloat) -> [NotchMascotCritterPart] {
        switch style {
        case .cat: return catParts(colors: colors, hat: hat, size: size)
        case .phoenix: return phoenixParts(colors: colors, hat: hat, size: size)
        case .mouse: return mouseParts(colors: colors, size: size)
        default: return []
        }
    }

    /// The figure's own shape that the body's fill paints, for the five.
    static func critterBody(_ style: NotchMascotStyle, size: CGFloat) -> CGPath {
        switch style {
        case .cat: return catBody(size: size)
        case .phoenix: return phoenixBody(size: size)
        case .mouse: return mouseBody(size: size)
        default: return CGMutablePath()
        }
    }

    /// The box the animal fills at rest, body and parts together, effects
    /// left out, in shares of its size.
    static func critterBounds(_ style: NotchMascotStyle) -> CGRect {
        critterBoundsCache.withLock { cache in
            if let known = cache[style] { return known }
            let colors = NotchMascotCritterColors(light: NotchMascotPalette.pearl.light, shade: NotchMascotPalette.pearl.shade)
            let box = critterParts(style, colors: colors, size: 1).filter { !$0.effect }
                .reduce(critterBody(style, size: 1).boundingBoxOfPath) { $0.union($1.rest().boundingBoxOfPath) }
            cache[style] = box
            return box
        }
    }
    private static let critterBoundsCache = NotchMascotLockedBox<[NotchMascotStyle: CGRect]>([:])
    /// Where the animal holds things and stands, read off its own parts at
    /// rest, so what it wears follows the drawing.
    static func critterAnatomy(_ style: NotchMascotStyle) -> NotchMascotAnatomy? {
        switch style {
        case .cat: return catAnatomy
        case .phoenix: return phoenixAnatomy
        case .mouse: return mouseAnatomy
        default: return nil
        }
    }

    // MARK: Drawing

    /// A path drawn in shares of the figure's square and laid out in points,
    /// optionally turned about a pivot first, with an oval, a limb, a flame
    /// and a feather that always take the same commands, so two poses of
    /// one part morph.
    final class CritterPen {
        let path = CGMutablePath()
        let size: CGFloat
        /// Applied to every point, in shares, before scaling to points.
        var turn = CGAffineTransform.identity

        init(size: CGFloat) { self.size = size }

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let turned = CGPoint(x: x, y: y).applying(turn)
            return CGPoint(x: turned.x * size, y: turned.y * size)
        }
        func point(_ p: CGPoint) -> CGPoint { point(p.x, p.y) }

        /// Turns what is drawn next by `degrees`, clockwise on screen, about
        /// `pivot`; nil goes back to drawing straight.
        func turning(_ degrees: CGFloat, about pivot: CGPoint) {
            let angle = degrees * .pi / 180
            turn = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle)
                .translatedBy(x: -pivot.x, y: -pivot.y)
        }
        func straight() { turn = .identity }

        func move(_ x: CGFloat, _ y: CGFloat) { path.move(to: point(x, y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: point(x, y)) }
        func quad(_ x: CGFloat, _ y: CGFloat, _ cx: CGFloat, _ cy: CGFloat) {
            path.addQuadCurve(to: point(x, y), control: point(cx, cy))
        }
        func curve(_ x: CGFloat, _ y: CGFloat, _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
            path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
        }
        func close() { path.closeSubpath() }

        /// An oval round `center`, tilted `degrees`, in four curves, even
        /// when it shrinks to nothing.
        func oval(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, tilt degrees: CGFloat = 0) {
            let angle = degrees * .pi / 180, k: CGFloat = 0.5523
            let (c, s) = (cos(angle), sin(angle))
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                point(center.x + x * c - y * s, center.y + x * s + y * c)
            }
            path.move(to: at(rx, 0))
            path.addCurve(to: at(0, ry), control1: at(rx, ry * k), control2: at(rx * k, ry))
            path.addCurve(to: at(-rx, 0), control1: at(-rx * k, ry), control2: at(-rx, ry * k))
            path.addCurve(to: at(0, -ry), control1: at(-rx, -ry * k), control2: at(-rx * k, -ry))
            path.addCurve(to: at(rx, 0), control1: at(rx * k, -ry), control2: at(rx, -ry * k))
            path.closeSubpath()
        }

        /// A tapered limb from one joint to the next, rounded at both ends.
        func limb(_ from: CGPoint, _ to: CGPoint, _ widths: (CGFloat, CGFloat)) {
            let (ux, uy) = critterUnit(from, to)
            let (a, b) = (widths.0 / 2, widths.1 / 2)
            path.move(to: point(from.x - uy * a, from.y + ux * a))
            path.addLine(to: point(to.x - uy * b, to.y + ux * b))
            path.addQuadCurve(to: point(to.x + uy * b, to.y - ux * b), control: point(to.x + ux * b * 1.4, to.y + uy * b * 1.4))
            path.addLine(to: point(from.x + uy * a, from.y - ux * a))
            path.addQuadCurve(to: point(from.x - uy * a, from.y + ux * a),
                              control: point(from.x - ux * a * 1.4, from.y - uy * a * 1.4))
            path.closeSubpath()
        }

        /// A flame from a round `base` of `width` out to a pointed `tip`,
        /// its tip bent `curl` of its length to the side.
        func flame(_ base: CGPoint, _ tip: CGPoint, width: CGFloat, curl: CGFloat) {
            let (ux, uy) = critterUnit(base, tip)
            let (nx, ny) = (-uy, ux)
            let length = critterDistance(base, tip)
            let w = width / 2
            let bend = CGPoint(x: (base.x + tip.x) / 2 + nx * curl * length, y: (base.y + tip.y) / 2 + ny * curl * length)
            path.move(to: point(tip))
            path.addCurve(to: point(base.x + nx * w, base.y + ny * w),
                          control1: point(bend.x + nx * w * 0.5, bend.y + ny * w * 0.5),
                          control2: point(base.x + nx * w + ux * length * 0.35, base.y + ny * w + uy * length * 0.35))
            path.addCurve(to: point(base.x - nx * w, base.y - ny * w),
                          control1: point(base.x + nx * w - ux * w * 1.35, base.y + ny * w - uy * w * 1.35),
                          control2: point(base.x - nx * w - ux * w * 1.35, base.y - ny * w - uy * w * 1.35))
            path.addCurve(to: point(tip),
                          control1: point(base.x - nx * w + ux * length * 0.35, base.y - ny * w + uy * length * 0.35),
                          control2: point(bend.x - nx * w * 0.5, bend.y - ny * w * 0.5))
            path.closeSubpath()
        }

        /// A feather or a leaf from `root` to `tip`, widest a third of the
        /// way along and bent `curl` of its length to the side.
        func feather(_ root: CGPoint, _ tip: CGPoint, width: CGFloat, curl: CGFloat = 0) {
            let (ux, uy) = critterUnit(root, tip)
            let (nx, ny) = (-uy, ux)
            let length = critterDistance(root, tip)
            let w = width / 2
            let side = CGPoint(x: root.x + ux * length * 0.38 + nx * curl * length, y: root.y + uy * length * 0.38 + ny * curl * length)
            path.move(to: point(root))
            path.addQuadCurve(to: point(tip), control: point(side.x + nx * w * 2, side.y + ny * w * 2))
            path.addQuadCurve(to: point(root), control: point(side.x - nx * w * 2, side.y - ny * w * 2))
            path.closeSubpath()
        }
        /// A smooth tube along `spine`, `widths.0` wide at its first point
        /// and `widths.1` at its last, rounded at both ends: a tail.
        func tube(_ spine: [CGPoint], widths: (CGFloat, CGFloat)) {
            let count = spine.count
            guard count > 2 else { return }
            var left: [CGPoint] = [], right: [CGPoint] = []
            for index in 0..<count {
                let (ux, uy) = critterUnit(spine[max(0, index - 1)], spine[min(count - 1, index + 1)])
                let share = CGFloat(index) / CGFloat(count - 1)
                let half = (widths.0 + (widths.1 - widths.0) * share) / 2
                left.append(CGPoint(x: spine[index].x - uy * half, y: spine[index].y + ux * half))
                right.append(CGPoint(x: spine[index].x + uy * half, y: spine[index].y - ux * half))
            }
            func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            func side(_ points: [CGPoint]) {
                path.addLine(to: point(middle(points[0], points[1])))
                for index in 1..<(points.count - 1) {
                    path.addQuadCurve(to: point(middle(points[index], points[index + 1])), control: point(points[index]))
                }
                path.addLine(to: point(points[points.count - 1]))
            }
            let (ex, ey) = critterUnit(spine[count - 2], spine[count - 1])
            let (sx, sy) = critterUnit(spine[1], spine[0])
            let endHalf = widths.1 / 2, startHalf = widths.0 / 2
            path.move(to: point(left[0]))
            side(left)
            path.addQuadCurve(to: point(right[count - 1]),
                              control: point(spine[count - 1].x + ex * endHalf * 2, spine[count - 1].y + ey * endHalf * 2))
            side(right.reversed())
            path.addQuadCurve(to: point(left[0]),
                              control: point(spine[0].x + sx * startHalf * 2, spine[0].y + sy * startHalf * 2))
            path.closeSubpath()
        }
    }
    /// `count` points along the curve from `a` to `d` drawn toward `b` and `c`.
    static func critterSpine(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, count: Int = 12) -> [CGPoint] {
        (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1), u = 1 - t
            let (wa, wb, wc, wd) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
            return CGPoint(x: a.x * wa + b.x * wb + c.x * wc + d.x * wd, y: a.y * wa + b.y * wb + c.y * wc + d.y * wd)
        }
    }

    /// The unit vector from one point toward another.
    static func critterUnit(_ from: CGPoint, _ to: CGPoint) -> (CGFloat, CGFloat) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return (dx / length, dy / length)
    }

    static func critterDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }

    /// The point `degrees` round from straight down, `length` away from
    /// `from`: nought hangs down, ninety points to the right of the screen,
    /// a hundred and eighty straight up.
    static func critterReach(_ from: CGPoint, _ degrees: CGFloat, _ length: CGFloat) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: from.x + sin(angle) * length, y: from.y + cos(angle) * length)
    }

    /// Mirrored across the figure's middle.
    static func critterMirror(_ point: CGPoint) -> CGPoint { CGPoint(x: 1 - point.x, y: point.y) }
}

/// One part of an animal: where it sits among the layers, what it is
/// painted with, and its path in every pose. `phase`, from 0 to 1 and round
/// again, runs its idle motion, a sway or a flicker or embers rising, for
/// the parts that have one; at 0 it is still.
struct NotchMascotCritterPart {
    enum Level {
        /// Behind the body: ears, tails, far wings.
        case back
        /// Over the body, under the eyes: bellies, paws, noses, whiskers.
        case middle
        /// Over everything: embers and splashes.
        case front
    }

    enum Paint: Equatable {
        /// The body's own colours, as its fill paints them, mixed toward
        /// white by a positive `tone` or toward black by a negative one.
        case fur(tone: CGFloat)
        case color(NotchMascotColor)
        /// From one colour to the next between two points in shares of the
        /// figure's square.
        case gradient([NotchMascotColor], from: CGPoint, to: CGPoint)
        /// A line `width` shares of the figure's size wide, with round caps.
        case line(NotchMascotColor, width: CGFloat)
        /// A soft light fading out from `center` to `radius` away, in shares.
        case radial(NotchMascotColor, center: CGPoint, radius: CGSize)
    }

    var name: String
    var level: Level
    var paint: Paint
    /// A soft light round it, as flames have.
    var glow: NotchMascotColor? = nil
    /// How bright it stays asleep, as flames that sink to embers.
    var asleep: CGFloat = 1
    /// How long one round of its idle motion takes, and in how many steps;
    /// nil keeps it still.
    var idle: (period: TimeInterval, steps: Int)? = nil
    /// Its idle motion goes on asleep too, slowly, as embers do.
    var idlesAsleep = false
    /// A light or sparks about it rather than the animal itself, left out
    /// of its outline.
    var effect = false
    var path: (NotchMascotCreatures.CritterPose, CGFloat) -> CGPath

    /// Its path at rest and still.
    func rest() -> CGPath { path(.rest, 0) }
}

/// The colours the animals are worked out from: the body's light and shade,
/// as its fill paints it, and what they say: a hue, how grey and how dark
/// it is. Each animal mixes its own accents from these, so they belong to
/// every palette and any hand-picked colour.
struct NotchMascotCritterColors: Equatable {
    var light: NotchMascotColor
    var shade: NotchMascotColor
    var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat
    /// Too grey to have a hue of its own.
    var grey: Bool
    /// Dark enough to want light details, as a black swan has.
    var dark: Bool

    init(light: NotchMascotColor, shade: NotchMascotColor) {
        self.light = light
        self.shade = shade
        (hue, saturation, brightness) = shade.hsb
        grey = saturation < 0.12
        dark = light.hsb.2 < 0.45
    }

    init(_ look: NotchMascotLook) {
        if let fusion = look.fusion {
            self.init(light: fusion.primary.brightened(0.24), shade: fusion.primary.darkened(0.18))
        } else {
            let palette = look.bodyPalette
            self.init(light: palette.light, shade: palette.shade)
        }
    }

    static func rgb(_ hex: UInt32) -> NotchMascotColor {
        NotchMascotColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                         blue: CGFloat(hex & 0xFF) / 255)
    }

    /// The body's colour `share` of the way from its light to its shade.
    func fur(_ share: CGFloat) -> NotchMascotColor {
        NotchMascotColor(red: light.red + (shade.red - light.red) * share,
                         green: light.green + (shade.green - light.green) * share,
                         blue: light.blue + (shade.blue - light.blue) * share)
    }

    /// `color` mixed `share` of the way toward `other`.
    static func mix(_ color: NotchMascotColor, _ other: NotchMascotColor, _ share: CGFloat) -> NotchMascotColor {
        NotchMascotColor(red: color.red + (other.red - color.red) * share,
                         green: color.green + (other.green - color.green) * share,
                         blue: color.blue + (other.blue - color.blue) * share,
                         alpha: color.alpha + (other.alpha - color.alpha) * share)
    }
}

/// A value behind a lock, for what is worked out once and read from anywhere.
final class NotchMascotLockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
