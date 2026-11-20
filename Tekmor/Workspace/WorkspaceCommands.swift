import SwiftUI
import TekmorCore

struct WorkspaceCommands: Commands {
  let l10n: AppL10n
  @FocusedValue(Workspace.self) private var workspace

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button(l10n.tr(.init("action.addProjectEllipsis", defaultValue: "Add Project…"))) {
        workspace?.chooseProject()
      }
      .keyboardShortcut("o")
      .disabled(workspace?.canStartAction != true)
    }
    CommandGroup(after: .textEditing) {
      Button(l10n.tr(.init("action.searchActiveConsole", defaultValue: "Find in Output"))) {
        workspace?.requestConsoleSearch()
      }
      .keyboardShortcut("f")
      .disabled(workspace?.canSearchActiveConsole != true)
      Button(l10n.tr(.init("action.findNext", defaultValue: "Find Next"))) {
        workspace?.requestConsoleSearch(.next)
      }
      .keyboardShortcut("g")
      .disabled(workspace?.canNavigateConsoleSearch != true)
      Button(l10n.tr(.init("action.findPrevious", defaultValue: "Find Previous"))) {
        workspace?.requestConsoleSearch(.previous)
      }
      .keyboardShortcut("g", modifiers: [.command, .shift])
      .disabled(workspace?.canNavigateConsoleSearch != true)
      Button(l10n.tr(.init("action.clearActiveConsole", defaultValue: "Clear Output"))) {
        workspace?.clearActiveConsole()
      }
      .keyboardShortcut("k")
      .disabled(workspace?.canClearActiveConsole != true)
    }
    CommandGroup(after: .sidebar) {
      Button(l10n.tr(.init("pane.buildLog", defaultValue: "Build Log"))) {
        workspace?.showBuildLog()
      }
      .keyboardShortcut("1")
      .disabled(workspace == nil)
      Button(l10n.tr(.init("pane.serial", defaultValue: "Serial Monitor"))) {
        workspace?.showSerialMonitor()
      }
      .keyboardShortcut("2")
      .disabled(workspace == nil)
      Button(l10n.tr(.init("sidebar.devices", defaultValue: "Devices"))) {
        workspace?.selectSidebarItem(.devices)
      }
      .keyboardShortcut("3")
      .disabled(workspace == nil)
      Button(l10n.tr(.init("sidebar.tools", defaultValue: "Toolchains"))) {
        workspace?.selectSidebarItem(.tools)
      }
      .keyboardShortcut("4")
      .disabled(workspace == nil)
      Button(ConsolePane.terminal.title(using: l10n)) { workspace?.showTerminal() }
        .keyboardShortcut("5")
        .disabled(workspace == nil)
      Divider()
      Button(
        l10n.tr(
          workspace?.isSplitConsole == true
            ? .init("action.unsplitConsole", defaultValue: "Exit Split Console")
            : .init("action.splitConsole", defaultValue: "Split Log & Serial"))
      ) { workspace?.toggleSplitConsole() }
      .keyboardShortcut("\\")
      .disabled(workspace?.canArrangeConsole != true)
      Button(
        l10n.tr(
          workspace?.showInspector == true
            ? .init("action.hideInspector", defaultValue: "Hide Inspector")
            : .init("action.showInspector", defaultValue: "Show Inspector"))
      ) { workspace?.showInspector.toggle() }
      .keyboardShortcut("i", modifiers: [.command, .option])
      .disabled(workspace?.canArrangeConsole != true)
    }
    CommandMenu(l10n.tr(.init("menu.project", defaultValue: "Project"))) {
      Button(l10n.tr(.init("action.buildAndFlash", defaultValue: "Build & Flash"))) {
        workspace?.start(.run)
      }
      .keyboardShortcut("r")
      .disabled(workspace?.canRunProject != true)
      Button(l10n.tr(.init("action.build", defaultValue: "Build"))) { workspace?.start(.build) }
        .keyboardShortcut("b")
        .disabled(workspace?.canBuildProject != true)
      Button(l10n.tr(.init("help.cancelTask", defaultValue: "Cancel current task"))) {
        workspace?.cancel()
      }
      .keyboardShortcut(".")
      .disabled(workspace?.canCancelTask != true)
      Divider()
      Button(
        l10n.tr(
          workspace?.serialConnected == true
            ? .init("action.disconnectSerial", defaultValue: "Stop Listening")
            : .init("action.openSerial", defaultValue: "Listen"))
      ) { workspace?.toggleSerial() }
      .disabled(workspace?.canToggleSerial != true)
      Button(l10n.tr(.init("action.flashFirmwareEllipsis", defaultValue: "Flash Firmware…"))) {
        workspace?.chooseFirmware()
      }
      .disabled(workspace?.canChooseFirmware != true)
      Divider()
      Button(l10n.tr(.init("action.refreshDevices", defaultValue: "Refresh Devices"))) {
        workspace?.refreshDevices()
      }
      .disabled(workspace == nil)
    }
  }
}
