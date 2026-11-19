// SPDX-License-Identifier: MIT

import Cocoa
import Carbon

/// Plain-text state for a bug report, copied from the menu. No window titles or app names: only
/// versions, permissions, settings and counts.
enum Diagnostics {
    /// Another app (a password field, Terminal's "Secure Keyboard Entry") holds secure input:
    /// macOS then hands key events to no event tap, and ⌘-Tab reaches the system switcher.
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    static func report() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif

        let windows = WindowManager.shared.getOpenWindows()
        let apps = Set(windows.map(\.pid)).count
        let settings = AppSettings.shared

        return """
        AltSwitch \(version) (\(build)), \(arch)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility: \(PermissionsManager.shared.isAccessibilityGranted ? "granted" : "missing")
        Screen Recording: \(PermissionsManager.shared.isScreenRecordingGranted ? "granted" : "missing")
        Window capture available: \(WindowManager.isCaptureAvailable ? "yes" : "no")
        Event tap installed: \(HotkeyManager.shared.isTapInstalled ? "yes" : "no")
        Event tap re-enabled by macOS since launch: \(HotkeyManager.shared.tapReenables)
        Secure keyboard entry on: \(isSecureInputEnabled ? "yes" : "no")
        Shortcut: \(settings.shortcutMode.rawValue), layout: \(settings.switcherLayout.rawValue)
        Windows listed: \(windows.count) from \(apps) apps
        Displays: \(NSScreen.screens.count)
        """
    }

    static func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report(), forType: .string)
    }
}
