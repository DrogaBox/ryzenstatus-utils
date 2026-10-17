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
    let leader: NotchMascotTrack
    let friend: NotchMascotTrack
    let leaderLook: NotchMascotLook
    let friendLook: NotchMascotLook

    var body: some View {
        TimelineView(.animation) { _ in
            let now = CACurrentMediaTime()
            ZStack {
                if let flight { flying(flight, now: now) }
                if let burst { bursting(burst, now: now) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            let lift = min(leader.size * 0.42, max(2, leader.baseline - leader.ceiling - size / 2))
            let start = CGPoint(x: from.rest, y: from.baseline - from.size * 0.1)
            let end = CGPoint(x: to.rest, y: to.baseline - to.size * 0.1)
            let place = Self.place(progress: progress, from: start, to: end, lift: lift, falls: flight.falls,
                                   drop: leader.size * 0.5)
            thing(flight.thing, size: size, look: flight.fromLeader ? leaderLook : friendLook)
                .rotationEffect(.degrees(Self.spins(flight.thing) ? progress * 360 : 0))
                .opacity(place.opacity)
                .position(place.point)
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
        case .star, .ball, .coin, .cookie, .flower: return true
        case .heart, .note, .spark, .snowball: return false
        }
    }

    @ViewBuilder
    private func thing(_ thing: NotchMascotIslandPlay.Thing, size: CGFloat, look: NotchMascotLook) -> some View {
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
        let progress = (now - event.start) / NotchMascotIslandPlay.burstLength
        if progress >= 0, progress <= 1 {
            let track = event.burst.onLeader ? leader : friend
            let look = event.burst.onLeader ? leaderLook : friendLook
            let center = CGPoint(x: track.rest, y: track.baseline - track.size * 0.45)
            let p = CGFloat(progress)
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * 2 * .pi - .pi / 2 + 0.3
                let reach = track.size * (0.35 + 0.45 * p)
                let rise = event.burst.burst == .hearts ? track.size * 0.4 * p : 0
                particle(event.burst.burst, index: index, size: max(3, track.size * 0.2), look: look)
                    .opacity(Double(1 - p * p))
                    .position(x: center.x + CGFloat(cos(angle)) * reach,
                              y: center.y + CGFloat(sin(angle)) * reach * 0.55 - rise)
            }
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
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
