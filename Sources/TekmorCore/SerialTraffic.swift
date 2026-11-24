import Foundation
import Synchronization

public enum SerialFormat: String, CaseIterable, Identifiable, Sendable {
  case text, hex

  public var id: Self { self }
}

public enum SerialLineEnding: String, CaseIterable, Identifiable, Sendable {
  case none = "None"
  case lf = "\\n"
  case crlf = "\\r\\n"

  public var id: Self { self }

  var bytes: [UInt8] {
    switch self {
    case .none: []
    case .lf: [10]
    case .crlf: [13, 10]
    }
  }
}

public struct SerialCommand: Equatable, Sendable {
  public var input = ""
  public var format = SerialFormat.text
  public var lineEnding = SerialLineEnding.none

  public init() {}

  /// Encodes one command, including its selected line ending, up to 64 KiB.
  public func payload() throws -> Data {
    let suffix = lineEnding.bytes
    var bytes = Data()
    switch format {
    case .text:
      bytes = Data(input.utf8)
    case .hex:
      for group in input.split(whereSeparator: \.isWhitespace) {
        let digits = group.utf8
        guard digits.count.isMultiple(of: 2) else { throw Self.invalidHEX }
        var index = digits.startIndex
        while index < digits.endIndex {
          let lowIndex = digits.index(after: index)
          guard let high = Self.nibble(digits[index]), let low = Self.nibble(digits[lowIndex])
          else { throw Self.invalidHEX }
          bytes.append(high << 4 | low)
          index = digits.index(after: lowIndex)
        }
      }
    }
    bytes.append(contentsOf: suffix)
    guard (1...64 * 1024).contains(bytes.count) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.serial.invalidPayloadSize",
            defaultValue: "Enter a command of 1 to 65536 bytes, including its line ending.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return bytes
  }

  private static var invalidHEX: TekmorError {
    TekmorError(
      TekmorLocalization.core(
        .init(
          "core.serial.invalidHEX",
          defaultValue: "Enter complete HEX byte pairs, for example 01 02 FF.",
          bundle: .atURL(Bundle.module.bundleURL))))
  }

  private static func nibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }
}

/// Batches device bytes before updating the UI while bounding pending memory.
public final class SerialInbox: Sendable {
  public struct Batch: Sendable {
    public fileprivate(set) var data = Data()
    public fileprivate(set) var byteCount = 0
    public fileprivate(set) var newlineCount = 0
    public var hasGap: Bool { byteCount > data.count }
  }

  private struct Pending {
    var batch = Batch()
    var scheduled = false
  }

  private let pending = Mutex(Pending())

  public init() {}

  /// Returns true when the caller needs to schedule a drain.
  public func append(_ bytes: Data) -> Bool {
    guard !bytes.isEmpty else { return false }
    let capacity = 160_000
    let newlines = bytes.count { $0 == 10 }
    return pending.withLock {
      $0.batch.byteCount += bytes.count
      $0.batch.newlineCount += newlines
      if bytes.count >= capacity {
        $0.batch.data = Data(bytes.suffix(capacity))
      } else {
        let excess = $0.batch.data.count + bytes.count - capacity
        if excess > 0 { $0.batch.data.removeFirst(excess) }
        $0.batch.data.append(bytes)
      }
      guard !$0.scheduled else { return false }
      $0.scheduled = true
      return true
    }
  }

  /// A synchronous drain leaves any scheduled drain in place.
  public func drain(scheduled: Bool = false) -> Batch {
    pending.withLock {
      let batch = $0.batch
      $0 = Pending(scheduled: !scheduled && $0.scheduled)
      return batch
    }
  }
}

/// Formats a stream as uppercase hexadecimal with sixteen bytes per row.
public struct SerialHEXView {
  private static let digits = Array("0123456789ABCDEF".utf8)
  private var column = 0

  public init() {}

  public mutating func append(_ bytes: Data) -> String {
    var result: [UInt8] = []
    result.reserveCapacity(bytes.count * 3)
    for byte in bytes {
      if column != 0 { result.append(32) }
      result.append(Self.digits[Int(byte >> 4)])
      result.append(Self.digits[Int(byte & 15)])
      column += 1
      if column == 16 {
        result.append(10)
        column = 0
      }
    }
    return String(decoding: result, as: UTF8.self)
  }
}
