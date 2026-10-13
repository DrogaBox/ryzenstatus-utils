// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import CoreImage
import SwiftUI

/// A dark cover on the island's black loses its edges and reads as a hole.
/// Its deepest shadows are lifted just off black, so the cover keeps its
/// outline; brighter covers, and their own midtones, stay as they are.
@MainActor
enum NotchArtworkLift {
    /// Average luminance under which a cover counts as dark.
    static let threshold = 0.22
    /// Where pure black lands once lifted.
    static let floor = 0.07

    /// The curve's points are display values, so it works in gamma-encoded
    /// sRGB rather than Core Image's default linear space.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])
    private static let cache: NSCache<NSImage, NSImage> = {
        let cache = NSCache<NSImage, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    static func image(for image: NSImage) -> NSImage {
        if let cached = cache.object(forKey: image) { return cached }
        let lifted = lift(image) ?? image
        cache.setObject(lifted, forKey: image)
        return lifted
    }

    /// The Rec. 709 luminance of the cover's average colour, read from a 1×1 downscale.
    static func averageLuminance(_ cgImage: CGImage) -> Double? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    private static func lift(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let luminance = averageLuminance(cgImage), luminance < threshold,
              let curve = CIFilter(name: "CIToneCurve") else { return nil }
        let input = CIImage(cgImage: cgImage)
        curve.setValue(input, forKey: kCIInputImageKey)
        // Only the shadows move; from the midtones up the curve is the identity.
        curve.setValue(CIVector(x: 0, y: floor), forKey: "inputPoint0")
        curve.setValue(CIVector(x: 0.12, y: 0.16), forKey: "inputPoint1")
        curve.setValue(CIVector(x: 0.3, y: 0.31), forKey: "inputPoint2")
        curve.setValue(CIVector(x: 0.6, y: 0.6), forKey: "inputPoint3")
        curve.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
        guard let output = curve.outputImage,
              let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: rendered, size: image.size)
    }
}

/// A new cover turns over like a card: the old one turns away to its edge,
/// then the new one turns in from the other side.
struct NotchArtworkFlip: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(opacity)
    }

    static let half = 0.16

    static var transition: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: NotchArtworkFlip(angle: -90, opacity: 0),
                                 identity: NotchArtworkFlip(angle: 0, opacity: 1))
                .animation(.easeOut(duration: half).delay(half)),
            removal: .modifier(active: NotchArtworkFlip(angle: 90, opacity: 0),
                               identity: NotchArtworkFlip(angle: 0, opacity: 1))
                .animation(.easeIn(duration: half)))
    }
}
