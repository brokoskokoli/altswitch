<!-- SPDX-License-Identifier: MIT -->
# Changelog

All notable changes to AltSwitch. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/brokoskokoli/altswitch/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/brokoskokoli/altswitch/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/brokoskokoli/altswitch/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/brokoskokoli/altswitch/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/brokoskokoli/altswitch/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/brokoskokoli/altswitch/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/brokoskokoli/altswitch/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/brokoskokoli/altswitch/releases/tag/v1.0.1
[1.0.0]: https://github.com/brokoskokoli/altswitch/commits/6f36082
