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
    ///   - isOnOtherSpace, isOnAnySpace: asked only when needed (window server round trips)
    static func decide(
        _ entry: Entry,
        ax: AXFacts?,
        appIsHidden: Bool,
        appListComplete: Bool,
        isOnOtherSpace: () -> Bool,
        isOnAnySpace: () -> Bool
    ) -> Decision {
        guard entry.layer == 0,
              entry.bounds.width >= minimumSize, entry.bounds.height >= minimumSize else {
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
}
