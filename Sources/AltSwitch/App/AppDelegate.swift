// SPDX-License-Identifier: MIT

import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    private var statusBarController: StatusBarController?
    private var overlayPanel: OverlayPanel?
    /// Keeps App Nap away: a napping menu bar app reacts late to the shortcut and pages out the overlay.
    private var noNapActivity: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = PerfLog.now()
        defer { PerfLog.log("launch total", since: launchStart) }

        // Only one instance: a second launch tells the user and quits
        if isAnotherInstanceRunning() {
            showAlreadyRunningAlert()
            NSApplication.shared.terminate(nil)
            return
        }

        // Run as menu bar accessory (LSUIElement)
        NSApplication.shared.setActivationPolicy(.accessory)

        AutostartManager.shared.enableOnFirstLaunchIfInstalled()

        noNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "AltSwitch must react to the shortcut immediately"
        )

        // First: the first contact with each app runs in the background while the overlay is
        // built, so the order tracker and the prewarm below find the apps already answering
        PerfLog.measure("launch warm up") { WindowManager.shared.warmUp() }

        // Initialize Overlay Panel
        let panel = PerfLog.measure("launch overlay panel") { OverlayPanel() }
        panel.onWindowChosen = { [weak self] item in
            self?.handleWindowSelection(item)
        }
        panel.onDismissed = {
            HotkeyManager.shared.isOverlayActive = false
        }
        self.overlayPanel = panel

        // Initialize Status Bar Icon & Menu
        statusBarController = PerfLog.measure("launch status bar") { StatusBarController() }

        // Set Hotkey Manager Delegate
        HotkeyManager.shared.delegate = self
        HotkeyManager.shared.onTriggerModifierDown = {
            WindowManager.shared.prepareForPress()
        }

        // Check if onboarding / setup assistant is needed
        let needsSetup = !AppSettings.shared.hasCompletedSetup ||
                         !PermissionsManager.shared.isAccessibilityGranted

        if needsSetup {
            SetupWindowController.shared.show()
        }

        // Start global hotkey tap
        PerfLog.measure("launch hotkey tap") { HotkeyManager.shared.start() }

        // Keep recent window images so minimized windows still get a preview
        PerfLog.measure("launch thumbnail caching") { WindowManager.shared.startThumbnailCaching() }

        // Order windows by last focus, not by the stacking order on screen
        PerfLog.measure("launch order tracker") { WindowOrderTracker.shared.start() }

        // Pay the SwiftUI first-render cost now instead of on the first shortcut press
        PerfLog.measure("launch prewarm overlay") { panel.prewarm() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
    }

    // MARK: - Single Instance

    private func isAnotherInstanceRunning() -> Bool {
        let current = NSRunningApplication.current
        // Bundle ID covers every copy of the app; the name catches builds launched without a bundle
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stefanrichter.altswitch"
        return NSWorkspace.shared.runningApplications.contains { app in
            app.processIdentifier != current.processIdentifier &&
                !app.isTerminated &&
                (app.bundleIdentifier == bundleID || app.executableURL?.lastPathComponent == "AltSwitch")
        }
    }

    private func showAlreadyRunningAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("alert.alreadyRunning.title")
        alert.informativeText = L("alert.alreadyRunning.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("alert.ok"))
        alert.runModal()
    }

    // MARK: - HotkeyManagerDelegate

    public func hotkeyTriggered(forward: Bool) {
        // The grouped list shows titles only: no previews to look up or capture
        let pressStart = PerfLog.now()
        let showsCards = AppSettings.shared.switcherLayout.showsCards
        let openWindows = PerfLog.measure("press window list") { WindowManager.shared.getOpenWindows() }
        let windows = showsCards ? WindowManager.shared.cachedThumbnails(for: openWindows) : openWindows
        guard !windows.isEmpty else {
            HotkeyManager.shared.isOverlayActive = false
            return
        }

        // In MRU front-to-back: index 0 is currently active window.
        // Option-Tab should select the second window (index 1), Shift-Option-Tab selects the last.
        let initialIndex: Int
        if forward {
            initialIndex = (windows.count > 1) ? 1 : 0
        } else {
            initialIndex = (windows.count > 1) ? (windows.count - 1) : 0
        }

        HotkeyManager.shared.isOverlayActive = true
        PerfLog.logWhenFrameCommitted("press to overlay frame (\(windows.count) windows)", since: pressStart)
        PerfLog.measure("press show overlay") {
            overlayPanel?.show(windows: windows, initialIndex: initialIndex)
        }

        // Load thumbnails asynchronously without blocking event tap or runloop
        if showsCards {
            WindowManager.shared.loadThumbnailsAsync(for: windows) { [weak self] winId, image in
                self?.overlayPanel?.updateThumbnail(for: winId, image: image)
            }
        }
    }

    public func hotkeyToggleLayout() {
        guard let panel = overlayPanel, panel.isVisible else { return }
        panel.toggleLayout()

        // Opened in the grouped list: the cards still need their previews
        guard AppSettings.shared.switcherLayout.showsCards else { return }
        let windows = panel.presentedWindows
        for item in WindowManager.shared.cachedThumbnails(for: windows) {
            if let image = item.thumbnail {
                panel.updateThumbnail(for: item.id, image: image)
            }
        }
        WindowManager.shared.loadThumbnailsAsync(for: windows) { [weak panel] winId, image in
            panel?.updateThumbnail(for: winId, image: image)
        }
    }

    public func hotkeyCycle(forward: Bool) {
        if forward {
            overlayPanel?.cycleNext()
        } else {
            overlayPanel?.cyclePrevious()
        }
    }

    public func hotkeyNavigate(direction: NavigationDirection) {
        overlayPanel?.navigate(direction: direction)
    }

    public func hotkeyConfirmed() {
        HotkeyManager.shared.isOverlayActive = false
        overlayPanel?.confirmSelection()
    }

    public func hotkeyCancelled() {
        HotkeyManager.shared.isOverlayActive = false
        overlayPanel?.cancel()
    }

    private func handleWindowSelection(_ item: WindowItem) {
        HotkeyManager.shared.isOverlayActive = false
        WindowManager.shared.activateWindow(item)
    }
}
