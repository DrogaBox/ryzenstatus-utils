// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// A live line chart for the Monitor window: the newest sample on the right,
/// grid lines at familiar values with their labels on the trailing side
/// (HIG Charts: a clean leading edge), and one path per series drawn in a
/// single `Canvas` pass, so a 1 Hz update costs one fill and one stroke.
/// A non-finite sample breaks the line instead of drawing a false value.
struct TrendChart: View {
    struct Series: Equatable {
        var values: [Double]
        var color: Color
        /// Said by VoiceOver before this series' summary.
        var name: String = ""
        /// A second series is dashed and unfilled, so two lines never rely
        /// on color alone (HIG Charts).
        var dashed = false
    }

    var series: [Series]
    /// The value at the top grid line; the bottom one is zero.
    var ceiling: Double
    /// How many samples span the full width, so a short history grows in
    /// from the right instead of stretching.
    var capacity: Int = 120
    /// Labels for the grid lines at 0, ½ and 1 of the ceiling.
    var gridLabel: (Double) -> String
    var fillsArea: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size)
            }
            VStack(alignment: .leading) {
                Text(gridLabel(ceiling))
                Spacer(minLength: 0)
                Text(gridLabel(ceiling / 2))
                Spacer(minLength: 0)
                Text(gridLabel(0))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let grid = Color(nsColor: .separatorColor)
        for fraction in [0.0, 0.5, 1.0] {
            let y = (size.height - 1) * (1 - fraction) + 0.5
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(grid), lineWidth: 1)
        }
        guard ceiling > 0, capacity > 1 else { return }
        let step = size.width / CGFloat(capacity - 1)
        for item in series {
            let values = item.values.suffix(capacity)
            let start = capacity - values.count
            var stroke = Path()
            var fill = Path()
            var open = false
            var firstX: CGFloat = 0
            var lastX: CGFloat = 0
            func closeFill() {
                guard open, fillsArea else { return }
                fill.addLine(to: CGPoint(x: lastX, y: size.height))
                fill.addLine(to: CGPoint(x: firstX, y: size.height))
                fill.closeSubpath()
            }
            for (offset, value) in values.enumerated() {
                let x = CGFloat(start + offset) * step
                guard value.isFinite else {
                    closeFill()
                    open = false
                    continue
                }
                let fraction = min(1, max(0, value / ceiling))
                let point = CGPoint(x: x, y: (size.height - 1) * (1 - fraction) + 0.5)
                if open {
                    stroke.addLine(to: point)
                    if fillsArea { fill.addLine(to: point) }
                } else {
                    stroke.move(to: point)
                    if fillsArea {
                        fill.move(to: CGPoint(x: x, y: size.height))
                        fill.addLine(to: point)
                    }
                    firstX = x
                    open = true
                }
                lastX = x
            }
            closeFill()
            if fillsArea && !item.dashed {
                context.fill(fill, with: .color(item.color.opacity(0.18)))
            }
            context.stroke(stroke, with: .color(item.color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                              dash: item.dashed ? [4, 3] : []))
        }
    }

    /// The smallest familiar value (1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a
    /// power of ten) at or above `value`, so the top grid line reads like
    /// 80, 150 or 250.
    nonisolated static func niceCeiling(_ value: Double, minimum: Double = 1) -> Double {
        let target = max(minimum, value.isFinite ? value : minimum)
        let magnitude = pow(10, floor(log10(target)))
        for multiple in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0] where multiple * magnitude >= target {
            return multiple * magnitude
        }
        return 10 * magnitude
    }
}

/// The system's continuous capacity level indicator (HIG Gauges › macOS):
/// green, yellow past `warning`, red past `critical`.
struct LevelIndicator: NSViewRepresentable {
    var value: Double
    var maximum: Double = 1
    var warning: Double?
    var critical: Double?

    func makeNSView(context: Context) -> NSLevelIndicator {
        let indicator = NSLevelIndicator()
        indicator.levelIndicatorStyle = .continuousCapacity
        indicator.minValue = 0
        indicator.isEditable = false
        indicator.setContentHuggingPriority(.defaultLow, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return indicator
    }

    func updateNSView(_ indicator: NSLevelIndicator, context: Context) {
        if indicator.maxValue != maximum { indicator.maxValue = maximum }
        let warningValue = warning ?? 0
        let criticalValue = critical ?? 0
        if indicator.warningValue != warningValue { indicator.warningValue = warningValue }
        if indicator.criticalValue != criticalValue { indicator.criticalValue = criticalValue }
        let clamped = min(maximum, max(0, value.isFinite ? value : 0))
        if indicator.doubleValue != clamped { indicator.doubleValue = clamped }
    }
}

/// Average, peak and latest value of a history series, for the charts'
/// spoken summaries and the average caption. Non-finite samples are ignored;
/// nil for a series with no finite sample.
enum MetricSeriesSummary {
    static func summary(_ values: [Double]) -> (average: Double, peak: Double, last: Double)? {
        let finite = values.filter(\.isFinite)
        guard let last = finite.last, let peak = finite.max() else { return nil }
        return (finite.reduce(0, +) / Double(finite.count), peak, last)
    }
}
