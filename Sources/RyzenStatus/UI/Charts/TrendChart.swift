// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// One plotted point on a `TrendChart`.
struct TrendPoint: Equatable, Sendable {
    var date: Date
    var value: Double
}

/// One line (with optional area fill) on a `TrendChart`.
struct TrendSeries: Equatable, Sendable {
    var points: [TrendPoint]
    var color: Color
    var filled: Bool = false
    var lineWidth: CGFloat = 2
}

/// A dashed horizontal threshold line with a leading label (e.g. "90°C").
struct TrendRule: Equatable, Sendable {
    var value: Double
    var label: String
    var color: Color
}

/// A lightweight, immediate-mode timeline chart drawn entirely with a single SwiftUI `Canvas`.
/// Draws smooth cubic spline waveforms with zero layout overhead.
struct TrendChart: View {
    var series: [TrendSeries]
    var yDomain: ClosedRange<Double>? = nil
    var yTicks: [Double]? = nil
    var yFormat: @Sendable (Double) -> String = { String(Int($0)) }
    var rules: [TrendRule] = []
    var showsTimeAxis: Bool = false

    private let leftGutter: CGFloat = 32
    private let topPad: CGFloat = 6
    private let bottomPad: CGFloat = 4

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let xAxisHeight: CGFloat = showsTimeAxis ? 14 : 0
            let plot = CGRect(
                x: leftGutter,
                y: topPad,
                width: max(1, size.width - leftGutter - 6),
                height: max(1, size.height - topPad - bottomPad - xAxisHeight)
            )

            let domain = resolvedDomain()
            let span = max(domain.upperBound - domain.lowerBound, 0.0001)
            func yPos(_ v: Double) -> CGFloat {
                plot.maxY - CGFloat((min(max(v, domain.lowerBound), domain.upperBound) - domain.lowerBound) / span) * plot.height
            }

            let (tMin, tMax) = timeBounds()
            let tSpan = max(tMax - tMin, 0.0001)
            func xPos(_ d: Date) -> CGFloat {
                plot.minX + CGFloat((d.timeIntervalSinceReferenceDate - tMin) / tSpan) * plot.width
            }

            // Gridlines + Y labels
            for tick in yTicks ?? defaultTicks(domain) {
                let yy = yPos(tick)
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: yy))
                line.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(line, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)

                let label = ctx.resolve(Text(yFormat(tick)).font(.system(size: 8)).foregroundColor(.secondary))
                ctx.draw(label, at: CGPoint(x: plot.minX - 4, y: yy), anchor: .trailing)
            }

            // Threshold rules
            for rule in rules {
                let yy = yPos(rule.value)
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: yy))
                line.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(
                    line,
                    with: .color(rule.color.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                let label = ctx.resolve(Text(rule.label).font(.system(size: 8, weight: .semibold)).foregroundColor(rule.color))
                ctx.draw(label, at: CGPoint(x: plot.minX + 3, y: yy - 6), anchor: .topLeading)
            }

            guard tMax > tMin else { return }

            // Series rendering
            for s in series {
                for run in Self.runs(s.points) where !run.isEmpty {
                    let cgPoints = run.map { CGPoint(x: xPos($0.date), y: yPos($0.value)) }
                    let linePath = Self.smoothPath(for: cgPoints)

                    if s.filled, run.count >= 2 {
                        var fill = linePath
                        fill.addLine(to: CGPoint(x: cgPoints.last!.x, y: plot.maxY))
                        fill.addLine(to: CGPoint(x: cgPoints.first!.x, y: plot.maxY))
                        fill.closeSubpath()
                        ctx.fill(
                            fill,
                            with: .linearGradient(
                                Gradient(colors: [s.color.opacity(0.38), s.color.opacity(0.02)]),
                                startPoint: CGPoint(x: 0, y: plot.minY),
                                endPoint: CGPoint(x: 0, y: plot.maxY)
                            )
                        )
                    }

                    if run.count >= 2 {
                        ctx.stroke(
                            linePath,
                            with: .color(s.color),
                            style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round)
                        )
                    } else if let only = cgPoints.first {
                        let r: CGFloat = 1.5
                        let dot = Path(ellipseIn: CGRect(x: only.x - r, y: only.y - r, width: 2 * r, height: 2 * r))
                        ctx.fill(dot, with: .color(s.color))
                    }
                }
            }
        }
    }

    private func resolvedDomain() -> ClosedRange<Double> {
        if let yDomain { return yDomain }
        let peak = series.flatMap(\.points).map(\.value).max() ?? 1
        return 0...max(peak * 1.1, 1)
    }

    private func defaultTicks(_ domain: ClosedRange<Double>) -> [Double] {
        if domain.lowerBound == 0 && domain.upperBound == 100 {
            return [0, 50, 100]
        }
        let n = 2
        return (0...n).map {
            domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double($0) / Double(n)
        }
    }

    private func timeBounds() -> (Double, Double) {
        let all = series.flatMap(\.points).map(\.date.timeIntervalSinceReferenceDate)
        return (all.min() ?? 0, all.max() ?? 0)
    }

    private static func smoothPath(for points: [CGPoint]) -> Path {
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

    private static func runs(_ points: [TrendPoint]) -> [[TrendPoint]] {
        guard points.count > 1 else { return points.isEmpty ? [] : [points] }
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(points.count - 1)
        for i in 1..<points.count {
            deltas.append(points[i].date.timeIntervalSince(points[i - 1].date))
        }
        deltas.sort()
        let threshold = max(deltas[deltas.count / 2] * 15, 30)
        var result: [[TrendPoint]] = []
        var current: [TrendPoint] = [points[0]]
        for pt in points.dropFirst() {
            if let last = current.last, pt.date.timeIntervalSince(last.date) > threshold {
                result.append(current)
                current = [pt]
            } else {
                current.append(pt)
            }
        }
        result.append(current)
        return result
    }
}
