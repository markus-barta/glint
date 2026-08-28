# GLINT

GLINT is a private macOS menu-bar app that makes nearby ticket references glanceable. It follows the cursor, OCRs a small crop in memory with Apple Vision, resolves tickets read-only through the local Paimos CLI, and shows up to three one-line matches beside the pointer.

No screenshot is saved or uploaded. No pixels or hover content are sent to a model.

## Build and run

```sh
swift build
.build/debug/Glint --self-test
./scripts/package-app.sh
open dist/Glint.app
```

Grant Screen Recording from GLINT's menu when macOS asks. The default trigger is a 300 ms dwell; Settings also offers Hold Option and Always follow.

The packaging script stages the app in `dist/`, outside SwiftPM's cleanable build directory, and applies a stable local designated requirement so one TCC grant survives rebuilds without a paid signing identity.

Routing is narrow: HAUSV, JANUS, PHAROS, PAI, and INSPR use `ppm`; START uses `pma`. Bare numbers try the last-seen tracker/project, the other tracker/project, then a GitHub PR title.
