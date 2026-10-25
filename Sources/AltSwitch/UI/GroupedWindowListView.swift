// SPDX-License-Identifier: MIT

import SwiftUI
import Cocoa

/// Sizes of the grouped list, shared with OverlayPanel so the panel fits the list without guessing.
enum GroupedListMetrics {
    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let rowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    static let headerHeight: CGFloat = 26
    static let sectionPadding: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let glyphWidth: CGFloat = 20
    static let glyphSpacing: CGFloat = 8

    /// Height of one app section with `windowCount` rows
    static func sectionHeight(windowCount: Int) -> CGFloat {
        2 * sectionPadding + headerHeight + CGFloat(windowCount) * (rowSpacing + rowHeight)
    }

    /// Height of all sections stacked
    static func contentHeight(for groups: [WindowGroup]) -> CGFloat {
        let sections = groups.reduce(CGFloat(0)) { $0 + sectionHeight(windowCount: $1.windows.count) }
        return sections + CGFloat(max(0, groups.count - 1)) * sectionSpacing
    }

    /// Width a row needs to show `item`'s title without truncation
    static func rowWidth(for item: WindowItem) -> CGFloat {
        let title = GroupedWindowRowView.displayTitle(for: item) as NSString
        let textWidth = ceil(title.size(withAttributes: [.font: titleFont]).width)
        let badge: CGFloat = item.isMinimized ? 110 : 0
        // Two HStack spacings (glyph | title | spacer), the spacer minimum and a little slack for
        // rounding and the scroll indicator
        return 2 * sectionPadding + 2 * rowHorizontalPadding + glyphWidth + 2 * glyphSpacing + textWidth + 8 + 12 + badge
    }
}

/// "Grouped by App" layout: one rounded section per app (icon and name as header) listing the full
/// window titles, in the same navigation order as `viewModel.windows`.
struct GroupedWindowListView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: GroupedListMetrics.sectionSpacing) {
                    ForEach(viewModel.groups) { group in
                        GroupedWindowSectionView(
                            group: group,
                            selectedIndex: viewModel.selectedIndex,
                            onSelect: { viewModel.selectWindow(at: $0) },
                            onHover: { viewModel.hover(at: $0) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    // nil anchor: scroll only as far as needed, so the list does not jump on every step
                    proxy.scrollTo(newIndex, anchor: nil)
                }
            }
        }
    }
}

struct GroupedWindowSectionView: View {
    let group: WindowGroup
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void

    private var containsSelection: Bool {
        group.indices.contains(selectedIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListMetrics.rowSpacing) {
            HStack(spacing: GroupedListMetrics.glyphSpacing) {
                if let icon = group.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: GroupedListMetrics.glyphWidth, height: GroupedListMetrics.glyphWidth)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 14))
                        .frame(width: GroupedListMetrics.glyphWidth, height: GroupedListMetrics.glyphWidth)
                }

                Text(verbatim: group.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if group.windows.count > 1 {
                    Text(verbatim: "\(group.windows.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
            }
            .padding(.horizontal, GroupedListMetrics.rowHorizontalPadding)
            .frame(height: GroupedListMetrics.headerHeight)

            ForEach(Array(group.windows.enumerated()), id: \.offset) { offset, item in
                let index = group.startIndex + offset
                GroupedWindowRowView(
                    item: item,
                    isSelected: index == selectedIndex,
                    onSelect: { onSelect(index) },
                    onHover: { onHover(index) }
                )
                .id(index)
            }
        }
        .padding(GroupedListMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(containsSelection ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    containsSelection ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        )
    }
}

struct GroupedWindowRowView: View {
    let item: WindowItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: () -> Void
    // Re-render when the UI language changes
    @ObservedObject private var settings = AppSettings.shared

    /// The window's own title; windows without one show the app name instead of an empty row
    static func displayTitle(for item: WindowItem) -> String {
        let title = item.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.appName : title
    }

    private var hasOwnTitle: Bool {
        let title = item.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title != item.appName
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: GroupedListMetrics.glyphSpacing) {
                Image(systemName: item.isMinimized ? "dock.rectangle" : "macwindow")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .frame(width: GroupedListMetrics.glyphWidth)

                // Middle truncation keeps both ends readable: the start (file, host) and the end
                // (project, app) of titles like "file.swift — project"
                Text(verbatim: Self.displayTitle(for: item))
                    .font(.system(size: GroupedListMetrics.titleFont.pointSize))
                    .foregroundColor(isSelected ? .white : (hasOwnTitle ? .primary : .secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if item.isMinimized {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                            .font(.system(size: 8))
                        Text(verbatim: L("overlay.minimized"))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.10)))
                }
            }
            .padding(.horizontal, GroupedListMetrics.rowHorizontalPadding)
            .frame(height: GroupedListMetrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
    }
}
