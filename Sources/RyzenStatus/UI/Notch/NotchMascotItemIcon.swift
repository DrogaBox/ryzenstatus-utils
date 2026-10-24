// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Vector preview of a companion accessory, scaled and centered within a square canvas.
struct NotchMascotAccessoryVector: View {
    let accessory: NotchMascotAccessory
    var size: CGFloat = 28

    private static let refFrame = NotchMascotWearableFrame(
        outline: CGRect(x: 20, y: 30, width: 60, height: 60),
        size: 100,
        leftEye: CGPoint(x: 38, y: 55),
        rightEye: CGPoint(x: 62, y: 55)
    )

    var body: some View {
        if accessory == .none {
            Image(systemName: "slash.circle")
                .font(.system(size: size * 0.58, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            let parts = NotchMascotWearableShapes.parts(for: accessory, in: Self.refFrame)
            let unionBox = calculateUnionBox(of: parts)
            Canvas { context, canvasSize in
                guard !parts.isEmpty, !unionBox.isNull, (unionBox.width > 0 || unionBox.height > 0) else { return }
                let pad: CGFloat = 2
                let targetW = max(1, canvasSize.width - pad * 2)
                let targetH = max(1, canvasSize.height - pad * 2)
                let boxW = max(0.1, unionBox.width)
                let boxH = max(0.1, unionBox.height)
                let scale = min(targetW / boxW, targetH / boxH)
                let renderedW = boxW * scale
                let renderedH = boxH * scale
                let originX = (canvasSize.width - renderedW) / 2.0
                let originY = (canvasSize.height - renderedH) / 2.0

                var transform = CGAffineTransform(translationX: -unionBox.minX, y: -unionBox.minY)
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                transform = transform.concatenating(CGAffineTransform(translationX: originX, y: originY))

                for part in parts {
                    let path = Path(part.path).applying(transform)
                    if let fill = part.fill {
                        context.fill(path, with: .color(Color(cgColor: fill)))
                    }
                    if let stroke = part.stroke, part.lineWidth > 0 {
                        context.stroke(
                            path,
                            with: .color(Color(cgColor: stroke)),
                            style: StrokeStyle(lineWidth: max(0.8, part.lineWidth * scale), lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func calculateUnionBox(of parts: [NotchMascotWearablePart]) -> CGRect {
        var union = CGRect.null
        for part in parts {
            let box = part.path.boundingBoxOfPath
            guard !box.isNull, (box.width > 0 || box.height > 0) else { continue }
            union = union.isNull ? box : union.union(box)
        }
        return union
    }
}

/// A compact 44x44 tile displaying an accessory vector with selection and unlock state.
struct NotchMascotAccessoryTile: View {
    let accessory: NotchMascotAccessory
    let selected: Bool
    let unlocked: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 44, height: 44)

                NotchMascotAccessoryVector(accessory: accessory, size: 28)
                    .opacity(unlocked ? 1.0 : 0.45)

                if !unlocked {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .disabled(!unlocked)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
