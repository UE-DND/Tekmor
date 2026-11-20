import Foundation
import SwiftUI
import TekmorCore

struct AppL10n: Equatable, Sendable {
  let language: AppLanguage

  var locale: Locale { language.locale }

  func tr(_ resource: LocalizedStringResource) -> String {
    TekmorLocalization.string(resource, language: language)
  }
}

extension EnvironmentValues {
  @Entry var l10n = AppL10n(language: .system)
}
