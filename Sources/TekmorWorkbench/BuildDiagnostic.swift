import Foundation

/// A source file and line/column reference extracted from a compiler, linker, or CMake log line.
public struct BuildDiagnosticLocation: Equatable, Hashable, Sendable {
  public let path: String
  public let line: Int
  public let column: Int?

  public init(path: String, line: Int, column: Int? = nil) {
    self.path = path
    self.line = line
    self.column = column
  }

  /// Short label suitable for inline badges and context menus (e.g. `main.c:42`).
  public var displayLabel: String {
    "\(URL(filePath: path).lastPathComponent):\(line)"
  }

  /// Parses a source location from a build log line emitted by GCC, Clang, GNU ld, or CMake.
  public static func parse(from logLine: String) -> BuildDiagnosticLocation? {
    let trimmed = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let cmake = parseCMake(trimmed) {
      return cmake
    }
    return parseCompilerOrLinker(trimmed)
  }

  /// Resolves the parsed path against `projectRoot` and verifies an existing regular file on disk.
  public func resolveURL(
    relativeTo projectRoot: URL?, fileManager: FileManager = .default
  ) -> URL? {
    let candidate: URL
    if path.hasPrefix("/") {
      candidate = URL(filePath: path).standardizedFileURL
    } else if let projectRoot {
      candidate = projectRoot.appending(path: path).standardizedFileURL
    } else {
      return nil
    }

    guard fileManager.fileExists(atPath: candidate.path),
      (try? candidate.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        .isRegularFile) == true
    else {
      return nil
    }
    return candidate
  }

  private static func parseCMake(_ line: String) -> BuildDiagnosticLocation? {
    // Matches e.g. "CMake Error at CMakeLists.txt:15 (add_executable):"
    // or "CMake Warning at cmake/toolchain.cmake:8:"
    let prefixes = [
      "CMake Error at ",
      "CMake Warning at ",
      "CMake Deprecation Warning at ",
    ]
    for prefix in prefixes where line.hasPrefix(prefix) {
      let remainder = line.dropFirst(prefix.count)
      return extractPathAndLine(from: remainder)
    }
    return nil
  }

  private static func parseCompilerOrLinker(_ line: String) -> BuildDiagnosticLocation? {
    // Matches "In file included from <path>:<line>[:<col>][,|:]"
    let includePrefixes = ["In file included from ", "from "]
    for prefix in includePrefixes where line.hasPrefix(prefix) {
      let remainder = line.dropFirst(prefix.count)
      if let parsed = extractPathLineColumn(from: remainder, requireDiagnosticTail: false) {
        return parsed
      }
    }

    return extractPathLineColumn(from: line[...], requireDiagnosticTail: true)
  }

  private static func extractPathAndLine(from substring: Substring) -> BuildDiagnosticLocation? {
    // Stop before " (" or trailing ":"
    let head: Substring
    if let paren = substring.range(of: " (") {
      head = substring[..<paren.lowerBound]
    } else if substring.hasSuffix(":") {
      head = substring.dropLast()
    } else {
      head = substring
    }

    guard let colon = head.lastIndex(of: ":") else { return nil }
    let rawPath = head[..<colon].trimmingCharacters(in: .whitespaces)
    let rawLine = head[head.index(after: colon)...]
    guard isPlausiblePath(rawPath), let lineNumber = Int(rawLine), lineNumber > 0 else {
      return nil
    }
    return BuildDiagnosticLocation(path: rawPath, line: lineNumber)
  }

  private static func extractPathLineColumn(
    from substring: Substring, requireDiagnosticTail: Bool
  ) -> BuildDiagnosticLocation? {
    // Find ":<digits>" followed by either ":<digits>:" or ":" (optionally linker ":(...)").
    let scalars = substring
    var searchStart = scalars.startIndex
    while let colon = scalars[searchStart...].firstIndex(of: ":") {
      let afterColon = scalars.index(after: colon)
      let lineDigitsEnd = digitsEnd(in: scalars, from: afterColon)
      if lineDigitsEnd > afterColon,
        let lineNumber = Int(scalars[afterColon..<lineDigitsEnd]), lineNumber > 0
      {
        let rawPath = scalars[..<colon].trimmingCharacters(in: .whitespaces)
        guard isPlausiblePath(rawPath) else {
          searchStart = afterColon
          continue
        }

        // Optional ":<column>"
        var columnNumber: Int?
        var tailStart = lineDigitsEnd
        if tailStart < scalars.endIndex, scalars[tailStart] == ":" {
          let afterSecondColon = scalars.index(after: tailStart)
          let colDigitsEnd = digitsEnd(in: scalars, from: afterSecondColon)
          if colDigitsEnd > afterSecondColon,
            isColumnTerminator(
              scalars[colDigitsEnd...], requireDiagnosticTail: requireDiagnosticTail),
            let col = Int(scalars[afterSecondColon..<colDigitsEnd]), col > 0
          {
            columnNumber = col
            tailStart = colDigitsEnd
          }
        }

        let tail = scalars[tailStart...]
        if !requireDiagnosticTail {
          if tail.isEmpty || tail.hasPrefix(":") || tail.hasPrefix(",") {
            return BuildDiagnosticLocation(path: rawPath, line: lineNumber, column: columnNumber)
          }
        } else if isDiagnosticTail(tail) {
          return BuildDiagnosticLocation(path: rawPath, line: lineNumber, column: columnNumber)
        }
      }
      searchStart = afterColon
    }
    return nil
  }

  private static func digitsEnd(in text: Substring, from start: Substring.Index) -> Substring.Index
  {
    var index = start
    while index < text.endIndex, text[index].isASCII, text[index].isNumber {
      index = text.index(after: index)
    }
    return index
  }

  private static func isColumnTerminator(
    _ tail: Substring, requireDiagnosticTail: Bool
  ) -> Bool {
    tail.hasPrefix(":") || (!requireDiagnosticTail && (tail.isEmpty || tail.hasPrefix(",")))
  }

  private static func isDiagnosticTail(_ tail: Substring) -> Bool {
    guard tail.hasPrefix(":") else { return false }
    let afterColon = tail.dropFirst()
    if afterColon.hasPrefix("(") {
      // Linker format: "main.c:42:(.text+0x4): undefined reference to ..."
      let lower = afterColon.lowercased()
      return lower.contains("undefined reference") || lower.contains("multiple definition")
        || lower.contains("error:") || lower.contains("warning:")
    }
    let message = afterColon.trimmingCharacters(in: .whitespaces).lowercased()
    return message.hasPrefix("error:")
      || message.hasPrefix("fatal error:")
      || message.hasPrefix("warning:")
      || message.hasPrefix("note:")
      || message.hasPrefix("undefined reference")
      || message.hasPrefix("multiple definition")
  }

  private static func isPlausiblePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.contains("://"), !path.hasPrefix("[") else { return false }
    let lastComponent = URL(filePath: path).lastPathComponent
    guard !lastComponent.isEmpty else { return false }
    // Require either a path separator or a filename extension (or CMakeLists.txt).
    return path.contains("/") || lastComponent.contains(".")
  }
}
