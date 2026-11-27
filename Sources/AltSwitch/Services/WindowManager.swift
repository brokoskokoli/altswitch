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

    /// Which of the private calls this macOS has, for the diagnostics
    static var availability: String {
        let spaces = connection != nil && copySpacesForWindows != nil && copyManagedDisplaySpaces != nil
        let focus = getProcessForPID != nil && setFrontProcessWithOptions != nil && postEventRecordTo != nil
        return "Spaces \(spaces ? "yes" : "no"), focus across Spaces \(focus ? "yes" : "no")"
    }

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

/// What Accessibility says about an app's windows.
private struct AXWindowList {
    let windows: [AXWindowInfo]
    /// false if the app stopped answering before all its windows were read
    let isComplete: Bool
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
    /// A dialog the app runs modally: its other windows take no input while it is open
    let isModal: Bool
}

public class WindowManager {
    public static let shared = WindowManager()

    /// False once a macOS version drops CGWindowListCreateImage: no previews at all then.
    public static var isCaptureAvailable: Bool {
        dynamicCGWindowListCreateImage != nil
    }

    /// Last captured image per window, scaled down. macOS cannot capture minimized windows, so
    /// they show the image from before they were minimized. Accessed only on cacheQueue.
    private var thumbnailCache: [CGWindowID: CGImage] = [:]
    private let cacheQueue = DispatchQueue(label: "AltSwitch.thumbnailCache", qos: .utility)
    private let maxCachedThumbnailWidth = 520
    private var lastBackgroundRefresh = Date.distantPast
    /// The app in front before the last app switch. Main thread only.
    private var frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    private var lastPrepareForPress = Date.distantPast
    /// Regular apps as read by prepareForPress, for the next press only. Main thread only.
    private var preparedRegularApps: (apps: [NSRunningApplication], time: CFTimeInterval)?
    /// App icons by process. Loading an icon takes ~0.1–2 ms and the overlay needs one per window
    /// on every press. Main thread only.
    private var iconCache: [pid_t: NSImage] = [:]
    /// PIDs of the regular apps from the last window list, so the background capture after every
    /// app switch does not ask LaunchServices about all processes again (~20 ms). Main thread only.
    private var lastRegularPIDs: (pids: Set<pid_t>, time: CFTimeInterval)?
    /// Size of the last window list (windows, apps), for the diagnostics
    public private(set) var lastListSize: (windows: Int, apps: Int)?

    /// Which private calls are available on this macOS, for the diagnostics
    public static var privateCallsAvailability: String {
        "\(SkyLight.availability), window IDs \(dynamicAXUIElementGetWindow != nil ? "yes" : "no")"
    }

    private init() {
        // Refresh the cache whenever the user switches apps: a window minimized afterwards
        // still has a recent image.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let left = self.frontmostPID
            self.frontmostPID = app?.processIdentifier
            self.refreshThumbnailCacheInBackground(activated: app, left: left)
            if let app = app {
                self.warmUp([app])
            }
        }
        // A new process may get the same PID
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.iconCache[app.processIdentifier] = nil
            }
        }
    }

    /// The first Accessibility call to an app is slow (~20 ms each, ~300 ms for 15 apps one after
    /// the other here). Doing it in the background, for all apps at once (~50 ms), keeps that cost
    /// out of the first shortcut press and out of the launch.
    public func warmUp(_ apps: [NSRunningApplication]? = nil) {
        let currentPID = NSRunningApplication.current.processIdentifier
        let candidates = apps ?? NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .utility).async {
            let targets = candidates.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != currentPID
            }
            DispatchQueue.concurrentPerform(iterations: targets.count) { index in
                let app = targets[index]
                _ = app.icon
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(appElement, 0.2)
                var windowListValue: AnyObject?
                AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue)
            }
        }
    }

    /// Called when the shortcut's modifier goes down, shortly before the shortcut itself. Finding
    /// the regular apps asks LaunchServices about every running process (~110 here), which takes
    /// 5–20 ms whenever its data has gone stale, and it goes stale within a fraction of a second.
    /// Reading it now, in the background, keeps that out of the shortcut press.
    public func prepareForPress() {
        guard Date().timeIntervalSince(lastPrepareForPress) > 0.5 else { return }
        lastPrepareForPress = Date()
        let apps = NSWorkspace.shared.runningApplications
        let currentPID = NSRunningApplication.current.processIdentifier
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let regular = apps.filter { $0.activationPolicy == .regular && $0.processIdentifier != currentPID }
            let time = CACurrentMediaTime()
            DispatchQueue.main.async {
                self?.preparedRegularApps = (regular, time)
            }
        }
    }

    /// The regular apps from prepareForPress if they are at most a second old, else read now.
    private func takeRegularApps() -> [NSRunningApplication] {
        defer { preparedRegularApps = nil }
        if let prepared = preparedRegularApps, CACurrentMediaTime() - prepared.time < 1.0 {
            return prepared.apps
        }
        let currentPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != currentPID
        }
    }

    private func icon(of app: NSRunningApplication) -> NSImage? {
        if let cached = iconCache[app.processIdentifier] {
            return cached
        }
        let icon = app.icon
        iconCache[app.processIdentifier] = icon
        return icon
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

        let regularApps = takeRegularApps()
        lastRegularPIDs = (Set(regularApps.map(\.processIdentifier)), CACurrentMediaTime())
        let tracker = WindowOrderTracker.shared
        tracker.refresh(regularApps: regularApps)
        var appByPID: [pid_t: NSRunningApplication] = [:]
        for app in regularApps {
            appByPID[app.processIdentifier] = app
        }

        // Windows as each app reports them. An app missing here did not answer (busy or timed out).
        // All apps at once: each call waits for the app to answer, so one app after the other the
        // waits add up (~10–40 ms here), and one app running into the timeout would delay the rest.
        var fetched = [AXWindowList?](repeating: nil, count: regularApps.count)
        fetched.withUnsafeMutableBufferPointer { slots in
            DispatchQueue.concurrentPerform(iterations: regularApps.count) { index in
                slots[index] = axWindowInfos(of: regularApps[index].processIdentifier)
            }
        }
        var axWindowsByPID: [pid_t: [AXWindowInfo]] = [:]
        // Apps that reported all their windows; an app that stopped answering midway is not
        // among them, its other windows are judged as if it had not answered at all
        var completeAXPIDs = Set<pid_t>()
        var axWindowByID: [CGWindowID: AXWindowInfo] = [:]
        for (app, list) in zip(regularApps, fetched) {
            guard let list = list else { continue }
            let pid = app.processIdentifier
            axWindowsByPID[pid] = list.windows
            if list.isComplete {
                completeAXPIDs.insert(pid)
            }
            for window in list.windows where window.id != 0 {
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
        // Apps with a visible window they do not list themselves: it may be a sheet
        var pidsWithUnlistedWindows = Set<pid_t>()

        for winInfo in infoList {
            guard let layer = winInfo[kCGWindowLayer as String] as? Int,
                  let wid = winInfo[kCGWindowNumber as String] as? CGWindowID,
                  let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let app = appByPID[pid],
                  let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let ax = axWindowByID[wid]
            let cgTitle = ((winInfo[kCGWindowName as String] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isVisible = winInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
            let entry = WindowFilter.Entry(
                layer: layer,
                bounds: bounds,
                isOnscreen: isVisible,
                alpha: winInfo[kCGWindowAlpha as String] as? Double ?? 1.0,
                title: cgTitle
            )
            let decision = WindowFilter.decide(
                entry,
                ax: ax.map { WindowFilter.AXFacts(isStandard: $0.isStandard, isMinimized: $0.isMinimized) },
                appIsHidden: app.isHidden,
                appListComplete: completeAXPIDs.contains(pid),
                wasFocused: tracker.wasFocused(wid),
                isOnOtherSpace: { isOnOtherSpace(wid) },
                isOnAnySpace: { !(SkyLight.spaces(of: wid) ?? []).isEmpty }
            )
            if decision == .skip {
                continue
            }
            let isMinimized = decision == .minimized
            if ax == nil && isVisible && completeAXPIDs.contains(pid) {
                pidsWithUnlistedWindows.insert(pid)
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
                appIcon: icon(of: app),
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
                    appIcon: icon(of: app),
                    thumbnail: nil,
                    isMinimized: true,
                    runningApp: app,
                    isOnScreen: false
                ))
            }
        }

        // An open modal dialog stands for all windows of its app (WindowFilter.blockedByModal)
        let modalIDs = Set(axWindowByID.values.filter { $0.isModal && !$0.isMinimized }.map(\.id))
        var all = onScreen + offScreen
        if !modalIDs.isEmpty {
            let blocked = WindowFilter.blockedByModal(all.map { ($0.id, $0.pid) }, modalIDs: modalIDs)
            all.removeAll { blocked.contains($0.id) }
        }
        var sheetParents: [CGWindowID: CGWindowID] = [:]
        for pid in pidsWithUnlistedWindows {
            sheetParents.merge(self.sheetParents(of: axWindowsByPID[pid] ?? [])) { first, _ in first }
        }
        if !sheetParents.isEmpty {
            let hidden = WindowFilter.hiddenSheets(listed: Set(all.map(\.id)), sheetParents: sheetParents)
            all.removeAll { hidden.contains($0.id) }
        }
        lastListSize = (all.count, Set(all.map(\.pid)).count)
        // Screen stacking order groups windows by app (activating an app raises all its windows):
        // order by when each window last had focus instead
        return tracker.sortedByRecentUse(all)
    }

    /// The app's windows with the attributes needed to sort out junk, one Accessibility round trip
    /// per window. nil if the app does not answer.
    private func axWindowInfos(of pid: pid_t) -> AXWindowList? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        var windowListValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
              let windows = windowListValue as? [AXUIElement] else {
            return nil
        }

        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, kAXTitleAttribute, kAXModalAttribute] as CFArray
        var infos: [AXWindowInfo] = []
        for window in windows {
            var values: CFArray?
            var role: String?
            var subrole: String?
            var isMinimized = false
            var title = ""
            var isModal = false
            let result = AXUIElementCopyMultipleAttributeValues(window, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
            // The app stopped answering: each further window would wait for the timeout again.
            // Keep what was read and mark the list incomplete; with nothing read it counts as no answer.
            if result == .cannotComplete {
                return infos.isEmpty ? nil : AXWindowList(windows: infos, isComplete: false)
            }
            if result == .success, let array = values as? [AnyObject], array.count == 5 {
                // Attributes that could not be read come back as AXError values and fail these casts
                role = array[0] as? String
                subrole = array[1] as? String
                isMinimized = array[2] as? Bool ?? false
                title = array[3] as? String ?? ""
                isModal = array[4] as? Bool ?? false
            }

            var wid: CGWindowID = 0
            if let getWindow = dynamicAXUIElementGetWindow, getWindow(window, &wid) != .success {
                wid = 0
            }

            let isStandard = role == kAXWindowRole as String
                && (subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String)
            infos.append(AXWindowInfo(element: window, id: wid, isMinimized: isMinimized, title: title,
                                      isStandard: isStandard, isModal: isModal && role == kAXWindowRole as String))
        }
        return AXWindowList(windows: infos, isComplete: true)
    }

    /// The sheets on the app's visible windows: sheet → its window. Sheets are not in the app's
    /// window list, only among the children of their window.
    private func sheetParents(of windows: [AXWindowInfo]) -> [CGWindowID: CGWindowID] {
        guard let getWindow = dynamicAXUIElementGetWindow else { return [:] }
        var parents: [CGWindowID: CGWindowID] = [:]
        for window in windows where window.id != 0 && !window.isMinimized {
            AXUIElementSetMessagingTimeout(window.element, 0.2)
            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(window.element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else {
                continue
            }
            for child in children {
                var role: AnyObject?
                var sheetID: CGWindowID = 0
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                   role as? String == kAXSheetRole as String,
                   getWindow(child, &sheetID) == .success, sheetID != 0 {
                    parents[sheetID] = window.id
                }
            }
        }
        return parents
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

        // Minimized, hidden or on another Space: a capture would be empty and overwrite the cached image
        let targets = windows.filter { $0.isOnScreen && !$0.isMinimized }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let listOptions: CGWindowListOption = [.optionIncludingWindow]

            // Several windows at once: one after the other, 16 windows took ~400 ms here, mostly
            // spent scaling down Retina-sized captures
            DispatchQueue.concurrentPerform(iterations: targets.count) { index in
                let item = targets[index]
                // The card shows at most 220 pt; the cached size covers that on Retina. A window at
                // least that wide in points gives enough pixels without the 4x of a Retina capture.
                let resolution: CGWindowImageOption = item.bounds.width >= CGFloat(self.maxCachedThumbnailWidth)
                    ? .nominalResolution : .bestResolution
                guard let thumb = createImage(.null, listOptions, item.id, [resolution, .boundsIgnoreFraming])?.takeRetainedValue() else {
                    return
                }
                // The card gets the small image too: a full Retina capture per card only costs
                // memory and drawing time
                let scaled = self.downscaled(thumb)
                DispatchQueue.main.async {
                    onThumbnail(item.id, scaled)
                }
                self.storeScaledInCache(scaled, for: item.id)
            }
        }
    }

    /// Captures on-screen windows into the cache (throttled, low priority). After an app switch
    /// (`left`: the app in front before) only the windows of the app left and windows without an
    /// image yet: the others did not have focus, so their image is mostly still current. Every
    /// capture costs ~10 ms of CPU and leaks 176 bytes inside macOS (CGWindowListCreateImage hands
    /// over to ScreenCaptureKit and does not free a dictionary; seen up to macOS 27).
    /// `activated`: the app the user just switched to.
    private func refreshThumbnailCacheInBackground(activated: NSRunningApplication? = nil, left: pid_t? = nil) {
        guard Date().timeIntervalSince(lastBackgroundRefresh) > (left == nil ? 2.0 : 0.5),
              PermissionsManager.shared.isScreenRecordingGranted,
              let createImage = dynamicCGWindowListCreateImage else {
            return
        }
        lastBackgroundRefresh = Date()

        // The apps of the last window list plus the one just activated (it may have been
        // launched since); after a while without a press, all apps are read again
        var knownPIDs: Set<pid_t>?
        if let last = lastRegularPIDs, CACurrentMediaTime() - last.time < 300 {
            knownPIDs = last.pids
            if let app = activated, app.activationPolicy == .regular {
                knownPIDs?.insert(app.processIdentifier)
            }
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self,
                  let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                return
            }
            let start = PerfLog.now()
            defer { PerfLog.log("background capture", since: start) }
            let currentPID = NSRunningApplication.current.processIdentifier
            // Only apps the switcher lists: windows of background agents and helpers would be
            // captured and kept for nothing
            let regularPIDs = knownPIDs ?? Set(NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != currentPID }
                .map(\.processIdentifier))
            let cachedIDs = left == nil ? [] : self.cacheQueue.sync { Set(self.thumbnailCache.keys) }
            var visibleIds: [CGWindowID] = []
            for winInfo in infoList {
                guard let layer = winInfo[kCGWindowLayer as String] as? Int, layer == 0,
                      let wid = winInfo[kCGWindowNumber as String] as? CGWindowID,
                      let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t, regularPIDs.contains(pid),
                      let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                      bounds.width >= 80, bounds.height >= 80 else {
                    continue
                }
                visibleIds.append(wid)
                if left != nil, pid != left, cachedIDs.contains(wid) {
                    continue
                }
                if let image = createImage(.null, [.optionIncludingWindow], wid, [.nominalResolution, .boundsIgnoreFraming])?.takeRetainedValue() {
                    self.storeInCache(image, for: wid)
                }
            }
            self.pruneCache(keeping: Set(visibleIds))
        }
    }

    private func storeInCache(_ image: CGImage, for id: CGWindowID) {
        guard image.width > 1, image.height > 1 else { return }
        storeScaledInCache(downscaled(image), for: id)
    }

    private func storeScaledInCache(_ scaled: CGImage, for id: CGWindowID) {
        guard scaled.width > 1, scaled.height > 1 else { return }
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
                    // Position and size: windows of one app often share one of the two
                    if (abs(frame.origin.x - item.bounds.origin.x) < 35 && abs(frame.origin.y - item.bounds.origin.y) < 35) &&
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

    /// Presses the window's close button, as a click on it would: the app may still ask whether to
    /// save. Returns false if the window or its close button cannot be reached (e.g. on another Space).
    public func closeWindow(_ item: WindowItem) -> Bool {
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowListValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
              let axWindows = windowListValue as? [AXUIElement],
              let window = axWindow(withID: item.id, in: axWindows) else {
            return false
        }
        var buttonValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &buttonValue) == .success,
              let buttonRef = buttonValue, CFGetTypeID(buttonRef) == AXUIElementGetTypeID() else {
            return false
        }
        return AXUIElementPerformAction(buttonRef as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Whether the window server still has the window (closing may take a moment or wait for a dialog)
    public func windowExists(_ id: CGWindowID) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else {
            return false
        }
        return !info.isEmpty
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
