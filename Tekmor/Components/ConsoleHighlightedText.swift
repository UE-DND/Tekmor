import SwiftUI
import TekmorWorkbench

struct ConsoleHighlightedText: View {
  let text: String
  let matches: [ConsoleSearchResults.Match]
  let currentMatch: ConsoleSearchResults.Match?

  var body: some View {
    highlightedText
      .textRenderer(MatchRenderer())
  }

  private var highlightedText: Text {
    var result = Text(verbatim: "")
    var start = text.startIndex
    for match in matches {
      let prefix = Text(verbatim: String(text[start..<match.range.lowerBound]))
      let highlight = Text(verbatim: String(text[match.range]))
        .customAttribute(MatchAttribute(isCurrent: match == currentMatch))
      result = Text("\(result)\(prefix)\(highlight)")
      start = match.range.upperBound
    }
    let suffix = Text(verbatim: String(text[start...]))
    return Text("\(result)\(suffix)")
  }

  private struct MatchAttribute: TextAttribute {
    let isCurrent: Bool
  }

  private struct MatchRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
      for line in layout {
        for run in line {
          if let match = run[MatchAttribute.self] {
            let rect = run.typographicBounds.rect
            let background = RoundedRectangle(cornerRadius: 3).path(in: rect)
            context.fill(
              background,
              with: .color(
                match.isCurrent ? TekmorColor.currentSearchMatch : TekmorColor.searchMatch))
          }
          context.draw(run)
        }
      }
    }
  }
}
