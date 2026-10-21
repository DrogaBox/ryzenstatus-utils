// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import QuartzCore
import SwiftUI

/// What flies between the companion and its friend resting in the closed
/// island as they play, and the little bursts over them. Drawn over the
/// strip, between their two places; nothing here takes a click.
struct NotchMascotIslandPlayLayer: View {
    let flight: NotchMascotIslandFlightEvent?
    let burst: NotchMascotIslandBurstEvent?
    var marker: NotchMascotIslandMarkerEvent? = nil
    let leader: NotchMascotTrack
    let friend: NotchMascotTrack
    let leaderLook: NotchMascotLook
    let friendLook: NotchMascotLook

    /// Whether something is in the air or on show; the clock only runs then,
    /// so a resting pair costs no frames.
    @State private var live = false
    @State private var settle: DispatchWorkItem?
    @State private var until: CFTimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !live)) { _ in
            let now = CACurrentMediaTime()
            ZStack {
                if let flight { flying(flight, now: now) }
                if let burst { bursting(burst, now: now) }
                if let marker { marking(marker, now: now) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: flight) { _, event in if let event { run(for: event.flight.duration) } }
        .onChange(of: burst) { _, event in if let event { run(for: event.burst.duration) } }
        .onChange(of: marker) { _, event in if event != nil { run(for: NotchMascotIslandPlay.markerLength) } }
        .onDisappear { settle?.cancel(); live = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Runs the clock for `length` more seconds, then pauses it on a clean frame.
    private func run(for length: TimeInterval) {
        live = true
        settle?.cancel()
        until = max(until, CACurrentMediaTime() + length + 0.15)
        let item = DispatchWorkItem { live = false }
        settle = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (until - CACurrentMediaTime()), execute: item)
    }

    // MARK: Flight

    @ViewBuilder
    private func flying(_ event: NotchMascotIslandFlightEvent, now: CFTimeInterval) -> some View {
        let flight = event.flight
        let progress = (now - event.start) / max(0.01, flight.duration)
        if progress >= 0, progress <= 1 {
            let from = flight.fromLeader ? leader : friend
            let to = flight.fromLeader ? friend : leader
            let size = max(5, leader.size * 0.38)
            // Each figure sits a little off its square: the flight leaves and
            // lands at the figure's own height, not the square's.
            let fromLook = flight.fromLeader ? leaderLook : friendLook
            let toLook = flight.fromLeader ? friendLook : leaderLook
            let start = CGPoint(x: from.rest,
                                y: from.baseline - from.size * 0.1 + NotchMascotGeometry.figureOffset(fromLook) * from.size)
            let end = CGPoint(x: to.rest,
                              y: to.baseline - to.size * 0.1 + NotchMascotGeometry.figureOffset(toLook) * to.size)
            // A high arc, as high as the island allows, so it clears the
            // camera's gap, and out of sight while it is over the gap.
            let lift = Self.arcLift(start: start, end: end, ceiling: leader.ceiling, thing: size, figure: leader.size)
            let place = Self.place(progress: progress, from: start, to: end, lift: lift, falls: flight.falls,
                                   drop: leader.size * 0.5)
            let hidden = Self.overGap(place.point.x, gap: leader.hidden ?? friend.hidden, margin: size * 0.5)
            thing(flight.thing, size: size, look: fromLook)
                .rotationEffect(.degrees(Self.spins(flight.thing) ? progress * 360 : 0))
                .scaleEffect(x: end.x < start.x && Self.points(flight.thing) ? -1 : 1, y: 1)
                .opacity(hidden ? 0 : place.opacity)
                .position(place.point)
        }
    }

    /// How high the arc rises above the line between the two: the island's
    /// room up to its top, but at least what a figure's hop takes.
    static func arcLift(start: CGPoint, end: CGPoint, ceiling: CGFloat, thing: CGFloat, figure: CGFloat) -> CGFloat {
        let room = min(start.y, end.y) - ceiling - thing / 2
        return max(2, min(figure * 1.1, room))
    }

    /// Whether x is over the camera's gap, where nothing shows.
    static func overGap(_ x: CGFloat, gap: ClosedRange<CGFloat>?, margin: CGFloat) -> Bool {
        guard let gap else { return false }
        return x > gap.lowerBound - margin && x < gap.upperBound + margin
    }

    /// Things that have a front and point the way they fly.
    static func points(_ thing: NotchMascotIslandPlay.Thing) -> Bool {
        switch thing {
        case .arrow, .sword, .fireball, .key: return true
        default: return false
        }
    }

    /// Where it is `progress` of the way: an arc from one to the other, or
    /// for one that falls short, most of the arc, then a drop as it fades.
    static func place(progress: Double, from: CGPoint, to: CGPoint, lift: CGFloat, falls: Bool,
                      drop: CGFloat) -> (point: CGPoint, opacity: Double) {
        let p = CGFloat(max(0, min(1, progress)))
        guard falls else {
            let x = from.x + (to.x - from.x) * p
            let y = from.y + (to.y - from.y) * p - lift * sin(.pi * p)
            return (CGPoint(x: x, y: y), 1)
        }
        // It covers two thirds of the way by 0.7, then drops.
        let reach: CGFloat = 0.66
        if p <= 0.7 {
            let q = p / 0.7
            let x = from.x + (to.x - from.x) * reach * q
            let y = from.y + (to.y - from.y) * reach * q - lift * sin(.pi * q * 0.8)
            return (CGPoint(x: x, y: y), 1)
        }
        let q = min(1, (p - 0.7) / 0.3)
        let edge = sin(.pi * 0.8) * lift
        let x = from.x + (to.x - from.x) * (reach + 0.08 * q)
        let y = from.y + (to.y - from.y) * reach - edge + (edge + drop) * q * q
        return (CGPoint(x: x, y: y), Double(max(0, 1 - q)))
    }

    static func spins(_ thing: NotchMascotIslandPlay.Thing) -> Bool {
        switch thing {
        case .star, .ball, .coin, .cookie, .flower, .boomerang: return true
        case .heart, .note, .spark, .snowball, .fireball, .arrow, .key, .potion, .bag, .bolt, .tornado, .sword,
             .snack: return false
        }
    }

    @ViewBuilder
    private func thing(_ thing: NotchMascotIslandPlay.Thing, size: CGFloat, look: NotchMascotLook) -> some View {
        if let parts = NotchMascotRPGShapes.prop(thing, at: CGPoint(x: size, y: size), side: size * 1.5) {
            NotchMascotPartsView(parts: parts, side: size * 2)
                .frame(width: size * 2, height: size * 2)
        } else {
            basicThing(thing, size: size, look: look)
        }
    }

    @ViewBuilder
    private func basicThing(_ thing: NotchMascotIslandPlay.Thing, size: CGFloat, look: NotchMascotLook) -> some View {
        switch thing {
        case .heart: symbol("heart.fill", size: size, color: Color(hex: 0xFF5E8A))
        case .star: symbol("star.fill", size: size, color: Color(hex: 0xFFD23F))
        case .note: symbol("music.note", size: size, color: .white)
        case .flower: symbol("camera.macro", size: size, color: Color(hex: 0xFF8FB1))
        case .ball: symbol("baseball.fill", size: size, color: .white)
        case .spark:
            let energy = Self.color(NotchMascotPlay.energy(for: look))
            Circle().fill(energy).frame(width: size * 0.7, height: size * 0.7)
                .shadow(color: energy, radius: size * 0.4)
        case .snowball:
            Circle().fill(Color.white).frame(width: size * 0.75, height: size * 0.75)
                .overlay(Circle().stroke(Color(hex: 0xCFE6FF), lineWidth: 0.6))
        case .cookie:
            Circle().fill(Color(hex: 0xC68642)).frame(width: size * 0.8, height: size * 0.8)
                .overlay {
                    ForEach(0..<3, id: \.self) { chip in
                        Circle().fill(Color(hex: 0x5C3B1E)).frame(width: size * 0.14, height: size * 0.14)
                            .offset(x: [-0.18, 0.16, 0.0][chip] * size, y: [-0.12, -0.04, 0.18][chip] * size)
                    }
                }
        case .coin:
            Circle().fill(Color(hex: 0xFFC940)).frame(width: size * 0.8, height: size * 0.8)
                .overlay(Circle().stroke(Color(hex: 0xD99A1E), lineWidth: 0.8))
        default:
            EmptyView()
        }
    }

    private func symbol(_ name: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: name).font(.system(size: size, weight: .bold)).foregroundStyle(color)
    }

    static func color(_ energy: NotchMascotPlay.Energy) -> Color {
        Color(red: Double(energy.red), green: Double(energy.green), blue: Double(energy.blue))
    }

    // MARK: Burst

    @ViewBuilder
    private func bursting(_ event: NotchMascotIslandBurstEvent, now: CFTimeInterval) -> some View {
        let progress = (now - event.start) / max(0.01, event.burst.duration)
        if progress >= 0, progress <= 1 {
            let track = event.burst.onLeader ? leader : friend
            let look = event.burst.onLeader ? leaderLook : friendLook
            let center = CGPoint(x: track.rest,
                                 y: track.baseline - track.size * 0.45 + NotchMascotGeometry.figureOffset(look) * track.size)
            let p = CGFloat(progress)
            switch event.burst.burst {
            case .door: door(progress: progress, now: now, event: event)
            case .coins: coins(center: center, track: track, progress: p)
            case .smoke: smoke(center: center, track: track, progress: p, look: look)
            default: classicBurst(event.burst, center: center, track: track, look: look, p: p)
            }
        }
    }

    /// The secret door in the middle, over the camera's gap or between the two.
    @ViewBuilder
    private func door(progress: Double, now: CFTimeInterval, event: NotchMascotIslandBurstEvent) -> some View {
        let p = max(0, min(1, (now - event.start) / max(0.01, event.burst.duration)))
        let height = leader.size * 1.5
        let width = height * 0.62
        let x = leader.hidden.map { ($0.lowerBound + $0.upperBound) / 2 } ?? (leader.rest + friend.rest) / 2
        // It grows in, swings open, holds, and closes.
        let open = p < 0.25 ? p / 0.25 : (p < 0.8 ? 1 : max(0, 1 - (p - 0.8) / 0.2))
        let scale = p < 0.15 ? 0.2 + 0.88 * (p / 0.15) : (p > 0.85 ? max(0.2, 1 - (p - 0.85) / 0.15 * 0.8) : 1)
        let rect = CGRect(x: (height - width) / 2, y: 0, width: width, height: height)
        NotchMascotPartsView(parts: NotchMascotRPGShapes.door(in: rect, open: CGFloat(open)), side: height)
            .frame(width: height, height: height)
            .scaleEffect(scale, anchor: .bottom)
            .opacity(p < 0.08 ? p / 0.08 : (p > 0.9 ? max(0, (1 - p) / 0.1) : 1))
            .position(x: x, y: max(height / 2, leader.baseline + leader.size * 0.3 - height / 2))
    }

    @ViewBuilder
    private func coins(center: CGPoint, track: NotchMascotTrack, progress p: CGFloat) -> some View {
        let radius = max(2.5, track.size * 0.11)
        ForEach(0..<5, id: \.self) { index in
            let drift = CGFloat(index - 2) * radius * 1.7
            // Up and over, then a bounce on the way down.
            let t = min(1, p * 1.1)
            let arc = sin(.pi * min(1, t * 1.15))
            let bounce = t > 0.75 ? abs(sin(.pi * (t - 0.75) / 0.25)) * 0.25 : 0
            NotchMascotPartsView(parts: NotchMascotRPGShapes.coin(at: CGPoint(x: radius * 1.5, y: radius * 1.5), radius: radius,
                                                                  turn: CGFloat(cos(Double(t) * 14 + Double(index)))),
                                 side: radius * 3)
                .frame(width: radius * 3, height: radius * 3)
                .opacity(Double(t > 0.9 ? (1 - t) * 10 : 1))
                .position(x: center.x + drift * t, y: center.y - track.size * 0.7 * (arc + bounce))
        }
    }

    @ViewBuilder
    private func smoke(center: CGPoint, track: NotchMascotTrack, progress p: CGFloat, look: NotchMascotLook) -> some View {
        let tint = Self.color(NotchMascotPlay.energy(for: look))
        ForEach(0..<5, id: \.self) { index in
            let side = CGFloat(index % 2 == 0 ? 1 : -1)
            let radius = track.size * (0.14 + 0.1 * CGFloat(index % 3)) * (0.5 + p)
            Circle().fill(index.isMultiple(of: 2) ? Color.white.opacity(0.8) : tint.opacity(0.75))
                .frame(width: radius * 2, height: radius * 2)
                .opacity(Double(1 - p * p))
                .position(x: center.x + side * track.size * 0.18 * CGFloat(index) * p,
                          y: center.y - track.size * 0.7 * p - CGFloat(index) * 1.5)
        }
    }

    @ViewBuilder
    private func classicBurst(_ at: NotchMascotIslandPlay.BurstAt, center: CGPoint, track: NotchMascotTrack,
                              look: NotchMascotLook, p: CGFloat) -> some View {
        ForEach(0..<6, id: \.self) { index in
            let angle = Double(index) / 6 * 2 * .pi - .pi / 2 + 0.3
            let reach = track.size * (0.35 + 0.45 * p)
            let rise = at.burst == .hearts ? track.size * 0.4 * p : 0
            particle(at.burst, index: index, size: max(3, track.size * 0.2), look: look)
                .opacity(Double(1 - p * p))
                .position(x: center.x + CGFloat(cos(angle)) * reach,
                          y: center.y + CGFloat(sin(angle)) * reach * 0.55 - rise)
        }
    }

    // MARK: Marker

    /// An arcade marker rising over one of them, lit in pixels.
    @ViewBuilder
    private func marking(_ event: NotchMascotIslandMarkerEvent, now: CFTimeInterval) -> some View {
        let progress = (now - event.start) / NotchMascotIslandPlay.markerLength
        if progress >= 0, progress <= 1 {
            let track = event.marker.onLeader ? leader : friend
            let look = event.marker.onLeader ? leaderLook : friendLook
            let p = CGFloat(progress)
            let cell = max(0.9, track.size * 0.065)
            let size = NotchMascotRPGShapes.pixelSize(event.marker.text, cell: cell)
            let top = track.baseline - track.size * 0.8 + NotchMascotGeometry.figureOffset(look) * track.size
            let lift = track.size * 0.35 * p
            let pop = p < 0.2 ? 0.4 + 3 * p : 1
            NotchMascotPixelText(text: event.marker.text, cell: cell)
                .frame(width: size.width + cell, height: size.height + cell)
                .scaleEffect(pop)
                .opacity(p < 0.1 ? Double(p / 0.1) : (p > 0.75 ? Double(max(0, (1 - p) / 0.25)) : 1))
                .position(x: min(max(track.rest, size.width / 2 + 1), max(size.width / 2 + 1, track.width - size.width / 2 - 1)),
                          y: max(size.height / 2, top - lift))
        }
    }

    @ViewBuilder
    private func particle(_ burst: NotchMascotIslandPlay.Burst, index: Int, size: CGFloat,
                          look: NotchMascotLook) -> some View {
        switch burst {
        case .confetti:
            let colors: [UInt32] = [0xFF5E8A, 0xFFD23F, 0x6C8CFF, 0x3FB8AF, 0xFF8C2B, 0xB57CFF]
            Rectangle().fill(Color(hex: colors[index % colors.count]))
                .frame(width: size * 0.6, height: size)
                .rotationEffect(.degrees(Double(index) * 47))
        case .sparkles: symbol("sparkle", size: size, color: index % 2 == 0 ? Color(hex: 0xFFE27A) : .white)
        case .hearts: symbol("heart.fill", size: size, color: Color(hex: 0xFF5E8A))
        case .magic: symbol("sparkles", size: size, color: Self.color(NotchMascotPlay.energy(for: look)))
        case .coins, .smoke, .door: EmptyView()
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Parts drawn in a square of `side` points, y growing downward.
struct NotchMascotPartsView: View {
    let parts: [NotchMascotWearablePart]
    let side: CGFloat

    var body: some View {
        Canvas { context, _ in
            for part in parts {
                let path = Path(part.path)
                if let fill = part.fill { context.fill(path, with: .color(Color(cgColor: fill))) }
                if let stroke = part.stroke, part.lineWidth > 0 {
                    context.stroke(path, with: .color(Color(cgColor: stroke)),
                                   style: StrokeStyle(lineWidth: part.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: side, height: side)
    }
}

/// An arcade marker lit in pixels, with a shadow a pixel below.
struct NotchMascotPixelText: View {
    let text: String
    let cell: CGFloat

    var body: some View {
        Canvas { context, _ in
            let path = Path(NotchMascotRPGShapes.pixelPath(text, cell: cell))
            context.fill(path.offsetBy(dx: cell * 0.6, dy: cell * 0.6), with: .color(.black.opacity(0.7)))
            context.fill(path, with: .color(Color(cgColor: NotchMascotRPGShapes.markerColor(text))))
        }
    }
}

