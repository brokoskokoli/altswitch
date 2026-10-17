import Cocoa
import SwiftUI

@MainActor
public class SetupWindowController: NSObject, NSWindowDelegate {
    public static let shared = SetupWindowController()

    private var window: NSWindow?
    private var viewModel: SetupViewModel?
    private var isCleaningUp = false

    private override init() {
        super.init()
    }

    public func show() {
        // Temporarily promote to regular activation policy so window can become key & frontmost
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let vm = SetupViewModel()
            self.viewModel = vm

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Willkommen bei AltSwitch — Ersteinrichtung"
            win.isReleasedWhenClosed = false
            win.isMovableByWindowBackground = true
            win.delegate = self

            let setupView = SetupView(viewModel: vm) { [weak self] in
                self?.close()
            }
            win.contentView = NSHostingView(rootView: setupView)
            self.window = win
        }

        viewModel?.startPolling()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
            NSRunningApplication.current.activate(options: .activateAllWindows)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    public func close() {
        if let win = window {
            win.close()
        }
        cleanup()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        defer { isCleaningUp = false }

        viewModel?.stopPolling()
        viewModel = nil

        if let win = window {
            win.delegate = nil
            win.orderOut(nil)
            self.window = nil
        }

        // Restore accessory policy (no Dock icon, background menu-bar app)
        NSApp.setActivationPolicy(.accessory)

        // Ensure HotkeyManager starts if permissions were granted
        HotkeyManager.shared.start()
    }
}
