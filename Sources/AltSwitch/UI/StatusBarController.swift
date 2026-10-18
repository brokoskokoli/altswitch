// SPDX-License-Identifier: MIT

import Cocoa

@MainActor
public class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    public override init() {
        super.init()
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "AltSwitch") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⌥⇥"
            }
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        statusItem.button?.toolTip = L("menu.tooltip")

        // 1. App Header
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let headerItem = NSMenuItem(title: version.isEmpty ? "AltSwitch" : "AltSwitch \(version)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let setupItem = NSMenuItem(
            title: L("menu.openSetup"),
            action: #selector(handleOpenSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Permissions Section
        let axGranted = PermissionsManager.shared.isAccessibilityGranted
        if axGranted {
            let axItem = NSMenuItem(title: L("menu.accessibilityEnabled"), action: nil, keyEquivalent: "")
            axItem.isEnabled = false
            menu.addItem(axItem)
        } else {
            let axItem = NSMenuItem(
                title: L("menu.allowAccessibility"),
                action: #selector(handleRequestAccessibility),
                keyEquivalent: ""
            )
            axItem.target = self
            menu.addItem(axItem)
        }

        let scrGranted = PermissionsManager.shared.isScreenRecordingGranted
        if scrGranted {
            let scrItem = NSMenuItem(title: L("menu.screenRecordingEnabled"), action: nil, keyEquivalent: "")
            scrItem.isEnabled = false
            menu.addItem(scrItem)
        } else {
            let scrItem = NSMenuItem(
                title: L("menu.allowScreenRecording"),
                action: #selector(handleRequestScreenRecording),
                keyEquivalent: ""
            )
            scrItem.target = self
            menu.addItem(scrItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Shortcut Selection
        let shortcutHeader = NSMenuItem(title: L("settings.shortcut"), action: nil, keyEquivalent: "")
        shortcutHeader.isEnabled = false
        menu.addItem(shortcutHeader)

        let currentShortcut = AppSettings.shared.shortcutMode

        let optTabItem = NSMenuItem(
            title: "    " + ShortcutMode.optionTab.title,
            action: #selector(selectOptionTabShortcut),
            keyEquivalent: ""
        )
        optTabItem.target = self
        optTabItem.state = (currentShortcut == .optionTab) ? .on : .off
        menu.addItem(optTabItem)

        let cmdTabItem = NSMenuItem(
            title: "    " + ShortcutMode.cmdTab.title,
            action: #selector(selectCmdTabShortcut),
            keyEquivalent: ""
        )
        cmdTabItem.target = self
        cmdTabItem.state = (currentShortcut == .cmdTab) ? .on : .off
        menu.addItem(cmdTabItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Layout Selection
        let layoutHeader = NSMenuItem(title: L("menu.layout"), action: nil, keyEquivalent: "")
        layoutHeader.isEnabled = false
        menu.addItem(layoutHeader)

        let currentLayout = AppSettings.shared.switcherLayout

        let compactItem = NSMenuItem(
            title: "    " + SwitcherLayout.compact.title,
            action: #selector(selectCompactLayout),
            keyEquivalent: ""
        )
        compactItem.target = self
        compactItem.state = (currentLayout == .compact) ? .on : .off
        menu.addItem(compactItem)

        let gridItem = NSMenuItem(
            title: "    " + SwitcherLayout.grid.title,
            action: #selector(selectGridLayout),
            keyEquivalent: ""
        )
        gridItem.target = self
        gridItem.state = (currentLayout == .grid) ? .on : .off
        menu.addItem(gridItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Autostart
        let autostartItem = NSMenuItem(
            title: L("menu.startAtLogin"),
            action: #selector(toggleAutostart),
            keyEquivalent: ""
        )
        autostartItem.target = self
        autostartItem.state = AutostartManager.shared.isAutostartEnabled ? .on : .off
        menu.addItem(autostartItem)

        // 6. Language
        menu.addItem(languageMenuItem())

        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(
            title: L("menu.quit"),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Submenu with "System Language" and every translation in its own name. The title keeps the
    /// English word, so someone who picked a language they cannot read still finds the way back.
    private func languageMenuItem() -> NSMenuItem {
        let localizedTitle = L("menu.language")
        let title = (localizedTitle == "Language") ? localizedTitle : "\(localizedTitle) / Language"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let current = AppSettings.shared.language

        let systemItem = NSMenuItem(
            title: L("menu.systemLanguage"),
            action: #selector(selectLanguage(_:)),
            keyEquivalent: ""
        )
        systemItem.target = self
        systemItem.representedObject = Localization.systemLanguage
        systemItem.state = (current == Localization.systemLanguage) ? .on : .off
        submenu.addItem(systemItem)

        submenu.addItem(NSMenuItem.separator())

        for language in Localization.supportedLanguages {
            let languageItem = NSMenuItem(
                title: language.nativeName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            languageItem.target = self
            languageItem.representedObject = language.code
            languageItem.state = (current == language.code) ? .on : .off
            submenu.addItem(languageItem)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func handleOpenSetup() {
        SetupWindowController.shared.show()
    }

    @objc private func handleRequestAccessibility() {
        if !PermissionsManager.shared.requestAccessibility() {
            PermissionsManager.shared.openAccessibilitySettings()
        }
    }

    @objc private func handleRequestScreenRecording() {
        PermissionsManager.shared.requestScreenRecording()
        PermissionsManager.shared.openScreenRecordingSettings()
    }

    @objc private func selectOptionTabShortcut() {
        AppSettings.shared.shortcutMode = .optionTab
        HotkeyManager.shared.start()
        rebuildMenu()
    }

    @objc private func selectCmdTabShortcut() {
        AppSettings.shared.shortcutMode = .cmdTab
        HotkeyManager.shared.start()
        rebuildMenu()
    }

    @objc private func selectCompactLayout() {
        AppSettings.shared.switcherLayout = .compact
        rebuildMenu()
    }

    @objc private func selectGridLayout() {
        AppSettings.shared.switcherLayout = .grid
        rebuildMenu()
    }

    @objc private func toggleAutostart() {
        let current = AutostartManager.shared.isAutostartEnabled
        _ = AutostartManager.shared.setAutostart(enabled: !current)
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        AppSettings.shared.language = code
        rebuildMenu()
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
