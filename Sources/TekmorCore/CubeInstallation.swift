import CryptoKit
import Foundation

public actor CubeInstallation {
  public static let defaultDirectory = URL.applicationSupportDirectory
    .appendingPathComponent("Tekmor/Toolchains", isDirectory: true)
  public static let version = "0.10.3"
  public static let downloadURL = URL(
    string: "https://developer.st.com/bundles/c/cube-wrapper-0.10.3-aarch64-darwin.bundle")!
  public static let sha256 = "81bfe6508a472fb69718103f02d0e66975fb7d827d677b616206075faa8affb9"

  public nonisolated let directory: URL
  public nonisolated var executable: URL {
    directory.appendingPathComponent("cube/\(Self.version)/bin/cube")
  }
  public nonisolated var cli: CubeCLI? {
    let stamp = executable.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".tekmor.sha256")
    guard (try? String(contentsOf: stamp, encoding: .utf8)) == expectedDigest,
      FileManager.default.isExecutableFile(atPath: executable.path)
    else { return nil }
    return CubeCLI(executable: executable, directory: directory)
  }

  private let archiveURL: URL
  private nonisolated let expectedDigest: String
  private let runner: CommandRunner
  private var installing = false

  public init(directory: URL = defaultDirectory) {
    self.init(directory: directory, archiveURL: Self.downloadURL, expectedDigest: Self.sha256)
  }

  init(
    directory: URL, archiveURL: URL, expectedDigest: String, runner: CommandRunner = CommandRunner()
  ) {
    self.directory = directory
    self.archiveURL = archiveURL
    self.expectedDigest = expectedDigest
    self.runner = runner
  }

  public func install(log: @escaping ToolLog = { _ in }) async throws {
    guard !installing else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.installInProgress", defaultValue: "CubeCLI installation is already running.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    guard !directory.path.contains(":") else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.invalidDirectory",
            defaultValue: "The tool installation directory path cannot contain a colon.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    installing = true
    defer { installing = false }
    let files = FileManager.default
    let destination = executable.deletingLastPathComponent().deletingLastPathComponent()
    let container = destination.deletingLastPathComponent()
    try files.createDirectory(at: container, withIntermediateDirectories: true)
    let staging = container.appendingPathComponent(
      ".install-\(UUID().uuidString)", isDirectory: true)
    try files.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: staging) }

    let archive: URL
    if archiveURL.isFileURL {
      archive = archiveURL
    } else {
      log(
        TekmorLocalization.core(
          .init(
            "core.cube.downloadBootstrapLog",
            defaultValue: "Downloading STM32CubeCLI \(Self.version)",
            bundle: .atURL(Bundle.module.bundleURL))) + "\n")
      let (download, response) = try await URLSession.shared.download(from: archiveURL)
      defer { try? files.removeItem(at: download) }
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
        http.url?.scheme == "https"
      else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.cube.downloadFailed",
              defaultValue:
                "Failed to download STM32CubeCLI. Check the network connection and try again.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      archive = staging.appendingPathComponent("download.bundle")
      try files.moveItem(at: download, to: archive)
    }
    try Task.checkCancellation()
    guard try Self.digest(archive) == expectedDigest else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.sha256Mismatch", defaultValue: "STM32CubeCLI SHA-256 verification failed.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let payload = staging.appendingPathComponent("payload", isDirectory: true)
    try files.createDirectory(at: payload, withIntermediateDirectories: false)
    let unpack = try await runner.run(
      URL(filePath: "/usr/bin/tar"),
      ["-xf", archive.path, "--safe-writes", "-C", payload.path], log: log)
    try unpack.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opUnpack", defaultValue: "Unpacking STM32CubeCLI",
          bundle: .atURL(Bundle.module.bundleURL))))
    let binary = payload.appendingPathComponent("bin/cube")
    guard binary.resolvingSymlinksInPath().path.hasPrefix(payload.path + "/"),
      files.isExecutableFile(atPath: binary.path)
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.invalidInstallation",
            defaultValue: "The CubeCLI package has an invalid executable layout.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let check = try await runner.run(
      binary, ["--version"],
      environment: CubeCLI(executable: binary, directory: directory).processEnvironment,
      timeout: .seconds(10), log: log)
    try check.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opCheckInstallation", defaultValue: "Verifying STM32CubeCLI",
          bundle: .atURL(Bundle.module.bundleURL))))
    guard check.output.contains(Self.version) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.unexpectedVersion",
            defaultValue: "The CubeCLI package returned an unexpected version.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    try Task.checkCancellation()
    try expectedDigest.write(
      to: payload.appendingPathComponent(".tekmor.sha256"), atomically: true, encoding: .utf8)
    if files.fileExists(atPath: destination.path) {
      let backup = staging.appendingPathComponent("previous")
      try files.moveItem(at: destination, to: backup)
      do {
        try files.moveItem(at: payload, to: destination)
      } catch {
        try files.moveItem(at: backup, to: destination)
        throw error
      }
    } else {
      try files.moveItem(at: payload, to: destination)
    }
    log(
      TekmorLocalization.core(
        .init(
          "core.cube.installedBootstrapLog", defaultValue: "Installed STM32CubeCLI \(Self.version)",
          bundle: .atURL(Bundle.module.bundleURL))) + "\n")
  }

  static func digest(_ path: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: path)
    defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      hash.update(data: bytes)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
