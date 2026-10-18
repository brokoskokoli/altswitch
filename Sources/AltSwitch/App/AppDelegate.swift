// SPDX-License-Identifier: MIT

import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    private var statusBarController: StatusBarController?
    private var overlayPanel: OverlayPanel?
    /// Keeps App Nap away: a napping menu bar app reacts late to the shortcut and pages out the overlay.
    private var noNapActivity: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Initialize Overlay Panel
        let panel = OverlayPanel()
        panel.onWindowChosen = { [weak self] item in
            self?.handleWindowSelection(item)
        }
        panel.onDismissed = {
            HotkeyManager.shared.isOverlayActive = false
        }
        self.overlayPanel = panel

        // Initialize Status Bar Icon & Menu
        statusBarController = StatusBarController()

        // Set Hotkey Manager Delegate
        HotkeyManager.shared.delegate = self

        // Check if onboarding / setup assistant is needed
        let needsSetup = !AppSettings.shared.hasCompletedSetup ||
                         !PermissionsManager.shared.isAccessibilityGranted

        if needsSetup {
            SetupWindowController.shared.show()
        }

        // Start global hotkey tap
        HotkeyManager.shared.start()

        // Keep recent window images so minimized windows still get a preview
        WindowManager.shared.startThumbnailCaching()

        // Order windows by last focus, not by the stacking order on screen
        WindowOrderTracker.shared.start()

        // Pay the first-use costs now instead of on the first shortcut press
        WindowManager.shared.warmUp()
        panel.prewarm()
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
        let windows = WindowManager.shared.cachedThumbnails(for: WindowManager.shared.getOpenWindows())
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
        overlayPanel?.show(windows: windows, initialIndex: initialIndex)

        // Load thumbnails asynchronously without blocking event tap or runloop
        WindowManager.shared.loadThumbnailsAsync(for: windows) { [weak self] winId, image in
            self?.overlayPanel?.updateThumbnail(for: winId, image: image)
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
