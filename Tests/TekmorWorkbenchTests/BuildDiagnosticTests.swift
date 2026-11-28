import Foundation
import TekmorWorkbench
import Testing

@Suite("Build diagnostic location")
struct BuildDiagnosticTests {
  @Test func parsesGCCAndClangDiagnosticsWithLineAndColumn() {
    let error = BuildDiagnosticLocation.parse(
      from: "/Users/dev/stm32/Core/Src/main.c:42:13: error: 'LED_Pin' undeclared"
    )
    #expect(
      error
        == BuildDiagnosticLocation(
          path: "/Users/dev/stm32/Core/Src/main.c", line: 42, column: 13))
    #expect(error?.displayLabel == "main.c:42")

    let warning = BuildDiagnosticLocation.parse(
      from: "Core/Src/app.c:18:5: warning: unused variable 'count' [-Wunused-variable]"
    )
    #expect(warning == BuildDiagnosticLocation(path: "Core/Src/app.c", line: 18, column: 5))

    let fatal = BuildDiagnosticLocation.parse(
      from: "Core/Inc/main.h:10:10: fatal error: stm32f4xx_hal.h: No such file or directory"
    )
    #expect(fatal == BuildDiagnosticLocation(path: "Core/Inc/main.h", line: 10, column: 10))
  }

  @Test func parsesPathsContainingSpacesAndLinkerReferences() {
    let spaced = BuildDiagnosticLocation.parse(
      from: "/Users/dev/My STM32 Project/Core/Src/main.c:99:3: error: expected ';'"
    )
    #expect(
      spaced
        == BuildDiagnosticLocation(
          path: "/Users/dev/My STM32 Project/Core/Src/main.c", line: 99, column: 3))

    let linker = BuildDiagnosticLocation.parse(
      from: "Core/Src/main.c:54: undefined reference to `HAL_GPIO_TogglePin'"
    )
    #expect(linker == BuildDiagnosticLocation(path: "Core/Src/main.c", line: 54, column: nil))

    let linkerSection = BuildDiagnosticLocation.parse(
      from: "/tmp/proj/Core/Src/main.c:54:(.text.main+0x12): undefined reference to `foo'"
    )
    #expect(
      linkerSection
        == BuildDiagnosticLocation(path: "/tmp/proj/Core/Src/main.c", line: 54, column: nil))
  }

  @Test func parsesCMakeAndIncludeLines() {
    let cmakeError = BuildDiagnosticLocation.parse(
      from: "CMake Error at CMakeLists.txt:15 (add_executable):"
    )
    #expect(cmakeError == BuildDiagnosticLocation(path: "CMakeLists.txt", line: 15))

    let cmakeWarning = BuildDiagnosticLocation.parse(
      from: "CMake Warning at cmake/gcc-arm-none-eabi.cmake:8:"
    )
    #expect(
      cmakeWarning == BuildDiagnosticLocation(path: "cmake/gcc-arm-none-eabi.cmake", line: 8))

    let includeLine = BuildDiagnosticLocation.parse(
      from: "In file included from Core/Inc/main.h:24:"
    )
    #expect(includeLine == BuildDiagnosticLocation(path: "Core/Inc/main.h", line: 24))

    let includeWithColumn = BuildDiagnosticLocation.parse(
      from: "                 from Core/Inc/main.h:24:7,"
    )
    #expect(
      includeWithColumn == BuildDiagnosticLocation(path: "Core/Inc/main.h", line: 24, column: 7))
  }

  @Test func ignoresNonDiagnosticLines() {
    #expect(BuildDiagnosticLocation.parse(from: "[50%] Building C object main.c.obj") == nil)
    #expect(BuildDiagnosticLocation.parse(from: "12:34:56 warning: not a file") == nil)
    #expect(BuildDiagnosticLocation.parse(from: "https://example.com:443: error: url") == nil)
    #expect(
      BuildDiagnosticLocation.parse(from: "collect2: error: ld returned 1 exit status") == nil)
  }

  @Test func resolvesExistingRelativeAndAbsoluteFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "tekmor-diag-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let srcDir = tempDir.appending(path: "Core/Src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
    let fileURL = srcDir.appending(path: "main.c")
    try Data("int main(void) { return 0; }\n".utf8).write(to: fileURL)

    let relative = BuildDiagnosticLocation(path: "Core/Src/main.c", line: 1)
    #expect(relative.resolveURL(relativeTo: tempDir) == fileURL.standardizedFileURL)
    #expect(relative.resolveURL(relativeTo: nil) == nil)

    let absolute = BuildDiagnosticLocation(path: fileURL.path, line: 1)
    #expect(absolute.resolveURL(relativeTo: nil) == fileURL.standardizedFileURL)

    let missing = BuildDiagnosticLocation(path: "Core/Src/missing.c", line: 1)
    #expect(missing.resolveURL(relativeTo: tempDir) == nil)

    let directory = BuildDiagnosticLocation(path: "Core/Src", line: 1)
    #expect(directory.resolveURL(relativeTo: tempDir) == nil)
  }
}
