// Captures the real Tranquillity Maker window for the README, in light and dark.
// scripts/screenshot.sh compiles it with the app's sources, in place of SoundscapeApp.swift.

import AppKit
import AVFoundation
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let mix: [String: Float] = ["Rain": 0.75, "Fire": 0.4, "Stream": 0.55]

@main
enum Screenshot {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let mixer = Mixer()
    let host = NSHostingView(rootView: MixerView().frame(width: 720).environment(mixer))
    let window = ActiveWindow(
      contentRect: CGRect(x: 0, y: 0, width: 720, height: 460),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Tranquillity Maker"
    window.contentView = host
    window.center()
    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await capture(mixer, in: window) }
      }
    }
    app.run()
  }
}

/// Draws as the active window even when another app is frontmost, which is the case
/// when this runs from a terminal: macOS doesn't let it take focus.
final class ActiveWindow: NSWindow {
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
  @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
  @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
  @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
  @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
}

@MainActor
func capture(_ mixer: Mixer, in window: NSWindow) async {
  // Silence the engine itself, so the master volume slider still shows its usual level.
  mixer.masterVolume = 0.8
  let engine = Mirror(reflecting: mixer).children.first { $0.label == "engine" }?.value as! AVAudioEngine
  engine.mainMixerNode.outputVolume = 0
  // The live catalog adds the sounds this macOS version doesn't list yet.
  try? await Task.sleep(for: .seconds(4))
  for channel in mixer.channels {
    guard let volume = mix[channel.id] else { continue }
    channel.volume = volume
    mixer.toggle(channel)
  }

  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    NSApp.appearance = NSAppearance(named: appearance)
    try? await Task.sleep(for: .seconds(1))
    if let host = window.contentView {
      host.layoutSubtreeIfNeeded()
      window.setContentSize(host.fittingSize)
      window.center()
    }
    try? await Task.sleep(for: .seconds(0.5))
    write(framed(snapshot(window)), to: output.appending(path: "screenshot-\(name).png"))
  }
  NSApp.terminate(nil)
}

@MainActor
func snapshot(_ window: NSWindow) -> CGImage {
  let view = window.contentView!.superview!
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  return rep.cgImage!
}

/// Rounds the corners like a window and adds a soft shadow on a transparent margin.
func framed(_ image: CGImage) -> CGImage {
  let scale: CGFloat = 2
  let margin = 48 * scale
  let radius = 10 * scale
  let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
  let window = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: CGColor(gray: 0, alpha: 0.32))
  context.addPath(window)
  context.setFillColor(CGColor(gray: 0.5, alpha: 1))
  context.fillPath()
  context.restoreGState()

  context.addPath(window)
  context.clip()
  context.draw(image, in: rect)
  context.resetClip()
  context.addPath(window)
  context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
  context.setLineWidth(1)
  context.strokePath()
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print(url.path)
}
