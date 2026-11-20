import SwiftUI
import TekmorCore

/// Modal sheet showing live STM32CubeCLI and managed bundle installation output without leaving
/// the current view or mixing tool output into project build logs.
struct ToolLogSheet: View {
  @Bindable var workspace: Workspace
  @State private var follow: Bool
  @State private var copiedFeedback = false
  @State private var copiedResetTask: Task<Void, Never>?
  @Environment(\.l10n) private var l10n

  init(workspace: Workspace) {
    self.workspace = workspace
    _follow = State(initialValue: workspace.defaultFollowOutput)
  }

  private var isEmpty: Bool {
    workspace.output.toolLogLines.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      headerBar
      HairlineDivider()

      ConsoleViewport(
        mode: .buildLog,
        lines: workspace.output.toolLogLines,
        totalLineCount: workspace.output.toolLogLines.count,
        searchResults: ConsoleSearchResults(
          lines: workspace.output.toolLogLines, query: "", includeTimestamps: false),
        currentMatch: nil,
        fontSize: CGFloat(workspace.consoleFontSize),
        follow: $follow,
        emptyIcon: "doc.plaintext",
        emptyTitle: l10n.tr(
          .init("toolLog.emptyTitle", defaultValue: "No Installation Output Yet")),
        emptySubtitle: l10n.tr(
          .init(
            "toolLog.emptySubtitle",
            defaultValue: "Output from downloading and installing STM32 tools will appear here.")),
        onCopyAll: copyAll,
        onCopyLine: { line in
          workspace.copyText(
            line, label: l10n.tr(.init("notice.copiedLogLine", defaultValue: "Log line copied")))
          flashCopied()
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      HairlineDivider()
      footerBar
    }
    .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 440)
    .onDisappear {
      copiedResetTask?.cancel()
    }
  }

  private var headerBar: some View {
    HStack(spacing: 10) {
      Text(l10n.tr(.init("toolLog.title", defaultValue: "Toolchain Installation Log")))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(TekmorColor.textInk)

      if workspace.isManagingTools {
        InlineStatusIndicator(
          text: workspace.status,
          color: TekmorColor.brand,
          textColor: TekmorColor.textSecondary,
          spinning: true)
      }

      Spacer(minLength: 8)

      if copiedFeedback {
        InlineStatusIndicator(
          text: l10n.tr(.init("toolLog.copied", defaultValue: "Copied")),
          color: TekmorColor.success,
          textColor: TekmorColor.success,
          icon: "checkmark.circle.fill")
      }

      HStack(spacing: 2) {
        Button(
          l10n.tr(.init("console.copyAll", defaultValue: "Copy All Output")),
          systemImage: "doc.on.doc",
          action: copyAll
        )
        .labelStyle(.iconOnly)
        .buttonStyle(TekmorIconButtonStyle())
        .help(l10n.tr(.init("help.copyAllOutput", defaultValue: "Copy all output")))

        Button(
          l10n.tr(.init("action.clearActiveConsole", defaultValue: "Clear Output")),
          systemImage: "trash",
          action: workspace.clearToolLog
        )
        .labelStyle(.iconOnly)
        .buttonStyle(TekmorIconButtonStyle())
        .help(l10n.tr(.init("action.clearActiveConsole", defaultValue: "Clear Output")))
      }
      .disabled(isEmpty)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(TekmorColor.chromeBackground)
  }

  private var footerBar: some View {
    HStack(spacing: 10) {
      if !isEmpty {
        Text(
          "\(l10n.tr(.init("count.lines", defaultValue: "\(workspace.output.toolLogLines.count) lines"))) · \(workspace.formatBytes(workspace.output.toolLog.utf8.count))"
        )
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(TekmorColor.textSecondary)
      }

      Toggle(isOn: $follow) {
        Text(l10n.tr(.init("statusBar.followOutput", defaultValue: "Follow Output")))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(TekmorColor.textSecondary)
      }
      .toggleStyle(.checkbox)
      .fixedSize()

      Spacer(minLength: 8)

      if workspace.isManagingTools {
        Button(l10n.tr(.init("action.cancel", defaultValue: "Cancel")), action: workspace.cancel)
          .disabled(!workspace.canCancelTask)
      }

      Button(l10n.tr(.init("action.done", defaultValue: "Done"))) {
        workspace.showingToolLog = false
      }
      .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(TekmorColor.chromeBackground)
  }

  private func copyAll() {
    workspace.copyText(
      workspace.output.toolLog,
      label: l10n.tr(.init("toolLog.copied", defaultValue: "Copied")))
    flashCopied()
  }

  private func flashCopied() {
    copiedResetTask?.cancel()
    copiedFeedback = true
    copiedResetTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      copiedFeedback = false
    }
  }
}
