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

  // Called after validating the ARM executable header and its program headers.
  static func sections(in data: Data) -> [FirmwareSection]? {
    let start = data.startIndex
    let offset = word32(in: data, at: start + 32)
    let stride = word16(in: data, at: start + 46)
    let count = word16(in: data, at: start + 48)
    let namesIndex = word16(in: data, at: start + 50)
    guard stride == 40, count > 0, offset >= 52, offset + count * stride <= data.count,
      (1..<count).contains(namesIndex)
    else { return nil }
    let namesHeader = start + offset + namesIndex * stride
    let namesOffset = word32(in: data, at: namesHeader + 16)
    let namesSize = word32(in: data, at: namesHeader + 20)
    guard word32(in: data, at: namesHeader + 4) == 3, namesSize > 0,
      namesOffset + namesSize <= data.count
    else { return nil }

    let namesStart = start + namesOffset
    let namesEnd = namesStart + namesSize
    var sections: [FirmwareSection] = []
    for index in 1..<count {
      let header = start + offset + index * stride
      let flags = word32(in: data, at: header + 8)
      let size = word32(in: data, at: header + 20)
      guard flags & 2 != 0, size > 0 else { continue }  // SHF_ALLOC
      let nameIndex = namesStart + word32(in: data, at: header)
      let address = word32(in: data, at: header + 12)
      let type = word32(in: data, at: header + 4)
      let fileOffset = word32(in: data, at: header + 16)
      guard nameIndex < namesEnd, let end = data[nameIndex..<namesEnd].firstIndex(of: 0),
        address + size <= (1 << 32), type == 8 || fileOffset + size <= data.count,
        let name = String(data: data[nameIndex..<end], encoding: .utf8)
      else { return nil }
      sections.append(.init(index: index, name: name, address: UInt64(address), bytes: size))
    }
    return sections
  }

  static func word32(in data: Data, at index: Data.Index) -> Int {
    word16(in: data, at: index) | word16(in: data, at: index + 2) << 16
  }

  private static func word16(in data: Data, at index: Data.Index) -> Int {
    Int(data[index]) | Int(data[index + 1]) << 8
  }
}
