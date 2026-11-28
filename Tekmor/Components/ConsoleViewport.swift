import SwiftUI
import TekmorWorkbench

/// Pure flat terminal & build-log viewport without redundant footer chrome.
/// Follow state & metrics are coordinated directly with `Workspace` and the unified bottom `StatusBarView`.
struct ConsoleViewport: View {
  enum Mode {
    case buildLog
    case serial
  }

  let mode: Mode
  let lines: [ConsoleBuffer.Line]
  let totalLineCount: Int
  let searchResults: ConsoleSearchResults
  let currentMatch: ConsoleSearchResults.Match?
  var fontSize: CGFloat = 12.5
  @Binding var follow: Bool
  var onlyIssues: Bool = false
  var showTimestamps: Bool = true
  var emptyIcon: String
  var emptyTitle: String
  var emptySubtitle: String
  var emptyActionTitle: String? = nil
  var emptyAction: (() -> Void)? = nil
  var onCopyAll: () -> Void
  var onCopyLine: (String) -> Void
  var onResolveLocation: ((String) -> BuildDiagnosticLocation?)? = nil
  var onOpenLocation: ((BuildDiagnosticLocation) -> Void)? = nil
  var onRevealLocation: ((BuildDiagnosticLocation) -> Void)? = nil
  @Environment(\.l10n) private var l10n
  @State private var viewportSize: CGSize = .zero

  var body: some View {
    contentArea
      .background(TekmorColor.workspaceBackground)
  }

  @ViewBuilder
  private var contentArea: some View {
    if lines.isEmpty {
      let isFilteringIssues = onlyIssues && totalLineCount > 0
      ContentUnavailableView {
        if isFilteringIssues {
          Label(
            l10n.tr(.init("console.noIssues", defaultValue: "No Warnings or Errors")),
            systemImage: "checkmark.circle")
        } else {
          Label(emptyTitle, systemImage: emptyIcon)
        }
      } description: {
        if !isFilteringIssues && !emptySubtitle.isEmpty {
          Text(emptySubtitle)
        }
      } actions: {
        if !isFilteringIssues, let emptyActionTitle, let emptyAction {
          Button(emptyActionTitle, action: emptyAction)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      let matchesByLine = Dictionary(grouping: searchResults.matches, by: \.lineID)
      ScrollViewReader { proxy in
        ZStack(alignment: .bottomTrailing) {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 1) {
              ForEach(lines) { line in
                consoleRow(line, matches: matchesByLine[line.id] ?? [])
                  .id(line.id)
              }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .onGeometryChange(for: CGSize.self, of: \.size) { viewportSize = $0 }
          .task(id: scrollTrigger) {
            guard follow, searchResults.query.isEmpty, let lastID = lines.last?.id else { return }
            // Run after the current layout pass so NSScrollView never hits layout recursion,
            // while remaining shorter than Workspace's batch window so continuous logs never starve.
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            proxy.scrollTo(lastID, anchor: .bottom)
          }
          .task(id: FindScrollTrigger(query: searchResults.query, match: currentMatch)) {
            guard let currentMatch else { return }
            follow = false
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            proxy.scrollTo(currentMatch.lineID, anchor: .center)
          }

          if !follow {
            Button {
              follow = true
            } label: {
              Label(
                l10n.tr(.init("console.jumpToLatest", defaultValue: "Jump to Latest")),
                systemImage: "arrow.down.to.line"
              )
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(TekmorColor.ctaBottom, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(12)
          }
        }
      }
    }
  }

  private struct ScrollTrigger: Equatable {
    let lastID: Int?
    let lastLength: Int
    let viewportSize: CGSize
    let follow: Bool
  }

  private struct FindScrollTrigger: Equatable {
    let query: String
    let match: ConsoleSearchResults.Match?
  }

  private var scrollTrigger: ScrollTrigger {
    ScrollTrigger(
      lastID: lines.last?.id,
      lastLength: lines.last?.text.count ?? 0,
      viewportSize: viewportSize,
      follow: follow
    )
  }

  private func consoleRow(
    _ line: ConsoleBuffer.Line, matches: [ConsoleSearchResults.Match]
  ) -> some View {
    let rowBackground: Color =
      switch line.kind {
      case .error: TekmorColor.errorSubtle
      case .warning: TekmorColor.warningSubtle
      case .success: TekmorColor.successSubtle
      default: .clear
      }

    let textColor: Color =
      switch line.kind {
      case .error: TekmorColor.error
      case .warning: TekmorColor.warning
      case .success: TekmorColor.success
      case .info: TekmorColor.brandBright
      case .command: TekmorColor.primaryTonal
      case .normal: TekmorColor.textPrimary
      }

    let location: BuildDiagnosticLocation? =
      mode == .buildLog ? onResolveLocation?(line.text) : nil

    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      if let severity = severityLabel(for: line.kind) {
        Label(severity.title, systemImage: severity.symbol)
          .labelStyle(.iconOnly)
          .font(.system(size: max(11, fontSize - 1), weight: .medium))
          .foregroundStyle(textColor)
      }
      if mode == .serial, showTimestamps, let timestamp = line.timestamp {
        ConsoleHighlightedText(
          text: timestamp, matches: matches.filter { $0.field == .timestamp },
          currentMatch: currentMatch
        )
        .font(.system(size: max(10, fontSize - 1), weight: .regular, design: .monospaced))
        .foregroundStyle(TekmorColor.textTertiary)
        .fixedSize()
      }
      ConsoleHighlightedText(
        text: line.text.isEmpty ? " " : line.text, matches: matches.filter { $0.field == .text },
        currentMatch: currentMatch
      )
      .font(
        .system(
          size: fontSize, weight: line.kind == .error ? .medium : .regular, design: .monospaced)
      )
      .foregroundStyle(textColor)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      if let location, let onOpenLocation {
        Button {
          onOpenLocation(location)
        } label: {
          HStack(spacing: 3) {
            Text(location.displayLabel)
              .font(.system(size: max(10.5, fontSize - 1.5), weight: .medium, design: .monospaced))
            Image(systemName: "arrow.up.forward")
              .font(.system(size: max(9, fontSize - 3), weight: .semibold))
          }
        }
        .buttonStyle(TekmorFlatActionButtonStyle(tint: textColor, compact: true))
        .fixedSize()
        .help(
          l10n.tr(
            .init(
              "help.openSourceLocation",
              defaultValue: "Open \(location.displayLabel) in editor")))
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 1.5)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    .contextMenu {
      if let location {
        if let onOpenLocation {
          Button(
            l10n.tr(
              .init("console.openSourceLocation", defaultValue: "Open \(location.displayLabel)"))
          ) {
            onOpenLocation(location)
          }
        }
        if let onRevealLocation {
          Button(
            l10n.tr(
              .init("console.revealSourceFile", defaultValue: "Reveal Source File in Finder"))
          ) {
            onRevealLocation(location)
          }
        }
        Divider()
      }
      Button(l10n.tr(.init("console.copyLine", defaultValue: "Copy Line"))) {
        onCopyLine(line.text)
      }
      Button(l10n.tr(.init("console.copyAll", defaultValue: "Copy All Output")), action: onCopyAll)
    }
  }

  private func severityLabel(for kind: ConsoleBuffer.Line.Kind) -> (title: String, symbol: String)?
  {
    switch kind {
    case .error:
      (l10n.tr(.init("console.line.error", defaultValue: "Error")), "xmark.circle.fill")
    case .warning:
      (l10n.tr(.init("console.line.warning", defaultValue: "Warning")), "exclamationmark.triangle")
    case .success:
      (l10n.tr(.init("console.line.success", defaultValue: "Success")), "checkmark.circle")
    default:
      nil
    }
  }
}
