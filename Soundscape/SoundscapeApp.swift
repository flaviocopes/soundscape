import SwiftUI

@main
struct SoundscapeApp: App {
  @State private var mixer = Mixer()

  var body: some Scene {
    Window("Soundscape", id: "mixer") {
      MixerView()
        .frame(width: 720)
        .environment(mixer)
    }
    .windowResizability(.contentSize)

    MenuBarExtra {
      MenuBarContent()
        .environment(mixer)
    } label: {
      Image(systemName: mixer.isPlaying ? "waveform.circle.fill" : "waveform.circle")
    }
    .menuBarExtraStyle(.window)
  }
}
