// SPDX-License-Identifier: MIT

import Cocoa
import Carbon
import ApplicationServices
import Combine

public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyTriggered(forward: Bool)
    func hotkeyCycle(forward: Bool)
    func hotkeyNavigate(direction: NavigationDirection)
    /// G while the switcher is open: cards ⇄ grouped list
    func hotkeyToggleLayout()
    func hotkeyConfirmed()
    func hotkeyCancelled()
}

public class HotkeyManager {
    public static let shared = HotkeyManager()

    public weak var delegate: HotkeyManagerDelegate?

    /// Set from the main thread, read and reset on the tap thread.
    public var isOverlayActive: Bool {
        get { lock.locked { overlayActive } }
        set { lock.locked { setOverlayActive(newValue) } }
    }

    /// The tap's state. The tap runs on its own thread, so all of it is guarded by `lock`.
    private let lock = NSLock()
    private var overlayActive = false
    private var activeTriggerModifier: CGEventFlags?
    private var wasShiftDown: Bool = false
    private var shiftWasUsedWithKey: Bool = false
    private var wasTriggerModifierDown = false
    /// Copy of AppSettings.shortcutMode: the settings object belongs to the main thread
    private var shortcutMode: ShortcutMode = .optionTab
    private var eventTap: CFMachPort?

    /// The shortcut's modifier went down while the overlay is closed: a press may follow.
    /// Called on the main thread.
    public var onTriggerModifierDown: (() -> Void)?

    // Main thread only
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var settingsObserver: AnyCancellable?

    /// The event tap gets its own thread. On the main run loop, any stall there (an app slow to
    /// answer an Accessibility call, SwiftUI layout) holds the shortcut back; past about a second
    /// macOS disables the tap and the key goes to the system, which then shows its own app switcher.
    private lazy var tapThread: EventTapThread = {
        let thread = EventTapThread()
        thread.start()
        return thread
    }()

    private init() {}

    public func start() {
        stop()
        lock.locked { shortcutMode = AppSettings.shared.shortcutMode }
        settingsObserver = AppSettings.shared.$shortcutMode.sink { [weak self] mode in
            guard let self = self else { return }
            self.lock.locked { self.shortcutMode = mode }
        }
        setupEventTap()

        if lock.locked({ eventTap == nil }) {
            // Periodically attempt to acquire the tap once permission is granted
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.lock.locked({ self.eventTap == nil }) && PermissionsManager.shared.isAccessibilityGranted {
                    self.setupEventTap()
                    if self.lock.locked({ self.eventTap != nil }) {
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                }
            }
        }
    }

    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        settingsObserver = nil

        if let source = runLoopSource {
            CFRunLoopRemoveSource(tapThread.runLoop, source, .commonModes)
            runLoopSource = nil
        }
        let tap = lock.locked { () -> CFMachPort? in
            defer { eventTap = nil }
            return eventTap
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    /// Lock must be held.
    private func setOverlayActive(_ active: Bool) {
        overlayActive = active
        if !active {
            activeTriggerModifier = nil
            wasTriggerModifierDown = false
            wasShiftDown = false
            shiftWasUsedWithKey = false
        }
    }

    private func setupEventTap() {
        guard PermissionsManager.shared.isAccessibilityGranted else {
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                    (1 << CGEventType.flagsChanged.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            NSLog("AltSwitch: Failed to create CGEventTap. Accessibility permission may be required.")
            return
        }

        lock.locked { self.eventTap = tap }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        let runLoop = tapThread.runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Runs on the tap thread. Keep it short: macOS waits for it before passing any key on.
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        defer { lock.unlock() }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("AltSwitch: EventTap re-enabled after %@", type == .tapDisabledByTimeout ? "timeout" : "user input")
            }
            return nil
        }

        let flags = event.flags
        let currentMode = shortcutMode

        let isOptionDown = flags.contains(.maskAlternate)
        let isCmdDown = flags.contains(.maskCommand)
        let isShiftDown = flags.contains(.maskShift)

        // MARK: - KeyDown
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            let isTriggerModifierDown: Bool
            let triggerFlag: CGEventFlags
            switch currentMode {
            case .optionTab:
                // Option must be down, and Command must not be down
                isTriggerModifierDown = isOptionDown && !isCmdDown
                triggerFlag = .maskAlternate
            case .cmdTab:
                // Command must be down, and Option must not be down
                isTriggerModifierDown = isCmdDown && !isOptionDown
                triggerFlag = .maskCommand
            }

            // Tab key (KeyCode 48)
            if keyCode == 48 && isTriggerModifierDown {
                let forward = !isShiftDown
                wasShiftDown = isShiftDown
                if isShiftDown {
                    shiftWasUsedWithKey = true
                }

                if !overlayActive {
                    setOverlayActive(true)
                    activeTriggerModifier = triggerFlag
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.hotkeyTriggered(forward: forward)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.hotkeyCycle(forward: forward)
                    }
                }
                return nil // Consume event
            }

            // While overlay is active, intercept navigation keys
            if overlayActive {
                switch keyCode {
                case 124: // Right Arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyNavigate(direction: .right)
                    }
                    return nil

                case 123: // Left Arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyNavigate(direction: .left)
                    }
                    return nil

                case 126: // Up Arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyNavigate(direction: .up)
                    }
                    return nil

                case 125: // Down Arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyNavigate(direction: .down)
                    }
                    return nil

                case 5: // G (by position, so it works with any modifier held): toggle the view
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyToggleLayout()
                    }
                    return nil

                case 53: // Escape
                    setOverlayActive(false)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyCancelled()
                    }
                    return nil

                case 36, 49: // Return or Space
                    setOverlayActive(false)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyConfirmed()
                    }
                    return nil

                default:
                    break
                }
            }
        }

        // MARK: - FlagsChanged
        if type == .flagsChanged {
            if overlayActive, let trigger = activeTriggerModifier {
                let isTriggerStillDown = flags.contains(trigger)

                if !isTriggerStillDown {
                    // Trigger modifier was released! Confirm selection and dismiss
                    setOverlayActive(false)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyConfirmed()
                    }
                    return Unmanaged.passRetained(event)
                }

                // Trigger modifier is still held down!
                let isShiftNowDown = flags.contains(.maskShift)
                if isShiftNowDown && !wasShiftDown {
                    // Shift was just pressed
                    shiftWasUsedWithKey = false
                } else if !isShiftNowDown && wasShiftDown {
                    // Shift was just released!
                    // If Shift was tapped alone (not used with Tab), step backward
                    if !shiftWasUsedWithKey {
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.hotkeyCycle(forward: false)
                        }
                    }
                }
                wasShiftDown = isShiftNowDown
            } else {
                wasShiftDown = flags.contains(.maskShift)
                shiftWasUsedWithKey = false

                let triggerFlag: CGEventFlags = currentMode == .cmdTab ? .maskCommand : .maskAlternate
                let isTriggerDown = flags.contains(triggerFlag)
                if isTriggerDown && !wasTriggerModifierDown {
                    DispatchQueue.main.async { [weak self] in
                        self?.onTriggerModifierDown?()
                    }
                }
                wasTriggerModifierDown = isTriggerDown
            }
        }

        return Unmanaged.passRetained(event)
    }
}

/// A thread that only runs a run loop, for the event tap.
private final class EventTapThread: Thread {
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "AltSwitch.EventTap"
        qualityOfService = .userInteractive
    }

    /// Waits until the thread has started.
    var runLoop: CFRunLoop {
        ready.wait()
        defer { ready.signal() }
        return loop!
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A run loop without sources returns at once: a timer that never fires keeps it running
        let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
        CFRunLoopAddTimer(loop, keepAlive, .commonModes)
        ready.signal()
        while !isCancelled {
            CFRunLoopRun()
        }
    }
}

private extension NSLock {
    /// NSLocking.withLock needs macOS 14.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
