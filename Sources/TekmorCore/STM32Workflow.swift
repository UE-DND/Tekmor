import Foundation

/// Orders STM32 build, verified programming, and reset operations.
@MainActor
public struct STM32Workflow {
  public enum Action: Sendable {
    case inspect, reconfigure, build, run
    case resetTarget, eraseFlash
    case flash(URL, address: UInt64?, standalone: Bool)
  }

  /// The connection and chip information shown together when an operation was confirmed.
  public struct ConfirmedTarget: Sendable {
    public let connection: ChipConnection
    public let chip: ChipInformation

    public init(connection: ChipConnection, chip: ChipInformation) {
      self.connection = connection
      self.chip = chip
    }
  }

  public struct Context: Sendable {
    public let project: URL?
    public let configuration: ProjectConfiguration
    public let cube: CubeCLI?
    public let confirmedTarget: ConfirmedTarget?

    public init(
      project: URL?, configuration: ProjectConfiguration, cube: CubeCLI?,
      confirmedTarget: ConfirmedTarget? = nil
    ) {
      self.project = project
      self.configuration = configuration
      self.cube = cube
      self.confirmedTarget = confirmedTarget
    }
  }

  public enum Stage: Equatable, Sendable {
    case listingPresets, configuring
    case building(String)
    case checkingFirmware, readingChip
    case writing, resetting, startingApplication, resettingTarget, erasing
  }

  public enum Event: Sendable {
    case clearArtifact, toolsReady
    case stage(Stage)
    case presets([String], selected: String?)
    case targets([String], selected: String?)
    case configuredBuild(generator: String, toolsDescription: String)
    case builtArtifact(URL, usage: FirmwareUsage?)
    case selectedImage(URL, address: UInt64?, standalone: Bool)
    case chipRead(ChipConnection, ChipInformation)
    case firmwareUsage(FirmwareUsage)
    case writeEnded, applicationStarted
    case flashProgress(FlashProgress)
  }

  public enum Outcome: Equatable, Sendable {
    case inspected(Int)
    case awaitingTarget
    case built(URL)
    case flashed, targetReset, flashErased
  }

  @MainActor
  public protocol Interaction {
    func selectFlashConnection(for method: FlashMethod) throws -> (
      connection: ChipConnection, probeCount: Int
    )
    func checkTools(build: Bool, programmer: Bool) async throws
    func prepareProgrammerConnection(_ connection: ChipConnection) async throws
    func receive(_ event: Event)
  }

  private let builder: CMakeBuild
  private let cubeProgrammer: (CubeCLI) -> CubeProgrammer

  public init() {
    self.init(builder: CMakeBuild())
  }

  init(
    builder: CMakeBuild,
    cubeProgrammer: @escaping (CubeCLI) -> CubeProgrammer = { CubeProgrammer(cli: $0) }
  ) {
    self.builder = builder
    self.cubeProgrammer = cubeProgrammer
  }

  public func execute(
    _ action: Action, context: Context, interaction: any Interaction,
    log: @escaping ToolLog = { _ in }
  ) async throws -> Outcome {
    try Task.checkCancellation()
    do {
      switch action {
      case .flash(let file, let address, let standalone):
        try await interaction.checkTools(build: false, programmer: true)
        let target = try flashTarget(
          standalone: standalone, context: context, interaction: interaction)
        try Task.checkCancellation()
        interaction.receive(.toolsReady)
        interaction.receive(.selectedImage(file, address: address, standalone: standalone))
        try await flash(file, address: address, target: target, interaction: interaction, log: log)
        return .flashed
      case .resetTarget, .eraseFlash:
        let erase = if case .eraseFlash = action { true } else { false }
        return try await operateOnTarget(
          erase: erase, context: context, interaction: interaction, log: log)
      case .inspect, .reconfigure, .build, .run:
        return try await configureAndBuild(
          action, context: context, interaction: interaction, log: log)
      }
    } catch let failure as FlashFailure {
      interaction.receive(.flashProgress(failure.progress))
      throw failure
    }
  }

  private func configureAndBuild(
    _ action: Action, context: Context, interaction: any Interaction,
    log: @escaping ToolLog
  ) async throws -> Outcome {
    guard let project = context.project else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.workflow.openProjectFirst", defaultValue: "Open an existing CMake project first.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    var configuration = context.configuration
    let needsProgrammer: Bool
    if case .run = action { needsProgrammer = true } else { needsProgrammer = false }
    try await interaction.checkTools(build: true, programmer: needsProgrammer)
    let cli = try requireCube(context)
    let target =
      needsProgrammer
      ? try flashTarget(standalone: false, context: context, interaction: interaction) : nil
    interaction.receive(.clearArtifact)
    try Task.checkCancellation()
    interaction.receive(.toolsReady)

    interaction.receive(.stage(.listingPresets))
    let presets = CMakeBuild.sortedPresets(try await builder.presets(in: project, cli: cli))
    if configuration.cmake.toolchainFile == nil,
      configuration.cmake.configurePreset.map({ !presets.contains($0) }) ?? true
    {
      configuration.cmake.configurePreset = presets.first
    }
    interaction.receive(.presets(presets, selected: configuration.cmake.configurePreset))
    try configuration.validate()
    interaction.receive(.stage(.configuring))
    let fresh = if case .reconfigure = action { true } else { false }
    let selection = try await builder.configure(
      project: project, options: configuration.cmake, cli: cli, fresh: fresh, log: log)
    interaction.receive(
      .configuredBuild(generator: selection.generator, toolsDescription: selection.toolsDescription)
    )
    if let selected = configuration.cmake.target, !selection.targets.contains(selected) {
      configuration.cmake.target = nil
    }
    if selection.targets.count == 1 { configuration.cmake.target = selection.targets[0] }
    interaction.receive(.targets(selection.targets, selected: configuration.cmake.target))

    switch action {
    case .inspect, .reconfigure: return .inspected(selection.targets.count)
    default: break
    }
    guard let name = configuration.cmake.target else { return .awaitingTarget }
    interaction.receive(.stage(.building(name)))
    let elf = try await builder.build(name, selection: selection, log: log)
    interaction.receive(.builtArtifact(elf, usage: nil))

    guard let target else { return .built(elf) }
    try await flash(elf, address: nil, target: target, interaction: interaction, log: log)
    return .flashed
  }

  private struct FlashTarget {
    let connection: ChipConnection
    let cube: CubeCLI
    let expectedMCU: String?
    let confirmedChip: ChipInformation?
  }

  private func requireCube(_ context: Context) throws -> CubeCLI {
    guard let cli = context.cube else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.workflow.requireCube", defaultValue: "Install STM32CubeCLI in Tools first.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return cli
  }

  private func flashTarget(
    standalone: Bool, context: Context,
    interaction: any Interaction
  ) throws -> FlashTarget {
    let (connection, _) = try interaction.selectFlashConnection(for: context.configuration.flash)
    if let confirmed = context.confirmedTarget, confirmed.connection != connection {
      throw CubeProgrammer.targetChanged
    }
    return FlashTarget(
      connection: connection, cube: try requireCube(context),
      expectedMCU: standalone ? nil : context.configuration.mcu,
      confirmedChip: context.confirmedTarget?.chip)
  }

  private func flash(
    _ file: URL, address: UInt64?, target: FlashTarget,
    interaction: any Interaction, log: @escaping ToolLog
  ) async throws {
    try Task.checkCancellation()
    interaction.receive(.stage(.checkingFirmware))
    let image = try await Task.detached(priority: .userInitiated) {
      try FirmwareImage(file: file, binaryAddress: address)
    }.value
    try Task.checkCancellation()
    try await interaction.prepareProgrammerConnection(target.connection)
    try await flashWithCube(
      image, file: file, target: target, cube: cubeProgrammer(target.cube),
      interaction: interaction, log: log)
  }

  private func flashWithCube(
    _ image: FirmwareImage, file: URL, target: FlashTarget, cube: CubeProgrammer,
    interaction: any Interaction, log: @escaping ToolLog
  ) async throws {
    interaction.receive(.stage(.readingChip))
    let info = try await cube.read(target.connection, confirming: target.confirmedChip, log: log)
    interaction.receive(.chipRead(target.connection, info))
    try image.validateInternalFlash(capacity: info.flashBytes)
    try checkMCU(info, expected: target.expectedMCU)
    try await write(interaction: interaction) {
      try await cube.write(image, to: target.connection, confirmed: info, log: log)
    }
    interaction.receive(.flashProgress(.init(write: .verified)))
    if let capacity = info.flashBytes {
      interaction.receive(
        .firmwareUsage(.init(flashBytes: image.byteCount, flashCapacity: capacity)))
    }
    if case .swd = target.connection {
      interaction.receive(.stage(.resetting))
      try await cube.reset(target.connection, confirmed: info, log: log)
      interaction.receive(.flashProgress(.init(write: .verified, reset: .confirmed)))
    } else if let address = image.applicationStartAddress {
      interaction.receive(.stage(.startingApplication))
      do {
        try await cube.startUARTApplication(target.connection, address: address, log: log)
        interaction.receive(.applicationStarted)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        log(error.localizedDescription + "\n")
      }
    }
  }

  private func operateOnTarget(
    erase: Bool, context: Context, interaction: any Interaction, log: @escaping ToolLog
  ) async throws -> Outcome {
    try await interaction.checkTools(build: false, programmer: true)
    try context.configuration.validate()
    let target = try flashTarget(standalone: false, context: context, interaction: interaction)
    if !erase, case .uart = target.connection {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.cube.requiresSWD", defaultValue: "Target reset requires ST-LINK / SWD.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let cube = cubeProgrammer(target.cube)
    try await interaction.prepareProgrammerConnection(target.connection)
    interaction.receive(.stage(.readingChip))
    let info = try await cube.read(target.connection, confirming: target.confirmedChip, log: log)
    interaction.receive(.chipRead(target.connection, info))
    try checkMCU(info, expected: target.expectedMCU)
    if erase {
      try Task.checkCancellation()
      interaction.receive(.stage(.erasing))
      defer { interaction.receive(.writeEnded) }
      try await cube.erase(target.connection, confirmed: info, log: log)
      return .flashErased
    }
    interaction.receive(.stage(.resettingTarget))
    try await cube.resetTarget(target.connection, confirmed: info, log: log)
    return .targetReset
  }

  private func checkMCU(_ info: ChipInformation, expected: String?) throws {
    let match = info.match(expected: expected)
    if match == .mismatch, let expected {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.workflow.targetMismatch",
            defaultValue:
              "Connected target \(info.title) does not match expected project MCU \(expected).",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }

  private func write(
    interaction: any Interaction,
    _ action: () async throws -> Void
  ) async throws {
    try Task.checkCancellation()
    interaction.receive(.stage(.writing))
    defer { interaction.receive(.writeEnded) }
    try await action()
  }
}

extension STM32Workflow.Interaction {
  public func prepareProgrammerConnection(_ connection: ChipConnection) async throws {}
}
