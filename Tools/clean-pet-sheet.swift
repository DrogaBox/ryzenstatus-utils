#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus
//
// Cleans a companion sprite sheet (8 columns of 192×208 cells) and writes it
// as a lossless PNG:
//   • colour under fully transparent pixels is cleared, so no hidden
//     background bleeds into the edge when the sheet is scaled;
//   • with --despill <cyan|green>, the tint a chroma key left on the
//     outline (the pixels next to transparency) is taken back out;
//   • specks of a few pixels lying apart from the figure are removed;
//   • the stair-stepped one-bit outline gets a soft, one-pixel edge.
//
// usage: swift Tools/clean-pet-sheet.swift <in.webp|png> <out.png> [--despill cyan|green]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: clean-pet-sheet <in> <out.png> [--despill cyan|green]\n".data(using: .utf8)!)
    exit(2)
}
let despill: String? = arguments.firstIndex(of: "--despill").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}

let width = image.width, height = image.height
let cellWidth = 192, cellHeight = 208
// Straight (unpremultiplied) RGBA, so the colour of every pixel is kept
// exactly while the alpha changes.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard drawn else { exit(1) }
// The context premultiplied; take that back for opaque and partial pixels.
for index in stride(from: 0, to: pixels.count, by: 4) {
    let alpha = Int(pixels[index + 3])
    guard alpha > 0, alpha < 255 else { continue }
    for channel in 0..<3 { pixels[index + channel] = UInt8(min(255, Int(pixels[index + channel]) * 255 / alpha)) }
}

func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
var solid = (0..<(width * height)).map { pixels[$0 * 4 + 3] >= 128 }

// Specks: a connected run of solid pixels this small, inside one cell, is
// noise the generator left, not part of the figure.
let speckArea = 6
var seen = [Bool](repeating: false, count: width * height)
var removedSpecks = 0
for start in 0..<(width * height) where solid[start] && !seen[start] {
    let cellX = (start % width) / cellWidth, cellY = (start / width) / cellHeight
    var stack = [start], component: [Int] = []
    seen[start] = true
    while let current = stack.popLast() {
        component.append(current)
        let x = current % width, y = current / width
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height, nx / cellWidth == cellX, ny / cellHeight == cellY else { continue }
            let next = ny * width + nx
            if solid[next], !seen[next] { seen[next] = true; stack.append(next) }
        }
        if component.count > speckArea { break }
    }
    // Finish marking a large component so it is not walked again.
    while let current = stack.popLast() {
        let x = current % width, y = current / width
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height, nx / cellWidth == cellX, ny / cellHeight == cellY else { continue }
            let next = ny * width + nx
            if solid[next], !seen[next] { seen[next] = true; stack.append(next) }
        }
    }
    if component.count <= speckArea {
        component.forEach { solid[$0] = false }
        removedSpecks += 1
    }
}

// How many of the 8 neighbours are solid, and the distance to transparency.
func solidNeighbours(_ x: Int, _ y: Int) -> Int {
    var count = 0
    for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
        let nx = x + dx, ny = y + dy
        if nx >= 0, ny >= 0, nx < width, ny < height, solid[ny * width + nx] { count += 1 }
    } }
    return count
}
func nearEdge(_ x: Int, _ y: Int, within radius: Int) -> Bool {
    for dy in -radius...radius { for dx in -radius...radius {
        let nx = x + dx, ny = y + dy
        if nx < 0 || ny < 0 || nx >= width || ny >= height || !solid[ny * width + nx] { return true }
    } }
    return false
}

var despilled = 0
var output = pixels
for y in 0..<height {
    for x in 0..<width {
        let index = offset(x, y)
        guard solid[y * width + x] else {
            output[index] = 0; output[index + 1] = 0; output[index + 2] = 0; output[index + 3] = 0
            continue
        }
        var red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
        // The key's tint lives on the outline: take the excess of the key's
        // channels over the remaining one back out there, and only there,
        // so a blue apron or a green shirt inside the figure keeps its colour.
        if let despill, nearEdge(x, y, within: 2) {
            switch despill {
            case "cyan":
                let spill = min(green, blue) - red
                if spill > 6 { green -= spill; blue -= spill; despilled += 1 }
            case "green":
                let spill = green - max(red, blue)
                if spill > 6 { green -= spill; despilled += 1 }
            default: break
            }
        }
        output[index] = UInt8(clamping: red)
        output[index + 1] = UInt8(clamping: green)
        output[index + 2] = UInt8(clamping: blue)
        // A soft outline: a pixel on the edge is as opaque as the share of
        // its neighbourhood the figure covers, never less than half.
        let neighbours = solidNeighbours(x, y)
        let alpha = neighbours >= 8 ? 255 : max(128, min(255, (neighbours + 1) * 255 * 5 / (9 * 4)))
        output[index + 3] = UInt8(alpha)
    }
}

// Back to premultiplied for CoreGraphics, then out as PNG.
for index in stride(from: 0, to: output.count, by: 4) {
    let alpha = Int(output[index + 3])
    guard alpha < 255 else { continue }
    for channel in 0..<3 { output[index + channel] = UInt8(Int(output[index + channel]) * alpha / 255) }
}
let provider = CGDataProvider(data: Data(output) as CFData)!
let cleaned = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, cleaned, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("\(width)×\(height): removed \(removedSpecks) specks, despilled \(despilled) outline pixels")
