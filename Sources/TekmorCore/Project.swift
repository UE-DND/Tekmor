import Foundation

public struct TekmorError: LocalizedError, Sendable {
  public let errorDescription: String?

  public init(_ message: String) {
    errorDescription = message
  }
}

public enum FlashMethod: String, CaseIterable, Sendable, Identifiable {
  case uart, swd

  public var id: String { rawValue }
  public var title: String { self == .uart ? "UART Bootloader" : "ST-LINK / SWD" }
}

public struct SerialSettings: Equatable, Sendable {
  public enum Parity: String, CaseIterable, Sendable {
    case none, even, odd
  }

  public static let baudRates = [
    1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 1_000_000,
  ]
  public var baud = 115200
  public var parity = Parity.none
  public var stopBits = 1

  public init() {}

  public func validate() throws {
    guard Self.baudRates.contains(baud), [1, 2].contains(stopBits) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.serial.invalidSettings",
            defaultValue: "Select a supported baud rate and stop bits.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }
}

public struct CMakeSettings: Equatable, Sendable {
  public var configurePreset: String?
  public var target: String?
  public var toolchainFile: String?

  public init(configurePreset: String? = nil, target: String? = nil, toolchainFile: String? = nil) {
    self.configurePreset = configurePreset
    self.target = target
    self.toolchainFile = toolchainFile
  }
}

public struct ProjectConfiguration: Equatable, Sendable {
  public var mcu: String?
  public var cmake = CMakeSettings()
  public var flash = FlashMethod.uart
  public var serial = SerialSettings()

  public init() {}

  public func validate() throws {
    if let mcu, mcu.range(of: #"^STM32[A-Z0-9]+$"#, options: .regularExpression) == nil {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.project.invalidMCU",
            defaultValue: "Enter a full STM32 part number, or leave the expected MCU blank.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    if let file = cmake.toolchainFile {
      guard Self.isRelative(file), cmake.configurePreset == nil else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.project.invalidToolchainPath",
              defaultValue:
                "Without a preset, the CMake toolchain file must be a relative path inside the project.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
    }
    if let preset = cmake.configurePreset {
      guard !preset.isEmpty, !preset.contains(where: \.isNewline), !preset.contains("\0") else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.project.invalidPresetName", defaultValue: "Invalid CMake preset name.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
    }
    if let target = cmake.target {
      guard !target.hasPrefix("-"),
        target.range(of: #"^[A-Za-z0-9_.+\-]+$"#, options: .regularExpression) != nil
      else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.project.invalidTargetName", defaultValue: "Invalid CMake target name.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
    }
    try serial.validate()
  }

  public static func isRelative(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
      && !path.split(separator: "/").contains("..")
  }
}
