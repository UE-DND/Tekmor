import Foundation

enum ARMELF32 {
  struct LoadSegment {
    let address: Int
    let fileBytes: Range<Data.Index>
    let executable: Bool

    var addresses: Range<Int> { address..<(address + fileBytes.count) }
  }

  static func loadSegments(
    in data: Data, invalidHeader: LocalizedStringResource,
    invalidSegment: LocalizedStringResource
  ) throws -> [LoadSegment] {
    let start = data.startIndex
    guard data.count >= 52, data.prefix(7).elementsEqual([0x7f, 69, 76, 70, 1, 1, 1]),
      word16(in: data, at: start + 16) == 2, word16(in: data, at: start + 18) == 40,
      word32(in: data, at: start + 20) == 1, word16(in: data, at: start + 40) == 52
    else {
      throw TekmorError(TekmorLocalization.core(invalidHeader))
    }
    let table = word32(in: data, at: start + 28)
    let headerSize = word16(in: data, at: start + 42)
    let count = word16(in: data, at: start + 44)
    guard headerSize == 32, count > 0, table >= 52, table + count * headerSize <= data.count else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.firmware.incompleteProgramHeaders",
            defaultValue: "Incomplete ELF program headers.", bundle: .atURL(Bundle.module.bundleURL)
          )))
    }
    return try (0..<count).compactMap { index in
      let header = start + table + index * headerSize
      guard word32(in: data, at: header) == 1 else { return nil }  // PT_LOAD
      let length = word32(in: data, at: header + 16)
      guard length > 0 else { return nil }
      let offset = word32(in: data, at: header + 4)
      guard offset + length <= data.count, length <= word32(in: data, at: header + 20) else {
        throw TekmorError(TekmorLocalization.core(invalidSegment))
      }
      // Physical load address, including the Flash initializer for RAM .data.
      let address = word32(in: data, at: header + 12)
      let executable = word32(in: data, at: header + 24) & 1 != 0
      return LoadSegment(
        address: address, fileBytes: (start + offset)..<(start + offset + length),
        executable: executable)
    }
  }

  static func word32(in data: Data, at index: Data.Index) -> Int {
    word16(in: data, at: index) | word16(in: data, at: index + 2) << 16
  }

  private static func word16(in data: Data, at index: Data.Index) -> Int {
    Int(data[index]) | Int(data[index + 1]) << 8
  }
}
