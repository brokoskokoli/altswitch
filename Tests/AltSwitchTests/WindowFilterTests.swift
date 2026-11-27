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
    anySpace: Bool = true,
    focused: Bool = false
) -> Decision {
    WindowFilter.decide(entry, ax: ax, appIsHidden: hidden, appListComplete: complete, wasFocused: focused,
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

    @Test("A small window the user worked in is shown (a popup, so Alt-Tab does not jump past it)")
    func focusedSmallWindow() {
        #expect(decide(entry(size: 40), ax: panel, focused: true) == .onScreen)
        #expect(decide(entry(size: 0), focused: true) == .skip)
        #expect(decide(entry(layer: 25, size: 40), focused: true) == .skip)
        #expect(decide(entry(size: 40, alpha: 0), ax: panel, focused: true) == .skip)
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

    @Test("A modal dialog stands for the windows of its app it blocks, other apps are not touched")
    func modalDialog() {
        // App 1: main window 10, its password prompt 11; app 2: window 20
        let windows: [(id: CGWindowID, pid: pid_t)] = [(11, 1), (10, 1), (20, 2)]
        #expect(WindowFilter.blockedByModal(windows, modalIDs: [11]) == [10])
        #expect(WindowFilter.blockedByModal(windows, modalIDs: []) == [])
        // A modal window that is not listed (closed, or a helper) blocks nothing
        #expect(WindowFilter.blockedByModal(windows, modalIDs: [99]) == [])
    }

    @Test("A sheet is left out when its window is listed, the window stands for it")
    func sheets() {
        // Window 10 with its password sheet 11, window 20 of another app
        #expect(WindowFilter.hiddenSheets(listed: [10, 11, 20], sheetParents: [11: 10]) == [11])
        // Its window is not listed: the sheet stays
        #expect(WindowFilter.hiddenSheets(listed: [11, 20], sheetParents: [11: 10]) == [])
        #expect(WindowFilter.hiddenSheets(listed: [10, 20], sheetParents: [11: 10]) == [])
    }
}
