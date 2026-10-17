import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    private var statusBarController: StatusBarController?
    private var overlayPanel: OverlayPanel?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory (LSUIElement)
        NSApplication.shared.setActivationPolicy(.accessory)

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
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
    }

    // MARK: - HotkeyManagerDelegate

    public func hotkeyTriggered(forward: Bool) {
        let windows = WindowManager.shared.getOpenWindows()
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
