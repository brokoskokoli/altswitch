// SPDX-License-Identifier: MIT

import SwiftUI
import Cocoa

struct WindowCardView: View {
    let item: WindowItem
    let isSelected: Bool
    let isScreenRecordingGranted: Bool
    let onSelect: () -> Void
    let onHover: () -> Void
    // Re-render when the UI language changes
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: App icon, App name, Window title
                HStack(spacing: 8) {
                    if let icon = item.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 16))
                            .frame(width: 22, height: 22)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(verbatim: item.appName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if item.isMinimized {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                                        .font(.system(size: 7))
                                    Text(verbatim: L("overlay.minimized"))
                                        .font(.system(size: 8, weight: .medium))
                                        .lineLimit(1)
                                }
                                .fixedSize()
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                        }

                        if !item.windowTitle.isEmpty && item.windowTitle != item.appName {
                            Text(verbatim: item.windowTitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: 26)

                // Preview Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))

                    if let thumb = item.thumbnail {
                        Image(decorative: thumb, scale: 1.0, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220, maxHeight: 130)
                            .cornerRadius(6)
                    } else if item.isMinimized {
                        // Minimized window placeholder
                        VStack(spacing: 6) {
                            if let icon = item.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 44, height: 44)
                                    .opacity(0.7)
                            }

                            Text(verbatim: L("overlay.minimized"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    } else {
                        // Fallback placeholder
                        VStack(spacing: 6) {
                            if let icon = item.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                                    .opacity(0.6)
                            }

                            if !isScreenRecordingGranted {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 10))
                                    Text(verbatim: L("card.screenRecordingRequired"))
                                        .font(.system(size: 10, weight: .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                            } else {
                                Text(verbatim: L("card.loading"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(width: 220, height: 130)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2.5 : 1.0
                    )
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.2),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: 2
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
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
