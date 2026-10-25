// SPDX-License-Identifier: MIT

import SwiftUI
import Cocoa

public enum NavigationDirection {
    case left
    case right
    case up
    case down
}

public class OverlayViewModel: ObservableObject {
    /// Windows in navigation order: most recently used first for the cards, app by app for the
    /// grouped list. `selectedIndex` points into this list.
    @Published public var windows: [WindowItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var isScreenRecordingGranted: Bool = false
    @Published public var gridColumns: Int = 3
    /// Layout of the switcher on screen (can be toggled while it is open)
    @Published public var layout: SwitcherLayout = AppSettings.shared.switcherLayout
    /// Sections of the grouped list; empty in the card layouts
    @Published public var groups: [WindowGroup] = []

    /// All windows, most recently used first, independent of the layout
    public private(set) var recentWindows: [WindowItem] = []

    public var onSelectWindow: ((WindowItem) -> Void)?
    public var onCancel: (() -> Void)?

    public init() {}

    /// Shows `recent` (most recently used first) in `layout`. `initialIndex` refers to `recent`:
    /// 1 is the window used before the current one, `recent.count - 1` the start for Shift-Tab.
    public func present(recentWindows recent: [WindowItem], initialIndex: Int, layout: SwitcherLayout) {
        recentWindows = recent
        self.layout = layout
        rebuildDisplayOrder()

        guard !recent.isEmpty else {
            selectedIndex = 0
            return
        }
        let index = recent.indices.contains(initialIndex) ? initialIndex : 0
        if index == recent.count - 1 && recent.count > 2 {
            // Shift-Tab starts one step "back" from the current window: the end of the list
            selectedIndex = windows.count - 1
        } else {
            // The grouped list orders by app, so the window used before the current one can sit
            // anywhere in it: select it by identity, not by position
            selectedIndex = windows.firstIndex(where: { $0.id == recent[index].id }) ?? 0
        }
    }

    /// Switches the layout while the switcher is open and keeps the selected window selected
    public func applyLayout(_ newLayout: SwitcherLayout) {
        guard newLayout != layout else { return }
        let selectedID = windows.indices.contains(selectedIndex) ? windows[selectedIndex].id : nil
        layout = newLayout
        rebuildDisplayOrder()
        selectedIndex = selectedID.flatMap { id in windows.firstIndex(where: { $0.id == id }) } ?? 0
    }

    private func rebuildDisplayOrder() {
        if layout == .grouped {
            groups = WindowGroup.grouped(recentWindows)
            windows = WindowGroup.flattened(groups)
        } else {
            groups = []
            windows = recentWindows
        }
    }

    /// Index of the group that contains the window at `index` in `windows`
    private func groupIndex(containing index: Int) -> Int? {
        groups.firstIndex { $0.indices.contains(index) }
    }

    public func cycleNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    public func cyclePrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    public func navigate(direction: NavigationDirection) {
        guard !windows.isEmpty else { return }
        switch layout {
        case .grouped:
            switch direction {
            case .up:
                cyclePrevious()
            case .down:
                cycleNext()
            case .left, .right:
                // Jump to the first window of the previous / next app
                guard !groups.isEmpty, let current = groupIndex(containing: selectedIndex) else {
                    if direction == .left { cyclePrevious() } else { cycleNext() }
                    return
                }
                let step = direction == .left ? -1 : 1
                let target = (current + step + groups.count) % groups.count
                selectedIndex = groups[target].startIndex
            }
        case .compact:
            switch direction {
            case .left, .up:
                cyclePrevious()
            case .right, .down:
                cycleNext()
            }
        case .grid:
            let cols = max(1, gridColumns)
            switch direction {
            case .left:
                cyclePrevious()
            case .right:
                cycleNext()
            case .up:
                if selectedIndex - cols >= 0 {
                    selectedIndex -= cols
                } else {
                    // Wrap to bottom-most item in the same column
                    var target = selectedIndex
                    while target + cols < windows.count {
                        target += cols
                    }
                    selectedIndex = target
                }
            case .down:
                let col = selectedIndex % cols
                let row = selectedIndex / cols
                let lastRow = (windows.count - 1) / cols
                if selectedIndex + cols < windows.count {
                    selectedIndex += cols
                } else if row < lastRow {
                    // Last row is shorter: no card directly below, take its last card
                    selectedIndex = windows.count - 1
                } else {
                    // Wrap to top-most item in the same column
                    selectedIndex = col
                }
            }
        }
    }

    /// Mouse position at the last keyboard navigation. Scrolling the grid moves cards under a
    /// resting pointer and fires onHover; only a real mouse movement may change the selection.
    private var pointerAtKeyboardNavigation: NSPoint?

    public func noteKeyboardNavigation() {
        pointerAtKeyboardNavigation = NSEvent.mouseLocation
    }

    public func hover(at index: Int) {
        let pointer = NSEvent.mouseLocation
        if let resting = pointerAtKeyboardNavigation,
           abs(resting.x - pointer.x) < 2, abs(resting.y - pointer.y) < 2 {
            return
        }
        pointerAtKeyboardNavigation = nil
        selectedIndex = index
    }

    public func selectCurrent() {
        guard !windows.isEmpty, selectedIndex >= 0, selectedIndex < windows.count else { return }
        onSelectWindow?(windows[selectedIndex])
    }

    public func selectWindow(at index: Int) {
        guard index >= 0, index < windows.count else { return }
        selectedIndex = index
        onSelectWindow?(windows[index])
    }

    public func updateThumbnail(for id: CGWindowID, image: CGImage) {
        if let idx = windows.firstIndex(where: { $0.id == id }) {
            windows[idx].thumbnail = image
        }
        // Kept for a switch from the grouped list back to the cards
        if let idx = recentWindows.firstIndex(where: { $0.id == id }) {
            recentWindows[idx].thumbnail = image
        }
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(verbatim: L("overlay.noWindows"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 320, height: 160)
            } else {
                // Header: Current Selected Window Title & App Info
                let selectedWindow = viewModel.windows.indices.contains(viewModel.selectedIndex)
                    ? viewModel.windows[viewModel.selectedIndex]
                    : nil

                HStack(spacing: 10) {
                    if let win = selectedWindow {
                        if let icon = win.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        }

                        Text(verbatim: win.appName)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)

                        if win.isMinimized {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                                    .font(.system(size: 9))
                                Text(verbatim: L("overlay.minimized"))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                        }

                        if !win.windowTitle.isEmpty && win.windowTitle != win.appName {
                            Text(verbatim: "—")
                                .foregroundColor(.secondary)

                            Text(verbatim: win.windowTitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(verbatim: "\(viewModel.selectedIndex + 1) / \(viewModel.windows.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Content: grouped title list, grid of cards or carousel
                if viewModel.layout == .grouped {
                    GroupedWindowListView(viewModel: viewModel)
                } else if viewModel.layout == .grid {
                    let columns = Array(
                        repeating: GridItem(.fixed(240), spacing: 14),
                        count: max(1, viewModel.gridColumns)
                    )
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                // Identity by position: a duplicate or reused window ID must not leave a card unhighlighted
                                ForEach(Array(viewModel.windows.enumerated()), id: \.offset) { index, item in
                                    WindowCardView(
                                        item: item,
                                        isSelected: viewModel.selectedIndex == index,
                                        isScreenRecordingGranted: viewModel.isScreenRecordingGranted,
                                        onSelect: {
                                            viewModel.selectWindow(at: index)
                                        },
                                        onHover: {
                                            viewModel.hover(at: index)
                                        }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.selectedIndex) { newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                // Identity by position: a duplicate or reused window ID must not leave a card unhighlighted
                                ForEach(Array(viewModel.windows.enumerated()), id: \.offset) { index, item in
                                    WindowCardView(
                                        item: item,
                                        isSelected: viewModel.selectedIndex == index,
                                        isScreenRecordingGranted: viewModel.isScreenRecordingGranted,
                                        onSelect: {
                                            viewModel.selectWindow(at: index)
                                        },
                                        onHover: {
                                            viewModel.hover(at: index)
                                        }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.selectedIndex) { newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }

                // Footer: Keyboard Navigation Hints. Long translations drop the release hint first,
                // then the navigation hints, instead of being cut off.
                ViewThatFits(in: .horizontal) {
                    footer(showNavigate: true, showToggle: true, showRelease: true)
                    footer(showNavigate: true, showToggle: true, showRelease: false)
                    footer(showNavigate: false, showToggle: true, showRelease: false)
                    footer(showNavigate: false, showToggle: false, showRelease: false)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
        .padding(20)
    }
}

extension OverlayView {
    private func footer(showNavigate: Bool, showToggle: Bool, showRelease: Bool) -> some View {
        HStack(spacing: 16) {
            HintView(key: "⇥", text: L("overlay.hint.next"))
            HintView(key: "⇧⇥ / ⇧", text: L("overlay.hint.back"))
            if showNavigate {
                HintView(key: "← ↑ → ↓", text: L("overlay.hint.navigate"))
            }
            if showToggle {
                HintView(
                    key: "G",
                    text: viewModel.layout == .grouped ? L("overlay.hint.showCards") : L("overlay.hint.showList")
                )
            }
            HintView(key: "Esc", text: L("overlay.hint.cancel"))
            Spacer(minLength: 0)
            if showRelease {
                Text(verbatim: L("overlay.hint.release"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

struct HintView: View {
    let key: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)))
            Text(verbatim: text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
