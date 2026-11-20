import SwiftUI

struct ConsoleFindBar: View {
  let title: String
  @Binding var query: String
  let matchIndex: Int
  let matchCount: Int
  var onNext: () -> Void
  var onPrevious: () -> Void
  var onClose: () -> Void
  var onFocus: () -> Void
  @FocusState private var isFocused: Bool
  @Environment(\.l10n) private var l10n
  @Environment(\.workbenchTextScale) private var textScale

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: TekmorRadius.sheet)

    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(TekmorColor.textSecondary)
        .accessibilityHidden(true)
      TextField(title, text: $query)
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onSubmit(onNext)
        .onKeyPress(.return, phases: .down) { press in
          guard press.modifiers.contains(.shift) else { return .ignored }
          onPrevious()
          return .handled
        }
        .onKeyPress(.escape) {
          onClose()
          return .handled
        }
        .accessibilityIdentifier("console.find.query")

      if !query.isEmpty {
        Text(
          matchIndex > 0
            ? "\(matchIndex)/\(matchCount)"
            : l10n.tr(.init("console.findMatches", defaultValue: "\(matchCount) matches"))
        )
        .lineLimit(1)
        .monospacedDigit()
        .foregroundStyle(matchCount == 0 ? TekmorColor.textSecondary : TekmorColor.brand)
        .accessibilityLabel(
          l10n.tr(
            matchIndex > 0
              ? .init(
                "console.findMatchCount", defaultValue: "Match \(matchIndex) of \(matchCount)")
              : .init("console.findMatches", defaultValue: "\(matchCount) matches"))
        )
        .accessibilityIdentifier("console.find.count")
      }

      HStack(spacing: 1) {
        Button(action: onPrevious) { Image(systemName: "chevron.up") }
          .help(l10n.tr(.init("console.findPrevious", defaultValue: "Previous Match (⇧⌘G)")))
          .accessibilityLabel(
            l10n.tr(.init("console.findPrevious", defaultValue: "Previous Match (⇧⌘G)")))
        Button(action: onNext) { Image(systemName: "chevron.down") }
          .help(l10n.tr(.init("console.findNext", defaultValue: "Next Match (⌘G)")))
          .accessibilityLabel(
            l10n.tr(.init("console.findNext", defaultValue: "Next Match (⌘G)")))
      }
      .buttonStyle(TekmorIconButtonStyle())
      .disabled(matchCount == 0)

      Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(TekmorIconButtonStyle())
        .accessibilityLabel(
          l10n.tr(.init("accessibility.closeSearch", defaultValue: "Close search"))
        )
        .accessibilityIdentifier("console.find.close")
    }
    .font(.system(size: 13 * textScale))
    .padding(.horizontal, 12)
    .frame(maxWidth: 360, minHeight: max(30, 16 * textScale + 10))
    .background(TekmorColor.chromeBackground, in: shape)
    .overlay { shape.strokeBorder(TekmorColor.separator) }
    .padding(6)
    .task { isFocused = true }
    .onChange(of: isFocused) {
      if isFocused { onFocus() }
    }
  }
}
