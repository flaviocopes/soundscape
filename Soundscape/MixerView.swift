import SwiftUI

struct MixerView: View {
  /// Scrolls the sounds past this height, so the menu bar panel fits on a laptop screen.
  var maxGridHeight: CGFloat?

  @Environment(Mixer.self) private var mixer
  @State private var gridHeight: CGFloat = 0

  var body: some View {
    @Bindable var mixer = mixer

    VStack(spacing: 16) {
      HStack {
        Text(status)
          .font(.headline)
        Spacer()
        Button {
          mixer.togglePlayback()
        } label: {
          Label(mixer.isPlaying ? "Pause" : "Play", systemImage: mixer.isPlaying ? "pause.fill" : "play.fill")
            .frame(minWidth: 60)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.space, modifiers: [])
      }

      if let maxGridHeight {
        ScrollView {
          sounds.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
        }
        .frame(height: min(gridHeight, maxGridHeight))
        .scrollBounceBehavior(.basedOnSize)
      } else {
        sounds
      }

      HStack(spacing: 8) {
        Image(systemName: "speaker.fill")
        Slider(value: $mixer.masterVolume)
        Image(systemName: "speaker.wave.3.fill")
      }
      .foregroundStyle(.secondary)
      .controlSize(.small)
    }
    .padding(16)
  }

  private var sounds: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 162), spacing: 12)], spacing: 12) {
      ForEach(mixer.channels) { channel in
        ChannelTile(channel: channel)
      }
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

struct ChannelTile: View {
  @Environment(Mixer.self) private var mixer
  @Bindable var channel: Channel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        mixer.toggle(channel)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: channel.sound.symbol)
            .symbolVariant(channel.isOn ? .fill : .none)
            .font(.title3)
            .frame(width: 24)
          Text(channel.sound.name)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(channel.isOn ? Color.accentColor : Color.primary)
      .disabled(!channel.sound.isAvailable)

      controls
        .frame(height: 20)
    }
    .padding(12)
    .background(
      channel.isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
      in: .rect(cornerRadius: 12)
    )
    .animation(.easeOut(duration: 0.2), value: channel.isOn)
  }

  @ViewBuilder
  private var controls: some View {
    if channel.sound.isAvailable {
      Slider(value: $channel.volume)
        .controlSize(.small)
    } else if channel.isDownloading {
      ProgressView()
        .progressViewStyle(.linear)
    } else {
      Button(channel.downloadError == nil ? "Download · \(size)" : "Retry download") {
        Task { await channel.download() }
      }
      .controlSize(.small)
      .help(channel.downloadError ?? "Download this sound from Apple")
    }
  }

  private var size: String {
    channel.sound.downloadSize.formatted(.byteCount(style: .file))
  }
}

struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 0) {
      MixerView(maxGridHeight: 400)
      Divider()
      HStack {
        Button("Open Window") {
          openWindow(id: "mixer")
          NSApp.activate()
        }
        Spacer()
        Button("Quit Soundscape") {
          NSApp.terminate(nil)
        }
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .frame(width: 372)
  }
}
