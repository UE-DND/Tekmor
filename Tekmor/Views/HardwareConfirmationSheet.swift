import SwiftUI
import TekmorCore

struct HardwareConfirmationSheet: View {
  let workspace: Workspace
  let confirmation: Workspace.HardwareConfirmation
  @State private var address = ""
  @State private var readAttempt = 0
  @Environment(\.l10n) private var l10n

  private var value: UInt64? {
    let input = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let digits = input.hasPrefix("0x") ? input.dropFirst(2) : input[...]
    guard !digits.isEmpty, digits.count <= 8 else { return nil }
    return UInt64(digits, radix: 16)
  }

  private var isErase: Bool {
    if case .erase = confirmation.action { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        l10n.tr(
          isErase
            ? .init("sheet.erase.title", defaultValue: "Erase Internal Flash?")
            : .init("action.flashFirmware", defaultValue: "Flash Firmware"))
      )
      .font(.headline)

      if case .flash(let file) = confirmation.action {
        Text(file.lastPathComponent)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
      }
      if let target = confirmation.connection {
        LabeledContent(
          l10n.tr(.init("sheet.hardware.target", defaultValue: "Target")),
          value: workspace.targetLabel(target))
        if let chip = workspace.identifiedHardwareChip {
          Text(chip.details)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if case .failure(let error) = workspace.hardwareTargetRead {
          Text(error.localizedDescription)
            .foregroundStyle(.secondary)
          Button(l10n.tr(.init("devices.action.readChip", defaultValue: "Read Chip Info"))) {
            readAttempt += 1
          }
          .disabled(workspace.programmerIssue != nil)
        } else {
          ProgressView(
            l10n.tr(.init("status.readingChip", defaultValue: "Reading target chip"))
          )
          .controlSize(.small)
        }
      } else if let issue = workspace.flashSelectionIssue {
        Text(issue).foregroundStyle(.secondary)
      }
      if let issue = workspace.programmerIssue {
        Text(issue).foregroundStyle(.secondary)
      }

      if isErase {
        Text(
          l10n.tr(
            .init(
              "sheet.erase.description",
              defaultValue:
                "This erases all firmware and stored data in the target's internal Flash.")))
      }
      if confirmation.binary {
        TextField(
          l10n.tr(
            .init("sheet.binary.placeholder", defaultValue: "Hex start address, e.g. 0x08000000")),
          text: $address
        )
        .font(.system(.body, design: .monospaced))
      }

      HStack {
        Spacer()
        Button(l10n.tr(.init("action.cancel", defaultValue: "Cancel"))) {
          workspace.hardwareConfirmation = nil
        }
        .keyboardShortcut(.cancelAction)
        if isErase {
          Button(
            l10n.tr(.init("action.eraseFlash", defaultValue: "Erase Flash")), role: .destructive
          ) {
            workspace.confirmHardwareAction(address: nil)
          }
          .disabled(workspace.identifiedHardwareChip == nil || workspace.programmerIssue != nil)
        } else {
          Button(l10n.tr(.init("action.flashFirmware", defaultValue: "Flash Firmware"))) {
            workspace.confirmHardwareAction(address: value)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(
            workspace.identifiedHardwareChip == nil || workspace.programmerIssue != nil
              || (confirmation.binary && value == nil))
        }
      }
    }
    .padding(20)
    .frame(width: 420)
    .task(id: readAttempt) { await workspace.identifyHardwareTarget(confirmation) }
  }
}

struct TargetOperationButtons: View {
  let workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    Button(l10n.tr(.init("action.resetTarget", defaultValue: "Reset Target"))) {
      workspace.start(.resetTarget)
    }
    .disabled(!workspace.canResetTarget)
    Button(
      l10n.tr(.init("action.eraseFlashEllipsis", defaultValue: "Erase Flash…")),
      action: workspace.requestEraseFlash
    )
    .disabled(!workspace.canEraseFlash)
  }
}
