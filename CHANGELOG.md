<!-- SPDX-License-Identifier: MIT -->
# Changelog

All notable changes to AltSwitch. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-11-19

### Added
- **Close windows from the switcher:** hold `Q` and click a card or row – the window closes as with
  its close button, so the app can still ask to save. The switcher stays open for the next one.
  Can be turned off in the menu (*Q + Click Closes Windows*).

### Changed
- **Smooth scrolling with the mouse:** near the top or bottom edge of the list (left or right in the
  carousel) it now scrolls continuously, slowly at first and faster the closer the pointer gets to
  the edge. Before, a card touched at the edge was centred at once, which moved the next card under
  the pointer and made the list race away.

## [1.2.3] - 2026-11-19

### Added
- **Secure keyboard entry:** the menu shows when another app (a password field, Terminal's
  *Secure Keyboard Entry*) has secure keyboard entry on. macOS then gives key presses to no other
  app, so ⌘-Tab brings up the system switcher; the README explains it under *Troubleshooting*.
- **Copy Diagnostics** in the menu copies version, permissions and state for a bug report – no
  window titles or app names.

### Changed
- **Keys inside the switcher:** while it is open, other keys do nothing. Before, ⌘Q out of habit
  from the system switcher went to the app being left and quit it.
- **⌃⌥-Tab** no longer opens the switcher in the ⌥-Tab mode.
- **Smoother with busy apps:** an app that stops answering costs at most one timeout per press,
  not one per window, and AltSwitch stops retrying to watch such an app on every press.
- **Less work in the background:** previews are only kept for windows of apps the switcher lists.
- When no previews can be captured on a macOS version, cards say so instead of "Loading…".

### Fixed
- **Stuck switcher:** if the release of the modifier key was missed (sleep, secure input), the
  switcher stayed open and swallowed keys. Pressing the modifier again or any key without it now
  closes the switcher, and the key or shortcut goes through. When macOS switches the keyboard hook
  off for a moment, AltSwitch checks the modifier keys as soon as it is back.
- **Accessibility permission taken away while running:** AltSwitch now removes its keyboard hook
  and installs it again once the permission is back, and no longer switches the hook back on without
  the permission. An active hook without the permission can leave the whole Mac without keyboard
  input. A hook that macOS switched off for good is replaced.
- **Wrong window raised:** when a window had to be found by its frame, a window of the same app
  with only the same size (or only the same position) could be raised instead.
- Removed an unused Apple Events permission text from Info.plist.

## [1.2.2] - 2026-11-19

1.2.1 was tagged but never released; its changes are part of this release.

### Fixed
- **Memory:** AltSwitch no longer keeps a copy of every key press (about 1 KB each), so its memory
  use stays flat however long it runs.
- **System app switcher instead of AltSwitch:** now and then ⌘-Tab brought up macOS's own app
  switcher, and only the second try opened AltSwitch. The shortcut was handled on the same thread
  as everything else; when that thread waited on an app that was slow to answer, macOS switched
  the shortcut handling off and passed ⌘-Tab on to the system. The shortcut now has a thread of its
  own and always reaches AltSwitch.
- **Stuck switcher:** pressing ⌘-Tab twice in quick succession while AltSwitch was busy could
  leave the switcher open, and releasing ⌘ no longer chose a window.

### Changed
- **Smoother:** AltSwitch waits at most 0.3 s for an app that does not answer (before: up to 6 s
  per window), so a busy app no longer freezes the switcher or the switch to the chosen window.

## [1.2.0] - 2026-10-25

### Added
- **Grouped by app:** a third layout lists the windows app by app – app icon and name as a header,
  below it the full window titles (e.g. `file.swift — project` in VS Code or
  `user@host: ~/project — zsh` in Terminal) instead of previews. Apps are ordered by when you last
  used them, their windows too; a quick Tab still goes back to the window you used before. `↑` `↓`
  move by row, `←` `→` jump to the previous or next app. Choose it under *Layout* in the menu or
  in the setup assistant, or press `G` while the switcher is open to flip between cards and list.

### Changed
- **Faster:** the switcher opens about twice as fast (around 25 ms instead of 50–60 ms here with
  30 windows, the first press after launch around 50 ms instead of 90–100 ms), in the cards and in
  the grouped list. AltSwitch now asks all apps at once instead of one after the other, and gets
  the list of running apps ready as soon as you press the modifier key.
- **Faster start:** AltSwitch is ready about 2.5 times sooner after launch (around 120–160 ms
  instead of 310–390 ms here), because it contacts all apps at once.
- **Previews:** fresh window previews arrive about 2.5 times faster after the switcher opens.

### Fixed
- **Missing windows:** windows on another desktop (Space), in full screen and of hidden apps (⌘H)
  now appear in the switcher, like on Windows. Before, AltSwitch only listed windows visible on
  the current desktop plus minimized ones, so an app such as VS Code could be missing entirely.
  Picking such a window switches to its desktop or shows the app again.
- **Window titles:** several windows of one app with the same size no longer all show the same
  title; titles are matched by window ID.

## [1.1.3] - 2026-10-19

### Fixed
- **Windows of the same app:** switching between several windows of one app (e.g. VS Code)
  now opens the window you picked. Before, AltSwitch often brought up another window of that app
  because the windows had the same size.

## [1.1.2] - 2026-10-19

### Fixed
- **Window order:** windows are listed by when you last used them, like Alt-Tab on Windows.
  Before, all windows of an app came first as a group as soon as you switched to that app,
  because macOS raises all of them together.

## [1.1.1] - 2026-10-19

### Changed
- **Faster:** the switcher appears about four times faster on the first press (around 50 ms
  instead of 300 ms here). AltSwitch prepares the overlay at launch, contacts apps in the
  background and is exempt from App Nap, so it also stays quick after a long pause.
- **Previews at once:** cards show the last known image of each window immediately instead of
  “Loading…”, then refresh it.

## [1.1.0] - 2026-10-18

### Added
- **25 languages:** English, German, French, Spanish, Italian, Portuguese (Brazil and Portugal),
  Dutch, Polish, Czech, Slovak, Swedish, Danish, Norwegian Bokmål, Finnish, Hungarian, Romanian,
  Greek, Turkish, Russian, Ukrainian, Japanese, Korean and Chinese (Simplified and Traditional).
- **Language setting:** the menu bar menu has a “Language” submenu. “System Language” (the
  default) follows macOS, or pick any language; the switch takes effect at once, without a restart.

### Fixed
- **Highlight:** every selected card is highlighted while you step through with Tab. Before, some
  cards stayed without the blue frame although the counter moved on. Several minimized windows of
  one app could get the same internal ID, which caused this.

## [1.0.2] - 2026-10-18

### Added
- **Previews of minimized windows:** they show the last image from before they were minimized.
- **Start at login** is switched on at the first launch from the Applications folder. You can turn
  it off in the menu bar menu.
- **Single instance:** a second launch shows a notice (“AltSwitch läuft bereits”) and quits.

### Fixed
- **Grid view:** `↓` no longer jumps back to the first row when the last row is shorter.
- **Grid view:** scrolling under a resting mouse pointer no longer changes the selection.

## [1.0.1] - 2026-10-18

### Changed
- **Signed and notarized:** AltSwitch is signed with an Apple Developer ID and notarized by Apple,
  so it opens without a Gatekeeper warning.
- **Universal app:** runs natively on Apple silicon and Intel Macs.
- **Homebrew:** `brew install --cask brokoskokoli/tap/altswitch`.

## [1.0.0] - 2026-10-17

First version (unsigned, withdrawn).

[Unreleased]: https://github.com/brokoskokoli/altswitch/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/brokoskokoli/altswitch/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/brokoskokoli/altswitch/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/brokoskokoli/altswitch/compare/v1.2.0...v1.2.2
[1.2.0]: https://github.com/brokoskokoli/altswitch/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/brokoskokoli/altswitch/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/brokoskokoli/altswitch/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/brokoskokoli/altswitch/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/brokoskokoli/altswitch/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/brokoskokoli/altswitch/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/brokoskokoli/altswitch/releases/tag/v1.0.1
[1.0.0]: https://github.com/brokoskokoli/altswitch/commits/6f36082
