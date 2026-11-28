import TekmorWorkbench
import Testing

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
