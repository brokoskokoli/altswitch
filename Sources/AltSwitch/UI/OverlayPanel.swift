// SPDX-License-Identifier: MIT

import Cocoa
import SwiftUI

public class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

public class OverlayPanel: NSPanel {
    private let viewModel = OverlayViewModel()
    private var hostingView: ClickableHostingView<OverlayView>?

    public var onWindowChosen: ((WindowItem) -> Void)?
    public var onDismissed: (() -> Void)?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.becomesKeyOnlyIfNeeded = true

        viewModel.onSelectWindow = { [weak self] item in
            self?.hide()
            self?.onWindowChosen?(item)
        }

        viewModel.onCancel = { [weak self] in
            self?.hide()
        }

        viewModel.onCloseWindow = { [weak self] item in
            self?.close(item)
        }

        let view = OverlayView(viewModel: viewModel)
        let hosting = ClickableHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting
        self.hostingView = hosting
    }

    override public var canBecomeKey: Bool {
        return false
    }

    override public var canBecomeMain: Bool {
        return false
    }

    /// Screen the switcher is shown on, kept for re-sizing it when the layout is toggled
    private var currentScreen: NSScreen?

    /// `windows` in most-recently-used order; `initialIndex` refers to that order (see
    /// OverlayViewModel.present), the grouped layout re-orders them by app.
    public func show(windows: [WindowItem], initialIndex: Int) {
        viewModel.present(recentWindows: windows, initialIndex: initialIndex, layout: AppSettings.shared.switcherLayout)
        viewModel.isScreenRecordingGranted = PermissionsManager.shared.isScreenRecordingGranted
        // A pointer that happens to rest where the panel appears must not pick a card
        viewModel.noteKeyboardNavigation()

        // Center on the active display:
        // 1. Try finding screen of the active (first) window
        // 2. Otherwise screen containing mouse pointer
        // 3. Fallback to main or first screen
        var targetScreen: NSScreen?
        if let firstWin = windows.first {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let cocoaX = firstWin.bounds.midX
            let cocoaY = primaryHeight - firstWin.bounds.midY
            let winCenter = CGPoint(x: cocoaX, y: cocoaY)
            targetScreen = NSScreen.screens.first { NSPointInRect(winCenter, $0.frame) }
        }

        if targetScreen == nil {
            let mouseLocation = NSEvent.mouseLocation
            targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        }

        let activeScreen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first

        currentScreen = activeScreen
        if let screen = activeScreen {
            applyFrame(on: screen)
        }

        self.alphaValue = 1.0
        self.orderFrontRegardless()
        startFrameTimer()
    }

    // MARK: - Pointer and keys while open

    /// Key code of Q by position (ANSI layout), so it is the same key with any keyboard layout
    private static let quickCloseKeyCode: CGKeyCode = 12

    private var frameTimer: Timer?
    private var lastFrameTime: CFTimeInterval = 0

    /// Edge scrolling and the quick-close key, checked every frame while the switcher is open. The
    /// key is read from the keyboard state: the event tap swallows the key presses themselves.
    private func startFrameTimer() {
        frameTimer?.invalidate()
        lastFrameTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.frameTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
        if viewModel.isCloseKeyHeld {
            viewModel.isCloseKeyHeld = false
        }
    }

    private func frameTick() {
        let now = CACurrentMediaTime()
        // Capped, so a stalled main thread does not make the list jump afterwards
        let elapsed = min(now - lastFrameTime, 0.05)
        lastFrameTime = now

        let closeKeyHeld = AppSettings.shared.quickCloseEnabled
            && CGEventSource.keyState(.hidSystemState, key: Self.quickCloseKeyCode)
        if closeKeyHeld != viewModel.isCloseKeyHeld {
            viewModel.isCloseKeyHeld = closeKeyHeld
        }

        // A pointer that has not moved since the switcher opened or since the last arrow key must
        // not scroll the list away from the keyboard selection
        if !viewModel.isPointerResting {
            viewModel.edgeScroller.step(pointer: NSEvent.mouseLocation, elapsed: elapsed)
        }
    }

    /// Closes `item` through its close button and takes the card away once the window is gone. If
    /// the app asks first (unsaved changes), the card stays until the window really closes.
    private func close(_ item: WindowItem) {
        guard WindowManager.shared.closeWindow(item) else {
            NSSound.beep()
            return
        }
        removeWhenClosed(item.id, checksLeft: 8)
    }

    private func removeWhenClosed(_ id: CGWindowID, checksLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.isVisible else { return }
            if !WindowManager.shared.windowExists(id) {
                self.viewModel.removeWindow(id: id)
            } else if checksLeft > 1 {
                self.removeWhenClosed(id, checksLeft: checksLeft - 1)
            }
        }
    }

    /// Windows in most-recently-used order, as passed to show(windows:initialIndex:)
    public var presentedWindows: [WindowItem] {
        viewModel.recentWindows
    }

    /// Switches between the cards and the grouped list while the switcher is open; the choice is
    /// kept as the layout setting.
    public func toggleLayout() {
        AppSettings.shared.toggleCardsAndGroupedList()
        viewModel.applyLayout(AppSettings.shared.switcherLayout)
        if let screen = currentScreen ?? NSScreen.main {
            applyFrame(on: screen)
        }
    }

    /// Sizes and centers the panel for the current layout and windows on `screen`
    private func applyFrame(on screen: NSScreen) {
        let windows = viewModel.windows
        let panelWidth: CGFloat
        let panelHeight: CGFloat

        if viewModel.layout == .grouped {
            // Wide enough for the longest title (most fit in full), tall enough for all sections
            let maxWidth = min(screen.visibleFrame.width * 0.8, 1200)
            let maxHeight = screen.visibleFrame.height * 0.8
            let overheadW: CGFloat = 72
            let overheadH: CGFloat = 150
            let longestRow = windows.map(GroupedListMetrics.rowWidth(for:)).max() ?? 0
            let contentH = GroupedListMetrics.contentHeight(for: viewModel.groups)

            panelWidth = max(min(longestRow + overheadW, maxWidth), 560)
            panelHeight = max(min(contentH + overheadH, maxHeight), 260)
        } else if viewModel.layout == .grid {
            // Multi-Column Raster / Task View: expands flexibly up to 88% width and 80% height
            let maxGridWidth = screen.visibleFrame.width * 0.88
            let maxGridHeight = screen.visibleFrame.height * 0.80

            let cardW: CGFloat = 240
            let cardH: CGFloat = 185
            let spacing: CGFloat = 14
            let overheadW: CGFloat = 72
            let overheadH: CGFloat = 144

            let count = windows.count
            if count <= 0 {
                panelWidth = 400
                panelHeight = 220
            } else {
                let maxCols = max(1, Int((maxGridWidth - overheadW + spacing) / (cardW + spacing)))
                let maxColsLimit = min(maxCols, 5)
                let cols: Int
                if count <= 3 {
                    cols = max(1, count)
                } else if count == 4 {
                    cols = min(maxColsLimit, 2)
                } else if count <= 6 {
                    cols = min(maxColsLimit, 3)
                } else if count <= 8 {
                    cols = min(maxColsLimit, 4)
                } else {
                    cols = maxColsLimit
                }

                viewModel.gridColumns = cols
                let rows = Int(ceil(Double(count) / Double(cols)))

                let contentW = CGFloat(cols) * cardW + CGFloat(max(0, cols - 1)) * spacing + overheadW
                let contentH = CGFloat(rows) * cardH + CGFloat(max(0, rows - 1)) * spacing + overheadH

                panelWidth = max(min(contentW, maxGridWidth), 400)
                panelHeight = max(min(contentH, maxGridHeight), 330)
            }
        } else {
            // Compact Carousel mode
            let cardWidth: CGFloat = 240
            let spacing: CGFloat = 14
            let overheadW: CGFloat = 72
            let totalCardsWidth = CGFloat(windows.count) * cardWidth + CGFloat(max(0, windows.count - 1)) * spacing + overheadW
            let maxWidth = min(screen.visibleFrame.width * 0.90, 920)
            panelWidth = max(min(totalCardsWidth, maxWidth), 400)
            panelHeight = 330
        }

        let x = screen.visibleFrame.origin.x + (screen.visibleFrame.width - panelWidth) / 2
        let y = screen.visibleFrame.origin.y + (screen.visibleFrame.height - panelHeight) / 2

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    /// Renders the overlay once, invisible and off screen: the first real shortcut press then skips
    /// SwiftUI's cold start (~200 ms).
    public func prewarm() {
        viewModel.present(recentWindows: WindowManager.shared.getOpenWindows(), initialIndex: 0, layout: AppSettings.shared.switcherLayout)
        alphaValue = 0
        // At the size the first press will use: the grid only builds the cards it has room for
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            applyFrame(on: screen)
        }
        setFrameOrigin(NSPoint(x: -10000 - frame.width, y: -10000 - frame.height))
        orderFrontRegardless()
        contentView?.layoutSubtreeIfNeeded()
        display()
        orderOut(nil)
        // The content stays: the first press then updates it instead of building it (~25 ms)
    }

    public func updateThumbnail(for windowId: CGWindowID, image: CGImage) {
        viewModel.updateThumbnail(for: windowId, image: image)
    }

    public func hide() {
        stopFrameTimer()
        self.orderOut(nil)
        onDismissed?()
    }

    public func cycleNext() {
        viewModel.noteKeyboardNavigation()
        viewModel.cycleNext()
    }

    public func cyclePrevious() {
        viewModel.noteKeyboardNavigation()
        viewModel.cyclePrevious()
    }

    public func navigate(direction: NavigationDirection) {
        viewModel.noteKeyboardNavigation()
        viewModel.navigate(direction: direction)
    }

    public func confirmSelection() {
        viewModel.selectCurrent()
    }

    public func cancel() {
        viewModel.onCancel?()
    }
}
