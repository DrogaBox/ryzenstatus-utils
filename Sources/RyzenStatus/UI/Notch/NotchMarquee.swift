// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// A line too long for its room slides along, resting at its start each time
/// round and fading at the edges; a line that fits stays still, and with
/// reduced motion a long one is cut short instead.
struct NotchMarquee<Content: View>: View {
    /// Points per second.
    var speed: CGFloat = 26
    var pause: TimeInterval = 1.8
    var gap: CGFloat = 32
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineWidth: CGFloat = 0
    @State private var room: CGFloat = 0
    @State private var start = Date()

    private static var fade: CGFloat { 8 }
    private var scrolls: Bool { !reduceMotion && room > 0 && lineWidth > room + 1 }

    var body: some View {
        content()
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .background(alignment: .leading) {
                content().lineLimit(1).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    TimelineView(NotchMarqueeSchedule(start: start, pause: pause,
                                                      travel: Double((lineWidth + gap) / speed),
                                                      interval: 1.0 / 30)) { timeline in
                        HStack(spacing: gap) {
                            content().lineLimit(1).fixedSize()
                            content().lineLimit(1).fixedSize()
                        }
                        .offset(x: -offset(at: timeline.date))
                    }
                    .frame(width: room, alignment: .leading)
                    .clipped()
                    .mask(edges)
                }
            }
            // A new line starts from its beginning.
            .onChange(of: lineWidth) { start = Date() }
    }

    /// Resting at the start, then one whole turn to where the copy behind it
    /// stands exactly where the line began.
    private func offset(at date: Date) -> CGFloat {
        let travel = lineWidth + gap
        let cycle = pause + Double(travel / speed)
        let elapsed = max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle)
        return elapsed < pause ? 0 : CGFloat(elapsed - pause) * speed
    }

    private var edges: some View {
        let edge = room > 0 ? min(0.2, Self.fade / room) : 0
        return LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: edge),
                                      .init(color: .black, location: 1 - edge), .init(color: .clear, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
    }
}

/// Frames only while the line moves: one as each rest begins, then steady
/// frames through the scroll. The rest draws the same frame throughout, so
/// a 30 Hz timeline there would redraw it 54 times for nothing.
struct NotchMarqueeSchedule: TimelineSchedule {
    let start: Date
    let pause: TimeInterval
    let travel: TimeInterval
    let interval: TimeInterval

    /// Never shorter than this, so a rest that ends a hair after `current`
    /// cannot round to the same date and stall the timeline.
    static let minimumStep: TimeInterval = 1.0 / 240

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let cycle = max(interval, pause + travel)
        var next = startDate
        return AnyIterator {
            let current = next
            let elapsed = max(0, current.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle)
            next = current.addingTimeInterval(Self.step(elapsed: elapsed, pause: pause, interval: interval))
            return current
        }
    }

    /// From `elapsed` into a cycle to the next frame: to the end of the rest,
    /// or one frame on while scrolling.
    static func step(elapsed: TimeInterval, pause: TimeInterval, interval: TimeInterval) -> TimeInterval {
        max(elapsed < pause ? pause - elapsed : interval, minimumStep)
    }
}
