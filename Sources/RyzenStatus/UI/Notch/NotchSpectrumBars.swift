// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The island's visualizer: mirrored bars that grow up and down from the
/// middle line, the bass in the centre and the treble at both ends, each with
/// a small cap on its peak that rests a moment and sinks slowly. Live levels
/// move them when the player's sound is read; otherwise they keep a gentle
/// motion of their own. Drawn on the bars' own layers, never by SwiftUI.
struct NotchSpectrumBars: View {
    var isPlaying = true
    var height: CGFloat = 16
    var tint: Color = .white
    /// The spectrum's bands from 0 to 1, bass first, when the sound is read.
    var live: [Double]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchSpectrumBridge(animates: isPlaying && !reduceMotion, height: height, tint: NSColor(tint),
                            levels: isPlaying && !reduceMotion ? live : nil)
            .frame(width: NotchMusicVisualizerSupport.width, height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// The visualizer with the live spectrum attached. Only this small view
/// observes the audio service, so its updates never re-render the island.
struct NotchLiveSpectrumBars: View {
    var isPlaying = true
    var height: CGFloat = 16
    var tint: Color = .white
    @ObservedObject private var audio = NotchAudioLevelService.shared

    var body: some View {
        NotchSpectrumBars(isPlaying: isPlaying, height: height, tint: tint, live: audio.spectrum)
    }
}

private struct NotchSpectrumBridge: NSViewRepresentable {
    let animates: Bool
    let height: CGFloat
    let tint: NSColor
    let levels: [Double]?

    func makeNSView(context: Context) -> NotchSpectrumView { NotchSpectrumView() }

    func updateNSView(_ view: NotchSpectrumView, context: Context) {
        view.configure(animates: animates, height: height, tint: tint, levels: levels)
    }

    static func dismantleNSView(_ view: NotchSpectrumView, coordinator: ()) { view.stop() }
}

final class NotchSpectrumView: NSView {
    private typealias Support = NotchMusicVisualizerSupport
    private var bars: [CALayer] = []
    /// Two caps per bar, above and below the middle line.
    private var caps: [(top: CALayer, bottom: CALayer)] = []
    private var height: CGFloat = 0
    private var animates = false
    private var levels: [Double]?
    private var peaks = NotchAudioLevelSupport.PeakHold()
    private var lastStep: CFTimeInterval = 0
    private var motionStart: CFTimeInterval = 0
    private var visibilityObserver: NSObjectProtocol?
    private lazy var clock = NotchDecorativeClock { [weak self] time in self?.drawSynthetic(at: time) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(animates: Bool, height: CGFloat, tint: NSColor, levels: [Double]?) {
        self.animates = animates
        self.levels = levels
        self.height = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bars.count != Support.barCount {
            bars.forEach { $0.removeFromSuperlayer() }
            caps.forEach { $0.top.removeFromSuperlayer(); $0.bottom.removeFromSuperlayer() }
            bars = (0..<Support.barCount).map { _ in
                let bar = CALayer()
                layer?.addSublayer(bar)
                return bar
            }
            caps = (0..<Support.barCount).map { _ in
                let top = CALayer(), bottom = CALayer()
                layer?.addSublayer(top)
                layer?.addSublayer(bottom)
                return (top, bottom)
            }
        }
        // The bars wear the cover's tint, a little lighter towards the middle
        // where the bass is; the caps are nearly white.
        let center = Double(Support.barCount - 1) / 2
        for (index, bar) in bars.enumerated() {
            let fromMiddle = abs(Double(index) - center) / center
            bar.backgroundColor = (tint.blended(withFraction: 0.25 * (1 - fromMiddle), of: .white) ?? tint)
                .withAlphaComponent(0.95).cgColor
        }
        let capColor = (tint.blended(withFraction: 0.7, of: .white) ?? .white).withAlphaComponent(0.9).cgColor
        for cap in caps { cap.top.backgroundColor = capColor; cap.bottom.backgroundColor = capColor }
        CATransaction.commit()
        update()
    }

    func stop() {
        animates = false
        levels = nil
        update()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.update()
            }
        }
        update()
    }

    override func viewDidHide() { super.viewDidHide(); update() }
    override func viewDidUnhide() { super.viewDidUnhide(); update() }
    override func layout() { super.layout(); update() }

    private var moving: Bool {
        animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }

    private func update() {
        let moving = self.moving
        if moving, let live = levels, !live.isEmpty {
            clock.stop()
            draw(NotchAudioLevelSupport.mirrored(live, bars: Support.barCount), at: CACurrentMediaTime())
        } else if moving {
            if !clock.isRunning { motionStart = CACurrentMediaTime() }
            clock.start(in: self)
            drawSynthetic(at: CACurrentMediaTime())
        } else {
            clock.stop()
            peaks = NotchAudioLevelSupport.PeakHold()
            draw(Array(repeating: 0, count: Support.barCount), at: CACurrentMediaTime(), caps: false)
        }
    }

    /// Without the live sound: a slow ripple out from the middle, taller
    /// there, so the bars still read as music.
    private func drawSynthetic(at time: CFTimeInterval) {
        let elapsed = time - motionStart
        let center = Double(Support.barCount - 1) / 2
        let levels = (0..<Support.barCount).map { index -> Double in
            let fromMiddle = abs(Double(index) - center) / center
            let envelope = 0.35 + 0.55 * pow(1 - fromMiddle, 1.3)
            let beat = NotchDecorativeClock.swing(elapsed / 0.48)
            let ripple = NotchDecorativeClock.swing((elapsed + fromMiddle * 0.9) / (0.31 + fromMiddle * 0.12))
            return envelope * (0.25 + 0.45 * ripple + 0.3 * beat * (1 - fromMiddle))
        }
        draw(levels, at: time)
    }

    private func draw(_ levels: [Double], at time: CFTimeInterval, caps showsCaps: Bool = true) {
        guard bars.count == levels.count else { return }
        let step = lastStep > 0 ? min(0.1, max(0, time - lastStep)) : 1 / 30
        lastStep = time
        let peaks = self.peaks.next(levels, at: time, step: step)
        let width = Support.barWidth
        let mid = bounds.midY
        let capHeight: CGFloat = 1.2
        let capGap: CGFloat = 1.4
        // Room above and below the middle line for half a bar and its cap.
        let reach = max(width, height - 2 * (capHeight + capGap))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in bars.indices {
            let level = min(1, max(0, levels[index]))
            let barHeight = max(width, reach * CGFloat(0.08 + 0.92 * level))
            let x = CGFloat(index) * (width + Support.barGap) + width / 2
            let bar = bars[index]
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: barHeight)
            bar.position = CGPoint(x: x, y: mid)
            bar.cornerRadius = width / 2
            let peakHeight = max(width, reach * CGFloat(0.08 + 0.92 * min(1, max(0, peaks[index]))))
            let offset = peakHeight / 2 + capGap + capHeight / 2
            for (cap, sign) in [(caps[index].top, CGFloat(1)), (caps[index].bottom, CGFloat(-1))] {
                cap.bounds = CGRect(x: 0, y: 0, width: width, height: capHeight)
                cap.position = CGPoint(x: x, y: mid + sign * offset)
                cap.cornerRadius = capHeight / 2
                cap.opacity = showsCaps && peaks[index] > 0.12 ? 1 : 0
            }
        }
        CATransaction.commit()
    }
}
