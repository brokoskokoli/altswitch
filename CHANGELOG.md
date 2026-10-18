<!-- SPDX-License-Identifier: MIT -->
# Changelog

All notable changes to AltSwitch. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/brokoskokoli/altswitch/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/brokoskokoli/altswitch/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/brokoskokoli/altswitch/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/brokoskokoli/altswitch/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/brokoskokoli/altswitch/releases/tag/v1.0.1
[1.0.0]: https://github.com/brokoskokoli/altswitch/commits/6f36082
