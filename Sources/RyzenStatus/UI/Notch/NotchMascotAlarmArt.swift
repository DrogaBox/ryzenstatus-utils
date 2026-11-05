// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import QuartzCore
import SwiftUI

/// What an alarm draws over the desktop: the beacon and sign the companion
/// flashes to send the guests home, the rings of sound coming off it, and
/// the red light pulsing at the screen's edges while it rings. Each draws
/// into a layer whose y grows upward and takes itself away once done.
enum NotchMascotAlarmArt {
    static let red = CGColor(srgbRed: 0.93, green: 0.16, blue: 0.14, alpha: 1)
    static let amber = CGColor(srgbRed: 1, green: 0.78, blue: 0.16, alpha: 1)
    private static let ink = CGColor(srgbRed: 0.16, green: 0.1, blue: 0.06, alpha: 1)

    private static func scale(of parent: CALayer) -> CGFloat {
        parent.contentsScale > 0 ? parent.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// A siren's beacon on a sign that says `text`, popping up with its
    /// foot at `base` and `width` across, flashing red and amber with its
    /// light sweeping round, for `duration`. With Reduce Motion it only
    /// fades in and out, lit.
    static func siren(in parent: CALayer, at base: CGPoint, width: CGFloat, text: String, duration: TimeInterval,
                      reduceMotion: Bool) {
        let scale = scale(of: parent)
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: width, height: width * 1.05)
        holder.anchorPoint = CGPoint(x: 0.5, y: 0)
        holder.position = base
        // The post it stands on.
        let post = CALayer()
        post.frame = CGRect(x: width / 2 - width * 0.03, y: 0, width: width * 0.06, height: width * 0.3)
        post.backgroundColor = CGColor(srgbRed: 0.55, green: 0.36, blue: 0.2, alpha: 1)
        post.cornerRadius = width * 0.02
        holder.addSublayer(post)
        // The sign: red with a white rim, the words in white.
        let boardHeight = width * 0.36
        let board = CALayer()
        board.frame = CGRect(x: 0, y: width * 0.26, width: width, height: boardHeight)
        board.backgroundColor = red
        board.cornerRadius = width * 0.06
        board.borderColor = CGColor(gray: 1, alpha: 1)
        board.borderWidth = max(1.5, width * 0.025)
        board.shadowColor = CGColor(gray: 0, alpha: 1)
        board.shadowOpacity = 0.45
        board.shadowRadius = 4
        board.shadowOffset = CGSize(width: 0, height: -2)
        holder.addSublayer(board)
        let words = CATextLayer()
        let fontSize = min(boardHeight * 0.42, width * 1.5 / CGFloat(max(6, text.count)))
        words.string = text
        words.font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        words.fontSize = fontSize
        words.foregroundColor = CGColor(gray: 1, alpha: 1)
        words.alignmentMode = .center
        words.contentsScale = scale
        words.frame = CGRect(x: width * 0.04, y: (boardHeight - fontSize * 1.25) / 2, width: width * 0.92,
                             height: fontSize * 1.25)
        board.addSublayer(words)
        // The beacon on top: a dome on a base, and its light.
        let domeSize = width * 0.3
        let domeBase = CGPoint(x: width / 2, y: width * 0.26 + boardHeight)
        let foot = CALayer()
        foot.frame = CGRect(x: domeBase.x - domeSize * 0.6, y: domeBase.y - 1, width: domeSize * 1.2, height: domeSize * 0.22)
        foot.backgroundColor = CGColor(gray: 0.22, alpha: 1)
        foot.cornerRadius = domeSize * 0.06
        holder.addSublayer(foot)
        let dome = CAShapeLayer()
        let domeRect = CGRect(x: domeBase.x - domeSize / 2, y: domeBase.y + domeSize * 0.18, width: domeSize,
                              height: domeSize * 0.9)
        let domePath = CGMutablePath()
        domePath.move(to: CGPoint(x: domeRect.minX, y: domeRect.minY))
        domePath.addLine(to: CGPoint(x: domeRect.minX, y: domeRect.minY + domeRect.height * 0.45))
        domePath.addArc(center: CGPoint(x: domeRect.midX, y: domeRect.minY + domeRect.height * 0.45),
                        radius: domeRect.width / 2, startAngle: .pi, endAngle: 0, clockwise: true)
        domePath.addLine(to: CGPoint(x: domeRect.maxX, y: domeRect.minY))
        domePath.closeSubpath()
        dome.path = domePath
        dome.fillColor = red
        dome.strokeColor = ink
        dome.lineWidth = max(1, width * 0.012)
        dome.shadowColor = red
        dome.shadowOpacity = 1
        dome.shadowRadius = domeSize * 0.5
        dome.shadowOffset = .zero
        // A shine on the glass.
        let shine = CAShapeLayer()
        shine.path = CGPath(ellipseIn: CGRect(x: domeRect.minX + domeSize * 0.18, y: domeRect.minY + domeSize * 0.42,
                                              width: domeSize * 0.16, height: domeSize * 0.3), transform: nil)
        shine.fillColor = CGColor(gray: 1, alpha: 0.7)
        // The light sweeping round: two beams from the dome's middle.
        let beams = CAShapeLayer()
        let center = CGPoint(x: domeRect.midX, y: domeRect.minY + domeRect.height * 0.45)
        let reach = width * 0.95
        let beamPath = CGMutablePath()
        for side in [0.0, Double.pi] {
            beamPath.move(to: .zero)
            beamPath.addLine(to: CGPoint(x: reach * CGFloat(cos(side - 0.2)), y: reach * CGFloat(sin(side - 0.2))))
            beamPath.addLine(to: CGPoint(x: reach * CGFloat(cos(side + 0.2)), y: reach * CGFloat(sin(side + 0.2))))
            beamPath.closeSubpath()
        }
        beams.path = beamPath
        beams.bounds = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
        beams.position = center
        beams.fillColor = CGColor(srgbRed: 1, green: 0.3, blue: 0.2, alpha: 0.32)
        holder.insertSublayer(beams, at: 0)
        holder.addSublayer(dome)
        holder.addSublayer(shine)

        let now = CACurrentMediaTime()
        holder.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.06, 0.88, 1]
        fade.duration = duration
        fade.beginTime = now
        holder.add(fade, forKey: "show")
        if !reduceMotion {
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.1
            pop.toValue = 1
            pop.damping = 8
            pop.stiffness = 300
            pop.mass = 0.6
            pop.duration = pop.settlingDuration
            pop.beginTime = now
            holder.add(pop, forKey: "pop")
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 0.7
            spin.repeatCount = .infinity
            beams.add(spin, forKey: "sweep")
            let flash = CAKeyframeAnimation(keyPath: "backgroundColor")
            flash.values = [red, amber, red]
            flash.keyTimes = [0, 0.5, 1]
            flash.calculationMode = .discrete
            flash.duration = 0.5
            flash.repeatCount = .infinity
            board.add(flash, forKey: "flash")
            let glow = CAKeyframeAnimation(keyPath: "fillColor")
            glow.values = [red, amber, red]
            glow.keyTimes = [0, 0.5, 1]
            glow.calculationMode = .discrete
            glow.duration = 0.35
            glow.repeatCount = .infinity
            dome.add(glow, forKey: "flash")
            let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            shake.values = [0, 0.05, -0.05, 0.03, -0.03, 0]
            shake.duration = 0.45
            shake.repeatCount = .infinity
            shake.isAdditive = true
            board.add(shake, forKey: "shake")
        }
        parent.addSublayer(holder)
        NotchMascotPlayEffects.remove(holder, after: duration + 0.05)
    }

    /// Rings of sound spreading from `point` out to `radius` and fading,
    /// `count` of them one after another.
    static func rings(in parent: CALayer, at point: CGPoint, radius: CGFloat, color: CGColor = amber, count: Int = 3) {
        let now = CACurrentMediaTime()
        for index in 0..<count {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                               transform: nil)
            ring.position = point
            ring.fillColor = nil
            ring.strokeColor = color
            ring.lineWidth = max(1.5, radius * 0.05)
            ring.opacity = 0
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.25
            grow.toValue = 1
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0]
            fade.keyTimes = [0, 0.2, 1]
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 0.9
            group.beginTime = now + Double(index) * 0.22
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "ring")
            parent.addSublayer(ring)
            NotchMascotPlayEffects.remove(ring, after: 1 + Double(index) * 0.22)
        }
    }

    /// The red light of an alarm pulsing along the four edges of `bounds`,
    /// until the layer is cleared away. Still and faint with Reduce Motion.
    static func edgeGlow(in parent: CALayer, bounds: CGRect, reduceMotion: Bool) {
        let depth = min(bounds.width, bounds.height) * 0.09
        let holder = CALayer()
        holder.frame = bounds
        holder.name = "alarm.edges"
        let clear = CGColor(srgbRed: 0.93, green: 0.16, blue: 0.14, alpha: 0)
        let edges: [(CGRect, CGPoint, CGPoint)] = [
            (CGRect(x: 0, y: 0, width: bounds.width, height: depth), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
            (CGRect(x: 0, y: bounds.height - depth, width: bounds.width, height: depth), CGPoint(x: 0.5, y: 1),
             CGPoint(x: 0.5, y: 0)),
            (CGRect(x: 0, y: 0, width: depth, height: bounds.height), CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
            (CGRect(x: bounds.width - depth, y: 0, width: depth, height: bounds.height), CGPoint(x: 1, y: 0.5),
             CGPoint(x: 0, y: 0.5)),
        ]
        for (frame, start, end) in edges {
            let gradient = CAGradientLayer()
            gradient.frame = frame
            gradient.colors = [red, clear]
            gradient.startPoint = start
            gradient.endPoint = end
            holder.addSublayer(gradient)
        }
        holder.opacity = reduceMotion ? 0.25 : 0
        if !reduceMotion {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0.1, 0.55, 0.1]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.duration = 0.9
            pulse.repeatCount = .infinity
            holder.add(pulse, forKey: "pulse")
        }
        parent.addSublayer(holder)
    }
}

// MARK: The signs

/// The colours of the cardboard the signs are cut from.
enum NotchMascotAlarmPaint {
    static let card = Color(red: 0.89, green: 0.76, blue: 0.56)
    static let cardDark = Color(red: 0.82, green: 0.66, blue: 0.43)
    static let edge = Color(red: 0.55, green: 0.38, blue: 0.2)
    static let ink = Color(red: 0.23, green: 0.15, blue: 0.08)
    static let wood = Color(red: 0.55, green: 0.35, blue: 0.18)
    static let woodLight = Color(red: 0.7, green: 0.48, blue: 0.27)
    static let tape = Color(white: 1, opacity: 0.55)
    static let alarmRed = Color(red: 0.88, green: 0.16, blue: 0.13)
    static let amber = Color(red: 1, green: 0.78, blue: 0.16)
}

/// A piece of cardboard with what it says on it: a torn-off look, its
/// ridges showing faintly, taped at the top corners. Ringing, its rim
/// flashes red and amber.
struct NotchMascotAlarmBoard<Content: View>: View {
    var flashing = false
    var reduceMotion = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .foregroundStyle(NotchMascotAlarmPaint.ink)
            .background { cardboard }
            .overlay { rim }
            .overlay(alignment: .topLeading) { tape(angle: -32).offset(x: -8, y: 2) }
            .overlay(alignment: .topTrailing) { tape(angle: 32).offset(x: 8, y: 2) }
            .environment(\.colorScheme, .light)
    }

    private var cardboard: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [NotchMascotAlarmPaint.card, NotchMascotAlarmPaint.cardDark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                // The corrugation under the paper, barely there.
                Canvas { context, size in
                    var y: CGFloat = 5
                    while y < size.height {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(NotchMascotAlarmPaint.edge.opacity(0.07)), lineWidth: 1)
                        y += 6
                    }
                }
                .clipShape(shape)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    @ViewBuilder
    private var rim: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if flashing && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                let lit = Int(context.date.timeIntervalSinceReferenceDate / 0.3).isMultiple(of: 2)
                shape.strokeBorder(lit ? NotchMascotAlarmPaint.alarmRed : NotchMascotAlarmPaint.amber, lineWidth: 5)
            }
        } else if flashing {
            shape.strokeBorder(NotchMascotAlarmPaint.alarmRed, lineWidth: 5)
        } else {
            shape.strokeBorder(NotchMascotAlarmPaint.edge, lineWidth: 2.5)
        }
    }

    private func tape(angle: Double) -> some View {
        Rectangle()
            .fill(NotchMascotAlarmPaint.tape)
            .frame(width: 38, height: 13)
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
    }
}

/// The wooden stick a sign is held up by, `length` long.
struct NotchMascotAlarmStick: View {
    let length: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [NotchMascotAlarmPaint.woodLight, NotchMascotAlarmPaint.wood],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(NotchMascotAlarmPaint.edge.opacity(0.8), lineWidth: 1))
            .frame(width: 8, height: max(0, length))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// An old wind-up alarm clock: two bells and the hammer between them, its
/// hands at `hour`:`minute`. Ringing, it rattles and the hammer flies.
struct NotchMascotAlarmClock: View {
    var hour: Int
    var minute: Int
    var ringing: Bool
    var reduceMotion: Bool
    var size: CGFloat = 54

    var body: some View {
        if ringing && !reduceMotion {
            TimelineView(.animation) { context in
                clock(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            clock(at: nil)
        }
    }

    private func clock(at time: TimeInterval?) -> some View {
        let rattle = time.map { sin($0 * 48) * 7 } ?? 0
        let hammer = time.map { sin($0 * 62) * 22 } ?? 0
        let hop = time.map { abs(sin($0 * 24)) * 2 } ?? 0
        return ZStack {
            // The two bells and the hammer between them.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.62)], startPoint: .top,
                                         endPoint: .bottom))
                    .overlay(Circle().strokeBorder(NotchMascotAlarmPaint.ink, lineWidth: 1.5))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: side * size * 0.3, y: -size * 0.42)
            }
            Capsule()
                .fill(NotchMascotAlarmPaint.ink)
                .frame(width: 2.5, height: size * 0.24)
                .offset(y: -size * 0.12)
                .rotationEffect(.degrees(hammer), anchor: .bottom)
                .offset(y: -size * 0.4)
            // The legs.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(NotchMascotAlarmPaint.ink)
                    .frame(width: 3, height: size * 0.18)
                    .rotationEffect(.degrees(side * 30))
                    .offset(x: side * size * 0.27, y: size * 0.4)
            }
            Circle()
                .fill(NotchMascotAlarmPaint.alarmRed)
                .overlay(Circle().strokeBorder(NotchMascotAlarmPaint.ink, lineWidth: 2))
                .frame(width: size * 0.82, height: size * 0.82)
            Circle()
                .fill(Color(white: 0.98))
                .frame(width: size * 0.62, height: size * 0.62)
            ForEach(0..<12, id: \.self) { tick in
                Capsule()
                    .fill(NotchMascotAlarmPaint.ink.opacity(0.7))
                    .frame(width: 1.4, height: tick % 3 == 0 ? size * 0.07 : size * 0.04)
                    .offset(y: -size * 0.26)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            hand(length: size * 0.16, width: 2.6, degrees: (Double(hour % 12) + Double(minute) / 60) * 30)
            hand(length: size * 0.24, width: 1.8, degrees: Double(minute) * 6)
            Circle().fill(NotchMascotAlarmPaint.ink).frame(width: 4, height: 4)
        }
        .frame(width: size * 1.1, height: size * 1.2)
        .rotationEffect(.degrees(rattle))
        .offset(y: -hop)
        .accessibilityHidden(true)
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
        Capsule()
            .fill(NotchMascotAlarmPaint.ink)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

/// Arcs of sound beside the ringing clock, spreading out one after another.
struct NotchMascotAlarmWaves: View {
    var reduceMotion: Bool
    var size: CGFloat = 54

    var body: some View {
        if reduceMotion {
            waves(phase: 0.5)
        } else {
            TimelineView(.animation) { context in
                waves(phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9)
            }
        }
    }

    private func waves(phase: Double) -> some View {
        HStack(spacing: size * 1.25) {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let share = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Arc(side: side)
                            .stroke(NotchMascotAlarmPaint.alarmRed.opacity(reduceMotion ? 0.7 : 1 - share),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: size * (0.3 + 0.5 * share), height: size * (0.6 + 0.6 * share))
                    }
                }
                .frame(width: size * 0.8, height: size * 1.2)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Arc: Shape {
        let side: Double

        func path(in rect: CGRect) -> Path {
            // Bowed away from the clock, its middle reaching the far side.
            var path = Path()
            let near = side < 0 ? rect.maxX : rect.minX
            let far = side < 0 ? rect.minX : rect.maxX
            path.move(to: CGPoint(x: near, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: 2 * far - near, y: rect.midY))
            return path
        }
    }
}
