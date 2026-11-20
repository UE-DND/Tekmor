import SwiftUI
import TekmorCore

/// Single full-window 28pt bottom status bar — the sole source of truth for global workspace status,
/// active console metrics/follow control, and the global Settings trigger.
struct StatusBarView: View {
  @Bindable var workspace: Workspace
  @State private var showingErrorDetail = false
  @Environment(\.l10n) private var l10n
  @Environment(\.workbenchTextScale) private var textScale

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        statusSummary(maxErrorWidth: workspace.canUseOutputCommands ? 420 : 680)
        Spacer(minLength: 8)
        if workspace.canUseOutputCommands {
          outputMetrics
          followOutput
          VerticalHairline(height: 12)
        }
        settingsLink
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          statusSummary(maxErrorWidth: nil)
          Spacer(minLength: 8)
          settingsLink
        }
        if workspace.canUseOutputCommands {
          ViewThatFits(in: .horizontal) {
            HStack {
              outputMetrics
              Spacer(minLength: 8)
              followOutput
            }
            VStack(alignment: .leading, spacing: 4) {
              outputMetrics
              followOutput
            }
          }
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 12)
    .padding(.vertical, 3)
    .frame(minHeight: 28)
    .background(TekmorColor.chromeBackground)
    .onChange(of: workspace.errorMessage) {
      if workspace.errorMessage == nil {
        showingErrorDetail = false
      }
    }
  }

  private func statusSummary(maxErrorWidth: CGFloat?) -> some View {
    HStack(spacing: 8) {
      if workspace.running || workspace.errorMessage == nil {
        statusLeading
      }

      if let error = workspace.errorMessage {
        if workspace.running {
          VerticalHairline(height: 12)
        }
        errorStatusControl(error, maxWidth: maxErrorWidth)
      } else if workspace.running && (workspace.isManagingTools || !workspace.isShowingProjectArea)
      {
        Button(l10n.tr(.init("action.viewLog", defaultValue: "View Log"))) {
          if workspace.isManagingTools {
            workspace.showToolLog()
          } else {
            workspace.showBuildLog()
          }
        }
        .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
      } else if !workspace.running,
        let duration = workspace.lastBuildDuration
      {
        Text("·")
          .font(.system(size: 12 * textScale))
          .foregroundStyle(TekmorColor.textTertiary)
        Text(
          duration.formatted(
            .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1)).locale(
              l10n.locale))
        )
        .font(.system(size: 12 * textScale, design: .monospaced))
        .foregroundStyle(TekmorColor.textTertiary)
      }
    }
  }

  private func errorStatusControl(_ message: String, maxWidth: CGFloat?) -> some View {
    HStack(spacing: 4) {
      errorTriggerButton(message, maxWidth: maxWidth)

      if canViewErrorLog {
        Button(l10n.tr(.init("action.viewLog", defaultValue: "View Log")), action: viewErrorLog)
          .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
      }

      Button {
        showingErrorDetail = false
        workspace.errorMessage = nil
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
      }
      .buttonStyle(TekmorIconButtonStyle())
      .accessibilityLabel(l10n.tr(.init("help.dismissBanner", defaultValue: "Dismiss")))
      .help(l10n.tr(.init("help.dismissBanner", defaultValue: "Dismiss")))
    }
  }

  @ViewBuilder
  private func errorTriggerButton(_ message: String, maxWidth: CGFloat?) -> some View {
    let summary = singleLineSummary(message)
    let button = Button {
      showingErrorDetail.toggle()
    } label: {
      HStack(spacing: 5.5) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 11 * textScale, weight: .semibold))
          .foregroundStyle(TekmorColor.error)
        Text(summary)
          .font(.system(size: 12 * textScale, weight: .medium))
          .foregroundStyle(TekmorColor.error)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: maxWidth, alignment: .leading)
      }
    }
    .buttonStyle(
      TekmorFlatActionButtonStyle(
        tint: TekmorColor.error,
        active: showingErrorDetail,
        activeTint: TekmorColor.error,
        activeFill: TekmorColor.errorSubtle,
        compact: true)
    )
    .help(message)
    .popover(isPresented: $showingErrorDetail, arrowEdge: .top) {
      errorPopover(message)
    }

    if maxWidth != nil {
      button.fixedSize(horizontal: true, vertical: false)
    } else {
      button
    }
  }

  private func errorPopover(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(TekmorColor.error)
        Text(l10n.tr(.init("statusBar.errorDetails", defaultValue: "Error Details")))
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(TekmorColor.textInk)
        Spacer(minLength: 8)
      }

      ViewThatFits(in: .vertical) {
        errorDetailText(message)
        ScrollView {
          errorDetailText(message)
        }
      }
      .frame(maxHeight: 220)

      HStack(spacing: 6) {
        if canViewErrorLog {
          Button(l10n.tr(.init("action.viewLog", defaultValue: "View Log")), action: viewErrorLog)
            .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
        }
        Spacer(minLength: 0)
        Button(l10n.tr(.init("action.copy", defaultValue: "Copy"))) {
          workspace.copyText(
            message,
            label: l10n.tr(.init("notice.copiedError", defaultValue: "Error message copied")))
        }
        .buttonStyle(TekmorFlatActionButtonStyle(compact: true))
        Button(l10n.tr(.init("help.dismissBanner", defaultValue: "Dismiss"))) {
          showingErrorDetail = false
          workspace.errorMessage = nil
        }
        .buttonStyle(TekmorFlatActionButtonStyle(compact: true))
      }
    }
    .padding(14)
    .frame(width: 440)
  }

  private func errorDetailText(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(TekmorColor.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func singleLineSummary(_ message: String) -> String {
    let lines = message.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return lines.isEmpty ? message : lines.joined(separator: " · ")
  }

  private var canViewErrorLog: Bool {
    switch workspace.errorLogDestination {
    case .tools:
      !workspace.output.toolLogLines.isEmpty
    case .build:
      !workspace.isShowingProjectArea && !workspace.output.logLines.isEmpty
    case nil:
      false
    }
  }

  private func viewErrorLog() {
    showingErrorDetail = false
    switch workspace.errorLogDestination {
    case .tools:
      workspace.showToolLog()
    case .build:
      workspace.showBuildLog()
    case nil:
      break
    }
  }

  private var settingsLink: some View {
    SettingsLink {
      Label(l10n.tr(.init("action.settings", defaultValue: "Settings")), systemImage: "gearshape")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(TekmorIconButtonStyle())
    .help(l10n.tr(.init("help.settings", defaultValue: "Settings (⌘,)")))
  }

  private var statusLeading: some View {
    Button {
      if workspace.isManagingTools {
        workspace.showToolLog()
      } else {
        workspace.showProjectArea()
      }
    } label: {
      InlineStatusIndicator(
        text: workspace.status,
        color: statusColor,
        textColor: workspace.running ? TekmorColor.textInk : TekmorColor.textSecondary,
        spinning: workspace.running
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(
      workspace.isManagingTools
        ? l10n.tr(.init("help.viewToolLog", defaultValue: "Show tool installation log"))
        : (workspace.isShowingProjectArea
          ? workspace.status
          : l10n.tr(.init("help.showProjectArea", defaultValue: "Show Project View"))))
  }

  private var outputMetrics: some View {
    HStack(spacing: 10) {
      if let filteredSummary {
        Text(filteredSummary)
          .font(.system(size: 12 * textScale, design: .monospaced))
          .foregroundStyle(TekmorColor.brand)
      }

      if let metricSummary {
        Text(metricSummary)
          .font(.system(size: 12 * textScale, design: .monospaced))
          .foregroundStyle(TekmorColor.textSecondary)
      }
    }
  }

  private var followOutput: some View {
    Toggle(isOn: activeFollowBinding) {
      Text(l10n.tr(.init("statusBar.followOutput", defaultValue: "Follow Output")))
        .font(.system(size: 12 * textScale, weight: .medium))
        .foregroundStyle(TekmorColor.textSecondary)
    }
    .toggleStyle(.checkbox)
    .fixedSize()
  }

  private var statusColor: Color {
    switch workspace.statusState {
    case .failed: TekmorColor.error
    case .buildComplete, .verifiedNeedsReset, .verifiedAndReset, .toolsReady: TekmorColor.success
    default: TekmorColor.brandBright
    }
  }

  private var filteredSummary: String? {
    switch workspace.activePane {
    case .buildLog:
      guard workspace.output.logOnlyIssues else { return nil }
      return l10n.tr(
        .init(
          "statusBar.filter.showing",
          defaultValue:
            "Showing \(workspace.output.filteredLogLines.count)/\(workspace.output.logLines.count)")
      )
    case .serial, .terminal:
      return nil
    }
  }

  private var metricSummary: String? {
    switch workspace.activePane {
    case .buildLog:
      return
        "\(l10n.tr(.init("count.lines", defaultValue: "\(workspace.output.logLines.count) lines"))) · \(workspace.formatBytes(workspace.output.log.utf8.count))"
    case .serial:
      return
        "RX \(l10n.tr(.init("count.lines", defaultValue: "\(workspace.output.serialLineCount) lines"))) · \(workspace.formatBytes(workspace.output.serialByteCount))"
    case .terminal:
      return nil
    }
  }

  private var activeFollowBinding: Binding<Bool> {
    workspace.activePane == .serial ? $workspace.followSerial : $workspace.followBuildLog
  }
}
