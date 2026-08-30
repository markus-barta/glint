<p align="center">
  <img src="docs/screenshots/hero-1.0.0.png" alt="Nuncid — point at a ticket and know what matters" width="100%">
</p>

<p align="center">
  <a href="https://github.com/markus-barta/nuncid/releases/latest"><img src="https://img.shields.io/badge/release-1.0.0-0A84FF?style=flat-square" alt="Latest release 1.0.0"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111827?style=flat-square&logo=apple" alt="macOS 13 or newer">
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/OCR-local-22C55E?style=flat-square" alt="Local OCR">
  <img src="https://img.shields.io/badge/lookups-read--only-22C55E?style=flat-square" alt="Read-only lookups">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-0A84FF?style=flat-square" alt="GNU AGPL v3.0"></a>
</p>

<p align="center">
  <strong>Ticket context, right where you point.</strong><br>
  <strong>Nuncid</strong> (pronounced <strong>NUN-sid</strong>, formerly Glint) is a private macOS menu-bar utility that turns nearby issue references into useful, navigable cards.
</p>

<p align="center">
  <a href="https://github.com/markus-barta/nuncid/releases/latest"><strong>Download the latest release</strong></a>
  &nbsp;·&nbsp;
  <a href="#build-from-source">Build from source</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Release history</a>
</p>

## Look once. Keep moving.

Nuncid watches a small area around the pointer, recognizes ticket keys and numbers with Apple Vision, and resolves only real matches through your existing Paimos and GitHub sessions. The strongest result gets the space it deserves—key, state, title, metadata, and useful detail—while the next likely matches remain visible before you scroll.

<p align="center">
  <img src="docs/screenshots/workflow-1.0.0.png" alt="Nuncid keeps the current ticket fixed between previous and next results" width="100%">
</p>

| Invoke anywhere | Keep context nearby | Navigate without friction |
| --- | --- | --- |
| The **activation shortcut** can stay off, toggle hover scanning, or scan once when pressed. Toggled hover scans each newly settled pointer location once—never in a timer loop. | Move into a temporary card without racing it, pin or unpin directly, and resize from any edge. Nuncid remembers the card’s size, position, and pin state. | Previous and next tickets move around a fixed primary card. Scroll inside it normally, or hold your chosen modifier to navigate while working in another app. |

The small scan cue shows where Nuncid is looking, outlines recognized IDs, and confirms the selected ticket. It never steals focus and respects Reduce Motion.

When you scroll, every row follows one continuous direction while the ticket key and first title line travel between NEXT, the fixed card, and PREVIOUS. Long titles remain on one line while moving, then reveal their wrapped lines after landing—so the card never jumps.

The pinned header keeps its grab handle, pin state, and result position centered. Close directly at the left, or use the quiet arrow controls at the right to move between projects and results by mouse.

## Your shortcuts. Your card.

Activation and presentation are independent on purpose. Record any safe global shortcut, choose Off, Toggle Hover, or Press to Scan, and tune how much information the card shows. The menu bar icon shows when hover is active and confirms when it finds a ticket. Settings apply immediately; the appearance preview uses local sample data and never contacts a tracker.

| Hover off | Hover on | Ticket found |
| --- | --- | --- |
| <img src="docs/screenshots/menu-hover-off-0.3.2.png" alt="Dimmed Nuncid menu bar icon: hover is off" width="40"> | <img src="docs/screenshots/menu-hover-on-0.3.2.png" alt="Filled viewfinder menu bar icon: hover is on" width="40"> | <img src="docs/screenshots/menu-ticket-found-0.3.2.png" alt="Checkmark menu bar icon: ticket found" width="40"> |

<p align="center">
  <img src="docs/screenshots/settings-showcase-1.0.0.png" alt="Nuncid activation and spatial card appearance settings" width="100%">
</p>

Nuncid can show zero to six neighboring destinations and offers four text sizes, three presets plus a remembered Custom size, three content densities, and system or solid surfaces. Cards adapt their content to the available space instead of forcing every ticket into the same dimensions.

## What changed—and why it feels better

The app’s **Version History** explains each release in concise, positive human language. Open it from the menu, About window, or by clicking the version in Settings; your running version is always highlighted.

<p align="center">
  <img src="docs/screenshots/version-history-1.0.0.png" alt="Nuncid Version History with the current release highlighted and benefit-led notes" width="100%">
</p>

## Smarter resolution, fewer wrong guesses

Explicit evidence wins. Nuncid combines the shape and position of nearby OCR text with GitHub URLs, the foreground app and window, the pinned card, and short-lived per-app history. It resolves strong candidates first, tries weaker fallbacks only when needed, and never fabricates a “maybe” result.

- Known PPM projects resolve through the `ppm` Paimos instance; `START` resolves through `pma`.
- Explicit GitHub pull-request URLs route directly to their repository.
- Bare numbers use nearby project text and foreground context before trying cautious fallbacks.
- GitHub lookups are limited to configured repositories or an explicit `github.com` URL. Ordinary OCR paths never become network targets.
- Only high-confidence or directly confirmed context is learned; weak guesses are not.

## Private by construction

The screen crop and Apple Vision OCR stay in the Nuncid process. No screenshot is saved or uploaded. No pixels, OCR text, or ticket content are sent to an AI model, and there is no telemetry.

Nuncid launches only local, read-only commands:

```text
paimos --instance <ppm|pma> --json issue get <key>
gh pr view … --json …
```

Those tools may contact their configured services using your existing credentials. Nuncid never writes to either service. Scan-feedback panels opt out of screen capture, and the only learned hint is a bounded, decaying project association keyed by application bundle identifier. Settings can clear it together with cached titles.

## Install

1. Download the current build from [Latest Release](https://github.com/markus-barta/nuncid/releases/latest).
2. Move `Nuncid.app` to `~/Applications` or `/Applications`.
3. Open Nuncid. Public GitHub builds are currently locally signed and not notarized, so macOS may block the first launch. If it does, open **System Settings → Privacy & Security**, find the Nuncid notice, and choose **Open Anyway**. Only override this protection for the app downloaded from this repository’s release page; Apple explains the same process in [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).
4. Grant Screen Recording when macOS asks.
5. Make sure `paimos` and/or `gh` are authenticated for the sources you use.

Default commands:

| Command | Shortcut | Behavior |
| --- | --- | --- |
| Activation | `⌥Space` | Follow the selected behavior; Press to Scan is the default. |
| Pin / direct open | `⇧⌥Space` | Open pinned, pin the temporary card, focus it, or close it. |

Both shortcuts are fully configurable. F1 through F20 work without modifiers; regular keys require a safe global modifier. The native recorder reports unsafe choices and conflicts directly in Settings.

## Pinned navigation

| Input | Result |
| --- | --- |
| Mouse wheel | Select another resolved ticket. |
| `⇧` + mouse wheel | Keep the number and try another project. |
| Chosen modifier + wheel, anywhere | Select another result while any app remains active. |
| Type digits | Jump to a ticket number while keeping the project. |
| Type letters | Fuzzy-match a project; the best guess previews immediately. |
| Paste `PHAROS-203`, `#203`, or `203` | Resolve a full key, pull request, or number directly. |
| Return | Apply the previewed input. |
| Escape | Clear the current input, then close. |

Typing is captured only while the pinned card is focused. Global wheel navigation is passive: Nuncid responds to the configured modifier without consuming the active app’s scroll event.

## Build from source

You need macOS 13 or newer, a Swift 5.10 toolchain, and authenticated `paimos` / `gh` installations for the sources you want to resolve.

```sh
swift build
./scripts/test.sh
./scripts/package-app.sh
open dist/Nuncid.app
```

The packaging script stages `dist/Nuncid.app` outside SwiftPM's cleanable build directory. It derives the build number from Git history and, by default, applies a stable local designated requirement so Screen Recording permission survives rebuilds without a paid signing identity. The package records whether it was signed locally or with Developer ID; signature verification is not presented as notarization.

## Release and visual workflow

[`VERSION`](VERSION) is the source of truth for the packaged version; [`CHANGELOG.md`](CHANGELOG.md) keeps the user-visible history.

```sh
./scripts/bump-version.sh patch "Short user-visible release summary"
```

Add the matching benefit-led entry to `ReleaseHistory.swift`, then capture and compose the new interface before running consistency-gated tests:

```sh
./scripts/capture-release-shots.sh
swift scripts/render-marketing-shots.swift
./scripts/test.sh
./scripts/package-release.sh
./scripts/verify-release.sh
```

The capture script opens DEBUG-only visual probes long enough to save the current pinned card, Scanning, Appearance, and light/dark Version History. The compositor reads `VERSION` and rebuilds the README hero, feature gallery, and social preview from those same-version captures plus the checked-in scan-field artwork. Historical GLINT captures and the [0.3.0 visual comparison](docs/compare-0.3.0.html) remain unchanged so the release record stays truthful. The [rename decision and migration record](docs/nuncid-rename-2026-08-30.md) documents the collision screen and compatibility choices.

Developer ID distribution is opt-in and requires credentials already stored in your macOS keychain. Apple requires Developer ID, hardened runtime, a secure timestamp, notarization, and a stapled ticket for the trusted distribution path; see [Apple’s notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

```sh
NUNCID_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
NUNCID_NOTARY_PROFILE='nuncid-notary' \
./scripts/package-release.sh
NUNCID_EXPECT_NOTARIZED=1 ./scripts/verify-release.sh
```

Without those variables, packaging remains deliberately local/ad-hoc and verification says so. CI uses that credential-free path and never publishes an artifact. Complete Swift strict-concurrency checking is reserved for the Swift 6 migration; 1.0 remains in Swift 5 language mode and treats all warnings in its supported build mode as errors.

## Project map

```text
Sources/Nuncid/              App, OCR, parsing, resolution, shortcuts, and UI
Sources/Nuncid/Resources/    Packaged visual assets
Fixtures/                    Deterministic hover/OCR test material
docs/screenshots/            Raw product captures and rendered marketing images
scripts/test.sh              Build, self-tests, and versioning regression checks
scripts/check-release-consistency.sh
                             README, changelog, history, and visual version parity
scripts/capture-release-shots.sh
                             Reproducible raw Settings, card, and history captures
scripts/package-app.sh       Release build, app bundle, metadata, and local signing
scripts/package-release.sh   Signed app plus versioned release archive
scripts/verify-release.sh    Signature, archive, metadata, and portable smoke checks
scripts/bump-version.sh      Semantic version and changelog update
scripts/render-marketing-shots.swift
                             Reproducible GitHub image compositor
```

Nuncid is deliberately small, local-first, and read-only. Those are product constraints, not missing features.

## License

Nuncid is open-source software licensed under the [GNU Affero General Public License v3.0](LICENSE). The complete terms are included in the repository and inside every packaged app.

Copyright © 2026 Markus Barta.
