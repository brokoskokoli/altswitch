// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing
@testable import AltSwitch

private typealias Key = ShortcutStateMachine.KeyCode

// Flags as macOS sends them: the modifier plus the device bit of the key that is held
private let leftCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
private let rightCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
private let bothCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08 | 0x10)
private let leftOpt = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
private let leftShift: Int64 = 56

private func machine(_ mode: ShortcutMode) -> ShortcutStateMachine {
    var machine = ShortcutStateMachine()
    machine.mode = mode
    return machine
}

/// ⌘ down, then ⌘⇥: the switcher is open with session 1
private func openCmdTab() -> ShortcutStateMachine {
    var m = machine(.cmdTab)
    _ = m.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd)
    _ = m.keyDown(keyCode: Key.tab, flags: leftCmd)
    return m
}

@Suite("Shortcut state machine")
struct ShortcutStateMachineTests {
    @Test("⌘⇥ opens, a further Tab moves on, releasing ⌘ confirms")
    func openCycleConfirm() {
        var m = machine(.cmdTab)
        #expect(m.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd).actions == [.triggerModifierDown])

        let open = m.keyDown(keyCode: Key.tab, flags: leftCmd)
        #expect(open == .init(actions: [.open(forward: true, session: 1)], consume: true))
        #expect(m.isActive)

        let cycle = m.keyDown(keyCode: Key.tab, flags: leftCmd)
        #expect(cycle == .init(actions: [.cycle(forward: true)], consume: true))

        let release = m.flagsChanged(keyCode: Key.leftCommand, flags: [])
        #expect(release.actions == [.confirm])
        #expect(!release.consume)
        #expect(!m.isActive)
    }

    @Test("⇧ with Tab goes backwards; ⇧ tapped alone steps back once")
    func shiftHandling() {
        var m = machine(.optionTab)
        let optShift = leftOpt.union(.maskShift)
        #expect(m.keyDown(keyCode: Key.tab, flags: optShift).actions == [.open(forward: false, session: 1)])
        // ⇧ released after being used with Tab: no extra step
        #expect(m.flagsChanged(keyCode: leftShift, flags: leftOpt).actions.isEmpty)
        // ⇧ tapped alone
        #expect(m.flagsChanged(keyCode: leftShift, flags: optShift).actions.isEmpty)
        #expect(m.flagsChanged(keyCode: leftShift, flags: leftOpt).actions == [.cycle(forward: false)])
        // ⇧⇥ in an open switcher goes back one step
        #expect(m.keyDown(keyCode: Key.tab, flags: optShift) == .init(actions: [.cycle(forward: false)], consume: true))
    }

    @Test("Wrong modifier combinations do not open the switcher")
    func modifierCombinations() {
        var cmd = machine(.cmdTab)
        #expect(cmd.keyDown(keyCode: Key.tab, flags: leftCmd.union(.maskAlternate)) == .init())
        #expect(cmd.keyDown(keyCode: Key.tab, flags: leftOpt) == .init())

        var option = machine(.optionTab)
        #expect(option.keyDown(keyCode: Key.tab, flags: leftOpt.union(.maskCommand)) == .init())
        #expect(option.keyDown(keyCode: Key.tab, flags: leftOpt.union(.maskControl)) == .init())
        #expect(option.keyDown(keyCode: Key.tab, flags: []) == .init())
        #expect(!option.isActive)
    }

    @Test("Keys pass through while the switcher is closed")
    func closedPassesKeys() {
        var m = machine(.cmdTab)
        #expect(m.keyDown(keyCode: 12, flags: leftCmd) == .init()) // ⌘Q
        #expect(m.keyDown(keyCode: Key.escape, flags: []) == .init())
    }

    @Test("While open, every key is swallowed: ⌘Q must not quit the app being left")
    func openSwallowsKeys() {
        var m = openCmdTab()
        #expect(m.keyDown(keyCode: 12, flags: leftCmd) == .init(actions: [], consume: true))
        #expect(m.keyDown(keyCode: Key.leftArrow, flags: leftCmd)
            == .init(actions: [.navigate(.left)], consume: true))
        #expect(m.keyDown(keyCode: Key.g, flags: leftCmd)
            == .init(actions: [.toggleLayout], consume: true))
        #expect(m.isActive)
    }

    @Test("Escape cancels, Return and Space confirm")
    func escapeReturnSpace() {
        var m = openCmdTab()
        #expect(m.keyDown(keyCode: Key.escape, flags: leftCmd) == .init(actions: [.cancel], consume: true))
        #expect(!m.isActive)

        _ = m.keyDown(keyCode: Key.tab, flags: leftCmd)
        #expect(m.keyDown(keyCode: Key.space, flags: leftCmd) == .init(actions: [.confirm], consume: true))
        _ = m.keyDown(keyCode: Key.tab, flags: leftCmd)
        #expect(m.keyDown(keyCode: Key.returnKey, flags: leftCmd) == .init(actions: [.confirm], consume: true))
    }

    @Test("Missed release, then a key without ⌘: the switcher closes and the key goes through")
    func missedReleaseThenPlainKey() {
        var m = openCmdTab()
        let typed = m.keyDown(keyCode: 0, flags: [])
        #expect(typed == .init(actions: [.cancel], consume: false))
        #expect(!m.isActive)

        // A new ⌘⇥ opens a fresh session
        #expect(m.keyDown(keyCode: Key.tab, flags: leftCmd).actions == [.open(forward: true, session: 2)])
    }

    @Test("Missed release, then Tab alone: closes and lets the Tab through")
    func missedReleaseThenTab() {
        var m = openCmdTab()
        #expect(m.keyDown(keyCode: Key.tab, flags: []) == .init(actions: [.cancel], consume: false))
    }

    @Test("Missed release, then ⌘ pressed again: the switcher closes, the ⌘ shortcut goes through")
    func missedReleaseThenCommandShortcut() {
        var m = openCmdTab()
        // ⌘ goes down again: its release in between was never seen
        let press = m.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd)
        #expect(press.actions == [.cancel, .triggerModifierDown])
        #expect(!m.isActive)
        // ⌘S reaches the app, and releasing ⌘ switches nothing
        #expect(m.keyDown(keyCode: 1, flags: leftCmd) == .init())
        #expect(m.flagsChanged(keyCode: Key.leftCommand, flags: []).actions.isEmpty)
    }

    @Test("Releasing one ⌘ key while the other is held keeps the switcher open")
    func twoCommandKeys() {
        // Both ⌘ keys down before the switcher opens
        var held = machine(.cmdTab)
        _ = held.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd)
        _ = held.flagsChanged(keyCode: Key.rightCommand, flags: bothCmd)
        _ = held.keyDown(keyCode: Key.tab, flags: bothCmd)
        // Right ⌘ up, left still down: the device bit of the right key is gone, ⌘ stays
        #expect(held.flagsChanged(keyCode: Key.rightCommand, flags: leftCmd).actions.isEmpty)
        #expect(held.isActive)
        #expect(held.flagsChanged(keyCode: Key.leftCommand, flags: []).actions == [.confirm])
    }

    @Test("After the tap was switched off, the real modifier state closes a stale switcher")
    func syncAfterTapOutage() {
        var m = openCmdTab()
        #expect(m.sync(flags: leftCmd).actions.isEmpty)
        #expect(m.isActive)
        #expect(m.sync(flags: []).actions == [.cancel])
        #expect(!m.isActive)
        // Nothing open: nothing to do
        #expect(m.sync(flags: []).actions.isEmpty)
    }

    @Test("Ending an earlier session leaves a newer one open")
    func staleEndIsIgnored() {
        var m = openCmdTab()
        _ = m.flagsChanged(keyCode: Key.leftCommand, flags: [])
        _ = m.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd)
        _ = m.keyDown(keyCode: Key.tab, flags: leftCmd) // session 2, ⌘ still held
        m.end(session: 1)
        #expect(m.isActive)
        #expect(m.flagsChanged(keyCode: Key.leftCommand, flags: []).actions == [.confirm])

        _ = m.flagsChanged(keyCode: Key.leftCommand, flags: leftCmd)
        _ = m.keyDown(keyCode: Key.tab, flags: leftCmd) // session 3
        m.end(session: 3)
        #expect(!m.isActive)
        // Ending when nothing is open changes nothing
        m.end(session: 3)
        #expect(!m.isActive)
    }

    @Test("Changing the shortcut while the switcher is open: releasing the key that opened it confirms")
    func modeChangeWhileOpen() {
        var m = openCmdTab()
        m.mode = .optionTab
        #expect(m.flagsChanged(keyCode: Key.leftCommand, flags: []).actions == [.confirm])
        // From now on ⌥⇥ opens it
        #expect(m.keyDown(keyCode: Key.tab, flags: leftOpt).actions == [.open(forward: true, session: 2)])
    }

    @Test("Esc with ⌘ still held, then Tab: a fresh opening")
    func reopenAfterEscape() {
        var m = openCmdTab()
        _ = m.keyDown(keyCode: Key.escape, flags: leftCmd)
        // Shift pressed in between: the held ⌘ counts as a new possible press (prepares the list)
        #expect(m.flagsChanged(keyCode: leftShift, flags: leftCmd.union(.maskShift)).actions == [.triggerModifierDown])
        #expect(m.keyDown(keyCode: Key.tab, flags: leftCmd.union(.maskShift)).actions
            == [.open(forward: false, session: 2)])
        #expect(m.flagsChanged(keyCode: Key.leftCommand, flags: .maskShift).actions == [.confirm])
    }
}
