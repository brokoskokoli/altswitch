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

    public func show(windows: [WindowItem], initialIndex: Int) {
        viewModel.windows = windows
        viewModel.selectedIndex = (initialIndex >= 0 && initialIndex < windows.count) ? initialIndex : 0
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

        if let screen = activeScreen {
            let panelWidth: CGFloat
            let panelHeight: CGFloat

            if AppSettings.shared.switcherLayout == .grid {
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

        self.alphaValue = 1.0
        self.orderFrontRegardless()
    }

    public func updateThumbnail(for windowId: CGWindowID, image: CGImage) {
        viewModel.updateThumbnail(for: windowId, image: image)
    }

    public func hide() {
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

    public func navigate(forward: Bool) {
        if forward {
            viewModel.cycleNext()
        } else {
            viewModel.cyclePrevious()
        }
    }

    public func confirmSelection() {
        viewModel.selectCurrent()
    }

    public func cancel() {
        viewModel.onCancel?()
    }
}
