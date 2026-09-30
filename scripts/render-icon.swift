#!/usr/bin/env swift
// Renders the Soundscape app icon into Soundscape/AppIcon.icon, an Icon Composer bundle.
// Layers are flat 1024pt PNGs: macOS adds the Liquid Glass, and Xcode derives the
// icons for older macOS releases from the same bundle.
// Usage: swift scripts/render-icon.swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let waterline: CGFloat = 612
let barWidth: CGFloat = 64
let barGap: CGFloat = 26
// A mountain range that doubles as a waveform, mirrored in the lake below.
let peaks: [CGFloat] = [96, 184, 304, 412, 312, 208, 268, 160, 92]
let reflectionScale: CGFloat = 0.6
let moonCenter = CGPoint(x: 756, y: 250)
let moonRadius: CGFloat = 92

let skyTop: UInt32 = 0x1D2266
let skyBottom: UInt32 = 0x4262CF
let darkSkyTop: UInt32 = 0x0B0D2B
let darkSkyBottom: UInt32 = 0x1F2F75
let mountainColor: UInt32 = 0x9BF1E5
let moonColor: UInt32 = 0xFFDA7A

func rgb(_ hex: UInt32) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
  (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}

func cgColor(_ hex: UInt32) -> CGColor {
  let color = rgb(hex)
  return CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
}

func iconColor(_ hex: UInt32) -> String {
  let color = rgb(hex)
  return "\"extended-srgb:" + [color.red, color.green, color.blue, 1].map { String(format: "%.5f", $0) }.joined(separator: ",") + "\""
}

func barX(_ index: Int) -> CGFloat {
  let width = CGFloat(peaks.count) * barWidth + CGFloat(peaks.count - 1) * barGap
  return (canvas - width) / 2 + CGFloat(index) * (barWidth + barGap)
}

// A bar with a round cap on the far end and a flat edge on the waterline.
func bar(x: CGFloat, from edge: CGFloat, length: CGFloat, upward: Bool) -> CGPath {
  let radius = min(barWidth, length) / 2
  let capped = CGRect(x: x, y: upward ? edge - length : edge, width: barWidth, height: length)
  let flat = CGRect(x: x, y: upward ? edge - radius : edge, width: barWidth, height: radius)
  let path = CGMutablePath()
  path.addRoundedRect(in: capped, cornerWidth: radius, cornerHeight: radius)
  path.addRect(flat)
  return path
}

func layer(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: 0, y: canvas)
  context.scaleBy(x: 1, y: -1)
  draw(context)
  return context.makeImage()!
}

let moon = layer { context in
  context.setFillColor(cgColor(moonColor))
  context.fillEllipse(in: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: 2 * moonRadius, height: 2 * moonRadius))
  context.setBlendMode(.clear)
  let bite = CGPoint(x: moonCenter.x + 46, y: moonCenter.y - 32)
  context.fillEllipse(in: CGRect(x: bite.x - 80, y: bite.y - 80, width: 160, height: 160))
}

let mountains = layer { context in
  context.setFillColor(cgColor(mountainColor))
  for (index, peak) in peaks.enumerated() {
    context.addPath(bar(x: barX(index), from: waterline, length: peak, upward: true))
  }
  context.fillPath()
}

let reflection = layer { context in
  context.setFillColor(cgColor(mountainColor))
  for (index, peak) in peaks.enumerated() {
    context.addPath(bar(x: barX(index), from: waterline + 18, length: peak * reflectionScale, upward: false))
  }
  context.fillPath()
}

let manifest = """
{
  "fill-specializations" : [
    { "value" : { "linear-gradient" : [\(iconColor(skyTop)), \(iconColor(skyBottom))] } },
    { "appearance" : "dark", "value" : { "linear-gradient" : [\(iconColor(darkSkyTop)), \(iconColor(darkSkyBottom))] } }
  ],
  "groups" : [
    {
      "name" : "Moon",
      "layers" : [
        { "name" : "Moon", "image-name" : "moon.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    },
    {
      "name" : "Range",
      "layers" : [
        { "name" : "Reflection", "image-name" : "reflection.png", "glass" : true, "opacity" : 0.45 },
        { "name" : "Mountains", "image-name" : "mountains.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    }
  ],
  "supported-platforms" : {
    "squares" : ["macOS"]
  }
}

"""

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("Soundscape/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(moon, to: assets.appendingPathComponent("moon.png"))
write(mountains, to: assets.appendingPathComponent("mountains.png"))
write(reflection, to: assets.appendingPathComponent("reflection.png"))
try! manifest.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")
