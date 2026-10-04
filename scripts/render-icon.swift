#!/usr/bin/env swift
// Renders the Soundscape app icons from one set of shapes:
// - Soundscape/AppIcon.icon, an Icon Composer bundle. Layers are flat 1024pt PNGs: macOS adds
//   the Liquid Glass, and Xcode derives the icons for older macOS releases from the same bundle.
// - SoundscapeTV/Assets.xcassets, the Apple TV icon and Top Shelf images. tvOS doesn't take
//   Icon Composer bundles, so its icon is a stack of sky, moon and mountains that shift apart
//   when the icon has focus.
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
let reflectionOpacity: CGFloat = 0.45
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

func render(width: CGFloat, height: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil,
    width: Int(width),
    height: Int(height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: 0, y: height)
  context.scaleBy(x: 1, y: -1)
  draw(context)
  return context.makeImage()!
}

func drawMoon(_ context: CGContext) {
  // The bite clears pixels, so it happens in its own layer to keep the sky behind intact.
  context.saveGState()
  context.beginTransparencyLayer(auxiliaryInfo: nil)
  context.setFillColor(cgColor(moonColor))
  context.fillEllipse(in: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: 2 * moonRadius, height: 2 * moonRadius))
  context.setBlendMode(.clear)
  let bite = CGPoint(x: moonCenter.x + 46, y: moonCenter.y - 32)
  context.fillEllipse(in: CGRect(x: bite.x - 80, y: bite.y - 80, width: 160, height: 160))
  context.endTransparencyLayer()
  context.restoreGState()
}

func drawMountains(_ context: CGContext) {
  context.setFillColor(cgColor(mountainColor))
  for (index, peak) in peaks.enumerated() {
    context.addPath(bar(x: barX(index), from: waterline, length: peak, upward: true))
  }
  context.fillPath()
}

func drawReflection(_ context: CGContext) {
  context.setFillColor(cgColor(mountainColor))
  for (index, peak) in peaks.enumerated() {
    context.addPath(bar(x: barX(index), from: waterline + 18, length: peak * reflectionScale, upward: false))
  }
  context.fillPath()
}

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

// MARK: Mac

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
        { "name" : "Reflection", "image-name" : "reflection.png", "glass" : true, "opacity" : \(reflectionOpacity) },
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

let bundle = root.appendingPathComponent("Soundscape/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(render(width: canvas, height: canvas, drawMoon), to: assets.appendingPathComponent("moon.png"))
write(render(width: canvas, height: canvas, drawMountains), to: assets.appendingPathComponent("mountains.png"))
write(render(width: canvas, height: canvas, drawReflection), to: assets.appendingPathComponent("reflection.png"))
try! manifest.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")

// MARK: Apple TV

func drawFadedReflection(_ context: CGContext) {
  context.setAlpha(reflectionOpacity)
  drawReflection(context)
  context.setAlpha(1)
}

// The 1024pt artwork, scaled to the image's height and centered on a wider sky.
func tvImage(width: CGFloat, height: CGFloat, sky: Bool = false, artwork: [(CGContext) -> Void]) -> CGImage {
  render(width: width, height: height) { context in
    if sky {
      let gradient = CGGradient(colorsSpace: nil, colors: [cgColor(skyTop), cgColor(skyBottom)] as CFArray, locations: [0, 1])!
      context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }
    context.translateBy(x: (width - height) / 2, y: 0)
    context.scaleBy(x: height / canvas, y: height / canvas)
    for draw in artwork {
      draw(context)
    }
  }
}

func writeContents(_ folder: URL, _ body: String? = nil) {
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let info = #"  "info" : { "author" : "xcode", "version" : 1 }"#
  let json = "{\n" + [body, info].compactMap { $0 }.joined(separator: ",\n") + "\n}\n"
  try! json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func writeImageSet(_ folder: URL, width: CGFloat, height: CGFloat, scales: [Int], _ image: (CGFloat, CGFloat) -> CGImage) {
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  var images: [String] = []
  for scale in scales {
    let name = scale == 1 ? "image.png" : "image@\(scale)x.png"
    write(image(width * CGFloat(scale), height * CGFloat(scale)), to: folder.appendingPathComponent(name))
    images.append(#"    { "filename" : "\#(name)", "idiom" : "tv", "scale" : "\#(scale)x" }"#)
  }
  writeContents(folder, "  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ]")
}

func writeIconStack(_ folder: URL, width: CGFloat, height: CGFloat, scales: [Int]) {
  let layers: [(name: String, image: (CGFloat, CGFloat) -> CGImage)] = [
    ("Front", { tvImage(width: $0, height: $1, artwork: [drawFadedReflection, drawMountains]) }),
    ("Middle", { tvImage(width: $0, height: $1, artwork: [drawMoon]) }),
    ("Back", { tvImage(width: $0, height: $1, sky: true, artwork: []) }),
  ]
  for layer in layers {
    let layerFolder = folder.appendingPathComponent("\(layer.name).imagestacklayer")
    writeContents(layerFolder)
    writeImageSet(layerFolder.appendingPathComponent("Content.imageset"), width: width, height: height, scales: scales, layer.image)
  }
  let list = layers.map { #"    { "filename" : "\#($0.name).imagestacklayer" }"# }.joined(separator: ",\n")
  writeContents(folder, "  \"layers\" : [\n" + list + "\n  ]")
}

func topShelf(width: CGFloat, height: CGFloat) -> CGImage {
  tvImage(width: width, height: height, sky: true, artwork: [drawMoon, drawFadedReflection, drawMountains])
}

let tvAssets = root.appendingPathComponent("SoundscapeTV/Assets.xcassets")
let brand = tvAssets.appendingPathComponent("AppIcon.brandassets")
try? FileManager.default.removeItem(at: tvAssets)
writeContents(tvAssets)
writeIconStack(brand.appendingPathComponent("App Icon.imagestack"), width: 400, height: 240, scales: [1, 2])
writeIconStack(brand.appendingPathComponent("App Icon - App Store.imagestack"), width: 1280, height: 768, scales: [1])
writeImageSet(brand.appendingPathComponent("Top Shelf Image.imageset"), width: 1920, height: 720, scales: [1, 2], topShelf)
writeImageSet(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), width: 2320, height: 720, scales: [1, 2], topShelf)
writeContents(brand, """
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ]
""")
print("Wrote \(tvAssets.path)")
