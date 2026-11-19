// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing
@testable import AltSwitch

private typealias Key = ShortcutStateMachine.KeyCode

private func machine(_ mode: ShortcutMode) -> ShortcutStateMachine {
    var machine = ShortcutStateMachine()
    machine.mode = mode
    return machine
}

@Suite("Shortcut state machine")
struct ShortcutStateMachineTests {
    @Test("⌘⇥ opens, a further Tab moves on, releasing ⌘ confirms")
    func openCycleConfirm() {
        var m = machine(.cmdTab)
        #expect(m.flagsChanged(flags: .maskCommand).actions == [.triggerModifierDown])

        let open = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(open == .init(actions: [.open(forward: true, session: 1)], consume: true))
        #expect(m.isActive)

        let cycle = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(cycle == .init(actions: [.cycle(forward: true)], consume: true))

        let release = m.flagsChanged(flags: [])
        #expect(release.actions == [.confirm])
        #expect(!release.consume)
        #expect(!m.isActive)
    }

    @Test("⇧ with Tab goes backwards; ⇧ tapped alone steps back once")
    func shiftHandling() {
        var m = machine(.optionTab)
        #expect(m.keyDown(keyCode: Key.tab, flags: [.maskAlternate, .maskShift]).actions
            == [.open(forward: false, session: 1)])
        // ⇧ released after being used with Tab: no extra step
        #expect(m.flagsChanged(flags: .maskAlternate).actions.isEmpty)
        // ⇧ tapped alone
        #expect(m.flagsChanged(flags: [.maskAlternate, .maskShift]).actions.isEmpty)
        #expect(m.flagsChanged(flags: .maskAlternate).actions == [.cycle(forward: false)])
    }

    @Test("Wrong modifier combinations do not open the switcher")
    func modifierCombinations() {
        var cmd = machine(.cmdTab)
        #expect(cmd.keyDown(keyCode: Key.tab, flags: [.maskCommand, .maskAlternate]) == .init())
        #expect(cmd.keyDown(keyCode: Key.tab, flags: .maskAlternate) == .init())

        var option = machine(.optionTab)
        #expect(option.keyDown(keyCode: Key.tab, flags: [.maskAlternate, .maskCommand]) == .init())
        #expect(option.keyDown(keyCode: Key.tab, flags: [.maskAlternate, .maskControl]) == .init())
        #expect(option.keyDown(keyCode: Key.tab, flags: []) == .init())
        #expect(!option.isActive)
    }

    @Test("Keys pass through while the switcher is closed")
    func closedPassesKeys() {
        var m = machine(.cmdTab)
        #expect(m.keyDown(keyCode: 12, flags: .maskCommand) == .init()) // ⌘Q
        #expect(m.keyDown(keyCode: Key.escape, flags: []) == .init())
    }

    @Test("While open, every key is swallowed: ⌘Q must not quit the app being left")
    func openSwallowsKeys() {
        var m = machine(.cmdTab)
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(m.keyDown(keyCode: 12, flags: .maskCommand) == .init(actions: [], consume: true))
        #expect(m.keyDown(keyCode: Key.leftArrow, flags: .maskCommand)
            == .init(actions: [.navigate(.left)], consume: true))
        #expect(m.keyDown(keyCode: Key.g, flags: .maskCommand)
            == .init(actions: [.toggleLayout], consume: true))
        #expect(m.isActive)
    }

    @Test("Escape cancels, Return and Space confirm")
    func escapeReturnSpace() {
        var m = machine(.cmdTab)
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(m.keyDown(keyCode: Key.escape, flags: .maskCommand) == .init(actions: [.cancel], consume: true))
        #expect(!m.isActive)

        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(m.keyDown(keyCode: Key.space, flags: .maskCommand) == .init(actions: [.confirm], consume: true))
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        #expect(m.keyDown(keyCode: Key.returnKey, flags: .maskCommand) == .init(actions: [.confirm], consume: true))
    }

    @Test("A missed release closes the switcher at the next key, which then goes through")
    func missedReleaseRecovers() {
        var m = machine(.cmdTab)
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        // The flagsChanged for releasing ⌘ never arrived; the user types a letter
        let typed = m.keyDown(keyCode: 0, flags: [])
        #expect(typed == .init(actions: [.cancel], consume: false))
        #expect(!m.isActive)

        // A new ⌘⇥ opens a fresh session
        #expect(m.keyDown(keyCode: Key.tab, flags: .maskCommand).actions == [.open(forward: true, session: 2)])
    }

    @Test("Ending an earlier session leaves a newer one open")
    func staleEndIsIgnored() {
        var m = machine(.cmdTab)
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand)
        _ = m.flagsChanged(flags: [])
        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand) // session 2, ⌘ still held
        m.end(session: 1)
        #expect(m.isActive)
        #expect(m.flagsChanged(flags: []).actions == [.confirm])

        _ = m.keyDown(keyCode: Key.tab, flags: .maskCommand) // session 3
        m.end(session: 3)
        #expect(!m.isActive)
    }
}
