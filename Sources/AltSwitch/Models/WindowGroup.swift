// SPDX-License-Identifier: MIT

import Cocoa

/// The windows of one app in the grouped list ("Grouped by App" layout).
public struct WindowGroup: Identifiable {
    public let pid: pid_t
    public let appName: String
    public let appIcon: NSImage?
    /// Most recently focused first
    public let windows: [WindowItem]
    /// Position of the group's first window in the flattened navigation order
    public let startIndex: Int

    public var id: pid_t { pid }

    public var indices: Range<Int> { startIndex..<(startIndex + windows.count) }

    /// Groups windows by app. `recentWindows` must be in most-recently-used order (as returned by
    /// WindowManager.getOpenWindows): keeping the order of first appearance then sorts the groups by
    /// the last time any of their windows had focus, and the windows inside each group by last
    /// focus. The current window (`recentWindows[0]`) is the first window of the first group.
    public static func grouped(_ recentWindows: [WindowItem]) -> [WindowGroup] {
        var order: [pid_t] = []
        var windowsByApp: [pid_t: [WindowItem]] = [:]
        for item in recentWindows {
            if windowsByApp[item.pid] == nil {
                order.append(item.pid)
                windowsByApp[item.pid] = []
            }
            windowsByApp[item.pid]?.append(item)
        }

        var groups: [WindowGroup] = []
        var start = 0
        for pid in order {
            guard let windows = windowsByApp[pid], let first = windows.first else { continue }
            groups.append(WindowGroup(
                pid: pid,
                appName: first.runningApp?.localizedName ?? first.appName,
                appIcon: first.appIcon,
                windows: windows,
                startIndex: start
            ))
            start += windows.count
        }
        return groups
    }

    /// Navigation order of the grouped list: the first group's windows, then the second group's …
    public static func flattened(_ groups: [WindowGroup]) -> [WindowItem] {
        groups.flatMap { $0.windows }
    }
}
