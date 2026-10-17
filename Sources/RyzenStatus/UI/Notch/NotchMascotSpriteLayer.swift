// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreText
import QuartzCore

/// The frames of a sprite sheet, cut once and shared by every companion drawn
/// from it: the island's, the perch's, the desktop's and the previews. Each
/// frame is its own image, so scaling one never reaches into the next cell.
/// A figure holding up a sign has its words written in the language the Mac
/// speaks, unless the sheet already letters them in it.
final class NotchMascotSpriteFrames {
    private static var cache: [String: NotchMascotSpriteFrames] = [:]
    private static var missing: Set<String> = []

    /// One image per frame, row by row in `NotchMascotSpriteState` order.
    let rows: [[CGImage]]

    /// The sheet's frames cut to `framing`, signs in `language`, or nil when
    /// its image is not in the app.
    static func frames(for sheet: NotchMascotSpriteSheet, framing: CGRect,
                       language: AppLanguage) -> NotchMascotSpriteFrames? {
        let signs = sheet.signs.flatMap { NotchMascotSpriteSigns.writes(language) ? $0 : nil }
        let resource = signs?.resource ?? sheet.resource
        let key = "\(resource) \(signs == nil ? "" : language.rawValue) "
            + "\(framing.minX) \(framing.minY) \(framing.width) \(framing.height)"
        if let cached = cache[key] { return cached }
        guard !missing.contains(resource) else { return nil }
        guard let frames = NotchMascotSpriteFrames(sheet: sheet, framing: framing, resource: resource, signs: signs,
                                                   words: FeatureStrings.notchMascotSign(language)) else {
            missing.insert(resource)
            return nil
        }
        cache[key] = frames
        return frames
    }

    private init?(sheet: NotchMascotSpriteSheet, framing: CGRect, resource: String, signs: NotchMascotSpriteSigns?,
                  words: NotchMascotSignStrings) {
        let url = Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Images")
            ?? Bundle.main.url(forResource: resource, withExtension: "png")
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        var rows: [[CGImage]] = []
        for state in NotchMascotSpriteState.allCases {
            let row = sheet.frames(for: state).compactMap { frame -> CGImage? in
                guard let cut = image.cropping(to: sheet.crop(state, column: frame.column, framing: framing)) else { return nil }
                guard let box = signs?.box(state, column: frame.column) else { return cut }
                return Self.letter(cut, text: words.text(for: state),
                                   in: box.offsetBy(dx: -framing.minX, dy: -framing.minY)) ?? cut
            }
            guard !row.isEmpty else { return nil }
            rows.append(row)
        }
        self.rows = rows
    }

    func images(_ state: NotchMascotSpriteState) -> [CGImage] { rows[state.rawValue] }

    // MARK: Lettering

    /// The dark brown of the comic's marker on cardboard.
    private static let ink = CGColor(srgbRed: 0.16, green: 0.10, blue: 0.07, alpha: 1)

    private static func font(_ size: CGFloat) -> CTFont {
        let base = NSFont.systemFont(ofSize: size, weight: .black)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return rounded as CTFont
    }

    private static func line(_ text: String, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(size), NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// `frame` with `text` written across the sign whose face is `box`, in
    /// pixels from the frame's top left: centred, a line to each break, as
    /// large as the face holds.
    private static func letter(_ frame: CGImage, text: String, in box: CGRect) -> CGImage? {
        let width = frame.width, height = frame.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The context's rows count up from the bottom.
        let face = CGRect(x: box.minX, y: CGFloat(height) - box.maxY, width: box.width, height: box.height)
        let area = face.insetBy(dx: face.width * 0.07, dy: face.height * 0.14)
        let lines = text.components(separatedBy: "\n")
        let row = area.height / CGFloat(lines.count)
        var size = row * 0.9
        let widest = lines.map { CGFloat(CTLineGetTypographicBounds(line($0, size: size), nil, nil, nil)) }.max() ?? 0
        if widest > area.width { size *= area.width / widest }
        for (index, text) in lines.enumerated() {
            let drawn = line(text, size: size)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(drawn, &ascent, &descent, nil))
            let middle = area.maxY - row * (CGFloat(index) + 0.5)
            context.textPosition = CGPoint(x: area.midX - lineWidth / 2, y: middle - (ascent - descent) / 2)
            CTLineDraw(drawn, context)
        }
        return context.makeImage()
    }
}

/// A sprite companion's figure. It keeps one row going for its mood, plays a
/// reaction's row over it for as long as the reaction lasts, and runs the
/// way a stroll takes it. Every frame is a Core Animation keyframe, so the
/// app runs nothing while it plays.
final class NotchMascotSpriteLayer: CALayer {
    private(set) var sheet: NotchMascotSpriteSheet?
    private var framing: CGRect?
    private var language: AppLanguage?
    private var frames: NotchMascotSpriteFrames?
    /// A bust fades out at its bottom, so it rises out of the island rather
    /// than ending in a cut. An image, so it stands the way the frames do.
    private let fade = CALayer()
    private var loopState: NotchMascotSpriteState = .idle
    private var loopSpeed: Float = 1

    override init() {
        super.init()
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(),
                   "transform": NSNull()]
        contentsGravity = .resizeAspect
        // Smooth when the island shrinks it, as the sheets are drawn far larger.
        minificationFilter = .trilinear
        magnificationFilter = .linear
        fade.contents = Self.fadeImage
        fade.contentsGravity = .resize
        fade.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    }

    /// Opaque down to the last fifth, then clear at the bottom, its first
    /// row on top as a frame's is.
    private static let fadeImage: CGImage? = {
        let height = 64
        guard let context = CGContext(data: nil, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        // The context's rows count up from the bottom.
        for row in 0..<height {
            let fromBottom = (CGFloat(row) + 0.5) / CGFloat(height)
            context.setAlpha(min(1, fromBottom / 0.22))
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
        }
        return context.makeImage()
    }()

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    /// Fits `sheet`'s figure into a box `size` points square, as tall as the
    /// box, standing on its bottom and centred across: all of it, or its bust
    /// when the box is small, its sign in the app's language. False when the
    /// sheet's image is not in the app.
    func configure(sheet: NotchMascotSpriteSheet, size: CGFloat, scale: CGFloat,
                   language: AppLanguage = L10n.shared.language) -> Bool {
        let framing = sheet.framing(for: size)
        guard let frames = NotchMascotSpriteFrames.frames(for: sheet, framing: framing, language: language)
        else { return false }
        let width = size * NotchMascotSpriteSheet.aspect(of: framing)
        frame = CGRect(x: (size - width) / 2, y: 0, width: width, height: size)
        contentsScale = scale
        let bust = framing != sheet.figure
        fade.frame = bounds
        mask = bust ? fade : nil
        if sheet != self.sheet || framing != self.framing || language != self.language {
            self.sheet = sheet
            self.framing = framing
            self.language = language
            self.frames = frames
            removeAllAnimations()
            startLoop()
        }
        return true
    }

    /// Keeps `state` going, at `speed`, under whatever plays over it.
    func loop(_ state: NotchMascotSpriteState, speed: Float = 1) {
        guard state != loopState || speed != loopSpeed else { return }
        loopState = state
        loopSpeed = speed
        startLoop()
    }

    /// Plays `state` over the mood's row for `duration` seconds, from the
    /// row's first frame.
    func perform(_ state: NotchMascotSpriteState, for duration: TimeInterval, beginTime: CFTimeInterval? = nil) {
        guard let animation = cycle(state, speed: 1) else { return }
        animation.beginTime = beginTime ?? CACurrentMediaTime()
        animation.repeatDuration = max(duration, animation.duration)
        add(animation, forKey: "perform")
    }

    /// Runs the way `path` takes it, from `start` on the media clock: to the
    /// right or the left while it moves, its idle while it stands.
    func walk(_ path: NotchMascotPath, start: CFTimeInterval, holdsEnd: Bool) {
        guard let frames, path.duration > 0, path.x.count == path.keyTimes.count, path.x.count > 1 else { return }
        let step = NotchMascotSpriteSheet.timing(.running).step
        var values: [CGImage] = []
        var keyTimes: [NSNumber] = []
        var counters: [NotchMascotSpriteState: Int] = [:]
        var time: TimeInterval = 0
        while time < path.duration {
            let dx = Self.x(at: time + step, in: path) - Self.x(at: time, in: path)
            let state = NotchMascotSpriteChoreography.walking(dx: dx)
            let row = frames.images(state)
            let index = counters[state, default: 0]
            counters[state] = index + 1
            values.append(row[index % row.count])
            keyTimes.append(NSNumber(value: time / path.duration))
            time += step
        }
        keyTimes.append(1)
        let walk = CAKeyframeAnimation(keyPath: "contents")
        walk.values = values
        walk.keyTimes = keyTimes
        walk.calculationMode = .discrete
        walk.duration = path.duration
        walk.beginTime = start
        if holdsEnd {
            walk.fillMode = .forwards
            walk.isRemovedOnCompletion = false
        }
        add(walk, forKey: "walk")
    }

    /// Runs on the spot toward `direction`, or stops with nil, for a body the
    /// desktop moves itself.
    func run(toward direction: CGFloat?) {
        guard let direction else { removeAnimation(forKey: "run"); return }
        guard let animation = cycle(direction > 0 ? .runRight : .runLeft, speed: 1) else { return }
        animation.repeatCount = .infinity
        add(animation, forKey: "run")
    }

    /// Takes off what plays over the mood's row.
    func clearOverlays() {
        for key in ["perform", "walk", "run"] { removeAnimation(forKey: key) }
    }

    private func startLoop() {
        guard let frames else { return }
        contents = frames.images(loopState).first
        guard let animation = cycle(loopState, speed: loopSpeed) else { return }
        animation.repeatCount = .infinity
        add(animation, forKey: "loop")
    }

    /// One pass of `state`'s row, each frame held for its time.
    private func cycle(_ state: NotchMascotSpriteState, speed: Float) -> CAKeyframeAnimation? {
        guard let sheet, let frames else { return nil }
        let timing = sheet.frames(for: state)
        let images = frames.images(state)
        guard !images.isEmpty, images.count == timing.count else { return nil }
        let total = timing.reduce(0) { $0 + $1.duration }
        var keyTimes: [NSNumber] = [0]
        var elapsed: TimeInterval = 0
        for frame in timing.dropLast() {
            elapsed += frame.duration
            keyTimes.append(NSNumber(value: elapsed / total))
        }
        keyTimes.append(1)
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images
        // Discrete keyframes take one time more than values: each frame's start, and the end.
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = total
        animation.speed = speed
        return animation
    }

    /// Where `path` has it `time` seconds in.
    private static func x(at time: TimeInterval, in path: NotchMascotPath) -> CGFloat {
        let share = min(1, max(0, time / path.duration))
        guard let upper = path.keyTimes.firstIndex(where: { $0 >= share }) else { return path.x.last ?? 0 }
        guard upper > 0 else { return path.x[0] }
        let lower = upper - 1
        let span = path.keyTimes[upper] - path.keyTimes[lower]
        let t = span > 0 ? CGFloat((share - path.keyTimes[lower]) / span) : 1
        return path.x[lower] + (path.x[upper] - path.x[lower]) * t
    }
}
