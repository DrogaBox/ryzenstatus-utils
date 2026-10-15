// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// A long-history graph: `LongHistoryStore.bucketCount` averaged columns
/// spread across the full width, oldest on the left. A column with no
/// samples stays empty. Hovering shows the column's value and when its
/// stretch of time ended.
struct LongHistoryGraph: View {
    enum Series {
        /// Raw values drawn against `ceiling`.
        case single([Double], ceiling: Double)
        /// Two directions of traffic, each scaled to its own busiest column.
        case dual(upper: [Double], lower: [Double])
    }

    let series: Series
    let range: LongHistoryRange
    let end: Date
    let language: AppLanguage
    /// The hovered column's text. The second value is the lower series of a
    /// dual graph, nil for a single one. Values may be NaN for a gap.
    let format: (Double, Double?) -> String
    @State private var hoverIndex: Int?

    private var count: Int { LongHistoryStore.bucketCount }

    var body: some View {
        GeometryReader { geometry in
            // Half a point of slack keeps every column inside the width
            // whatever the rounding.
            let pitch = max(0.5, (geometry.size.width - 0.5) / CGFloat(count))
            let spacing: CGFloat = pitch >= 2 ? 1 : 0
            let columnWidth = pitch - spacing
            ZStack(alignment: .topLeading) {
                graph(columnWidth: columnWidth, spacing: spacing)
                if let index = hoverIndex {
                    let left = geometry.size.width - 0.5 - CGFloat(count - index) * pitch
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: geometry.size.height)
                        .offset(x: max(0, left + columnWidth / 2))
                    hoverLabel(index)
                        .fixedSize()
                        .frame(maxWidth: .infinity,
                               alignment: index < count / 2 ? .trailing : .leading)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let fromRight = Int(((geometry.size.width - 0.5 - point.x) / pitch).rounded(.down))
                    hoverIndex = min(count - 1, max(0, count - 1 - fromRight))
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func graph(columnWidth: CGFloat, spacing: CGFloat) -> some View {
        switch series {
        case .single(let values, let ceiling):
            ColumnHistoryGraph(layers: [ColumnGraphGeometry.fractions(values, ceiling: ceiling)],
                               inks: [.primary],
                               columnWidth: columnWidth,
                               spacing: spacing)
        case .dual(let upper, let lower):
            DualColumnHistoryGraph(upper: upper, lower: lower,
                                   columnWidth: columnWidth,
                                   spacing: spacing)
        }
    }

    private func hoverLabel(_ index: Int) -> some View {
        let text: String
        switch series {
        case .single(let values, _):
            text = format(values.indices.contains(index) ? values[index] : .nan, nil)
        case .dual(let upper, let lower):
            text = format(upper.indices.contains(index) ? upper[index] : .nan,
                          lower.indices.contains(index) ? lower[index] : .nan)
        }
        return Text("\(text) · \(Self.time(ofColumn: index, range: range, end: end, language: language))")
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
    }

    /// When column `index` ends, as a clock time, with the date for ranges
    /// past a day.
    static func time(ofColumn index: Int, range: LongHistoryRange, end: Date, language: AppLanguage) -> String {
        let width = range.duration / Double(LongHistoryStore.bucketCount)
        let columnEnd = end.addingTimeInterval(-range.duration + Double(index + 1) * width)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate(range.duration > 86_400 ? "MMMd jm" : "jm")
        return formatter.string(from: columnEnd)
    }
}

/// A long-history graph for a panel section: a "History" line with the range
/// menu, and the graph under it. Every panel graph shares one range. With
/// `collapsible`, the graph stays folded until the line is clicked.
struct PanelLongHistory: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.panelHistoryRange) private var rangeRaw = LongHistoryRange.oneHour.rawValue
    @State private var expanded = false
    var collapsible = false
    var height: CGFloat = 30
    /// The columns for a range ending at a time (seconds since 1970).
    let series: (LongHistoryRange, TimeInterval) -> LongHistoryGraph.Series
    let format: (Double, Double?) -> String

    private var range: LongHistoryRange { LongHistoryRange(rawValue: rangeRaw) ?? .oneHour }
    private var showsGraph: Bool { !collapsible || expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if collapsible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                            Text(l10n.s.historyTitle)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(l10n.s.historyTitle)
                }
                Spacer(minLength: 4)
                if showsGraph {
                    Menu {
                        ForEach(LongHistoryRange.allCases) { option in
                            Button(option.label(l10n.language)) { rangeRaw = option.rawValue }
                        }
                    } label: {
                        Text(range.label(l10n.language))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            if showsGraph {
                let end = Date()
                LongHistoryGraph(series: series(range, end.timeIntervalSince1970),
                                 range: range, end: end, language: l10n.language, format: format)
                    .frame(height: height)
            }
        }
    }
}

/// The 1, 5 and 15 minute load averages as shares of the threads, each in
/// its level's color: green with room to spare, yellow past half, orange
/// near every thread busy, red once work waits.
struct LoadAverageText: View {
    let percents: [Int]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(percents.enumerated()), id: \.offset) { index, percent in
                if index > 0 {
                    Text("·").foregroundStyle(.secondary)
                }
                Text("\(percent)%").foregroundStyle(color(percent))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
    }

    private func color(_ percent: Int) -> Color {
        switch MetricFormat.loadLevel(percent: percent) {
        case 0: return PanelMetricColor.green(for: colorScheme)
        case 1: return PanelMetricColor.yellow(for: colorScheme)
        case 2: return PanelMetricColor.orange(for: colorScheme)
        default: return PanelMetricColor.red(for: colorScheme)
        }
    }
}
