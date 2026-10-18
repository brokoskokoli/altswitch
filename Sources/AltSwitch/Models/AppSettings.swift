// SPDX-License-Identifier: MIT

import Foundation
import Combine

public enum ShortcutMode: String, CaseIterable {
    case optionTab = "optionTab"
    case cmdTab = "cmdTab"

    public var title: String {
        switch self {
        case .optionTab:
            return L("shortcut.optionTab")
        case .cmdTab:
            return L("shortcut.cmdTab")
        }
    }
}

public enum SwitcherLayout: String, CaseIterable {
    case compact = "compact"
    case grid = "grid"

    public var title: String {
        switch self {
        case .compact:
            return L("layout.compact")
        case .grid:
            return L("layout.grid")
        }
    }
}

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let shortcutKey = "AltSwitch_ShortcutMode"
    private let layoutKey = "AltSwitch_SwitcherLayout"
    private let hasCompletedSetupKey = "AltSwitch_HasCompletedSetup"
    private let languageKey = "AltSwitch_Language"

    @Published public var shortcutMode: ShortcutMode {
        didSet {
            defaults.set(shortcutMode.rawValue, forKey: shortcutKey)
        }
    }

    @Published public var switcherLayout: SwitcherLayout {
        didSet {
            defaults.set(switcherLayout.rawValue, forKey: layoutKey)
        }
    }

    @Published public var hasCompletedSetup: Bool {
        didSet {
            defaults.set(hasCompletedSetup, forKey: hasCompletedSetupKey)
        }
    }

    /// `.lproj` code of the UI language, or `Localization.systemLanguage` to follow macOS
    @Published public var language: String {
        didSet {
            defaults.set(language, forKey: languageKey)
        }
    }

    private init() {
        if let saved = defaults.string(forKey: shortcutKey),
           let mode = ShortcutMode(rawValue: saved) {
            self.shortcutMode = mode
        } else {
            self.shortcutMode = .optionTab
        }

        if let savedLayout = defaults.string(forKey: layoutKey),
           let layout = SwitcherLayout(rawValue: savedLayout) {
            self.switcherLayout = layout
        } else {
            self.switcherLayout = .compact
        }

        self.hasCompletedSetup = defaults.bool(forKey: hasCompletedSetupKey)

        if let savedLanguage = defaults.string(forKey: languageKey),
           Localization.supportedLanguages.contains(where: { $0.code == savedLanguage }) {
            self.language = savedLanguage
        } else {
            self.language = Localization.systemLanguage
        }
    }
}
