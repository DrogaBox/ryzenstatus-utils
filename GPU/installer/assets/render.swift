// Regenerate AppIcon.icns: swift installer/assets/render.swift /tmp/ic && mkdir -p /tmp/ic/AppIcon.iconset && for s in 16 32 128 256 512; do sips -z $s $s /tmp/ic/icon-1024.png --out /tmp/ic/AppIcon.iconset/icon_${s}x${s}.png; sips -z $((s*2)) $((s*2)) /tmp/ic/icon-1024.png --out /tmp/ic/AppIcon.iconset/icon_${s}x${s}@2x.png; done && iconutil -c icns /tmp/ic/AppIcon.iconset -o installer/assets/AppIcon.icns
// Renders the app icon master and the DMG window background.
// Usage: render <output-dir>
import AppKit

func png(_ w: Int, _ h: Int, _ path: String, _ draw: (CGFloat) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(w))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) {
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: a)
    str.draw(at: NSPoint(x: x - str.size().width / 2, y: y))
}

let out = CommandLine.arguments[1]

// Icon: same pink/purple bolt as the app's header, on the 824/1024 macOS icon grid.
png(1024, 1024, out + "/icon-1024.png") { _ in
    let r = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
    NSGradient(starting: .systemPink, ending: .systemPurple)!.draw(in: path, angle: -45)
    let cfg = NSImage.SymbolConfiguration(pointSize: 460, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let s = bolt.size
    bolt.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))
}

// DMG background, 640x420 points, drawn at 1x and 2x.
for (scale, name) in [(1, "dmg-bg.png"), (2, "dmg-bg@2x.png")] {
    png(640 * scale, 420 * scale, out + "/" + name) { w in
        let k = NSAffineTransform()
        k.scale(by: w / 640)
        k.concat()
        NSGradient(starting: NSColor(white: 0.99, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: 640, height: 420), angle: -90)
        text("AMD VCN Video Decoders", 320, 366, 22, .bold, NSColor(white: 0.1, alpha: 1))
        text("Hardware AV1 + VP9 for Safari & Chrome", 320, 342, 13, .regular, NSColor(white: 0.35, alpha: 1))
        // Arrow between the two icons, which sit 200 points from the top of the window.
        let arrow = NSBezierPath()
        arrow.lineWidth = 5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 270, y: 220))
        arrow.line(to: NSPoint(x: 370, y: 220))
        arrow.move(to: NSPoint(x: 352, y: 238))
        arrow.line(to: NSPoint(x: 370, y: 220))
        arrow.line(to: NSPoint(x: 352, y: 202))
        NSColor(white: 0.6, alpha: 1).setStroke()
        arrow.stroke()
        text("First launch: if macOS refuses to open it, go to", 320, 102, 12, .regular, NSColor(white: 0.3, alpha: 1))
        text("System Settings > Privacy & Security > Open Anyway", 320, 84, 12, .semibold, NSColor(white: 0.1, alpha: 1))
        text("Made by DrogaBox & Izzy  ·  github.com/DrogaBox  ·  github.com/wh0ami7", 320, 52, 11, .regular, NSColor(white: 0.4, alpha: 1))
    }
}
