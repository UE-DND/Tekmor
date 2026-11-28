import AppKit
import SwiftUI
import TekmorWorkbench

/// Project controls and the dockable workbench.
struct ProjectDetailView: View {
  private static let minInspectorWidth: CGFloat = 252
  private static let idealInspectorWidth: CGFloat = 276
  private static let maxInspectorWidth: CGFloat = 320
  private static let minWorkbenchWidth: CGFloat = 240

  @Bindable var workspace: Workspace
  @State private var inspectorWidth: CGFloat = idealInspectorWidth
  @State private var inspectorDragStartWidth: CGFloat?
  @Environment(\.l10n) private var l10n
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var showsInspector: Bool {
    workspace.canArrangeConsole && workspace.showInspector
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        QuickConfigBar(workspace: workspace) { contextBarTrailing }
        workbenchArea
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .environment(\.workbenchTextScale, CGFloat(workspace.workbenchTextScale))
    .background(TekmorColor.workspaceBackground)
  }

  private var workbenchArea: some View {
    GeometryReader { geometry in
      let resolvedInspectorWidth = clampedInspectorWidth(for: geometry.size.width)
      let visibleInspectorWidth = showsInspector ? resolvedInspectorWidth + 1 : 0
      let contentWidth = max(0, geometry.size.width - visibleInspectorWidth)

      ZStack(alignment: .leading) {
        HStack(spacing: 0) {
          Group {
            if workspace.hasConsoleContent {
              consoleContent
            } else {
              emptyState
            }
          }
          .frame(width: contentWidth, height: geometry.size.height)

          HStack(spacing: 0) {
            Rectangle()
              .fill(TekmorColor.separator)
              .frame(width: 1, height: geometry.size.height)
            ProjectInspectorView(workspace: workspace)
              .frame(width: resolvedInspectorWidth, height: geometry.size.height)
          }
          .frame(width: visibleInspectorWidth, height: geometry.size.height, alignment: .leading)
          .clipped()
          .disabled(!showsInspector)
          .allowsHitTesting(showsInspector)
          .accessibilityHidden(!showsInspector)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)

        if showsInspector {
          inspectorResizeHandle(
            availableWidth: geometry.size.width,
            height: geometry.size.height
          )
          .offset(x: max(0, contentWidth - 3))
        }
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: showsInspector)
    }
  }

  private func inspectorResizeHandle(availableWidth: CGFloat, height: CGFloat) -> some View {
    let upper = maxInspectorWidth(for: availableWidth)
    let lower = min(Self.minInspectorWidth, upper)

    return Color.clear
      .frame(width: 7, height: height)
      .contentShape(Rectangle())
      .pointerStyle(.columnResize)
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { value in
            let startWidth =
              inspectorDragStartWidth ?? clampedInspectorWidth(for: availableWidth)
            if inspectorDragStartWidth == nil {
              inspectorDragStartWidth = startWidth
            }
            let proposed = startWidth - value.translation.width
            inspectorWidth = min(max(proposed, lower), upper)
          }
          .onEnded { _ in
            inspectorDragStartWidth = nil
          }
      )
      .onTapGesture(count: 2) {
        inspectorWidth = Self.idealInspectorWidth
      }
      .accessibilityHidden(true)
  }

  private func maxInspectorWidth(for availableWidth: CGFloat) -> CGFloat {
    let workbenchWidth = max(Self.minWorkbenchWidth, workspace.workbench.root.minimumSize().width)
    return min(Self.maxInspectorWidth, max(0, availableWidth - workbenchWidth - 1))
  }

  private func clampedInspectorWidth(for availableWidth: CGFloat) -> CGFloat {
    let upper = maxInspectorWidth(for: availableWidth)
    let lower = min(Self.minInspectorWidth, upper)
    return min(max(inspectorWidth, lower), upper)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "folder")
        .font(.system(size: 28, weight: .ultraLight))
        .foregroundStyle(TekmorColor.textTertiary)

      VStack(spacing: 5) {
        Text(l10n.tr(.init("project.empty.title", defaultValue: "No Project Open")))
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(TekmorColor.textInk)
        Text(
          workspace.projectFolders.isEmpty
            ? l10n.tr(
              .init("project.empty.add", defaultValue: "Add a CMake project folder to get started.")
            )
            : l10n.tr(
              .init("project.empty.select", defaultValue: "Select a project from the sidebar."))
        )
        .font(.system(size: 12.5))
        .foregroundStyle(TekmorColor.textSecondary)
      }

      Button(action: workspace.chooseProject) {
        Label(
          l10n.tr(.init("action.addProjectEllipsis", defaultValue: "Add Project…")),
          systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .tint(TekmorColor.ctaBottom)
      .disabled(!workspace.canStartAction)

      HStack(spacing: 6) {
        Button(
          l10n.tr(.init("action.flashFirmwareEllipsis", defaultValue: "Flash Firmware…")),
          action: workspace.chooseFirmware
        )
        .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.primaryTonal, compact: true))
        .disabled(!workspace.canChooseFirmware)

        Text("·")
          .foregroundStyle(TekmorColor.textTertiary)

        Button(l10n.tr(.init("project.empty.serialOnly", defaultValue: "Open Serial Monitor Only")))
        {
          workspace.showSerialMonitor()
        }
        .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.primaryTonal, compact: true))

        Text("·")
          .foregroundStyle(TekmorColor.textTertiary)

        Button(
          l10n.tr(.init("terminal.open", defaultValue: "Open Terminal")),
          action: workspace.showTerminal
        )
        .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.primaryTonal, compact: true))
      }
      if let issue = workspace.programmerIssue {
        Button {
          workspace.selectSidebarItem(.tools)
        } label: {
          Label(
            l10n.tr(.init("action.openTools", defaultValue: "Open Tools")),
            systemImage: "shippingbox")
        }
        .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
        .help(issue)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var consoleContent: some View {
    WorkbenchView(
      workspace: workspace,
      node: workspace.workbench.root,
      showsHeaderSeparator: { pane in
        pane != .terminal || hasTerminalHeaderActions
      },
      headerAccessory: { pane in
        switch pane {
        case .buildLog, .serial:
          ProjectOutputHeaderAccessory(workspace: workspace, pane: pane)
        case .terminal:
          ProjectTerminalHeaderAccessory(workspace: workspace)
        }
      },
      content: { pane in
        switch pane {
        case .buildLog, .serial:
          ProjectOutputPane(workspace: workspace, pane: pane)
        case .terminal:
          ProjectTerminalPane(workspace: workspace)
        }
      })
  }

  private var hasTerminalHeaderActions: Bool {
    guard let session = workspace.terminalSession else { return false }
    return session.terminalView != nil || session.state != .idle
  }

  @ViewBuilder
  private var contextBarTrailing: some View {
    if let artifact = workspace.lastArtifact {
      HStack(spacing: 4) {
        Button {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            workspace.showInspector = true
          }
        } label: {
          HStack(spacing: 5) {
            Text(artifact.lastPathComponent)
              .font(.system(size: 11, weight: .medium, design: .monospaced))
              .foregroundStyle(TekmorColor.textPrimary)
              .lineLimit(1)
            if let usage = workspace.lastFirmwareUsage {
              Text(String(format: "%.1f%%", usage.utilization * 100))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(
                  usage.utilization > 0.85 ? TekmorColor.warning : TekmorColor.textSecondary)
            }
          }
        }
        .buttonStyle(TekmorFlatActionButtonStyle(compact: true))
        .help(
          l10n.tr(
            .init(
              "help.inspectArtifact",
              defaultValue: "View firmware Flash usage details in Inspector")))

        Button(action: workspace.flashLastArtifact) {
          Image(systemName: "arrow.down.to.line")
        }
        .buttonStyle(TekmorIconButtonStyle(tint: TekmorColor.brand))
        .accessibilityLabel(
          l10n.tr(.init("action.flashFirmware", defaultValue: "Flash Firmware"))
        )
        .disabled(
          !workspace.canStartAction || workspace.programmerIssue != nil
            || workspace.flashSelectionIssue != nil
        )
        .help(
          workspace.programmerIssue ?? workspace.flashHardwareIssue
            ?? l10n.tr(
              .init(
                "help.flashArtifact",
                defaultValue: "Flash this artifact (\(artifact.lastPathComponent))")))
      }
    }
  }
}

private struct ProjectOutputHeaderAccessory: View {
  private enum Control: Hashable {
    case searchButton, menu, filter, connect, port, framing, copy, export, clear
  }

  @Bindable var workspace: Workspace
  let pane: ConsolePane
  @FocusState private var focusedControl: Control?
  @Environment(\.l10n) private var l10n

  private var isSerial: Bool { pane == .serial }

  private var outputIsEmpty: Bool {
    isSerial ? workspace.output.serialLines.isEmpty : workspace.output.logLines.isEmpty
  }

  private var isSearchVisible: Bool {
    let query = isSerial ? workspace.output.serialSearchQuery : workspace.output.logSearchQuery
    return workspace.output.showsSearch(for: isSerial) || !query.isEmpty
  }

  var body: some View {
    Group {
      if isSerial {
        serialHeader
      } else {
        buildLogHeader
      }
    }
    .onChange(of: focusedControl) {
      if focusedControl != nil { activate() }
    }
  }

  private var buildLogHeader: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 4) {
        issuesFilterButton
        searchButton
        consoleIconActions
      }
      .fixedSize(horizontal: true, vertical: false)

      HStack(spacing: 4) {
        issuesFilterButton
        searchButton
        secondaryOutputMenu
      }
      .fixedSize(horizontal: true, vertical: false)

      outputMenu
    }
  }

  private var serialHeader: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 4) {
        SerialDeviceInlineMenu(workspace: workspace, maxValueWidth: 148)
          .disabled(!workspace.canSelectMonitorPort)
          .focused($focusedControl, equals: .port)
        SerialFramingInlineMenu(workspace: workspace)
          .disabled(!workspace.canSelectMonitorPort || workspace.serialConnected)
          .focused($focusedControl, equals: .framing)
        serialConnectButton()
        VerticalHairline(height: 12)
        timestampsButton
        searchButton
        consoleIconActions
      }
      .fixedSize(horizontal: true, vertical: false)

      HStack(spacing: 4) {
        SerialDeviceInlineMenu(workspace: workspace, maxValueWidth: 132)
          .disabled(!workspace.canSelectMonitorPort)
          .focused($focusedControl, equals: .port)
        SerialFramingInlineMenu(workspace: workspace)
          .disabled(!workspace.canSelectMonitorPort || workspace.serialConnected)
          .focused($focusedControl, equals: .framing)
        serialConnectButton()
        VerticalHairline(height: 12)
        timestampsButton
        searchButton
        secondaryOutputMenu
      }
      .fixedSize(horizontal: true, vertical: false)

      HStack(spacing: 4) {
        SerialDeviceInlineMenu(workspace: workspace, maxValueWidth: 120)
          .disabled(!workspace.canSelectMonitorPort)
          .focused($focusedControl, equals: .port)
        serialConnectButton()
        outputMenu
      }
      .fixedSize(horizontal: true, vertical: false)

      HStack(spacing: 3) {
        SerialDeviceInlineMenu(workspace: workspace, compact: true)
          .disabled(!workspace.canSelectMonitorPort)
          .focused($focusedControl, equals: .port)
        serialConnectButton(compact: true)
        outputMenu
      }
      .fixedSize()
    }
  }

  @ViewBuilder
  private var issuesFilterButton: some View {
    if workspace.output.logIssueCount > 0 || workspace.output.logOnlyIssues {
      Button {
        filterBinding.wrappedValue.toggle()
      } label: {
        Label(
          l10n.tr(
            .init(
              "console.onlyIssues", defaultValue: "Issues (\(workspace.output.logIssueCount))")),
          systemImage: "exclamationmark.triangle")
      }
      .buttonStyle(
        TekmorFlatActionButtonStyle(
          tint: TekmorColor.warning,
          active: workspace.output.logOnlyIssues,
          activeTint: TekmorColor.warning,
          activeFill: TekmorColor.warningSubtle,
          compact: true)
      )
      .help(l10n.tr(.init("help.onlyIssues", defaultValue: "Show only warning and error lines")))
      .accessibilityRepresentation {
        Toggle(
          l10n.tr(.init("help.onlyIssues", defaultValue: "Show only warning and error lines")),
          isOn: filterBinding)
      }
      .focused($focusedControl, equals: .filter)
      .fixedSize()

      VerticalHairline(height: 12)
    }
  }

  private var timestampsButton: some View {
    Button {
      filterBinding.wrappedValue.toggle()
    } label: {
      Image(systemName: "clock")
    }
    .buttonStyle(TekmorIconButtonStyle(active: workspace.showTimestamps))
    .accessibilityRepresentation {
      Toggle(
        l10n.tr(.init("accessibility.showTimestamps", defaultValue: "Show timestamps")),
        isOn: filterBinding)
    }
    .focused($focusedControl, equals: .filter)
    .help(l10n.tr(.init("help.showTimestamps", defaultValue: "Show or hide serial timestamps")))
  }

  private func serialConnectButton(compact: Bool = false) -> some View {
    let title = l10n.tr(
      workspace.serialConnected
        ? .init("action.disconnect", defaultValue: "Stop Listening")
        : .init("action.connect", defaultValue: "Listen"))
    return Button {
      activate()
      workspace.toggleSerial()
    } label: {
      if compact {
        Image(systemName: workspace.serialConnected ? "stop.fill" : "play.fill")
          .frame(width: 12, height: 14)
      } else if workspace.serialConnected {
        HStack(spacing: 5) {
          Circle()
            .fill(TekmorColor.success)
            .frame(width: 6, height: 6)
          Text(title)
        }
      } else {
        HStack(spacing: 4) {
          Image(systemName: "play.fill")
            .font(.system(size: 8.5, weight: .semibold))
          Text(title)
        }
      }
    }
    .buttonStyle(
      TekmorFlatActionButtonStyle(
        tint: TekmorColor.brand,
        active: workspace.serialConnected,
        activeTint: TekmorColor.success,
        activeFill: TekmorColor.successSubtle,
        compact: true)
    )
    .accessibilityLabel(title)
    .focused($focusedControl, equals: .connect)
    .disabled(!workspace.canToggleSerial)
    .help(
      workspace.serialSelectionIssue
        ?? l10n.tr(
          workspace.serialConnected
            ? .init("help.disconnectSerial", defaultValue: "Stop listening to serial output")
            : .init("help.connectSerial", defaultValue: "Listen to serial output"))
    )
    .fixedSize()
  }

  private var searchButton: some View {
    let title = l10n.tr(
      isSerial
        ? .init("console.searchSerial", defaultValue: "Search serial output")
        : .init("console.searchBuildLog", defaultValue: "Search build log"))
    return Button(action: toggleSearch) {
      Image(systemName: "magnifyingglass")
    }
    .buttonStyle(TekmorIconButtonStyle(active: isSearchVisible))
    .accessibilityLabel(title)
    .help(title)
    .focused($focusedControl, equals: .searchButton)
  }

  private var consoleIconActions: some View {
    HStack(spacing: 1) {
      Button(
        l10n.tr(.init("console.copyAll", defaultValue: "Copy All Output")),
        systemImage: "doc.on.doc", action: copyOutput
      )
      .labelStyle(.iconOnly)
      .buttonStyle(TekmorIconButtonStyle())
      .help(l10n.tr(.init("help.copyAllOutput", defaultValue: "Copy all output")))
      .focused($focusedControl, equals: .copy)

      Button(
        l10n.tr(.init("console.export", defaultValue: "Export Log…")),
        systemImage: "square.and.arrow.up", action: exportOutput
      )
      .labelStyle(.iconOnly)
      .buttonStyle(TekmorIconButtonStyle())
      .help(l10n.tr(.init("help.exportLog", defaultValue: "Export log file")))
      .focused($focusedControl, equals: .export)

      Button(
        l10n.tr(.init("action.clearActiveConsole", defaultValue: "Clear Output")),
        systemImage: "trash", action: clearOutput
      )
      .labelStyle(.iconOnly)
      .buttonStyle(TekmorIconButtonStyle())
      .help(l10n.tr(.init("help.clearOutput", defaultValue: "Clear output (⌘K)")))
      .focused($focusedControl, equals: .clear)
    }
    .disabled(outputIsEmpty)
  }

  private var secondaryOutputMenu: some View {
    Menu {
      outputTransferButtons
    } label: {
      overflowMenuLabel
    }
    .menuIndicator(.hidden)
    .menuStyle(.borderlessButton)
    .fixedSize()
    .focused($focusedControl, equals: .menu)
  }

  private var outputMenu: some View {
    Menu {
      if isSerial {
        SerialFramingInlineMenu(workspace: workspace)
          .disabled(!workspace.canSelectMonitorPort || workspace.serialConnected)
        Toggle(
          l10n.tr(.init("accessibility.showTimestamps", defaultValue: "Show timestamps")),
          isOn: filterBinding)
      } else {
        Toggle(
          l10n.tr(.init("help.onlyIssues", defaultValue: "Show only warning and error lines")),
          isOn: filterBinding)
      }
      Button(
        l10n.tr(.init("action.searchActiveConsole", defaultValue: "Find in Output")),
        action: toggleSearch)
      Divider()
      outputTransferButtons
    } label: {
      overflowMenuLabel
    }
    .menuIndicator(.hidden)
    .menuStyle(.borderlessButton)
    .fixedSize()
    .focused($focusedControl, equals: .menu)
  }

  @ViewBuilder
  private var outputTransferButtons: some View {
    Button(l10n.tr(.init("console.copyAll", defaultValue: "Copy All Output")), action: copyOutput)
      .disabled(outputIsEmpty)
    Button(
      l10n.tr(.init("help.exportLog", defaultValue: "Export log file")), action: exportOutput
    ).disabled(outputIsEmpty)
    Button(
      l10n.tr(.init("action.clearActiveConsole", defaultValue: "Clear Output")),
      action: clearOutput
    ).disabled(outputIsEmpty)
  }

  private var overflowMenuLabel: some View {
    Label(
      l10n.tr(.init("console.outputActions", defaultValue: "Output Actions")),
      systemImage: "ellipsis.circle"
    )
    .labelStyle(.iconOnly)
    .foregroundStyle(TekmorColor.textSecondary)
    .frame(width: 24, height: 24)
  }

  private func activate() { workspace.selectConsolePane(pane) }

  private func toggleSearch() {
    activate()
    workspace.output.setShowsSearch(!isSearchVisible, isSerial: isSerial)
  }

  private func copyOutput() {
    activate()
    if isSerial {
      workspace.copyText(
        workspace.output.transcript,
        label: l10n.tr(.init("notice.copiedSerialOutput", defaultValue: "Serial output copied")))
    } else {
      workspace.copyText(
        workspace.output.log,
        label: l10n.tr(.init("notice.copiedBuildLog", defaultValue: "Build log copied")))
    }
  }

  private func exportOutput() {
    activate()
    workspace.exportConsole(isSerial: isSerial)
  }

  private func clearOutput() {
    activate()
    workspace.clearActiveConsole()
  }

  private var filterBinding: Binding<Bool> {
    Binding(
      get: { isSerial ? workspace.showTimestamps : workspace.output.logOnlyIssues },
      set: { isEnabled in
        activate()
        if isSerial {
          workspace.showTimestamps = isEnabled
        } else {
          workspace.output.logOnlyIssues = isEnabled
        }
      })
  }
}

private struct ProjectOutputPane: View {
  private enum Control: Hashable {
    case output
  }

  @Bindable var workspace: Workspace
  let pane: ConsolePane
  @State private var selectedMatch: ConsoleSearchResults.Match?
  @FocusState private var focusedControl: Control?
  @Environment(\.l10n) private var l10n

  private var isSerial: Bool { pane == .serial }

  private var searchResults: ConsoleSearchResults {
    ConsoleSearchResults(
      lines: isSerial ? workspace.output.serialLines : workspace.output.filteredLogLines,
      query: searchQuery.wrappedValue,
      includeTimestamps: isSerial && workspace.showTimestamps)
  }

  var body: some View {
    let results = searchResults
    Group {
      if isSerial {
        VStack(spacing: 0) {
          serialViewport(results: results)
          HairlineDivider()
          SerialComposer(workspace: workspace)
        }
      } else {
        buildLogViewport(results: results)
      }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(TapGesture().onEnded { activate() })
    .focusable()
    .focusEffectDisabled()
    .focused($focusedControl, equals: .output)
    .overlay(alignment: .topTrailing) { searchField(results: results) }
    .onChange(of: focusedControl) {
      if focusedControl != nil { activate() }
    }
    .onChange(of: showsSearch) {
      if !showsSearch {
        selectedMatch = nil
        if workspace.activePane == pane {
          focusedControl = .output
        }
      } else {
        focusedControl = nil
      }
    }
    .onChange(of: workspace.consoleSearchRequest) {
      guard workspace.activePane == pane else { return }
      switch workspace.consoleSearchAction {
      case .toggle: toggleSearch()
      case .next: navigateSearch()
      case .previous: navigateSearch(backwards: true)
      }
    }
    .onChange(of: searchQuery.wrappedValue) { selectedMatch = nil }
    .onChange(of: workspace.output.serialFormat) {
      if isSerial { selectedMatch = nil }
    }
    .onExitCommand { if isSearchVisible { closeSearch() } }
  }

  private func activate() { workspace.selectConsolePane(pane) }

  // MARK: - Viewports

  private func buildLogViewport(results: ConsoleSearchResults) -> some View {
    ConsoleViewport(
      mode: .buildLog,
      lines: workspace.output.filteredLogLines,
      totalLineCount: workspace.output.logLines.count,
      searchResults: results,
      currentMatch: results.currentMatch(selectedMatch),
      fontSize: CGFloat(workspace.consoleFontSize),
      follow: $workspace.followBuildLog,
      onlyIssues: workspace.output.logOnlyIssues,
      emptyIcon: "terminal",
      emptyTitle: l10n.tr(
        .init("console.buildLog.emptyTitle", defaultValue: "Waiting for Build or Flash Output")),
      emptySubtitle: l10n.tr(
        workspace.project == nil
          ? .init(
            "console.buildLog.emptySubtitleStandalone",
            defaultValue: "Output from flashing local firmware will appear here.")
          : .init(
            "console.buildLog.emptySubtitleProject",
            defaultValue: "Press ⌘B to build, or ⌘R to build and flash.")),
      emptyActionTitle: workspace.canBuildProject
        ? l10n.tr(.init("action.startBuild", defaultValue: "Start Build")) : nil,
      emptyAction: workspace.canBuildProject ? { workspace.start(.build) } : nil,
      onCopyAll: {
        workspace.copyText(
          workspace.output.log,
          label: l10n.tr(.init("notice.copiedBuildLog", defaultValue: "Build log copied")))
      },
      onCopyLine: {
        workspace.copyText(
          $0, label: l10n.tr(.init("notice.copiedLogLine", defaultValue: "Log line copied")))
      },
      onResolveLocation: { line in
        guard let location = BuildDiagnosticLocation.parse(from: line),
          workspace.resolveSourceLocation(location) != nil
        else { return nil }
        return location
      },
      onOpenLocation: workspace.openSourceLocation,
      onRevealLocation: workspace.revealSourceLocation
    )
  }

  private func serialViewport(results: ConsoleSearchResults) -> some View {
    let emptyAction: (title: String, action: () -> Void)? =
      if workspace.serialConnected {
        nil
      } else if workspace.selectedSerial == nil {
        (
          l10n.tr(.init("action.viewDevices", defaultValue: "View Devices")),
          { workspace.selectSidebarItem(.devices) }
        )
      } else if workspace.canToggleSerial {
        (
          l10n.tr(.init("action.connect", defaultValue: "Listen")),
          { workspace.toggleSerial() }
        )
      } else {
        nil
      }

    return ConsoleViewport(
      mode: .serial,
      lines: workspace.output.serialLines,
      totalLineCount: workspace.output.serialLines.count,
      searchResults: results,
      currentMatch: results.currentMatch(selectedMatch),
      fontSize: CGFloat(workspace.consoleFontSize),
      follow: $workspace.followSerial,
      showTimestamps: workspace.showTimestamps,
      emptyIcon: workspace.serialConnected ? "waveform.path.ecg" : "cable.connector",
      emptyTitle: l10n.tr(
        workspace.serialConnected
          ? .init("console.serial.emptyTitleConnected", defaultValue: "Waiting for Serial Data…")
          : .init("console.serial.emptyTitleDisconnected", defaultValue: "Not Listening")),
      emptySubtitle: workspace.serialConnected
        ? l10n.tr(
          .init(
            "console.serial.emptySubtitleConnected",
            defaultValue: "Listening for output on the selected serial port."))
        : (workspace.selectedSerial == nil
          ? (workspace.serialSelectionIssue
            ?? l10n.tr(
              .init(
                "console.serial.emptySubtitleSelect", defaultValue: "Select a serial device first.")
            ))
          : l10n.tr(
            .init(
              "console.serial.emptySubtitleConnect",
              defaultValue: "Click “Listen” above to start receiving output."))),
      emptyActionTitle: emptyAction?.title,
      emptyAction: emptyAction?.action,
      onCopyAll: {
        workspace.copyText(
          workspace.output.transcript,
          label: l10n.tr(.init("notice.copiedSerialOutput", defaultValue: "Serial output copied")))
      },
      onCopyLine: {
        workspace.copyText(
          $0, label: l10n.tr(.init("notice.copiedSerialLine", defaultValue: "Serial line copied")))
      }
    )
  }

  // MARK: - Console Search

  private var searchQuery: Binding<String> {
    @Bindable var output = workspace.output
    return isSerial ? $output.serialSearchQuery : $output.logSearchQuery
  }

  private var showsSearch: Bool { workspace.output.showsSearch(for: isSerial) }

  private var isSearchVisible: Bool { showsSearch || !searchQuery.wrappedValue.isEmpty }

  private func toggleSearch() {
    activate()
    if isSearchVisible {
      closeSearch()
      return
    }
    workspace.output.setShowsSearch(true, isSerial: isSerial)
    focusedControl = nil
  }

  private func closeSearch() {
    workspace.output.setShowsSearch(false, isSerial: isSerial)
    selectedMatch = nil
    focusedControl = .output
  }

  private func navigateSearch(backwards: Bool = false) {
    activate()
    selectedMatch = searchResults.nextMatch(after: selectedMatch, backwards: backwards)
  }

  @ViewBuilder
  private func searchField(results: ConsoleSearchResults) -> some View {
    if isSearchVisible {
      ConsoleFindBar(
        title: l10n.tr(
          pane == .buildLog
            ? .init("console.searchBuildLogPlaceholder", defaultValue: "Search build log…")
            : .init("console.searchSerialPlaceholder", defaultValue: "Search serial output…")),
        query: searchQuery,
        matchIndex: results.index(of: selectedMatch),
        matchCount: results.matches.count,
        onNext: { navigateSearch() },
        onPrevious: { navigateSearch(backwards: true) },
        onClose: closeSearch,
        onFocus: activate)
    }
  }
}

private struct ProjectTerminalHeaderAccessory: View {
  let workspace: Workspace
  @Environment(\.l10n) private var l10n
  @State private var outputSnapshot: String?

  var body: some View {
    let session = workspace.terminalSession
    let state = session?.state ?? .idle
    let hasActions = session?.terminalView != nil || state != .idle

    Group {
      if hasActions {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 1) {
            if let session, session.terminalView != nil {
              Button {
                toggleSearch(session)
              } label: {
                Image(systemName: "magnifyingglass")
              }
              .buttonStyle(TekmorIconButtonStyle(active: session.showsSearch))
              .accessibilityLabel(
                l10n.tr(.init("console.searchTerminal", defaultValue: "Search terminal output"))
              )
              .help(
                l10n.tr(.init("console.searchTerminal", defaultValue: "Search terminal output")))
            }
            if let terminal = session?.terminalView {
              Button {
                outputSnapshot = terminal.outputSnapshot()
              } label: {
                Label(
                  l10n.tr(.init("terminal.readOutput", defaultValue: "Read Terminal Output…")),
                  systemImage: "doc.plaintext")
              }
              .labelStyle(.iconOnly)
              .buttonStyle(TekmorIconButtonStyle())
              .help(l10n.tr(.init("terminal.readOutput", defaultValue: "Read Terminal Output…")))
            }
            if state != .idle {
              Button(action: workspace.startTerminalSession) {
                Image(systemName: "arrow.clockwise")
              }
              .buttonStyle(TekmorIconButtonStyle())
              .accessibilityLabel(
                l10n.tr(.init("terminal.restart", defaultValue: "Restart Terminal Session"))
              )
              .help(l10n.tr(.init("terminal.restart", defaultValue: "Restart Terminal Session")))
            }
          }
          .fixedSize(horizontal: true, vertical: false)

          Menu {
            if let session, session.terminalView != nil {
              Button(
                l10n.tr(.init("console.searchTerminal", defaultValue: "Search terminal output"))
              ) {
                toggleSearch(session)
              }
            }
            if let terminal = session?.terminalView {
              Button(
                l10n.tr(.init("terminal.readOutput", defaultValue: "Read Terminal Output…"))
              ) {
                outputSnapshot = terminal.outputSnapshot()
              }
            }
            if state != .idle {
              if session?.terminalView != nil { Divider() }
              Button(
                l10n.tr(.init("terminal.restart", defaultValue: "Restart Terminal Session")),
                action: workspace.startTerminalSession)
            }
          } label: {
            Label(
              l10n.tr(.init("terminal.actions", defaultValue: "Terminal Actions")),
              systemImage: "ellipsis.circle"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(TekmorColor.textSecondary)
            .frame(width: 24, height: 24)
          }
          .menuIndicator(.hidden)
          .menuStyle(.borderlessButton)
          .fixedSize()
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { outputSnapshot != nil },
        set: { if !$0 { outputSnapshot = nil } }
      )
    ) {
      let title = l10n.tr(.init("terminal.output", defaultValue: "Terminal Output"))
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        TerminalOutputTextView(
          text: outputSnapshot ?? "", title: title, fontSize: workspace.consoleFontSize)
        Button(l10n.tr(.init("action.done", defaultValue: "Done"))) {
          outputSnapshot = nil
        }
        .keyboardShortcut(.cancelAction)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding()
      .frame(minWidth: 440, idealWidth: 620, minHeight: 280, idealHeight: 420)
    }
  }

  private func toggleSearch(_ session: ProjectTerminal) {
    workspace.activateTerminalSearch()
    if session.showsSearch {
      session.closeSearch()
      workspace.terminals.requestFocus()
    } else {
      session.showsSearch = true
    }
  }
}

private struct ProjectTerminalPane: View {
  let workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    let session = workspace.terminalSession
    let state = session?.state ?? .idle

    VStack(spacing: 0) {
      if let session, let view = session.terminalView {
        if let notice = exitNotice(for: state) {
          FlatCalloutStrip(
            icon: "terminal",
            message: notice,
            accent: TekmorColor.textSecondary,
            background: TekmorColor.chromeBackground
          ) {
            Button(
              l10n.tr(.init("action.restart", defaultValue: "Restart")),
              action: workspace.startTerminalSession
            )
            .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
          }
          HairlineDivider(subtle: true)
        }

        ProjectTerminalHost(
          session: session,
          terminal: view,
          fontSize: workspace.consoleFontSize,
          focusRequest: workspace.activePane == .terminal && !session.showsSearch
            ? workspace.terminals.focusRequest : nil,
          onFocus: { [weak workspace] in workspace?.activateTerminalPane() }
        )
        .overlay(alignment: .topTrailing) {
          if session.showsSearch {
            terminalSearchField(session)
          }
        }
      } else {
        switch state {
        case .idle:
          Button(
            l10n.tr(.init("terminal.open", defaultValue: "Open Terminal")),
            action: workspace.startTerminalSession
          )
          .controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
          ContentUnavailableView {
            Label(
              ConsolePane.terminal.title(using: l10n),
              systemImage: "exclamationmark.triangle")
          } description: {
            Text(message)
          } actions: {
            Button(
              l10n.tr(.init("terminal.restart", defaultValue: "Restart Terminal Session")),
              action: workspace.startTerminalSession
            )
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
          Color.clear
        }
      }
    }
    .background(TekmorColor.workspaceBackground)
    .onChange(of: workspace.consoleSearchRequest) {
      guard workspace.activePane == .terminal, let session else { return }
      switch workspace.consoleSearchAction {
      case .toggle: toggleSearch(session)
      case .next: session.findMatch()
      case .previous: session.findMatch(backwards: true)
      }
    }
    .onExitCommand {
      if let session, session.showsSearch { closeSearch(session) }
    }
  }

  private func toggleSearch(_ session: ProjectTerminal) {
    workspace.activateTerminalSearch()
    if session.showsSearch {
      closeSearch(session)
    } else {
      session.showsSearch = true
    }
  }

  private func closeSearch(_ session: ProjectTerminal) {
    session.closeSearch()
    workspace.terminals.requestFocus()
  }

  private func terminalSearchField(_ session: ProjectTerminal) -> some View {
    @Bindable var session = session
    return ConsoleFindBar(
      title: l10n.tr(
        .init("console.searchTerminalPlaceholder", defaultValue: "Search terminal output…")),
      query: $session.searchQuery,
      matchIndex: session.searchMatchIndex,
      matchCount: session.searchMatchCount,
      onNext: { session.findMatch() },
      onPrevious: { session.findMatch(backwards: true) },
      onClose: { closeSearch(session) },
      onFocus: workspace.activateTerminalSearch)
  }

  private func exitNotice(for state: ProjectTerminal.State) -> String? {
    switch state {
    case .idle, .starting, .running:
      nil
    case .stopped:
      l10n.tr(.init("terminal.stopped", defaultValue: "Session ended"))
    case .exited(let code):
      if let code {
        l10n.tr(.init("terminal.exited", defaultValue: "Shell exited with status \(code)"))
      } else {
        l10n.tr(.init("terminal.stopped", defaultValue: "Session ended"))
      }
    case .failed(let message):
      message
    }
  }
}
