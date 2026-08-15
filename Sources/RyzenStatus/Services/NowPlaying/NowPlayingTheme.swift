// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// The popup theme styles. `artworkAdaptive` tints everything from the
/// cover itself; the presets are fixed palettes that can still blend the
/// artwork's colors back in. Style list, preset values and the blend
/// mechanics mirror PlayStatus (MIT, github.com/nbolar/PlayStatus).
enum NowPlayingThemeStyle: String, CaseIterable {
    case artworkAdaptive
    case frosted
    case midnight
    case warmStudio
    case highContrast
    case graphite
}

struct NowPlayingThemeSpec {
    let tint: NSColor
    let palette: [NSColor]
    let contrastBoost: Double
}

/// Resolves the theme for a surface: the adaptive spec sampled from the
/// artwork, a preset spec, or a blend of both. Mechanism replicated from
/// PlayStatus (MIT): palette alphas scale with the artwork color intensity
/// (capped at 0.95), and presets interpolate toward the adaptive spec by
/// the blend amount.
enum NowPlayingThemeEngine {
    /// Small memo so per-body evaluations on the 2s poll cadence never
    /// resample the artwork bitmap. Main thread only, like the views.
    private static var specCache: [String: NowPlayingThemeSpec] = [:]
    private static var cacheOrder: [String] = []

    static func clearCache() {
        specCache.removeAll()
        cacheOrder.removeAll()
    }

    static func resolveTheme(style: NowPlayingThemeStyle,
                             image: NSImage?,
                             artworkColorIntensity: Double,
                             artworkBlend: Double,
                             cacheKey: String) -> NowPlayingThemeSpec {
        if let cached = specCache[cacheKey] {
            return cached
        }
        let spec = resolveThemeUncached(style: style,
                                        image: image,
                                        artworkColorIntensity: artworkColorIntensity,
                                        artworkBlend: artworkBlend)
        specCache[cacheKey] = spec
        cacheOrder.append(cacheKey)
        if cacheOrder.count > 48, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            specCache.removeValue(forKey: oldest)
        }
        return spec
    }

    private static func resolveThemeUncached(style: NowPlayingThemeStyle,
                                             image: NSImage?,
                                             artworkColorIntensity: Double,
                                             artworkBlend: Double) -> NowPlayingThemeSpec {
        let adaptiveSpec = adaptiveThemeSpec(from: image, artworkColorIntensity: artworkColorIntensity)
        switch style {
        case .artworkAdaptive:
            return adaptiveSpec
        case .frosted, .midnight, .warmStudio, .highContrast, .graphite:
            let presetSpec = presetThemeSpec(for: style, artworkColorIntensity: artworkColorIntensity)
            guard image != nil, artworkBlend > 0 else {
                return presetSpec
            }
            return blendedThemeSpec(base: presetSpec, artwork: adaptiveSpec, amount: artworkBlend)
        }
    }

    private static func controlContrastBoost(for color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = (0.2126 * Double(rgb.redComponent))
            + (0.7152 * Double(rgb.greenComponent))
            + (0.0722 * Double(rgb.blueComponent))
        return min(max((luminance - 0.56) / 0.30, 0), 1)
    }

    private static func adaptiveThemeSpec(from image: NSImage?,
                                          artworkColorIntensity: Double) -> NowPlayingThemeSpec {
        guard let image else {
            let neutral = NSColor.white
            return NowPlayingThemeSpec(
                tint: neutral,
                palette: [
                    themedColor(neutral, alpha: 0.24, intensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.20, intensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.16, intensity: artworkColorIntensity),
                    themedColor(neutral, alpha: 0.10, intensity: artworkColorIntensity),
                ],
                contrastBoost: controlContrastBoost(for: neutral)
            )
        }

        let average = image.nowPlayingAverageColor() ?? NSColor.white
        if let palette = image.nowPlayingPalette() {
            let opacities: [Double] = [0.62, 0.56, 0.48, 0.40, 0.32, 0.24, 0.18]
            return NowPlayingThemeSpec(
                tint: average,
                palette: zip(palette, opacities).map { color, alpha in
                    themedColor(color, alpha: alpha, intensity: artworkColorIntensity)
                },
                contrastBoost: controlContrastBoost(for: average)
            )
        }

        return NowPlayingThemeSpec(
            tint: average,
            palette: [
                themedColor(average, alpha: 0.55, intensity: artworkColorIntensity),
                themedColor(average, alpha: 0.45, intensity: artworkColorIntensity),
                themedColor(average, alpha: 0.34, intensity: artworkColorIntensity),
                themedColor(average, alpha: 0.24, intensity: artworkColorIntensity),
            ],
            contrastBoost: controlContrastBoost(for: average)
        )
    }

    private static func presetThemeSpec(for style: NowPlayingThemeStyle,
                                        artworkColorIntensity: Double) -> NowPlayingThemeSpec {
        switch style {
        case .artworkAdaptive:
            return adaptiveThemeSpec(from: nil, artworkColorIntensity: artworkColorIntensity)
        case .frosted:
            return NowPlayingThemeSpec(
                tint: rgb(0.90, 0.95, 1.00),
                palette: [
                    themedColor(rgb(0.97, 0.99, 1.00), alpha: 0.42, intensity: artworkColorIntensity),
                    themedColor(rgb(0.83, 0.90, 0.99), alpha: 0.34, intensity: artworkColorIntensity),
                    themedColor(rgb(0.73, 0.82, 0.95), alpha: 0.28, intensity: artworkColorIntensity),
                    themedColor(rgb(0.93, 0.95, 0.99), alpha: 0.22, intensity: artworkColorIntensity),
                ],
                contrastBoost: 0.72
            )
        case .midnight:
            return NowPlayingThemeSpec(
                tint: rgb(0.24, 0.30, 0.46),
                palette: [
                    themedColor(rgb(0.12, 0.15, 0.24), alpha: 0.74, intensity: artworkColorIntensity),
                    themedColor(rgb(0.17, 0.22, 0.34), alpha: 0.64, intensity: artworkColorIntensity),
                    themedColor(rgb(0.25, 0.30, 0.46), alpha: 0.56, intensity: artworkColorIntensity),
                    themedColor(rgb(0.34, 0.41, 0.57), alpha: 0.40, intensity: artworkColorIntensity),
                ],
                contrastBoost: 0.18
            )
        case .warmStudio:
            return NowPlayingThemeSpec(
                tint: rgb(0.82, 0.47, 0.24),
                palette: [
                    themedColor(rgb(0.24, 0.11, 0.08), alpha: 0.82, intensity: artworkColorIntensity),
                    themedColor(rgb(0.44, 0.19, 0.12), alpha: 0.64, intensity: artworkColorIntensity),
                    themedColor(rgb(0.78, 0.35, 0.18), alpha: 0.48, intensity: artworkColorIntensity),
                    themedColor(rgb(0.93, 0.64, 0.34), alpha: 0.30, intensity: artworkColorIntensity),
                ],
                contrastBoost: 0.44
            )
        case .highContrast:
            return NowPlayingThemeSpec(
                tint: rgb(0.92, 0.95, 0.99),
                palette: [
                    themedColor(rgb(0.04, 0.05, 0.08), alpha: 0.95, intensity: artworkColorIntensity),
                    themedColor(rgb(0.08, 0.10, 0.16), alpha: 0.86, intensity: artworkColorIntensity),
                    themedColor(rgb(0.18, 0.22, 0.30), alpha: 0.64, intensity: artworkColorIntensity),
                    themedColor(rgb(0.84, 0.90, 0.99), alpha: 0.22, intensity: artworkColorIntensity),
                ],
                contrastBoost: 1.0
            )
        case .graphite:
            return NowPlayingThemeSpec(
                tint: rgb(0.70, 0.73, 0.79),
                palette: [
                    themedColor(rgb(0.18, 0.19, 0.22), alpha: 0.84, intensity: artworkColorIntensity),
                    themedColor(rgb(0.28, 0.30, 0.34), alpha: 0.66, intensity: artworkColorIntensity),
                    themedColor(rgb(0.42, 0.45, 0.50), alpha: 0.46, intensity: artworkColorIntensity),
                    themedColor(rgb(0.62, 0.66, 0.72), alpha: 0.28, intensity: artworkColorIntensity),
                ],
                contrastBoost: 0.56
            )
        }
    }

    private static func blendedThemeSpec(base: NowPlayingThemeSpec,
                                         artwork: NowPlayingThemeSpec,
                                         amount: Double) -> NowPlayingThemeSpec {
        let clampedAmount = CGFloat(min(max(amount, 0), 1))
        let paletteCount = max(base.palette.count, artwork.palette.count)

        let blendedPalette: [NSColor] = (0..<paletteCount).map { index in
            let baseColor = index < base.palette.count ? base.palette[index] : (base.palette.last ?? base.tint)
            let artworkColor = index < artwork.palette.count ? artwork.palette[index] : (artwork.palette.last ?? artwork.tint)
            return blend(baseColor, artworkColor, ratio: clampedAmount)
        }

        return NowPlayingThemeSpec(
            tint: blend(base.tint, artwork.tint, ratio: clampedAmount),
            palette: blendedPalette,
            contrastBoost: base.contrastBoost + ((artwork.contrastBoost - base.contrastBoost) * Double(clampedAmount))
        )
    }

    private static func themedColor(_ color: NSColor, alpha: Double, intensity: Double) -> NSColor {
        let scaledAlpha = min(max(alpha * intensity, 0), 0.95)
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(calibratedRed: rgb.redComponent,
                       green: rgb.greenComponent,
                       blue: rgb.blueComponent,
                       alpha: CGFloat(scaledAlpha))
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    private static func blend(_ lhs: NSColor, _ rhs: NSColor, ratio: CGFloat) -> NSColor {
        let clampedRatio = min(max(ratio, 0), 1)
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return NSColor(
            calibratedRed: left.redComponent * (1 - clampedRatio) + right.redComponent * clampedRatio,
            green: left.greenComponent * (1 - clampedRatio) + right.greenComponent * clampedRatio,
            blue: left.blueComponent * (1 - clampedRatio) + right.blueComponent * clampedRatio,
            alpha: left.alphaComponent * (1 - clampedRatio) + right.alphaComponent * clampedRatio
        )
    }

    static func blended(_ lhs: NSColor, bottomRight rhs: NSColor) -> NSColor {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return NSColor(calibratedRed: (left.redComponent + right.redComponent) / 2,
                       green: (left.greenComponent + right.greenComponent) / 2,
                       blue: (left.blueComponent + right.blueComponent) / 2,
                       alpha: 1)
    }

    static func lifted(_ color: NSColor, saturation: CGFloat, brightness: CGFloat) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)
        return NSColor(calibratedHue: hue,
                       saturation: min(max(sat * saturation, 0), 1),
                       brightness: min(max(bright * brightness, 0), 1),
                       alpha: 1)
    }
}

// MARK: - Artwork color analysis

/// Dominant-color and palette sampling of a cover, replicated from
/// PlayStatus (MIT): a 32×32 alpha-weighted average with a small lift, and
/// a 40×40 quadrant/center/cross palette led by the most vibrant pixel
/// (saturation weighted by brightness).
extension NSImage {
    func nowPlayingAverageColor() -> NSColor? {
        let w = 32, h = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: w * 4, bitsPerPixel: 32)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: w, height: h),
             from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let alpha = Double(data[i + 3]) / 255.0
            r += (Double(data[i]) / 255.0) * alpha
            g += (Double(data[i + 1]) / 255.0) * alpha
            b += (Double(data[i + 2]) / 255.0) * alpha
            a += alpha
        }
        guard a > 0 else { return nil }
        r /= a; g /= a; b /= a
        // A small lift keeps dark covers from tinting surfaces to black.
        let lift = 0.12
        return NSColor(calibratedRed: CGFloat(min(1, r + lift)),
                       green: CGFloat(min(1, g + lift)),
                       blue: CGFloat(min(1, b + lift)),
                       alpha: 1.0)
    }

    func nowPlayingPalette() -> [NSColor]? {
        let w = 40, h = 40
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: w * 4, bitsPerPixel: 32)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: w, height: h),
             from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }

        func regionAverage(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> NSColor {
            var r = 0.0, g = 0.0, b = 0.0, a = 0.0
            for y in yRange {
                for x in xRange {
                    let idx = (min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)) * 4
                    let alpha = Double(data[idx + 3]) / 255.0
                    guard alpha > 0 else { continue }
                    r += (Double(data[idx]) / 255.0) * alpha
                    g += (Double(data[idx + 1]) / 255.0) * alpha
                    b += (Double(data[idx + 2]) / 255.0) * alpha
                    a += alpha
                }
            }
            guard a > 0 else { return NSColor(calibratedWhite: 0.5, alpha: 1) }
            return NSColor(calibratedRed: CGFloat(r / a),
                           green: CGFloat(g / a),
                           blue: CGFloat(b / a),
                           alpha: 1)
        }

        func vibrantColor() -> NSColor {
            var best = NSColor(calibratedWhite: 0.5, alpha: 1)
            var bestScore: CGFloat = -1
            for y in stride(from: 0, to: h, by: 2) {
                for x in stride(from: 0, to: w, by: 2) {
                    let idx = (y * w + x) * 4
                    let alpha = CGFloat(data[idx + 3]) / 255.0
                    guard alpha > 0.02 else { continue }
                    let color = NSColor(calibratedRed: CGFloat(data[idx]) / 255.0,
                                        green: CGFloat(data[idx + 1]) / 255.0,
                                        blue: CGFloat(data[idx + 2]) / 255.0,
                                        alpha: 1)
                    let rgb = color.usingColorSpace(.deviceRGB) ?? color
                    var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, aC: CGFloat = 0
                    rgb.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &aC)
                    // Prefer colors saturated and bright enough to tint a card.
                    let score = sat * (0.55 + (bright * 0.45))
                    if score > bestScore {
                        bestScore = score
                        best = color
                    }
                }
            }
            return best
        }

        let topLeft = regionAverage(xRange: 0...19, yRange: 0...19)
        let topRight = regionAverage(xRange: 20...39, yRange: 0...19)
        let bottomLeft = regionAverage(xRange: 0...19, yRange: 20...39)
        let bottomRight = regionAverage(xRange: 20...39, yRange: 20...39)
        let center = regionAverage(xRange: 12...27, yRange: 12...27)
        let cross = NowPlayingThemeEngine.blended(topRight, bottomRight: bottomLeft)
        let accent = vibrantColor()

        return [
            NowPlayingThemeEngine.lifted(accent, saturation: 1.45, brightness: 1.10),
            NowPlayingThemeEngine.lifted(center, saturation: 1.18, brightness: 1.10),
            NowPlayingThemeEngine.lifted(topLeft, saturation: 1.34, brightness: 1.06),
            NowPlayingThemeEngine.lifted(topRight, saturation: 1.28, brightness: 1.06),
            NowPlayingThemeEngine.lifted(cross, saturation: 1.20, brightness: 1.04),
            NowPlayingThemeEngine.lifted(bottomLeft, saturation: 1.22, brightness: 1.02),
            NowPlayingThemeEngine.lifted(bottomRight, saturation: 1.18, brightness: 1.00),
        ]
    }
}
