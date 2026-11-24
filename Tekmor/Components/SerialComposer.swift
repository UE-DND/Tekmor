import AppKit
import SwiftUI
import TekmorCore

struct SerialComposer: View {
  @Bindable var workspace: Workspace
  @Environment(\.l10n) private var l10n

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) {
        receiveFormat
        sendFormat
        lineEnding
        commandField
        sendButton
      }
      VStack(spacing: 4) {
        HStack(spacing: 6) {
          receiveFormat
          Spacer(minLength: 0)
          sendFormat
          lineEnding
        }
        HStack(spacing: 6) {
          commandField
          sendButton
        }
      }
    }
    .controlSize(.small)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(TekmorColor.chromeBackground)
  }

  private var receiveFormat: some View {
    let title = l10n.tr(.init("serial.receiveFormat", defaultValue: "Receive Format"))
    return Menu {
      Picker(
        title,
        selection: Binding(
          get: { workspace.output.serialFormat },
          set: {
            workspace.selectConsolePane(.serial)
            workspace.output.serialFormat = $0
          }
        )
      ) {
        formatOptions
      }
    } label: {
      Text(workspace.output.serialFormat == .hex ? "RX HEX" : "RX")
    }
    .fixedSize()
    .help(title)
    .accessibilityLabel(title)
  }

  private var sendFormat: some View {
    let title = l10n.tr(.init("serial.sendFormat", defaultValue: "Send Format"))
    return Picker(title, selection: $workspace.serialCommand.format) {
      formatOptions
    }
    .labelsHidden()
    .fixedSize()
    .help(title)
  }

  private var formatOptions: some View {
    Group {
      Text(l10n.tr(.init("serial.format.text", defaultValue: "Text"))).tag(SerialFormat.text)
      Text("HEX").tag(SerialFormat.hex)
    }
  }

  private var lineEnding: some View {
    let title = l10n.tr(.init("serial.lineEnding", defaultValue: "Line Ending"))
    return Picker(title, selection: $workspace.serialCommand.lineEnding) {
      Text(l10n.tr(.init("serial.lineEnding.none", defaultValue: "None"))).tag(
        SerialLineEnding.none)
      Text(SerialLineEnding.lf.rawValue).tag(SerialLineEnding.lf)
      Text(SerialLineEnding.crlf.rawValue).tag(SerialLineEnding.crlf)
    }
    .labelsHidden()
    .fixedSize()
    .help(title)
  }

  private var commandField: some View {
    SerialCommandField(
      input: $workspace.serialCommand.input,
      placeholder: l10n.tr(
        workspace.serialCommand.format == .hex
          ? .init("serial.command.hex", defaultValue: "HEX bytes, e.g. 01 02 FF")
          : .init("serial.command.text", defaultValue: "Enter a serial command")),
      onFocus: { workspace.selectConsolePane(.serial) },
      onRecall: workspace.recallSerialCommand(previous:),
      onSend: workspace.sendSerialCommand
    )
    .frame(minWidth: 100, minHeight: 22)
  }

  private var sendButton: some View {
    Button(action: workspace.sendSerialCommand) {
      Label(
        l10n.tr(.init("serial.send", defaultValue: "Send")), systemImage: "paperplane")
    }
    .disabled(!workspace.canSendSerial)
    .fixedSize()
  }
}

private struct SerialCommandField: NSViewRepresentable {
  @Binding var input: String
  let placeholder: String
  let onFocus: () -> Void
  let onRecall: (Bool) -> Void
  let onSend: () -> Void

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(string: input)
    field.delegate = context.coordinator
    field.controlSize = .small
    field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    field.usesSingleLineMode = true
    field.lineBreakMode = .byClipping
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    field.placeholderString = placeholder
    field.setAccessibilityLabel(placeholder)
    if let editor = field.currentEditor() {
      if editor.string != input {
        editor.string = input
        editor.selectedRange = NSRange(location: input.utf16.count, length: 0)
      }
    } else if field.stringValue != input {
      field.stringValue = input
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: SerialCommandField

    init(_ parent: SerialCommandField) {
      self.parent = parent
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
      parent.onFocus()
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.input = field.currentEditor()?.string ?? field.stringValue
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy command: Selector
    ) -> Bool {
      guard !textView.hasMarkedText() else { return false }
      switch command {
      case #selector(NSResponder.moveUp(_:)): parent.onRecall(true)
      case #selector(NSResponder.moveDown(_:)): parent.onRecall(false)
      case #selector(NSResponder.insertNewline(_:)): parent.onSend()
      default: return false
      }
      return true
    }
  }
}
