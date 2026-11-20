import Foundation

public struct CubeBundle: Identifiable, Equatable, Sendable {
  public let name: String
  public let version: String
  public let platform: String
  public let path: URL?
  public let installed: Bool
  public var id: String { "\(name)@\(version):\(platform)" }

  public init(name: String, version: String, platform: String, path: URL? = nil, installed: Bool) {
    self.name = name
    self.version = version
    self.platform = platform
    self.path = path
    self.installed = installed
  }
}

public struct SystemToolStatus: Equatable, Sendable {
  public let name: String
  public let path: URL
  public let version: String?
  public let available: Bool
  public let detail: String?

  public init(
    name: String, path: URL, version: String? = nil, available: Bool, detail: String? = nil
  ) {
    self.name = name
    self.path = path
    self.version = version
    self.available = available
    self.detail = detail
  }
}

public struct CubeToolStatus: Equatable, Sendable {
  public let buildBundles: [CubeBundle]
  public let programmerBundles: [CubeBundle]
  public let buildIssue: String?
  public let programmerIssue: String?
  public let systemMake: SystemToolStatus

  public init(
    buildBundles: [CubeBundle], programmerBundles: [CubeBundle], buildIssue: String?,
    programmerIssue: String?, systemMake: SystemToolStatus
  ) {
    self.buildBundles = buildBundles
    self.programmerBundles = programmerBundles
    self.buildIssue = buildIssue
    self.programmerIssue = programmerIssue
    self.systemMake = systemMake
  }
}

struct CubeBuildRuntime: Sendable {
  let cli: CubeCLI
  let gcc: URL?
  let bundles: [CubeBundle]
}

extension CubeCLI {
  public static let defaultBuildNames = ["cmake", "gnu-tools-for-stm32", "ninja"]
  public static let programmerBundleName = "programmer"

  public static var defaultBuildBundles: [CubeBundle] {
    defaultBuildNames.map {
      CubeBundle(name: $0, version: "", platform: hostPlatform, installed: false)
    }
  }

  public static var defaultProgrammerBundles: [CubeBundle] {
    [CubeBundle(name: programmerBundleName, version: "", platform: hostPlatform, installed: false)]
  }

  public static func detectSystemMake(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> SystemToolStatus {
    let path = URL(filePath: "/usr/bin/make")
    let make = try? await CommandRunner().run(
      path, ["--version"], environment: environment, timeout: .seconds(10))
    if let make, make.succeeded {
      let firstLine =
        make.output.split(whereSeparator: \.isNewline).first
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      let version = firstLine.map { line in
        let prefix = "GNU Make "
        if line.hasPrefix(prefix) {
          let stripped = String(line.dropFirst(prefix.count))
          if !stripped.isEmpty { return stripped }
        }
        return line
      }
      return SystemToolStatus(name: "GNU Make", path: path, version: version, available: true)
    }
    return SystemToolStatus(
      name: "GNU Make",
      path: path,
      version: nil,
      available: false,
      detail: TekmorLocalization.core(
        .init(
          "core.cube.makeUnavailable",
          defaultValue: "System Make is unavailable. Unix Makefiles builds require Make.",
          bundle: .atURL(Bundle.module.bundleURL)))
    )
  }

  public func toolStatus() async throws -> CubeToolStatus {
    let installed = try await installedBundles()
    let build = Self.defaultBuildNames.map { name in
      installed.filter { $0.name == name }.sorted(by: Self.newerBundle).first
        ?? CubeBundle(name: name, version: "", platform: Self.hostPlatform, installed: false)
    }
    let programmers = installed.filter { $0.name == Self.programmerBundleName }.sorted(
      by: Self.newerBundle)
    let programmerRows = programmers.isEmpty ? Self.defaultProgrammerBundles : programmers

    let missingBuild = build.filter { !$0.installed }.map(\.name)
    var buildIssue: String?
    if !missingBuild.isEmpty {
      buildIssue = TekmorLocalization.core(
        .init(
          "core.cube.missingBuildBundles",
          defaultValue:
            "Prepare the missing build bundles in Tools: \(missingBuild.joined(separator: ", ")).",
          bundle: .atURL(Bundle.module.bundleURL)))
    } else if !build.contains(where: { $0.name == "cmake" && $0.installed })
      || !build.contains(where: { $0.name == "gnu-tools-for-stm32" && $0.installed })
    {
      buildIssue = TekmorLocalization.core(
        .init(
          "core.cube.missingCompilerBundles",
          defaultValue:
            "This build requires CMake and a Cube-managed compiler bundle. Prepare them in Tools.",
          bundle: .atURL(Bundle.module.bundleURL)))
    } else {
      buildIssue = try await validateInstalledBuildBundles(build)
    }

    let programmerIssue =
      programmers.isEmpty
      ? TekmorLocalization.core(
        .init(
          "core.cube.missingProgrammerBundle",
          defaultValue: "Prepare the programmer bundle in Tools.",
          bundle: .atURL(Bundle.module.bundleURL)))
      : try await commandIssue(Self.programmerBundleName)

    let systemMake = await Self.detectSystemMake(environment: processEnvironment)
    try Task.checkCancellation()
    return CubeToolStatus(
      buildBundles: build, programmerBundles: programmerRows,
      buildIssue: buildIssue, programmerIssue: programmerIssue, systemMake: systemMake)
  }

  public func installBundle(_ name: String, log: @escaping ToolLog = { _ in }) async throws {
    let supported = Set(Self.defaultBuildNames + [Self.programmerBundleName])
    guard supported.contains(name) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.unsupportedBundle",
            defaultValue: "Unsupported CubeCLI bundle \"\(name)\".",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let result = try await run(["bundle", "install", name, "--yes"], log: log)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opInstallBundle", defaultValue: "Installing bundle \(name)",
          bundle: .atURL(Bundle.module.bundleURL))))
    if name == Self.programmerBundleName {
      _ = try await resolve(Self.programmerBundleName)
      return
    }
    let status = try await toolStatus()
    guard let bundle = status.buildBundles.first(where: { $0.name == name && $0.installed }) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.missingBuildBundles",
            defaultValue: "Prepare the missing build bundles in Tools: \(name).",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    if let issue = try await validateInstalledBuildBundle(bundle) {
      throw TekmorError(issue)
    }
  }

  public func prepareBuildTools(log: @escaping ToolLog = { _ in }) async throws {
    let installedNames = Set((try? await installedBundles())?.map(\.name) ?? [])
    let missing = Self.defaultBuildNames.filter { !installedNames.contains($0) }
    let targets = missing.isEmpty ? Self.defaultBuildNames : missing
    let result = try await run(["bundle", "install", "--yes"] + targets, log: log)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opPrepareBuild", defaultValue: "Preparing build bundles",
          bundle: .atURL(Bundle.module.bundleURL))))
    let status = try await toolStatus()
    if let issue = status.buildIssue { throw TekmorError(issue) }
    _ = try await buildRuntime()
  }

  public func prepareProgrammer(log: @escaping ToolLog = { _ in }) async throws {
    let result = try await run(
      ["bundle", "install", Self.programmerBundleName, "--yes"], log: log)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opPrepareProgrammer", defaultValue: "Preparing the programmer bundle",
          bundle: .atURL(Bundle.module.bundleURL))))
    _ = try await resolve(Self.programmerBundleName)
  }

  public func prepareAllTools(log: @escaping ToolLog = { _ in }) async throws {
    let installedNames = Set((try? await installedBundles())?.map(\.name) ?? [])
    let allRequired = Self.defaultBuildNames + [Self.programmerBundleName]
    let missing = allRequired.filter { !installedNames.contains($0) }
    let targets = missing.isEmpty ? allRequired : missing
    let result = try await run(["bundle", "install", "--yes"] + targets, log: log)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opPrepareAll", defaultValue: "Preparing required bundles",
          bundle: .atURL(Bundle.module.bundleURL))))
    let status = try await toolStatus()
    if let issue = status.buildIssue ?? status.programmerIssue { throw TekmorError(issue) }
    _ = try await buildRuntime()
  }

  func buildRuntime() async throws -> CubeBuildRuntime {
    let status = try await toolStatus()
    if let issue = status.buildIssue { throw TekmorError(issue) }
    let bins = status.buildBundles.compactMap { $0.path?.appendingPathComponent("bin").path }
    var additions = ["PATH": (bins + [processEnvironment["PATH"] ?? ""]).joined(separator: ":")]
    for bundle in status.buildBundles {
      guard let root = bundle.path,
        let data = try? Data(contentsOf: root.appendingPathComponent("CubeBundle.json")),
        let definition = try? JSONDecoder().decode(BundleExports.self, from: data)
      else { continue }
      for name in definition.export ?? [] where name != "PATH" {
        if let value = definition.variables?[name]?.text {
          additions[name] = value.replacingOccurrences(of: "${CUBE_BUNDLE_ROOT}", with: root.path)
        }
      }
    }
    let root = status.buildBundles.first(where: { $0.name == "gnu-tools-for-stm32" })?.path
    let gcc = root?.appendingPathComponent("bin/arm-none-eabi-gcc")
    if let root, let gcc {
      additions["ARM_GNU_ROOT"] = root.path
      additions["ARM_GNU_GCC"] = gcc.path
      additions["CC"] = gcc.path
      additions["CXX"] = root.appendingPathComponent("bin/arm-none-eabi-g++").path
    }
    return CubeBuildRuntime(
      cli: settingEnvironment(additions), gcc: gcc, bundles: status.buildBundles)
  }

  private func validateInstalledBuildBundles(_ bundles: [CubeBundle]) async throws -> String? {
    for bundle in bundles {
      if let issue = try await validateInstalledBuildBundle(bundle) {
        return issue
      }
    }
    return nil
  }

  private func validateInstalledBuildBundle(_ bundle: CubeBundle) async throws -> String? {
    switch bundle.name {
    case "cmake":
      return try await commandIssue("cmake")
    case "gnu-tools-for-stm32":
      guard let root = bundle.path,
        ["arm-none-eabi-gcc", "arm-none-eabi-g++"].allSatisfy({
          FileManager.default.isExecutableFile(
            atPath: root.appendingPathComponent("bin/" + $0).path)
        })
      else {
        return TekmorLocalization.core(
          .init(
            "core.cube.compilerUnavailable",
            defaultValue:
              "The Cube-managed GCC compiler is unavailable. Prepare build tools again.",
            bundle: .atURL(Bundle.module.bundleURL)))
      }
      return nil
    case "ninja":
      return try await commandIssue("ninja")
    default:
      return nil
    }
  }

  private func installedBundles() async throws -> [CubeBundle] {
    let result = try await run(["--json", "bundle", "list"], timeout: .seconds(15))
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cube.opListBundles", defaultValue: "Listing installed bundles",
          bundle: .atURL(Bundle.module.bundleURL))))
    let entries = try JSONDecoder().decode([InstalledBundle].self, from: Data(result.output.utf8))
    return try entries.filter { Self.supportsPlatform($0.details.platform) }.map { entry in
      guard entry.path.hasPrefix("/"), !entry.details.name.isEmpty, !entry.details.version.isEmpty
      else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.cube.invalidBundleInfo",
              defaultValue: "CubeCLI returned invalid installed bundle information.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      return CubeBundle(
        name: entry.details.name, version: entry.details.version, platform: entry.details.platform,
        path: URL(filePath: entry.path, directoryHint: .isDirectory), installed: true)
    }
  }

  private func commandIssue(_ command: String) async throws -> String? {
    do {
      let data = try await resolve(command)
      let resolved = try JSONDecoder().decode(ResolvedCommand.self, from: data)
      guard let path = resolved.command.first, path.hasPrefix("/"),
        FileManager.default.isExecutableFile(atPath: path),
        (try? URL(filePath: path).resolvingSymlinksInPath().resourceValues(forKeys: [
          .isRegularFileKey
        ]).isRegularFile) == true
      else {
        return TekmorLocalization.core(
          .init(
            "core.cube.commandUnavailable",
            defaultValue: "CubeCLI command \(command) is unavailable. Prepare its bundle in Tools.",
            bundle: .atURL(Bundle.module.bundleURL)))
      }
      return nil
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return error.localizedDescription
    }
  }

  private static var hostPlatform: String { "aarch64-darwin" }
  private static func supportsPlatform(_ platform: String) -> Bool {
    [hostPlatform, "darwin", "all"].contains(platform)
  }

  private static func newerBundle(_ left: CubeBundle, _ right: CubeBundle) -> Bool {
    left.version.compare(right.version, options: .numeric) == .orderedDescending
  }

  private struct InstalledBundle: Decodable {
    struct Details: Decodable {
      let name: String
      let version: String
      let platform: String
    }
    let path: String
    let details: Details
  }
  private struct ResolvedCommand: Decodable { let command: [String] }
  private struct BundleExports: Decodable {
    struct Variable: Decodable {
      let text: String?
      init(from decoder: any Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
      }
    }
    let variables: [String: Variable]?
    let export: [String]?
  }
}
