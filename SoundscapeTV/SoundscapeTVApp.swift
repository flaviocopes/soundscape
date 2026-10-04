import SwiftUI

@main
struct SoundscapeTVApp: App {
  @State private var mixer = Mixer()

  var body: some Scene {
    WindowGroup {
      TVMixerView()
        .environment(mixer)
    }
  }
}
