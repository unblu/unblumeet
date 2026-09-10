// Renders a seamlessly looping "person on a video call" clip as raw RGBA
// frames on stdout, for ffmpeg to encode. Every motion completes whole cycles
// per loop so clips concatenate without a jump.
//
//   swift avatar-video.swift --width 640 --height 360 --fps 15 \
//        --seconds 2 --seed 3 --talking 1

import CoreGraphics
import Foundation
import ImageIO

func arg(_ name: String, _ fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

let width = Int(arg("width", "640"))!
let height = Int(arg("height", "360"))!
let fps = Int(arg("fps", "15"))!
let seconds = Double(arg("seconds", "30"))!
let seed = Int(arg("seed", "0"))!
let pngPath = arg("png", "")
/// Whether this clip is of the person talking.
let talking = arg("talking", "0") == "1"

let frameCount = Int(seconds * Double(fps))

// Deterministic per seed, so a participant looks the same on every run.
struct Palette {
    let background: (CGFloat, CGFloat, CGFloat)
    let shirt: (CGFloat, CGFloat, CGFloat)
    let skin: (CGFloat, CGFloat, CGFloat)
    let hair: (CGFloat, CGFloat, CGFloat)
}
let backgrounds: [(CGFloat, CGFloat, CGFloat)] = [
    (0.16, 0.20, 0.30), (0.20, 0.17, 0.26), (0.13, 0.24, 0.25),
    (0.26, 0.19, 0.17), (0.17, 0.22, 0.18), (0.22, 0.20, 0.14),
]
let shirts: [(CGFloat, CGFloat, CGFloat)] = [
    (0.24, 0.42, 0.66), (0.62, 0.30, 0.32), (0.30, 0.52, 0.40),
    (0.46, 0.36, 0.60), (0.70, 0.52, 0.24), (0.34, 0.36, 0.40),
]
let skins: [(CGFloat, CGFloat, CGFloat)] = [
    (0.96, 0.82, 0.71), (0.87, 0.69, 0.55), (0.70, 0.50, 0.37),
    (0.50, 0.35, 0.26), (0.36, 0.25, 0.19), (0.99, 0.87, 0.78),
]
let hairs: [(CGFloat, CGFloat, CGFloat)] = [
    (0.16, 0.12, 0.10), (0.35, 0.22, 0.11), (0.62, 0.47, 0.24),
    (0.55, 0.55, 0.57), (0.28, 0.16, 0.14), (0.10, 0.09, 0.09),
]
let palette = Palette(background: backgrounds[seed % backgrounds.count],
                      shirt: shirts[(seed / 2) % shirts.count],
                      skin: skins[(seed / 3) % skins.count],
                      hair: hairs[(seed / 5) % hairs.count])

/// Whole cycles per loop, so the clip joins back onto itself cleanly.
func cycles(_ base: Int) -> Double { Double(base + seed % 2) }

let context = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let out = FileHandle.standardOutput

func set(_ rgb: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat = 1) {
    context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
}

for frame in 0 ..< frameCount {
    let t = Double(frame) / Double(frameCount)          // 0…1 across the loop
    let angle = t * 2 * .pi

    // Background: a soft vertical gradient, plus a slow drifting highlight so
    // the frame is never perfectly static (static frames make an encoder
    // produce nothing, which looks like a frozen stream).
    let bg = palette.background
    for band in 0 ..< 24 {
        let f = CGFloat(band) / 24
        set((bg.0 + f * 0.06, bg.1 + f * 0.06, bg.2 + f * 0.08))
        context.fill(CGRect(x: 0, y: CGFloat(height) * f,
                            width: CGFloat(width), height: CGFloat(height) / 24 + 1))
    }
    // Two drifting highlights, at different rates, so the background is never
    // a still image — an encoder given identical frames emits almost nothing
    // and the stream looks frozen.
    for (index, rate) in [cycles(1), cycles(2)].enumerated() {
        let phase = angle * rate + Double(index) * 2.1
        // Travel is bounded by the clip length: motion must complete whole
        // cycles inside it to concatenate seamlessly, so a wide swing in a
        // short clip strobes instead of drifting.
        let glowX = CGFloat(0.5 + 0.22 * cos(phase)) * CGFloat(width)
        let glowY = CGFloat(0.45 + 0.14 * sin(phase)) * CGFloat(height)
        let size = CGFloat(height) * (index == 0 ? 1.4 : 0.9)
        set((1, 1, 1), index == 0 ? 0.055 : 0.035)
        context.fillEllipse(in: CGRect(x: glowX - size / 2, y: glowY - size / 2,
                                       width: size, height: size))
    }

    // The person does not move.
    let centreX = CGFloat(width) / 2
    let headRadius = CGFloat(height) * 0.20
    let headY = CGFloat(height) * 0.60

    // Shoulders.
    set(palette.shirt)
    let shoulderWidth = CGFloat(width) * 0.62
    context.fillEllipse(in: CGRect(x: centreX - shoulderWidth / 2,
                                   y: -CGFloat(height) * 0.30,
                                   width: shoulderWidth,
                                   height: CGFloat(height) * 0.72))
    // Neck.
    set(palette.skin)
    context.fill(CGRect(x: centreX - headRadius * 0.32,
                        y: headY - headRadius * 1.30,
                        width: headRadius * 0.64, height: headRadius * 0.75))
    // Head.
    context.fillEllipse(in: CGRect(x: centreX - headRadius * 0.82,
                                   y: headY - headRadius,
                                   width: headRadius * 1.64, height: headRadius * 2.05))
    // Hair, clipped to the skull so it sits on the head rather than across
    // the face.
    set(palette.hair)
    context.saveGState()
    context.addEllipse(in: CGRect(x: centreX - headRadius * 0.86,
                                  y: headY - headRadius * 1.02,
                                  width: headRadius * 1.72, height: headRadius * 2.13))
    context.clip()
    context.fill(CGRect(x: centreX - headRadius, y: headY + headRadius * 0.52,
                        width: headRadius * 2, height: headRadius))
    context.restoreGState()

    let eyeOpen: CGFloat = 1
    let eyeY = headY + headRadius * 0.28
    for side in [-1.0, 1.0] {
        set((1, 1, 1))
        let eyeWidth = headRadius * 0.26
        context.fillEllipse(in: CGRect(x: centreX + CGFloat(side) * headRadius * 0.34 - eyeWidth / 2,
                                       y: eyeY - eyeWidth * 0.35 * eyeOpen,
                                       width: eyeWidth, height: eyeWidth * 0.7 * eyeOpen))
        set((0.12, 0.10, 0.10))
        let pupil = headRadius * 0.10
        context.fillEllipse(in: CGRect(x: centreX + CGFloat(side) * headRadius * 0.34 - pupil / 2,
                                       y: eyeY - pupil / 2 * eyeOpen,
                                       width: pupil, height: pupil * eyeOpen))
    }

    // Whole cycles per loop again, so a talking second joins onto the next
    // without the mouth jumping.
    let openness: CGFloat = talking
        ? 0.2 + 0.8 * CGFloat(abs(sin(angle * 3)))
        : 0.1
    set((0.35, 0.16, 0.18))
    let mouthWidth = headRadius * 0.46
    context.fillEllipse(in: CGRect(x: centreX - mouthWidth / 2,
                                   y: headY - headRadius * 0.22 - headRadius * 0.16 * openness,
                                   width: mouthWidth,
                                   height: headRadius * 0.34 * openness))

    guard let image = context.makeImage() else { continue }

    if !pngPath.isEmpty, frame == frameCount / 3 {
        if let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: pngPath) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    let data = context.data!
    out.write(Data(bytes: data, count: width * height * 4))
}
