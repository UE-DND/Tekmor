import SwiftUI
import TekmorCore

/// Flat native macOS resource list for connected USB Serial devices and ST-LINK probes.
/// Zero floating cards, zero icon boxes, zero pill clutter.
struct DevicesView: View {
  @Bindable var workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        serialDevicesSection
        stlinkProbesSection
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(TekmorColor.workspaceBackground)
  }

  private var serialDevicesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader(
        title: l10n.tr(.init("devices.section.usbSerial", defaultValue: "USB Serial Ports")),
        count: workspace.devices.count
      )

      HairlineDivider()

      if workspace.devices.isEmpty {
        emptyRow(
          icon: "cable.connector.slash",
          text: l10n.tr(
            .init(
              "devices.empty.serialGeneric",
              defaultValue:
                "No USB serial devices detected. Connect a USB-to-serial adapter with voltage levels suitable for your board."
            ))
        )
      } else {
        ForEach(Array(workspace.devices.enumerated()), id: \.element.id) { index, device in
          let isSelected = workspace.selectedSerial?.id == device.id
          let isMonitoring = isSelected && workspace.serialConnected
          FlatDeviceRow(
            icon: "cable.connector",
            iconColor: isMonitoring
              ? TekmorColor.success : (isSelected ? TekmorColor.brand : TekmorColor.textSecondary),
            title: device.label,
            subtitle: device.id,
            connectionID: device.registryID,
            reading: workspace.chipReadings[device.registryID],
            workspace: workspace,
            statusText: l10n.tr(
              isMonitoring
                ? .init("devices.status.monitoring", defaultValue: "Listening")
                : .init("serial.disconnected", defaultValue: "Not Listening")),
            statusColor: isMonitoring ? TekmorColor.success : TekmorColor.brand
          ) {
            HStack(spacing: 8) {
              readButton(.uart(device))
              if !isSelected {
                Button(
                  l10n.tr(.init("devices.action.useForMonitor", defaultValue: "Use for Listening"))
                ) {
                  workspace.setSerialPath(device.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!workspace.canSelectMonitorPort)
              }
              Button(
                l10n.tr(
                  isMonitoring
                    ? .init("action.disconnect", defaultValue: "Stop Listening")
                    : .init("devices.action.openMonitor", defaultValue: "Listen"))
              ) {
                if isMonitoring {
                  workspace.toggleSerial()
                } else {
                  workspace.selectDeviceAndMonitor(device)
                }
              }
              .buttonStyle(.borderedProminent)
              .tint(TekmorColor.ctaBottom)
              .controlSize(.small)
              .disabled(!workspace.canSelectMonitorPort)
              Button(l10n.tr(.init("pane.serial", defaultValue: "Serial Monitor"))) {
                workspace.showSerialMonitor()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }

          if index < workspace.devices.count - 1 {
            HairlineDivider().padding(.leading, 38)
          }
        }
      }
    }
  }

  private var stlinkProbesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader(
        title: l10n.tr(.init("devices.section.stlink", defaultValue: "ST-LINK Probes")),
        count: workspace.probes.count
      )

      HairlineDivider()

      if workspace.probes.count > 1
        && workspace.probes.contains(where: { !workspace.canIdentify($0) })
      {
        FlatCalloutStrip(
          icon: "exclamationmark.triangle.fill",
          message: l10n.tr(
            .init(
              "devices.warning.multipleProbes",
              defaultValue:
                "Multiple ST-LINK probes detected. Keep only the target probe connected before SWD flashing."
            )),
          accent: TekmorColor.warning,
          background: TekmorColor.warningSubtle
        )
        HairlineDivider()
      }

      if workspace.probes.isEmpty {
        emptyRow(
          icon: "bolt.slash",
          text: l10n.tr(
            .init(
              "devices.empty.stlink",
              defaultValue: "No ST-LINK debug probes detected (required for SWD flashing only)."))
        )
      } else {
        ForEach(Array(workspace.probes.enumerated()), id: \.element.id) { index, probe in
          let ready = workspace.canIdentify(probe)
          let selected = workspace.flashProbe?.id == probe.id
          let reading = workspace.chipReadings[probe.id]
          FlatDeviceRow(
            icon: "bolt.fill",
            iconColor: ready ? TekmorColor.success : TekmorColor.warning,
            title: probe.label,
            subtitle: reading?.chip?.probeSerialNumber ?? probe.serialNumber
              ?? String(format: "Registry ID · 0x%llX", probe.id),
            connectionID: probe.id,
            reading: reading,
            workspace: workspace,
            statusText: selected
              ? l10n.tr(.init("devices.status.selectedProbe", defaultValue: "Selected"))
              : (ready
                ? nil
                : l10n.tr(
                  .init("devices.status.ambiguousProbe", defaultValue: "Cannot Distinguish"))),
            statusColor: ready ? TekmorColor.success : TekmorColor.warning
          ) {
            HStack(spacing: 8) {
              readButton(.swd(probe))
              if !selected {
                Button(l10n.tr(.init("devices.action.selectProbe", defaultValue: "Select Probe"))) {
                  workspace.selectProbe(probe)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!workspace.canStartAction || !ready)
              }
            }
          }

          if index < workspace.probes.count - 1 {
            HairlineDivider().padding(.leading, 38)
          }
        }
      }
    }
  }

  private func readButton(_ connection: ChipConnection) -> some View {
    let hasReadChip = workspace.chipReadings[connection.id]?.chip != nil
    let title = l10n.tr(
      hasReadChip
        ? .init("devices.action.rereadChip", defaultValue: "Re-read Chip Info")
        : .init("devices.action.readChip", defaultValue: "Read Chip Info"))
    return HStack(spacing: 8) {
      if workspace.programmerIssue != nil
        || workspace.chipReadings[connection.id]?.needsTool == true
      {
        Button(l10n.tr(.init("devices.action.openTools", defaultValue: "Open Tools"))) {
          workspace.selectSidebarItem(.tools)
        }
        .buttonStyle(.plain)
        .foregroundStyle(TekmorColor.brand)
      }
      Button(title) {
        workspace.readChip(connection)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(!workspace.canReadChip(connection) || workspace.programmerIssue != nil)
      .help(workspace.programmerIssue ?? title)
    }
  }

  private func sectionHeader(title: String, count: Int) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(TekmorColor.textSecondary)
      if count > 0 {
        Text("\(count)")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(TekmorColor.textTertiary)
      }
      Spacer()
    }
    .padding(.bottom, 8)
  }

  private func emptyRow(icon: String, text: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 13))
        .foregroundStyle(TekmorColor.textTertiary)
        .frame(width: 20, alignment: .center)
      Text(text)
        .font(.system(size: 12.5))
        .foregroundStyle(TekmorColor.textSecondary)
      Spacer()
    }
    .padding(.vertical, 14)
  }
}

private struct FlatDeviceRow<Trailing: View>: View {
  let icon: String
  let iconColor: Color
  let title: String
  let subtitle: String
  let connectionID: UInt64
  let reading: ChipReadStatus?
  let workspace: Workspace
  let statusText: String?
  let statusColor: Color
  @ViewBuilder let trailing: () -> Trailing
  @State private var hovered = false
  @Environment(\.l10n) private var l10n

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(iconColor)
        .frame(width: 20, alignment: .center)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 10) {
          Text(title)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(TekmorColor.textInk)

          if let statusText {
            InlineStatusIndicator(
              text: statusText,
              color: statusColor,
              textColor: statusColor
            )
          }
        }

        Text(subtitle)
          .font(.system(size: 11.5, design: .monospaced))
          .foregroundStyle(TekmorColor.textTertiary)
          .lineLimit(1)
          .truncationMode(.middle)
        if let reading {
          switch reading {
          case .reading:
            Text(l10n.tr(.init("devices.readingChip", defaultValue: "Reading chip information…")))
              .foregroundStyle(TekmorColor.brand)
          case .ready(let chip):
            Text(
              chip.title + " · " + chip.details
                + (chip.flashBytes == nil
                  ? " · "
                    + l10n.tr(
                      .init("devices.unknownFlashCapacity", defaultValue: "Flash size unknown"))
                  : "")
            )
            .foregroundStyle(TekmorColor.textSecondary)
            .textSelection(.enabled)
          case .needsTool(let message), .failed(let message):
            Text(workspace.chipMessage(for: connectionID, fallback: message))
              .foregroundStyle(TekmorColor.textSecondary)
          }
        }
      }
      .font(.system(size: 11.5))

      Spacer(minLength: 10)

      trailing()
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 11)
    .background(
      hovered ? TekmorColor.hoverFill : .clear,
      in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
    )
    .onHover { hovered = $0 }
  }
}
