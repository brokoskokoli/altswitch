// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing
@testable import AltSwitch

private typealias Decision = WindowFilter.Decision

private func entry(
    layer: Int = 0,
    size: CGFloat = 600,
    onscreen: Bool = true,
    alpha: Double = 1,
    title: String = "Document"
) -> WindowFilter.Entry {
    WindowFilter.Entry(layer: layer, bounds: CGRect(x: 0, y: 0, width: size, height: size),
                       isOnscreen: onscreen, alpha: alpha, title: title)
}

private let standard = WindowFilter.AXFacts(isStandard: true, isMinimized: false)
private let panel = WindowFilter.AXFacts(isStandard: false, isMinimized: false)
private let minimized = WindowFilter.AXFacts(isStandard: true, isMinimized: true)

private func decide(
    _ entry: WindowFilter.Entry,
    ax: WindowFilter.AXFacts? = nil,
    hidden: Bool = false,
    complete: Bool = true,
    otherSpace: Bool = false,
    anySpace: Bool = true
) -> Decision {
    WindowFilter.decide(entry, ax: ax, appIsHidden: hidden, appListComplete: complete,
                        isOnOtherSpace: { otherSpace }, isOnAnySpace: { anySpace })
}

@Suite("Window filter")
struct WindowFilterTests {
    @Test("A normal visible window is shown")
    func visibleWindow() {
        #expect(decide(entry(), ax: standard) == .onScreen)
        // Also when the app did not answer
        #expect(decide(entry(), complete: false) == .onScreen)
    }

    @Test("Menus, overlays and tiny helper windows are left out")
    func helpers() {
        #expect(decide(entry(layer: 25), ax: standard) == .skip)
        #expect(decide(entry(size: 40), ax: standard) == .skip)
    }

    @Test("A transparent window is a helper, unless the app calls it a real window (fading in)")
    func transparent() {
        #expect(decide(entry(alpha: 0)) == .skip)
        #expect(decide(entry(alpha: 0), ax: panel) == .skip)
        #expect(decide(entry(alpha: 0), ax: standard) == .onScreen)
    }

    @Test("Minimized windows are shown as minimized")
    func minimizedWindow() {
        #expect(decide(entry(onscreen: false), ax: minimized) == .minimized)
    }

    @Test("Windows of a hidden app (⌘H) are shown, its panels are not")
    func hiddenApp() {
        #expect(decide(entry(onscreen: false), ax: standard, hidden: true) == .offScreen)
        #expect(decide(entry(onscreen: false), ax: panel, hidden: true) == .skip)
    }

    @Test("An off-screen window the app knows: only if it is on another Space")
    func knownOffScreen() {
        #expect(decide(entry(onscreen: false), ax: standard, otherSpace: true) == .offScreen)
        // Not hidden, not on another Space: a window the app keeps around invisibly
        #expect(decide(entry(onscreen: false), ax: standard, otherSpace: false) == .skip)
    }

    @Test("Windows on other Spaces are not listed by Accessibility: kept with a title and a Space")
    func otherSpaceWithoutAX() {
        #expect(decide(entry(onscreen: false), otherSpace: true) == .offScreen)
        #expect(decide(entry(onscreen: false, title: ""), otherSpace: true) == .skip)
        #expect(decide(entry(onscreen: false), otherSpace: true, anySpace: false) == .skip)
    }

    @Test("An app that answered completely: an unknown off-screen window on this Space is a helper")
    func completeAppUnknownWindow() {
        #expect(decide(entry(onscreen: false), complete: true, otherSpace: false) == .skip)
    }

    @Test("An app that did not answer (completely): its off-screen windows with a title stay")
    func incompleteApp() {
        // ⌘H app whose window list broke off: the windows not read must not vanish
        #expect(decide(entry(onscreen: false), hidden: true, complete: false) == .offScreen)
        #expect(decide(entry(onscreen: false, title: ""), complete: false) == .skip)
    }

    @Test("Space lookups only happen when needed")
    func lazySpaceLookups() {
        var lookups = 0
        let count: () -> Bool = { lookups += 1; return false }
        _ = WindowFilter.decide(entry(), ax: standard, appIsHidden: false, appListComplete: true,
                                isOnOtherSpace: count, isOnAnySpace: count)
        _ = WindowFilter.decide(entry(onscreen: false), ax: standard, appIsHidden: true,
                                appListComplete: true, isOnOtherSpace: count, isOnAnySpace: count)
        _ = WindowFilter.decide(entry(onscreen: false), ax: minimized, appIsHidden: false,
                                appListComplete: true, isOnOtherSpace: count, isOnAnySpace: count)
        #expect(lookups == 0)
    }
}
