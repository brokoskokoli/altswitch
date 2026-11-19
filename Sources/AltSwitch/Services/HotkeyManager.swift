// SPDX-License-Identifier: MIT

import Cocoa
import Carbon
import ApplicationServices
import Combine

public protocol HotkeyManagerDelegate: AnyObject {
    /// `session` identifies this opening of the switcher; pass it to `endSession(_:)`.
    func hotkeyTriggered(forward: Bool, session: UInt64)
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

    /// The tap's state. The tap runs on its own thread, so all of it is guarded by `lock`.
    private let lock = NSLock()
    /// Keyboard logic; its `mode` mirrors AppSettings.shortcutMode, which belongs to the main thread
    private var machine = ShortcutStateMachine()
    private var eventTap: CFMachPort?
    /// How often macOS switched the tap off (for the diagnostics)
    private var tapReenableCount = 0

    /// The shortcut's modifier went down while the overlay is closed: a press may follow.
    /// Called on the main thread.
    public var onTriggerModifierDown: (() -> Void)?

    // Main thread only
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
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

    /// Whether the event tap is installed (for the diagnostics)
    public var isTapInstalled: Bool { lock.locked { eventTap != nil } }
    public var tapReenables: Int { lock.locked { tapReenableCount } }

    public func start() {
        stop()
        lock.locked { machine.mode = AppSettings.shared.shortcutMode }
        settingsObserver = AppSettings.shared.$shortcutMode.sink { [weak self] mode in
            guard let self = self else { return }
            self.lock.locked {
                self.machine.mode = mode
                self.machine.reset()
            }
        }
        setupEventTap()

        // Follow the Accessibility permission while running: install the tap once it is granted,
        // and remove it when it is taken away. An active tap without the permission can leave the
        // whole system without keyboard input.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let granted = PermissionsManager.shared.isAccessibilityGranted
            let installed = self.isTapInstalled
            if granted && !installed {
                self.setupEventTap()
            } else if !granted && installed {
                NSLog("AltSwitch: Accessibility permission revoked, removing the event tap")
                self.removeEventTap()
            }
        }
    }

    public func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        settingsObserver = nil
        removeEventTap()
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(tapThread.runLoop, source, .commonModes)
            runLoopSource = nil
        }
        let tap = lock.locked { () -> CFMachPort? in
            defer {
                eventTap = nil
                machine.reset()
            }
            return eventTap
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        // A switcher left open would no longer get the release of the modifier
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.hotkeyCancelled()
        }
    }

    /// The main thread closed the switcher of `session`. Ignored if the tap has opened a newer one
    /// since, or closed this one itself.
    public func endSession(_ session: UInt64) {
        lock.locked { machine.end(session: session) }
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
                // The event is not ours: handing it back must not retain it (one leak per key press)
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
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
        let result: ShortcutStateMachine.Result
        lock.lock()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                tapReenableCount += 1
                NSLog("AltSwitch: EventTap re-enabled after %@", type == .tapDisabledByTimeout ? "timeout" : "user input")
            }
            lock.unlock()
            return nil
        case .keyDown:
            result = machine.keyDown(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
        case .flagsChanged:
            result = machine.flagsChanged(flags: event.flags)
        default:
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        lock.unlock()

        if !result.actions.isEmpty {
            let actions = result.actions
            DispatchQueue.main.async { [weak self] in
                self?.perform(actions)
            }
        }
        return result.consume ? nil : Unmanaged.passUnretained(event)
    }

    /// Main thread
    private func perform(_ actions: [ShortcutAction]) {
        for action in actions {
            switch action {
            case .open(let forward, let session): delegate?.hotkeyTriggered(forward: forward, session: session)
            case .cycle(let forward): delegate?.hotkeyCycle(forward: forward)
            case .navigate(let direction): delegate?.hotkeyNavigate(direction: direction)
            case .toggleLayout: delegate?.hotkeyToggleLayout()
            case .confirm: delegate?.hotkeyConfirmed()
            case .cancel: delegate?.hotkeyCancelled()
            case .triggerModifierDown: onTriggerModifierDown?()
            }
        }
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
