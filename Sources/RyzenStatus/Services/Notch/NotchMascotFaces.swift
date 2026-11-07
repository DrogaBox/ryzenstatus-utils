// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics
import Foundation

/// In the island the companions show their faces, not their whole bodies:
/// a figure whose head is a part of it is drawn zoomed in on its head, the
/// rest cut off under the chin, like a portrait in a locket. Out on the
/// desktop it is whole again. The head-only figures, the minimal
/// companion, the robot, the chip and the fan, are all face already, and the
/// comic's sprites frame their own busts, so neither is touched. Pure
/// geometry in shares of the figure's box, so it is tested without a window.
extension NotchMascotCreatures {
    /// How much of the box the face fills, across or down, whichever binds.
    static let faceFill: CGFloat = 0.82
    /// Where the head's middle sits down the box: a little under the
    /// middle, so a hat has room above it.
    static let faceCenterY: CGFloat = 0.55
    /// Room around the head for ears, cheeks and the brim of a hat, in
    /// shares of the box.
    static let facePad: CGFloat = 0.1
    /// How far under the chin the portrait reaches: the top of the shoulders.
    static let faceChin: CGFloat = 0.05

    /// Whether `look` is drawn as a face in the island.
    static func showsFaceOnly(_ look: NotchMascotLook) -> Bool {
        !headOnly.contains(look.style) && look.style.sprite == nil && headOutline(look.style, size: 1) != nil
    }

    /// Takes the figure, in shares, to where its head fills the box: the
    /// same scale across and down, the head's middle at the box's middle.
    /// The identity for a figure that is all face.
    static func faceFit(_ look: NotchMascotLook) -> CGAffineTransform {
        guard showsFaceOnly(look), let head = headOutline(look.style, size: 1), head.width > 0, head.height > 0
        else { return .identity }
        let scale = min(faceFill / head.width, faceFill / head.height, 2.6)
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: 0.5 - head.midX * scale, ty: faceCenterY - head.midY * scale)
    }

    /// The same, in points, for a box `size` points wide.
    static func faceFit(_ look: NotchMascotLook, size: CGFloat) -> CGAffineTransform {
        let fit = faceFit(look)
        return CGAffineTransform(a: fit.a, b: 0, c: 0, d: fit.d, tx: fit.tx * size, ty: fit.ty * size)
    }

    /// The window the portrait shows through, in points of the fitted box:
    /// the head with room about it, open above for whatever it wears on its
    /// head and closed just under its chin so the body stays out of sight.
    static func faceMask(_ look: NotchMascotLook, size: CGFloat) -> CGPath {
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        guard showsFaceOnly(look), let outline = headOutline(look.style, size: 1) else {
            return CGPath(rect: box.insetBy(dx: -size, dy: -size), transform: nil)
        }
        let head = outline.applying(faceFit(look))
        let pad = facePad
        let left = max(-0.5, head.minX - pad) * size
        let right = min(1.5, head.maxX + pad) * size
        let bottom = min(1.3, head.maxY + faceChin) * size
        let top = -size * 1.5
        let radius = min(right - left, bottom - top) * 0.28
        return CGPath(roundedRect: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The face of `look` where the portrait puts it, for whatever is
    /// measured against the eyes in the fitted box.
    static func facedFace(_ look: NotchMascotLook) -> NotchMascotFaceLayout {
        let face = look.face
        let fit = faceFit(look)
        return NotchMascotFaceLayout(leftEye: face.leftEye.applying(fit), rightEye: face.rightEye.applying(fit),
                                     eyeSize: CGSize(width: face.eyeSize.width * fit.a, height: face.eyeSize.height * fit.a),
                                     shineCenter: face.shineCenter.applying(fit),
                                     shineRadii: CGSize(width: face.shineRadii.width * fit.a,
                                                        height: face.shineRadii.height * fit.a),
                                     shineAngle: face.shineAngle)
    }

    /// Whether `accessory` shows on a portrait: what is worn on the head,
    /// the face, the ears or the neck. What is held in a hand, worn on the
    /// feet or carried on the back is out of the picture.
    static func faceShows(_ accessory: NotchMascotAccessory) -> Bool {
        switch accessory.placement {
        case .head, .eyes, .ears, .neck: return true
        case .hand, .feet, .back: return false
        }
    }
}
