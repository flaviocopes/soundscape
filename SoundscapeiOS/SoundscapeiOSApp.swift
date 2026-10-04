import SwiftUI

@main
struct SoundscapeiOSApp: App {
  @State private var mixer = Mixer()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ScrollView {
          MixerView()
        }
        .navigationTitle("Soundscape")
      }
      .environment(mixer)
    }
  }
}
