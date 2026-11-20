import SwiftUI
import TekmorCore

struct BinaryFlashSheet: View {
  let workspace: Workspace
  @State private var address = ""
  @Environment(\.l10n) private var l10n

  private var value: UInt64? {
    let input = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let digits = input.hasPrefix("0x") ? input.dropFirst(2) : input[...]
    guard !digits.isEmpty, digits.count <= 8 else { return nil }
    return UInt64(digits, radix: 16)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(l10n.tr(.init("sheet.binary.title", defaultValue: "BIN Flash Address"))).font(.headline)
      Text(workspace.binaryFirmware?.lastPathComponent ?? "")
        .foregroundStyle(.secondary)
      TextField(
        l10n.tr(
          .init("sheet.binary.placeholder", defaultValue: "Hex start address, e.g. 0x08000000")),
        text: $address
      )
      .font(.system(.body, design: .monospaced))
      HStack {
        Spacer()
        Button(l10n.tr(.init("action.cancel", defaultValue: "Cancel"))) {
          workspace.binaryFirmware = nil
        }
        .keyboardShortcut(.cancelAction)
        Button(l10n.tr(.init("action.continue", defaultValue: "Continue"))) {
          if let value { workspace.flashBinary(at: value) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(value == nil)
      }
    }
    .padding(20)
    .frame(width: 420)
  }
}
