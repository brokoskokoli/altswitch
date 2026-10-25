// SPDX-License-Identifier: MIT

import Cocoa
import ApplicationServices
import CoreGraphics

private typealias CGWindowListCreateImageFunc = @convention(c) (
    CGRect,
    CGWindowListOption,
    CGWindowID,
    CGWindowImageOption
) -> Unmanaged<CGImage>?

private let dynamicCGWindowListCreateImage: CGWindowListCreateImageFunc? = {
    guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGWindowListCreateImage") else {
        return nil
    }
    return unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
}()

// Private but long-stable AX call (used by AltTab, yabai …): CGWindowID of an AX window. Needed to
// find a minimized window's cached thumbnail, since minimized windows are not in the on-screen list,
// and to record which window got focus (WindowOrderTracker).
typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

let dynamicAXUIElementGetWindow: AXUIElementGetWindowFunc? = {
    guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
}()

// Private but long-stable SkyLight calls (used by AltTab, yabai …). Accessibility lists only the
// windows of the current Space and CGWindowList does not say which Space a window is on, so these
// tell windows on other Spaces (and in native full screen) apart from invisible helper windows, and
// bring such a window up, switching to its Space. All optional: without them those windows are left out.
private enum SkyLight {
    private typealias MainConnectionIDFunc = @convention(c) () -> Int32
    private typealias CopySpacesForWindowsFunc = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyManagedDisplaySpacesFunc = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias GetProcessForPIDFunc = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessWithOptionsFunc = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordToFunc = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        ?? dlopen(nil, RTLD_LAZY)

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let sym = dlsym(handle, name) ?? dlsym(dlopen(nil, RTLD_LAZY), name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static let connection: Int32? = symbol("CGSMainConnectionID", MainConnectionIDFunc.self)?()
    private static let copySpacesForWindows = symbol("CGSCopySpacesForWindows", CopySpacesForWindowsFunc.self)
    private static let copyManagedDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", CopyManagedDisplaySpacesFunc.self)
    private static let getProcessForPID = symbol("GetProcessForPID", GetProcessForPIDFunc.self)
    private static let setFrontProcessWithOptions = symbol("_SLPSSetFrontProcessWithOptions", SetFrontProcessWithOptionsFunc.self)
    private static let postEventRecordTo = symbol("SLPSPostEventRecordTo", PostEventRecordToFunc.self)

    /// Spaces shown right now, one per display; nil if unknown.
    static func currentSpaces() -> Set<UInt64>? {
        guard let connection = connection, let copy = copyManagedDisplaySpaces,
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        var ids = Set<UInt64>()
        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let id = (current["ManagedSpaceID"] ?? current["id64"]) as? NSNumber {
                ids.insert(id.uint64Value)
            }
        }
        return ids.isEmpty ? nil : ids
    }

    /// Spaces the window belongs to; empty for helper windows that are on none; nil if unknown.
    static func spaces(of windowID: CGWindowID) -> Set<UInt64>? {
        guard let connection = connection, let copy = copySpacesForWindows else { return nil }
        // 0x7: current, other and user Spaces
        let ids = copy(connection, 0x7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        return ids.map { Set($0.map { $0.uint64Value }) }
    }

    /// Makes the window the front one of its app, which also switches to its Space. Returns false if
    /// the calls are not available or failed.
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getProcessForPID = getProcessForPID, let setFront = setFrontProcessWithOptions else {
            return false
        }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        // 0x200: kCPSUserGenerated, as if the user had clicked the window
        guard setFront(&psn, windowID, 0x200) == .success else { return false }
        // Make it the key window, not just the front one (same event records as AltTab sends)
        if let post = postEventRecordTo {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: windowID) { widBytes in
                for (offset, byte) in widBytes.enumerated() {
                    bytes[0x3c + offset] = byte
                }
            }
            for offset in 0x20..<0x30 {
                bytes[offset] = 0xff
            }
            bytes[0x08] = 0x01
            _ = post(&psn, &bytes)
            bytes[0x08] = 0x02
            _ = post(&psn, &bytes)
        }
        return true
    }
}

/// What Accessibility says about one window of an app.
private struct AXWindowInfo {
    let element: AXUIElement
    /// 0 if unknown
    let id: CGWindowID
    let isMinimized: Bool
    let title: String
    /// A document or dialog window, not a panel, tooltip, sheet or popover
    let isStandard: Bool
}

public class WindowManager {
    public static let shared = WindowManager()

    /// Last captured image per window, scaled down. macOS cannot capture minimized windows, so
    /// they show the image from before they were minimized. Accessed only on cacheQueue.
    private var thumbnailCache: [CGWindowID: CGImage] = [:]
    private let cacheQueue = DispatchQueue(label: "AltSwitch.thumbnailCache", qos: .utility)
    private let maxCachedThumbnailWidth = 520
    private var lastBackgroundRefresh = Date.distantPast

    private init() {
        // Refresh the cache whenever the user switches apps: a window minimized afterwards
        // still has a recent image.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.refreshThumbnailCacheInBackground()
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.warmUp([app])
            }
        }
    }

    /// The first Accessibility call to an app is slow (~150 ms for ten apps here). Doing it in the
    /// background keeps that cost out of the first shortcut press.
    public func warmUp(_ apps: [NSRunningApplication]? = nil) {
        let currentPID = NSRunningApplication.current.processIdentifier
        let targets = (apps ?? NSWorkspace.shared.runningApplications).filter {
            $0.activationPolicy == .regular && $0.processIdentifier != currentPID
        }
        DispatchQueue.global(qos: .utility).async {
            for app in targets {
                _ = app.icon
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(appElement, 0.2)
                var windowListValue: AnyObject?
                AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue)
            }
        }
    }

    /// Cached images for the given windows, so cards show a preview right away instead of a placeholder.
    public func cachedThumbnails(for windows: [WindowItem]) -> [WindowItem] {
        let cache = cacheQueue.sync { thumbnailCache }
        return windows.map { item in
            var item = item
            item.thumbnail = item.thumbnail ?? cache[item.id]
            return item
        }
    }

    /// Starts observing app switches (the singleton is created lazily otherwise).
    public func startThumbnailCaching() {
        refreshThumbnailCacheInBackground()
    }

    /// All real windows of regular apps, like Alt-Tab on Windows: on-screen ones, minimized ones,
    /// those on other Spaces or in native full screen, and those of hidden apps. Ordered by last use.
    public func getOpenWindows() -> [WindowItem] {
        // One list of every window: on-screen only would leave out other Spaces, full screen and
        // hidden apps, so an app could vanish from the switcher entirely
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = NSRunningApplication.current.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != currentPID
        }
        var appByPID: [pid_t: NSRunningApplication] = [:]
        for app in regularApps {
            appByPID[app.processIdentifier] = app
        }

        // Windows as each app reports them. An app missing here did not answer (busy or timed out).
        var axWindowsByPID: [pid_t: [AXWindowInfo]] = [:]
        var axWindowByID: [CGWindowID: AXWindowInfo] = [:]
        for pid in regularApps.map({ $0.processIdentifier }) {
            guard let windows = axWindowInfos(of: pid) else { continue }
            axWindowsByPID[pid] = windows
            for window in windows where window.id != 0 {
                axWindowByID[window.id] = window
            }
        }

        // Looked up only when an off-screen window needs it
        var currentSpaces: Set<UInt64>?
        var currentSpacesLoaded = false
        func isOnOtherSpace(_ wid: CGWindowID) -> Bool {
            if !currentSpacesLoaded {
                currentSpaces = SkyLight.currentSpaces()
                currentSpacesLoaded = true
            }
            guard let current = currentSpaces,
                  let spaces = SkyLight.spaces(of: wid), !spaces.isEmpty else {
                return false
            }
            return spaces.isDisjoint(with: current)
        }

        var onScreen: [WindowItem] = []
        var offScreen: [WindowItem] = []
        var included = Set<CGWindowID>()

        for winInfo in infoList {
            guard let layer = winInfo[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = winInfo[kCGWindowNumber as String] as? CGWindowID,
                  let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let app = appByPID[pid],
                  let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 80, bounds.height >= 80 else {
                continue
            }

            let ax = axWindowByID[wid]
            let cgTitle = ((winInfo[kCGWindowName as String] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isVisible = winInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
            var isMinimized = false

            if isVisible {
                // Nearly transparent: an invisible helper window. A real window that is just
                // fading in or out stays, Accessibility knows it.
                let alpha = winInfo[kCGWindowAlpha as String] as? Double ?? 1.0
                guard alpha >= 0.05 || ax?.isStandard == true else { continue }
            } else if let ax = ax {
                // Off screen and known to the app: minimized, hidden app (⌘H) or another Space
                if ax.isMinimized {
                    isMinimized = true
                } else {
                    guard ax.isStandard, app.isHidden || isOnOtherSpace(wid) else { continue }
                }
            } else {
                // Accessibility does not list windows on other Spaces. Off-screen windows without a
                // title or not on any Space are helpers (menu bar, status items, drag images …).
                guard !cgTitle.isEmpty,
                      axWindowsByPID[pid] == nil || isOnOtherSpace(wid),
                      let spaces = SkyLight.spaces(of: wid), !spaces.isEmpty else {
                    continue
                }
            }

            let appName = (winInfo[kCGWindowOwnerName as String] as? String) ?? app.localizedName ?? "App"
            var title = cgTitle
            if title.isEmpty, let axTitle = ax?.title, !axTitle.isEmpty {
                title = axTitle
            }
            if title.isEmpty {
                title = appName
            }

            let item = WindowItem(
                id: wid,
                pid: pid,
                appName: appName,
                windowTitle: title,
                bounds: bounds,
                appIcon: app.icon,
                thumbnail: nil,
                isMinimized: isMinimized,
                runningApp: app,
                isOnScreen: isVisible
            )
            included.insert(wid)
            if isVisible {
                onScreen.append(item)
            } else {
                offScreen.append(item)
            }
        }

        // Minimized windows the window list did not show (or without a known window ID)
        var syntheticIdCounter: UInt32 = 0x80000000
        for app in regularApps {
            let pid = app.processIdentifier
            guard let windows = axWindowsByPID[pid] else { continue }
            for window in windows where window.isMinimized && !included.contains(window.id) {
                var id = window.id
                if id == 0 {
                    // Plain counter: OR-ing in pid and index made different windows share an ID
                    syntheticIdCounter += 1
                    id = CGWindowID(syntheticIdCounter)
                }
                included.insert(id)
                let appName = app.localizedName ?? "App"
                offScreen.append(WindowItem(
                    id: id,
                    pid: pid,
                    appName: appName,
                    windowTitle: window.title.isEmpty ? appName : window.title,
                    bounds: axFrame(of: window.element) ?? CGRect(x: 0, y: 0, width: 800, height: 600),
                    appIcon: app.icon,
                    thumbnail: nil,
                    isMinimized: true,
                    runningApp: app,
                    isOnScreen: false
                ))
            }
        }

        // Screen stacking order groups windows by app (activating an app raises all its windows):
        // order by when each window last had focus instead
        return WindowOrderTracker.shared.sortedByRecentUse(onScreen + offScreen)
    }

    /// The app's windows with the attributes needed to sort out junk, one Accessibility round trip
    /// per window. nil if the app does not answer.
    private func axWindowInfos(of pid: pid_t) -> [AXWindowInfo]? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        var windowListValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
              let windows = windowListValue as? [AXUIElement] else {
            return nil
        }

        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, kAXTitleAttribute] as CFArray
        return windows.map { window in
            var values: CFArray?
            var role: String?
            var subrole: String?
            var isMinimized = false
            var title = ""
            if AXUIElementCopyMultipleAttributeValues(window, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
               let array = values as? [AnyObject], array.count == 4 {
                // Attributes that could not be read come back as AXError values and fail these casts
                role = array[0] as? String
                subrole = array[1] as? String
                isMinimized = array[2] as? Bool ?? false
                title = array[3] as? String ?? ""
            }

            var wid: CGWindowID = 0
            if let getWindow = dynamicAXUIElementGetWindow, getWindow(window, &wid) != .success {
                wid = 0
            }

            let isStandard = role == kAXWindowRole as String
                && (subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String)
            return AXWindowInfo(element: window, id: wid, isMinimized: isMinimized, title: title, isStandard: isStandard)
        }
    }

    private func axFrame(of window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID(),
              AXValueGetValue(pv as! AXValue, .cgPoint, &point),
              AXValueGetValue(sv as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    /// Loads fresh window thumbnails asynchronously without blocking the main run loop. Minimized
    /// windows cannot be captured; they keep the cached image from cachedThumbnails(for:).
    public func loadThumbnailsAsync(for windows: [WindowItem], onThumbnail: @escaping (CGWindowID, CGImage) -> Void) {
        guard PermissionsManager.shared.isScreenRecordingGranted,
              let createImage = dynamicCGWindowListCreateImage else {
            return
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let listOptions: CGWindowListOption = [.optionIncludingWindow]
            let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]

            for item in windows {
                // Minimized, hidden or on another Space: a capture would be empty and overwrite the
                // cached image
                guard item.isOnScreen, !item.isMinimized else { continue }
                if let thumb = createImage(.null, listOptions, item.id, imageOptions)?.takeRetainedValue() {
                    DispatchQueue.main.async {
                        onThumbnail(item.id, thumb)
                    }
                    self?.storeInCache(thumb, for: item.id)
                }
            }
        }
    }

    /// Captures all on-screen windows into the cache (throttled, low priority).
    private func refreshThumbnailCacheInBackground() {
        guard Date().timeIntervalSince(lastBackgroundRefresh) > 2.0,
              PermissionsManager.shared.isScreenRecordingGranted,
              let createImage = dynamicCGWindowListCreateImage else {
            return
        }
        lastBackgroundRefresh = Date()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self,
                  let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                return
            }
            let currentPID = NSRunningApplication.current.processIdentifier
            var visibleIds: [CGWindowID] = []
            for winInfo in infoList {
                guard let layer = winInfo[kCGWindowLayer as String] as? Int, layer == 0,
                      let wid = winInfo[kCGWindowNumber as String] as? CGWindowID,
                      let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t, pid != currentPID,
                      let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                      bounds.width >= 80, bounds.height >= 80 else {
                    continue
                }
                visibleIds.append(wid)
                if let image = createImage(.null, [.optionIncludingWindow], wid, [.nominalResolution, .boundsIgnoreFraming])?.takeRetainedValue() {
                    self.storeInCache(image, for: wid)
                }
            }
            self.pruneCache(keeping: Set(visibleIds))
        }
    }

    private func storeInCache(_ image: CGImage, for id: CGWindowID) {
        guard image.width > 1, image.height > 1 else { return }
        let scaled = downscaled(image)
        cacheQueue.async { [weak self] in
            self?.thumbnailCache[id] = scaled
        }
    }

    /// Drops images of windows that no longer exist (closed windows, quit apps).
    private func pruneCache(keeping visibleIds: Set<CGWindowID>) {
        let existing = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var alive = visibleIds
        for info in existing {
            if let wid = info[kCGWindowNumber as String] as? CGWindowID {
                alive.insert(wid)
            }
        }
        cacheQueue.async { [weak self] in
            self?.thumbnailCache = self?.thumbnailCache.filter { alive.contains($0.key) } ?? [:]
        }
    }

    private func downscaled(_ image: CGImage) -> CGImage {
        guard image.width > maxCachedThumbnailWidth else { return image }
        let scale = CGFloat(maxCachedThumbnailWidth) / CGFloat(image.width)
        let width = maxCachedThumbnailWidth
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Brings the specified window to the front and activates its application. Works for minimized
    /// windows, windows of hidden apps and windows on other Spaces or in native full screen.
    public func activateWindow(_ item: WindowItem) {
        guard let app = item.runningApp ?? NSRunningApplication(processIdentifier: item.pid) else {
            return
        }

        // Unhide application if hidden
        if app.isHidden {
            app.unhide()
        }

        // Off screen but not minimized: on another Space, in full screen or of a hidden app.
        // Accessibility cannot reach other Spaces; the window server brings the window and
        // switches to its Space.
        let focusedAcrossSpaces = !item.isOnScreen && !item.isMinimized
            && SkyLight.focus(windowID: item.id, pid: item.pid)

        // Target window using Accessibility API
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowListValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue)

        if copyResult == .success, let axWindows = windowListValue as? [AXUIElement] {
            // 0. Exact match by window ID: windows of one app often share size and nearly the
            //    same position, so the geometry match below would pick the wrong one
            var matchedWindow = axWindow(withID: item.id, in: axWindows)

            // A window on another Space is not in the list (yet); guessing by size or title would
            // raise a different window of the app
            let mayGuess = item.isOnScreen || item.isMinimized

            // 1. If item.isMinimized, prioritize matching minimized windows by title
            if matchedWindow == nil && item.isMinimized {
                for axWin in axWindows {
                    var isMinVal: AnyObject?
                    if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &isMinVal) == .success,
                       let isMin = isMinVal as? Bool, isMin {
                        if !item.windowTitle.isEmpty && item.windowTitle != item.appName {
                            var titleVal: AnyObject?
                            if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal) == .success,
                               let title = titleVal as? String, title == item.windowTitle {
                                matchedWindow = axWin
                                break
                            }
                        } else {
                            matchedWindow = axWin
                            break
                        }
                    }
                }
            }

            // 2. Try matching by position and size
            if matchedWindow == nil && item.isOnScreen {
                for axWin in axWindows {
                    guard let frame = axFrame(of: axWin) else { continue }
                    if (abs(frame.origin.x - item.bounds.origin.x) < 35 && abs(frame.origin.y - item.bounds.origin.y) < 35) ||
                       (abs(frame.width - item.bounds.size.width) < 35 && abs(frame.height - item.bounds.size.height) < 35) {
                        matchedWindow = axWin
                        break
                    }
                }
            }

            // 3. Try matching by title if not matched by bounds
            if matchedWindow == nil && mayGuess && !item.windowTitle.isEmpty && item.windowTitle != item.appName {
                for axWin in axWindows {
                    var titleVal: AnyObject?
                    if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal) == .success,
                       let title = titleVal as? String, title == item.windowTitle {
                        matchedWindow = axWin
                        break
                    }
                }
            }

            // 4. Fallback to first window of app if still nil
            if matchedWindow == nil && mayGuess {
                matchedWindow = axWindows.first
            }

            if let target = matchedWindow {
                raise(target)
            }
        }

        if focusedAcrossSpaces {
            // Raise once more when the Space switch is done and the window is reachable
            let pid = item.pid
            let windowID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                let appElement = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(appElement, 0.25)
                var value: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                   let windows = value as? [AXUIElement],
                   let target = self.axWindow(withID: windowID, in: windows) {
                    self.raise(target)
                }
            }
            // The app is in front already; activating it again could switch to another of its Spaces
            return
        }

        // Activate application
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func axWindow(withID id: CGWindowID, in windows: [AXUIElement]) -> AXUIElement? {
        guard let getWindow = dynamicAXUIElementGetWindow else { return nil }
        return windows.first { axWin in
            var wid: CGWindowID = 0
            return getWindow(axWin, &wid) == .success && wid == id
        }
    }

    /// Restores the window if minimized, raises it and makes it the app's main window.
    private func raise(_ window: AXUIElement) {
        var isMin: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMin) == .success,
           let minVal = isMin as? Bool, minVal {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        WindowOrderTracker.shared.noteFocused(window: window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
