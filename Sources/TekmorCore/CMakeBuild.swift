import CryptoKit
import Foundation

public struct BuildSelection: Sendable {
  public let targets: [String]
  public let directory: URL
  fileprivate let artifacts: [String: URL]
  fileprivate let project: URL
  public let generator: String
  public let toolsDescription: String
  fileprivate let cli: CubeCLI
}

public struct CMakeBuild: Sendable {
  public static let defaultCache = URL.cachesDirectory.appendingPathComponent(
    "Tekmor/Builds", isDirectory: true)
  private static let presetFilenames = ["CMakePresets.json", "CMakeUserPresets.json"]
  private let cache: URL

  public init(cache: URL = Self.defaultCache) {
    self.cache = cache
  }

  public static func sortedPresets(_ names: [String]) -> [String] {
    Set(names).sorted { left, right in
      if (left == "Debug") != (right == "Debug") { return left == "Debug" }
      return left.localizedStandardCompare(right) == .orderedAscending
    }
  }

  public func presets(in project: URL, cli: CubeCLI) async throws -> [String] {
    let manager = FileManager.default
    guard
      Self.presetFilenames.contains(where: {
        manager.fileExists(atPath: project.appendingPathComponent($0).path)
      })
    else { return [] }
    let result = try await cli.run(["cmake", "--list-presets=configure"], in: project)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cmake.opListPresets", defaultValue: "Listing CMake configure presets",
          bundle: .atURL(Bundle.module.bundleURL))))
    return result.output.split(whereSeparator: \.isNewline).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.first == "\"" else { return nil }
      return trimmed.dropFirst().split(separator: "\"", maxSplits: 1).first.map(String.init)
    }
  }

  public func configure(
    project: URL, options: CMakeSettings, cli: CubeCLI, fresh: Bool = false,
    preferCached: Bool = false, log: @escaping ToolLog = { _ in }
  ) async throws -> BuildSelection {
    let files = FileManager.default
    let project = project.resolvingSymlinksInPath()
    let runtime = try await cli.buildRuntime()
    let directory = try await buildDirectory(project: project, options: options, runtime: runtime)
    try Task.checkCancellation()
    let reply = directory.appendingPathComponent(".cmake/api/v1/reply")
    let query = directory.appendingPathComponent(".cmake/api/v1/query")
    let inputStamp = reply.appendingPathComponent(".tekmor-inputs")
    let root = cache.resolvingSymlinksInPath().standardizedFileURL
    guard
      directory.resolvingSymlinksInPath().standardizedFileURL.path
        == root.appendingPathComponent(directory.lastPathComponent).path,
      isContained(query, in: directory),
      isContained(reply, in: directory)
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.invalidCacheDirectory",
            defaultValue: "Tekmor's build cache directory is invalid.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    if preferCached, !fresh, Self.cachedProjectPath(in: directory) == project.path,
      let index = try? fileAPIIndex(in: reply),
      let cachedStamp = try? Data(contentsOf: inputStamp),
      let currentStamp = try? inputFingerprint(for: index, in: reply, project: project),
      cachedStamp == currentStamp,
      let selection = try? selection(
        from: index.model, in: reply, project: project, directory: directory, runtime: runtime)
    {
      return selection
    }
    try Task.checkCancellation()
    try files.createDirectory(at: query, withIntermediateDirectories: true)
    try Data(project.path.utf8).write(
      to: directory.appendingPathComponent(Self.ownershipFile), options: .atomic)
    for request in ["codemodel-v2", "toolchains-v1", "cmakeFiles-v1"] {
      try Data().write(to: query.appendingPathComponent(request), options: .atomic)
    }
    // Each successful configure must produce a new response for this query.
    if files.fileExists(atPath: reply.path) { try files.removeItem(at: reply) }

    var args = ["-S", project.path, "-B", directory.path]
    if let gcc = runtime.gcc {
      args += [
        "-DARM_GNU_ROOT:PATH=\(gcc.deletingLastPathComponent().deletingLastPathComponent().path)",
        "-DARM_GNU_GCC:FILEPATH=\(gcc.path)",
      ]
    }
    if let preset = options.configurePreset {
      args.insert(contentsOf: ["--preset", preset], at: 0)
    } else {
      guard let toolchain = options.toolchainFile, ProjectConfiguration.isRelative(toolchain) else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.cmake.missingPresetAndToolchain",
              defaultValue:
                "This project has no configure presets. Select a CMake toolchain file inside the project.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      let toolchainURL = project.appendingPathComponent(toolchain)
      guard files.fileExists(atPath: toolchainURL.path) else {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.cmake.toolchainNotFound",
              defaultValue: "CMake toolchain file \"\(toolchain)\" not found.",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      args += ["-G", "Ninja", "--toolchain", toolchainURL.path, "-DCMAKE_BUILD_TYPE=Debug"]
    }
    let configureArgs = ["cmake"] + (fresh ? ["--fresh"] : []) + args
    let configureStarted = Date.now
    let result = try await runtime.cli.run(configureArgs, in: project, log: log)
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cmake.opConfigure", defaultValue: "Configuring CMake",
          bundle: .atURL(Bundle.module.bundleURL))))
    var index = try fileAPIIndex(in: reply)
    if index.model.cmake.generator.name == "Unix Makefiles" {
      try files.removeItem(at: reply)
      let configured = try await runtime.cli.run(
        ["cmake"] + args + ["-DCMAKE_MAKE_PROGRAM:FILEPATH=/usr/bin/make"], in: project, log: log)
      try configured.requireSuccess(
        TekmorLocalization.core(
          .init(
            "core.cmake.opConfigure", defaultValue: "Configuring CMake",
            bundle: .atURL(Bundle.module.bundleURL))))
      index = try fileAPIIndex(in: reply)
    }
    let selection = try selection(
      from: index.model, in: reply, project: project, directory: directory, runtime: runtime)
    if isContained(reply, in: directory),
      let stamp = try? inputFingerprint(
        for: index, in: reply, project: project, unchangedSince: configureStarted)
    {
      try? stamp.write(to: inputStamp, options: .atomic)
    }
    try Task.checkCancellation()
    return selection
  }

  private func fileAPIIndex(in reply: URL) throws -> (name: String, model: Index) {
    let files = try FileManager.default.contentsOfDirectory(
      at: reply, includingPropertiesForKeys: nil)
    guard
      let name = files.map(\.lastPathComponent).sorted(by: >).first(where: {
        $0.hasPrefix("index-") && $0.hasSuffix(".json")
      })
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.missingFileAPI",
            defaultValue: "CMake did not generate a File API target index.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return (name, try load(Index.self, at: jsonFile(name, in: reply)))
  }

  private func inputFingerprint(
    for index: (name: String, model: Index), in reply: URL, project: URL,
    unchangedSince: Date? = nil
  ) throws -> Data? {
    guard let reference = index.model.reply["cmakeFiles-v1"] else { return nil }
    let model = try load(ConfigureInputs.self, at: jsonFile(reference.jsonFile, in: reply))
    // Let CMake expand configure-dependent globs and resolve included presets.
    guard model.version.minor >= 1, model.globsDependent?.isEmpty != false,
      !model.inputs.isEmpty, try !usesIncludedPresets(in: project)
    else { return nil }

    var fingerprint = SHA256()
    fingerprint.update(data: Data(index.name.utf8))
    for input in model.inputs {
      try Task.checkCancellation()
      let url =
        input.path.hasPrefix("/") ? URL(filePath: input.path) : project.appending(path: input.path)
      let file = url.resolvingSymlinksInPath()
      let values = try file.resourceValues(forKeys: [
        .isRegularFileKey, .contentModificationDateKey,
      ])
      guard values.isRegularFile == true else { return nil }
      if let unchangedSince, input.isGenerated != true {
        guard let modified = values.contentModificationDate, modified <= unchangedSince else {
          return nil
        }
      }
      let digest = try CubeInstallation.digest(file)
      fingerprint.update(data: Data("\0\(file.path)\0\(digest)".utf8))
    }
    return Data(fingerprint.finalize())
  }

  private func usesIncludedPresets(in project: URL) throws -> Bool {
    for filename in Self.presetFilenames {
      let file = project.appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: file.path),
        try load(PresetIncludes.self, at: file).include?.isEmpty == false
      {
        return true
      }
    }
    return false
  }

  private func selection(
    from index: Index, in reply: URL, project: URL, directory: URL, runtime: CubeBuildRuntime
  ) throws -> BuildSelection {
    let generator = index.cmake.generator.name
    guard ["Unix Makefiles", "Ninja"].contains(generator) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.unsupportedGenerator",
            defaultValue: "This preset uses \(generator). Select a Unix Makefiles or Ninja preset.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    guard let toolchains = index.reply["toolchains-v1"] else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.missingToolchains",
            defaultValue: "CMake did not return the selected compiler information.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let compiler = try compilerBundle(
      at: try jsonFile(toolchains.jsonFile, in: reply), bundles: runtime.bundles)
    guard let codemodel = index.reply["codemodel-v2"] else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.missingCodeModel", defaultValue: "Failed to read CMake codemodel v2.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let model = try load(CodeModel.self, at: try jsonFile(codemodel.jsonFile, in: reply))
    var artifacts: [String: URL] = [:]
    for target in model.configurations.first?.targets ?? [] {
      let definition = try load(Target.self, at: try jsonFile(target.jsonFile, in: reply))
      if definition.type == "EXECUTABLE", let artifact = definition.artifacts?.first {
        let path = URL(filePath: artifact.path, relativeTo: directory).absoluteURL
        guard isContained(path, in: directory) else {
          throw TekmorError(
            TekmorLocalization.core(
              .init(
                "core.cmake.artifactOutsideBuildDir",
                defaultValue:
                  "The artifact for firmware target \"\(target.name)\" is outside Tekmor's build directory.",
                bundle: .atURL(Bundle.module.bundleURL))))
        }
        artifacts[target.name] = path
      }
    }
    guard !artifacts.isEmpty else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.noExecutableTargets",
            defaultValue: "This CMake configuration contains no executable firmware targets.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return BuildSelection(
      targets: artifacts.keys.sorted(), directory: directory, artifacts: artifacts,
      project: project, generator: generator,
      toolsDescription: "\(compiler.name) \(compiler.version) · \(generator)", cli: runtime.cli)
  }

  private static let ownershipFile = ".tekmor-project"

  private static func cachedProjectPath(in directory: URL) -> String? {
    let marker = directory.appendingPathComponent(ownershipFile)
    if let path = try? String(contentsOf: marker, encoding: .utf8), !path.isEmpty {
      return path
    }
    let cache = directory.appendingPathComponent("CMakeCache.txt")
    guard let contents = try? String(contentsOf: cache, encoding: .utf8) else { return nil }
    let prefix = "CMAKE_HOME_DIRECTORY:INTERNAL="
    return contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) })
      .map { String($0.dropFirst(prefix.count)) }
  }

  /// Removes identified build directories belonging to this project from Tekmor's cache.
  public func cleanCache(for project: URL) throws {
    let files = FileManager.default
    let root = cache.resolvingSymlinksInPath().standardizedFileURL
    guard files.fileExists(atPath: root.path) else { return }
    let path = project.resolvingSymlinksInPath().standardizedFileURL.path
    let directories = try files.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    for directory in directories {
      try Task.checkCancellation()
      guard
        directory.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression)
          != nil,
        let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
        values.isDirectory == true, values.isSymbolicLink != true,
        Self.cachedProjectPath(in: directory) == path
      else { continue }
      try files.removeItem(at: directory)
    }
  }

  public func build(
    _ target: String, selection: BuildSelection, log: @escaping ToolLog = { _ in }
  ) async throws -> URL {
    guard !target.hasPrefix("-"), let artifact = selection.artifacts[target] else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.selectTarget",
            defaultValue: "Select a firmware target from the current CMake configuration.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let result = try await selection.cli.run(
      [
        "cmake", "--build", selection.directory.path, "--target", target, "--parallel",
        String(min(8, ProcessInfo.processInfo.activeProcessorCount)),
      ],
      in: selection.project, log: log
    )
    try result.requireSuccess(
      TekmorLocalization.core(
        .init(
          "core.cmake.opBuild", defaultValue: "Building \(target)",
          bundle: .atURL(Bundle.module.bundleURL))))
    guard isContained(artifact, in: selection.directory),
      (try? artifact.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.artifactNotFound",
            defaultValue: "ELF artifact for firmware target \"\(target)\" not found.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return artifact
  }

  private func buildDirectory(project: URL, options: CMakeSettings, runtime: CubeBuildRuntime)
    async throws -> URL
  {
    var identity = [
      project.path, options.configurePreset ?? "", options.toolchainFile ?? "",
      runtime.cli.executable.path, try await runtime.cli.version(),
    ]
    let resolved = try await runtime.cli.resolve("cmake")
    let parsed = try JSONSerialization.jsonObject(with: resolved)
    let canonical = try JSONSerialization.data(withJSONObject: parsed, options: [.sortedKeys])
    identity.append(String(decoding: canonical, as: UTF8.self))
    identity += runtime.bundles.map { "\($0.id)|\($0.path?.path ?? "")" }
    identity += try await buildProgramIdentity(environment: runtime.cli.processEnvironment)
    for path in Self.presetFilenames {
      let file = project.appendingPathComponent(path)
      if FileManager.default.fileExists(atPath: file.path) {
        identity.append(try CubeInstallation.digest(file))
      }
    }
    if let toolchain = options.toolchainFile {
      identity.append(try CubeInstallation.digest(project.appendingPathComponent(toolchain)))
    }
    let key = SHA256.hash(data: Data(identity.joined(separator: "\0").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
    return cache.appendingPathComponent(key, isDirectory: true)
  }

  private func buildProgramIdentity(environment: [String: String]) async throws -> [String] {
    let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
    var identity: [String] = []
    for name in ["make", "ninja"] {
      let candidates =
        name == "make"
        ? [URL(filePath: "/usr/bin/make")]
        : directories.map { URL(filePath: $0).appendingPathComponent(name) }
      guard
        let executable = candidates.first(where: {
          FileManager.default.isExecutableFile(atPath: $0.path)
            && (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
              .isRegularFile) == true
        })
      else { continue }
      let result = try? await CommandRunner().run(
        executable, ["--version"], environment: environment, timeout: .seconds(10))
      try Task.checkCancellation()
      let version = result.flatMap { $0.succeeded ? $0.output : nil } ?? "unavailable"
      identity += [name, executable.resolvingSymlinksInPath().path, version]
    }
    return identity
  }

  private func compilerBundle(at file: URL, bundles: [CubeBundle]) throws -> CubeBundle {
    let model = try load(Toolchains.self, at: file)
    let paths = model.toolchains.compactMap { $0.compiler?.path }
    guard let first = paths.first else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.compilerMissing", defaultValue: "CMake did not select a C compiler.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let selected = paths.map { path in
      bundles.first { bundle in
        guard let root = bundle.path else { return false }
        return isContained(URL(filePath: path), in: root)
      }
    }
    guard selected.allSatisfy({ $0 != nil }),
      let bundle = bundles.first(where: {
        $0.path.map { isContained(URL(filePath: first), in: $0) } ?? false
      })
    else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.compilerOutsideCube",
            defaultValue:
              "The project compiler is outside the selected Cube bundles. Check its preset and toolchain file.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return bundle
  }

  private func isContained(_ url: URL, in directory: URL) -> Bool {
    url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/")
  }

  private func jsonFile(_ filename: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(filename)
    guard isContained(url, in: directory) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cmake.fileAPIOutsideDir",
            defaultValue: "The CMake File API reply references a file outside the build directory.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return url
  }

  private func load<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private struct Reference: Decodable { let jsonFile: String }
  private struct Index: Decodable {
    struct CMake: Decodable {
      struct Generator: Decodable { let name: String }
      let generator: Generator
    }
    let cmake: CMake
    let reply: [String: Reference]
  }
  private struct ConfigureInputs: Decodable {
    struct Version: Decodable { let minor: Int }
    struct Input: Decodable {
      let path: String
      let isGenerated: Bool?
    }
    struct Glob: Decodable { let expression: String }
    let version: Version
    let inputs: [Input]
    let globsDependent: [Glob]?
  }
  private struct PresetIncludes: Decodable { let include: [String]? }

  private struct CodeModel: Decodable {
    struct Configuration: Decodable {
      struct Target: Decodable {
        let name: String
        let jsonFile: String
      }
      let targets: [Target]
    }
    let configurations: [Configuration]
  }
  private struct Target: Decodable {
    struct Artifact: Decodable { let path: String }
    let type: String
    let artifacts: [Artifact]?
  }
  private struct Toolchains: Decodable {
    struct Toolchain: Decodable {
      struct Compiler: Decodable { let path: String? }
      let compiler: Compiler?
    }
    let toolchains: [Toolchain]
  }
}
