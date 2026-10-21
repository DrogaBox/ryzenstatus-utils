// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore

/// What the companion wears, drawn with shape layers like the rest of it.
/// Hats and bows ride on the head and hop, squash and tilt with the body;
/// glasses sit on the face and follow the eyes. Shapes are bold and few,
/// since the companion is about twenty points tall in the island.
final class NotchMascotWearables {
    /// On the head, in front of the body.
    let head = CALayer()
    /// On the face, moving with the eyes.
    let face = CALayer()

    private(set) var accessory = NotchMascotAccessory.none

    init() {
        for layer in [head, face] { layer.actions = Self.noActions }
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "sublayers": NSNull(), "hidden": NSNull(), "frame": NSNull(),
    ]

    /// Whether it covers the top of the head, where the robot's antenna is.
    static func coversHead(_ accessory: NotchMascotAccessory) -> Bool {
        switch accessory {
        case .topHat, .beanie, .crown, .witchHat, .santaHat, .partyHat, .headphones,
             .cap, .cowboyHat, .chefHat, .halo, .knightHelm, .vikingHelm,
             .trafficCone, .tinfoilHat, .unicornHorn: return true
        default: return false
        }
    }

    /// Dresses it for `body`, the outline its fill is cut from, and the eyes
    /// of `face`, at `size` points.
    func configure(accessory: NotchMascotAccessory, body: CGPath?, face eyes: NotchMascotFaceLayout,
                   size: CGFloat, scale: CGFloat) {
        self.accessory = accessory
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        head.frame = box
        face.frame = box
        head.sublayers = nil
        face.sublayers = nil
        guard accessory != .none, size > 0 else { return }
        let outline = body?.boundingBoxOfPath ?? box.insetBy(dx: size * 0.12, dy: size * 0.12)
        let frame = NotchMascotWearableFrame(outline: outline, size: size,
                                             leftEye: CGPoint(x: eyes.leftEye.x * size, y: eyes.leftEye.y * size),
                                             rightEye: CGPoint(x: eyes.rightEye.x * size, y: eyes.rightEye.y * size))
        let parts = NotchMascotWearableShapes.parts(for: accessory, in: frame)
        let target = accessory.placement == .eyes ? face : head
        for part in parts {
            let layer = CAShapeLayer()
            layer.actions = Self.noActions
            layer.frame = box
            layer.contentsScale = scale
            layer.path = part.path
            layer.fillColor = part.fill
            layer.strokeColor = part.stroke
            layer.lineWidth = part.lineWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            target.addSublayer(layer)
        }
    }
}

/// Where a wearable goes: the head's outline and the eyes, in points from
/// the top left corner, y growing downward.
struct NotchMascotWearableFrame: Equatable {
    var outline: CGRect
    var size: CGFloat
    var leftEye: CGPoint
    var rightEye: CGPoint

    var center: CGFloat { outline.midX }
    var top: CGFloat { outline.minY }
    var width: CGFloat { outline.width }
}

struct NotchMascotWearablePart {
    var path: CGPath
    var fill: CGColor?
    var stroke: CGColor? = nil
    var lineWidth: CGFloat = 0
}

/// The outlines of every wearable. Pure geometry, so it is tested.
enum NotchMascotWearableShapes {
    static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func parts(for accessory: NotchMascotAccessory, in f: NotchMascotWearableFrame) -> [NotchMascotWearablePart] {
        let w = f.width, cx = f.center, top = f.top
        let line = max(0.8, f.size * 0.045)
        switch accessory {
        case .none:
            return []

        case .bow:
            let knot = CGPoint(x: cx + w * 0.24, y: top + w * 0.06)
            let s = w * 0.2
            let wings = CGMutablePath()
            wings.move(to: knot)
            wings.addLine(to: CGPoint(x: knot.x - s, y: knot.y - s * 0.55))
            wings.addLine(to: CGPoint(x: knot.x - s, y: knot.y + s * 0.55))
            wings.closeSubpath()
            wings.move(to: knot)
            wings.addLine(to: CGPoint(x: knot.x + s, y: knot.y - s * 0.55))
            wings.addLine(to: CGPoint(x: knot.x + s, y: knot.y + s * 0.55))
            wings.closeSubpath()
            return [NotchMascotWearablePart(path: wings, fill: rgb(0xFF5E8A)),
                    NotchMascotWearablePart(path: circle(knot, s * 0.32), fill: rgb(0xD93A68))]

        case .flower:
            let heart = CGPoint(x: cx - w * 0.26, y: top + w * 0.07)
            let r = w * 0.075
            let petals = CGMutablePath()
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                petals.addPath(circle(CGPoint(x: heart.x + CGFloat(cos(a)) * r * 1.3,
                                              y: heart.y + CGFloat(sin(a)) * r * 1.3), r))
            }
            return [NotchMascotWearablePart(path: petals, fill: rgb(0xFF8FB1)),
                    NotchMascotWearablePart(path: circle(heart, r * 0.85), fill: rgb(0xFFD23F))]

        case .topHat:
            let brim = CGRect(x: cx - w * 0.36, y: top - w * 0.01, width: w * 0.72, height: w * 0.09)
            let crown = CGRect(x: cx - w * 0.23, y: brim.minY - w * 0.38, width: w * 0.46, height: w * 0.4)
            let band = CGRect(x: crown.minX, y: brim.minY - w * 0.1, width: crown.width, height: w * 0.08)
            return [NotchMascotWearablePart(path: rounded(crown, w * 0.03), fill: rgb(0x2B2B33)),
                    NotchMascotWearablePart(path: rounded(brim, w * 0.04), fill: rgb(0x2B2B33)),
                    NotchMascotWearablePart(path: CGPath(rect: band, transform: nil), fill: rgb(0xE5384F))]

        case .beanie:
            let dome = CGMutablePath()
            let base = top + w * 0.16
            dome.move(to: CGPoint(x: cx - w * 0.42, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.42, y: base),
                          control1: CGPoint(x: cx - w * 0.42, y: top - w * 0.34),
                          control2: CGPoint(x: cx + w * 0.42, y: top - w * 0.34))
            dome.closeSubpath()
            let cuff = CGRect(x: cx - w * 0.45, y: base - w * 0.06, width: w * 0.9, height: w * 0.13)
            return [NotchMascotWearablePart(path: dome, fill: rgb(0x3FB8AF)),
                    NotchMascotWearablePart(path: rounded(cuff, w * 0.06), fill: rgb(0x2E8F88)),
                    NotchMascotWearablePart(path: circle(CGPoint(x: cx, y: top - w * 0.2), w * 0.1),
                                            fill: rgb(0xF4F1EA))]

        case .crown:
            let base = top + w * 0.04
            let height = w * 0.26, half = w * 0.27
            let points = CGMutablePath()
            points.move(to: CGPoint(x: cx - half, y: base))
            points.addLine(to: CGPoint(x: cx - half, y: base - height))
            points.addLine(to: CGPoint(x: cx - half * 0.5, y: base - height * 0.45))
            points.addLine(to: CGPoint(x: cx, y: base - height * 1.1))
            points.addLine(to: CGPoint(x: cx + half * 0.5, y: base - height * 0.45))
            points.addLine(to: CGPoint(x: cx + half, y: base - height))
            points.addLine(to: CGPoint(x: cx + half, y: base))
            points.closeSubpath()
            return [NotchMascotWearablePart(path: points, fill: rgb(0xFFC940), stroke: rgb(0xD99A1E),
                                            lineWidth: line * 0.6),
                    NotchMascotWearablePart(path: circle(CGPoint(x: cx, y: base - height * 0.3), w * 0.05),
                                            fill: rgb(0xE5384F))]

        case .witchHat:
            let brim = CGRect(x: cx - w * 0.46, y: top - w * 0.04, width: w * 0.92, height: w * 0.12)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: cx - w * 0.26, y: brim.midY))
            cone.addQuadCurve(to: CGPoint(x: cx + w * 0.2, y: top - w * 0.62),
                              control: CGPoint(x: cx - w * 0.06, y: top - w * 0.3))
            cone.addQuadCurve(to: CGPoint(x: cx + w * 0.26, y: brim.midY),
                              control: CGPoint(x: cx + w * 0.12, y: top - w * 0.24))
            cone.closeSubpath()
            let band = CGRect(x: cx - w * 0.25, y: brim.minY - w * 0.08, width: w * 0.5, height: w * 0.07)
            return [NotchMascotWearablePart(path: cone, fill: rgb(0x5B3A8C)),
                    NotchMascotWearablePart(path: CGPath(ellipseIn: brim, transform: nil), fill: rgb(0x4A2E73)),
                    NotchMascotWearablePart(path: CGPath(rect: band, transform: nil), fill: rgb(0xFF8C2B))]

        case .santaHat:
            let base = top + w * 0.1
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: cx - w * 0.4, y: base))
            cap.addQuadCurve(to: CGPoint(x: cx + w * 0.42, y: top - w * 0.28),
                             control: CGPoint(x: cx - w * 0.1, y: top - w * 0.5))
            cap.addQuadCurve(to: CGPoint(x: cx + w * 0.4, y: base),
                             control: CGPoint(x: cx + w * 0.3, y: top - w * 0.05))
            cap.closeSubpath()
            let trim = CGRect(x: cx - w * 0.46, y: base - w * 0.07, width: w * 0.92, height: w * 0.15)
            return [NotchMascotWearablePart(path: cap, fill: rgb(0xE23B3B)),
                    NotchMascotWearablePart(path: rounded(trim, w * 0.075), fill: rgb(0xF7F4EE)),
                    NotchMascotWearablePart(path: circle(CGPoint(x: cx + w * 0.44, y: top - w * 0.28), w * 0.1),
                                            fill: rgb(0xF7F4EE))]

        case .partyHat:
            let base = top + w * 0.06
            let tip = CGPoint(x: cx + w * 0.06, y: top - w * 0.5)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: cx - w * 0.2, y: base))
            cone.addLine(to: tip)
            cone.addLine(to: CGPoint(x: cx + w * 0.22, y: base))
            cone.closeSubpath()
            let stripes = CGMutablePath()
            for t in [0.35, 0.65] as [CGFloat] {
                let y = base + (tip.y - base) * t
                let half = w * 0.21 * (1 - t)
                let x = cx + (tip.x - cx) * t
                stripes.move(to: CGPoint(x: x - half, y: y))
                stripes.addLine(to: CGPoint(x: x + half, y: y))
            }
            return [NotchMascotWearablePart(path: cone, fill: rgb(0x6C8CFF)),
                    NotchMascotWearablePart(path: stripes, fill: nil, stroke: rgb(0xFFD23F), lineWidth: line),
                    NotchMascotWearablePart(path: circle(tip, w * 0.08), fill: rgb(0xFF5E8A))]

        case .headband:
            let y = top + w * 0.13
            let band = CGRect(x: cx - w * 0.5, y: y, width: w, height: w * 0.14)
            let tails = CGMutablePath()
            let knot = CGPoint(x: band.maxX - w * 0.02, y: band.midY)
            tails.move(to: knot)
            tails.addLine(to: CGPoint(x: knot.x + w * 0.2, y: knot.y + w * 0.1))
            tails.addLine(to: CGPoint(x: knot.x + w * 0.16, y: knot.y + w * 0.18))
            tails.closeSubpath()
            return [NotchMascotWearablePart(path: rounded(band, w * 0.05), fill: rgb(0xE5384F)),
                    NotchMascotWearablePart(path: tails, fill: rgb(0xB82638))]

        case .headphones:
            let eyeY = (f.leftEye.y + f.rightEye.y) / 2
            let band = CGMutablePath()
            band.move(to: CGPoint(x: f.outline.minX + w * 0.02, y: eyeY))
            band.addCurve(to: CGPoint(x: f.outline.maxX - w * 0.02, y: eyeY),
                          control1: CGPoint(x: f.outline.minX, y: top - w * 0.32),
                          control2: CGPoint(x: f.outline.maxX, y: top - w * 0.32))
            let cupSize = CGSize(width: w * 0.18, height: w * 0.3)
            let cups = CGMutablePath()
            cups.addPath(rounded(CGRect(x: f.outline.minX - cupSize.width * 0.45, y: eyeY - cupSize.height / 2,
                                        width: cupSize.width, height: cupSize.height), cupSize.width * 0.45))
            cups.addPath(rounded(CGRect(x: f.outline.maxX - cupSize.width * 0.55, y: eyeY - cupSize.height / 2,
                                        width: cupSize.width, height: cupSize.height), cupSize.width * 0.45))
            return [NotchMascotWearablePart(path: band, fill: nil, stroke: rgb(0x3A3F4B), lineWidth: line * 1.3),
                    NotchMascotWearablePart(path: cups, fill: rgb(0x5AC8FA), stroke: rgb(0x3A3F4B), lineWidth: line)]

        case .scarf:
            let y = f.outline.minY + f.outline.height * 0.66
            let band = CGRect(x: f.outline.minX + w * 0.03, y: y - w * 0.02, width: w * 0.94, height: w * 0.17)
            let tail = CGRect(x: cx + w * 0.1, y: band.midY, width: w * 0.17, height: w * 0.32)
            let stripe = CGMutablePath()
            stripe.move(to: CGPoint(x: tail.minX, y: tail.maxY - w * 0.07))
            stripe.addLine(to: CGPoint(x: tail.maxX, y: tail.maxY - w * 0.07))
            return [NotchMascotWearablePart(path: rounded(tail, w * 0.03), fill: rgb(0xC63E3B)),
                    NotchMascotWearablePart(path: rounded(band, w * 0.065), fill: rgb(0xE8524F)),
                    NotchMascotWearablePart(path: stripe, fill: nil, stroke: rgb(0xFFD166), lineWidth: line)]

        case .cap:
            let base = top + w * 0.12
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: cx - w * 0.4, y: base))
            dome.addCurve(to: CGPoint(x: cx + w * 0.4, y: base),
                          control1: CGPoint(x: cx - w * 0.4, y: top - w * 0.3),
                          control2: CGPoint(x: cx + w * 0.4, y: top - w * 0.3))
            dome.closeSubpath()
            let brim = CGRect(x: cx + w * 0.16, y: base - w * 0.08, width: w * 0.5, height: w * 0.11)
            return [NotchMascotWearablePart(path: rounded(brim, w * 0.055), fill: rgb(0x3358C9)),
                    NotchMascotWearablePart(path: dome, fill: rgb(0x4A7BFF)),
                    NotchMascotWearablePart(path: circle(CGPoint(x: cx, y: top - w * 0.16), w * 0.05),
                                            fill: rgb(0xF4F1EA))]

        case .cowboyHat:
            let brim = CGRect(x: cx - w * 0.56, y: top - w * 0.07, width: w * 1.12, height: w * 0.16)
            let crown = CGMutablePath()
            let foot = brim.midY
            crown.move(to: CGPoint(x: cx - w * 0.27, y: foot))
            crown.addLine(to: CGPoint(x: cx - w * 0.24, y: top - w * 0.3))
            crown.addQuadCurve(to: CGPoint(x: cx, y: top - w * 0.24), control: CGPoint(x: cx - w * 0.12, y: top - w * 0.36))
            crown.addQuadCurve(to: CGPoint(x: cx + w * 0.24, y: top - w * 0.3), control: CGPoint(x: cx + w * 0.12, y: top - w * 0.36))
            crown.addLine(to: CGPoint(x: cx + w * 0.27, y: foot))
            crown.closeSubpath()
            let band = CGRect(x: cx - w * 0.26, y: foot - w * 0.1, width: w * 0.52, height: w * 0.07)
            return [NotchMascotWearablePart(path: crown, fill: rgb(0xB07A45)),
                    NotchMascotWearablePart(path: CGPath(rect: band, transform: nil), fill: rgb(0x5C3B1E)),
                    NotchMascotWearablePart(path: CGPath(ellipseIn: brim, transform: nil), fill: rgb(0x9A6638))]

        case .chefHat:
            let band = CGRect(x: cx - w * 0.27, y: top - w * 0.07, width: w * 0.54, height: w * 0.15)
            let puffs = CGMutablePath()
            puffs.addPath(circle(CGPoint(x: cx - w * 0.17, y: top - w * 0.18), w * 0.16))
            puffs.addPath(circle(CGPoint(x: cx, y: top - w * 0.27), w * 0.19))
            puffs.addPath(circle(CGPoint(x: cx + w * 0.17, y: top - w * 0.18), w * 0.16))
            return [NotchMascotWearablePart(path: puffs, fill: rgb(0xF7F4EE)),
                    NotchMascotWearablePart(path: rounded(band, w * 0.03), fill: rgb(0xE4DED2),
                                            stroke: rgb(0xC9C1B2), lineWidth: line * 0.5)]

        case .halo:
            let ring = CGRect(x: cx - w * 0.27, y: top - w * 0.33, width: w * 0.54, height: w * 0.13)
            return [NotchMascotWearablePart(path: CGPath(ellipseIn: ring, transform: nil), fill: nil,
                                            stroke: rgb(0xFFD84D), lineWidth: line * 1.4)]

        case .horns:
            let horns = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                let inner = CGPoint(x: cx + side * w * 0.12, y: top + w * 0.05)
                let outer = CGPoint(x: cx + side * w * 0.32, y: top + w * 0.07)
                let tip = CGPoint(x: cx + side * w * 0.36, y: top - w * 0.22)
                horns.move(to: inner)
                horns.addQuadCurve(to: tip, control: CGPoint(x: cx + side * w * 0.16, y: top - w * 0.14))
                horns.addQuadCurve(to: outer, control: CGPoint(x: cx + side * w * 0.38, y: top - w * 0.06))
                horns.closeSubpath()
            }
            return [NotchMascotWearablePart(path: horns, fill: rgb(0xE5384F), stroke: rgb(0xB82638),
                                            lineWidth: line * 0.5)]

        case .bowTie:
            let knot = CGPoint(x: cx, y: f.outline.minY + f.outline.height * 0.74)
            let s = w * 0.17
            let wings = CGMutablePath()
            for side in [-1, 1] as [CGFloat] {
                wings.move(to: knot)
                wings.addLine(to: CGPoint(x: knot.x + side * s, y: knot.y - s * 0.6))
                wings.addLine(to: CGPoint(x: knot.x + side * s, y: knot.y + s * 0.6))
                wings.closeSubpath()
            }
            return [NotchMascotWearablePart(path: wings, fill: rgb(0xE5384F)),
                    NotchMascotWearablePart(path: circle(knot, s * 0.3), fill: rgb(0xB82638))]

        case .monocle:
            let r = max(f.size * 0.06, abs(f.rightEye.x - f.leftEye.x) * 0.4)
            let chain = CGMutablePath()
            chain.move(to: CGPoint(x: f.rightEye.x, y: f.rightEye.y + r))
            chain.addQuadCurve(to: CGPoint(x: f.outline.maxX - w * 0.04, y: f.outline.minY + f.outline.height * 0.7),
                               control: CGPoint(x: f.rightEye.x + r * 0.4, y: f.rightEye.y + r * 3))
            return [NotchMascotWearablePart(path: chain, fill: nil, stroke: rgb(0xD9A82E), lineWidth: line * 0.6),
                    NotchMascotWearablePart(path: circle(f.rightEye, r * 1.05), fill: nil, stroke: rgb(0xD9A82E),
                                            lineWidth: line * 1.1)]

        case .eyePatch:
            let r = max(f.size * 0.06, abs(f.rightEye.x - f.leftEye.x) * 0.42)
            let strap = CGMutablePath()
            strap.move(to: CGPoint(x: f.outline.minX + w * 0.02, y: f.leftEye.y - r * 1.4))
            strap.addLine(to: CGPoint(x: f.outline.maxX - w * 0.02, y: f.rightEye.y - r * 2.1))
            let ink = NotchMascotColor.ink.cgColor
            return [NotchMascotWearablePart(path: strap, fill: nil, stroke: ink, lineWidth: line * 0.8),
                    NotchMascotWearablePart(path: CGPath(ellipseIn: CGRect(x: f.leftEye.x - r, y: f.leftEye.y - r * 0.9,
                                                                         width: r * 2, height: r * 1.8), transform: nil),
                                            fill: rgb(0x16161C), stroke: ink, lineWidth: line * 0.6)]

        case .glasses, .sunglasses:
            // Lenses a little apart, so the bridge shows between them.
            let r = max(f.size * 0.06, abs(f.rightEye.x - f.leftEye.x) * 0.4)
            let lenses = CGMutablePath()
            lenses.addPath(circle(f.leftEye, r))
            lenses.addPath(circle(f.rightEye, r))
            let bridge = CGMutablePath()
            bridge.move(to: CGPoint(x: f.leftEye.x + r, y: f.leftEye.y))
            bridge.addLine(to: CGPoint(x: f.rightEye.x - r, y: f.rightEye.y))
            let ink = NotchMascotColor.ink.cgColor
            if accessory == .sunglasses {
                return [NotchMascotWearablePart(path: lenses, fill: rgb(0x16161C), stroke: ink, lineWidth: line),
                        NotchMascotWearablePart(path: bridge, fill: nil, stroke: ink, lineWidth: line)]
            }
            return [NotchMascotWearablePart(path: lenses, fill: nil, stroke: ink, lineWidth: line),
                    NotchMascotWearablePart(path: bridge, fill: nil, stroke: ink, lineWidth: line)]

        default:
            // The Wonder Boy wardrobe has its own file.
            return rpgParts(for: accessory, in: f)
        }
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
               transform: nil)
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }
}
