// SPDX-License-Identifier: MIT

import Cocoa
import ApplicationServices

/// Remembers which window had focus when, like Alt-Tab on Windows. The on-screen stacking order is
/// not good enough: activating an app raises all of its windows, so they would come first as a group.
public class WindowOrderTracker {
    public static let shared = WindowOrderTracker()

    /// Window IDs, most recently focused first. Main thread only.
    private var recentWindowIDs: [CGWindowID] = []
    /// The IDs in recentWindowIDs that really had focus, not just seeded from the stacking order.
    /// Main thread only.
    private var focusedWindowIDs = Set<CGWindowID>()
    private var observers: [pid_t: AXObserver] = [:]
    /// When registering for an app last failed. Every press tries the apps without an observer
    /// again, one after the other on the main thread: an app that does not answer would cost up
    /// to its timeout on each press. Main thread only.
    private var failedAt: [pid_t: CFTimeInterval] = [:]
    private let retryAfterFailure: CFTimeInterval = 30

    private init() {}

    public func start() {
        // Until focus changes are seen, the stacking order is the best guess
        seedFromStackingOrder()
        observeRunningApps()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Switching apps does not change the app's own focused window, so no AX notification comes
            self?.noteFocusedWindow(of: app.processIdentifier)
        }
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // A freshly launched app answers Accessibility calls only after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.observe(app)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.stopObserving(app.processIdentifier)
            self?.failedAt[app.processIdentifier] = nil
        }
    }

    /// Brings the order up to date before a window list is built.
    /// `regularApps`: the running regular apps if the caller has them (saves reading them again).
    public func refresh(regularApps: [NSRunningApplication]? = nil) {
        // Picks up apps that were not ready before, or Accessibility permission granted after launch
        observeRunningApps(regularApps)
        // The frontmost window is the current one, even if its notification was missed
        if let front = NSWorkspace.shared.frontmostApplication {
            noteFocusedWindow(of: front.processIdentifier)
        }
    }

    /// The user worked in this window (it had keyboard focus), so it is a real window even if it
    /// looks like a helper, e.g. a small popup
    public func wasFocused(_ id: CGWindowID) -> Bool {
        focusedWindowIDs.contains(id)
    }

    /// Orders windows by last focus. Windows never seen focused keep their relative order behind them.
    public func sortedByRecentUse(_ windows: [WindowItem]) -> [WindowItem] {
        var rank: [CGWindowID: Int] = [:]
        for (index, id) in recentWindowIDs.enumerated() where rank[id] == nil {
            rank[id] = index
        }
        return windows.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max
            let rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { $0.element }
    }

    public func noteFocused(window: AXUIElement) {
        var id: CGWindowID = 0
        guard let getWindow = dynamicAXUIElementGetWindow,
              getWindow(window, &id) == .success, id != 0 else {
            return
        }
        recentWindowIDs.removeAll { $0 == id }
        recentWindowIDs.insert(id, at: 0)
        focusedWindowIDs.insert(id)
        // Closed windows linger here; a short list is enough to order what is open
        if recentWindowIDs.count > 200 {
            for dropped in recentWindowIDs[200...] {
                focusedWindowIDs.remove(dropped)
            }
            recentWindowIDs.removeLast(recentWindowIDs.count - 200)
        }
    }

    private func noteFocusedWindow(of pid: pid_t) {
        guard pid != NSRunningApplication.current.processIdentifier else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() {
            noteFocused(window: window as! AXUIElement)
        }
    }

    private func seedFromStackingOrder() {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        recentWindowIDs = infoList.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
    }

    private func observeRunningApps(_ regularApps: [NSRunningApplication]? = nil) {
        guard PermissionsManager.shared.isAccessibilityGranted else { return }
        let apps = regularApps ?? NSWorkspace.shared.runningApplications
        for app in apps where app.activationPolicy == .regular {
            observe(app)
        }
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular,
              pid != NSRunningApplication.current.processIdentifier,
              observers[pid] == nil else {
            return
        }
        if let failed = failedAt[pid], CACurrentMediaTime() - failed < retryAfterFailure {
            return
        }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon = refcon else { return }
            let tracker = Unmanaged<WindowOrderTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.noteFocused(window: element)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer = observer else {
            failedAt[pid] = CACurrentMediaTime()
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon) == .success else {
            failedAt[pid] = CACurrentMediaTime()
            return
        }
        failedAt[pid] = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
