<!-- SPDX-License-Identifier: MIT -->
**English** · [Deutsch](README.de.md)

<div align="center">

<img src="packaging/brand/icon-1024.png" width="128" height="128" alt="AltSwitch app icon">

# AltSwitch

**Windows-style Alt-Tab for your Mac: switch between windows, not just apps.**

[![CI](https://github.com/brokoskokoli/altswitch/actions/workflows/ci.yml/badge.svg)](https://github.com/brokoskokoli/altswitch/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/brokoskokoli/altswitch?sort=semver)](https://github.com/brokoskokoli/altswitch/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#install)
[![Universal: Apple silicon + Intel](https://img.shields.io/badge/universal-Apple%20silicon%20%2B%20Intel-lightgrey.svg)](#install)
[![Homebrew: brokoskokoli/tap](https://img.shields.io/badge/homebrew-brokoskokoli%2Ftap-orange.svg)](https://github.com/brokoskokoli/homebrew-tap)

<img src="website/images/social-preview.png" width="820" alt="AltSwitch: Windows-style Alt-Tab for your Mac. Switch windows, not just apps.">

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-latest_release-2F6FE0?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/brokoskokoli/altswitch/releases/latest)

</div>

## Why AltSwitch?

On a Mac, `⌘-Tab` switches between **apps**. With three browser windows, two documents and a few
terminals open, you end up in Mission Control or pressing `⌘-<` until the right window shows up.

AltSwitch works like Alt-Tab on Windows: **every window of every app is its own card with a live
preview**, in the order you last used them. Hold the modifier, tap Tab, let go – you are in the
window you wanted.

## Features

- **Every window, not every app** – each open window gets its own card with app icon, title and
  live preview.
- **Most recently used order** – the first Tab selects the window you used before the current one.
- **Two layouts** – a compact carousel for quick switching, or a grid of all windows (like Task
  View on Windows) with arrow-key navigation in both directions.
- **Your shortcut** – `⌥-Tab` (Option-Tab) or `⌘-Tab` (replaces the app switcher), set in the menu.
- **Keyboard or mouse** – `⇧-Tab` or a tap on Shift goes back, `Esc` cancels, a single click
  activates a card.
- **Minimized windows** included, marked with a badge, restored when you pick them.
- **25 languages** – follows the macOS language or the one you pick in the menu (Language).
- **Menu bar app** – no Dock icon, a setup assistant for the macOS permissions, optional start at
  login.
- **Native and light** – Swift, AppKit and SwiftUI, no Electron.
- **Private** – no network connections at all, no telemetry, no account.
- **Free and open source** – MIT licence.

## Install

Requirements: **macOS 13 Ventura or later**, Apple silicon or Intel (universal app).

- **Homebrew:**

  ```sh
  brew install --cask brokoskokoli/tap/altswitch
  ```

  Updates: `brew upgrade --cask altswitch`.

- **Download:** get `AltSwitch-<version>.dmg` from the
  [latest release](https://github.com/brokoskokoli/altswitch/releases/latest), open it and drag
  AltSwitch into *Applications*. Releases are signed with a Developer ID and notarized by Apple.

On first launch the setup assistant asks for two permissions in *System Settings → Privacy &
Security*:

| Permission | Why | Required |
|---|---|---|
| **Accessibility** | catch the shortcut, focus and raise the chosen window | yes |
| **Screen Recording** | window previews on the cards | no – without it the cards show the app icon |

**Uninstall:** quit AltSwitch from the menu bar and delete it from *Applications*
(`brew uninstall --cask --zap altswitch` also removes the settings).

## Keyboard shortcuts

| Action | Keys |
|---|---|
| Open the switcher, next window | `⌥-Tab` or `⌘-Tab` |
| Next / previous | `Tab` / `⇧-Tab`, or tap `⇧` |
| Move in carousel or grid | `←` `→` `↑` `↓` |
| Switch to the selected window | release the modifier, `Return` or `Space` |
| Switch by mouse | click a card |
| Cancel | `Esc` |

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/brokoskokoli/altswitch.git
cd altswitch
./build.sh                 # universal build → .build/AltSwitch.app
open .build/AltSwitch.app
```

`ARCHS=arm64 ./build.sh` builds only for Apple silicon (faster). Local builds are signed ad hoc;
macOS asks for the permissions again for such a build.

## Privacy

AltSwitch makes **no network connections** – no update check, no analytics, no crash reporter.
Window previews stay in memory and are never written to disk. The only stored data are your
settings in `~/Library/Preferences/com.stefanrichter.altswitch.plist`. Details on the
[privacy page](https://brokoskokoli.github.io/altswitch/privacy.html).

## Contributing

Bug reports, ideas and pull requests are welcome – see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Please report security issues privately as described in
[SECURITY.md](SECURITY.md). Releases are documented in [CHANGELOG.md](CHANGELOG.md), the release
process in [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE) © 2026 brokoskokoli and contributors.
