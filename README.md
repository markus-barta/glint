<p align="center">
  <img src="Sources/Glint/Resources/Brand/glint-app-icon-1024.png" width="144" alt="GLINT app icon">
</p>

<h1 align="center">GLINT</h1>

<p align="center">
  <strong>Ticket context, right where you are looking.</strong><br>
  A private macOS menu-bar utility that turns nearby issue references into useful, navigable cards.
</p>

<p align="center">
  macOS 13+ &nbsp;·&nbsp; Swift 5.10 &nbsp;·&nbsp; Local OCR &nbsp;·&nbsp; Read-only lookup
</p>

---

GLINT watches a small area around the pointer, recognizes ticket keys and numbers with Apple Vision, and resolves only real matches through your local Paimos and GitHub sessions. The strongest result gets a detailed card—key, state, title, metadata, and description excerpt—while the next likely matches remain visible as compact rows before you scroll to them.

No screenshot is saved or uploaded. No pixels, OCR text, or ticket content are sent to a model.

## Screenshots

<p align="center">
  <img src="docs/screenshots/pinned-card-0.3.0.png" width="760" alt="GLINT pinned ticket card with a prominent primary result and visible scroll alternatives">
</p>

<p align="center">
  <img src="docs/screenshots/settings-scanning-0.3.0.png" width="720" alt="GLINT Scanning settings with a one-shot Inspect shortcut and optional hover activation">
</p>

<p align="center">
  <img src="docs/screenshots/settings-appearance-0.3.0.png" width="720" alt="GLINT Appearance settings with a live ticket-card preview and visual controls">
</p>

<p align="center">
  <img src="docs/screenshots/scan-feedback-0.3.0.png" width="760" alt="GLINT scan feedback states: invoked, recognized, and resolved">
</p>

## How it feels

GLINT has two configurable global commands:

- **Inspect** (default `⌥Space`) scans at the pointer and opens a temporary card.
- **Pin / direct open** (default `⇧⌥Space`) opens GLINT pinned from anywhere, pins a temporary card, or closes an already pinned card.

Both shortcuts use native recorder controls in Settings, reject unsafe plain-letter globals, detect conflicts, and can be cleared or reset.

The Inspect command always performs exactly one scan. Optional hands-free activation can be turned off, delayed by a configurable dwell, limited to any chosen modifier-key combination, or run continuously at a calm, balanced, or fast cadence. A small capture-excluded cue marks the pointer immediately, outlines recognized IDs, and confirms the selected ticket; Reduce Motion replaces animated transitions with restrained fades.

When pinned, GLINT becomes a compact ticket navigator:

- Drag its top handle to a fixed place on the current display; GLINT remembers and safely clamps that position when displays change.
- Scroll over the panel to move through the resolved tickets. Hold Shift while scrolling to try the same number in another project.
- Focus the panel and type digits to jump to that ticket number while keeping the project.
- Type letters to switch projects with typo-tolerant fuzzy matching; the best guess is always previewed, then applied after a brief pause or with Return.
- Paste full keys such as `PHAROS-203`, `#203`, or bare numbers directly. Backspace edits the active input; Escape first clears it, then closes.

Typing is captured only while the pinned panel is focused. Ordinary scrolling elsewhere on the Mac is never intercepted.

Appearance settings update a local sample card immediately. You can show zero to five upcoming scroll destinations and choose the card's text size, width, content density, and system or solid surface.

## Resolution model

Explicit keys take the narrowest route. Known PPM projects (`GLINT`, `HAUSV`, `INSPR`, `JANUS`, `PAI`, and `PHAROS`) resolve through the `ppm` Paimos instance; `START` resolves through `pma`. Unknown project keys can try both. For ambiguous numbers, GLINT ranks nearby project names, explicit GitHub URLs, foreground app/window context, the pinned card, and short-lived per-app history. Explicit evidence always outranks weak context, and weak guesses are never learned automatically.

GitHub lookups are restricted to configured project repositories or a repository extracted from an explicit `github.com` URL. Ordinary slash text, paths, and dates seen by OCR never become network lookup targets.

Failures stay invisible: GLINT never invents a synthetic “maybe” row. Successful results are cached briefly for responsiveness, with misses cached for only one minute.

## Privacy and trust boundary

The screen crop and Apple Vision OCR stay in process. GLINT launches only local, read-only commands:

- `paimos --instance <ppm|pma> --json issue get <key>`
- `gh pr view … --json …` for mapped pull-request candidates

Those tools may contact their configured services under your existing credentials. GLINT does not write to either service, does not add telemetry, and does not call an LLM. macOS Screen Recording permission is required for the small cursor-adjacent capture; GLINT also reads the foreground app identity and, when available under that permission, its visible window title to disambiguate otherwise identical ticket numbers.

GLINT stores only a bounded, decaying resolution hint keyed by application bundle identifier so a recent confirmed project can improve the next ambiguous match. It never stores screen pixels or raw OCR text. Scan-feedback panels explicitly opt out of screen capture.

## Build and run

You need macOS 13 or newer, a Swift 5.10 toolchain, and authenticated `paimos` / `gh` installations for the sources you want to resolve.

```sh
swift build
./scripts/test.sh
./scripts/package-app.sh
open dist/Glint.app
```

Grant Screen Recording from GLINT's menu when macOS asks. Inspect always performs one scan; optional hover activation defaults to a 300 ms dwell and can be disabled or changed in Settings.

The packaging script stages `dist/Glint.app` outside SwiftPM's cleanable build directory. It derives the build number from Git history and applies a stable local designated requirement so the Screen Recording grant survives rebuilds without a paid signing identity.

## Versions and release history

[`VERSION`](VERSION) is the single source for the packaged short version. [`CHANGELOG.md`](CHANGELOG.md) keeps the user-visible history. Bump both atomically with:

```sh
./scripts/bump-version.sh patch "Short user-visible release summary"
```

Use `major`, `minor`, or `patch`. Validate the release path with `./scripts/test.sh` before packaging.

## Project map

```text
Sources/Glint/              App, OCR, parsing, resolution, shortcuts, and UI
Sources/Glint/Resources/    Packaged visual assets
Fixtures/                   Deterministic hover/OCR test material
scripts/test.sh             Build, self-tests, and versioning regression checks
scripts/package-app.sh      Release build, app bundle, metadata, and local signing
scripts/bump-version.sh     Semantic version and changelog update
```

GLINT is currently a personal, private utility. Its narrow permissions and local-first architecture are intentional product constraints.
