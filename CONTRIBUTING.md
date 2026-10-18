<!-- SPDX-License-Identifier: MIT -->
# Contributing to AltSwitch

Thanks for your interest! Bug reports, documentation fixes and code are all welcome.
By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

- **Found a bug?** Open a [bug report](https://github.com/brokoskokoli/altswitch/issues/new?template=bug_report.yml).
- **Have an idea?** Start a [feature request](https://github.com/brokoskokoli/altswitch/issues/new?template=feature_request.yml)
  or a thread in [Discussions](https://github.com/brokoskokoli/altswitch/discussions).
- **Security issue?** Please don't open a public issue – see [SECURITY.md](SECURITY.md).

## Development setup

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
ARCHS=arm64 ./build.sh          # fast local build → .build/AltSwitch.app (ad-hoc signed)
open .build/AltSwitch.app
./build.sh                      # universal build, as in the release
```

macOS ties the Accessibility and Screen Recording permissions to the code signature: an ad-hoc
build is a different app for macOS, so grant the permissions again (or remove the old entry in
*System Settings → Privacy & Security* first). Quit any installed AltSwitch before testing – only
one instance runs at a time.

## Project layout

| Path | Contents |
|---|---|
| `Sources/AltSwitch/App/` | App entry point and delegate |
| `Sources/AltSwitch/Models/` | Window model and settings |
| `Sources/AltSwitch/Services/` | Hotkey event tap, window list and previews, permissions, autostart |
| `Sources/AltSwitch/UI/` | Overlay panel, cards, menu bar, setup assistant (SwiftUI + AppKit) |
| `Resources/` | `Info.plist`, app icon |
| `tools/` | Release packaging and secrets setup |
| `packaging/brand/` | Icon PNG and social preview template |
| `website/` | Project homepage (GitHub Pages) |
| `docs/` | Release process |

## Coding conventions

<!-- REUSE-IgnoreStart -->
- Every source file starts with an SPDX line: `// SPDX-License-Identifier: MIT`.
<!-- REUSE-IgnoreEnd -->
- Match the surrounding code: Swift API Design Guidelines, four-space indent, comments explain *why*.
- Keep pull requests focused: one logical change per PR.

## Commit messages

- One logical change per commit. Summary line ≤ 72 characters, no trailing period.
- In the body, explain *why*, and reference issues (`#123`).
- Don't add e-mail addresses beyond your own author identity. Using your GitHub `noreply`
  address as the author e-mail is recommended.

## Licensing of contributions

AltSwitch is licensed under **MIT**. Contributions are accepted under the same licence
(*inbound = outbound*): by opening a pull request you agree that your contribution is licensed
under MIT. There is **no CLA**. A `Signed-off-by` line
([Developer Certificate of Origin](https://developercertificate.org)) is welcome but not required.

Only contribute code you wrote yourself or that is under a compatible licence – say so in the PR
when you include third-party code, and add its licence to `LICENSES/` and `REUSE.toml`.

## Pull request checklist

- [ ] The change is described in an issue (for features: discussed first)
- [ ] `./build.sh` succeeds and the change was tried in the running app
- [ ] New files carry an SPDX header
- [ ] User-visible changes are noted in [CHANGELOG.md](CHANGELOG.md) under *Unreleased*
- [ ] Docs updated where needed (README, docs/, website/)

The [pull request template](.github/PULL_REQUEST_TEMPLATE.md) contains the same list.
