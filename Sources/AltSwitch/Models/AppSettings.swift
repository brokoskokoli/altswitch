import Foundation
import Combine

public enum ShortcutMode: String, CaseIterable {
    case optionTab = "optionTab"
    case cmdTab = "cmdTab"

    public var title: String {
        switch self {
        case .optionTab:
            return "Option + Tab (⌥-Tab)"
        case .cmdTab:
            return "Command + Tab (⌘-Tab)"
        }
    }
}

public enum SwitcherLayout: String, CaseIterable {
    case compact = "compact"
    case grid = "grid"

    public var title: String {
        switch self {
        case .compact:
            return "Kompakt (Fokus)"
        case .grid:
            return "Alle Fenster (Raster-Übersicht)"
        }
    }
}

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let shortcutKey = "AltSwitch_ShortcutMode"
    private let layoutKey = "AltSwitch_SwitcherLayout"
    private let hasCompletedSetupKey = "AltSwitch_HasCompletedSetup"

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
    }
}
