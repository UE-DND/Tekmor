import AppKit
import SwiftUI
import TekmorCore

/// The workspace window's navigation, toolbar, and status bar.
struct MainSplitView: View {
  @Bindable var workspace: Workspace
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.l10n) private var l10n
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    workspaceSplit
      .navigationTitle(windowTitle)
      .navigationSubtitle(windowSubtitle)
      .tint(TekmorColor.brand)
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          contextualToolbarItems
        }
      }
      .sheet(
        isPresented: Binding(
          get: { workspace.binaryFirmware != nil },
          set: { if !$0 { workspace.binaryFirmware = nil } }
        )
      ) {
        BinaryFlashSheet(workspace: workspace)
      }
      .sheet(isPresented: $workspace.showingToolLog) {
        ToolLogSheet(workspace: workspace)
      }
  }

  private var workspaceSplit: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(workspace: workspace)
        .background {
          SidebarCollapseBehavior()
            .allowsHitTesting(false)
        }
        .navigationSplitViewColumnWidth(min: 204, ideal: 260, max: 340)
    } detail: {
      // Reserve space for the status bar in the frame proposed to the AppKit-backed panes.
      VStack(spacing: 0) {
        ZStack(alignment: .bottomTrailing) {
          detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          if let notice = workspace.copiedNotice {
            toastNotice(notice)
              .padding(14)
              .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: workspace.copiedNotice)

        HairlineDivider()
        StatusBarView(workspace: workspace)
          .environment(\.workbenchTextScale, CGFloat(workspace.workbenchTextScale))
      }
    }
    .navigationSplitViewStyle(.balanced)
  }

  // MARK: - Native Window Title & Contextual Toolbar

  private var windowTitle: String {
    switch workspace.sidebarSelection {
    case .project, nil:
      workspace.project?.lastPathComponent ?? "Tekmor"
    case .devices:
      l10n.tr(.init("sidebar.devices", defaultValue: "Devices"))
    case .tools:
      l10n.tr(.init("sidebar.tools", defaultValue: "Toolchains"))
    }
  }

  private var windowSubtitle: String {
    switch workspace.sidebarSelection {
    case .project, nil:
      if let project = workspace.project {
        return (project.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
      }
      guard workspace.hasConsoleContent, workspace.activePane != .buildLog else { return "" }
      return workspace.activePane.title(using: l10n)
    case .devices:
      return workspace.connectedDeviceCount > 0
        ? "\(l10n.tr(.init("devices.subtitle.serialCount", defaultValue: "\(workspace.devices.count) serial ports"))) · \(l10n.tr(.init("devices.subtitle.probeCount", defaultValue: "\(workspace.probes.count) probes")))"
        : ""
    case .tools:
      return ""
    }
  }

  @ViewBuilder
  private var contextualToolbarItems: some View {
    switch workspace.sidebarSelection {
    case .project, nil:
      if workspace.project != nil {
        if workspace.running {
          Button(action: workspace.cancel) {
            Label(
              l10n.tr(
                workspace.writing
                  ? .init("action.writing", defaultValue: "Writing…")
                  : .init("action.cancel", defaultValue: "Cancel")), systemImage: "stop.fill")
          }
          .disabled(!workspace.canCancelTask)
          .help(l10n.tr(.init("help.cancelTask", defaultValue: "Cancel current task")))
        } else {
          Button {
            workspace.start(.run)
          } label: {
            Label(
              l10n.tr(.init("action.buildAndFlash", defaultValue: "Build & Flash")),
              systemImage: "play.fill"
            )
            .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.borderedProminent)
          .tint(TekmorColor.ctaBottom)
          .disabled(!workspace.canRunProject)
          .help(
            workspace.buildToolsIssue ?? workspace.programmerIssue ?? workspace.flashHardwareIssue
              ?? l10n.tr(
                .init(
                  "help.buildAndFlash",
                  defaultValue: "Build, flash, verify firmware, and reset the target (⌘R)")))

          Button {
            workspace.start(.build)
          } label: {
            Label(l10n.tr(.init("action.build", defaultValue: "Build")), systemImage: "hammer")
          }
          .disabled(!workspace.canBuildProject)
          .help(
            workspace.buildToolsIssue
              ?? l10n.tr(.init("help.buildOnly", defaultValue: "Build ELF only (⌘B)")))

        }

        Menu {
          Button(
            l10n.tr(.init("action.flashFirmwareEllipsis", defaultValue: "Flash Firmware…")),
            action: workspace.chooseFirmware
          )
          .disabled(!workspace.canChooseFirmware)
          Divider()
          Button(l10n.tr(.init("action.reconfigureCMake", defaultValue: "Reconfigure CMake"))) {
            workspace.start(.reconfigure)
          }
          .disabled(!workspace.canConfigureProject)
          Button(
            l10n.tr(.init("action.cleanProjectCache", defaultValue: "Clear Project Build Cache"))
          ) {
            workspace.start(.cleanProjectCache)
          }
          Divider()
          Button(
            l10n.tr(.init("action.revealProjectInFinder", defaultValue: "Reveal Project in Finder"))
          ) { workspace.revealProject() }
          if workspace.lastArtifact != nil {
            Button(
              l10n.tr(.init("action.revealELFInFinder", defaultValue: "Reveal ELF in Finder")),
              action: workspace.revealArtifact)
          }
          Divider()
          Button(
            l10n.tr(.init("action.closeProject", defaultValue: "Close Project")),
            action: workspace.closeProject)
        } label: {
          Label(l10n.tr(.init("action.more", defaultValue: "More")), systemImage: "ellipsis.circle")
        }
        .disabled(!workspace.canStartAction)

        inspectorToggleToolbarButton
      } else if workspace.hasConsoleContent {
        if workspace.running {
          Button(action: workspace.cancel) {
            Label(
              l10n.tr(
                workspace.writing
                  ? .init("action.writing", defaultValue: "Writing…")
                  : .init("action.cancel", defaultValue: "Cancel")), systemImage: "stop.fill")
          }
          .disabled(!workspace.canCancelTask)
        } else {
          Menu {
            Button(
              l10n.tr(.init("action.flashFirmwareEllipsis", defaultValue: "Flash Firmware…")),
              action: workspace.chooseFirmware
            )
            .disabled(!workspace.canChooseFirmware)
          } label: {
            Label(
              l10n.tr(.init("action.more", defaultValue: "More")), systemImage: "ellipsis.circle")
          }
          .disabled(!workspace.canStartAction)
        }

        inspectorToggleToolbarButton
      } else {
        Button(action: workspace.chooseFirmware) {
          Label(
            l10n.tr(.init("action.flashFirmware", defaultValue: "Flash Firmware")),
            systemImage: "arrow.down.to.line")
        }
        .disabled(!workspace.canChooseFirmware)
        .help(
          workspace.programmerIssue
            ?? l10n.tr(.init("help.flashFirmware", defaultValue: "Flash an ELF, HEX, or BIN file")))
      }

    case .devices:
      Button(action: workspace.refreshDevices) {
        Label(
          l10n.tr(.init("action.refresh", defaultValue: "Refresh")), systemImage: "arrow.clockwise")
      }
      .help(l10n.tr(.init("help.scanDevices", defaultValue: "Scan for hardware devices now")))

    case .tools:
      if workspace.running {
        if workspace.isManagingTools {
          Button(action: workspace.showToolLog) {
            Label(
              l10n.tr(.init("action.viewLog", defaultValue: "View Log")),
              systemImage: "doc.plaintext")
          }
          .help(l10n.tr(.init("help.viewToolLog", defaultValue: "Show tool installation log")))
        }
        Button(action: workspace.cancel) {
          Label(l10n.tr(.init("action.cancel", defaultValue: "Cancel")), systemImage: "stop.fill")
        }
        .disabled(!workspace.canCancelTask)
      } else {
        if !workspace.output.toolLogLines.isEmpty {
          Button(action: workspace.showToolLog) {
            Label(
              l10n.tr(.init("action.viewLog", defaultValue: "View Log")),
              systemImage: "doc.plaintext")
          }
          .help(l10n.tr(.init("help.viewToolLog", defaultValue: "Show tool installation log")))
        }
        if workspace.hasCheckedCube && !workspace.loadingCube
          && workspace.missingRequiredToolCount > 0
        {
          Button {
            workspace.start(.prepareAllTools)
          } label: {
            Label(
              l10n.tr(.init("tools.action.installMissing", defaultValue: "Install Missing")),
              systemImage: "arrow.down.circle"
            )
            .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.borderedProminent)
          .tint(TekmorColor.ctaBottom)
          .disabled(!workspace.canStartAction)
          .help(
            l10n.tr(
              .init(
                "help.installMissingTools",
                defaultValue: "Install all missing STM32CubeCLI and required tool bundles")))
        }
        Button {
          Task { await workspace.refreshTools() }
        } label: {
          Label(
            l10n.tr(.init("action.refreshTools", defaultValue: "Refresh Tools")),
            systemImage: "arrow.clockwise")
        }
        .disabled(!workspace.canStartAction || workspace.loadingCube)
        .help(l10n.tr(.init("help.refreshTools", defaultValue: "Check installed STM32 tools now")))
      }
    }
  }

  private var inspectorToggleToolbarButton: some View {
    Button {
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
        workspace.showInspector.toggle()
      }
    } label: {
      Label(
        l10n.tr(.init("action.inspector", defaultValue: "Inspector")),
        systemImage: "sidebar.trailing")
    }
    .accessibilityValue(
      l10n.tr(
        workspace.showInspector
          ? .init("accessibility.visible", defaultValue: "Visible")
          : .init("accessibility.hidden", defaultValue: "Hidden"))
    )
    .help(
      l10n.tr(
        workspace.showInspector
          ? .init("help.hideInspector", defaultValue: "Hide Inspector (⌘⌥I)")
          : .init("help.showInspector", defaultValue: "Show Inspector (⌘⌥I)")))
  }

  // MARK: - Detail Router

  @ViewBuilder
  private var detailContent: some View {
    switch workspace.sidebarSelection {
    case .project, nil:
      ProjectDetailView(workspace: workspace)
    case .devices:
      DevicesView(workspace: workspace)
    case .tools:
      ToolchainsView(workspace: workspace)
    }
  }

  // MARK: - Non-blocking Feedback

  private func toastNotice(_ text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(TekmorColor.success)
      Text(text)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(TekmorColor.textInk)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 6.5)
    .background(
      TekmorColor.chromeBackground,
      in: RoundedRectangle(cornerRadius: TekmorRadius.sheet, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: TekmorRadius.sheet, style: .continuous)
        .strokeBorder(TekmorColor.separatorStrong, lineWidth: 1)
    )
  }
}

private struct SidebarCollapseBehavior: NSViewRepresentable {
  func makeNSView(context: Context) -> SplitAttachment {
    SplitAttachment()
  }

  func updateNSView(_ view: SplitAttachment, context: Context) {
    view.applyCollapseBehavior()
  }

  final class SplitAttachment: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      applyCollapseBehavior()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      applyCollapseBehavior()
    }

    func applyCollapseBehavior() {
      var ancestor = window == nil ? nil : superview
      while let view = ancestor {
        if let splitView = view as? NSSplitView,
          let controller = splitView.delegate as? NSSplitViewController,
          let sidebarItem = controller.splitViewItems.first(where: { $0.behavior == .sidebar })
        {
          // Keep detail pane width pinned to the window while expanding the sidebar,
          // avoiding frame-by-frame layout thrash and toolbar overflow clipping.
          if sidebarItem.collapseBehavior != .useConstraints {
            sidebarItem.collapseBehavior = .useConstraints
          }
          return
        }
        ancestor = view.superview
      }
    }
  }
}
