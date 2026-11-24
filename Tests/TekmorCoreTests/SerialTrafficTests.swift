import Darwin
import Foundation
import Testing

@testable import TekmorCore

@Test func serialCommandEncodesTextAndHEXWithLineEndings() throws {
  var command = SerialCommand()
  command.input = "串口"
  command.lineEnding = .lf
  #expect(try command.payload() == Data("串口\n".utf8))
  command.input = "00aB 80\tFF"
  command.format = .hex
  command.lineEnding = .crlf
  #expect(try command.payload() == Data([0, 0xab, 0x80, 0xff, 13, 10]))
  for input in ["f", "0x33", "01 ZZ", "1 2"] {
    command.input = input
    #expect(throws: TekmorError.self) { try command.payload() }
  }
  command.input = ""
  command.lineEnding = .none
  #expect(throws: TekmorError.self) { try command.payload() }
  for rate in [460800, 921600, 1_000_000] {
    var settings = SerialSettings()
    settings.baud = rate
    try settings.validate()
  }
}

@Test func serialInboxCountsRawBytesAndHEXSplitsRowsAcrossReads() {
  let inbox = SerialInbox()
  #expect(inbox.append(Data([0, 10, 0xff])))
  #expect(!inbox.append(Data([0x80])))
  let batch = inbox.drain(scheduled: true)
  #expect(batch.byteCount == 4)
  #expect(batch.newlineCount == 1)
  var hex = SerialHEXView()
  #expect(hex.append(batch.data) == "00 0A FF 80")
  #expect(hex.append(Data(repeating: 1, count: 12)) == String(repeating: " 01", count: 12) + "\n")
  #expect(hex.append(Data([0xca, 0xfe])) == "CA FE")
  #expect(inbox.append(Data(repeating: 10, count: 200_000)))
  let overrun = inbox.drain()
  #expect(overrun.hasGap)
  #expect(overrun.byteCount == 200_000)
  #expect(overrun.newlineCount == 200_000)
}

@Test func serialConnectionTransfersBothWaysAndRejectsWritesAfterClose() async throws {
  var master: Int32 = -1
  var slave: Int32 = -1
  try #require(openpty(&master, &slave, nil, nil, nil) == 0)
  defer { Darwin.close(master) }
  var options = termios()
  try #require(tcgetattr(slave, &options) == 0)
  cfmakeraw(&options)
  try #require(tcsetattr(slave, TCSANOW, &options) == 0)
  try #require(fcntl(master, F_SETFL, O_NONBLOCK) == 0)
  try #require(fcntl(slave, F_SETFL, O_NONBLOCK) == 0)

  let raw = SerialInbox()
  let connection = SerialConnection(
    device: SerialDevice(id: "/dev/cu.fixture", label: "Fixture", registryID: 1),
    descriptor: slave, receive: { _ = raw.append($0) }, disconnected: { _ in })
  let outbound = Data((0..<(64 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
  let send = Task { try await connection.send(outbound) }
  let inbound = Data([1, 2, 13, 10, 0xff])
  #expect(
    inbound.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) } == inbound.count)

  var received = Data()
  var fromDevice = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  let deadline = ContinuousClock.now + .seconds(4)
  while received.count < outbound.count || fromDevice.count < inbound.count,
    ContinuousClock.now < deadline
  {
    let count = Darwin.read(master, &buffer, buffer.count)
    if count > 0 { received.append(contentsOf: buffer.prefix(count)) }
    fromDevice.append(raw.drain(scheduled: true).data)
    try await Task.sleep(for: .milliseconds(10))
  }
  await connection.close()
  try await send.value
  #expect(received == outbound)
  #expect(fromDevice == inbound)
  await #expect(throws: TekmorError.self) { try await connection.send(outbound) }
}
