import Foundation
import TekmorCore

/// App-local selections for a project root. CMake inputs stay in memory when in use.
struct ProjectPreferences: Codable {
  private static let key = "projectPreferences.v1"

  let configuration: ProjectConfiguration
  let monitorPort: String?
  let flashPort: String?

  init(configuration: ProjectConfiguration, monitorPort: String?, flashPort: String?) {
    self.configuration = configuration
    self.monitorPort = monitorPort
    self.flashPort = flashPort
  }

  private enum CodingKeys: String, CodingKey {
    case preset, target, toolchain, mcu, method, baud, parity, stopBits, monitorPort, flashPort
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    var configuration = ProjectConfiguration()
    configuration.cmake = CMakeSettings(
      configurePreset: try values.decodeIfPresent(String.self, forKey: .preset),
      target: try values.decodeIfPresent(String.self, forKey: .target),
      toolchainFile: try values.decodeIfPresent(String.self, forKey: .toolchain))
    configuration.mcu = try values.decodeIfPresent(String.self, forKey: .mcu)
    configuration.flash =
      try FlashMethod(rawValue: values.decode(String.self, forKey: .method)) ?? .uart
    configuration.serial.baud = try values.decode(Int.self, forKey: .baud)
    configuration.serial.parity =
      try SerialSettings.Parity(rawValue: values.decode(String.self, forKey: .parity)) ?? .none
    configuration.serial.stopBits = try values.decode(Int.self, forKey: .stopBits)
    try configuration.validate()
    self.configuration = configuration
    monitorPort = try values.decodeIfPresent(String.self, forKey: .monitorPort)
    flashPort = try values.decodeIfPresent(String.self, forKey: .flashPort)
  }

  func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(configuration.cmake.configurePreset, forKey: .preset)
    try values.encodeIfPresent(configuration.cmake.target, forKey: .target)
    try values.encodeIfPresent(configuration.cmake.toolchainFile, forKey: .toolchain)
    try values.encodeIfPresent(configuration.mcu, forKey: .mcu)
    try values.encode(configuration.flash.rawValue, forKey: .method)
    try values.encode(configuration.serial.baud, forKey: .baud)
    try values.encode(configuration.serial.parity.rawValue, forKey: .parity)
    try values.encode(configuration.serial.stopBits, forKey: .stopBits)
    try values.encodeIfPresent(monitorPort, forKey: .monitorPort)
    try values.encodeIfPresent(flashPort, forKey: .flashPort)
  }

  static func load(for path: String, from defaults: UserDefaults) -> Self? {
    guard let data = defaults.dictionary(forKey: key)?[path] as? Data else { return nil }
    return try? PropertyListDecoder().decode(Self.self, from: data)
  }

  func save(for path: String, in defaults: UserDefaults) {
    guard let data = try? PropertyListEncoder().encode(self) else { return }
    var projects = defaults.dictionary(forKey: Self.key) ?? [:]
    projects[path] = data
    defaults.set(projects, forKey: Self.key)
  }
}
