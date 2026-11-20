import AppKit
import SwiftUI
import TekmorCore

/// Native macOS Settings window (⌘,) organizing global appearance, console/serial defaults,
/// storage/cache management, and application information.
struct SettingsView: View {
  @Bindable var workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    TabView {
      GeneralSettingsTab(workspace: workspace)
        .tabItem {
          Label(
            l10n.tr(.init("settings.tab.general", defaultValue: "General")),
            systemImage: "gearshape")
        }

      StorageSettingsTab(workspace: workspace)
        .tabItem {
          Label(
            l10n.tr(.init("settings.tab.storage", defaultValue: "Storage")),
            systemImage: "internaldrive")
        }

      AboutSettingsTab()
        .tabItem {
          Label(
            l10n.tr(.init("settings.section.about", defaultValue: "About")),
            systemImage: "info.circle")
        }
    }
    .frame(width: 540)
    .tint(TekmorColor.brand)
  }
}

// MARK: - General & Appearance

private struct GeneralSettingsTab: View {
  @Bindable var workspace: Workspace
  @Environment(\.l10n) private var l10n

  private let fontSizes: [Double] = [11, 12.5, 13.5, 14.5, 18, 21, 25]
  private let workbenchScales: [Double] = [1, 1.25, 1.5, 2]

  var body: some View {
    Form {
      Section {
        Picker(
          l10n.tr(.init("settings.appearance", defaultValue: "Appearance")),
          selection: $workspace.appearance
        ) {
          ForEach(Workspace.AppearanceMode.allCases) { mode in
            Text(mode.title(using: l10n)).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Picker(
          l10n.tr(.init("settings.language", defaultValue: "Language")),
          selection: $workspace.language
        ) {
          Text(l10n.tr(.init("language.system", defaultValue: "Follow System"))).tag(
            AppLanguage.system)
          Text("简体中文").tag(AppLanguage.zhHans)
          Text("English").tag(AppLanguage.english)
        }
      } header: {
        Text(
          l10n.tr(
            .init("settings.section.appearanceAndLanguage", defaultValue: "Appearance & Language")))
      } footer: {
        if workspace.language != .system {
          Text(
            l10n.tr(
              .init(
                "settings.language.systemNote",
                defaultValue:
                  "System menus and file dialogs follow the app language configured in macOS System Settings."
              ))
          )
          .font(.system(size: 11))
          .foregroundStyle(TekmorColor.textSecondary)
        }
      }

      Section(l10n.tr(.init("settings.section.console", defaultValue: "Console & Serial"))) {
        Picker(
          l10n.tr(.init("settings.workbenchTextSize", defaultValue: "Workbench Text Size")),
          selection: $workspace.workbenchTextScale
        ) {
          ForEach(workbenchScales, id: \.self) { scale in
            Text(scale.formatted(.percent.locale(l10n.locale))).tag(scale)
          }
        }
        Picker(
          l10n.tr(.init("settings.consoleFontSize", defaultValue: "Monospace Font Size")),
          selection: $workspace.consoleFontSize
        ) {
          ForEach(fontSizes, id: \.self) { size in
            Text(
              l10n.tr(
                .init(
                  "settings.fontSize.points",
                  defaultValue: "\(size.formatted(.number.locale(l10n.locale))) pt"))
            ).tag(size)
          }
        }
        Toggle(
          l10n.tr(
            .init(
              "settings.defaultFollowOutput",
              defaultValue: "Follow latest log and serial output by default")),
          isOn: $workspace.defaultFollowOutput)
        Toggle(
          l10n.tr(
            .init(
              "settings.showTimestamps",
              defaultValue: "Show timestamps when listening to serial output by default")),
          isOn: $workspace.showTimestamps)
      }

      Section(l10n.tr(.init("settings.section.projectDefaults", defaultValue: "Project Defaults")))
      {
        Picker(
          l10n.tr(.init("settings.defaultFlashMethod", defaultValue: "Default Flash Method")),
          selection: $workspace.defaultFlashMethod
        ) {
          ForEach(FlashMethod.allCases) { method in
            Text(method.title).tag(method)
          }
        }
        Picker(
          l10n.tr(.init("settings.defaultBaudRate", defaultValue: "Default Serial Baud Rate")),
          selection: $workspace.defaultBaudRate
        ) {
          ForEach(SerialSettings.baudRates, id: \.self) { rate in
            Text("\(rate) bps").tag(rate)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: 480)
  }
}

// MARK: - Storage & Build Cache

private struct StorageSettingsTab: View {
  @Bindable var workspace: Workspace
  @State private var cacheBytes: Int64?
  @State private var measuring = false
  @Environment(\.l10n) private var l10n

  var body: some View {
    Form {
      Section(
        l10n.tr(
          .init("settings.section.applicationTools", defaultValue: "CubeCLI Installation Directory")
        )
      ) {
        VStack(alignment: .leading, spacing: 8) {
          Text(workspace.toolDirectory.path)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(TekmorColor.textSecondary)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)

          HStack(spacing: 8) {
            Button(
              l10n.tr(.init("action.changeDirectory", defaultValue: "Change…")),
              action: workspace.chooseToolDirectory
            )
            .disabled(!workspace.canStartAction)
            Button(
              l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder")),
              action: workspace.revealCubeDirectory)
            if !workspace.isDefaultToolDirectory {
              Spacer()
              Button(
                l10n.tr(.init("action.resetDefault", defaultValue: "Reset Default")),
                action: workspace.resetToolDirectory
              )
              .disabled(!workspace.canStartAction)
            }
          }
          .controlSize(.small)
        }
        .padding(.vertical, 2)
      }

      Section(l10n.tr(.init("settings.section.buildCache", defaultValue: "CMake Build Cache"))) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(CMakeBuild.defaultCache.path)
              .font(.system(size: 11.5, design: .monospaced))
              .foregroundStyle(TekmorColor.textSecondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
            Spacer()
            if measuring {
              MiniActivitySpinner(size: 11, tint: TekmorColor.textSecondary)
            } else if let cacheBytes {
              Text(workspace.formatBytes64(cacheBytes))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(TekmorColor.primaryTonal)
            }
          }

          HStack(spacing: 8) {
            Button(
              l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder")),
              action: workspace.revealBuildCache)
            Spacer()
            Button(
              l10n.tr(.init("action.clearBuildCache", defaultValue: "Clear Build Cache")),
              role: .destructive
            ) {
              workspace.clearBuildCache()
              Task { await refreshCacheSize() }
            }
            .disabled(!workspace.canStartAction || (cacheBytes ?? 0) == 0)
          }
          .controlSize(.small)
        }
        .padding(.vertical, 2)
      }
    }
    .formStyle(.grouped)
    .frame(height: 340)
    .task {
      await refreshCacheSize()
    }
  }

  private func refreshCacheSize() async {
    measuring = true
    cacheBytes = await workspace.measureBuildCacheBytes()
    measuring = false
  }
}

// MARK: - About

private struct AboutSettingsTab: View {
  @Environment(\.l10n) private var l10n

  var body: some View {
    Form {
      Section(l10n.tr(.init("settings.section.about", defaultValue: "About"))) {
        HStack(spacing: 10) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 28, height: 28)
          VStack(alignment: .leading, spacing: 1) {
            Text(
              "Tekmor \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")"
            )
            .font(.system(size: 12.5, weight: .semibold))
            Text("STM32 · UART / SWD")
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(TekmorColor.textSecondary)
          }
          Spacer()
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: 390)
  }
}
