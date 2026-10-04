import Foundation

struct Sound: Identifiable {
  let id: String
  let order: Int
  var segments: [URL] = []
  var downloadURL: URL?
  var downloadSize: Int64 = 0

  var isAvailable: Bool { !segments.isEmpty }

  var name: String {
    switch id {
    case "PinkNoise": "Balanced Noise"
    case "WhiteNoise": "Bright Noise"
    case "BrownNoise": "Dark Noise"
    case "RainOnRoof": "Rain on Roof"
    default:
      id.reduce(into: "") { name, character in
        if character.isUppercase, !name.isEmpty { name += " " }
        name.append(character)
      }
    }
  }

  var symbol: String {
    switch id {
    case "PinkNoise": "waveform"
    case "WhiteNoise": "sun.max"
    case "BrownNoise": "moon"
    case "Ocean": "water.waves"
    case "Rain": "cloud.rain"
    case "Stream": "drop"
    case "Night": "moon.stars"
    case "Fire": "flame"
    case "Babble": "bubble.left.and.bubble.right"
    case "Steam": "humidity"
    case "Airplane": "airplane"
    case "Boat": "ferry"
    case "Bus": "bus"
    case "Train": "tram"
    case "RainOnRoof": "house"
    case "QuietNight": "moon.zzz"
    default: "speaker.wave.2"
    }
  }
}

/// Finds the Background Sounds that macOS ships in its MobileAsset folder,
/// and downloads the missing ones from Apple's CDN using the same catalog.
/// iOS and tvOS apps can't read the system copies, so there every sound is a download.
enum SoundLibrary {
  private static let systemFolder = URL(filePath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets")
  #if os(tvOS)
  // tvOS apps can only keep files in Caches, which the system empties when it runs low on space.
  private static let downloadsFolder = URL.cachesDirectory.appending(path: "Sounds")
  #else
  private static let downloadsFolder = URL.applicationSupportDirectory.appending(path: "Soundscape/Sounds")
  #endif
  private static let localCatalog = systemFolder.appending(path: "com_apple_MobileAsset_ComfortSoundsAssets.xml")
  // The local copy only lists the sounds this macOS version knows about. The live
  // catalog also has the newer ones, like the eight that arrived with Tahoe.
  private static let catalogURL = URL(string: "https://mesu.apple.com/assets/macos/com_apple_MobileAsset_ComfortSoundsAssets/com_apple_MobileAsset_ComfortSoundsAssets.xml")!

  /// Pass the live catalog from `fetchCatalog()`, or nothing to use the local copy.
  static func load(catalog: Data? = nil) -> [Sound] {
    var sounds: [String: Sound] = [:]

    for asset in assets(in: catalog ?? (try? Data(contentsOf: localCatalog))) {
      sounds[asset.name] = Sound(
        id: asset.name,
        order: asset.group,
        downloadURL: URL(string: asset.baseURL + asset.path),
        downloadSize: asset.size
      )
    }

    for folder in contents(of: systemFolder) + contents(of: downloadsFolder) {
      guard let info = decode(AssetInfo.self, from: folder.appending(path: "Info.plist")) else { continue }
      let name = info.properties.name
      let segments = segments(in: folder)
      guard !segments.isEmpty, sounds[name]?.isAvailable != true else { continue }
      sounds[name, default: Sound(id: name, order: info.properties.group)].segments = segments
    }

    return sounds.values.sorted { $0.order < $1.order }
  }

  static func download(_ sound: Sound) async throws -> [URL] {
    guard let url = sound.downloadURL else { throw URLError(.badURL) }

    let (zip, response) = try await URLSession.shared.download(from: url)
    defer { try? FileManager.default.removeItem(at: zip) }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

    let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try await unzip(zip, to: staging)

    let destination = downloadsFolder.appending(path: sound.id)
    try FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: staging, to: destination)
    return segments(in: destination)
  }

  static func fetchCatalog() async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: catalogURL, timeoutInterval: 15))
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return data
  }

  private static func assets(in catalog: Data?) -> [CatalogAsset] {
    guard let catalog, let assets = try? PropertyListDecoder().decode(Catalog.self, from: catalog).assets else { return [] }
    let newest = Dictionary(assets.map { ($0.name, $0) }) { $0.version >= $1.version ? $0 : $1 }
    return Array(newest.values)
  }

  private static func segments(in folder: URL) -> [URL] {
    contents(of: folder.appending(path: "AssetData")).filter { $0.pathExtension == "m4a" }
  }

  private static func contents(of folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
  }

  private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? PropertyListDecoder().decode(type, from: data)
  }
}

private struct Catalog: Decodable {
  let assets: [CatalogAsset]

  enum CodingKeys: String, CodingKey {
    case assets = "Assets"
  }
}

private struct CatalogAsset: Decodable {
  let name: String
  let group: Int
  let version: Int
  let baseURL: String
  let path: String
  let size: Int64

  enum CodingKeys: String, CodingKey {
    case name = "SoundName"
    case group = "SoundGroup"
    case version = "CompatibilityVersion"
    case baseURL = "__BaseURL"
    case path = "__RelativePath"
    case size = "_DownloadSize"
  }
}

private struct AssetInfo: Decodable {
  let properties: Properties

  struct Properties: Decodable {
    let name: String
    let group: Int

    enum CodingKeys: String, CodingKey {
      case name = "SoundName"
      case group = "SoundGroup"
    }
  }

  enum CodingKeys: String, CodingKey {
    case properties = "MobileAssetProperties"
  }
}
