# PRD-009: Command-Line Tool

> **Status:** Backlog
> **Priority:** P3
> **Effort:** XL (> 3d) *(roadmap estimate: Medium, 3-4 days, plus the shared framework)*
> **Schema changes:** None
> **Source:** `docs/ROADMAP.md` item 9 (open; roadmap says do this last).

---

## Overview

A `purge` command-line tool (`purge scan`, `purge clean --safe`) that uses the same scanners and `DeletionSafetyPolicy` as the app.

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

- `purge scan`: list findings with sizes and safety labels (human-readable and `--json`).
- `purge clean --safe`: move only `safe` items to the Trash, recording Cleanup History so Put Back works.
- Same safety rules as the app: no code path that bypasses `DeletionSafetyPolicy`.

## Non-Goals

- Permanent deletion flags.
- Cleaning `medium` / `unknown` items non-interactively.
- Uninstalling apps or using the privileged helper from the CLI in v1.

---

## Sub-features

| Step | Scope | Status |
|---|---|---|
| Shared framework | Move scanners, `DeletionSafetyPolicy`, `FileDeleter`, history and models out of the `purge` app target into a framework both targets link. | Not started |
| CLI target | New command-line target using the framework; argument parsing; output formats. | Not started |

*(Split into sub-PRDs `prd-009a`/`prd-009b` when work starts.)*

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | The app's existing tests pass unchanged after the framework move. |
| AC-2 | `purge scan --json` on a fake home matches what the app's scanners find. |
| AC-3 | `purge clean --safe` never moves a `medium` or `unknown` item (tested). |
| AC-4 | Items cleaned by the CLI appear in Cleanup History and can be put back from the app. |

---

## Open questions

- [ ] How is the CLI shipped and signed (inside Purge.app with a symlink installer, or Homebrew)?
- [ ] Full Disk Access is per binary: does the CLI inherit Terminal's, and how is that explained?
- [ ] Interaction with `FolderSizeCache` (shared cache file vs separate).

---

## Related

- `docs/ROADMAP.md` item 9
- [PRD-001: Put Back](../../completed/prd-001-put-back/prd-001-put-back-index.md), [PRD-002: Saved folder sizes](../../completed/prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md)
