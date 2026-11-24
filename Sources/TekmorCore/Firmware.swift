import Foundation

public struct FirmwareUsage: Sendable, Equatable {
  public let flashBytes: Int
  public let flashCapacity: Int

  public var utilization: Double {
    guard flashCapacity > 0 else { return 0 }
    return min(1.0, Double(flashBytes) / Double(flashCapacity))
  }

  public init(flashBytes: Int, flashCapacity: Int) {
    self.flashBytes = flashBytes
    self.flashCapacity = flashCapacity
  }
}

/// An allocated ELF section and its runtime address and size.
public struct FirmwareSection: Sendable, Equatable, Identifiable {
  public let index: Int
  public let name: String
  public let address: UInt64
  public let bytes: Int
  public var id: Int { index }

  var countsTowardStaticRAM: Bool {
    name == ".data" || name.hasPrefix(".data.") || name == ".bss" || name.hasPrefix(".bss.")
  }
}
