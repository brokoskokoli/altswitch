// SPDX-License-Identifier: MIT

import Cocoa
import SwiftUI

/// Scrolls the switcher's list while the pointer rests near its top or bottom (left or right in the
/// carousel): slowly at the start of the zone, faster the further the pointer goes towards and past
/// the edge. Driven by OverlayPanel's frame timer.
final class EdgeScroller {
    /// Depth of the zone inside the visible area where scrolling starts
    static let zoneDepth: CGFloat = 70
    /// How far past the edge the speed keeps growing (header and footer of the panel)
    static let overshoot: CGFloat = 40
    static let minSpeed: CGFloat = 60
    static let maxSpeed: CGFloat = 1400

    private weak var scrollView: NSScrollView?
    private var axis: Axis = .vertical
    /// Fractions of a pixel not scrolled yet, so slow speeds still move smoothly
    private var carry: CGFloat = 0

    func attach(_ scrollView: NSScrollView, axis: Axis) {
        if self.scrollView !== scrollView {
            carry = 0
        }
        self.scrollView = scrollView
        self.axis = axis
    }

    /// Points per second for a pointer `distance` points inside the visible edge (negative: past it),
    /// 0 outside the zone. Grows with the square of the depth, so the start of the zone is gentle.
    static func speed(distanceFromEdge distance: CGFloat, zone: CGFloat) -> CGFloat {
        let depth = zone - distance
        guard depth > 0, distance > -overshoot else { return 0 }
        let fraction = min(depth / (zone + overshoot), 1)
        return minSpeed + (maxSpeed - minSpeed) * fraction * fraction
    }

    /// Moves the list for `elapsed` seconds with the pointer at `pointer` (screen coordinates).
    func step(pointer: NSPoint, elapsed: TimeInterval) {
        guard let scrollView = scrollView, let window = scrollView.window,
              let documentView = scrollView.documentView,
              window.frame.contains(pointer) else {
            carry = 0
            return
        }
        let point = scrollView.convert(window.convertPoint(fromScreen: pointer), from: nil)
        let bounds = scrollView.bounds
        let clipView = scrollView.contentView

        // Distances to the leading (top, left) and trailing (bottom, right) edge as seen on screen
        let leading: CGFloat
        let length: CGFloat
        switch axis {
        case .vertical:
            guard point.x >= bounds.minX, point.x <= bounds.maxX else { carry = 0; return }
            leading = scrollView.isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
            length = bounds.height
        case .horizontal:
            guard point.y >= bounds.minY, point.y <= bounds.maxY else { carry = 0; return }
            leading = point.x - bounds.minX
            length = bounds.width
        }
        let trailing = length - leading
        let zone = min(Self.zoneDepth, length / 4)

        // Positive: towards the end of the list
        let velocity = Self.speed(distanceFromEdge: trailing, zone: zone)
            - Self.speed(distanceFromEdge: leading, zone: zone)
        guard velocity != 0 else {
            carry = 0
            return
        }

        // Whole device pixels only; the rest is kept for the next frame
        let scale = window.backingScaleFactor
        carry += velocity * CGFloat(elapsed)
        let delta = (carry * scale).rounded(.towardZero) / scale
        guard delta != 0 else { return }
        carry -= delta

        var origin = clipView.bounds.origin
        switch axis {
        case .vertical:
            // In a flipped document the end of the list lies at larger y
            origin.y += documentView.isFlipped ? delta : -delta
        case .horizontal:
            origin.x += delta
        }
        let constrained = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size)).origin
        guard constrained != clipView.bounds.origin else {
            // At the end of the list
            carry = 0
            return
        }
        clipView.scroll(to: constrained)
        scrollView.reflectScrolledClipView(clipView)
    }
}

/// Hands the enclosing NSScrollView of a SwiftUI ScrollView to an EdgeScroller. Place it as the
/// background of the scroll view's content.
struct EdgeScrollerAnchor: NSViewRepresentable {
    let scroller: EdgeScroller
    let axis: Axis

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onAttach = { [scroller, axis] scrollView in
            scroller.attach(scrollView, axis: axis)
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.onAttach = { [scroller, axis] scrollView in
            scroller.attach(scrollView, axis: axis)
        }
        nsView.attachIfPossible()
    }

    final class AnchorView: NSView {
        var onAttach: ((NSScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfPossible()
        }

        func attachIfPossible() {
            if window != nil, let scrollView = enclosingScrollView {
                onAttach?(scrollView)
            }
        }

        // Never in the way of clicks and hovering on the cards
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
