import AppKit
import Observation
import SwiftUI
import TekmorCore
import UniformTypeIdentifiers

@MainActor @Observable
final class Workspace {
  enum Action {
    case inspect, build, run
    case flash(URL, address: UInt64?, standalone: Bool)
    case installCube
    case installBundle(String)
    case prepareAllTools

    var isToolAction: Bool {
      switch self {
      case .installCube, .installBundle, .prepareAllTools: true
      case .inspect, .build, .run, .flash: false
      }
    }
  }

  enum LogDestination {
    case build
    case tools
  }

  enum ToolActivity: Equatable {
    case installingCube
    case installingBundle(String)
    case preparingAll(includesCube: Bool, bundles: Set<String>)
  }

  enum SidebarItem: Hashable {
    case project(String)
    case devices
    case tools
  }

  enum ProjectSortOrder: String, CaseIterable, Identifiable {
    case added, name
    var id: Self { self }

    func title(using l10n: AppL10n) -> String {
      switch self {
      case .added: l10n.tr(.init("sidebar.sort.added", defaultValue: "Date Added"))
      case .name: l10n.tr(.init("sidebar.sort.name", defaultValue: "Name (A–Z)"))
      }
    }
  }

  struct ProjectFolder: Identifiable {
    enum Tint: String, CaseIterable, Identifiable {
      case automatic, red, orange, yellow, green, blue, purple, gray
      var id: Self { self }
    }

    let path: String
    var tint: Tint
    var id: String { path }
    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
    var name: String { url.lastPathComponent }
  }

  enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    func title(using l10n: AppL10n) -> String {
      switch self {
      case .system: l10n.tr(.init("appearance.system", defaultValue: "System"))
      case .light: l10n.tr(.init("appearance.light", defaultValue: "Light"))
      case .dark: l10n.tr(.init("appearance.dark", defaultValue: "Dark"))
      }
    }

    var appAppearance: NSAppearance? {
      switch self {
      case .system: nil
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      }
    }
  }

  enum ExternalEditor: String, CaseIterable, Identifiable {
    case systemDefault
    case vsCode
    case cursor
    case zed
    case xcode

    var id: Self { self }

    func title(using l10n: AppL10n) -> String {
      switch self {
      case .systemDefault:
        l10n.tr(.init("settings.editor.systemDefault", defaultValue: "System Default"))
      case .vsCode: "Visual Studio Code"
      case .cursor: "Cursor"
      case .zed: "Zed"
      case .xcode: "Xcode"
      }
    }

    var urlScheme: String? {
      switch self {
      case .vsCode: "vscode"
      case .cursor: "cursor"
      case .zed: "zed"
      case .systemDefault, .xcode: nil
      }
    }
  }

  enum WorkspaceStatus: Equatable {
    case ready
    case preparing
    case cancelled
    case failed
    case toolsReady
    case verifyingTools
    case unavailableTools(Int)
    case installingTool(String)
    case toolInstalled(String)
    case configuringCMake
    case loadedTargets(Int)
    case selectTarget
    case building(String)
    case buildComplete(String)
    case checkingFirmware
    case readingChip
    case writingAndVerifying
    case verifiedResetting
    case flashingUART
    case flashingSWD
    case verifiedNeedsReset
    case verifiedAndReset
    case custom(String)

    func text(using l10n: AppL10n) -> String {
      switch self {
      case .ready: l10n.tr(.init("status.ready", defaultValue: "Ready"))
      case .preparing: l10n.tr(.init("status.preparing", defaultValue: "Preparing"))
      case .cancelled: l10n.tr(.init("status.cancelled", defaultValue: "Cancelled"))
      case .failed: l10n.tr(.init("status.failed", defaultValue: "Task failed"))
      case .toolsReady: l10n.tr(.init("status.toolsReady", defaultValue: "Tools ready"))
      case .verifyingTools:
        l10n.tr(.init("status.verifyingTools", defaultValue: "Checking Cube tools"))
      case .unavailableTools(let count):
        l10n.tr(.init("status.unavailableTools", defaultValue: "Tools to install (\(count))"))
      case .installingTool(let name):
        l10n.tr(.init("status.installingTool", defaultValue: "Installing \(name)"))
      case .toolInstalled(let name):
        l10n.tr(.init("status.toolInstalled", defaultValue: "Installed \(name)"))
      case .configuringCMake:
        l10n.tr(.init("status.configuringCMake", defaultValue: "Configuring CMake"))
      case .loadedTargets(let count):
        l10n.tr(.init("status.loadedTargets", defaultValue: "Loaded \(count) executable targets"))
      case .selectTarget:
        l10n.tr(.init("status.selectTarget", defaultValue: "Select a firmware target"))
      case .building(let target):
        l10n.tr(.init("status.building", defaultValue: "Building \(target)"))
      case .buildComplete(let elf):
        l10n.tr(.init("status.buildComplete", defaultValue: "Build complete · \(elf)"))
      case .checkingFirmware:
        l10n.tr(.init("status.checkingFirmware", defaultValue: "Inspecting firmware"))
      case .readingChip: l10n.tr(.init("status.readingChip", defaultValue: "Reading target chip"))
      case .writingAndVerifying:
        l10n.tr(.init("status.writingAndVerifying", defaultValue: "Writing and verifying"))
      case .verifiedResetting:
        l10n.tr(.init("status.verifiedResetting", defaultValue: "Verified, resetting target"))
      case .flashingUART:
        l10n.tr(.init("status.flashingUART", defaultValue: "Flashing & verifying via UART"))
      case .flashingSWD:
        l10n.tr(.init("status.flashingSWD", defaultValue: "Flashing & verifying via SWD"))
      case .verifiedNeedsReset:
        l10n.tr(
          .init(
            "status.verifiedNeedsReset", defaultValue: "Flashed & verified · manual reset required")
        )
      case .verifiedAndReset:
        l10n.tr(.init("status.verifiedAndReset", defaultValue: "Flashed, verified & reset"))
      case .custom(let message): message
      }
    }
  }

  enum CubeStatusMessage: Equatable {
    case notFound
    case custom(String)

    func text(using l10n: AppL10n) -> String {
      switch self {
      case .notFound: l10n.tr(.init("cube.notFound", defaultValue: "STM32CubeCLI not found."))
      case .custom(let message): message
      }
    }
  }

  // MARK: - Navigation & Global Settings
  private(set) var sidebarSelection: SidebarItem?
  private(set) var workbench: WorkbenchLayout {
    didSet {
      if workbench != oldValue, let data = try? JSONEncoder().encode(workbench) {
        preferences.set(data, forKey: "workbenchLayout")
      }
    }
  }
  var activePane: ConsolePane { workbench.activePane }
  var isSplitConsole: Bool { workbench.isSplit }
  var canUseOutputCommands: Bool {
    canArrangeConsole && activePane != .terminal
  }
  var canSearchActiveConsole: Bool {
    canArrangeConsole && (activePane != .terminal || terminalSession?.terminalView != nil)
  }
  var canNavigateConsoleSearch: Bool {
    guard canSearchActiveConsole else { return false }
    switch activePane {
    case .buildLog: return !output.logSearchQuery.isEmpty
    case .serial: return !output.serialSearchQuery.isEmpty
    case .terminal: return terminalSession?.searchQuery.isEmpty == false
    }
  }
  var canClearActiveConsole: Bool {
    canUseOutputCommands && !(activePane == .serial ? output.serialLines : output.logLines).isEmpty
  }

  let terminals = ProjectTerminalSessions()
  var terminalSession: ProjectTerminal? { terminals.session(for: project) }
  var terminalDirectory: URL { project ?? FileManager.default.homeDirectoryForCurrentUser }
  private var showsStandaloneConsole = false

  var projectSortOrder: ProjectSortOrder {
    didSet { preferences.set(projectSortOrder.rawValue, forKey: "projectSortOrder") }
  }

  var showInspector: Bool {
    didSet { preferences.set(showInspector, forKey: "showInspector") }
  }
  var followBuildLog: Bool
  var followSerial: Bool

  var appearance: AppearanceMode {
    didSet {
      preferences.set(appearance.rawValue, forKey: "appearanceMode")
      NSApplication.shared.appearance = appearance.appAppearance
    }
  }
  var language: AppLanguage {
    didSet {
      preferences.set(language.rawValue, forKey: "appLanguage")
      TekmorLocalization.language = language
    }
  }
  var consoleFontSize: Double {
    didSet { preferences.set(consoleFontSize, forKey: "consoleFontSize") }
  }
  var workbenchTextScale: Double {
    didSet { preferences.set(workbenchTextScale, forKey: "workbenchTextScale") }
  }
  var defaultFollowOutput: Bool {
    didSet {
      preferences.set(defaultFollowOutput, forKey: "defaultFollowOutput")
      followBuildLog = defaultFollowOutput
      followSerial = defaultFollowOutput
    }
  }
  var showTimestamps: Bool {
    didSet { preferences.set(showTimestamps, forKey: "showTimestamps") }
  }
  var defaultFlashMethod: FlashMethod {
    didSet { preferences.set(defaultFlashMethod.rawValue, forKey: "defaultFlashMethod") }
  }
  var defaultBaudRate: Int {
    didSet { preferences.set(defaultBaudRate, forKey: "defaultBaudRate") }
  }
  var externalEditor: ExternalEditor {
    didSet { preferences.set(externalEditor.rawValue, forKey: "externalEditor") }
  }

  // MARK: - Project & Hardware State
  private(set) var project: URL?
  private(set) var projectFolders: [ProjectFolder] = [] {
    didSet {
      preferences.set(
        projectFolders.map { ["path": $0.path, "tint": $0.tint.rawValue] }, forKey: "projectFolders"
      )
    }
  }
  var configuration = ProjectConfiguration()
  private(set) var presets: [String] = []
  private(set) var targets: [String] = []
  private(set) var devices: [SerialDevice] = []
  private(set) var probes: [STLinkProbe] = []
  private(set) var selectedProbeID: UInt64?
  private(set) var chipReadings = ChipReadings()
  private(set) var chipHintKeys: [UInt64: LocalizedStringResource] = [:]
  private(set) var cubeVersion: String?
  private(set) var cubeMessageState: CubeStatusMessage?
  private(set) var loadingCube = false
  private(set) var hasCheckedCube = false
  var binaryFirmware: URL?
  private(set) var serialPath: String? {
    didSet {
      if let serialPath {
        preferences.set(serialPath, forKey: "monitorSerialPath")
      } else {
        preferences.removeObject(forKey: "monitorSerialPath")
      }
    }
  }
  private(set) var flashSerialPath: String? {
    didSet {
      if let flashSerialPath {
        preferences.set(flashSerialPath, forKey: "flashSerialPath")
      } else {
        preferences.removeObject(forKey: "flashSerialPath")
      }
    }
  }
  private var serialTransmitByProject: [URL?: SerialTransmit] = [:]
  var serialCommand: SerialCommand {
    get { serialTransmitByProject[project]?.command ?? SerialCommand() }
    set { serialTransmitByProject[project, default: SerialTransmit()].edit(newValue) }
  }
  let output = WorkspaceOutput()
  enum ConsoleSearchAction { case toggle, next, previous }
  private(set) var consoleSearchAction: ConsoleSearchAction = .toggle
  private(set) var consoleSearchRequest = 0

  // MARK: - Task & Serial State
  private(set) var statusState: WorkspaceStatus = .ready
  private(set) var lastBuildDuration: Duration?
  private(set) var lastFirmwareUsage: FirmwareUsage?
  private var closingSerialDevices: [UUID: SerialDevice] = [:]
  private(set) var activeFlashConnection: ChipConnection?
  private(set) var serialConnected = false
  private(set) var sendingSerial = false
  private(set) var running = false
  private(set) var writing = false
  private(set) var choosingFile = false
  private(set) var toolActivity: ToolActivity?
  var showingToolLog = false
  private(set) var errorLogDestination: LogDestination?
  var errorMessage: String? {
    didSet {
      if errorMessage == nil { errorLogDestination = nil }
    }
  }
  private(set) var buildBundleRows: [CubeBundle] = CubeCLI.defaultBuildBundles
  private(set) var programmerBundleRows: [CubeBundle] = CubeCLI.defaultProgrammerBundles
  private(set) var buildToolsIssue: String?
  private(set) var programmerIssue: String?
  private(set) var buildGenerator: String?
  private(set) var buildToolsDescription: String?
  private(set) var lastArtifact: URL?
  private(set) var firmwareByteCount: Int?
  private(set) var firmwareFlashBytes: Int?
  private(set) var firmwareRAMBytes: Int?
  private(set) var firmwareSections: [FirmwareSection] = []
  private(set) var firmwareRanges: [Range<UInt64>] = []
  private(set) var toolDirectory: URL
  private(set) var copiedNotice: String?

  @ObservationIgnored private let preferences = UserDefaults.standard
  @ObservationIgnored private let workflow = STM32Workflow()
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var artifactReadID = UUID()
  @ObservationIgnored private var standaloneImage: (file: URL, address: UInt64?)?
  @ObservationIgnored private var chipTask: Task<Void, Never>?
  @ObservationIgnored private var activeChipConnection: ChipConnection?
  @ObservationIgnored private var programmerAvailable = false
  @ObservationIgnored private var cubeRefreshID = UUID()
  @ObservationIgnored private var serial: SerialConnection?
  @ObservationIgnored private var serialID = UUID()
  @ObservationIgnored private var operationID = UUID()
  @ObservationIgnored private var noticeTask: Task<Void, Never>?

  init() {
    let defaults = UserDefaults.standard
    projectSortOrder =
      defaults.string(forKey: "projectSortOrder").flatMap(ProjectSortOrder.init(rawValue:))
      ?? .added
    let savedLayout = defaults.data(forKey: "workbenchLayout")
      .flatMap { try? JSONDecoder().decode(WorkbenchLayout.self, from: $0) }
    workbench = savedLayout.flatMap { $0.isValid ? $0 : nil } ?? WorkbenchLayout()
    showInspector = defaults.bool(forKey: "showInspector")
    let initialAppearance =
      defaults.string(forKey: "appearanceMode")
      .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    appearance = initialAppearance
    // Property observers do not run during initialization. Apply the saved mode before creating windows.
    NSApplication.shared.appearance = initialAppearance.appAppearance
    let initialLanguage =
      defaults.string(forKey: "appLanguage")
      .flatMap(AppLanguage.init(rawValue:)) ?? .system
    language = initialLanguage
    TekmorLocalization.language = initialLanguage
    let storedFont = defaults.double(forKey: "consoleFontSize")
    consoleFontSize = (11.0...25.0).contains(storedFont) ? storedFont : 12.5
    let storedScale = defaults.double(forKey: "workbenchTextScale")
    workbenchTextScale = (1.0...2.0).contains(storedScale) ? storedScale : 1
    let initialFollow = defaults.object(forKey: "defaultFollowOutput") as? Bool ?? true
    defaultFollowOutput = initialFollow
    followBuildLog = initialFollow
    followSerial = initialFollow
    showTimestamps = defaults.object(forKey: "showTimestamps") as? Bool ?? true
    let initialFlash =
      defaults.string(forKey: "defaultFlashMethod")
      .flatMap(FlashMethod.init(rawValue:)) ?? .uart
    defaultFlashMethod = initialFlash
    let storedBaud = defaults.integer(forKey: "defaultBaudRate")
    let initialBaud = SerialSettings.baudRates.contains(storedBaud) ? storedBaud : 115200
    defaultBaudRate = initialBaud
    externalEditor =
      defaults.string(forKey: "externalEditor").flatMap(ExternalEditor.init(rawValue:))
      ?? .systemDefault

    toolDirectory =
      defaults.string(forKey: "toolDirectory")
      .map { URL(filePath: $0, directoryHint: .isDirectory) } ?? CubeInstallation.defaultDirectory

    buildToolsIssue = l10n.tr(.init("tools.checking", defaultValue: "Checking tools…"))
    programmerIssue = buildToolsIssue
    configuration.flash = initialFlash
    configuration.serial.baud = initialBaud
    projectFolders = (defaults.array(forKey: "projectFolders") as? [[String: String]] ?? [])
      .compactMap { record in
        guard let path = record["path"],
          let tint = record["tint"].flatMap(ProjectFolder.Tint.init(rawValue:))
        else { return nil }
        return ProjectFolder(path: path, tint: tint)
      }
    let savedMonitorSerial = defaults.string(forKey: "monitorSerialPath")
    let savedFlashSerial = defaults.string(forKey: "flashSerialPath")
    refreshDevices()
    if let savedMonitorSerial, devices.contains(where: { $0.id == savedMonitorSerial }) {
      serialPath = savedMonitorSerial
    }
    if let savedFlashSerial, devices.contains(where: { $0.id == savedFlashSerial }) {
      flashSerialPath = savedFlashSerial
    }

    if let last = defaults.string(forKey: "lastProject"),
      let folder = projectFolders.first(where: { $0.path == last })
    {
      loadProject(folder.url)
    }
    Task { await refreshCube() }
  }

  // MARK: - Computed Properties

  var l10n: AppL10n { AppL10n(language: language) }
  var locale: Locale { language.locale }
  var status: String { statusState.text(using: l10n) }
  var cubeMessage: String? { cubeMessageState?.text(using: l10n) }

  func chipMessage(for id: UInt64, fallback: String) -> String {
    chipHintKeys[id].map { l10n.tr($0) } ?? fallback
  }

  var selectedSerial: SerialDevice? { devices.first { $0.id == serialPath } }
  var canStartAction: Bool { !running && !choosingFile }
  var canSendSerial: Bool {
    serialConnected && !sendingSerial
      && (!serialCommand.input.isEmpty || serialCommand.lineEnding != .none)
  }
  var selectedFlashSerial: SerialDevice? { devices.first { $0.id == flashSerialPath } }
  var canSelectMonitorPort: Bool { !choosingFile }
  var canToggleSerial: Bool {
    guard canSelectMonitorPort else { return false }
    if serialConnected { return true }
    guard let device = selectedSerial,
      !closingSerialDevices.values.contains(where: { $0.isSamePort(as: device) })
    else { return false }
    if case .uart(let target) = activeFlashConnection { return !target.isSamePort(as: device) }
    return true
  }
  var canChooseFirmware: Bool { canStartAction && programmerIssue == nil }
  var canCancelTask: Bool { running && !writing }
  var canArrangeConsole: Bool { isShowingProjectArea && hasConsoleContent }
  var canBuildProject: Bool {
    project != nil && canStartAction && buildToolsIssue == nil && !loadingCube
  }
  var canRunProject: Bool {
    canBuildProject && programmerIssue == nil && flashSelectionIssue == nil
  }

  var serialSelectionIssue: String? {
    guard selectedSerial == nil else { return nil }
    if devices.isEmpty {
      return l10n.tr(.init("issue.noSerialPort", defaultValue: "No serial port detected"))
    }
    if serialPath != nil {
      return l10n.tr(
        .init(
          "issue.serialDisconnected",
          defaultValue: "Selected serial port disconnected; choose another"))
    }
    return l10n.tr(.init("issue.selectMonitorSerial", defaultValue: "Select a listening port"))
  }

  var flashProbe: STLinkProbe? {
    if probes.count == 1 { return probes.first }
    return probes.first { $0.id == selectedProbeID }
  }

  var probeIssue: String? {
    guard configuration.flash == .swd else { return nil }
    if probes.isEmpty {
      return l10n.tr(.init("issue.noSTLink", defaultValue: "No ST-LINK detected"))
    }
    guard let probe = flashProbe else {
      return l10n.tr(
        .init("issue.selectSTLink", defaultValue: "Select an ST-LINK probe for flashing"))
    }
    if probes.count > 1, !canIdentify(probe) {
      return l10n.tr(
        .init(
          "issue.ambiguousSTLink",
          defaultValue: "Cannot distinguish selected ST-LINK; keep only the target probe connected")
      )
    }
    return nil
  }

  var flashSelectionIssue: String? {
    if configuration.flash == .swd { return probeIssue }
    guard selectedFlashSerial == nil else { return nil }
    if devices.isEmpty {
      return l10n.tr(.init("issue.noSerialPort", defaultValue: "No serial port detected"))
    }
    return l10n.tr(.init("quickbar.selectFlashPort", defaultValue: "Select Flash Port"))
  }

  var flashSerialOccupancyIssue: String? {
    guard let device = selectedFlashSerial,
      serial?.device.isSamePort(as: device) == true
        || closingSerialDevices.values.contains(where: { $0.isSamePort(as: device) })
    else { return nil }
    return l10n.tr(
      .init("issue.stopListeningBeforeFlash", defaultValue: "Stop listening before flashing"))
  }

  var flashHardwareIssue: String? {
    flashSelectionIssue ?? (configuration.flash == .uart ? flashSerialOccupancyIssue : nil)
  }
  var cubeDisplayVersion: String? { cubeVersion.map(CubeCLI.displayVersion(from:)) }
  var cubeExecutablePath: String { CubeInstallation(directory: toolDirectory).executable.path }

  private var cubeCLI: CubeCLI? { CubeInstallation(directory: toolDirectory).cli }
  var isManagingTools: Bool { toolActivity != nil }

  var isInstallingCube: Bool {
    switch toolActivity {
    case .installingCube: true
    case .preparingAll(let includesCube, _): includesCube && cubeVersion == nil
    default: false
    }
  }

  func isInstallingBundle(_ bundle: CubeBundle) -> Bool {
    switch toolActivity {
    case .installingBundle(let name):
      return bundle.name == name
    case .preparingAll(_, let names):
      return names.contains(bundle.name)
    case .installingCube, nil:
      return false
    }
  }

  var missingBuildBundleNames: [String] {
    buildBundleRows.filter { !$0.installed }.map(\.name)
  }

  var missingProgrammerBundles: Bool {
    !programmerBundleRows.contains(where: \.installed)
  }

  var buildHasValidationIssue: Bool {
    cubeVersion != nil && missingBuildBundleNames.isEmpty && buildToolsIssue != nil && !loadingCube
  }

  var programmerHasValidationIssue: Bool {
    cubeVersion != nil && !missingProgrammerBundles && programmerIssue != nil && !loadingCube
  }

  var displayedProjectFolders: [ProjectFolder] {
    switch projectSortOrder {
    case .added: projectFolders
    case .name:
      projectFolders.sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))
    }
  }

  var isShowingProjectArea: Bool {
    switch sidebarSelection {
    case .project, nil: true
    case .devices, .tools: false
    }
  }

  var hasConsoleContent: Bool {
    project != nil || showsStandaloneConsole || (running && !isManagingTools)
      || !output.logLines.isEmpty
      || serialConnected
      || !output.serialLines.isEmpty
  }

  private var bundleRows: [CubeBundle] {
    Array(
      Dictionary(
        (buildBundleRows + programmerBundleRows).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
      ).values)
  }
  var installedToolCount: Int {
    (cubeVersion == nil ? 0 : 1) + bundleRows.filter(\.installed).count
  }
  var totalToolCount: Int { 1 + bundleRows.count }
  var missingRequiredToolCount: Int {
    guard hasCheckedCube else { return 0 }
    return (cubeVersion == nil ? 1 : 0) + bundleRows.filter { !$0.installed }.count
  }
  var connectedDeviceCount: Int { devices.count + probes.count }
  var isDefaultToolDirectory: Bool {
    toolDirectory.standardizedFileURL == CubeInstallation.defaultDirectory.standardizedFileURL
  }

  var serialFramingSummary: String {
    let parityCode: String =
      switch configuration.serial.parity {
      case .none: "N"
      case .even: "E"
      case .odd: "O"
      }
    return "\(configuration.serial.baud) 8\(parityCode)\(configuration.serial.stopBits)"
  }

  // MARK: - Project Actions

  func chooseProject() {
    guard canStartAction else { return }
    chooseDirectory(
      title: l10n.tr(
        .init("panel.openProject", defaultValue: "Open a project containing CMakeLists.txt"))
    ) {
      self.open($0.resolvingSymlinksInPath().standardizedFileURL)
    }
  }

  private func open(_ url: URL) {
    if project?.path == url.path {
      showProjectArea()
    } else if canStartAction {
      loadProject(url)
    }
  }

  private func loadProject(_ url: URL) {
    do {
      guard
        FileManager.default.fileExists(atPath: url.appendingPathComponent("CMakeLists.txt").path)
      else {
        throw TekmorError(
          l10n.tr(
            .init(
              "error.noCMakeLists",
              defaultValue:
                "No CMakeLists.txt found in the selected directory. Choose the project root.")))
      }
      let suggestedPresets = proposedPresets(in: url)
      var nextConfiguration = ProjectConfiguration()
      nextConfiguration.flash = defaultFlashMethod
      nextConfiguration.serial.baud = defaultBaudRate
      nextConfiguration.cmake.configurePreset = suggestedPresets.first
      dropSerial()
      project = url
      preferences.set(url.path, forKey: "lastProject")
      configuration = nextConfiguration
      presets = suggestedPresets
      targets = []
      refreshDevices()
      if !projectFolders.contains(where: { $0.path == url.path }) {
        projectFolders.append(ProjectFolder(path: url.path, tint: .automatic))
      }
      output.clearLog()
      output.clearSerial()
      output.resetSearch()
      errorMessage = nil
      buildGenerator = nil
      buildToolsDescription = nil
      statusState = .ready
      lastArtifact = nil
      clearArtifactDetails()
      lastFirmwareUsage = nil
      lastBuildDuration = nil
      showsStandaloneConsole = false
      showProjectArea()
      if activePane == .terminal { openTerminalSession() }
    } catch {
      reportError(error.localizedDescription)
    }
  }

  func closeProject() {
    guard canStartAction else { return }
    unloadProject()
  }

  private func unloadProject() {
    dropSerial()
    if let project { terminals.remove(project) }
    project = nil
    showProjectArea()
    preferences.removeObject(forKey: "lastProject")
    configuration = ProjectConfiguration()
    configuration.flash = defaultFlashMethod
    configuration.serial.baud = defaultBaudRate
    presets = []
    targets = []
    lastArtifact = nil
    clearArtifactDetails()
    lastFirmwareUsage = nil
    lastBuildDuration = nil
    output.clearLog()
    output.clearSerial()
    output.resetSearch()
    showsStandaloneConsole = false
    workbench.select(.buildLog)
    statusState = .ready
    buildGenerator = nil
    buildToolsDescription = nil
  }

  func removeProject(_ path: String) {
    if project?.path == path {
      guard canStartAction else { return }
      unloadProject()
    } else if let folder = projectFolders.first(where: { $0.path == path }) {
      terminals.remove(folder.url)
    }
    projectFolders.removeAll { $0.path == path }
  }

  func setProjectTint(_ tint: ProjectFolder.Tint, for path: String) {
    guard let index = projectFolders.firstIndex(where: { $0.path == path }) else { return }
    projectFolders[index].tint = tint
  }

  func chooseCMakeToolchain() {
    guard canStartAction, let project else { return }
    let panel = NSOpenPanel()
    panel.directoryURL = project
    panel.allowedContentTypes = [UTType(filenameExtension: "cmake") ?? .text]
    panel.message = l10n.tr(
      .init(
        "panel.chooseToolchain", defaultValue: "Select a CMake toolchain file inside the project"))
    chooseFile(using: panel) { file in
      guard self.project == project, file.path.hasPrefix(project.path + "/") else { return }
      self.configuration.cmake.toolchainFile = String(file.path.dropFirst(project.path.count + 1))
    }
  }

  func setConfigurePreset(_ preset: String?) {
    guard configuration.cmake.configurePreset != preset else { return }
    configuration.cmake.configurePreset = preset
    if preset != nil { configuration.cmake.toolchainFile = nil }
    targets = []
    buildGenerator = nil
    buildToolsDescription = nil
  }

  func chooseFirmware() {
    guard canChooseFirmware else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = ["elf", "axf", "out", "hex", "bin"].map {
      UTType(filenameExtension: $0) ?? .data
    }
    panel.message = l10n.tr(
      .init("panel.chooseFirmware", defaultValue: "Select an ELF, Intel HEX, or BIN firmware file"))
    chooseFile(using: panel) { url in
      if url.pathExtension.lowercased() == "bin" {
        self.binaryFirmware = url
      } else {
        self.start(.flash(url, address: nil, standalone: true))
      }
    }
  }

  func flashBinary(at address: UInt64) {
    guard let file = binaryFirmware else { return }
    binaryFirmware = nil
    start(.flash(file, address: address, standalone: true))
  }

  func flashLastArtifact() {
    guard canStartAction, let artifact = lastArtifact else { return }
    let image = standaloneImage?.file == artifact ? standaloneImage : nil
    start(.flash(artifact, address: image?.address, standalone: image != nil))
  }

  func requestConsoleSearch(_ action: ConsoleSearchAction = .toggle) {
    guard canSearchActiveConsole else { return }
    consoleSearchAction = action
    consoleSearchRequest += 1
  }

  func showBuildLog() {
    showProjectArea()
    selectConsolePane(.buildLog)
  }

  func showToolLog() {
    showingToolLog = true
  }

  func clearToolLog() {
    output.clearToolLog()
  }

  func showSerialMonitor() {
    showProjectArea()
    if project == nil { showsStandaloneConsole = true }
    selectConsolePane(.serial)
  }

  func showTerminal() {
    showProjectArea()
    if project == nil { showsStandaloneConsole = true }
    selectConsolePane(.terminal)
  }

  func selectConsolePane(_ pane: ConsolePane) {
    workbench.select(pane)
    if pane == .terminal {
      openTerminalSession()
    } else {
      releaseTerminalFocus()
    }
  }

  func activateTerminalPane() {
    guard isShowingProjectArea, workbench.root.visiblePanes.contains(.terminal),
      terminalSession?.hasKeyboardFocus == true
    else { return }
    workbench.select(.terminal)
  }

  func activateTerminalSearch() {
    workbench.select(.terminal)
  }

  func moveConsolePane(_ pane: ConsolePane, to destination: WorkbenchLayout.Destination) {
    if workbench.move(pane, to: destination) {
      selectConsolePane(pane)
    }
  }

  func resizeConsoleSplit(_ id: UUID, fraction: Double) {
    workbench.resize(id, fraction: fraction)
  }

  func toggleSplitConsole() {
    workbench.toggleSplit()
    if activePane == .terminal {
      terminals.requestFocus()
    } else {
      releaseTerminalFocus()
    }
  }

  func mergeConsolePanes() {
    workbench.merge()
    if activePane == .terminal { terminals.requestFocus() }
  }

  func startTerminalSession() {
    terminalSession?.stop()
    workbench.select(.terminal)
    openTerminalSession(restart: true)
  }

  func stopTerminalsForQuit() -> Bool {
    terminals.stopAll()
  }

  private func openTerminalSession(restart: Bool = false) {
    terminals.open(for: project, directory: terminalDirectory, restart: restart)
  }

  private func releaseTerminalFocus() {
    terminals.releaseFocus(for: project)
  }

  private func revealConsoleOutput(_ pane: ConsolePane) {
    if terminalSession?.hasKeyboardFocus == true {
      if workbench.group(containing: pane)?.selected != .terminal {
        workbench.select(pane, activate: false)
      }
    } else {
      workbench.select(pane)
    }
  }

  func showProjectArea() {
    sidebarSelection = project.map { .project($0.path) }
  }

  func selectSidebarItem(_ item: SidebarItem) {
    guard sidebarSelection != item else { return }
    switch item {
    case .project(let path):
      guard let folder = projectFolders.first(where: { $0.path == path }) else { return }
      open(folder.url)
    case .devices:
      sidebarSelection = item
      refreshDevices()
    case .tools:
      sidebarSelection = item
    }
  }

  // MARK: - Build, Flash & Install Tasks

  func start(_ action: Action) {
    guard canStartAction else { return }
    let isTool = action.isToolAction
    switch action {
    case .installCube, .installBundle, .prepareAllTools:
      guard !loadingCube else { return }
    case .run, .flash:
      if configuration.flash == .uart, let issue = flashSerialOccupancyIssue {
        reportError(issue)
        return
      }
    default:
      break
    }
    let reading = chipTask
    reading?.cancel()
    if isTool {
      output.flushToolLog()
      output.toolLogInbox = ConsoleInbox()
    } else {
      output.flushLog()
      output.logInbox = ConsoleInbox()
    }
    operationID = UUID()
    let token = operationID
    running = true
    statusState = .preparing
    errorMessage = nil
    switch action {
    case .installCube:
      toolActivity = .installingCube
    case .installBundle(let name):
      toolActivity = .installingBundle(name)
    case .prepareAllTools:
      let missing = Set(
        missingBuildBundleNames
          + (missingProgrammerBundles ? [CubeCLI.programmerBundleName] : []))
      let all = Set(CubeCLI.defaultBuildNames + [CubeCLI.programmerBundleName])
      toolActivity = .preparingAll(
        includesCube: cubeVersion == nil, bundles: missing.isEmpty ? all : missing)
    case .inspect, .build, .run, .flash:
      showProjectArea()
      revealConsoleOutput(.buildLog)
    }
    let startedAt = ContinuousClock.now
    operation = Task { [weak self] in
      guard let self else { return }
      defer {
        if isTool {
          output.flushToolLog()
          output.toolLogInbox = ConsoleInbox()
        } else {
          output.flushLog()
          output.logInbox = ConsoleInbox()
        }
        running = false
        writing = false
        toolActivity = nil
        activeFlashConnection = nil
        lastBuildDuration = startedAt.duration(to: .now)
        operation = nil
        scheduleChipRead()
      }
      do {
        await reading?.value
        try Task.checkCancellation()
        try await perform(action, token: token)
      } catch is CancellationError {
        statusState = .cancelled
      } catch {
        statusState = .failed
        let errorLine =
          "\n" + l10n.tr(.init("log.errorPrefix", defaultValue: "[Error]")) + " "
          + error.localizedDescription + "\n"
        if isTool {
          output.flushToolLog()
          output.appendToolLog(errorLine)
          reportError(error.localizedDescription, logDestination: .tools)
        } else {
          output.flushLog()
          output.appendLog(errorLine)
          reportError(error.localizedDescription, logDestination: .build)
        }
      }
    }
  }

  func cancel() {
    guard !writing else { return }
    operation?.cancel()
  }

  func requestQuit() -> Bool {
    if !writing {
      chipTask?.cancel()
      return true
    }
    reportError(
      l10n.tr(
        .init(
          "error.cannotQuitWhileWriting",
          defaultValue:
            "Flashing or verifying firmware. You can quit Tekmor after the task completes.")))
    return false
  }

  // MARK: - Devices & Serial

  func refreshDevices() {
    let updated = DeviceDiscovery.serial()
    let adapters = DeviceDiscovery.probes()
    if updated != devices { devices = updated }
    if adapters != probes { probes = adapters }
    if devices.count == 1 {
      if serialPath == nil { serialPath = devices[0].id }
      if flashSerialPath == nil { flashSerialPath = devices[0].id }
    }
    let connected = Set(devices.map(\.registryID) + probes.map(\.id))
    chipReadings.retainConnections(connected)
    chipHintKeys = chipHintKeys.filter { connected.contains($0.key) }
    if let activeChipConnection, !connected.contains(activeChipConnection.id) { chipTask?.cancel() }
    if let selectedProbeID, !connected.contains(selectedProbeID) { self.selectedProbeID = nil }
    scheduleChipRead()
  }

  func selectProbe(_ probe: STLinkProbe) {
    guard canStartAction, probes.contains(probe) else { return }
    selectedProbeID = probe.id
    scheduleChipRead()
  }

  func canIdentify(_ probe: STLinkProbe) -> Bool {
    probes.count == 1
      || (probe.serialNumber.map { serial in
        probes.filter { $0.serialNumber == serial }.count == 1
      } ?? false)
  }

  func canReadChip(_ connection: ChipConnection) -> Bool {
    guard canStartAction, chipTask == nil else { return false }
    if case .uart(let device) = connection {
      return serial?.device.isSamePort(as: device) != true
        && !closingSerialDevices.values.contains(where: { $0.isSamePort(as: device) })
    }
    return true
  }

  func readChip(_ connection: ChipConnection) {
    guard canReadChip(connection) else { return }
    if case .swd(let probe) = connection, !canIdentify(probe) {
      let message = LocalizedStringResource(
        "chip.ambiguousProbe",
        defaultValue: "Cannot distinguish probes. Keep only the target ST-LINK connected.")
      chipHintKeys[connection.id] = message
      chipReadings[connection.id] = .failed(l10n.tr(message))
      return
    }
    guard programmerAvailable, cubeCLI != nil else {
      let message = LocalizedStringResource(
        "chip.prepareProgrammer", defaultValue: "Prepare the programming tools in Tools.")
      chipHintKeys[connection.id] = message
      chipReadings[connection.id] = .needsTool(l10n.tr(message))
      return
    }
    chipHintKeys.removeValue(forKey: connection.id)
    chipReadings[connection.id] = .reading
    activeChipConnection = connection
    chipTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.chipTask = nil
        self.activeChipConnection = nil
      }
      do {
        guard let cli = self.cubeCLI else {
          throw TekmorError(
            self.l10n.tr(.init("cube.installInTools", defaultValue: "Install CubeCLI in Tools.")))
        }
        let info = try await CubeProgrammer(cli: cli).read(
          connection, log: self.logger(token: self.operationID))
        try Task.checkCancellation()
        if connection.present() {
          self.chipHintKeys.removeValue(forKey: connection.id)
          self.chipReadings[connection.id] = .ready(info)
        }
      } catch is CancellationError {
        if self.chipReadings[connection.id] == .reading { self.chipReadings[connection.id] = nil }
      } catch {
        if connection.present() {
          self.chipHintKeys.removeValue(forKey: connection.id)
          self.chipReadings[connection.id] = .failed(error.localizedDescription)
        }
      }
      if !connection.present() {
        self.chipHintKeys.removeValue(forKey: connection.id)
        self.chipReadings[connection.id] = nil
      }
    }
  }

  private func scheduleChipRead() {
    guard canStartAction, chipTask == nil else { return }
    let uart = selectedFlashSerial
    let connections =
      probes.filter(canIdentify).map(ChipConnection.swd) + (uart.map { [.uart($0)] } ?? [])
    for connection in connections where canReadChip(connection) {
      if chipReadings.shouldRead(connection.id, toolsReady: programmerAvailable) {
        readChip(connection)
        if chipTask != nil { return }
      }
    }
  }

  func setSerialPath(_ path: String?) {
    guard canSelectMonitorPort else { return }
    if serialPath != path {
      dropSerial()
      serialPath = path
    }
  }

  func setFlashSerialPath(_ path: String?) {
    guard canStartAction else { return }
    flashSerialPath = path
    scheduleChipRead()
  }

  func selectDeviceAndMonitor(_ device: SerialDevice) {
    setSerialPath(device.id)
    if !serialConnected { toggleSerial() }
  }

  func toggleSerial() {
    guard canToggleSerial else { return }
    if serialConnected {
      dropSerial()
      return
    }
    if let reading = chipTask {
      reading.cancel()
      let selected = selectedSerial
      Task {
        await reading.value
        if canToggleSerial, !serialConnected, selectedSerial == selected { toggleSerial() }
      }
      return
    }
    do {
      guard let device = selectedSerial else {
        throw TekmorError(
          l10n.tr(
            .init("error.selectMonitorSerial", defaultValue: "Select a serial port to listen on.")))
      }
      try connectSerial(device)
    } catch {
      reportError(error.localizedDescription)
    }
  }

  func recallSerialCommand(previous: Bool) {
    serialTransmitByProject[project, default: SerialTransmit()].recall(previous: previous)
  }

  func sendSerialCommand() {
    guard canSendSerial, let serial else { return }
    let command = serialCommand
    let bytes: Data
    do {
      bytes = try command.payload()
    } catch {
      reportError(error.localizedDescription)
      return
    }
    let key = project
    let identity = serialID
    sendingSerial = true
    Task { [weak self] in
      guard let self else { return }
      defer { if self.serialID == identity { self.sendingSerial = false } }
      do {
        try await serial.send(bytes)
        self.serialTransmitByProject[key, default: SerialTransmit()].record(command)
      } catch {
        if self.serialID == identity { self.reportError(error.localizedDescription) }
      }
    }
  }

  // MARK: - Tools, Storage & Trust Settings

  func chooseToolDirectory() {
    guard canStartAction, !loadingCube else { return }
    chooseDirectory(
      title: l10n.tr(
        .init("panel.chooseToolDirectory", defaultValue: "Choose tools installation directory")),
      canCreate: true
    ) { directory in
      self.toolDirectory = directory
      self.preferences.set(directory.path, forKey: "toolDirectory")
      self.buildGenerator = nil
      self.buildToolsDescription = nil
      await self.refreshCube()
    }
  }

  func resetToolDirectory() {
    guard canStartAction, !loadingCube else { return }
    toolDirectory = CubeInstallation.defaultDirectory
    preferences.removeObject(forKey: "toolDirectory")
    buildGenerator = nil
    buildToolsDescription = nil
    Task { await refreshCube() }
  }

  private func refreshCube() async {
    guard !loadingCube else { return }
    let token = UUID()
    let directory = toolDirectory
    cubeRefreshID = token
    loadingCube = true
    programmerAvailable = false
    buildToolsIssue = l10n.tr(.init("tools.checking", defaultValue: "Checking tools…"))
    programmerIssue = buildToolsIssue
    defer {
      if cubeRefreshID == token {
        loadingCube = false
        hasCheckedCube = true
      }
    }
    if let cli = CubeInstallation(directory: directory).cli {
      var detectedVersion: String?
      do {
        let version = try await cli.version()
        guard cubeRefreshID == token, directory == toolDirectory else { return }
        detectedVersion = version
        cubeVersion = version
        cubeMessageState = nil
        let tools = try await cli.toolStatus()
        guard cubeRefreshID == token, directory == toolDirectory else { return }
        applyToolStatus(tools)
        scheduleChipRead()
        return
      } catch {
        guard cubeRefreshID == token, directory == toolDirectory else { return }
        cubeVersion = detectedVersion
        cubeMessageState = detectedVersion == nil ? .custom(error.localizedDescription) : nil
        buildBundleRows = CubeCLI.defaultBuildBundles
        programmerBundleRows = CubeCLI.defaultProgrammerBundles
        buildToolsIssue = error.localizedDescription
        programmerIssue = error.localizedDescription
      }
    } else {
      cubeVersion = nil
      cubeMessageState = .notFound
      buildBundleRows = CubeCLI.defaultBuildBundles
      programmerBundleRows = CubeCLI.defaultProgrammerBundles
      buildToolsIssue = l10n.tr(
        .init("cube.installInTools", defaultValue: "Install CubeCLI in Tools."))
      programmerIssue = buildToolsIssue
    }
    scheduleChipRead()
  }

  func refreshTools() async {
    guard canStartAction, !loadingCube else { return }
    statusState = .verifyingTools
    await refreshCube()
    if !running {
      statusState =
        missingRequiredToolCount == 0
        ? .toolsReady : .unavailableTools(missingRequiredToolCount)
    }
  }

  private func applyToolStatus(_ tools: CubeToolStatus) {
    buildBundleRows = tools.buildBundles
    programmerBundleRows = tools.programmerBundles
    buildToolsIssue = tools.buildIssue
    programmerIssue = tools.programmerIssue
    programmerAvailable = tools.programmerIssue == nil
  }

  func revealInFinder(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
  }

  func resolveSourceLocation(_ location: BuildDiagnosticLocation) -> URL? {
    location.resolveURL(relativeTo: project)
  }

  func openSourceLocation(_ location: BuildDiagnosticLocation) {
    guard let fileURL = resolveSourceLocation(location) else { return }

    if let scheme = externalEditor.urlScheme {
      var components = URLComponents()
      components.scheme = scheme
      components.host = "file"
      let suffix = location.column.map { ":\(location.line):\($0)" } ?? ":\(location.line)"
      components.path = fileURL.path + suffix
      if let editorURL = components.url,
        NSWorkspace.shared.urlForApplication(toOpen: editorURL) != nil,
        NSWorkspace.shared.open(editorURL)
      {
        return
      }
    } else if externalEditor == .xcode {
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/xed")
      process.arguments = ["--line", "\(location.line)", fileURL.path]
      process.terminationHandler = { process in
        guard process.terminationStatus != 0 else { return }
        Task { @MainActor in Self.openSourceFileWithDefaultEditor(fileURL) }
      }
      if (try? process.run()) != nil {
        return
      }
    }

    Self.openSourceFileWithDefaultEditor(fileURL)
  }

  private static func openSourceFileWithDefaultEditor(_ fileURL: URL) {
    let resolved = fileURL.resolvingSymlinksInPath()
    let values = try? resolved.resourceValues(forKeys: [.contentTypeKey, .isExecutableKey])
    let type = values?.contentType
    let workspace = NSWorkspace.shared
    // Keep executable scripts and other launchable files in a text editor.
    if type?.conforms(to: .plainText) == true,
      type?.conforms(to: .shellScript) == false,
      values?.isExecutable == false
    {
      workspace.open(resolved)
    } else if let editor = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
      workspace.open(
        [resolved], withApplicationAt: editor, configuration: .init(), completionHandler: nil)
    }
  }

  func revealSourceLocation(_ location: BuildDiagnosticLocation) {
    guard let fileURL = resolveSourceLocation(location) else { return }
    revealInFinder(fileURL)
  }

  func revealCubeDirectory() {
    revealInFinder(toolDirectory)
  }

  func revealBuildCache() {
    revealInFinder(CMakeBuild.defaultCache)
  }

  func measureBuildCacheBytes() async -> Int64 {
    let cacheURL = CMakeBuild.defaultCache
    return await Task.detached(priority: .utility) {
      Self.directorySize(at: cacheURL)
    }.value
  }

  private nonisolated static func directorySize(at url: URL) -> Int64 {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path),
      let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
        options: []
      )
    else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard
        let values = try? fileURL.resourceValues(forKeys: [
          .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
        ]),
        values.isRegularFile == true
      else { continue }
      total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }
    return total
  }

  func clearBuildCache() {
    guard canStartAction else { return }
    let cache = CMakeBuild.defaultCache
    do {
      if FileManager.default.fileExists(atPath: cache.path) {
        try FileManager.default.removeItem(at: cache)
      }
      lastArtifact = nil
      clearArtifactDetails()
      lastFirmwareUsage = nil
      flashNotice(l10n.tr(.init("notice.clearedBuildCache", defaultValue: "Build cache cleared")))
    } catch {
      reportError(error.localizedDescription)
    }
  }

  // MARK: - Finder, Copy & Export

  func revealProject(_ customURL: URL? = nil) {
    if let target = customURL ?? project {
      NSWorkspace.shared.activateFileViewerSelecting([target])
    }
  }

  private func clearArtifactDetails() {
    artifactReadID = UUID()
    firmwareByteCount = nil
    firmwareFlashBytes = nil
    firmwareRAMBytes = nil
    firmwareSections = []
    firmwareRanges = []
  }

  private func refreshArtifactDetails(_ file: URL, address: UInt64?) {
    clearArtifactDetails()
    let token = artifactReadID
    Task { [weak self] in
      let image = try? await Task.detached(priority: .userInitiated) {
        try FirmwareImage(file: file, binaryAddress: address)
      }.value
      guard let self, self.artifactReadID == token, self.lastArtifact == file else { return }
      self.firmwareByteCount = image?.byteCount
      self.firmwareFlashBytes = image?.internalFlashBytes
      self.firmwareRAMBytes = image?.staticRAMBytes
      self.firmwareSections = image?.sections ?? []
      self.firmwareRanges = image?.ranges ?? []
    }
  }

  func revealArtifact() {
    if let lastArtifact { NSWorkspace.shared.activateFileViewerSelecting([lastArtifact]) }
  }

  func clearActiveConsole() {
    guard canClearActiveConsole else { return }
    switch activePane {
    case .buildLog: output.clearLog()
    case .serial: output.clearSerial()
    case .terminal: break
    }
  }

  func copyText(_ text: String, label: String? = nil) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    flashNotice(
      label ?? l10n.tr(.init("notice.copiedClipboard", defaultValue: "Copied to clipboard")))
  }

  func exportConsole(isSerial: Bool) {
    if isSerial {
      flushPendingSerial()
    } else {
      output.flushLog()
    }
    let dialog = NSSavePanel()
    dialog.nameFieldStringValue = isSerial ? "tekmor-serial.log" : "tekmor-build.log"
    let content = isSerial ? output.transcript : output.log
    chooseFile(using: dialog) { url in
      do {
        try content.write(to: url, atomically: true, encoding: .utf8)
        self.flashNotice(
          self.l10n.tr(
            .init("notice.exportedFile", defaultValue: "Exported \(url.lastPathComponent)")))
      } catch {
        self.reportError(error.localizedDescription)
      }
    }
  }

  // MARK: - Internal Execution

  private func perform(_ action: Action, token: UUID)
    async throws
  {
    switch action {
    case .installCube, .installBundle, .prepareAllTools:
      do {
        switch action {
        case .installCube:
          statusState = .installingTool("STM32CubeCLI")
          try await CubeInstallation(directory: toolDirectory).install(
            log: toolLogger(token: token))
        case .installBundle(let name):
          statusState = .installingTool(name)
          try await requireCube().installBundle(name, log: toolLogger(token: token))
        case .prepareAllTools:
          if cubeCLI == nil {
            statusState = .installingTool("STM32CubeCLI")
            try await CubeInstallation(directory: toolDirectory).install(
              log: toolLogger(token: token))
            await refreshCube()
            try Task.checkCancellation()
          }
          statusState = .preparing
          try await requireCube().prepareAllTools(log: toolLogger(token: token))
        default: break
        }
        await refreshCube()
        switch action {
        case .installCube:
          statusState = .custom(
            l10n.tr(.init("status.cubeInstalled", defaultValue: "CubeCLI installed")))
        case .installBundle(let name):
          statusState = .toolInstalled(name)
        case .prepareAllTools:
          statusState = .toolsReady
        default: break
        }
      } catch {
        await refreshCube()
        throw error
      }
    case .flash(let file, let address, let standalone):
      try await performWorkflow(
        .flash(file, address: address, standalone: standalone), token: token)
    case .inspect:
      try await performWorkflow(.inspect, token: token)
    case .build:
      try await performWorkflow(.build, token: token)
    case .run:
      try await performWorkflow(.run, token: token)
    }
  }

  private func performWorkflow(
    _ action: STM32Workflow.Action, token: UUID
  ) async throws {
    let context = STM32Workflow.Context(
      project: project, configuration: configuration, cube: cubeCLI)
    let outcome = try await workflow.execute(
      action, context: context, interaction: self, log: logger(token: token))
    switch outcome {
    case .inspected(let count):
      statusState = .loadedTargets(count)
    case .awaitingTarget:
      statusState = .selectTarget
      return
    case .built(let artifact):
      statusState = .buildComplete(artifact.lastPathComponent)
    case .flashed:
      if case .uart = activeFlashConnection {
        statusState = .verifiedNeedsReset
      } else {
        statusState = .verifiedAndReset
      }
    }
  }

  private func connectSerial(_ device: SerialDevice) throws {
    let identity = UUID()
    serialID = identity
    let inbox = SerialInbox()
    output.serialInbox = inbox
    serial = try SerialConnection(device: device, settings: configuration.serial) {
      [weak self] bytes in
      guard inbox.append(bytes) else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(24))
        guard let self, self.output.serialInbox === inbox else { return }
        self.flushPendingSerial(scheduled: true)
      }
    } disconnected: { [weak self] message in
      Task { @MainActor in
        guard let self, self.serialID == identity else { return }
        self.dropSerial()
        self.output.appendSerialNotice(
          self.l10n.tr(
            .init(
              "log.serialDisconnectedHint",
              defaultValue: "\(message) Reconnect it to resume listening.")))
        self.refreshDevices()
      }
    }
    serialConnected = true
  }

  private func dropSerial() {
    flushPendingSerial()
    output.finishSerialStream()
    output.serialInbox = SerialInbox()
    let connection = serial
    serial = nil
    serialID = UUID()
    serialConnected = false
    sendingSerial = false
    guard let connection else { return }
    let releaseID = UUID()
    closingSerialDevices[releaseID] = connection.device
    Task { [weak self] in
      await connection.close()
      self?.closingSerialDevices.removeValue(forKey: releaseID)
    }
  }

  private func requireSerial() throws -> SerialDevice {
    guard let device = selectedFlashSerial else {
      throw TekmorError(
        l10n.tr(
          .init("error.selectUARTSerial", defaultValue: "Select a serial port for UART flashing.")))
    }
    if let issue = flashSerialOccupancyIssue { throw TekmorError(issue) }
    return device
  }

  private func requireCube() throws -> CubeCLI {
    guard let cli = cubeCLI else {
      throw TekmorError(
        l10n.tr(.init("cube.installInTools", defaultValue: "Install CubeCLI in Tools.")))
    }
    return cli
  }

  private func reportError(_ message: String, logDestination: LogDestination? = nil) {
    errorLogDestination = logDestination
    errorMessage = message
  }

  private func logger(token: UUID) -> ToolLog {
    let inbox = output.logInbox
    return { [weak self] text in
      guard inbox.append(text) else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(33))
        guard let self, self.operationID == token, self.output.logInbox === inbox else { return }
        self.output.flushLog(scheduled: true)
      }
    }
  }

  private func toolLogger(token: UUID) -> ToolLog {
    let inbox = output.toolLogInbox
    return { [weak self] text in
      guard inbox.append(text) else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(33))
        guard let self, self.operationID == token, self.output.toolLogInbox === inbox else {
          return
        }
        self.output.flushToolLog(scheduled: true)
      }
    }
  }

  private func proposedPresets(in project: URL) -> [String] {
    struct File: Decodable {
      struct Entry: Decodable {
        let name: String
        let hidden: Bool?
      }
      let configurePresets: [Entry]?
    }
    let names = ["CMakePresets.json", "CMakeUserPresets.json"].flatMap { filename -> [String] in
      guard let data = try? Data(contentsOf: project.appendingPathComponent(filename)),
        let parsed = try? JSONDecoder().decode(File.self, from: data)
      else { return [] }
      return (parsed.configurePresets ?? []).filter { $0.hidden != true }.map(\.name)
    }
    return CMakeBuild.sortedPresets(names)
  }

  private func flashNotice(_ message: String) {
    noticeTask?.cancel()
    copiedNotice = message
    noticeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.0))
      guard !Task.isCancelled else { return }
      self?.copiedNotice = nil
    }
  }

  // MARK: - Console Output

  private func flushPendingSerial(scheduled: Bool = false) {
    _ = output.flushSerial(
      scheduled: scheduled,
      timestamp: Date.now.formatted(.dateTime.hour().minute().second().locale(locale)),
      showTimestamp: showTimestamps
    )
  }

  // MARK: - Formatting Helpers

  func formatBytes(_ bytes: Int) -> String {
    formatBytes64(Int64(bytes))
  }

  func formatBytes64(_ bytes: Int64) -> String {
    if bytes >= 1024 * 1024 {
      let value = Double(bytes) / (1024.0 * 1024.0)
      return "\(value.formatted(.number.precision(.fractionLength(1)).locale(locale))) MiB"
    }
    if bytes >= 1024 {
      let value = Double(bytes) / 1024.0
      return "\(value.formatted(.number.precision(.fractionLength(1)).locale(locale))) KiB"
    }
    return "\(bytes.formatted(.number.locale(locale))) B"
  }

  // MARK: - File Panels

  func chooseDirectory(
    title: String, canCreate: Bool = false, onSelection: @escaping @MainActor (URL) async -> Void
  ) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = canCreate
    panel.message = title
    chooseFile(using: panel, onSelection: onSelection)
  }

  private func chooseFile(
    using panel: NSSavePanel, onSelection: @escaping @MainActor (URL) async -> Void
  ) {
    guard !choosingFile else { return }
    choosingFile = true
    Task {
      let response: NSApplication.ModalResponse
      if let window = NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil {
        response = await panel.beginSheetModal(for: window)
      } else {
        // A file panel opened from an existing SwiftUI sheet must not queue behind it.
        response = await panel.begin()
      }
      panel.orderOut(nil)
      choosingFile = false
      if response == .OK, let url = panel.url { await onSelection(url) }
    }
  }
}

extension Workspace: STM32Workflow.Interaction {
  func selectFlashConnection(for method: FlashMethod) throws -> (
    connection: ChipConnection, probeCount: Int
  ) {
    refreshDevices()
    if method == .uart {
      let connection = ChipConnection.uart(try requireSerial())
      activeFlashConnection = connection
      return (connection, probes.count)
    }
    if let issue = probeIssue { throw TekmorError(issue) }
    guard let probe = flashProbe else {
      throw TekmorError(
        l10n.tr(
          .init("error.selectFlashSTLink", defaultValue: "Select an ST-LINK probe for flashing.")))
    }
    activeFlashConnection = .swd(probe)
    return (.swd(probe), probes.count)
  }

  func checkTools(build: Bool, programmer: Bool) async throws {
    let tools = try await requireCube().toolStatus()
    try Task.checkCancellation()
    applyToolStatus(tools)
    if build, let issue = tools.buildIssue { throw TekmorError(issue) }
    if programmer, let issue = tools.programmerIssue { throw TekmorError(issue) }
  }

  func receive(_ event: STM32Workflow.Event) {
    switch event {
    case .clearArtifact:
      lastArtifact = nil
      clearArtifactDetails()
      lastFirmwareUsage = nil
    case .toolsReady:
      break
    case .stage(let stage):
      updateStage(stage)
    case .configuredBuild(let generator, let toolsDescription):
      buildGenerator = generator
      buildToolsDescription = toolsDescription
    case .presets(let names, let selected):
      presets = names
      configuration.cmake.configurePreset = selected
    case .targets(let names, let selected):
      targets = names
      configuration.cmake.target = selected
    case .builtArtifact(let artifact, let usage):
      lastArtifact = artifact
      refreshArtifactDetails(artifact, address: nil)
      standaloneImage = nil
      lastFirmwareUsage = usage
    case .selectedImage(let file, let address, let standalone):
      lastArtifact = file
      refreshArtifactDetails(file, address: address)
      standaloneImage = standalone ? (file, address) : nil
      lastFirmwareUsage = nil
    case .chipRead(let connection, let info):
      chipHintKeys.removeValue(forKey: connection.id)
      chipReadings[connection.id] = .ready(info)
    case .firmwareUsage(let usage):
      lastFirmwareUsage = usage
    case .writeEnded:
      writing = false
    case .flashProgress:
      break
    }
  }

  private func updateStage(_ stage: STM32Workflow.Stage) {
    switch stage {
    case .listingPresets, .configuring:
      statusState = .configuringCMake
    case .building(let target):
      statusState = .building(target)
    case .checkingFirmware:
      statusState = .checkingFirmware
    case .readingChip:
      statusState = .readingChip
    case .writing:
      writing = true
      statusState = .writingAndVerifying
    case .resetting:
      statusState = .verifiedResetting
    }
  }
}
