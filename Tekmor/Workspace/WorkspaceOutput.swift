import Foundation
import Observation
import TekmorCore
import TekmorWorkbench

@MainActor @Observable
final class WorkspaceOutput {
  @ObservationIgnored var logInbox = ConsoleInbox()
  @ObservationIgnored var toolLogInbox = ConsoleInbox()
  @ObservationIgnored var serialInbox = SerialInbox()

  private var buildBuffer = ConsoleBuffer(.build)
  private var toolBuffer = ConsoleBuffer(.build)
  private var serialText = ConsoleBuffer(.serial)
  private var serialHEX = ConsoleBuffer(.serial)
  @ObservationIgnored private var decoder = SerialDecoder()
  @ObservationIgnored private var hexFormatter = SerialHEXView()
  var serialFormat = SerialFormat.text

  private var serialBuffer: ConsoleBuffer { serialFormat == .hex ? serialHEX : serialText }
  var logSearchQuery = ""
  var logShowsSearch = false
  var logOnlyIssues = false
  var serialSearchQuery = ""
  var serialShowsSearch = false
  private(set) var serialByteCount = 0
  private(set) var serialLineCount = 0

  var log: String { buildBuffer.transcript }
  var toolLog: String { toolBuffer.transcript }
  var transcript: String { serialBuffer.transcript }
  var logLines: [ConsoleBuffer.Line] { buildBuffer.lines }
  var toolLogLines: [ConsoleBuffer.Line] { toolBuffer.lines }
  var serialLines: [ConsoleBuffer.Line] { serialBuffer.lines }

  var logIssueCount: Int {
    logLines.reduce(into: 0) { count, line in
      if line.kind == .error || line.kind == .warning { count += 1 }
    }
  }

  var filteredLogLines: [ConsoleBuffer.Line] {
    guard logOnlyIssues else { return logLines }
    return logLines.filter { line in
      line.kind == .error || line.kind == .warning
    }
  }

  func clearLog() {
    _ = logInbox.drain()
    buildBuffer.clear()
    logOnlyIssues = false
  }

  func clearToolLog() {
    _ = toolLogInbox.drain()
    toolBuffer.clear()
  }

  func clearSerial() {
    _ = serialInbox.drain()
    serialText.clear()
    serialHEX.clear()
    decoder = SerialDecoder()
    hexFormatter = SerialHEXView()
    serialByteCount = 0
    serialLineCount = 0
  }

  func showsSearch(for isSerial: Bool) -> Bool {
    isSerial ? serialShowsSearch : logShowsSearch
  }

  func setShowsSearch(_ visible: Bool, isSerial: Bool) {
    if isSerial {
      serialShowsSearch = visible
      if !visible { serialSearchQuery = "" }
    } else {
      logShowsSearch = visible
      if !visible { logSearchQuery = "" }
    }
  }

  func resetSearch() {
    logSearchQuery = ""
    logShowsSearch = false
    serialSearchQuery = ""
    serialShowsSearch = false
  }

  func flushLog(scheduled: Bool = false) {
    let batch = logInbox.drain(scheduled: scheduled)
    buildBuffer.append(batch.text, hasGap: batch.hasGap)
  }

  func appendLog(_ text: String) {
    buildBuffer.append(text)
  }

  func flushToolLog(scheduled: Bool = false) {
    let batch = toolLogInbox.drain(scheduled: scheduled)
    toolBuffer.append(batch.text, hasGap: batch.hasGap)
  }

  func appendToolLog(_ text: String) {
    toolBuffer.append(text)
  }

  func flushSerial(
    scheduled: Bool = false,
    timestamp: @autoclosure () -> String,
    showTimestamp: Bool
  ) -> Bool {
    let batch = serialInbox.drain(scheduled: scheduled)
    guard batch.byteCount > 0 else { return false }
    serialByteCount += batch.byteCount
    serialLineCount += batch.newlineCount
    if batch.hasGap {
      decoder = SerialDecoder()
      hexFormatter = SerialHEXView()
    }
    let stamp = showTimestamp ? timestamp() : nil
    serialText.append(
      decoder.append(batch.data), timestamp: stamp, showTimestamp: showTimestamp,
      hasGap: batch.hasGap)
    serialHEX.append(
      hexFormatter.append(batch.data), timestamp: stamp, showTimestamp: showTimestamp,
      hasGap: batch.hasGap)
    return true
  }

  func finishSerialStream() {
    serialText.append(decoder.finish())
  }

  func appendSerialNotice(_ message: String) {
    serialText.append("\n" + message + "\n")
    serialHEX.append("\n" + message + "\n")
    hexFormatter = SerialHEXView()
  }
}
