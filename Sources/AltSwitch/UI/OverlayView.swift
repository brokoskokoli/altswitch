import SwiftUI
import Cocoa

public enum NavigationDirection {
    case left
    case right
    case up
    case down
}

public class OverlayViewModel: ObservableObject {
    @Published public var windows: [WindowItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var isScreenRecordingGranted: Bool = false
    @Published public var gridColumns: Int = 3

    public var onSelectWindow: ((WindowItem) -> Void)?
    public var onCancel: (() -> Void)?

    public init() {}

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
        switch AppSettings.shared.switcherLayout {
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
                    let wrapped = selectedIndex - cols + windows.count
                    selectedIndex = (wrapped < windows.count) ? wrapped : ((selectedIndex - 1 + windows.count) % windows.count)
                }
            case .down:
                if selectedIndex + cols < windows.count {
                    selectedIndex += cols
                } else {
                    let wrapped = (selectedIndex + cols) % windows.count
                    selectedIndex = wrapped
                }
            }
        }
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
                    Text("Keine geöffneten Fenster gefunden")
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

                        Text(win.appName)
                            .font(.system(size: 13, weight: .bold))

                        if win.isMinimized {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                                    .font(.system(size: 9))
                                Text("Minimiert")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                        }

                        if !win.windowTitle.isEmpty && win.windowTitle != win.appName {
                            Text("—")
                                .foregroundColor(.secondary)

                            Text(win.windowTitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text("\(viewModel.selectedIndex + 1) / \(viewModel.windows.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Window Cards Content: Grid or Carousel
                if settings.switcherLayout == .grid {
                    let columns = Array(
                        repeating: GridItem(.fixed(240), spacing: 14),
                        count: max(1, viewModel.gridColumns)
                    )
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, item in
                                    WindowCardView(
                                        item: item,
                                        isSelected: viewModel.selectedIndex == index,
                                        isScreenRecordingGranted: viewModel.isScreenRecordingGranted,
                                        onSelect: {
                                            viewModel.selectWindow(at: index)
                                        },
                                        onHover: {
                                            viewModel.selectedIndex = index
                                        }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.selectedIndex) { _, newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(viewModel.windows.enumerated()), id: \.element.id) { index, item in
                                    WindowCardView(
                                        item: item,
                                        isSelected: viewModel.selectedIndex == index,
                                        isScreenRecordingGranted: viewModel.isScreenRecordingGranted,
                                        onSelect: {
                                            viewModel.selectWindow(at: index)
                                        },
                                        onHover: {
                                            viewModel.selectedIndex = index
                                        }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.selectedIndex) { _, newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }

                // Footer: Keyboard Navigation Hints
                HStack(spacing: 16) {
                    HintView(key: "⇥", text: "Weiter")
                    HintView(key: "⇧⇥ / ⇧", text: "Zurück")
                    HintView(key: "← ↑ → ↓", text: "Navigieren")
                    HintView(key: "Esc", text: "Abbrechen")
                    Spacer()
                    Text("Taste loslassen zum Wechseln")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
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

struct HintView: View {
    let key: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
