import SwiftUI
import TekmorCore

struct ProjectInspectorView: View {
  let workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if workspace.project != nil {
          projectSection
          HairlineDivider()
        }
        if workspace.project != nil && workspace.configuration.cmake.configurePreset == nil {
          toolchainSection
          HairlineDivider()
        }

        if let artifact = workspace.lastArtifact {
          artifactSection(artifact)
        } else {
          VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
              l10n.tr(.init("inspector.recentArtifact", defaultValue: "Latest Firmware Artifact")))
            Text(
              l10n.tr(
                .init(
                  "inspector.firmwareEmpty",
                  defaultValue: "Firmware details appear here after building or choosing a file."))
            )
            .font(.system(size: 11.5))
            .foregroundStyle(TekmorColor.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
        }
      }
    }
    .background(TekmorColor.chromeBackground)
  }

  private var projectSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle(l10n.tr(.init("inspector.projectSettings", defaultValue: "Project Settings")))
      TextField(
        l10n.tr(
          .init("inspector.expectedMCUPrompt", defaultValue: "Expected STM32 MCU (optional)")),
        text: Binding(
          get: { workspace.configuration.mcu ?? "" },
          set: { value in
            let model = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            workspace.configuration.mcu = model.isEmpty ? nil : model
          }
        )
      )
      .font(.system(size: 11.5))
      .disabled(!workspace.canStartAction)
      if let generator = workspace.buildGenerator {
        LabeledContent(
          l10n.tr(.init("inspector.generator", defaultValue: "Generator")), value: generator
        )
        .font(.system(size: 11.5))
        .foregroundStyle(TekmorColor.textSecondary)
      }
      if let description = workspace.buildToolsDescription {
        Text(description)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(TekmorColor.textSecondary)
          .textSelection(.enabled)
      }
    }
    .padding(14)
  }

  private var toolchainSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle(l10n.tr(.init("inspector.toolchainFile", defaultValue: "CMake Toolchain File")))
      Button(action: workspace.chooseCMakeToolchain) {
        HStack {
          Text(
            workspace.configuration.cmake.toolchainFile
              ?? l10n.tr(
                .init(
                  "inspector.selectToolchainPlaceholder",
                  defaultValue: "Select a .cmake file in the project…"))
          )
          .lineLimit(1)
          .truncationMode(.middle)
          Spacer(minLength: 4)
          Image(systemName: "ellipsis")
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(!workspace.canStartAction)
      .help(
        workspace.configuration.cmake.toolchainFile
          ?? l10n.tr(
            .init(
              "inspector.selectToolchainHelp",
              defaultValue: "Choose a toolchain file for projects without CMake presets")))
    }
    .padding(14)
  }

  private func artifactSection(_ artifact: URL) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        sectionTitle(
          l10n.tr(.init("inspector.recentArtifact", defaultValue: "Latest Firmware Artifact")))
        Spacer()
        Button(action: workspace.revealArtifact) {
          Image(systemName: "folder")
        }
        .buttonStyle(TekmorIconButtonStyle())
        .help(
          l10n.tr(
            .init(
              "help.revealFileInFinder",
              defaultValue: "Reveal \(artifact.lastPathComponent) in Finder")))
      }

      Text(artifact.lastPathComponent)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(TekmorColor.textInk)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)

      if let byteCount = workspace.firmwareByteCount {
        LabeledContent(
          l10n.tr(.init("inspector.firmwareData", defaultValue: "Firmware Data")),
          value: workspace.formatBytes(byteCount)
        )
        .font(.system(size: 11.5))
        .foregroundStyle(TekmorColor.textSecondary)
      }

      if !workspace.firmwareRanges.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          sectionTitle(l10n.tr(.init("inspector.loadAddresses", defaultValue: "Load Addresses")))
          ForEach(workspace.firmwareRanges, id: \.self) { range in
            Text(FirmwareImage.addressLabel(range))
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(TekmorColor.textSecondary)
              .textSelection(.enabled)
          }
        }
      }

      if let usage = workspace.lastFirmwareUsage {
        VStack(alignment: .leading, spacing: 5) {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(TekmorColor.chromeSubtle)
              Capsule()
                .fill(usage.utilization > 0.85 ? TekmorColor.warning : TekmorColor.brand)
                .frame(width: max(4, geo.size.width * usage.utilization))
            }
          }
          .frame(height: 4.5)

          HStack {
            Text(
              "\(workspace.formatBytes(usage.flashBytes)) / \(workspace.formatBytes(usage.flashCapacity))"
            )
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(TekmorColor.textPrimary)
            Spacer()
            Text(
              usage.utilization.formatted(
                .percent.precision(.fractionLength(1)).locale(workspace.locale))
            )
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(TekmorColor.textSecondary)
          }
        }
      }

    }
    .padding(14)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(TekmorColor.textSecondary)
  }
}
