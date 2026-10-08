import SwiftUI

@main
struct SoundscapeApp: App {
  @State private var mixer = Mixer()

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/tranquillity-maker")
  }

  var body: some Scene {
    Window("Tranquillity Maker", id: "mixer") {
      MixerView()
        .frame(width: 720)
        .environment(mixer)
    }
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About Tranquillity Maker") {
          NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        }
        Button("Check for Updates…") {
          AppUpdater.shared.checkForUpdates()
        }
      }
    }

    MenuBarExtra {
      MenuBarContent()
        .environment(mixer)
    } label: {
      Image(systemName: mixer.isPlaying ? "waveform.circle.fill" : "waveform.circle")
    }
    .menuBarExtraStyle(.window)
  }

  private var credits: NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    return NSAttributedString(
      string: """
        Tranquillity Maker includes no audio. It plays the Background Sounds that come with macOS. \
        They belong to Apple and are covered by the macOS Software License Agreement.

        Tranquillity Maker isn't affiliated with Apple.
        """,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraph,
      ]
    )
  }
}
