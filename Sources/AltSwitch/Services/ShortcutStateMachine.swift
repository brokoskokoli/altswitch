// SPDX-License-Identifier: MIT

import CoreGraphics

/// What a key event asks the switcher to do.
enum ShortcutAction: Equatable {
    /// Open the switcher. `session` numbers the opening (see HotkeyManager.endSession).
    case open(forward: Bool, session: UInt64)
    case cycle(forward: Bool)
    case navigate(NavigationDirection)
    case toggleLayout
    case confirm
    case cancel
    /// The shortcut's modifier went down while the switcher is closed: a press may follow.
    case triggerModifierDown
}

/// The keyboard logic of the switcher, without the event tap: which key events open, move, confirm
/// or close it, and which ones are swallowed. Pure state, so it can be tested.
struct ShortcutStateMachine {
    struct Result: Equatable {
        var actions: [ShortcutAction] = []
        /// Keep the event from the frontmost app and the system
        var consume = false
    }

    enum KeyCode {
        static let tab: Int64 = 48
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
        static let g: Int64 = 5
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let space: Int64 = 49
    }

    var mode: ShortcutMode = .optionTab

    private(set) var isActive = false
    /// Counts the openings of the switcher
    private(set) var session: UInt64 = 0
    private var activeTriggerModifier: CGEventFlags?
    private var wasShiftDown = false
    private var shiftWasUsedWithKey = false
    private var wasTriggerModifierDown = false

    private var triggerFlag: CGEventFlags {
        mode == .cmdTab ? .maskCommand : .maskAlternate
    }

    /// Ends the active opening without an action (closed by the main thread or after an error).
    mutating func reset() {
        isActive = false
        activeTriggerModifier = nil
        wasTriggerModifierDown = false
        wasShiftDown = false
        shiftWasUsedWithKey = false
    }

    /// Ends `session` if it is still the active one; a newer opening stays.
    mutating func end(session: UInt64) {
        if self.session == session {
            reset()
        }
    }

    mutating func keyDown(keyCode: Int64, flags: CGEventFlags) -> Result {
        var result = Result()

        // The release of the modifier was missed (tap switched off for a moment, secure input,
        // sleep): the switcher would stay open and swallow every key. Close it and handle the key
        // as if it had never been open.
        if isActive, let trigger = activeTriggerModifier, !flags.contains(trigger) {
            reset()
            result.actions.append(.cancel)
        }

        let isShiftDown = flags.contains(.maskShift)
        let isTriggerModifierDown: Bool
        switch mode {
        case .optionTab:
            // ⌥ alone: not with ⌘ (system shortcuts) or ⌃
            isTriggerModifierDown = flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
        case .cmdTab:
            isTriggerModifierDown = flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
        }

        if keyCode == KeyCode.tab && isTriggerModifierDown {
            let forward = !isShiftDown
            wasShiftDown = isShiftDown
            if isShiftDown {
                shiftWasUsedWithKey = true
            }
            if isActive {
                result.actions.append(.cycle(forward: forward))
            } else {
                isActive = true
                activeTriggerModifier = triggerFlag
                session &+= 1
                result.actions.append(.open(forward: forward, session: session))
            }
            result.consume = true
            return result
        }

        guard isActive else { return result }

        // While the switcher is open no key reaches the app being left: ⌘Q out of habit from the
        // system switcher would quit it
        result.consume = true
        switch keyCode {
        case KeyCode.rightArrow: result.actions.append(.navigate(.right))
        case KeyCode.leftArrow: result.actions.append(.navigate(.left))
        case KeyCode.upArrow: result.actions.append(.navigate(.up))
        case KeyCode.downArrow: result.actions.append(.navigate(.down))
        // By position, so it works with any keyboard layout and any modifier held
        case KeyCode.g: result.actions.append(.toggleLayout)
        case KeyCode.escape:
            reset()
            result.actions.append(.cancel)
        case KeyCode.returnKey, KeyCode.space:
            reset()
            result.actions.append(.confirm)
        default:
            break
        }
        return result
    }

    mutating func flagsChanged(flags: CGEventFlags) -> Result {
        var result = Result()

        if isActive, let trigger = activeTriggerModifier {
            if !flags.contains(trigger) {
                // Modifier released: choose the selected window
                reset()
                result.actions.append(.confirm)
                return result
            }

            let isShiftNowDown = flags.contains(.maskShift)
            if isShiftNowDown && !wasShiftDown {
                shiftWasUsedWithKey = false
            } else if !isShiftNowDown && wasShiftDown && !shiftWasUsedWithKey {
                // Shift tapped alone (not used with Tab): one step back
                result.actions.append(.cycle(forward: false))
            }
            wasShiftDown = isShiftNowDown
            return result
        }

        wasShiftDown = flags.contains(.maskShift)
        shiftWasUsedWithKey = false
        let isTriggerDown = flags.contains(triggerFlag)
        if isTriggerDown && !wasTriggerModifierDown {
            result.actions.append(.triggerModifierDown)
        }
        wasTriggerModifierDown = isTriggerDown
        return result
    }
}
