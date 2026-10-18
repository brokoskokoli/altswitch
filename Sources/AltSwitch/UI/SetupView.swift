// SPDX-License-Identifier: MIT

import SwiftUI
import Cocoa
import Combine

@MainActor
public class SetupViewModel: ObservableObject {
    @Published public var isAccessibilityGranted: Bool
    @Published public var isScreenRecordingGranted: Bool
    @Published public var selectedShortcut: ShortcutMode
    @Published public var selectedLayout: SwitcherLayout
    @Published public var autostartEnabled: Bool

    private var timerCancellable: AnyCancellable?

    public init() {
        self.isAccessibilityGranted = PermissionsManager.shared.isAccessibilityGranted
        self.isScreenRecordingGranted = PermissionsManager.shared.isScreenRecordingGranted
        self.selectedShortcut = AppSettings.shared.shortcutMode
        self.selectedLayout = AppSettings.shared.switcherLayout
        self.autostartEnabled = AppSettings.shared.hasCompletedSetup
            ? AutostartManager.shared.isAutostartEnabled
            : true
    }

    public func startPolling() {
        guard timerCancellable == nil else { return }
        refreshPermissions()

        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
    }

    public func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    deinit {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    public func refreshPermissions() {
        let ax = PermissionsManager.shared.isAccessibilityGranted
        let scr = PermissionsManager.shared.isScreenRecordingGranted

        if ax != isAccessibilityGranted {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isAccessibilityGranted = ax
            }
            if ax {
                HotkeyManager.shared.start()
            }
        }
        if scr != isScreenRecordingGranted {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isScreenRecordingGranted = scr
            }
        }
    }
}

@MainActor
public struct SetupView: View {
    @ObservedObject public var viewModel: SetupViewModel
    // Re-render when the UI language changes
    @ObservedObject private var settings = AppSettings.shared
    public var onFinish: (() -> Void)?

    public init(viewModel: SetupViewModel, onFinish: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onFinish = onFinish
    }

    public init(onFinish: (() -> Void)? = nil) {
        self.viewModel = SetupViewModel()
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 24)

                Text(verbatim: L("setup.welcome"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text(verbatim: L("setup.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 18)

            // Content Cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Step 1: Accessibility
                    setupCard(
                        stepNumber: 1,
                        title: L("setup.accessibility.title"),
                        symbol: "hand.raised.fill",
                        symbolColor: .blue,
                        description: L("setup.accessibility.description"),
                        isGranted: viewModel.isAccessibilityGranted,
                        onOpenSettings: {
                            PermissionsManager.shared.requestAndOpenAccessibility()
                        }
                    )

                    // Step 2: Screen Recording
                    setupCard(
                        stepNumber: 2,
                        title: L("setup.screenRecording.title"),
                        symbol: "camera.metering.matrix",
                        symbolColor: .purple,
                        description: L("setup.screenRecording.description"),
                        isGranted: viewModel.isScreenRecordingGranted,
                        onOpenSettings: {
                            PermissionsManager.shared.requestAndOpenScreenRecording()
                        }
                    )

                    // Step 3: Quick Settings
                    settingsCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.top, 10)

            // Bottom Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    dismissSetup()
                }) {
                    Text(verbatim: L("setup.later"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    completeSetup()
                }) {
                    HStack(spacing: 6) {
                        Text(verbatim: L("setup.finish"))
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Card View Builder

    @ViewBuilder
    private func setupCard(
        stepNumber: Int,
        title: String,
        symbol: String,
        symbolColor: Color,
        description: String,
        isGranted: Bool,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(symbolColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(symbolColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L("setup.step", stepNumber, title))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Live status badge
                if isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                        Text(verbatim: L("setup.enabled"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(verbatim: L("setup.required"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Text(description)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !isGranted {
                HStack {
                    Spacer()
                    Button(action: onOpenSettings) {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                            Text(verbatim: L("setup.openSettings"))
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isGranted ? Color.green.opacity(0.3) : Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Step 3: Quick Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }

                Text(verbatim: L("setup.step", 3, L("setup.quickSettings")))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L("settings.shortcut"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $viewModel.selectedShortcut) {
                    Text(verbatim: L("setup.shortcut.optionTab")).tag(ShortcutMode.optionTab)
                    Text(verbatim: ShortcutMode.cmdTab.title).tag(ShortcutMode.cmdTab)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L("setup.layout"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $viewModel.selectedLayout) {
                    Text(verbatim: SwitcherLayout.compact.title).tag(SwitcherLayout.compact)
                    Text(verbatim: SwitcherLayout.grid.title).tag(SwitcherLayout.grid)
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: $viewModel.autostartEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L("setup.autostart"))
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: L("setup.autostart.detail"))
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func dismissSetup() {
        // Save shortcut, layout, and autostart preferences without marking setup permanently complete
        AppSettings.shared.shortcutMode = viewModel.selectedShortcut
        AppSettings.shared.switcherLayout = viewModel.selectedLayout
        _ = AutostartManager.shared.setAutostart(enabled: viewModel.autostartEnabled)
        HotkeyManager.shared.start()
        onFinish?()
    }

    private func completeSetup() {
        // Save shortcut mode and layout
        AppSettings.shared.shortcutMode = viewModel.selectedShortcut
        AppSettings.shared.switcherLayout = viewModel.selectedLayout

        // Apply autostart
        _ = AutostartManager.shared.setAutostart(enabled: viewModel.autostartEnabled)

        // Mark setup complete
        AppSettings.shared.hasCompletedSetup = true

        // Ensure HotkeyManager is running
        HotkeyManager.shared.start()

        // Close window
        onFinish?()
    }
}
