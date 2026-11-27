import Foundation

public struct CubeCLI: Sendable {
  public let executable: URL
  public let directory: URL?
  private let runner: CommandRunner
  private(set) var processEnvironment: [String: String]

  public init(
    executable: URL, directory: URL? = nil, runner: CommandRunner = CommandRunner(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    // Preserve the wrapper location. ST uses it to resolve its installation and bundles.
    self.executable = executable
    self.directory = directory
    self.runner = runner
    var environment = environment
    let extraPaths = [
      executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
      "/usr/bin", "/bin",
    ]
    environment["PATH"] = (extraPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
    environment["LC_ALL"] = "en_US.UTF-8"
    if let directory {
      environment["CUBE_BUNDLE_PATH"] = directory.appendingPathComponent("bundles").path
      environment["CUBE_CACHE_PATH"] = directory.appendingPathComponent("cache").path
      environment["CUBE_LOG_PATH"] = directory.appendingPathComponent("logs").path
      environment.removeValue(forKey: "CUBE_BUNDLE_PATH_EXTRA")
    }
    self.processEnvironment = environment
  }

  public static func displayVersion(from rawVersion: String) -> String {
    let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "cube wrapper version:"
    if trimmed.lowercased().hasPrefix(prefix) {
      let version = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
      if !version.isEmpty { return version }
    }
    return trimmed
  }

  public func run(
    _ arguments: [String], in directory: URL? = nil, timeout: Duration? = nil,
    log: @escaping ToolLog = { _ in }
  ) async throws -> CommandResult {
    let workingDirectory =
      directory
      ?? self.directory.flatMap {
        FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
      }
      ?? executable.deletingLastPathComponent()
    if let timeout {
      return try await runner.run(
        executable, arguments, directory: workingDirectory,
        environment: processEnvironment, timeout: timeout, log: log)
    }
    return try await runner.run(
      executable, arguments, directory: workingDirectory, environment: processEnvironment, log: log)
  }

  func settingEnvironment(_ additions: [String: String]) -> Self {
    var configured = self
    configured.processEnvironment.merge(additions) { _, replacement in replacement }
    return configured
  }

  public func version() async throws -> String {
    let result = try await run(["--version"], timeout: .seconds(10))
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opCheck", defaultValue: "Checking CubeCLI",
          bundle: .atURL(Bundle.module.bundleURL))))
    guard let first = result.output.split(whereSeparator: \.isNewline).first else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.missingVersion", defaultValue: "CubeCLI did not return a version.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return String(first)
  }

  public func resolve(_ command: String) async throws -> Data {
    let result = try await run(["--json", "--resolve", command], timeout: .seconds(10))
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opResolveCommand", defaultValue: "Resolving CubeCLI command \"\(command)\"",
          bundle: .atURL(Bundle.module.bundleURL))))
    let data = Data(result.output.utf8)
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.invalidCommandInfo",
            defaultValue: "CubeCLI did not return valid command info for \"\(command)\".",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return data
  }
}

public struct ChipInformation: Equatable, Sendable {
  public let id: UInt16
  public let name: String?
  public private(set) var flashBytes: Int?
  public let revision: String?
  public let bootloader: String?
  public let voltage: String?
  public let probeSerialNumber: String?

  public var title: String { name ?? "STM32" }
  public var idLabel: String { String(format: "0x%03X", id) }
  public var details: String {
    [
      idLabel, flashBytes.map { "\($0 / 1024) KiB Flash" }, revision,
      bootloader.map { "Bootloader \($0)" }, voltage,
    ]
    .compactMap { $0 }.joined(separator: " · ")
  }

  public enum Match { case exact, ambiguous, mismatch }

  public func match(expected: String?) -> Match {
    guard let expected else { return .ambiguous }
    guard let name else { return .ambiguous }
    let reported = name.uppercased().split(separator: "/").map { field -> String? in
      let component = field.trimmingCharacters(in: .whitespaces)
      let model = component.hasPrefix("STM32") ? component : "STM32" + component
      guard let range = model.range(of: #"^STM32[A-Z][A-Z0-9]+"#, options: .regularExpression)
      else { return nil }
      return String(model[range])
    }
    let models = reported.compactMap { $0 }
    guard !models.isEmpty, models.count == reported.count,
      models.allSatisfy({ $0.prefix { $0 != "X" }.count >= 7 })
    else { return .ambiguous }
    if models == [expected], expected.count >= 13 { return .exact }
    return models.contains {
      let prefix = $0.prefix { $0 != "X" }
      return expected.hasPrefix(prefix) || prefix.hasPrefix(expected)
    } ? .ambiguous : .mismatch
  }

  func sameTarget(as previous: Self) -> Bool {
    id == previous.id && name == previous.name && flashBytes == previous.flashBytes
      && revision == previous.revision && bootloader == previous.bootloader
      && probeSerialNumber == previous.probeSerialNumber
  }

  static func plainText(_ output: String) -> String {
    output.replacingOccurrences(
      of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
  }

  public static func parseProgrammer(_ output: String) throws -> Self {
    var fields: [String: String] = [:]
    for line in plainText(output).split(whereSeparator: \.isNewline) {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    let rawID =
      (fields["device id"] ?? fields["chip id"])?.split(whereSeparator: \.isWhitespace).first ?? ""
    guard rawID.lowercased().hasPrefix("0x"), let id = UInt16(rawID.dropFirst(2), radix: 16), id > 0
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.programmerInvalidChipID",
            defaultValue: "CubeProgrammer did not return a valid chip ID.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    func value(_ key: String) -> String? {
      guard let field = fields[key], !field.isEmpty, field != "--", field != "N/A" else {
        return nil
      }
      return field
    }
    if let type = value("device type"), type.uppercased() != "MCU" {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.unsupportedDeviceType",
            defaultValue:
              "Target device (\(type)) is not an STM32 MCU supported by this flashing flow.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return Self(
      id: id, name: value("device name"),
      flashBytes: (value("flash size") ?? value("nvm size")).flatMap(parseCapacity),
      revision: value("revision id"),
      bootloader: value("bl version") ?? value("bootloader version")
        ?? value("bootloader protocol version"),
      voltage: value("voltage"),
      probeSerialNumber: value("st-link sn").flatMap { serial in
        serial.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil ? nil : serial
      })
  }

  mutating func setMeasuredFlashBytes(_ bytes: Int?) {
    flashBytes = bytes
  }

  static func parseCapacity(_ text: String) -> Int? {
    let compact = text.lowercased().filter { !$0.isWhitespace }
    let number = compact.prefix { $0.isNumber || $0 == "." }
    guard let value = Double(number), value.isFinite, value > 0 else { return nil }
    let multiplier: Int
    switch compact.dropFirst(number.count) {
    case "b", "byte", "bytes": multiplier = 1
    case "kb", "kib", "kbyte", "kbytes": multiplier = 1024
    case "mb", "mib", "mbyte", "mbytes": multiplier = 1024 * 1024
    default: return nil
    }
    let bytes = value * Double(multiplier)
    guard bytes <= 64 * 1024 * 1024, bytes.rounded() == bytes else { return nil }
    return Int(bytes)
  }
}

public enum ChipConnection: Equatable, Sendable {
  case uart(SerialDevice)
  case swd(STLinkProbe)

  var flashMethod: FlashMethod {
    switch self {
    case .uart: .uart
    case .swd: .swd
    }
  }

  public var id: UInt64 {
    switch self {
    case .uart(let device): device.registryID
    case .swd(let probe): probe.id
    }
  }

  public func present() -> Bool {
    switch self {
    case .uart(let device): DeviceDiscovery.serial().contains(device)
    case .swd(let probe): DeviceDiscovery.probes().contains(probe)
    }
  }

  func arguments(
    probes: [STLinkProbe], confirmedSerial: String? = nil, reuseUART: Bool = false,
    programming: Bool = false
  ) throws -> [String] {
    switch self {
    case .uart(let device):
      let arguments = ["-c", "port=\(device.id)", "br=57600"]
      return reuseUART ? arguments + ["noinit=1"] : arguments
    case .swd(let probe):
      // Keep reads nonintrusive. For writes, reset and halt so the running
      // user firmware cannot interfere with the Flash programming operation.
      let arguments = ["-c", "port=SWD", programming ? "mode=NORMAL" : "mode=HOTPLUG"]
      if let confirmedSerial { return arguments + ["sn=\(confirmedSerial)"] }
      if let serial = probe.serialNumber, probes.filter({ $0.serialNumber == serial }).count == 1 {
        return arguments + ["sn=\(serial)"]
      }
      guard probes == [probe] else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.cube.ambiguousProbe",
              defaultValue:
                "Cannot distinguish the selected ST-LINK. Keep only the target probe connected.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      return arguments
    }
  }
}

public struct CubeProgrammer: Sendable {
  private let cli: CubeCLI
  private let isPresent: @Sendable (ChipConnection) -> Bool
  private let probes: @Sendable () -> [STLinkProbe]
  private let deadline: @Sendable (FlashMethod, Int) -> Duration
  private let resetDeadline: Duration

  public init(cli: CubeCLI) {
    self.init(cli: cli, isPresent: { $0.present() }, probes: DeviceDiscovery.probes)
  }

  init(
    cli: CubeCLI, isPresent: @escaping @Sendable (ChipConnection) -> Bool,
    probes: @escaping @Sendable () -> [STLinkProbe],
    deadline: @escaping @Sendable (FlashMethod, Int) -> Duration = FlashDeadline.programming,
    resetDeadline: Duration = .seconds(12)
  ) {
    self.cli = cli
    self.isPresent = isPresent
    self.probes = probes
    self.deadline = deadline
    self.resetDeadline = resetDeadline
  }

  public func read(_ connection: ChipConnection, log: @escaping ToolLog = { _ in }) async throws
    -> ChipInformation
  {
    try await read(connection, confirmedSerial: nil, reuseUART: false, log: log)
  }

  /// Identifies the target before presenting confirmation, including an already synced UART session.
  public func identifyTarget(
    _ connection: ChipConnection, log: @escaping ToolLog = { _ in }
  ) async throws -> ChipInformation {
    do {
      return try await read(connection, log: log)
    } catch {
      try Task.checkCancellation()
      guard case .uart = connection, isPresent(connection) else { throw error }
      return try await read(connection, confirmedSerial: nil, reuseUART: true, log: log)
    }
  }

  func read(
    _ connection: ChipConnection, confirming confirmed: ChipInformation?, log: @escaping ToolLog
  ) async throws -> ChipInformation {
    guard let confirmed else { return try await read(connection, log: log) }
    let observed = try await read(
      connection, confirmedSerial: confirmed.probeSerialNumber, reuseUART: true, log: log)
    try checkTarget(observed, confirmed: confirmed)
    return observed
  }

  private func read(
    _ connection: ChipConnection, confirmedSerial: String?, reuseUART: Bool, log: @escaping ToolLog
  ) async throws -> ChipInformation {
    let result = try await execute(
      connection, [], confirmedSerial: confirmedSerial, reuseUART: reuseUART,
      timeout: .seconds(12), log: log)
    let diagnostic = result.output + "\n" + result.errorOutput
    if let problem = diagnostic.split(whereSeparator: \.isNewline).last(where: {
      $0.localizedCaseInsensitiveContains("error:")
    }) {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.connectFailed",
            defaultValue:
              "Failed to connect to target: \(problem.trimmingCharacters(in: .whitespaces))",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opReadChip", defaultValue: "Reading chip information",
          bundle: .atURL(Bundle.module.bundleURL))))
    var info = try ChipInformation.parseProgrammer(diagnostic)
    if case .uart = connection {
      info.setMeasuredFlashBytes(
        try? await measureUARTFlash(info.id, connection: connection, log: log))
    }
    try Task.checkCancellation()
    return info
  }

  private func measureUARTFlash(
    _ id: UInt16, connection: ChipConnection, log: @escaping ToolLog
  ) async throws -> Int? {
    // CubeProgrammer may print a device family's default size over UART. Read the
    // factory register when registered by ST, and never use that default for writes.
    let resolved = try await cli.resolve("programmer")
    let details = try JSONDecoder().decode(ResolvedProgrammer.self, from: resolved)
    guard let executable = details.command.first, executable.hasPrefix("/") else { return nil }
    let database = URL(filePath: executable).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Data_Base", isDirectory: true)
      .appendingPathComponent(String(format: "STM32_Prog_DB_0x%03X.xml", id))
    guard let register = try FlashCapacityRegister.definition(at: database) else { return nil }
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("capacity.bin")
    let address = String(format: "0x%08X", register.address)
    let result = try await execute(
      connection, ["--upload", address, "4", output.path], reuseUART: true,
      timeout: .seconds(10), log: log)
    guard result.succeeded, !Self.reportsError(result.output + result.errorOutput),
      let data = try? Data(contentsOf: output), data.count == 4
    else { return nil }
    let value = data.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
    return register.bytes(from: value)
  }

  private struct ResolvedProgrammer: Decodable {
    let command: [String]
  }

  struct FlashCapacityRegister: Hashable {
    let address: UInt32
    let mask: UInt32

    static func definition(at file: URL) throws -> Self? {
      guard let data = try? Data(contentsOf: file), data.count <= 8 * 1024 * 1024 else {
        return nil
      }
      let xml = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
      let nodes = try xml.nodes(
        forXPath:
          "//*[translate(local-name(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='flashsize']/ReadRegister"
      )
      let definitions = nodes.compactMap { node -> Self? in
        guard let element = node as? XMLElement,
          let address = element.attribute(forName: "address")?.stringValue.flatMap(parseHex),
          let mask = element.attribute(forName: "mask")?.stringValue.flatMap(parseHex), mask > 0
        else { return nil }
        return Self(address: address, mask: mask)
      }
      let registers = Set(definitions)
      if !nodes.isEmpty {
        guard definitions.count == nodes.count, registers.count == 1 else { return nil }
        return registers.first
      }
      let sizes = try xml.nodes(
        forXPath:
          "//*[translate(local-name(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='flashsize']"
      )
      let addresses = Set(
        sizes.compactMap { node in
          (node as? XMLElement)?.attribute(forName: "address")?.stringValue.flatMap(parseHex)
        })
      guard addresses.count == 1, let address = addresses.first else { return nil }
      return Self(address: address, mask: 0xFFFF)
    }

    private static func parseHex(_ text: String) -> UInt32? {
      guard text.lowercased().hasPrefix("0x") else { return nil }
      return UInt32(text.dropFirst(2), radix: 16)
    }

    func bytes(from value: UInt32) -> Int? {
      let masked = value & mask
      let kib = masked >> mask.trailingZeroBitCount
      guard masked != mask, (1...65536).contains(kib) else { return nil }
      return Int(kib) * 1024
    }
  }

  private func temporaryDirectory() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Tekmor-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    return folder
  }

  public func write(
    _ image: FirmwareImage, to connection: ChipConnection, confirmed: ChipInformation,
    log: @escaping ToolLog = { _ in }
  ) async throws {
    try image.validateInternalFlash(capacity: confirmed.flashBytes)
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let command: [String]
    if let address = image.binaryAddress, let segment = image.segments.first {
      let snapshot = folder.appendingPathComponent("firmware.bin")
      try segment.bytes.write(to: snapshot)
      command = ["-w", snapshot.path, String(format: "0x%08llX", address), "-v"]
    } else {
      let snapshot = folder.appendingPathComponent("firmware.hex")
      try image.intelHEX().write(to: snapshot)
      command = ["-w", snapshot.path, "-v"]
    }
    _ = try await read(connection, confirming: confirmed, log: log)
    let result: CommandResult
    do {
      result = try await execute(
        connection, command, confirmedSerial: confirmed.probeSerialNumber,
        reuseUART: true, programming: true,
        timeout: deadline(connection.flashMethod, image.byteCount), log: log)
    } catch let timeout as CommandTimeout {
      let diagnostic = ChipInformation.plainText(timeout.result?.diagnostic ?? "")
      let verified = Self.reportsVerification(diagnostic) && !Self.reportsError(diagnostic)
      throw FlashFailure.timedOut(.init(write: verified ? .verified : .unknown))
    }
    guard result.succeeded, !Self.reportsError(result.diagnostic),
      Self.reportsVerification(result.diagnostic)
    else {
      throw FlashFailure(
        TekmorLocalization.core(
          .init(
            "core.cube.writeFailed",
            defaultValue: "CubeProgrammer write or verification failed. See log for details.",
            bundle: .atURL(Bundle.module.bundleURL))), progress: .init(write: .unknown))
    }
  }

  public func reset(
    _ connection: ChipConnection, confirmed: ChipInformation? = nil,
    log: @escaping ToolLog = { _ in }
  ) async throws {
    let result: CommandResult
    do {
      result = try await resetCommand(connection, confirmed: confirmed, log: log)
    } catch let timeout as CommandTimeout {
      let diagnostic = ChipInformation.plainText(timeout.result?.diagnostic ?? "")
      throw FlashFailure.timedOut(
        .init(write: .verified, reset: Self.reportsReset(diagnostic) ? .confirmed : .unconfirmed))
    }
    guard result.succeeded, Self.reportsReset(result.diagnostic) else {
      throw FlashFailure(
        TekmorLocalization.core(
          .init(
            "core.cube.resetUnconfirmed",
            defaultValue:
              "Write verified, but SWD reset was not confirmed. Check the log or reset manually.",
            bundle: .atURL(Bundle.module.bundleURL))),
        progress: .init(write: .verified, reset: .unconfirmed))
    }
  }

  /// Resets a selected SWD target and requires a positive reset report.
  public func resetTarget(
    _ connection: ChipConnection, confirmed: ChipInformation,
    log: @escaping ToolLog = { _ in }
  ) async throws {
    guard case .swd = connection else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.requiresSWD", defaultValue: "Target reset requires ST-LINK / SWD.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let result = try await resetCommand(connection, confirmed: confirmed, log: log)
    guard result.succeeded, Self.reportsReset(result.diagnostic) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.targetResetUnconfirmed",
            defaultValue: "Target reset was not confirmed. Check the log or reset manually.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  /// Erases internal Flash on the selected, previously identified target.
  public func erase(
    _ connection: ChipConnection, confirmed: ChipInformation,
    log: @escaping ToolLog = { _ in }
  ) async throws {
    _ = try await read(connection, confirming: confirmed, log: log)
    let result = try await execute(
      connection, ["-e", "all"], confirmedSerial: confirmed.probeSerialNumber, reuseUART: true,
      programming: true, timeout: .seconds(90), log: log)
    guard result.succeeded, !Self.reportsError(result.diagnostic),
      result.diagnostic.localizedCaseInsensitiveContains("mass erase successfully achieved")
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.eraseUnconfirmed",
            defaultValue: "Full Flash erase was not confirmed. See the log for details.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  func startUARTApplication(
    _ connection: ChipConnection, address: UInt64, log: @escaping ToolLog
  ) async throws {
    let result = try await execute(
      connection, ["--start", String(format: "0x%08llX", address)], reuseUART: true,
      timeout: resetDeadline, log: log)
    guard result.succeeded, !Self.reportsError(result.diagnostic),
      result.diagnostic.localizedCaseInsensitiveContains("start operation achieved successfully")
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.startUnconfirmed",
            defaultValue: "UART application start was not confirmed. Reset the board manually.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  private func checkTarget(_ observed: ChipInformation, confirmed: ChipInformation) throws {
    guard observed.sameTarget(as: confirmed) else {
      throw Self.targetChanged
    }
  }

  static var targetChanged: TekmorError {
    TekmorError(
      TekmorLocalization.core(
        .init(
          "core.cube.targetChanged",
          defaultValue: "Target chip information changed. Re-read and confirm the target.",
          bundle: .atURL(Bundle.module.bundleURL))))
  }

  private func resetCommand(
    _ connection: ChipConnection, confirmed: ChipInformation?, log: @escaping ToolLog
  ) async throws -> CommandResult {
    try await execute(
      connection, ["-rst"], confirmedSerial: confirmed?.probeSerialNumber,
      timeout: resetDeadline, log: log)
  }

  private func execute(
    _ connection: ChipConnection, _ command: [String], confirmedSerial: String? = nil,
    reuseUART: Bool = false, programming: Bool = false, timeout: Duration? = nil,
    log: @escaping ToolLog
  ) async throws -> CommandResult {
    try Task.checkCancellation()
    guard isPresent(connection) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.connectionLostBefore",
            defaultValue: "Target port or ST-LINK was disconnected or changed.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let arguments = try connection.arguments(
      probes: probes(), confirmedSerial: confirmedSerial,
      reuseUART: reuseUART, programming: programming)
    let result = try await cli.run(
      ["programmer"] + arguments + command,
      timeout: timeout
    ) { log(ChipInformation.plainText($0)) }
    guard isPresent(connection) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.connectionLostDuring",
            defaultValue: "Connection to the target was lost during the operation.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return CommandResult(
      status: result.status, output: ChipInformation.plainText(result.output),
      errorOutput: ChipInformation.plainText(result.errorOutput))
  }

  private static func reportsError(_ output: String) -> Bool {
    output.lowercased().split(whereSeparator: \.isNewline).contains {
      $0.contains("error:") || $0.contains("verification failed")
    }
  }

  private static func reportsVerification(_ output: String) -> Bool {
    let lower = output.lowercased()
    return lower.contains("download verified successfully")
      || lower.contains("verification successful")
  }

  private static func reportsReset(_ output: String) -> Bool {
    let lower = output.lowercased()
    return !reportsError(output)
      && (lower.contains("reset is performed") || lower.contains("reset successful"))
  }
}
