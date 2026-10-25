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
    /// One section per app with the full window titles, no previews
    case grouped = "grouped"

    public var title: String {
        switch self {
        case .compact:
            return L("layout.compact")
        case .grid:
            return L("layout.grid")
        case .grouped:
            return L("layout.grouped")
        }
    }

    /// Shows a card with a preview per window (as opposed to the grouped title list)
    public var showsCards: Bool {
        self != .grouped
    }
}

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let shortcutKey = "AltSwitch_ShortcutMode"
    private let layoutKey = "AltSwitch_SwitcherLayout"
    private let lastCardLayoutKey = "AltSwitch_LastCardLayout"
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
            if switcherLayout.showsCards {
                lastCardLayout = switcherLayout
            }
        }
    }

    /// Card layout the view toggle (G in the switcher) returns to from the grouped list
    public private(set) var lastCardLayout: SwitcherLayout {
        didSet {
            defaults.set(lastCardLayout.rawValue, forKey: lastCardLayoutKey)
        }
    }

    /// Switches between the cards (compact or grid, whichever was used last) and the grouped list
    public func toggleCardsAndGroupedList() {
        switcherLayout = switcherLayout.showsCards ? .grouped : lastCardLayout
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

        let initialLayout: SwitcherLayout
        if let savedLayout = defaults.string(forKey: layoutKey),
           let layout = SwitcherLayout(rawValue: savedLayout) {
            initialLayout = layout
        } else {
            initialLayout = .compact
        }
        self.switcherLayout = initialLayout

        if let savedCardLayout = defaults.string(forKey: lastCardLayoutKey),
           let layout = SwitcherLayout(rawValue: savedCardLayout), layout.showsCards {
            self.lastCardLayout = layout
        } else {
            self.lastCardLayout = initialLayout.showsCards ? initialLayout : .compact
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
