import SwiftUI

struct TVMixerView: View {
  @Environment(Mixer.self) private var mixer

  var body: some View {
    VStack(alignment: .leading, spacing: 40) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Tranquillity Maker")
            .font(.title3.bold())
          HStack(spacing: 0) {
            Text(status)
              .foregroundStyle(.secondary)
            Text(" · Hold a sound to change its volume")
              .foregroundStyle(.tertiary)
          }
        }
        Spacer()
        Button {
          mixer.togglePlayback()
        } label: {
          Label(mixer.isPlaying ? "Pause" : "Play", systemImage: mixer.isPlaying ? "pause.fill" : "play.fill")
        }
      }

      if mixer.channels.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 4), spacing: 40) {
            ForEach(mixer.channels) { channel in
              TVChannelTile(channel: channel)
            }
          }
          .padding(.vertical, 12)
        }
        .scrollClipDisabled()
      }
    }
    .background {
      LinearGradient(colors: [.night, .dusk], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
    .onPlayPauseCommand {
      mixer.togglePlayback()
    }
  }

  private var status: LocalizedStringKey {
    if mixer.isPlaying {
      "Playing ^[\(mixer.playingCount) sound](inflect: true)"
    } else if mixer.savedMix.isEmpty {
      "Pick a sound"
    } else {
      "Paused"
    }
  }
}

struct TVChannelTile: View {
  @Environment(Mixer.self) private var mixer
  let channel: Channel

  private static let levels: [Float] = [1, 0.75, 0.5, 0.25]

  var body: some View {
    Button {
      mixer.select(channel)
    } label: {
      VStack(alignment: .leading) {
        HStack(alignment: .top) {
          Image(systemName: channel.sound.symbol)
            .symbolVariant(channel.isOn ? .fill : .none)
            .font(.system(size: 44))
          Spacer()
          detail
            .font(.caption)
        }
        Spacer(minLength: 0)
        Text(channel.sound.name)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .padding(28)
      .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170, alignment: .leading)
      .foregroundStyle(channel.isOn ? Color.night : .white)
      .opacity(channel.sound.isAvailable || channel.isOn ? 1 : 0.65)
      .background(channel.isOn ? Color.mountain : .clear)
      .animation(.easeOut(duration: 0.2), value: channel.isOn)
    }
    .buttonStyle(.card)
    .contextMenu {
      if channel.sound.isAvailable {
        ForEach(Self.levels, id: \.self) { level in
          Button {
            channel.volume = level
          } label: {
            if channel.volume == level {
              Label("Volume \(Int(level * 100))%", systemImage: "checkmark")
            } else {
              Text("Volume \(Int(level * 100))%")
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if channel.sound.isAvailable {
      Image(systemName: "speaker.wave.3", variableValue: Double(channel.volume))
    } else if channel.isDownloading {
      ProgressView()
    } else if channel.downloadError != nil {
      Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
    } else {
      Label(channel.sound.downloadSize.formatted(.byteCount(style: .file)), systemImage: "arrow.down.circle")
    }
  }
}

extension Mixer {
  /// Turns a sound on or off. A sound that isn't on the Apple TV yet downloads first, then starts.
  func select(_ channel: Channel) {
    if channel.sound.isAvailable {
      toggle(channel)
    } else if !channel.isDownloading {
      Task {
        await channel.download()
        if channel.sound.isAvailable, !channel.isOn {
          toggle(channel)
        }
      }
    }
  }
}

// Same colors as the app icon in scripts/render-icon.swift.
private extension Color {
  static let night = Color(red: 0.043, green: 0.051, blue: 0.169)
  static let dusk = Color(red: 0.122, green: 0.184, blue: 0.459)
  static let mountain = Color(red: 0.608, green: 0.945, blue: 0.898)
}
