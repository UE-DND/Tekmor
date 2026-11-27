import Darwin
import Foundation
import Testing

@testable import TekmorCore

@Test func projectConfigurationValidatesRuntimeSettings() throws {
  var configuration = ProjectConfiguration()
  #expect(configuration.mcu == nil)
  try configuration.validate()

  configuration.mcu = "STM32F407VGT6"
  configuration.cmake = CMakeSettings(configurePreset: "Debug", target: "Blink_Test")
  configuration.flash = .swd
  try configuration.validate()

  var toolchainOnly = ProjectConfiguration()
  toolchainOnly.cmake = CMakeSettings(target: "Blink", toolchainFile: "cmake/gcc-arm.cmake")
  try toolchainOnly.validate()

  var invalidMCU = configuration
  invalidMCU.mcu = "F407"
  #expect(throws: TekmorError.self) { try invalidMCU.validate() }

  var outsideToolchain = ProjectConfiguration()
  outsideToolchain.cmake = CMakeSettings(target: "Build", toolchainFile: "../outside.cmake")
  #expect(throws: TekmorError.self) { try outsideToolchain.validate() }

  var absoluteToolchain = ProjectConfiguration()
  absoluteToolchain.cmake = CMakeSettings(toolchainFile: "/tmp/toolchain.cmake")
  #expect(throws: TekmorError.self) { try absoluteToolchain.validate() }

  var conflictingPresetAndToolchain = ProjectConfiguration()
  conflictingPresetAndToolchain.cmake = CMakeSettings(
    configurePreset: "Debug", toolchainFile: "cmake/gcc-arm.cmake")
  #expect(throws: TekmorError.self) { try conflictingPresetAndToolchain.validate() }

  var invalidTarget = ProjectConfiguration()
  invalidTarget.cmake.target = "-bad"
  #expect(throws: TekmorError.self) { try invalidTarget.validate() }

  var invalidSerial = ProjectConfiguration()
  invalidSerial.serial.baud = 12345
  #expect(throws: TekmorError.self) { try invalidSerial.validate() }
}

@Test func installsCubeInCustomDirectoryAndPreservesSuccessfulInstallationOnFailure() async throws {
  let fixture = try await cubeArchiveFixture(body: "printf 'cube wrapper version: 0.10.3\\n'")
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let root = fixture.directory.appendingPathComponent("custom tools directory")
  let installer = CubeInstallation(
    directory: root, archiveURL: fixture.archive, expectedDigest: fixture.sha256)
  try await installer.install()
  #expect(installer.cli != nil)
  #expect(FileManager.default.isExecutableFile(atPath: installer.executable.path))
  let stamp = installer.executable.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".tekmor.sha256")
  #expect(try String(contentsOf: stamp, encoding: .utf8) == fixture.sha256)

  let rejected = CubeInstallation(
    directory: root, archiveURL: fixture.archive, expectedDigest: String(repeating: "0", count: 64))
  await #expect(throws: TekmorError.self) { try await rejected.install() }
  #expect(installer.cli != nil)
  #expect(try String(contentsOf: stamp, encoding: .utf8) == fixture.sha256)
  let versions = root.appendingPathComponent("cube")
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: versions.path) == [CubeInstallation.version]
  )
}

@Test func cancelledCubeInstallationLeavesNoPublishedOrPartialVersion() async throws {
  let fixture = try await cubeArchiveFixture(body: "printf 'probing\\n'; exec /bin/sleep 30")
  defer { try? FileManager.default.removeItem(at: fixture.directory) }
  let root = fixture.directory.appendingPathComponent("tools")
  let installer = CubeInstallation(
    directory: root, archiveURL: fixture.archive, expectedDigest: fixture.sha256)
  let (messages, stream) = AsyncStream<String>.makeStream()
  let task = Task { try await installer.install(log: { stream.yield($0) }) }
  for await message in messages where message.contains("probing") {
    task.cancel()
    stream.finish()
    break
  }
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(installer.cli == nil)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("cube").path)
      .isEmpty)
}

@Test func preservesUTF8AcrossSerialReads() {
  var decoder = SerialDecoder()
  let text = "Rain é 雨 ☔ 🌧\n"
  let bytes = Array(text.utf8)
  let output = bytes.indices.map { decoder.append(bytes[$0...$0]) }.joined()
  #expect(output == text)

  let invalidBytes: [UInt8] = [0xFF]
  #expect(decoder.append(invalidBytes[...]) == "\u{FFFD}")
  let recovered = bytes.indices.map { decoder.append(bytes[$0...$0]) }.joined()
  #expect(recovered == text)
}

@Test func consoleRetainsBoundedRecentOutputAndCountsDroppedInput() {
  let inbox = ConsoleInbox()
  let input = String(repeating: "🌧雨\n", count: 70_001)
  #expect(inbox.append(input))
  #expect(!inbox.append("latest 雨"))
  let batch = inbox.drain(scheduled: true)
  #expect(batch.hasGap)
  #expect(batch.text.utf8.count <= 512_000)
  #expect(batch.text.hasSuffix("latest 雨"))
  #expect(!batch.text.contains("\u{fffd}"))
  #expect(batch.byteCount == input.utf8.count + "latest 雨".utf8.count)
  #expect(batch.newlineCount == 70_001)
  #expect(inbox.append("new"))
  #expect(inbox.drain().text == "new")
  #expect(!inbox.append("after synchronous drain"))
  #expect(inbox.drain(scheduled: true).text == "after synchronous drain")

  var buffer = ConsoleBuffer(.serial)
  buffer.append(batch.text, timestamp: "12:00", showTimestamp: true, hasGap: batch.hasGap)
  #expect(buffer.lines.count <= 4_000)
  #expect(buffer.lines.first?.text == "…")
  #expect(buffer.lines.last?.text == "latest 雨")
  #expect(buffer.transcript.utf8.count <= 512_000)
  #expect(buffer.transcript.hasSuffix("12:00  latest 雨"))
  #expect(!buffer.transcript.contains("\u{fffd}"))
}

@Test func consoleBoundsUnterminatedLinesAndPreservesNormalFormatting() {
  var buffer = ConsoleBuffer(.build)
  buffer.append("partial warning:")
  let firstID = buffer.lines.first?.id
  buffer.append(" message\r")
  buffer.append("\nnext\n")
  #expect(buffer.transcript == "partial warning: message\nnext\n")
  #expect(buffer.lines.map(\.text) == ["partial warning: message", "next"])
  #expect(buffer.lines.first?.id == firstID)
  #expect(buffer.lines.first?.kind == .warning)

  buffer.clear()
  let fragment = String(repeating: "雨🌧", count: 1000)
  for _ in 0..<100 { buffer.append(fragment) }
  #expect(buffer.lines.count == 1)
  #expect((buffer.lines.first?.text.utf8.count ?? 0) <= 8192)
  #expect(buffer.lines.first?.text.hasPrefix("…") == true)
  #expect(buffer.transcript.utf8.count <= 512_000)
  #expect(!buffer.transcript.contains("\u{fffd}"))
  buffer.append(String(repeating: "\n" + fragment, count: 100))
  #expect(buffer.lines.reduce(0) { $0 + $1.text.utf8.count } <= 512_000)

  var serial = ConsoleBuffer(.serial)
  serial.append("Rain", timestamp: "12:00", showTimestamp: true)
  serial.append(" 雨\r", timestamp: "12:01", showTimestamp: true)
  serial.append("\nDry\n", timestamp: "12:02", showTimestamp: true)
  #expect(serial.transcript == "12:00  Rain 雨\n12:02  Dry\n")
  #expect(serial.lines.map(\.timestamp) == ["12:00", "12:02"])
}

@Test func processGroupsCancelDescendantsHoldingLogPipes() async {
  let (messages, log) = AsyncStream<String>.makeStream()
  let task = Task {
    try await CommandRunner().run(
      URL(filePath: "/bin/sh"),
      [
        "-c", "trap '' TERM; /bin/sleep 30 & printf 'ready\\n'; wait",
      ]
    ) { message in
      log.yield(message)
    }
  }
  for await message in messages where message.contains("ready") {
    task.cancel()
    log.finish()
    break
  }

  await #expect(throws: CancellationError.self) { try await task.value }
}

private func withDirectory(_ action: (URL) throws -> Void) throws {
  let directory = try makeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  try action(directory)
}

private func makeDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("TekmorTests-\(UUID())", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}

private func elf() -> Data {
  var data = Data(repeating: 0, count: 0x110)
  data.replaceSubrange(0..<7, with: [0x7f, 69, 76, 70, 1, 1, 1])
  setWord(&data, at: 16, value: 2 | (40 << 16))  // ET_EXEC and ARM
  setWord(&data, at: 20, value: 1)
  setWord(&data, at: 28, value: 52)
  setWord(&data, at: 40, value: 52 | (32 << 16))
  setWord(&data, at: 44, value: 1)
  setWord(&data, at: 52, value: 1)
  setWord(&data, at: 56, value: 0x100)
  setWord(&data, at: 60, value: 0x0800_0000)
  setWord(&data, at: 64, value: 0x0800_0000)
  setWord(&data, at: 68, value: 16)
  setWord(&data, at: 72, value: 16)
  setWord(&data, at: 76, value: 5)
  setWord(&data, at: 0x100, value: 0x2000_c000)
  setWord(&data, at: 0x104, value: 0x0800_000d)
  return data
}

private func setWord(_ data: inout Data, at offset: Int, value: Int) {
  for index in 0..<4 {
    data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
  }
}

@Test func elfCountsAllocatedSectionsAndValidatesUARTVector() throws {
  var data = elf()
  let strings = Data([0] + Array(".isr_vector\0.text\0.data\0.bss\0.debug_info\0".utf8))
  data.append(strings)
  let table = data.count
  data.append(Data(repeating: 0, count: 7 * 40))
  setWord(&data, at: 32, value: table)
  setWord(&data, at: 46, value: 40 | (7 << 16))
  data[50] = 1
  setWord(&data, at: table + 40 + 4, value: 3)
  setWord(&data, at: table + 40 + 16, value: 0x110)
  setWord(&data, at: table + 40 + 20, value: strings.count)
  let sections = [
    (1, 1, 2, 0x0800_0000, 0x100, 8),
    (13, 1, 6, 0x0800_0008, 0x108, 8),
    (19, 1, 3, 0x2000_0000, 0x10c, 4),
    (25, 8, 3, 0x2000_0004, 0, 36),
    (30, 1, 0, 0, 0x110, 3),
  ]
  for (index, section) in sections.enumerated() {
    let header = table + (index + 2) * 40
    for (field, value) in [section.0, section.1, section.2, section.3, section.4, section.5]
      .enumerated()
    {
      setWord(&data, at: header + field * 4, value: value)
    }
  }
  let image = try FirmwareImage(data: data, format: "elf")
  #expect(image.internalFlashBytes == 16)
  #expect(image.staticRAMBytes == 40)
  #expect(image.sections?.map(\.name) == [".isr_vector", ".text", ".data", ".bss"])
  #expect(image.applicationStartAddress == 0x0800_0000)

  setWord(&data, at: 0x104, value: 0x0801_000d)
  #expect(try FirmwareImage(data: data, format: "elf").applicationStartAddress == nil)
  setWord(&data, at: table + 3 * 40, value: strings.count)
  let corruptSections = try FirmwareImage(data: data, format: "elf")
  #expect(corruptSections.staticRAMBytes == nil)
  #expect(corruptSections.internalFlashBytes == 16)
}

@Test func genericFirmwareUsesPhysicalAddressesAndKeepsGaps() throws {
  var data = elf()
  setWord(&data, at: 44, value: 2)
  setWord(&data, at: 64, value: 0x0802_0000)
  setWord(&data, at: 84, value: 1)
  setWord(&data, at: 88, value: 0x108)
  setWord(&data, at: 92, value: 0x2400_0000)
  setWord(&data, at: 96, value: 0x0804_0010)
  setWord(&data, at: 100, value: 8)
  setWord(&data, at: 104, value: 12)  // .data initializer only, excluding zero-filled bytes
  let image = try FirmwareImage(data: data, format: "elf")
  #expect(image.ranges == [0x0802_0000..<0x0802_0010, 0x0804_0010..<0x0804_0018])
  #expect(image.byteCount == 24)
  try image.validateInternalFlash(capacity: 1024 * 1024)
  #expect(throws: TekmorError.self) { try image.validateInternalFlash(capacity: 256 * 1024) }
  #expect(throws: TekmorError.self) { try image.validateInternalFlash(capacity: nil) }
  #expect(try FirmwareImage(data: image.intelHEX(), format: "hex").segments == image.segments)

  setWord(&data, at: 96, value: 0x0802_0004)
  #expect(throws: TekmorError.self) { try FirmwareImage(data: data, format: "elf") }
  #expect(throws: TekmorError.self) { try FirmwareImage(data: data.dropLast(), format: "elf") }
}

@Test func armELFStructuralChecksAcceptReadOnlySegmentsAndSlicedData() throws {
  let original = elf()
  let slice = (Data([0]) + original).dropFirst()
  #expect(slice.startIndex == 1)
  #expect(
    try FirmwareImage(data: slice, format: "elf").segments.first?.bytes
      == original.subdata(in: 0x100..<0x110))

  var invalid = original
  setWord(&invalid, at: 72, value: 15)  // p_memsz smaller than p_filesz
  #expect(throws: TekmorError.self) { try FirmwareImage(data: invalid, format: "elf") }

  var noExecutableSegment = original
  setWord(&noExecutableSegment, at: 76, value: 4)  // read-only, no execute bit
  let cubeImage = try FirmwareImage(data: noExecutableSegment, format: "elf")
  try cubeImage.validateInternalFlash(capacity: 256 * 1024)

  var lastBytes = original
  setWord(&lastBytes, at: 64, value: 0xffff_fff0)
  #expect(try FirmwareImage(data: lastBytes, format: "elf").ranges == [0xffff_fff0..<0x1_0000_0000])
  setWord(&lastBytes, at: 64, value: 0xffff_fff1)
  #expect(throws: TekmorError.self) { try FirmwareImage(data: lastBytes, format: "elf") }
}

@Test func hexChecksumAndBinaryAddressAreValidated() throws {
  let bytes = Data([0x00, 0x12, 0x34, 0x56])
  let image = try FirmwareImage(data: bytes, format: "bin", binaryAddress: 0x0800_FFFE)
  #expect(image.binaryAddress == 0x0800_FFFE)
  #expect(image.ranges == [0x0800_FFFE..<0x0801_0002])
  let decoded = try FirmwareImage(data: image.intelHEX(), format: "hex")
  #expect(decoded.ranges == image.ranges)
  #expect(decoded.segments.flatMap(\.bytes) == Array(bytes))
  #expect(throws: TekmorError.self) { try FirmwareImage(data: bytes, format: "bin") }
  #expect(throws: TekmorError.self) {
    try FirmwareImage(data: bytes, format: "bin", binaryAddress: 0xFFFF_FFFF)
  }
  #expect(throws: TekmorError.self) {
    try FirmwareImage(data: Data(":00000001FE\n".utf8), format: "hex")
  }
  #expect(throws: TekmorError.self) {
    try FirmwareImage(data: Data(":020000040800F2\n".utf8), format: "hex")
  }
}

@Test func parsesCubeTargetInformation() throws {
  let info = try ChipInformation.parseProgrammer(
    """
    \u{001B}[39;49m\u{001B}[0mDevice ID : 0x414
    Device name : STM32F101/F103 High-density
    NVM size : 256 KBytes
    Device type : MCU
    Revision ID : Rev X
    Voltage : 3.27V
    BL Version : --
    """)
  #expect(info.id == 0x414)
  #expect(info.flashBytes == 256 * 1024)
  #expect(info.bootloader == nil)
  #expect(info.match(expected: "STM32F103VCT6") == .ambiguous)
  #expect(info.match(expected: "STM32F411CEU6") == .mismatch)
  #expect(info.match(expected: "STM32F103C8T6") == .ambiguous)
  #expect(throws: TekmorError.self) {
    try ChipInformation.parseProgrammer("Error: No STM32 target found!")
  }
}

@Test func respectsProbeIdentity() throws {
  let first = STLinkProbe(id: 1, label: "ST-LINK", serialNumber: "123456")
  let other = STLinkProbe(id: 2, label: "ST-LINK", serialNumber: nil)
  let duplicate = STLinkProbe(id: 3, label: "ST-LINK", serialNumber: "123456")
  let arguments = try ChipConnection.swd(first).arguments(probes: [first, other])
  #expect(arguments.contains("sn=123456"))
  #expect(arguments.contains("mode=HOTPLUG"))
  #expect(throws: TekmorError.self) {
    try ChipConnection.swd(other).arguments(probes: [first, other])
  }
  #expect(throws: TekmorError.self) {
    try ChipConnection.swd(first).arguments(probes: [first, duplicate])
  }
}

@Test func cubeWriteRejectsChangedTargetsAndRequiresPositiveVerification() async throws {
  let directory = try makeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let tool = directory.appendingPathComponent("cube")
  try #"""
  #!/bin/sh
  root=$(/usr/bin/dirname "$0")
  printf '%s\n' "$*" >> "$root/commands"
  case "$*" in
      *' -w '*)
          shift 6
          /bin/cp "$1" "$root/written.hex" || exit 1
          if [ -f "$root/fail-verify" ]; then
              printf 'Error: verification failed\n'
          else
              printf 'Download verified successfully\n'
          fi
          ;;
      *' -rst'*) printf 'Reset is performed\n' ;;
      *) /bin/cat "$root/target" ;;
  esac
  """#.write(to: tool, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
  let target = directory.appendingPathComponent("target")
  let first = "Device ID: 0x413\nDevice name: STM32F407xx\nFlash size: 1 MBytes\nVoltage: 3.28V\n"
  try first.write(to: target, atomically: true, encoding: .utf8)
  let probe = STLinkProbe(id: 1, label: "ST-LINK", serialNumber: "1234")
  let connection = ChipConnection.swd(probe)
  let programmer = CubeProgrammer(
    cli: CubeCLI(executable: tool),
    isPresent: { _ in true }, probes: { [probe] })
  let info = try await programmer.read(connection)
  let image = try FirmwareImage(data: elf(), format: "elf")
  try first.replacingOccurrences(of: "0x413", with: "0x415").write(
    to: target, atomically: true, encoding: .utf8)
  await #expect(throws: TekmorError.self) {
    try await programmer.write(image, to: connection, confirmed: info)
  }
  let commands = directory.appendingPathComponent("commands")
  #expect(!(try String(contentsOf: commands, encoding: .utf8)).contains(" -w "))
  try first.replacingOccurrences(of: "3.28V", with: "3.27V").write(
    to: target, atomically: true, encoding: .utf8)
  try await programmer.write(image, to: connection, confirmed: info)
  #expect(try Data(contentsOf: directory.appendingPathComponent("written.hex")) == image.intelHEX())

  let binary = try FirmwareImage(
    data: Data([1, 2, 3, 4]), format: "bin", binaryAddress: 0x0802_0000)
  try await programmer.write(binary, to: connection, confirmed: info)
  #expect(
    (try String(contentsOf: commands, encoding: .utf8)).contains("firmware.bin 0x08020000 -v"))

  try Data().write(to: directory.appendingPathComponent("fail-verify"))
  await #expect(throws: FlashFailure.self) {
    try await programmer.write(image, to: connection, confirmed: info)
  }
  #expect(!(try String(contentsOf: commands, encoding: .utf8)).contains(" -rst"))
  try await programmer.reset(connection)

  let absent = CubeProgrammer(
    cli: CubeCLI(executable: tool),
    isPresent: { _ in false }, probes: { [] })
  await #expect(throws: TekmorError.self) { try await absent.read(connection) }
}

@Test func boundedHardwareCommandsTimeOut() async throws {
  let started = ContinuousClock.now
  await #expect(throws: CommandTimeout.self) {
    try await CommandRunner().run(URL(filePath: "/bin/sleep"), ["30"], timeout: .milliseconds(100))
  }
  #expect(started.duration(to: .now) < .seconds(5))
}

@Test func timeoutRetainsOutputFromProcessGroupHoldingPipes() async throws {
  do {
    _ = try await CommandRunner().run(
      URL(filePath: "/bin/sh"),
      [
        "-c", "trap '' TERM; /bin/sleep 30 & printf 'before deadline\\n' >&2; wait",
      ], timeout: .milliseconds(150))
    Issue.record("Expected the process group to time out")
  } catch let error as CommandTimeout {
    #expect(error.result?.errorOutput == "before deadline\n")
    #expect(error.result?.status == 137)
  }
}

@Test func cubeTimeoutRetainsVerificationAndIndependentResetEvidence() async throws {
  let directory = try makeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let tool = directory.appendingPathComponent("cube")
  try writeExecutable(
    tool,
    body: #"""
      root=$(/usr/bin/dirname "$0")
      case "$*" in
          *' -w '*) [ ! -f "$root/verified" ] || printf 'Download verified successfully\n'; exec /bin/sleep 30 ;;
          *' -rst') [ ! -f "$root/reset" ] || printf 'Reset is performed\n'; exec /bin/sleep 30 ;;
          *) printf 'Device ID: 0x413\nDevice name: STM32F407xx\nFlash size: 1 MBytes\n' ;;
      esac
      """#)
  let probe = STLinkProbe(id: 1, label: "ST-LINK", serialNumber: "1234")
  let connection = ChipConnection.swd(probe)
  let programmer = CubeProgrammer(
    cli: CubeCLI(executable: tool),
    isPresent: { _ in true }, probes: { [probe] },
    deadline: { _, _ in .milliseconds(150) }, resetDeadline: .milliseconds(150))
  let info = try await programmer.read(connection)
  let image = try FirmwareImage(data: elf(), format: "elf")
  await expectFlashFailure(.init(write: .unknown)) {
    try await programmer.write(image, to: connection, confirmed: info)
  }
  try Data().write(to: directory.appendingPathComponent("verified"))
  await expectFlashFailure(.init(write: .verified)) {
    try await programmer.write(image, to: connection, confirmed: info)
  }
  await expectFlashFailure(.init(write: .verified, reset: .unconfirmed)) {
    try await programmer.reset(connection, confirmed: info)
  }
  try Data().write(to: directory.appendingPathComponent("reset"))
  await expectFlashFailure(.init(write: .verified, reset: .confirmed)) {
    try await programmer.reset(connection, confirmed: info)
  }
}

private func expectFlashFailure(_ expected: FlashProgress, action: () async throws -> Void) async {
  do {
    try await action()
    Issue.record("Expected flashing to fail")
  } catch let error as FlashFailure {
    #expect(error.progress == expected)
  } catch {
    Issue.record("Unexpected flash error \(error)")
  }
}

private func writeExecutable(_ file: URL, body: String) throws {
  try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
}

private struct CubeArchiveFixture {
  let directory: URL
  let archive: URL
  let sha256: String
}

private func cubeArchiveFixture(body: String) async throws -> CubeArchiveFixture {
  let directory = try makeDirectory()
  let payload = directory.appendingPathComponent("payload")
  let bin = payload.appendingPathComponent("bin")
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  try writeExecutable(bin.appendingPathComponent("cube"), body: body)
  let archive = directory.appendingPathComponent("cube.bundle")
  let result = try await CommandRunner().run(
    URL(filePath: "/usr/bin/ditto"), ["-c", "-k", payload.path, archive.path])
  try result.requireSuccess("Creating CubeCLI test package")
  return CubeArchiveFixture(
    directory: directory, archive: archive, sha256: try CubeInstallation.digest(archive))
}

private func writeMockBundles(in directory: URL) throws {
  let tools = [
    ("cmake", "cmake", "cmake"),
    ("gnu-tools-for-stm32", "gcc", "arm-none-eabi-gcc"),
    ("ninja", "ninja", "ninja"),
  ]
  var entries: [[String: Any]] = []
  for (name, folder, executable) in tools {
    let root = directory.appendingPathComponent(folder)
    let bin = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try writeExecutable(
      bin.appendingPathComponent(executable), body: "printf 'Mock version 1.0\\n'")
    if folder == "gcc" {
      try writeExecutable(
        bin.appendingPathComponent("arm-none-eabi-g++"), body: "printf 'Mock version 1.0\\n'")
    }
    entries.append([
      "path": root.path, "details": ["name": name, "version": "1.0", "platform": "aarch64-darwin"],
    ])
  }
  let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
  try data.write(to: directory.appendingPathComponent("bundles.json"))
}

private func addMockCompilerVersion(in directory: URL, version: String) throws {
  let root = directory.appendingPathComponent("gcc-" + version)
  let bin = root.appendingPathComponent("bin")
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  for name in ["arm-none-eabi-gcc", "arm-none-eabi-g++"] {
    try writeExecutable(
      bin.appendingPathComponent(name), body: "printf 'Mock version \(version)\\n'")
  }
  let file = directory.appendingPathComponent("bundles.json")
  var bundles = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
  bundles.append([
    "path": root.path,
    "details": ["name": "gnu-tools-for-stm32", "version": version, "platform": "aarch64-darwin"],
  ])
  try JSONSerialization.data(withJSONObject: bundles).write(to: file)
}

@Test func cubeCLIDefaultsWorkingDirectoryToToolRootInsteadOfHome() async throws {
  let root = try makeDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let bin = root.appendingPathComponent("cube/0.10.3/bin", isDirectory: true)
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  let tool = bin.appendingPathComponent("cube")
  try writeExecutable(tool, body: "pwd")

  let withToolRoot = CubeCLI(executable: tool, directory: root)
  let rootResult = try await withToolRoot.run(["--version"])
  #expect(
    URL(filePath: rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
      .resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path)

  let withoutToolRoot = CubeCLI(executable: tool)
  let binResult = try await withoutToolRoot.run(["--version"])
  #expect(
    URL(filePath: binResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
      .resolvingSymlinksInPath().path == bin.resolvingSymlinksInPath().path)
}

@MainActor
@Test func globalBundleSelectionIgnoresProjectLocksAndSupportsSingleInstall() async throws {
  #expect(CubeCLI.displayVersion(from: "cube wrapper version: 0.10.3") == "0.10.3")
  #expect(CubeCLI.displayVersion(from: "Mock CubeCLI") == "Mock CubeCLI")

  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  try addMockCompilerVersion(in: fixture.project, version: "2.0")
  let settings = fixture.project.appendingPathComponent(".settings")
  try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: false)
  try Data("{}".utf8).write(to: settings.appendingPathComponent("bundles.store.json"))

  let status = try await fixture.cube.toolStatus()
  #expect(status.buildIssue == nil)
  #expect(status.buildBundles.count == 3)
  #expect(status.buildBundles.first { $0.name == "gnu-tools-for-stm32" }?.version == "2.0")
  #expect(status.systemMake.path.path == "/usr/bin/make")
  let runtime = try await fixture.cube.buildRuntime()
  #expect(
    runtime.gcc?.path
      == fixture.project.appendingPathComponent("gcc-2.0/bin/arm-none-eabi-gcc").path)
  #expect(
    runtime.cli.processEnvironment["ARM_GNU_ROOT"]
      == fixture.project.appendingPathComponent("gcc-2.0").path)
  let paths = (runtime.cli.processEnvironment["PATH"] ?? "").split(separator: ":").map(String.init)
  let compilerPath = try #require(
    paths.firstIndex(of: fixture.project.appendingPathComponent("gcc-2.0/bin").path))
  let systemPath = try #require(paths.firstIndex(of: "/opt/homebrew/bin"))
  #expect(compilerPath < systemPath)
  #expect(status.programmerIssue != nil)

  let listing = fixture.project.appendingPathComponent("bundles.json")
  let withProgrammer = try addMockProgrammer(in: fixture.project, to: Data(contentsOf: listing))
  try withProgrammer.write(to: fixture.project.appendingPathComponent("prepared-bundles.json"))
  try await fixture.cube.installBundle("programmer")
  let afterProgrammer = try await fixture.cube.toolStatus()
  #expect(afterProgrammer.programmerIssue == nil)
  await #expect(throws: TekmorError.self) {
    try await fixture.cube.installBundle("unknown-bundle")
  }
  let commands = try fixture.commands()
  #expect(commands.contains("bundle install programmer --yes"))
  #expect(!commands.contains("--project"))
}

private func addMockProgrammer(in directory: URL, to listingData: Data) throws -> Data {
  let root = directory.appendingPathComponent("programmer")
  let bin = root.appendingPathComponent("bin")
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  try writeExecutable(
    bin.appendingPathComponent("STM32_Programmer_CLI"), body: "printf 'Mock programmer 2.0\\n'")
  var bundles = try #require(JSONSerialization.jsonObject(with: listingData) as? [[String: Any]])
  bundles.append([
    "path": root.path,
    "details": ["name": "programmer", "version": "2.0", "platform": "aarch64-darwin"],
  ])
  return try JSONSerialization.data(withJSONObject: bundles)
}

@MainActor
@Test func compilerVersionChangeSelectsANewBuildCache() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let maker = CMakeBuild(cache: fixture.project.appendingPathComponent("cache"))
  let options = CMakeSettings(configurePreset: "Debug")
  let first = try await maker.configure(
    project: fixture.project, options: options, cli: fixture.cube)
  try addMockCompilerVersion(in: fixture.project, version: "2.0")
  let second = try await maker.configure(
    project: fixture.project, options: options, cli: fixture.cube)
  #expect(first.directory != second.directory)
}

@MainActor
@Test func manualBundlePreparationCanRetryAfterFailureAndInstallMissingTools() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let listing = fixture.project.appendingPathComponent("bundles.json")
  let prepared = try Data(contentsOf: listing)
  try prepared.write(to: fixture.project.appendingPathComponent("prepared-bundles.json"))
  try Data("[]".utf8).write(to: listing)
  let before = try await fixture.cube.toolStatus()
  #expect(before.buildIssue != nil)
  let failure = fixture.project.appendingPathComponent("fail-install")
  try Data().write(to: failure)
  await #expect(throws: TekmorError.self) {
    try await fixture.cube.prepareBuildTools()
  }
  #expect(try Data(contentsOf: listing) == Data("[]".utf8))
  try FileManager.default.removeItem(at: failure)
  try await fixture.cube.prepareBuildTools()
  let ready = try await fixture.cube.toolStatus()
  #expect(ready.buildIssue == nil)
  let entries = try #require(JSONSerialization.jsonObject(with: prepared) as? [[String: Any]])
  let missingNinja = entries.filter {
    ($0["details"] as? [String: Any])?["name"] as? String != "ninja"
  }
  try JSONSerialization.data(withJSONObject: missingNinja).write(to: listing)
  let after = try await fixture.cube.toolStatus()
  #expect(after.buildBundles.first { $0.name == "ninja" }?.installed == false)
  let allPrepared = try addMockProgrammer(in: fixture.project, to: prepared)
  try allPrepared.write(to: fixture.project.appendingPathComponent("prepared-bundles.json"))
  try await fixture.cube.prepareAllTools()
  let allReady = try await fixture.cube.toolStatus()
  #expect(allReady.buildIssue == nil)
  #expect(allReady.programmerIssue == nil)
  let commands = try fixture.commands()
  #expect(commands.contains("bundle install --yes cmake gnu-tools-for-stm32 ninja"))
  #expect(commands.contains("bundle install --yes ninja programmer"))
  #expect(!commands.contains("bundle remove"))
  #expect(!commands.contains("--project"))
}

@MainActor
@Test func workflowRequiresManualToolPreparationBeforeInvokingCube() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  host.toolsAvailable = false
  await #expect(throws: TekmorError.self) {
    try await fixture.workflow.execute(
      .build, context: fixture.context(), interaction: host)
  }
  #expect(host.steps == ["tools"])
  #expect(
    !FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent("commands").path)
  )
}

@MainActor
@Test func workflowInspectsBuildsAndFlashesInOrder() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  let workflow = fixture.workflow

  let inspect = try await workflow.execute(.inspect, context: fixture.context(), interaction: host)
  #expect(inspect == .inspected(1))
  #expect(host.targets == ["Blink"])
  #expect(host.selectedTarget == "Blink")
  #expect(
    !FileManager.default.fileExists(
      atPath: fixture.project.appendingPathComponent("tekmor.json").path))
  #expect(host.steps == ["tools"])

  host.steps = []
  let result = try await workflow.execute(
    .run, context: fixture.context(), interaction: host)
  #expect(result == .flashed)
  #expect(
    host.steps == [
      "tools", "select", "build", "artifact", "read", "write", "write ended",
      "verified", "reset", "reset confirmed",
    ])
  #expect(host.selectedTarget == "Blink")
  #expect(
    !FileManager.default.fileExists(
      atPath: fixture.project.appendingPathComponent("tekmor.json").path))
  let commands = try fixture.commands().split(separator: "\n").filter {
    $0.hasPrefix("programmer ")
  }
  try #require(commands.count == 4)
  #expect(commands[0].contains("mode=HOTPLUG"))
  #expect(commands[1].contains("mode=HOTPLUG"))
  #expect(commands[2].contains("mode=NORMAL") && commands[2].contains(" -w "))
  #expect(commands[3].hasSuffix(" -rst"))
}

@MainActor
@Test func workflowStopsOnBuildFailureAndChangedTarget() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  let workflow = fixture.workflow

  let build = try await workflow.execute(
    .build, context: fixture.context(), interaction: host)
  guard case .built(let previous) = build else {
    Issue.record("Expected a built artifact")
    return
  }

  let buildFailure = fixture.project.appendingPathComponent("fail-build")
  try Data().write(to: buildFailure)
  host.steps = []
  await #expect(throws: TekmorError.self) {
    try await workflow.execute(.run, context: fixture.context(), interaction: host)
  }
  #expect(FileManager.default.fileExists(atPath: previous.path))
  #expect(host.artifact == nil)
  #expect(host.steps == ["tools", "select", "build"])
  try FileManager.default.removeItem(at: buildFailure)

  host.steps = []
  host.afterChipRead = {
    do {
      try Data().write(to: fixture.project.appendingPathComponent("changed-target"))
    } catch {
      Issue.record(error)
    }
  }
  await #expect(throws: TekmorError.self) {
    try await workflow.execute(.run, context: fixture.context(), interaction: host)
  }
  #expect(host.steps.suffix(3) == ["read", "write", "write ended"])
  #expect(!(try fixture.commands()).contains(" -w "))
  #expect(!host.writing)
}

@MainActor
@Test func workflowBuildsAndStartsVerifiedUARTApplication() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(
    connection: .uart(SerialDevice(id: "/dev/fake", label: "UART", registryID: 1)))
  let result = try await fixture.workflow.execute(
    .run, context: fixture.context(method: .uart), interaction: host)
  #expect(result == .flashed)
  #expect(
    host.steps == [
      "tools", "select", "build", "artifact", "read", "write", "write ended", "verified",
      "start", "started",
    ])
  #expect(host.preparedConnections == [host.connection])
  #expect(host.progress == .init(write: .verified))
  #expect(!host.writing)
  let commands = try fixture.commands()
  #expect(!commands.contains(" -rst"))
  #expect(commands.contains("noinit=1 --start 0x08000000"))
}

@MainActor
@Test func workflowKeepsVerifiedWriteWhenUARTStartIsUnconfirmed() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  try Data().write(to: fixture.project.appendingPathComponent("fail-start"))
  let host = WorkflowHost(
    connection: .uart(SerialDevice(id: "/dev/fake", label: "UART", registryID: 1)))
  let result = try await fixture.workflow.execute(
    .flash(fixture.image, address: nil, standalone: true),
    context: fixture.context(method: .uart), interaction: host)
  #expect(result == .flashed)
  #expect(
    host.steps == [
      "tools", "select", "read", "write", "write ended", "verified", "start",
    ])
  #expect(host.progress == .init(write: .verified))
  #expect(!host.writing)
  #expect(!(try fixture.commands()).contains(" -rst"))
}

@MainActor
@Test func workflowResetsAndErasesWithoutBuildingOrFlashingAnImage() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  let reset = try await fixture.workflow.execute(
    .resetTarget, context: fixture.context(), interaction: host)
  #expect(reset == .targetReset)
  #expect(host.steps == ["tools", "select", "read", "target reset"])
  host.steps = []
  let chip = try await fixture.programmer.read(host.connection)
  let confirmed = STM32Workflow.ConfirmedTarget(connection: host.connection, chip: chip)
  let erase = try await fixture.workflow.execute(
    .eraseFlash, context: fixture.context(confirmedTarget: confirmed), interaction: host)
  #expect(erase == .flashErased)
  #expect(host.steps == ["tools", "select", "read", "erase", "write ended"])
  #expect(!host.writing)
  #expect(host.preparedConnections == [host.connection, host.connection])
  let commands = try fixture.commands()
  #expect(commands.contains("mode=NORMAL sn=SERIAL -e all"))
  #expect(commands.contains(" -rst"))
  #expect(!commands.contains("cmake --build"))
  #expect(!commands.contains(" -w "))
}

@MainActor
@Test(arguments: [false, true])
func workflowRejectsChipChangedSinceConfirmation(erase: Bool) async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  let chip = try await fixture.programmer.identifyTarget(host.connection)
  let confirmed = STM32Workflow.ConfirmedTarget(connection: host.connection, chip: chip)
  try Data().write(to: fixture.project.appendingPathComponent("changed-target"))
  let action: STM32Workflow.Action =
    erase ? .eraseFlash : .flash(fixture.image, address: nil, standalone: true)

  await #expect(throws: TekmorError.self) {
    try await fixture.workflow.execute(
      action, context: fixture.context(confirmedTarget: confirmed), interaction: host)
  }
  #expect(host.steps == ["tools", "select", "read"])
  let commands = try fixture.commands()
  #expect(!commands.contains(" -w "))
  #expect(!commands.contains(" -e all"))
}

@MainActor
@Test func confirmedUARTFlashReusesTheIdentifiedBootloaderSession() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(
    connection: .uart(SerialDevice(id: "/dev/fake", label: "UART", registryID: 1)))
  let chip = try await fixture.programmer.identifyTarget(host.connection)
  let confirmed = STM32Workflow.ConfirmedTarget(connection: host.connection, chip: chip)
  try Data().write(to: fixture.project.appendingPathComponent("uart-already-synced"))

  let outcome = try await fixture.workflow.execute(
    .flash(fixture.image, address: nil, standalone: true),
    context: fixture.context(method: .uart, confirmedTarget: confirmed), interaction: host)
  #expect(outcome == .flashed)
  #expect(host.steps.last == "started")
}

@MainActor
@Test func workflowDoesNotEraseWhenTargetChangesAfterRead() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  host.afterChipRead = {
    do {
      try Data().write(to: fixture.project.appendingPathComponent("changed-target"))
    } catch {
      Issue.record(error)
    }
  }
  await #expect(throws: TekmorError.self) {
    try await fixture.workflow.execute(.eraseFlash, context: fixture.context(), interaction: host)
  }
  #expect(!host.writing)
  #expect(!(try fixture.commands()).contains(" -e all"))
}

@MainActor
@Test(arguments: [false, true])
func workflowStopsWhenTheSelectedPresetIsUnavailable(flash: Bool) async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  var configuration = ProjectConfiguration()
  configuration.flash = .swd
  configuration.cmake = CMakeSettings(configurePreset: "Release", target: "Blink")
  let context = STM32Workflow.Context(
    project: fixture.project, configuration: configuration, cube: fixture.cube)

  await #expect(throws: TekmorError.self) {
    try await fixture.workflow.execute(flash ? .run : .build, context: context, interaction: host)
  }
  #expect(host.presets == ["Debug"])
  #expect(host.selectedPreset == "Release")
  let commands = try fixture.commands()
  #expect(!commands.contains(" --preset "))
  #expect(!commands.contains("cmake --build"))
  #expect(!commands.contains("programmer "))
}

@MainActor
@Test func workflowDoesNotBuildTheOnlyRemainingTargetWhenSelectionDisappears() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let host = WorkflowHost(connection: .swd(fixture.probe))
  var configuration = ProjectConfiguration()
  configuration.flash = .swd
  configuration.cmake = CMakeSettings(configurePreset: "Debug", target: "Other")
  let context = STM32Workflow.Context(
    project: fixture.project, configuration: configuration, cube: fixture.cube)

  let result = try await fixture.workflow.execute(.run, context: context, interaction: host)
  #expect(result == .awaitingTarget)
  #expect(host.targets == ["Blink"])
  #expect(host.selectedTarget == nil)
  let commands = try fixture.commands()
  #expect(!commands.contains("cmake --build"))
  #expect(!commands.contains("programmer "))
}

@MainActor
@Test func multipleCMakeTargetsRequireOrPreserveAnExplicitSelection() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  try Data().write(to: fixture.project.appendingPathComponent("multiple-targets"))
  let host = WorkflowHost(connection: .swd(fixture.probe))
  let initial = try await fixture.workflow.execute(
    .inspect, context: fixture.context(), interaction: host)
  #expect(initial == .inspected(2))
  #expect(host.targets == ["Blink", "Other"])
  #expect(host.selectedTarget == nil)

  var configuration = ProjectConfiguration()
  configuration.cmake.target = "Other"
  let context = STM32Workflow.Context(
    project: fixture.project, configuration: configuration, cube: fixture.cube)
  _ = try await fixture.workflow.execute(.inspect, context: context, interaction: host)
  #expect(host.selectedTarget == "Other")
}

@MainActor
@Test(arguments: ["CMakeLists.txt", "cmake/targets.cmake"])
func cachedSelectionRefreshesWhenConfigureInputChanges(path: String) async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let builder = CMakeBuild(cache: fixture.project.appendingPathComponent("cache"))
  let options = CMakeSettings(configurePreset: "Debug")
  let initial = try await builder.configure(
    project: fixture.project, options: options, cli: fixture.cube)
  #expect(initial.targets == ["Blink"])

  let input = fixture.project.appending(path: path)
  let date = try #require(
    input.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate)
  try "# Changed contents with identical modification date\n".write(
    to: input, atomically: false, encoding: .utf8)
  try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: input.path)
  try Data().write(to: fixture.project.appendingPathComponent("multiple-targets"))
  let refreshed = try await builder.configure(
    project: fixture.project, options: options, cli: fixture.cube, preferCached: true)
  #expect(refreshed.directory == initial.directory)
  #expect(refreshed.targets == ["Blink", "Other"])
}

@MainActor
@Test func cachedSelectionReconfiguresWithConfigureDependentGlobs() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let builder = CMakeBuild(cache: fixture.project.appendingPathComponent("cache"))
  let options = CMakeSettings(configurePreset: "Debug")
  try Data().write(to: fixture.project.appendingPathComponent("configure-dependent-glob"))
  let initial = try await builder.configure(
    project: fixture.project, options: options, cli: fixture.cube)
  #expect(initial.targets == ["Blink"])

  try Data().write(to: fixture.project.appendingPathComponent("multiple-targets"))
  let refreshed = try await builder.configure(
    project: fixture.project, options: options, cli: fixture.cube, preferCached: true)
  #expect(refreshed.targets == ["Blink", "Other"])
}

@MainActor
@Test func cachedSelectionReusesCMakeReplyAndCleanupIsScopedToProject() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  let other = try WorkflowFixture()
  defer { other.remove() }
  let maker = CMakeBuild(cache: fixture.project.appendingPathComponent("cache"))
  let options = CMakeSettings(configurePreset: "Debug")
  let initial = try await maker.configure(
    project: fixture.project, options: options, cli: fixture.cube)
  let originalOwner = initial.directory.appendingPathComponent(".tekmor-project")
  try FileManager.default.removeItem(at: originalOwner)
  let existingCache = initial.directory.appendingPathComponent("CMakeCache.txt")
  try "CMAKE_HOME_DIRECTORY:INTERNAL=\(fixture.project.resolvingSymlinksInPath().path)\n".write(
    to: existingCache, atomically: true, encoding: .utf8)
  let attempts = try fixture.commands().split(separator: "\n").filter { $0.contains(" -B ") }
  let cached = try await maker.configure(
    project: fixture.project, options: options, cli: fixture.cube, preferCached: true)
  #expect(cached.directory == initial.directory)
  #expect(cached.targets == ["Blink"])
  #expect(try fixture.commands().split(separator: "\n").filter { $0.contains(" -B ") } == attempts)
  let fresh = try await maker.configure(
    project: fixture.project, options: options, cli: fixture.cube, fresh: true)
  #expect(fresh.directory == initial.directory)
  #expect((try fixture.commands()).contains("cmake --fresh "))
  let another = try await maker.configure(project: other.project, options: options, cli: other.cube)
  try maker.cleanCache(for: fixture.project)
  #expect(!FileManager.default.fileExists(atPath: initial.directory.path))
  #expect(FileManager.default.fileExists(atPath: another.directory.path))
}

@MainActor
@Test func workflowStopsAfterTimedOutWriteEvenWhenFirmwareWasVerified() async throws {
  let fixture = try WorkflowFixture()
  defer { fixture.remove() }
  try Data().write(to: fixture.project.appendingPathComponent("hang-write"))
  let host = WorkflowHost(connection: .swd(fixture.probe))
  await #expect(throws: FlashFailure.self) {
    try await fixture.workflow.execute(
      .flash(fixture.image, address: nil, standalone: false),
      context: fixture.context(), interaction: host)
  }
  #expect(host.steps.suffix(3) == ["write", "write ended", "verified"])
  #expect(host.progress == .init(write: .verified))
  #expect(!host.writing)
  #expect(!(try fixture.commands()).contains(" -rst"))
}

@MainActor
private final class WorkflowHost: STM32Workflow.Interaction {
  let connection: ChipConnection
  var steps: [String] = []
  var presets: [String] = []
  var selectedPreset: String?
  var targets: [String] = []
  var selectedTarget: String?
  var artifact: URL?
  var progress: FlashProgress?
  var writing = false
  var afterChipRead: (() -> Void)?
  var preparedConnections: [ChipConnection] = []

  init(connection: ChipConnection) { self.connection = connection }

  func selectFlashConnection(for method: FlashMethod) throws -> (
    connection: ChipConnection, probeCount: Int
  ) {
    steps.append("select")
    #expect(connection.flashMethod == method)
    return (connection, 1)
  }

  var toolsAvailable = true

  func checkTools(build: Bool, programmer: Bool) async throws {
    steps.append("tools")
    if !toolsAvailable { throw TekmorError("Prepare tools first") }
  }

  func prepareProgrammerConnection(_ connection: ChipConnection) async throws {
    preparedConnections.append(connection)
  }

  func receive(_ event: STM32Workflow.Event) {
    switch event {
    case .presets(let names, let selected):
      presets = names
      selectedPreset = selected
    case .targets(let names, let selected):
      targets = names
      selectedTarget = selected
    case .clearArtifact: artifact = nil
    case .builtArtifact(let value, _):
      artifact = value
      steps.append("artifact")
    case .stage(.building): steps.append("build")
    case .stage(.readingChip): steps.append("read")
    case .stage(.writing):
      writing = true
      steps.append("write")
    case .stage(.resetting): steps.append("reset")
    case .stage(.resettingTarget): steps.append("target reset")
    case .stage(.startingApplication): steps.append("start")
    case .applicationStarted: steps.append("started")
    case .stage(.erasing):
      writing = true
      steps.append("erase")
    case .chipRead: afterChipRead?()
    case .writeEnded:
      writing = false
      steps.append("write ended")
    case .flashProgress(let value):
      progress = value
      if value.write == .verified {
        steps.append(value.reset == .confirmed ? "reset confirmed" : "verified")
      }
    default: break
    }
  }
}

@MainActor
private struct WorkflowFixture {
  let project: URL
  let image: URL
  let cube: CubeCLI
  let probe = STLinkProbe(id: 17, label: "ST-LINK", serialNumber: "SERIAL")

  init() throws {
    project = try makeDirectory()
    image = project.appendingPathComponent("input.elf")
    try elf().write(to: image)
    try Data("{}".utf8).write(to: project.appendingPathComponent("CMakePresets.json"))
    try writeMockBundles(in: project)
    let database = project.appendingPathComponent("cmake/Data_Base")
    try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
    try Data("# Main configure input\n".utf8).write(
      to: project.appendingPathComponent("CMakeLists.txt"))
    try Data("# Included configure input\n".utf8).write(
      to: project.appendingPathComponent("cmake/targets.cmake"))
    try
      "<Device><FlashSize><ReadRegister address=\"0x1FFF7A22\" mask=\"0xFFF\"/></FlashSize></Device>"
      .write(
        to: database.appendingPathComponent("STM32_Prog_DB_0x413.xml"), atomically: true,
        encoding: .utf8
      )
    let executable = project.appendingPathComponent("cube")
    cube = CubeCLI(executable: executable)
    try writeExecutable(
      executable,
      body: #"""
        root=$(/usr/bin/dirname "$0")
        printf '%s\n' "$*" >> "$root/commands"
        case "$*" in
            '--version') printf 'Mock CubeCLI\n' ;;
            '--json bundle list') /bin/cat "$root/bundles.json" ;;
            '--json --resolve '*) printf '{"command":["%s/cmake/bin/cmake"],"bundle":{"name":"cmake","version":"1.0"}}\n' "$root" ;;
            'bundle install '*)
                [ ! -f "$root/fail-install" ] || exit 2
                /bin/cp "$root/prepared-bundles.json" "$root/bundles.json" ;;
            'cmake --list-presets=configure') printf '  "Debug"\n' ;;
            'cmake --build '*)
                [ ! -f "$root/fail-build" ] || exit 2
                /bin/cp "$root/input.elf" "$3/Blink.elf" ;;
            'cmake '*)
                while [ "$1" != -B ]; do [ "$#" -gt 0 ] || exit 3; shift; done
                reply="$2/.cmake/api/v1/reply"
                /bin/mkdir -p "$reply"
                printf '%s' '{"cmake":{"generator":{"name":"Ninja"}},"reply":{"codemodel-v2":{"jsonFile":"model.json"},"toolchains-v1":{"jsonFile":"toolchains.json"},"cmakeFiles-v1":{"jsonFile":"inputs.json"}}}' > "$reply/index-test.json"
                globs='[]'
                if [ -f "$root/configure-dependent-glob" ]; then
                    globs='[{"expression":"src/*.c"}]'
                fi
                printf '{"version":{"minor":1},"inputs":[{"path":"CMakeLists.txt"},{"path":"cmake/targets.cmake"}],"globsDependent":%s}' "$globs" > "$reply/inputs.json"
                printf '{"toolchains":[{"language":"C","compiler":{"path":"%s"}}]}\n' "$ARM_GNU_GCC" > "$reply/toolchains.json"
                if [ -f "$root/multiple-targets" ]; then
                    printf '%s' '{"configurations":[{"targets":[{"name":"Blink","jsonFile":"target.json"},{"name":"Other","jsonFile":"target.json"}]}]}' > "$reply/model.json"
                else
                    printf '%s' '{"configurations":[{"targets":[{"name":"Blink","jsonFile":"target.json"}]}]}' > "$reply/model.json"
                fi
                printf '%s' '{"type":"EXECUTABLE","artifacts":[{"path":"Blink.elf"}]}' > "$reply/target.json" ;;
            'programmer '*--upload*)
                for output do :; done
                printf '\000\004\000\000' > "$output" ;;
            'programmer '*'-w '*)
                printf 'Download verified successfully\n'
                [ ! -f "$root/hang-write" ] || exec /bin/sleep 30 ;;
            'programmer '*'-rst') printf 'Reset is performed\n' ;;
            'programmer '*'-e all') printf 'Mass erase successfully achieved\n' ;;
            'programmer '*--start*)
                [ ! -f "$root/fail-start" ] || exit 8
                printf 'Start operation achieved successfully\n' ;;
            'programmer '*)
                if [ -f "$root/uart-already-synced" ]; then
                    case "$*" in *'noinit=1'*) ;; *) exit 9 ;; esac
                fi
                if [ -f "$root/changed-target" ]; then id=0x415; else id=0x413; fi
                printf 'Device ID: %s\nDevice name: STM32F407xx\nFlash size: 1 MBytes\n' "$id" ;;
            *) exit 4 ;;
        esac
        """#)
  }

  var workflow: STM32Workflow {
    STM32Workflow(builder: CMakeBuild(cache: project.appendingPathComponent("cache"))) {
      [programmer] _ in programmer
    }
  }

  var programmer: CubeProgrammer {
    let probe = probe
    return CubeProgrammer(
      cli: cube, isPresent: { _ in true }, probes: { [probe] },
      deadline: { _, _ in .milliseconds(500) })
  }

  func context(
    method: FlashMethod = .swd, confirmedTarget: STM32Workflow.ConfirmedTarget? = nil
  ) -> STM32Workflow.Context {
    var configuration = ProjectConfiguration()
    configuration.flash = method
    return .init(
      project: project, configuration: configuration, cube: cube, confirmedTarget: confirmedTarget)
  }

  func commands() throws -> String {
    try String(contentsOf: project.appendingPathComponent("commands"), encoding: .utf8)
  }

  func remove() { try? FileManager.default.removeItem(at: project) }
}

@Test func chipReadsRetryAfterToolInstallAndReplug() {
  var readings = ChipReadings()
  let firstMount: UInt64 = 1
  let secondMount: UInt64 = 2
  #expect(readings.shouldRead(firstMount, toolsReady: false))
  readings[firstMount] = .needsTool("Missing Programmer bundle")
  #expect(!readings.shouldRead(firstMount, toolsReady: false))
  #expect(readings.shouldRead(firstMount, toolsReady: true))
  readings[firstMount] = .reading
  #expect(!readings.shouldRead(firstMount, toolsReady: true))
  readings[firstMount] = .failed("Busy")
  #expect(!readings.shouldRead(firstMount, toolsReady: true))
  readings.retainConnections([secondMount])
  #expect(readings[firstMount] == nil)
  #expect(readings.shouldRead(secondMount, toolsReady: true))
}

@Test func resolvesCapacityFromAnUnambiguousSTRegister() throws {
  try withDirectory { directory in
    let file = directory.appendingPathComponent("STM32_Prog_DB_0x413.xml")
    try """
    <Device><Variant>
    <FlashSize><ReadRegister address="0x1FFF7A22" mask="0xFFF" value="0x400"/></FlashSize>
    <FLASHSIZE><ReadRegister address="0x1FFF7A22" mask="0xFFF" value="0x200"/></FLASHSIZE>
    </Variant></Device>
    """.write(to: file, atomically: true, encoding: .utf8)
    let parsed = try CubeProgrammer.FlashCapacityRegister.definition(at: file)
    let definition = try #require(parsed)
    #expect(definition.address == 0x1FFF_7A22)
    #expect(definition.bytes(from: 0xFFFF_0400) == 1024 * 1024)
    #expect(definition.bytes(from: 0xFFFF_FFFF) == nil)
  }
}

@Test func capacityDatabaseSupportsDirectAddressesAndRejectsAmbiguity() throws {
  try withDirectory { directory in
    let file = directory.appendingPathComponent("target.xml")
    try "<Device><FlashSize address=\"0x1FFFF7E0\" default=\"0x80000\"/></Device>".write(
      to: file, atomically: true, encoding: .utf8)
    let parsed = try CubeProgrammer.FlashCapacityRegister.definition(at: file)
    let register = try #require(parsed)
    #expect(register.address == 0x1FFF_F7E0)
    #expect(register.bytes(from: 0xFFFF_0040) == 64 * 1024)
    #expect(register.bytes(from: 0xFFFF_FFFF) == nil)
    try "<Device><FlashSize address=\"0x1FFFF7E0\"/><FlashSize address=\"0x1FFF7A22\"/></Device>"
      .write(to: file, atomically: true, encoding: .utf8)
    #expect(try CubeProgrammer.FlashCapacityRegister.definition(at: file) == nil)
    try
      "<Device><FlashSize><ReadRegister address=\"0x1FFF7A22\" mask=\"0xFFF\"/><ReadRegister address=\"0x1FFFF7E0\" mask=\"0xFFFF\"/></FlashSize></Device>"
      .write(to: file, atomically: true, encoding: .utf8)
    #expect(try CubeProgrammer.FlashCapacityRegister.definition(at: file) == nil)
  }
}

@Test func cubeUARTReadsRealCapacityAndReusesBootloaderSession() async throws {
  let directory = try makeDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let tool = directory.appendingPathComponent("cube")
  try #"""
  #!/bin/sh
  root=$(/usr/bin/dirname "$0")
  printf '%s\n' "$*" >> "$root/commands"
  case "$*" in
      *' --upload '*)
          shift 5
          test "$1" = "--upload" && test "$2" = "0x1FFFF7E0" && test "$3" = "4" || exit 1
          printf '\100\000\377\377' > "$4"
          ;;
      *' -w '*)
          if [ "$5" != "noinit=1" ]; then exit 1; fi
          printf 'Download verified successfully\n'
          ;;
      '--json --resolve programmer')
          printf '{"command":["%s/bin/programmer"]}\n' "$root"
          ;;
      *)
          printf 'Chip ID: 0x410\nDevice name: STM32F101/F102/F103 Medium-density\n'
          printf 'NVM size: 128 KBytes (default)\nBootLoader protocol version: 2.2\n'
          ;;
  esac
  """#.write(to: tool, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
  let database = directory.appendingPathComponent("Data_Base")
  try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
  try "<Device><FlashSize address=\"0x1FFFF7E0\" default=\"0x20000\"/></Device>".write(
    to: database.appendingPathComponent("STM32_Prog_DB_0x410.xml"), atomically: true,
    encoding: .utf8
  )
  let device = SerialDevice(id: "/dev/cu.example", label: "example", registryID: 5)
  let connection = ChipConnection.uart(device)
  let programmer = CubeProgrammer(
    cli: CubeCLI(executable: tool),
    isPresent: { _ in true }, probes: { [] })
  let info = try await programmer.read(connection)
  #expect(info.id == 0x410)
  #expect(info.flashBytes == 64 * 1024)
  #expect(info.bootloader == "2.2")
  let fits = try FirmwareImage(data: Data([1, 2, 3, 4]), format: "bin", binaryAddress: 0x0800_FFFC)
  try await programmer.write(fits, to: connection, confirmed: info)
  let tooLarge = try FirmwareImage(
    data: Data([1, 2, 3, 4]), format: "bin", binaryAddress: 0x0801_0000)
  await #expect(throws: TekmorError.self) {
    try await programmer.write(tooLarge, to: connection, confirmed: info)
  }
  let logged = try String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8)
  #expect(logged.contains("noinit=1 --upload 0x1FFFF7E0 4"))
  #expect(logged.split(whereSeparator: \.isNewline).filter { $0.contains(" -w ") }.count == 1)
  try FileManager.default.removeItem(at: database.appendingPathComponent("STM32_Prog_DB_0x410.xml"))
  let unknown = try await programmer.read(connection)
  #expect(unknown.flashBytes == nil)
  await #expect(throws: TekmorError.self) {
    try await programmer.write(fits, to: connection, confirmed: unknown)
  }
}

@Test func coreLocalizationSwitchesBetweenChineseAndEnglish() throws {
  let previous = TekmorLocalization.language
  defer { TekmorLocalization.language = previous }

  let failure = CommandResult(status: 2, output: "", errorOutput: "boom")

  TekmorLocalization.language = .zhHans
  do {
    try failure.requireSuccess("配置 CMake")
    Issue.record("Expected requireSuccess to throw")
  } catch let error as TekmorError {
    let description = try #require(error.errorDescription)
    #expect(description.contains("配置 CMake失败（退出码 2）"))
    #expect(description.contains("boom"))
  }

  TekmorLocalization.language = .english
  do {
    try failure.requireSuccess("Configuring CMake")
    Issue.record("Expected requireSuccess to throw")
  } catch let error as TekmorError {
    let description = try #require(error.errorDescription)
    #expect(description.contains("Configuring CMake failed (exit code 2)"))
    #expect(description.contains("boom"))
  }
  var invalid = ProjectConfiguration()
  invalid.cmake.configurePreset = ""
  do {
    try invalid.validate()
    Issue.record("Expected invalid preset validation to throw")
  } catch let error as TekmorError {
    #expect(error.errorDescription == "Invalid CMake preset name.")
  }
}

@Test func languageSelectionPreservesRegionalPreferences() {
  var components = Locale.Components(identifier: "en_GB")
  components.hourCycle = .zeroToTwentyThree
  components.firstDayOfWeek = .monday
  components.calendar = .gregorian
  components.numberingSystem = .init("latn")
  let regionalLocale = Locale(components: components)

  for language in [AppLanguage.zhHans, .english] {
    let locale = language.locale(overriding: regionalLocale)
    #expect(locale.region == regionalLocale.region)
    #expect(locale.hourCycle == regionalLocale.hourCycle)
    #expect(locale.firstDayOfWeek == regionalLocale.firstDayOfWeek)
    #expect(locale.calendar.identifier == regionalLocale.calendar.identifier)
    #expect(locale.numberingSystem == regionalLocale.numberingSystem)
    #expect(locale.currency == regionalLocale.currency)
    #expect(locale.measurementSystem == regionalLocale.measurementSystem)
  }
  #expect(AppLanguage.zhHans.locale(overriding: regionalLocale).language.languageCode == .chinese)
  #expect(AppLanguage.english.locale(overriding: regionalLocale).language.languageCode == .english)
}

@Test func localizedResourcesUseSelectedLanguageAndPreserveIntegerArguments() throws {
  try withDirectory { directory in
    let translations = [
      "en": ["ordered": "%2$@ has %1$lld items"],
      "zh-Hans": ["ordered": "%2$@有 %1$lld 项"],
    ]
    for (code, values) in translations {
      let folder = directory.appendingPathComponent("\(code).lproj")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
      let data = try PropertyListSerialization.data(
        fromPropertyList: values, format: .xml, options: 0)
      try data.write(to: folder.appendingPathComponent("Localizable.strings"))
    }

    let count = Int(Int32.max) + 1
    let name = "Firmware %08X"
    let resource = LocalizedStringResource(
      "ordered", defaultValue: "\(count) items for \(name)", bundle: .atURL(directory)
    )
    let englishCount = count.formatted(.number.locale(AppLanguage.english.locale))
    let chineseCount = count.formatted(.number.locale(AppLanguage.zhHans.locale))
    #expect(
      TekmorLocalization.string(resource, language: .english)
        == "Firmware %08X has \(englishCount) items")
    #expect(
      TekmorLocalization.string(resource, language: .zhHans) == "Firmware %08X有 \(chineseCount) 项")

    let missing = LocalizedStringResource(
      "missing", defaultValue: "Fallback \(count)", bundle: .atURL(directory)
    )
    #expect(TekmorLocalization.string(missing, language: .english) == "Fallback \(englishCount)")
    #expect(TekmorLocalization.string(missing, language: .zhHans) == "Fallback \(chineseCount)")
  }
}
