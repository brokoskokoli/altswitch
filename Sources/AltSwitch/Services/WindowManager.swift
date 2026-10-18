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
// find a minimized window's cached thumbnail, since minimized windows are not in the on-screen list.
private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private let dynamicAXUIElementGetWindow: AXUIElementGetWindowFunc? = {
    guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementGetWindow") else {
        return nil
    }
    return unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
}()

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
        ) { [weak self] _ in
            self?.refreshThumbnailCacheInBackground()
        }
    }

    /// Starts observing app switches (the singleton is created lazily otherwise).
    public func startThumbnailCaching() {
        refreshThumbnailCacheInBackground()
    }

    /// Retrieves a list of all currently open normal user windows in MRU (Z-order) front-to-back,
    /// followed by any minimized windows.
    public func getOpenWindows() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [WindowItem] = []
        let currentPID = NSRunningApplication.current.processIdentifier

        // Cache NSRunningApplication objects and AXUIElements by PID to avoid repeated lookups
        var appCache: [pid_t: NSRunningApplication] = [:]
        var axAppCache: [pid_t: AXUIElement] = [:]
        var axWindowsCache: [pid_t: [AXUIElement]] = [:]

        // MARK: - 1. On-Screen Windows (in MRU order)
        for winInfo in infoList {
            guard let layer = winInfo[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let wid = winInfo[kCGWindowNumber as String] as? CGWindowID,
                  let pid = winInfo[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            // Exclude our own app
            if pid == currentPID {
                continue
            }

            // Check window alpha
            let alpha = winInfo[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha < 0.05 {
                continue
            }

            // Check window bounds
            guard let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 80, bounds.height >= 80 else {
                continue
            }

            // Resolve running application
            let app: NSRunningApplication
            if let cached = appCache[pid] {
                app = cached
            } else if let running = NSRunningApplication(processIdentifier: pid) {
                appCache[pid] = running
                app = running
            } else {
                continue
            }

            // Filter out non-regular apps (system daemons, dock, etc.)
            guard app.activationPolicy == .regular else {
                continue
            }

            let appName = (winInfo[kCGWindowOwnerName as String] as? String)
                ?? app.localizedName
                ?? "App"

            var windowTitle = (winInfo[kCGWindowName as String] as? String) ?? ""
            if windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Try fetching title via AX if empty
                windowTitle = getAXWindowTitle(
                    pid: pid,
                    bounds: bounds,
                    appName: appName,
                    axAppCache: &axAppCache,
                    axWindowsCache: &axWindowsCache
                )
            }

            let appIcon = app.icon

            let item = WindowItem(
                id: wid,
                pid: pid,
                appName: appName,
                windowTitle: windowTitle,
                bounds: bounds,
                appIcon: appIcon,
                thumbnail: nil,
                isMinimized: false,
                runningApp: app
            )

            results.append(item)
        }

        // MARK: - 2. Minimized Windows
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != currentPID
        }

        var syntheticIdCounter: UInt32 = 0x80000000
        for app in regularApps {
            let pid = app.processIdentifier
            let appElement: AXUIElement
            if let cached = axAppCache[pid] {
                appElement = cached
            } else {
                appElement = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(appElement, 0.2)
                axAppCache[pid] = appElement
            }

            let axWindows: [AXUIElement]
            if let cached = axWindowsCache[pid] {
                axWindows = cached
            } else {
                var windowListValue: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
                   let wins = windowListValue as? [AXUIElement] {
                    axWindows = wins
                } else {
                    axWindows = []
                }
                axWindowsCache[pid] = axWindows
            }

            for axWin in axWindows {
                var minVal: AnyObject?
                if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minVal) == .success,
                   let isMin = minVal as? Bool, isMin {
                    var titleVal: AnyObject?
                    var title = ""
                    if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal) == .success,
                       let t = titleVal as? String {
                        title = t
                    }
                    let appName = app.localizedName ?? "App"
                    if title.isEmpty {
                        title = appName
                    }

                    var posValue: AnyObject?
                    var sizeValue: AnyObject?
                    AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posValue)
                    AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeValue)
                    var axPoint = CGPoint.zero
                    var axSize = CGSize(width: 800, height: 600)
                    if let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID() {
                        AXValueGetValue(pv as! AXValue, .cgPoint, &axPoint)
                    }
                    if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                        AXValueGetValue(sv as! AXValue, .cgSize, &axSize)
                    }

                    var realWid: CGWindowID = 0
                    if let getWindow = dynamicAXUIElementGetWindow,
                       getWindow(axWin, &realWid) == .success, realWid != 0 {
                        // Real ID: lets the cached thumbnail from before minimizing be found
                    } else {
                        // Plain counter: OR-ing in pid and index made different windows share an ID
                        syntheticIdCounter += 1
                        realWid = CGWindowID(syntheticIdCounter)
                    }

                    let item = WindowItem(
                        id: realWid,
                        pid: pid,
                        appName: appName,
                        windowTitle: title,
                        bounds: CGRect(origin: axPoint, size: axSize),
                        appIcon: app.icon,
                        thumbnail: nil,
                        isMinimized: true,
                        runningApp: app
                    )
                    results.append(item)
                }
            }
        }

        // One card per window, even if a window shows up in both lists
        var seen = Set<CGWindowID>()
        return results.filter { seen.insert($0.id).inserted }
    }

    /// Loads window thumbnails asynchronously without blocking the main run loop.
    /// Minimized windows get their cached image from before they were minimized.
    public func loadThumbnailsAsync(for windows: [WindowItem], onThumbnail: @escaping (CGWindowID, CGImage) -> Void) {
        guard PermissionsManager.shared.isScreenRecordingGranted,
              let createImage = dynamicCGWindowListCreateImage else {
            return
        }

        // Minimized windows cannot be captured: show their image from before minimizing
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            for item in windows where item.isMinimized {
                if let cached = self.thumbnailCache[item.id] {
                    DispatchQueue.main.async {
                        onThumbnail(item.id, cached)
                    }
                }
            }
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let listOptions: CGWindowListOption = [.optionIncludingWindow]
            let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]

            for item in windows {
                guard !item.isMinimized else { continue }
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

    /// Brings the specified window to the front and activates its application.
    public func activateWindow(_ item: WindowItem) {
        guard let app = item.runningApp ?? NSRunningApplication(processIdentifier: item.pid) else {
            return
        }

        // Unhide application if hidden
        if app.isHidden {
            app.unhide()
        }

        // Target window using Accessibility API
        let appElement = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var windowListValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue)

        if copyResult == .success, let axWindows = windowListValue as? [AXUIElement] {
            var matchedWindow: AXUIElement?

            // 1. If item.isMinimized, prioritize matching minimized windows by title
            if item.isMinimized {
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
            if matchedWindow == nil && !item.isMinimized {
                for axWin in axWindows {
                    var posValue: AnyObject?
                    var sizeValue: AnyObject?
                    AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posValue)
                    AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeValue)

                    var axPoint = CGPoint.zero
                    var axSize = CGSize.zero
                    if let posVal = posValue, CFGetTypeID(posVal) == AXValueGetTypeID() {
                        AXValueGetValue(posVal as! AXValue, .cgPoint, &axPoint)
                    }
                    if let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
                        AXValueGetValue(sizeVal as! AXValue, .cgSize, &axSize)
                    }

                    if (abs(axPoint.x - item.bounds.origin.x) < 35 && abs(axPoint.y - item.bounds.origin.y) < 35) ||
                       (abs(axSize.width - item.bounds.size.width) < 35 && abs(axSize.height - item.bounds.size.height) < 35) {
                        matchedWindow = axWin
                        break
                    }
                }
            }

            // 3. Try matching by title if not matched by bounds
            if matchedWindow == nil && !item.windowTitle.isEmpty && item.windowTitle != item.appName {
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
            if matchedWindow == nil {
                matchedWindow = axWindows.first
            }

            if let target = matchedWindow {
                // If minimized, restore it
                var isMin: AnyObject?
                if AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &isMin) == .success,
                   let minVal = isMin as? Bool, minVal {
                    AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }

                // Raise window to the front and make main
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
        }

        // Activate application
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func getAXWindowTitle(
        pid: pid_t,
        bounds: CGRect,
        appName: String,
        axAppCache: inout [pid_t: AXUIElement],
        axWindowsCache: inout [pid_t: [AXUIElement]]
    ) -> String {
        let appElement: AXUIElement
        if let cached = axAppCache[pid] {
            appElement = cached
        } else {
            appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            axAppCache[pid] = appElement
        }

        let axWindows: [AXUIElement]
        if let cached = axWindowsCache[pid] {
            axWindows = cached
        } else {
            var windowListValue: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowListValue) == .success,
               let wins = windowListValue as? [AXUIElement] {
                axWindows = wins
            } else {
                axWindows = []
            }
            axWindowsCache[pid] = axWindows
        }

        // Single window optimization
        if axWindows.count == 1, let singleWin = axWindows.first {
            var titleVal: AnyObject?
            if AXUIElementCopyAttributeValue(singleWin, kAXTitleAttribute as CFString, &titleVal) == .success,
               let t = titleVal as? String, !t.isEmpty {
                return t
            }
        }

        // Multiple windows: match by geometry
        for axWin in axWindows {
            var posValue: AnyObject?
            var sizeValue: AnyObject?
            AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posValue)
            AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeValue)

            var axPoint = CGPoint.zero
            var axSize = CGSize.zero
            if let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID() {
                AXValueGetValue(pv as! AXValue, .cgPoint, &axPoint)
            }
            if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &axSize)
            }

            if (abs(axPoint.x - bounds.origin.x) < 40 && abs(axPoint.y - bounds.origin.y) < 40) ||
               (abs(axSize.width - bounds.width) < 40 && abs(axSize.height - bounds.height) < 40) {
                var titleVal: AnyObject?
                if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal) == .success,
                   let t = titleVal as? String, !t.isEmpty {
                    return t
                }
            }
        }

        return appName
    }
}
