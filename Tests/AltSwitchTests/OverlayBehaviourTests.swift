// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing
@testable import AltSwitch

private func item(_ id: CGWindowID, app: String = "App") -> WindowItem {
    // One process per app name
    WindowItem(id: id, pid: app == "B" ? 2 : 1, appName: app, windowTitle: "w\(id)", bounds: .zero, appIcon: nil, thumbnail: nil)
}

@Suite("Edge scrolling")
struct EdgeScrollerTests {
    @Test("No scrolling outside the zone, slow at its start, fastest at and past the edge")
    func speedCurve() {
        let zone: CGFloat = 70
        #expect(EdgeScroller.speed(distanceFromEdge: 100, zone: zone) == 0)
        #expect(EdgeScroller.speed(distanceFromEdge: zone, zone: zone) == 0)

        let start = EdgeScroller.speed(distanceFromEdge: zone - 5, zone: zone)
        let middle = EdgeScroller.speed(distanceFromEdge: 20, zone: zone)
        let edge = EdgeScroller.speed(distanceFromEdge: 0, zone: zone)
        let past = EdgeScroller.speed(distanceFromEdge: -EdgeScroller.overshoot + 1, zone: zone)
        #expect(start < 100)
        #expect(start < middle && middle < edge && edge < past)
        #expect(past <= EdgeScroller.maxSpeed)
        // Far outside the list (another part of the screen): nothing
        #expect(EdgeScroller.speed(distanceFromEdge: -200, zone: zone) == 0)
    }
}

@Suite("Closing windows from the switcher")
struct OverlayCloseTests {
    @Test("A click switches, with the close key held it asks to close instead")
    func clickClosesWhileKeyHeld() {
        let model = OverlayViewModel()
        model.present(recentWindows: [item(1), item(2)], initialIndex: 0, layout: .compact)
        var chosen: [CGWindowID] = []
        var closed: [CGWindowID] = []
        model.onSelectWindow = { chosen.append($0.id) }
        model.onCloseWindow = { closed.append($0.id) }

        model.isCloseKeyHeld = true
        model.click(at: 1)
        #expect(closed == [2] && chosen.isEmpty)

        model.isCloseKeyHeld = false
        model.click(at: 0)
        #expect(chosen == [1])
    }

    @Test("Removing the selected window selects the one that takes its place")
    func removeSelected() {
        let model = OverlayViewModel()
        model.present(recentWindows: [item(1), item(2), item(3)], initialIndex: 1, layout: .grid)
        model.removeWindow(id: 2)
        #expect(model.windows.map(\.id) == [1, 3])
        #expect(model.selectedIndex == 1)

        // Last one removed: the selection moves back
        model.removeWindow(id: 3)
        #expect(model.selectedIndex == 0)
        model.removeWindow(id: 1)
        #expect(model.windows.isEmpty && model.selectedIndex == 0)
    }

    @Test("Removing another window keeps the selection on the same window, also in the grouped list")
    func removeOtherKeepsSelection() {
        let model = OverlayViewModel()
        let windows = [item(1, app: "A"), item(2, app: "B"), item(3, app: "A")]
        model.present(recentWindows: windows, initialIndex: 1, layout: .grouped)
        let selected = model.windows[model.selectedIndex].id
        model.removeWindow(id: 1)
        #expect(model.windows[model.selectedIndex].id == selected)
        #expect(model.recentWindows.map(\.id) == [2, 3])
        #expect(model.groups.count == 2)
    }
}
