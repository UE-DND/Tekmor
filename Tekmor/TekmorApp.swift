import AppKit
import SwiftUI
import TekmorCore

@main
struct TekmorApp: App {
  @State private var workspace = Workspace()
  @NSApplicationDelegateAdaptor(TekmorDelegate.self) private var delegate

  var body: some Scene {
    let l10n = workspace.l10n

    Window("Tekmor", id: "workspace") {
      MainSplitView(workspace: workspace)
        .environment(\.l10n, l10n)
        .environment(\.locale, workspace.locale)
        .focusedSceneValue(workspace)
        .frame(minWidth: 880, minHeight: 560)
        .task {
          delegate.canQuit = workspace.requestQuit
          delegate.stopTerminals = workspace.stopTerminalsForQuit
          while !Task.isCancelled {
            workspace.refreshDevices()
            try? await Task.sleep(for: .seconds(2))
          }
        }
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified)
    .defaultSize(width: 1120, height: 720)
    .commands { WorkspaceCommands(l10n: l10n) }

    Settings {
      SettingsView(workspace: workspace)
        .environment(\.l10n, l10n)
        .environment(\.locale, workspace.locale)
    }
  }
}

@MainActor
final class TekmorDelegate: NSObject, NSApplicationDelegate {
  var canQuit: (() -> Bool)?
  var stopTerminals: (() -> Bool)?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard canQuit?() != false else { return .terminateCancel }
    guard stopTerminals?() == true else { return .terminateNow }
    Task { @MainActor in
      // Let SwiftTerm finish releasing the PTY and escalate if the shell ignores SIGTERM.
      try? await Task.sleep(for: .milliseconds(250))
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
