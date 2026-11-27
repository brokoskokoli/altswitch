// SPDX-License-Identifier: MIT

import CoreGraphics

/// Whether an entry of the window server's list is a real window for the switcher, and how it is
/// shown. Pure, so the rules can be tested; WindowManager.getOpenWindows feeds it.
enum WindowFilter {
    enum Decision: Equatable {
        case skip
        /// Visible right now
        case onScreen
        /// Hidden app (⌘H), another Space or native full screen
        case offScreen
        case minimized
    }

    /// What the window server says about one window
    struct Entry {
        var layer: Int
        var bounds: CGRect
        var isOnscreen: Bool
        var alpha: Double
        /// Title from the window list, trimmed; often empty without Screen Recording
        var title: String
    }

    /// What the app reports about it through Accessibility; nil if it does not list the window
    struct AXFacts {
        var isStandard: Bool
        var isMinimized: Bool
    }

    static let minimumSize: CGFloat = 80

    /// - Parameters:
    ///   - appListComplete: the app answered and reported all its windows
    ///   - wasFocused: the window had keyboard focus at some point (WindowOrderTracker)
    ///   - isOnOtherSpace, isOnAnySpace: asked only when needed (window server round trips)
    static func decide(
        _ entry: Entry,
        ax: AXFacts?,
        appIsHidden: Bool,
        appListComplete: Bool,
        wasFocused: Bool = false,
        isOnOtherSpace: () -> Bool,
        isOnAnySpace: () -> Bool
    ) -> Decision {
        // A small window the user worked in (a popup, a mini player) is a real window: skipping
        // it would make the switcher jump past it to the window used before
        let isLargeEnough = entry.bounds.width >= minimumSize && entry.bounds.height >= minimumSize
        guard entry.layer == 0, isLargeEnough || (wasFocused && !entry.bounds.isEmpty) else {
            return .skip
        }

        if entry.isOnscreen {
            // Nearly transparent: an invisible helper window. A real window that is just fading
            // in or out stays, Accessibility knows it.
            guard entry.alpha >= 0.05 || ax?.isStandard == true else { return .skip }
            return .onScreen
        }

        if let ax = ax {
            // Off screen and known to the app: minimized, hidden app (⌘H) or another Space
            if ax.isMinimized {
                return .minimized
            }
            guard ax.isStandard, appIsHidden || isOnOtherSpace() else { return .skip }
            return .offScreen
        }

        // Accessibility does not list windows on other Spaces. Off-screen windows without a title
        // or not on any Space are helpers (menu bar, status items, drag images …). An app that
        // did not report all its windows gets the benefit of the doubt.
        guard !entry.title.isEmpty,
              !appListComplete || isOnOtherSpace(),
              isOnAnySpace() else {
            return .skip
        }
        return .offScreen
    }

    /// Windows blocked by a modal dialog of their app (a password prompt, an alert). While it is
    /// open the app takes input only there: switching to another of its windows lands on the
    /// dialog again, so the switcher would get stuck on it. The dialog stands for all of them.
    /// - Parameter modalIDs: windows the apps report as modal; only those in the list count
    static func blockedByModal(_ windows: [(id: CGWindowID, pid: pid_t)], modalIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        let blockedPIDs = Set(windows.filter { modalIDs.contains($0.id) }.map(\.pid))
        return Set(windows.filter { blockedPIDs.contains($0.pid) && !modalIDs.contains($0.id) }.map(\.id))
    }

    /// Sheets to leave out (a password prompt slid out of a window, as in the Windows App). The
    /// window server lists a sheet as a window of its own, but it belongs to its window: switching
    /// to that window shows the sheet, and the window takes no input without it. Its window stands
    /// for it; a sheet whose window is not listed stays, so the two do not vanish together.
    /// - Parameter sheetParents: sheet → the window it belongs to
    static func hiddenSheets(listed: Set<CGWindowID>, sheetParents: [CGWindowID: CGWindowID]) -> Set<CGWindowID> {
        Set(sheetParents.filter { listed.contains($0.key) && listed.contains($0.value) }.keys)
    }
}
