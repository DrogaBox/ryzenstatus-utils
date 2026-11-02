// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import CoreGraphics

/// Where a drawn figure's hands, feet, torso, nose and mouth are, so what it
/// wears goes where it belongs: shoes on its feet rather than its chin, a
/// sword in its hand rather than floating by its cheek, wings out of its
/// back. Shares of its size from the top left corner, y growing downward;
/// left and right as seen on screen. Read off the outlines in
/// `NotchMascotCreatures` and `NotchMascotHologramAndroid`, so a figure
/// redrawn there wants its numbers checked here too.
struct NotchMascotAnatomy: Equatable {
    /// The hand that holds things, on the right of the screen, and the other.
    var rightHand: CGPoint
    var leftHand: CGPoint
    /// Where its soles, paws or hem meet the ground.
    var floor: CGFloat
    /// The middle of each foot, across.
    var leftFoot: CGFloat
    var rightFoot: CGFloat
    /// How wide one foot is.
    var foot: CGFloat
    /// Its chest and belly, for what goes on its back or its shoulder.
    var torso: CGRect
    /// The tip of its nose, snout or beak, and its mouth, where the face has
    /// them somewhere the eyes alone do not tell.
    var nose: CGPoint? = nil
    var mouth: CGPoint? = nil

    /// The same anatomy in points, for a figure `size` points tall.
    func scaled(by size: CGFloat) -> NotchMascotAnatomy {
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size, y: p.y * size) }
        return NotchMascotAnatomy(rightHand: point(rightHand), leftHand: point(leftHand), floor: floor * size,
                                  leftFoot: leftFoot * size, rightFoot: rightFoot * size, foot: foot * size,
                                  torso: CGRect(x: torso.minX * size, y: torso.minY * size,
                                                width: torso.width * size, height: torso.height * size),
                                  nose: nose.map(point), mouth: mouth.map(point))
    }
}

extension NotchMascotCreatures {
    /// The figure's anatomy, in shares of its size; nil for the minimal
    /// companion and the robot, whose outline is all there is of them.
    static func anatomy(_ style: NotchMascotStyle) -> NotchMascotAnatomy? {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
        switch style {
        case .minimal, .robot:
            return nil
        // The two comic figures are drawn from sprite sheets and wear nothing
        // drawn over them, but keep honest numbers for the day they do.
        case .cristobal:
            return .init(rightHand: at(0.72, 0.60), leftHand: at(0.34, 0.60), floor: 0.94,
                         leftFoot: 0.46, rightFoot: 0.62, foot: 0.10, torso: box(0.33, 0.46, 0.42, 0.40),
                         nose: at(0.50, 0.36), mouth: at(0.50, 0.41))
        case .whiteRabbit:
            return .init(rightHand: at(0.72, 0.62), leftHand: at(0.32, 0.62), floor: 0.91,
                         leftFoot: 0.44, rightFoot: 0.60, foot: 0.09, torso: box(0.32, 0.50, 0.40, 0.34),
                         nose: at(0.50, 0.41), mouth: at(0.50, 0.45))
        // A chip holds things by its side pins and stands on its bottom row.
        case .chip:
            return .init(rightHand: at(0.89, 0.66), leftHand: at(0.11, 0.66), floor: 0.97,
                         leftFoot: 0.34, rightFoot: 0.66, foot: 0.16, torso: box(0.18, 0.26, 0.64, 0.64))
        case .fan:
            return .init(rightHand: at(0.91, 0.64), leftHand: at(0.09, 0.64), floor: 0.98,
                         leftFoot: 0.36, rightFoot: 0.64, foot: 0.18, torso: box(0.10, 0.18, 0.80, 0.80))
        // A cat is one round loaf; its nose sits well under the eyes.
        case .cat:
            return .init(rightHand: at(0.86, 0.74), leftHand: at(0.14, 0.74), floor: 0.92,
                         leftFoot: 0.38, rightFoot: 0.62, foot: 0.14, torso: box(0.12, 0.56, 0.76, 0.36),
                         nose: at(0.50, 0.737), mouth: at(0.50, 0.79))
        // A ghost has no feet: what goes on them hangs at its hem.
        case .ghost:
            return .init(rightHand: at(0.86, 0.64), leftHand: at(0.14, 0.64), floor: 0.93,
                         leftFoot: 0.40, rightFoot: 0.60, foot: 0.12, torso: box(0.16, 0.20, 0.68, 0.72),
                         nose: at(0.50, 0.63), mouth: at(0.50, 0.70))
        case .slime:
            return .init(rightHand: at(0.90, 0.72), leftHand: at(0.10, 0.72), floor: 0.94,
                         leftFoot: 0.36, rightFoot: 0.64, foot: 0.16, torso: box(0.09, 0.22, 0.82, 0.72))
        // Stubby arms either side and two big round feet.
        case .devourer:
            return .init(rightHand: at(0.86, 0.55), leftHand: at(0.14, 0.55), floor: 0.98,
                         leftFoot: 0.29, rightFoot: 0.71, foot: 0.22, torso: box(0.12, 0.20, 0.76, 0.70))
        case .shifter:
            return .init(rightHand: at(0.92, 0.72), leftHand: at(0.09, 0.72), floor: 0.95,
                         leftFoot: 0.34, rightFoot: 0.66, foot: 0.16, torso: box(0.08, 0.34, 0.85, 0.62))
        // A bird holds things against its chest and stands on its talons.
        case .phoenix:
            return .init(rightHand: at(0.78, 0.64), leftHand: at(0.22, 0.64), floor: 0.855,
                         leftFoot: 0.42, rightFoot: 0.58, foot: 0.12, torso: box(0.26, 0.36, 0.48, 0.46),
                         nose: at(0.50, 0.36), mouth: at(0.50, 0.40))
        // Its head is wider than its body, so it holds things out past the
        // head's edge, where a sword raised up stays clear of its eyes.
        case .axolotl:
            return .init(rightHand: at(0.75, 0.70), leftHand: at(0.25, 0.70), floor: 0.87,
                         leftFoot: 0.40, rightFoot: 0.60, foot: 0.12, torso: box(0.32, 0.50, 0.36, 0.38),
                         nose: at(0.50, 0.38), mouth: at(0.50, 0.42))
        case .dog:
            return .init(rightHand: at(0.82, 0.70), leftHand: at(0.18, 0.70), floor: 0.95,
                         leftFoot: 0.36, rightFoot: 0.64, foot: 0.18, torso: box(0.17, 0.46, 0.66, 0.46),
                         nose: at(0.50, 0.345), mouth: at(0.50, 0.42))
        case .mouse:
            return .init(rightHand: at(0.69, 0.64), leftHand: at(0.31, 0.64), floor: 0.86,
                         leftFoot: 0.42, rightFoot: 0.58, foot: 0.10, torso: box(0.33, 0.46, 0.34, 0.40),
                         nose: at(0.50, 0.40), mouth: at(0.50, 0.45))
        case .capybara:
            return .init(rightHand: at(0.83, 0.70), leftHand: at(0.17, 0.70), floor: 0.93,
                         leftFoot: 0.38, rightFoot: 0.62, foot: 0.16, torso: box(0.16, 0.50, 0.68, 0.42),
                         nose: at(0.50, 0.42), mouth: at(0.50, 0.48))
        case .dragon:
            return .init(rightHand: at(0.79, 0.66), leftHand: at(0.21, 0.66), floor: 0.92,
                         leftFoot: 0.38, rightFoot: 0.62, foot: 0.14, torso: box(0.22, 0.50, 0.56, 0.42),
                         nose: at(0.50, 0.36), mouth: at(0.50, 0.42))
        // Wide webbed feet, far apart.
        case .frog:
            return .init(rightHand: at(0.84, 0.68), leftHand: at(0.16, 0.68), floor: 0.90,
                         leftFoot: 0.25, rightFoot: 0.75, foot: 0.18, torso: box(0.16, 0.50, 0.68, 0.40),
                         mouth: at(0.50, 0.40))
        // A swan floats: what goes on its feet rides its waterline.
        case .swan:
            return .init(rightHand: at(0.80, 0.66), leftHand: at(0.20, 0.66), floor: 0.86,
                         leftFoot: 0.42, rightFoot: 0.58, foot: 0.12, torso: box(0.23, 0.50, 0.54, 0.36),
                         nose: at(0.50, 0.30), mouth: at(0.50, 0.33))
        // Her arms are up in a crown over her head, so she holds things at
        // the rim of her tutu, and her two pointes are close together.
        case .ballerina:
            return .init(rightHand: at(0.84, 0.62), leftHand: at(0.16, 0.62), floor: 0.96,
                         leftFoot: 0.455, rightFoot: 0.545, foot: 0.075, torso: box(0.38, 0.44, 0.24, 0.18),
                         nose: at(0.50, 0.37), mouth: at(0.50, 0.40))
        case .danseur:
            return .init(rightHand: at(0.78, 0.60), leftHand: at(0.22, 0.60), floor: 0.96,
                         leftFoot: 0.415, rightFoot: 0.585, foot: 0.11, torso: box(0.24, 0.44, 0.52, 0.22),
                         nose: at(0.50, 0.36), mouth: at(0.50, 0.40))
        case .contemporary:
            return .init(rightHand: at(0.83, 0.66), leftHand: at(0.17, 0.66), floor: 0.96,
                         leftFoot: 0.38, rightFoot: 0.62, foot: 0.12, torso: box(0.20, 0.45, 0.60, 0.33),
                         nose: at(0.50, 0.39), mouth: at(0.50, 0.43))
        // Held out by its haunch, below the wide mask, so nothing tall it
        // carries rises over its face.
        case .kitsune:
            return .init(rightHand: at(0.79, 0.78), leftHand: at(0.21, 0.78), floor: 0.94,
                         leftFoot: 0.40, rightFoot: 0.60, foot: 0.14, torso: box(0.28, 0.58, 0.44, 0.34),
                         nose: at(0.50, 0.58), mouth: at(0.50, 0.61))
        // Flipper tips, resting, and two orange feet under the egg.
        case .penguin:
            return .init(rightHand: at(0.84, 0.72), leftHand: at(0.16, 0.72), floor: 0.94,
                         leftFoot: 0.395, rightFoot: 0.605, foot: 0.15, torso: box(0.22, 0.42, 0.56, 0.48),
                         nose: at(0.50, 0.39), mouth: at(0.50, 0.43))
        // Her hands where they rest: the right one down, the left on her hip.
        case .hologram:
            return .init(rightHand: at(0.72, 0.69), leftHand: at(0.32, 0.65), floor: 0.90,
                         leftFoot: 0.43, rightFoot: 0.57, foot: 0.09, torso: box(0.30, 0.45, 0.40, 0.26),
                         nose: at(0.50, 0.365), mouth: at(0.50, 0.40))
        case .android:
            return .init(rightHand: at(0.73, 0.69), leftHand: at(0.27, 0.69), floor: 0.885,
                         leftFoot: 0.445, rightFoot: 0.555, foot: 0.09, torso: box(0.28, 0.45, 0.44, 0.25),
                         nose: at(0.50, 0.345), mouth: at(0.50, 0.38))
        }
    }
}
