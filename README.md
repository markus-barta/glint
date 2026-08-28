# GLINT

GLINT is a private macOS menu-bar app that makes nearby ticket references glanceable. It follows the cursor, OCRs a small crop in memory with Apple Vision, resolves tickets read-only through the local Paimos CLI, and shows a detailed primary match plus a bounded list of additional real matches beside the pointer.

The first real match is shown as a detailed card. Additional matches stay in a compact list; double-press the configured modifier (Option by default) to pin the card, then use the mouse wheel to browse. Repeat the shortcut to close it. Settings controls the scan trigger, modifier, and double-press interval.

No screenshot is saved or uploaded. No pixels or hover content are sent to a model.

## Build and run

```sh
swift build
./scripts/test.sh
./scripts/package-app.sh
open dist/Glint.app
```

Grant Screen Recording from GLINT's menu when macOS asks. The default trigger is a 300 ms dwell; Settings also offers Hold Option and Always follow.

The packaging script stages the app in `dist/`, outside SwiftPM's cleanable build directory, and applies a stable local designated requirement so one TCC grant survives rebuilds without a paid signing identity.

Routing is narrow: HAUSV, JANUS, PHAROS, PAI, and INSPR use `ppm`; START uses `pma`. Bare numbers try the last-seen tracker/project, the other tracker/project, then a GitHub PR title.

## Versions

`VERSION` is the single packaged short version. `scripts/package-app.sh` derives the build number from Git history. To cut the next version and add its history entry atomically:

```sh
./scripts/bump-version.sh patch "Short user-visible release summary"
```

Use `major`, `minor`, or `patch`; committed history lives in `CHANGELOG.md`.
