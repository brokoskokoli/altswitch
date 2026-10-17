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

public class WindowManager {
    public static let shared = WindowManager()

    private init() {}

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

            for (idx, axWin) in axWindows.enumerated() {
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

                    syntheticIdCounter += 1
                    let syntheticWid = CGWindowID(syntheticIdCounter | (UInt32(pid) << 8) | UInt32(idx & 0xFF))

                    let item = WindowItem(
                        id: syntheticWid,
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

        return results
    }

    /// Loads window thumbnails asynchronously without blocking the main run loop.
    public func loadThumbnailsAsync(for windows: [WindowItem], onThumbnail: @escaping (CGWindowID, CGImage) -> Void) {
        guard PermissionsManager.shared.isScreenRecordingGranted,
              let createImage = dynamicCGWindowListCreateImage else {
            return
        }

        DispatchQueue.global(qos: .userInteractive).async {
            let listOptions: CGWindowListOption = [.optionIncludingWindow]
            let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]

            for item in windows {
                guard !item.isMinimized else { continue }
                if let thumb = createImage(.null, listOptions, item.id, imageOptions)?.takeRetainedValue() {
                    DispatchQueue.main.async {
                        onThumbnail(item.id, thumb)
                    }
                }
            }
        }
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
