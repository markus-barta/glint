<p align="center">
  <img src="docs/screenshots/hero-0.3.1.png" alt="GLINT — point at a ticket and know what matters" width="100%">
</p>

<p align="center">
  <a href="https://github.com/markus-barta/glint/releases/latest"><img src="https://img.shields.io/badge/release-0.3.1-0A84FF?style=flat-square" alt="Latest release 0.3.1"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111827?style=flat-square&logo=apple" alt="macOS 13 or newer">
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/OCR-local-22C55E?style=flat-square" alt="Local OCR">
  <img src="https://img.shields.io/badge/lookups-read--only-22C55E?style=flat-square" alt="Read-only lookups">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-0A84FF?style=flat-square" alt="GNU AGPL v3.0"></a>
</p>

<p align="center">
  <strong>Ticket context, right where you point.</strong><br>
  GLINT is a private macOS menu-bar utility that turns nearby issue references into useful, navigable cards.
</p>

<p align="center">
  <a href="https://github.com/markus-barta/glint/releases/latest"><strong>Download the latest release</strong></a>
  &nbsp;·&nbsp;
  <a href="#build-from-source">Build from source</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Release history</a>
</p>

## Look once. Keep moving.

GLINT watches a small area around the pointer, recognizes ticket keys and numbers with Apple Vision, and resolves only real matches through your existing Paimos and GitHub sessions. The strongest result gets the space it deserves—key, state, title, metadata, and useful detail—while the next likely matches remain visible before you scroll.

<p align="center">
  <img src="docs/screenshots/workflow-0.3.1.png" alt="GLINT scans a ticket reference at the pointer and opens a rich card with ranked alternatives" width="100%">
</p>

| Invoke anywhere | Keep context nearby | Navigate without friction |
| --- | --- | --- |
| **Inspect** performs exactly one scan beneath the pointer. Optional hover activation can wait for a dwell, require chosen modifiers, or run continuously. | **Pin** turns the result into a movable card with a remembered screen position. Use the handle to place it where it belongs. | Scroll through results, Shift-scroll through projects, type a number to jump tickets, or fuzzy-type a project—even with a typo. |

The small scan cue shows where GLINT is looking, outlines recognized IDs, and confirms the selected ticket. It never steals focus and respects Reduce Motion.

## Your shortcuts. Your card.

Activation and presentation are independent on purpose. Record any safe global shortcut, choose exactly when pointer-only scanning should happen, and tune how much information the card shows. Settings apply immediately; the appearance preview uses local sample data and never contacts a tracker.

<p align="center">
  <img src="docs/screenshots/settings-showcase-0.3.1.png" alt="GLINT activation and card appearance settings" width="100%">
</p>

GLINT can show zero to five alternative destinations and offers four text sizes, three widths, three content densities, and system or solid surfaces. Cards measure their content rather than forcing every ticket into the same height.

## Smarter resolution, fewer wrong guesses

Explicit evidence wins. GLINT combines the shape and position of nearby OCR text with GitHub URLs, the foreground app and window, the pinned card, and short-lived per-app history. It resolves strong candidates first, tries weaker fallbacks only when needed, and never fabricates a “maybe” result.

- Known PPM projects resolve through the `ppm` Paimos instance; `START` resolves through `pma`.
- Explicit GitHub pull-request URLs route directly to their repository.
- Bare numbers use nearby project text and foreground context before trying cautious fallbacks.
- GitHub lookups are limited to configured repositories or an explicit `github.com` URL. Ordinary OCR paths never become network targets.
- Only high-confidence or directly confirmed context is learned; weak guesses are not.

## Private by construction

The screen crop and Apple Vision OCR stay in the GLINT process. No screenshot is saved or uploaded. No pixels, OCR text, or ticket content are sent to an AI model, and there is no telemetry.

GLINT launches only local, read-only commands:

```text
paimos --instance <ppm|pma> --json issue get <key>
gh pr view … --json …
```

Those tools may contact their configured services using your existing credentials. GLINT never writes to either service. Scan-feedback panels opt out of screen capture, and the only learned hint is a bounded, decaying project association keyed by application bundle identifier. Settings can clear it together with cached titles.

## Install

1. Download [`Glint-0.3.1.zip`](https://github.com/markus-barta/glint/releases/download/v0.3.1/Glint-0.3.1.zip).
2. Move `Glint.app` to `~/Applications` or `/Applications`.
3. Open GLINT and grant Screen Recording when macOS asks.
4. Make sure `paimos` and/or `gh` are authenticated for the sources you use.

Default commands:

| Command | Shortcut | Behavior |
| --- | --- | --- |
| Inspect | `⌥Space` | Scan once at the pointer and show a temporary card. |
| Pin / direct open | `⇧⌥Space` | Open pinned, pin the temporary card, focus it, or close it. |

Both shortcuts are fully configurable. Native recorder controls reject unsafe plain-letter globals and report conflicts directly in Settings.

## Pinned navigation

| Input | Result |
| --- | --- |
| Mouse wheel | Select another resolved ticket. |
| `⇧` + mouse wheel | Keep the number and try another project. |
| Type digits | Jump to a ticket number while keeping the project. |
| Type letters | Fuzzy-match a project; the best guess previews immediately. |
| Paste `PHAROS-203`, `#203`, or `203` | Resolve a full key, pull request, or number directly. |
| Return | Apply the previewed input. |
| Escape | Clear the current input, then close. |

Typing is captured only while the pinned card is focused. Ordinary scrolling elsewhere on the Mac is never intercepted.

## Build from source

You need macOS 13 or newer, a Swift 5.10 toolchain, and authenticated `paimos` / `gh` installations for the sources you want to resolve.

```sh
swift build
./scripts/test.sh
./scripts/package-app.sh
open dist/Glint.app
```

The packaging script stages `dist/Glint.app` outside SwiftPM's cleanable build directory. It derives the build number from Git history and applies a stable local designated requirement so Screen Recording permission survives rebuilds without a paid signing identity.

## Release and visual workflow

[`VERSION`](VERSION) is the source of truth for the packaged version; [`CHANGELOG.md`](CHANGELOG.md) keeps the user-visible history.

```sh
./scripts/bump-version.sh patch "Short user-visible release summary"
./scripts/test.sh
./scripts/package-release.sh
swift scripts/render-marketing-shots.swift
```

The last command rebuilds the README hero and feature gallery from the real captured GLINT interfaces plus the checked-in scan-field artwork. The raw release screenshots and the [0.3.0 visual comparison](docs/compare-0.3.0.html) remain available for closer inspection.

## Project map

```text
Sources/Glint/               App, OCR, parsing, resolution, shortcuts, and UI
Sources/Glint/Resources/     Packaged visual assets
Fixtures/                    Deterministic hover/OCR test material
docs/screenshots/            Raw product captures and rendered marketing images
scripts/test.sh              Build, self-tests, and versioning regression checks
scripts/package-app.sh       Release build, app bundle, metadata, and local signing
scripts/package-release.sh   Signed app plus versioned release archive
scripts/bump-version.sh      Semantic version and changelog update
scripts/render-marketing-shots.swift
                             Reproducible GitHub image compositor
```

GLINT is deliberately small, local-first, and read-only. Those are product constraints, not missing features.

## License

GLINT is open-source software licensed under the [GNU Affero General Public License v3.0](LICENSE). The complete terms are included in the repository and inside every packaged app.

Copyright © 2026 Markus Barta.
