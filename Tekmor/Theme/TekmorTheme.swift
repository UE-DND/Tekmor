import AppKit
import SwiftUI

extension EnvironmentValues {
  @Entry var workbenchTextScale: CGFloat = 1
}

/// Flat, native macOS engineering color palette with high typographic contrast and minimal visual chrome.
enum TekmorColor {
  static func adaptive(
    light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1.0, darkAlpha: CGFloat = 1.0,
    highContrast: (light: UInt32, dark: UInt32)? = nil
  ) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(
          from: [
            .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua,
          ])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let hex: UInt32
        switch match {
        case .accessibilityHighContrastDarkAqua: hex = highContrast?.dark ?? dark
        case .accessibilityHighContrastAqua: hex = highContrast?.light ?? light
        default: hex = isDark ? dark : light
        }
        let alpha = isDark ? darkAlpha : lightAlpha
        return NSColor(
          srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
          green: CGFloat((hex >> 8) & 0xFF) / 255.0,
          blue: CGFloat(hex & 0xFF) / 255.0,
          alpha: alpha
        )
      })
  }

  // MARK: - Brand Accent
  static let brand = adaptive(light: 0x0068B7, dark: 0x4DA3F7)
  static let brandBright = adaptive(light: 0x006BBF, dark: 0x60B4FF)
  static let ctaBottom = adaptive(light: 0x0068B7, dark: 0x1465BD)
  static let primaryTonal = adaptive(light: 0x416189, dark: 0x9BB8E0)
  static let brandTintSubtle = adaptive(
    light: 0x0068B7, dark: 0x4DA3F7, lightAlpha: 0.09, darkAlpha: 0.14)
  static let searchMatch = adaptive(light: 0xDCE9FA, dark: 0x354B65)
  static let currentSearchMatch = adaptive(light: 0xBED6F5, dark: 0x55779C)

  // MARK: - Flat Native Surfaces
  static let workspaceBackground = adaptive(light: 0xFFFFFF, dark: 0x232322)
  static let chromeBackground = adaptive(light: 0xF5F6F8, dark: 0x2C2C2E)
  static let chromeSubtle = adaptive(light: 0xE9ECF0, dark: 0x38383A)
  static let hoverFill = adaptive(
    light: 0x0F172A, dark: 0xE2E8F0, lightAlpha: 0.045, darkAlpha: 0.06)
  static let pressedFill = adaptive(
    light: 0x0F172A, dark: 0xE2E8F0, lightAlpha: 0.085, darkAlpha: 0.11)

  // MARK: - Typography Ink
  static let textInk = adaptive(light: 0x0F172A, dark: 0xF1F5F9)
  static let textPrimary = adaptive(light: 0x272D37, dark: 0xDCE1EA)
  static let textSecondary = adaptive(
    light: 0x49515C, dark: 0xB4BCC8, highContrast: (0x272D37, 0xE1E7EE))
  static let textTertiary = adaptive(
    light: 0x5C6470, dark: 0xA4ADBB, highContrast: (0x39414D, 0xD5DEEA))

  // MARK: - Hairline Separators
  static let separator = adaptive(light: 0xE2E5EA, dark: 0x3A3A3E)
  static let separatorSubtle = adaptive(
    light: 0xECEEF2, dark: 0x303033, highContrast: (0x8B93A1, 0x7A8290))
  static let separatorStrong = adaptive(
    light: 0xCFD5DE, dark: 0x4A4A50, highContrast: (0x606876, 0xAAB3C0))

  // MARK: - Semantic Indicators
  static let success = adaptive(light: 0x146D37, dark: 0x4ADE80)
  static let successSubtle = adaptive(
    light: 0x15803D, dark: 0x4ADE80, lightAlpha: 0.085, darkAlpha: 0.12)
  static let warning = adaptive(light: 0x9A430A, dark: 0xFBBF24)
  static let warningSubtle = adaptive(
    light: 0xB45309, dark: 0xFBBF24, lightAlpha: 0.085, darkAlpha: 0.12)
  static let error = adaptive(light: 0xB91C1C, dark: 0xF87171)
  static let errorSubtle = adaptive(
    light: 0xB91C1C, dark: 0xF87171, lightAlpha: 0.075, darkAlpha: 0.13)
  static let signalCyan = adaptive(light: 0x08756D, dark: 0x2DD4BF)
}

enum TekmorRadius {
  static let control: CGFloat = 5
  static let sheet: CGFloat = 8
  static let pill: CGFloat = 999
}

// MARK: - Flat Hairlines

struct HairlineDivider: View {
  var subtle: Bool = false

  var body: some View {
    Rectangle()
      .fill(subtle ? TekmorColor.separatorSubtle : TekmorColor.separator)
      .frame(height: 1)
  }
}

struct VerticalHairline: View {
  var height: CGFloat? = 14

  var body: some View {
    Rectangle()
      .fill(TekmorColor.separator)
      .frame(width: 1, height: height)
  }
}

// MARK: - Flat Button Styles

/// Borderless icon action button (e.g. copy, export, clear, reveal) with subtle hover surface only.
struct TekmorIconButtonStyle: ButtonStyle {
  var tint: Color = TekmorColor.textSecondary
  var active: Bool = false
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(
        active
          ? TekmorColor.brand
          : (hovered ? TekmorColor.textInk : tint)
      )
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
      .background(
        configuration.isPressed
          ? TekmorColor.pressedFill
          : (active ? TekmorColor.brandTintSubtle : (hovered ? TekmorColor.hoverFill : .clear)),
        in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
      )
      .opacity(isEnabled ? 1 : 0.35)
      .onHover { hovered = $0 }
  }
}

/// Borderless quiet text/label action button with subtle hover highlight.
struct TekmorFlatActionButtonStyle: ButtonStyle {
  var tint: Color = TekmorColor.textSecondary
  var active: Bool = false
  var activeTint: Color? = nil
  var activeFill: Color? = nil
  var compact: Bool = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.workbenchTextScale) private var textScale
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    let resolvedActiveTint = activeTint ?? TekmorColor.brand
    let resolvedActiveFill = activeFill ?? TekmorColor.brandTintSubtle
    configuration.label
      .font(.system(size: (compact ? 12 : 13) * textScale, weight: active ? .semibold : .medium))
      .foregroundStyle(
        active
          ? resolvedActiveTint
          : (hovered ? TekmorColor.textInk : tint)
      )
      .padding(.horizontal, compact ? 7 : 8.5)
      .padding(.vertical, compact ? 3.5 : 4.5)
      .background(
        configuration.isPressed
          ? TekmorColor.pressedFill
          : (active ? resolvedActiveFill : (hovered ? TekmorColor.hoverFill : .clear)),
        in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
      )
      .opacity(isEnabled ? 1 : 0.38)
      .onHover { hovered = $0 }
  }
}

// MARK: - Inline Semantic Indicators & Callouts

/// Pure SwiftUI mini activity spinner avoiding AppKit NSProgressIndicator's floating-point
/// scaleEffect min/max layout warnings and layout recursion in compact bars.
struct MiniActivitySpinner: View {
  var size: CGFloat = 11
  var tint: Color = TekmorColor.brand
  @State private var rotating = false
  @Environment(\.l10n) private var l10n
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .trim(from: 0.12, to: 0.82)
      .stroke(tint, style: StrokeStyle(lineWidth: max(1.4, size * 0.15), lineCap: .round))
      .frame(width: size, height: size)
      .rotationEffect(.degrees(rotating && !reduceMotion ? 360 : 0))
      .onChange(of: reduceMotion, initial: true) {
        withAnimation(
          reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false)
        ) {
          rotating = !reduceMotion
        }
      }
      .accessibilityLabel(l10n.tr(.init("accessibility.inProgress", defaultValue: "In progress")))
  }
}

/// Lightweight dot/icon + plain text status indicator (zero capsule background clutter).
struct InlineStatusIndicator: View {
  let text: String
  var color: Color = TekmorColor.textSecondary
  var textColor: Color = TekmorColor.textSecondary
  var icon: String? = nil
  var spinning: Bool = false
  var monospaced: Bool = false
  @Environment(\.workbenchTextScale) private var textScale

  var body: some View {
    HStack(spacing: 5.5) {
      if spinning {
        MiniActivitySpinner(size: 10.5, tint: color)
      } else if let icon {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(color)
      } else {
        Circle()
          .fill(color)
          .frame(width: 6, height: 6)
      }

      Text(text)
        .font(
          monospaced
            ? .system(size: 12 * textScale, weight: .medium, design: .monospaced)
            : .system(size: 12 * textScale, weight: .medium)
        )
        .foregroundStyle(textColor)
        .lineLimit(1)
    }
  }
}

/// Flat full-width semantic callout strip with a crisp leading accent edge (zero rounded card chrome).
struct FlatCalloutStrip<Trailing: View>: View {
  let icon: String
  let message: String
  let accent: Color
  let background: Color
  let messageLineLimit: Int?
  @ViewBuilder var trailing: () -> Trailing
  @Environment(\.workbenchTextScale) private var textScale

  init(
    icon: String,
    message: String,
    accent: Color,
    background: Color,
    messageLineLimit: Int? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
  ) {
    self.icon = icon
    self.message = message
    self.accent = accent
    self.background = background
    self.messageLineLimit = messageLineLimit
    self.trailing = trailing
  }

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(accent)

      Text(message)
        .font(.system(size: 13 * textScale, weight: .medium))
        .foregroundStyle(TekmorColor.textInk)
        .lineLimit(messageLineLimit)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 8)

      trailing()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(background)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(accent)
        .frame(width: 2.5)
    }
  }
}
