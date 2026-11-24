import Foundation

/// File-backed bytes and their physical load addresses. Gaps are left unwritten.
public struct FirmwareImage: Sendable {
  public static let standardFlashStart: UInt64 = 0x0800_0000
  private static let addressLimit: UInt64 = 1 << 32
  private static let hexDigits = Array("0123456789ABCDEF".utf8)

  public struct Segment: Sendable, Equatable {
    public let address: UInt64
    public let bytes: Data
    public var range: Range<UInt64> { address..<(address + UInt64(bytes.count)) }
  }

  public let segments: [Segment]
  public let binaryAddress: UInt64?
  /// Allocated ELF sections, when the file contains a valid section table.
  public let sections: [FirmwareSection]?
  private let executableRanges: [Range<UInt64>]?
  public var staticRAMBytes: Int? {
    sections.map { $0.filter(\.countsTowardStaticRAM).reduce(0) { $0 + $1.bytes } }
  }

  public var internalFlashBytes: Int? {
    guard
      segments.allSatisfy({
        $0.address >= Self.standardFlashStart && $0.range.upperBound <= 0x1000_0000
      })
    else { return nil }
    return byteCount
  }

  /// A Flash vector table that refers to an MSP and Thumb reset handler in the image.
  var applicationStartAddress: UInt64? {
    let address: UInt64
    if let sections {
      let vectors = sections.filter { $0.name == ".isr_vector" && $0.bytes >= 8 }
      guard vectors.count == 1, let vector = vectors.first else { return nil }
      address = vector.address
    } else {
      address = Self.standardFlashStart
    }
    guard address >= Self.standardFlashStart, address.isMultiple(of: 128) else { return nil }
    var vector = Data()
    var nextAddress = address
    for segment in segments where segment.range.contains(nextAddress) {
      let offset = Int(nextAddress - segment.address)
      let bytes = segment.bytes.dropFirst(offset).prefix(8 - vector.count)
      vector.append(contentsOf: bytes)
      nextAddress += UInt64(bytes.count)
      if vector.count == 8 { break }
    }
    guard vector.count == 8 else { return nil }
    let stack = ARMELF32.word32(in: vector, at: vector.startIndex)
    let reset = UInt64(ARMELF32.word32(in: vector, at: vector.startIndex + 4))
    let code = reset & ~1
    guard stack.isMultiple(of: 4),
      (0x1000_0004...0x1008_0000).contains(stack) || (0x2000_0004..<0x4000_0000).contains(stack),
      reset & 1 == 1, code >= address + 8,
      (executableRanges ?? ranges).contains(where: { $0.contains(code) && $0.contains(code + 1) })
    else { return nil }
    return address
  }

  public var byteCount: Int { segments.reduce(0) { $0 + $1.bytes.count } }
  public var ranges: [Range<UInt64>] {
    var ranges: [Range<UInt64>] = []
    for segment in segments {
      if let last = ranges.last, last.upperBound == segment.address {
        ranges[ranges.count - 1] = last.lowerBound..<segment.range.upperBound
      } else {
        ranges.append(segment.range)
      }
    }
    return ranges
  }

  public init(file: URL, binaryAddress: UInt64? = nil) throws {
    let resolved = file.resolvingSymlinksInPath()
    let properties = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard properties.isRegularFile == true, let size = properties.fileSize,
      (1...64 * 1024 * 1024).contains(size)
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.invalidFile",
            defaultValue: "Select a non-empty regular firmware file up to 64 MiB.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    try self.init(
      data: Data(contentsOf: resolved), format: file.pathExtension, binaryAddress: binaryAddress)
  }

  public init(data: Data, format: String, binaryAddress: UInt64? = nil) throws {
    let segments: [Segment]
    self.binaryAddress = format.lowercased() == "bin" ? binaryAddress : nil
    switch format.lowercased() {
    case "elf", "axf", "out":
      let loads = try Self.elfLoadSegments(data)
      segments = loads.map {
        Segment(address: UInt64($0.address), bytes: data.subdata(in: $0.fileBytes))
      }
      executableRanges = loads.filter(\.executable).map {
        UInt64($0.address)..<UInt64($0.address + $0.fileBytes.count)
      }
      sections = ARMELF32.sections(in: data)
    case "hex":
      segments = try Self.hexSegments(data)
      sections = nil
      executableRanges = nil
    case "bin":
      sections = nil
      executableRanges = nil
      guard let binaryAddress, binaryAddress < Self.addressLimit else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.image.missingBinaryAddress",
              defaultValue: "Enter a valid 32-bit start address for the BIN file.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      segments = [Segment(address: binaryAddress, bytes: data)]
    default:
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.unsupportedFormat",
            defaultValue: "Select an ELF, Intel HEX, or BIN firmware file.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    var end: UInt64 = 0
    self.segments = try segments.sorted { $0.address < $1.address }.map { segment in
      guard !segment.bytes.isEmpty, segment.address >= end,
        segment.range.upperBound <= Self.addressLimit
      else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.image.invalidSegments",
              defaultValue:
                "Firmware contains empty segments, overlapping addresses, or a 32-bit address overflow.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      end = segment.range.upperBound
      return segment
    }
    guard !segments.isEmpty else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.noWritableData", defaultValue: "Firmware contains no writable data.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  public func validateInternalFlash(capacity: Int?) throws {
    guard let capacity, capacity > 0,
      UInt64(capacity) <= Self.addressLimit - Self.standardFlashStart
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.unknownFlashCapacity",
            defaultValue:
              "Cannot verify firmware addresses because the target internal Flash capacity is unknown.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let end = Self.standardFlashStart + UInt64(capacity)
    if let invalid = ranges.first(where: {
      $0.lowerBound < Self.standardFlashStart || $0.upperBound > end
    }) {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.addressOutOfFlash",
            defaultValue:
              "Firmware address range \(Self.addressLabel(invalid)) exceeds target internal Flash \(Self.addressLabel(Self.standardFlashStart..<end)).",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  public static func addressLabel(_ range: Range<UInt64>) -> String {
    String(format: "0x%08llX–0x%08llX", range.lowerBound, range.upperBound - 1)
  }

  public func intelHEX() -> Data {
    var output = Data()
    var upperAddress: UInt64?
    for segment in segments {
      var address = segment.address
      var offset = segment.bytes.startIndex
      while offset < segment.bytes.endIndex {
        let upper = address >> 16
        if upper != upperAddress {
          Self.appendRecord(
            type: 4, address: 0, bytes: [UInt8(upper >> 8), UInt8(truncatingIfNeeded: upper)],
            to: &output)
          upperAddress = upper
        }
        let low = Int(address & 0xFFFF)
        let count = min(32, segment.bytes.endIndex - offset, 0x10000 - low)
        Self.appendRecord(
          type: 0, address: low, bytes: segment.bytes[offset..<(offset + count)], to: &output)
        address += UInt64(count)
        offset += count
      }
    }
    Self.appendRecord(type: 1, address: 0, bytes: [UInt8](), to: &output)
    return output
  }

  private static func appendRecord(
    type: UInt8, address: Int, bytes: some Collection<UInt8>, to output: inout Data
  ) {
    output.append(0x3A)
    var checksum: UInt8 = 0
    func append(_ byte: UInt8) {
      output.append(hexDigits[Int(byte >> 4)])
      output.append(hexDigits[Int(byte & 15)])
    }
    for byte in [UInt8(bytes.count), UInt8(address >> 8), UInt8(truncatingIfNeeded: address), type]
    {
      append(byte)
      checksum &+= byte
    }
    for byte in bytes {
      append(byte)
      checksum &+= byte
    }
    append(0 &- checksum)
    output.append(10)
  }

  private static func elfLoadSegments(_ data: Data) throws -> [ARMELF32.LoadSegment] {
    try ARMELF32.loadSegments(
      in: data,
      invalidHeader: .init(
        "core.image.invalidARMELF", defaultValue: "Select a valid 32-bit ARM executable ELF.",
        bundle: .atURL(Bundle.module.bundleURL)
      ),
      invalidSegment: .init(
        "core.image.truncatedLoadSegment",
        defaultValue: "ELF load segment is truncated or has an invalid size.",
        bundle: .atURL(Bundle.module.bundleURL)
      )
    )
  }

  private static func hexSegments(_ data: Data) throws -> [Segment] {
    guard let contents = String(data: data, encoding: .utf8) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.invalidHexEncoding", defaultValue: "Invalid Intel HEX encoding.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    var base: UInt64 = 0
    var ended = false
    var segments: [Segment] = []
    for (index, line) in contents.split(whereSeparator: \.isNewline).enumerated() {
      let invalid = TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.invalidHexRecord",
            defaultValue: "Invalid Intel HEX record on line \(index + 1).",
            bundle: .atURL(Bundle.module.bundleURL))))
      let text = Array(line.utf8)
      guard !ended, text.first == 58, (11...521).contains(text.count), text.count % 2 == 1 else {
        throw invalid
      }
      let bytes = try stride(from: 1, to: text.count, by: 2).map { offset in
        guard let high = hexDigit(text[offset]), let low = hexDigit(text[offset + 1]) else {
          throw invalid
        }
        return (high << 4) | low
      }
      let count = Int(bytes[0])
      let address = Int(bytes[1]) << 8 | Int(bytes[2])
      guard bytes.count == count + 5, bytes.reduce(UInt8(0), &+) == 0 else { throw invalid }
      switch bytes[3] {
      case 0:
        guard address + count <= 0x10000 else { throw invalid }
        if count > 0 {
          segments.append(
            Segment(address: base + UInt64(address), bytes: Data(bytes[4..<(4 + count)])))
        }
      case 1:
        guard count == 0, address == 0 else { throw invalid }
        ended = true
      case 2, 4:
        guard count == 2, address == 0 else { throw invalid }
        let extensionAddress = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
        base = extensionAddress << (bytes[3] == 2 ? 4 : 16)
      case 3, 5:
        guard count == 4, address == 0 else { throw invalid }
      default:
        throw invalid
      }
    }
    guard ended else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.image.missingHexEOF", defaultValue: "Intel HEX is missing an end-of-file record.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return segments
  }

  private static func hexDigit(_ character: UInt8) -> UInt8? {
    switch character {
    case 48...57: character - 48
    case 65...70: character - 55
    case 97...102: character - 87
    default: nil
    }
  }
}
