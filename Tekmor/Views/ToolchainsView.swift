import SwiftUI
import TekmorCore

/// Flat native macOS view for global STM32CubeCLI and its managed bundles.
struct ToolchainsView: View {
  @Bindable var workspace: Workspace
  @State private var bundlesExpanded = true
  @Environment(\.l10n) private var l10n

  private var managedBundles: [CubeBundle] {
    workspace.buildBundleRows + workspace.programmerBundleRows
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        cubeSection
        bundlesSection
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(TekmorColor.workspaceBackground)
  }

  // MARK: - STM32CubeCLI Core

  private var cubeSection: some View {
    let installed = workspace.cubeVersion != nil
    let installing = workspace.isInstallingCube
    let checking = workspace.loadingCube && !installing
    let status: ToolRowStatus =
      if installing {
        .spinning(l10n.tr(.init("tools.status.installing", defaultValue: "Installing…")))
      } else if checking {
        .spinning(l10n.tr(.init("tools.status.checking", defaultValue: "Checking…")))
      } else if installed {
        .installed(l10n.tr(.init("tools.status.installed", defaultValue: "Installed")))
      } else {
        .pending(l10n.tr(.init("tools.status.pending", defaultValue: "Not Installed")))
      }

    return VStack(alignment: .leading, spacing: 0) {
      sectionHeader(title: "STM32CubeCLI")

      HairlineDivider()

      if case .custom(let message) = workspace.cubeMessageState {
        FlatCalloutStrip(
          icon: "exclamationmark.triangle.fill",
          message: message,
          accent: TekmorColor.warning,
          background: TekmorColor.warningSubtle
        )
        HairlineDivider()
      }

      FlatToolRow(
        icon: "terminal",
        iconColor: installing || checking
          ? TekmorColor.brand : (installed ? TekmorColor.success : TekmorColor.textTertiary),
        title: "STM32CubeCLI",
        version: workspace.cubeDisplayVersion,
        status: status,
        path: installed ? workspace.cubeExecutablePath : nil
      ) {
        if installed {
          Button {
            workspace.revealInFinder(URL(filePath: workspace.cubeExecutablePath))
          } label: {
            Image(systemName: "folder")
          }
          .buttonStyle(TekmorIconButtonStyle())
          .accessibilityLabel(
            l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder"))
          )
          .help(l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder")))
        } else {
          Button(l10n.tr(.init("tools.action.install", defaultValue: "Install"))) {
            workspace.start(.installCube)
          }
          .buttonStyle(.borderedProminent)
          .tint(TekmorColor.ctaBottom)
          .controlSize(.small)
          .disabled(!workspace.canStartAction || workspace.loadingCube)
        }
      }
    }
  }

  // MARK: - CubeCLI Managed Bundles

  private var bundlesSection: some View {
    let bundles = managedBundles
    let installedCount = bundles.filter(\.installed).count
    let hasMissing =
      !workspace.missingBuildBundleNames.isEmpty || workspace.missingProgrammerBundles
    let hasIssue = workspace.buildHasValidationIssue || workspace.programmerHasValidationIssue
    let canBatchAction = workspace.cubeVersion != nil && (hasMissing || hasIssue)

    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Button {
          bundlesExpanded.toggle()
        } label: {
          HStack(spacing: 5) {
            Text(l10n.tr(.init("tools.section.bundles", defaultValue: "Managed Bundles")))
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(TekmorColor.textSecondary)
            if workspace.hasCheckedCube {
              Text("\(installedCount)/\(bundles.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(TekmorColor.textTertiary)
            }
            Image(systemName: bundlesExpanded ? "chevron.down" : "chevron.right")
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(TekmorColor.textTertiary)
              .accessibilityHidden(true)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
          l10n.tr(
            bundlesExpanded
              ? .init("tools.bundles.expanded", defaultValue: "Expanded")
              : .init("tools.bundles.collapsed", defaultValue: "Collapsed")))

        Spacer()

        if canBatchAction {
          Button(
            l10n.tr(
              hasIssue && !hasMissing
                ? .init("tools.action.repair", defaultValue: "Repair")
                : .init("tools.action.installMissing", defaultValue: "Install Missing"))
          ) {
            workspace.start(.prepareAllTools)
          }
          .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.brand, compact: true))
          .disabled(!workspace.canStartAction || workspace.loadingCube)
        }
      }
      .padding(.bottom, 8)

      HairlineDivider()

      if hasIssue, let issue = workspace.buildToolsIssue ?? workspace.programmerIssue {
        FlatCalloutStrip(
          icon: "exclamationmark.triangle.fill",
          message: issue,
          accent: TekmorColor.warning,
          background: TekmorColor.warningSubtle
        )
        HairlineDivider()
      }

      if bundlesExpanded {
        ForEach(Array(bundles.enumerated()), id: \.element.id) { index, bundle in
          bundleRow(bundle)
          if index < bundles.count - 1 {
            HairlineDivider().padding(.leading, 38)
          }
        }
      }
    }
  }

  // MARK: - Bundle Row

  private func bundleRow(_ bundle: CubeBundle) -> some View {
    let info = metadata(for: bundle)
    let installing = workspace.isInstallingBundle(bundle)
    let checkingInitial = workspace.loadingCube && !workspace.hasCheckedCube
    let status: ToolRowStatus =
      if installing {
        .spinning(l10n.tr(.init("tools.status.installing", defaultValue: "Installing…")))
      } else if checkingInitial {
        .spinning(l10n.tr(.init("tools.status.checking", defaultValue: "Checking…")))
      } else if bundle.installed {
        .installed(l10n.tr(.init("tools.status.installed", defaultValue: "Installed")))
      } else {
        .pending(l10n.tr(.init("tools.status.pending", defaultValue: "Not Installed")))
      }

    let iconColor: Color =
      if installing || checkingInitial {
        TekmorColor.brand
      } else if bundle.installed {
        TekmorColor.success
      } else {
        TekmorColor.textTertiary
      }

    return FlatToolRow(
      icon: info.icon,
      iconColor: iconColor,
      title: info.title,
      version: bundle.installed && !bundle.version.isEmpty ? bundle.version : nil,
      status: status,
      path: bundle.path?.path
    ) {
      HStack(spacing: 6) {
        if bundle.installed {
          if let path = bundle.path {
            Button {
              workspace.revealInFinder(path)
            } label: {
              Image(systemName: "folder")
            }
            .buttonStyle(TekmorIconButtonStyle())
            .accessibilityLabel(
              l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder"))
            )
            .help(l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder")))
          }
        } else {
          Button(l10n.tr(.init("tools.action.install", defaultValue: "Install"))) {
            workspace.start(.installBundle(bundle.name))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(
            !workspace.canStartAction || workspace.loadingCube || workspace.cubeVersion == nil
          )
          .help(
            workspace.cubeVersion == nil
              ? l10n.tr(
                .init("tools.help.requiresCubeCLI", defaultValue: "Install STM32CubeCLI first"))
              : l10n.tr(.init("tools.action.install", defaultValue: "Install")))
        }
      }
    }
  }

  private struct BundleMetadata {
    let icon: String
    let title: String
  }

  private func metadata(for bundle: CubeBundle) -> BundleMetadata {
    switch bundle.name {
    case "cmake":
      BundleMetadata(icon: "hammer", title: "CMake")
    case "gnu-tools-for-stm32":
      BundleMetadata(
        icon: "cpu",
        title: l10n.tr(.init("tools.bundle.gcc.title", defaultValue: "ARM GCC Toolchain")))
    case "ninja":
      BundleMetadata(icon: "bolt", title: "Ninja")
    case CubeCLI.programmerBundleName:
      BundleMetadata(icon: "memorychip", title: "STM32CubeProgrammer")
    default:
      BundleMetadata(icon: "shippingbox", title: bundle.name)
    }
  }

  private func sectionHeader(title: String) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(TekmorColor.textSecondary)
      Spacer()
    }
    .padding(.bottom, 8)
  }
}

private enum ToolRowStatus {
  case installed(String)
  case pending(String)
  case spinning(String)
}

private struct FlatToolRow<Trailing: View>: View {
  let icon: String
  let iconColor: Color
  let title: String
  let version: String?
  let status: ToolRowStatus?
  let path: String?
  @ViewBuilder let trailing: () -> Trailing
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(iconColor)
        .frame(width: 20, alignment: .center)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 10) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TekmorColor.textInk)
            .lineLimit(1)

          if let version {
            Text(version)
              .font(.system(size: 11.5, design: .monospaced))
              .foregroundStyle(TekmorColor.textSecondary)
              .fixedSize()
          }
        }

        if let path {
          Text((path as NSString).abbreviatingWithTildeInPath)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(TekmorColor.textMuted)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(path)
        }
      }

      Spacer(minLength: 10)

      HStack(spacing: 12) {
        if let status {
          statusIndicator(for: status)
        }
        trailing()
      }
      .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 10)
    .background(
      hovered ? TekmorColor.hoverFill : .clear,
      in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
    )
    .onHover { hovered = $0 }
  }

  @ViewBuilder
  private func statusIndicator(for status: ToolRowStatus) -> some View {
    switch status {
    case .installed(let text):
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(TekmorColor.success)
        .help(text)
        .accessibilityLabel(text)
    case .pending(let text):
      InlineStatusIndicator(
        text: text, color: TekmorColor.textTertiary, textColor: TekmorColor.textTertiary)
    case .spinning(let text):
      InlineStatusIndicator(
        text: text, color: TekmorColor.brand, textColor: TekmorColor.brand, spinning: true)
    }
  }
}
