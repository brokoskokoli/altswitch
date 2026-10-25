// SPDX-License-Identifier: MIT

import Cocoa

public struct WindowItem: Identifiable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let windowTitle: String
    public let bounds: CGRect
    public let appIcon: NSImage?
    public var thumbnail: CGImage?
    public let isMinimized: Bool
    public let runningApp: NSRunningApplication?
    /// False for windows that cannot be seen right now: minimized, on another Space (also native
    /// full screen) or of a hidden app. They cannot be captured, so the cached image is shown.
    public let isOnScreen: Bool

    public init(
        id: CGWindowID,
        pid: pid_t,
        appName: String,
        windowTitle: String,
        bounds: CGRect,
        appIcon: NSImage?,
        thumbnail: CGImage?,
        isMinimized: Bool = false,
        runningApp: NSRunningApplication? = nil,
        isOnScreen: Bool = true
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.windowTitle = windowTitle
        self.bounds = bounds
        self.appIcon = appIcon
        self.thumbnail = thumbnail
        self.isMinimized = isMinimized
        self.runningApp = runningApp
        self.isOnScreen = isOnScreen
    }

    public static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}
