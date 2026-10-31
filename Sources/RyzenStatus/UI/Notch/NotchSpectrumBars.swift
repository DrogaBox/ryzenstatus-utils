// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The island's visualizer, in the style chosen for it: retro bars up from
/// the floor, a hi-fi's lit blocks, bars mirrored around the middle line, or
/// a glowing wave. Bars carry a small cap on their peak that rests a moment
/// and sinks slowly. Live levels move them when the player's sound is read;
/// otherwise they keep a gentle motion of their own. Drawn on the view's own
/// layers, never by SwiftUI.
struct NotchSpectrumBars: View {
    var isPlaying = true
    var height: CGFloat = 16
    var tint: Color = .white
    /// The spectrum's bands from 0 to 1, bass first, when the sound is read.
    var live: [Double]? = nil
    /// A style of its own, as the settings' preview shows; otherwise the chosen one.
    var style: NotchMusicVisualizerStyle? = nil
    @AppStorage(DefaultsKey.notchMusicVisualizerStyle) private var chosenStyle = NotchMusicVisualizerStyle.retro.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchSpectrumBridge(animates: isPlaying && !reduceMotion, height: height, tint: NSColor(tint),
                            levels: isPlaying && !reduceMotion ? live : nil,
                            style: style ?? NotchMusicVisualizerStyle(rawValue: chosenStyle) ?? .retro)
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
    let style: NotchMusicVisualizerStyle

    func makeNSView(context: Context) -> NotchSpectrumView { NotchSpectrumView() }

    func updateNSView(_ view: NotchSpectrumView, context: Context) {
        view.configure(animates: animates, height: height, tint: tint, levels: levels, style: style)
    }

    static func dismantleNSView(_ view: NotchSpectrumView, coordinator: ()) { view.stop() }
}

final class NotchSpectrumView: NSView {
    private typealias Support = NotchMusicVisualizerSupport
    /// The bars' colours, seen only through the bars themselves.
    private let fill = CAGradientLayer()
    private let barMask = CALayer()
    /// The fill and the caps; the LED style cuts it into blocks.
    private let meter = CALayer()
    private let blocks = CAReplicatorLayer()
    private let block = CALayer()
    /// The wave's soft glow below its line, seen through the area under it.
    private let waveGlow = CAGradientLayer()
    private let waveArea = CAShapeLayer()
    private let waveLine = CAShapeLayer()
    private var bars: [CALayer] = []
    /// Two caps per bar; the one below the middle line only for the mirror.
    private var caps: [(top: CALayer, bottom: CALayer)] = []
    private var built = false
    private var style = NotchMusicVisualizerStyle.retro
    private var height: CGFloat = 0
    private var animates = false
    private var levels: [Double]?
    private var peaks = NotchAudioLevelSupport.PeakHold()
    private var lastStep: CFTimeInterval = 0
    private var motionStart: CFTimeInterval = 0
    private var visibilityObserver: NSObjectProtocol?
    private lazy var clock = NotchDecorativeClock { [weak self] time in self?.drawSynthetic(at: time) }

    /// A lit block and the dark line under it, for the LED style.
    private static let blockHeight: CGFloat = 2
    private static let blockGap: CGFloat = 1
    private static var blockPitch: CGFloat { blockHeight + blockGap }

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

    private func build() {
        guard !built, let layer else { return }
        built = true
        layer.addSublayer(meter)
        meter.addSublayer(fill)
        fill.mask = barMask
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        block.backgroundColor = NSColor.black.cgColor
        blocks.addSublayer(block)
        layer.addSublayer(waveGlow)
        waveGlow.mask = waveArea
        waveGlow.startPoint = CGPoint(x: 0.5, y: 0)
        waveGlow.endPoint = CGPoint(x: 0.5, y: 1)
        waveArea.fillColor = NSColor.black.cgColor
        layer.addSublayer(waveLine)
        waveLine.fillColor = nil
        waveLine.lineWidth = 1.6
        waveLine.lineCap = .round
        waveLine.lineJoin = .round
        waveLine.shadowOffset = .zero
        waveLine.shadowRadius = 2.5
        waveLine.shadowOpacity = 0.9
        bars = (0..<Support.barCount).map { _ in
            let bar = CALayer()
            bar.backgroundColor = NSColor.black.cgColor
            barMask.addSublayer(bar)
            return bar
        }
        caps = (0..<Support.barCount).map { _ in
            let top = CALayer(), bottom = CALayer()
            meter.addSublayer(top)
            meter.addSublayer(bottom)
            return (top, bottom)
        }
    }

    func configure(animates: Bool, height: CGFloat, tint: NSColor, levels: [Double]?, style: NotchMusicVisualizerStyle) {
        self.animates = animates
        self.levels = levels
        self.height = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        build()
        if style != self.style { peaks = NotchAudioLevelSupport.PeakHold() }
        self.style = style
        let tint = tint.usingColorSpace(.sRGB) ?? tint
        let lighter = { (fraction: CGFloat) in (tint.blended(withFraction: fraction, of: .white) ?? tint) }
        let capColor: NSColor
        switch style {
        case .retro:
            // The classic player's meter: green at the floor, red at the top.
            fill.colors = [NSColor(srgbRed: 0.10, green: 0.78, blue: 0.20, alpha: 1),
                           NSColor(srgbRed: 0.55, green: 0.86, blue: 0.12, alpha: 1),
                           NSColor(srgbRed: 0.98, green: 0.86, blue: 0.10, alpha: 1),
                           NSColor(srgbRed: 1.00, green: 0.52, blue: 0.08, alpha: 1),
                           NSColor(srgbRed: 0.95, green: 0.16, blue: 0.10, alpha: 1)].map(\.cgColor)
            fill.locations = [0, 0.35, 0.6, 0.8, 1]
            capColor = NSColor(white: 0.82, alpha: 1)
        case .led:
            fill.colors = [tint, tint, lighter(0.45)].map { $0.withAlphaComponent(0.95).cgColor }
            fill.locations = [0, 0.55, 1]
            capColor = lighter(0.65)
        case .mirror:
            // A little lighter at the middle line, where the bass is.
            fill.colors = [tint, lighter(0.25), tint].map { $0.withAlphaComponent(0.95).cgColor }
            fill.locations = [0, 0.5, 1]
            capColor = lighter(0.7).withAlphaComponent(0.9)
        case .wave:
            capColor = .clear
        }
        for cap in caps { cap.top.backgroundColor = capColor.cgColor; cap.bottom.backgroundColor = capColor.cgColor }
        waveLine.strokeColor = lighter(0.35).cgColor
        waveLine.shadowColor = tint.cgColor
        waveGlow.colors = [tint.withAlphaComponent(0.05).cgColor, tint.withAlphaComponent(0.5).cgColor]
        meter.isHidden = style == .wave
        waveGlow.isHidden = style != .wave
        waveLine.isHidden = style != .wave
        meter.mask = style == .led ? blocks : nil
        CATransaction.commit()
        layoutLayers()
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
    override func layout() { super.layout(); layoutLayers(); update() }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [meter, fill, barMask, blocks, waveGlow, waveArea, waveLine] as [CALayer] {
            layer.frame = bounds
        }
        block.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.blockHeight)
        blocks.instanceCount = Int(bounds.height / Self.blockPitch) + 1
        blocks.instanceTransform = CATransform3DMakeTranslation(0, Self.blockPitch, 0)
        CATransaction.commit()
    }

    private var moving: Bool {
        animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }

    private func update() {
        let moving = self.moving
        if moving, let live = levels, !live.isEmpty {
            clock.stop()
            let shown = style == .mirror ? NotchAudioLevelSupport.mirrored(live, bars: Support.barCount)
                : NotchAudioLevelSupport.spread(live, bars: Support.barCount)
            draw(shown, at: CACurrentMediaTime())
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

    /// Without the live sound the bars still read as music: for the mirror,
    /// a slow ripple out from the middle, taller there; otherwise a ripple
    /// running from the bass on the left, which stands tallest.
    private func drawSynthetic(at time: CFTimeInterval) {
        let elapsed = time - motionStart
        let count = Support.barCount
        let beat = NotchDecorativeClock.swing(elapsed / 0.48)
        let levels = (0..<count).map { index -> Double in
            if style == .mirror {
                let center = Double(count - 1) / 2
                let fromMiddle = abs(Double(index) - center) / center
                let envelope = 0.35 + 0.55 * pow(1 - fromMiddle, 1.3)
                let ripple = NotchDecorativeClock.swing((elapsed + fromMiddle * 0.9) / (0.31 + fromMiddle * 0.12))
                return envelope * (0.25 + 0.45 * ripple + 0.3 * beat * (1 - fromMiddle))
            }
            let fromLeft = Double(index) / Double(count - 1)
            let envelope = 0.4 + 0.5 * pow(1 - fromLeft, 1.2)
            let ripple = NotchDecorativeClock.swing((elapsed + fromLeft * 1.3) / (0.27 + fromLeft * 0.1))
            let flicker = NotchDecorativeClock.swing((elapsed * 1.7 + Double(index) * 0.37) / 0.21)
            return envelope * (0.2 + 0.4 * ripple + 0.25 * beat * (1 - fromLeft) + 0.15 * flicker)
        }
        draw(levels, at: time)
    }

    private func draw(_ levels: [Double], at time: CFTimeInterval, caps showsCaps: Bool = true) {
        guard bars.count == levels.count else { return }
        let step = lastStep > 0 ? min(0.1, max(0, time - lastStep)) : 1 / 30
        lastStep = time
        let levels = levels.map { min(1, max(0, $0)) }
        let peaks = self.peaks.next(levels, at: time, step: step).map { min(1, max(0, $0)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch style {
        case .mirror: drawMirror(levels, peaks: peaks, caps: showsCaps)
        case .retro: drawRetro(levels, peaks: peaks, caps: showsCaps)
        case .led: drawLED(levels, peaks: peaks, caps: showsCaps)
        case .wave: drawWave(levels)
        }
        CATransaction.commit()
    }

    private func barX(_ index: Int) -> CGFloat {
        CGFloat(index) * (Support.barWidth + Support.barGap)
    }

    private func drawMirror(_ levels: [Double], peaks: [Double], caps showsCaps: Bool) {
        let width = Support.barWidth
        let mid = bounds.midY
        let capHeight: CGFloat = 1.2
        let capGap: CGFloat = 1.4
        // Room above and below the middle line for half a bar and its cap.
        let reach = max(width, height - 2 * (capHeight + capGap))
        for index in bars.indices {
            let barHeight = max(width, reach * CGFloat(0.08 + 0.92 * levels[index]))
            let x = barX(index) + width / 2
            let bar = bars[index]
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: barHeight)
            bar.position = CGPoint(x: x, y: mid)
            bar.cornerRadius = width / 2
            let peakHeight = max(width, reach * CGFloat(0.08 + 0.92 * peaks[index]))
            let offset = peakHeight / 2 + capGap + capHeight / 2
            for (cap, sign) in [(caps[index].top, CGFloat(1)), (caps[index].bottom, CGFloat(-1))] {
                cap.bounds = CGRect(x: 0, y: 0, width: width, height: capHeight)
                cap.position = CGPoint(x: x, y: mid + sign * offset)
                cap.cornerRadius = capHeight / 2
                cap.opacity = showsCaps && peaks[index] > 0.12 ? 1 : 0
            }
        }
    }

    private func drawRetro(_ levels: [Double], peaks: [Double], caps showsCaps: Bool) {
        let width = Support.barWidth
        let capHeight: CGFloat = 1.2
        let capGap: CGFloat = 1
        let reach = max(1, bounds.height - capHeight - capGap)
        for index in bars.indices {
            let x = barX(index)
            let bar = bars[index]
            bar.frame = CGRect(x: x, y: 0, width: width, height: max(1, reach * CGFloat(levels[index])))
            bar.cornerRadius = 0.5
            let cap = caps[index].top
            cap.frame = CGRect(x: x, y: max(1, reach * CGFloat(peaks[index])) + capGap, width: width, height: capHeight)
            cap.cornerRadius = 0
            cap.opacity = showsCaps && peaks[index] > 0.04 ? 1 : 0
            caps[index].bottom.opacity = 0
        }
    }

    private func drawLED(_ levels: [Double], peaks: [Double], caps showsCaps: Bool) {
        let width = Support.barWidth
        let pitch = Self.blockPitch
        let count = max(2, Int((bounds.height + Self.blockGap) / pitch))
        // The top block stays free for the floating peak.
        let room = Double(count - 1)
        for index in bars.indices {
            let x = barX(index)
            // The bottom block always glows, as a hi-fi's does at rest.
            let lit = max(1, Int((levels[index] * room).rounded(.up)))
            let bar = bars[index]
            bar.frame = CGRect(x: x, y: 0, width: width, height: CGFloat(lit) * pitch)
            bar.cornerRadius = 0
            let peak = Int((peaks[index] * room).rounded(.up))
            let cap = caps[index].top
            cap.frame = CGRect(x: x, y: CGFloat(max(peak, lit)) * pitch, width: width, height: Self.blockHeight)
            cap.cornerRadius = 0
            cap.opacity = showsCaps && peak >= lit && peak > 1 ? 1 : 0
            caps[index].bottom.opacity = 0
        }
    }

    /// One smooth line through the bars' levels, its area filled below.
    private func drawWave(_ levels: [Double]) {
        let floor: CGFloat = 1.5
        let reach = max(1, bounds.height - floor - 3)
        var points = levels.indices.map { index in
            CGPoint(x: barX(index) + Support.barWidth / 2, y: floor + reach * CGFloat(levels[index]))
        }
        guard let first = points.first, let last = points.last else { return }
        points.insert(CGPoint(x: bounds.minX, y: first.y), at: 0)
        points.append(CGPoint(x: bounds.maxX, y: last.y))
        let line = CGMutablePath()
        line.move(to: points[0])
        // Catmull-Rom through the points, kept inside the view.
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(points.count - 1, index + 2)]
            let clamp = { (y: CGFloat) in min(self.bounds.height - 1, max(floor, y)) }
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: clamp(p1.y + (p2.y - p0.y) / 6))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: clamp(p2.y - (p3.y - p1.y) / 6))
            line.addCurve(to: p2, control1: c1, control2: c2)
        }
        let area = line.mutableCopy() ?? CGMutablePath()
        area.addLine(to: CGPoint(x: bounds.maxX, y: 0))
        area.addLine(to: CGPoint(x: bounds.minX, y: 0))
        area.closeSubpath()
        waveLine.path = line
        // Without a shadow path Core Animation renders the line offscreen
        // every frame to find the shadow's shape.
        waveLine.shadowPath = line.copy(strokingWithWidth: waveLine.lineWidth, lineCap: .round,
                                        lineJoin: .round, miterLimit: 10)
        waveArea.path = area
    }
}
