// Renders the app icon at one size as a PNG.
//
//   swift app-icon.swift --size 1024 --out icon_512x512@2x.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func arg(_ name: String, _ fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

let size = Int(arg("size", "1024"))!
let out = arg("out", "icon.png")
let s = CGFloat(size)

let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high

/// macOS icons sit inside the canvas rather than filling it.
let inset = s * 0.09
let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let corner = plate.width * 0.2237   // the standard macOS squircle proportion

let shape = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)

context.saveGState()
context.addPath(shape)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.16, green: 0.22, blue: 0.52, alpha: 1),
                                   CGColor(red: 0.42, green: 0.24, blue: 0.68, alpha: 1)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY),
                           options: [])
context.restoreGState()

// A video camera: rounded body, lens wedge to its right.
let bodyWidth = plate.width * 0.42
let bodyHeight = bodyWidth * 0.66
let body = CGRect(x: plate.midX - bodyWidth * 0.62,
                  y: plate.midY - bodyHeight / 2,
                  width: bodyWidth, height: bodyHeight)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.addPath(CGPath(roundedRect: body, cornerWidth: bodyHeight * 0.24,
                       cornerHeight: bodyHeight * 0.24, transform: nil))
context.fillPath()

let wedge = CGMutablePath()
let gap = plate.width * 0.028
let wedgeWidth = plate.width * 0.15
// Corners in order around the outline; crossing them makes a bowtie.
wedge.move(to: CGPoint(x: body.maxX + gap, y: body.midY + bodyHeight * 0.18))
wedge.addLine(to: CGPoint(x: body.maxX + gap + wedgeWidth, y: body.midY + bodyHeight * 0.46))
wedge.addLine(to: CGPoint(x: body.maxX + gap + wedgeWidth, y: body.midY - bodyHeight * 0.46))
wedge.addLine(to: CGPoint(x: body.maxX + gap, y: body.midY - bodyHeight * 0.18))
wedge.closeSubpath()
context.addPath(wedge)
context.fillPath()

// A live dot, so the mark is not just another camera glyph.
let dot = plate.width * 0.085
context.setFillColor(CGColor(red: 1, green: 0.36, blue: 0.32, alpha: 1))
context.fillEllipse(in: CGRect(x: body.minX + bodyHeight * 0.22,
                               y: body.midY - dot / 2,
                               width: dot, height: dot))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
