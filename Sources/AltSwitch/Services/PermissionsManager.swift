import Cocoa
import ApplicationServices
import CoreGraphics

public class PermissionsManager {
    public static let shared = PermissionsManager()

    private init() {}

    // MARK: - Accessibility

    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibility() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func requestAndOpenAccessibility() {
        _ = requestAccessibility()
        openAccessibilitySettings()
    }

    // MARK: - Screen Recording

    public var isScreenRecordingGranted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    public func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func requestAndOpenScreenRecording() {
        requestScreenRecording()
        openScreenRecordingSettings()
    }
}
