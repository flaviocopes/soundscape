import AVFoundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class Mixer {
  private(set) var channels: [Channel]

  var masterVolume: Float {
    didSet {
      engine.mainMixerNode.outputVolume = masterVolume * masterVolume
      UserDefaults.standard.set(masterVolume, forKey: "masterVolume")
    }
  }

  private(set) var savedMix: [String] {
    didSet { UserDefaults.standard.set(savedMix, forKey: "savedMix") }
  }

  var isPlaying: Bool { channels.contains(where: \.isOn) }

  var playingCount: Int { channels.count(where: \.isOn) }

  @ObservationIgnored private let engine: AVAudioEngine

  init() {
    let engine = AVAudioEngine()
    self.engine = engine
    masterVolume = (UserDefaults.standard.object(forKey: "masterVolume") as? NSNumber)?.floatValue ?? 0.8
    savedMix = UserDefaults.standard.stringArray(forKey: "savedMix") ?? []
    channels = SoundLibrary.load().map { Channel(sound: $0, engine: engine) }
    engine.mainMixerNode.outputVolume = masterVolume * masterVolume

    // The engine stops itself when the output device changes, like plugging in headphones.
    _ = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.resume() }
    }

    #if !os(macOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback)

    // A call, Siri or another app's audio stops the engine, so pause the mix to match.
    _ = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
      MainActor.assumeIsolated {
        if self?.isPlaying == true { self?.togglePlayback() }
      }
    }
    #endif

    // The play/pause key and the Now Playing controls reach whichever app last
    // published Now Playing info, which updateNowPlaying() does on every play and stop.
    let commands = MPRemoteCommandCenter.shared()
    commands.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.togglePlayback()
      return .success
    }
    commands.playCommand.addTarget { [weak self] _ in
      if self?.isPlaying == false { self?.togglePlayback() }
      return .success
    }
    commands.pauseCommand.addTarget { [weak self] _ in
      if self?.isPlaying == true { self?.togglePlayback() }
      return .success
    }

    Task { await refreshCatalog() }
  }

  private func refreshCatalog() async {
    guard let catalog = try? await SoundLibrary.fetchCatalog() else { return }
    for sound in SoundLibrary.load(catalog: catalog) {
      if let channel = channels.first(where: { $0.id == sound.id }) {
        channel.updateDownload(from: sound)
      } else {
        channels.append(Channel(sound: sound, engine: engine))
      }
    }
    channels.sort { $0.sound.order < $1.sound.order }
  }

  func toggle(_ channel: Channel) {
    if channel.isOn {
      stop(channel)
    } else {
      play(channel)
    }
    let mix = channels.filter(\.isOn).map(\.id)
    if !mix.isEmpty {
      savedMix = mix
    }
  }

  func togglePlayback() {
    if isPlaying {
      channels.filter(\.isOn).forEach(stop)
      return
    }
    let saved = channels.filter { savedMix.contains($0.id) && $0.sound.isAvailable }
    if saved.isEmpty, let first = channels.first(where: \.sound.isAvailable) {
      toggle(first)
    } else {
      saved.forEach(play)
    }
  }

  private func play(_ channel: Channel) {
    guard channel.sound.isAvailable else { return }
    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        return
      }
    }
    channel.play()
    updateNowPlaying()
  }

  private func stop(_ channel: Channel) {
    let fadeOut = channel.stop()
    updateNowPlaying()
    Task {
      await fadeOut.value
      if !isPlaying, !channels.contains(where: \.isAudible) {
        engine.pause()
      }
    }
  }

  private func updateNowPlaying() {
    let mix = isPlaying ? channels.filter(\.isOn) : channels.filter { savedMix.contains($0.id) }
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = [
      MPMediaItemPropertyTitle: mix.map(\.sound.name).formatted(.list(type: .and)),
      MPMediaItemPropertyArtist: "Tranquillity Maker",
      MPNowPlayingInfoPropertyIsLiveStream: true,
    ]
    center.playbackState = isPlaying ? .playing : .paused
  }

  private func resume() {
    guard isPlaying, (try? engine.start()) != nil else { return }
    for channel in channels where channel.isOn {
      channel.restart()
    }
  }
}
