import Foundation
import TekmorWorkbench
import Testing

@Suite("Console search")
struct ConsoleSearchTests {
  @Test func findsEveryOccurrenceAndKeepsLineIdentity() {
    var buffer = ConsoleBuffer(.build)
    buffer.append("before\nmaster MASTER master\nafter\n")
    let lines = buffer.lines
    let results = ConsoleSearchResults(lines: lines, query: "master")

    #expect(results.matches.count == 3)
    #expect(results.matches.allSatisfy { $0.lineID == lines[1].id && $0.field == .text })
    #expect(
      results.matches.map { String(lines[1].text[$0.range]) } == ["master", "MASTER", "master"])
    #expect(buffer.lines == lines)
    #expect(buffer.transcript == "before\nmaster MASTER master\nafter\n")
  }

  @Test func supportsUnicodeAndCanonicalEquivalence() {
    var buffer = ConsoleBuffer(.build)
    buffer.append("🌧️ 雨滴 Café cafe\u{301} 触摸\n")
    let text = buffer.lines[0].text
    let results = ConsoleSearchResults(lines: buffer.lines, query: "CAFÉ")

    #expect(results.matches.count == 2)
    #expect(results.matches.map { String(text[$0.range]) } == ["Café", "cafe\u{301}"])
    let rain = ConsoleSearchResults(lines: buffer.lines, query: "🌧️ 雨滴")
    #expect(rain.matches.count == 1)
    #expect(rain.matches.map { String(text[$0.range]) } == ["🌧️ 雨滴"])
  }

  @Test func treatsWhitespaceAndRegexCharactersLiterally() {
    var buffer = ConsoleBuffer(.build)
    buffer.append("master .* master\n")
    let text = buffer.lines[0].text
    let results = ConsoleSearchResults(lines: buffer.lines, query: " .* ")

    #expect(results.matches.count == 1)
    #expect(results.matches.map { String(text[$0.range]) } == [" .* "])
    #expect(ConsoleSearchResults(lines: buffer.lines, query: " ").matches.count == 2)
    #expect(ConsoleSearchResults(lines: buffer.lines, query: "").matches.isEmpty)
    #expect(ConsoleSearchResults(lines: buffer.lines, query: "missing").matches.isEmpty)
  }

  @Test func searchesTimestampsWhenDisplayed() {
    var buffer = ConsoleBuffer(.serial)
    buffer.append("12:30 payload\n", timestamp: "12:30:00", showTimestamp: true)
    let hidden = ConsoleSearchResults(lines: buffer.lines, query: "12:30")
    let shown = ConsoleSearchResults(lines: buffer.lines, query: "12:30", includeTimestamps: true)

    #expect(hidden.matches.map(\.field) == [.text])
    #expect(shown.matches.map(\.field) == [.timestamp, .text])
  }

  @Test func wrapsNavigationInBothDirections() throws {
    var buffer = ConsoleBuffer(.build)
    buffer.append("match match\nmatch\n")
    let results = ConsoleSearchResults(lines: buffer.lines, query: "match")
    let first = try #require(results.currentMatch(nil))
    let second = try #require(results.nextMatch(after: first))
    let third = try #require(results.nextMatch(after: second))

    #expect(results.index(of: nil) == 1)
    #expect(results.index(of: second) == 2)
    #expect(results.nextMatch(after: third) == first)
    #expect(results.nextMatch(after: first, backwards: true) == third)
    #expect(results.nextMatch(after: third, backwards: true) == second)
    let empty = ConsoleSearchResults(lines: buffer.lines, query: "missing")
    #expect(empty.currentMatch(first) == nil)
    #expect(empty.nextMatch(after: first) == nil)
    #expect(empty.index(of: first) == 0)
  }

  @Test func retainsSelectionOnAppendAndRecoversAfterEviction() throws {
    var buffer = ConsoleBuffer(.build)
    buffer.append("match\npartial mat")
    let original = ConsoleSearchResults(lines: buffer.lines, query: "match")
    let selected = try #require(original.currentMatch(nil))
    buffer.append("ch\n")
    let appended = ConsoleSearchResults(lines: buffer.lines, query: "match")

    #expect(appended.matches.count == 2)
    #expect(appended.currentMatch(selected) == selected)
    buffer.append(String(repeating: "match\n", count: 4100))
    let evicted = ConsoleSearchResults(lines: buffer.lines, query: "match")
    #expect(!evicted.matches.contains(selected))
    #expect(evicted.currentMatch(selected) == evicted.matches.first)
    #expect(evicted.index(of: selected) == 1)
  }
}
