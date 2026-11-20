import Foundation

/// Literal, case-insensitive matches in the displayed console lines.
public struct ConsoleSearchResults: Equatable {
  public struct Match: Equatable {
    public enum Field: Equatable { case text, timestamp }

    public let lineID: Int
    public let field: Field
    public let range: Range<String.Index>
  }

  public let query: String
  public let matches: [Match]

  public init(lines: [ConsoleBuffer.Line], query: String, includeTimestamps: Bool = false) {
    self.query = query
    guard !query.isEmpty else {
      matches = []
      return
    }

    var matches: [Match] = []
    for line in lines {
      if includeTimestamps, let timestamp = line.timestamp {
        matches += Self.ranges(in: timestamp, query: query).map {
          Match(lineID: line.id, field: .timestamp, range: $0)
        }
      }
      matches += Self.ranges(in: line.text, query: query).map {
        Match(lineID: line.id, field: .text, range: $0)
      }
    }
    self.matches = matches
  }

  public func currentMatch(_ selection: Match?) -> Match? {
    selection.flatMap { matches.contains($0) ? $0 : nil } ?? matches.first
  }

  /// The current match's 1-based position, or zero when there are no matches.
  public func index(of selection: Match?) -> Int {
    guard let current = currentMatch(selection), let index = matches.firstIndex(of: current) else {
      return 0
    }
    return index + 1
  }

  public func nextMatch(after selection: Match?, backwards: Bool = false) -> Match? {
    guard !matches.isEmpty else { return nil }
    let index = index(of: selection) - 1
    let next = (index + (backwards ? matches.count - 1 : 1)) % matches.count
    return matches[next]
  }

  private static func ranges(in text: String, query: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var start = text.startIndex
    while start < text.endIndex,
      let range = text.range(
        of: query, options: .caseInsensitive, range: start..<text.endIndex, locale: .current)
    {
      ranges.append(range)
      start = range.upperBound
    }
    return ranges
  }
}
