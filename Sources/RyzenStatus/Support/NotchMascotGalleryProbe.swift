// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

#if DEBUG
import AppKit
import QuartzCore

/// `--mascot-gallery <file.png>`: draws companions with the production rig,
/// each in a few colours and wearing a few things, on the island's black
/// and on a light desktop, and writes the sheet to `file.png`; `--styles`
/// and `--items` pick which. Only in debug
/// builds, for a look at a figure without running the app.
extension NotchPresentationProbe {
    static func mascotGalleryAndExit(to path: String) -> Never {
        let arguments = CommandLine.arguments
        let named = arguments.firstIndex(of: "--styles").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let styles = named.map { $0.split(separator: ",").compactMap { NotchMascotStyle(rawValue: String($0)) } }
            ?? [.hologram, .android]
        let palettes: [NotchMascotPalette] = [.lilac, .sky, .mint, .rose, .lemon, .pearl, .peach]
        // `--items a,b` draws just those things worn, each in its own colour.
        let items = arguments.firstIndex(of: "--items").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .map { $0.split(separator: ",").compactMap { NotchMascotAccessory(rawValue: String($0)) } }
        let looks: [(NotchMascotPalette, NotchMascotAccessory)] = items.map { worn in
            worn.enumerated().map { (palettes[$0.offset % palettes.count], $0.element) }
        } ?? [
            (.lilac, .none), (.sky, .none), (.mint, .topHat), (.rose, .glasses), (.lemon, .crown),
            (.pearl, .headphones), (.peach, .partyHat), (.sky, .witchHat), (.lilac, .scarf), (.mint, .bow),
        ]
        let cell: CGFloat = 160, scale: CGFloat = 2
        let width = Int(cell * CGFloat(looks.count) * scale), height = Int(cell * CGFloat(styles.count * 2) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { print("MASCOT GALLERY FAILED: no bitmap"); exit(1) }
        context.scaleBy(x: scale, y: scale)
        let rows = CGFloat(styles.count * 2)
        for (row, style) in styles.enumerated() {
            for band in 0..<2 {
                let top = CGFloat(row * 2 + band) * cell
                context.setFillColor(band == 0 ? CGColor(gray: 0, alpha: 1)
                                     : CGColor(srgbRed: 0.86, green: 0.89, blue: 0.94, alpha: 1))
                context.fill(CGRect(x: 0, y: (rows - 1) * cell - top, width: cell * CGFloat(looks.count), height: cell))
                for (column, item) in looks.enumerated() {
                    let rig = NotchMascotRig()
                    rig.configure(look: NotchMascotLook(style: style, shape: .ball, palette: item.0, accessory: item.1),
                                  size: cell * 0.8, contentsScale: scale)
                    rig.root.layoutIfNeeded()
                    context.saveGState()
                    // The rig lays out from the top, as in a flipped view.
                    context.translateBy(x: CGFloat(column) * cell + cell * 0.1, y: rows * cell - top - cell * 0.1)
                    context.scaleBy(x: 1, y: -1)
                    rig.root.render(in: context)
                    context.restoreGState()
                }
            }
        }
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? data.write(to: URL(fileURLWithPath: path))) != nil
        else { print("MASCOT GALLERY FAILED: could not write \(path)"); exit(1) }
        print("MASCOT GALLERY OK \(path)")
        exit(0)
    }
}
#endif
