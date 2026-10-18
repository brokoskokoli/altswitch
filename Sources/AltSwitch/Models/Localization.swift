// SPDX-License-Identifier: MIT

import Foundation

/// A language the UI is translated into. `code` is the name of its `.lproj` folder,
/// `nativeName` is how the language calls itself (shown in the language menu).
public struct AppLanguage: Hashable {
    public let code: String
    public let nativeName: String
}

/// Looks up UI texts in the language chosen in the menu bar menu. "System" follows the normal
/// bundle resolution (`Bundle.preferredLocalizations`), any other choice loads that `.lproj`
/// directly, so a switch works without restarting the app. Missing keys fall back to English.
public enum Localization {
    /// Setting value for "follow the macOS language"
    public static let systemLanguage = "system"
    public static let developmentLanguage = "en"

    public static let supportedLanguages: [AppLanguage] = [
        AppLanguage(code: "en", nativeName: "English"),
        AppLanguage(code: "de", nativeName: "Deutsch"),
        AppLanguage(code: "fr", nativeName: "Français"),
        AppLanguage(code: "es", nativeName: "Español"),
        AppLanguage(code: "it", nativeName: "Italiano"),
        AppLanguage(code: "pt-BR", nativeName: "Português (Brasil)"),
        AppLanguage(code: "pt-PT", nativeName: "Português (Portugal)"),
        AppLanguage(code: "nl", nativeName: "Nederlands"),
        AppLanguage(code: "pl", nativeName: "Polski"),
        AppLanguage(code: "cs", nativeName: "Čeština"),
        AppLanguage(code: "sk", nativeName: "Slovenčina"),
        AppLanguage(code: "sv", nativeName: "Svenska"),
        AppLanguage(code: "da", nativeName: "Dansk"),
        AppLanguage(code: "nb", nativeName: "Norsk bokmål"),
        AppLanguage(code: "fi", nativeName: "Suomi"),
        AppLanguage(code: "hu", nativeName: "Magyar"),
        AppLanguage(code: "ro", nativeName: "Română"),
        AppLanguage(code: "el", nativeName: "Ελληνικά"),
        AppLanguage(code: "tr", nativeName: "Türkçe"),
        AppLanguage(code: "ru", nativeName: "Русский"),
        AppLanguage(code: "uk", nativeName: "Українська"),
        AppLanguage(code: "ja", nativeName: "日本語"),
        AppLanguage(code: "ko", nativeName: "한국어"),
        AppLanguage(code: "zh-Hans", nativeName: "简体中文"),
        AppLanguage(code: "zh-Hant", nativeName: "繁體中文"),
    ]

    private static let lock = NSLock()
    private static var bundles: [String: Bundle] = [:]
    private static let missingMarker = "\u{0}AltSwitchMissing"

    /// Code of the language texts are currently shown in
    public static var activeLanguageCode: String {
        let chosen = AppSettings.shared.language
        if chosen != systemLanguage {
            return chosen
        }
        return Bundle.main.preferredLocalizations.first ?? developmentLanguage
    }

    public static func string(_ key: String) -> String {
        let chosen = AppSettings.shared.language
        let primary = (chosen == systemLanguage) ? Bundle.main : bundle(for: chosen)

        if let value = primary.flatMap({ lookUp(key, in: $0) }) {
            return value
        }
        if let value = bundle(for: developmentLanguage).flatMap({ lookUp(key, in: $0) }) {
            return value
        }
        return key
    }

    private static func lookUp(_ key: String, in bundle: Bundle) -> String? {
        let value = bundle.localizedString(forKey: key, value: missingMarker, table: nil)
        return value == missingMarker ? nil : value
    }

    /// The `.lproj` folder of one language as its own bundle, so its strings load regardless of
    /// the system language
    private static func bundle(for code: String) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = bundles[code] {
            return cached
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        bundles[code] = bundle
        return bundle
    }
}

/// Localized UI text for `key` in the language chosen in the menu
public func L(_ key: String) -> String {
    Localization.string(key)
}

/// Localized format string for `key`, filled with `arguments` (`%@`, `%lld`)
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: Localization.string(key),
        locale: Locale(identifier: Localization.activeLanguageCode),
        arguments: arguments
    )
}
