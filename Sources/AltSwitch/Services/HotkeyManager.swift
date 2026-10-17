import Cocoa
import Carbon
import ApplicationServices

public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyTriggered(forward: Bool)
    func hotkeyCycle(forward: Bool)
    func hotkeyNavigate(direction: NavigationDirection)
    func hotkeyConfirmed()
    func hotkeyCancelled()
}

public class HotkeyManager {
    public static let shared = HotkeyManager()

    public weak var delegate: HotkeyManagerDelegate?
    public var isOverlayActive: Bool = false {
        didSet {
            if !isOverlayActive {
                activeTriggerModifier = nil
                wasShiftDown = false
                shiftWasUsedWithKey = false
            }
        }
    }

    private var activeTriggerModifier: CGEventFlags?
    private var wasShiftDown: Bool = false
    private var shiftWasUsedWithKey: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private init() {}

    public func start() {
        stop()
        setupEventTap()

        if eventTap == nil {
            // Periodically attempt to acquire the tap once permission is granted
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.eventTap == nil && PermissionsManager.shared.isAccessibilityGranted {
                    self.setupEventTap()
                    if self.eventTap != nil {
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

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
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

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("AltSwitch: EventTap re-enabled after %@", type == .tapDisabledByTimeout ? "timeout" : "user input")
            }
            return nil
        }

        let flags = event.flags
        let currentMode = AppSettings.shared.shortcutMode

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

                if !isOverlayActive {
                    isOverlayActive = true
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
            if isOverlayActive {
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

                case 53: // Escape
                    isOverlayActive = false
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyCancelled()
                    }
                    return nil

                case 36, 49: // Return or Space
                    isOverlayActive = false
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
            if isOverlayActive, let trigger = activeTriggerModifier {
                let isTriggerStillDown = flags.contains(trigger)

                if !isTriggerStillDown {
                    // Trigger modifier was released! Confirm selection and dismiss
                    isOverlayActive = false
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
            }
        }

        return Unmanaged.passRetained(event)
    }
}
