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
            button.toolTip = "AltSwitch — Windows-Style Window Switcher"
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

        // 1. App Header
        let headerItem = NSMenuItem(title: "AltSwitch v1.0", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let setupItem = NSMenuItem(
            title: "Einrichtungs-Assistent öffnen...",
            action: #selector(handleOpenSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Permissions Section
        let axGranted = PermissionsManager.shared.isAccessibilityGranted
        if axGranted {
            let axItem = NSMenuItem(title: "✓ Bedienungshilfen aktiviert", action: nil, keyEquivalent: "")
            axItem.isEnabled = false
            menu.addItem(axItem)
        } else {
            let axItem = NSMenuItem(
                title: "⚠️ Bedienungshilfen erlauben...",
                action: #selector(handleRequestAccessibility),
                keyEquivalent: ""
            )
            axItem.target = self
            menu.addItem(axItem)
        }

        let scrGranted = PermissionsManager.shared.isScreenRecordingGranted
        if scrGranted {
            let scrItem = NSMenuItem(title: "✓ Bildschirmaufnahme aktiviert", action: nil, keyEquivalent: "")
            scrItem.isEnabled = false
            menu.addItem(scrItem)
        } else {
            let scrItem = NSMenuItem(
                title: "⚠️ Bildschirmaufnahme erlauben...",
                action: #selector(handleRequestScreenRecording),
                keyEquivalent: ""
            )
            scrItem.target = self
            menu.addItem(scrItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Shortcut Selection
        let shortcutHeader = NSMenuItem(title: "Tastenkombination:", action: nil, keyEquivalent: "")
        shortcutHeader.isEnabled = false
        menu.addItem(shortcutHeader)

        let currentShortcut = AppSettings.shared.shortcutMode

        let optTabItem = NSMenuItem(
            title: "    Option + Tab (⌥-Tab)",
            action: #selector(selectOptionTabShortcut),
            keyEquivalent: ""
        )
        optTabItem.target = self
        optTabItem.state = (currentShortcut == .optionTab) ? .on : .off
        menu.addItem(optTabItem)

        let cmdTabItem = NSMenuItem(
            title: "    Command + Tab (⌘-Tab)",
            action: #selector(selectCmdTabShortcut),
            keyEquivalent: ""
        )
        cmdTabItem.target = self
        cmdTabItem.state = (currentShortcut == .cmdTab) ? .on : .off
        menu.addItem(cmdTabItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Layout Selection
        let layoutHeader = NSMenuItem(title: "Layout:", action: nil, keyEquivalent: "")
        layoutHeader.isEnabled = false
        menu.addItem(layoutHeader)

        let currentLayout = AppSettings.shared.switcherLayout

        let compactItem = NSMenuItem(
            title: "    Kompakt (Fokus)",
            action: #selector(selectCompactLayout),
            keyEquivalent: ""
        )
        compactItem.target = self
        compactItem.state = (currentLayout == .compact) ? .on : .off
        menu.addItem(compactItem)

        let gridItem = NSMenuItem(
            title: "    Alle Fenster (Raster-Übersicht)",
            action: #selector(selectGridLayout),
            keyEquivalent: ""
        )
        gridItem.target = self
        gridItem.state = (currentLayout == .grid) ? .on : .off
        menu.addItem(gridItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Autostart
        let autostartItem = NSMenuItem(
            title: "Beim Anmelden starten",
            action: #selector(toggleAutostart),
            keyEquivalent: ""
        )
        autostartItem.target = self
        autostartItem.state = AutostartManager.shared.isAutostartEnabled ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(
            title: "AltSwitch beenden",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
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

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
