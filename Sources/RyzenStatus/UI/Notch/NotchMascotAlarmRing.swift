// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// An alarm ringing, as the companion shows it: it comes out onto the
/// desktop and holds up a big flashing sign with a rattling clock, the
/// time and what the alarm is for, while rings of sound come off it and
/// red light pulses at the screen's edges. It starts in a fright, gets
/// determined, then cross, and left ringing long enough it stomps and
/// shakes. Guests out with it run about in a panic. Stop and Snooze are on
/// the sign, and on the keys: Space or Return stops it, S snoozes.
final class NotchMascotAlarmRing {
    let alarm: NotchMascotAlarm
    var stop: (() -> Void)?
    var snooze: (() -> Void)?

    private var panel: NotchMascotAlarmPanel?
    private let layout = NotchMascotAlarmSignLayout()
    private let stage = NotchMascotPlayStage()
    private var holder: NotchMascotDesktop?
    private var timer: DispatchSourceTimer?
    private var started = CACurrentMediaTime()
    private var ended = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    static let board = CGSize(width: 300, height: 250)
    /// How long it rings before it gets determined, then cross, then stomps.
    static let determinedAfter: TimeInterval = 12
    static let angryAfter: TimeInterval = 25
    static let stompsAfter: TimeInterval = 40

    init(alarm: NotchMascotAlarm) {
        self.alarm = alarm
    }

    /// Brings the companion out if it may come, then puts the sign up.
    func begin() {
        let cameOut = NotchService.shared.bringMascotOutForAlarm()
        DispatchQueue.main.asyncAfter(deadline: .now() + (cameOut ? 0.9 : 0)) { [weak self] in
            guard let self, !self.ended else { return }
            self.show()
        }
    }

    private func show() {
        started = CACurrentMediaTime()
        let anchor = NotchMascotAlarmAnchor.current()
        if case .held(let holder) = anchor {
            self.holder = holder
            holder.beginPlay()
            holder.react(.surprised)
            holder.pullFace(.surprised, for: Self.determinedAfter)
            holder.emote(.interrobang)
        }
        let headroom: CGFloat = 0
        let place = anchor.placement(board: Self.board, headroom: headroom)
        layout.stickX = place.stickX
        layout.stickLength = place.stickLength
        layout.stickUp = place.stickUp
        let text = FeatureStrings.notchMascotAlarms(L10n.shared.language)
        let panel = NotchMascotAlarmPanel.make()
        let sign = NotchMascotAlarmHeldSign(layout: layout, headroom: headroom) {
            NotchMascotAlarmBoard(flashing: true, reduceMotion: reduceMotion) {
                NotchMascotAlarmRingFace(alarm: alarm, text: text, reduceMotion: reduceMotion,
                                         stop: { [weak self] in self?.stop?() },
                                         snooze: alarm.snooze ? { [weak self] in self?.snooze?() } : nil)
                    .frame(width: Self.board.width - 32, height: Self.board.height - 28)
            }
        }
        panel.contentView = NSHostingView(rootView: sign)
        panel.setFrame(place.frame, display: true)
        panel.onKey = { [weak self] event in
            guard let self else { return false }
            switch event.keyCode {
            case 49, 36, 76: self.stop?(); return true
            case 1 where self.alarm.snooze: self.snooze?(); return true
            default: return false
            }
        }
        panel.onCancel = { [weak self] in self?.stop?() }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        if let screen = holder?.playScreen ?? NSScreen.main, let canvas = stage.layer(over: screen) {
            NotchMascotAlarmArt.edgeGlow(in: canvas, bounds: canvas.bounds, reduceMotion: reduceMotion)
        }
        NotchService.shared.mascotAlarmCast?.gang.panic()
        startBeats()
    }

    /// Every beat it rings again: a ring of sound off its head, a hop, and
    /// as time goes by a crosser face, then stomps that shake it.
    private func startBeats() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.4, repeating: 1.6, leeway: .milliseconds(100))
        var beat = 0
        timer.setEventHandler { [weak self] in
            guard let self, !self.ended else { return }
            beat += 1
            self.ringBeat(beat, elapsed: CACurrentMediaTime() - self.started)
        }
        self.timer = timer
        timer.resume()
    }

    private func ringBeat(_ beat: Int, elapsed: TimeInterval) {
        guard let holder, holder.isOut else { return }
        if let screen = holder.playScreen, let canvas = stage.layer(over: screen) {
            NotchMascotAlarmArt.rings(in: canvas, at: stage.point(holder.head), radius: holder.figureSize * 1.8,
                                      count: reduceMotion ? 1 : 2)
        }
        if elapsed >= Self.determinedAfter, elapsed < Self.determinedAfter + 1.6 {
            holder.pullFace(.determined, for: Self.angryAfter - Self.determinedAfter)
        }
        if elapsed >= Self.angryAfter, elapsed < Self.angryAfter + 1.6 {
            holder.pullFace(.angry, for: 60)
            holder.emote(.anger)
        }
        guard !reduceMotion else { return }
        if elapsed >= Self.stompsAfter {
            holder.react(.panic)
            holder.cheatShake(amplitude: 4, duration: 0.6)
            if beat.isMultiple(of: 3) { holder.emote(.curse) }
        } else {
            holder.react(.bounce)
        }
        if beat.isMultiple(of: 6) { NotchService.shared.mascotAlarmCast?.gang.panic() }
    }

    /// Takes the sign down and lets the companion go back to its day:
    /// dozing off again when snoozed, relieved when stopped.
    func end(snoozed: Bool, rangOut: Bool = false) {
        guard !ended else { return }
        ended = true
        timer?.cancel(); timer = nil
        if let panel {
            self.panel = nil
            panel.onKey = nil
            panel.onCancel = nil
            panel.orderOut(nil)
            panel.close()
        }
        stage.close()
        guard let holder else { return }
        self.holder = nil
        if snoozed {
            holder.pullFace(.sleepy, for: 2.5)
            holder.emote(.ellipsis)
        } else {
            holder.pullFace(rangOut ? .bored : .happy, for: 2.5)
        }
        holder.endPlay(after: 1.5)
    }
}

/// The ringing sign's face: the rattling clock with sound coming off it,
/// what comics letter a ringing as, the time, the alarm's label, and the
/// buttons.
private struct NotchMascotAlarmRingFace: View {
    let alarm: NotchMascotAlarm
    let text: NotchMascotAlarmStrings
    let reduceMotion: Bool
    let stop: () -> Void
    let snooze: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                NotchMascotAlarmWaves(reduceMotion: reduceMotion, size: 40).scaleEffect(x: -1)
                NotchMascotAlarmClock(hour: alarm.hour, minute: alarm.minute, ringing: true, reduceMotion: reduceMotion,
                                      size: 62)
                NotchMascotAlarmWaves(reduceMotion: reduceMotion, size: 40)
            }
            Text(text.ring)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(NotchMascotAlarmPaint.alarmRed)
                .rotationEffect(.degrees(-4))
            Text(text.time(alarm, calendar: .autoupdatingCurrent))
                .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
            Text(alarm.label.isEmpty ? text.alarm : alarm.label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            HStack(spacing: 10) {
                if let snooze {
                    Button(text.snoozeButton(alarm.snoozeMinutes), action: snooze)
                }
                Button(text.stop, action: stop)
                    .keyboardShortcut(.defaultAction)
            }
            Text(text.keysHint)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.65)
        }
    }
}
