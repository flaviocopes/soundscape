import Compression
import Foundation

extension SoundLibrary {
  /// tvOS has no `ditto`, so this reads the zip itself. Apple's zips leave the sizes
  /// out of the local headers, so it walks the central directory at the end instead.
  static func unzip(_ zip: URL, to folder: URL) async throws {
    let data = try Data(contentsOf: zip, options: .alwaysMapped)
    let corrupt = CocoaError(.fileReadCorruptFile)

    func uint16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
    func uint32(_ offset: Int) -> Int { uint16(offset) | uint16(offset + 2) << 16 }

    guard let end = data.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards)?.lowerBound,
          end + 22 <= data.count else { throw corrupt }

    var entry = uint32(end + 16)
    for _ in 0..<uint16(end + 10) {
      guard entry + 46 <= end, uint32(entry) == 0x0201_4B50 else { throw corrupt }
      let method = uint16(entry + 10)
      let compressedSize = uint32(entry + 20)
      let size = uint32(entry + 24)
      let nameLength = uint16(entry + 28)
      let header = uint32(entry + 42)
      guard entry + 46 + nameLength <= end else { throw corrupt }
      let name = String(decoding: data[entry + 46..<entry + 46 + nameLength], as: UTF8.self)
      entry += 46 + nameLength + uint16(entry + 30) + uint16(entry + 32)

      if name.hasSuffix("/") { continue }
      guard !name.split(separator: "/").contains(".."), header + 30 <= data.count else { throw corrupt }
      let start = header + 30 + uint16(header + 26) + uint16(header + 28)
      guard start + compressedSize <= data.count else { throw corrupt }
      let compressed = data[start..<start + compressedSize]

      let contents: Data
      switch method {
      case 0: contents = compressed
      case 8: contents = try inflate(compressed, size: size)
      default: throw CocoaError(.fileReadUnsupportedScheme)
      }

      let file = folder.appending(path: name)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: file)
    }
  }

  private static func inflate(_ compressed: Data, size: Int) throws -> Data {
    guard size > 0 else { return Data() }
    guard !compressed.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    var output = Data(count: size)
    let written = output.withUnsafeMutableBytes { destination in
      compressed.withUnsafeBytes { source in
        compression_decode_buffer(
          destination.bindMemory(to: UInt8.self).baseAddress!, size,
          source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
          nil, COMPRESSION_ZLIB
        )
      }
    }
    guard written == size else { throw CocoaError(.fileReadCorruptFile) }
    return output
  }
}
