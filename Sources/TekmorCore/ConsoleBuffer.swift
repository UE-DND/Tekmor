import Foundation
import Synchronization

private let consoleCapacity = 512_000
private let gapMarker = "…"

private func utf8Tail(_ text: String, within limit: Int) -> String {
  guard text.utf8.count > limit else { return text }
  let bytes = text.utf8.suffix(limit).drop(while: { $0 & 0xc0 == 0x80 })
  return String(decoding: bytes, as: UTF8.self)
}

/// Coalesces producers before scheduling a consumer on the main actor.
public final class ConsoleInbox: Sendable {
  public struct Batch: Sendable {
    public let text: String
    public let byteCount: Int
    public let newlineCount: Int
    public let hasGap: Bool
  }

  private struct Pending {
    var text = ""
    var byteCount = 0
    var newlineCount = 0
    var scheduled = false
  }

  private let pending = Mutex(Pending())

  public init() {}

  /// Returns true when the caller needs to schedule a drain.
  public func append(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let count = text.utf8.count
    let newlineCount = text.utf8.count { $0 == 10 }
    let tail = utf8Tail(text, within: consoleCapacity)
    return pending.withLock {
      $0.text = count > consoleCapacity ? tail : utf8Tail($0.text + tail, within: consoleCapacity)
      $0.byteCount += count
      $0.newlineCount += newlineCount
      guard !$0.scheduled else { return false }
      $0.scheduled = true
      return true
    }
  }

  /// A synchronous flush leaves any scheduled drain in place.
  public func drain(scheduled: Bool = false) -> Batch {
    pending.withLock {
      let batch = Batch(
        text: $0.text, byteCount: $0.byteCount, newlineCount: $0.newlineCount,
        hasGap: $0.byteCount > $0.text.utf8.count)
      $0 = Pending(scheduled: !scheduled && $0.scheduled)
      return batch
    }
  }
}

public struct ConsoleBuffer {
  public enum Mode { case build, serial }

  public struct Line: Identifiable, Equatable {
    public enum Kind: Equatable { case normal, info, success, warning, error, command }

    public let id: Int
    public let timestamp: String?
    public fileprivate(set) var text: String
    public fileprivate(set) var kind: Kind
  }

  private let mode: Mode
  private var nextID = 1
  private var continuesLine = false
  private var previousCarriageReturn = false
  private var historyBytes = 0
  private var evictedHistory = false
  private var rows: [Line] = []
  public private(set) var transcript = ""
  public var lines: [Line] {
    evictedHistory ? [Line(id: 0, timestamp: nil, text: gapMarker, kind: .normal)] + rows : rows
  }

  public init(_ mode: Mode) { self.mode = mode }

  public mutating func clear() {
    rows.removeAll()
    transcript = ""
    historyBytes = 0
    evictedHistory = false
    continuesLine = false
    previousCarriageReturn = false
  }

  public mutating func append(
    _ text: String, timestamp: String? = nil, showTimestamp: Bool = false, hasGap: Bool = false
  ) {
    guard !text.isEmpty || hasGap else { return }
    var raw = ""
    var clippedRaw = false
    let stamp = showTimestamp ? timestamp.map { $0 + "  " } ?? "" : ""
    if hasGap {
      if continuesLine { raw += "\n" }
      continuesLine = false
      previousCarriageReturn = false
      appendPart(gapMarker[...], endsLine: true, timestamp: nil)
      raw += gapMarker + "\n"
    }
    var input = text[...]
    if mode == .build, previousCarriageReturn, text.utf8.first == 10 {
      input = input.dropFirst()
    }
    previousCarriageReturn = text.utf8.last == 13
    let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: mode == .build ? "\n" : "")
    var remaining = normalized[...]
    while let newline = remaining.firstIndex(of: "\n") {
      if !continuesLine { raw += stamp }
      let part = remaining[..<newline]
      raw += part
      raw += "\n"
      appendPart(part, endsLine: true, timestamp: timestamp)
      if raw.utf8.count > consoleCapacity {
        raw = utf8Tail(raw, within: consoleCapacity - 4096)
        clippedRaw = true
      }
      remaining = remaining[remaining.index(after: newline)...]
    }
    if !remaining.isEmpty {
      if !continuesLine { raw += stamp }
      raw += remaining
      appendPart(remaining, endsLine: false, timestamp: timestamp)
    }
    let marker = gapMarker + "\n"
    if clippedRaw {
      transcript = marker + utf8Tail(raw, within: consoleCapacity - marker.utf8.count)
    } else {
      transcript += raw
      if transcript.utf8.count > consoleCapacity {
        transcript = marker + utf8Tail(transcript, within: 160_000 - marker.utf8.count)
      }
    }
  }

  private mutating func appendPart(_ part: Substring, endsLine: Bool, timestamp: String?) {
    let previous = continuesLine ? rows.removeLast() : nil
    historyBytes -= previous?.text.utf8.count ?? 0
    var text = (previous?.text ?? "") + part
    if text.utf8.count > 8192 {
      text = gapMarker + utf8Tail(text, within: 8192 - gapMarker.utf8.count)
    }
    let kind = mode == .build ? Self.classify(text) : .normal
    let id = previous?.id ?? nextID
    if previous == nil { nextID += 1 }
    rows.append(
      Line(
        id: id, timestamp: previous == nil ? timestamp : previous?.timestamp, text: text, kind: kind
      ))
    historyBytes += text.utf8.count
    continuesLine = !endsLine

    let byteLimit = consoleCapacity - gapMarker.utf8.count
    if rows.count >= 4000 || historyBytes > byteLimit {
      var removed = max(0, rows.count - 2500)
      var remainingBytes = historyBytes - rows.prefix(removed).reduce(0) { $0 + $1.text.utf8.count }
      while remainingBytes > byteLimit - 8192 {
        remainingBytes -= rows[removed].text.utf8.count
        removed += 1
      }
      historyBytes = remainingBytes
      rows.removeFirst(removed)
      evictedHistory = true
    }
  }

  private static func classify(_ line: String) -> Line.Kind {
    let lower = line.lowercased()
    if line.hasPrefix("[错误]") || line.hasPrefix("[Error]") || lower.contains("error:")
      || lower.contains("fatal error")
      || lower.contains("undefined reference") || lower.contains("cmake error")
      || (lower.contains("failed") && !lower.contains("0 failed"))
    {
      return .error
    }
    if lower.contains("warning:") || lower.contains("cmake warning") { return .warning }
    if line.contains("TEKMOR_UART_VERIFIED") || line.contains("TEKMOR_SWD_VERIFIED")
      || line.contains("TEKMOR_SWD_RESET") || line.hasPrefix("已安装 ") || line.hasPrefix("Installed ")
      || lower.contains("[100%]") || lower.contains("verified ok")
    {
      return .success
    }
    if line.hasPrefix("-- ") || line.hasPrefix("Scanning ") || line.hasPrefix("Building ")
      || line.hasPrefix("Linking ") || line.hasPrefix("[")
    {
      return .info
    }
    if line.hasPrefix("$ ") || line.hasPrefix("> ") { return .command }
    return .normal
  }
}
