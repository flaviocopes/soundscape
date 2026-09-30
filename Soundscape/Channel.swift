import AVFoundation
import Observation

@MainActor
@Observable
final class Channel: Identifiable {
  private(set) var sound: Sound
  private(set) var isOn = false
  private(set) var isDownloading = false
  private(set) var downloadError: String?

  var volume: Float {
    didSet {
      output.outputVolume = volume * volume
      UserDefaults.standard.set(volume, forKey: "volume.\(id)")
    }
  }

  let id: String

  var isAudible: Bool { players.contains(where: \.isPlaying) }

  private let output = AVAudioMixerNode()
  private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
  private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
  @ObservationIgnored private var scheduler: Task<Void, any Error>?
  @ObservationIgnored private var fadeTask: Task<Void, Never>?
  @ObservationIgnored private var gain: Float = 0 {
    didSet {
      for player in players {
        player.volume = gain
      }
    }
  }

  private static let fadeIn: Duration = .seconds(2)
  private static let fadeOut: Duration = .seconds(1.5)
  private static let crossfadeSeconds = 4.0

  init(sound: Sound, engine: AVAudioEngine) {
    self.sound = sound
    id = sound.id
    volume = (UserDefaults.standard.object(forKey: "volume.\(sound.id)") as? NSNumber)?.floatValue ?? 0.5

    engine.attach(output)
    engine.connect(output, to: engine.mainMixerNode, format: format)
    for player in players {
      engine.attach(player)
      engine.connect(player, to: output, format: format)
    }
    output.outputVolume = volume * volume
  }

  func play() {
    guard sound.isAvailable else { return }
    isOn = true
    if scheduler == nil {
      gain = 0
      startPlayers()
    }
    fadeTask?.cancel()
    fadeTask = Task {
      try? await fade(to: 1, over: Self.fadeIn)
    }
  }

  @discardableResult
  func stop() -> Task<Void, Never> {
    isOn = false
    fadeTask?.cancel()
    let task = Task {
      do {
        try await fade(to: 0, over: Self.fadeOut)
      } catch {
        return
      }
      stopPlayers()
    }
    fadeTask = task
    return task
  }

  func restart() {
    stopPlayers()
    play()
  }

  func updateDownload(from catalog: Sound) {
    guard !sound.isAvailable else { return }
    sound.downloadURL = catalog.downloadURL
    sound.downloadSize = catalog.downloadSize
  }

  func download() async {
    isDownloading = true
    downloadError = nil
    defer { isDownloading = false }
    do {
      sound.segments = try await SoundLibrary.download(sound)
    } catch {
      downloadError = error.localizedDescription
    }
  }

  // Both players start at the same instant, so they share a sample timeline
  // and each segment can be queued to overlap the previous one exactly.
  private func startPlayers() {
    let lead = 0.1
    let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead))
    for player in players {
      player.play(at: start)
    }
    let origin = ContinuousClock.now + .seconds(lead)
    scheduler = Task { try await schedule(from: origin) }
  }

  private func stopPlayers() {
    scheduler?.cancel()
    scheduler = nil
    for player in players {
      player.stop()
    }
  }

  // Queues random segments one ahead of playback. The audio engine handles the
  // timing, so a late wake-up here never causes a gap.
  private func schedule(from origin: ContinuousClock.Instant) async throws {
    let crossfade = AVAudioFramePosition(Self.crossfadeSeconds * format.sampleRate)
    var position: AVAudioFramePosition = 0
    var previous: URL?
    var index = 0

    while true {
      let url = sound.segments.filter { $0 != previous }.randomElement() ?? sound.segments[0]
      guard let file = try? AVAudioFile(forReading: url),
            file.processingFormat == format,
            file.length > 2 * crossfade else {
        stop()
        return
      }

      try Task.checkCancellation()
      try queue(file, on: players[index], at: position, crossfade: crossfade)

      let start = origin + .seconds(Double(position) / format.sampleRate)
      try await Task.sleep(until: start, tolerance: .seconds(1), clock: .continuous)

      position += file.length - crossfade
      previous = url
      index = 1 - index
    }
  }

  private func queue(
    _ file: AVAudioFile,
    on player: AVAudioPlayerNode,
    at position: AVAudioFramePosition,
    crossfade: AVAudioFramePosition
  ) throws {
    let head = try read(file, from: 0, frames: crossfade) { sin($0 * .pi / 2) }
    let tail = try read(file, from: file.length - crossfade, frames: crossfade) { cos($0 * .pi / 2) }

    player.scheduleBuffer(head, at: AVAudioTime(sampleTime: position, atRate: format.sampleRate))
    player.scheduleSegment(
      file,
      startingFrame: crossfade,
      frameCount: AVAudioFrameCount(file.length - 2 * crossfade),
      at: nil
    )
    player.scheduleBuffer(tail, at: nil)
  }

  private func read(
    _ file: AVAudioFile,
    from start: AVAudioFramePosition,
    frames: AVAudioFramePosition,
    fade: (Float) -> Float
  ) throws -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    file.framePosition = start
    try file.read(into: buffer)

    let count = Int(buffer.frameLength)
    for channel in 0..<Int(format.channelCount) {
      let samples = buffer.floatChannelData![channel]
      for frame in 0..<count {
        samples[frame] *= fade(Float(frame) / Float(count))
      }
    }
    return buffer
  }

  private func fade(to target: Float, over duration: Duration) async throws {
    let from = gain
    let start = ContinuousClock.now
    while true {
      let progress = Float(min(1, (ContinuousClock.now - start) / duration))
      gain = from + (target - from) * progress
      if progress == 1 { return }
      try await Task.sleep(for: .milliseconds(20))
    }
  }
}
