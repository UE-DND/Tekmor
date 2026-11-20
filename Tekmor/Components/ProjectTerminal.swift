import AppKit
import Observation
import SwiftTerm
import SwiftUI

@MainActor @Observable
final class ProjectTerminal: LocalProcessTerminalViewDelegate {
  enum State: Equatable {
    case idle, starting, running, stopped
    case exited(Int32?)
    case failed(String)

    var isOpen: Bool { self == .starting || self == .running }
  }

  // Apple's Clear Dark profile, converted to sRGB in ANSI index order.
  private static let ansiColors: [SwiftTerm.Color] = [
    0x35424C, 0xB45648, 0x6CAA71, 0xC4AC62,
    0x6D96B4, 0xBD7BCD, 0x7CCBCD, 0xDEE5EB,
    0x465C6D, 0xDF6C5A, 0x79BE7E, 0xE5C872,
    0x67B5ED, 0xD389E5, 0x84DDE0, 0xE5EFF5,
  ].map { hex in
    SwiftTerm.Color(
      red8: UInt16((hex >> 16) & 0xFF),
      green8: UInt16((hex >> 8) & 0xFF),
      blue8: UInt16(hex & 0xFF)
    )
  }

  let directory: URL
  private(set) var state: State = .idle
  private(set) var terminalView: WorkbenchTerminalView?
  var showsSearch = false
  var searchQuery = "" {
    didSet {
      guard searchQuery != oldValue else { return }
      terminalView?.clearSearch()
      if !searchQuery.isEmpty { terminalView?.findNext(searchQuery) }
      refreshSearchResults()
    }
  }
  private(set) var searchMatchIndex = 0
  private(set) var searchMatchCount = 0

  init(directory: URL) {
    self.directory = directory
  }

  var hasKeyboardFocus: Bool {
    guard let terminalView else { return false }
    return terminalView.window?.firstResponder === terminalView
  }

  func prepare() {
    guard !state.isOpen else { return }
    closeSearch()
    let view = WorkbenchTerminalView(
      frame: .zero, options: TerminalOptions(ansi256PaletteStrategy: .xterm))
    view.installColors(Self.ansiColors)
    view.useBrightColors = false
    view.collapseBrightColorsToBase = false
    view.updateAppearanceColors()
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.textArea)
    view.processDelegate = self
    view.notifyUpdateChanges = true
    view.onOutputChanged = { [weak self] in self?.refreshSearchResults() }
    terminalView = view
    state = .starting
  }

  func startIfReady(_ view: WorkbenchTerminalView, using l10n: AppL10n) {
    guard terminalView === view, state == .starting else { return }

    let path = directory.path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue, Darwin.access(path, X_OK) == 0
    else {
      terminalView = nil
      state = .failed(
        l10n.tr(
          .init("terminal.directoryUnavailable", defaultValue: "Cannot open terminal in \(path).")))
      return
    }

    var environment = ProcessInfo.processInfo.environment
    let configuredShell = getpwuid(getuid()).flatMap { entry in
      entry.pointee.pw_shell.map { String(cString: $0) }
    }
    let shell =
      [configuredShell, environment["SHELL"]].compactMap { $0 }.first {
        $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
      } ?? "/bin/zsh"
    environment["SHELL"] = shell
    environment["TERM"] = "xterm-256color"
    environment["COLORTERM"] = "truecolor"
    environment["TERM_PROGRAM"] = "Tekmor"
    environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
    environment["PWD"] = path
    environment.removeValue(forKey: "OLDPWD")

    state = .running
    view.startProcess(
      executable: shell,
      environment: environment.map { "\($0.key)=\($0.value)" },
      execName: "-" + URL(filePath: shell).lastPathComponent,
      currentDirectory: path
    )
  }

  func stop(escalationDelay: TimeInterval = 0.5) {
    closeSearch()
    if let view = terminalView {
      view.onOutputChanged = nil
      view.processDelegate = nil
      view.process.killEscalationDelay = escalationDelay
      view.terminate()
      view.removeFromSuperview()
      terminalView = nil
    }
    state = .stopped
  }

  func findMatch(backwards: Bool = false) {
    guard !searchQuery.isEmpty, let terminalView else { return }
    if backwards {
      terminalView.findPrevious(searchQuery)
    } else {
      terminalView.findNext(searchQuery)
    }
    refreshSearchResults()
  }

  func closeSearch() {
    showsSearch = false
    searchQuery = ""
    terminalView?.clearSearch()
    searchMatchIndex = 0
    searchMatchCount = 0
  }

  private func refreshSearchResults() {
    guard !searchQuery.isEmpty, let terminalView else {
      searchMatchIndex = 0
      searchMatchCount = 0
      return
    }
    var summary = terminalView.searchMatchSummary(searchQuery, limit: .max)
    if summary.total > 0 && !terminalView.selectionActive {
      terminalView.findNext(searchQuery, scrollToResult: false)
      summary = terminalView.searchMatchSummary(searchQuery, limit: .max)
    }
    searchMatchIndex = summary.index
    searchMatchCount = summary.total
  }

  func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  func processTerminated(source: TerminalView, exitCode: Int32?) {
    guard source === terminalView else { return }
    state = .exited(exitCode)
  }

  func processFailedToStart(source: TerminalView, error: LocalProcessError) {
    guard source === terminalView else { return }
    state = .failed(String(describing: error))
  }
}

final class WorkbenchTerminalView: LocalProcessTerminalView {
  var onFocus: (() -> Void)?
  var onOutputChanged: (() -> Void)?
  var lastFocusRequest: Int?
  private var outputUpdateScheduled = false

  override var hasFocus: Bool {
    get { super.hasFocus }
    set {
      super.hasFocus = newValue
      if newValue { Task { @MainActor [weak self] in self?.onFocus?() } }
    }
  }

  override func accessibilityValue() -> Any? {
    visibleRowsText(0..<terminalDimensions.rows).joined(separator: "\n")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearanceColors()
  }

  override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
    super.rangeChanged(source: source, startY: startY, endY: endY)
    guard onOutputChanged != nil, !outputUpdateScheduled else { return }
    outputUpdateScheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      outputUpdateScheduled = false
      onOutputChanged?()
    }
  }

  func updateAppearanceColors() {
    guard terminalInputStateSnapshot() != nil else { return }
    // Resolve dynamic colors before SwiftTerm converts them to RGB and CGColor.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      nativeBackgroundColor =
        NSColor(TekmorColor.workspaceBackground).usingColorSpace(.sRGB) ?? .textBackgroundColor
      nativeForegroundColor =
        NSColor(TekmorColor.textInk).usingColorSpace(.sRGB) ?? .textColor
      selectedTextBackgroundColor =
        NSColor(TekmorColor.currentSearchMatch).usingColorSpace(.sRGB)
        ?? .selectedTextBackgroundColor
      selectedTextForegroundColor = nativeForegroundColor
    }
    updateColorScheme(
      effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
  }

  func outputSnapshot() -> String {
    String(decoding: getBufferAsData(), as: UTF8.self)
  }
}

struct ProjectTerminalHost: NSViewRepresentable {
  let session: ProjectTerminal
  let terminal: WorkbenchTerminalView
  let fontSize: Double
  let focusRequest: Int?
  var onFocus: () -> Void
  @Environment(\.l10n) private var l10n

  func makeNSView(context: Context) -> Container { Container(frame: .zero) }

  func updateNSView(_ container: Container, context: Context) {
    container.attach(terminal)
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    if terminal.font != font { terminal.font = font }
    terminal.onFocus = onFocus
    terminal.setAccessibilityLabel(
      l10n.tr(.init("terminal.output", defaultValue: "Terminal Output")))

    let request = focusRequest
    let l10n = l10n
    container.onLayout = { [weak container, weak terminal, weak session] in
      guard let container, let terminal, let session,
        terminal.superview === container, let window = container.window,
        terminal.bounds.width > 0, terminal.bounds.height > 0
      else { return }
      session.startIfReady(terminal, using: l10n)
      if let request, !session.showsSearch, terminal.lastFocusRequest != request,
        session.terminalView === terminal,
        window.makeFirstResponder(terminal)
      {
        terminal.lastFocusRequest = request
      }
    }
    container.scheduleUpdate()
  }

  static func dismantleNSView(_ container: Container, coordinator: ()) {
    container.onLayout = nil
    container.attach(nil)
  }

  final class Container: NSView {
    var onLayout: (() -> Void)?
    private weak var terminal: WorkbenchTerminalView?
    private var updateScheduled = false

    func attach(_ view: WorkbenchTerminalView?) {
      if let view, terminal === view, view.superview === self { return }
      if terminal?.superview === self { terminal?.removeFromSuperview() }
      terminal = view
      guard let view else { return }
      view.removeFromSuperview()
      view.frame = bounds
      view.autoresizingMask = [.width, .height]
      addSubview(view)
    }

    override func layout() {
      super.layout()
      scheduleUpdate()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      scheduleUpdate()
    }

    func scheduleUpdate() {
      guard !updateScheduled else { return }
      updateScheduled = true
      Task { @MainActor [weak self] in
        guard let self else { return }
        updateScheduled = false
        onLayout?()
      }
    }
  }
}

struct TerminalOutputTextView: NSViewRepresentable {
  let text: String
  let title: String
  let fontSize: Double

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    if let textView = scrollView.documentView as? NSTextView {
      textView.isEditable = false
      textView.isSelectable = true
      textView.usesFindBar = true
      textView.textContainerInset = NSSize(width: 8, height: 8)
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    textView.setAccessibilityLabel(title)
    textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    if textView.string != text { textView.string = text }
  }
}
