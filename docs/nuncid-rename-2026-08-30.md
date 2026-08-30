# Nuncid rename decision and migration record

Date: 30 August 2026

Decision owner: Markus Barta

Decision: rename **Glint** to **Nuncid**, written exactly that way and pronounced **NUN-sid**. `NuncID` is not the brand. The tagline remains “Ticket context, right where you point.”

This is a practical product and collision screen, not legal advice or a comprehensive trademark clearance.

## Identity comparison

| Surface | Nuncid | Ocellus |
| --- | --- | --- |
| Meaning | `nunc` (now) + `id` (identify): “identify it now” closely matches the instant ticket-context promise. | An eye-like structure, so it indirectly suggests seeing; the word is anatomical and obscure. |
| Spoken use | Short and distinct after one pronunciation cue; initial reading can vary, so About and launch copy say “NUN-sid.” | Pronunciation is also uncertain and less likely to be remembered accurately. |
| Menu bar and scan feedback | Six compact letters stay legible beside the existing reticle/spark mark. | Seven letters remain workable but feel more clinical and less immediate. |
| Ticket card and Settings | Reads as a product name without competing with ticket keys; `NUNCID-*` is explicit and scannable. | Can read as a biological term beside OCR and cursor language. |
| About and README | Supports a concise origin story while retaining the proven tagline. | Needs more explanation before the product promise becomes clear. |
| INSPR family fit | Invented, compact, and product-specific beside Paimos, Janus, and Pharos. | Similar family character, but its meaning is less directly connected to the job. |
| Risk | Pronunciation ambiguity; `id` can suggest identity/KYC; search engines may split `nunc id`. | Anatomical/obscure quality; weaker recall and search intent. |

Nuncid wins because its meaning maps directly to the interaction and its risks can be handled honestly: show the pronunciation once, keep the established ticket-context tagline, and consistently describe it as a local macOS ticket utility—not identity verification.

The existing icon remains intentionally. It is text-free, works at 18 px in light and dark menu bars, represents the cursor/recognition moment rather than the old word “Glint,” and preserves visual continuity through the rename.

## Dated collision screen

Screened on 30 August 2026:

- General exact web search found no active software product or company using `Nuncid`. Results were overwhelmingly malformed or concatenated Latin placeholder text such as `nunc id`; this is search-token noise, not a confusing product use.
- GitHub’s current repository search returned zero repositories with `nuncid` in the name. User search returned one unrelated longer handle, `nuncidvides`, created in 2012 with two public repositories.
- Apple’s public Search API returned zero software results for `nuncid` in both Austria and the United States.
- Exact package lookups returned no package on npm, PyPI, crates.io, or RubyGems.
- RDAP and DNS checks returned no registration or address records for `nuncid.com`, `nuncid.at`, `nuncid.app`, `nuncid.dev`, `nuncid.io`, or `nuncid.eu` at screening time. This is a point-in-time observation, not a promise of registrability or reservation.
- Exact-index searches surfaced no `Nuncid` record from EUIPO, WIPO, USPTO, or the Austrian Patent Office. The official interactive registries could not be queried in the available browser session, so this is deliberately recorded as a product knock-out screen only. Before seeking registered protection or investing materially in the mark, repeat similarity searches with a trademark professional across relevant classes.

Official follow-up sources:

- [Austrian Patent Office mark search](https://seeip.patentamt.at/markesuche)
- [EUIPO eSearch](https://euipo.europa.eu/eSearch/)
- [WIPO Global Brand Database](https://www.wipo.int/en/web/global-brand-database)
- [USPTO Trademark Search](https://www.uspto.gov/trademarks/search)

No material exact conflict was found that stops the approved product rename. The known `nunc id` search noise and potential identity/KYC reading are addressed in product metadata and copy.

## Migration inventory and decisions

| Surface | Migration | Continuity decision |
| --- | --- | --- |
| App/menu/window copy | `Nuncid`, title case; settings, About, status accessibility labels, and Version History updated. | Historical release prose keeps the name GLINT where that was true. |
| Executable and artifact | `Nuncid`, `Nuncid.app`, and `Nuncid-<version>.zip`. | The release is a deliberate minor version, 0.4.0. |
| App and menu-bar artwork | Resource filenames updated; text-free artwork retained. | Recognition at small size and visual continuity are preserved. |
| Bundle identity | Keep `at.markusbarta.glint`. | This preserves UserDefaults, cache data, designated signing identity, and the existing Screen Recording grant. The retained identifier is an implementation compatibility key, not visible branding. |
| Preferences/caches | Existing keys and data formats stay unchanged. | Shortcuts, activation, card appearance, pinned position, learned context, and title cache survive in place. |
| Repository | Rename GitHub repository from `markus-barta/glint` to `markus-barta/nuncid`; update clone links, badges, metadata, and current source links. | GitHub’s old-repository redirect is verified after the rename; immutable tags and releases remain. |
| Documentation/screenshots | Current README and new 0.4.0 captures use Nuncid. | Historical comparison pages and pre-0.4 screenshots remain unchanged and truthfully show GLINT. |
| Paimos project | Create active project `NUNCID`, move records 1–29 in numeric order, restore all nine parent links, copy repositories/agents/tags, and archive `GLINT`. | Paimos move aliases keep every `GLINT-*` reference resolvable; new keys preserve the same numeric suffix. The old project remains archived history. |
| Installed app | Move prior builds to a rollback directory outside `~/Applications`, install one canonical `Nuncid.app`, then launch and verify. | Rollback remains possible without leaving ambiguous duplicate menu-bar apps. |
| License/provenance | AGPL-3.0 and copyright unchanged. | No history rewriting or author/provenance change. |

## Rollback

The last Glint build and earlier backups are retained under `~/Library/Application Support/Nuncid/Rollback/`. To roll back, quit Nuncid, move `Nuncid.app` out of `~/Applications`, restore the chosen archived app as `Glint.app`, and launch it. Because the bundle identifier and preferences domain stay stable, configuration remains available to either build.
