// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

// Generates all icon assets from the official artwork (Resources/Brand/logo.png):
// - the app iconset (black mark on a clean light squircle)
// - the menu bar template glyph (trimmed mark, 1x/2x)
// Usage: swift Tools/MakeIcon.swift <output-folder.iconset>
import AppKit

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let logoPath = projectDir.appendingPathComponent("Resources/Brand/logo.png").path

guard let logo = NSImage(contentsOfFile: logoPath),
      let logoTIFF = logo.tiffRepresentation,
      let logoRep = NSBitmapImageRep(data: logoTIFF)
else {
    print("could not load \(logoPath)")
    exit(1)
}

/// Bounding box of visible (non-transparent) pixels, so the mark can be
/// centered optically regardless of padding in the source file.
func contentBounds(of rep: NSBitmapImageRep) -> CGRect {
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX > minX, maxY > minY else {
        return CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = contentBounds(of: logoRep)
// NSImage draws bottom-up while colorAt() is top-down — flip Y for drawing.
let sourceRect = CGRect(x: bounds.minX,
                        y: CGFloat(logoRep.pixelsHigh) - bounds.maxY,
                        width: bounds.width,
                        height: bounds.height)

func bitmapCanvas(_ px: Int, _ py: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)
}

/// Draws the trimmed mark fitted into `target`, preserving aspect ratio.
func drawMark(into target: CGRect) {
    let scale = min(target.width / sourceRect.width, target.height / sourceRect.height)
    let size = CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
    let rect = CGRect(x: target.midX - size.width / 2,
                      y: target.midY - size.height / 2,
                      width: size.width, height: size.height)
    logo.draw(in: rect, from: sourceRect, operation: .sourceOver, fraction: 1,
              respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
}

// MARK: - App icon

func renderAppIcon(px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = bitmapCanvas(px, px), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Squircle on the standard macOS icon grid (~82% of the canvas).
    let inset = size * 0.097
    let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: bgRect, xRadius: bgRect.width * 0.225, yRadius: bgRect.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.99, alpha: 1),
        NSColor(calibratedWhite: 0.93, alpha: 1),
    ])?.draw(in: bgRect, angle: -90)
    drawMark(into: bgRect.insetBy(dx: bgRect.width * 0.115, dy: bgRect.height * 0.115))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Menu bar glyph (template)

func renderMenuBarIcon(scale: Int) -> Data? {
    // 20×14 pt canvas fits the wide mark nicely in a 24 pt menu bar.
    let width = 20 * scale, height = 14 * scale
    guard let rep = bitmapCanvas(width, height), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: 20, height: 14)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawMark(into: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}


try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in iconSizes {
    guard let data = renderAppIcon(px: px) else {
        print("failed to render \(name)")
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

for scale in [1, 2] {
    guard let data = renderMenuBarIcon(scale: scale) else {
        print("failed to render menu bar icon @\(scale)x")
        exit(1)
    }
    let suffix = scale == 1 ? "" : "@2x"
    try data.write(to: URL(fileURLWithPath: "\(outDir)/../MenuBarIcon\(suffix).png"))
}

// Trimmed mark for in-app use (panel header, onboarding, About).
let markWidth = 640
let markHeight = Int(CGFloat(markWidth) * sourceRect.height / sourceRect.width)
if let rep = bitmapCanvas(markWidth, markHeight), let ctx = NSGraphicsContext(bitmapImageRep: rep) {
    rep.size = NSSize(width: markWidth, height: markHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawMark(into: CGRect(x: 0, y: 0, width: CGFloat(markWidth), height: CGFloat(markHeight)))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(outDir)/../BrandMark.png"))
    }
}
print("iconset written to \(outDir)")
