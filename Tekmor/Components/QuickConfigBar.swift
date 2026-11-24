import SwiftUI
import TekmorCore

struct QuickConfigBar<Trailing: View>: View {
  let workspace: Workspace
  @ViewBuilder var trailing: () -> Trailing
  @Environment(\.l10n) private var l10n

  init(workspace: Workspace, @ViewBuilder trailing: @escaping () -> Trailing) {
    self.workspace = workspace
    self.trailing = trailing
  }

  var body: some View {
    HStack(spacing: 8) {
      ViewThatFits(in: .horizontal) {
        fullControls
          .fixedSize(horizontal: true, vertical: false)
        compactControls
      }
      .disabled(workspace.running)

      Spacer(minLength: 4)

      trailing()
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 12)
    .padding(.vertical, 3)
    .frame(minHeight: 32)
    .background(TekmorColor.configBarBackground, ignoresSafeAreaEdges: [])
    .overlay(alignment: .bottom) { HairlineDivider() }
  }

  private var fullControls: some View {
    HStack(spacing: 4) {
      if workspace.project != nil {
        PresetInlineMenu(workspace: workspace)
        TargetInlineMenu(workspace: workspace)
        VerticalHairline(height: 12)
          .padding(.horizontal, 2)
      }
      FlashMethodInlineMenu(workspace: workspace)

      if workspace.configuration.flash == .swd {
        swdProbeStatus
      } else {
        SerialDeviceInlineMenu(workspace: workspace, forFlashing: true, maxValueWidth: 168)
      }
    }
  }

  private var compactControls: some View {
    VStack(alignment: .leading, spacing: 4) {
      Menu {
        if workspace.project != nil {
          PresetInlineMenu(workspace: workspace, inOverflow: true)
          TargetInlineMenu(workspace: workspace, inOverflow: true)
        }
        FlashMethodInlineMenu(workspace: workspace, inOverflow: true)
        if workspace.configuration.flash == .swd {
          if let probe = workspace.flashProbe {
            Text(
              l10n.tr(.init("quickbar.probeDetected", defaultValue: "\(probe.label) Detected")))
          }
          Button(l10n.tr(.init("help.openDevices", defaultValue: "Open Devices"))) {
            workspace.selectSidebarItem(.devices)
          }
        }
        if workspace.configuration.flash == .uart {
          SerialDeviceInlineMenu(workspace: workspace, forFlashing: true, inOverflow: true)
        }
      } label: {
        Label(
          l10n.tr(.init("quickbar.configuration", defaultValue: "Project Configuration")),
          systemImage: "slider.horizontal.3"
        )
        .labelStyle(.iconOnly)
      }
      .fixedSize()

      if let issue = workspace.flashHardwareIssue {
        Text(issue)
          .font(.caption)
          .foregroundStyle(TekmorColor.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var swdProbeStatus: some View {
    if let issue = workspace.probeIssue {
      Button {
        workspace.selectSidebarItem(.devices)
      } label: {
        Label(issue, systemImage: "exclamationmark.triangle").lineLimit(1)
      }
      .buttonStyle(TekmorFlatActionButtonStyle(tint: TekmorColor.warning, compact: true))
      .help(l10n.tr(.init("help.openDevices", defaultValue: "Open Devices")))
    } else if let probe = workspace.flashProbe {
      InlineStatusIndicator(
        text: l10n.tr(.init("quickbar.probeDetected", defaultValue: "\(probe.label) Detected")),
        color: TekmorColor.success
      )
      .help(
        l10n.tr(.init("help.swdProbe", defaultValue: "Probe currently selected for SWD flashing")))
    }
  }

}

// MARK: - Inline Menus

struct PresetInlineMenu: View {
  let workspace: Workspace
  var inOverflow = false
  @Environment(\.l10n) private var l10n

  var body: some View {
    Menu {
      Picker(
        l10n.tr(.init("quickbar.preset.picker", defaultValue: "Configure Preset")),
        selection: Binding(
          get: { workspace.configuration.cmake.configurePreset },
          set: workspace.setConfigurePreset
        )
      ) {
        Text(l10n.tr(.init("quickbar.preset.useToolchain", defaultValue: "Use Toolchain File")))
          .tag(String?.none)
        ForEach(workspace.presets, id: \.self) { preset in
          Text(preset).tag(Optional(preset))
        }
      }
      .pickerStyle(.inline)

      if workspace.configuration.cmake.configurePreset == nil {
        Divider()
        Button(
          l10n.tr(
            .init("quickbar.preset.toolchainSettings", defaultValue: "Toolchain File Settings…"))
        ) { workspace.showInspector = true }
      }
    } label: {
      if inOverflow {
        Text(l10n.tr(.init("quickbar.preset.picker", defaultValue: "Configure Preset")))
      } else {
        InlineMenuTrigger(
          label: l10n.tr(.init("quickbar.preset.label", defaultValue: "Preset")),
          value: workspace.configuration.cmake.configurePreset
            ?? (workspace.configuration.cmake.toolchainFile.map {
              URL(filePath: $0).lastPathComponent
            } ?? l10n.tr(.init("quickbar.preset.chooseToolchain", defaultValue: "Select Toolchain")))
        )
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(l10n.tr(.init("help.preset", defaultValue: "CMake configure preset or toolchain file")))
  }
}

struct TargetInlineMenu: View {
  @Bindable var workspace: Workspace
  var inOverflow = false
  @Environment(\.l10n) private var l10n

  var body: some View {
    let missing = workspace.configuration.cmake.target == nil
    Menu {
      if workspace.targets.isEmpty {
        Text(
          l10n.tr(
            workspace.discoveringTargets
              ? .init("quickbar.target.discovering", defaultValue: "Discovering targets…")
              : .init("quickbar.target.notLoaded", defaultValue: "Targets not loaded")))
      } else {
        Picker(
          l10n.tr(.init("quickbar.target.picker", defaultValue: "Firmware Target")),
          selection: $workspace.configuration.cmake.target
        ) {
          if missing {
            Text(l10n.tr(.init("quickbar.target.unselected", defaultValue: "No Target Selected")))
              .tag(String?.none)
          }
          ForEach(workspace.targets, id: \.self) { target in
            Text(target).tag(Optional(target))
          }
        }
        .pickerStyle(.inline)
      }
      Divider()
      Button {
        workspace.start(.inspect)
      } label: {
        Label(
          l10n.tr(.init("quickbar.target.reload", defaultValue: "Reload Executable Targets")),
          systemImage: "arrow.clockwise")
      }
      .disabled(!workspace.canConfigureProject)

      if workspace.buildToolsIssue != nil {
        Button {
          workspace.selectSidebarItem(.tools)
        } label: {
          Label(
            l10n.tr(.init("action.openTools", defaultValue: "Open Tools")),
            systemImage: "shippingbox")
        }
      }
    } label: {
      if inOverflow {
        Text(l10n.tr(.init("quickbar.target.picker", defaultValue: "Firmware Target")))
      } else {
        InlineMenuTrigger(
          label: l10n.tr(.init("quickbar.target.label", defaultValue: "Target")),
          value: workspace.configuration.cmake.target
            ?? l10n.tr(.init("quickbar.target.select", defaultValue: "Select Target")),
          valueColor: missing ? TekmorColor.warning : TekmorColor.textInk,
          dotColor: missing ? TekmorColor.warning : nil
        )
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(l10n.tr(.init("help.target", defaultValue: "Firmware build target")))
  }
}

struct FlashMethodInlineMenu: View {
  @Bindable var workspace: Workspace
  var inOverflow = false
  @Environment(\.l10n) private var l10n

  var body: some View {
    let isSWD = workspace.configuration.flash == .swd
    Menu {
      Picker(
        l10n.tr(.init("quickbar.flash.picker", defaultValue: "Flash Method")),
        selection: $workspace.configuration.flash
      ) {
        ForEach(FlashMethod.allCases) { method in
          Text(method.title).tag(method)
        }
      }
      .pickerStyle(.inline)
    } label: {
      if inOverflow {
        Text(l10n.tr(.init("quickbar.flash.picker", defaultValue: "Flash Method")))
      } else {
        InlineMenuTrigger(
          label: l10n.tr(.init("quickbar.flash.label", defaultValue: "Flash")),
          value: isSWD ? "SWD" : "UART"
        )
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(isSWD ? "ST-LINK / SWD" : "UART Bootloader")
  }
}

struct SerialDeviceInlineMenu: View {
  let workspace: Workspace
  var compact = false
  var forFlashing = false
  var inOverflow = false
  var maxValueWidth: CGFloat? = nil
  @Environment(\.l10n) private var l10n

  private var device: SerialDevice? {
    forFlashing ? workspace.selectedFlashSerial : workspace.selectedSerial
  }

  private var title: String {
    l10n.tr(
      forFlashing
        ? .init("quickbar.flashPortPicker", defaultValue: "UART Flash Port")
        : .init("quickbar.serial.picker", defaultValue: "Listening Port"))
  }

  var body: some View {
    Menu {
      if workspace.devices.isEmpty {
        Text(
          l10n.tr(.init("quickbar.serial.empty", defaultValue: "No USB serial ports detected")))
      }
      Picker(
        title,
        selection: Binding(
          get: { forFlashing ? workspace.flashSerialPath : workspace.serialPath },
          set: { path in
            if forFlashing {
              workspace.setFlashSerialPath(path)
            } else {
              workspace.setSerialPath(path)
            }
          }
        )
      ) {
        Text(l10n.tr(.init("quickbar.serial.none", defaultValue: "No Port Selected"))).tag(
          String?.none)
        ForEach(workspace.devices) { device in
          Text(device.label).tag(Optional(device.id))
        }
      }
      .pickerStyle(.inline)

      Divider()
      Button {
        workspace.refreshDevices()
      } label: {
        Label(
          l10n.tr(.init("quickbar.serial.refresh", defaultValue: "Refresh Serial Ports")),
          systemImage: "arrow.clockwise")
      }
      Button {
        workspace.selectSidebarItem(.devices)
      } label: {
        Label(
          l10n.tr(.init("help.openDevices", defaultValue: "Open Devices")),
          systemImage: "cable.connector")
      }
    } label: {
      if inOverflow {
        Text(title)
      } else if compact {
        Image(systemName: "cable.connector")
          .foregroundStyle(device == nil ? TekmorColor.warning : TekmorColor.textSecondary)
          .frame(width: 20, height: 22)
          .accessibilityLabel(title)
      } else {
        InlineMenuTrigger(
          label: nil,
          value: device?.label
            ?? l10n.tr(.init("quickbar.serial.select", defaultValue: "Select Port")),
          valueColor: device == nil ? TekmorColor.warning : TekmorColor.textInk,
          leadingIcon: "cable.connector",
          leadingIconColor: device == nil ? TekmorColor.warning : TekmorColor.textTertiary,
          monospaced: device != nil,
          maxValueWidth: maxValueWidth,
          accessibilityTitle: title
        )
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityIdentifier(forFlashing ? "serial.flashPort" : "serial.listeningPort")
    .help(
      (forFlashing ? workspace.flashHardwareIssue : workspace.serialSelectionIssue)
        ?? l10n.tr(
          forFlashing
            ? .init("help.selectFlashSerial", defaultValue: "Select serial port for UART flashing")
            : .init("help.selectMonitorSerial", defaultValue: "Select serial port for listening")))
  }
}

struct SerialFramingInlineMenu: View {
  @Bindable var workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    Menu {
      Picker(
        l10n.tr(.init("quickbar.framing.baud", defaultValue: "Baud Rate")),
        selection: $workspace.configuration.serial.baud
      ) {
        ForEach(SerialSettings.baudRates, id: \.self) { rate in
          Text("\(rate)").tag(rate)
        }
      }
      .pickerStyle(.menu)

      Picker(
        l10n.tr(.init("quickbar.framing.parity", defaultValue: "Parity")),
        selection: $workspace.configuration.serial.parity
      ) {
        Text(l10n.tr(.init("quickbar.framing.parityNone", defaultValue: "None (N)"))).tag(
          SerialSettings.Parity.none)
        Text(l10n.tr(.init("quickbar.framing.parityEven", defaultValue: "Even (E)"))).tag(
          SerialSettings.Parity.even)
        Text(l10n.tr(.init("quickbar.framing.parityOdd", defaultValue: "Odd (O)"))).tag(
          SerialSettings.Parity.odd)
      }
      .pickerStyle(.menu)

      Picker(
        l10n.tr(.init("quickbar.framing.stopBits", defaultValue: "Stop Bits")),
        selection: $workspace.configuration.serial.stopBits
      ) {
        Text(l10n.tr(.init("quickbar.framing.stopBits1", defaultValue: "1 bit"))).tag(1)
        Text(l10n.tr(.init("quickbar.framing.stopBits2", defaultValue: "2 bits"))).tag(2)
      }
      .pickerStyle(.menu)
    } label: {
      InlineMenuTrigger(
        label: nil,
        value: workspace.serialFramingSummary,
        valueColor: TekmorColor.textSecondary,
        monospaced: true
      )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(
      l10n.tr(
        workspace.serialConnected
          ? .init(
            "help.framingConnected", defaultValue: "Stop listening to change port settings")
          : .init(
            "help.framingDisconnected", defaultValue: "Listening baud rate, parity, and stop bits"))
    )
  }
}

// MARK: - Borderless Trigger Appearance

private struct InlineMenuTrigger: View {
  let label: String?
  let value: String
  var valueColor: Color = TekmorColor.textInk
  var dotColor: Color? = nil
  var leadingIcon: String? = nil
  var leadingIconColor: Color = TekmorColor.textTertiary
  var monospaced: Bool = false
  var maxValueWidth: CGFloat? = nil
  var accessibilityTitle: String? = nil

  @State private var hovered = false
  @Environment(\.l10n) private var l10n
  @Environment(\.workbenchTextScale) private var textScale

  var body: some View {
    HStack(spacing: 4.5) {
      if let dotColor {
        Circle()
          .fill(dotColor)
          .frame(width: 5.5, height: 5.5)
      }
      if let leadingIcon {
        Image(systemName: leadingIcon)
          .font(.system(size: 11 * textScale, weight: .medium))
          .foregroundStyle(leadingIconColor)
      }
      if let label {
        Text(label)
          .font(.system(size: 12 * textScale))
          .foregroundStyle(TekmorColor.textTertiary)
      }
      Text(value)
        .font(
          monospaced
            ? .system(size: 12 * textScale, weight: .medium, design: .monospaced)
            : .system(size: 12 * textScale, weight: .medium)
        )
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: maxValueWidth, alignment: .leading)
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 7.5, weight: .semibold))
        .foregroundStyle(TekmorColor.textTertiary)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3.5)
    .background(
      hovered ? TekmorColor.hoverFill : .clear,
      in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
    )
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      accessibilityTitle ?? label
        ?? l10n.tr(.init("accessibility.serialParams", defaultValue: "Serial parameters"))
    )
    .accessibilityValue(value)
  }
}
