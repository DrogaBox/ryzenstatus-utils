// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// A small history graph: a filled area under a smooth cubic spline curve.
/// Rendered with Catmull-Rom interpolation for fluid 60fps waveform visualization.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double? = nil
    var fillOpacity: Double = 0.16
    var lineWidth: CGFloat = 1.5
    var showsZeroBaseline = false

    var body: some View {
        GeometryReader { geometry in
            let baselineY = max(0.5, geometry.size.height - 0.5)
            let points = points(in: geometry.size, baselineY: baselineY)
            if points.count >= 2 {
                let strokePath = smoothPath(points: points)
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: baselineY))
                        path.addPath(strokePath)
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    strokePath
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        if points.count < 3 {
            path.move(to: points[0])
            for pt in points.dropFirst() { path.addLine(to: pt) }
            return path
        }

        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i < points.count - 2 ? points[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    private func points(in size: CGSize, baselineY: CGFloat) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let topY: CGFloat = 0.5
        let plotHeight = max(1, baselineY - topY)
        let lastIndex = values.count - 1
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1, max(0, value / peak))
            let y = baselineY - plotHeight * CGFloat(normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
