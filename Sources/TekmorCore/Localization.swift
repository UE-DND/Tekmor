import Foundation
import Synchronization

public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
  case system
  case zhHans = "zh-Hans"
  case english = "en"

  public static let supportedCodes = ["en", "zh-Hans"]

  public var id: Self { self }

  public var resolvedCode: String {
    switch self {
    case .zhHans:
      return "zh-Hans"
    case .english:
      return "en"
    case .system:
      return Bundle.preferredLocalizations(
        from: Self.supportedCodes, forPreferences: Locale.preferredLanguages
      ).first ?? "en"
    }
  }

  public var locale: Locale {
    locale(overriding: .autoupdatingCurrent)
  }

  public func locale(overriding regionalLocale: Locale) -> Locale {
    var components = Locale.Components(locale: regionalLocale)
    components.region = regionalLocale.region
    components.languageComponents = Locale.Language.Components(identifier: resolvedCode)
    return Locale(components: components)
  }
}

public enum TekmorLocalization {
  private static let current = Mutex(AppLanguage.system)

  public static var language: AppLanguage {
    get { current.withLock { $0 } }
    set { current.withLock { $0 = newValue } }
  }

  public static func string(
    _ resource: LocalizedStringResource, language: AppLanguage? = nil
  ) -> String {
    var localized = resource
    localized.locale = (language ?? Self.language).locale
    return String(localized: localized)
  }

  static func core(_ resource: LocalizedStringResource) -> String {
    string(resource)
  }
}
